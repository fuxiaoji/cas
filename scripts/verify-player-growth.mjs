import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/growth/progression');
const native=resolve(root,'target/release/cas-sim.exe');
const wasm=await readFile(resolve(root,'target/wasm32-unknown-unknown/release/cas_core.wasm'));
const oldNative=resolve(root,'artifacts/growth/frozen-backend/cas-sim.exe');
const oldWasm=await readFile(resolve(root,'artifacts/growth/frozen-backend/cas_core.wasm'));
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a<b?-1:a>b?1:0)):x);
const enc=new TextEncoder(),dec=new TextDecoder(),cases=[];
await mkdir(out,{recursive:true});
async function session(bytes){
 const {instance}=await WebAssembly.instantiate(bytes,{}),api=instance.exports;
 return q=>{const bytes=enc.encode(JSON.stringify(q)),p=api.cas_alloc(bytes.length)>>>0;new Uint8Array(api.memory.buffer,p,bytes.length).set(bytes);const r=api.cas_request(p,bytes.length)>>>0;return JSON.parse(dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0)));};
}
async function verify(name,build,frozen=false){
 const requests=[],responses=[],call=await session(wasm);
 const ask=(q,allowError=false)=>{requests.push(q);const r=call(q);responses.push(r);if(!allowError)assert.equal(r.ok,true,`${name}: ${JSON.stringify(r)}`);return allowError?r:r.data;};
 const detail=build(ask);
 const proc=spawnSync(native,[],{input:requests.map(JSON.stringify).join('\n')+'\n',encoding:'utf8',maxBuffer:128*1024*1024});assert.equal(proc.status,0,proc.stderr);
 assert.equal(canonical(proc.stdout.trim().split(/\r?\n/).map(JSON.parse)),canonical(responses),name+' native/WASM');
 if(frozen){
  const previous=spawnSync(oldNative,[],{input:requests.map(JSON.stringify).join('\n')+'\n',encoding:'utf8',maxBuffer:128*1024*1024});assert.equal(previous.status,0,previous.stderr);
  assert.equal(canonical(previous.stdout.trim().split(/\r?\n/).map(JSON.parse)),canonical(responses),name+' previous native');
  const oldCall=await session(oldWasm);assert.equal(canonical(requests.map(oldCall)),canonical(responses),name+' previous WASM');
 }
 const row={name,requests:requests.length,nativeWasmCanonicalMatch:true,frozenOldNativeAndWasm:frozen,sha256:createHash('sha256').update(canonical(responses)).digest('hex'),...detail};cases.push(row);
 await writeFile(resolve(out,name+'-commands.json'),JSON.stringify(requests,null,2));console.log(JSON.stringify(row));
}
const hull={id:'IBS-U-USN-FLETCHER',hp:100,ammo:100,level:0};
const start={content:'salvage-v3',owned_growth:'cas-owned-growth-v1',fleet:[hull]};
for(const content of ['salvage-v1','salvage-v2','salvage-v3']) await verify('frozen-'+content,ask=>{
 let v=ask({op:'new_salvage',seed:42,start:{content,fleet:[{...hull,level:1}]}});
 ask({op:'route',fleet:1,mode:'follow',speed:6,points:[{x:3000,y:2200}]});v=ask({op:'step',seconds:60});
 const save=ask({op:'save'});
 assert.equal(canonical(ask({op:'replay',save})),canonical(v));return {tick:v.tick};
},true);
for(const profile of ['fire_control','propulsion','bulkhead','balanced','ballistics']) await verify('gear-'+profile,ask=>{
 let v=ask({op:'new_salvage',seed:42,start:{...start,fleet:[{...hull,equipment_bonus_bp:100,equipment_profile:profile}]}});
 assert.equal(v.salvage.ships.length,1);v=ask({op:'step',seconds:90});const save=ask({op:'save'});
 assert.equal(save.salvage.fleet[0].equipment_profile,profile);
 assert.equal(canonical(ask({op:'load',save})),canonical(v));assert.equal(canonical(ask({op:'replay',save})),canonical(v));
 return {profile,tick:v.tick};
});
for(const tier of [1,2,3]) await verify('resource-tier-'+tier,ask=>{
 const id=tier===1?'training':`training-t${tier}`,cache=[3000,4800,5800][tier-1];
 let v=ask({op:'new_salvage',seed:42,start:{...start,mission:{kind:'resources',id,loot_kind:'alloy'}}});
 if(tier>1) assert.equal(ask({op:'salvage_extract',exit:0},true).ok,false,'empty hold blocked');
 ask({op:'route',fleet:1,mode:'follow',speed:30,points:[{x:cache-500,y:2200}]});
 let collected=false;
 for(let i=0;i<60;i++){
  if(ask({op:'salvage_collect',ruin:1},true).ok){v=ask({op:'step',seconds:6});if(v.salvage.loot.alloy>0){collected=true;break;}}
  v=ask({op:'step',seconds:10});
 }
 assert.equal(collected,true);ask({op:'salvage_extract',exit:0});v=ask({op:'step',seconds:12});assert.equal(v.salvage.extracted,true);
 const save=ask({op:'save'});assert.equal(canonical(ask({op:'replay',save})),canonical(v));
 return {tier,tick:v.tick,actualExtraction:true,creatures:v.salvage.enemyBudgetHulls};
});
await verify('typed-campaign',ask=>{
 let v=ask({op:'new_campaign',id:'CAMP-ALLIES-02',difficulty:'story',seed:42,groups:[{position:0,ships:[hull.id]}],ownedGrowth:{version:'cas-owned-growth-v1',hulls:[{...hull,equipment_bonus_bp:100,equipment_profile:'ballistics'}]}});
 v=ask({op:'step',seconds:120});const save=ask({op:'save'});assert.equal(canonical(ask({op:'replay',save})),canonical(v));return {tick:v.tick};
});
const result={passed:cases.length,cases,nativeSha256:createHash('sha256').update(await readFile(native)).digest('hex'),wasmSha256:createHash('sha256').update(wasm).digest('hex')};
await writeFile(resolve(out,'parity.json'),JSON.stringify(result,null,2));console.log(JSON.stringify({passed:cases.length}));
