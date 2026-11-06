import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { resumeExercise, signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
const out = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/guidance/', import.meta.url));
await fs.mkdir(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH });

try {
  const page = await browser.newPage({ viewport: { width: 740, height: 360 }, hasTouch: true, isMobile: true, reducedMotion: 'reduce' });
  page.setDefaultTimeout(6_000);
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(url);
  await signInLocal(page, 'cas-guidance-qa', true);
  await resumeExercise(page);
  const button = (name) => page.getByRole('button', { name, exact: true });
  const map = page.locator('.battle-map');
  const chart = page.locator('.chart-column');

  // Mount the shared components into the running real chart while testing them
  // independently of the scenario-specific main integration.
  const result = await page.evaluate(async () => {
    const resource = (filename) => performance.getEntriesByType('resource').find(entry => new URL(entry.name).pathname.endsWith('/' + filename))?.name;
    const [react, dom, story, tutorial] = await Promise.all([
      import(resource('react.js')), import(resource('react-dom_client.js')), import('/src/prologue/index.ts'), import('/src/tutorial/index.ts'),
    ]);
    const { createElement: h, useState } = react.default;
    const { guidedTrainingDone, guidedTrainingProgress, recordGuidedTrainingSignals } = tutorial;
    const scene = story.initialPrologueProgress();
    const initial = { ...scene, step: 1, dialogue: 1 };
    const withoutOrder = recordGuidedTrainingSignals('follow', {}, ['gunFired', 'followAccepted', 'followPreview']);
    const withRoute = recordGuidedTrainingSignals('follow', withoutOrder, ['followMode', 'followPreview', 'followAccepted']);
    const withGun = recordGuidedTrainingSignals('follow', withRoute, ['gunFired', 'gunOrdered']);
    const cancelWithoutPoint = recordGuidedTrainingSignals('sync', {}, ['followMode', 'draftCancelled']);
    const afterCancel = recordGuidedTrainingSignals('sync', cancelWithoutPoint, ['routePoint', 'draftCancelled', 'syncMode']);
    const throughClock = ['fleetViewed', 'mapViewed', 'followMode', 'followPreview', 'followAccepted', 'paused', 'stepped'];
    const night = recordGuidedTrainingSignals('night', {}, throughClock, { radar: true });
    const withRadar = recordGuidedTrainingSignals('night', night,
      ['radarContactViewed', 'radarViewed', 'radarPowered', 'radarContactViewed'], { radar: true });

    const host = document.createElement('div');
    host.style.display = 'contents';
    document.querySelector('.chart-column').append(host);
    const root = dom.default.createRoot(host);
    function Overlay() {
      const [progress, setProgress] = useState(initial);
      return h(story.PrologueDialogue, { progress, onProgress: setProgress, placement: 'chart' });
    }
    root.render(h(Overlay));
    window.__casGuidanceQa = {
      coach() {
        root.render(h(tutorial.TrainingCoach, { course: 'follow', evidence: withoutOrder, guided: true, onExit() {}, onFinish() {} }));
      },
      afterMode() {
        root.render(h(tutorial.TrainingCoach, { course: 'follow', evidence: { followMode: true }, guided: true, onExit() {}, onFinish() {} }));
      },
      close() { root.unmount(); host.remove(); },
    };
    return {
      hasDialogue: story.hasPrologueDialogue(initial),
      noDialogue: story.hasPrologueDialogue({ ...scene, step: 7 }),
      outOfOrder: withoutOrder,
      nextAfterRoute: guidedTrainingProgress('follow', withRoute).next,
      nextAfterLateOrder: guidedTrainingProgress('follow', withGun).next,
      genuineShotCompletes: guidedTrainingDone('follow', recordGuidedTrainingSignals('follow', withGun, ['gunFired'])),
      cancelWaitsForPoint: guidedTrainingProgress('sync', cancelWithoutPoint).next,
      nextAfterCancellation: guidedTrainingProgress('sync', afterCancel).next,
      radarNext: guidedTrainingProgress('night', night, { radar: true }).next,
      opticalNext: guidedTrainingProgress('night', night).next,
      afterRadar: guidedTrainingProgress('night', withRadar, { radar: true }).next,
    };
  });
  assert.deepEqual(result, {
    hasDialogue: true, noDialogue: false, outOfOrder: {}, nextAfterRoute: 'gunOrdered',
    nextAfterLateOrder: 'gunFired', genuineShotCompletes: true, cancelWaitsForPoint: 'routePoint',
    nextAfterCancellation: 'syncPreview', radarNext: 'radarViewed', opticalNext: 'contactViewed', afterRadar: 'contactViewed',
  });
  const dialogue = chart.getByRole('region', { name: '剧情对话' });
  await dialogue.waitFor();
  await map.locator('[data-ship] .ship-hull').first().waitFor();
  const fits = await dialogue.evaluate(panel => {
    const box = panel.getBoundingClientRect(), chart = panel.closest('.chart-column').getBoundingClientRect();
    return box.left >= chart.left && box.right <= chart.right && box.top >= chart.top && box.bottom <= chart.bottom &&
      box.height < chart.height / 2;
  });
  assert(fits, 'Landscape dialogue must leave at least half of the chart visible.');
  assert.equal(await page.evaluate(() => document.activeElement?.getAttribute('aria-label')), '剧情对话');
  await button('先告诉我，舰队怎么样了？').tap();
  await dialogue.locator('p').filter({ hasText: '五艘驱逐舰仍在等你的命令' }).waitFor();
  await page.screenshot({ path: out + '/01-chart-dialogue.png' });

  await page.evaluate(() => window.__casGuidanceQa.coach());
  const coach = page.getByRole('region', { name: '白汐实操引导' });
  await coach.getByText('在「编队」中点「领舰移动」。', { exact: true }).waitFor();
  const mode = button('领舰移动');
  await mode.and(page.locator('[data-guide-active]')).waitFor();
  await mode.tap();
  await page.evaluate(() => window.__casGuidanceQa.afterMode());
  await map.and(page.locator('[data-guide-active]')).waitFor();
  assert.equal(await mode.getAttribute('data-guide-active'), null);
  await page.screenshot({ path: out + '/02-chart-guide.png' });
  await page.evaluate(() => window.__casGuidanceQa.close());
  assert.equal(await page.locator('[data-guide-active]').count(), 0);
  assert.deepEqual(errors, []);

  const receipt = { ...result, chartDialogueAt740x360: fits, realGuideTargets: ['领舰移动', '战术海图'], highlightRemoved: true };
  await fs.writeFile(out + '/browser-receipt.json', JSON.stringify(receipt, null, 2));
  console.log(JSON.stringify(receipt, null, 2));
} finally {
  await browser.close();
}
