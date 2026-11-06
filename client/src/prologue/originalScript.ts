export const STARTER_DD_IDS=['IBS-U-USN-FLETCHER','IBS-U-USN-PERKINS','IBS-U-USN-MAURY','IBS-U-USN-DRAYTON','IBS-U-USN-LAMSON'] as const;
export type StarterDDId=typeof STARTER_DD_IDS[number];
export interface PrologueProgress {version:1;step:number;dialogue:number;leaderId:string;answers:Record<string,string>;flags:Record<string,boolean>}
export const PROLOGUE_LAST_STEP=30;
export const nextPrologueStep=(step:number)=>step===12?18:Math.min(PROLOGUE_LAST_STEP,step+1);
export function initialPrologueProgress():PrologueProgress{return {version:1,step:0,dialogue:0,leaderId:STARTER_DD_IDS[0],answers:{},flags:{}}}
export function normalizePrologueProgress(raw:unknown):PrologueProgress{
 const v=raw as Partial<PrologueProgress>|null,base=initialPrologueProgress();
 if(!v||v.version!==1)return base;
 const step=Number.isInteger(v.step)?Math.max(0,Math.min(PROLOGUE_LAST_STEP,v.step!)):0;
 const oldFollowCheckpoint=step>=13&&step<=17;
 return {...base,step:oldFollowCheckpoint?12:step,dialogue:!oldFollowCheckpoint&&Number.isInteger(v.dialogue)?Math.max(0,Math.min(9,v.dialogue!)):0,leaderId:STARTER_DD_IDS.includes(v.leaderId as StarterDDId)?v.leaderId!:base.leaderId,answers:Object.fromEntries(Object.entries(v.answers||{}).filter((p):p is [string,string]=>typeof p[1]==='string')),flags:Object.fromEntries(Object.entries(v.flags||{}).filter((p):p is [string,boolean]=>typeof p[1]==='boolean'))};
}
export const DD_PERSONALITIES=[
 {id:STARTER_DD_IDS[0],name:'弗莱彻',role:'可靠的先锋',portrait:'/characters/ships/fletcher-anime-face.png',line:'弗莱彻，驱逐编队先锋。记忆可以慢慢找，眼前这五艘船，先交给你。',response:'好，旗舰信号已经升起。你看海图，我看前方。'},
 {id:STARTER_DD_IDS[1],name:'帕金斯',role:'冷静的参谋',portrait:'/characters/ships/perkins-anime-face.png',line:'帕金斯。别逞强，指挥官。把复杂的命令分成几步，我们会执行得很漂亮。',response:'收到。我会替你守住队形，也会提醒你每一个遗漏。'},
 {id:STARTER_DD_IDS[2],name:'莫里',role:'阳光的行动派',portrait:'/characters/ships/maury-anime-face.png',line:'莫里报到！想不起来也没关系，先打一场让大家记住的胜仗吧。',response:'交给我！领舰就该先把航路开出来，你跟紧我的信号。'},
 {id:STARTER_DD_IDS[3],name:'德雷顿',role:'温柔的守望者',portrait:'/characters/ships/drayton-anime-face.png',line:'我是德雷顿。你的声音还有些发抖……没关系，我们会一起回到有灯的地方。',response:'我在。无论海雾多深，我都会把后面的姐妹带回来。'},
 {id:STARTER_DD_IDS[4],name:'拉姆森',role:'细致的技术少女',portrait:'/characters/ships/lamson-anime-face.png',line:'拉姆森，动力和鱼雷状态正常。你只管做决定，剩下的我们一起修好。',response:'明白。领舰、队列、发射顺序，逐项确认，不会掉链子。'},
];
export interface DialogueLine {speaker:string;text:string;portrait:string;shipId?:StarterDDId}
const helper='/characters/prologue/baixi.png';
export function dialogueFor(progress:PrologueProgress):DialogueLine[]{
 const lead=DD_PERSONALITIES.find(s=>s.id===progress.leaderId)||DD_PERSONALITIES[0];
 const ai=(text:string):DialogueLine=>({speaker:'白汐 · 状态机辅助',text,portrait:helper});
 const dd=(ship:(typeof DD_PERSONALITIES)[number],text=ship.line):DialogueLine=>({speaker:ship.name,text,portrait:ship.portrait,shipId:ship.id});
 switch(progress.step){
  case 1:return [ai('指挥官，听得见吗？别闭眼。你现在在第五驱逐编队的舰桥上。'),ai('舰队正在交战。你的伤势已经稳定，但刚才的冲击……你还记得自己的名字吗？')];
  case 2:return [ai(progress.answers.memory==='duty'?'你先问舰队的状况……这一点倒是和从前一样。五艘驱逐舰仍在等你的命令。':progress.answers.memory==='trust'?'那就先记住我。我叫白汐，是你的状态机辅助。我会把每一道命令拆给你看。':'没关系，记忆可以以后找。先记住一件事：我们还在这里，你不是一个人。'),ai('现在向你移交指挥权。我提供路线与火力建议，最后的决定，由你亲手确认。')];
  case 4:return DD_PERSONALITIES.map(ship=>dd(ship));
  case 6:return [dd(lead,lead.response),ai('第五驱逐编队位于敌战列线侧翼。先试一条从敌领舰舰首前方横切的航路。')];
  case 12:return [dd(lead,'照这条航路，领舰会先过敌纵队的舰首延长线。草稿还留在指挥面板上。'),ai('鱼雷可在同步移动途中发射。先安排发射时点和舷角，舰船到达指定位置才发射，鱼雷效果稍后裁决。')];
  case 18:return [{speaker:'总指挥 · 无线电',text:'第五驱逐编队，主力正面牵制敌舰。取消横切，改为侧翼雷击！',portrait:''},ai('先撤回刚才的尾随草稿。换成整队机动，五艘舰在同一时点执行相同舵令。'),dd(lead,'收到。先查清整队的回环，再沿航路设置发射时点。')];
  case 23:return [ai('三次右转只走了半圈。完整回环让五舰回到各自起始格和原航向。现在给鱼雷选一个途中的发射点。'),dd(DD_PERSONALITIES[4],'发射管准备好了。鱼雷不会辨认敌我，封存前记得检查友舰航路。')];
  case 29:return [dd(lead,'武藏和信浓均被命中。回环已经完成，五艘驱逐舰都回来了。'),ai('你可能还没有找回过去，但刚才的命令，每个人都记住了。'),dd(DD_PERSONALITIES[3],'欢迎回来，指挥官。下一次出航，也请带上我们。')];
  default:return [];
 }
}
export interface ScriptTask {title:string;text:string;target:string;button:string}
export const SCRIPT_TASKS:Record<number,ScriptTask>={
 7:{title:'先给领舰一条横切航路',text:'试着用 3S 让领舰先直行三格，再向右转 60°。',target:'flank-route',button:'录入 3S'},
 8:{title:'后续舰沿航迹跟随',text:'选择尾随机动，后续舰依次跟上领舰。',target:'flank-follow',button:'尾随机动'},
 9:{title:'检查领舰和队尾',text:'打开全队预览，比较领舰和队尾的位置，并看敌战列线指向哪里。',target:'flank-preview',button:'预览全队航路'},
 10:{title:'预演抢 T 头',text:'看领舰怎样抢到敌纵队舰首前方。预演只检查草稿，舰队仍在原阵位。',target:'flank-demonstrate',button:'预演领舰航路'},
 19:{title:'撤回原来的尾随草稿',text:'总指挥改令雷击。撤回 3S 草稿，保留当前阵位，重新规划。',target:'withdraw-plan',button:'撤回原计划'},
 20:{title:'五舰同步转向',text:'切到整队机动，五舰按同一节拍执行各自的回环。',target:'sync-mode',button:'整队机动'},
 21:{title:'将两个半圈接成完整回环',text:'1S1S1S 是三格、三个右转，只完成半圈。将它连做两次，共 6 MF，再预览回起点的航路。',target:'sync-plan',button:'录入 1S1S1S1S1S1S'},
 24:{title:'选择鱼雷发射管',text:'先点击“1号发射管”。每一管都要明确安排，不能只选一个目标就结束。',target:'torpedo-tube',button:'1号发射管'},
 25:{title:'确认发射舷侧',text:'在航路第一格向右舷发射，鱼雷航向会切过敌战列线。',target:'torpedo-side',button:'右舷发射'},
 26:{title:'设置发射时点与舷角',text:'确认 TT1、第 1 MF、右舷 A 和 2 枚，再点右栏的「替换本管发射计划」。',target:'torpedo-target',button:'替换本管发射计划'},
 27:{title:'封存同步机动与雷击',text:'核对航路和鱼雷命令，再封存。舰队将按八个脉冲同步移动，并在指定时点发射。',target:'torpedo-fire',button:'封存并执行'},
};
export const CINEMAS:Record<number,{duration:number;title:string;subtitle:string}>={
 0:{duration:7600,title:'舰队决战 · 同步移动',subtitle:'海面正在燃烧，而你的记忆停在了炮声之前。'},
 11:{duration:4200,title:'领舰抢 T 头 · 草稿预演',subtitle:'领舰向敌纵队舰首前方横切，队尾沿航迹跟上。'},
 22:{duration:6200,title:'整队回环 · 航路预览',subtitle:'五舰同步走完六次右转，回到各自的起始格和原航向。'},
 28:{duration:7600,title:'同步移动 · 途中雷击',subtitle:'五舰在预定脉冲发射，鱼雷向敌战列线航行。'},
};
