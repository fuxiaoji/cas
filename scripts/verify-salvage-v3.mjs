import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/v3');
const native=resolve(root,'target/release/cas-sim.exe'),wasm=await readFile(resolve(root,'target/wasm32-unknown-unknown/release/cas_core.wasm'));
const enc=new TextEncoder(),dec=new TextDecoder();
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a<b?-1:a>b?1:0)):x);
await mkdir(out,{recursive:true});const cases=[];
async function verify(name,build){
 const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports,requests=[],responses=[];
 const ask=q=>{requests.push(q);const bytes=enc.encode(JSON.stringify(q)),p=api.cas_alloc(bytes.length)>>>0;new Uint8Array(api.memory.buffer,p,bytes.length).set(bytes);const r=api.cas_request(p,bytes.length)>>>0;const response=JSON.parse(dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0)));responses.push(response);assert.equal(response.ok,true,`${name}: ${JSON.stringify(response)}`);return response.data;};
 const detail=build(ask);
 const proc=spawnSync(native,[],{input:requests.map(JSON.stringify).join('\n')+'\n',encoding:'utf8',maxBuffer:128*1024*1024});assert.equal(proc.status,0,proc.stderr);
 const actual=proc.stdout.trim().split(/\r?\n/).map(JSON.parse);assert.equal(canonical(actual),canonical(responses),name+' native/WASM');
 await writeFile(resolve(out,name+'-commands.json'),JSON.stringify(requests,null,2));
 const row={name,requests:requests.length,nativeWasmCanonicalMatch:true,transcriptSha256:createHash('sha256').update(canonical(responses)).digest('hex'),...detail};cases.push(row);console.log(JSON.stringify(row));
}
const start={content:'salvage-v3',owned_growth:'cas-owned-growth-v1',fleet:[{id:'IBS-U-USN-FLETCHER',hp:100,ammo:100,level:0}]};
for(const seed of [40,41,42,43]) await verify(`terrain-${seed}`,ask=>{
 let v=ask({op:'new_salvage',seed,start});assert.equal(v.salvage.generatorVersion,'archipelago-3');const geometry=canonical(v.islands);
 assert.equal(canonical(ask({op:'new_salvage',seed,start}).islands),geometry);
 ask({op:'salvage_collect',ruin:1});v=ask({op:'step',seconds:6});assert.equal(v.salvage.loot.scrap,5);
 const save=ask({op:'save'});assert.equal(canonical(ask({op:'load',save})),canonical(v));
 ask({op:'salvage_extract',exit:0});v=ask({op:'step',seconds:12});assert.equal(v.result.primary,true);
 assert.equal(canonical(ask({op:'replay',save:ask({op:'save'})})),canonical(v));
 return {theme:v.salvage.terrainTheme,islands:v.islands.length,landmarks:v.salvage.landmarks.length,actualCargoExtraction:true};
});
for(const id of ['c1-breakout','c1-salvage','c1-boss']) await verify(id,ask=>{
 let v=ask({op:'new_chapter',seed:6109,id});assert.equal(v.chapter.status,'active');assert.equal(v.ships.length,5);
 const route=id==='c1-breakout'?[{x:7400,y:1200},{x:7400,y:2200}]:[{x:id==='c1-boss'?8000:7600,y:id==='c1-boss'?1200:2200}];
 ask({op:'route',fleet:1,mode:'follow',speed:id==='c1-boss'?24:20,points:route});
 v=ask({op:'step',seconds:180});const save=ask({op:'save'});assert.equal(save.salvage.chapter_version,'chapter-01-v1');assert.equal(canonical(ask({op:'load',save})),canonical(v));
 let seenWarning=false,seenPhase=1;
 const target=id==='c1-breakout'?800:id==='c1-salvage'?700:1000;
 while(v.tick<target&&!v.result){v=ask({op:'step',seconds:Math.min(20,target-v.tick)});seenWarning ||= v.salvage.telegraphs.length>0;for(const c of v.contacts)seenPhase=Math.max(seenPhase,c.phase||1);}
 if(id==='c1-salvage')for(let i=0;i<6&&!v.salvage.cargo.includes('archive');i++){ask({op:'salvage_collect',ruin:1});v=ask({op:'step',seconds:8});}
 if(id!=='c1-boss'){ask({op:'salvage_extract',exit:0});v=ask({op:'step',seconds:12});}
 assert.equal(v.chapter.status,'won');assert.equal(v.result.primary,true);assert.equal(v.result.winner,'allies');
 assert.ok(v.chapter.events.includes(id==='c1-breakout'?'beacon_reached':id==='c1-salvage'?'archive_recovered':'boss_defeated'));
 if(id==='c1-breakout')assert.ok(v.chapter.events.includes('aversion_spared_flagship'));
 if(id==='c1-boss'){assert.ok(seenPhase>=2);assert.ok(v.chapter.events.includes('gatekeepers_control_link'));assert.ok(seenWarning);}
 const final=ask({op:'save'});assert.equal(canonical(ask({op:'replay',save:final})),canonical(v));
 return {stage:id,tick:v.tick,result:v.result,events:v.chapter.events,survivors:v.ships.length,actualWarnings:seenWarning,maxPhase:seenPhase};
});
await verify('boss-third-phase',ask=>{let v=ask({op:'new_chapter',seed:6109,id:'c1-boss'});ask({op:'route',fleet:1,mode:'follow',speed:24,points:[{x:10000,y:2200}]});let third=false,barrage=false;while(!v.result&&v.tick<1600){v=ask({op:'step',seconds:10});third ||= v.contacts.some(c=>c.species==='leviathan'&&c.phase===3);barrage ||= v.salvage.telegraphs.filter(t=>t.kind==='barrage').length>=3;}assert.ok(third);assert.ok(barrage);assert.equal(v.result?.primary,true);assert.equal(canonical(ask({op:'replay',save:ask({op:'save'})})),canonical(v));return {tick:v.tick,actualThirdPhase:true,threeAuthoritativeTelegraphs:true};});
await verify('boss-real-defeat',ask=>{let v=ask({op:'new_chapter',seed:6109,id:'c1-boss'});while(!v.result)v=ask({op:'step',seconds:180});assert.equal(v.chapter.status,'lost');assert.equal(v.result.primary,false);assert.equal(canonical(ask({op:'replay',save:ask({op:'save'})})),canonical(v));return {tick:v.tick,actualDefeat:true};});
const frozen=JSON.parse(await readFile(resolve(out,'frozen-baseline.json'),'utf8'));
const old=spawnSync(native,[],{input:frozen.requests.map(JSON.stringify).join('\n')+'\n',encoding:'utf8'});assert.equal(old.status,0);assert.equal(canonical(old.stdout.trim().split(/\r?\n/).map(JSON.parse)),canonical(frozen.responses));
const receipt={passed:cases.length,oldV1V2FrozenBaseline:true,nativeWasmCanonicalMatch:true,cases,nativeSha256:createHash('sha256').update(await readFile(native)).digest('hex'),wasmSha256:createHash('sha256').update(wasm).digest('hex')};
await writeFile(resolve(out,'parity.json'),JSON.stringify(receipt,null,2));console.log(JSON.stringify({passed:cases.length,oldV1V2FrozenBaseline:true}));
