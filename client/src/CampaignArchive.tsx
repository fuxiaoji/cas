import { useEffect, useState } from 'react';
import { ask } from './engine';
import type { Side } from './engine';
import { CampaignMap, campaignMapStageIds } from './campaign-map';
import type { CampaignMapSelection } from './campaign-map';
import { campaignForceGroup, campaignLegacyFormation, campaignScenarioTitle, campaignShipName, campaignText } from './campaign-labels';
import { campaignBest, campaignDifficulties, campaignRewards, campaignRewardText, campaignStars, pendingCampaignRewards } from './campaign-progress';
import type { CampaignDifficulty, CampaignLaunch, CampaignMission, CampaignOutcome, CampaignProgress, CampaignStars } from './campaign-progress';
import './campaign-archive.css';

type Match = 'exact_historical_counterpart' | 'related_alternate' | 'unverified' | 'ibs_original_or_absent';
type Reference = { document: string; pdf_pages: number[]; printed_pages: number[] };
type Entry = {
  ibs_id: string; ibs_title: string; ibs_date: string; ibs_kind: string; stage_ids: string[];
  classification: Match; cas: null | { scenario_id: string; title: string; source: Reference; verification: string; import: string | null };
  playable: boolean; note: string; runtime?: { historicalReady: boolean; label: string; localOnly?: boolean };
};
interface Archive { schema_version: number; content_version: string; scenarios: Entry[] }
type Condition = { type: string; count?: number; kind?: string; pct?: number; damage_pct?: number; damage_pct_gte?: number;
  fraction?: number; distance_nmi?: number; duration_seconds?: number; tonnage_gt?: number };
