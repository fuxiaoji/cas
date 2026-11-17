import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),dir=resolve(root,'artifacts/tide-v2-core');await mkdir(dir,{recursive:true});
const binary=process.env.CAS_TIDE_NATIVE||resolve(root,'target/tide-v2-build/release/cas-sim.exe');
const roster=['IBS-U-USN-UNNAMED-T01-R03','IBS-U-USN-ERMA-IOWA','IBS-U-USN-ERMA-DES-MOINES','IBS-U-USN-PENSACOLA','IBS-U-USN-ASTORIA'];
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a.localeCompare(b,'en'))):x);
class Sim {
 constructor(){this.p=spawn(binary,[],{stdio:['pipe','pipe','inherit']});this.pending=[];this.requests=[];this.timings={};this.bytes=0;createInterface({input:this.p.stdout}).on('line',s=>{this.bytes+=s.length;this.pending.shift()(JSON.parse(s));});}
 async ask(q,ok=true){this.requests.push(q);const start=performance.now(),r=await new Promise(f=>{this.pending.push(f);this.p.stdin.write(JSON.stringify(q)+'\n');});(this.timings[q.op]||=[]).push(performance.now()-start);assert.equal(r.ok,ok,JSON.stringify(r));return r.data;}
 close(){this.p.stdin.end();}
}
function timing(list){list=[...list].sort((a,b)=>a-b);return {count:list.length,totalMs:list.reduce((a,b)=>a+b,0),p50:list[Math.floor(list.length*.5)],p95:list[Math.floor(list.length*.95)],max:list.at(-1)};}
function choice(v,defensive=false,decline=false){return (!defensive&&!decline?v.tide.choices.find(c=>c.id.startsWith('reinforce:')):null)||((v.tide.team_hp/v.tide.team_max_hp<.65)?v.tide.choices.find(c=>['shield','repair','restore'].includes(c.id)):null)||(defensive?['maneuver','magnet','shield','repair','restore','blast','torpedo','orbit','chain','damage','multishot','haste']:['chain','orbit','multishot','haste','magnet','blast','damage','shield','repair','torpedo','maneuver','restore']).map(id=>v.tide.choices.find(c=>c.id===id)).find(Boolean)||v.tide.choices.find(c=>!c.id.startsWith('reinforce:'))||v.tide.choices[0];}
const results=[];
async function boundaries(){
 const name='tide-v2-protocol-boundaries';if(process.env.CAS_TIDE_CASE&&!name.includes(process.env.CAS_TIDE_CASE))return;
 const sim=new Sim();let checks=0;
 try{
  let v=await sim.ask({op:'new_tide',version:'cas-event-tide-v2',seed:42,character_id:'IBS-U-USN-FLETCHER',roster:[],difficulty:'normal',intel_profile:'open-intel-v1'});
  v=await sim.ask({op:'route',fleet:1,speed:60,points:[{x:18000,y:7000}]});v=await sim.ask({op:'step',seconds:.1});assert.equal(v.tick,.1);assert.equal(v.tide.frame,1);
  const snapshot=canonical(v),saved=await sim.ask({op:'save'}),newRun={op:'new_tide',version:'cas-event-tide-v2',seed:42,character_id:'IBS-U-USN-FLETCHER'};
  const invalid=[...[-.1,.15,2700.1,'0.1',null].map(seconds=>({op:'step',seconds})),{op:'route',fleet:2,points:[{x:12000,y:7000}]},{op:'route',fleet:1,points:[{x:-1,y:7000}]},{op:'speed',fleet:1,speed:61},{op:'tide_choose',offer_id:0,upgrade:'reinforce:IBS-U-USN-ERMA-IOWA'},{...newRun,version:'future'},{...newRun,roster:['fabricated']},{...newRun,roster:['IBS-U-USN-FLETCHER']},{...newRun,roster:[9]},{...newRun,roster:Array(65).fill(roster[0])}];
  for(const save of [{...saved,frame:1801,tick:180.1},{...saved,tick:.2},{...saved,commands:[{frame:2,request:{op:'speed',speed:0}}]},{...saved,frame:1.5},{...saved,commands:[{frame:1,request:{op:'speed',speed:0}},{frame:0,request:{op:'speed',speed:60}}]}])invalid.push({op:'load',save});
  for(const q of invalid){await sim.ask(q,false);assert.equal(canonical(await sim.ask({op:'observe'})),snapshot,'atomic invalid request');checks++;}
  assert.equal((await sim.ask({op:'preview_route',fleet:2,points:[{x:12000,y:7000}]})).valid,false);
  const replay=await sim.ask({op:'replay',save:saved,tick:.1});assert.equal(canonical(replay),snapshot);
  await sim.ask({op:'speed',fleet:1,speed:0});const held=(await sim.ask({op:'observe'})).ships[0];v=await sim.ask({op:'step',seconds:.5});assert.equal(v.ships[0].x,held.x);assert.equal(v.ships[0].y,held.y);
  v=await sim.ask({op:'tide_abandon'});assert.equal(v.tide.outcome.event_tokens,0);const end=await sim.ask({op:'save'});assert.equal(canonical(await sim.ask({op:'load',save:end})),canonical(v));assert.equal(canonical(await sim.ask({op:'replay',save:end})),canonical(v));
  const legacy=await sim.ask({op:'new_tide',version:'cas-event-tide-v1',seed:42,character_id:'IBS-U-USN-FLETCHER'});assert.equal(legacy.version,'cas-event-tide-v1');assert.equal(legacy.ships.length,1);assert.ok(!legacy.tide.members);
  await sim.ask({op:'step',seconds:.1},false);await sim.ask({op:'new',seed:42});v=await sim.ask({op:'observe'});assert.ok(!v.tide);v=await sim.ask({op:'load',save:saved});assert.equal(canonical(v),snapshot);assert.equal(v.version,'cas-event-tide-v2');
  const summary={name,binary,checks,kind:'protocol',timings:Object.fromEntries(Object.entries(sim.timings).map(([k,l])=>[k,timing(l)]))};await writeFile(resolve(dir,name+'-commands.json'),JSON.stringify(sim.requests,null,2));await writeFile(resolve(dir,name+'-native.json'),JSON.stringify({summary},null,2));results.push(summary);console.log(JSON.stringify(summary));
 }finally{sim.close();}
}
async function run(seed,difficulty='normal',stationary=false,empty=false,noBoss=false,decline=false,leader='IBS-U-USN-FLETCHER'){
 const name=`tide-v2-${difficulty}-${seed}${stationary?'-stationary':''}${empty?'-solo':''}${noBoss?'-no-boss':''}${decline?'-decline':''}${leader.includes('IOWA')?'-heavy':''}`;
 if(process.env.CAS_TIDE_CASE&&!name.includes(process.env.CAS_TIDE_CASE))return;
 const sim=new Sim(),trace=[],fired=new Set(),reinforcements=[];let firstKill,firstOffer,restored=false,v;
 try {
  v=await sim.ask({op:'new_tide',version:'cas-event-tide-v2',seed,character_id:leader,roster:empty?[]:roster.filter(id=>id!==leader).concat(leader==='IBS-U-USN-FLETCHER'?[]:['IBS-U-USN-FLETCHER']),difficulty,intel_profile:'open-intel-v1'});
  const peaks={foes:0,bolts:0,drops:0,shots:0,impacts:0};let lastRoute=-1;
  for(let guard=0;guard<5000&&!v.result;guard++){
   if(v.tide.paused){firstOffer??=v.tick;assert.equal(v.tide.offer_kind,v.tide.choices.some(c=>c.id.startsWith('reinforce:'))?'reinforcement':'upgrade','offer category matches real choices');const c=choice(v,noBoss,decline);if(c.id.startsWith('reinforce:'))reinforcements.push({tick:v.tick,id:c.character_id});v=await sim.ask({op:'tide_choose',offer_id:v.tide.offer_id,upgrade:c.id});continue;}
   if(!stationary&&Math.floor(v.tick)!==lastRoute){lastRoute=Math.floor(v.tick);const angle=v.tick*.13;const point=noBoss&&v.tick>=145?(v.ships[0].x>600?{x:300,y:v.ships[0].y}:{x:300,y:v.ships[0].y<1000?13700:300}):{x:12000+Math.cos(angle)*1500,y:7000+Math.sin(angle)*1500};v=await sim.ask({op:'route',fleet:1,mode:'follow',speed:60,points:[point]});}
   v=await sim.ask({op:'step',seconds:.1});
   if(v.tide.kills)firstKill??=v.tick;for(const shot of v.tide.shots)fired.add(shot.ship_id);
   peaks.foes=Math.max(peaks.foes,v.contacts.length);peaks.bolts=Math.max(peaks.bolts,v.shells.length+v.torpedoes.length);peaks.drops=Math.max(peaks.drops,v.tide.drops.length);peaks.shots=Math.max(peaks.shots,v.tide.shots.length);peaks.impacts=Math.max(peaks.impacts,v.tide.impacts.length);
   if(v.tide.frame%100===0||v.result)trace.push({frame:v.tide.frame,tick:v.tick,kills:v.tide.kills,level:v.tide.level,members:v.ships.length,hp:v.tide.team_hp,foes:v.contacts.length,bolts:v.shells.length+v.torpedoes.length,drops:v.tide.drops.length,upgrades:v.tide.upgrades});
   if(!restored&&v.tick>=60&&v.ships.length>=3){const saved=await sim.ask({op:'save'});assert.equal(canonical(await sim.ask({op:'load',save:saved})),canonical(v),'mid-load');assert.equal(canonical(await sim.ask({op:'replay',save:saved})),canonical(v),'mid-replay');restored=true;}
  }
  const before=canonical(v),saved=await sim.ask({op:'save'});assert.equal(canonical(await sim.ask({op:'load',save:saved})),before,'final-load');assert.equal(canonical(await sim.ask({op:'replay',save:saved})),before,'final-replay');
  const summary={name,binary,seed,difficulty,stationary,expected_success:!noBoss,decline,firstKill,firstOffer,reinforcements,restored,kills:v.tide.kills,members:v.ships.length,crew:v.tide.members,fired:[...fired],hp:v.tide.team_hp,frame:v.tide.frame,tick:v.tick,result:v.tide.outcome,peaks,timings:Object.fromEntries(Object.entries(sim.timings).map(([k,l])=>[k,timing(l)])),bytes:sim.bytes,saveBytes:JSON.stringify(saved).length};
  await writeFile(resolve(dir,name+'-commands.json'),JSON.stringify(sim.requests,null,2));await writeFile(resolve(dir,name+'-native.json'),JSON.stringify({summary,trace,terminal:v},null,2));console.log(JSON.stringify(summary));results.push(summary);
  assert.ok(v.result,'real terminal');assert.ok(peaks.foes<=96&&peaks.bolts<=192&&peaks.drops<=48&&peaks.shots<=64&&peaks.impacts<=64,'entity budget');
  assert.ok(v.tide.outcome.event_tokens<=1000&&v.tide.outcome.score<1000000,'bounded local reward');
  if(noBoss){assert.equal(v.tide.outcome.boss_defeated,false,'real undefeated boss');assert.equal(v.tide.outcome.success,false,'real objective failure');assert.equal(v.tick,180,'actual full duration');}
  else {assert.equal(v.tide.outcome.success,true,'real victory');assert.ok(firstKill<=2,'early clear');assert.ok(v.tide.kills>=300,'continuous mowing');if(!empty&&!decline&&!stationary){assert.equal(v.ships.length,6,'six real crew');assert.equal(fired.size,6,'each crew fired');assert.ok(['torpedo','barrage','heavy'].every(role=>v.tide.members.some(m=>m.role===role)),'real mixed ship roles');}}
  if(decline){assert.equal(v.ships.length,1,'declined reinforcements');assert.equal(v.tide.reserves.length,roster.length,'reserves preserved');}
 }finally{sim.close();}
}
try{for(const seed of [42,43,6106])await run(seed);await run(42,'hard');await run(43,'normal',false,true);await run(42,'hard',true);await run(42,'normal',false,false,false,false,'IBS-U-USN-ERMA-IOWA');await run(44,'normal',false,false,false,true);await run(43,'hard',false,true,true);await boundaries();await writeFile(resolve(dir,'native-receipt.json'),JSON.stringify({binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),results},null,2));}catch(e){await writeFile(resolve(dir,'native-failure.json'),JSON.stringify({message:e.message,stack:e.stack,results},null,2));throw e;}
