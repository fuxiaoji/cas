declare const __CAS_LOCAL_RADIO__: boolean;
declare module 'virtual:cas-fleet-radio-clips' {
  export function localClip(side: import('../engine').Side, cue: string): string | undefined;
  export function archiveClips(side: import('../engine').Side, cue: string, variant?: string): string[];
  export function archiveClip(side: import('../engine').Side, cue: string, variant?: string): string | undefined;
  export function syntheticClip(side: import('../engine').Side, cue: string, variant?: string): string | undefined;
  export const archiveFiles: readonly string[];
  export const syntheticFiles: readonly string[];
}
declare module 'virtual:cas-commander-clips' {
  export function commanderClip(pack: string, cue: string): string | undefined;
  export const commanderPacks: readonly { id: string; title: string }[];
}
