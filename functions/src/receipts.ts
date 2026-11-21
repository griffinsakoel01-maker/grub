// Receipt scanning: a customer photographs a shop receipt, Gemini reads it,
// the customer confirms, and the confirmed prices become real shop prices.
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';

const db = () => getFirestore();
const REGION = 'africa-south1'; // must match AppConfig.functionsRegion
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');
const GEMINI_MODEL = process.env.GEMINI_MODEL ?? 'gemini-2.5-flash';
const DAILY_SCAN_LIMIT = 20;

export interface ScannedItem {
  text: string;
  quantity: number; // how many packs/pieces were bought
  unitPrice: number; // KSh per pack/piece
  lineTotal: number;
  productId: string | null;
  packageSize: number | null; // in the product's base unit (g, ml, pcs, bunch)
  packageLabel: string;
}

export interface ScanResult {
  supermarketId: string | null;
  shopName: string;
  branch: string;
  date: string | null;
  total: number | null;
  items: ScannedItem[];
}

const num = (v: unknown): number | null => {
  const n = typeof v === 'number' ? v : parseFloat(String(v ?? '').replace(/[^0-9.]/g, ''));
  return Number.isFinite(n) && n >= 0 ? n : null;
};

async function rateLimit(uid: string, key: string, limit: number) {
  const day = new Date().toISOString().slice(0, 10);
  const ref = db().doc(`users/${uid}/usage/${key}_${day}`);
  const n = await db().runTransaction(async (t) => {
    const s = await t.get(ref);
    const c = (s.exists ? (s.data()?.count as number) : 0) + 1;
    t.set(ref, { count: c, day }, { merge: true });
    return c;
  });
  if (n > limit) throw new HttpsError('resource-exhausted', 'Daily limit reached. Try again tomorrow.');
}

export const scanReceipt = onCall({ region: REGION, secrets: [GEMINI_API_KEY], timeoutSeconds: 90, memory: '512MiB' }, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Please sign in.');
  const uid = req.auth.uid;
  const image = String(req.data?.imageBase64 ?? '');
  const mime = String(req.data?.mimeType ?? 'image/jpeg');
  if (!image || image.length > 9_000_000) throw new HttpsError('invalid-argument', 'Please send a photo under 6 MB.');
  if (!/^image\/(jpeg|png|webp|heic|heif)$/.test(mime)) throw new HttpsError('invalid-argument', 'Unsupported image type.');
  await rateLimit(uid, 'scan', DAILY_SCAN_LIMIT);

  const [productsSnap, shopsSnap] = await Promise.all([db().collection('products').get(), db().collection('supermarkets').get()]);
  const products = productsSnap.docs.map((d) => ({ id: d.id, ...(d.data() as { name: string; unit: string; defaultPackageSize?: number; defaultPackageLabel?: string }) }));
  const shops = shopsSnap.docs.map((d) => ({ id: d.id, name: (d.data().name as string) ?? d.id }));

  const prompt = [
    'You read Kenyan supermarket and shop receipts (Naivas, Carrefour, Quickmart, Chandarana, Cleanshelf, etc.).',
    'Extract every purchased line. Ignore VAT lines, change, payment, loyalty points and discounts summaries (but use the discounted price if a line discount applies to an item).',
    'For each line: text (as printed), quantity (number of packs or pieces bought; for weighed items use 1), unitPrice (KSh per pack/piece; for weighed items the line price), lineTotal (KSh).',
    'Match each line to ONE product id from PRODUCTS if it is clearly the same kind of item, else null (household items like soap are null).',
    'packageSize = size of ONE pack in the product\'s base unit (g for g, ml for ml, pcs, bunch). Examples: "JOGOO 2KG" → 2000; "Fresh Fri 1L" → 1000; "EGGS TRAY 30" → 30; weighed "TOMATOES 0.76kg" → 760. Use null if unknown.',
    'packageLabel = short human label like "2 kg packet", "1 litre", "tray of 30", "0.76 kg".',
    'shop: supermarketId from SHOPS if it matches, else null; shopName and branch as printed; date as YYYY-MM-DD; total = the amount paid.',
    'Return ONLY JSON: {"supermarketId":string|null,"shopName":string,"branch":string,"date":string|null,"total":number|null,"items":[{"text":string,"quantity":number,"unitPrice":number,"lineTotal":number,"productId":string|null,"packageSize":number|null,"packageLabel":string}]}',
    'PRODUCTS (id | name | base unit | usual pack):',
    products.map((p) => `${p.id} | ${p.name} | ${p.unit} | ${p.defaultPackageLabel ?? ''}`).join('\n'),
    'SHOPS (id | name):',
    shops.map((s) => `${s.id} | ${s.name}`).join('\n'),
  ].join('\n');

  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY.value() },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: prompt }, { inlineData: { mimeType: mime, data: image } }] }],
      generationConfig: { temperature: 0, responseMimeType: 'application/json' },
    }),
  });
  if (!res.ok) {
    console.error('Gemini error', res.status, await res.text());
    throw new HttpsError('unavailable', 'Could not read the receipt right now. Please try again.');
  }
  const json = (await res.json()) as { candidates?: { content?: { parts?: { text?: string }[] } }[] };
  let raw: Record<string, unknown> = {};
  try {
    raw = JSON.parse(json.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}');
  } catch {
    throw new HttpsError('failed-precondition', "That photo doesn't look like a readable receipt. Try a clearer, flat photo.");
  }
  const productIds = new Set(products.map((p) => p.id));
  const shopIds = new Set(shops.map((s) => s.id));
  const items: ScannedItem[] = (Array.isArray(raw.items) ? raw.items : [])
    .map((i: Record<string, unknown>) => {
      const quantity = num(i.quantity) || 1;
      const lineTotal = num(i.lineTotal);
      let unitPrice = num(i.unitPrice);
      if (unitPrice === null && lineTotal !== null) unitPrice = lineTotal / quantity;
      const pid = typeof i.productId === 'string' && productIds.has(i.productId) ? i.productId : null;
      return {
        text: String(i.text ?? '').slice(0, 80),
        quantity,
        unitPrice: unitPrice ?? 0,
        lineTotal: lineTotal ?? (unitPrice ?? 0) * quantity,
        productId: pid,
        packageSize: num(i.packageSize),
        packageLabel: String(i.packageLabel ?? '').slice(0, 40),
      };
    })
    .filter((i) => i.text && i.lineTotal > 0)
    .slice(0, 120);
  if (!items.length) throw new HttpsError('failed-precondition', "We couldn't find any items on that receipt. Try a clearer photo.");

  const result: ScanResult = {
    supermarketId: typeof raw.supermarketId === 'string' && shopIds.has(raw.supermarketId) ? raw.supermarketId : null,
    shopName: String(raw.shopName ?? '').slice(0, 60),
    branch: String(raw.branch ?? '').slice(0, 60),
    date: typeof raw.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(raw.date) ? raw.date : null,
    total: num(raw.total),
    items,
  };
  return result;
});

