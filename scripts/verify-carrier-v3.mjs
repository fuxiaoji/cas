import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/carrier-v3');await mkdir(out,{recursive:true});
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
const newBattle={op:'new_littoral',version:'cas-littoral-v4',mode:'raid',seed:42,ships:[{id:'CAS-H-USN-ENTERPRISE-1942',hp:100,ammo:100},{id:'CAS-H-IJN-SHOKAKU-1942',hp:100,ammo:100}],roster:['MCP-034','MCP-001'],unit_condition:[],transport_preset:'combat',defense:[]};
const mode=level=>({op:'carrier_automation',version:'cas-carrier-ops-v3',level});
let v=await ask(newBattle);await ask(mode('high'));
for(let i=0;i<200;i++)v=await ask({op:'step',seconds:.1});
assert.ok(v.littoral.aviation.squadrons.some(s=>s.ammunition<18));
await ask(mode('medium'));
const target=v.littoral.land.entities.find(e=>e.side==='axis'&&e.hp>0),goal={op:'carrier_mission',carrier:1,action:'strike',target_kind:'land',x:target.x,y:target.y};
let saved=await ask({op:'save'});await ask({...goal,op:'carrier_mission_preview'});assert.deepEqual(await ask({op:'save'}),saved);
v=await ask(goal);assert.equal(v.littoral.carrier_ops.automation.missions.length,1);
assert.ok(v.littoral.carrier_ops.automation.carriers[0].status.includes('接收'));
saved=await ask({op:'save'});await ask({...goal,x:-100000},false);assert.deepEqual(await ask({op:'save'}),saved);
for(let i=0;i<220;i++)v=await ask({op:'step',seconds:.1});
await ask({op:'carrier_mission',carrier:1,action:'return'});
for(let i=0;i<700;i++){v=await ask({op:'step',seconds:.1});if(!v.littoral.aviation.aircraft.some(a=>a.carrier===1))break;}
assert.ok(!v.littoral.aviation.aircraft.some(a=>a.carrier===1));
assert.ok(v.littoral.carrier_ops.automation.stopped_carriers.includes(1));
await ask(mode('low'));
const c=v.ships.find(s=>s.id===1),fighter=v.littoral.aviation.squadrons.find(s=>s.carrier===1&&s.role==='fighter');
await ask({op:'littoral_air_order',queue:true,squadron_id:fighter.id,action:'patrol',x:c.x-1800,y:c.y-1200});
for(let i=0;i<220;i++)v=await ask({op:'step',seconds:.1});
assert.ok(v.littoral.aviation.aircraft.some(a=>a.carrier===1));
saved=await ask({op:'save'});assert.deepEqual(await ask({op:'load',save:saved}),v);
// Current island war: use its public known static objective, not the practice
// island's original positions. Leave troop/vehicle rules to that core.
const island=JSON.parse(await readFile(resolve(root,'artifacts/island-war-v1/initial-raid.json'),'utf8'));island.version='cas-island-war-v3';
v=await ask(island);await ask(mode('medium'));
const carrier=v.littoral.aviation.squadrons[0].carrier;
const building=v.littoral.land.buildings.find(e=>e.side==='axis'&&e.hp>0&&['warehouse','hq'].includes(e.kind))||v.littoral.land.buildings.find(e=>e.side==='axis'&&e.hp>0);
const b0=building.hp;
await ask({op:'island_autonomy',enabled:true});
await ask({op:'carrier_mission',carrier,action:'strike',target_kind:'land',x:building.x,y:building.y});
v=await ask({op:'observe'});assert.equal(v.littoral.autonomy.enabled,true,'air objective must preserve ground automation');
let actualLandFlight=false,actualDamage=false;const ownAirIds=new Set();
for(let i=0;i<700;i++){
 v=await ask({op:'step',seconds:.1});
 actualLandFlight ||= v.littoral.aviation.aircraft.some(a=>a.side==='allies'&&a.target_kind==='land'&&a.kind==='SBD');
 for(const a of v.littoral.aviation.aircraft.filter(a=>a.side==='allies'))ownAirIds.add(`aircraft:${a.id}`);
 actualDamage ||= v.littoral.impacts.some(e=>e.kind==='air_strike'&&e.hits>0&&ownAirIds.has(e.source));
 if(actualLandFlight&&actualDamage&&i>150)break;
}
assert.ok(actualLandFlight&&actualDamage,'current island ground support must actually fly and damage an actual public objective');
saved=await ask({op:'save'});assert.deepEqual(await ask({op:'load',save:saved}),v);
await ask({op:'island_autonomy',enabled:true,posture:'withdraw'});
for(let i=0;i<600;i++){v=await ask({op:'step',seconds:.1});if(!v.littoral.aviation.aircraft.some(a=>a.side==='allies'))break;}
assert.ok(!v.littoral.aviation.aircraft.some(a=>a.side==='allies'),'joint withdrawal physically recovers planes');
sim.close();assert.ok(orbitSeen&&holdingSeen&&movementSamples>1000);await writeFile(resolve(out,'commands.json'),JSON.stringify(commands));
let frozen=0;for(const file of ['artifacts/carrier-20261115/ops-commands.json','artifacts/littoral-v4/v4-air-naval-loop-commands.json','artifacts/carrier-v2/commands.json']){
 const qs=JSON.parse(await readFile(resolve(root,file),'utf8')),a=new Sim(),b=new Sim(baseline);try{for(const q of qs){assert.equal(await a.raw(q),await b.raw(q),`frozen ${file} ${q.op}`);frozen++;}}finally{a.close();b.close();}
}
assert.ok(frozen>=1644);
const require=createRequire(resolve(root,'client/package.json')),{chromium}=require('playwright');
const browser=await chromium.launch({headless:true,executablePath:process.env.CAS_BROWSER_PATH||'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});let browserCalls=0;
try{const page=await browser.newPage();await page.goto(pathToFileURL(resolve(root,'output/carrier-20261115/index.html')).href);
 browserCalls=await page.evaluate(async({bytes,commands,expected})=>{const b=Uint8Array.from(atob(bytes),c=>c.charCodeAt(0)),{instance}=await WebAssembly.instantiate(b,{}),a=instance.exports,e=new TextEncoder(),d=new TextDecoder();let count=0;for(const q of commands){const b=e.encode(JSON.stringify(q)),p=a.cas_alloc(b.length)>>>0;new Uint8Array(a.memory.buffer,p,b.length).set(b);const r=a.cas_request(p,b.length)>>>0;const raw=new Uint8Array(a.memory.buffer,r,a.cas_response_len()>>>0).slice();JSON.parse(d.decode(raw));const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',raw)),x=>x.toString(16).padStart(2,'0')).join('');if(digest!==expected[count])throw Error(`browser/native response mismatch ${count} ${q.op}`);count++;}return count;},{bytes:wasm.toString('base64'),commands,expected});
}finally{await browser.close();}
assert.equal(browserCalls,calls);
const report={passed:true,calls,browserCalls,frozen,movementSamples,minTravelPerTenthSecond:minTravel,patrolOrbitObserved:orbitSeen,returnFlightObserved:holdingSeen,normalCoreInstalled:false,actualIslandLandFlight:actualLandFlight,actualIslandDamage:actualDamage};
await writeFile(resolve(out,'verification.json'),JSON.stringify(report,null,2));console.log(report);
