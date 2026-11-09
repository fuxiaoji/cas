import { useEffect, useRef, useState } from 'react';
import { sideNames } from '../../engine';
import type { Pool, PortState } from '../../port';
import { drawRecruit, hulls, recruitReceipt, rosters } from '../../port';
import type { Hull } from '../../port';
import { shipPortrait } from '../../shipPortraits';
import { RecruitArrival } from '../../RecruitArrival';
import { Drawer, PityMeter, ShopCard, WalletBar } from '../../widgets/economy';
import type { WalletItem } from '../../widgets/economy';
import type { QuartermasterCounter } from '../quartermaster/counters';
import './recruit-screen.css';

type Props = {
  state: PortState;
  change: (reducer: (current: PortState) => PortState) => void;
  busy: boolean;
  onClose: () => void;
  onQuartermaster: (counter: QuartermasterCounter) => void;
  onCampaign?: () => void;
  onTraining?: () => void;
  initialPool?: Pool;
};

type DrawerName = 'probability' | 'records' | 'exchange';

const standardCandidates: Hull[] = ['fletcher', 'cleveland', 'kagero', 'sendai'];

function percent(value: number) {
  return Number.isInteger(value) ? value + '%' : value.toFixed(1) + '%';
}
function chance(hull: Hull, pool: Pool) {
  const base = hulls[hull].kind === '轻巡洋舰' ? 15 : 85;
  return pool === 'up' ? base : base / 2;
}

