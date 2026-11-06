import { useEffect, useState } from 'react';
import { ask } from './engine';
import type { Side } from './engine';
import './campaign-archive.css';

type Match = 'exact_historical_counterpart' | 'related_alternate' | 'unverified' | 'ibs_original_or_absent';
type Reference = { document: string; pdf_pages: number[]; printed_pages: number[] };
type Entry = {
  ibs_id: string; ibs_title: string; ibs_date: string; ibs_kind: string; stage_ids: string[];
  classification: Match; cas: null | { title: string; source: Reference; verification: string; import: string | null };
  playable: boolean; note: string;
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
  ships: LegacyShip[]; objectives: { intent: string[] }; gates: string[];
  post_default_formation_setup?: { ships: Pick<LegacyShip, 'ibs_ship_id' | 'initial_hex' | 'x_m' | 'y_m' | 'heading_deg' | 'speed_knots'>[] } | null;
  conflicts: unknown[]; source: { baseline: string };
};

const matchNames: Record<Match, string> = {
  exact_historical_counterpart: '同一历史战斗', related_alternate: '相关改编',
  unverified: '尚待核对', ibs_original_or_absent: '旧作想定或未找到',
};
const sources: Record<string, string> = { rising_sun_5e: 'Rising Sun（第五版）', steel_typhoon_5e: 'Steel Typhoon（第五版）' };
const sides = ['allies', 'axis'] as const;
const sideName = { allies: '同盟', axis: '轴心' };
// Keep the original CampaignScreen side/node selection and its three difficulty IDs.
const difficulties = { story: '故事', standard: '标准', challenge: '挑战' };
const difficultyNotes = { story: '完整提示，熟悉战场。', standard: '常规提示，按公开目标争取星级。', challenge: '更强的战术与公开附加目标。' };

function goalText(goal: Goal) {
  if (typeof goal === 'string') return goal;
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

function forceNames(force: unknown): string[] {
  if (typeof force === 'string') return [force];
  if (Array.isArray(force)) return force.flatMap(forceNames);
  if (typeof force !== 'object' || force === null) return [];
  const row = force as Record<string, unknown>;
  const name = row.name ?? row.ship;
  if (typeof name === 'string') return [name];
  if (typeof row.class === 'string' && typeof row.count === 'number') return [`${row.class} × ${row.count}`];
  return Object.entries(row).filter(([key, value]) =>
    Array.isArray(value) || (typeof value === 'object' && value !== null && key !== 'deployment'),
  ).flatMap(([, value]) => forceNames(value));
}

function LegacySource({ id, side, data }: { id: string; side: Side; data: LegacyDeployment }) {
  const [showFormation, setShowFormation] = useState(false);
  const positions = showFormation ? new Map(data.post_default_formation_setup?.ships.map(ship => [ship.ibs_ship_id, ship])) : undefined;
  const placement = positions ? data.ships.map(ship => ({ ...ship, ...positions.get(ship.ibs_ship_id) })) : data.ships;
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
          {ship.formation_id && ` · ${ship.formation_id}`}</li>)}</ul>
      </details></section>;
    })}</div>
    <div><h4>原剧本任务</h4><ul>{data.objectives.intent.map(text => <li key={text}>{text}</li>)}</ul></div>
    <div><h4>出航前待验证</h4><ul>{data.gates.map(text => <li key={text}>{text}</li>)}</ul>
      {data.conflicts.length > 0 && <p>{data.conflicts.length} 处原部署和编队设置存在差异，已保留原阵位供核对。</p>}</div>
  </div>;
}

function StageSource({ id, side }: { id: string; side: Side }) {
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
  if (legacy) return <LegacySource id={id} side={side} data={legacy} />;
  if (!record) return null;
  const weather = record.environment;
  return <div className="archive-source" data-source-stage={id}>
    <p><strong>CAS 开局</strong> · {record.start.date_local} {record.start.time_local} · {record.start.location}
      {weather?.light === 'night' && ' · 夜间'}
      {weather?.visibility_pct !== undefined && ` · 能见度 ${weather.visibility_pct}%`}
      {weather?.sea_state !== undefined && ` · 海况 ${weather.sea_state}`}</p>
    <div className="archive-sides">
      {([side, side === 'allies' ? 'axis' : 'allies'] as const).map((faction) => {
        const fleets = record.groups?.filter(group => group.side === faction);
        const ships = forceNames(record.forces?.[faction]);
        const goals = record.objectives[faction];
        return <section key={faction}><h4>{sideName[faction]}编制与目标</h4>
          {fleets?.map(group => <p key={group.id}>{group.unit} · {group.course_deg}° / {group.speed_knots} 节<br />{
            group.members_in_order.map(id => record.ships?.find(ship => ship.id === id)?.name ?? id).join('、')
          }</p>)}
          {ships.length > 0 && <p>{ships.join('、')}</p>}
          <dl><dt>命令</dt><dd>{goals.orders}</dd><dt>决定胜利</dt><dd>{goalText(goals.decisive)}</dd><dt>战术胜利</dt><dd>{goalText(goals.tactical)}</dd></dl>
        </section>;
      })}
    </div>
    {record.special_rules?.length ? <div><h4>想定特例</h4><ul>{record.special_rules.map((rule, i) =>
      <li key={i}>{typeof rule === 'string' ? rule : rule.rule}</li>)}</ul></div> : null}
    <div><h4>尚待验证</h4>
      {readiness && <p>已录入 {readiness.periodProfiles} 类时期配置，关联 {readiness.datedShips} 艘舰；仍有 {readiness.unresolvedPeriodData.length} 项原表或装载问题待核对。</p>}
      <ul>{record.blockers.map((blocker, i) => <li key={i}>{typeof blocker === 'string' ? blocker : blocker.detail}</li>)}</ul>
    </div>
  </div>;
}

