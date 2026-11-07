import type { PortState } from './port';

export const campaignDifficulties = { story: '故事', standard: '标准', challenge: '挑战' } as const;
export type CampaignDifficulty = keyof typeof campaignDifficulties;
export type CampaignGrade = 'none' | 'tactical' | 'decisive';
export interface CampaignLaunch { stageId: string; difficulty: CampaignDifficulty }
export interface CampaignMission extends CampaignLaunch {
  missionLabel: string;
  objectives: string;
  supplyZone?: { x: number; y: number; radius: number; label: string };
  supplySeconds?: number;
  supplyComplete?: boolean;
}
export interface CampaignOutcome { grade?: CampaignGrade; primary?: string | boolean }
export type CampaignStars = 0 | 1 | 2 | 3;
type StageProgress = { best: Partial<Record<CampaignDifficulty, CampaignStars>>; claimed: CampaignStars };
export type CampaignProgress = Record<string, StageProgress>;

const validStage = (id: string) => /^CAMP-(ALLIES|AXIS)-\d{2}$/.test(id);
const validStars = (value: unknown): value is CampaignStars => value === 0 || value === 1 || value === 2 || value === 3;

export function campaignStars(result: CampaignOutcome): CampaignStars {
  return result.grade === 'decisive' ? 3 : result.grade === 'tactical' ? 2 : 0;
}

export function campaignBest(progress: CampaignProgress | undefined, stageId: string, difficulty?: CampaignDifficulty): CampaignStars | undefined {
  const best = progress?.[stageId]?.best;
  if (!best) return undefined;
  if (difficulty) return best[difficulty];
  return Math.max(0, ...Object.values(best)) as CampaignStars;
}

export function normalizeCampaignProgress(value: unknown): CampaignProgress {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  const progress: CampaignProgress = {};
  for (const [id, input] of Object.entries(value)) {
    if (!validStage(id) || !input || typeof input !== 'object' || Array.isArray(input) || !input.best || typeof input.best !== 'object') continue;
    const best: StageProgress['best'] = {};
    for (const key of Object.keys(campaignDifficulties) as CampaignDifficulty[]) {
      if (validStars(input.best[key])) best[key] = input.best[key];
    }
    if (!Object.keys(best).length) continue;
    const max = Math.max(...Object.values(best));
    progress[id] = { best, claimed: validStars(input.claimed) ? Math.min(max, input.claimed) as CampaignStars : 0 };
  }
  return progress;
}

export function recordCampaignResult(port: PortState, campaign: CampaignLaunch, outcome: CampaignOutcome): PortState {
  const { stageId, difficulty } = campaign;
  if (!validStage(stageId) || !Object.hasOwn(campaignDifficulties, difficulty) ||
      !['none', 'tactical', 'decisive'].includes(outcome.grade ?? '')) return port;
  const previous = port.campaignProgress?.[stageId];
  const stars = campaignStars(outcome);
  const previousBest = previous?.best[difficulty];
  if (previousBest !== undefined && previousBest >= stars) return port;
  return { ...port, campaignProgress: { ...port.campaignProgress, [stageId]: {
    best: { ...previous?.best, [difficulty]: stars }, claimed: previous?.claimed ?? 0,
  } } };
}

const capeRewards = [
  { stars: 1, title: '首通补给', credits: 400, tickets: 1, marks: 0 },
  { stars: 2, title: '战术胜利奖励', credits: 200, tickets: 1, marks: 0 },
  { stars: 3, title: '决定胜利奖励', credits: 0, tickets: 2, marks: 10 },
] as const;
const channelStarRewards = [
  { stars: 2, title: '保存舰队', credits: 200, tickets: 1, marks: 0 },
  { stars: 3, title: '战术星章', credits: 0, tickets: 2, marks: 10 },
] as const;
const rewardsByStage: Record<string, readonly CampaignReward[]> = {
  'CAMP-ALLIES-01': [{ stars: 1, title: '首通补给与舰队勋章', credits: 700, tickets: 1, marks: 5 }, ...channelStarRewards],
  'CAMP-AXIS-01': [{ stars: 1, title: '首通补给', credits: 400, tickets: 1, marks: 0 }, ...channelStarRewards],
  'CAMP-ALLIES-03': capeRewards,
  'CAMP-AXIS-03': capeRewards,
  'CAMP-ALLIES-04': [{ stars: 1, title: '首通补给', credits: 400, tickets: 1, marks: 0 }, ...channelStarRewards],
  'CAMP-AXIS-04': [{ stars: 1, title: '首通补给', credits: 400, tickets: 1, marks: 0 }, ...channelStarRewards],
  'CAMP-ALLIES-11': capeRewards,
  'CAMP-AXIS-11': capeRewards,
};
type CampaignReward = { stars: Exclude<CampaignStars, 0>; title: string; credits: number; tickets: number; marks: number };
export function campaignRewards(stageId: string): readonly CampaignReward[] { return rewardsByStage[stageId] ?? []; }
export function pendingCampaignRewards(progress: CampaignProgress | undefined, stageId: string) {
  const best = campaignBest(progress, stageId) ?? 0;
  const claimed = progress?.[stageId]?.claimed ?? 0;
  return campaignRewards(stageId).filter((reward) => reward.stars > claimed && reward.stars <= best);
}
export function campaignRewardText(reward: CampaignReward) {
  return [reward.credits && `${reward.credits} 补给币`, reward.tickets && `${reward.tickets} 张常驻券`, reward.marks && `${reward.marks} 舰队勋章`]
    .filter(Boolean).join('、');
}

export function claimCampaignRewards(port: PortState, stageId: string): PortState {
  const old = port.campaignProgress?.[stageId];
  const pending = pendingCampaignRewards(port.campaignProgress, stageId);
  if (!old || !pending.length) return port;
  const reward = pending.reduce((sum, item) => ({ credits: sum.credits + item.credits,
    tickets: sum.tickets + item.tickets, marks: sum.marks + item.marks }), { credits: 0, tickets: 0, marks: 0 });
  return { ...port, credits: port.credits + reward.credits, marks: port.marks + reward.marks,
    wallet: { ...port.wallet, standard: port.wallet.standard + reward.tickets },
    campaignProgress: { ...port.campaignProgress, [stageId]: { ...old, claimed: pending.at(-1)!.stars } } };
}
