import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const root=resolve(import.meta.dirname,'..');
const out=resolve(root,'artifacts/extraction-stall-20261113');await mkdir(out,{recursive:true});
const binary=process.env.CAS_STALL_NATIVE||resolve(root,'godot/bin/runtime/ddf088630609814e/cas-sim.exe');
const account=JSON.parse(await readFile(resolve(out,'actual-account-before.json'),'utf8'));
const save=JSON.parse(account.active_run.snapshot);
const requests=[],pending=[],child=spawn(binary,[],{stdio:['pipe','pipe','inherit']});
createInterface({input:child.stdout}).on('line',line=>pending.shift()(JSON.parse(line)));
const ask=async q=>{requests.push(q);const r=await new Promise(done=>{pending.push(done);child.stdin.write(JSON.stringify(q)+'\n');});assert.equal(r.ok,true,JSON.stringify(r));return r.data;};
const summary=v=>({tick:v.tick,result:v.result,pilot:v.salvage.expedition.autopilot,search:v.salvage.search,extracting:v.salvage.extracting,cargo:v.salvage.cargo_grid,ruins:v.salvage.ruins,ships:v.ships.map(s=>({id:s.id,fleet:s.fleet,x:s.x,y:s.y,speed:s.speed,hp:s.hp,heading:s.heading,navigation:s.navigation})),fleets:v.fleets,tasks:v.salvage.expedition.tasks,fuel:v.fuel});
let v=await ask({op:'load',save});const loaded=summary(v);await writeFile(resolve(out,'actual-loaded-view.json'),JSON.stringify(v,null,2));
console.log(JSON.stringify({stage:'loaded',tick:v.tick,pilot:loaded.pilot,cargo:loaded.cargo.items.map(i=>({id:i.id,placement:i.placement})),search:v.salvage.search}));
const version=process.env.CAS_STALL_PILOT||'cas-extraction-pilot-v2';
v=await ask({op:'extraction_autopilot',enabled:true,policy:'balanced',version});
const trace=[summary(v)];let phase=v.salvage.expedition.autopilot.phase;
for(let i=0;i<750&&!v.result;i++){
 v=await ask({op:'step',seconds:1});const a=v.salvage.expedition.autopilot;
 if(a.phase!==phase||i%15===0){phase=a.phase;trace.push(summary(v));console.log(JSON.stringify({tick:v.tick,phase:a.phase,reason:a.reason,error:a.last_error,commands:a.commands_issued,cargo:a.stowed_value,ships:v.ships.map(s=>({id:s.id,x:s.x,y:s.y,speed:s.speed})),result:v.result}));}
}
const label=version.endsWith('v3')?'v3':'v2';
await writeFile(resolve(out,'actual-'+label+'-diagnosis.json'),JSON.stringify({binary,loaded,trace,terminal:summary(v)},null,2));
await writeFile(resolve(out,'actual-'+label+'-diagnosis-commands.json'),JSON.stringify(requests,null,2));
child.stdin.end();
