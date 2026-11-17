// Compare full response bytes, including original serialized save integers.
import assert from 'node:assert/strict';
import {readFile,writeFile,readdir,mkdir} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {resolve,basename} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),dir=resolve(root,'artifacts/littoral-core');await mkdir(dir,{recursive:true});
const native=process.env.CAS_LITTORAL_NATIVE||resolve(root,'target/littoral-build/release/cas-sim.exe');
const wasmPath=process.env.CAS_LITTORAL_WASM||resolve(root,'target/littoral-wasm-build/wasm32-unknown-unknown/release/cas_core.wasm');
const baseline=resolve(root,'godot/bin/runtime/f38a927ce8ef4d24/cas-sim.exe');
const wasm=await readFile(wasmPath),sha=b=>createHash('sha256').update(b).digest('hex');
function core(path){const p=spawn(path,[],{stdio:['pipe','pipe','pipe']}),lines=createInterface({input:p.stdout})[Symbol.asyncIterator]();let error='';p.stderr.on('data',x=>error+=x);return{async ask(q){p.stdin.write(JSON.stringify(q)+'\n');const row=await lines.next();assert.equal(row.done,false,error||'native exited');return row.value;},close(){p.stdin.end();}};}
async function wasmer(){const{instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports,enc=new TextEncoder(),dec=new TextDecoder();return q=>{let wire=JSON.stringify(q);if(typeof q.serialized==='string'&&['load','replay'].includes(q.op)){const fields={...q};delete fields.serialized;wire=JSON.stringify(fields).slice(0,-1)+',"save":'+q.serialized+'}';}const bytes=enc.encode(wire),p=api.cas_alloc(bytes.length)>>>0;new Uint8Array(api.memory.buffer,p,bytes.length).set(bytes);const r=api.cas_request(p,bytes.length)>>>0;return dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0));};}
const reports=[];
async function run(file,legacy=false){const qs=JSON.parse(await readFile(file,'utf8')),now=core(native),old=legacy?core(baseline):null,wasmAsk=await wasmer(),timings={};let bytes=0,last;
 try{for(let i=0;i<qs.length;i++){const q=qs[i],a0=performance.now(),a=await now.ask(q),a1=performance.now(),b=wasmAsk(q),a2=performance.now();const t=timings[q.op]||={count:0,nativeTotalMs:0,wasmTotalMs:0,nativeMaxMs:0,wasmMaxMs:0};t.count++;t.nativeTotalMs+=a1-a0;t.wasmTotalMs+=a2-a1;t.nativeMaxMs=Math.max(t.nativeMaxMs,a1-a0);t.wasmMaxMs=Math.max(t.wasmMaxMs,a2-a1);
   if(a!==b){await writeFile(resolve(dir,'raw-mismatch-native.json'),a);await writeFile(resolve(dir,'raw-mismatch-wasm.json'),b);await writeFile(resolve(dir,'raw-mismatch-request.json'),JSON.stringify({file,i,q},null,2));}
   assert.equal(a,b,`${basename(file)} raw native/WASM ${i} ${q.op}`);if(old)assert.equal(a,await old.ask(q),`${basename(file)} frozen f38 ${i}`);bytes+=Buffer.byteLength(a);const r=JSON.parse(a);if(r.data?.ships)last=r.data;
  }
  if(!legacy){const evidence=JSON.parse(await readFile(file.replace(/-commands\.json$/,'-native.json'),'utf8'));assert.ok(last?.littoral?.outcome,'actual terminal');assert.equal(last.littoral.outcome.success,evidence.summary.expected_success,'actual success matches recorded expectation');}
  const row={file,legacy,requests:qs.length,bytes,rawBytesIdentical:true,legacyBytesFrozen:legacy,tick:last?.tick,result:last?.littoral?.outcome||null,timings};reports.push(row);console.log(JSON.stringify({file:basename(file),requests:qs.length,bytes,legacy,tick:row.tick}));
 }finally{now.close();old?.close();}}
try{
 const args=process.argv.slice(2),files=args.length?args.map(f=>resolve(root,f)):(await readdir(dir)).filter(f=>f.endsWith('-commands.json')).map(f=>resolve(dir,f));for(const f of files)await run(f);
 const legacyFiles=['normal-42','normal-43','hard-44','deadline-43','stationary-45'].map(n=>`artifacts/tide-play/${n}-commands.json`);
 legacyFiles.push('artifacts/tide-v2-core/tide-v2-normal-42-heavy-commands.json','artifacts/extraction-stall-20261113/actual-v2-diagnosis-commands.json','artifacts/arena-autonomy/arena-ranked-commands.json');
 for(const f of legacyFiles)await run(resolve(root,f),true);
 await writeFile(resolve(dir,'parity-receipt.json'),JSON.stringify({passed:true,native,nativeSha256:sha(await readFile(native)),wasmPath,wasmSha256:sha(wasm),baseline,baselineSha256:sha(await readFile(baseline)),reports},null,2));console.log(JSON.stringify({passed:true,fixtures:reports.length,requests:reports.reduce((n,r)=>n+r.requests,0),bytes:reports.reduce((n,r)=>n+r.bytes,0)}));
}catch(error){await writeFile(resolve(dir,'parity-failure.json'),JSON.stringify({message:error.message,stack:error.stack,reports},null,2));throw error;}
