import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,readdir,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),folder=resolve(root,'artifacts/story-modernization-v3'),out=resolve(folder,'parity');
const native=process.env.CAS_LITTORAL_NATIVE,wasmPath=process.env.CAS_LITTORAL_WASM;
assert.ok(native&&wasmPath,'Set candidate native and WASM paths');await mkdir(out,{recursive:true});
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const files=(await readdir(folder)).filter(name=>/^c\d-.*-commands\.json$/.test(name)).sort();assert.equal(files.length,9);
const wasm=await readFile(wasmPath),encoder=new TextEncoder(),decoder=new TextDecoder(),rows=[];
for(const name of files){
  const p=spawn(native,[],{stdio:['pipe','pipe','inherit']});const lines=createInterface({input:p.stdout})[Symbol.asyncIterator]();
  const {instance}=await WebAssembly.instantiate(wasm,{}),api=instance.exports;
  let requests=0,bytes=0,lastView;const rejected=[];
  async function call(q){
    const wire=encoder.encode(JSON.stringify(q)),pointer=api.cas_alloc(wire.length)>>>0;
    new Uint8Array(api.memory.buffer,pointer,wire.length).set(wire);
    const r=api.cas_request(pointer,wire.length)>>>0;
    const wasmRaw=decoder.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0));
    p.stdin.write(JSON.stringify(q)+'\n');const nativeRaw=await lines.next();assert.equal(nativeRaw.done,false);
    if(nativeRaw.value!==wasmRaw){await writeFile(resolve(out,`${name}-native-mismatch.json`),nativeRaw.value);await writeFile(resolve(out,`${name}-wasm-mismatch.json`),wasmRaw);assert.equal(nativeRaw.value,wasmRaw,`${name} #${requests+1} ${q.op}`);}
    requests++;bytes+=Buffer.byteLength(wasmRaw);const parsed=JSON.parse(wasmRaw);
    if(parsed.ok!==true)rejected.push({request:requests,op:q.op,error:parsed.error});
    if(parsed.data?.ships)lastView=parsed.data;
    return parsed;
  }
  try{
    const source=await readFile(resolve(folder,name),'utf8');const calls=JSON.parse(source);
    // Rejections from the recorded public playthrough are authoritative too.
    // In particular premature extraction must remain rejected on both backends.
    for(const q of calls)await call(q);
    const saved=await call({op:'save'});assert.equal(saved.ok,true);
    const terminal=JSON.stringify(lastView);
    await call({op:'load',save:saved.data});assert.equal(JSON.stringify(lastView),terminal,`${name}: load reproduces terminal view`);
    await call({op:'replay',save:saved.data});assert.equal(JSON.stringify(lastView),terminal,`${name}: replay reproduces terminal view`);
    rows.push({stage:name.replace('-commands.json',''),playthrough_requests:calls.length,requests,bytes,tick:lastView?.tick,result:lastView?.result??null,rejected,raw_identical:true,commands_sha256:hash(Buffer.from(source))});
  }finally{p.stdin.end();}
}
const receipt={passed:true,native,native_sha256:hash(await readFile(native)),wasm:wasmPath,wasm_sha256:hash(wasm),stages:rows.length,requests:rows.reduce((n,r)=>n+r.requests,0),bytes:rows.reduce((n,r)=>n+r.bytes,0),rows,scope:'All recorded public commands from nine completed canon-missions-v3 story missions, including rejected early extraction, plus exact terminal save/load/replay. Every raw native/WASM response must match.'};
await writeFile(resolve(out,'modern-story-nine-missions.json'),JSON.stringify(receipt,null,2));
console.log(JSON.stringify({passed:true,stages:receipt.stages,requests:receipt.requests,bytes:receipt.bytes,rejected:rows.reduce((n,r)=>n+r.rejected.length,0),native_sha256:receipt.native_sha256,wasm_sha256:receipt.wasm_sha256,receipt:resolve(out,'modern-story-nine-missions.json')}));
