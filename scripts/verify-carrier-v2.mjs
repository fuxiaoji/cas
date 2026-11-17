import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/carrier-v2');await mkdir(out,{recursive:true});
const exe=resolve(root,'target-carrier/release/cas-sim.exe'),baseline=resolve(out,'baseline/cas-sim.exe');
class Sim{constructor(path=exe){this.p=spawn(path,[],{stdio:['pipe','pipe','inherit']});this.lines=createInterface({input:this.p.stdout})[Symbol.asyncIterator]();}async raw(q){this.p.stdin.write(JSON.stringify(q)+'\n');return (await this.lines.next()).value;}close(){this.p.stdin.end();}}
const wasm=await readFile(resolve(root,'target-carrier/wasm32-unknown-unknown/release/cas_core.wasm'));
const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports,enc=new TextEncoder(),dec=new TextDecoder();
function wasmAsk(q){const b=enc.encode(JSON.stringify(q)),p=api.cas_alloc(b.length)>>>0;new Uint8Array(api.memory.buffer,p,b.length).set(b);const r=api.cas_request(p,b.length)>>>0;return dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0));}
const sim=new Sim(),commands=[],expected=[];let calls=0,movementSamples=0,minTravel=Infinity,last,orbitSeen=false,holdingSeen=false;
async function ask(q,ok=true){commands.push(q);const raw=await sim.raw(q);expected.push(createHash('sha256').update(raw).digest('hex'));assert.equal(raw,wasmAsk(q),`native/WASM ${calls++} ${q.op}`);const response=JSON.parse(raw);assert.equal(response.ok,ok,JSON.stringify(response));const v=response.data;
 if(q.op==='step'&&q.seconds===.1&&v?.littoral?.aviation&&last?.littoral?.aviation){for(const a of v.littoral.aviation.aircraft){const before=last.littoral.aviation.aircraft.find(b=>b.id===a.id);if(!before||before.phase==='launching'||a.phase==='launching')continue;const distance=Math.hypot(a.x-before.x,a.y-before.y);assert.ok(distance>1,`aircraft ${a.id} stopped in ${a.phase}`);minTravel=Math.min(minTravel,distance);movementSamples++;if(a.phase==='patrolling')orbitSeen=true;if(a.phase==='returning')holdingSeen=true;}}
 if(v?.littoral?.aviation){last=v;for(const s of v.littoral.aviation.squadrons)assert.equal(s.available+s.airborne+s.lost,s.total);}return v;
}
let v=await ask({op:'new_littoral',version:'cas-littoral-v4',mode:'tutorial',lesson:'landing',seed:42,ships:[{id:'CAS-H-USN-ENTERPRISE-1942',hp:100,ammo:100},{id:'CAS-H-IJN-SHOKAKU-1942',hp:100,ammo:100}],roster:['MCP-034','MCP-001'],unit_condition:[],transport_preset:'combat',defense:[]});
await ask({op:'carrier_ops',version:'cas-carrier-ops-v2',ally_ai:false});
const c=v.ships[0],s=v.littoral.aviation.squadrons[0],other=v.littoral.aviation.squadrons[3];
const cap={op:'littoral_air_order',queue:true,squadron_id:s.id,action:'patrol',x:c.x-1800,y:c.y-1200};
await ask(cap);await ask({...cap,squadron_id:other.id,x:c.x-2300});
for(let i=0;i<240;i++)v=await ask({op:'step',seconds:.1});
assert.ok(v.littoral.aviation.aircraft.some(a=>a.phase==='patrolling'));
await ask({...cap,x:c.x-2400});await ask({...cap,x:c.x-2800});assert.equal(last.littoral.carrier_ops.queue.length,1);
const before=last.littoral.aviation.aircraft.map(a=>[a.id,a.fuel_remaining,a.weapon_remaining]);
v=await ask({op:'carrier_air_order',scope:'flight',squadron_id:s.id,action:'patrol',x:c.x-3000,y:c.y-1600});
assert.deepEqual(v.littoral.aviation.aircraft.map(a=>[a.id,a.fuel_remaining,a.weapon_remaining]),before);
const savedBefore=await ask({op:'save'});await ask({op:'carrier_air_order',scope:'flight',squadron_id:s.id,action:'patrol',x:100000,y:100000},false);assert.deepEqual(await ask({op:'save'}),savedBefore);
for(let i=0;i<80;i++)v=await ask({op:'step',seconds:.1});
await ask({op:'carrier_air_order',scope:'wing',carrier:c.id,action:'return'});
for(let i=0;i<800;i++){v=await ask({op:'step',seconds:.1});if(!v.littoral.aviation.aircraft.some(a=>a.carrier===c.id))break;}
assert.equal(v.littoral.aviation.squadrons[0].available,3);assert.equal(v.littoral.carrier_ops.queue.length,0);
await ask(cap);for(let i=0;i<600;i++){v=await ask({op:'step',seconds:.1});if(v.littoral.aviation.aircraft.some(a=>a.carrier===c.id&&a.phase==='patrolling'))break;}assert.ok(v.littoral.aviation.aircraft.some(a=>a.carrier===c.id&&a.phase==='patrolling'));
await ask({op:'carrier_ops',version:'cas-carrier-ops-v2',ally_ai:true});for(const carrier of [1,2])await ask({op:'carrier_policy',carrier,policy:'balanced',release_manual:true});
for(let i=0;i<100;i++)v=await ask({op:'step',seconds:.1});
const save=await ask({op:'save'});assert.deepEqual(await ask({op:'load',save}),v);sim.close();
assert.ok(orbitSeen&&holdingSeen&&movementSamples>1000);await writeFile(resolve(out,'commands.json'),JSON.stringify(commands));
let frozen=0;for(const file of ['artifacts/carrier-20261115/ops-commands.json','artifacts/littoral-v4/v4-air-naval-loop-commands.json']){
 const qs=JSON.parse(await readFile(resolve(root,file),'utf8')),a=new Sim(),b=new Sim(baseline);try{for(const q of qs){assert.equal(await a.raw(q),await b.raw(q),`frozen ${file} ${q.op}`);frozen++;}}finally{a.close();b.close();}
}
assert.ok(frozen>=591);
const require=createRequire(resolve(root,'client/package.json')),{chromium}=require('playwright');
const browser=await chromium.launch({headless:true,executablePath:process.env.CAS_BROWSER_PATH||'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});let browserCalls=0;
try{const page=await browser.newPage();await page.goto(pathToFileURL(resolve(root,'output/carrier-20261115/index.html')).href);
 browserCalls=await page.evaluate(async({bytes,commands,expected})=>{const b=Uint8Array.from(atob(bytes),c=>c.charCodeAt(0)),{instance}=await WebAssembly.instantiate(b,{}),a=instance.exports,e=new TextEncoder(),d=new TextDecoder();let count=0;for(const q of commands){const b=e.encode(JSON.stringify(q)),p=a.cas_alloc(b.length)>>>0;new Uint8Array(a.memory.buffer,p,b.length).set(b);const r=a.cas_request(p,b.length)>>>0;const raw=new Uint8Array(a.memory.buffer,r,a.cas_response_len()>>>0).slice();JSON.parse(d.decode(raw));const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',raw)),x=>x.toString(16).padStart(2,'0')).join('');if(digest!==expected[count])throw Error(`browser/native response mismatch ${count} ${q.op}`);count++;}return count;},{bytes:wasm.toString('base64'),commands,expected});
}finally{await browser.close();}
assert.equal(browserCalls,calls);
const report={passed:true,calls,browserCalls,frozen,movementSamples,minTravelPerTenthSecond:minTravel,patrolOrbitObserved:orbitSeen,returnFlightObserved:holdingSeen,normalCoreInstalled:false};
await writeFile(resolve(out,'verification.json'),JSON.stringify(report,null,2));console.log(report);
