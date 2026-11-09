import { useEffect, useState } from 'react';
import { ask, clock } from './engine';
import type { Side } from './engine';
import { CampaignMap, campaignMapStageIds, campaignPlace, charts, places } from './campaign-map';
import type { CampaignMapSelection } from './campaign-map';
import { campaignForceGroup, campaignLegacyFormation, campaignScenarioTitle, campaignShipName, campaignText } from './campaign-labels';
import { campaignBest, campaignDifficulties, campaignRewards, campaignRewardText, campaignStars, pendingCampaignRewards } from './campaign-progress';
import type { CampaignDifficulty, CampaignLaunch, CampaignMission, CampaignOutcome, CampaignProgress, CampaignStars } from './campaign-progress';
import './campaign-archive.css';

export type Match = 'exact_historical_counterpart' | 'related_alternate' | 'unverified' | 'ibs_original_or_absent';
export type Reference = { document: string; pdf_pages: number[]; printed_pages: number[] };
export type Entry = {
  ibs_id: string; ibs_title: string; ibs_date: string; ibs_kind: string; stage_ids: string[];
  classification: Match; cas: null | { scenario_id: string; title: string; source: Reference; verification: string; import: string | null };
  playable: boolean; note: string; runtime?: { historicalReady: boolean; label: string; localOnly?: boolean };
};
export interface Archive { schema_version: number; content_version: string; scenarios: Entry[] }
export type FleetOption = { id: string; class: string; name: string; kind: string; points: number };
export type FleetPosition = {
  position: number; fleet: number; name: string; leader?: string; course?: number;
  speed: number; x?: number; y?: number; members: number;
};
export type FleetPick = {
  budget: number;
  historical: { class: string; name: string; kind: string; points: number; slot: number }[];
  options: FleetOption[];
  positions?: FleetPosition[];
  taskForceSupported?: boolean;
};
type Condition = { type: string; count?: number; kind?: string; pct?: number; damage_pct?: number; damage_pct_gte?: number;
  fraction?: number; distance_nmi?: number; duration_seconds?: number; tonnage_gt?: number };
export type Goal = string | { all_of: Condition[] } | { type: string; ratio?: number } | null;
export type Objective = { orders: string; decisive: Goal; tactical: Goal };
export interface RecordDetail {
  record: null | { start: { date_local: string; time_local: string; location: string }; environment?: {
    light?: string; visibility_pct?: number; sea_state?: number; wind_from_deg?: number; wind_speed_knots?: number | number[];
  }; forces?: Record<Side, unknown>; groups?: { id: string; side: Side; unit: string; members_in_order: string[]; course_deg: number; speed_knots: number }[];
  ships?: { id: string; name: string }[]; objectives: Record<Side, Objective>;
  setup?: Record<string, unknown>;
  special_rules?: (string | { rule: string })[]; blockers: (string | { detail: string })[] };
  readiness: null | { datedShips: number; periodProfiles: number; unresolvedPeriodData: { id: string }[] };
  legacy?: LegacyDeployment | null;
}

type LegacyShip = {
  ibs_ship_id: string; name: string; side: Side; initial_hex: string; x_m: number; y_m: number;
  heading_deg: number; speed_knots: number; formation_id: string | null; cas_profile_id: string | null;
};
type LegacyDeployment = {
  title: string; map: { width_m: number; height_m: number };
  start: { light_hint: string | null; legacy_turn_limit: number | null };
  ships: LegacyShip[]; formations: { id: string; note?: string | null }[]; objectives: { intent: string[] }; gates: string[];
  post_default_formation_setup?: { ships: Pick<LegacyShip, 'ibs_ship_id' | 'initial_hex' | 'x_m' | 'y_m' | 'heading_deg' | 'speed_knots'>[] } | null;
  conflicts: unknown[]; source: { baseline: string };
};

