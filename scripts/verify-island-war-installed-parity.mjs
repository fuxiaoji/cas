// Isolated public-protocol native/WASM comparison for the new original island mode.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/island-war-v1/final-installed/new-mode');
const native=process.env.CAS_LITTORAL_NATIVE,wasmPath=process.env.CAS_LITTORAL_WASM;
assert.ok(native&&wasmPath,'Set candidate native and WASM paths');
const hash=b=>createHash('sha256').update(b).digest('hex');
const wasm=await readFile(wasmPath),enc=new TextEncoder(),dec=new TextDecoder();
await mkdir(out,{recursive:true});
const base=JSON.parse(await readFile(resolve(root,'artifacts/island-war-v1/initial-raid.json'),'utf8'));
const catalogue=JSON.parse(await readFile(resolve(root,'godot/data/island-war-v1.json'),'utf8'));
const cases=[];
async function run(name,request,play){
 const p=spawn(native,[],{stdio:['pipe','pipe','inherit']});
 const lines=createInterface({input:p.stdout})[Symbol.asyncIterator]();
 const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports;
 let view,calls=[],bytes=0;
 async function call(q,expect=true){
  calls.push(q);const wire=enc.encode(JSON.stringify(q)),ptr=api.cas_alloc(wire.length)>>>0;
  new Uint8Array(api.memory.buffer,ptr,wire.length).set(wire);
  const response=api.cas_request(ptr,wire.length)>>>0;
  const raw=dec.decode(new Uint8Array(api.memory.buffer,response,api.cas_response_len()>>>0));
  p.stdin.write(JSON.stringify(q)+'\n');const line=await lines.next();assert.equal(line.done,false);
  if(line.value!==raw){await writeFile(resolve(out,name+'-native-mismatch.json'),line.value);await writeFile(resolve(out,name+'-wasm-mismatch.json'),raw);}
  assert.equal(line.value,raw,`${name} #${calls.length} ${q.op}`);
  const result=JSON.parse(raw);assert.equal(result.ok,expect,`${name} ${q.op}: ${result.error??''}`);
  bytes+=Buffer.byteLength(raw);if(result.data?.ships)view=result.data;return result.data;
 }
 try{
  await call(request);await play(call,()=>view);
  const terminal=structuredClone(view),saved=await call({op:'save'});
  await call({op:'load',save:saved});assert.deepEqual(view,terminal);
  for(const tick of [0,Math.min(12,saved.tick),Math.min(25,saved.tick),Math.min(7,saved.tick),saved.tick]) await call({op:'replay',save:saved,tick});
  assert.deepEqual(view,terminal);await call({op:'observe'});assert.deepEqual(view,terminal);
  await writeFile(resolve(out,name+'-commands.json'),JSON.stringify(calls,null,2));
  const row={name,requests:calls.length,bytes,terminal_tick:terminal.tick,success:terminal.result?.success??null,plundered:terminal.island_war.plundered,raw_identical:true};cases.push(row);console.log(JSON.stringify(row));
 }finally{p.stdin.end();}
}
for(const island of catalogue.islands){
 for(const mode of ['raid','defense']){
  const q=structuredClone(base);q.mode=mode;q.island.npc_id=island.id;q.island.island_level=island.level;
  await run(`catalogue-${island.id}-${mode}`,q,async call=>{await call({op:'step',seconds:8});});
 }
}
await run('full-multi-company-raid',structuredClone(base),async(call,get)=>{
 await call({op:'littoral_autonomy',version:'cas-island-war-v1',enabled:true});
 for(let n=0;n<70&&!get().result;n++)await call({op:'step',seconds:10});
 assert.equal(get().result?.success,true);assert.ok(get().result.resources.credits>0);assert.equal(get().result.companies.length,10);
});
const defend=structuredClone(base);defend.mode='defense';
await run('full-garrison-defense',defend,async(call,get)=>{
 await call({op:'littoral_autonomy',version:'cas-island-war-v1',enabled:true});
 for(let n=0;n<60&&!get().result;n++)await call({op:'step',seconds:10});
 assert.equal(get().result?.success,true);assert.equal(get().island_war.remaining_invasion_landings,0);
});
const weak=structuredClone(defend);weak.island.npc_id='old_arsenal';weak.island.island_level=10;
weak.ships=[{id:'CAS-O-APV-TIDEBRIDGE',hp:10,ammo:0}];weak.roster=['MCP-034','MCP-009'];weak.unit_condition=weak.roster.map(id=>({id,hp:10}));
weak.island.forts=[{id:'hq',kind:'hq',level:1,x:.8,y:.5,hp:100},{id:'warehouse',kind:'warehouse',level:1,x:.5,y:.5,hp:100}];weak.island.storage={credits:100,scrap:40,alloy:20,protocols:1};
await run('physical-landing-and-warehouse-loss',weak,async(call,get)=>{
 await call({op:'littoral_autonomy',version:'cas-island-war-v1',enabled:true});
 for(let n=0;n<90&&!get().result;n++)await call({op:'step',seconds:10});
 assert.equal(get().result?.success,false);assert.ok(get().island_war.plundered.credits>0&&get().island_war.plundered.credits<=100);
});
await run('unmooring-and-immediate-manual-takeover',structuredClone(defend),async(call,get)=>{
 await call({op:'littoral_autonomy',version:'cas-island-war-v1',enabled:true});
 const q={op:'littoral_ship_order',ship:1,action:'move',x:10000,y:13000,speed:12};
 await call(q,false);assert.equal(get().littoral.autonomy.enabled,true);
 await call({op:'step',seconds:8});await call(q);assert.equal(get().littoral.autonomy.enabled,false);
 await call({op:'step',seconds:2});await call({op:'littoral_abandon'});assert.equal(get().result.abandoned,true);
});
const receipt={passed:true,native,native_sha256:hash(await readFile(native)),wasm:wasmPath,wasm_sha256:hash(wasm),cases,requests:cases.reduce((s,c)=>s+c.requests,0),bytes:cases.reduce((s,c)=>s+c.bytes,0),scope:'new opt-in island mode; 6 NPCs both sides, real attack/defense/loss, unmooring/manual orders, exact native/WASM every response including save/load/cursor seek and rejected command; no account access'};
await writeFile(resolve(out,'receipt.json'),JSON.stringify(receipt,null,2));console.log(JSON.stringify(receipt));
