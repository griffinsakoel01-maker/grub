// Takes phone-size screenshots of the built web app (used by GitHub Actions).
const { chromium } = require('playwright');
const [, , base, out] = process.argv;
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  p.on('pageerror', (e) => console.log('pageerror', e.message));
  // in-app loading animation
  await p.goto(base + '/#logo');
  const t0 = Date.now();
  for (const ms of [2500, 3400, 4300, 5200, 6200, 7400]) {
    await p.waitForTimeout(Math.max(0, ms - (Date.now() - t0)));
    await p.screenshot({ path: `${out}/logo_${ms}.jpg`, quality: 80, type: 'jpeg' });
  }
  // normal start: web loading video, then the welcome screen
  const p2 = await b.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  p2.on('pageerror', (e) => console.log('pageerror', e.message));
  await p2.goto(base + '/');
  for (const ms of [800, 2000, 3500, 9000]) {
    await p2.waitForTimeout(ms === 800 ? 800 : ms - [800, 2000, 3500, 9000][[800, 2000, 3500, 9000].indexOf(ms) - 1]);
    await p2.screenshot({ path: `${out}/start_${ms}.jpg`, quality: 80, type: 'jpeg' });
  }
  await b.close();
  console.log('screenshots done');
})().catch((e) => { console.error(e); process.exit(1); });
