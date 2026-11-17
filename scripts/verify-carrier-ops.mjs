import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/carrier-20261115');await mkdir(out,{recursive:true});
const exe=resolve(root,'target-carrier/release/cas-sim.exe'),wasm=await readFile(resolve(root,'target-carrier/wasm32-unknown-unknown/release/cas_core.wasm'));
class Sim{constructor(path=exe){this.p=spawn(path,[],{stdio:['pipe','pipe','inherit']});this.lines=createInterface({input:this.p.stdout})[Symbol.asyncIterator]();}async raw(q){this.p.stdin.write(JSON.stringify(q)+'\n');return (await this.lines.next()).value;}close(){this.p.stdin.end();}}
const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports,enc=new TextEncoder(),dec=new TextDecoder();let calls=0;
function wasmAsk(q){let b=enc.encode(JSON.stringify(q)),p=api.cas_alloc(b.length)>>>0;new Uint8Array(api.memory.buffer,p,b.length).set(b);let r=api.cas_request(p,b.length)>>>0;let value=dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0));return value;}
const sim=new Sim(),commands=[];
async function ask(q,ok=true){commands.push(q);const n=await sim.raw(q);assert.equal(n,wasmAsk(q),`native/WASM #${calls++} ${q.op}`);const r=JSON.parse(n);assert.equal(r.ok,ok,JSON.stringify(r));return r.data;}
const config={op:'new_littoral',version:'cas-littoral-v4',seed:42,mode:'tutorial',lesson:'landing',ships:[{id:'CAS-H-USN-ENTERPRISE-1942',hp:100,ammo:100},{id:'CAS-H-IJN-SHOKAKU-1942',hp:100,ammo:100}],roster:['MCP-034','MCP-001'],unit_condition:[],transport_preset:'combat',defense:[]};
let v=await ask(config);assert.equal(v.littoral.carrier_ops,undefined);v=await ask({op:'carrier_ops',version:'cas-carrier-ops-v1',ally_ai:false});
const squadrons=v.littoral.aviation.squadrons;const fighter=squadrons[0],bomb=squadrons[1],other=squadrons[4];
await ask({op:'littoral_air_order',squadron_id:fighter.id,action:'patrol',x:9000,y:17000});
await ask({op:'littoral_air_order',squadron_id:bomb.id,action:'strike',target_kind:'land',x:12000,y:13000,queue:true});
await ask({op:'littoral_air_order',squadron_id:other.id,action:'strike',target_kind:'land',x:12000,y:13000,queue:true});
let peak=0;for(let i=0;i<170;i++){v=await ask({op:'step',seconds:.5});peak=Math.max(peak,v.littoral.aviation.aircraft.length);for(const s of v.littoral.aviation.squadrons)assert.equal(s.available+s.airborne+s.lost,s.total);}
const saved=await ask({op:'save'});assert.deepEqual(await ask({op:'load',save:saved}),v);
await ask({op:'carrier_ops',version:'cas-carrier-ops-v1',ally_ai:true});for(let i=0;i<40;i++)v=await ask({op:'step',seconds:.5});
assert.ok(v.littoral.aviation.aircraft.some(a=>a.carrier===1));assert.ok(v.littoral.aviation.aircraft.some(a=>a.carrier===2));assert.ok(peak<=24);
sim.close();await writeFile(resolve(out,'ops-commands.json'),JSON.stringify(commands));
const manifest=JSON.parse(await readFile(resolve(root,'godot/bin/core-current.json'),'utf8')),oracle=resolve(root,'godot/bin',manifest.executable);let frozen=0;
for(const file of ['artifacts/littoral-v4/v4-air-naval-loop-commands.json','artifacts/littoral-v4/v4-air-npc-intercept-commands.json']){
 let rows;try{rows=JSON.parse(await readFile(resolve(root,file),'utf8'));}catch{continue}const a=new Sim(),b=new Sim(oracle);try{for(const q of rows){assert.equal(await a.raw(q),await b.raw(q),`old frozen ${file} ${q.op}`);frozen++;}}finally{a.close();b.close();}}
assert.ok(frozen>0);const report={calls,frozen,peak,passed:true,coreInstalled:false,sourceOnlyHulls:7,sourceOnlyAircraft:7};await writeFile(resolve(out,'verification.json'),JSON.stringify(report,null,2));console.log(report);
