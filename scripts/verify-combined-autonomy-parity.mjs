import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir,stat} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..');
const out=resolve(root,'artifacts/story-modernization-v3/parity/combined-autonomy');
const native=process.env.CAS_LITTORAL_NATIVE,wasmPath=process.env.CAS_LITTORAL_WASM;
assert.ok(native&&wasmPath,'Set CAS_LITTORAL_NATIVE and CAS_LITTORAL_WASM');
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const wasm=await readFile(wasmPath);const enc=new TextEncoder(),dec=new TextDecoder();
await mkdir(out,{recursive:true});
const base={op:'new_littoral',version:'cas-littoral-v4',company_layout:'multi-company-v1',seed:42,mode:'tutorial',lesson:'landing',ships:[{id:'IBS-U-USN-ERMA-IOWA',hp:100,ammo:100},{id:'CAS-H-USN-ENTERPRISE-1942',hp:100,ammo:100},{id:'CAS-O-APV-TIDEBRIDGE',hp:100,ammo:100}],roster:['MCP-034','MCP-001','MCP-009'],unit_condition:[],transport_preset:'combat',defense:[]};
const toggle=(extra={})=>({op:'littoral_autonomy',version:'combined-autonomy-v1',enabled:true,...extra});
const cases=[];
async function scenario(name,request,play){
  const p=spawn(native,[],{stdio:['pipe','pipe','inherit']});const lines=createInterface({input:p.stdout})[Symbol.asyncIterator]();
  const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports;
  const calls=[];let bytes=0,view;
  const call=async q=>{
    calls.push(q);const wire=enc.encode(JSON.stringify(q));const pointer=api.cas_alloc(wire.length)>>>0;
    new Uint8Array(api.memory.buffer,pointer,wire.length).set(wire);
    const response=api.cas_request(pointer,wire.length)>>>0;
    const wasmRaw=dec.decode(new Uint8Array(api.memory.buffer,response,api.cas_response_len()>>>0));
    p.stdin.write(JSON.stringify(q)+'\n');const line=await lines.next();assert.equal(line.done,false);
    if(line.value!==wasmRaw){
      await writeFile(resolve(out,`${name}-mismatch-native.json`),line.value);
      await writeFile(resolve(out,`${name}-mismatch-wasm.json`),wasmRaw);
      assert.equal(line.value,wasmRaw,`${name} raw response ${calls.length}: ${q.op}`);
    }
    bytes+=Buffer.byteLength(wasmRaw);const parsed=JSON.parse(wasmRaw);
    if(q.op==='littoral_order'&&q.company_id==='not-owned')assert.equal(parsed.ok,false);
    else assert.equal(parsed.ok,true,`${name}: ${q.op} ${parsed.error??''}`);
    if(parsed.data?.ships)view=parsed.data;
    return parsed;
  };
  try{
    await call(structuredClone(request));await play(call,()=>view);
    const saved=(await call({op:'save'})).data;const finalView=JSON.stringify(view);
    await call({op:'load',save:saved});assert.equal(JSON.stringify(view),finalView,`${name} exact native saved-frame rebuild`);
    await call({op:'replay',save:saved});assert.equal(JSON.stringify(view),finalView,`${name} exact native replay`);
    await writeFile(resolve(out,`${name}-commands.json`),JSON.stringify(calls,null,2));
    cases.push({name,requests:calls.length,bytes,terminal_tick:view.tick,result:view.result?{success:view.result.success,abandoned:view.result.abandoned,searched_ruins:view.result.searched_ruins}:null,commands_sha256:hash(Buffer.from(JSON.stringify(calls))),raw_identical:true});
  }finally{p.stdin.end();}
}
await scenario('01-multi-search-and-recovery',base,async(call,get)=>{
  await call(toggle());await call({op:'step',seconds:120});
  assert.equal(get().result?.success,true);assert.equal(get().result.searched_ruins,3);assert.equal(get().result.companies.length,10);
});
await scenario('02-mid-save-resume',base,async(call,get)=>{
  await call(toggle());await call({op:'step',seconds:30});const saved=(await call({op:'save'})).data;
  await call({op:'replay',save:saved,tick:12});await call({op:'load',save:saved});await call({op:'step',seconds:50});assert.equal(get().result?.success,true);
});
await scenario('03-manual-takeover',base,async(call,get)=>{
  await call(toggle());await call({op:'step',seconds:12});await call({op:'littoral_order',company_id:'not-owned',action:'retreat'});assert.equal(get().littoral.autonomy.enabled,true);
  await call({op:'littoral_ship_order',ship:1,action:'hold'});assert.equal(get().littoral.autonomy.enabled,false);
  await call(toggle());await call(toggle({enabled:false}));await call({op:'step',seconds:3});assert.equal(get().littoral.autonomy.enabled,false);
});
const carrier=structuredClone(base);delete carrier.company_layout;carrier.seed=44;carrier.lesson='sea_control';carrier.roster=['MCP-001','MCP-034'];carrier.ships=[{id:'CAS-H-USN-ENTERPRISE-1942',hp:100,ammo:0}];
await scenario('04-carrier-zero-gun-ammo',carrier,async(call,get)=>{
  await call(toggle());await call({op:'step',seconds:200});assert.equal(get().result?.success,true);
  assert.ok(get().littoral.aviation.squadrons.some(s=>s.ammunition<18));assert.equal(get().littoral.aviation.aircraft.length,0);
});
const salvage=structuredClone(base);salvage.mode='salvage';delete salvage.lesson;
await scenario('05-early-real-withdrawal',salvage,async(call,get)=>{
  await call(toggle({posture:'withdraw'}));await call({op:'step',seconds:120});assert.equal(get().result?.success,false);assert.equal(get().result.abandoned,true);
});
const damaged=structuredClone(base);damaged.ships.forEach(s=>s.hp=20);damaged.unit_condition=damaged.roster.map(id=>({id,hp:20}));
await scenario('06-damaged-fleet-safety',damaged,async(call,get)=>{
  await call(toggle());await call({op:'step',seconds:120});assert.equal(get().result?.success,false);assert.ok(get().result.ships.every(s=>s.hp_percent<=20));
});
const combined=structuredClone(base);combined.lesson='combined';
await scenario('07-combined-arms-lesson',combined,async(call,get)=>{
  await call(toggle());await call({op:'step',seconds:200});assert.equal(get().result?.success,true);assert.ok(get().result.shore_support_hits>0);
});
const defense=structuredClone(base);defense.mode='defense';delete defense.lesson;
await scenario('08-hq-defense',defense,async(call,get)=>{
  await call(toggle());await call({op:'step',seconds:200});assert.equal(get().result?.success,true);assert.equal(get().result.objective_complete,true);
});
const raid=structuredClone(base);raid.mode='raid';delete raid.lesson;
await scenario('09-outmatched-raid-withdrawal',raid,async(call,get)=>{
  await call(toggle());await call({op:'step',seconds:240});assert.equal(get().result?.success,false);assert.equal(get().result.abandoned,true);assert.equal(get().result.objective_complete,false);
});
const receipt={passed:true,native,native_sha256:hash(await readFile(native)),native_mtime:(await stat(native)).mtime.toISOString(),wasm:wasmPath,wasm_sha256:hash(wasm),wasm_mtime:(await stat(wasmPath)).mtime.toISOString(),cases,requests:cases.reduce((sum,c)=>sum+c.requests,0),raw_identical_bytes:cases.reduce((sum,c)=>sum+c.bytes,0),scope:'nine explicit combined-autonomy scenarios; every native/WASM response compared byte-for-byte, including dynamic save/load/replay; no account access'};
await writeFile(resolve(out,'receipt.json'),JSON.stringify(receipt,null,2));console.log(JSON.stringify(receipt));
