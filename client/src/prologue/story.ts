import { DD_PERSONALITIES, dialogueFor, initialPrologueProgress, normalizePrologueProgress, STARTER_DD_IDS } from './originalScript';
import type { DialogueLine, PrologueProgress, StarterDDId } from './originalScript';

export { DD_PERSONALITIES, initialPrologueProgress, STARTER_DD_IDS };
export type { PrologueProgress, StarterDDId };
export type PrologueBattleStage = 'follow' | 'sync' | 'torpedo';

export const PROLOGUE_STORAGE_KEY = 'cas.prologue.journey.v1';
const battleExit: Record<PrologueBattleStage, [number, number]> = { follow: [7, 11], sync: [19, 22], torpedo: [24, 28] };
const milestones: Record<number, number> = { 7: 7, 8: 7, 9: 7, 10: 7, 19: 19, 20: 19, 21: 19, 24: 24, 25: 24, 26: 24, 27: 24 };

export function normalizeCasPrologue(raw: unknown): PrologueProgress {
  const p = normalizePrologueProgress(raw);
  const step = milestones[p.step] ?? p.step;
  const maxDialogue = Math.max(0, dialogueFor({ ...p, step }).length - 1);
  return { ...p, step, dialogue: Math.min(p.dialogue, maxDialogue) };
}

export function loadPrologue(key = PROLOGUE_STORAGE_KEY): PrologueProgress {
  try { return normalizeCasPrologue(JSON.parse(localStorage.getItem(key) ?? 'null')); }
  catch { return initialPrologueProgress(); }
}

export function savePrologue(progress: PrologueProgress, key = PROLOGUE_STORAGE_KEY) {
  localStorage.setItem(key, JSON.stringify(progress));
}

export function completePrologueBattle(progress: PrologueProgress, stage: PrologueBattleStage): PrologueProgress {
  const [from, to] = battleExit[stage];
  if (progress.step !== from) return progress;
  return { ...progress, step: to, dialogue: 0, flags: { ...progress.flags, [`cas-${stage}`]: true } };
}

export function storyDialogue(progress: PrologueProgress): DialogueLine[] {
  const original = dialogueFor(progress);
  const replace = (index: number, text: string) => { original[index] = { ...original[index], text }; };
  // Preserve the old script as source. Only these lines referred to old
  // rules or promised a particular combat outcome. CAS judges real orders.
  switch (progress.step) {
    case 12:
      replace(0, '尾随航线已经确认。领舰先转，后面的姐妹沿着领舰的航迹通过转向点。');
      replace(1, '鱼雷可在机动途中发射。先拖到已发现的敌舰，再在合法扇区里调整发射方向。');
      break;
    case 18:
      replace(1, '改用同步移动。五艘舰在同一时刻转向，但各走各的航迹。');
      replace(2, '收到。我们先看清各舰的航迹，再争取一个安全的发射位置。');
      break;
    case 23:
      replace(0, '领舰的参考线已经确认，各舰会沿平移后的航路一起转向。现在给鱼雷选一个安全的发射方向。');
      break;
    case 29:
      replace(0, '鱼雷已经离管。航迹和战果都有记录，下一次，我们会比这一次配合得更好。');
      break;
  }
  return original;
}
