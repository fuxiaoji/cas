import type { PortState } from '../port';
import { challengeStages } from './challenge-stages';
import type { ChallengeStage } from './challenge-stages';

/**
 * Fictional challenge ladder state. It lives in the local port document as an
 * extra property (loadPort preserves unknown fields), so progress is per local
 * account without changing the frozen PortState schema in port.ts.
 */
export interface ChallengeLadder {
  version: 1;
  cleared: string[];
  selected: string;
}

interface PendingChallenge {
  stageId: string;
  started: number;
}

type ChallengeCarrier = PortState & {
  challengeLadder?: unknown;
  challengePending?: unknown;
};

export const CHALLENGE_LADDER_VERSION = 1;
export const playableChallengeStages: readonly ChallengeStage[] = challengeStages
  .filter((stage) => stage.status === 'playable')
  .slice()
  .sort((a, b) => a.order - b.order);

const knownStages = new Map(challengeStages.map((stage) => [stage.id, stage]));

export function challengeStage(id: string): ChallengeStage | undefined {
  return knownStages.get(id);
}

function firstPlayable(): ChallengeStage {
  return playableChallengeStages[0];
}

function defaultSelection(cleared: readonly string[]): string {
  return playableChallengeStages.find((stage) => !cleared.includes(stage.id))?.id
    ?? playableChallengeStages[playableChallengeStages.length - 1]?.id
    ?? '';
}

function rawLadder(state: PortState): unknown {
  return (state as ChallengeCarrier).challengeLadder;
}

function isLadder(value: unknown): value is ChallengeLadder {
  if (!value || typeof value !== 'object') return false;
  const row = value as { version?: unknown; cleared?: unknown; selected?: unknown };
  return row.version === CHALLENGE_LADDER_VERSION
    && Array.isArray(row.cleared)
    && row.cleared.every((id) => typeof id === 'string' && knownStages.get(id)?.status === 'playable')
    && typeof row.selected === 'string'
    && knownStages.has(row.selected);
}

/**
 * Existing saves have a single `challengeClear` bit. Treat that as a clear of
 * stage 1 so a player who already beat the 3-vs-5 challenge does not have to
 * replay it; newer saves carry the full ladder.
 */
export function challengeLadder(state: PortState): ChallengeLadder {
  const raw = rawLadder(state);
  if (isLadder(raw)) {
    const cleared = [...new Set(raw.cleared)];
    return {
      version: CHALLENGE_LADDER_VERSION,
      cleared,
      selected: knownStages.get(raw.selected)?.id ?? defaultSelection(cleared),
    };
  }
  const cleared = state.challengeClear && firstPlayable() ? [firstPlayable().id] : [];
  return {
    version: CHALLENGE_LADDER_VERSION,
    cleared,
    selected: defaultSelection(cleared),
  };
}

function withLadder(state: PortState, ladder: ChallengeLadder): PortState {
  return { ...state, challengeLadder: ladder } as PortState;
}

export function stageUnlocked(ladder: ChallengeLadder, stage: ChallengeStage): boolean {
  if (stage.status !== 'playable') return false;
  if (stage.order === 1) return true;
  const previous = playableChallengeStages.find((row) => row.order === stage.order - 1);
  return previous ? ladder.cleared.includes(previous.id) : false;
}

export function selectedChallengeStage(state: PortState): ChallengeStage | undefined {
  const ladder = challengeLadder(state);
  return knownStages.get(ladder.selected) ?? firstPlayable();
}

export function challengeProgress(state: PortState): { cleared: number; total: number } {
  return { cleared: challengeLadder(state).cleared.length, total: playableChallengeStages.length };
}

export function selectChallengeStage(state: PortState, id: string): PortState {
  const stage = knownStages.get(id);
  if (!stage) return state;
  const ladder = challengeLadder(state);
  if (stage.status === 'playable' && !stageUnlocked(ladder, stage)) return state;
  if (ladder.selected === id) return state;
  return withLadder(state, { ...ladder, selected: id });
}

/**
 * Record the selected stage and the pending clear. The actual clear is only
 * committed when the engine reports `result.primary`; see recordChallengeClear.
 */
export function beginChallengeStage(state: PortState, id: string): PortState {
  const stage = knownStages.get(id);
  if (!stage || stage.status !== 'playable') return state;
  const ladder = challengeLadder(state);
  if (!stageUnlocked(ladder, stage)) return state;
  const next: ChallengeLadder = { ...ladder, selected: id };
  const pending: PendingChallenge = { stageId: id, started: Date.now() };
  return { ...withLadder(state, next), challengePending: pending } as PortState;
}

export function pendingChallengeStage(state: PortState): string | undefined {
  const pending = (state as ChallengeCarrier).challengePending;
  if (!pending || typeof pending !== 'object') return undefined;
  const stageId = (pending as { stageId?: unknown }).stageId;
  return typeof stageId === 'string' && knownStages.get(stageId)?.status === 'playable'
    ? stageId
    : undefined;
}

/**
 * Commit the pending stage after the engine reports the challenge primary
 * objective. Idempotent: replaying a cleared stage keeps the ladder unchanged.
 */
export function completePendingChallenge(state: PortState): PortState {
  const stageId = pendingChallengeStage(state);
  if (!stageId) {
    if (!(state as ChallengeCarrier).challengePending) return state;
    return { ...state, challengePending: undefined } as PortState;
  }
  const stage = knownStages.get(stageId);
  if (!stage) return { ...state, challengePending: undefined } as PortState;
  const ladder = challengeLadder(state);
  const cleared = ladder.cleared.includes(stageId) ? ladder.cleared : [...ladder.cleared, stageId];
  const nextPlayable = playableChallengeStages.find((row) => row.order === stage.order + 1);
  const selected = stage.id === ladder.selected && nextPlayable ? nextPlayable.id : ladder.selected;
  return {
    ...withLadder(state, { ...ladder, cleared, selected }),
    challengePending: undefined,
  } as PortState;
}
