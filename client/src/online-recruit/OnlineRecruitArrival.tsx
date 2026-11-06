import { useEffect, useId, useRef, useState } from 'react';
import { recruitPortrait } from './art';
import { rarityNames } from './types';
import type { RecruitReceipt, RecruitShip } from './types';
import './online-recruit.css';

export function OnlineRecruitArrival({ receipts, ships, replay, onClose }: {
  receipts: RecruitReceipt[]; ships: RecruitShip[]; replay: boolean; onClose: () => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const title = useId();
  const [index, setIndex] = useState(0);
  const [phase, setPhase] = useState<'scan' | 'ship' | 'report'>(() =>
    replay ? 'report' : window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'ship' : 'scan');
  useEffect(() => {
    const element = dialog.current;
    element?.showModal();
    return () => element?.close();
  }, []);
  useEffect(() => {
    const back = (event: Event) => { event.stopImmediatePropagation(); onClose(); };
    window.addEventListener('hardware-back', back, true);
    return () => window.removeEventListener('hardware-back', back, true);
  }, [onClose]);
  useEffect(() => {
    if (phase !== 'scan') return;
    const timer = window.setTimeout(() => setPhase('ship'), 1000);
    return () => window.clearTimeout(timer);
  }, [phase]);
  const receipt = receipts[index];
  const byId = new Map(ships.map(ship => [ship.id, ship]));
  const ship = byId.get(receipt.ship_id);
  const portrait = recruitPortrait(receipt.ship_id);
  function advance() {
    if (phase === 'report') onClose();
    else if (phase === 'scan') setPhase('ship');
    else if (index + 1 < receipts.length) setIndex(value => value + 1);
    else setPhase('report');
  }
  return <dialog ref={dialog} className="online-recruit-arrival" aria-labelledby={title} data-phase={phase}
    onCancel={event => { event.preventDefault(); onClose(); }}>
    <header><div><small>联机征募 · 已入账</small><h2 id={title}>{phase === 'scan' ? '港灯正在引航' : phase === 'ship' ? '舰船到港' : '到港清册'}</h2></div>
      {phase !== 'report' && <button type="button" onClick={() => setPhase('report')}>跳过动画</button>}
    </header>
    {phase === 'scan' ? <div className="online-arrival-scan" role="status">收到舰船呼号</div> :
      phase === 'ship' ? <div className="online-arrival-ship">
        <div><small>{rarityNames[receipt.rarity]} · {ship?.type ?? '舰船'}</small><h3>{ship?.name ?? receipt.ship_id}</h3>
          <p>{receipt.duplicate ? '重复舰船已转为舰队勋章。' : ship?.combat_ready ? '已编入收藏，可加入编队。' : '已编入收藏。'}</p></div>
        {portrait && <img src={portrait} alt={(ship?.name ?? receipt.ship_id) + '立绘'} data-character={receipt.ship_id} />}
      </div> : <ol className="online-arrival-report" aria-label="本次到港清册">{receipts.map(row =>
        <li key={row.id} data-receipt-id={row.id}><b>{byId.get(row.ship_id)?.name ?? row.ship_id}</b>
          <span>{rarityNames[row.rarity]} · {row.duplicate ? '重复转为勋章' : '新舰入列'}</span></li>)}</ol>}
    <footer><span>{phase === 'ship' ? `第 ${index + 1} / ${receipts.length} 艘` : `本次征募 ${receipts.length} 艘`}</span>
      <button type="button" className="primary" autoFocus onClick={advance}>{phase === 'report' ? '关闭到港清册' :
        phase === 'scan' ? '查看舰船' : index + 1 < receipts.length ? '查看下一艘' : '查看到港清册'}</button>
    </footer>
  </dialog>;
}
