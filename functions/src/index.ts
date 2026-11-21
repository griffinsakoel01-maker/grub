import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { ksh, Price, Product, Profile, Recipe, recipeAllowed, recipeCostCents } from './pricing';

initializeApp();
const db = getFirestore();

// Must match AppConfig.functionsRegion in the Flutter app.
setGlobalOptions({ region: 'africa-south1', maxInstances: 10 });

// Set with: firebase functions:secrets:set GEMINI_API_KEY
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');
const GEMINI_MODEL = process.env.GEMINI_MODEL ?? 'gemini-2.5-flash';
const DAILY_AI_LIMIT = 40;

function requireAuth(req: CallableRequest): string {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Please sign in.');
  return req.auth.uid;
}
function requireAdmin(req: CallableRequest): string {
  const uid = requireAuth(req);
  if (req.auth?.token?.admin !== true) throw new HttpsError('permission-denied', 'Administrators only.');
  return uid;
}

// ------------------------------------------------------------------ AI assistant
/**
 * The model chooses recipes and writes advice. It is given a pre-computed
 * list of recipes with costs from Grub's price data and must not invent
 * prices. The app recalculates every cost it displays.
 */
export const mealAssistant = onCall({ secrets: [GEMINI_API_KEY], timeoutSeconds: 60, memory: '512MiB' }, async (req) => {
  const uid = requireAuth(req);
  const message = String(req.data?.message ?? '').slice(0, 1000).trim();
  if (!message) throw new HttpsError('invalid-argument', 'Message is empty.');
  const history: { role: string; content: string }[] = Array.isArray(req.data?.history) ? req.data.history.slice(-10) : [];
  const pantry: Record<string, number> = typeof req.data?.pantry === 'object' && req.data?.pantry ? req.data.pantry : {};

  // simple per-user daily rate limit
  const day = new Date().toISOString().slice(0, 10);
  const usageRef = db.doc(`users/${uid}/usage/ai_${day}`);
  const used = await db.runTransaction(async (t) => {
    const snap = await t.get(usageRef);
    const n = (snap.exists ? (snap.data()?.count as number) : 0) + 1;
    t.set(usageRef, { count: n, day }, { merge: true });
    return n;
  });
  if (used > DAILY_AI_LIMIT) throw new HttpsError('resource-exhausted', 'Daily AI limit reached. Try again tomorrow.');

  const [userSnap, recipesSnap, productsSnap, pricesSnap] = await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.collection('recipes').where('published', '==', true).get(),
    db.collection('products').get(),
    db.collection('prices').where('active', '==', true).get(),
  ]);
  const profile = (userSnap.data() ?? {}) as Profile & { adults?: number; kids?: number; budget?: number; budgetFrequency?: string; name?: string };
  const portions = Math.max(1, (profile.adults ?? 2) + (profile.kids ?? 0) * 0.5);
  const products = new Map<string, Product>(productsSnap.docs.map((d) => [d.id, { id: d.id, ...(d.data() as Omit<Product, 'id'>) }]));
  const prices = pricesSnap.docs.map((d) => d.data() as Price);
  const recipes = recipesSnap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<Recipe, 'id'>) }));

  const demoOnly = prices.every((p) => (p.verificationStatus ?? 'demo') === 'demo');
  const candidates = recipes
    .filter((r) => recipeAllowed(r, products, profile))
    .map((r) => ({ r, cost: recipeCostCents(r, portions, prices, pantry) }))
    .filter((x) => x.cost !== null)
    .sort((a, b) => (a.cost as number) - (b.cost as number));

  const catalogue = candidates
    .map((x) => `${x.r.id} | ${x.r.name} | ${x.r.category} | ${(x.r.prepMinutes ?? 0) + (x.r.cookMinutes ?? 0)} min | ${ksh(x.cost as number)} for ${portions} portions`)
    .join('\n');
  const pantryNames = Object.keys(pantry).map((id) => products.get(id)?.name).filter(Boolean).join(', ') || 'nothing recorded';

  const system = [
    'You are Grub, a friendly grocery and meal-planning assistant for Kenyan households. Use Kenyan English and KSh.',
    `Household: ${portions} portions per meal. Diet: ${(profile.preferences ?? []).join(', ') || 'no restrictions'}. Allergies: ${(profile.allergies ?? []).join(', ') || 'none'}.`,
    `Budget: KSh ${profile.budget ?? 'unknown'} (${profile.budgetFrequency ?? 'weekly'}). Pantry: ${pantryNames}.`,
    'RULES: Only recommend recipes from the CATALOGUE below, by id. Only mention costs that appear in the CATALOGUE; never invent prices.',
    'All costs are estimates' + (demoOnly ? ' from DEMO data (say so).' : '.') + ' Never suggest anything containing the user\'s allergens.',
    'For multi-day plans, add up catalogue costs and say it is an estimate; mention that whole packets may cost more.',
    'Respond ONLY as JSON: {"reply": string (max 120 words, plain text), "recipeIds": string[] (max 7, from catalogue)}.',
    'CATALOGUE (id | name | meal | time | estimated cost):',
    catalogue,
  ].join('\n');

  const contents = [
    ...history
      .filter((h) => h && typeof h.content === 'string')
      .slice(0, -1)
      .map((h) => ({ role: h.role === 'user' ? 'user' : 'model', parts: [{ text: h.content.slice(0, 1000) }] })),
    { role: 'user', parts: [{ text: message }] },
  ];

  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY.value() },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: system }] },
      contents,
      generationConfig: { temperature: 0.4, responseMimeType: 'application/json' },
    }),
  });
  if (!res.ok) {
    console.error('Gemini error', res.status, await res.text());
    throw new HttpsError('unavailable', 'The AI assistant is unavailable right now.');
  }
  const json = (await res.json()) as { candidates?: { content?: { parts?: { text?: string }[] } }[] };
  const text = json.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}';
  let parsed: { reply?: string; recipeIds?: string[] } = {};
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = { reply: text, recipeIds: [] };
  }
  const allowed = new Set(candidates.map((c) => c.r.id));
  return {
    reply: String(parsed.reply ?? '').slice(0, 2000),
    recipeIds: (parsed.recipeIds ?? []).filter((id) => allowed.has(id)).slice(0, 7),
    demoPrices: demoOnly,
  };
});

