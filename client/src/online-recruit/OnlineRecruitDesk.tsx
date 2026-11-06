// Pool disclosure, theme and history adapted from the 0.6.11 RecruitDesk.
import { recruitPortrait } from './art';
import { rarityNames } from './types';
import type { Rarity, RecruitPool, RecruitProgress, RecruitReceipt, RecruitShip } from './types';
import type { OnlineMeta } from '../online';
import './online-recruit.css';

const rarities = ['common', 'elite', 'rare', 'ur'] as const;
const percentage = (probability: number) => (probability * 100).toFixed(2) + '%';

type Props = {
  ships: RecruitShip[]; pools: RecruitPool[]; pool: RecruitPool; meta?: OnlineMeta; busy: boolean;
  onPool: (id: string) => void; onDraw: (id: string, count: number) => void; onExchange: (id: string) => void;
  onMail: () => void; onShop: () => void; onReview: (receipts: RecruitReceipt[]) => void;
};

export function recentBatch(progress?: RecruitProgress): RecruitReceipt[] {
  const last = progress?.history?.at(-1);
  if (!last) return [];
  return last.batch === undefined ? [last] : progress!.history!.filter(item => item.batch === last.batch);
}

export function OnlineRecruitDesk({ ships, pools, pool, meta, busy, onPool, onDraw, onExchange, onMail, onShop, onReview }: Props) {
  const up = pool.kind === 'up';
  const progress = meta?.pools?.[pool.id];
  const guaranteed = Boolean(up && progress?.up_guaranteed);
  const groups = Object.fromEntries(rarities.map(rarity => [rarity, ships.filter(ship => ship.recruitable && ship.rarity === rarity)])) as Record<Rarity, RecruitShip[]>;
  const offBanner = [...new Set(pool.ur_ship_ids)].filter(id => id !== pool.featured_ship_id).flatMap(id => groups.ur.filter(ship => ship.id === id));
  const featured = groups.ur.find(ship => ship.id === pool.featured_ship_id);
  const ur = featured ? [featured, ...offBanner] : offBanner;
  const candidates = [...groups.common, ...groups.elite, ...groups.rare, ...ur];
  const artwork = recruitPortrait((featured ?? ur.find(ship => ship.type === 'CV') ?? ur[0])?.id);
  const dedicated = (up ? meta?.wallet.up_tickets : meta?.wallet.standard_tickets) ?? 0;
  const shared = meta?.wallet.tickets ?? 0;
  const tickets = dedicated + shared;
  const history = progress?.history ?? [];
  const legacy = meta?.draw?.history ?? [];
  const batch = recentBatch(progress);
  const exchangePoints = progress?.exchange_points ?? 0;
  const shipsById = new Map(ships.map(ship => [ship.id, ship.name]));
  function probability(ship: RecruitShip, floor: number) {
    if (rarities.indexOf(ship.rarity) < floor) return 0;
    const sum = rarities.slice(floor).reduce((total, rarity) => total + pool.rates[rarity], 0);
    if (!sum) return 0;
    const share = ship.rarity !== 'ur' ? 1 / groups[ship.rarity].length :
      guaranteed ? Number(ship.id === featured?.id) : ship.id === featured?.id ? .5 : (featured ? .5 : 1) / offBanner.length;
    return pool.rates[ship.rarity] * share / sum;
  }
  function log(rows: RecruitReceipt[]) {
    return <ol>{rows.slice(-50).reverse().map(draw => <li key={draw.id}>
      第 {draw.index} 抽 · {shipsById.get(draw.ship_id) ?? draw.ship_id} · {rarityNames[draw.rarity]} · {draw.duplicate ? '重复转勋章' : '新舰入列'}
    </li>)}</ol>;
  }

  return <section className={'cas-online-recruit' + (up ? ' is-up' : '')} aria-label="舰船征募卡池">
    <nav className="online-recruit-tabs" aria-label="选择征募卡池">{pools.map(item =>
      <button type="button" key={item.id} aria-pressed={item.id === pool.id} aria-label={item.name} onClick={() => onPool(item.id)}>
        <strong>{item.name}</strong><small>{item.kind === 'up' ? '密苏里概率提升' : '五种舰型常驻 UR'}</small>
      </button>)}</nav>
    <div className="online-recruit-stage">
      {artwork && <img className="online-recruit-feature" src={artwork} alt="" />}
      <div className="online-recruit-copy">
        <small>{up ? 'UR 概率提升' : 'UR 常驻舰队'}</small>
        <h2>{featured?.name ?? '远海群星'}</h2>
        <p>{guaranteed ? '下次获得 UR 时必为密苏里。' : pool.description}</p>
        <div className="online-recruit-meters" aria-label="本池保底">
          {([['elite', progress?.since_elite, '精锐以上'], ['rare', progress?.since_rare, '稀有以上'], ['ur', progress?.since_ur, 'UR']] as const)
            .map(([id, count, title]) => <span key={id}><b>{Math.max(1, pool.pity[id] - (count ?? 0))}</b> 抽内 {title}</span>)}
        </div>
        <p className="online-recruit-balance">{up ? 'UP 券' : '常驻券'} {dedicated} · 旧通用券 {shared} · 本池可用 <b>{tickets}</b></p>
        <div className="online-pools">{[1, 10].map(count => <button type="button" className={count === 1 ? 'primary' : undefined}
          key={count} disabled={busy || tickets < count} onClick={() => onDraw(pool.id, count)}>征募 {count} 次</button>)}</div>
        <div className="online-recruit-links">
          <span>本池兑换进度 {exchangePoints}/{pool.exchange_price}</span>
          <button type="button" onClick={onMail}>前往邮箱</button>
          {!up && tickets < 10 && <button type="button" onClick={onShop}>查看补给商店</button>}
          {batch.length > 0 && <button type="button" onClick={() => onReview(batch)}>查看上次到港</button>}
        </div>
      </div>
    </div>
    <div className="online-recruit-ur" aria-label="本池 UR 舰船">{ur.map(ship => {
      const portrait = recruitPortrait(ship.id), owned = meta?.owned_ships.includes(ship.id);
      return <article key={ship.id} data-character={ship.id}>
        {portrait && <img src={portrait} alt="" loading="lazy" />}
        <small>UR · {ship.type}</small><h3>{ship.name}</h3>
        <p>{percentage(probability(ship, 0))} · {ship.combat_ready ? '可编队' : '收藏舰'}</p>
        <button type="button" disabled={busy || owned || exchangePoints < pool.exchange_price} onClick={() => onExchange(ship.id)}>
          {owned ? '已拥有 ' : '兑换 '}{ship.name}
        </button>
      </article>;
    })}</div>
    <details className="online-recruit-rules"><summary>概率与保证规则 · 本池独立记录</summary>
      <p>高档保证优先，获得更高档会重置对应低档计数。每抽累计 1 点本池兑换进度，指定兑换不改变保底。重复普通／精锐／稀有／UR 转 1／5／20／50 枚勋章。</p>
      <div className="online-recruit-table"><table><thead><tr><th>舰船</th><th>等级</th><th>基础</th>
        <th>{pool.pity.elite} 抽保证</th><th>{pool.pity.rare} 抽保证</th><th>{pool.pity.ur} 抽保证</th></tr></thead>
        <tbody>{candidates.map(ship => <tr key={ship.id}><td>{ship.name}</td><td>{rarityNames[ship.rarity]}</td>
          {rarities.map((_, floor) => <td key={floor}>{percentage(probability(ship, floor))}</td>)}</tr>)}</tbody>
      </table></div>
    </details>
    <details className="online-recruit-rules"><summary>{pool.name}征募记录（{history.length} 次）</summary>
      {history.length ? log(history) : <p>尚无记录。</p>}
    </details>
    {!!legacy.length && <details className="online-recruit-rules"><summary>旧版常驻航线 · 保留原进度</summary>
      <p>使用常驻券或旧通用券，普通 75%、精锐 20%、稀有 5%，无 UR。</p>
      {[1, 10].map(count => <button key={count} type="button" disabled={busy || (meta?.wallet.standard_tickets ?? 0) + shared < count}
        onClick={() => onDraw('legacy-v1', count)}>旧池征募 {count} 次</button>)}
      <button type="button" onClick={() => onReview(recentBatch(meta?.draw))}>回看旧池到港</button>
      {log(legacy)}
    </details>}
  </section>;
}
