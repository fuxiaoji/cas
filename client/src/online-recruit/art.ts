import ledger from './ledger.json';

const files = import.meta.glob<string>('./assets/*.webp', { eager: true, import: 'default', query: '?url' });
const paths = new Map(ledger.assets.map(asset => [asset.character_id, files['./assets/' + asset.path]]));
export const recruitPortrait = (id?: string) => id ? paths.get(id) : undefined;
