import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir,readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/littoral-v4/multi');await mkdir(out,{recursive:true});
const native=process.env.CAS_LITTORAL_NATIVE;assert.ok(native,'set immutable CAS_LITTORAL_NATIVE');
const old=resolve(root,'godot/bin/runtime/db75a0459d23c3c8/cas-sim.exe');
const wasmPath=process.env.CAS_LITTORAL_WASM;
const sha=b=>createHash('sha256').update(b).digest('hex');
class Sim{constructor(exe=native){this.p=spawn(exe,[],{stdio:['pipe','pipe','inherit']});this.lines=createInterface({input:this.p.stdout})[Symbol.asyncIterator]();this.commands=[];this.responses=[];}async raw(q){this.commands.push(q);this.p.stdin.write(JSON.stringify(q)+'\n');let r=await this.lines.next();assert.equal(r.done,false);this.responses.push(r.value);return r.value;}async ask(q,expected=true){const r=JSON.parse(await this.raw(q));if(expected!==null)assert.equal(r.ok,expected,JSON.stringify(r));return r.ok?r.data:r;}close(){this.p.stdin.end();}}
function request(mode,roster,seed=42,lesson='landing'){return{op:'new_littoral',version:'cas-littoral-v4',company_layout:'multi-company-v1',seed,mode,ships:[{id:'CAS-O-LHA-RETURNLIGHT',hp:100,ammo:100},{id:'IBS-U-USN-ERMA-IOWA',hp:100,ammo:100}],roster,unit_condition:roster.map(id=>({id,hp:seed===44?10:100})),transport_preset:'combat',defense:[],...(mode==='tutorial'?{lesson}:{})};}
const reports=[];
async function run(mode,roster,seed=42,success=true,lesson='landing'){let sim=new Sim(),v,stage=mode==='defense'?'defense':mode==='tutorial'&&lesson==='sea_control'?'sea':'land',groundAt=null,selected=new Set(),naval=false,firstSnapshot=false,seen=new Set(),shots=new Set(),bodyIds=new Set(),transportShotIds=new Set(),skills=new Set(),trace=[],peaks={bodies:0,projectiles:0,transports:0};
try{
v=await sim.ask(request(mode,roster,seed,lesson));
if(stage==='defense'){const hq=v.littoral.land.buildings.find(b=>b.kind==='hq');for(const g of v.littoral.groups)v=await sim.ask({op:'littoral_order',company_id:g.id,action:'defend',x:hq.x,y:hq.y});}
if(mode==='salvage'&&roster.length===5)stage='suppression';
if(stage==='land')for(const g of v.littoral.groups){const p=await sim.ask({op:'littoral_preview',kind:'deploy',company_id:g.id,beach:2,insertion:'landing'});assert.equal(p.valid,true);v=await sim.ask({op:'littoral_deploy',company_id:g.id,beach:2,insertion:'landing',queue:true});}
for(let n=0;n<3650&&!v.result;n++){
 if(stage==='suppression'){
   const target=v.littoral.land.buildings.find(b=>b.kind==='aa'&&b.hp>0)||v.littoral.land.buildings.find(b=>b.kind==='turret'&&b.hp>0);
   if(target){for(const s of v.littoral.support.naval)if(s.alive&&s.ammo>0&&!s.pending_target){const r=await sim.ask({op:'littoral_support',kind:'naval',ship:s.ship,x:target.x,y:target.y,queue:true},null);if(r.ok!==false)v=r;}}
   else{for(const g of v.littoral.groups)v=await sim.ask({op:'littoral_deploy',company_id:g.id,beach:2,insertion:'landing',queue:true});stage='land';}
 }

 peaks.bodies=Math.max(peaks.bodies,v.littoral.land.entities.length);peaks.projectiles=Math.max(peaks.projectiles,(v.shells||[]).length);peaks.transports=Math.max(peaks.transports,v.littoral.transports.length);
 for(const b of v.littoral.land.entities)if(b.side==='allies'){seen.add(b.unit_id);bodyIds.add(b.id);}
 // A severely injured body may land and die between two public 0.5s samples.
 // Its authoritative corpse proves actual spawning; no UI-only deployment counts.
 for(const b of v.littoral.corpses)if(b.side==='allies'&&b.kind!=='transport_wreck'){seen.add(b.unit_id);bodyIds.add(b.id);}
 for(const s of v.littoral.shots){if(s.side==='allies'){if(s.source.startsWith('body:')){let b=v.littoral.land.entities.find(b=>'body:'+b.id===s.source);if(b)shots.add(b.unit_id);}if(s.kind==='naval')naval=true;if(s.kind==='transport_gunship')transportShotIds.add(s.id);}}
 if(!firstSnapshot&&v.tick>=1){const s=await sim.ask({op:'save'});assert.deepEqual(await sim.ask({op:'load',save:s}),v);assert.deepEqual(await sim.ask({op:'replay',save:s}),v);firstSnapshot=true;}
 const groups=v.littoral.groups.filter(g=>g.stage==='ground');if(groups.length)groundAt??=v.tick;
 if(stage==='land'&&v.littoral.groups.every(g=>['ground','lost'].includes(g.stage))){for(const g of groups)v=await sim.ask({op:'littoral_order',company_id:g.id,action:'search',target:1});stage='battle';}
 if(['battle','defense'].includes(stage)){
   // Ground salvo at a public AA location; an actual queued shot must appear.
   const target=v.littoral.land.buildings.find(b=>b.kind==='aa'&&b.hp>0)||v.littoral.land.ruins[0];
   for(const s of v.littoral.support.naval){if(!selected.has(s.ship)&&s.alive&&s.ammo>=3){let r=await sim.ask({op:'littoral_ship_order',ship:s.ship,action:'aim_land',x:target.x,y:target.y},null);if(r.ok===false)continue;v=r;r=await sim.ask({op:'littoral_support',kind:'naval',ship:s.ship,x:target.x,y:target.y,queue:true},null);if(r.ok!==false){v=r;selected.add(s.ship);}}}
   for(const g of groups){if(!skills.has(g.id)&&g.ability?.available){const p=g.ability.range>0?{x:g.position.x,y:g.position.y-250}:{};const r=await sim.ask({op:'littoral_ability',company_id:g.id,...p},null);if(r.ok!==false){v=r;skills.add(g.id);}}}
 }
 if(stage==='battle'&&mode==='raid'&&v.littoral.land.ruins[0].searched){const hq=v.littoral.land.buildings.find(b=>b.kind==='hq');for(const g of groups)if(g.order!=='attack')v=await sim.ask({op:'littoral_order',company_id:g.id,action:'attack',x:hq.x,y:hq.y});}
 if(v.littoral.objectives[0].complete&&['battle','sea'].includes(stage)){for(const g of groups)v=await sim.ask({op:'littoral_order',company_id:g.id,action:'retreat'});stage='return';}
 if(stage==='return'&&v.littoral.groups.every(g=>['embarked','recovered','lost'].includes(g.stage))){for(const s of v.ships.filter(s=>s.hp>0&&Math.hypot(s.x-v.littoral.exit.x,s.y-v.littoral.exit.y)>1500))v=await sim.ask({op:'littoral_ship_order',ship:s.id,action:'move',x:v.littoral.exit.x+(s.id-1)*120,y:v.littoral.exit.y});stage='exit';}
 if(stage==='exit'&&v.ships.filter(s=>s.hp>0).every(s=>Math.hypot(s.x-v.littoral.exit.x,s.y-v.littoral.exit.y)<1500)){v=await sim.ask({op:'littoral_extract'});break;}
 v=await sim.ask({op:'step',seconds:.5});
 if(Math.round(v.tick*10)%100===0)trace.push({tick:v.tick,stage,groups:v.littoral.groups.map(g=>({id:g.id,stage:g.stage,hp:g.hp_percent,order:g.order})),ships:v.ships.map(s=>({id:s.id,hp:s.hp,ammo:s.ammo,x:s.x,y:s.y})),objective:v.littoral.objectives[0]});
}
await writeFile(resolve(out,`last-${mode}-${seed}.json`),JSON.stringify(v));assert.ok(v.result,'real terminal');assert.equal(v.littoral.outcome.success,success,JSON.stringify({mode,roster,trace:trace.slice(-4),outcome:v.littoral.outcome}));
assert.equal(seen.size,lesson==='sea_control'&&mode==='tutorial'?0:roster.length,'every selected tactical identity actually deployed');assert.ok(peaks.bodies<=320&&peaks.projectiles<=512&&peaks.transports<=25,'bounded physical simulation');if(mode==='tutorial'&&lesson!=='sea_control')assert.ok(groundAt>0&&groundAt<=45,'first actual landing within tutorial pacing');const saved=await sim.ask({op:'save'});assert.deepEqual(await sim.ask({op:'load',save:saved}),v);assert.deepEqual(await sim.ask({op:'replay',save:saved}),v);
for(const s of v.littoral.outcome.ships)assert.equal(s.loaded_ammo_percent,s.ammo_percent+s.ammo_spent_percent);
const name=`v4-${mode}-${lesson}-${seed}-${roster[0]}`;await writeFile(resolve(out,name+'-commands.json'),JSON.stringify(sim.commands));await writeFile(resolve(out,name+'-native.json'),JSON.stringify({terminal:v,trace},null,2));const report={name,realFriendlyBodyIds:bodyIds.size,transportGunshipShots:transportShotIds.size,tick:v.tick,firstGround:groundAt,seen:[...seen],firing:[...shots],skills:[...skills],naval,peaks,outcome:v.littoral.outcome};reports.push(report);console.log(JSON.stringify(report));
}finally{sim.close();}}
await run('tutorial',['MCP-034','MCP-001'],42,true,'landing');
await run('tutorial',['MCP-034','MCP-001','MCP-022'],43,true,'combined');
await run('salvage',['MCP-034','MCP-009'],44,false);
await run('salvage',['MCP-034','MCP-009','MCP-022','MCP-001','MCP-145'],45,true);
await run('defense',['MCP-034','MCP-116','MCP-167','MCP-011','MCP-103'],46,true);
await writeFile(resolve(out,'native-stage-receipt.json'),JSON.stringify({native,sha:sha(await readFile(native)),reports},null,2));