export function RecruitScreen({ state, change, busy, onClose, onQuartermaster, onTraining, initialPool = 'standard' }: Props) {
  const [pool, setPool] = useState<Pool>(initialPool);
  const [drawer, setDrawer] = useState<DrawerName>();
  const [arrival, setArrival] = useState<{ id: number; replay: boolean }>();
  const backRef = useRef<HTMLButtonElement>(null);
  const up = pool === 'up';
  const tickets = state.wallet[pool];
  const ticketName = up ? 'UP 券' : '常驻券';
  const side = up ? state.upSide : state.preset.side;
  const featuredHull = rosters[side][1];
  const featured = shipPortrait(featuredHull);
  const candidates: Hull[] = up ? rosters[state.upSide].slice(0, 2) : standardCandidates;
  const history = state.history.filter(draw => draw.pool === pool && Object.hasOwn(hulls, draw.hull));
  const latest = history[0];
  const pity = state.pity[pool];
  const remaining = Math.max(1, 10 - pity);
  const arrivalReceipts = arrival ? recruitReceipt(state.history, arrival.id) : [];
  const poolName = up ? '阵营 UP 池' : '常驻池';
  const poolTitle = up ? sideNames[state.upSide] + ' · UP' : '远洋群舰';

  useEffect(() => {
    backRef.current?.focus({ preventScroll: true });
  }, []);

  useEffect(() => {
    const close = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      if (document.querySelector('dialog[open]')) return;
      event.preventDefault();
      if (drawer) { setDrawer(undefined); return; }
      onClose();
    };
    window.addEventListener('keydown', close);
    return () => window.removeEventListener('keydown', close);
  }, [drawer, onClose]);

  useEffect(() => {
    const back = (event: Event) => {
      if (document.querySelector('dialog[open]')) return;
      event.stopImmediatePropagation();
      if (drawer) setDrawer(undefined);
      else onClose();
    };
    window.addEventListener('hardware-back', back, true);
    return () => window.removeEventListener('hardware-back', back, true);
  }, [drawer, onClose]);

  function recruit(count: 1 | 10) {
    if (busy || !state.starter || arrival || state.wallet[pool] < count) return;
    const entropy = crypto.getRandomValues(new Uint32Array(count * 2));
    setArrival({ id: state.sequence + count, replay: false });
    change(current => drawRecruit(current, pool, entropy));
  }
  function openCounter(counter: QuartermasterCounter) {
    onQuartermaster(counter);
  }

  const walletItems: WalletItem[] = [
    { key: 'standard', label: '常驻券', value: state.wallet.standard, icon: '▱', tone: 'ticket' },
    { key: 'up', label: 'UP 券', value: state.wallet.up, icon: '▱', tone: 'up' },
  ];
  const poolRows: { id: Pool; name: string; kicker: string; detail: string }[] = [
    { id: 'standard', name: '常驻池', kicker: '远洋群舰', detail: '同盟与轴心等概率' },
    { id: 'up', name: '阵营 UP 池', kicker: sideNames[state.upSide] + ' · 概率提升', detail: '只出 UP 阵营舰型' },
  ];

  return <section className="recruit-screen" role="dialog" aria-modal="true" aria-label="军港征募" data-recruit-screen data-pool={pool}>
    <header className="rs-top">
      <button ref={backRef} type="button" className="rs-back" onClick={onClose}>‹ 返回军需处</button>
      <div className="rs-title">
        <small>NIGHT ROADSTEAD · 探照灯已开</small>
        <h1>军港征募</h1>
      </div>
      <WalletBar className="rs-wallet" items={walletItems} label="征募券" />
      <button type="button" className="rs-record" data-open-drawer="records" onClick={() => setDrawer('records')}>
        记录 <b>{history.length}</b>
      </button>
    </header>

    <div className="rs-body">
      <aside className="rs-pools" aria-label="征募卡池">
        <header><small>POOL BERTHS</small><h2>卡池泊位</h2></header>
        {poolRows.map(row => <button type="button" key={row.id} data-pool={row.id}
          aria-pressed={pool === row.id} aria-label={row.name} onClick={() => setPool(row.id)}>
          <span className="rs-pool-beacon" aria-hidden="true" />
          <span className="rs-pool-copy">
            <strong>{row.name}</strong><small>{row.kicker}</small><em>{row.detail}</em>
          </span>
          <b className="rs-pool-tickets">{state.wallet[row.id]}</b>
        </button>)}
        <p className="rs-pool-note">两池保底与记录各自独立；切换卡池不会重置已抽次数。概率与保底在右侧公示。</p>
      </aside>

      <main className="rs-stage" data-stage-pool={pool}>
        <div className="rs-beam rs-beam--a" aria-hidden="true" />
        <div className="rs-beam rs-beam--b" aria-hidden="true" />
        <div className="rs-lamp rs-lamp--a" aria-hidden="true" />
        <div className="rs-lamp rs-lamp--b" aria-hidden="true" />
        <div className="rs-stage-copy">
          <small>夜间军港 · 信号灯引导入泊</small>
          <h2>{poolTitle}</h2>
          <p>{up ? `本池只出${sideNames[state.upSide]}舰型；UP 阵营仅包含该阵营舰型。` : '常驻征募：同盟与轴心等概率，驱逐与轻巡按固定概率出现。'}</p>
          <div className="rs-stage-stats">
            <span><b>{ticketName}</b> {tickets}</span>
            <span><b>保底</b> {remaining} 抽内出轻巡</span>
            <span><b>最近到港</b> {latest ? hulls[latest.hull].name : '尚无'}</span>
          </div>
          <div className="rs-stage-links">
            <button type="button" onClick={() => setDrawer('probability')}>概率</button>
            <button type="button" onClick={() => setDrawer('records')}>记录</button>
            <button type="button" onClick={() => setDrawer('exchange')}>兑换</button>
          </div>
          {!state.starter && <p className="rs-block">领取初始舰队后开放征募。
            {onTraining && <button type="button" onClick={onTraining}>前往教学复习</button>}</p>}
          {state.starter && tickets < 10 && <p className="rs-hint">十连还差 {10 - tickets} 张{ticketName}；补给在军需处「补给配给」。</p>}
        </div>
        {featured && <img className="rs-feature" src={featured.src} alt={(featured.name || hulls[featuredHull].name) + '舰娘立绘'} />}
        <div className="rs-stage-foot">
          <span data-signal={tickets > 0 ? 'green' : 'red'}><i aria-hidden="true" />{tickets > 0 ? '泊位信号：绿灯' : '泊位信号：红灯'}</span>
          <span>探照灯扫过泊位 · {poolName}</span>
        </div>
      </main>

      <aside className="rs-intel" aria-label="本池情报">
        <section className="rs-panel">
          <header><small>FEATURED</small><h2>{up ? '本期 UP' : '本期焦点'}</h2></header>
          {up ? <ShopCard id="up-featured" art={featured?.src} kicker={sideNames[state.upSide] + ' · 阵营 UP'}
            title={hulls[featuredHull].name}
            subtitle={`${hulls[featuredHull].kind} · 只在本池出现；换池不改变 UP 阵营。`}
            tags={['本池焦点', 'UP 阵营']} status="UP" tone="ok"
            priceNote={percent(chance(featuredHull, 'up')) + ' 本池概率'}
            onSelect={() => setDrawer('probability')} />
            : <div className="rs-up-pair">
              {(['cleveland', 'sendai'] as Hull[]).map(hull => {
                const art = shipPortrait(hull);
                return <figure key={hull}>
                  {art && <img src={art.src} alt="" loading="lazy" />}
                  <figcaption><strong>{hulls[hull].name}</strong><small>{hulls[hull].kind} · {percent(chance(hull, 'standard'))}</small></figcaption>
                </figure>;
              })}
              <p>常驻池不设 UP；同盟与轴心各 50%，两艘轻巡各 7.5%。</p>
            </div>}
        </section>

        <section className="rs-panel">
          <header><small>PROBABILITY</small><h2>本池概率</h2></header>
          <ul className="rs-rates">
            {candidates.map(hull => <li key={hull}>
              <span>{hulls[hull].name}</span><small>{hulls[hull].kind}</small>
              <b>{percent(chance(hull, pool))}</b>
            </li>)}
          </ul>
          <p>每抽驱逐 85% / 轻巡 15%；常驻池两阵营等分，UP 池只出 UP 阵营。</p>
          <button type="button" className="rs-link" onClick={() => setDrawer('probability')}>查看完整概率与规则</button>
        </section>

        <section className="rs-panel">
          <header><small>PITY</small><h2>{remaining} 抽内出轻巡</h2></header>
          <PityMeter value={pity} limit={10} label="本池保底计数" caption={`第 ${pity + 1} 抽计入本池保底；两池独立。`} />
          <p>连续 9 次未获得轻巡后，下一抽必出轻巡。保底只提高舰种，不改变阵营。</p>
        </section>

        <section className="rs-panel">
          <header><small>EXCHANGE</small><h2>兑换与重复</h2></header>
          <p>重复到港自动转舰队勋章：驱逐 +1、轻巡 +3。本机不开放舰船勋章兑换，战术兑换在军需处。</p>
          <button type="button" className="rs-link" onClick={() => setDrawer('exchange')}>查看兑换规则</button>
        </section>

        <section className="rs-panel rs-arrival-panel">
          <header><small>ARRIVAL</small><h2>最近到港</h2></header>
          {latest ? <div className="rs-last" data-last-draw={latest.id}>
            <small>{latest.guaranteed ? '保底到港' : '最近到港'} · 第 {latest.id} 抽</small>
            <strong>{hulls[latest.hull].name}</strong>
            <span>{latest.duplicate ? '重复 · 已转舰队勋章' : '新舰入列'} · {latest.pool === 'up' ? 'UP 池' : '常驻池'}</span>
            <button type="button" className="rs-link" onClick={() => setArrival({ id: latest.id, replay: true })}>回看到港报告</button>
          </div> : <p>本池尚无到港记录。征募 1 或 10 次后在这里留下回执。</p>}
        </section>
      </aside>
    </div>

    <footer className="rs-draw-bar">
      <div className="rs-draw-balance">
        <span>常驻券 <b>{state.wallet.standard}</b></span>
        <span>UP 券 <b>{state.wallet.up}</b></span>
      </div>
      <div className="rs-draw-pity">
        <PityMeter compact value={pity} limit={10} label="保底" caption={remaining + ' 抽内出轻巡'} />
      </div>
      <div className="rs-draw-actions">
        <button type="button" className="cas-btn" data-draw="1"
          disabled={busy || !state.starter || tickets < 1} onClick={() => recruit(1)}>
          征募 1<span>1 张</span>
        </button>
        <button type="button" className="cas-btn cas-btn--primary" data-draw="10"
          disabled={busy || !state.starter || tickets < 10} onClick={() => recruit(10)}>
          征募 10<span>10 张</span>
        </button>
      </div>
    </footer>

    <Drawer open={drawer === 'probability'} name="probability" title="本池概率与保底" kicker={poolName + ' · 公示'}
      onClose={() => setDrawer(undefined)} wide footer={<button type="button" className="cas-btn" onClick={() => setDrawer(undefined)}>关闭</button>}>
      <p>每抽驱逐舰 85%、轻巡洋舰 15%。{up ? 'UP 池只出当前 UP 阵营，阵营内两艘舰型按上述舰种概率分配。' : '常驻池同盟与轴心各 50%，两阵营按上述舰种概率分配。'}</p>
      <table>
        <thead><tr><th>舰船</th><th>舰种</th><th>阵营</th><th>本池每抽</th></tr></thead>
        <tbody>{candidates.map(hull => <tr key={hull}>
          <td>{hulls[hull].name}</td><td>{hulls[hull].kind}</td><td>{sideNames[hulls[hull].side]}</td>
          <td>{percent(chance(hull, pool))}</td>
        </tr>)}</tbody>
      </table>
      <h3>保底</h3>
      <p>连续 9 次未获得轻巡后，下一抽必出轻巡；中出轻巡后计数重置。两池独立计算，互不继承。保底只作用于舰种，不改变阵营。</p>
      <h3>重复到港</h3>
      <p>重复征募自动转舰队勋章：驱逐舰 +1、轻巡洋舰 +3。到港回执会写明「重复 · 已转舰队勋章」，不另行消耗货币。</p>
      <h3>兑换边界</h3>
      <p>本机征募台没有舰船兑换点；舰队勋章兑换、6 勋章炮战 AI 与联机礼包都在军需处「礼包与兑换」说明。抽卡概率与接口未在本批改动。</p>
    </Drawer>

    <Drawer open={drawer === 'records'} name="records" title={poolName + '到港记录'} kicker={`本池 ${history.length} 次 · 最近 50 次`}
      onClose={() => setDrawer(undefined)} footer={<button type="button" className="cas-btn" onClick={() => setDrawer(undefined)}>关闭</button>}>
      {history.length ? <ol className="rs-records">{history.map(draw => <li key={draw.id} data-draw-id={draw.id}>
        <span>第 {draw.id} 抽</span>
        <strong>{hulls[draw.hull].name}</strong>
        <small>{draw.duplicate ? '重复 · 转舰队勋章' : '入列'}{draw.guaranteed ? ' · 保底' : ''}{draw.batchSize === 10 ? ' · 十连' : ''}</small>
      </li>)}</ol> : <p>本池尚无到港记录。切换卡池可以查看另一池的记录。</p>}
      <p>记录只读本机已保存的到港回执；回看不会重新抽卡。</p>
    </Drawer>

    <Drawer open={drawer === 'exchange'} name="exchange" title="兑换与重复到港" kicker="本机征募 · 不新增货币"
      onClose={() => setDrawer(undefined)} footer={<>
        <button type="button" className="cas-btn" onClick={() => setDrawer(undefined)}>留在卡池</button>
        <button type="button" className="cas-btn cas-btn--primary" onClick={() => openCounter('exchange')}>前往军需处兑换</button>
      </>}>
      <p>本机不开放舰船勋章兑换，也不新增征募点或兑换币。重复到港自动转舰队勋章，兑换与礼包沿用既有账目。</p>
      <h3>重复到港</h3>
      <ul><li>重复驱逐舰：+1 舰队勋章</li><li>重复轻巡洋舰：+3 舰队勋章</li></ul>
      <h3>舰队勋章去处</h3>
      <ul>
        <li>军需处「礼包与兑换」：6 舰队勋章兑换炮战 AI（既有）。</li>
        <li>联机账号：联机补给可按 15 / 45 / 120 / 300 勋章兑换舰船。</li>
        <li>联机征募台：每抽累计 1 点本池兑换进度，80 点兑换当期 UP（线上规则，本机不开放）。</li>
      </ul>
      <h3>补券去处</h3>
      <p>常驻券与 UP 券来自签到、战役、挑战复战、周补给与邮箱；周常驻券在军需处「补给配给」每周一次。</p>
      <div className="rs-drawer-actions">
        <button type="button" className="cas-btn" onClick={() => openCounter('supply')}>去补给配给</button>
        <button type="button" className="cas-btn" onClick={() => openCounter('exchange')}>去礼包与兑换</button>
      </div>
    </Drawer>

    {arrival && arrivalReceipts.length > 0 && <RecruitArrival key={arrival.id} receipts={arrivalReceipts}
      replay={arrival.replay} onClose={() => setArrival(undefined)} />}
  </section>;
}
