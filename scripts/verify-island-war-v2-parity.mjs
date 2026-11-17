// Isolated public-protocol native/WASM comparison for the new original island mode.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/island-war-v2/parity/new-mode');
const native=process.env.CAS_LITTORAL_NATIVE,wasmPath=process.env.CAS_LITTORAL_WASM;
assert.ok(native&&wasmPath,'Set candidate native and WASM paths');
const hash=b=>createHash('sha256').update(b).digest('hex');
const wasm=await readFile(wasmPath),enc=new TextEncoder(),dec=new TextDecoder();
await mkdir(out,{recursive:true});
const base=JSON.parse(await readFile(resolve(root,'artifacts/island-war-v1/initial-raid.json'),'utf8'));
base.version='cas-island-war-v2';
const catalogue=JSON.parse(await readFile(resolve(root,'godot/data/island-war-v2.json'),'utf8'));
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
  await writeFile(resolve(root,'artifacts/island-war-v2/core',name+'.json'),JSON.stringify({initial_request:request,snapshot:saved,serialized:JSON.stringify(saved),final:terminal},null,2));
  const row={name,requests:calls.length,bytes,terminal_tick:terminal.tick,success:terminal.result?.success??null,plundered:terminal.island_war.plundered,raw_identical:true};cases.push(row);console.log(JSON.stringify(row));
 }finally{p.stdin.end();}
}

for(const island of catalogue.islands){for(const mode of ['raid','defense']){
 const q=structuredClone(base);q.mode=mode;q.island.npc_id=island.id;q.island.island_level=island.level;
 await run(`catalogue-${island.id}-${mode}`,q,async call=>{await call({op:'step',seconds:8});});
}}
const auto={op:'island_autonomy',version:'cas-island-war-v2',enabled:true};
const play=async(call,get)=>{await call(auto);for(let n=0;n<120&&!get().result;n++)await call({op:'step',seconds:10});assert.ok(get().result,'terminal required');};
const exercise=structuredClone(base);exercise.mode='exercise';exercise.island.npc_id='';exercise.roster=['MCP-088','MCP-006','MCP-034'];exercise.defender={ships:[{id:'CAS-O-APV-TIDEBRIDGE',hp:25,ammo:30}],roster:['MCP-034'],unit_condition:[{id:'MCP-034',hp:30}]};
await run('exercise-terminal',exercise,async(call,get)=>{await play(call,get);assert.equal(get().result.success,true);assert.equal(get().result.settle_allowed,false);assert.equal(get().result.resources.credits,0);});
const raid=structuredClone(base);raid.roster=['MCP-088','MCP-006','MCP-034'];
await run('raid-terminal',raid,async(call,get)=>{await play(call,get);assert.equal(get().result.success,true);assert.ok(get().result.resources.credits>0);});
const defense=structuredClone(base);defense.mode='defense';defense.roster=['MCP-088','MCP-006','MCP-034'];
await run('defense-terminal',defense,async(call,get)=>{await play(call,get);assert.equal(get().result.success,true);});
const weak=structuredClone(defense);weak.island.npc_id='old_arsenal';weak.island.island_level=10;weak.ships=[{id:'CAS-O-APV-TIDEBRIDGE',hp:10,ammo:0}];weak.roster=['MCP-034'];weak.unit_condition=[{id:'MCP-034',hp:10}];weak.island.forts=[{id:'hq',kind:'hq',level:1,x:.8,y:.5,hp:100},{id:'warehouse',kind:'warehouse',level:1,x:.5,y:.5,hp:100}];weak.island.storage={credits:100,scrap:40,alloy:20,protocols:1};
await run('defense-loss-terminal',weak,async(call,get)=>{await play(call,get);assert.equal(get().result.success,false);assert.ok(get().island_war.plundered.credits<=100);});
await run('manual-takeover-rejected-order',structuredClone(defense),async(call,get)=>{
 await call(auto);await call({op:'littoral_order',group:'missing',action:'move',x:0,y:0},false);assert.equal(get().littoral.autonomy.enabled,true);
 await call({op:'step',seconds:8});await call({op:'littoral_ship_order',ship:1,action:'move',x:10000,y:13000,speed:12});assert.equal(get().littoral.autonomy.enabled,false);await call({op:'littoral_abandon'});
});
const dense=structuredClone(defense);dense.roster=['MCP-034','MCP-011','MCP-167','MCP-116','MCP-088'];dense.ships=[{id:'CAS-H-USN-ENTERPRISE-1942',hp:100,ammo:100},{id:'CAS-O-APV-TIDEBRIDGE',hp:100,ammo:100},{id:'CAS-O-LHA-RETURNLIGHT',hp:100,ammo:100}];
await run('dense-garrison',dense,async(call,get)=>{
 const e=get().littoral.land.entities.filter(e=>e.side==='allies'&&e.hp>0);assert.equal(e.length,199);
 for(let i=0;i<e.length;i++)for(let j=i+1;j<e.length;j++)assert.ok(Math.hypot(e[i].x-e[j].x,e[i].y-e[j].y)>=e[i].collision_radius_m+e[j].collision_radius_m);
 await call({op:'step',seconds:2});
});
const plunder=JSON.parse(await readFile(resolve(root,'artifacts/island-war-v2/core/defense-positive-plunder-trial.json'),'utf8')).initial_request;
await run('defense-positive-plunder-terminal',plunder,async(call,get)=>{await play(call,get);assert.equal(get().result.success,false);assert.ok(get().island_war.plundered.credits>0&&get().island_war.plundered.credits<=100);});
const amphib=structuredClone(exercise);amphib.roster=['MCP-103','MCP-006','MCP-034'];
await run('amphibious-insertion-return-terminal',amphib,async(call,get)=>{await play(call,get);assert.equal(get().result.success,true);assert.ok(get().result.companies.filter(c=>c.unit_id==='MCP-103').every(c=>c.recovered));});
const receipt={passed:true,native,native_sha256:hash(await readFile(native)),wasm:wasmPath,wasm_sha256:hash(wasm),cases,requests:cases.reduce((s,c)=>s+c.requests,0),bytes:cases.reduce((s,c)=>s+c.bytes,0),scope:'explicit v2: all six NPCs/attack-defense, real successful raid/defense/exercise, real loss, manual takeover/rejected commands, dense physical garrison; every response raw compared including terminal save/load and cursor rewind/forward, no account access'};
await writeFile(resolve(out,'receipt.json'),JSON.stringify(receipt,null,2));console.log(JSON.stringify(receipt));
