/**
 * Imports national average retail prices from the KNBS monthly
 * "Consumer Price Indices and Inflation Rates" report (Table 3) into Firestore.
 *
 * Saved as prices of the reference "shop" kenya_avg, status "estimated",
 * source "KNBS CPI report <Month YYYY>". The app uses them as the fallback
 * whenever a real shop price is missing, and they replace the demo prices.
 *
 * Runs in GitHub Actions (needs `pdftotext` from poppler-utils and
 * GOOGLE_APPLICATION_CREDENTIALS). Usage: node scripts/import-knbs.js [monthsBack=4]
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const UA = 'Mozilla/5.0 (compatible; GrubPriceBot/1.0; monthly CPI import)';
const REF = 'kenya_avg';

// KNBS commodity name → Grub product, and how one KNBS unit converts to the product's pack
// perUnit: product base quantity per KNBS unit (e.g. 1 kg of tomatoes ≈ 8 tomatoes)
const MAP = [
  { re: /^maize ?flour.*sifted/, id: 'maize_flour', pack: (q) => q * 1000, label: (q) => `${q} kg packet` },
  { re: /^fortified ?maize ?flour/, id: 'maize_flour', pack: (q) => q * 1000, label: (q) => `${q} kg packet (fortified)` },
  { re: /^maize ?flour.*loose/, id: 'maize_flour', pack: (q) => q * 1000, label: (q) => `${q} kg loose` },
  { re: /^maize ?grain/, id: 'maize_dry', pack: (q) => q * 1000, label: (q) => `${q} kg` },
  { re: /^wheat ?flour/, id: 'wheat_flour', pack: (q) => q * 1000, label: (q) => `${q} kg packet` },
  { re: /^sugar/, id: 'sugar', pack: (q) => q * 1000, label: (q) => `${q} kg` },
  { re: /rice/, id: 'rice_white', pack: (q) => q * 1000, label: (q) => `${q} kg` },
  { re: /^beans/, id: 'beans', pack: (q) => q * 1000, label: (q) => `${q} kg` },
  { re: /^green ?grams/, id: 'ndengu', pack: (q) => q * 1000, label: (q) => `${q} kg` },
  { re: /^potatoes/, id: 'potatoes', pack: (q) => q * 1000, label: (q) => `${q} kg` },
  { re: /^beef/, id: 'beef', pack: (q) => q * 1000, label: (q) => `${q} kg` },
  { re: /^cooking ?oil|^vegetable ?oil/, id: 'cooking_oil', pack: (q) => q * 1000, label: (q) => (q === 1 ? '1 litre' : `${q} litres`) },
  { re: /milk/, id: 'milk', pack: (q, unit) => (/litre/.test(unit) ? q * 1000 : q), label: (q, unit) => (/litre/.test(unit) ? `${q} litre` : `${q} ml`) },
  // sold by the kg at KNBS, by the piece / bunch in Grub (approximate conversion, labelled)
  { re: /^tomato/, id: 'tomatoes', perKg: 8, label: () => '1 tomato (from per-kg price)' },
  { re: /^onion/, id: 'onions', perKg: 8, label: () => '1 onion (from per-kg price)' },
  { re: /^carrot/, id: 'carrots', perKg: 8, label: () => '1 carrot (from per-kg price)' },
  { re: /^cabbage/, id: 'cabbage', perKg: 0.67, label: () => '1 head ≈1.5 kg (from per-kg price)' },
  { re: /^kale|sukuma/, id: 'sukuma', perKg: 3, label: () => '1 bunch ≈330 g (from per-kg price)' },
  { re: /^spinach/, id: 'spinach', perKg: 3, label: () => '1 bunch ≈330 g (from per-kg price)' },
  { re: /^oranges?/, id: 'oranges', perKg: 5, label: () => '1 orange (from per-kg price)' },
  { re: /^avocado/, id: 'avocado', perKg: 4, label: () => '1 avocado (from per-kg price)' },
  { re: /^mango/, id: 'mangoes', perKg: 3, label: () => '1 mango (from per-kg price)' },
  { re: /^bananas?/, id: 'bananas', perKg: 7, label: () => '1 banana (from per-kg price)' },
  { re: /^eggs?/, id: 'eggs', pack: (q) => q, label: (q) => (q === 1 ? '1 egg' : `${q} eggs`) },
];

async function download(url) {
  const res = await fetch(url, { headers: { 'User-Agent': UA } });
  if (!res.ok) return null;
  const buf = Buffer.from(await res.arrayBuffer());
  return buf.subarray(0, 4).toString() === '%PDF' ? buf : null;
}

async function findReport(year, monthIdx) {
  const name = `Kenya-Consumer-Price-Indices-and-Inflation-Rates-${MONTHS[monthIdx]}-${year}`;
  const folders = [[year, monthIdx + 1], monthIdx === 11 ? [year + 1, 1] : [year, monthIdx + 2]];
  for (const [y, m] of folders) {
    for (const suffix of ['', '_1', '-1', '_2']) {
      const url = `https://www.knbs.or.ke/wp-content/uploads/${y}/${String(m).padStart(2, '0')}/${name}${suffix}.pdf`;
      const pdf = await download(url).catch(() => null);
      if (pdf) return { url, pdf };
    }
  }
  return null;
}

function parseTable3(text) {
  const start = text.lastIndexOf('Table 3: National Average Retail Prices'); // skip the contents page
  if (start < 0) return [];
  const lines = text.slice(start).split('\n').slice(1, 80);
  const rows = [];
  for (const line of lines) {
    const m = line.match(/^\s*([A-Za-z][A-Za-z ()\-\/'.,&]+?)\s{2,}(\d+(?:\.\d+)?)\s+([A-Za-z][A-Za-z ]*?)\s{2,}([\d,]+\.\d+)\s+([\d,]+\.\d+)\s+([\d,]+\.\d+)/);
    if (!m) continue;
    rows.push({ name: m[1].trim(), qty: parseFloat(m[2]), unit: m[3].trim().toLowerCase(), price: parseFloat(m[6].replace(/,/g, '')) });
  }
  return rows;
}

(async () => {
  const monthsBack = parseInt(process.argv[2] || '4', 10);
  initializeApp({ credential: applicationDefault() });
  const db = getFirestore();
  const productIds = new Set((await db.collection('products').get()).docs.map((d) => d.id));

  await db.collection('supermarkets').doc(REF).set(
    { name: 'Kenya average (KNBS)', color: '#6B7A6D', location: 'National average', address: 'KNBS monthly price survey', reference: true },
    { merge: true },
  );

  const now = new Date();
  const found = [];
  for (let k = monthsBack; k >= 0; k--) {
    const d = new Date(now.getFullYear(), now.getMonth() - k, 1);
    const r = await findReport(d.getFullYear(), d.getMonth());
    if (r) found.push({ ...r, year: d.getFullYear(), month: d.getMonth() });
  }
  if (!found.length) {
    console.log('No KNBS report found for the last', monthsBack + 1, 'months.');
    process.exit(0);
  }

  let written = 0;
  const unmapped = new Set();
  for (const rep of found) {
    const tmp = path.join(os.tmpdir(), `knbs-${rep.year}-${rep.month}.pdf`);
    fs.writeFileSync(tmp, rep.pdf);
    const text = execFileSync('pdftotext', ['-layout', tmp, '-'], { encoding: 'utf8' });
    const rows = parseTable3(text);
    const label = `${MONTHS[rep.month]} ${rep.year}`;
    const updated = new Date(rep.year, rep.month + 1, 0, 12); // last day of the report month
    console.log(`\n${label}: ${rows.length} rows from ${rep.url}`);
    const batch = db.batch();
    for (const row of rows) {
      const key = row.name.toLowerCase().replace(/\s+/g, ' ');
      const map = MAP.find((x) => x.re.test(key));
      if (!map || !productIds.has(map.id)) {
        unmapped.add(row.name);
        continue;
      }
      let packageSize, price;
      if (map.perKg) {
        if (!/kilo|kg/.test(row.unit)) continue;
        packageSize = 1;
        price = Math.round((row.price / row.qty / map.perKg) * 100) / 100;
      } else {
        packageSize = map.pack(row.qty, row.unit);
        price = row.price;
      }
      const id = `${map.id}__${REF}__${key.replace(/[^a-z0-9]+/g, '_')}`;
      batch.set(db.collection('prices').doc(id), {
        productId: map.id,
        supermarketId: REF,
        brand: '',
        packageSize,
        packageLabel: map.label(row.qty, row.unit),
        price,
        location: 'Kenya (national average)',
        lastUpdated: updated,
        verificationStatus: 'estimated',
        source: `KNBS CPI report, ${label} – national average (${row.name})`,
        active: true,
      });
      console.log(`  ✓ ${row.name} ${row.qty} ${row.unit}: KSh ${row.price} → ${map.id} @ KSh ${price} / ${packageSize}`);
      written++;
    }
    await batch.commit();
  }
  if (unmapped.size) console.log('\nNot used (no matching Grub product):', [...unmapped].join(', '));
  console.log(`\nDone: ${written} KNBS prices saved.`);
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
