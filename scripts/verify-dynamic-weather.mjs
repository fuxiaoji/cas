import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';

const root=resolve(import.meta.dirname,'..');
const native=resolve(root,'target/release/cas-sim.exe');
const wasm=await readFile(resolve(root,'target/wasm32-unknown-unknown/release/cas_core.wasm'));
const output=resolve(root,'artifacts/weather');
const enc=new TextEncoder(),dec=new TextDecoder();
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a<b?-1:a>b?1:0)):x);
const start={content:'salvage-v1',fleet:[{id:'IBS-U-USN-FLETCHER',hp:100,ammo:100,level:1}]};
const cases=[];
async function verify(name,build){
 const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports;
 const requests=[],responses=[];
 const ask=request=>{
  requests.push(request);
  const bytes=enc.encode(JSON.stringify(request)),ptr=api.cas_alloc(bytes.length)>>>0;
  new Uint8Array(api.memory.buffer,ptr,bytes.length).set(bytes);
  const result=api.cas_request(ptr,bytes.length)>>>0;
  const response=JSON.parse(dec.decode(new Uint8Array(api.memory.buffer,result,api.cas_response_len()>>>0)));
  assert.equal(response.ok,true,`${name}: ${JSON.stringify(response)}`);
  responses.push(response);return response.data;
 };
 const details=build(ask);
 const proc=spawnSync(native,[],{input:requests.map(JSON.stringify).join('\n')+'\n',encoding:'utf8',maxBuffer:64*1024*1024});
 assert.equal(proc.status,0,proc.stderr);
 const actual=proc.stdout.trim().split(/\r?\n/).map(JSON.parse);
 assert.equal(actual.length,responses.length);
 for(let i=0;i<actual.length;i++)assert.equal(canonical(actual[i]),canonical(responses[i]),`${name} request ${i} ${requests[i].op}`);
 const report={name,requests:requests.length,nativeWasmCanonicalMatch:true,transcriptSha256:createHash('sha256').update(canonical(responses)).digest('hex'),...details};
 cases.push(report);
 await writeFile(resolve(output,`${name}-commands.json`),JSON.stringify(requests,null,2));
}
await mkdir(output,{recursive:true});
for(const seed of [42,6106,0xffffffff])await verify(`dynamic-${seed}`,ask=>{
 let view=ask({op:'new_salvage',seed,start});
 assert.equal(view.weather.kind,'clear');
 assert.equal(view.weather.rules_change_tick,240);
 const frames=[];
 for(const tick of [194,195,215,239,240,435,479,480,675,719,720,915,959,960]){
  view=ask({op:'step',seconds:tick-view.tick});
  assert.equal(view.tick,tick);
  const paused=ask({op:'observe'});
  assert.equal(canonical(paused),canonical(view),'observing a paused world does not change weather');
  const save=ask({op:'save'});
  assert.equal(save.salvage.weather,'salvage-weather-v1');
  assert.equal(canonical(ask({op:'load',save})),canonical(view),'save/load during transition retains exact weather and battle');
  assert.equal(canonical(ask({op:'replay',save})),canonical(view),'replay retains weather and battle');
  assert.equal(view.environment.visibility,view.weather.visibility);
  frames.push({tick,environment:view.environment,weather:view.weather});
 }
 assert.equal(frames.find(f=>f.tick===239).weather.kind,'clear');
 assert.equal(frames.find(f=>f.tick===240).weather.kind,'cloudy');
 assert.ok(frames.some(f=>f.weather.kind==='rain'||f.weather.kind==='fog'),'actual voyage reaches obscured weather');
 const save=ask({op:'save'});
 const preview=ask({op:'replay',save,tick:239});
 assert.equal(preview.weather.kind,'clear');
 assert.equal(canonical(ask({op:'observe'})),canonical(view),'preview replay never overwrites current live world');
 return {actualTicks:frames.map(f=>f.tick),kinds:[...new Set(frames.map(f=>f.weather.kind))],pausedReadOnly:true,loadAndReplayMatch:true,frames};
});
// Captured from the pre-weather executable before replacing it. This checks
// real compatibility, not merely two executions of the changed constructor.
const legacy=JSON.parse(await readFile(resolve(output,'legacy-baseline.json'),'utf8'));
for(const row of legacy)await verify(`legacy-${row.seed}`,ask=>{
 const view=ask({op:'load',save:row.save});
 assert.equal(canonical(view),canonical(row.view),'old executable snapshot must be unchanged');
 assert.ok(!('weather' in view));
 const end=ask({op:'step',seconds:241}),save=ask({op:'save'});
 assert.ok(!('weather' in save.salvage));
 assert.equal(end.environment.visibility,100);
 assert.equal(canonical(ask({op:'replay',save})),canonical(end));
 return {preWeatherExecutableMatch:true,oldSaveStayedFixed:true,replayMatch:true};
});
const receipt={date:'2026-11-11',nativeWasmCanonicalMatch:true,
 nativeSha256:createHash('sha256').update(await readFile(native)).digest('hex'),
 wasmSha256:createHash('sha256').update(wasm).digest('hex'),cases};
await writeFile(resolve(output,'receipt.json'),JSON.stringify(receipt,null,2));
console.log(JSON.stringify({nativeWasmCanonicalMatch:true,cases:cases.map(({frames,...summary})=>summary)},null,2));
