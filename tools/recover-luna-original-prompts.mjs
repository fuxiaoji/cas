import fs from 'node:fs';
import vm from 'node:vm';
const calls=JSON.parse(fs.readFileSync('tools/luna-chibi-original-call-inputs.json','utf8'));
const captured=[];
for(let index=4;index<=11;index++){
  const call=calls[index];
  if(call.input.includes('exec_command'))throw new Error('Only original generation cells are allowed');
  const tools=Object.freeze({image_gen__imagegen:async args=>{
    const identity=args.prompt.match(/IBS-U-[A-Z0-9-]+/)?.[0];
    captured.push({identity,...args,call_id:call.call_id,timestamp:call.timestamp});
    return {output_hint:'Offline capture only; no image generation or writes performed.'};
  }});
  await vm.runInNewContext('(async()=>{'+call.input+'})()', {tools,text:()=>{},generatedImage:()=>{}}, {timeout:2000});
}
if(captured.length!==29||new Set(captured.map(row=>row.identity)).size!==29)throw new Error('Expected 29 unique original generation arguments');
fs.writeFileSync('tools/luna-chibi-29-original-prompts.json',JSON.stringify({policy:'Exact arguments reconstructed by evaluating original logged generation cells with an offline capture stub. No tool or image call executed.',jobs:captured},null,2));
const path='tools/luna-chibi-29-candidates.json';
const manifest=JSON.parse(fs.readFileSync(path,'utf8'));
for(const row of manifest.jobs){
  const original=captured.find(x=>x.identity===row.identity);
  if(!original)throw new Error('Missing exact original '+row.identity);
  row.reconstructed_template_not_actual=row.prompt;
  row.prompt=original.prompt;
  row.prompt_reconstructed_from_generation_method=false;
  row.prompt_source={kind:'exact original generation arguments',call_id:original.call_id,timestamp:original.timestamp,evidence:'tools/luna-chibi-29-original-prompts.json'};
}
fs.writeFileSync(path,JSON.stringify(manifest,null,2));
console.log('Recovered exact original prompts and 3 references for all 29 candidates');
