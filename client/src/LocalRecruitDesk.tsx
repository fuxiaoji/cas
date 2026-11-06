// Pool tabs, theater artwork and draw history adapted from 铁底湾 0.6.11 RecruitDesk.
import { useId, useRef } from 'react';
import { sideNames } from './engine';
import { hulls, rosters } from './port';
import type { Hull, Pool, PortState } from './port';
import { shipPortrait } from './shipPortraits';
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
  const featured = shipPortrait(rosters[up ? state.upSide : state.preset.side][1]);
  const tickets = state.wallet[pool];
  const ticket = up ? 'UP 券' : '常驻券';
  const history = state.history.filter(draw => draw.pool === pool && Object.hasOwn(hulls, draw.hull));
  const last = history[0];
  const candidates: Hull[] = up ? rosters[state.upSide].slice(0, 2) : ['fletcher', 'cleveland', 'kagero', 'sendai'];
  return <section className={'cas-recruit-desk' + (up ? ' is-up' : '')} aria-label="舰船征募卡池">
    <nav className="recruit-pool-tabs" aria-label="选择征募卡池">
      {(Object.keys(poolNames) as Pool[]).map(id => <button type="button" key={id} aria-label={poolNames[id]}
        aria-pressed={id === pool} onClick={() => onPoolChange(id)}>
        <strong>{poolNames[id]}</strong><small>{id === 'up' ? sideNames[state.upSide] : '同盟及轴心舰型'}</small>
      </button>)}
    </nav>
    <div className="recruit-stage">
      <div className="recruit-halo" aria-hidden="true" />
      {featured && <img className="recruit-feature-art" src={featured.src} alt="" />}
      <div className="recruit-feature-copy">
        <span className="recruit-grade">本机演习舰征募</span>
        <h3>{up ? sideNames[state.upSide] : '远洋群舰'}</h3>
        <p>{up ? '补充初始舰队以外的阵营舰型。' : '征募两个阵营的驱逐舰和轻巡洋舰。'}</p>
        <div className="recruit-meter">
          <span>{ticket} <b>{tickets}</b></span><span>至多 <b>{Math.max(1, 10 - state.pity[pool])}</b> 抽获得轻巡</span>
        </div>
        <div className="recruit-actions">
          <button type="button" className="primary" disabled={busy || !state.starter || tickets < 1} onClick={() => onRecruit(1)}>
            {up ? '用 1 张 UP 券征募' : '用 1 张常驻券征募'}
          </button>
          <button type="button" disabled={busy || !state.starter || tickets < 10} onClick={() => onRecruit(10)}>
            {up ? '用 10 张 UP 券征募' : '用 10 张常驻券征募'}
          </button>
          {tickets < 10 && <button type="button" aria-controls={helpId} onClick={() => {
            help.current?.focus({ preventScroll: true }); help.current?.scrollIntoView({ block: 'nearest' });
          }}>获取征募券</button>}
        </div>
        {last && <button type="button" className="recruit-review" onClick={() => onReview(last.id)}>查看最近到港报告</button>}
      </div>
    </div>
    {(!state.starter || tickets < 10) && <aside className="recruit-ticket-help" id={helpId} ref={help} tabIndex={-1}>
      <div><strong>{!state.starter ? '领取初始舰队后开放征募' : `十连还差 ${10 - tickets} 张${ticket}`}</strong>
        <p>{up ? '教学、序章和活动中心可获得 UP 券。' : '活动中心、战役和挑战可获得常驻券，补给商店每周可兑换一张。'}</p></div>
      <div>{!state.starter && <button type="button" onClick={onTraining}>前往舰桥学堂</button>}
        {!up && <><button type="button" onClick={onCampaign}>前往战役</button><button type="button" onClick={onSupply}>查看补给商店</button></>}</div>
    </aside>}
    {last && <div className="recruit-result" role="status">
      <span>{last.guaranteed ? '保底到港' : '最新到港'}</span><strong>{hulls[last.hull].name}</strong>
      <small>{last.duplicate ? '该舰型仓位已满，已转换为舰队勋章。' : '已编入本机舰库。'}</small>
    </div>}
    <details className="recruit-rules"><summary>卡池概率与保底</summary>
      <p>每抽驱逐舰 85%、轻巡洋舰 15%。连续九次未获得轻巡时，第十抽必出。{!up && '两阵营等概率。'}两池独立计算。</p>
      <ul>{candidates.map(id => <li key={id}>{hulls[id].name} · 基础 {((hulls[id].kind === '轻巡洋舰' ? 15 : 85) / (up ? 1 : 2))}%</li>)}</ul>
    </details>
    <details className="recruit-rules"><summary>本池到港记录（最近 {history.length} 抽）</summary>
      {history.length ? <ol>{history.map(draw => <li key={draw.id}>第 {draw.id} 抽 · {hulls[draw.hull].name} · {draw.duplicate ? '转为舰队勋章' : '入列'}</li>)}</ol>
        : <p>尚无到港记录。</p>}
    </details>
  </section>;
}
