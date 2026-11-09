import classLedger from './assets/portraits/ledger.json';
import identityLedger from './assets/portraits/all/ledger.json';

// The authoritative ledger binds one portrait to each IBS-U-* catalogue
// identity.  The 167 identities whose 700x1050 WebP was already pinned for the
// free-economy pool reuse that file; the other 43 are 512x768 WebPs in
// assets/portraits/all.  Class representatives are only a fallback for slots
// that carry no identity at all (the four local-recruit hulls and historical
// class cards); they never stand in for a named ship.
//
// Only the four registered class-representative PNGs are imported.  The older
// named battle PNGs stay in the ledger as provenance but are no longer loaded
// by this module, which keeps ~60 MB of superseded art out of the bundle.
const classFiles = import.meta.glob<string>([
  './assets/portraits/cleveland.png',
  './assets/portraits/fletcher.png',
  './assets/portraits/kagero.png',
  './assets/portraits/sendai.png',
], { eager: true, import: 'default', query: '?url' });
const identityFiles = import.meta.glob<string>('./assets/portraits/all/*.webp', { eager: true, import: 'default', query: '?url' });
const recruitFiles = import.meta.glob<string>('./online-recruit/assets/*.webp', { eager: true, import: 'default', query: '?url' });

export type ShipPortrait = {
  src: string;
  name: string;
  id: string;
  /** True only for an explicit class fallback; never for a named identity. */
  representative: boolean;
};

type IdentityAsset = (typeof identityLedger.assets)[number];

const identityById = new Map<string, IdentityAsset>(identityLedger.assets.map(asset => [asset.identity, asset]));
const identityByName = new Map<string, IdentityAsset[]>();
for (const asset of identityLedger.assets) {
  const rows = identityByName.get(asset.character_name);
  if (rows) rows.push(asset);
  else identityByName.set(asset.character_name, [asset]);
}

function identitySrc(asset: IdentityAsset) {
  return asset.root === 'online-recruit'
    ? recruitFiles['./online-recruit/assets/' + asset.path]
    : identityFiles['./assets/portraits/all/' + asset.path];
}

function identityArt(asset: IdentityAsset | undefined): ShipPortrait | undefined {
  if (!asset) return undefined;
  const src = identitySrc(asset);
  if (!src) return undefined;
  return { src, name: asset.character_name, id: asset.identity, representative: false };
}

function classArt(classId: string | undefined): ShipPortrait | undefined {
  if (!classId) return undefined;
  const item = classLedger.assets.find(entry =>
    entry.mapping === 'class_representative' && entry.cas_class_id === classId);
  if (!item) return undefined;
  const src = classFiles['./assets/portraits/' + item.path];
  if (!src) return undefined;
  return { src, name: item.character_name, id: item.ibs_character_id, representative: true };
}

/**
 * Two catalogue identities can share a display name (卷波/长波/风云).  A name
 * alone is never used to guess between them; the legacy ledger may pin one of
 * the two explicitly, and only that single pinned identity is accepted.
 */
function pinnedIdentity(name: string) {
  const pinned = classLedger.assets.filter(entry =>
    entry.mapping !== 'class_representative' && entry.character_name === name);
  const ids = new Set(pinned.map(entry => entry.ibs_character_id));
  return ids.size === 1 ? [...ids][0] : undefined;
}

/**
 * Battle / formation resolver.  A supplied character id is authoritative: the
 * identity's own art is returned, or nothing if that identity has no ledger
 * row.  It never falls through to a same-class girl.  The class representative
 * is used only when no identity is supplied at all (historical class cards).
 */
export function shipPortrait(classId?: string, characterId?: string): ShipPortrait | undefined {
  if (characterId) return identityArt(identityById.get(characterId));
  return classArt(classId);
}

/** Collection / roster lookup by the stable catalogue identity. */
export function shipPortraitById(characterId: string): ShipPortrait | undefined {
  return identityArt(identityById.get(characterId));
}

/**
 * Fallback for old roster rows that only carry a Chinese ship name.  A unique
 * identity name resolves directly; an ambiguous name resolves only through an
 * explicit legacy pin.  Unknown or ambiguous names return undefined instead of
 * a same-class stand-in.
 */
export function shipPortraitByName(name: string): ShipPortrait | undefined {
  const matches = identityByName.get(name) ?? [];
  if (matches.length === 1) return identityArt(matches[0]);
  if (matches.length > 1) {
    const pinned = pinnedIdentity(name);
    return pinned ? identityArt(identityById.get(pinned)) : undefined;
  }
  return undefined;
}
