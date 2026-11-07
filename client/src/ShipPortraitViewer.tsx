import { useEffect, useRef } from 'react';
import { shipPortraitById } from './shipPortraits';
import type { RecruitShip } from './online-recruit/types';
import { rarityNames, shipTypeNames } from './online-recruit/types';
import './online-supply.css';

/**
 * Full-body portrait viewer from the collection shelf (铁底湾 0.6.11
 * mobile/src/fleet/FleetPanel.tsx portrait dialog). Only ledger-registered
 * portrait assets are ever passed in, so the dialog can never show a stand-in.
 */
export function ShipPortraitViewer({ ship, onClose }: { ship: RecruitShip; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const art = shipPortraitById(ship.id);
  useEffect(() => {
    const element = dialog.current;
    element?.showModal();
    return () => { if (element?.open) element.close(); };
  }, []);
  useEffect(() => {
    const back = (event: Event) => { event.stopImmediatePropagation(); onClose(); };
    window.addEventListener('hardware-back', back, true);
    return () => window.removeEventListener('hardware-back', back, true);
  }, [onClose]);
  if (!art) return null;
  return <dialog ref={dialog} className="online-portrait-dialog" aria-label={ship.name + '全身立绘'}
    onClose={onClose}
    onClick={event => { if (event.target === dialog.current) dialog.current?.close(); }}>
    <img src={art.src} alt={ship.name + '全身立绘'} data-character={ship.id}/>
    <div><small>{shipTypeNames[ship.type] ?? ship.type}</small><h2>{ship.name}</h2>
      <p>{rarityNames[ship.rarity]} · 收藏立绘</p></div>
    <button autoFocus aria-label="关闭立绘" onClick={() => dialog.current?.close()}>×</button>
  </dialog>;
}
