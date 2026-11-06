import { trainingCourses } from './curriculum';
import type { CourseId, TrainingEvidence, TrainingSignal, TrainingStep } from './curriculum';

export type GuideControl = 'fleet-tab' | 'ship-tab' | 'fleet-ship' | 'set-leader' | 'map' | 'follow' | 'sync'
  | 'route-commit' | 'route-cancel' | 'gun' | 'torpedo' | 'fire-cancel' | 'clock-toggle' | 'clock-step'
  | 'contact' | 'radar' | 'radar-contact' | 'illumination' | 'battle-log' | 'ai-tab' | 'ai-mode';

type GuideCue = { controls: readonly GuideControl[]; instruction: string };
type GuidanceOptions = { radar?: boolean };

const cueBySignal: Partial<Record<TrainingSignal, GuideCue>> = {
  fleetViewed: { controls: ['fleet-tab'], instruction: '点「编队」，确认领舰和后续舰。' },
  mapViewed: { controls: ['map'], instruction: '点海图空处，看看本舰队在哪里。' },
  lead: { controls: ['set-leader', 'fleet-ship', 'fleet-tab'], instruction: '在编队内选一艘后舰，再点「设为领舰」。' },
  followMode: { controls: ['follow', 'fleet-tab'], instruction: '在「编队」中点「领舰移动」。' },
  syncMode: { controls: ['sync', 'fleet-tab'], instruction: '在「编队」中点「同步移动」。' },
  routePoint: { controls: ['map'], instruction: '点海图放一个途经点，留下一段待撤回的草稿。' },
  followPreview: { controls: ['map'], instruction: '在海图放至少两个途经点，等全队航线预览通过。' },
  syncPreview: { controls: ['map'], instruction: '在海图画参考航线，确认每艘舰都能走自己的航迹。' },
  followAccepted: { controls: ['route-commit', 'fleet-tab'], instruction: '点「下达航线」，让后舰沿领舰航迹行驶。' },
  syncAccepted: { controls: ['route-commit', 'fleet-tab'], instruction: '点「下达航线」，让各舰按同一时刻转向。' },
  draftCancelled: { controls: ['route-cancel', 'fleet-tab'], instruction: '点「取消草稿」，撤回未下达的航线。' },
  gunOrdered: { controls: ['gun', 'clock-toggle'], instruction: '按住舰上的炮标，拖到合法接触，等炮位提示后松手。' },
  gunFired: { controls: ['clock-step', 'clock-toggle'], instruction: '让时间运行，等战情记录实际开火。也可逐秒推进。' },
  fireCancelled: { controls: ['fire-cancel', 'gun', 'torpedo'], instruction: '按住炮标或雷标，拖到取消区再松手。' },
  torpedoAimed: { controls: ['torpedo', 'clock-toggle'], instruction: '拖住雷标，在接触上稍停，等推荐射向出现。' },
  torpedoAdjusted: { controls: ['map'], instruction: '保持按住，稍微拖动，在合法扇区内调整射向。' },
  torpedoOrdered: { controls: ['map'], instruction: '保持合法射向，松手下达雷击。' },
  torpedoFired: { controls: ['clock-step', 'clock-toggle'], instruction: '让时间运行，等战情记录鱼雷实际离管。' },
  override: { controls: ['ai-mode', 'ai-tab'], instruction: '在「战术 AI」托管一项任务，再亲自下达同类命令。' },
  paused: { controls: ['clock-toggle'], instruction: '让演习开始运行，再按「暂停」。' },
  stepped: { controls: ['clock-step'], instruction: '点「推进一秒」，留意本方舰艇和海图变化。' },
  contactViewed: { controls: ['contact', 'clock-toggle'], instruction: '在海图点一个可见接触，检查代号和识别情况。' },
  radarViewed: { controls: ['ship-tab'], instruction: '打开「舰况」，找到所选舰的舰载雷达。' },
  radarPowered: { controls: ['radar', 'ship-tab'], instruction: '在舰况开启可用的搜索雷达，等开机回执。' },
  radarContactViewed: { controls: ['radar-contact', 'clock-toggle'], instruction: '推进到探测窗口，再点海图上已出现的 R 回波。' },
  lightAccepted: { controls: ['illumination', 'contact'], instruction: '选有照明弹的舰和合法接触，下达照明命令。' },
  lightApplied: { controls: ['clock-step', 'clock-toggle'], instruction: '让时间运行，等照明弹实际起亮。' },
  reportViewed: { controls: ['battle-log'], instruction: '打开「战情记录」，核对发现、发射和裁决。' },
};

