import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react';
import { sideNames } from './engine';
import { hulls } from './port';
import type { PortState } from './port';
import { shipPortrait } from './shipPortraits';
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
export function RecruitArrival({ receipt, replay, onClose }: {
  receipt: PortState['history'][number]; replay: boolean; onClose: () => void;
}) {
  const label = useId();
  const dialog = useRef<HTMLDialogElement>(null);
  const primary = useRef<HTMLButtonElement>(null);
  const [phase, setPhase] = useState<'scan' | 'arrival' | 'receipt'>(() => replay ? 'receipt' :
    window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'arrival' : 'scan');
  const hull = hulls[receipt.hull];
  const portrait = shipPortrait(receipt.hull);
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

  const title = phase === 'scan' ? '港灯正在引航' : phase === 'arrival' ? '舰船到港' : '到港清册';
  return <dialog ref={dialog} className="recruit-arrival" aria-labelledby={label} data-draw-id={receipt.id} data-phase={phase}
    data-hull={receipt.hull} onCancel={(event) => { event.preventDefault(); onClose(); }}>
    <header><div><span>{receipt.pool === 'up' ? '阵营 UP 池' : '常驻池'} · 本机征募</span><h2 id={label}>{title}</h2></div>
      <button type="button" onClick={phase === 'receipt' ? onClose : () => setPhase('receipt')}>
        {phase === 'receipt' ? '关闭到港报告' : '跳过动画'}
      </button>
    </header>
    <div className="arrival-content">
      {phase === 'scan' ? <div className="arrival-scan"><HarborPlot /><div aria-hidden="true" /><p>收到舰船呼号</p></div> : <>
        <div className="arrival-description">
          <span>{receipt.guaranteed ? '保底到港' : sideNames[hull.side]}</span>
          <h3>{hull.name}</h3><p>{receipt.guaranteed ? sideNames[hull.side] + ' · ' : ''}{hull.kind}</p>
          <strong>{receipt.duplicate ? '仓位已满，转为舰队勋章' : '已编入本机舰库'}</strong>
        </div>
        <figure className="arrival-portrait"><HarborPlot />
          {portrait && <><img src={portrait.src} alt={portrait.name + '舰娘立绘'} />
            <figcaption>{portrait.name} · 舰型代表</figcaption></>}
        </figure>
      </>}
    </div>
    <footer><span>{phase === 'scan' ? '接舰信号' : '本次征募 1 艘'}</span>
      <button ref={primary} type="button" onClick={phase === 'receipt' ? onClose : () => setPhase(phase === 'scan' ? 'arrival' : 'receipt')}>
        {phase === 'scan' ? '查看舰船' : phase === 'arrival' ? '查看到港清册' : '确认入列'}
      </button>
    </footer>
  </dialog>;
}
