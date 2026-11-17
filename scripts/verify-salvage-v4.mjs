import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/v4');
const native=process.env.CAS_V4_NATIVE||resolve(root,'target/release/cas-sim.exe');
const wasm=await readFile(resolve(root,'target/wasm32-unknown-unknown/release/cas_core.wasm'));
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a.localeCompare(b,'en'))):x);
const enc=new TextEncoder(),dec=new TextDecoder(),cases=[];await mkdir(out,{recursive:true});
const start=(difficulty='calm',environment='atoll',level=1,ship='IBS-U-USN-FLETCHER',ammo=50,torpedoes=false)=>({content:'salvage-v4',fleet:[{id:ship,hp:100,ammo,level:0}],mission:{kind:'salvage',id:difficulty,loot_kind:'scrap'},cargo_v4:{commander_level:level,difficulty,environment,weather:'clear',loadouts:{[ship]:{torpedoes}}}});
async function verify(name,run){
 const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports,requests=[],responses=[];
 function raw(q){requests.push(q);const bytes=enc.encode(JSON.stringify(q)),p=api.cas_alloc(bytes.length)>>>0;new Uint8Array(api.memory.buffer,p,bytes.length).set(bytes);const r=api.cas_request(p,bytes.length)>>>0;const a=JSON.parse(dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0)));responses.push(a);return a;}
 const ask=q=>{const a=raw(q);assert.equal(a.ok,true,`${name}: ${JSON.stringify(a)}`);return a.data;};
 const detail=run(ask,raw);
 const proc=spawnSync(native,[],{input:requests.map(JSON.stringify).join('\n')+'\n',encoding:'utf8',maxBuffer:128*1024*1024});assert.equal(proc.status,0,proc.stderr);
 assert.equal(canonical(proc.stdout.trim().split(/\r?\n/).map(JSON.parse)),canonical(responses),name+' native / WASM');
 const row={name,requests:requests.length,nativeWasmCanonicalMatch:true,sha256:createHash('sha256').update(canonical(responses)).digest('hex'),...detail};cases.push(row);
 await writeFile(resolve(out,name+'-commands.json'),JSON.stringify(requests,null,2));console.log(JSON.stringify(row));
}
for(const difficulty of ['calm','standard','hazard'])for(const environment of ['atoll','fractured','fjord','drowned_city'])await verify(`${difficulty}-${environment}`,ask=>{
 const v=ask({op:'new_salvage',seed:40,start:start(difficulty,environment)});
 assert.equal(v.salvage.generatorVersion,'archipelago-4');assert.equal(v.salvage.terrainTheme,environment);
 assert.equal(v.salvage.enemyBudgetHulls,{calm:3,standard:7,hazard:11}[difficulty]);assert.equal(v.salvage.searchDuration,{calm:8,standard:12,hazard:16}[difficulty]);
 assert.equal(canonical(ask({op:'new_salvage',seed:40,start:start(difficulty,environment)})),canonical(v));
 return {enemies:v.salvage.enemyBudgetHulls,searchSeconds:v.salvage.searchDuration,islands:v.islands.length};
});
await verify('real-voyage-packing-extraction', (ask,raw)=>{
 let v=ask({op:'new_salvage',seed:40,start:start()});assert.equal(v.salvage.ships[0].ammo,50);assert.equal(v.ships[0].ammo,0);
 const x=v.ships[0].x,y=v.ships[0].y;
 ask({op:'route',fleet:1,mode:'follow',speed:6,points:[{x:x+400,y}]});v=ask({op:'step',seconds:60});assert.ok(Math.hypot(v.ships[0].x-x,v.ships[0].y-y)>10,'actual navigation');
 ask({op:'search_salvage',ruin:1});v=ask({op:'step',seconds:2});assert.equal(v.salvage.cargo_grid.items.length,1);assert.equal(v.salvage.cargo.length,0);
 let saved=ask({op:'save'});assert.equal(canonical(ask({op:'load',save:saved})),canonical(v));assert.equal(canonical(ask({op:'replay',save:saved})),canonical(v));
 ask({op:'cancel_search'});v=ask({op:'step',seconds:2});assert.equal(v.salvage.cargo_grid.items.length,1);
 ask({op:'search_salvage',ruin:1});v=ask({op:'step',seconds:8});assert.equal(v.salvage.cargo_grid.items.length,4);assert.equal(v.salvage.cargo.length,0);
 assert.equal(raw({op:'search_salvage',ruin:1}).ok,false);
 const place=(item,x,y,rotation)=>({op:'cargo_place',item,x,y,rotation});
 v=ask(place('v4-1-0',7,0,1));assert.deepEqual(v.salvage.cargo_grid.items[0].placement,[7,0,1]);
 const before=canonical(v.salvage.cargo_grid);assert.equal(raw(place('v4-1-1',7,0,0)).ok,false);v=ask({op:'observe'});assert.equal(canonical(v.salvage.cargo_grid),before);
 assert.equal(raw(place('v4-1-0',8,0,0)).ok,false);v=ask(place('v4-1-1',0,0,1));
 ask({op:'cargo_sort'});v=ask({op:'cargo_drop',item:'v4-1-0'});assert.equal(v.salvage.cargo.length,1);assert.equal(raw(place('v4-1-0',0,0,0)).ok,false);
 saved=ask({op:'save'});assert.equal(canonical(ask({op:'load',save:saved})),canonical(v));
 ask({op:'salvage_extract',exit:0});v=ask({op:'step',seconds:12});assert.equal(v.salvage.extracted,true);assert.equal(v.salvage.cargo.length,1);assert.equal(v.result.primary,true);
 assert.equal(canonical(ask({op:'replay',save:ask({op:'save'})})),canonical(v));return {tick:v.tick,extractedItems:v.salvage.cargo,actualNavigation:true,partialSearchReload:true,invalidMovesAtomic:true,discardPermanent:true};
});
await verify('capacity-loadout-transport',ask=>{
 const budget=s=>ask({op:'new_salvage',seed:40,start:s}).salvage.cargo_grid;
 const heavy=budget(start('calm','atoll',1,'IBS-U-USN-FLETCHER',100,true));
 const light=budget(start()),senior=budget(start('calm','atoll',5)),transport=budget(start('calm','atoll',1,'IBS-U-IJN-MONCHIZUKI',100,true));
 assert.equal(light.max_kg-heavy.max_kg,330);assert.ok(senior.max_kg>light.max_kg);assert.equal(transport.ships[0].kind,'DD');assert.equal(transport.ships[0].transport,true);assert.ok(transport.max_kg>heavy.max_kg);
 return {fullKg:heavy.max_kg,lightKg:light.max_kg,level5Kg:senior.max_kg,registeredTransportKg:transport.max_kg,transportCombatKindUnchanged:true};
});
await verify('actual-voyage-failure',ask=>{
 ask({op:'new_salvage',seed:40,start:start()});ask({op:'route',fleet:1,mode:'follow',speed:6,points:[{x:2600,y:2200}]});ask({op:'step',seconds:60});ask({op:'search_salvage',ruin:1});ask({op:'step',seconds:8});ask({op:'cargo_place',item:'v4-1-0',x:0,y:0,rotation:0});
 let v=ask({op:'salvage_abandon'});assert.equal(v.result.primary,false);assert.equal(v.salvage.extracted,false);assert.equal(canonical(ask({op:'replay',save:ask({op:'save'})})),canonical(v));return {actualFailure:true,unextractedCargoNotReward:true};
});
const frozenRequests=[{op:'new_salvage',seed:42,start:{content:'salvage-v1',fleet:[{id:'IBS-U-USN-FLETCHER',hp:100,ammo:100,level:1}]}},{op:'step',seconds:6},{op:'save'},{op:'new_salvage',seed:40,start:{content:'salvage-v2',fleet:[{id:'IBS-U-USN-FLETCHER',hp:100,ammo:100,level:0}]}},{op:'step',seconds:12},{op:'save'},{op:'new_salvage',seed:40,start:{content:'salvage-v3',fleet:[{id:'IBS-U-USN-FLETCHER',hp:100,ammo:100,level:0}]}},{op:'salvage_collect',ruin:1},{op:'step',seconds:6},{op:'salvage_extract',exit:0},{op:'step',seconds:12},{op:'save'},{op:'new_campaign',id:'CAMP-ALLIES-03',difficulty:'story',seed:6106},{op:'step',seconds:30},{op:'save'}];
const runBinary=path=>{const p=spawnSync(path,[],{input:frozenRequests.map(JSON.stringify).join('\n')+'\n',encoding:'utf8',maxBuffer:128*1024*1024});assert.equal(p.status,0);return p.stdout.trim().split(/\r?\n/).map(JSON.parse);};
const frozen=runBinary(resolve(root,'target/cargo-v4-baseline/cas-sim.exe')),current=runBinary(native);assert.equal(canonical(current),canonical(frozen),'old v1/v2/v3/historical frozen bytes');
const report={passed:cases.length,nativeWasmCanonicalMatch:true,oldV1V2V3HistoricalFrozen:true,frozenCommands:frozenRequests.length,native,sha256:createHash('sha256').update(await readFile(native)).digest('hex'),cases};await writeFile(resolve(out,'parity.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({passed:cases.length,oldFrozen:true}));


