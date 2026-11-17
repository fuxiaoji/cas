import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { AI_SHOP, aiShopBlockReason, aiShopOwned, aiShopStars, aiShopUnlocked, buyAiShopEntry } from '../../ai-shop';
import type { AiShopEntry } from '../../ai-shop';
import { sideNames } from '../../engine';
import { getGunnery, ownedShips } from '../../port';
import type { PortState } from '../../port';
import { FEATURED_SHIP, shipRarityName, shipTypeName } from '../../ship-catalog';
import { buyWeeklyTicket, claimWeeklySupply, CHALLENGE_WEEKLY_TICKETS, WEEKLY_TICKET_PRICE, weeklyStatus } from '../../activities/week';
import { shipPortraitById } from '../../shipPortraits';
import { Drawer, ShopCard, WalletBar } from '../../widgets/economy';
import type { ShopAction, ShopMeta, WalletItem } from '../../widgets/economy';
import { quartermasterCounters } from './counters';
import type { QuartermasterCounter } from './counters';
import './quartermaster.css';

type Props = {
  state: PortState;
  change: (reducer: (current: PortState) => PortState) => void;
  busy: boolean;
  counter: QuartermasterCounter;
  onCounter: (counter: QuartermasterCounter) => void;
  onRecruit: () => void;
  onCampaign?: () => void;
};

type Notice = { title: string; detail: string };
type Item = {
  key: string;
  kicker?: string;
  title: string;
  subtitle?: string;
  tags?: string[];
  meta?: ShopMeta[];
  art?: string;
  price?: string;
  priceNote?: string;
  status: string;
  tone: 'ok' | 'owned' | 'locked' | 'warn' | 'dim';
  reason?: string;
  action?: ShopAction;
  children?: ReactNode;
  className?: string;
  data?: Record<string, string | number | boolean | undefined>;
};

const counterCopy: Record<QuartermasterCounter, { kicker: string; title: string; note: string }> = {
  ships: { kicker: 'COUNTER 01 · 舰船', title: '舰船柜台', note: '征募入口与已拥有单舰清单；采购不在卡池里。' },
  supply: { kicker: 'COUNTER 02 · 配给', title: '补给配给', note: '每周常驻券与实战补给，沿用现有本机经济。' },
  ai: { kicker: 'COUNTER 03 · 战术', title: 'AI 战术室', note: '按 doctrine 采购风格；解锁读战役通关，价格用常驻券。' },
  exchange: { kicker: 'COUNTER 04 · 兑换', title: '礼包与兑换', note: '舰队勋章与既有兑换；不新增货币，不卖数值。' },
};

const roleNames: Record<string, string> = {
  screen: '屏护协同', escort: '屏护协同', torpedo: '雷击突击', gunnery: '炮战纵队', gun: '炮战纵队',
  brawler: '近战乱斗', brawl: '近战乱斗', kiter: '远距风筝', kite: '远距风筝',
  denial: '雷网封路', torpedo_denial: '雷网封路', torpedoDenial: '雷网封路',
  support: '支援协同', scout: '侦察引导',
};

const axisSpec = [
  { key: 'engagement', label: '交战距离', names: ['engagement', 'engage', 'engagementRange', 'range', 'distance', 'standoff', 'gunRange', '交战距离'] },
  { key: 'maneuver', label: '机动', names: ['maneuver', 'maneuverability', 'mobility', 'speed', 'evasion', '机动'] },
  { key: 'torpedo', label: '雷击', names: ['torpedo', 'torp', 'torpedo_denial', 'torpedoDenial', 'torpedoAttack', 'torpedoThreat', 'denial', '雷击'] },
] as const;

type AxisKey = typeof axisSpec[number]['key'];
type AxisReading = { value?: number; word?: string };
type AxisRead = Partial<Record<AxisKey, AxisReading>>;

const axisWords: Record<string, Record<string, { value: number; word: string }>> = {
  engagement: {
    near: { value: 25, word: '近距' }, mid: { value: 55, word: '中距' }, far: { value: 85, word: '远距' },
  },
  maneuver: {
    brawl: { value: 25, word: '乱战' }, screen: { value: 55, word: '屏护' }, kite: { value: 85, word: '风筝' },
  },
  torpedo: {
    direct: { value: 80, word: '直击' }, deny: { value: 92, word: '封路' }, support: { value: 45, word: '支援' },
  },
};

