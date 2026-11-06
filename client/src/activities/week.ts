// Calendar and reward amounts from 铁底湾 mobile/src/meta/store.ts (3ba9c5b).
import type { PortState } from '../port';

export function beijingWeek(now = Date.now()): { key: string; start: number; end: number } {
  const dayMs = 86400000, offset = 8 * 3600000, day = Math.floor((now + offset) / dayMs), monday = day - ((day + 3) % 7);
  const date = new Date(monday * dayMs), start = monday * dayMs - offset;
  return { key: `${date.getUTCFullYear()}-${date.getUTCMonth() + 1}-${date.getUTCDate()}`, start, end: start + 7 * dayMs };
}
export const CHALLENGE_WEEKLY_LIMIT = 3;
export const CHALLENGE_WEEKLY_TICKETS = 2;
export const WEEKLY_TICKET_PRICE = 500;

export function recordChallengeClear(state: PortState, id?: string, now = Date.now()): PortState {
  if (!id) return state.challengeClear ? state : { ...state, challengeClear: true };
  if (Object.hasOwn(state.challengeReceipts, id)) return state;
  return { ...state, challengeClear: true, challengeReceipts: {
    ...state.challengeReceipts, [id]: { time: now, first: !state.challengeClear, claimed: false },
  } };
}
export function weeklyStatus(state: PortState, now = Date.now()) {
  const week = beijingWeek(now);
  const inWeek = Object.entries(state.challengeReceipts).filter(([, entry]) => entry.time >= week.start && entry.time < week.end);
  const repeats = inWeek.filter(([, entry]) => !entry.first);
  const claimed = repeats.filter(([, entry]) => entry.claimed).length;
  const pending = repeats.filter(([, entry]) => !entry.claimed).map(([id]) => id);
  return { ...week, claimed, pending, count: inWeek.length, supply: state.weeklySupply === week.key, ticket: state.weeklyTicket === week.key };
}
export function claimRepeat(state: PortState, now = Date.now()): PortState {
  const status = weeklyStatus(state, now);
  const id = status.pending[0];
  if (!id || status.claimed >= CHALLENGE_WEEKLY_LIMIT) return state;
  return { ...state, wallet: { ...state.wallet, standard: state.wallet.standard + CHALLENGE_WEEKLY_TICKETS },
    challengeReceipts: { ...state.challengeReceipts, [id]: { ...state.challengeReceipts[id], claimed: true } } };
}
export function buyWeeklyTicket(state: PortState, now = Date.now()): PortState {
  const week = weeklyStatus(state, now);
  if (week.ticket || state.credits < WEEKLY_TICKET_PRICE) return state;
  return { ...state, weeklyTicket: week.key, credits: state.credits - WEEKLY_TICKET_PRICE,
    wallet: { ...state.wallet, standard: state.wallet.standard + 1 } };
}
export function claimWeeklySupply(state: PortState, now = Date.now()): PortState {
  const week = weeklyStatus(state, now);
  if (week.count < 3 || week.supply) return state;
  return { ...state, weeklySupply: week.key, credits: state.credits + 500,
    wallet: { ...state.wallet, standard: state.wallet.standard + 3 } };
}
