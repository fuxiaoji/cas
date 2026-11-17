import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import fs from 'node:fs/promises';
const root=resolve(import.meta.dirname,'..');
const require=createRequire(resolve(root,'client/package.json'));
const {chromium}=require('playwright');
const out=resolve(root,'output',process.argv[2]??'tactical-specialists-20261116');
const count=Number(process.argv[3]??6);
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
const checks=[],errors=[];
try {
 const page=await browser.newPage();
 page.on('pageerror',e=>errors.push(String(e)));
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:1000});
  await page.goto(pathToFileURL(resolve(out,'index.html')).href);
  await page.waitForFunction(n=>document.images.length===n&&[...document.images].every(i=>i.complete&&i.naturalWidth>0),count);
  const state=await page.evaluate(()=>({overflow:document.documentElement.scrollWidth>innerWidth,images:document.images.length,downloads:document.querySelectorAll('a[download][href$=".png"]').length,cards:document.querySelectorAll('article').length}));
  if(state.overflow||state.cards!==count||state.downloads!==count)throw Error(JSON.stringify(state));
  await page.screenshot({path:resolve(out,`gallery-${width}.png`)});
  checks.push({width,...state});
 }
 if(errors.length)throw Error(errors.join('\n'));
 await fs.writeFile(resolve(out,'browser-validation.json'),JSON.stringify({checks,errors},null,2));
 console.log(JSON.stringify({checks,errors}));
}finally{await browser.close()}
