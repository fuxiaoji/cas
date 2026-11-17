import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {performance} from 'node:perf_hooks';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/littoral-v3');await mkdir(out,{recursive:true});
const native=process.env.CAS_LITTORAL_NATIVE;assert.ok(native);
const child=spawn(native,[],{stdio:['pipe','pipe','inherit']}),lines=createInterface({input:child.stdout})[Symbol.asyncIterator]();
const journal=[];
async function ask(q){journal.push(q);child.stdin.write(JSON.stringify(q)+'\n');const line=await lines.next();assert.ok(!line.done);const r=JSON.parse(line.value);assert.equal(r.ok,true,JSON.stringify(r));return r.data;}
const ids=['MCP-034','MCP-009','MCP-011','MCP-018','MCP-052'];
const request={op:'new_littoral',version:'cas-littoral-v3',seed:45,mode:'defense',ships:[{id:'IBS-U-IJN-NISSHIN',hp:100,ammo:100},{id:'IBS-U-USN-ERMA-IOWA',hp:100,ammo:100}],roster:ids,unit_condition:ids.map(id=>({id,hp:100})),transport_preset:'transport',defense:[],company_transports:ids.map(id=>({id,kind:'landing_craft'}))};
try{
let v=await ask(request);assert.equal(v.littoral.land.entities.filter(e=>e.side==='allies').length,50);
const times=[],peaks={friendly:0,bodies:0,projectiles:0,transports:0},firing=new Set();let loadMs=0,savedBytes=0;
for(let frame=0;frame<1000&&!v.result;frame++){
 const t=performance.now();v=await ask({op:'step',seconds:.1});times.push(performance.now()-t);
 const entities=v.littoral.land.entities;peaks.friendly=Math.max(peaks.friendly,entities.filter(e=>e.side==='allies').length);peaks.bodies=Math.max(peaks.bodies,entities.length);peaks.projectiles=Math.max(peaks.projectiles,v.shells.length);peaks.transports=Math.max(peaks.transports,v.littoral.transports.length);
 for(const s of v.littoral.shots)if(s.side==='allies'&&s.source.startsWith('body:')){const entity=entities.find(e=>'body:'+e.id===s.source);if(entity)firing.add(entity.unit_id);}
 if(frame===799){const save=await ask({op:'save'});savedBytes=Buffer.byteLength(JSON.stringify(save));const t=performance.now();assert.deepEqual(await ask({op:'load',save}),v);loadMs=performance.now()-t;assert.deepEqual(await ask({op:'replay',save}),v);}
}
assert.equal(peaks.friendly,50);assert.ok(peaks.bodies<=128&&peaks.projectiles<=384);assert.ok(v.tick>=100&&!v.result);
v=await ask({op:'littoral_abandon'});assert.equal(v.littoral.outcome.abandoned,true);assert.ok(Object.values(v.littoral.outcome.resources).every(n=>n===0));
times.sort((a,b)=>a-b);const pick=p=>times[Math.min(times.length-1,Math.floor(times.length*p))];
const receipt={passed:true,native,sha:createHash('sha256').update(await readFile(native)).digest('hex'),measurement:'Native process IPC + real 0.1s step + serialize/parse public observation; not isolated CPU nor GPU',frames:times.length,simulationSeconds:100,p50Ms:pick(.5),p95Ms:pick(.95),maxMs:times.at(-1),peaks,firing:[...firing],savedBytes,loadReplayMs:loadMs,abandonedZeroReward:true};
await writeFile(resolve(out,'performance-receipt.json'),JSON.stringify(receipt,null,2));await writeFile(resolve(out,'v3-performance-commands.json'),JSON.stringify(journal));console.log(JSON.stringify(receipt));
}finally{child.stdin.end();}