const guidedRequirements: Record<string, TrainingSignal[]> = {
  'bridge-follow': ['followMode', 'followPreview', 'followAccepted'],
  'bridge-sync': ['syncMode', 'syncPreview', 'syncAccepted'],
  'prologue-withdraw-plan': ['followMode', 'routePoint', 'draftCancelled'],
  'campaign-night-route': ['followMode', 'followPreview'],
};

const radarStep: TrainingStep = {
  id: 'campaign-night-radar',
  title: '用雷达建立本舰接触',
  instruction: '打开舰况，开启搜索雷达，再检查海图上的 R 回波。',
  reason: '搜索回波给出位置，舰名和目标运动仍需后续观测才能确认。',
  guide: '[data-guide-control="radar"]',
  require: ['radarViewed', 'radarPowered', 'radarContactViewed'],
};

function requirements(step: TrainingStep) {
  return guidedRequirements[step.id] ?? step.require;
}

export function guidedTrainingProgress(course: CourseId, evidence: TrainingEvidence, { radar = false }: GuidanceOptions = {}) {
  const courseSteps = trainingCourses[course].steps;
  const steps = radar && course === 'night' ? courseSteps.flatMap(step =>
    step.id === 'campaign-night-contact' ? [radarStep, step] : [step]) : courseSteps;
  const index = steps.findIndex(step => requirements(step).some(signal => !evidence[signal]));
  const current = index < 0 ? undefined : steps[index];
  const next = current && requirements(current).find(signal => !evidence[signal]);
  return { current, complete: index < 0 ? steps.length : index, total: steps.length, next,
    cue: next ? cueBySignal[next] : undefined };
}

export function guidedTrainingDone(course: CourseId, evidence: TrainingEvidence, options?: GuidanceOptions) {
  return !guidedTrainingProgress(course, evidence, options).current;
}

export function recordGuidedTrainingSignals(course: CourseId, evidence: TrainingEvidence, signals: readonly TrainingSignal[],
  options?: GuidanceOptions): TrainingEvidence {
  let result = evidence;
  for (const signal of signals) {
    if (signal === guidedTrainingProgress(course, result, options).next) {
      result = { ...result, [signal]: true };
    }
  }
  return result;
}

const fallback: Partial<Record<GuideControl, string>> = {
  'fleet-tab': '.staff-tabs button:first-child',
  'ship-tab': '.staff-tabs button:nth-child(2)',
  'fleet-ship': '.roster-ship[aria-pressed="false"]',
  map: '.battle-map',
  follow: '.maneuver-choice button:first-child',
  sync: '.maneuver-choice button:nth-child(2)',
  gun: '.battle-map button.weapon.gun',
  torpedo: '.battle-map button.weapon.torpedo',
  'fire-cancel': '.battle-map .cancel-well.visible',
  'clock-toggle': '.clock-play',
  'clock-step': '.clock-step',
  contact: '[data-contact]:not(.radar-contact)',
  illumination: '.night-tools',
  'battle-log': '.signal-strip .text-button',
  'ai-tab': '.staff-tabs button:nth-child(3)',
  'ai-mode': '.ai-panel select:nth-of-type(2)',
};

export function guideSelectors(control: GuideControl) {
  const hook = `[data-guide-control~="${control}"]`;
  return fallback[control] ? [hook, fallback[control]] : [hook];
}
