import { useEffect, useRef, useState } from 'react';
import { clock, sideNames } from './engine';
import { duelPath, OnlineError, onlineRequest } from './online';
import type { OnlineDuel, OnlineDuelSummary } from './online';
import './online-duel.css';

interface Invitation { code: string; expires_at: number; status: 'waiting' }
interface QueueEntry { queued_at: number; expires_at: number }
interface DuelStatus { invites: Invitation[]; matches: OnlineDuelSummary[]; queue: QueueEntry | null }
type QueueReply = { status: 'queued' } | { status: 'matched'; match: OnlineDuel };

export function OnlineDuelLobby({ token, onBack, onBattle }: {
  token: string; onBack: () => void; onBattle: (battle: OnlineDuel) => void;
}) {
  const [status, setStatus] = useState<DuelStatus>();
  const [code, setCode] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState('');
  const pending = useRef(new Map<string, string>());
  const poll = useRef(0);
  const acting = useRef(false);

  async function refresh() {
    const sequence = ++poll.current;
    try {
      const next = await onlineRequest<DuelStatus>('/pvp/status', token);
      if (sequence === poll.current) { setStatus(next); setError(''); }
    } catch (error) {
      if (sequence === poll.current) setError(message(error));
    }
  }
  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => { if (!acting.current && !document.hidden) void refresh(); }, 3500);
    return () => { ++poll.current; window.clearInterval(timer); };
  }, [token]);

  async function act<T>(path: string, receive?: (reply: T) => void, readOnly = false) {
    if (acting.current) return;
    acting.current = true;
    ++poll.current;
    setBusy(true); setError(''); setCopied('');
    const id = pending.current.get(path) ?? crypto.randomUUID();
    if (!readOnly) pending.current.set(path, id);
    try {
      const reply = await onlineRequest<T>(path, token, readOnly ? undefined : { request_id: id });
      pending.current.delete(path);
      receive?.(reply);
      if (!readOnly) await refresh();
    } catch (error) {
      if (error instanceof OnlineError && error.status && error.status < 500) pending.current.delete(path);
      setError(message(error));
    } finally { acting.current = false; setBusy(false); }
  }
  async function copy(value: string) {
    try { await navigator.clipboard.writeText(value); setCopied('已复制约战口令'); }
    catch { setCopied('可长按或选中口令手动复制'); }
  }

  const joinCode = code.trim().toUpperCase();
  return <main className="duel-lobby" aria-labelledby="duel-lobby-title">
    <header className="duel-heading">
      <button type="button" disabled={busy} onClick={onBack}>‹ 返回母港</button>
      <div><h1 id="duel-lobby-title">线上舰桥</h1><p>双席约战 · 非排位</p></div>
      <button type="button" disabled={busy} onClick={() => void refresh()}>刷新</button>
    </header>
    <section className="duel-mode" aria-label="当前玩法">
      <strong>昼间舰队演习</strong><span>同盟／轴心各 4 艘驱逐舰、1 艘轻巡洋舰 · 联机时钟 4×</span>
    </section>
    {error && <p className="inline-warning" role="alert">{error}</p>}
    {status ? <div className="duel-columns">
      <section aria-labelledby="duel-invite-heading">
        <h2 id="duel-invite-heading">邀请好友</h2>
        <button type="button" className="primary" disabled={busy} onClick={() => void act('/pvp/invites')}>创建约战口令</button>
        {status.invites.map(invite => <div className="duel-invite" key={invite.code}>
          <output aria-label="约战口令">{invite.code}</output>
          <button type="button" onClick={() => void copy(invite.code)}>复制</button>
          <button type="button" disabled={busy} onClick={() => void act('/pvp/invites/' + encodeURIComponent(invite.code) + '/cancel')}>撤销</button>
        </div>)}
        {copied && <p role="status">{copied}</p>}
        <form onSubmit={event => { event.preventDefault(); if (joinCode) void act<OnlineDuel>('/pvp/invites/' + encodeURIComponent(joinCode) + '/join', onBattle); }}>
          <label>好友口令 <input autoComplete="off" autoCapitalize="characters" value={code} maxLength={24} onChange={event => setCode(event.target.value)} /></label>
          <button type="submit" disabled={busy || !joinCode}>加入约战</button>
        </form>
      </section>
      <section aria-labelledby="duel-queue-heading">
        <h2 id="duel-queue-heading">非排位匹配</h2>
        <p>{status.queue ? '正在等待对手。找到对手后可从我的对局进入。' : '按入队顺序寻找对手，双方使用预编舰队。'}</p>
        {status.queue ? <button type="button" disabled={busy} onClick={() => void act('/pvp/queue/cancel')}>退出匹配</button> :
          <button type="button" disabled={busy} onClick={() => void act<QueueReply>('/pvp/queue', reply => { if (reply.status === 'matched') onBattle(reply.match); })}>开始匹配</button>}
      </section>
      <section className="duel-history" aria-labelledby="duel-history-heading">
        <h2 id="duel-history-heading">我的对局</h2>
        {!status.matches.length && <p>暂无对局。</p>}
        {status.matches.map(match => <button className="duel-match" type="button" key={match.match_id} disabled={busy}
          onClick={() => void act<OnlineDuel>(duelPath(match.match_id), onBattle, true)}>
          <span>{match.status === 'active' ? '进入对局' : '查看战果'} · {sideNames[match.seat]}</span><span>{clock(match.tick)}　›</span>
        </button>)}
      </section>
    </div> : !error && <p role="status">正在连接线上舰桥…</p>}
  </main>;
}

function message(error: unknown) {
  return error instanceof Error ? error.message : '线上舰桥暂时无法处理请求。';
}