export const matchNames: Record<Match, string> = {
  exact_historical_counterpart: '同一历史战斗', related_alternate: '相关改编',
  unverified: '尚待核对', ibs_original_or_absent: '旧作想定或未找到',
};
const sources: Record<string, string> = { rising_sun_5e: '《旭日》（第五版）', steel_typhoon_5e: '《钢铁台风》（第五版）' };
const sides = ['allies', 'axis'] as const;
const sideName = { allies: '同盟', axis: '轴心' };
const difficultyNotes: Record<CampaignDifficulty, string> = {
  story: '敌方使用协同战术。', standard: '敌方以炮战为主。', challenge: '敌方优先寻找鱼雷攻击位置。',
};

export function CampaignStarRating({ stars }: { stars: CampaignStars }) {
  return <span className="campaign-stars" role="img" aria-label={`${stars} / 3 星`} data-stars={stars}>
    {[1, 2, 3].map((number) => <span key={number} aria-hidden="true" data-earned={number <= stars}>{number <= stars ? '★' : '☆'}</span>)}
  </span>;
}

export function CampaignResultSummary({ campaign, result }: { campaign: CampaignMission; result: CampaignOutcome }) {
  const stars = campaignStars(result);
  const grade = result.grade === 'decisive' ? '决定胜利' : result.grade === 'tactical' ? '战术胜利' : '未达成任务';
  return <div className="campaign-debrief" data-stage-id={campaign.stageId} data-difficulty={campaign.difficulty}>
    <div><span>{campaignDifficulties[campaign.difficulty]}难度</span><strong>{typeof result.primary === 'string' && result.primary ? result.primary : grade}</strong></div>
    <CampaignStarRating stars={stars} />
  </div>;
}

export function CampaignMissionBrief({ campaign }: { campaign: CampaignMission }) {
  return <section className="campaign-mission-brief" aria-label="战役任务">
    <strong>{campaign.missionLabel}</strong><span>{campaignDifficulties[campaign.difficulty]}难度</span><p>{campaign.objectives}</p>
    {campaign.supplySeconds !== undefined && <p>{campaign.supplyComplete ? '维拉卸载已完成' : `维拉卸载连续计时 ${clock(campaign.supplySeconds)} / 30:00`}</p>}
    {campaign.supplyScore !== undefined && <p>已卸补给 {campaign.supplyScore} 分{campaign.supplyStrings !== undefined ? ` · 余 ${campaign.supplyStrings} 串` : ''}</p>}
  </section>;
}

export function CampaignRewardActions({ stageId, progress, onClaim, busy }: {
  stageId: string; progress?: CampaignProgress; onClaim: () => void; busy?: boolean;
}) {
  const pending = pendingCampaignRewards(progress, stageId);
  const claimed = progress?.[stageId]?.claimed ?? 0;
  if (!pending.length) return claimed > 0 ? <p className="campaign-reward-claimed" role="status">已达成的星级奖励已领取。</p> : null;
  return <div className="campaign-reward-actions">
    <ul aria-label="可领取的战役奖励">{pending.map(reward =>
      <li key={reward.stars}><span>{reward.title}</span><strong>{campaignRewardText(reward)}</strong></li>)}</ul>
    <button type="button" className="primary" disabled={busy} onClick={onClaim}>领取战役奖励</button>
  </div>;
}

