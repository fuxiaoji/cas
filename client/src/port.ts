import { isProfile } from './engine';
import type { Profile, Side } from './engine';
import { normalizeCampaignProgress } from './campaign-progress';
import type { CampaignProgress } from './campaign-progress';
import {
  FEATURED_SHIP, PLAYABLE_SHIPS, STARTER_SHIPS, shipCard, shipPoints,
} from './ship-catalog';
import type { ShipCard, ShipRarity } from './ship-catalog';

export const PORT_KEY = 'cas.harbor.progress.v1';
const MAX_HISTORY = 50;
export const lessons = [
  { id: 'lead', name: '选定领舰', detail: '开始前，在编队名单中选一艘非领舰，点「设为领舰」。' },
  { id: 'follow', name: '绘制尾随航路', detail: '选择领舰移动，至少添加两个途经点，再下达航线。' },
  { id: 'sync', name: '绘制同步航路', detail: '保持舰队同向，切到同步移动，校核并下达新的航线。' },
  { id: 'gun', name: '拖动炮击', detail: '按住舰上的「炮」，拖到一个可攻击的敌方接触后松开。' },
  { id: 'cancel', name: '取消火力手势', detail: '拖动炮标或雷标，移到海图上的取消区再松手。' },
  { id: 'torpedo', name: '调整鱼雷方向', detail: '机动到可用雷击扇区。拖向敌舰并停留，等出现推荐射向；继续调整方向，再松开下令。' },
  { id: 'override', name: '从 AI 手中接管', detail: '在战术 AI 中托管一项，然后亲自下达该项命令。' },
] as const;
export type Lesson = typeof lessons[number]['id'];
export type Pool = 'standard' | 'up';
type Wallet = Record<Pool, number>;

/** Every owned row is one unique IBS-U-* identity; duplicates turn into medals. */
export type OwnedShips = Record<string, true>;

export interface FleetPreset {
  side: Side;
  leaderSlot: number;
  profile: Profile;
  /** Exactly five same-side identities, one per slot. */
  ships: string[];
}
export interface Draw {
  id: number; pool: Pool; ship: string; duplicate: boolean; guaranteed: boolean; batchSize?: 10;
}
export interface LocalMail {
  id: string; title: string; body: string; sender: string; created: number; claimed: boolean;
  standard: number; up: number;
}
export function welcomeMail(): LocalMail {
  return { id: 'welcome-20', title: '内测启航补给', body: '20 次征募补给已放入邮箱，请在邮箱领取。',
    sender: '舰桥补给处', created: 0, claimed: false, standard: 20, up: 0 };
}
export interface PortState {
  version: 1; lessons: Lesson[]; starter: boolean; challengeClear: boolean; challengeClaim: boolean;
  wallet: Wallet; marks: number; pity: Wallet; owned: OwnedShips;
  profiles: Profile[]; preset: FleetPreset; upSide: Side; sequence: number; history: Draw[];
  credits: number; watch?: string; courses: string[]; attendance: number[];
  prologueReward?: boolean;
  campaignProgress?: CampaignProgress;
  challengeReceipts: Record<string, { time: number; first: boolean; claimed: boolean }>;
  weeklySupply?: string; weeklyTicket?: string; mail?: LocalMail[];
}
export type PortLaunch = {
  side: Side; profile: Profile; leaderSlot: number;
  /** Five local single-ship identities; only the harbour preset supplies this. */
  ships?: string[];
  variant?: 'challenge' | 'night'; training?: boolean;
  /** Fictional challenge stage id; the engine resolves the roster from stages.json. */
  stage?: string;
  seed?: number;
  enemy?: Profile;
};

/**
 * Gacha tiers use the source's four names (common/rare/elite/ur) and these
 * fixed weights.  Axis battleships are projected as `ur` by ship-catalog.ts.
 */
export const RARITY_WEIGHTS: Record<ShipRarity, number> = { ur: 2, elite: 8, rare: 20, common: 70 };
export const RARITY_ORDER: ShipRarity[] = ['ur', 'elite', 'rare', 'common'];
/** Duplicate identities convert into fleet medals by gacha rarity. */
export const DUPLICATE_MEDALS: Record<ShipRarity, number> = { ur: 5, elite: 3, rare: 2, common: 1 };

export function duplicateMedals(rarity: ShipRarity): number {
  return DUPLICATE_MEDALS[rarity];
}

