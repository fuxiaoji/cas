import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/extraction-stall-20261113');await mkdir(out,{recursive:true});
const native=process.env.CAS_STALL_NATIVE||resolve(root,'target/extraction-stall-build/release/cas-sim.exe');
const actualRaw=JSON.parse(await readFile(resolve(out,'actual-account-before.json'),'utf8')).active_run.snapshot,actual=JSON.parse(actualRaw);
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a.localeCompare(b,'en'))):x);
class Sim{
 constructor(){this.child=spawn(native,[],{stdio:['pipe','pipe','inherit']});this.pending=[];this.requests=[];this.totalMs=0;this.maxMs=0;this.slowRequests=0;this.timings={};createInterface({input:this.child.stdout}).on('line',line=>this.pending.shift()(JSON.parse(line)));}
 async ask(q){const start=performance.now();this.requests.push(q);const r=await new Promise(done=>{this.pending.push(done);this.child.stdin.write(JSON.stringify(q)+'\n');});const ms=performance.now()-start;this.totalMs+=ms;this.maxMs=Math.max(this.maxMs,ms);this.slowRequests+=ms>1000?1:0;const t=this.timings[q.op]||={count:0,totalMs:0,maxMs:0};t.count++;t.totalMs+=ms;t.maxMs=Math.max(t.maxMs,ms);assert.equal(r.ok,true,JSON.stringify(r));return r.data;}
 close(){this.child.stdin.end();}
}
const results=[];
async function voyage(name,initial,expectCargo=true,expectedExtracted=true,maxSteps=1500){
 if(process.env.CAS_STALL_CASE&&!name.includes(process.env.CAS_STALL_CASE))return;
 const sim=new Sim();const trace=[];let phase='',v,searched=false,placed=false,restored=false,taskCompleted=false;const groupSearches={};let minSpread=Infinity,initialSpread=0;
 try{
  v=await sim.ask(initial);const initialShips=v.ships.length;const originalFleets=v.fleets.filter(f=>!f.name.includes(' · 独立'));for(const f of originalFleets){const ms=v.ships.filter(s=>s.fleet===f.id);initialSpread=Math.max(initialSpread,...ms.map(s=>Math.hypot(s.x-ms[0].x,s.y-ms[0].y)));}v=await sim.ask({op:'extraction_autopilot',enabled:true,policy:'balanced',version:'cas-extraction-pilot-v3'});
  for(let i=0;i<maxSteps&&!v.result;i++){
   v=await sim.ask({op:'step',seconds:1});const s=v.salvage,a=s.expedition.autopilot;
   searched||=!!s.search||s.cargo_grid.items.length>0;placed||=s.cargo_grid.items.some(i=>i.placement);taskCompleted||=s.expedition.tasks.some(t=>t.status==='complete');
   for(const row of a.fleet_targets||[])if(row.phase==='search'&&s.search?.ruin===row.ruin){const r=s.ruins.find(r=>r.id===row.ruin),p=r?.p||r;if(p&&v.ships.some(ship=>ship.fleet===row.fleet&&ship.speed<=8&&Math.hypot(ship.x-p.x,ship.y-p.y)<750)){groupSearches[row.fleet]||=[];if(!groupSearches[row.fleet].includes(row.ruin))groupSearches[row.fleet].push(row.ruin);}}
   if(a.phase==='extract'||a.phase==='extract_wait')for(const f of v.fleets.filter(f=>f.members.length>1)){const ms=v.ships.filter(s=>s.fleet===f.id);minSpread=Math.min(minSpread,Math.max(...ms.map(s=>Math.hypot(s.x-ms[0].x,s.y-ms[0].y))));}
   if(a.phase!==phase||i%30===0){phase=a.phase;trace.push({tick:v.tick,pilot:a,search:s.search,cargo:s.cargo_grid.items.map(i=>({id:i.id,placement:i.placement})),ships:v.ships.map(s=>({id:s.id,fleet:s.fleet,x:s.x,y:s.y,hp:s.hp,speed:s.speed})),tasks:s.expedition.tasks.map(t=>({id:t.id,status:t.status,progress:t.progress}))});}
   if(i%30===0)await writeFile(resolve(out,'live-native-progress.json'),JSON.stringify({name,tick:v.tick,pilot:a,ships:v.ships.map(s=>({id:s.id,fleet:s.fleet,x:s.x,y:s.y,hp:s.hp,speed:s.speed,rudderJam:s.rudderJam})),fleets:v.fleets,completed:s.cargo_grid.completed,groupSearches},null,2));
   if(!restored&&placed&&a.phase==='extract'&&i>10){const save=await sim.ask({op:'save'});assert.equal(canonical(await sim.ask({op:'load',save})),canonical(v),name+' load');assert.equal(canonical(await sim.ask({op:'replay',save})),canonical(v),name+' replay');restored=true;}
  }
  const summary={name,tick:v.tick,expected_extracted:expectedExtracted,extracted:v.salvage.extracted,result:v.result,searched,placed,taskCompleted,restored,cargo:v.salvage.cargo_grid.items.filter(i=>i.placement).length,completed:v.salvage.cargo_grid.completed,groupSearches,originalFleets:originalFleets.map(f=>f.id),initialSpread,minSpread:Number.isFinite(minSpread)?minSpread:null,alive:v.ships.length,initialShips,requestTimeMs:Math.round(sim.totalMs),maxRequestMs:Math.round(sim.maxMs),requestsOver1s:sim.slowRequests,timings:structuredClone(sim.timings),pilot:v.salvage.expedition.autopilot};
  await writeFile(resolve(out,name+'-commands.json'),JSON.stringify(sim.requests,null,2));await writeFile(resolve(out,name+'-native.json'),JSON.stringify({summary,trace,terminal:v},null,2));
  console.log(JSON.stringify(summary));results.push(summary);
  assert.ok(summary.result,name+' actual terminal');assert.equal(summary.extracted,expectedExtracted,name+' actual extraction');if(expectedExtracted)assert.equal(summary.alive,initialShips,name+' every deployed ship alive');if(expectCargo)assert.ok(searched&&placed&&summary.cargo>0,name+' actual search/load');
  if(name==='v3-actual-five-fresh')assert.ok(summary.completed.length>=2,name+' multiple actual completed searches');
  if(name.includes('multifleet')||name.includes('three-fleets'))for(const fleet of summary.originalFleets)assert.ok((groupSearches[fleet]||[]).some(r=>summary.completed.includes(r)),name+' fleet '+fleet+' actual search');
  const save=await sim.ask({op:'save'});assert.equal(canonical(await sim.ask({op:'load',save})),canonical(v),name+' final load');assert.equal(canonical(await sim.ask({op:'replay',save})),canonical(v),name+' final replay');
  await writeFile(resolve(out,name+'-commands.json'),JSON.stringify(sim.requests,null,2));
 }finally{sim.close();}
}
function config(seed,environment='drowned_city',scene='sunken_metropolis',risk='calm',groups=null){const start=structuredClone(actual.salvage);start.cargo_v4.environment=environment;start.cargo_v4.difficulty=risk;start.expedition_v2.scene=scene;start.mission.id=risk;if(groups)start.groups=groups;return{op:'new_salvage',seed,start};}
try{
 await voyage('v3-actual-save-resume',{op:'load',serialized:actualRaw});
 await voyage('v3-actual-five-fresh',config(actual.seed));
 await voyage('v3-five-fjord-6106',config(6106,'fjord','thermal_vent'));
 await voyage('v3-five-standard-43',config(43,'atoll','cult_relay','standard'));
 const ids=actual.salvage.fleet.map(h=>h.id);await voyage('v3-five-multifleet-40',config(40,'atoll','sunken_metropolis','calm',[{id:'g1',name:'主力',ships:ids.slice(0,2)},{id:'g2',name:'巡洋',ships:ids.slice(2)}]));
 await voyage('v3-five-three-fleets-40',config(40,'atoll','sunken_metropolis','calm',[{id:'g1',name:'主力',ships:ids.slice(0,2)},{id:'g2',name:'巡洋',ships:ids.slice(2,4)},{id:'g3',name:'游击',ships:ids.slice(4)}]));
 const dd=JSON.parse(await readFile(resolve(root,'scripts/fixtures/extraction-default-player-start.json'),'utf8'));await voyage('v3-default-three-dd-42',{op:'new_salvage',seed:42,start:dd});
 const injured=config(45);injured.start.fleet.forEach(h=>h.hp=30);await voyage('v3-five-low-hp-45',injured,false);
 const low=config(46);low.start.fleet.forEach(h=>h.ammo=20);await voyage('v3-five-low-ammo-46',low,false);
 const fuel=config(40);fuel.start.fuel_v1.initial=180;await voyage('v3-five-low-fuel-40',fuel,false);
 const empty=config(40);empty.start.fuel_v1.initial=1;await voyage('v3-five-exhausted-fuel-40',empty,false,false,4000);
 await writeFile(resolve(out,'native-v3-receipt.json'),JSON.stringify({native,sha256:createHash('sha256').update(await readFile(native)).digest('hex'),results},null,2));
}catch(e){await writeFile(resolve(out,'native-v3-failure.json'),JSON.stringify({message:e.message,stack:e.stack,results},null,2));throw e;}
