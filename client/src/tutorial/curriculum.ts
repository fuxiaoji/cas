export type CourseId = 'day' | 'night' | 'follow' | 'sync' | 'torpedo';
export type TrainingSignal = 'fleetViewed' | 'mapViewed' | 'lead' | 'followMode' | 'followPreview' | 'followAccepted'
  | 'draftCancelled' | 'syncMode' | 'syncPreview' | 'syncAccepted' | 'gunOrdered' | 'gunFired' | 'fireCancelled'
  | 'torpedoAimed' | 'torpedoAdjusted' | 'torpedoOrdered' | 'torpedoFired' | 'override'
  | 'paused' | 'stepped' | 'contactViewed' | 'lightAccepted' | 'lightApplied' | 'reportViewed' | 'finished';
export type TrainingEvidence = Partial<Record<TrainingSignal, boolean>>;
export type TrainingStep = { id: string; title: string; instruction: string; reason: string; guide: string; require: TrainingSignal[] };

const fleet = '.staff-tabs button:first-child';
const map = '.battle-map';
const route = '.maneuver-choice';
const draft = '.route-tools';
const gun = '.battle-map button.weapon.gun';
const torpedo = '.battle-map button.weapon.torpedo';
const clock = '.clock-deck';
const contact = '[data-contact]';
const light = '.night-tools';
const log = '.signal-strip .text-button';

const step = (id: string, title: string, instruction: string, reason: string, guide: string, ...require: TrainingSignal[]): TrainingStep => ({ id, title, instruction, reason, guide, require });
const follow = step('bridge-follow', '让后舰跟上领舰', '选「领舰移动」，点出至少两个途经点。等显示「航线可用」后，查看各舰的航迹，再下达航线。', '领舰先过转向点，后舰沿同一条实际航迹转向。', route, 'followPreview', 'followAccepted');
const sync = step('bridge-sync', '让各舰同时转向', '切换「同步移动」，画好参考线后检查每一条平移航迹，确认并下达新航线。', '同步移动时，各舰不会集中到同一个转向点。', route, 'syncPreview', 'syncAccepted');
const gunStep = step('bridge-gun', '完成一次实际炮击', '按住己方舰上的「炮」拖向可攻击接触，等出现可用炮位后松手。继续推进时钟，看到战情里的实际发射。', '下令与发射是两件事；结课不看是否命中。', gun, 'gunOrdered', 'gunFired');
const cancel = step('bridge-cancel', '取消一次火力手势', '按住炮标或雷标，拖到「拖到这里取消」再松手。', '在取消区松手不会下令，也不会消耗弹药。', gun, 'fireCancelled');
const aim = step('bridge-torpedo-aim', '留出安全雷道', '拖住「雷」，在可攻击接触上停留至出现推荐射向。继续拖动，把射向调整到合法扇区内，再松手下令。', '鱼雷按实际发射方向航行；发射后不会追随敌舰或避让友舰。', torpedo, 'torpedoAimed', 'torpedoAdjusted', 'torpedoOrdered');
const launch = step('bridge-torpedo-fire', '看到鱼雷真正离管', '继续推进时钟，留意直航鱼雷和发射记录。如果窗口到来前接触丢失，重新寻找合法射向。', '确认收到命令不代表已经发射。是否命中不影响结课。', clock, 'torpedoFired');

export const trainingCourses: Record<CourseId, { title: string; steps: TrainingStep[] }> = {
  day: { title: '舰桥学堂 · 昼间实操', steps: [
    step('bridge-lead', '挑选领舰', '在开始演习前，从编队列表选一艘非领舰，按「设为领舰」。', '先确认谁带队，再绘制编队航线。', fleet, 'lead'),
    follow, sync, gunStep, cancel, aim, launch,
    step('bridge-override', '亲自接管一项任务', '在「战术 AI」托管一项任务，再亲自下达同类合法命令。', '手动下令后，该项由你继续指挥，直到重新交还。', '.staff-tabs button:nth-child(3)', 'override'),
  ] },
  follow: { title: '序章 · 侧翼机动', steps: [follow, gunStep] },
  sync: { title: '序章 · 改令同步', steps: [
    step('prologue-withdraw-plan', '撤回尾随草稿', '打开领舰移动，画出旧计划的一段，再按「取消草稿」。已生效的航线要靠新命令替换。', '草稿不会移动舰艇；下一条获准的命令才会替换现行路线。', draft, 'draftCancelled'), sync,
  ] },
  torpedo: { title: '序章 · 编队雷击', steps: [aim, launch] },
  night: { title: '夜海初航 · 实战教学', steps: [
    step('campaign-night-formation', '先确认领舰和队列', '查看「编队」，确认领舰、舰艇数量与队列。', '夜里也只能从本席观察掌握双方态势。', fleet, 'fleetViewed'),
    step('campaign-night-map', '查看自己的海图', '点一下海图空处，查看本方舰船、黑暗海域和当前可见接触。', '海图空白不代表那里没有敌舰。', map, 'mapViewed'),
    step('campaign-night-route', '画一条能走的航路', '选择「领舰移动」，画至少两个途经点。同盟席可先朝东到海图 13E 附近，再转北；在「调整航速」设 15 节。', '预览会检查全队航迹。适当降低接敌航速，可以给照明弹留出距离。', route, 'followPreview'),
    step('campaign-night-follow', '确认尾随航线', '在合法预览后按「下达航线」，开始机动接敌。', '确认前只是草稿；确认后编队才会执行航线。', draft, 'followAccepted'),
    step('campaign-night-pulse', '暂停，再推进一秒', '开始演习，按「暂停」，然后使用「推进一秒」。留意海图怎样更新。', '舰船、炮弹、鱼雷和接触共用同一时钟。', clock, 'paused', 'stepped'),
    step('campaign-night-contact', '确认当前接触', '推进时钟直到发现敌方接触，点一个当前可见接触查看代号和识别情况。', '已经看见一个位置，并不等于知道对方舰名。', contact, 'contactViewed'),
    step('campaign-night-light', '用照明弹照亮目标', '选一艘后列驱逐舰，打开「照明」，对较远的合法接触下令。继续推进；未起亮或距离太近时可重新选择。', '照明弹在合法射击时点发射；承担照明的炮座当次不再进行常规炮击。', light, 'lightAccepted', 'lightApplied'),
    step('campaign-night-guns', '完成一次夜间炮击', '拖炮标到当前接触并下令；推进时钟直到战情记录实际炮击。', '这一步只检查合法炮击，不要求命中。', gun, 'gunOrdered', 'gunFired'),
    step('campaign-night-torpedo', '亲手发出一批鱼雷', '在雷击距离内拖住雷标，对可见接触瞄准、调整后下令，再推进到实际发射。', '先核对己方航迹；只有引擎确认发射才算完成。', torpedo, 'torpedoAimed', 'torpedoOrdered', 'torpedoFired'),
    step('campaign-night-cycle', '查看本次正式战情', '点开「战情记录」，对照发现接触、照明、发射和判定结果。', '完成这轮操作即可结课，演习战果仍由正常规则决定。', log, 'reportViewed'),
  ] },
};

export const trainingStepDone = (step: TrainingStep, evidence: TrainingEvidence) => step.require.every((signal) => evidence[signal] === true);
export function trainingCourseDone(course: CourseId, evidence: TrainingEvidence) { return trainingCourses[course].steps.every((item) => trainingStepDone(item, evidence)); }
