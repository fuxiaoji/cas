// New v3 core audit: every native/WASM public response is compared as raw UTF-8.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir} from 'node:fs/promises';import {resolve} from 'node:path';import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/island-war-v3/parity/new-mode');await mkdir(out,{recursive:true});
const native=process.env.CAS_LITTORAL_NATIVE,wasmPath=process.env.CAS_LITTORAL_WASM;assert.ok(native&&wasmPath);
const wasm=await readFile(wasmPath),hash=b=>createHash('sha256').update(b).digest('hex'),enc=new TextEncoder(),dec=new TextDecoder(),cases=[];
// Resume only already compared whole cases from this exact pair of binaries.
// The checkpoint also binds the complete request streams, so a changed fixture
// cannot silently reuse an earlier success.
let resumedFrom=null;
if(process.env.CAS_V3_PARITY_RESUME){const path=resolve(process.env.CAS_V3_PARITY_RESUME),checkpoint=JSON.parse(await readFile(path,'utf8'));assert.equal(checkpoint.native_sha256,hash(await readFile(native)));assert.equal(checkpoint.wasm_sha256,hash(wasm));for(const row of checkpoint.cases){assert.equal(hash(await readFile(resolve(out,row.name+'-commands.json'))),checkpoint.command_sha256[row.name]);cases.push(row);}resumedFrom={path,sha256:hash(await readFile(path))};}
async function run(name,commands,options={}){
 const p=spawn(native,[],{stdio:['pipe','pipe','inherit']}),lines=createInterface({input:p.stdout})[Symbol.asyncIterator]();
 const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports;let calls=[],bytes=0,view;
 async function call(q){calls.push(q);const text=JSON.stringify(q);p.stdin.write(text+'\n');const wire=enc.encode(text),ptr=api.cas_alloc(wire.length)>>>0;new Uint8Array(api.memory.buffer,ptr,wire.length).set(wire);const r=api.cas_request(ptr,wire.length)>>>0;const raw=dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0));const line=await lines.next();assert.equal(line.done,false);if(line.value!==raw){await writeFile(resolve(out,name+'-native-mismatch.json'),line.value);await writeFile(resolve(out,name+'-wasm-mismatch.json'),raw);}assert.equal(line.value,raw,`${name} #${calls.length} ${q.op}`);bytes+=Buffer.byteLength(raw);const result=JSON.parse(raw);if(result.ok&&result.data?.ships)view=result.data;return result;}
 try{
  if(name==='training-landing')assert.equal((await call({op:'island_war_catalogue',version:'cas-island-war-v3'})).ok,true);
  for(const q of commands)await call(q);
  if(options.autoplay){assert.equal((await call({op:'island_autonomy',enabled:true})).ok,true);for(let n=0;n<120&&!view.result;n++)await call({op:'step',seconds:10});assert.ok(view.result,`${name} actual terminal required`);}
  if(options.training){assert.equal(view.result?.success,true);assert.equal(view.littoral.training.complete,true);assert.equal(view.result.resources.credits,0);assert.equal(view.result.settle_allowed,false);}
  const terminal=structuredClone(view),saved=(await call({op:'save'})).data;
  assert.equal((await call({op:'load',save:saved})).ok,true);assert.deepEqual(view,terminal);
  for(const tick of [0,Math.min(12,saved.tick),Math.min(25,saved.tick),Math.min(7,saved.tick),saved.tick])assert.equal((await call({op:'replay',save:saved,tick})).ok,true);
  assert.deepEqual(view,terminal);await call({op:'observe'});assert.deepEqual(view,terminal);
  await writeFile(resolve(out,name+'-commands.json'),JSON.stringify(calls,null,2));
  const row={name,requests:calls.length,bytes,terminal_tick:view.tick,success:view.result?.success??null,training_complete:view.littoral.training?.complete??null,raw_identical:true};cases.push(row);console.log(JSON.stringify(row));
 }finally{p.stdin.end();}
}
for(const lesson of ['landing','weapons','artillery','airborne','roles','combined_arms']){if(cases.some(c=>c.name==='training-'+lesson))continue;const data=JSON.parse(await readFile(resolve(root,`artifacts/island-war-v3/core/training-${lesson}-terminal.json`),'utf8'));await run('training-'+lesson,data.commands,{training:true});}
for(const kind of ['tank','ifv']){const data=JSON.parse(await readFile(resolve(root,`artifacts/island-war-v3/core/actual-${kind}-rear-cover.json`),'utf8'));const id=data.evidence.vehicle_id;await run('physical-'+kind+'-cover',[{op:'load',save:JSON.parse(data.serialized)},{op:'littoral_vehicle_preview',vehicle_id:id,action:'embark'},{op:'littoral_ability_preview',company_id:data.evidence.company_id,x:data.evidence.vehicle_position.x,y:data.evidence.vehicle_position.y}]);}
const base=JSON.parse(await readFile(resolve(root,'artifacts/island-war-v1/initial-raid.json'),'utf8'));base.version='cas-island-war-v3';
const catalogue=JSON.parse(await readFile(resolve(root,'godot/data/island-war-v3.json'),'utf8'));
for(const island of catalogue.islands)for(const mode of ['raid','defense']){const q=structuredClone(base);q.mode=mode;q.island.npc_id=island.id;q.island.island_level=island.level;await run(`catalogue-${island.id}-${mode}`,[q,{op:'step',seconds:8}]);}
for(const mode of ['raid','defense']){const q=structuredClone(base);q.mode=mode;q.roster=['MCP-088','MCP-006','MCP-034'];await run(mode+'-terminal',[q],{autoplay:true});}
const weak=JSON.parse(await readFile(resolve(root,'artifacts/island-war-v2/core/defense-positive-plunder-trial.json'),'utf8')).initial_request;weak.version='cas-island-war-v3';await run('defense-positive-loss',[weak],{autoplay:true});
await run('manual-rejection-and-takeover',[base,{op:'island_autonomy',enabled:true},{op:'littoral_order',group:'missing',action:'move',x:0,y:0},{op:'step',seconds:8},{op:'littoral_ship_order',ship:1,action:'move',x:10000,y:13000,speed:12},{op:'littoral_abandon'}]);
const receipt={passed:true,native,native_sha256:hash(await readFile(native)),wasm:wasmPath,wasm_sha256:hash(wasm),resumed_from:resumedFrom,cases,requests:cases.reduce((s,c)=>s+c.requests,0),bytes:cases.reduce((s,c)=>s+c.bytes,0),scope:'v3 six actual successful borrowed training lessons with all real checks; two genuine tank/IFV rear-cover arrivals and readonly vehicle/ability previews; six NPC raid/defense; actual raid/defense/loss terminals; rejected commands/manual takeover; every raw response including save/load and forward/back replay; no account access'};
await writeFile(resolve(out,'receipt.json'),JSON.stringify(receipt,null,2));console.log(JSON.stringify(receipt));
