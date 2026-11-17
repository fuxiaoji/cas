import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react';
import { sideNames } from './engine';
import type { PortState } from './port';
import { shipCard, shipName, shipRarityName, shipTypeName } from './ship-catalog';
import { shipPortraitById } from './shipPortraits';
import './recruit-arrival.css';

function HarborPlot() {
  return <svg className="arrival-chart" viewBox="0 0 420 250" aria-hidden="true">
    <path d="M210 9v232M92 125h236M126 42l168 166M126 208 294 42" />
    {[31, 59, 87, 116].map((radius) => <circle key={radius} cx="210" cy="125" r={radius} />)}
    <path className="arrival-channel" d="M58 203 111 177 139 143 183 143 210 125l32-31 50-15 62-40m-144 86 31 50 41 15 70 40" />
    <path className="arrival-anchor" d="M210 112v25m-7-17h14m-19 9a12 12 0 0 0 24 0" />
    <circle className="arrival-anchor" cx="210" cy="109" r="3" />
  </svg>;
}

// A reveal can only read a CAS receipt already present in the account state.
// Dismissing, skipping or replaying it never rolls another draw.
export function RecruitArrival({ receipts, replay, onClose }: {
  receipts: PortState['history']; replay: boolean; onClose: () => void;
}) {
  const label = useId();
  const dialog = useRef<HTMLDialogElement>(null);
  const primary = useRef<HTMLButtonElement>(null);
  const [phase, setPhase] = useState<'scan' | 'arrival' | 'receipt'>(() => replay ? 'receipt' :
    window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'arrival' : 'scan');
  const [index, setIndex] = useState(0);
  const receipt = receipts[index];
  const more = phase === 'arrival' && index + 1 < receipts.length;
  const card = shipCard(receipt.ship);
  const portrait = shipPortraitById(receipt.ship);
  useLayoutEffect(() => {
    const element = dialog.current!;
    if (!element.open) element.showModal();
    return () => { if (element.open) element.close(); };
  }, []);
  useEffect(() => {
    const back = (event: Event) => { event.stopImmediatePropagation(); onClose(); };
    window.addEventListener('hardware-back', back, true);
    return () => window.removeEventListener('hardware-back', back, true);
  }, [onClose]);
  useEffect(() => {
    primary.current?.focus({ preventScroll: true });
    if (phase !== 'scan') return;
    const timer = window.setTimeout(() => setPhase('arrival'), 1100);
    return () => window.clearTimeout(timer);
  }, [phase]);

  function advance() {
    if (phase === 'receipt') onClose();
    else if (phase === 'scan') setPhase('arrival');
    else if (more) setIndex(value => value + 1);
    else setPhase('receipt');
  }
  const title = phase === 'scan' ? '港灯正在引航' : phase === 'arrival' ? '舰船到港' : '到港清册';
  return <dialog ref={dialog} className="recruit-arrival" aria-labelledby={label} data-draw-id={receipts.at(-1)!.id} data-phase={phase}
    data-ship={receipt.ship} onCancel={(event) => { event.preventDefault(); onClose(); }}>
    <header><div><span>{receipt.pool === 'up' ? '阵营 UP 池' : '常驻池'} · 本机征募</span><h2 id={label}>{title}</h2></div>
      <button type="button" onClick={phase === 'receipt' ? onClose : () => setPhase('receipt')}>
        {phase === 'receipt' ? '关闭到港报告' : '跳过动画'}
      </button>
    </header>
    <div className="arrival-content">
      {phase === 'scan' ? <div className="arrival-scan"><HarborPlot /><div aria-hidden="true" /><p>收到舰船呼号</p></div> :
        phase === 'receipt' && receipts.length > 1 ? <ol className="arrival-batch" aria-label="本次到港清册">
          {receipts.map(row => <li key={row.id} data-draw-id={row.id} data-ship={row.ship}>
            <strong>{shipName(row.ship)}</strong><span>{row.duplicate ? '转为舰队勋章' : '入列'}{row.guaranteed ? ' · 保底' : ''}</span>
          </li>)}
        </ol> : <>
        <div className="arrival-description">
          <span>{receipt.guaranteed ? '保底到港' : card ? sideNames[card.side] : '本机征募'}</span>
          <h3>{shipName(receipt.ship)}</h3>
          <p>{receipt.guaranteed && card ? sideNames[card.side] + ' · ' : ''}{card ? `${shipTypeName(card.type)} · ${shipRarityName(card.gachaRarity)}` : '单舰身份'}</p>
          <strong>{receipt.duplicate ? '该舰已在舰库，转为舰队勋章' : '已编入本机舰库'}</strong>
        </div>
        <figure className="arrival-portrait"><HarborPlot />
          {portrait && <><img src={portrait.src} alt={portrait.name + '舰娘立绘'} />
            <figcaption>{portrait.name} · 单舰身份</figcaption></>}
          {!portrait && <figcaption>{shipName(receipt.ship)} · 暂无立绘</figcaption>}
        </figure>
      </>}
    </div>
    <footer><span>{phase === 'scan' ? '接舰信号' : phase === 'arrival' && receipts.length > 1 ?
      `第 ${index + 1} / ${receipts.length} 艘` : `本次征募 ${receipts.length} 艘`}</span>
      <button ref={primary} type="button" onClick={advance}>
        {phase === 'scan' ? '查看舰船' : more ? '查看下一艘' : phase === 'arrival' ? '查看到港清册' : '确认入列'}
      </button>
    </footer>
  </dialog>;
}
