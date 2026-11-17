import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..');
const native=process.env.CAS_AI_NATIVE||resolve(root,'target/extraction-ai-build/release/cas-sim.exe');
const out=resolve(root,'artifacts/extraction-autopilot');await mkdir(out,{recursive:true});
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a.localeCompare(b,'en'))):x);
const profile='cas-adventure-v2';
function start(difficulty='calm',environment='atoll',scene='sunken_metropolis',hp=100,ammo=100,multiple=false){return {content:'salvage-v4',gameplay_profile:profile,fleet:[{id:'IBS-U-USN-FLETCHER',hp,ammo,level:0},...(multiple?[{id:'IBS-U-USN-OBANNON',hp:100,ammo:100,level:0}]:[])],mission:{kind:'salvage',id:difficulty,loot_kind:'scrap'},cargo_v4:{commander_level:1,difficulty,environment,weather:'clear',loadouts:{}},expedition_v2:{scene,munitions:{}}};}
class Sim{
 constructor(){this.child=spawn(native,[],{stdio:['pipe','pipe','pipe']});this.pending=[];this.stderr='';this.requests=[];this.child.stderr.on('data',b=>this.stderr+=b);createInterface({input:this.child.stdout}).on('line',line=>{const next=this.pending.shift();if(next)try{next.resolve(JSON.parse(line));}catch(e){next.reject(e);}});this.child.on('exit',code=>{for(const p of this.pending)p.reject(new Error(`native exit ${code}: ${this.stderr}`));});}
 async raw(q){this.requests.push(q);return await new Promise((resolve,reject)=>{this.pending.push({resolve,reject});this.child.stdin.write(JSON.stringify(q)+'\n');});}
 async ask(q){const r=await this.raw(q);assert.equal(r.ok,true,`${JSON.stringify(q)} => ${JSON.stringify(r)}`);return r.data;}
 close(){this.child.stdin.end();}
}
const results=[];
async function voyage(name,seed,config,policy='balanced',expectLoot=true){
 const sim=new Sim(),trace=[];let v;let restored=false,placed=false,searched=false,phase='';try{
  v=await sim.ask({op:'new_salvage',seed,start:config});assert.equal(v.salvage.expedition.autopilot.enabled,false);
  v=await sim.ask({op:'extraction_autopilot',enabled:true,policy});
  for(let i=0;i<900&&!v.result;i++){
   v=await sim.ask({op:'step',seconds:1});const a=v.salvage.expedition.autopilot,g=v.salvage.cargo_grid;
   searched ||= !!v.salvage.search||g.items.length>0;placed ||=g.items.some(it=>it.placement);
   if(a.phase!==phase||i%30===0){phase=a.phase;trace.push({tick:v.tick,phase:a.phase,reason:a.reason,error:a.last_error,ship:v.ships.map(s=>({id:s.id,x:s.x,y:s.y,speed:s.speed,hp:s.hp})),cargo:g.items.filter(it=>it.placement).length,value:a.stowed_value,known:v.salvage.ruins.length});}
   if(!restored&&v.tick>=3&&!v.result){const save=await sim.ask({op:'save'});assert.equal(canonical(await sim.ask({op:'load',save})),canonical(v),name+' load');assert.equal(canonical(await sim.ask({op:'replay',save})),canonical(v),name+' replay');restored=true;}
  }
  const a=v.salvage.expedition.autopilot;
  const summary={name,seed,policy,tick:v.tick,searched,placed,extracted:v.salvage.extracted,result:v.result,commands:a.commands_issued,reason:a.reason,error:a.last_error,restored,cargo:v.salvage.cargo_grid.items.filter(it=>it.placement).map(it=>({id:it.id,value:it.value,placement:it.placement})),trace};
  await writeFile(resolve(out,name+'.json'),JSON.stringify(summary,null,2));await writeFile(resolve(out,name+'-commands.json'),JSON.stringify(sim.requests,null,2));console.log(JSON.stringify({...summary,trace:undefined,cargo:summary.cargo.length}));
  if(process.argv.includes('--probe'))return summary;
  assert.equal(summary.extracted,true,name+' actual extraction');
  if(expectLoot){assert.equal(searched,true,name+' actual search');assert.equal(placed,true,name+' actual stow');assert.ok(summary.cargo.length>0,name+' actual cargo');}
  const save=await sim.ask({op:'save'});assert.equal(canonical(await sim.ask({op:'load',save})),canonical(v),name+' end load');assert.equal(canonical(await sim.ask({op:'replay',save})),canonical(v),name+' end replay');
  assert.ok(save.commands.every(e=>e.request.op==='extraction_autopilot'),name+' internal commands must regenerate and never double-log');
  results.push({...summary,trace:undefined});return summary;
 }finally{sim.close();}
}
async function controls(){
 const sim=new Sim();let checks=0;const check=(ok,message)=>{assert.ok(ok,message);checks++;};try{
  let v=await sim.ask({op:'new_salvage',seed:42,start:start()});
  v=await sim.ask({op:'step',seconds:3});check(!v.salvage.expedition.autopilot.enabled&&v.salvage.expedition.autopilot.commands_issued===0,'default off never issues an automatic command');
  v=await sim.ask({op:'extraction_autopilot',enabled:true,policy:'balanced'});v=await sim.ask({op:'step',seconds:3});check(v.salvage.expedition.autopilot.commands_issued>0,'authorized native auto makes real commands');
  check(!(await sim.raw({op:'speed',fleet:99999,speed:0})).ok,'invalid manual order rejected');
  v=await sim.ask({op:'observe'});check(v.salvage.expedition.autopilot.enabled,'rejected order cannot silently take control');
  v=await sim.ask({op:'speed',fleet:1,speed:0});check(!v.salvage.expedition.autopilot.enabled&&v.salvage.expedition.autopilot.phase==='manual','valid manual control immediately disengages');
  const issued=v.salvage.expedition.autopilot.commands_issued;v=await sim.ask({op:'step',seconds:5});check(v.salvage.expedition.autopilot.commands_issued===issued,'no new automatic commands after takeover');
  const saved=await sim.ask({op:'save'});check(canonical(await sim.ask({op:'load',save:saved}))===canonical(v),'manual takeover saved precisely');check(canonical(await sim.ask({op:'replay',save:saved}))===canonical(v),'manual takeover replayed precisely');
  v=await sim.ask({op:'extraction_autopilot',enabled:true,policy:'bold'});check(v.salvage.expedition.autopilot.policy==='bold','policy explicitly switched');
  v=await sim.ask({op:'extraction_autopilot',enabled:false,policy:'bold'});check(!v.salvage.expedition.autopilot.enabled,'explicit off works immediately');
  const before=canonical(v);check(!(await sim.raw({op:'extraction_autopilot',enabled:true,policy:'hidden-omniscient'})).ok,'invalid policy rejected');check(canonical(await sim.ask({op:'observe'}))===before,'invalid policy is atomic');
  for(const profileName of ['legacy','story']){
   if(profileName==='legacy'){const config=start();delete config.gameplay_profile;delete config.expedition_v2;v=await sim.ask({op:'new_salvage',seed:40,start:config});}
   else v=await sim.ask({op:'new_chapter',id:'c1-breakout',seed:6109,gameplay_profile:'cas-adventure-v1'});
   const original=canonical(v);check(!(await sim.raw({op:'extraction_autopilot',enabled:true,policy:'bold'})).ok,profileName+' cannot start extraction automation');check(canonical(await sim.ask({op:'observe'}))===original,profileName+' remains unchanged after rejection');
  }
  const summary={name:'native-authorization-takeover-and-mode-boundaries',checks,passed:true};results.push(summary);await writeFile(resolve(out,'controls-commands.json'),JSON.stringify(sim.requests,null,2));console.log(JSON.stringify(summary));
 }finally{sim.close();}
}
try{
 await voyage('calm-40',40,start(),'balanced');
 if(!process.argv.includes('--one')){
  await voyage('standard-43',43,start('standard','fractured','cult_relay'),'balanced');
  await voyage('hazard-44',44,start('hazard','drowned_city','storm_wrecks'),'cautious',false);
  await voyage('hazard-balanced-44',44,start('hazard','drowned_city','storm_wrecks'),'balanced');
  await voyage('bold-42',42,start('calm','fractured','cult_relay'),'bold');
  const multi=start('calm','atoll','refugee_causeway',100,100,true);multi.groups=[{id:'g1',name:'前卫',ships:['IBS-U-USN-FLETCHER']},{id:'g2',name:'护航',ships:['IBS-U-USN-OBANNON']}];await voyage('multiple-fleets-40',40,multi,'balanced');
  await voyage('fjord-6106',6106,start('calm','fjord','thermal_vent'),'balanced');
  await voyage('injured-45',45,start('standard','atoll','refugee_causeway',30),'balanced',false);
  await voyage('low-ammo-46',46,start('standard','atoll','cult_relay',100,20),'cautious',false);
  const realStart=JSON.parse(await readFile(resolve(root,'scripts/fixtures/extraction-default-player-start.json'),'utf8'));await voyage('default-new-player-42',42,realStart,'balanced');
  await controls();
 }
 await writeFile(resolve(out,'report.json'),JSON.stringify({native,sha256:createHash('sha256').update(await readFile(native)).digest('hex'),passed:results.length,results},null,2));
}catch(e){await writeFile(resolve(out,'failure.json'),JSON.stringify({message:e.message,stack:e.stack},null,2));throw e;}
