import { useEffect, useRef, useState } from 'react';
import { clock, sideNames } from './engine';
import { duelPath, OnlineError, onlineRequest, rankedBudgetTitle, rankedVoided } from './online';
import type { OnlineDuel, OnlineDuelSummary, OnlineLadder, OnlineRankedStatus } from './online';
import './online-duel.css';

interface Invitation { code: string; expires_at: number; status: 'waiting' }
interface QueueEntry { queued_at: number; expires_at: number }
interface DuelStatus { invites: Invitation[]; matches: OnlineDuelSummary[]; queue: QueueEntry | null }
type QueueReply = { status: 'queued' } | { status: 'matched'; match: OnlineDuel };
type RankedQueueReply = { status: 'queued' } | { status: 'matched'; match: OnlineDuel };
interface RankedPreset { fleet: { id: string; name: string; budget: number };
  validation: { ranked_ready: boolean; cost: number | null; blocking_reasons: string[] } }
interface FleetBook { fleets: RankedPreset[]; active_fleet_id: string | null; ranked_available: boolean }

const BUDGETS = [3000, 10000] as const;
const stamp = (ms: number) => new Date(ms).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
const seasonDay = (ms: number) => new Date(ms).toLocaleDateString('zh-CN', { year: 'numeric', month: 'long', day: 'numeric' });
const signed = (value: number) => (value >= 0 ? '+' + value : String(value));

function outcomeLine(match: OnlineDuelSummary) {
  if (match.status !== 'complete') return clock(match.tick);
  if (rankedVoided(match) || match.rated === false) return '作废 · 积分不变';
  const winner = match.result?.winner;
  const verdict = winner === 'draw' ? '平局' : winner === match.seat ? '胜' : '负';
  const change = match.rating && match.rated ? ` ${match.rating.before}→${match.rating.after}` : '';
  return verdict + change;
}

