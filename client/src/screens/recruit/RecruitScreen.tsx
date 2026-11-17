import { useEffect, useRef, useState } from 'react';
import { sideNames } from '../../engine';
import type { Pool, PortState } from '../../port';
import {
  claimLocalMail, drawChance, drawRecruit, duplicateMedals, poolShips, RARITY_ORDER,
  RARITY_WEIGHTS, recruitReceipt,
} from '../../port';
import {
  FEATURED_SHIP, shipCard, shipName, shipRarityName, shipTypeName,
} from '../../ship-catalog';
import type { ShipCard, ShipRarity } from '../../ship-catalog';
import { shipPortraitById } from '../../shipPortraits';
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
  initialPool?: Pool;
};

type DrawerName = 'probability' | 'records' | 'exchange';

function percent(value: number) {
  if (!Number.isFinite(value) || value <= 0) return '0%';
  if (value >= 10) return value.toFixed(0) + '%';
  if (value >= 1) return value.toFixed(1) + '%';
  return value.toFixed(2) + '%';
}
function cardChance(card: ShipCard, pool: Pool) {
  return percent(drawChance(card, pool) * 100);
}
function byRarity(a: ShipCard, b: ShipCard) {
  return RARITY_ORDER.indexOf(a.gachaRarity) - RARITY_ORDER.indexOf(b.gachaRarity) ||
    a.type.localeCompare(b.type) || a.name.localeCompare(b.name, 'zh-CN');
}

