import { useEffect, useRef, useState } from 'react';
import { OnlineError, onlineMeta, onlineRequest } from './online';
import type { OnlineMeta } from './online';
import './online-supply.css';

type Ship = { id: string; name: string; rarity: string; type: string; recruitable: boolean; credits_price: number; combat_ready: boolean };
type Catalog = {
  ships: Ship[];
  recruit_pools: { id: string; name: string; featured_ship_id?: string; ur_ship_ids: string[]; exchange_price: number }[];
  ship_bundles: { id: string; name: string; credits: number; ship_ids: string[] }[];
  ai_profiles: { id: string; name: string; cost?: number }[];
};
type Mail = { id: string; title: string; body: string; sender: string; claimed_at: string | null;
  attachments: { up_tickets: number; standard_tickets: number } };
type Receipt = { id: string; ship_id: string; rarity: string; duplicate: boolean };
type Weekly = { count: number; target: number; claimed: boolean; eligible: boolean };
type Tab = 'recruit' | 'shop' | 'mail' | 'fleet';
const tabs: Record<Tab, string> = { recruit: '征募', shop: '补给商店', mail: '邮箱', fleet: '舰船收藏' };
const rarity: Record<string, string> = { common: '普通', elite: '精锐', rare: '稀有', ur: 'UR' };
const medalPrice: Record<string, number> = { common: 15, elite: 45, rare: 120, ur: 300 };