function opposite(side: Side): Side { return side === 'allies' ? 'axis' : 'allies'; }
function fresh(): PortState {
  return { version: 1, lessons: [], starter: false, challengeClear: false, challengeClaim: false,
    wallet: { standard: 0, up: 0 }, marks: 0, pity: { standard: 0, up: 0 }, owned: {},
    profiles: ['coord'],
    preset: { side: 'allies', leaderSlot: 0, profile: 'coord', ships: [...STARTER_SHIPS.allies] },
    upSide: 'axis', sequence: 0, history: [], credits: 0, courses: [], attendance: [],
    challengeReceipts: {}, mail: [welcomeMail()] };
}
function nonnegative(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

/** Legacy 4-hull counters migrate onto the five starter identities of a side. */
const LEGACY_HULLS: Record<string, readonly string[]> = {
  fletcher: STARTER_SHIPS.allies.slice(0, 4),
  cleveland: [STARTER_SHIPS.allies[4]],
  kagero: STARTER_SHIPS.axis.slice(0, 4),
  sendai: [STARTER_SHIPS.axis[4]],
};
const LEGACY_DRAW_HULL: Record<string, string> = {
  fletcher: STARTER_SHIPS.allies[0],
  cleveland: STARTER_SHIPS.allies[4],
  kagero: STARTER_SHIPS.axis[0],
  sendai: STARTER_SHIPS.axis[4],
};

/** Identity catalogue only; unknown and collection-only rows are dropped. */
function migrateOwned(raw: unknown): OwnedShips {
  const owned: OwnedShips = {};
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return owned;
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    const legacy = LEGACY_HULLS[key];
    if (legacy) {
      const count = typeof value === 'number' && Number.isSafeInteger(value) ? value : 0;
      legacy.slice(0, Math.min(count, 4, legacy.length)).forEach(id => { owned[id] = true; });
      continue;
    }
    const card = shipCard(key);
    if (!card || !card.playable) continue;
    if (value === true || (typeof value === 'number' && value > 0)) owned[key] = true;
  }
  return owned;
}

function normalizeShips(value: unknown, side: Side): string[] {
  const raw = Array.isArray(value) ? value.filter((id): id is string => typeof id === 'string') : [];
  const valid = raw.filter(id => {
    const card = shipCard(id);
    return !!card && card.playable && card.side === side;
  });
  const fallback = [
    ...STARTER_SHIPS[side],
    ...PLAYABLE_SHIPS.filter(card => card.side === side).map(card => card.id),
  ];
  const ships: string[] = [];
  for (const id of [...valid, ...fallback]) {
    if (ships.length === 5) break;
    if (!ships.includes(id)) ships.push(id);
  }
  return ships;
}

function normalizePreset(raw: Partial<FleetPreset> & { ships?: unknown }, side: Side): FleetPreset {
  const leaderSlot = nonnegative(raw.leaderSlot) ? Math.min(4, raw.leaderSlot) : 0;
  return { side, leaderSlot, profile: isProfile(raw.profile) ? raw.profile : 'coord',
    ships: normalizeShips(raw.ships, side) };
}

function normalizeHistory(raw: unknown): Draw[] {
  if (!Array.isArray(raw)) return [];
  const history: Draw[] = [];
  for (const row of raw) {
    if (!row || typeof row !== 'object') continue;
    const value = row as Record<string, unknown>;
    const id = nonnegative(value.id) && value.id > 0 ? value.id : 0;
    if (!id) continue;
    const ship = typeof value.ship === 'string' && shipCard(value.ship)?.playable ? value.ship
      : typeof value.hull === 'string' ? LEGACY_DRAW_HULL[value.hull] : undefined;
    if (!ship) continue;
    history.push({
      id, pool: value.pool === 'up' ? 'up' : 'standard', ship,
      duplicate: value.duplicate === true, guaranteed: value.guaranteed === true,
      ...(value.batchSize === 10 ? { batchSize: 10 as const } : {}),
    });
    if (history.length >= MAX_HISTORY) break;
  }
  return history;
}

type StoredState = Omit<PortState, 'owned' | 'history' | 'preset' | 'watch'> & {
  owned?: unknown; history?: unknown; watch?: unknown;
  preset?: Partial<FleetPreset> & { ships?: unknown };
};