export function OnlineDuelLobby({ token, initialTab = 'casual', onBack, onBattle }: {
  token: string; initialTab?: 'casual' | 'ranked'; onBack: () => void; onBattle: (battle: OnlineDuel) => void;
}) {
  const [tab, setTab] = useState<'casual' | 'ranked'>(initialTab);
  const [status, setStatus] = useState<DuelStatus>();
  const [ranked, setRanked] = useState<OnlineRankedStatus>();
  const [book, setBook] = useState<FleetBook>();
  const [budget, setBudget] = useState(3000);
  const [fleetId, setFleetId] = useState('');
  const [code, setCode] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState('');
  const pending = useRef(new Map<string, string>());
  const poll = useRef(0);
  const polling = useRef(false);
  const acting = useRef(false);

  async function refresh(which: 'casual' | 'ranked' = tab) {
    const sequence = ++poll.current;
    polling.current = true;
    try {
      if (which === 'ranked') {
        const [next, fleets] = await Promise.all([
          onlineRequest<OnlineRankedStatus>('/pvp/ranked/status', token),
          onlineRequest<FleetBook>('/fleets', token),
        ]);
        if (sequence === poll.current) {
          setRanked(next); setBook(fleets);
          setBudget(current => next.available_budgets.includes(current) ? current : next.available_budgets[0] ?? 3000);
          setError('');
        }
      } else {
        const next = await onlineRequest<DuelStatus>('/pvp/status', token);
        if (sequence === poll.current) { setStatus(next); setError(''); }
      }
    } catch (error) {
      if (sequence === poll.current) setError(message(error));
    } finally { if (sequence === poll.current) polling.current = false; }
  }
  useEffect(() => {
    void refresh(tab);
    const timer = window.setInterval(() => {
      if (!acting.current && !polling.current && !document.hidden) void refresh(tab);
    }, 3500);
    return () => { ++poll.current; window.clearInterval(timer); };
  }, [token, tab]);

  async function act<T>(path: string, receive?: (reply: T) => void, readOnly = false, body?: Record<string, unknown>) {
    if (acting.current) return;
    acting.current = true;
    ++poll.current;
    setBusy(true); setError(''); setCopied('');
    const id = pending.current.get(path) ?? crypto.randomUUID();
    if (!readOnly) pending.current.set(path, id);
    try {
      const reply = await onlineRequest<T>(path, token, readOnly ? undefined : { request_id: id, ...body });
      pending.current.delete(path);
      receive?.(reply);
      if (!readOnly) await refresh();
    } catch (error) {
      if (error instanceof OnlineError && error.status && error.status < 500) pending.current.delete(path);
      setError(message(error));
    } finally { acting.current = false; polling.current = false; setBusy(false); }
  }
  async function copy(value: string) {
    try { await navigator.clipboard.writeText(value); setCopied('已复制约战口令'); }
    catch { setCopied('可长按或选中口令手动复制'); }
  }

  const joinCode = code.trim();
  const openBudgets = ranked?.available_budgets ?? [];
  const ladderFor = (value: number): OnlineLadder | undefined =>
    ranked?.ratings.find(entry => entry.budget === value) ?? (ranked ?
      { budget: value, season_id: ranked.season.id, rating: 1000, games: 0, wins: 0, losses: 0, draws: 0, rank: '白银' } : undefined);
  const budgetOpen = openBudgets.includes(budget);
  const readyFleets = (book?.fleets ?? []).filter(entry => entry.validation.ranked_ready && entry.fleet.budget === budget);
  const chosenFleet = readyFleets.some(entry => entry.fleet.id === fleetId) ? fleetId :
    readyFleets.find(entry => entry.fleet.id === book?.active_fleet_id)?.fleet.id ?? readyFleets[0]?.fleet.id ?? '';
  const history = ranked?.historical_ratings ?? [];

  const queueSection = <section aria-labelledby="duel-queue-heading">
    <h2 id="duel-queue-heading">排位匹配 · {rankedBudgetTitle(budget)}</h2>
    {ranked?.queue ? <>
      <p>正在寻找 {rankedBudgetTitle(ranked.queue.budget)} 对手，{stamp(ranked.queue.expires_at)} 前有效，超时自动退出。</p>
      <button type="button" disabled={busy} onClick={() => void act('/pvp/ranked/queue/cancel')}>取消排队</button>
    </> : <>
      <p>排位按积分与赛季匹配对手，开局冻结舰队与指挥风格。</p>
      {readyFleets.length ? <label>出战预设 <select value={chosenFleet} disabled={busy}
        onChange={event => setFleetId(event.target.value)}>
        {readyFleets.map(entry => <option key={entry.fleet.id} value={entry.fleet.id}>
          {entry.fleet.name} · 点价 {entry.validation.cost} 分
        </option>)}
      </select></label> :
        <p>本账号还没有 {budget} 分档通过核验的预设。请先在云端编队保存排位预设。</p>}
      <button type="button" className="primary" disabled={busy || !budgetOpen || !chosenFleet}
        onClick={() => void act<RankedQueueReply>('/pvp/ranked/queue',
          reply => { if (reply.status === 'matched') onBattle(reply.match); }, false,
          { budget, fleet_id: chosenFleet })}>入队</button>
      {!budgetOpen && <p>{rankedBudgetTitle(budget)}暂未开放，开放后可在此入队。</p>}
    </>}
  </section>;

  const seasonSection = ranked && <section className="duel-season" aria-label="排位赛季与点表">
    <strong>当前赛季 {ranked.season.id}</strong>
    <span>{seasonDay(ranked.season.start)} ～ {seasonDay(ranked.season.end)} · 共 {ranked.season.duration_days} 天</span>
    <span>点表版本 {ranked.point_table_version ?? '未配置'}</span>
  </section>;

  const budgetSection = <section aria-labelledby="duel-budgets-heading">
    <h2 id="duel-budgets-heading">积分档位与段位</h2>
    <div className="duel-budgets">
      {BUDGETS.map(value => {
        const ladder = ladderFor(value);
        const open = openBudgets.includes(value);
        return <button type="button" key={value} aria-pressed={budget === value}
          disabled={busy || !open} onClick={() => setBudget(value)}>
          <strong>{rankedBudgetTitle(value)}</strong>
          <span>{open ? `${ladder?.rank} · ${ladder?.rating} 分` : '未开放'}</span>
          <small>{ladder ? `${ladder.games} 战 ${ladder.wins} 胜 ${ladder.losses} 负 ${ladder.draws} 平` : '暂无战绩'}</small>
        </button>;
      })}
    </div>
  </section>;

  const rankedHistory = <section className="duel-history" aria-labelledby="duel-ranked-heading">
    <h2 id="duel-ranked-heading">排位战况</h2>
    {!ranked?.matches.length && <p>本赛季还没有排位对局。</p>}
    {ranked?.matches.map(match => <button className="duel-match" type="button" key={match.match_id} disabled={busy}
      onClick={() => void act<OnlineDuel>(duelPath(match.match_id), onBattle, true)}>
      <span>{match.status === 'active' ? '进入对局' : '查看战果'} · {rankedBudgetTitle(match.budget ?? 0)} · {sideNames[match.seat]}</span>
      <span>{outcomeLine(match)}{match.status === 'complete' && match.rating && match.rated ?
        `（${signed(match.rating.delta)} · ${match.rating.rank}）` : ''}　›</span>
    </button>)}
    <h3>历史赛季</h3>
    {!history.length && <p>暂无历史赛季战绩。</p>}
    {history.map(entry => <p className="duel-history-row" key={entry.season_id + ':' + entry.budget}>
      {entry.season_id} · {rankedBudgetTitle(entry.budget)} · {entry.rank} {entry.rating} 分 ·
      {' '}{entry.wins} 胜 {entry.losses} 负 {entry.draws} 平
    </p>)}
  </section>;

  return <main className="duel-lobby" aria-labelledby="duel-lobby-title">
    <header className="duel-heading">
      <button type="button" disabled={busy} onClick={onBack}>‹ 返回母港</button>
      <div><h1 id="duel-lobby-title">线上舰桥</h1><p>双席约战 · 同一 CAS 内核裁决</p></div>
      <button type="button" disabled={busy} onClick={() => void refresh()}>刷新</button>
    </header>
    <nav className="duel-tabs" aria-label="玩法选择">
      <button type="button" aria-pressed={tab === 'casual'} disabled={busy} onClick={() => setTab('casual')}>非排位演习</button>
      <button type="button" aria-pressed={tab === 'ranked'} disabled={busy} onClick={() => setTab('ranked')}>排位赛</button>
    </nav>
    {error && <p className="inline-warning" role="alert">{error}</p>}
    {tab === 'casual' ? <>
      <section className="duel-mode" aria-label="当前玩法">
        <strong>昼间舰队演习</strong><span>同盟／轴心各 4 艘驱逐舰、1 艘轻巡洋舰 · 联机时钟 4×</span>
      </section>
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
            <label>好友口令 <input autoComplete="off" autoCapitalize="off" spellCheck={false} value={code} maxLength={32} onChange={event => setCode(event.target.value)} /></label>
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
    </> : ranked ? <>
      {seasonSection}
      <div className="duel-columns">
        {budgetSection}
        {queueSection}
        {rankedHistory}
      </div>
    </> : !error && <p role="status">正在连接排位赛…</p>}
  </main>;
}

function message(error: unknown) {
  return error instanceof Error ? error.message : '线上舰桥暂时无法处理请求。';
}
