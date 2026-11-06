declare const __CAS_LOCAL_RADIO__: boolean;
declare module 'virtual:cas-fleet-radio-clips' {
  export function localClip(side: import('../engine').Side, cue: string): string | undefined;
}
