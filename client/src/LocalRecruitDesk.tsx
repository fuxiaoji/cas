// Pool tabs, theater artwork and draw history adapted from 铁底湾 0.6.11 RecruitDesk.
import { useId, useRef } from 'react';
import { poolShips, RARITY_ORDER, RARITY_WEIGHTS } from './port';
import type { Pool, PortState } from './port';
import { FEATURED_SHIP, shipCard, shipName, shipRarityName, shipTypeName } from './ship-catalog';
import { shipPortraitById } from './shipPortraits';
import './local-recruit-desk.css';

const poolNames: Record<Pool, string> = { standard: '常驻池', up: '阵营 UP 池' };

type Props = {
  state: PortState;
  pool: Pool;
  busy: boolean;
  onPoolChange: (pool: Pool) => void;
  onRecruit: (count: 1 | 10) => void;
  onReview: (id: number) => void;
  onTraining: () => void;
  onSupply: () => void;
  onCampaign: () => void;
};

export function LocalRecruitDesk({ state, pool, busy, onPoolChange, onRecruit, onReview, onTraining, onSupply, onCampaign }: Props) {
  const help = useRef<HTMLElement>(null);
  const helpId = useId();
  const up = pool === 'up';
  const featuredId = FEATURED_SHIP;
  const featured = shipPortraitById(featuredId);
  const tickets = state.wallet[pool];
  const ticket = up ? 'UP 券' : '常驻券';
  const history = state.history.filter(draw => draw.pool === pool && !!shipCard(draw.ship));
  const last = history[0];
  const cards = poolShips();
  return <section className={'cas-recruit-desk' + (up ? ' is-up' : '')} aria-label="舰船征募卡池">
    <nav className="recruit-pool-tabs" aria-label="选择征募卡池">
      {(Object.keys(poolNames) as Pool[]).map(id => <button type="button" key={id} aria-label={poolNames[id]}
        aria-pressed={id === pool} onClick={() => onPoolChange(id)}>
        <strong>{poolNames[id]}</strong><small>{id === 'up' ? '密苏里 UP' : '同盟及轴心单舰'}</small>
      </button>)}
    </nav>
    <div className="recruit-stage">
      <div className="recruit-halo" aria-hidden="true" />
      {featured && <img className="recruit-feature-art" src={featured.src} alt="" />}
      <div className="recruit-feature-copy">
        <span className="recruit-grade">本机演习舰征募</span>
        <h3>{up ? '密苏里 UP' : '远洋群舰'}</h3>
        <p>{up ? '密苏里在 UR 内 50% 命中；池内仍是全部 202 艘单舰。' : '征募两个阵营的 202 艘可出战单舰。'}</p>
        <div className="recruit-meter">
          <span>{ticket} <b>{tickets}</b></span><span>至多 <b>{Math.max(1, 10 - state.pity[pool])}</b> 抽获得 SR+</span>
        </div>
        <div className="recruit-actions">
          <button type="button" className="primary" disabled={busy || tickets < 1} onClick={() => onRecruit(1)}>
            {up ? '用 1 张 UP 券征募' : '用 1 张常驻券征募'}
          </button>
          <button type="button" disabled={busy || tickets < 10} onClick={() => onRecruit(10)}>
            {up ? '用 10 张 UP 券征募' : '用 10 张常驻券征募'}
          </button>
          {tickets < 10 && <button type="button" aria-controls={helpId} onClick={() => {
            help.current?.focus({ preventScroll: true }); help.current?.scrollIntoView({ block: 'nearest' });
          }}>获取征募券</button>}
        </div>
        {last && <button type="button" className="recruit-review" onClick={() => onReview(last.id)}>查看最近到港报告</button>}
      </div>
    </div>
    {tickets < 10 && <aside className="recruit-ticket-help" id={helpId} ref={help} tabIndex={-1}>
      <div><strong>{`十连还差 ${10 - tickets} 张${ticket}`}</strong>
        <p>{up ? '教学、序章和活动中心可获得 UP 券。' : '活动中心、战役和挑战可获得常驻券，补给商店每周可兑换一张。'}</p></div>
      <div>{!up && <><button type="button" onClick={onCampaign}>前往战役</button><button type="button" onClick={onSupply}>查看补给商店</button></>}
        <button type="button" onClick={onTraining}>前往舰桥学堂</button></div>
    </aside>}
    {last && <div className="recruit-result" role="status">
      <span>{last.guaranteed ? '保底到港' : '最新到港'}</span><strong>{shipName(last.ship)}</strong>
      <small>{last.duplicate ? '该单舰已在舰库，已转换为舰队勋章。' : '已编入本机舰库。'}</small>
    </div>}
    <details className="recruit-rules"><summary>卡池概率与保底</summary>
      <p>每抽按稀有度权重：UR 2%、SSR 8%、SR 20%、R 70%。连续九次未获得 SR 及以上时，第十抽必出 SR+。{!up && '常驻池包含双方全部 202 艘单舰。'}两池独立计算。</p>
      <ul>{RARITY_ORDER.map(rarity => <li key={rarity}>{shipRarityName(rarity)} · {RARITY_WEIGHTS[rarity]}% ·
        {' '}{cards.filter(card => card.gachaRarity === rarity).length} 艘</li>)}</ul>
      {up && <p>UP 旗舰在对应稀有度内占 50%。</p>}
    </details>
    <details className="recruit-rules"><summary>本池到港记录（最近 {history.length} 抽）</summary>
      {history.length ? <ol>{history.map(draw => {
        const card = shipCard(draw.ship);
        return <li key={draw.id}>第 {draw.id} 抽 · {shipName(draw.ship)}{card ? ` · ${shipTypeName(card.type)}` : ''} · {draw.duplicate ? '转为舰队勋章' : '入列'}</li>;
      })}</ol> : <p>尚无到港记录。</p>}
    </details>
  </section>;
}