export function CampaignArchive({ onNight, busy }: { onNight: () => void; busy: boolean }) {
  const [archive, setArchive] = useState<Archive>();
  const [error, setError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [filter, setFilter] = useState<'all' | Match>('all');
  const [side, setSide] = useState<Side>('allies');
  const [difficulty, setDifficulty] = useState<keyof typeof difficulties>('story');
  const [open, setOpen] = useState<string>();
  useEffect(() => {
    let active = true;
    void ask<Archive>({ op: 'campaign' }).then((value) => {
      if (active) setArchive(value);
    }, () => { if (active) setError(true); });
    return () => { active = false; };
  }, [attempt]);
  const exactCount = archive?.scenarios.filter((entry) => entry.classification === 'exact_historical_counterpart').length ?? 0;
  const visible = archive?.scenarios.filter((entry) => filter === 'all' || entry.classification === filter) ?? [];

  return <section className="harbor-section campaign-archive" aria-label="CAS 战役档案">
    <div className="night-card">
      <div><span>独立练习 · 虚构夜战</span><h3>夜航接敌</h3><p>5 对 5 目视搜索演习。靠近敌舰才能建立接触。</p></div>
      <button type="button" className="primary" onClick={onNight} disabled={busy}>开始夜航演习</button>
    </div>
    <div className="harbor-title"><h3>战役航图</h3>{archive && <span>双线 {archive.scenarios.length * 2} 关 · {exactCount} 份原书想定</span>}</div>
    <p className="harbor-fine">选择战线与难度，展开关卡查看 CAS 原书或旧剧本部署。出航须先核对舰卡、胜利条件和想定规则。</p>
    {error && <div className="harbor-action" role="status"><span>档案未能载入。</span><button type="button" onClick={() => { setError(false); setAttempt((n) => n + 1); }}>重新载入</button></div>}
    {!archive && !error && <p className="harbor-fine" role="status">正在查阅档案…</p>}
    {archive && <>
      <div className="archive-toolbar campaign-controls">
        <div className="war-side-tabs" aria-label="战役阵营">
          {sides.map(value => <button key={value} type="button" aria-pressed={side === value} onClick={() => setSide(value)}>{sideName[value]}战线</button>)}
        </div>
        <label>难度 <select value={difficulty} onChange={event => setDifficulty(event.target.value as typeof difficulty)}>
          {Object.entries(difficulties).map(([id, name]) => <option key={id} value={id}>{name}</option>)}
        </select></label>
        <label>档案范围 <select value={filter} onChange={(event) => setFilter(event.target.value as typeof filter)}>
          <option value="all">全部</option>
          {Object.entries(matchNames).map(([id, name]) => <option key={id} value={id}>{name}</option>)}
        </select></label>
      </div>
      <p className="archive-difficulty">{difficulties[difficulty]}：{difficultyNotes[difficulty]}</p>
      <ul className="archive-list">
        {visible.map((entry) => {
          const stageId = entry.stage_ids.find(id => id.startsWith(side === 'allies' ? 'CAMP-ALLIES-' : 'CAMP-AXIS-'))!;
          return <li key={entry.ibs_id} data-stage-id={stageId}>
          <details open={open === entry.ibs_id} onToggle={e => {
            if (e.target !== e.currentTarget) return;
            const isOpen = e.currentTarget.open;
            if (isOpen) setOpen(entry.ibs_id);
            else setOpen(current => current === entry.ibs_id ? undefined : current);
          }}>
            <summary>
              <span className="archive-name"><time>{stageId.slice(-2)} · {entry.ibs_date || '日期待定'}</time><strong>{entry.ibs_title}</strong></span>
              <span className={'archive-tag ' + entry.classification}>{matchNames[entry.classification]}</span>
              <span className="archive-lock">{entry.playable ? '已验证关卡' : '未开放'}</span>
            </summary>
            <div className="archive-detail">
              {entry.cas && <p><strong>{entry.cas.title}</strong><br />{sources[entry.cas.source.document] ?? entry.cas.source.document}
                {entry.cas.source.pdf_pages.length > 0 && ' · PDF 第 ' + entry.cas.source.pdf_pages.join('、') + ' 页'}
                {entry.cas.source.printed_pages.length > 0 && '（书页 ' + entry.cas.source.printed_pages.join('、') + '）'}</p>}
              <p>{entry.note}</p>
              <small>关卡编号：{stageId}</small>
              {open === entry.ibs_id && <StageSource key={stageId} id={stageId} side={side} />}
            </div>
          </details>
        </li>;
        })}
      </ul>
    </>}
  </section>;
}
