import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/littoral-v4');
const native=process.env.CAS_LITTORAL_NATIVE,wasmPath=process.env.CAS_LITTORAL_WASM;assert.ok(native&&wasmPath);
const hash=b=>createHash('sha256').update(b).digest('hex');
class Sim{constructor(exe=native){this.p=spawn(exe,[],{stdio:['pipe','pipe','inherit']});this.lines=createInterface({input:this.p.stdout})[Symbol.asyncIterator]();}async raw(q){this.p.stdin.write(JSON.stringify(q)+'\n');const r=await this.lines.next();assert.equal(r.done,false);return r.value;}close(){this.p.stdin.end();}}
async function files(dir,prefix=''){return(await readdir(resolve(root,dir))).filter(f=>f.startsWith(prefix)&&f.endsWith('-commands.json')).map(f=>resolve(root,dir,f));}
const old12=await files('artifacts/littoral-core');old12.push(...await files('artifacts/littoral-v2','v2-'));
const old3=await files('artifacts/littoral-v3','v3-'),fresh=await files('artifacts/littoral-v4','v4-');
async function freeze(list,exe){let requests=0,bytes=0;for(const file of list){const a=new Sim(),b=new Sim(exe);try{for(const q of JSON.parse(await readFile(file,'utf8'))){const x=await a.raw(q),y=await b.raw(q);assert.equal(x,y,`frozen ${file} #${requests} ${q.op}`);requests++;bytes+=Buffer.byteLength(x);}}finally{a.close();b.close();}}return{files:list.length,requests,bytes,oracle:exe,sha:hash(await readFile(exe))};}
const legacy12=await freeze(old12,resolve(root,'godot/bin/runtime/db75a0459d23c3c8/cas-sim.exe'));
const legacy3=await freeze(old3,resolve(root,'godot/bin/runtime/696ed97942e17473/cas-sim.exe'));
const wasm=await readFile(wasmPath);let requests=0,bytes=0;
try{fresh.push(...await files('artifacts/littoral-v4/multi','v4-'));}catch{}
const expedition=resolve(root,'artifacts/amphibious-expedition/native-wasm-calls.jsonl'),carriers=resolve(root,'artifacts/amphibious-expedition/carrier-wasm-calls.jsonl');
const multiExpedition=resolve(root,'artifacts/amphibious-expedition/multicompany-wasm-calls.jsonl');
const all=[...old12,...old3,...fresh];
for(const file of [...all,expedition,carriers,multiExpedition]){const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports,sim=new Sim(),enc=new TextEncoder(),dec=new TextDecoder();try{const source=await readFile(file,'utf8');const calls=file.endsWith('.jsonl')?source.trim().split(/\r?\n/).map(s=>JSON.parse(s)):JSON.parse(source);for(const q of calls){let text=JSON.stringify(q);if(typeof q.serialized==='string'&&['load','replay'].includes(q.op)){const fields={...q};delete fields.serialized;text=JSON.stringify(fields).slice(0,-1)+',"save":'+q.serialized+'}';}const wire=enc.encode(text),p=api.cas_alloc(wire.length)>>>0;new Uint8Array(api.memory.buffer,p,wire.length).set(wire);const r=api.cas_request(p,wire.length)>>>0;const result=dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0));assert.equal(await sim.raw(q),result,`WASM ${file} #${requests} ${q.op}`);requests++;bytes+=Buffer.byteLength(result);}}finally{sim.close();}}
const receipt={passed:true,native,nativeSha:hash(await readFile(native)),legacy12,legacy3,raw:{files:all.length+3,requests,bytes,wasmPath,sha:hash(wasm)}};
await writeFile(resolve(out,'parity-receipt.json'),JSON.stringify(receipt,null,2));console.log(JSON.stringify(receipt));
