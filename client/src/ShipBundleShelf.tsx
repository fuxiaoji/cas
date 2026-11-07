import { useState } from 'react';
import type { OnlineMeta } from './online';
import type { RecruitShip } from './online-recruit/types';
import { rarityNames } from './online-recruit/types';
import { recruitPortrait } from './online-recruit/art';
import './ship-bundles.css';

// Duplicate ships convert into medals at the same rates as recruitment,
// mirroring 铁底湾 0.6.11 mobile/src/meta/store.ts DUPLICATE_MEDALS.
const duplicateMedals: Record<string, number> = { common: 1, elite: 5, rare: 20, ur: 50 };
const shipTypes: Record<string, string> = { DD: '驱逐舰', CL: '轻巡洋舰', CA: '重巡洋舰', BB: '战列舰', CV: '航空母舰' };
export const shipBundleClaimId = (id: string) => 'shop:ship-bundle:' + id;

type Bundle = { id: string; name: string; description?: string; credits: number; ship_ids: string[] };

function ShipSignal({ name }: { name: string }) {
  return <svg className="arrival-ship-signal" viewBox="0 0 220 110" role="img" aria-label={name + '信号剪影'}>
    <path className="signal-water" d="M9 88h200M25 96h160M43 103h125"/>
    <path d="m21 73 178-5-20 18H43Z"/>
    <path d="M53 71V55h35V42h23v29m12-1V51h15v19m13-1V57h19v12M97 43V22m0 9h29M73 55V44m72 9 13-10h21m-132 20-19-8m129 8 31-8"/>
    <path className="signal-window" d="M92 49h10m-34 14h12m49-7h5"/>
  </svg>;
}

function BundleShipArt({ ship }: { ship: RecruitShip }) {
  const [failed, setFailed] = useState(false);
  const portrait = recruitPortrait(ship.id);
  if (portrait && !failed) {
    return <img className="arrival-ship-art" src={portrait} alt="" onError={() => setFailed(true)}/>;
  }
  return <ShipSignal name={ship.name}/>;
}

export function ShipBundleShelf({ bundles, ships, meta, busy, onBuy }: {
  bundles: Bundle[]; ships: RecruitShip[]; meta: OnlineMeta; busy?: boolean; onBuy: (bundleId: string) => void;
}) {
  const byId = new Map(ships.map(ship => [ship.id, ship]));
  return <section className="ship-bundle-shelf" aria-label="三舰编成礼包">
    <header><h3>三舰编成礼包</h3><p>每包固定三艘舰，使用补给币购买，每包限购一次。</p></header>
    <div className="ship-bundle-grid">{bundles.map(bundle => {
      // Only the bundles the server catalog actually issues, with three
      // recruitable identities. CAS grants collection ships here; the
      // reference's combat-ready gate does not apply to this catalog.
      const items = bundle.ship_ids.flatMap(id => {
        const ship = byId.get(id);
        return ship && ship.recruitable !== false ? [ship] : [];
      });
      if (items.length !== 3) return null;
      const claimed = meta.claims.includes(shipBundleClaimId(bundle.id));
      const owned = (ship: RecruitShip) => meta.owned_ships.includes(ship.id);
      const complete = items.every(owned);
      const shortfall = Math.max(0, bundle.credits - meta.wallet.credits);
      const detail = claimed ? '已购买' : complete ? '三舰均已拥有' :
        shortfall ? `还差${shortfall}补给币` : '可购买';
      return <article className="ship-bundle" key={bundle.id} data-bundle={bundle.id}>
        <div className="ship-bundle-kicker">{items[0]?.side === 'axis' ? '轴心' : '同盟'}舰队 <span>三舰固定入列</span></div>
        <h4>{bundle.name}</h4>
        <p>{bundle.description}</p>
        <div className="ship-bundle-ships">{items.map(ship => <div key={ship.id}>
          <div className="ship-bundle-art"><BundleShipArt ship={ship}/></div>
          <strong>{ship.name}</strong>
          <small>{owned(ship) ? (claimed || complete ? '已拥有' : `已有 · 转${duplicateMedals[ship.rarity]}勋章`) :
            `${shipTypes[ship.type] ?? ship.type} · ${rarityNames[ship.rarity]}`}</small>
        </div>)}</div>
        <footer>
          <div><strong>{bundle.credits.toLocaleString()} 补给币</strong><small>{detail}</small></div>
          <button aria-label={`购买${bundle.name}`} disabled={!!busy || claimed || complete || shortfall > 0}
            onClick={() => onBuy(bundle.id)}>购买礼包</button>
        </footer>
      </article>;
    })}</div>
  </section>;
}
