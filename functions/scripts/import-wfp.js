/**
 * Imports open-market retail food prices for Kenya from the World Food Programme
 * dataset on HDX (Humanitarian Data Exchange, updated monthly, CC-BY licence).
 *
 * Takes the latest month for each commodity, ignores refugee-camp markets,
 * and saves the median across markets as the reference "shop" market_avg,
 * status "estimated". The app uses these as a fallback when a shop price is missing.
 *
 * Usage (GitHub Actions, needs GOOGLE_APPLICATION_CREDENTIALS): node scripts/import-wfp.js
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PKG = 'https://data.humdata.org/api/3/action/package_show?id=wfp-food-prices-for-kenya';
const REF = 'market_avg';
const UA = 'Mozilla/5.0 (compatible; GrubPriceBot/1.0; monthly market price import)';
const CAMPS = /kakuma|kalobeyei|dadaab|hagadera|ifo|dagahaley|camp|refugee/i;

// WFP commodity → Grub product. perKg: pieces/bunches in 1 kg (for count-based products).
const MAP = [
  { re: /^maize flour/, id: 'maize_flour' },
  { re: /^maize( \(white\))?$/, id: 'maize_dry' },
  { re: /^rice/, id: 'rice_white' },
  { re: /^wheat flour/, id: 'wheat_flour' },
  { re: /^beans/, id: 'beans', not: /mung/ },
  { re: /green ?grams|beans \(mung\)/, id: 'ndengu' },
  { re: /^lentils/, id: 'lentils' },
  { re: /^potatoes \(irish\)|^potatoes$/, id: 'potatoes' },
  { re: /^sweet potatoes/, id: 'sweet_potatoes', perKg: 4 },
  { re: /^cassava/, id: 'cassava' },
  { re: /^(sorghum|millet) flour/, id: 'millet_flour' },
  { re: /^sugar/, id: 'sugar' },
  { re: /^oil \(vegetable\)|^oil/, id: 'cooking_oil' },
  { re: /^salt/, id: 'salt' },
  { re: /^milk/, id: 'milk', not: /powder/ },
  { re: /^meat \(beef\)/, id: 'beef' },
  { re: /^meat \(chicken\)|^chicken/, id: 'chicken' },
  { re: /^eggs/, id: 'eggs', perKg: 16 },
  { re: /^cabbage/, id: 'cabbage', perKg: 0.67 },
  { re: /^kale/, id: 'sukuma', perKg: 3 },
  { re: /^tomatoes/, id: 'tomatoes', perKg: 8 },
  { re: /^onions/, id: 'onions', perKg: 8 },
  { re: /^bananas/, id: 'bananas', perKg: 7 },
  { re: /^fish \(omena/, id: 'omena' },
  { re: /^fish \(tilapia/, id: 'tilapia', perKg: 2 },
];

function parseCsv(text) {
  const rows = [];
  let row = [], cur = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"' && text[i + 1] === '"') { cur += '"'; i++; }
      else if (c === '"') q = false;
      else cur += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n') { row.push(cur); rows.push(row); row = []; cur = ''; }
    else if (c !== '\r') cur += c;
  }
  if (cur || row.length) { row.push(cur); rows.push(row); }
  return rows;
}

/** Quantity of the product's base unit in one WFP unit, or null if it can't be converted. */
function baseQty(unitText, product, map) {
  const m = /^\s*(\d+(?:\.\d+)?)?\s*([A-Za-z]+)/.exec(unitText || '');
  if (!m) return null;
  const n = m[1] ? parseFloat(m[1]) : 1;
  const u = m[2].toUpperCase();
  const base = product.unit;
  if (base === 'g') return u === 'KG' ? n * 1000 : u === 'G' ? n : null;
  if (base === 'ml') return u === 'L' ? n * 1000 : u === 'ML' ? n : u === 'KG' ? n * 1000 : null;
  // pcs / bunch
  if (['UNIT', 'HEAD', 'BUNCH', 'PIECE', 'PCS'].includes(u)) return n;
  if (u === 'DOZEN') return n * 12;
  if (u === 'TRAY') return n * 30;
  if (u === 'KG' && map.perKg) return n * map.perKg;
  if (u === 'G' && map.perKg) return (n / 1000) * map.perKg;
  return null;
}