export function loadPort(key = PORT_KEY): PortState {
  try {
    const s = JSON.parse(localStorage.getItem(key) ?? 'null') as StoredState | null;
    if (!s || s.version !== 1 || !Array.isArray(s.lessons) || !Array.isArray(s.profiles) ||
      !s.preset || (s.preset.side !== 'allies' && s.preset.side !== 'axis') || !nonnegative(s.preset.leaderSlot) ||
      s.preset.leaderSlot > 4 || !s.owned || !s.wallet || !s.pity ||
      !nonnegative(s.wallet.standard) || !nonnegative(s.wallet.up) ||
      !nonnegative(s.pity.standard) || !nonnegative(s.pity.up) || !nonnegative(s.marks) ||
      !nonnegative(s.sequence)) return fresh();
    const side: Side = s.preset.side === 'axis' ? 'axis' : 'allies';
    const owned = migrateOwned(s.owned);
    const profiles = [...new Set((Array.isArray(s.profiles) ? s.profiles : []).filter(isProfile))];
    if (!profiles.length) profiles.push('coord');
    const preset = normalizePreset(s.preset, side);
    const history = normalizeHistory(s.history);
    const challengeReceipts = Object.fromEntries(Object.entries(s.challengeReceipts ?? {}).filter(([id, row]) =>
      /^[0-9a-f-]{36}$/i.test(id) && row && nonnegative(row.time) && typeof row.first === 'boolean' && typeof row.claimed === 'boolean'));
    const mail = Array.isArray(s.mail) ? s.mail.filter(letter => letter && typeof letter.id === 'string' &&
      typeof letter.title === 'string' && typeof letter.body === 'string' && typeof letter.sender === 'string' &&
      typeof letter.claimed === 'boolean' && nonnegative(letter.standard) && nonnegative(letter.up)) : [welcomeMail()];
    const watch = typeof s.watch === 'string' && owned[s.watch] === true ? s.watch : undefined;
    return { ...s, owned, profiles, preset, history, challengeReceipts,
      campaignProgress: normalizeCampaignProgress(s.campaignProgress),
      credits: nonnegative(s.credits) ? s.credits : 0, mail, watch,
      courses: Array.isArray(s.courses) ? [...new Set(s.courses.filter(v => typeof v === 'string'))] : [],
      attendance: Array.isArray(s.attendance) ? [...new Set(s.attendance.filter(nonnegative))].sort((a,b)=>a-b).slice(0,7) : [],
      upSide: s.upSide === 'allies' || s.upSide === 'axis' ? s.upSide : side === 'allies' ? 'axis' : 'allies' };
  } catch { return fresh(); }
}
export function claimLocalMail(s: PortState, id: string): PortState {
  const letter = s.mail?.find(item => item.id === id);
  if (!letter || letter.claimed) return s;
  return { ...s, credits: s.credits,
    wallet: { standard: s.wallet.standard + letter.standard, up: s.wallet.up + letter.up },
    mail: s.mail!.map(item => item.id === id ? { ...item, claimed: true } : item) };
}
export function writePort(s: PortState, key = PORT_KEY) { localStorage.setItem(key, JSON.stringify(s)); }
export function recordLesson(s: PortState, id: Lesson): PortState {
  return s.lessons.includes(id) ? s : { ...s, lessons: [...s.lessons, id] };
}
export function receiveStarter(s: PortState, side: Side): PortState {
  if (s.starter || !lessons.every(({ id }) => s.lessons.includes(id))) return s;
  return starterFleet(s, side);
}
function starterFleet(s: PortState, side: Side): PortState {
  const owned = { ...s.owned };
  for (const id of STARTER_SHIPS[side]) owned[id] = true;
  return { ...s, starter: true, owned,
    preset: { ...s.preset, side, leaderSlot: 0, ships: [...STARTER_SHIPS[side]] },
    upSide: opposite(side), wallet: { standard: s.wallet.standard + 10, up: s.wallet.up + 10 } };
}
export function grantPrologue(s: PortState): PortState {
  if (s.prologueReward) return s;
  const next = s.starter ? s : starterFleet(s, 'allies');
  return { ...next, credits: next.credits + 2000, prologueReward: true,
    courses: next.courses.includes('prologue') ? next.courses : [...next.courses, 'prologue'] };
}

/** Escapes repeated identities into one owned row; the preset must be five owned hulls. */
export function meetsRoster(s: PortState) {
  const ships = s.preset.ships;
  return ships.length === 5 && new Set(ships).size === 5 &&
    ships.every(id => s.owned[id] === true && shipCard(id)?.side === s.preset.side);
}

export function ownedShips(s: PortState, side?: Side): ShipCard[] {
  return PLAYABLE_SHIPS
    .filter(card => s.owned[card.id] === true && (!side || card.side === side))
    .sort((a, b) => RARITY_ORDER.indexOf(a.gachaRarity) - RARITY_ORDER.indexOf(b.gachaRarity) ||
      a.type.localeCompare(b.type) || a.name.localeCompare(b.name, 'zh-CN'));
}

/** Five same-side slots: prefer the player's owned hulls, then the printed starters. */
export function defaultFleet(s: PortState, side: Side): string[] {
  const ships: string[] = [];
  const push = (id: string) => {
    if (ships.length < 5 && !ships.includes(id)) ships.push(id);
  };
  ownedShips(s, side).forEach(card => push(card.id));
  STARTER_SHIPS[side].forEach(push);
  PLAYABLE_SHIPS.filter(card => card.side === side).forEach(card => push(card.id));
  return ships.slice(0, 5);
}

export function fleetPoints(ships: readonly string[]): number {
  return ships.reduce((sum, id) => sum + shipPoints(id), 0);
}