/**
 * Called after the customer has checked the scanned items. Confirmed food items
 * with a known shop and pack size become "user_submitted" prices (labelled
 * "Customer receipt"). Obvious outliers are kept for admin review instead.
 */
export const saveReceiptPrices = onCall({ region: REGION }, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Please sign in.');
  const uid = req.auth.uid;
  await rateLimit(uid, 'receiptsave', 30);
  const supermarketId = String(req.data?.supermarketId ?? '');
  const branch = String(req.data?.branch ?? '').slice(0, 60);
  const date = /^\d{4}-\d{2}-\d{2}$/.test(String(req.data?.date)) ? String(req.data.date) : new Date().toISOString().slice(0, 10);
  const items: ScannedItem[] = Array.isArray(req.data?.items) ? req.data.items.slice(0, 120) : [];
  if (!supermarketId) return { saved: 0, review: 0 };
  const shop = await db().collection('supermarkets').doc(supermarketId).get();
  if (!shop.exists) throw new HttpsError('invalid-argument', 'Unknown shop.');

  let saved = 0;
  let review = 0;
  const batch = db().batch();
  for (const it of items) {
    const pid = String(it.productId ?? '');
    const size = num(it.packageSize);
    const price = num(it.unitPrice);
    if (!pid || !size || !price || price > 100000) continue;
    const product = await db().collection('products').doc(pid).get();
    if (!product.exists) continue;
    // compare with known prices for the same product (per base unit)
    const known = await db().collection('prices').where('productId', '==', pid).where('active', '==', true).limit(20).get();
    const perUnit = known.docs
      .map((d) => d.data())
      .filter((d) => d.packageSize > 0 && d.price > 0)
      .map((d) => d.price / d.packageSize)
      .sort((a, b) => a - b);
    const median = perUnit.length ? perUnit[Math.floor(perUnit.length / 2)] : null;
    const mine = price / size;
    const outlier = median !== null && (mine > median * 3 || mine < median / 3);
    const report = {
      userId: uid,
      productId: pid,
      supermarketId,
      price,
      packageSize: size,
      packageLabel: String(it.packageLabel ?? '').slice(0, 40),
      location: branch,
      receiptText: String(it.text ?? '').slice(0, 80),
      receiptDate: date,
      source: 'receipt',
      status: outlier ? 'pending' : 'auto_approved',
      createdAt: FieldValue.serverTimestamp(),
    };
    batch.set(db().collection('priceReports').doc(), report);
    if (outlier) {
      review++;
      continue;
    }
    const id = `${pid}__${supermarketId}__r${Math.round(size)}`;
    batch.set(db().collection('prices').doc(id), {
      productId: pid,
      supermarketId,
      brand: '',
      packageSize: size,
      packageLabel: report.packageLabel,
      price,
      location: branch,
      lastUpdated: new Date(`${date}T12:00:00+03:00`),
      verificationStatus: 'user_submitted',
      source: `Customer receipt${branch ? ' · ' + branch : ''}`,
      active: true,
    });
    saved++;
  }
  await batch.commit();
  return { saved, review };
});
