import assert from 'node:assert/strict';
import{readFile,readdir,mkdir,writeFile}from'node:fs/promises';
import{spawnSync}from'node:child_process';
import{resolve}from'node:path';
import{createHash}from'node:crypto';
const root=resolve(import.meta.dirname,'..'),out=resolve(root,'artifacts/expedition-v2-launcher');await mkdir(out,{recursive:true});
const audited=resolve(root,'target/expedition-v2-runtime/4786d5c707db7534cbe512c33a55474199fb3f506eb5d7100e49f7bd4e846b16/cas-sim.exe');
const manifest=JSON.parse(await readFile(resolve(root,'godot/bin/core-current.json'),'utf8'));const launcher=process.env.CAS_LAUNCHER_NATIVE||resolve(root,'godot/bin',manifest.executable);
const wasmPath=resolve(root,'client/public/cas_core.wasm'),wasm=await readFile(wasmPath),digest=b=>createHash('sha256').update(b).digest('hex');
const run=(file,commands)=>{const p=spawnSync(file,[],{input:commands.map(JSON.stringify).join('\n')+'\n',encoding:'utf8',maxBuffer:192*1024*1024});assert.equal(p.status,0,p.stderr);return p.stdout;};
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>a.localeCompare(b,'en'))):x);
const rows=[];for(const folder of ['artifacts/expedition-v2-core','artifacts/extraction-autopilot'])for(const file of(await readdir(resolve(root,folder))).filter(s=>s.endsWith('-commands.json')).sort()){
 const commands=JSON.parse(await readFile(resolve(root,folder,file),'utf8'));const baseline=run(audited,commands),actual=run(launcher,commands);assert.equal(actual,baseline,file+' native raw UTF-8 output bytes');
 const{instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports,enc=new TextEncoder(),dec=new TextDecoder(),answers=[];for(const q of commands){const b=enc.encode(JSON.stringify(q)),p=api.cas_alloc(b.length)>>>0;new Uint8Array(api.memory.buffer,p,b.length).set(b);const r=api.cas_request(p,b.length)>>>0;answers.push(JSON.parse(dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0))));}
 const nativeAnswers=actual.trim().split(/\r?\n/).map(JSON.parse);assert.equal(canonical(nativeAnswers),canonical(answers),file+' launcher native/WASM values');
 rows.push({name:folder+'/'+file,requests:commands.length,nativeRawBytesEqual:true,nativeWasmEqual:true,outputBytes:Buffer.byteLength(actual),outputSha256:digest(actual)});
}
const report={launcher,launcherSha256:digest(await readFile(launcher)),audited,auditedSha256:digest(await readFile(audited)),wasmSha256:digest(wasm),manifest,suites:rows.length,requests:rows.reduce((n,r)=>n+r.requests,0),passed:rows.length,results:rows};await writeFile(resolve(out,'receipt.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({...report,results:undefined,manifest:undefined}));

