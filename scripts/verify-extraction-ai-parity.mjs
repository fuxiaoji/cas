import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/extraction-autopilot');
const native=process.env.CAS_AI_NATIVE||resolve(root,'target/expedition-v2-build/release/cas-sim.exe');
const wasmPath=resolve(root,'target/wasm32-unknown-unknown/release/cas_core.wasm'),wasm=await readFile(wasmPath);
const report=JSON.parse(await readFile(resolve(out,'report.json'),'utf8'));
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a.localeCompare(b,'en'))):x);
const sha=v=>createHash('sha256').update(v).digest('hex');const results=[];
for(const row of report.results){
 const name=row.name,file=name==='native-authorization-takeover-and-mode-boundaries'?'controls-commands.json':name+'-commands.json';
 const requests=JSON.parse(await readFile(resolve(out,file),'utf8'));
 const p=spawnSync(native,[],{input:requests.map(JSON.stringify).join('\n')+'\n',encoding:'utf8',maxBuffer:256*1024*1024});assert.equal(p.status,0,p.stderr);
 const expected=p.stdout.trim().split(/\r?\n/).map(JSON.parse),actual=[];
 const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports,enc=new TextEncoder(),dec=new TextDecoder();
 for(const q of requests){const bytes=enc.encode(JSON.stringify(q)),ptr=api.cas_alloc(bytes.length)>>>0;new Uint8Array(api.memory.buffer,ptr,bytes.length).set(bytes);const result=api.cas_request(ptr,bytes.length)>>>0;actual.push(JSON.parse(dec.decode(new Uint8Array(api.memory.buffer,result,api.cas_response_len()>>>0))));}
 for(let i=0;i<expected.length;i++)assert.equal(canonical(actual[i]),canonical(expected[i]),`${name} request ${i} ${requests[i].op}`);
 const result={name,requests:requests.length,nativeWasmEqual:true,responseSha256:sha(canonical(actual))};results.push(result);console.log(JSON.stringify(result));
}
await writeFile(resolve(out,'parity.json'),JSON.stringify({native,nativeSha256:sha(await readFile(native)),wasm:wasmPath,wasmSha256:sha(wasm),passed:results.length,requests:results.reduce((n,r)=>n+r.requests,0),results},null,2));
