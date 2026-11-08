import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs/promises';
import { signInLocal } from './browser-login.mjs';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const root = process.env.CAS_ARTIFACTS || 'artifacts/client/tutorial/';
await fs.mkdir(root, { recursive: true });
const errors = [];
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const page = await (await browser.newContext({ viewport: { width: 1360, height: 768 } })).newPage();
page.on('pageerror', e => errors.push(e.stack));
try {
  await page.goto('http://127.0.0.1:5175/');
  await signInLocal(page, 'cas-tutorial-' + Date.now().toString(36), true);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await signInLocal(page, 'cas-tutorial-' + Date.now().toString(36), true);
  await page.locator('.growth-lesson').click();
  await page.getByRole('button', { name: '进入实操演习', exact: true }).click();
  await page.locator('.guided-tutorial').waitFor();
  for (let step = 0; step < 9; step++) {
    const spot = await page.locator('.guided-spot').boundingBox();
    assert(spot, 'spotlight missing');
    await page.mouse.click(spot.x + spot.width / 2, spot.y + spot.height / 2);
    await page.waitForTimeout(450);
    console.log('step', step + 1, await page.locator('.guided-panel h2').innerText().catch(() => 'done'));
  }
  await page.waitForTimeout(600);
  console.log('tutorial finished; errors', errors.length);
  await page.screenshot({ path: root + 'guided-finished.png' });
  assert.deepEqual(errors, []);
  await fs.writeFile(root + 'browser-receipt.json', JSON.stringify({ ok: true }, null, 2));
} finally { await browser.close(); }