type Goal = string | { all_of: Condition[] } | { type: string; ratio?: number } | null;
type Objective = { orders: string; decisive: Goal; tactical: Goal };
interface RecordDetail {
  record: null | { start: { date_local: string; time_local: string; location: string }; environment?: {
    light?: string; visibility_pct?: number; sea_state?: number; wind_from_deg?: number; wind_speed_knots?: number | number[];
  }; forces?: Record<Side, unknown>; groups?: { id: string; side: Side; unit: string; members_in_order: string[]; course_deg: number; speed_knots: number }[];
  ships?: { id: string; name: string }[]; objectives: Record<Side, Objective>;
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

const matchNames: Record<Match, string> = {
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

function goalText(goal: Goal) {
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

export function CampaignArchive({ onNight, onCampaign, progress, onClaim, busy, online = false }: {
  onNight: () => void; onCampaign?: (launch: CampaignLaunch) => void; progress?: CampaignProgress;
  onClaim: (stageId: string) => void; busy: boolean; online?: boolean;
}) {
  const [archive, setArchive] = useState<Archive>();
  const [error, setError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [filter, setFilter] = useState<'all' | Match>('all');
  const [side, setSide] = useState<Side>('allies');
  const [difficulty, setDifficulty] = useState<CampaignDifficulty>('story');
  const [open, setOpen] = useState<string>();
  const [mapSelection, setMapSelection] = useState<CampaignMapSelection>({ region: 'overview' });
  useEffect(() => {
    let active = true;
    void ask<Archive>({ op: 'campaign' }).then((value) => {
      if (active) setArchive(value);
    }, () => { if (active) setError(true); });
    return () => { active = false; };
  }, [attempt]);
  const exactCount = archive?.scenarios.filter((entry) => entry.classification === 'exact_historical_counterpart').length ?? 0;
  const stagePrefix = side === 'allies' ? 'CAMP-ALLIES-' : 'CAMP-AXIS-';
  const canLaunch = (entry: Entry) => entry.playable && !(online && entry.runtime?.localOnly);
  const matchingEntries = archive?.scenarios.filter(entry => filter === 'all' || entry.classification === filter) ?? [];
  const mapStageIds = new Set(campaignMapStageIds(matchingEntries, side, mapSelection));
  const visible = matchingEntries.flatMap(entry => {
    const stageId = entry.stage_ids.find(id => id.startsWith(stagePrefix) && mapStageIds.has(id));
    return stageId ? [{ entry, stageId }] : [];
  });
  const playableCount = visible.filter(({ entry }) => canLaunch(entry)).length;
  const activeScenario = visible.some(({ entry }) => entry.ibs_id === open) ? open : undefined;

  function chooseMap(selection: CampaignMapSelection) {
    setMapSelection(selection);
    const nextIds = new Set(campaignMapStageIds(matchingEntries, side, selection));
    if (!visible.some(({ entry, stageId }) => entry.ibs_id === open && nextIds.has(stageId))) setOpen(undefined);
  }

  return <section className="harbor-section campaign-archive" aria-label="CAS 战役档案">
    <div className="harbor-title"><h3>战役航图</h3>{archive && <span>双线 {archive.scenarios.length * 2} 关 · {exactCount} 份原书想定</span>}</div>
    <p className="harbor-fine">选择战线和难度，点航图上的海域查看对应关卡。可出航的关卡提供历史编制借舰；其他关卡可查阅档案。</p>
    {error && <div className="harbor-action" role="status"><span>档案未能载入。</span><button type="button" onClick={() => { setError(false); setAttempt((n) => n + 1); }}>重新载入</button></div>}
    {!archive && !error && <p className="harbor-fine" role="status">正在查阅档案…</p>}
    {archive && <>
      <div className="archive-toolbar campaign-controls">
        <div className="war-side-tabs" aria-label="战役阵营">
          {sides.map(value => <button key={value} type="button" aria-pressed={side === value} onClick={() => setSide(value)}>{sideName[value]}战线</button>)}
        </div>
        <label>难度 <select value={difficulty} onChange={event => setDifficulty(event.target.value as typeof difficulty)}>
          {Object.entries(campaignDifficulties).map(([id, name]) => <option key={id} value={id}>{name}</option>)}
        </select></label>
        <label>档案范围 <select value={filter} onChange={event => { setFilter(event.target.value as typeof filter); setOpen(undefined); }}>
          <option value="all">全部</option>
          {Object.entries(matchNames).map(([id, name]) => <option key={id} value={id}>{name}</option>)}
        </select></label>
      </div>
      <CampaignMap entries={matchingEntries} side={side} selection={mapSelection} onSelectionChange={chooseMap} activeScenarioId={activeScenario} />
      <div className="archive-difficulty"><span>{campaignDifficulties[difficulty]}：{difficultyNotes[difficulty]}各档舰卡与规则一致。</span><span>{sideName[side]}战线 · {playableCount} 关可出航</span></div>
      {!visible.length && <p className="harbor-fine" role="status">该海域没有符合筛选的关卡。</p>}
      <ul className="archive-list">
        {visible.map(({ entry, stageId }) => {
          const best = campaignBest(progress, stageId, difficulty);
          const pending = pendingCampaignRewards(progress, stageId).length > 0;
          return <li key={entry.ibs_id} data-stage-id={stageId} data-playable={canLaunch(entry)}>
          <details open={open === entry.ibs_id} onToggle={e => {
            if (e.target !== e.currentTarget) return;
            const isOpen = e.currentTarget.open;
            if (isOpen) setOpen(entry.ibs_id);
            else setOpen(current => current === entry.ibs_id ? undefined : current);
          }}>
            <summary>
              <span className="archive-name"><time>{stageId.slice(-2)} · {entry.ibs_date || '日期待定'}</time><strong>{entry.ibs_title}</strong></span>
              <span className={'archive-tag ' + entry.classification}>{matchNames[entry.classification]}</span>
              <span className="archive-lock">{canLaunch(entry) ? pending ? '奖励待领' : '可出航' : entry.runtime?.localOnly ? '仅离线开放' : '未开放'}</span>
            </summary>
            <div className="archive-detail">
              {entry.playable && <div className="archive-sortie-brief">
                <div className="archive-sortie-row"><div><strong>{entry.runtime?.label ?? entry.ibs_title}</strong>
                  <span>{sideName[side]}战线 · {campaignDifficulties[difficulty]}难度</span>
                  <span>{best === undefined ? '尚无战果' : <>最高评级 <CampaignStarRating stars={best} /></>}</span></div>
                  <button type="button" className="primary" disabled={busy || !onCampaign || !canLaunch(entry)} onClick={() => onCampaign?.({ stageId, difficulty })}>出航作战</button>
                </div>
                <p>本关按历史编制借舰，不消耗个人舰库。</p>
                {!online && <CampaignRewardActions stageId={stageId} progress={progress} busy={busy} onClaim={() => onClaim(stageId)} />}
                {stageId === 'CAMP-AXIS-01' && <p>原首通舰高波待核准 CAS 舰卡后开放，补给可照常领取。</p>}
                {campaignRewards(stageId).length > 0 && <details className="campaign-reward-ledger"><summary>查看星级奖励</summary>
                  <ol>{campaignRewards(stageId).map(reward => <li key={reward.stars}><span>{reward.stars} 星 · {reward.title}</span>
                    <strong>{campaignRewardText(reward)}</strong><small>{(progress?.[stageId]?.claimed ?? 0) >= reward.stars ? '已领取' : '每条战线各领一次'}</small></li>)}</ol>
                </details>}
              </div>}
              {entry.cas && <p><strong data-source-title={entry.cas.title}>{campaignScenarioTitle(entry.cas.scenario_id, entry.ibs_title)}</strong><br />{sources[entry.cas.source.document] ?? entry.cas.source.document}
                {entry.cas.source.pdf_pages.length > 0 && ' · PDF 第 ' + entry.cas.source.pdf_pages.join('、') + ' 页'}
                {entry.cas.source.printed_pages.length > 0 && '（书页 ' + entry.cas.source.printed_pages.join('、') + '）'}</p>}
              <p>{campaignText(entry.note)}</p>
              <small>关卡编号：{stageId}</small>
              {open === entry.ibs_id && <StageSource key={stageId} id={stageId} side={side} playable={entry.playable} historicalReady={entry.runtime?.historicalReady} />}
            </div>
          </details>
        </li>;
        })}
      </ul>
    </>}
    <div className="night-card archive-practice">
      <div><span>独立练习 · 虚构夜战</span><h3>夜航接敌</h3><p>5 对 5 目视搜索演习。靠近敌舰才能建立接触。</p></div>
      <button type="button" className="primary" onClick={onNight} disabled={busy}>开始夜航演习</button>
    </div>
  </section>;
}
