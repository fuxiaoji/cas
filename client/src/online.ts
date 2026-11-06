import type { LocalProfile } from './account';
import type { Observation, Result } from './engine';

function serviceUrl() {
  const raw = import.meta.env.VITE_CAS_ACCOUNT_URL || (import.meta.env.DEV ? 'http://127.0.0.1:8021' : '');
  try {
    const url = new URL(raw);
    const loopback = ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
    if (url.username || url.password || url.search || url.hash ||
        !(url.protocol === 'https:' || (loopback && url.protocol === 'http:'))) return undefined;
    return url.toString().replace(/\/+$/, '');
  } catch { return undefined; }
}
const base = serviceUrl();
export const onlineEnabled = Boolean(base);

export class OnlineError extends Error {
  constructor(message: string, readonly status?: number) { super(message); }
}

export async function onlineRequest<T>(path: string, token?: string, body?: unknown): Promise<T> {
  if (!base) throw new OnlineError('当前安装包未配置内测服务。');
  let result: Response;
  try {
    result = await fetch(base + path, { method: body === undefined ? 'GET' : 'POST',
      headers: { ...(token ? { Authorization: 'Bearer ' + token } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
      body: body === undefined ? undefined : JSON.stringify(body),
      credentials: 'omit', cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(8000) });
  } catch { throw new OnlineError('无法连接内测服务，请检查连接后重试。'); }
  const value = await result.json().catch(() => undefined);
  if (!result.ok) throw new OnlineError(typeof value?.detail === 'string' ? value.detail :
    result.status === 401 ? '登录已失效，请重新登录。' : '内测服务未能处理这条请求。', result.status);
  if (value === undefined) throw new OnlineError('内测服务返回了无法读取的结果。');
  return value as T;
}

export async function authenticateOnline(username: string, password: string, register: boolean): Promise<LocalProfile> {
  if (!/^[A-Za-z0-9_.-]{3,40}$/.test(username.trim())) throw new OnlineError('联机用户名须用 3–40 位字母、数字或 . _ -。');
  const result = await onlineRequest<{ account_id: string; username: string; token: string }>(
    register ? '/auth/register' : '/auth/login', undefined, { username: username.trim(), password });
  return { id: 'online-' + result.account_id, name: result.username, online: { token: result.token } };
}

export interface OnlineMeta {
  wallet: { credits: number; up_tickets: number; standard_tickets: number; tickets: number; medals: number };
  owned_ships: string[]; claims: string[]; ai_profiles: string[];
  pools?: Record<string, { exchange_points: number; since_elite: number; since_rare: number; since_ur: number; featured_guaranteed: boolean }>;
}

export async function onlineMeta(token: string) {
  return (await onlineRequest<{ meta: OnlineMeta }>('/me', token)).meta;
}

export interface OnlineBattleSummary {
  battle_id: string; stage_id: string; difficulty: string; revision: number;
  status: 'active' | 'complete'; tick: number; result: Result | null;
}
export interface OnlineBattle extends OnlineBattleSummary { view: Observation }
export type OnlineBattleClaim = { grade: string; stars: number; claimed: boolean; meta: OnlineMeta;
  rewards: { id: string; title: string; credits?: number; tickets?: number; medals?: number }[] };
export const battlePath = (id: string) => '/battles/' + encodeURIComponent(id);
