const ACCOUNTS = 'cas.accounts.local.v1';
const LAST_NAME = 'cas.accounts.last-name.v1';
const legacy = ['cas.harbor.progress.v1', 'cas.exercise.autosave.v1'];
const rounds = 310_000;

export type LocalProfile = { id: string; name: string };
type Record = LocalProfile & { username: string; salt: string; verifier: string };

export const profileKey = (profile: LocalProfile, key: string) => `cas.profile.${profile.id}.${key}`;
const hex = (values: Uint8Array) => Array.from(values, b => b.toString(16).padStart(2, '0')).join('');
const unhex = (text: string) => new Uint8Array(text.match(/../g)?.map(b => Number.parseInt(b, 16)) ?? []);
const canonical = (name: string) => name.trim().normalize('NFKC');

function accounts(): Record[] {
  const raw = localStorage.getItem(ACCOUNTS);
  if (raw === null) return [];
  const records: unknown = JSON.parse(raw);
  if (!Array.isArray(records) || records.some(v => !v || typeof v.name !== 'string' || typeof v.username !== 'string' ||
    !/^[a-f0-9-]{36}$/.test(v.id) || !/^[a-f0-9]{32}$/.test(v.salt) || !/^[a-f0-9]{64}$/.test(v.verifier))) {
    throw new Error('本机账号档案无法读取，请保留存档后排查。');
  }
  return records as Record[];
}

async function derive(password: string, salt: Uint8Array<ArrayBuffer>) {
  const material = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits']);
  return hex(new Uint8Array(await crypto.subtle.deriveBits({ name: 'PBKDF2', salt, iterations: rounds, hash: 'SHA-256' }, material, 256)));
}

function sameVerifier(a: string, b: string) {
  let different = a.length ^ b.length;
  for (let i = 0; i < a.length; i++) different |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return different === 0;
}

export function lastLocalName() {
  try { return localStorage.getItem(LAST_NAME) ?? ''; } catch { return ''; }
}

export async function authenticateLocal(rawName: string, password: string, register: boolean): Promise<LocalProfile> {
  const name = canonical(rawName);
  if (!/^[\p{L}\p{N}_.-]{3,24}$/u.test(name)) throw new Error('用户名需为 3–24 个字，只使用文字、数字或 . _ -。');
  if (password.length < 10 || password.length > 128) throw new Error('密码须为 10–128 个字符。');
  const username = name.toLowerCase();
  const initial = accounts().find(v => v.username === username);
  let profile: LocalProfile;
  if (register) {
    if (initial) throw new Error('该指挥官账号已存在，请登录。');
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const verifier = await derive(password, salt);
    const list = accounts();
    if (list.some(v => v.username === username)) throw new Error('该指挥官账号已存在，请登录。');
    profile = { id: crypto.randomUUID(), name };
    // The first local profile adopts the old single-player saves once. New
    // profiles do not see the device's old fleet or any other profile's data.
    if (!list.length) {
      for (const key of legacy) {
        const value = localStorage.getItem(key);
        if (value !== null) localStorage.setItem(profileKey(profile, key), value);
      }
    }
    localStorage.setItem(ACCOUNTS, JSON.stringify([...list, { ...profile, username, salt: hex(salt), verifier }]));
  } else {
    const actual = await derive(password, initial ? unhex(initial.salt) : new Uint8Array(16));
    if (!initial || !sameVerifier(actual, initial.verifier)) throw new Error('用户名或密码不正确。');
    profile = { id: initial.id, name: initial.name };
  }
  try { localStorage.setItem(LAST_NAME, profile.name); } catch { /* account already authenticated */ }
  return profile;
}
