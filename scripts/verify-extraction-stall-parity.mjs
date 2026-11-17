// Replay actual-player recovery and new autonomous voyages on native and WASM.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..');
const manifest=JSON.parse(await readFile(resolve(root,'godot/bin/core-current.json'),'utf8'));
const exe=process.env.CAS_STALL_NATIVE||resolve(root,'godot/bin',manifest.executable);
const baseline=resolve(root,'godot/bin/runtime/ddf088630609814e/cas-sim.exe');
const wasmPath=resolve(root,'target/arena-wasm-build/wasm32-unknown-unknown/release/cas_core.wasm');
const wasm=await readFile(wasmPath);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
function native(path){
 const child=spawn(path,[],{stdio:['pipe','pipe','pipe']});
 const lines=createInterface({input:child.stdout})[Symbol.asyncIterator]();
 let error='';child.stderr.on('data',s=>error+=s);
 return {async ask(q){child.stdin.write(JSON.stringify(q)+'\n');const row=await lines.next();assert.ok(!row.done,error||'core closed');return row.value;},close(){child.stdin.end();}};
}
async function wasmer(){
 const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports,enc=new TextEncoder(),dec=new TextDecoder();
 return q=>{
  // cas-sim unwraps serialized transport saves before calling the shared core.
  // Embed the original JSON verbatim for WASM; do not round u64 values through JS.
  let wire=JSON.stringify(q);
  if(typeof q.serialized==='string'&&['load','replay'].includes(q.op)){
   const fields={...q};delete fields.serialized;
   wire=JSON.stringify(fields).slice(0,-1)+',"save":'+q.serialized+'}';
  }
  const bytes=enc.encode(wire),p=api.cas_alloc(bytes.length)>>>0;new Uint8Array(api.memory.buffer,p,bytes.length).set(bytes);const out=api.cas_request(p,bytes.length)>>>0;const raw=dec.decode(new Uint8Array(api.memory.buffer,out,api.cas_response_len()>>>0));return {raw,value:JSON.parse(raw)};
 };
}
const out=resolve(root,process.env.CAS_STALL_OUTPUT||'artifacts/extraction-stall-20261113');await mkdir(out,{recursive:true});
const files=process.argv.slice(2);assert.ok(files.length,'Supply actual v3 voyage command fixtures');
const reports=[];
for(const file of files){
 const qs=JSON.parse(await readFile(resolve(root,file),'utf8'));
 let expectedExtracted=true;
 try{const detail=JSON.parse(await readFile(resolve(root,file.replace(/-commands\.json$/,'-native.json')),'utf8'));expectedExtracted=detail.summary?.expected_extracted!==false;}catch(error){if(error.code!=='ENOENT')throw error;}
 const core=native(exe),ask=await wasmer();let last,maxRoundtripMs=0;const started=performance.now();
 try{
  for(let i=0;i<qs.length;i++){
   const before=performance.now();const nativeRaw=await core.ask(qs[i]),a=JSON.parse(nativeRaw),b=ask(qs[i]);maxRoundtripMs=Math.max(maxRoundtripMs,performance.now()-before);assert.equal(nativeRaw,b.raw,`${file} native/WASM raw bytes request ${i}`);assert.equal(a.ok,true,`${file} request ${i}`);last=a.data||last;
  }
  reports.push({file,requests:qs.length,nativeWasm:true,rawBytesIdentical:true,tick:last?.tick,result:last?.result,extracted:last?.salvage?.extracted,expectedExtracted,wallTimeSeconds:(performance.now()-started)/1000,maxRoundtripMs});console.log(JSON.stringify(reports.at(-1)));
 }finally{core.close();}
}
const frozenFile='artifacts/extraction-stall-20261113/actual-v2-diagnosis-commands.json';
const old=native(baseline),now=native(exe);let bytes=0;
const qs=JSON.parse(await readFile(resolve(root,frozenFile),'utf8'));
try{for(let i=0;i<qs.length;i++){const [a,b]=await Promise.all([old.ask(qs[i]),now.ask(qs[i])]);assert.equal(a,b,`v2 actual save frozen request ${i}`);bytes+=Buffer.byteLength(a);}}finally{old.close();now.close();}
const autonomousTerminalsValid=reports.every(r=>r.extracted===r.expectedExtracted&&r.result!=null);
const report={native:exe,nativeSha256:hash(await readFile(exe)),wasmPath,wasmSha256:hash(wasm),reports,frozen:{file:frozenFile,requests:qs.length,bytes,oldBytesUnchanged:true},parityPassed:true,autonomousTerminalsValid,passed:autonomousTerminalsValid};
await writeFile(resolve(out,'parity-receipt.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
assert.ok(autonomousTerminalsValid,'Every selected voyage must genuinely terminate with its expected extraction outcome, not merely match the same stalled native/WASM state');
