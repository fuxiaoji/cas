import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),dir=resolve(root,'artifacts/island-war-v4/core'),out=resolve(root,'artifacts/island-war-v4/parity');await mkdir(out,{recursive:true});
const native=process.env.CAS_LITTORAL_NATIVE,wasmPath=process.env.CAS_LITTORAL_WASM;assert.ok(native&&wasmPath);const wasm=await readFile(wasmPath),hash=b=>createHash('sha256').update(b).digest('hex'),rows=[];
const names=process.env.CAS_V4_PARITY_CASES?.split(',').filter(Boolean)??['catalogue-and-preview','022-bodyless','manual-default-cover','new-five-autonomy',...['landing','weapons','artillery','airborne','roles','combined_arms'].map(l=>'training-'+l+'-terminal')];
for(const name of names){
 const source=JSON.parse(await readFile(resolve(dir,name+'.json'),'utf8'));const p=spawn(native,[],{stdio:['pipe','pipe','inherit']}),lines=createInterface({input:p.stdout})[Symbol.asyncIterator]();const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports,enc=new TextEncoder(),dec=new TextDecoder();let n=0,bytes=0,view;
 async function call(q){const text=JSON.stringify(q);p.stdin.write(text+'\n');const data=enc.encode(text),ptr=api.cas_alloc(data.length)>>>0;new Uint8Array(api.memory.buffer,ptr,data.length).set(data);const r=api.cas_request(ptr,data.length)>>>0;const raw=dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0));const line=await lines.next();assert.equal(line.done,false);assert.equal(line.value,raw,`${name} #${n} ${q.op}`);n++;bytes+=Buffer.byteLength(raw);const result=JSON.parse(raw);if(result.ok&&result.data.ships)view=result.data;return result;}
 try{
  for(const q of source.commands)await call(q);
  if(source.save||source.snapshot){const saved=(await call({op:'save'})).data;const terminal=structuredClone(view);await call({op:'load',save:saved});assert.deepEqual(view,terminal);for(const tick of [0,Math.min(saved.tick,12),saved.tick])await call({op:'replay',save:saved,tick});assert.deepEqual(view,terminal);}
  rows.push({name,requests:n,bytes,raw_identical:true,tick:view?.tick,success:view?.result?.success});console.log(JSON.stringify(rows.at(-1)));
 }finally{p.stdin.end();}
}
const receipt={passed:true,native,native_sha256:hash(await readFile(native)),wasm:wasmPath,wasm_sha256:hash(wasm),cases:rows,requests:rows.reduce((a,b)=>a+b.requests,0),scope:'Listed complete public command streams and, where applicable, save/load/forward-back replay; raw native/WASM UTF-8 identity'};await writeFile(resolve(out,process.env.CAS_V4_PARITY_RECEIPT??'receipt.json'),JSON.stringify(receipt,null,2));console.log(JSON.stringify(receipt));
