import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const root=resolve(import.meta.dirname,'..');
const require=createRequire(resolve(root,'client/package.json'));
const {chromium}=require('playwright');
const out=resolve(root,'output/tactical-cg-pairs-20261115');
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
const errors=[];const checks=[];
try {
 const page=await browser.newPage();page.on('pageerror',e=>errors.push(String(e)));
 for(const [width,height] of [[1440,1100],[390,844]]) {
  await page.setViewportSize({width,height});await page.goto(pathToFileURL(resolve(out,'index.html')).href);
  await page.locator('img').evaluateAll(xs=>Promise.all(xs.map(x=>x.decode())));
  assert.equal(await page.locator('section').count(),5);assert.equal(await page.locator('img').count(),10);
  assert.equal(await page.locator('a[download]').count(),10);
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  await page.screenshot({path:resolve(out,`gallery-${width}.png`)});
  await page.locator('section').last().scrollIntoViewIfNeeded();await page.screenshot({path:resolve(out,`gallery-end-${width}.png`)});
  const href=await page.locator('figure a').last().getAttribute('href');await page.locator('figure a').last().click();
  assert.ok(page.url().endsWith(href));assert.ok(await page.locator('img').evaluate(i=>i.complete&&i.naturalWidth>0));
  checks.push({width,images:10,groups:5,overflow:false,lastOriginalOpens:true});
 }
 assert.deepEqual(errors,[]);
 const result={passed:true,checks,errors};await writeFile(resolve(out,'browser-verification.json'),JSON.stringify(result,null,2));console.log(result);
} finally {await browser.close();}
