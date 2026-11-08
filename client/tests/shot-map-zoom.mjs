import { createRequire } from 'node:module';
import { signInLocal } from './browser-login.mjs';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CAS_PLAYWRIGHT_MODULE);
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const page = await (await browser.newContext({ viewport: { width: 1360, height: 768 } })).newPage();
const errors = [];
page.on('pageerror', e => errors.push(e.stack));
page.on('console', m => { if (m.text().startsWith('PHOTO')) console.log(m.text()); });
page.on('response', r => { if (r.status() >= 400) console.log('404:', r.url()); });
page.on('console', m => { if (m.type() === 'error') console.log('console:', m.text(), m.location?.url); });
const q = (op, params = {}) => page.evaluate(async request =>
  (await import(performance.getEntriesByType('resource').filter(e => e.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask(request), { op, ...params });
try {
  await page.goto('http://127.0.0.1:5175/');
  await signInLocal(page, 'cas-shot-' + Date.now().toString(36), true);
  await page.locator('.growth-campaign-entry').click();
  await page.locator('.war-archive-entries li').filter({ hasText: '萨沃岛' }).first().locator('button.war-entry').click();
  await page.getByRole('button', { name: '作战简报', exact: true }).click();
  await page.getByRole('button', { name: '出航作战', exact: true }).click();
  await page.locator('.battle-map').waitFor();
  for (let i = 0; i < 7; i++) await page.locator('.map-zoom-out, button:has-text("−")').first().click().catch(() => {});
  await page.waitForTimeout(800);
  console.log('drawn:', JSON.stringify(await page.evaluate(() => window.__photoDrawn ?? 'never')));
  const px = await page.evaluate(() => {
    const canvas = document.querySelector('.battle-map canvas');
    const rect = canvas.getBoundingClientRect();
    const ctx = canvas.getContext('2d');
    // Savo on canvas: field (26345,31745) -> screen via left/bottom/mapRatio
    // read from the previous draw log; scan a window for any green pixels.
    let green = 0, total = 0, first = null;
    const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    for (let y = 200; y < 500; y += 4) {
      for (let x = 200; x < 600; x += 4) {
        const i = (y * canvas.width + x) * 4;
        total++;
        if (data[i + 1] > data[i + 2] + 8 && data[i + 1] > 55) { green++; if (!first) first = [x, y, data[i], data[i+1], data[i+2]]; }
      }
    }
    return { rect: [rect.left, rect.top], w: canvas.width, h: canvas.height, green, total, first };
  });
  console.log('pixels', JSON.stringify(px));
  const direct = await page.evaluate(async () => {
    const canvas = document.querySelector('.battle-map canvas');
    const ctx = canvas.getContext('2d');
    const img = new Image();
    img.src = '/maps/ironbottom.jpg';
    await new Promise(done => { img.onload = done; });
    ctx.drawImage(img, 392 - 40, 306 - 30, 80, 60);
    const a = ctx.getImageData(392, 306, 1, 1).data;
    return [a[0], a[1], a[2]];
  });
  console.log('direct draw pixel', JSON.stringify(direct));
  console.log('dataset', await page.evaluate(() => document.querySelector('.battle-map canvas')?.getAttribute('data-photo')));
  console.log('errors:', JSON.stringify(errors));
  await page.screenshot({ path: 'artifacts/client/savo/savo-underlay.png' });
  const obs = await q('observe');
  console.log('ships', obs.ships.length, 'islands', JSON.stringify(obs.islands.map(i => i.length)));
} finally { await browser.close(); }
