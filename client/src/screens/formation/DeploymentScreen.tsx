import { useEffect, useMemo, useState } from 'react';
import { ask, profileNames, sideNames } from '../../engine';
import type { Profile, Side } from '../../engine';
import type { FleetPick } from '../../CampaignArchive';
import type { CampaignDifficulty, GroupPick } from '../../campaign-progress';
import { BudgetMeter, RuleCheck } from '../../widgets/formation';
import { ShipThumb } from '../../widgets/ship-thumb';
import { TaskForceBuilder } from './TaskForceBuilder';
import { appendPreset, readDraft, readPresets, writeDraft } from './draft';
import type { FleetPreset } from './draft';
import './deployment.css';

const kindNames: Record<string, string> = { DD: '驱逐舰', CL: '轻巡洋舰', CA: '重巡洋舰', BB: '战列舰' };
const difficultyNames: Record<CampaignDifficulty, string> = { story: '故事', standard: '标准', challenge: '挑战' };
const kinds = ['DD', 'CL', 'CA', 'BB'] as const;
type KindFilter = 'all' | typeof kinds[number];
type Sort = 'points' | 'kind' | 'name';

type Candidate = {
  key: string; pick: string; classId: string; name: string; kind: string; points: number; historical: boolean;
};

type Formation = { course?: number; speed?: number };

interface Props {
  stageId: string;
  difficulty: CampaignDifficulty;
  side: Side;
  stageTitle: string;
  formation?: Formation;
  profileId: string;
  profiles: Profile[];
  defaultProfile: Profile;
  busy?: boolean;
  error?: string;
  onBack: () => void;
  onLaunch: (launch: { fleet?: string[]; groups?: GroupPick[]; profile: Profile }) => void;
}

