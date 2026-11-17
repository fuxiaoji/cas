import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile} from 'node:fs/promises';
const p='artifacts/extraction-stall-20261113/',a=JSON.parse(await readFile(p+'actual-account-before.json','utf8')),start=JSON.parse(a.active_run.snapshot).salvage;
start.cargo_v4.environment='fjord';start.cargo_v4.difficulty='calm';start.expedition_v2.scene='thermal_vent';start.mission.id='calm';
const child=spawn(process.env.CAS_STALL_NATIVE||'target/extraction-stall-build/release/cas-sim.exe',[],{stdio:['pipe','pipe','inherit']}),pending=[],trace=[];createInterface({input:child.stdout}).on('line',l=>pending.shift()(JSON.parse(l)));
async function ask(q){const r=await new Promise(f=>{pending.push(f);child.stdin.write(JSON.stringify(q)+'\n');});if(!r.ok)throw Error(JSON.stringify(r));return r.data;}
try{await ask({op:'new_salvage',seed:6106,start});await ask({op:'extraction_autopilot',enabled:true,version:'cas-extraction-pilot-v3',policy:'balanced'});for(let i=1;i<=216;i++){const v=await ask({op:'step',seconds:1});if(i>=198){trace.push(v);console.log(JSON.stringify({tick:i,phase:v.salvage.expedition.autopilot.phase,commands:v.salvage.expedition.autopilot.commands_issued,fleets:v.fleets.map(f=>({id:f.id,speed:f.speed,actual:f.actual,paths:f.paths.map(p=>({ship:p.ship,points:p.points.length})),points:f.points})),ships:v.ships.map(s=>({id:s.id,x:s.x,y:s.y,speed:s.speed}))}));}}await writeFile(p+'fjord-ingress-raw-views.json',JSON.stringify(trace,null,2));}finally{child.stdin.end();}
