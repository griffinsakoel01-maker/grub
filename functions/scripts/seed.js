/**
 * Uploads the Grub catalogue (assets/seed/*.json) to Firestore.
 *
 *   cd functions
 *   GOOGLE_APPLICATION_CREDENTIALS=./service-account.json npm run seed
 *   (or use the emulator: FIRESTORE_EMULATOR_HOST=localhost:8080 GCLOUD_PROJECT=demo-grub npm run seed)
 *
 * Every seeded price is marked verificationStatus "demo" with a clear source
 * label. Replace them with real prices from the admin dashboard.
 *   --skip-prices   only upload products, recipes and supermarkets
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const path = require('path');

initializeApp(process.env.FIRESTORE_EMULATOR_HOST ? { projectId: process.env.GCLOUD_PROJECT || 'demo-grub' } : { credential: applicationDefault() });
const db = getFirestore();
const seedDir = path.join(__dirname, '..', '..', 'assets', 'seed');
const load = (f) => require(path.join(seedDir, f));

async function upload(collection, items, extra = {}) {
  let batch = db.batch();
  let n = 0;
  for (const item of items) {
    const { id, ...data } = item;
    batch.set(db.collection(collection).doc(id), { ...data, ...extra }, { merge: true });
    if (++n % 400 === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  await batch.commit();
  console.log(`✓ ${collection}: ${items.length}`);
}

(async () => {
  await upload('products', load('products.json'));
  await upload('supermarkets', load('supermarkets.json'));
  await upload('recipes', load('recipes.json'), { published: true });
  if (!process.argv.includes('--skip-prices')) {
    await upload('prices', load('prices.json'), { active: true });
  }
  console.log('Done. Seeded prices are DEMO estimates – replace them with verified prices in the admin dashboard.');
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
