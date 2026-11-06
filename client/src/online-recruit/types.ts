export type Rarity = 'common' | 'elite' | 'rare' | 'ur';
export type RecruitShip = { id: string; name: string; rarity: Rarity; type: string; recruitable: boolean; credits_price: number; combat_ready: boolean };
export type RecruitPool = {
  id: string; name: string; kind: 'up' | 'standard'; featured_ship_id?: string; ur_ship_ids: string[];
  rates: Record<Rarity, number>; pity: Record<Exclude<Rarity, 'common'>, number>;
  exchange_price: number; description: string;
};
export type RecruitReceipt = { id: string; ship_id: string; rarity: Rarity; duplicate: boolean; index?: number; batch?: number };
export type RecruitProgress = {
  exchange_points: number; since_elite: number; since_rare: number; since_ur?: number;
  up_guaranteed?: boolean; history?: RecruitReceipt[];
};
export const rarityNames: Record<Rarity, string> = { common: '普通', elite: '精锐', rare: '稀有', ur: 'UR' };
