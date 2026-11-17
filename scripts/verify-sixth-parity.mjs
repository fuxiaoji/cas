import fs from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/sixth-infantry');
const source=JSON.parse(await fs.readFile(resolve(out,'public-session.json'),'utf8'));
const bytes=await fs.readFile(resolve(root,'target-sixth/wasm32-unknown-unknown/release/cas_core.wasm'));
const hash=x=>createHash('sha256').update(x).digest('hex');
async function run(api){const enc=new TextEncoder(),dec=new TextDecoder(),responses=[];for(const q of source.commands){const b=enc.encode(JSON.stringify(q)),p=api.cas_alloc(b.length)>>>0;new Uint8Array(api.memory.buffer,p,b.length).set(b);const r=api.cas_request(p,b.length)>>>0;responses.push(dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0)));}return responses;}
const {instance}=await WebAssembly.instantiate(bytes,{});const responses=await run(instance.exports);
if(responses.some((r,i)=>r!==source.responses[i]))throw Error('native/WASM mismatch at '+responses.findIndex((r,i)=>r!==source.responses[i]));
const require=createRequire(resolve(root,'client/package.json'));const {chromium}=require('playwright');const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
try{const page=await browser.newPage();await page.route('https://cas-audit.test/',r=>r.fulfill({contentType:'text/html',body:'<!doctype html><title>CAS audit</title>'}));await page.goto('https://cas-audit.test/');const hashes=await page.evaluate(async({bytes,commands})=>{const {instance}=await WebAssembly.instantiate(Uint8Array.from(bytes),{}),api=instance.exports,enc=new TextEncoder(),dec=new TextDecoder(),hashes=[];for(const q of commands){const b=enc.encode(JSON.stringify(q)),p=api.cas_alloc(b.length)>>>0;new Uint8Array(api.memory.buffer,p,b.length).set(b);const r=api.cas_request(p,b.length)>>>0,raw=dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0)),h=await crypto.subtle.digest('SHA-256',enc.encode(raw));hashes.push([...new Uint8Array(h)].map(x=>x.toString(16).padStart(2,'0')).join(''));}return hashes;},{bytes:[...bytes],commands:source.commands});
if(hashes.some((h,i)=>h!==hash(source.responses[i])))throw Error('browser mismatch');
await fs.writeFile(resolve(out,'parity.json'),JSON.stringify({passed:true,requests:responses.length,native_wasm_raw_identical:true,browser_identical:true,browser:browser.version(),wasm_sha256:hash(bytes)},null,2));console.log('native/WASM/Edge parity passed',responses.length);
}finally{await browser.close();}
