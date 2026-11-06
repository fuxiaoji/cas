import type { Profile, Side } from './engine';

export const PORT_KEY = 'cas.harbor.progress.v1';
const MAX_HISTORY = 20;
export const hulls = {
  fletcher: { name: '弗莱彻级', side: 'allies', kind: '驱逐舰', max: 4 },
  cleveland: { name: '克利夫兰级', side: 'allies', kind: '轻巡洋舰', max: 1 },
  kagero: { name: '阳炎级', side: 'axis', kind: '驱逐舰', max: 4 },
  sendai: { name: '川内级', side: 'axis', kind: '轻巡洋舰', max: 1 },
} as const;
export type Hull = keyof typeof hulls;
export const rosters: Record<Side, Hull[]> = {
  allies: ['fletcher', 'cleveland', 'fletcher', 'fletcher', 'fletcher'],
  axis: ['kagero', 'sendai', 'kagero', 'kagero', 'kagero'],
};
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
type Pool = 'standard' | 'up';
type Wallet = Record<Pool, number>;
export interface FleetPreset { side: Side; leaderSlot: number; profile: Profile }
interface Draw { id: number; pool: Pool; hull: Hull; duplicate: boolean; guaranteed: boolean }
export interface PortState {
  version: 1; lessons: Lesson[]; starter: boolean; challengeClear: boolean; challengeClaim: boolean;
  wallet: Wallet; marks: number; pity: Wallet; owned: Partial<Record<Hull, number>>;
  profiles: Profile[]; preset: FleetPreset; upSide: Side; sequence: number; history: Draw[];
  credits: number; watch?: Hull; courses: string[]; attendance: number[];
  prologueReward?: boolean;
  challengeReceipts: Record<string, { time: number; first: boolean; claimed: boolean }>;
  weeklySupply?: string; weeklyTicket?: string;
}
export type PortLaunch = { side: Side; profile: Profile; leaderSlot: number; variant?: 'challenge' | 'night'; training?: boolean };
function fresh(): PortState {
  return { version: 1, lessons: [], starter: false, challengeClear: false, challengeClaim: false,
    wallet: { standard: 0, up: 0 }, marks: 0, pity: { standard: 0, up: 0 }, owned: {},
    profiles: ['coord'], preset: { side: 'allies', leaderSlot: 0, profile: 'coord' }, upSide: 'axis', sequence: 0, history: [],
    credits: 0, courses: [], attendance: [], challengeReceipts: {} };
}
function nonnegative(value: unknown) { return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0; }
export function loadPort(key = PORT_KEY): PortState {
  try {
    const s = JSON.parse(localStorage.getItem(key) ?? 'null') as PortState | null;
    if (!s || s.version !== 1 || !Array.isArray(s.lessons) || !Array.isArray(s.history) || !Array.isArray(s.profiles) ||
      !s.preset || !['allies', 'axis'].includes(s.preset.side) || !nonnegative(s.preset.leaderSlot) || s.preset.leaderSlot > 4 ||
      !s.owned || !s.wallet || !s.pity || !nonnegative(s.wallet.standard) || !nonnegative(s.wallet.up) ||
      !nonnegative(s.pity.standard) || !nonnegative(s.pity.up) || !nonnegative(s.marks) || !nonnegative(s.sequence)) return fresh();
    const owned = Object.fromEntries((Object.keys(hulls) as Hull[]).filter(id => nonnegative(s.owned[id])).map(id => [id, Math.min(hulls[id].max, s.owned[id] ?? 0)]));
    const challengeReceipts = Object.fromEntries(Object.entries(s.challengeReceipts ?? {}).filter(([id, row]) =>
      /^[0-9a-f-]{36}$/i.test(id) && row && nonnegative(row.time) && typeof row.first === 'boolean' && typeof row.claimed === 'boolean'));
    return { ...s, owned, challengeReceipts, credits: nonnegative(s.credits) ? s.credits : 0,
      courses: Array.isArray(s.courses) ? [...new Set(s.courses.filter(v => typeof v === 'string'))] : [],
      attendance: Array.isArray(s.attendance) ? [...new Set(s.attendance.filter(nonnegative))].sort((a,b)=>a-b).slice(0,7) : [],
      watch: s.watch && Object.hasOwn(hulls, s.watch) ? s.watch : undefined,
      upSide: s.upSide === 'allies' || s.upSide === 'axis' ? s.upSide : s.preset.side === 'allies' ? 'axis' : 'allies' };
  } catch { return fresh(); }
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
  for (const hull of rosters[side]) owned[hull] = Math.min(hulls[hull].max, (owned[hull] ?? 0) + 1);
  return { ...s, starter: true, owned, preset: { ...s.preset, side, leaderSlot: 0 }, upSide: side === 'allies' ? 'axis' : 'allies',
    wallet: { standard: s.wallet.standard + 10, up: s.wallet.up + 10 } };
}
export function grantPrologue(s: PortState): PortState {
  if (s.prologueReward) return s;
  const next = s.starter ? s : starterFleet(s, 'allies');
  return { ...next, credits: next.credits + 2000, prologueReward: true,
    courses: next.courses.includes('prologue') ? next.courses : [...next.courses, 'prologue'] };
}
export function meetsRoster(s: PortState, side: Side, challenge = false) {
  const needed: Partial<Record<Hull, number>> = {};
  for (const id of rosters[side].slice(0, challenge ? 3 : 5)) needed[id] = (needed[id] ?? 0) + 1;
  return (Object.keys(needed) as Hull[]).every((id) => (s.owned[id] ?? 0) >= (needed[id] ?? Infinity));
}
export function drawRecruit(s: PortState, pool: Pool): PortState {
  if (s.wallet[pool] <= 0 || !s.starter) return s;
  const source = crypto.getRandomValues(new Uint32Array(2));
  const chance = source[0] / 4294967296;
  const side = pool === 'up' ? s.upSide : source[1] % 2 === 0 ? 'allies' : 'axis';
  const guaranteed = s.pity[pool] >= 9;
  const rare = guaranteed || chance < .15;
  const id = rosters[side][rare ? 1 : 0];
  const quantity = s.owned[id] ?? 0;
  const duplicate = quantity >= hulls[id].max;
  const draw: Draw = { id: s.sequence + 1, pool, hull: id, duplicate, guaranteed };
  return { ...s, wallet: { ...s.wallet, [pool]: s.wallet[pool] - 1 },
    pity: { ...s.pity, [pool]: rare ? 0 : s.pity[pool] + 1 },
    owned: duplicate ? s.owned : { ...s.owned, [id]: quantity + 1 },
    marks: s.marks + (duplicate ? rare ? 3 : 1 : 0), sequence: draw.id, history: [draw, ...s.history].slice(0, MAX_HISTORY) };
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
