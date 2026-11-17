import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const require=createRequire(path.join(root,'client/package.json'));
const {build}=require('esbuild');
async function moduleFrom(relative) {
  const result=await build({entryPoints:[path.join(root,relative)],bundle:true,platform:'node',format:'esm',write:false,logLevel:'silent'});
  return import('data:text/javascript;base64,'+Buffer.from(result.outputFiles[0].text).toString('base64'));
}
async function write(name,value) {await fs.writeFile(path.join(root,'godot/data',name),JSON.stringify(value,null,2)+'\n');}
const [story,script,training,ai,checkin,campaign]=await Promise.all([
  moduleFrom('client/src/prologue/story.ts'),moduleFrom('client/src/prologue/originalScript.ts'),
  moduleFrom('client/src/tutorial/curriculum.ts'),moduleFrom('client/src/ai-shop.ts'),
  moduleFrom('client/src/activities/check-in.ts'),moduleFrom('client/src/campaign-progress.ts'),
]);
const variants={};
for(const person of story.DD_PERSONALITIES) for(const memory of ['lost','duty','trust']) {
  variants[person.id+'|'+memory]=Array.from({length:31},(_,step)=>{
    const p={...story.initialPrologueProgress(),step,leaderId:person.id,answers:{memory}};
    return {step,lines:story.storyDialogue(p),cinema:script.CINEMAS[step]??null};
  });
}
await write('prologue.json',{version:1,source:'client/src/prologue/story.ts + originalScript.ts',fictional:true,personalities:story.DD_PERSONALITIES,variants});
const courses={...training.trainingCourses,radar:{title:'夜海初航 · 雷达与照明',steps:[
  {id:'campaign-night-radar',title:'用雷达建立本舰接触',instruction:'在舰况开启搜索雷达，等待并查看本席雷达回波。',require:['radarViewed','radarPowered','radarContactViewed']},
  ...training.trainingCourses.night.steps.filter(s=>['campaign-night-contact','campaign-night-light','campaign-night-cycle'].includes(s.id)),
]}};
await write('training.json',{version:1,source:'client/src/tutorial/curriculum.ts + guide.ts radar subset',courses});
await write('ai-shop.json',{version:1,source:'client/src/ai-shop.ts',profiles:ai.AI_SHOP});
const rewards={};for(const side of ['ALLIES','AXIS'])for(const stage of ['02','03','04','05','10','11']) {const id=`CAMP-${side}-${stage}`;rewards[id]=campaign.campaignRewards(id);}
await write('mode-rewards.json',{version:1,source:'client/src/activities/check-in.ts, activities/week.ts, port.ts, campaign-progress.ts',check_in:checkin.CHECK_IN_REWARDS,campaign:rewards,welcome:{tickets:20,up_tickets:0},prologue:{credits:2000,tickets:10,up_tickets:10},weekly:{repeat_limit:3,repeat_tickets:2,ticket_cost:500,supply_clears:3,supply_credits:500,supply_tickets:3}});
await fs.copyFile(path.join(root,'data/challenge/stages.json'),path.join(root,'godot/data/challenges.json'));
console.log(JSON.stringify({story_variants:Object.keys(variants).length,story_steps:31,ai:ai.AI_SHOP.length,challenges:5,training:Object.keys(courses).length}));
