import type { EvolvedProfile } from './engine';
import { campaignBest } from './campaign-progress';
import type { CampaignProgress } from './campaign-progress';
import type { PortState } from './port';

/** Storefront projection of data/ai/shop-merge.json. The server catalog mirrors
 *  these fields; the local harbor store uses them while offline. */
export interface AiShopEntry {
  id: EvolvedProfile;
  name: string;
  description: string;
  unlock: string;
  stage: string;
  stageName: string;
  cost: number;
  currency: 'recruit_ticket';
  provisional: boolean;
}

export const AI_SHOP: readonly AiShopEntry[] = [
  {
    id: 'evo-screen', name: '帷幄 · 屏护协同',
    description: '以屏护与交叉火力为主：驱逐分队卡在敌雷击队与主力之间，炮战保持射界并抢 T 头。',
    unlock: 'campaign:CAMP-ALLIES-02', stage: 'CAMP-ALLIES-02', stageName: '埃斯佩兰斯角',
    cost: 800, currency: 'recruit_ticket', provisional: true,
  },
  {
    id: 'evo-torpedo', name: '夜潮 · 雷击突击',
    description: '以雷击为主：分队分头绕向敌纵队侧翼，压缩距离后按侧舷角放雷，炮战只做压制。',
    unlock: 'campaign:CAMP-ALLIES-03', stage: 'CAMP-ALLIES-03', stageName: '圣乔治角',
    cost: 900, currency: 'recruit_ticket', provisional: true,
  },
  {
    id: 'evo-gunnery', name: '铁幕 · 炮战纵队',
    description: '以炮战为主：保持远距射界，优先抢占敌纵队的 T 头位置，用交叉火力分散其指挥。',
    unlock: 'campaign:CAMP-ALLIES-11', stage: 'CAMP-ALLIES-11', stageName: '奥古斯塔皇后湾',
    cost: 1000, currency: 'recruit_ticket', provisional: true,
  },
];

export function aiShopStars(entry: AiShopEntry, progress: CampaignProgress | undefined) {
  return campaignBest(progress, entry.stage) ?? 0;
}

export function aiShopUnlocked(entry: AiShopEntry, progress: CampaignProgress | undefined) {
  return aiShopStars(entry, progress) > 0;
}

export function aiShopOwned(port: PortState, entry: AiShopEntry) {
  return port.profiles.includes(entry.id);
}

/** Why the buy button is disabled; undefined means it can be purchased. */
export function aiShopBlockReason(port: PortState, entry: AiShopEntry): string | undefined {
  if (aiShopOwned(port, entry)) return '已拥有，可在战斗 AI 风格中选择。';
  // The store unlock is a real campaign clear, matching the server check.
  if (!aiShopUnlocked(entry, port.campaignProgress)) {
    const stars = aiShopStars(entry, port.campaignProgress);
    return `通关「${entry.stageName}」（${entry.stage}）后开放购买；当前最好 ${stars} 星。`;
  }
  const missing = entry.cost - port.wallet.standard;
  if (missing > 0) return `常驻征募券不足，还差 ${missing} 张。`;
  return undefined;
}

/** Local (offline) purchase. Server accounts buy through /shop/purchase and
 *  receive the same profile id in meta.ai_profiles. */
export function buyAiShopEntry(port: PortState, entry: AiShopEntry): PortState {
  if (aiShopBlockReason(port, entry)) return port;
  return {
    ...port,
    wallet: { ...port.wallet, standard: port.wallet.standard - entry.cost },
    profiles: [...port.profiles, entry.id],
  };
}
