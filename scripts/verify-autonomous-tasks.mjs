// Exercise the optional-objective branch without issuing any field commands.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const manifest=JSON.parse(await readFile(resolve(root,'godot/bin/core-current.json'),'utf8'));
const native=resolve(root,'godot/bin',manifest.executable);
const wasm=await readFile(resolve(root,'target/arena-wasm-build/wasm32-unknown-unknown/release/cas_core.wasm'));
const capitals=process.argv.includes('--capitals');
const solo=process.argv.includes('--solo');
const out=resolve(root,capitals?'artifacts/autonomous-tasks-capitals':solo?'artifacts/autonomous-tasks-solo':'artifacts/autonomous-tasks');await mkdir(out,{recursive:true});
const start=JSON.parse(await readFile(resolve(root,'artifacts/arena-autonomy/pilot-v2-40-commands.json'),'utf8'))[0].start;
if(capitals)start.fleet=['IBS-U-USN-WASHINGTON','IBS-U-USN-SOUTH-DAKOTA','IBS-U-USN-COLORADO'].map(id=>({id,hp:100,ammo:100,level:0}));
if(solo)start.fleet=start.fleet.slice(0,1);
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a.localeCompare(b,'en'))):x);
const reports=[];
for(const seed of (capitals||solo?[8,9]:[7,8,9,10])){
 const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports,encoder=new TextEncoder(),decoder=new TextDecoder(),commands=[],responses=[];
 const ask=q=>{commands.push(q);const bytes=encoder.encode(JSON.stringify(q)),p=api.cas_alloc(bytes.length)>>>0;new Uint8Array(api.memory.buffer,p,bytes.length).set(bytes);const pointer=api.cas_request(p,bytes.length)>>>0;const response=JSON.parse(decoder.decode(new Uint8Array(api.memory.buffer,pointer,api.cas_response_len()>>>0)));assert.equal(response.ok,true);responses.push(response);return response.data;};
 const policy=capitals?'balanced':'bold';
 let view=ask({op:'new_salvage',seed,start});view=ask({op:'extraction_autopilot',enabled:true,policy,version:'cas-extraction-pilot-v2'});
 let completed=false,accepted=false;const phases=new Set();
 for(let t=0;t<1200&&!view.result;t++){
  view=ask({op:'step',seconds:1});
  const exp=view.salvage.expedition;completed||=exp.tasks.some(task=>task.status==='complete');accepted||=exp.tasks.some(task=>task.status!=='offered');phases.add(exp.autopilot.phase);
 }
 const process=spawnSync(native,[],{input:commands.map(JSON.stringify).join('\n')+'\n',encoding:'utf8',maxBuffer:256*1024*1024});assert.equal(process.status,0,process.stderr);
 const actual=process.stdout.trim().split(/\r?\n/).map(JSON.parse);assert.equal(actual.length,responses.length);
 for(let n=0;n<actual.length;n++)assert.equal(canonical(actual[n]),canonical(responses[n]),`native/WASM ${seed} request ${n}`);
 assert.ok(view.result,'voyage genuinely terminates');
 const report={seed,policy,tick:view.tick,accepted,completed,extracted:view.salvage.extracted,cargo:view.salvage.cargo_grid.items.filter(item=>item.placement).length,phases:[...phases],tasks:view.salvage.expedition.tasks,requests:commands.length,nativeWasm:true};reports.push(report);
 await writeFile(resolve(out,`seed-${seed}-commands.json`),JSON.stringify(commands,null,2));
 console.log(JSON.stringify({seed,tick:report.tick,accepted,completed,extracted:report.extracted,cargo:report.cargo}));
}
await writeFile(resolve(out,'receipt.json'),JSON.stringify({native,sha256:manifest.sha256,reports,scope:capitals?'Two balanced-policy battleship voyages':solo?'Two bold-policy single destroyer voyages':'Four bold-policy destroyer voyages',commands:'No user field commands; actual task status and terminal state'},null,2));