// ------------------------------------------------------------- account deletion
export const deleteMyAccount = onCall(async (req) => {
  const uid = requireAuth(req);
  await db.recursiveDelete(db.doc(`users/${uid}`));
  // keep price reports for data quality but remove the link to the person
  const reports = await db.collection('priceReports').where('userId', '==', uid).get();
  const batch = db.batch();
  reports.docs.forEach((d) => batch.update(d.ref, { userId: 'deleted-user' }));
  await batch.commit();
  await getAuth().deleteUser(uid);
  return { ok: true };
});

// ------------------------------------------------------------------- admin
export const setAdminRole = onCall(async (req) => {
  requireAdmin(req);
  const email = String(req.data?.email ?? '').trim();
  const admin = req.data?.admin === true;
  if (!email) throw new HttpsError('invalid-argument', 'Email required.');
  const user = await getAuth().getUserByEmail(email);
  await getAuth().setCustomUserClaims(user.uid, { ...(user.customClaims ?? {}), admin });
  return { uid: user.uid, admin };
});

export const reviewPriceReport = onCall(async (req) => {
  const adminUid = requireAdmin(req);
  const reportId = String(req.data?.reportId ?? '');
  const approve = req.data?.approve === true;
  const status = req.data?.status === 'verified' ? 'verified' : 'user_submitted';
  const ref = db.collection('priceReports').doc(reportId);
  return db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Report not found.');
    const r = snap.data()!;
    if (r.status !== 'pending') throw new HttpsError('failed-precondition', 'Already reviewed.');
    if (approve) {
      const priceId = `${r.productId}__${r.supermarketId}__${String(r.packageLabel ?? r.packageSize).replace(/[^a-zA-Z0-9]+/g, '_')}`;
      t.set(db.collection('prices').doc(priceId), {
        productId: r.productId,
        supermarketId: r.supermarketId,
        brand: r.brand ?? 'Generic',
        packageSize: r.packageSize,
        packageLabel: r.packageLabel ?? '',
        price: r.price,
        location: r.location ?? '',
        lastUpdated: FieldValue.serverTimestamp(),
        verificationStatus: status,
        source: status === 'verified' ? 'Verified by Grub team' : 'User report (reviewed)',
        active: true,
      });
    }
    t.update(ref, { status: approve ? 'approved' : 'rejected', reviewedBy: adminUid, reviewedAt: FieldValue.serverTimestamp() });
    return { ok: true };
  });
});

export const adminStats = onCall(async (req) => {
  requireAdmin(req);
  const count = async (q: FirebaseFirestore.Query) => (await q.count().get()).data().count;
  const [users, recipes, products, prices, pending, verified] = await Promise.all([
    count(db.collection('users')),
    count(db.collection('recipes')),
    count(db.collection('products')),
    count(db.collection('prices')),
    count(db.collection('priceReports').where('status', '==', 'pending')),
    count(db.collection('prices').where('verificationStatus', '==', 'verified')),
  ]);
  const lists = await count(db.collectionGroup('shoppingLists'));
  const plans = await count(db.collectionGroup('mealPlans'));
  return { users, recipes, products, prices, pendingReports: pending, verifiedPrices: verified, shoppingLists: lists, mealPlans: plans };
});