function numeric(value: unknown): number | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() && Number.isFinite(Number(value))) return Number(value);
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const record = value as Record<string, unknown>;
    for (const key of ['value', 'score', 'level', 'rating', 'weight']) {
      if (typeof record[key] === 'number' && Number.isFinite(record[key])) return record[key] as number;
    }
  }
  return undefined;
}

function stringField(value: unknown): string {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return '';
  const record = value as Record<string, unknown>;
  for (const key of ['label', 'word', 'text', 'name', 'id', 'band', 'state', 'kind']) {
    if (typeof record[key] === 'string' && record[key].trim()) return record[key].trim();
  }
  return '';
}

function roleText(value: unknown): string {
  if (typeof value === 'string') return value.trim();
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const record = value as Record<string, unknown>;
    for (const key of ['label', 'name', 'id', 'role']) {
      if (typeof record[key] === 'string' && record[key].trim()) return record[key].trim();
    }
  }
  return '';
}

function axisFromName(name: string) {
  const token = name.trim().toLowerCase();
  return axisSpec.find(spec => spec.names.some(candidate => candidate.toLowerCase() === token || token.includes(candidate.toLowerCase())));
}

function readAxis(axis: AxisKey, value: unknown): AxisReading {
  const score = numeric(value);
  if (score !== undefined) return { value: score, word: stringField(value) || undefined };
  if (typeof value === 'string') {
    const word = axisWords[axis]?.[value.trim().toLowerCase()];
    if (word) return word;
  }
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const record = value as Record<string, unknown>;
    for (const key of ['band', 'state', 'level', 'kind', 'text', 'id']) {
      const reading = readAxis(axis, record[key]);
      if (reading.value !== undefined || reading.word) return reading;
    }
  }
  return {};
}

/** ai-shop.ts may grow role/axes/fit/risk; the ledger accepts numeric or
 *  categorical axes (near/mid/far, brawl/screen/kite, direct/deny/support)
 *  without editing the shop module. */
function readAxes(value: unknown): AxisRead {
  const out: AxisRead = {};
  if (Array.isArray(value)) {
    if (value.every(entry => typeof entry === 'number')) {
      axisSpec.forEach((spec, index) => {
        if (typeof value[index] === 'number') out[spec.key] = { value: value[index] as number };
      });
      return out;
    }
    for (const entry of value) {
      if (!entry || typeof entry !== 'object') continue;
      const record = entry as Record<string, unknown>;
      const spec = axisFromName(String(record.axis ?? record.key ?? record.label ?? record.name ?? ''));
      if (!spec) continue;
      const reading = readAxis(spec.key, record.value ?? record.score ?? record.level ?? record.rating ?? record.band ?? record.state);
      if (reading.value !== undefined || reading.word) out[spec.key] = reading;
    }
    return out;
  }
  if (value && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    for (const spec of axisSpec) {
      for (const name of spec.names) {
        if (!(name in record)) continue;
        const reading = readAxis(spec.key, record[name]);
        if (reading.value !== undefined || reading.word) { out[spec.key] = reading; break; }
      }
    }
    if (!Object.keys(out).length && record.axes) return readAxes(record.axes);
  }
  return out;
}

function scaledAxes(read: AxisRead) {
  const present = Object.values(read).filter(reading => reading?.value !== undefined) as AxisReading[];
  if (!present.length) return [];
  const max = Math.max(...present.map(reading => reading.value as number));
  const categorical = present.some(reading => !!reading.word);
  const scale = categorical ? 1 : max <= 1 ? 100 : max <= 5 ? 20 : max <= 10 ? 10 : 1;
  return axisSpec.map(spec => {
    const reading = read[spec.key];
    const value = reading?.value;
    return { ...spec, value: value === undefined ? undefined : Math.round(Math.max(0, Math.min(100, value * scale))), word: reading?.word };
  });
}