export function OnlineSupply({ token, meta, onMeta, onBack, initialTab, onFleetEditor }: {
  token: string; meta?: OnlineMeta; onMeta: (meta: OnlineMeta) => void; onBack: () => void; initialTab: Tab; onFleetEditor?: () => void;
}) {
  const [tab, setTab] = useState<Tab>(initialTab);
  const [catalog, setCatalog] = useState<Catalog>();
  const [mail, setMail] = useState<Mail[]>([]);
  const [poolId, setPool] = useState('standard-v2');
  const [filter, setFilter] = useState('');
  const [weekly, setWeekly] = useState<Weekly>();
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [busy, setBusy] = useState(false);
  const locked = useRef(false);
  const pending = useRef(new Map<string, string>());
  const pool = catalog?.recruit_pools.find(p => p.id === poolId);
  const wallet = meta?.wallet;
  const progress = meta?.pools?.[poolId];
  const available = (poolId === 'standard-v2' ? wallet?.standard_tickets ?? 0 : wallet?.up_tickets ?? 0) + (wallet?.tickets ?? 0);
  const names = new Map(catalog?.ships.map(s => [s.id, s.name]));
  const name = (id: string) => names.get(id) ?? id;
  const owns = (id: string) => meta?.owned_ships.includes(id) ?? false;
  const visible = (catalog?.ships ?? []).filter(ship => (tab === 'fleet' ? owns(ship.id) : ship.recruitable) &&
    (ship.name + ' ' + ship.type + ' ' + ship.id).toLowerCase().includes(filter.trim().toLowerCase()));

  async function refresh() {
    const [next, letters, week] = await Promise.all([onlineMeta(token),
      onlineRequest<{ messages: Mail[] }>('/mail', token),
      onlineRequest<Weekly>('/missions/weekly-pve', token)]);
    onMeta(next); setMail(letters.messages); setWeekly(week);
  }
  async function load() {
    if (locked.current) return;
    locked.current = true; setBusy(true); setError('');
    try { const [data] = await Promise.all([onlineRequest<Catalog>('/catalog'), refresh()]); setCatalog(data); }
    catch (e) { setError(String((e as Error).message)); }
    finally { locked.current = false; setBusy(false); }
  }
  useEffect(() => { void load(); }, [token]);

  async function act(path: string, params: object, message: string) {
    if (locked.current) return;
    const key = path + ':' + JSON.stringify(params);
    const id = pending.current.get(key) ?? crypto.randomUUID();
    pending.current.set(key, id);
    locked.current = true; setBusy(true); setNotice(''); setError('');
    try {
      const answer = await onlineRequest<{ receipts?: Receipt[]; meta?: OnlineMeta }>(path, token, { ...params, request_id: id });
      pending.current.delete(key);
      if (answer.meta) onMeta(answer.meta);
      setReceipts(answer.receipts ?? []); setNotice(message);
      try { await refresh(); } catch { setError('操作已确认，列表刷新失败。可手动刷新。'); }
    } catch (e) {
      if (e instanceof OnlineError && e.status && e.status < 500) pending.current.delete(key);
      setError((e as Error).message);
    } finally { locked.current = false; setBusy(false); }
  }
  const buy = (kind: string, item_id: string, currency = 'credits', extra = {}) =>
    void act('/shop/purchase', { kind, item_id, currency, ...extra }, '兑换已入账。');

  return <main className="online-supply">
    <header><button onClick={onBack}>‹ 返回母港</button><div><p>联机免费内测</p><h1>征募与补给</h1></div>
      {tab === 'fleet' && onFleetEditor && <button type="button" onClick={onFleetEditor}>个人编队</button>}
      <button onClick={() => void load()} disabled={busy}>刷新</button></header>
    {wallet && <div className="online-wallet" aria-label="联机钱包">
      <span>补给币 <b>{wallet.credits}</b></span><span>UP 券 <b>{wallet.up_tickets}</b></span>
      <span>常驻券 <b>{wallet.standard_tickets}</b></span><span>舰队勋章 <b>{wallet.medals}</b></span>
      {wallet.tickets > 0 && <span>通用券 <b>{wallet.tickets}</b></span>}
    </div>}
    <nav aria-label="联机补给功能">{(Object.entries(tabs) as [Tab, string][]).map(([id, title]) =>
      <button key={id} aria-pressed={id === tab} onClick={() => { setTab(id); setFilter(''); setReceipts([]); setNotice(''); }}>{title}</button>)}</nav>
    {error && <p className="inline-warning" role="alert">{error}</p>}
    {notice && <p role="status">{notice}</p>}
    {receipts.length > 0 && <ul aria-label="征募结果" className="online-receipts">{receipts.map(r =>
      <li key={r.id}>{rarity[r.rarity]} · {name(r.ship_id)}{r.duplicate ? ' · 重复转为勋章' : ' · 入列'}</li>)}</ul>}
    {tab === 'recruit' && pool && <section>
      <div className="online-pools">{catalog!.recruit_pools.map(item => <button key={item.id} aria-pressed={item.id === poolId}
        onClick={() => { setPool(item.id); setReceipts([]); }}>{item.name || (item.id === 'standard-v2' ? '常驻征募' : 'UP 征募')}</button>)}</div>
      <p>{pool.featured_ship_id ? '本期 UP · ' + name(pool.featured_ship_id) : '常驻征募'} · 可用 {available} 张</p>
      <p>精锐保底 {progress?.since_elite ?? 0}/10 · 稀有 {progress?.since_rare ?? 0}/40 · UR {progress?.since_ur ?? 0}/80{progress?.featured_guaranteed && ' · 下一艘 UR 必为本期 UP'}</p>
      <div className="online-pools">{[1, 10].map(count => <button className="primary" key={count} disabled={busy || available < count}
        onClick={() => void act('/recruit', { pool_id: poolId, count }, '征募已入账。')}>征募 {count} 次</button>)}</div>
      <h2>本池进度兑换 · {progress?.exchange_points ?? 0}/{pool.exchange_price}</h2>
      <div className="online-pools">{Array.from(new Set([...(pool.featured_ship_id ? [pool.featured_ship_id] : []), ...pool.ur_ship_ids]))
        .map(id => <button key={id} disabled={busy || owns(id) || (progress?.exchange_points ?? 0) < pool.exchange_price}
          onClick={() => buy('pool_ship', id, 'exchange_points', { pool_id: poolId })}>{owns(id) ? '已拥有 ' : '兑换 '}{name(id)}</button>)}</div>
    </section>}
    {tab === 'mail' && <section><h2>联机邮箱</h2>{mail.length ? <div className="online-list">{mail.map(letter => <article key={letter.id}>
      <h3>{letter.title}</h3><p>{letter.sender} · {letter.body}</p><p>UP 券 {letter.attachments.up_tickets} · 常驻券 {letter.attachments.standard_tickets}</p>
      <button disabled={busy || !!letter.claimed_at} onClick={() => void act('/mail/' + encodeURIComponent(letter.id) + '/claim', {}, '邮件附件已领取。')}>
        {letter.claimed_at ? '已领取' : '领取附件'}</button>
    </article>)}</div> : <p>没有邮件。</p>}</section>}
    {tab === 'shop' && <section><h2>免费兑换</h2><div className="online-list">
      <article><h3>每周补给券</h3><button disabled={busy || !wallet || wallet.credits < 500}
        onClick={() => buy('weekly_ticket', '')}>500 补给币兑常驻券</button></article>
      <article><h3>每周实战补给</h3><p>{weekly ? `权威战役达成 ${weekly.count} / ${weekly.target}` : '等待战绩同步'}</p>
        <button disabled={busy || !weekly?.eligible || weekly.claimed}
          onClick={() => void act('/missions/weekly-pve/claim', {}, '周任务奖励已入账。')}>{weekly?.claimed ? '已领取' : '领取周任务奖励'}</button></article>
      {catalog?.ship_bundles.map(item => <article key={item.id}><h3>{item.name}</h3><p>{item.ship_ids.map(name).join('、')}</p>
        <button disabled={busy || (wallet?.credits ?? 0) < item.credits || meta?.claims.includes('shop:ship-bundle:' + item.id)}
          onClick={() => buy('ship_bundle', item.id)}>{item.credits} 补给币</button></article>)}
      {catalog?.ai_profiles.filter(a => a.cost).map(a => <article key={a.id}><h3>{a.name}</h3><p>解锁保存在联机账号。</p>
        <button disabled={busy || (wallet?.credits ?? 0) < a.cost! || meta?.ai_profiles.includes(a.id)} onClick={() => buy('ai', a.id)}>{a.cost} 补给币</button></article>)}
    </div></section>}
    {(tab === 'fleet' || tab === 'shop') && catalog && <section>
      <h2>{tab === 'fleet' ? '联机收藏 · ' + (meta?.owned_ships.length ?? 0) : '舰船兑换'}</h2>
      <label>筛选舰船 <input type="search" value={filter} onChange={e => setFilter(e.target.value)} placeholder="舰名或舰种" /></label>
      <div className="online-list">{visible.map(ship => <article key={ship.id}><h3>{ship.name}</h3>
        <p>{ship.type} · {rarity[ship.rarity]}{!ship.combat_ready && ' · 收藏，尚未绑定出战舰卡'}</p>
        {tab === 'shop' && <div className="online-pools">
          {ship.rarity === 'common' && <button disabled={busy || owns(ship.id) || (wallet?.credits ?? 0) < ship.credits_price}
            onClick={() => buy('ship', ship.id)}>{ship.credits_price} 补给币</button>}
          <button disabled={busy || owns(ship.id) || (wallet?.medals ?? 0) < medalPrice[ship.rarity]}
            onClick={() => buy('ship', ship.id, 'medals')}>{medalPrice[ship.rarity]} 勋章</button></div>}
      </article>)}</div>
      {!visible.length && <p>没有符合条件的舰船。</p>}
    </section>}
  </main>;
}
