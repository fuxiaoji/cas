import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/littoral-core');await mkdir(out,{recursive:true});
const binary=process.env.CAS_LITTORAL_NATIVE||resolve(root,'target/littoral-build/release/cas-sim.exe');
const p=spawn(binary,[],{stdio:['pipe','pipe','inherit']}),rows=createInterface({input:p.stdout})[Symbol.asyncIterator](),commands=[];let checks=0;
async function ask(q,ok=true){commands.push(q);p.stdin.write(JSON.stringify(q)+'\n');const row=await rows.next();assert.equal(row.done,false);const r=JSON.parse(row.value);assert.equal(r.ok,ok,JSON.stringify(r));checks++;return r.data;}
const base={op:'new_littoral',version:'cas-littoral-v1',seed:42,mode:'tutorial',ships:[{id:'IBS-U-USN-FLETCHER',hp:60,ammo:100}],roster:['MCP-034'],unit_condition:[{id:'MCP-034',hp:60}],transport_preset:'balanced',defense:[]};
async function reject(q){const before=await ask({op:'observe'});await ask(q,false);assert.deepEqual(await ask({op:'observe'}),before);checks++;}
try{
 const catalogue=await ask({op:'littoral_catalogue'});assert.equal(catalogue.cards.length,5);assert.equal(catalogue.cards.every(c=>c.released),true);
 let v=await ask(base);assert.equal(v.littoral.groups[0].hp_percent,60);assert.equal(v.ships[0].hp/v.ships[0].maxHp,.6);
 for(const patch of [{version:'cas-littoral-v9'},{mode:'invented'},{ships:[{id:'invented',hp:100,ammo:100}]},{ships:[base.ships[0],base.ships[0]]},{roster:['MCP-020']},{roster:['MCP-034','MCP-034']},{unit_condition:[{id:'MCP-034',hp:9}]},{unit_condition:[{id:'MCP-001',hp:60}]},{transport_preset:'unlimited'},{ships:[{...base.ships[0],ammo:101}]},{transport_preset:'combat'},{client_type:'AP'},{defense:[{id:'a',kind:'turret',x:.5,y:.5,level:1,hp:100}]},{defense:[{id:'hq',kind:'hq',x:2,y:.5,level:1,hp:100}]}])await reject({...base,...patch});
 for(const seconds of [-1,.01,2700.1,'1',null])await reject({op:'step',seconds});
 for(const q of [
  {op:'littoral_deploy',unit_id:'MCP-034',beach:2,insertion:'landing'},
  {op:'littoral_deploy',unit_id:'MCP-034',beach:2,insertion:'air'},
  {op:'littoral_order',unit_id:'MCP-034',action:'move',x:13000,y:9000},
  {op:'littoral_ship_order',ship:1001,action:'move',x:5000,y:10000},
  {op:'littoral_support',kind:'helicopter',unit_id:'MCP-034',x:13000,y:9000},
  {op:'littoral_support',kind:'naval',ship:1,x:6500,y:13000,queue:'true'},
  {op:'route',fleet:1,speed:25,points:[{x:13000,y:7000}]},
  {op:'speed',fleet:1,speed:41},{op:'littoral_extract'}])await reject(q);
 const saved=await ask({op:'save'});
 for(const bad of [{...saved,frame:1},{...saved,tick:.1},{...saved,unknown:1},{...saved,commands:[{frame:1,request:{op:'speed',speed:0}}]},{...saved,config:{...saved.config,roster:['MCP-999']}}])await reject({op:'load',save:bad});
 await reject({op:'replay',save:saved,tick:.1});
 const initial=await ask({op:'observe'});assert.deepEqual(await ask({op:'load',serialized:JSON.stringify(saved)}),initial);
 assert.deepEqual(await ask({op:'replay',serialized:JSON.stringify(saved)}),initial);
 v=await ask({op:'littoral_abandon'});assert.equal(v.littoral.outcome.success,false);assert.equal(v.littoral.outcome.units[0].hp_percent,60);assert.equal(v.littoral.outcome.ships[0].hp_percent,60);assert.deepEqual(v.littoral.outcome.resources,{alloy:0,credits:0,protocols:0,scrap:0});
 await reject({op:'littoral_abandon'});assert.deepEqual(await ask({op:'step',seconds:1}),v);
 v=await ask({op:'new_tide',version:'cas-event-tide-v1',seed:42,character_id:'IBS-U-USN-FLETCHER'});assert.ok(v.tide);assert.equal(v.littoral,undefined);
 v=await ask(base);assert.equal(v.tide,undefined);assert.ok(v.littoral);
 v=await ask({op:'new',seed:42,side:'allies',enemy:'torpedo',profile:'gunnery'});assert.equal(v.littoral,undefined);
 v=await ask(base);v=await ask({op:'littoral_ship_order',ship:1,action:'face',heading:0});v=await ask({op:'step',seconds:1.5});
 v=await ask({op:'littoral_support',kind:'naval',ship:1,x:6500,y:13000});const ammoAfterFirst=v.ships[0].ammo;
 v=await ask({op:'littoral_support',kind:'naval',ship:1,x:6600,y:13000,queue:true});assert.ok(v.littoral.support.naval[0].pending_target);
 const queuedSave=await ask({op:'save'});assert.deepEqual(await ask({op:'load',serialized:JSON.stringify(queuedSave)}),v);assert.deepEqual(await ask({op:'replay',serialized:JSON.stringify(queuedSave)}),v);
 v=await ask({op:'step',seconds:7});assert.equal(v.littoral.support.naval[0].pending_target,null);assert.equal(v.ships[0].ammo,ammoAfterFirst-1);assert.ok(v.events.some(e=>e.kind==='support_fired'));
 v=await ask({op:'littoral_support',kind:'naval',ship:1,x:6600,y:13000,queue:true});v=await ask({op:'littoral_ship_order',ship:1,action:'cancel_support'});assert.equal(v.littoral.support.naval[0].pending_target,null);
 v=await ask({...base,mode:'raid',ships:[{id:'IBS-U-USN-ERMA-IOWA',hp:1,ammo:0}],unit_condition:[{id:'MCP-034',hp:10}],transport_preset:'transport'});
 v=await ask({op:'step',seconds:480});assert.ok(v.result);assert.equal(v.littoral.outcome.success,false);assert.deepEqual(v.littoral.outcome.resources,{alloy:0,credits:0,protocols:0,scrap:0});
 const terminalSave=await ask({op:'save'});assert.deepEqual(await ask({op:'load',serialized:JSON.stringify(terminalSave)}),v);assert.deepEqual(await ask({op:'replay',serialized:JSON.stringify(terminalSave)}),v);
 await writeFile(resolve(out,'littoral-protocol-commands.json'),JSON.stringify(commands,null,2));await writeFile(resolve(out,'littoral-protocol-native.json'),JSON.stringify({summary:{kind:'protocol',checks,expected_success:false},terminal:v},null,2));
 await writeFile(resolve(out,'protocol-receipt.json'),JSON.stringify({passed:true,binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),checks,requests:commands.length,terminal:v.littoral.outcome,transportKinds:[...new Set(catalogue.ships.map(s=>s.kind))]},null,2));console.log(JSON.stringify({passed:true,checks,requests:commands.length,terminalTick:v.tick}));
}finally{p.stdin.end();}
