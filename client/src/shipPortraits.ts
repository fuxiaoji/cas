import ledger from './assets/portraits/ledger.json';
import recruitLedger from './online-recruit/ledger.json';

const files = import.meta.glob<string>('./assets/portraits/*.png', { eager: true, import: 'default', query: '?url' });
const recruitFiles = import.meta.glob<string>('./online-recruit/assets/*.webp', { eager: true, import: 'default', query: '?url' });

// The free-economy pool imports every kept-scenario identity. Use that ledger
// when the battle-portrait ledger only carries class representatives.
function recruitPortraitById(characterId: string) {
  const item = recruitLedger.assets.find((entry) => entry.character_id === characterId);
  const src = item && recruitFiles['./online-recruit/assets/' + item.path];
  return src ? { src, name: item.character_name ?? item.character_id, id: item.character_id, representative: false } : undefined;
}

export function shipPortrait(classId?: string, characterId?: string) {
  // Named scenario ships only show matching identities. The prototype's
  // generic slots can use the explicitly labelled class representative.
  const item = ledger.assets.find((entry) => characterId ? entry.ibs_character_id === characterId && entry.cas_class_id === classId :
    entry.mapping === 'class_representative' && entry.cas_class_id === classId);
  if (!item) return undefined;
  const src = files[`./assets/portraits/${item.path}`];
  return src ? { src, name: item.character_name, id: item.ibs_character_id, representative: !characterId } : undefined;
}

/** Collection lookup by the stable character id recorded in the ledger. */
export function shipPortraitById(characterId: string) {
  const item = ledger.assets.find((entry) => entry.ibs_character_id === characterId);
  if (!item) return undefined;
  const src = files[`./assets/portraits/${item.path}`];
  if (src) return { src, name: item.character_name, id: item.ibs_character_id, representative: item.mapping === 'class_representative' };
  return recruitPortraitById(characterId);
}
