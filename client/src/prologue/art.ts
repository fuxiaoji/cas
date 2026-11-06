import ledger from './art/ledger.json';

const files = import.meta.glob<string>('./art/*.png', { eager: true, import: 'default', query: '?url' });
const paths = new Map(ledger.assets.map((asset) => [asset.old_url, files['./art/' + asset.path]]));

export const prologueArt = (oldUrl: string) => paths.get(oldUrl);
export const baixisPortrait = prologueArt('/characters/prologue/baixi.png');
export const prologueVictory = prologueArt('/story/prologue-victory-pov.png');