export function goalText(goal: Goal) {
  if (typeof goal === 'string') return campaignText(goal);
  if (!goal) return '原页未明确该档，待复核。';
  if (!('all_of' in goal)) {
    if (goal.type === 'damage_point_ratio' && goal.ratio !== undefined) return `损伤点比达到 ${goal.ratio}:1`;
    if (goal.type === 'damage_point_ratio_strictly_above' && goal.ratio !== undefined) return `损伤点比高于 ${goal.ratio}:1`;
    return '原页目标判定待核对。';
  }
  return goal.all_of.map((rule) => {
    const { count, pct, damage_pct, damage_pct_gte, fraction, distance_nmi, duration_seconds, tonnage_gt } = rule;
    switch (rule.type) {
      case 'opposing_ships_sunk_at_least':
      case 'opposing_destroyers_sunk_at_least': return `击沉至少 ${count} 艘敌驱逐舰`;
      case 'all_own_ships_damage_at_most_pct': return `每艘己方驱逐舰损伤不超过 ${pct}%`;
      case 'all_own_ships_escape': return '所有己舰逃脱';
      case 'all_own_ships_damage_strictly_below_pct': return `每艘己舰损伤低于 ${pct}%`;
      case 'group_escapes': return '运输驱逐舰组逃脱';
      case 'group_undamaged': return '运输驱逐舰组无损';
      case 'opposing_daihatsus_sunk_at_least': return `击沉至少 ${count} 艘敌大发驳船`;
      case 'opposing_destroyers_damaged_at_least': return `至少 ${count} 艘敌驱逐舰损伤达到 ${damage_pct}%`;
      case 'no_own_destroyers_lost': return '己方驱逐舰无损失';
      case 'barges_reach_horaniu': return `至少 ${(fraction ?? 0) * 100}% 的驳船抵达霍腊纽`;
      case 'opposing_cruisers_sunk_at_least': return `击沉至少 ${count} 艘敌巡洋舰`;
      case 'supply_destroyers_within_range_continuously': return `至少 ${count} 艘补给驱逐舰在维拉 ${distance_nmi} 海里以内连续停留 ${(duration_seconds ?? 0) / 60} 分钟`;
      case 'transport_group_ships_sunk_at_least': return `击沉至少 ${count} 艘超过 ${tonnage_gt} 吨的运输队舰艇`;
      case 'prevent_transport_group_arrival': return '阻止运输队抵达马尔夸纳湾';
      case 'axis_ships_damaged_at_least': return `至少 ${count} 艘超过 ${tonnage_gt} 吨的日舰损伤达到 ${damage_pct_gte}%`;
      case 'allied_destroyers_sunk_at_least': return `击沉至少 ${count} 艘盟军驱逐舰`;
      case 'transport_groups_arrive_undamaged': return '运输队无损抵达马尔夸纳湾';
      case 'allied_destroyers_damaged_at_least': return `至少 ${count} 艘盟军驱逐舰损伤达到 ${damage_pct_gte}%`;
      default: return '一项条件待整理';
    }
  }).join('；');
}

function forceNames(force: unknown, side: Side): string[] {
  if (typeof force === 'string') return [campaignShipName(force, side)];
  if (Array.isArray(force)) return force.flatMap(item => forceNames(item, side));
  if (typeof force !== 'object' || force === null) return [];
  const row = force as Record<string, unknown>;
  const name = row.name ?? row.ship;
  if (typeof name === 'string') return [campaignShipName(name, side)];
  if (typeof row.class === 'string' && typeof row.count === 'number') return [`${campaignShipName(row.class, side)} × ${row.count}`];
  return Object.entries(row).filter(([key, value]) =>
    Array.isArray(value) || (typeof value === 'object' && value !== null && key !== 'deployment'),
  ).flatMap(([, value]) => forceNames(value, side));
}

function forceRows(force: unknown, side: Side, label?: string): { label?: string; ships: string[] }[] {
  if (Array.isArray(force) && force.some(item => item && typeof item.unit === 'string')) {
    return force.flatMap(item => forceRows(item, side, label));
  }
  if (force && typeof force === 'object' && !Array.isArray(force)) {
    const row = force as Record<string, unknown>;
    if (typeof row.unit === 'string') label = campaignText(row.unit);
    const subgroups = Object.entries(row).flatMap(([key, value]) => {
      const subgroup = campaignForceGroup(key);
      if (!subgroup) return [];
      const subgroupLabel = label && key !== 'column' ? `${label} · ${subgroup}` : label ?? subgroup;
      return forceRows(value, side, subgroupLabel);
    });
    if (subgroups.length) return subgroups;
  }
  const ships = forceNames(force, side);
  return ships.length ? [{ label, ships }] : [];
}

