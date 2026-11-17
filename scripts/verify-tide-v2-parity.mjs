// Stream every request: compare the complete native and WASM JSON bytes.
// Transport saves are inserted as original JSON, preserving integer precision.
import assert from 'node:assert/strict';
import {readFile,writeFile,readdir,mkdir} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {resolve,basename} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),dir=resolve(root,'artifacts/tide-v2-core');await mkdir(dir,{recursive:true});
const native=process.env.CAS_TIDE_NATIVE||resolve(root,'target/tide-v2-build/release/cas-sim.exe');
const wasmPath=process.env.CAS_TIDE_WASM||resolve(root,'target/tide-v2-wasm-build/wasm32-unknown-unknown/release/cas_core.wasm');
const baseline=resolve(root,'godot/bin/runtime/c4c2a09b58d80b5b/cas-sim.exe');
const wasm=await readFile(wasmPath),sha=b=>createHash('sha256').update(b).digest('hex');
function core(path){const p=spawn(path,[],{stdio:['pipe','pipe','pipe']}),lines=createInterface({input:p.stdout})[Symbol.asyncIterator]();let err='';p.stderr.on('data',x=>err+=x);return{async ask(q){p.stdin.write(JSON.stringify(q)+'\n');const r=await lines.next();assert.equal(r.done,false,err||'native core exited');return r.value;},close(){p.stdin.end();}};}
async function wasmer(){const{instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports,enc=new TextEncoder(),dec=new TextDecoder();return q=>{let wire=JSON.stringify(q);if(typeof q.serialized==='string'&&['load','replay'].includes(q.op)){const fields={...q};delete fields.serialized;wire=JSON.stringify(fields).slice(0,-1)+',"save":'+q.serialized+'}';}const bytes=enc.encode(wire),p=api.cas_alloc(bytes.length)>>>0;new Uint8Array(api.memory.buffer,p,bytes.length).set(bytes);const r=api.cas_request(p,bytes.length)>>>0;return dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0));};}
const reports=[];
const requested=process.argv.slice(2),cases=requested.length?requested.map(f=>resolve(root,f)):(await readdir(dir)).filter(f=>f.endsWith('-commands.json')).map(f=>resolve(dir,f));
async function run(file,legacy=false){
 const qs=JSON.parse(await readFile(file,'utf8')),now=core(native),old=legacy?core(baseline):null,wasmAsk=await wasmer();let bytes=0,last;const times={};
 try{
  for(let i=0;i<qs.length;i++){
   const q=qs[i],before=performance.now(),a=await now.ask(q),middle=performance.now(),b=wasmAsk(q),after=performance.now();
   const t=times[q.op]||={count:0,nativeTotalMs:0,wasmTotalMs:0,nativeMaxMs:0,wasmMaxMs:0};t.count++;t.nativeTotalMs+=middle-before;t.wasmTotalMs+=after-middle;t.nativeMaxMs=Math.max(t.nativeMaxMs,middle-before);t.wasmMaxMs=Math.max(t.wasmMaxMs,after-middle);
   if(a!==b){await writeFile(resolve(dir,'raw-mismatch-native.json'),a);await writeFile(resolve(dir,'raw-mismatch-wasm.json'),b);}
   assert.equal(a,b,`${basename(file)} native/WASM raw request ${i} (${q.op})`);
   if(old)assert.equal(a,await old.ask(q),`${basename(file)} frozen v1 raw request ${i}`);
   bytes+=Buffer.byteLength(a);const r=JSON.parse(a);if(r.data?.ships)last=r.data;
  }
  if(!legacy){const evidence=JSON.parse(await readFile(file.replace(/-commands\.json$/,'-native.json'),'utf8'));if(evidence.summary.kind!=='protocol'){assert.ok(last?.tide?.outcome,'real terminal');assert.equal(last.tide.outcome.success,evidence.summary.expected_success,'expected real objective result');}}
  const row={file,legacy,requests:qs.length,bytes,rawBytesIdentical:true,legacyBytesFrozen:legacy,tick:last?.tick,result:last?.tide?.outcome||null,timings:times};reports.push(row);console.log(JSON.stringify({file:basename(file),requests:qs.length,rawBytesIdentical:true,legacy,tick:row.tick,result:row.result}));
 }finally{now.close();old?.close();}
}
try{
 for(const file of cases)await run(file);
 for(const file of (await readdir(resolve(root,'artifacts/tide-play'))).filter(f=>f.endsWith('-commands.json')))await run(resolve(root,'artifacts/tide-play',file),true);
 const report={passed:true,native,nativeSha256:sha(await readFile(native)),wasmPath,wasmSha256:sha(wasm),baseline,baselineSha256:sha(await readFile(baseline)),reports};await writeFile(resolve(dir,'parity-receipt.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({passed:true,fixtures:reports.length,requests:reports.reduce((n,r)=>n+r.requests,0),bytes:reports.reduce((n,r)=>n+r.bytes,0)}));
}catch(error){await writeFile(resolve(dir,'parity-failure.json'),JSON.stringify({message:error.message,stack:error.stack,reports},null,2));throw error;}
