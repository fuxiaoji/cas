import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/littoral-core');await mkdir(out,{recursive:true});
const exe=process.env.CAS_LITTORAL_NATIVE||resolve(root,'target/littoral-build/release/cas-sim.exe');
const dt=Number(process.env.CAS_LITTORAL_DT||.5),suffix=dt===.1?'-hz10':'';
const ids=['MCP-001','MCP-034','MCP-076','MCP-009','MCP-022'];
const shipIds=['IBS-U-USN-ERMA-IOWA','IBS-U-USN-ERMA-DES-MOINES','IBS-U-USN-FLETCHER'];
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a.localeCompare(b,'en'))):x);
const dist=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y);
class Sim{constructor(){this.p=spawn(exe,[],{stdio:['pipe','pipe','inherit']});this.lines=createInterface({input:this.p.stdout})[Symbol.asyncIterator]();this.commands=[];this.timings={};}async ask(q,expected=true){this.commands.push(q);const start=performance.now();this.p.stdin.write(JSON.stringify(q)+'\n');const row=await this.lines.next();assert.equal(row.done,false);const r=JSON.parse(row.value);(this.timings[q.op]||=[]).push(performance.now()-start);if(expected!==null)assert.equal(r.ok,expected,JSON.stringify(r));return r.ok?r.data:{error:r.error};}close(){this.p.stdin.end();}}
function stats(a){a=[...a].sort((x,y)=>x-y);return{count:a.length,p50:a[Math.floor(a.length*.5)],p95:a[Math.floor(a.length*.95)],max:a.at(-1),total:a.reduce((s,x)=>s+x,0)};}
function request(mode,seed,all=true,preset=all?'transport':'balanced',condition=100){const roster=all?ids:['MCP-034'];return{op:'new_littoral',version:'cas-littoral-v1',seed,mode,ships:(all?shipIds:['IBS-U-USN-FLETCHER']).map(id=>({id,hp:condition,ammo:100})),roster,unit_condition:roster.map(id=>({id,hp:condition})),transport_preset:preset,defense:[]};}
const summaries=[];
async function run(mode,seed,all=true,abandon=false,av=false){const name=`littoral-${mode}-${seed}${abandon?'-abandon':''}${av?'-av-transport':''}${suffix}`;if(process.env.CAS_LITTORAL_CASE&&!name.includes(process.env.CAS_LITTORAL_CASE))return;const sim=new Sim(),trace=[],firing=new Set(),bodyCards=new Set(),sources=new Set();let v,restored=false,stage='sail',sent=new Set(),peaks={bodies:0,projectiles:0,transports:0},firstGround;
 try{
  const q=request(mode,seed,all);if(av){q.ships=['IBS-U-IJN-NISSHIN','IBS-U-USN-ERMA-IOWA'].map(id=>({id,hp:100,ammo:100}));q.transport_preset='combat';}v=await sim.ask(q);
  if(av){assert.equal(v.ships[0].transport_role,'transport_support');assert.equal(v.ships[0].transport_slots,16);assert.ok(v.littoral.groups.every(g=>g.carrier===1),'all five cards physically loaded on actual Nisshin');}
  if(mode!=='defense')v=await sim.ask({op:'route',fleet:1,speed:30,points:[v.littoral.beaches[1].sea]});
  for(let guard=0;guard<Math.ceil(600/dt)&&!v.result;guard++){
   for(const b of v.littoral.land.entities)if(b.side==='allies')bodyCards.add(b.unit_id);
   for(const s of v.littoral.shots){sources.add(s.source);if(String(s.source).startsWith('body:')){const b=v.littoral.land.entities.find(b=>'body:'+b.id===s.source);if(b?.side==='allies')firing.add(b.unit_id);}}
   peaks.bodies=Math.max(peaks.bodies,v.littoral.land.entities.length);peaks.projectiles=Math.max(peaks.projectiles,v.shells.length);peaks.transports=Math.max(peaks.transports,v.littoral.transports.length);
   if(abandon&&v.tick>=45){v=await sim.ask({op:'littoral_abandon'});break;}
   if(mode!=='defense'){
    if(stage==='sail'&&v.ships.every(s=>dist(s,v.littoral.beaches[1].sea)<850)){v=await sim.ask({op:'speed',fleet:1,speed:0});stage=av?'bombard':'land';if(!av)for(const g of v.littoral.groups)v=await sim.ask({op:'littoral_deploy',unit_id:g.id,beach:2,insertion:['MCP-001','MCP-076'].includes(g.id)?'air':'landing'});}
    if(['bombard','land','battle'].includes(stage)){
     // Use real naval artillery to neutralize the public AA emplacement before
     // sending vulnerable air elements into its envelope. Failed legal requests
     // are retained in the fixture rather than being silently rewritten.
     const aa=v.littoral.land.buildings.find(b=>b.kind==='aa'&&b.hp>0);
     if(aa&&all)for(const support of v.littoral.support.naval){if(support.alive&&!support.anchored&&support.ammo>0&&support.ready_in===0){const ship=v.ships.find(s=>s.id===support.ship);if(!ship)continue;const heading=(Math.atan2(aa.x-ship.x,aa.y-ship.y)*180/Math.PI+90+360)%360;v=await sim.ask({op:'littoral_ship_order',ship:ship.id,action:'face',heading});const res=await sim.ask({op:'littoral_support',kind:'naval',ship:ship.id,x:aa.x,y:aa.y},null);if(!res.error)v=res;}}
     if(stage==='bombard'&&!aa){for(const g of v.littoral.groups)v=await sim.ask({op:'littoral_deploy',unit_id:g.id,beach:2,insertion:['MCP-001','MCP-076'].includes(g.id)?'air':'landing'});stage='land';}
     const groups=v.littoral.groups.filter(g=>g.stage==='ground');if(groups.length)firstGround??=v.tick;
     if(stage==='land'&&v.littoral.groups.every(g=>['ground','lost'].includes(g.stage))){
      if(all&&mode==='raid'){v=await sim.ask({op:'littoral_order',unit_id:'MCP-009',action:'move',x:12800,y:8500});stage='engineer';}
      else {for(const g of groups)v=await sim.ask({op:'littoral_order',unit_id:g.id,action:'search',target:1});stage='battle';}
     }
    }
    if(stage==='engineer'){
     const g=v.littoral.groups.find(g=>g.id==='MCP-009');if(g.stage==='lost'||dist(g.position,{x:12800,y:8500})<100){const hq=v.littoral.land.buildings.find(b=>b.kind==='hq');for(const unit of v.littoral.groups.filter(g=>g.stage==='ground'))v=await sim.ask(unit.id==='MCP-009'?{op:'littoral_order',unit_id:unit.id,action:'search',target:1}:{op:'littoral_order',unit_id:unit.id,action:'attack',x:hq.x,y:hq.y});stage='battle';}
    }
    if(stage==='battle'&&mode==='raid'){
     const eng=v.littoral.groups.find(g=>g.id==='MCP-009');if(eng?.stage==='ground'&&v.littoral.land.ruins[0].searched&&!sent.has('eng-hq')){sent.add('eng-hq');const hq=v.littoral.land.buildings.find(b=>b.kind==='hq');v=await sim.ask({op:'littoral_order',unit_id:eng.id,action:'attack',x:hq.x,y:hq.y});}
    }
    if(v.littoral.objectives[0].complete&&['battle','engineer'].includes(stage)){for(const g of v.littoral.groups.filter(g=>g.stage==='ground'))v=await sim.ask({op:'littoral_order',unit_id:g.id,action:'retreat'});stage='return';}
    if(stage==='return'&&v.littoral.groups.every(g=>['recovered','embarked','lost'].includes(g.stage))){v=await sim.ask({op:'route',fleet:1,speed:30,points:[{x:5500,y:13500}]});stage='exit';}
    if(stage==='exit'&&v.ships.filter(s=>s.hp>0).every(s=>dist(s,v.littoral.exit)<1500)){v=await sim.ask({op:'littoral_extract'});break;}
   }
   v=await sim.ask({op:'step',seconds:dt});
   if(Math.round(v.tick*10)%100===0||v.result)trace.push({tick:v.tick,stage,groups:v.littoral.groups.map(g=>({id:g.id,stage:g.stage,hp:g.hp_percent,order:g.order,x:g.position.x,y:g.position.y})),ships:v.ships.map(s=>({id:s.id,hp:s.hp,ammo:s.ammo,x:s.x,y:s.y})),objective:v.littoral.objectives[0],enemies:v.littoral.land.entities.filter(b=>b.side==='axis').length});
   if(!restored&&v.tick>=100){const saved=await sim.ask({op:'save'});assert.equal(canonical(await sim.ask({op:'load',save:saved})),canonical(v),'mid-load');assert.equal(canonical(await sim.ask({op:'replay',save:saved})),canonical(v),'mid-replay');restored=true;}
  }
  const saved=await sim.ask({op:'save'});assert.equal(canonical(await sim.ask({op:'load',save:saved})),canonical(v),'end-load');assert.equal(canonical(await sim.ask({op:'replay',save:saved})),canonical(v),'end-replay');
  const summary={name,mode,seed,binary:exe,tick:v.tick,firstGround,expected_success:!abandon,result:v.littoral.outcome,bodyCards:[...bodyCards],firingCards:[...firing],sources:[...sources],peaks,restored,timings:Object.fromEntries(Object.entries(sim.timings).map(([op,a])=>[op,stats(a)])),saveBytes:JSON.stringify(saved).length};summaries.push(summary);await writeFile(resolve(out,name+'-commands.json'),JSON.stringify(sim.commands,null,2));await writeFile(resolve(out,name+'-native.json'),JSON.stringify({summary,trace,terminal:v},null,2));console.log(JSON.stringify({name,tick:v.tick,result:v.littoral.outcome,bodyCards:summary.bodyCards,firing:summary.firingCards,peaks,step:summary.timings.step}));
  assert.ok(v.result,'genuine terminal');assert.equal(v.littoral.outcome.success,!abandon,'genuine mission outcome');assert.ok(peaks.bodies<=96&&peaks.projectiles<=256&&peaks.transports<=5,'bounded entities');if(abandon)assert.deepEqual(v.littoral.outcome.resources,{scrap:0,alloy:0,protocols:0,credits:0});else if(all)assert.equal(bodyCards.size,5,'all five real cards deployed');
 }finally{sim.close();}
}
try{await run('tutorial',42,false);await run('raid',42);await run('salvage',43);await run('defense',44);await run('raid',45,true,true);await run('raid',46,true,false,true);await writeFile(resolve(out,`native${suffix}-receipt.json`),JSON.stringify({passed:true,binary:exe,sha256:createHash('sha256').update(await readFile(exe)).digest('hex'),summaries},null,2));}catch(error){await writeFile(resolve(out,`native${suffix}-failure.json`),JSON.stringify({message:error.message,stack:error.stack,summaries},null,2));throw error;}
