import { useEffect, useRef, useState } from 'react';
import { OnlineError, onlineMeta, onlineRequest } from './online';
import type { OnlineMeta } from './online';
import { ShipBundleShelf } from './ShipBundleShelf';
import { ShipPortraitViewer } from './ShipPortraitViewer';
import { shipPortraitById } from './shipPortraits';
import { OnlineRecruitDesk } from './online-recruit/OnlineRecruitDesk';
import { OnlineRecruitArrival } from './online-recruit/OnlineRecruitArrival';
import { shipTypeNames } from './online-recruit/types';
import type { RecruitPool, RecruitReceipt, RecruitShip } from './online-recruit/types';
import './online-supply.css';

type Catalog = {
  ships: RecruitShip[];
  recruit_pools: RecruitPool[];
  ship_bundles: { id: string; name: string; description?: string; credits: number; ship_ids: string[] }[];
  ai_profiles: { id: string; name: string; description?: string; cost?: number; currency?: 'credits' | 'recruit_ticket';
    unlock?: string; provisional?: boolean }[];
};
type Mail = { id: string; title: string; body: string; sender: string; claimed_at: string | null;
  attachments: { up_tickets: number; standard_tickets: number } };
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
  const [receipts, setReceipts] = useState<RecruitReceipt[]>([]);
  const [arrival, setArrival] = useState<{ receipts: RecruitReceipt[]; replay: boolean }>();
  const [busy, setBusy] = useState(false);
  const [portrait, setPortrait] = useState<RecruitShip>();
  const locked = useRef(false);
  const pending = useRef(new Map<string, string>());
  const pool = catalog?.recruit_pools.find(p => p.id === poolId);
  const wallet = meta?.wallet;
  const names = new Map(catalog?.ships.map(s => [s.id, s.name]));
  const name = (id: string) => names.get(id) ?? id;
  const owns = (id: string) => meta?.owned_ships.includes(id) ?? false;
  // Only ledger-registered portrait assets get a viewer entry; ships without
  // an asset show no button at all.
  const portraitOf = (ship: RecruitShip) => shipPortraitById(ship.id);
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
      const answer = await onlineRequest<{ receipts?: RecruitReceipt[]; meta?: OnlineMeta }>(path, token, { ...params, request_id: id });
      pending.current.delete(key);
      if (answer.meta) onMeta(answer.meta);
      setReceipts(answer.receipts ?? []); setNotice(message);
      if (path === '/recruit' && answer.receipts?.length) setArrival({ receipts: answer.receipts, replay: false });
      try { await refresh(); } catch { setError('操作已确认，列表刷新失败。可手动刷新。'); }
    } catch (e) {
      if (e instanceof OnlineError && e.status && e.status < 500) pending.current.delete(key);
      setError((e as Error).message);
    } finally { locked.current = false; setBusy(false); }
  }
  const buy = (kind: string, item_id: string, currency = 'credits', extra = {}) =>
    void act('/shop/purchase', { kind, item_id, currency, ...extra },
      kind === 'ship_bundle' ? '礼包已入账，重复舰船转为勋章。' : '兑换已入账。');
  // Evolved AI profiles unlock after a real campaign clear on this account and
  // cost standard recruit tickets; the amounts come from server/catalog.json.
  const aiUnlockStage = (a: { unlock?: string }) => a.unlock?.startsWith('campaign:') ? a.unlock.slice(9) : '';
  const aiUnlocked = (a: { unlock?: string }) => {
    const stage = aiUnlockStage(a);
    if (!stage) return true;
    const best = meta?.campaign_progress?.[stage]?.best ?? {};
    return Object.values(best).some(stars => typeof stars === 'number' && stars > 0);
  };
  const aiBalance = (a: { currency?: string }) => a.currency === 'recruit_ticket' ?
    wallet?.standard_tickets ?? 0 : wallet?.credits ?? 0;

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
    {tab === 'recruit' && pool && catalog && <OnlineRecruitDesk ships={catalog.ships} pools={catalog.recruit_pools} pool={pool}
      meta={meta} busy={busy || !!arrival} onPool={id => { setPool(id); setReceipts([]); }} onMail={() => setTab('mail')}
      onShop={() => setTab('shop')} onDraw={(id, count) => void act('/recruit', { pool_id: id, count }, '征募已入账。')}
      onExchange={id => buy('pool_ship', id, 'exchange_points', { pool_id: poolId })}
      onReview={items => setArrival({ receipts: items, replay: true })} />}
    {arrival && catalog && <OnlineRecruitArrival receipts={arrival.receipts} ships={catalog.ships}
      replay={arrival.replay} onClose={() => setArrival(undefined)} />}
    {tab === 'mail' && <section><h2>联机邮箱</h2>{mail.length ? <div className="online-list">{mail.map(letter => <article key={letter.id}>
      <h3>{letter.title}</h3><p>{letter.sender} · {letter.body}</p><p>UP 券 {letter.attachments.up_tickets} · 常驻券 {letter.attachments.standard_tickets}</p>
      <button disabled={busy || !!letter.claimed_at} onClick={() => void act('/mail/' + encodeURIComponent(letter.id) + '/claim', {}, '邮件附件已领取。')}>
        {letter.claimed_at ? '已领取' : '领取附件'}</button>
    </article>)}</div> : <p>没有邮件。</p>}</section>}
    {tab === 'shop' && catalog && meta && <ShipBundleShelf bundles={catalog.ship_bundles} ships={catalog.ships}
      meta={meta} busy={busy} onBuy={id => buy('ship_bundle', id)}/>}
    {tab === 'shop' && <section><h2>免费兑换</h2><div className="online-list">
      <article><h3>每周补给券</h3><button disabled={busy || !wallet || wallet.credits < 500}
        onClick={() => buy('weekly_ticket', '')}>500 补给币兑常驻券</button></article>
      <article><h3>每周实战补给</h3><p>{weekly ? `权威战役达成 ${weekly.count} / ${weekly.target}` : '等待战绩同步'}</p>
        <button disabled={busy || !weekly?.eligible || weekly.claimed}
          onClick={() => void act('/missions/weekly-pve/claim', {}, '周任务奖励已入账。')}>{weekly?.claimed ? '已领取' : '领取周任务奖励'}</button></article>
      {catalog?.ai_profiles.filter(a => a.cost).map(a => {
        const owned = meta?.ai_profiles.includes(a.id) ?? false;
        const unlocked = aiUnlocked(a);
        const price = a.currency === 'recruit_ticket' ? `${a.cost} 常驻征募券` : `${a.cost} 补给币`;
        const scarce = aiBalance(a) < (a.cost ?? 0);
        return <article key={a.id} data-ai-profile={a.id}>
          <h3>{a.name}{a.provisional && <small className="ai-shop-provisional"> 暂定强度</small>}</h3>
          <p>{a.description ?? '解锁保存在联机账号。'}</p>
          <p className="field-note">解锁：{aiUnlockStage(a) ? `通关战役 ${aiUnlockStage(a)}` : '账号已开放'} · 价格 {price}</p>
          <button disabled={busy || owned || !unlocked || scarce}
            onClick={() => buy('ai', a.id, a.currency ?? 'credits')}>
            {owned ? '已拥有' : !unlocked ? '未解锁' : scarce ? '资源不足' : `购买 · ${price}`}
          </button>
          {!owned && !unlocked && <p className="inline-warning">请先通关战役 {aiUnlockStage(a)}。</p>}
          {!owned && unlocked && scarce && <p className="inline-warning">还差 {a.cost! - aiBalance(a)} 张常驻征募券。</p>}
        </article>;
      })}
    </div></section>}
    {(tab === 'fleet' || tab === 'shop') && catalog && <section>
      <h2>{tab === 'fleet' ? '联机收藏 · ' + (meta?.owned_ships.length ?? 0) : '舰船兑换'}</h2>
      <label>筛选舰船 <input type="search" value={filter} onChange={e => setFilter(e.target.value)} placeholder="舰名或舰种" /></label>
      <div className="online-list">{visible.map(ship => <article key={ship.id}><h3>{ship.name}</h3>
        <p>{shipTypeNames[ship.type] ?? ship.type} · {rarity[ship.rarity]}{!ship.combat_ready && ' · 收藏，尚未绑定出战舰卡'}</p>
        {tab === 'fleet' && portraitOf(ship) &&
          <button type="button" className="online-portrait-link" onClick={() => setPortrait(ship)}>查看全身立绘</button>}
        {tab === 'shop' && <div className="online-pools">
          {ship.rarity === 'common' && <button disabled={busy || owns(ship.id) || (wallet?.credits ?? 0) < ship.credits_price}
            onClick={() => buy('ship', ship.id)}>{ship.credits_price} 补给币</button>}
          <button disabled={busy || owns(ship.id) || (wallet?.medals ?? 0) < medalPrice[ship.rarity]}
            onClick={() => buy('ship', ship.id, 'medals')}>{medalPrice[ship.rarity]} 勋章</button></div>}
      </article>)}</div>
      {!visible.length && <p>没有符合条件的舰船。</p>}
    </section>}
    {portrait && <ShipPortraitViewer ship={portrait} onClose={() => setPortrait(undefined)}/>}
  </main>;
}