const median = (a) => { const s = [...a].sort((x, y) => x - y); const h = s.length >> 1; return s.length % 2 ? s[h] : (s[h - 1] + s[h]) / 2; };

(async () => {
  const meta = await (await fetch(PKG, { headers: { 'User-Agent': UA } })).json();
  const res = meta.result.resources.find((r) => /wfp_food_prices_ken\.csv/.test(r.url || '') || /Food Prices/i.test(r.name || ''));
  if (!res) throw new Error('WFP Kenya price file not found on HDX');
  console.log('Downloading', res.url);
  const csv = await (await fetch(res.url, { headers: { 'User-Agent': UA } })).text();
  const rows = parseCsv(csv);
  const head = rows.shift();
  const col = Object.fromEntries(head.map((h, i) => [h.trim(), i]));

  initializeApp({ credential: applicationDefault() });
  const db = getFirestore();
  const products = Object.fromEntries((await db.collection('products').get()).docs.map((d) => [d.id, d.data()]));

  // newest date per commodity (retail, KES, not a camp)
  const byCommodity = new Map();
  for (const r of rows) {
    if (r.length < head.length) continue;
    if (r[col.pricetype] !== 'Retail' || r[col.currency] !== 'KES') continue;
    if (CAMPS.test(r[col.market]) || CAMPS.test(r[col.admin2])) continue;
    const name = r[col.commodity].toLowerCase();
    const list = byCommodity.get(name) || [];
    list.push(r);
    byCommodity.set(name, list);
  }

  await db.collection('supermarkets').doc(REF).set(
    { name: 'Open-market average (WFP)', color: '#8A6D3B', location: 'Kenyan open markets', address: 'WFP market price monitoring', reference: true },
    { merge: true },
  );

  const batch = db.batch();
  let written = 0;
  const unused = [];
  const cutoff = new Date(Date.now() - 1000 * 60 * 60 * 24 * 200); // ignore data older than ~6 months
  for (const [name, list] of byCommodity) {
    const map = MAP.find((x) => x.re.test(name) && !(x.not && x.not.test(name)));
    const product = map && products[map.id];
    if (!product) { unused.push(name); continue; }
    const dates = [...new Set(list.map((r) => r[col.date]))].sort().reverse();
    let pick = null;
    for (const d of dates) {
      if (new Date(d) < cutoff) break;
      const perBase = list
        .filter((r) => r[col.date] === d)
        .map((r) => { const q = baseQty(r[col.unit], product, map); return q ? parseFloat(r[col.price]) / q : null; })
        .filter((v) => v && isFinite(v));
      if (perBase.length >= 3) { pick = { date: d, perBase, markets: perBase.length }; break; }
    }
    if (!pick) { unused.push(`${name} (too few recent markets)`); continue; }
    const size = product.defaultPackageSize || 1;
    const price = Math.round(median(pick.perBase) * size * 100) / 100;
    const month = new Date(pick.date).toLocaleString('en-GB', { month: 'long', year: 'numeric' });
    const id = `${map.id}__${REF}__${name.replace(/[^a-z0-9]+/g, '_')}`;
    batch.set(db.collection('prices').doc(id), {
      productId: map.id,
      supermarketId: REF,
      brand: '',
      packageSize: size,
      packageLabel: `${product.defaultPackageLabel || size} (market average)`,
      price,
      location: 'Kenya open markets (median)',
      lastUpdated: new Date(pick.date),
      verificationStatus: 'estimated',
      source: `WFP market prices via HDX, ${month} – median of ${pick.markets} markets (${name})`,
      active: true,
    });
    console.log(`  ✓ ${name}: KSh ${price} per ${product.defaultPackageLabel} → ${map.id} (${pick.markets} markets, ${pick.date})`);
    written++;
  }
  await batch.commit();
  if (unused.length) console.log('\nNot used:', unused.join(', '));
  console.log(`\nDone: ${written} market prices saved.`);
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
