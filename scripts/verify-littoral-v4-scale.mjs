import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {performance} from 'node:perf_hooks';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/littoral-v4/multi');await mkdir(out,{recursive:true});
const native=process.env.CAS_LITTORAL_NATIVE;assert.ok(native);
class Sim{constructor(){this.p=spawn(native,[],{stdio:['pipe','pipe','inherit']});this.lines=createInterface({input:this.p.stdout})[Symbol.asyncIterator]();this.commands=[];}async ask(q){this.commands.push(q);this.p.stdin.write(JSON.stringify(q)+'\n');const line=await this.lines.next();assert.equal(line.done,false);const r=JSON.parse(line.value);assert.equal(r.ok,true,JSON.stringify(r));return r.data;}close(){this.p.stdin.end();}}
const request=roster=>({op:'new_littoral',version:'cas-littoral-v4',company_layout:'multi-company-v1',seed:47,mode:'defense',ships:[{id:'IBS-U-USN-FLETCHER',hp:100,ammo:100}],roster,unit_condition:roster.map(id=>({id,hp:100})),transport_preset:'combat',defense:[]});
const sim=new Sim();let receipt;try{
 let v=await sim.ask(request(['MCP-034','MCP-001']));assert.equal(v.littoral.land.entities.filter(b=>b.side==='allies').length,69);assert.equal(v.littoral.groups.length,8);assert.ok(v.littoral.groups.every(g=>g.stage==='ground'));
 v=await sim.ask({op:'littoral_order',company_id:'MCP-001-C01',action:'retreat'});
 for(let i=0;i<100;i++)v=await sim.ask({op:'step',seconds:.5});
 const air=v.littoral.groups.find(g=>g.company_id==='MCP-001-C01');assert.equal(air.stage,'ground');assert.match(air.status_reason,/兼容.*舱位/);assert.ok(!v.littoral.transports.some(t=>t.company_id==='MCP-001-C01'));
 const saved=await sim.ask({op:'save'});assert.deepEqual(await sim.ask({op:'load',save:saved}),v);assert.deepEqual(await sim.ask({op:'replay',save:saved}),v);
 await writeFile(resolve(out,'v4-defense-dd-recovery-commands.json'),JSON.stringify(sim.commands));
 sim.commands=[];v=await sim.ask(request(['MCP-034','MCP-116','MCP-167','MCP-011','MCP-103']));assert.equal(v.littoral.land.entities.filter(b=>b.side==='allies').length,181);assert.equal(v.littoral.groups.length,21);const times=[];let size=0,peak=0;
 for(let i=0;i<200;i++){let at=performance.now();v=await sim.ask({op:'step',seconds:.1});const ms=performance.now()-at;if(i>=20)times.push(ms);size=Math.max(size,Buffer.byteLength(JSON.stringify(v)));peak=Math.max(peak,v.littoral.land.entities.length);}
 times.sort((a,b)=>a-b);let at=performance.now();const s=await sim.ask({op:'save'});const saveMs=performance.now()-at;at=performance.now();assert.deepEqual(await sim.ask({op:'load',save:s}),v);const loadMs=performance.now()-at;
 assert.equal(v.tick,20);assert.ok(peak<=320);assert.ok(times[Math.floor(times.length*.95)]<100,'native pipe+JSON p95 fits 10Hz budget');
 await writeFile(resolve(out,'v4-defense-181-scale-commands.json'),JSON.stringify(sim.commands));
 receipt={passed:true,native,sha:createHash('sha256').update(await readFile(native)).digest('hex'),garrisonDD:{bodies:69,companies:8,airStillGroundAt:50,reason:air.status_reason,saveReplayExact:true},scale:{friendlyBodies:181,companies:21,observedPeak:peak,samples:times.length,simulationHz:10,measurement:'wall-clock native request/pipe/JSON round trip; not GPU or Rust-only timing',medianMs:times[Math.floor(times.length*.5)],p95Ms:times[Math.floor(times.length*.95)],maxMs:times.at(-1),maxViewBytes:size,saveBytes:Buffer.byteLength(JSON.stringify(s)),saveMs,loadMs}};
 await writeFile(resolve(out,'scale-receipt.json'),JSON.stringify(receipt,null,2));console.log(JSON.stringify(receipt));
}finally{sim.close();}
