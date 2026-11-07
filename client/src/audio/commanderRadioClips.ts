// Local-playtest build only (VITE_CAS_LOCAL_VOICE=1 or dev server). The files
// below are the ledgered minimal subset of a personal commander voice pack;
// see commander/ledger.json for provenance and the not-migrated inventory.
const files = import.meta.glob<string>('./commander/al-*/*.m4a', { eager: true, import: 'default', query: '?url' });

export const commanderPacks: readonly { id: string; title: string }[] = [
  { id: 'al-enterprise', title: '碧蓝 · 企业' },
];

export function commanderClip(pack: string, cue: string) {
  return files[`./commander/${pack}/${pack}-${cue}-0.m4a`];
}
