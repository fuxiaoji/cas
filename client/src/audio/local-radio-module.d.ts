declare const __CAS_LOCAL_RADIO__: boolean;
declare module 'virtual:cas-fleet-radio-clips' {
  export function localClip(side: import('../engine').Side, cue: string): string | undefined;
}
declare module 'virtual:cas-commander-clips' {
  export function commanderClip(pack: string, cue: string): string | undefined;
  export const commanderPacks: readonly { id: string; title: string }[];
}
