import ledger from './art/ledger.json';
import fletcher from '../assets/portraits/fletcher.png';

const files = import.meta.glob<string>('./art/*.png', { eager: true, import: 'default', query: '?url' });
const paths = new Map(ledger.assets.map((asset) => [asset.old_url, files['./art/' + asset.path]]));

export const prologueArt = (oldUrl: string) => oldUrl === '/characters/ships/fletcher-anime-face.png' ? fletcher : paths.get(oldUrl);
export const baixisPortrait = prologueArt('/characters/prologue/baixi.png');
export const prologueVictory = prologueArt('/story/prologue-victory-pov.png');
