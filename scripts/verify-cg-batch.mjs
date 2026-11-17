import {createRequire} from 'node:module';
import {resolve,basename} from 'node:path';
import {pathToFileURL} from 'node:url';
import fs from 'node:fs/promises';
const root=resolve(import.meta.dirname,'..');
const doc=resolve(process.argv[2]);
const name=basename(doc);
const input=JSON.parse(await fs.readFile(resolve(doc,'generation-input.json'),'utf8'));
const count=input.jobs.length;
const require=createRequire(resolve(root,'client/package.json'));
const {chromium}=require('playwright');
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
const errors=[],checks=[];
try {
  const page=await browser.newPage();
  page.on('pageerror',e=>errors.push(String(e)));
  for(const width of [1440,390]) {
    await page.setViewportSize({width,height:1000});
    await page.goto(pathToFileURL(resolve(root,'output',name,'index.html')).href);
    await page.waitForFunction(n=>[...document.images].length===n&&[...document.images].every(i=>i.complete&&i.naturalWidth>0),count);
    const state=await page.evaluate(()=>({images:[...document.images].map(i=>[i.naturalWidth,i.naturalHeight]),overflow:document.documentElement.scrollWidth>innerWidth,downloads:document.querySelectorAll('a[download]').length}));
    if(state.overflow||state.downloads!==count)throw Error(JSON.stringify(state));
    checks.push({width,...state});
    await page.screenshot({path:resolve(doc,`gallery-${width}.png`),fullPage:true});
  }
  if(errors.length)throw Error(errors.join('\n'));
  const file=resolve(doc,'verification.json');
  const report=JSON.parse(await fs.readFile(file,'utf8'));
  report.browser_test={passed:true,checks,errors};
  await fs.writeFile(file,JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report.browser_test));
} finally {await browser.close()}