function LegacySource({ id, side, data, playable }: { id: string; side: Side; data: LegacyDeployment; playable: boolean }) {
  const [showFormation, setShowFormation] = useState(false);
  const positions = showFormation ? new Map(data.post_default_formation_setup?.ships.map(ship => [ship.ibs_ship_id, ship])) : undefined;
  const placement = positions ? data.ships.map(ship => ({ ...ship, ...positions.get(ship.ibs_ship_id) })) : data.ships;
  const formations = new Map(data.formations.map(formation => [formation.id, campaignLegacyFormation(formation.id, formation.note)]));
  const width = 640;
  const height = 340;
  const scale = Math.min((width - 28) / data.map.width_m, (height - 28) / data.map.height_m);
  const offsetX = (width - data.map.width_m * scale) / 2;
  const offsetY = (height - data.map.height_m * scale) / 2;
  return <div className="archive-source" data-legacy-stage={id}>
    <p><strong>原剧本开局阵位</strong> · {data.source.baseline} · {data.ships.length} 艘
      {data.start.legacy_turn_limit !== null && ` · 原作 ${data.start.legacy_turn_limit} 回合`}</p>
    {data.post_default_formation_setup && <label className="archive-placement-toggle">
      <input type="checkbox" checked={showFormation} onChange={event => setShowFormation(event.target.checked)} />
      查看旧作默认整列后的阵位
    </label>}
    <svg className="archive-deployment" viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`${data.title}原剧本阵位，北向上`}>
      <rect x={offsetX} y={offsetY} width={data.map.width_m * scale} height={data.map.height_m * scale} />
      <text x={width - 29} y={25}>北 ↑</text>
      {placement.map(ship => <g key={ship.ibs_ship_id} className={ship.side}
        transform={`translate(${offsetX + ship.x_m * scale} ${height - offsetY - ship.y_m * scale}) rotate(${ship.heading_deg})`}>
        <title>{ship.name} · {ship.initial_hex} · {ship.heading_deg}°</title>
        <path d="M0,-6 L3,4 L0,2 L-3,4 Z" />
      </g>)}
    </svg>
    <p className="archive-deployment-legend"><span>同盟</span><span>轴心</span>原有格位已换算成连续坐标。</p>
    <div className="archive-sides">{([side, side === 'allies' ? 'axis' : 'allies'] as const).map(faction => {
      const ships = placement.filter(ship => ship.side === faction);
      return <section key={faction}><details><summary>{sideName[faction]}部署 · {ships.length} 艘</summary>
        <ul>{ships.map(ship => <li key={ship.ibs_ship_id}>{ship.name} · {ship.initial_hex} · {ship.heading_deg}°
          {ship.formation_id && ` · ${formations.get(ship.formation_id) ?? '原编队'}`}</li>)}</ul>
      </details></section>;
    })}</div>
    <div><h4>原剧本任务</h4><ul>{data.objectives.intent.map(text => <li key={text}>{campaignText(text)}</li>)}</ul></div>
    <div><h4>{playable ? '原始档案的核验记录' : '出航前待验证'}</h4>
      {playable ? <p>当前可出航的是以这份部署为底稿、用 CAS 舰卡裁决的 RTS 版本。</p>
        : <ul>{data.gates.map(text => <li key={text}>{campaignText(text)}</li>)}</ul>}
      {data.conflicts.length > 0 && <p>{data.conflicts.length} 处原部署和编队设置存在差异，已保留原阵位供核对。</p>}</div>
  </div>;
}

