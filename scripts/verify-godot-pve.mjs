import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';

const root=resolve(import.meta.dirname,'..');
const native=resolve(root,'target/release/cas-sim.exe');
const wasmPath=resolve(root,'target/wasm32-unknown-unknown/release/cas_core.wasm');
const wasm=await readFile(wasmPath);
const enc=new TextEncoder(),dec=new TextDecoder();
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a<b?-1:a>b?1:0)):x);
const fleet=(count=1,extra={})=>['IBS-U-USN-FLETCHER','IBS-U-USN-PERKINS','IBS-U-USN-MAURY'].slice(0,count).map(id=>({id,hp:100,ammo:100,level:1,equipment:false,command:false,...extra}));
const cases=[];
async function run(name,build){
 const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports;
 const requests=[],outputs=[];
 const ask=request=>{
  requests.push(request);
  const bytes=enc.encode(JSON.stringify(request));const ptr=api.cas_alloc(bytes.length)>>>0;
  new Uint8Array(api.memory.buffer,ptr,bytes.length).set(bytes);
  const result=api.cas_request(ptr,bytes.length)>>>0;
  const response=JSON.parse(dec.decode(new Uint8Array(api.memory.buffer,result,api.cas_response_len()>>>0)));
  outputs.push(response);assert.equal(response.ok,true,`${name}: ${JSON.stringify(response)}`);return response.data;
 };
 const details=await build(ask);
 const proc=spawnSync(native,[],{input:requests.map(r=>JSON.stringify(r)).join('\n')+'\n',encoding:'utf8',maxBuffer:64*1024*1024});
 assert.equal(proc.status,0,proc.stderr);
 const actual=proc.stdout.trim().split(/\r?\n/).map(JSON.parse);
 assert.equal(actual.length,outputs.length);
 for(let i=0;i<actual.length;i++) { delete actual[i].serialized; assert.equal(canonical(actual[i]),canonical(outputs[i]),`${name} request ${i}: ${requests[i].op}`); }
 const result={name,commands:requests.length,nativeWasmCanonicalMatch:true,transcriptSha256:createHash('sha256').update(canonical(outputs)).digest('hex'),...details};
 cases.push(result);
 await mkdir(resolve(root,'artifacts/godot/pve'),{recursive:true});
 await writeFile(resolve(root,`artifacts/godot/pve/${name}-commands.json`),JSON.stringify(requests,null,2));
}
await run('collect-extract-resume',ask=>{
 ask({op:'new_salvage',seed:6106,start:{content:'salvage-v1',fleet:fleet()}});
 ask({op:'route',fleet:1,mode:'follow',speed:6,points:[{x:3700,y:2200}]});
 ask({op:'step',seconds:490});ask({op:'salvage_collect',ruin:1});
 const mid=ask({op:'step',seconds:6}),save=ask({op:'save'});
 assert.equal(canonical(ask({op:'load',save})),canonical(mid));
 ask({op:'step',seconds:6});
 ask({op:'route',fleet:1,mode:'follow',speed:6,points:[{x:4600,y:3200},{x:2600,y:3200},{x:2200,y:2200}]});
 ask({op:'step',seconds:1600});ask({op:'salvage_extract',exit:0});
 const end=ask({op:'step',seconds:20});assert.equal(end.salvage.extracted,true);assert.equal(end.salvage.loot.scrap,3);
 const finalSave=ask({op:'save'});assert.equal(canonical(ask({op:'replay',save:finalSave})),canonical(end));
 assert.equal(canonical(ask({op:'step',seconds:100})),canonical(end));
 return {success:true,tick:end.tick,loot:end.salvage.loot,pausedAndResumed:true,freezeAfterSettlement:true};
});
await run('combat-and-failure',ask=>{
 ask({op:'new_salvage',seed:6111,start:{content:'salvage-v1',fleet:fleet(3)}});
 ask({op:'ai',fleet:1,profile:'gunnery',mode:'auto',move:false,gun:true,torpedo:true});
 ask({op:'route',fleet:1,mode:'follow',speed:20,points:[{x:11500,y:2200}]});
 const end=ask({op:'step',seconds:2700});
 assert.ok(end.events.some(e=>e.kind==='gun'),'must fire real CAS guns');
 assert.ok(end.events.some(e=>e.kind==='damage'),'must resolve real damage');
 assert.ok(end.result,'must finish at limit or fleet failure');
 const save=ask({op:'save'});assert.equal(canonical(ask({op:'replay',save})),canonical(end));
 return {tick:end.tick,gunEvents:end.events.filter(e=>e.kind==='gun').length,damageEvents:end.events.filter(e=>e.kind==='damage').length,ships:end.salvage.ships};
});
await run('utility-upgrades-and-abandon',ask=>{
 const initial=ask({op:'new_salvage',seed:0xffffffff,start:{content:'salvage-v1',fleet:fleet(3,{level:15,equipment:true,command:true})}});
 assert.equal(initial.salvage.capacity,14);assert.equal(initial.salvage.searchDuration,4);
 const end=ask({op:'salvage_abandon'}),save=ask({op:'save'});
 assert.ok(end.result);assert.equal(end.salvage.extracted,false);
 assert.equal(canonical(ask({op:'replay',save})),canonical(end));
 return {score:initial.salvage.score,threat:initial.salvage.threat,capacity:initial.salvage.capacity,searchDuration:initial.salvage.searchDuration};
});
// Exercise the actual native bridge with the doubles emitted by Godot JSON.
const rawStart={op:'new_salvage',seed:6106.0,start:{content:'salvage-v1',fleet:fleet()}};
const floatJson=JSON.stringify(rawStart).replace(/"(seed|hp|ammo|level)":(\d+)/g,'"$1":$2.0');
const first=spawnSync(native,[],{input:floatJson+'\n'+JSON.stringify({op:'save',serialized:true})+'\n',encoding:'utf8'});
assert.equal(first.status,0);const firstRows=first.stdout.trim().split(/\r?\n/).map(JSON.parse);
assert.equal(firstRows[0].ok,true);assert.equal(firstRows[1].ok,true);assert.equal(typeof firstRows[1].serialized,'string');
const restored=spawnSync(native,[],{input:JSON.stringify({op:'load',serialized:firstRows[1].serialized})+'\n',encoding:'utf8'});
assert.equal(restored.status,0);assert.equal(canonical(JSON.parse(restored.stdout)),canonical(firstRows[0]));
const receipt={godotFloatRequestsAndOpaqueSaveRestore:true,date:'2026-11-11',nativeWasmCanonicalMatch:true,nativeSha256:createHash('sha256').update(await readFile(native)).digest('hex'),wasmSha256:createHash('sha256').update(wasm).digest('hex'),cases};
await writeFile(resolve(root,'artifacts/godot/pve/receipt.json'),JSON.stringify(receipt,null,2));
console.log(JSON.stringify(receipt,null,2));