export function RecruitScreen({ state, change, busy, onClose, onQuartermaster, initialPool = 'standard' }: Props) {
  const [pool, setPool] = useState<Pool>(initialPool);
  const [drawer, setDrawer] = useState<DrawerName>();
  const [arrival, setArrival] = useState<{ id: number; replay: boolean }>();
  const backRef = useRef<HTMLButtonElement>(null);
  const up = pool === 'up';
  const tickets = state.wallet[pool];
  const ticketName = up ? 'UP 券' : '常驻券';
  const featuredCard = shipCard(FEATURED_SHIP);
  const featured = shipPortraitById(FEATURED_SHIP);
  const cards = poolShips().slice().sort(byRarity);
  const tierRows = RARITY_ORDER.map((rarity: ShipRarity) => ({
    rarity, weight: RARITY_WEIGHTS[rarity], count: cards.filter(card => card.gachaRarity === rarity).length,
  }));
  const history = state.history.filter(draw => draw.pool === pool && !!shipCard(draw.ship));
  const latest = history[0];
  const latestCard = latest ? shipCard(latest.ship) : undefined;
  const pity = state.pity[pool];
  const remaining = Math.max(1, 10 - pity);
  const arrivalReceipts = arrival ? recruitReceipt(state.history, arrival.id) : [];
  const poolName = up ? '密苏里 UP 池' : '常驻池';
  const poolTitle = up ? '密苏里 · UP' : '远洋群舰';
  const welcome = state.mail?.find(letter => letter.id === 'welcome-20' && !letter.claimed);

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
    if (busy || arrival || state.wallet[pool] < count) return;
    const entropy = crypto.getRandomValues(new Uint32Array(count * 3));
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
    { id: 'standard', name: '常驻池', kicker: '远洋群舰', detail: '全部 202 艘可出战单舰' },
    { id: 'up', name: '密苏里 UP 池', kicker: '密苏里 · 概率提升', detail: '全部 202 艘单舰 · UR 内 50%' },
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
        <p className="rs-pool-note">两池保底与记录各自独立；切换卡池不会重置已抽次数。两池都包含全部 202 艘可出战单舰，区别只在 UP 池的密苏里概率提升。</p>
      </aside>

      <main className="rs-stage" data-stage-pool={pool}>
        <div className="rs-beam rs-beam--a" aria-hidden="true" />
        <div className="rs-beam rs-beam--b" aria-hidden="true" />
        <div className="rs-lamp rs-lamp--a" aria-hidden="true" />
        <div className="rs-lamp rs-lamp--b" aria-hidden="true" />
        <div className="rs-stage-copy">
          <small>夜间军港 · 信号灯引导入泊</small>
          <h2>{poolTitle}</h2>
          <p>{up ? '本池为密苏里 UP：全部 202 艘可出战单舰，密苏里在 UR 稀有度内 50% 命中。'
            : '常驻征募：同盟与轴心全部 202 艘可出战单舰按稀有度权重出现。'}</p>
          <div className="rs-stage-stats">
            <span><b>{ticketName}</b> {tickets}</span>
            <span><b>保底</b> {remaining} 抽内出 SR+</span>
            <span><b>最近到港</b> {latest ? shipName(latest.ship) : '尚无'}</span>
          </div>
          <div className="rs-stage-links">
            <button type="button" onClick={() => setDrawer('probability')}>概率</button>
            <button type="button" onClick={() => setDrawer('records')}>记录</button>
            <button type="button" onClick={() => setDrawer('exchange')}>兑换</button>
          </div>
          {tickets < 1 && welcome && <p className="rs-hint">内测补给：邮箱「内测启航补给」有 20 张常驻券。
            <button type="button" onClick={() => change(current => claimLocalMail(current, 'welcome-20'))}>领取内测补给</button>
          </p>}
          {tickets > 0 && tickets < 10 && <p className="rs-hint">十连还差 {10 - tickets} 张{ticketName}；补给在军需处「补给配给」，内测期抽卡不要求先完成教学。</p>}
        </div>
        {featured && <img className="rs-feature" src={featured.src} alt={(featured.name || shipName(FEATURED_SHIP)) + '舰娘立绘'} />}
        <div className="rs-stage-foot">
          <span data-signal={tickets > 0 ? 'green' : 'red'}><i aria-hidden="true" />{tickets > 0 ? '泊位信号：绿灯' : '泊位信号：红灯'}</span>
          <span>探照灯扫过泊位 · {poolName}</span>
        </div>
      </main>

      <aside className="rs-intel" aria-label="本池情报">
        <section className="rs-panel">
          <header><small>FEATURED</small><h2>{up ? '本期 UP' : '本期焦点'}</h2></header>
          <ShopCard id="up-featured" art={featured?.src} kicker={up ? '密苏里 · 阵营 UP' : '密苏里 · UR 旗舰'}
            title={shipName(FEATURED_SHIP)}
            subtitle={featuredCard ? `${shipTypeName(featuredCard.type)} · ${shipRarityName(featuredCard.gachaRarity)} · ${up ? '本池 UR 内 50% 命中；池内仍包含全部 202 艘单舰。' : '常驻池不设 UP；与全部 UR 均分权重。'}` : '密苏里待登记'}
            tags={['本期焦点', up ? '密苏里 UP' : 'UR 旗舰', 'UR']} status={up ? 'UP' : 'UR'} tone="ok"
            priceNote={featuredCard ? cardChance(featuredCard, pool) + ' 本池每抽' : undefined}
            onSelect={() => setDrawer('probability')} />
          <p>常驻池与 UP 池都包含同盟、轴心全部 202 艘可出战单舰；UP 池只把密苏里的 UR 份额提高到 50%。</p>
        </section>

        <section className="rs-panel">
          <header><small>PROBABILITY</small><h2>本池概率</h2></header>
          <ul className="rs-rates" data-candidate-count={cards.length}>
            {tierRows.map(row => <li key={row.rarity} data-rarity={row.rarity}>
              <span>{shipRarityName(row.rarity)}</span><small>{row.count} 艘</small>
              <b>{row.weight}%</b>
            </li>)}
          </ul>
          <p>本池候选 {cards.length} 艘单舰；{featuredCard ? `密苏里在 UR 内占 ${up ? '50%' : '1 / ' + tierRows.find(row => row.rarity === 'ur')?.count}` : ''}。</p>
          <button type="button" className="rs-link" onClick={() => setDrawer('probability')}>查看完整概率与规则</button>
        </section>

        <section className="rs-panel">
          <header><small>PITY</small><h2>{remaining} 抽内出 SR+</h2></header>
          <PityMeter value={pity} limit={10} label="本池保底计数" caption={`第 ${pity + 1} 抽计入本池保底；两池独立。`} />
          <p>连续 9 次未获得 SR 及以上，下一抽必出 SR 及以上；出 SR+ 后计数重置。保底只提高稀有度，不改变池内单舰构成。</p>
        </section>

        <section className="rs-panel">
          <header><small>EXCHANGE</small><h2>兑换与重复</h2></header>
          <p>每艘 identity 只占一个舰库位；重复到港自动转舰队勋章：UR +5、SSR +3、SR +2、R +1。本机不开放舰船勋章兑换，战术兑换在军需处。</p>
          <button type="button" className="rs-link" onClick={() => setDrawer('exchange')}>查看兑换规则</button>
        </section>

        <section className="rs-panel rs-arrival-panel">
          <header><small>ARRIVAL</small><h2>最近到港</h2></header>
          {latest ? <div className="rs-last" data-last-draw={latest.id} data-last-ship={latest.ship}>
            <small>{latest.guaranteed ? '保底到港' : '最近到港'} · 第 {latest.id} 抽</small>
            <strong>{shipName(latest.ship)}</strong>
            <span>{latestCard ? `${shipTypeName(latestCard.type)} · ${shipRarityName(latestCard.gachaRarity)} · ` : ''}{latest.duplicate ? '重复 · 已转舰队勋章' : '新舰入列'} · {latest.pool === 'up' ? '密苏里 UP 池' : '常驻池'}</span>
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
        <PityMeter compact value={pity} limit={10} label="保底" caption={remaining + ' 抽内出 SR+'} />
      </div>
      <div className="rs-draw-actions">
        <button type="button" className="cas-btn" data-draw="1"
          disabled={busy || tickets < 1} onClick={() => recruit(1)}>
          征募 1<span>1 张</span>
        </button>
        <button type="button" className="cas-btn cas-btn--primary" data-draw="10"
          disabled={busy || tickets < 10} onClick={() => recruit(10)}>
          征募 10<span>10 张</span>
        </button>
      </div>
    </footer>

    <Drawer open={drawer === 'probability'} name="probability" title="本池概率与保底" kicker={poolName + ' · 公示'}
      onClose={() => setDrawer(undefined)} wide footer={<button type="button" className="cas-btn" onClick={() => setDrawer(undefined)}>关闭</button>}>
      <p>每抽按稀有度权重：UR 2%、SSR 8%、SR 20%、R 70%。{up
        ? 'UP 池包含全部 202 艘可出战单舰；密苏里在 UR 稀有度内占 50%，其余 UR 均分剩余 50%。'
        : '常驻池包含同盟与轴心全部 202 艘可出战单舰，不设阵营或舰种分池。'}</p>
      <table>
        <thead><tr><th>舰名</th><th>舰种</th><th>稀有度</th><th>阵营</th><th>本池每抽</th></tr></thead>
        <tbody>{cards.map(card => <tr key={card.id} data-ship={card.id}>
          <td>{card.name}</td><td>{shipTypeName(card.type)}</td><td>{shipRarityName(card.gachaRarity)}</td>
          <td>{sideNames[card.side]}</td><td>{cardChance(card, pool)}</td>
        </tr>)}</tbody>
      </table>
      <h3>保底</h3>
      <p>连续 9 次未获得 SR 及以上，下一抽必出 SR 及以上；出 SR+ 后计数重置。两池独立计算，互不继承。保底只作用于稀有度，不改变池内单舰构成。</p>
      <h3>重复到港</h3>
      <p>每艘单舰 identity 只占一个舰库位；重复征募自动转舰队勋章：UR +5、SSR +3、SR +2、R +1。到港回执会写明「重复 · 已转舰队勋章」，不另行消耗货币。</p>
      <h3>兑换边界</h3>
      <p>本机征募台没有舰船兑换点；舰队勋章兑换、6 勋章炮战 AI 与联机礼包都在军需处「礼包与兑换」说明。</p>
    </Drawer>

    <Drawer open={drawer === 'records'} name="records" title={poolName + '到港记录'} kicker={`本池 ${history.length} 次 · 最近 50 次`}
      onClose={() => setDrawer(undefined)} footer={<button type="button" className="cas-btn" onClick={() => setDrawer(undefined)}>关闭</button>}>
      {history.length ? <ol className="rs-records">{history.map(draw => {
        const card = shipCard(draw.ship);
        return <li key={draw.id} data-draw-id={draw.id} data-ship={draw.ship}>
          <span>第 {draw.id} 抽</span>
          <strong>{shipName(draw.ship)}</strong>
          <small>{card ? `${shipTypeName(card.type)} · ${shipRarityName(card.gachaRarity)} · ` : ''}{draw.duplicate ? '重复 · 转舰队勋章' : '入列'}{draw.guaranteed ? ' · 保底' : ''}{draw.batchSize === 10 ? ' · 十连' : ''}</small>
        </li>;
      })}</ol> : <p>本池尚无到港记录。切换卡池可以查看另一池的记录。</p>}
      <p>记录只读本机已保存的到港回执；回看不会重新抽卡。</p>
    </Drawer>

    <Drawer open={drawer === 'exchange'} name="exchange" title="兑换与重复到港" kicker="本机征募 · 不新增货币"
      onClose={() => setDrawer(undefined)} footer={<>
        <button type="button" className="cas-btn" onClick={() => setDrawer(undefined)}>留在卡池</button>
        <button type="button" className="cas-btn cas-btn--primary" onClick={() => openCounter('exchange')}>前往军需处兑换</button>
      </>}>
      <p>本机不开放舰船勋章兑换，也不新增征募点或兑换币。每艘单舰 identity 只占一个舰库位，重复到港自动转舰队勋章。</p>
      <h3>重复到港</h3>
      <table>
        <thead><tr><th>稀有度</th><th>重复转勋章</th></tr></thead>
        <tbody>{RARITY_ORDER.map(rarity => <tr key={rarity}><td>{shipRarityName(rarity)}</td><td>+{duplicateMedals(rarity)}</td></tr>)}</tbody>
      </table>
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