function StageSource({ id, side, playable, historicalReady }: { id: string; side: Side; playable: boolean; historicalReady?: boolean }) {
  const [detail, setDetail] = useState<RecordDetail>();
  const [failed, setFailed] = useState(false);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    let active = true;
    void ask<RecordDetail>({ op: 'campaign_detail', id }).then((value) => {
      if (active) setDetail(value);
    }, () => { if (active) setFailed(true); });
    return () => { active = false; };
  }, [id, attempt]);
  if (failed) return <button type="button" onClick={() => { setFailed(false); setAttempt(n => n + 1); }}>重读想定记录</button>;
  if (!detail) return <p role="status">正在载入想定记录…</p>;
  const { record, readiness, legacy } = detail;
  if (legacy) return <LegacySource id={id} side={side} data={legacy} playable={playable} />;
  if (!record) return null;
  const weather = record.environment;
  return <div className="archive-source" data-source-stage={id}>
    {playable && !historicalReady && <p className="archive-variant-note">下列为 CAS 原页记录。出航后的任务栏会列出 RTS 改编采用的判定。</p>}
    <p><strong>CAS 开局</strong> · {record.start.date_local} {record.start.time_local} · {record.start.location}
      {weather?.light === 'night' && ' · 夜间'}
      {weather?.visibility_pct !== undefined && ` · 能见度 ${weather.visibility_pct}%`}
      {weather?.sea_state !== undefined && ` · 海况 ${weather.sea_state}`}</p>
    <div className="archive-sides">
      {([side, side === 'allies' ? 'axis' : 'allies'] as const).map((faction) => {
        const fleets = record.groups?.filter(group => group.side === faction);
        const forces = forceRows(record.forces?.[faction], faction);
        const goals = record.objectives[faction];
        return <section key={faction}><h4>{sideName[faction]}编制与目标</h4>
          {fleets?.map(group => <p key={group.id}>{campaignText(group.unit)} · {group.course_deg}° / {group.speed_knots} 节<br />{
            group.members_in_order.map(id => campaignShipName(record.ships?.find(ship => ship.id === id)?.name ?? id, faction)).join('、')
          }</p>)}
          {forces.map(({ label, ships }, i) => <p key={i}>{label && <><strong>{label}</strong><br /></>}{ships.join('、')}</p>)}
          <dl><dt>命令</dt><dd>{campaignText(goals.orders)}</dd><dt>决定胜利</dt><dd>{goalText(goals.decisive)}</dd><dt>战术胜利</dt><dd>{goalText(goals.tactical)}</dd></dl>
        </section>;
      })}
    </div>
    {record.special_rules?.length ? <div><h4>想定特例</h4><ul>{record.special_rules.map((rule, i) =>
      <li key={i}>{campaignText(typeof rule === 'string' ? rule : rule.rule)}</li>)}</ul></div> : null}
    {!historicalReady && <div><h4>{playable ? '原书版本仍待核验' : '尚待验证'}</h4>
      {readiness && <p>已录入 {readiness.periodProfiles} 类时期配置，关联 {readiness.datedShips} 艘舰；仍有 {readiness.unresolvedPeriodData.length} 项原表或装载问题待核对。</p>}
      <ul>{record.blockers.map((blocker, i) => <li key={i}>{campaignText(typeof blocker === 'string' ? blocker : blocker.detail)}</li>)}</ul>
    </div>}
  </div>;
}