/** Both pools draw from the full playable catalogue; only the UP boost differs. */
export function poolShips(): ShipCard[] {
  return [...PLAYABLE_SHIPS];
}

function tierPool(rarity: ShipRarity): ShipCard[] {
  return PLAYABLE_SHIPS.filter(card => card.gachaRarity === rarity);
}

/** Per-draw chance for one hull, including the UP banner's 50% share of UR. */
export function drawChance(card: ShipCard, pool: Pool): number {
  const tierWeight = RARITY_WEIGHTS[card.gachaRarity];
  const tier = tierPool(card.gachaRarity);
  if (pool === 'up') {
    const featuredCard = shipCard(FEATURED_SHIP);
    if (card.id === FEATURED_SHIP) return tierWeight / 100 * 0.5;
    if (featuredCard?.gachaRarity === card.gachaRarity && tier.length > 1) {
      return tierWeight / 100 * 0.5 / (tier.length - 1);
    }
  }
  return tier.length ? tierWeight / 100 / tier.length : 0;
}

function rollRarity(word: number, guaranteed: boolean): ShipRarity {
  const point = word / 4294967296 * (guaranteed ? 30 : 100);
  if (guaranteed) return point < 20 ? 'rare' : point < 28 ? 'elite' : 'ur';
  return point < 2 ? 'ur' : point < 10 ? 'elite' : point < 30 ? 'rare' : 'common';
}

function drawOne(s: PortState, pool: Pool, rarityWord: number,
  featureWord: number, indexWord: number): PortState {
  const guaranteed = s.pity[pool] >= 9;
  const rarity = rollRarity(rarityWord, guaranteed);
  const candidates = PLAYABLE_SHIPS.filter(card => card.gachaRarity === rarity);
  if (!candidates.length) return s;
  const featuredCard = shipCard(FEATURED_SHIP);
  const useFeatured = pool === 'up' && featuredCard?.gachaRarity === rarity &&
    featureWord < 2147483648;
  const others = candidates.filter(card => pool !== 'up' || card.id !== FEATURED_SHIP);
  const choices = useFeatured ? candidates.filter(card => card.id === FEATURED_SHIP) : others.length ? others : candidates;
  const pick = choices[indexWord % choices.length];
  const duplicate = s.owned[pick.id] === true;
  const draw: Draw = { id: s.sequence + 1, pool, ship: pick.id, duplicate, guaranteed };
  return { ...s, wallet: { ...s.wallet, [pool]: s.wallet[pool] - 1 },
    pity: { ...s.pity, [pool]: guaranteed || rarity !== 'common' ? 0 : s.pity[pool] + 1 },
    owned: duplicate ? s.owned : { ...s.owned, [pick.id]: true },
    marks: s.marks + (duplicate ? duplicateMedals(rarity) : 0),
    sequence: draw.id, history: [draw, ...s.history].slice(0, MAX_HISTORY) };
}

/**
 * Draw one or ten single-ship identities.  The caller supplies three 32-bit
 * words per draw (rarity, UP-feature, index) so every step stays deterministic.
 */
export function drawRecruit(s: PortState, pool: Pool, source = crypto.getRandomValues(new Uint32Array(3))): PortState {
  if (source.length % 3 !== 0) return s;
  const count = source.length / 3;
  if ((count !== 1 && count !== 10) || s.wallet[pool] < count) return s;
  let result = s;
  for (let i = 0; i < count; i++) {
    result = drawOne(result, pool, source[3 * i], source[3 * i + 1], source[3 * i + 2]);
  }
  if (count === 1) return result;
  const [last, ...earlier] = result.history;
  return { ...result, history: [{ ...last, batchSize: 10 }, ...earlier] };
}

export function recruitReceipt(history: PortState['history'], id: number) {
  const last = history.find(draw => draw.id === id);
  if (!last) return [];
  if (last.batchSize !== 10) return [last];
  const batch = history.filter(draw => draw.pool === last.pool && draw.id > id - 10 && draw.id <= id)
    .sort((a, b) => a.id - b.id);
  return batch.length === 10 && batch.every((draw, index) => draw.id === id - 9 + index) ? batch : [last];
}
export function receiveChallenge(s: PortState): PortState {
  if (!s.challengeClear || s.challengeClaim) return s;
  return { ...s, challengeClaim: true, wallet: { ...s.wallet, standard: s.wallet.standard + 2 },
    profiles: s.profiles.includes('torpedo') ? s.profiles : [...s.profiles, 'torpedo'] };
}
export function getGunnery(s: PortState): PortState {
  if (s.marks < 6 || s.profiles.includes('gunnery')) return s;
  return { ...s, marks: s.marks - 6, profiles: [...s.profiles, 'gunnery'] };
}
