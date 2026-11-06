import type { Side } from '../engine';

const files = import.meta.glob<string>('./assets/*.m4a', { eager: true, import: 'default', query: '?url' });

export function localClip(side: Side, cue: string) {
  const pack = side === 'allies' ? 'wows-us' : 'wows-jp';
  const exact = files[`./assets/${pack}-${cue}-0.m4a`];
  // The private sample has only the original generic warning. Never voice a
  // direction from geometry the current seat does not have.
  return exact ?? (cue.startsWith('torpedo_warning_') ? files[`./assets/${pack}-torpedo_warning-0.m4a`] : undefined);
}