function textList(value: unknown): string[] {
  if (typeof value === 'string') return value.trim() ? [value.trim()] : [];
  if (Array.isArray(value)) {
    return value.flatMap(entry => typeof entry === 'string' && entry.trim() ? [entry.trim()] : []);
  }
  if (value && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    for (const key of ['text', 'items', 'notes', 'summary']) {
      if (Array.isArray(record[key]) || typeof record[key] === 'string') return textList(record[key]);
    }
  }
  return [];
}

function AiDoctrine({ entry }: { entry: AiShopEntry }) {
  const extra = entry as unknown as { role?: unknown; axes?: unknown; fit?: unknown; risk?: unknown };
  const axes = scaledAxes(readAxes(extra.axes));
  const role = roleText(extra.role);
  const roleLabel = role ? roleNames[role] ?? role : '';
  const fit = textList(extra.fit);
  const risk = textList(extra.risk);
  const hasAxes = axes.some(axis => axis.value !== undefined);
  return <>
    {(roleLabel || fit.length > 0 || risk.length > 0) && <div className="ai-doctrine" data-role={role || undefined}>
      {roleLabel && <span className="ai-role">{roleLabel}</span>}
      {fit.length > 0 && <p className="ai-fit"><b>适配</b>{fit.join(' · ')}</p>}
      {risk.length > 0 && <p className="ai-risk"><b>风险</b>{risk.join(' · ')}</p>}
    </div>}
    {hasAxes ? <figure className="ai-axes" data-axes={hasAxes} aria-label="三轴相对定位">
      <figcaption>三轴定位 · 相对刻度</figcaption>
      {axisSpec.map(spec => {
        const axis = axes.find(row => row.key === spec.key);
        const value = axis?.value;
        return <div className="ai-axis" data-axis={spec.key} data-word={axis?.word} key={spec.key}>
          <span>{spec.label}</span>
          <div className="ai-axis__track" role="img" aria-label={`${spec.label}${axis?.word ?? (value === undefined ? '待登记' : ' ' + value)}`}>
            <i style={{ width: value === undefined ? 0 : value + '%' }} />
          </div>
          <b>{axis?.word ?? (value === undefined ? '—' : value)}</b>
        </div>;
      })}
    </figure> : <p className="ai-axes-missing" data-axes="false">三轴定位待 doctrine 数据登记</p>}
  </>;
}

function defaultItem(counter: QuartermasterCounter) {
  if (counter === 'ships') return 'recruit';
  if (counter === 'supply') return 'weekly-ticket';
  if (counter === 'ai') return AI_SHOP[0]?.id ?? 'ai-empty';
  return 'gunnery';
}

