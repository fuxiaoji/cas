import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const root=resolve(import.meta.dirname,'..');
const require=createRequire(resolve(root,'client/package.json'));
const {chromium}=require('playwright');
const out=resolve(root,'artifacts/carrier-20261115/album');await mkdir(out,{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:process.env.CAS_BROWSER_PATH||'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1100},deviceScaleFactor:1});
 const errors=[];page.on('pageerror',e=>errors.push(String(e)));
 await page.goto(pathToFileURL(resolve(root,'output/carrier-20261115/index.html')).href);
 await page.locator('img').evaluateAll(imgs=>Promise.all(imgs.map(i=>i.decode())));
 assert.equal(await page.locator('article').count(),7);assert.equal(await page.locator('img').count(),28);
 assert.equal(await page.locator('#source tr').count(),15);
 await page.screenshot({path:resolve(out,'gallery-desktop.png')});
 for(let i=0;i<7;i++)await page.locator('article').nth(i).screenshot({path:resolve(out,`character-${i+1}.png`)});
 const overview=await page.addStyleTag({content:'header,#source,#guide{display:none}main{max-width:none;padding:16px}.grid{grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}article{padding:12px}article h2{font-size:21px}.art{min-height:300px}.portrait{height:300px}.sd>img{max-height:140px}.sizes{display:none}article p{font-size:12px}small{font-size:10px}'});
 await page.locator('#art').screenshot({path:resolve(out,'seven-character-overview.png')});await overview.evaluate(e=>e.remove());
 await page.locator('nav a[href="#guide"]').click();assert.ok(await page.locator('#guide').isVisible());
 const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);assert.equal(overflow,false);
 await page.setViewportSize({width:390,height:844});await page.goto(pathToFileURL(resolve(root,'output/carrier-20261115/index.html')).href);
 await page.locator('img').evaluateAll(imgs=>Promise.all(imgs.map(i=>i.decode())));
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
 await page.screenshot({path:resolve(out,'gallery-mobile.png')});assert.deepEqual(errors,[]);
 // The exact opt-in command replay also runs in the actual browser WASM host.
 const wasm=(await readFile(resolve(root,'target-carrier/wasm32-unknown-unknown/release/cas_core.wasm'))).toString('base64');
 const commands=JSON.parse(await readFile(resolve(root,'artifacts/carrier-20261115/ops-commands.json'),'utf8'));
 const replay=await page.evaluate(async({wasm,commands})=>{
  const b=Uint8Array.from(atob(wasm),c=>c.charCodeAt(0)),{instance}=await WebAssembly.instantiate(b,{}),a=instance.exports;
  const e=new TextEncoder(),d=new TextDecoder();let v,peak=0;
  for(const q of commands){const bytes=e.encode(JSON.stringify(q)),p=a.cas_alloc(bytes.length)>>>0;new Uint8Array(a.memory.buffer,p,bytes.length).set(bytes);const r=a.cas_request(p,bytes.length)>>>0;v=JSON.parse(d.decode(new Uint8Array(a.memory.buffer,r,a.cas_response_len()>>>0)));if(!v.ok)throw Error(JSON.stringify(v));if(v.data?.littoral?.aviation)peak=Math.max(peak,v.data.littoral.aviation.aircraft.length);}
  return {calls:commands.length,peak,version:v.data.littoral.carrier_ops.version};
 },{wasm,commands});
 assert.equal(replay.calls,218);assert.ok(replay.peak<=24);
 const receipt={passed:true,characters:7,decodedImages:28,sourceRows:14,mobileOverflow:false,pageErrors:errors,browserWasm:replay,gameplayUi:'native Godot tested separately; this page is the art and tutorial album'};
 await writeFile(resolve(out,'receipt.json'),JSON.stringify(receipt,null,2));console.log(receipt);
}finally{await browser.close();}
