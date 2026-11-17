import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';

const root=resolve(import.meta.dirname,'..');
const native=resolve(root,'target/release/cas-sim.exe');
const wasm=await readFile(resolve(root,'target/wasm32-unknown-unknown/release/cas_core.wasm'));
const output=resolve(root,'artifacts/growth');
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
const hull={id:'IBS-U-USN-FLETCHER',hp:100,ammo:100,level:30,mastery:1000,equipment:true,equipment_bonus_bp:100,command:true,crew:{command:{primary:'command',primary_bp:18,secondary:'hp',secondary_bp:7}}};
const owned={content:'salvage-v2',owned_growth:'cas-owned-growth-v1',weather:'salvage-weather-v1',fleet:[hull]};
for(const seed of [42,6106,0xffffffff])await verify(`resource-${seed}`,ask=>{
 let view=ask({op:'new_salvage',seed,start:{...owned,mission:{kind:'resources',id:'equipment',loot_kind:'equipment'}}});
 assert.equal(view.variant,'salvage-v2');assert.equal(view.salvage.ruins.length,3);
 ask({op:'route',fleet:1,mode:'follow',speed:6,points:[{x:3000,y:2200}]});
 view=ask({op:'step',seconds:60});assert.ok(view.salvage.ships[0].practice>=1);
 ask({op:'salvage_collect',ruin:1});view=ask({op:'step',seconds:6});assert.equal(view.salvage.loot.equipment,1);
 const save=ask({op:'save'});assert.equal(canonical(ask({op:'load',save})),canonical(view));
 ask({op:'salvage_extract',exit:0});view=ask({op:'step',seconds:12});assert.equal(view.salvage.extracted,true);
 const final=ask({op:'save'});assert.equal(canonical(ask({op:'replay',save:final})),canonical(view));
 return {actualExtraction:true,practice:view.salvage.ships[0].practice,savedGrowth:final.salvage.owned_growth};
});
const catalog=JSON.parse(await readFile(resolve(root,'godot/data/ships.json'),'utf8'));
const records=Array.isArray(catalog)?catalog:Object.values(catalog).find(v=>Array.isArray(v)&&v[0]?.id);
const identities=records.filter(s=>s.playable&&s.id.startsWith('IBS-U-USN-')).slice(0,15).map(s=>s.id);
assert.equal(identities.length,15);
await verify('fifteen-hulls-two-real-fleets',ask=>{
 let view=ask({op:'new_salvage',seed:42,start:{...owned,fleet:identities.map(id=>({...hull,id})),groups:[{id:'one',name:'一队',ships:identities.slice(0,8)},{id:'two',name:'二队',ships:identities.slice(8)}]}});
 assert.equal(view.ships.length,15);assert.equal(view.fleets.length,2);
 for(const ship of view.ships)assert.ok(ship.x>0&&ship.x<view.width&&ship.y>0&&ship.y<view.height);
 for(const fleet of view.fleets){const leader=view.ships.find(s=>s.id===fleet.leader);ask({op:'route',fleet:fleet.id,mode:'follow',speed:6,points:[{x:leader.x+1000,y:leader.y}]});}
 view=ask({op:'step',seconds:60});const save=ask({op:'save'});assert.equal(canonical(ask({op:'replay',save})),canonical(view));
 assert.equal(view.salvage.exits[0].shape,'rectangle');
 ask({op:'salvage_collect',ruin:1});view=ask({op:'step',seconds:6});assert.equal(view.salvage.loot.scrap,5);
 ask({op:'salvage_extract',exit:0});view=ask({op:'step',seconds:12});assert.equal(view.salvage.extracted,true);assert.equal(view.salvage.ships.length,15);
 assert.equal(canonical(ask({op:'replay',save:ask({op:'save'})})),canonical(view));
 return {hulls:15,fleets:2,allInsideField:true,independentRouteCommands:true,actualFullFleetCargoExtraction:true,extractionBounds:view.salvage.exits[0].bounds};
});
for(const seed of [0,1,2,3])await verify(`synchronized-${seed}`,ask=>{
 let view=ask({op:'new_salvage',seed,start:owned});
 const command={op:'route',fleet:1,mode:'sync',speed:6,points:[{x:3000,y:2200}]};
 const preview=ask({...command,op:'preview_route'});assert.equal(preview.executionChance,0.3518);
 view=ask(command);const failed=view.events.some(e=>e.kind==='command_failed');
 const save=ask({op:'save'});assert.equal(canonical(ask({op:'load',save})),canonical(view));
 view=ask({op:'step',seconds:20});ask({...command,points:[{x:3500,y:2200}]});
 const last=ask({op:'observe'});assert.equal(canonical(ask({op:'replay',save:ask({op:'save'})})),canonical(last));
 return {executionChance:preview.executionChance,firstFailed:failed,cooldownSeconds:20};
});
for(const budget of [1000,2000,3000,5000])await verify(`ladder-${budget}`,ask=>{
 let view=ask({op:'new_salvage',seed:42,start:{...owned,mission:{kind:'ladder',id:`ladder-${budget}`,player_budget:budget,enemy_budget:budget*1.5,loot_kind:'scrap'}}});
 view=ask({op:'step',seconds:400});const save=ask({op:'save'});assert.equal(canonical(ask({op:'replay',save})),canonical(view));
 return {budget,enemyBudget:budget*1.5,actualTicks:view.tick};
});
await verify('owned-campaign-exercise',ask=>{
 let view=ask({op:'new_campaign',id:'CAMP-ALLIES-02',difficulty:'story',seed:42,groups:[{position:0,ships:[hull.id]}],ownedGrowth:{version:'cas-owned-growth-v1',hulls:[hull]}});
 assert.equal(view.ownedGrowth.scope,'自有舰战役演练');view=ask({op:'step',seconds:240});
 assert.ok(view.ownedGrowth.ships[0].practice>0);const save=ask({op:'save'});assert.equal(save.campaign.ownedGrowth.version,'cas-owned-growth-v1');
 assert.equal(canonical(ask({op:'load',save})),canonical(view));assert.equal(canonical(ask({op:'replay',save})),canonical(view));
 return {stage:'CAMP-ALLIES-02',practice:view.ownedGrowth.ships[0].practice,historicalStarsSeparate:true};
});
const receipt={date:'2026-11-11',nativeWasmCanonicalMatch:true,nativeSha256:createHash('sha256').update(await readFile(native)).digest('hex'),wasmSha256:createHash('sha256').update(wasm).digest('hex'),cases};
await writeFile(resolve(output,'parity.json'),JSON.stringify(receipt,null,2));console.log(JSON.stringify({passed:cases.length,cases},null,2));