export function CampaignArchive({ onNight, onCampaign, progress, onClaim, busy, online = false, onReturn, onStory, onReview }: {
  onNight: () => void; onCampaign?: (launch: CampaignLaunch) => void; progress?: CampaignProgress;
  onClaim: (stageId: string) => void; busy: boolean; online?: boolean;
  onReturn?: () => void; onStory?: () => void; onReview?: () => void;
}) {
  const [archive, setArchive] = useState<Archive>();
  const [error, setError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [side, setSide] = useState<Side>('allies');
  const [difficulty, setDifficulty] = useState<CampaignDifficulty>('story');
  const [selectedId, setSelectedId] = useState<string>();
  const [brief, setBrief] = useState<{ entry: Entry; stageId: string }>();
  const [fleet, setFleet] = useState<FleetPick>();
  const [picks, setPicks] = useState<string[]>([]);
  const [fleetError, setFleetError] = useState('');
  const [mapSelection, setMapSelection] = useState<CampaignMapSelection>({ region: 'overview' });
  useEffect(() => {
    let active = true;
    void ask<Archive>({ op: 'campaign' }).then((value) => {
      if (active) setArchive(value);
    }, () => { if (active) setError(true); });
    return () => { active = false; };
  }, [attempt]);
  useEffect(() => {
    if (!brief || difficulty !== 'story' || online) { setFleet(undefined); setPicks([]); setFleetError(''); return; }
    let active = true;
    setFleet(undefined); setFleetError('');
    void ask<FleetPick>({ op: 'campaign_fleet', id: brief.stageId, difficulty }).then(value => {
      if (!active) return;
      setFleet(value); setPicks(value.historical.map(slot => slot.class));
    }, (failure) => { if (active) setFleetError(failure instanceof Error ? failure.message : String(failure)); });
    return () => { active = false; };
  }, [brief?.stageId, difficulty, online]);
  const pointOf = (id: string) => fleet?.options.find(option => option.id === id)?.points
    ?? fleet?.options.find(option => option.class === id)?.points
    ?? fleet?.historical.find(slot => slot.class === id)?.points ?? 0;
  const fleetTotal = picks.reduce((sum, id) => sum + pointOf(id), 0);
  const fleetReady = difficulty !== 'story' || online || (!!fleet &&
    picks.length === fleet.historical.length && fleetTotal <= fleet.budget);
  const stagePrefix = side === 'allies' ? 'CAMP-ALLIES-' : 'CAMP-AXIS-';
  const canLaunch = (entry: Entry) => entry.playable && !(online && entry.runtime?.localOnly);
  const matchingEntries = archive?.scenarios ?? [];
  const mapStageIds = new Set(campaignMapStageIds(matchingEntries, side, mapSelection));
  const visible = matchingEntries.flatMap(entry => {
    const stageId = entry.stage_ids.find(id => id.startsWith(stagePrefix) && mapStageIds.has(id));
    return stageId ? [{ entry, stageId }] : [];
  });
  const allStages = matchingEntries.flatMap(entry => {
    const stageId = entry.stage_ids.find(id => id.startsWith(stagePrefix));
    return stageId ? [{ entry, stageId }] : [];
  });
  const selected = visible.find(({ entry }) => entry.ibs_id === selectedId) ?? visible[0];
  const earned = allStages.reduce((sum, { stageId }) => sum + (campaignBest(progress, stageId) ?? 0), 0);
  const selectedPlace = selected && campaignPlace(selected.entry.ibs_id);
  const review = onReview ?? onNight;

  function panelVisible(id: string, ids: Set<string>) {
    return matchingEntries.some(entry => entry.ibs_id === id &&
      entry.stage_ids.some(stageId => stageId.startsWith(stagePrefix) && ids.has(stageId)));
  }
  function chooseMap(selection: CampaignMapSelection) {
    setMapSelection(selection);
    const nextIds = new Set(campaignMapStageIds(matchingEntries, side, selection));
    if (selectedId && !panelVisible(selectedId, nextIds)) setSelectedId(undefined);
  }
  function chooseSide(next: Side) {
    setSide(next);
    setSelectedId(undefined);
  }
  const pending = selected ? pendingCampaignRewards(progress, selected.stageId) : [];
  const best = selected ? campaignBest(progress, selected.stageId) : undefined;
  const statusFor = (entry: Entry, stageId: string) => {
    if (pendingCampaignRewards(progress, stageId).length) return '奖励待领';
    if (canLaunch(entry)) return campaignBest(progress, stageId) ? '已完成' : '可出航';
    if (entry.playable) return entry.runtime?.localOnly ? '仅离线开放' : '待解锁';
    return entry.runtime || entry.cas ? '待规则核验' : '待解锁';
  };

  return <main className="campaign-archive war-atlas" data-faction={side}>
    <header className="war-header">
      {onReturn && <button type="button" onClick={onReturn}>返回港口</button>}
      <h1>战役航图</h1>
      <div className="war-side-tabs" aria-label="战役阵营">
        {sides.map(value => <button key={value} type="button" aria-pressed={side === value} onClick={() => chooseSide(value)}>{sideName[value]}方战线</button>)}
      </div>
      <span className="war-star-total" aria-label={`本阵营 ${earned} / ${allStages.length * 3} 星`}>★ {earned} / {allStages.length * 3}</span>
    </header>
    {error && <div className="war-alert" role="status"><span>档案未能载入。</span>
      <button type="button" onClick={() => { setError(false); setAttempt(n => n + 1); }}>重新载入</button></div>}
    {!archive && !error && <p className="war-loading" role="status">正在查阅档案…</p>}
    {archive && <div className="war-body">
      <section className="war-map" aria-label="海战地理航图">
        <CampaignMap entries={matchingEntries} side={side} selection={mapSelection} onSelectionChange={chooseMap}
          activeScenarioId={selected?.entry.ibs_id} />
        <div className="war-utility">
          <button type="button" onClick={onStory} disabled={!onStory} aria-label="剧情模式 · 序章 未明的海">剧情模式</button>
          <button type="button" onClick={review} disabled={!review}>操作复习</button>
          <span>地图按地理分区，列表按出航顺序。</span>
        </div>
      </section>
      <section className="war-archive" aria-label="作战关卡列表">
        <header className="war-archive-header">
          <div><h2>{mapSelection.place ? places[mapSelection.place].label : mapSelection.region === 'overview' ? '全战线关卡' : chartLabel(mapSelection.region)}</h2>
            <small>{visible.length} 个关卡</small></div>
          <span>{sideName[side]}方 · {visible.filter(({ entry }) => canLaunch(entry)).length} 关可出航</span>
        </header>
        <ol className="war-archive-entries">
          {visible.map(({ entry, stageId }) => {
            const stars = campaignBest(progress, stageId) ?? 0;
            const status = statusFor(entry, stageId);
            return <li key={entry.ibs_id}>
              <button type="button" className={`war-entry ${entry.classification}`} aria-pressed={selected?.entry.ibs_id === entry.ibs_id}
                aria-label={`${entry.ibs_title}，${matchNames[entry.classification]}，${status}，${stars} 星`}
                onClick={() => setSelectedId(entry.ibs_id)}>
                <span className="war-entry-number">{stageId.slice(-2)}</span>
                <span className="war-entry-copy"><strong>{entry.ibs_title}</strong>
                  <small>{entry.ibs_date || '日期待定'} · {matchNames[entry.classification]}</small></span>
                <span className={`war-entry-status${canLaunch(entry) ? ' ready' : ''}`}>
                  {stars > 0 ? '★'.repeat(stars) : status}</span>
              </button>
            </li>;
          })}
          {!visible.length && <li className="war-empty">此战区没有当前阵营的关卡。请选择其他战区。</li>}
        </ol>
        <footer className="war-archive-footer">
          {selected ? <>
            <p>{selectedPlace ? places[selectedPlace].label : '交战海域'} · {selected.entry.ibs_date || '日期待定'}
              {best ? <> · 最高评级 <CampaignStarRating stars={best} /></> : null}</p>
            <div className="war-launch-line">
              <div className="war-difficulty-tabs" aria-label="战役难度">
                {(Object.keys(campaignDifficulties) as CampaignDifficulty[]).map(option =>
                  <button key={option} type="button" aria-pressed={difficulty === option} onClick={() => setDifficulty(option)}>
                    {campaignDifficulties[option]}</button>)}
              </div>
              <button type="button" className="primary war-brief-button" disabled={busy} onClick={() => setBrief(selected)}>作战简报</button>
            </div>
            <small className="war-difficulty-note">{campaignDifficulties[difficulty]}：{difficultyNotes[difficulty]}{pending.length ? ' · 有未领取奖励' : ''}</small>
          </> : <p>选择一处交战海域查看关卡。</p>}
        </footer>
      </section>
    </div>}
    {brief && <div className="war-brief-layer" role="presentation" onClick={event => { if (event.target === event.currentTarget) setBrief(undefined); }}>
      <section className="war-brief" role="dialog" aria-modal="true" aria-label="作战简报">
        <header>
          <div><span>{matchNames[brief.entry.classification]} · {sideName[side]}方战线</span>
            <h2>{brief.entry.runtime?.label ?? brief.entry.ibs_title}</h2>
            <p>{brief.entry.ibs_date || '日期待定'} · {campaignDifficulties[difficulty]}难度</p></div>
          <button type="button" onClick={() => setBrief(undefined)}>关闭</button>
        </header>
        <div className="war-brief-body">
          {brief.entry.cas && <p className="war-brief-source"><strong>{campaignScenarioTitle(brief.entry.cas.scenario_id, brief.entry.ibs_title)}</strong><br />
            {sources[brief.entry.cas.source.document] ?? brief.entry.cas.source.document}
            {brief.entry.cas.source.pdf_pages.length > 0 && ' · PDF 第 ' + brief.entry.cas.source.pdf_pages.join('、') + ' 页'}
            {brief.entry.cas.source.printed_pages.length > 0 && '（书页 ' + brief.entry.cas.source.printed_pages.join('、') + '）'}</p>}
          {brief.entry.playable && <div className="archive-sortie-brief">
            <div className="archive-sortie-row"><div><strong>本方作战目标</strong>
              <span>{campaignDifficulties[difficulty]}难度 · 按历史编制借舰，不消耗个人舰库</span></div>
              <button type="button" className="primary"
                disabled={busy || !onCampaign || !canLaunch(brief.entry) || !fleetReady}
                onClick={() => onCampaign?.({ stageId: brief.stageId, difficulty,
                  ...(difficulty === 'story' && !online && picks.length ? { fleet: picks } : {}) })}>出航作战</button></div>
            {!online && <CampaignRewardActions stageId={brief.stageId} progress={progress} busy={busy} onClaim={() => onClaim(brief.stageId)} />}
          </div>}
          {brief.entry.playable && difficulty === 'story' && !online && <section className="war-fleet-picker" aria-label="基础难度分数编队">
            <header><div><span>基础难度</span><strong>分数编队</strong></div>
              <b data-over={!!fleet && fleetTotal > fleet.budget}>{fleet ? `${fleetTotal} / ${fleet.budget} 分` : '载入分数…'}</b></header>
            {fleetError && <p className="war-fleet-error" role="alert">{fleetError}</p>}
            {!fleet && !fleetError && <p>正在读取历史兵力与已登记舰卡…</p>}
            {fleet && <>
              <p>历史兵力共 {fleet.historical.length} 个舰位。每个舰位可换成同阵营已登记舰卡（历史舰为临时体验）；高难度使用原历史兵力。</p>
              <ol>
                {fleet.historical.map((slot, index) => {
                  const value = picks[index] ?? slot.class;
                  const choices = [...fleet.options];
                  if (!choices.some(option => option.id === slot.class || option.class === slot.class)) choices.unshift({ ...slot, id: slot.class });
                  return <li key={slot.slot}>
                    <span>第 {index + 1} 舰位 · {slot.name}</span>
                    <select value={value} aria-label={`第 ${index + 1} 舰位`} onChange={event => setPicks(current => {
                      const next = [...current]; next[index] = event.target.value; return next;
                    })}>
                      {choices.map(option => <option key={option.id} value={option.id}>
                        {option.name} · {option.kind} · {option.points} 分
                      </option>)}
                    </select>
                    <b>{pointOf(value)}</b>
                  </li>;
                })}
              </ol>
              <div className="war-fleet-actions">
                <button type="button" onClick={() => setPicks(fleet.historical.map(slot => slot.class))}>按历史编制</button>
                <span>{fleetTotal > fleet.budget ? `超出 ${fleetTotal - fleet.budget} 分` : '点价在历史兵力预算内'}</span>
              </div>
            </>}
          </section>}
          <StageSource key={brief.stageId} id={brief.stageId} side={side} playable={brief.entry.playable} historicalReady={brief.entry.runtime?.historicalReady} />
          <p className="war-brief-note">{campaignText(brief.entry.note)}</p>
          {!brief.entry.playable && <p className="war-brief-note">本关保持资料层，未通过出航核验前不能作战。</p>}
        </div>
      </section>
    </div>}
  </main>;
}

function chartLabel(region: CampaignMapSelection['region']) {
  return region === 'overview' ? '全战线关卡' : charts[region].label;
}