function errorText(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

export function DeploymentScreen({
  stageId, difficulty, side, stageTitle, formation, profileId, profiles, defaultProfile,
  busy, error: launchError, onBack, onLaunch,
}: Props) {
  const [fleet, setFleet] = useState<FleetPick>();
  const [loadError, setLoadError] = useState('');
  const [attempt, setAttempt] = useState(0);
  const [picks, setPicks] = useState<string[]>([]);
  const [profile, setProfile] = useState<Profile>(defaultProfile);
  const [slot, setSlot] = useState<number>();
  const [pendingKey, setPendingKey] = useState<string>();
  const [filter, setFilter] = useState<KindFilter>('all');
  const [search, setSearch] = useState('');
  const [sort, setSort] = useState<Sort>('points');
  const [presets, setPresets] = useState<FleetPreset[]>([]);
  const [notice, setNotice] = useState('');
  const [sheet, setSheet] = useState(false);
  const [mode, setMode] = useState<'history' | 'taskforce'>('history');

  useEffect(() => {
    let active = true;
    setFleet(undefined);
    setLoadError('');
    setNotice('');
    void ask<FleetPick>({ op: 'campaign_fleet', id: stageId, difficulty }).then((value) => {
      if (!active) return;
      const known = new Set([...value.historical.map((row) => row.class), ...value.options.map((row) => row.id)]);
      const saved = readDraft(profileId, stageId, difficulty);
      const usable = saved && saved.picks.length === value.historical.length && saved.picks.every((pick) => known.has(pick))
        ? saved.picks : value.historical.map((row) => row.class);
      setFleet(value);
      setPicks(usable);
      const unlocked = profiles.includes(defaultProfile) ? profiles : [defaultProfile, ...profiles];
      setProfile(saved && unlocked.includes(saved.profile) ? saved.profile : defaultProfile);
      setSlot(undefined);
      setPendingKey(undefined);
    }, (failure) => {
      if (active) setLoadError(errorText(failure));
    });
    return () => { active = false; };
  }, [stageId, difficulty, profileId, attempt, defaultProfile, profiles]);

  useEffect(() => {
    setPresets(readPresets(profileId));
  }, [profileId]);

  useEffect(() => {
    if (!fleet || picks.length !== fleet.historical.length) return;
    writeDraft(profileId, stageId, difficulty, { picks, profile, updatedAt: Date.now() });
  }, [fleet, picks, profile, profileId, stageId, difficulty]);

  useEffect(() => {
    const close = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      if (slot !== undefined) {
        event.preventDefault();
        setSlot(undefined);
        setPendingKey(undefined);
      } else if (sheet) {
        event.preventDefault();
        setSheet(false);
      }
    };
    window.addEventListener('keydown', close);
    return () => window.removeEventListener('keydown', close);
  }, [slot, sheet]);

  const historical = fleet?.historical ?? [];
  const options = fleet?.options ?? [];

  const resolved = useMemo(() => {
    const map = new Map<string, Candidate>();
    for (const row of historical) {
      if (!map.has(row.class)) {
        map.set(row.class, { key: 'hist:' + row.class, pick: row.class, classId: row.class, name: row.name, kind: row.kind, points: row.points, historical: true });
      }
    }
    for (const row of options) {
      map.set(row.id, { key: 'opt:' + row.id, pick: row.id, classId: row.class, name: row.name, kind: row.kind, points: row.points, historical: false });
    }
    return map;
  }, [fleet]);

  // The picker shows one historical hull per class (the named ship already on
  // the chart) plus every registered card the scenario data actually loads.
  const candidates = useMemo(() => {
    const rows: Candidate[] = [];
    const seen = new Set<string>();
    for (const row of historical) {
      if (seen.has(row.class)) continue;
      seen.add(row.class);
      rows.push({ key: 'hist:' + row.class, pick: row.class, classId: row.class, name: row.name, kind: row.kind, points: row.points, historical: true });
    }
    for (const row of options) {
      if (seen.has(row.class)) continue;
      seen.add(row.class);
      rows.push({ key: 'opt:' + row.id, pick: row.id, classId: row.class, name: row.name, kind: row.kind, points: row.points, historical: false });
    }
    return rows;
  }, [fleet]);

  const budget = fleet?.budget ?? 0;
  const pointsOf = (pick: string) => resolved.get(pick)?.points ?? 0;
  const classOf = (pick: string) => resolved.get(pick)?.classId ?? pick;
  const total = picks.reduce((sum, pick) => sum + pointsOf(pick), 0);
  const segments = kinds.map((kind) => ({
    kind,
    points: picks.filter((pick) => (resolved.get(pick)?.kind ?? '') === kind).reduce((sum, pick) => sum + pointsOf(pick), 0),
  }));
  const validPicks = picks.length === historical.length && picks.every((pick) => resolved.has(pick));
  const over = total > budget;
  const ready = !!fleet && validPicks && !over && !busy;

  const availableProfiles = useMemo(() => {
    const list = profiles.includes(defaultProfile) ? [] : [defaultProfile];
    return [...list, ...profiles];
  }, [profiles, defaultProfile]);

  function slotView(index: number) {
    const row = historical[index];
    const pick = picks[index] ?? row?.class ?? '';
    const candidate = resolved.get(pick);
    const sameClass = candidate?.classId === row?.class;
    return {
      pick,
      name: sameClass ? row.name : candidate?.name ?? pick,
      kind: candidate?.kind ?? row?.kind ?? '',
      points: candidate?.points ?? row?.points ?? 0,
      classId: candidate?.classId ?? row?.class ?? pick,
    };
  }

  function openPicker(index: number) {
    setSlot(index);
    setPendingKey(picks[index]);
    setFilter('all');
    setSearch('');
    setSort('points');
    setNotice('');
  }

  const visibleCandidates = useMemo(() => {
    const term = search.trim().toLowerCase();
    return candidates.filter((candidate) => (filter === 'all' || candidate.kind === filter) &&
      (!term || [candidate.name, candidate.classId, kindNames[candidate.kind]].some((value) => value?.toLowerCase().includes(term))))
      .sort((a, b) => sort === 'points' ? b.points - a.points
        : sort === 'kind' ? a.kind.localeCompare(b.kind) || b.points - a.points
          : a.name.localeCompare(b.name, 'zh-CN'));
  }, [candidates, filter, search, sort]);

  const current = slot === undefined ? undefined : slotView(slot);
  const pending = pendingKey ? resolved.get(pendingKey) : undefined;
  const pendingOver = !!pending && !!current && total - current.points + pending.points > budget;
  const presetsHere = presets.filter((preset) => preset.stageId === stageId && preset.difficulty === difficulty);

  function commit() {
    if (slot === undefined || !pending || pendingOver || !current) return;
    if (pending.pick !== current.pick) {
      setPicks((list) => {
        const next = [...list];
        next[slot] = pending.pick;
        return next;
      });
    }
    setSlot(undefined);
    setPendingKey(undefined);
  }

  function resetHistorical() {
    setPicks(historical.map((row) => row.class));
    setNotice('已恢复按历史编制。');
  }

  function savePreset() {
    if (!fleet || !validPicks) return;
    const preset: FleetPreset = {
      id: crypto.randomUUID(),
      name: `${stageTitle} · ${difficultyNames[difficulty]}`,
      stageId, difficulty, picks, profile, updatedAt: Date.now(),
    };
    setPresets(appendPreset(profileId, preset));
    setNotice('已保存为出击预设。');
  }

  function loadPreset(id: string) {
    const preset = presets.find((item) => item.id === id);
    if (!preset) return;
    const known = new Set([...historical.map((row) => row.class), ...options.map((row) => row.id)]);
    if (preset.picks.length !== historical.length || !preset.picks.every((pick) => known.has(pick))) {
      setNotice('该预设与当前关卡编制不符，未载入。');
      return;
    }
    setPicks(preset.picks);
    setProfile(preset.profile);
    setNotice('已载入预设。');
  }

  const checks = [
    { ok: picks.length === historical.length, label: '舰位数', detail: `${picks.length} / ${historical.length}` },
    { ok: true, label: '同阵营', detail: sideNames[side] },
    { ok: !over, label: '点价未超', detail: `${total.toLocaleString()} / ${budget.toLocaleString()}` },
    { ok: picks.every((pick) => resolved.has(pick)), label: '舰卡有效', detail: '已登记时期舰卡' },
    { ok: true, label: '历史阵位保持', detail: '位置 / 航向 / 航速' },
  ];

  function launch() {
    if (!ready) return;
    setSheet(false);
    onLaunch({ fleet: picks, profile });
  }

  function chooseMode(next: 'history' | 'taskforce') {
    setMode(next);
    setSlot(undefined);
    setPendingKey(undefined);
    setSheet(false);
  }

  const budgetBlock = <BudgetMeter total={total} budget={budget} segments={segments} />;
  const checksBlock = <RuleCheck items={checks} />;
  const tacticsBlock = <section className="dep-section">
    <h3>战术</h3>
    <label className="dep-field">战术风格
      <select value={profile} disabled={!!busy} onChange={(event) => setProfile(event.target.value as Profile)}>
        {availableProfiles.map((id) => <option key={id} value={id}>{profileNames[id]}</option>)}
      </select>
    </label>
    <div className="dep-rows">
      <div><span>编队</span><b>历史纵队 · 锁</b></div>
      <div><span>初始航速</span><b>{formation?.speed !== undefined ? `${formation.speed} 节 · 锁` : '按原页 · 锁'}</b></div>
      <div><span>领舰</span><b>{historical[0] ? slotView(0).name + ' · 锁' : '—'}</b></div>
    </div>
  </section>;
  const presetsBlock = <section className="dep-section">
    <h3>预设</h3>
    <div className="dep-actions">
      <button type="button" className="dep-btn" disabled={!ready} onClick={savePreset}>保存为预设</button>
      <button type="button" className="dep-btn" disabled={!fleet} onClick={resetHistorical}>按历史编制</button>
    </div>
    {presetsHere.length > 0 && <label className="dep-field">载入预设
      <select defaultValue="" onChange={(event) => { loadPreset(event.target.value); event.currentTarget.value = ''; }}>
        <option value="">选择预设</option>
        {presetsHere.map((preset) => <option key={preset.id} value={preset.id}>{preset.name}</option>)}
      </select>
    </label>}
    {notice && <p className="dep-notice" role="status">{notice}</p>}
  </section>;
  const launchBlock = <div className="dep-launch">
    <button type="button" className="dep-launch__button" disabled={!ready} onClick={launch}>
      {busy ? '正在出航…' : '出航作战'}
    </button>
    <p>{validPicks && !over ? '历史阵位固定 · 不消耗个人舰库' : over ? `超出预算 ${(total - budget).toLocaleString()} 分` : '编成尚未完成'}</p>
  </div>;

  return <main className="deployment-screen" aria-label="关卡前编成">
    <header className="dep-top">
      <button type="button" className="dep-back" onClick={onBack}>‹ 返回战役</button>
      <div className="dep-title">
        <h1>{stageTitle}</h1>
        <small>出击编成 · {mode === 'taskforce' ? '特混' : '历史'} · {difficultyNames[difficulty]}难度</small>
      </div>
      <div className="dep-mode-tabs" role="group" aria-label="编成方式">
        <button type="button" aria-pressed={mode === 'history'} onClick={() => chooseMode('history')}>历史编制</button>
        <button type="button" aria-pressed={mode === 'taskforce'} disabled={!fleet?.taskForceSupported}
          title={fleet && !fleet.taskForceSupported ? '本关暂未接入特混编成' : undefined}
          onClick={() => chooseMode('taskforce')}>特混编成</button>
      </div>
      <span className="dep-side">{sideNames[side]}</span>
      <span className="dep-count">{mode === 'taskforce' ? `${fleet?.positions?.length ?? 0} 个初设位置` : `${historical.length} 个历史舰位`}</span>
    </header>

    {(loadError || launchError) && <p className="dep-error" role="alert">{loadError || launchError}</p>}

    {mode === 'taskforce' && fleet ? <TaskForceBuilder
      fleet={fleet} side={side}
      profile={profile} setProfile={setProfile} availableProfiles={availableProfiles}
      busy={busy}
      onLaunch={({ groups, profile: nextProfile }) => onLaunch({ groups, profile: nextProfile })} />
      : <div className="dep-body">
      <aside className="dep-intel">
        <p className="dep-eyebrow">编成规则</p>
        <h2>换舰不换位</h2>
        <p>本关有 {historical.length} 个历史舰位，不可增减。每个舰位可换同阵营已登记舰卡；位置、航向、航速与领舰按原页固定。</p>
        <dl className="dep-facts">
          <div><dt>历史兵力</dt><dd>{historical.length} 艘</dd></div>
          <div><dt>点价预算</dt><dd>{budget.toLocaleString()} 分</dd></div>
          {formation?.course !== undefined && <div><dt>历史航向</dt><dd>{formation.course}°</dd></div>}
          {formation?.speed !== undefined && <div><dt>历史航速</dt><dd>{formation.speed} 节</dd></div>}
        </dl>
        <p className="dep-note">历史舰可临时体验，不消耗个人舰库。点价来自已核验舰卡，换舰会改变出战舰卡，但不改变阵位。</p>
        <p className="dep-note">本关可换舰卡以已录入的时期舰卡为准；未登记的舰不会出现在候选里。</p>
      </aside>

      <section className="dep-main">
        <div className="dep-main-head">
          <h2>出击编成</h2>
          <span>{picks.length} / {historical.length} 舰位</span>
        </div>
        <div className="dep-diagram" aria-hidden="true">
          <span>历史纵队{formation?.course !== undefined ? ` · 航向 ${formation.course}°` : ''}{formation?.speed !== undefined ? ` · ${formation.speed} 节` : ''}</span>
          <svg viewBox="0 0 640 56" preserveAspectRatio="none">
            <line x1="40" y1="44" x2="600" y2="12" stroke="#e8c98c55" strokeDasharray="3 5" />
            {historical.map((_, index) => {
              const x = 40 + (560 / Math.max(1, historical.length - 1)) * index;
              const y = 44 - (32 / Math.max(1, historical.length - 1)) * index;
              return <circle key={index} cx={x} cy={y} r={index === 0 ? 5 : 3.5}
                fill={index === 0 ? '#e8c98c' : '#102833'} stroke={index === 0 ? '#f3dca9' : '#7d9aa3'} />;
            })}
          </svg>
        </div>

        {!fleet && !loadError && <p className="dep-loading" role="status">正在读取历史编制与已登记舰卡…</p>}
        {fleet && historical.length === 0 && <p className="dep-loading" role="status">本关没有可编成的历史舰位。</p>}

        <ol className="dep-slots" aria-label="历史舰位">
          {historical.map((row, index) => {
            const view = slotView(index);
            const isHistorical = view.classId === row.class;
            return <li key={row.slot ?? index}>
              <button type="button" className={'dep-slot' + (index === 0 ? ' is-leader' : '')}
                onClick={() => openPicker(index)}
                aria-label={`第 ${index + 1} 舰位，${view.name}，${kindNames[view.kind] ?? view.kind}，${view.points} 分，点击更换`}>
                <span className="dep-slot__index">{String(index + 1).padStart(2, '0')}</span>
                <ShipThumb size="sm" ship={{ id: view.pick.startsWith('IBS-') ? view.pick : undefined, classId: view.classId, name: view.name, kind: view.kind }} />
                <span className="dep-slot__name">
                  <b>{view.name}
                    {isHistorical && <span className="dep-tag">历史舰</span>}
                    {index === 0 && <span className="dep-tag is-leader">领舰</span>}
                  </b>
                  <small>{kindNames[view.kind] ?? view.kind}{row.name !== view.name ? ` · 原 ${row.name}` : ''}</small>
                </span>
                <span className="dep-slot__points">{view.points.toLocaleString()}<small>分</small></span>
                <span className="dep-slot__swap">更换</span>
                <span className="dep-slot__lock" aria-hidden="true">◇</span>
              </button>
            </li>;
          })}
        </ol>

        <div className="dep-tools">
          <span>点击舰位更换同阵营舰卡</span>
          <span>候选 {candidates.length} 艘</span>
        </div>
      </section>

      <aside className="dep-staff">
        {budgetBlock}
        {checksBlock}
        {tacticsBlock}
        {presetsBlock}
        {launchBlock}
      </aside>
    </div>}

    {mode !== 'taskforce' && <>
    <div className="dep-mobile-bar">
      <button type="button" className="dep-mobile-budget" onClick={() => setSheet(true)}
        aria-label="打开参谋，查看编成校验与战术">
        <b>{total.toLocaleString()} <i>/ {budget.toLocaleString()}</i></b>
        <small className={over ? 'is-over' : ''}>{over ? `超 ${(total - budget).toLocaleString()} 分` : '预算内'}</small>
      </button>
      <button type="button" className="dep-mobile-staff" onClick={() => setSheet(true)}>参谋</button>
      <button type="button" className="dep-mobile-launch" disabled={!ready} onClick={launch}>
        {busy ? '出航中…' : '出航作战'}
      </button>
    </div>

    {sheet && <div className="dep-sheet-layer" role="presentation"
      onMouseDown={(event) => { if (event.target === event.currentTarget) setSheet(false); }}>
      <section className="dep-sheet" role="dialog" aria-modal="true" aria-label="参谋">
        <header className="dep-sheet__head">
          <div><span>编成校验与战术</span><h2>参谋</h2></div>
          <button type="button" className="dep-btn" onClick={() => setSheet(false)}>关闭</button>
        </header>
        <div className="dep-sheet__body">
          {budgetBlock}
          {checksBlock}
          {tacticsBlock}
          {presetsBlock}
        </div>
        <footer className="dep-sheet__foot">{launchBlock}</footer>
      </section>
    </div>}
    </>}

    {mode !== 'taskforce' && slot !== undefined && current && <div className="dep-candidate-layer" role="presentation"
      onMouseDown={(event) => { if (event.target === event.currentTarget) { setSlot(undefined); setPendingKey(undefined); } }}>
      <section className="dep-candidate" role="dialog" aria-modal="true" aria-label="更换舰船">
        <header className="dep-candidate__head">
          <div>
            <span>第 {slot + 1} 舰位 · 当前 {current.name}</span>
            <h2>更换舰船</h2>
          </div>
          <button type="button" className="dep-btn" onClick={() => { setSlot(undefined); setPendingKey(undefined); }}>关闭</button>
        </header>

        <div className="dep-candidate__tools">
          <div className="dep-filter" role="group" aria-label="舰种筛选">
            <button type="button" aria-pressed={filter === 'all'} onClick={() => setFilter('all')}>全部</button>
            {kinds.map((kind) => <button key={kind} type="button" aria-pressed={filter === kind} onClick={() => setFilter(kind)}>{kind}</button>)}
          </div>
          <label className="dep-sort">排序
            <select value={sort} onChange={(event) => setSort(event.target.value as Sort)}>
              <option value="points">点价</option>
              <option value="kind">舰种</option>
              <option value="name">舰名</option>
            </select>
          </label>
          <input className="dep-search" type="text" inputMode="search" autoFocus value={search}
            onChange={(event) => setSearch(event.target.value)} placeholder="搜索舰名 / 舰级" />
        </div>

        <ul className="dep-candidate__list">
          {visibleCandidates.map((candidate) => {
            const overBudget = total - current.points + candidate.points > budget;
            const same = candidate.pick === current.pick;
            return <li key={candidate.key}>
              <button type="button" className={'dep-candidate__row' + (pendingKey === candidate.pick ? ' is-selected' : '')}
                aria-pressed={pendingKey === candidate.pick} disabled={overBudget}
                onClick={() => setPendingKey(candidate.pick)}>
                <ShipThumb size="sm" ship={{ id: candidate.pick.startsWith('IBS-') ? candidate.pick : undefined, classId: candidate.classId, name: candidate.name, kind: candidate.kind }} />
                <span className="dep-candidate__name">
                  <b>{candidate.name}{candidate.historical && <span className="dep-tag">历史舰</span>}</b>
                  <small>{kindNames[candidate.kind] ?? candidate.kind} · {candidate.classId}</small>
                </span>
                <span className="dep-candidate__points">{candidate.points.toLocaleString()}<small>分</small></span>
                <span className={'dep-candidate__delta' + (overBudget ? ' is-over' : '')}>
                  {overBudget ? '超预算' : same ? '当前' : `${candidate.points - current.points >= 0 ? '+' : ''}${(candidate.points - current.points).toLocaleString()}`}
                </span>
              </button>
            </li>;
          })}
          {!visibleCandidates.length && <li className="dep-candidate__empty">没有符合筛选条件的舰卡。</li>}
        </ul>

        <footer className="dep-candidate__foot">
          <p>{pending ? <>已选 <b>{pending.name}</b> · {pending.points.toLocaleString()} 分{pendingOver ? `（超出 ${(total - current.points + pending.points - budget).toLocaleString()} 分）` : ''}</> : '选择一艘舰船后确认'}</p>
          <div>
            <button type="button" className="dep-btn" onClick={() => { setSlot(undefined); setPendingKey(undefined); }}>取消</button>
            <button type="button" className="dep-btn is-primary" disabled={!pending || pendingOver || pending.pick === current.pick} onClick={commit}>换上该舰</button>
          </div>
        </footer>
      </section>
    </div>}
  </main>;
}