export function Quartermaster({ state, change, busy, counter, onCounter, onRecruit, onCampaign }: Props) {
  const [selected, setSelected] = useState<string>(() => defaultItem(counter));
  const [notice, setNotice] = useState<Notice>();
  const [orderOpen, setOrderOpen] = useState(false);
  const shelfRef = useRef<HTMLDivElement>(null);
  const week = weeklyStatus(state);
  const copy = counterCopy[counter];
  const unlockedAi = AI_SHOP.filter(entry => aiShopUnlocked(entry, state.campaignProgress)).length;
  const ownedAi = AI_SHOP.filter(entry => aiShopOwned(state, entry)).length;
  const ownedShipCards = ownedShips(state);
  const ownedCount = ownedShipCards.length;

  useEffect(() => {
    setSelected(defaultItem(counter));
    setOrderOpen(false);
    shelfRef.current?.scrollTo({ top: 0 });
  }, [counter]);

  function announce(title: string, detail: string) {
    setNotice({ title, detail });
  }
  function buyAi(entry: AiShopEntry) {
    const reason = aiShopBlockReason(state, entry);
    if (busy || reason) return;
    change(current => buyAiShopEntry(current, entry));
    announce('已入库', `${entry.name} · ${entry.cost} 张常驻征募券 · 余额 ${state.wallet.standard - entry.cost} 张`);
  }
  function ticket() {
    if (busy || week.ticket || state.credits < WEEKLY_TICKET_PRICE) return;
    change(current => buyWeeklyTicket(current));
    announce('已入库', `常驻征募券 ×1 · ${WEEKLY_TICKET_PRICE} 信用点 · 余额 ${state.credits - WEEKLY_TICKET_PRICE}`);
  }
  function supply() {
    if (busy || week.count < 3 || week.supply) return;
    change(current => claimWeeklySupply(current));
    announce('已领取', `每周实战补给 · +500 信用点 · +${CHALLENGE_WEEKLY_TICKETS} 张常驻券`);
  }
  function gunnery() {
    if (busy || state.marks < 6 || state.profiles.includes('gunnery')) return;
    change(getGunnery);
    announce('已入库', `炮战 AI · 6 舰队勋章 · 余额 ${state.marks - 6} 枚`);
  }

  const shipItems: Item[] = [
    {
      key: 'recruit', kicker: '军港征募 · 独立页面', title: '进入军港征募',
      subtitle: '卡池、UP、概率、保底与到港记录在另一处；军需处只负责采购与兑换。',
      tags: ['常驻池', '密苏里 UP'], art: shipPortraitById(FEATURED_SHIP)?.src,
      priceNote: `${state.wallet.standard} 常驻券 · ${state.wallet.up} UP 券`,
      status: '开放', tone: 'ok',
      reason: undefined,
      action: { label: '进入军港征募', primary: true,
        disabled: busy, onClick: onRecruit },
    },
    ...ownedShipCards.map((card): Item => ({
      key: 'ship:' + card.id, kicker: shipTypeName(card.type), title: card.name,
      subtitle: `${sideNames[card.side]} · ${card.class ?? '舰级未登记'} · ${shipRarityName(card.gachaRarity)}`,
      tags: ['已入列'],
      art: shipPortraitById(card.id)?.src,
      priceNote: `${card.points ?? 0} 点 · 已拥有`,
      status: '在港', tone: 'owned',
      meta: [{ label: '身份', value: card.id }],
      data: { 'data-owned-ship': card.id },
    })),
    ...(ownedShipCards.length ? [] : [{
      key: 'ship-empty', kicker: '舰库', title: '暂无单舰',
      subtitle: '完成初始舰队或到军港征募，就能在这里看到每一艘已拥有的单舰。',
      tags: ['空状态'], status: '待征募', tone: 'dim' as const,
      priceNote: '抽卡入口在上方',
      action: { label: '进入军港征募', onClick: onRecruit },
    }]),
  ];

  const supplyItems: Item[] = [
    {
      key: 'weekly-ticket', kicker: '每周配给', title: '每周常驻征募券',
      subtitle: `${WEEKLY_TICKET_PRICE} 信用点兑换 1 张常驻征募券；周一北京时间 00:00 刷新。`,
      tags: ['每周 1 次'], price: `${WEEKLY_TICKET_PRICE} 信用点`,
      priceNote: week.ticket ? '本周已兑换' : `余额 ${state.credits.toLocaleString()}`,
      status: week.ticket ? '本周已兑换' : state.credits < WEEKLY_TICKET_PRICE ? '信用点不足' : '可兑换',
      tone: week.ticket ? 'owned' : state.credits < WEEKLY_TICKET_PRICE ? 'warn' : 'ok',
      reason: week.ticket ? '下周一 00:00 后重置购买次数。'
        : state.credits < WEEKLY_TICKET_PRICE ? `还差 ${WEEKLY_TICKET_PRICE - state.credits} 信用点。` : undefined,
      action: { label: week.ticket ? '本周已兑换' : '兑换常驻券',
        disabled: busy || week.ticket || state.credits < WEEKLY_TICKET_PRICE, onClick: ticket },
    },
    {
      key: 'weekly-supply', kicker: '每周实战', title: '每周实战补给',
      subtitle: `本周达成 3 局越级挑战主目标，领取 500 信用点与 ${CHALLENGE_WEEKLY_TICKETS} 张常驻券。`,
      tags: ['免费', '每周 1 次'], price: '免费', priceNote: `进度 ${Math.min(week.count, 3)} / 3`,
      status: week.supply ? '本周已领取' : week.count >= 3 ? '可领取' : '进行中',
      tone: week.supply ? 'owned' : week.count >= 3 ? 'ok' : 'dim',
      reason: week.supply ? '下周一 00:00 后重置领取状态。' : `还差 ${Math.max(0, 3 - week.count)} 局越级挑战。`,
      action: { label: week.supply ? '本周已领取' : '领取实战补给', primary: !week.supply && week.count >= 3,
        disabled: busy || week.supply || week.count < 3, onClick: supply },
    },
    {
      key: 'supply-rule', kicker: '配给说明', title: '本机补给口径',
      subtitle: '补给配给只含周常驻券与每周实战补给；维修与燃料不在本机经济里计费，出击整备由母港完成。',
      tags: ['不新增货币'], status: '说明', tone: 'dim',
      priceNote: onCampaign ? '征募券的其他来源：战役、挑战、签到' : undefined,
      action: onCampaign ? { label: '前往战役', onClick: onCampaign } : undefined,
    },
  ];

  const aiItems: Item[] = AI_SHOP.map((entry): Item => {
    const owned = aiShopOwned(state, entry);
    const unlocked = aiShopUnlocked(entry, state.campaignProgress);
    const reason = owned ? undefined : aiShopBlockReason(state, entry);
    const stars = aiShopStars(entry, state.campaignProgress);
    const stageName = entry.stageName ?? entry.stage ?? '战役';
    return {
      key: entry.id, className: 'ai-shop-card', kicker: 'AI doctrine',
      title: entry.name, subtitle: entry.description,
      tags: [roleTag(entry), entry.provisional ? '暂定强度' : ''].filter(Boolean),
      meta: [{ label: '解锁', value: `通关「${stageName}」${unlocked ? '（已达成）' : `（当前 ${stars} 星）`}` }],
      price: `${entry.cost} 常驻征募券`, priceNote: owned ? '已入库' : `余额 ${state.wallet.standard} 张`,
      status: owned ? '已拥有' : !unlocked ? '未解锁' : reason ? '券不足' : '可采购',
      tone: owned ? 'owned' : !unlocked ? 'locked' : reason ? 'warn' : 'ok',
      reason,
      action: { label: owned ? '已拥有' : !unlocked ? '未解锁' : reason ? '常驻券不足' : '采购',
        disabled: busy || owned || !unlocked || !!reason, onClick: () => buyAi(entry) },
      data: { 'data-ai-profile': entry.id, 'data-owned': owned, 'data-unlocked': unlocked,
        'data-role': roleText((entry as unknown as { role?: unknown }).role) || undefined },
      children: <AiDoctrine entry={entry} />,
    };
  });
  if (!AI_SHOP.length) {
    aiItems.push({
      key: 'ai-empty', kicker: 'AI doctrine', title: '战术目录暂未装载',
      subtitle: '本机没有可采购的 AI doctrine；不伪造商品。', status: '空', tone: 'dim', priceNote: '—',
    });
  }

  const exchangeItems: Item[] = [
    {
      key: 'gunnery', kicker: '舰队勋章兑换', title: '炮战 AI · 内置',
      subtitle: '沿用既有 6 勋章兑换；与商店里用常驻券采购的 evolved doctrine 分开记账。',
      tags: ['6 舰队勋章', '不解锁新经济'], price: '6 舰队勋章',
      priceNote: `余额 ${state.marks} 枚`,
      status: state.profiles.includes('gunnery') ? '已拥有' : state.marks < 6 ? '勋章不足' : '可兑换',
      tone: state.profiles.includes('gunnery') ? 'owned' : state.marks < 6 ? 'warn' : 'ok',
      reason: state.profiles.includes('gunnery') ? '已拥有，可在出航编队或战斗内选用。'
        : state.marks < 6 ? `还差 ${6 - state.marks} 枚舰队勋章。` : undefined,
      action: { label: state.profiles.includes('gunnery') ? '已拥有' : '6 勋章兑换',
        disabled: busy || state.profiles.includes('gunnery') || state.marks < 6, onClick: gunnery },
    },
    {
      key: 'duplicate', kicker: '到港兑换规则', title: '重复到港转勋章',
      subtitle: '重复征募自动转勋章：驱逐舰 +1、轻巡洋舰 +3；本机不开放舰船勋章兑换。',
      tags: ['自动结算'], status: '规则', tone: 'dim', priceNote: '无需手动兑换',
    },
    {
      key: 'online-bundle', kicker: '联机礼包', title: '联机舰船礼包',
      subtitle: '联机账号在「联机补给」购买舰船礼包，重复舰船按服务端规则转勋章；本机军需处不卖联机礼包。',
      tags: ['联机账号'], status: '联机开放', tone: 'dim', priceNote: '本机不开放',
    },
    {
      key: 'online-ship', kicker: '联机兑换', title: '勋章兑换舰船',
      subtitle: '联机账号可在联机补给按 15 / 45 / 120 / 300 勋章兑换舰船；本机不新增同类兑换。',
      tags: ['15 / 45 / 120 / 300'], status: '联机开放', tone: 'dim', priceNote: '本机不开放',
    },
  ];

  const items = counter === 'ships' ? shipItems : counter === 'supply' ? supplyItems
    : counter === 'ai' ? aiItems : exchangeItems;
  const selectedItem = items.find(item => item.key === selected) ?? items[0];
  const walletItems: WalletItem[] = [
    { key: 'credits', label: '信用点', value: state.credits, icon: '◈', tone: 'credits', hint: '本机补给币；周常驻券与既有补给使用。' },
    { key: 'marks', label: '舰队勋章', value: state.marks, icon: '✧', tone: 'marks', hint: '重复征募与战役三星获得；6 勋章兑换炮战 AI。' },
    { key: 'standard', label: '常驻券', value: state.wallet.standard, icon: '▱', tone: 'ticket', hint: '常驻征募与 AI doctrine 采购使用。' },
  ];

  function orderBody(compact: boolean) {
    if (!selectedItem) return <p>本柜台暂无商品。</p>;
    return <>
      <p className="qm-order__kicker">{selectedItem.kicker ?? copy.kicker}</p>
      <h3 className="qm-order__title">{selectedItem.title}</h3>
      {selectedItem.subtitle && <p className="qm-order__sub">{selectedItem.subtitle}</p>}
      <dl className="qm-order__facts">
        <div><dt>价格</dt><dd>{selectedItem.price ?? selectedItem.priceNote ?? '—'}</dd></div>
        <div><dt>状态</dt><dd>{selectedItem.status}</dd></div>
        {selectedItem.price && selectedItem.priceNote && <div><dt>余额</dt><dd>{selectedItem.priceNote}</dd></div>}
      </dl>
      {selectedItem.reason && <p className="qm-order__reason">{selectedItem.reason}</p>}
      {selectedItem.action
        ? <button type="button" className={'cas-btn qm-order__buy' + (selectedItem.action.primary ? ' cas-btn--primary' : '')}
          data-qm-order-action disabled={selectedItem.action.disabled}
          onClick={() => { selectedItem.action?.onClick(); if (compact) setOrderOpen(false); }}>
          {selectedItem.action.label}
        </button>
        : <p className="qm-order__muted">该条目只作说明，无需采购。</p>}
    </>;
  }

  return <div className="quartermaster" data-quartermaster-counter={counter}>
    <header className="qm-top">
      <WalletBar className="qm-wallet" items={walletItems} label="军需处账面" />
      <div className="qm-top-actions">
        <button type="button" className="qm-acquire" onClick={() => onCounter('supply')}>获取</button>
        <button type="button" className="qm-order-toggle" onClick={() => setOrderOpen(true)}>采购单</button>
      </div>
    </header>

    {notice && <div className="qm-notice-bar" role="status" data-qm-notice data-ai-shop-notice>
      <b>{notice.title}</b><span>{notice.detail}</span>
      <button type="button" onClick={() => setNotice(undefined)} aria-label="关闭回执">×</button>
    </div>}

    <section className="qm-body">
      <nav className="qm-counters" aria-label="军需处柜台">
        {quartermasterCounters.map((row, index) => <button type="button" key={row.id}
          className="qm-counter" aria-pressed={counter === row.id} aria-label={row.label}
          data-counter={row.id} onClick={() => onCounter(row.id)}>
          <span className="qm-counter__index">{String(index + 1).padStart(2, '0')}</span>
          <span className="qm-counter__copy"><strong>{row.label}</strong><small>{row.note}</small></span>
          {row.id === 'ai' && <b className="qm-counter__badge">{ownedAi}/{AI_SHOP.length}</b>}
        </button>)}
      </nav>

      <div className="qm-shelf" ref={shelfRef} data-quartermaster-shelf={counter}>
        <header className="qm-shelf-head">
          <div><small>{copy.kicker}</small><h2>{copy.title}</h2></div>
          <p>{copy.note}</p>
        </header>
        <div className={'qm-grid' + (counter === 'ai' ? ' ai-shop-grid' : '')} data-quartermaster-grid={counter}
          data-ai-count={counter === 'ai' ? AI_SHOP.length : undefined}>
          {items.map(item => <ShopCard key={item.key} id={item.key} selected={selectedItem?.key === item.key}
            onSelect={() => setSelected(item.key)} art={item.art} kicker={item.kicker} title={item.title}
            subtitle={item.subtitle} tags={item.tags} meta={item.meta} price={item.price} priceNote={item.priceNote}
            status={item.status} tone={item.tone} reason={item.reason}
            action={item.action && { ...item.action, onClick: () => { setSelected(item.key); item.action?.onClick(); } }}
            className={item.className} data={item.data}>{item.children}</ShopCard>)}
        </div>
        {counter === 'ai' && <p className="qm-fine">
          {AI_SHOP.length} 套 doctrine · 已解锁 {unlockedAi} / {AI_SHOP.length} · 已拥有 {ownedAi} / {AI_SHOP.length}。
          价格为常驻征募券；provisional 强度会随版本复核，购买记录随本机账号保存。
        </p>}
        {counter === 'ships' && <p className="qm-fine">
          已拥有 {ownedCount} 艘单舰（每艘 identity 唯一）。重复到港自动转舰队勋章；内测期征募不要求先完成教学。
        </p>}
        {counter === 'exchange' && <p className="qm-fine">
          礼包与兑换沿用既有账目：6 勋章炮战 AI、重复到港转勋章、联机账号的舰船礼包与 15/45/120/300 勋章兑换。
          本机不新增货币或舰船兑换。
        </p>}
      </div>

      <aside className="qm-order" aria-label="采购单">
        <header className="qm-order__head"><small>采购单</small><h2>今日配给</h2></header>
        {orderBody(false)}
        <section className="qm-ledger">
          <h3>柜台账簿</h3>
          <div><span>信用点</span><b>{state.credits.toLocaleString()}</b></div>
          <div><span>常驻券</span><b>{state.wallet.standard}</b></div>
          <div><span>舰队勋章</span><b>{state.marks}</b></div>
          <div><span>本周实战</span><b>{Math.min(week.count, 3)} / 3</b></div>
          <div><span>AI 已解锁</span><b>{unlockedAi} / {AI_SHOP.length}</b></div>
        </section>
        <p className="qm-order__note">军需处只做采购与兑换；征募在「军港征募」独立页面进行。账面在干船坞抄录，购买后盖章入册。</p>
      </aside>
    </section>

    <footer className="qm-buybar" data-quartermaster-buybar>
      <div className="qm-buybar__copy">
        <small>{copy.title} · 采购单</small>
        <strong>{selectedItem?.title ?? '请选择条目'}</strong>
      </div>
      <div className="qm-buybar__price">
        <span>{selectedItem?.price ?? selectedItem?.priceNote ?? '—'}</span>
        <small>{selectedItem?.status ?? ''}</small>
      </div>
      {selectedItem?.action
        ? <button type="button" className={'cas-btn' + (selectedItem.action.primary ? ' cas-btn--primary' : '')}
          disabled={selectedItem.action.disabled}
          onClick={() => selectedItem.action?.onClick()}>{selectedItem.action.label}</button>
        : <button type="button" className="cas-btn" onClick={() => setOrderOpen(true)}>查看说明</button>}
    </footer>

    <Drawer open={orderOpen} name="quartermaster-order" title="采购单" kicker="军需处 · 干船坞账本"
      onClose={() => setOrderOpen(false)} footer={
        <button type="button" className="cas-btn" onClick={() => setOrderOpen(false)}>关闭</button>
      }>{orderBody(true)}</Drawer>
  </div>;
}

function roleTag(entry: AiShopEntry) {
  const role = roleText((entry as unknown as { role?: unknown }).role);
  return role ? roleNames[role] ?? role : '';
}
