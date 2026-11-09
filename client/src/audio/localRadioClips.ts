import type { Side } from '../engine';

const files = import.meta.glob<string>('./assets/*.m4a', { eager: true, import: 'default', query: '?url' });
const archive = import.meta.glob<string>('./archive/*.wav', { eager: true, import: 'default', query: '?url' });
const synthetic = import.meta.glob<string>('./synthetic/*.wav', { eager: true, import: 'default', query: '?url' });

export function localClip(side: Side, cue: string) {
  const pack = side === 'allies' ? 'wows-us' : 'wows-jp';
  const exact = files[`./assets/${pack}-${cue}-0.m4a`];
  // The private sample has only the original generic warning. Never voice a
  // direction from geometry the current seat does not have.
  return exact ?? (cue.startsWith('torpedo_warning_') ? files[`./assets/${pack}-torpedo_warning-0.m4a`] : undefined);
}

function archiveHead(side: Side, cue: string, variant?: string) {
  const prefix = side === 'allies' ? 'allies' : 'axis';
  return `./archive/${prefix}-${cue}${variant ? `-${variant}` : ''}-`;
}

// A cue/variant can carry several numbered takes. BattleVoice picks one at
// random and avoids the previous file for the same cue.
export function archiveClips(side: Side, cue: string, variant?: string): string[] {
  const head = archiveHead(side, cue, variant);
  const paths = Object.keys(archive)
    .filter((path) => path.startsWith(head) && /^\d+\.wav$/.test(path.slice(head.length)))
    .sort((a, b) => Number(a.slice(head.length, -4)) - Number(b.slice(head.length, -4)));
  if (paths.length) return paths.map((path) => archive[path]);
  // The archive has no exact damage-control clip. Fall back to the closest
  // registered report and keep the approximation in the ledger.
  if (cue === 'damage' && variant === 'control-fire') return archiveClips(side, 'fire', 'damage');
  if (cue === 'damage' && variant === 'control-flood') return archiveClips(side, 'damage', 'flood');
  return [];
}

export function archiveClip(side: Side, cue: string, variant?: string): string | undefined {
  return archiveClips(side, cue, variant)[0];
}

// A synthetic UI line, not a recovered crew recording. Kept in its own folder
// and its own ledger array. Only the successful fire-control report uses it.
export function syntheticClip(side: Side, cue: string, variant?: string): string | undefined {
  if (cue !== 'damage' || variant !== 'control-fire') return undefined;
  return synthetic[`./synthetic/damage-control-fire-${side === 'allies' ? 'en' : 'zh'}.wav`];
}

// Used by browser-radio.mjs to prove every ledgered file is packed and playable.
export const archiveFiles = Object.keys(archive).sort();
export const syntheticFiles = Object.keys(synthetic).sort();
