import { useMemo, useState } from 'react';
import { profileNames, sideNames } from '../../engine';
import type { Profile, Side } from '../../engine';
import type { FleetPick } from '../../CampaignArchive';
import type { GroupPick } from '../../campaign-progress';
import { BudgetMeter, RuleCheck } from '../../widgets/formation';
import { ShipThumb } from '../../widgets/ship-thumb';
import './taskforce.css';

const kindNames: Record<string, string> = { DD: '驱逐舰', CL: '轻巡洋舰', CA: '重巡洋舰', BB: '战列舰' };
const kinds = ['DD', 'CL', 'CA', 'BB'] as const;
type KindFilter = 'all' | typeof kinds[number];

type Candidate = {
  key: string; pick: string; classId: string; name: string; kind: string; points: number; historical: boolean;
};

interface Props {
  fleet: FleetPick;
  side: Side;
  profile: Profile;
  setProfile: (profile: Profile) => void;
  availableProfiles: Profile[];
  busy?: boolean;
  onLaunch: (launch: { groups: GroupPick[]; profile: Profile }) => void;
}

export function TaskForceBuilder({
  fleet, side, profile, setProfile, availableProfiles, busy, onLaunch,
}: Props) {
  const [shipsAt, setShipsAt] = useState<Record<number, string[]>>({});
  const [picker, setPicker] = useState<number>();
  const [filter, setFilter] = useState<KindFilter>('all');
  const [search, setSearch] = useState('');

  const historical = fleet.historical ?? [];
  const options = fleet.options ?? [];
  const positions = fleet.positions ?? [];
  const budget = fleet.budget;

  const resolved = useMemo(() => {
    const map = new Map<string, Candidate>();
    for (const row of historical) {
      if (!map.has(row.class)) {
        map.set(row.class, {
          key: 'hist:' + row.class, pick: row.class, classId: row.class,
          name: row.name, kind: row.kind, points: row.points, historical: true,
        });
      }
    }
    for (const row of options) {
      map.set(row.id, {
        key: 'opt:' + row.id, pick: row.id, classId: row.class,
        name: row.name, kind: row.kind, points: row.points, historical: false,
      });
    }
    return map;
  }, [fleet]);

  const candidates = useMemo(() => {
    const rows: Candidate[] = [];
    const seen = new Set<string>();
    for (const row of historical) {
      if (seen.has(row.class)) continue;
      seen.add(row.class);
      rows.push({
        key: 'hist:' + row.class, pick: row.class, classId: row.class,
        name: row.name, kind: row.kind, points: row.points, historical: true,
      });
    }
    for (const row of options) {
      if (seen.has(row.class)) continue;
      seen.add(row.class);
      rows.push({
        key: 'opt:' + row.id, pick: row.id, classId: row.class,
        name: row.name, kind: row.kind, points: row.points, historical: false,
      });
    }
    return rows;
  }, [fleet]);

  const pointsOf = (pick: string) => resolved.get(pick)?.points ?? 0;
  const total = Object.values(shipsAt).flat().reduce((sum, pick) => sum + pointsOf(pick), 0);
  const segments = kinds.map((kind) => ({
    kind,
    points: Object.values(shipsAt).flat()
      .filter((pick) => resolved.get(pick)?.kind === kind)
      .reduce((sum, pick) => sum + pointsOf(pick), 0),
  }));
  const over = total > budget;
  const groups: GroupPick[] = positions.flatMap((position) => {
    const list = shipsAt[position.position] ?? [];
    return list.length ? [{ position: position.position, ships: list }] : [];
  });
  const ready = groups.length > 0 && !over && !busy;
  const pickerGroup = picker === undefined ? [] : shipsAt[picker] ?? [];

  function addShip(position: number, pick: string) {
    setShipsAt((current) => {
      const currentTotal = Object.values(current).flat()
        .reduce((sum, item) => sum + pointsOf(item), 0);
      if (currentTotal + pointsOf(pick) > budget) return current;
      return { ...current, [position]: [...(current[position] ?? []), pick] };
    });
  }

  function removeShip(position: number, index: number) {
    setShipsAt((current) => {
      const next = [...(current[position] ?? [])];
      next.splice(index, 1);
      return { ...current, [position]: next };
    });
  }

  function clearPosition(position: number) {
    setShipsAt((current) => ({ ...current, [position]: [] }));
  }

  const visibleCandidates = useMemo(() => {
    const term = search.trim().toLowerCase();
    return candidates.filter((candidate) => (filter === 'all' || candidate.kind === filter) &&
      (!term || [candidate.name, candidate.classId, kindNames[candidate.kind]]
        .some((value) => value?.toLowerCase().includes(term))));
  }, [candidates, filter, search]);

  const checks = [
    { ok: groups.length > 0, label: '至少一个编队', detail: `${groups.length} / ${positions.length} 个初设位置已派出` },
    { ok: !over, label: '点价未超', detail: `${total.toLocaleString()} / ${budget.toLocaleString()}` },
    { ok: groups.length > 0 && groups.every((group) => group.ships.length > 0), label: '编队非空', detail: '单舰编队也可以' },
    { ok: positions.length > 0, label: '初设位置', detail: '来自本剧本玩家编队' },
    { ok: true, label: '特混记录', detail: '不计历史星级' },
  ];

  return <div className="taskforce" aria-label="特混编成">
    <div className="tf-head">
      <div>
        <strong>特混编成</strong>
        <span>架空部署 · 不计历史星级</span>
      </div>
      <p>{sideNames[side]} · 最多 {positions.length} 个编队 · 点价 {budget.toLocaleString()} 分 · 初设位置由剧本提供</p>
    </div>

    <div className="tf-body">
      <section className="tf-positions" aria-label="初设位置与编队">
        {!positions.length && <p className="tf-empty">本关没有可用的初设位置。</p>}
        {positions.map((position) => {
          const list = shipsAt[position.position] ?? [];
          const points = list.reduce((sum, pick) => sum + pointsOf(pick), 0);
          return <article className={'tf-position' + (list.length ? ' is-active' : '')} key={position.position}>
            <header>
              <span className="tf-position__num">{String(position.position + 1).padStart(2, '0')}</span>
              <div className="tf-position__copy">
                <h3>{position.name}</h3>
                <small>{position.leader ?? '历史编队'} · {position.course ?? '—'}° · {position.speed} 节 · 历史 {position.members} 舰</small>
              </div>
              <b className="tf-position__points">{points.toLocaleString()}<small>分</small></b>
            </header>
            {list.length ? <ol className="tf-group">
              {list.map((pick, index) => {
                const candidate = resolved.get(pick);
                return <li key={`${pick}:${index}`}>
                  <ShipThumb size="sm" ship={{
                    id: pick.startsWith('IBS-') ? pick : undefined,
                    classId: candidate?.classId, name: candidate?.name, kind: candidate?.kind,
                  }} />
                  <span><strong>{candidate?.name ?? pick}</strong><small>{kindNames[candidate?.kind ?? ''] ?? candidate?.kind ?? ''} · {pointsOf(pick).toLocaleString()} 分</small></span>
                  <button type="button" className="tf-btn tf-btn--quiet" onClick={() => removeShip(position.position, index)}>移除</button>
                </li>;
              })}
            </ol> : <p className="tf-position__empty">空置 · 可以不派编队</p>}
            <footer>
              <button type="button" className="tf-btn" onClick={() => { setPicker(position.position); setFilter('all'); setSearch(''); }}>
                {list.length ? '继续编入' : '编成'}
              </button>
              {list.length > 0 && <button type="button" className="tf-btn tf-btn--quiet" onClick={() => clearPosition(position.position)}>清空</button>}
            </footer>
          </article>;
        })}
      </section>

      <aside className="tf-staff">
        <BudgetMeter total={total} budget={budget} segments={segments} />
        <RuleCheck items={checks} />
        <section className="tf-section">
          <h3>战术</h3>
          <label className="tf-field">战术风格
            <select value={profile} disabled={!!busy} onChange={(event) => setProfile(event.target.value as Profile)}>
              {availableProfiles.map((id) => <option key={id} value={id}>{profileNames[id]}</option>)}
            </select>
          </label>
          <p className="tf-note">每个编队从自己的初设位置出发；航向、航速与领舰按该位置固定。编队内按登记的 500 码间距列队。</p>
        </section>
        <div className="tf-launch">
          <button type="button" className="tf-launch__button" disabled={!ready} onClick={() => onLaunch({ groups, profile })}>
            {busy ? '正在出航…' : '特混出航'}
          </button>
          <p>{groups.length ? `派出 ${groups.length} 个编队 · ${total.toLocaleString()} 分` : '先编入至少一个编队'}</p>
          <p>特混编成不计历史星级，不计史实编成。</p>
        </div>
      </aside>
    </div>

    {picker !== undefined && <div className="tf-picker-layer" role="presentation"
      onMouseDown={(event) => { if (event.target === event.currentTarget) setPicker(undefined); }}>
      <section className="tf-picker" role="dialog" aria-modal="true" aria-label="编入舰船">
        <header className="tf-picker__head">
          <div>
            <span>第 {picker + 1} 初设位置 · 当前 {pickerGroup.length} 舰 · {pickerGroup.reduce((sum, pick) => sum + pointsOf(pick), 0).toLocaleString()} 分</span>
            <h2>编入舰船</h2>
          </div>
          <button type="button" className="tf-btn" onClick={() => setPicker(undefined)}>完成</button>
        </header>
        <div className="tf-picker__tools">
          <div className="tf-filter" role="group" aria-label="舰种筛选">
            <button type="button" aria-pressed={filter === 'all'} onClick={() => setFilter('all')}>全部</button>
            {kinds.map((kind) => <button key={kind} type="button" aria-pressed={filter === kind} onClick={() => setFilter(kind)}>{kind}</button>)}
          </div>
          <input className="tf-search" type="text" inputMode="search" autoFocus value={search}
            onChange={(event) => setSearch(event.target.value)} placeholder="搜索舰名 / 舰级" />
        </div>
        <ul className="tf-picker__list">
          {visibleCandidates.map((candidate) => {
            const overBudget = total + candidate.points > budget;
            return <li key={candidate.key}>
              <button type="button" className="tf-candidate" disabled={overBudget}
                onClick={() => addShip(picker, candidate.pick)}>
                <ShipThumb size="sm" ship={{
                  id: candidate.pick.startsWith('IBS-') ? candidate.pick : undefined,
                  classId: candidate.classId, name: candidate.name, kind: candidate.kind,
                }} />
                <span className="tf-candidate__name">
                  <b>{candidate.name}{candidate.historical && <span className="tf-tag">历史舰</span>}</b>
                  <small>{kindNames[candidate.kind] ?? candidate.kind} · {candidate.classId}</small>
                </span>
                <span className="tf-candidate__points">{candidate.points.toLocaleString()}<small>分</small></span>
                <span className={'tf-candidate__add' + (overBudget ? ' is-over' : '')}>{overBudget ? '超预算' : '加入'}</span>
              </button>
            </li>;
          })}
          {!visibleCandidates.length && <li className="tf-picker__empty">没有符合筛选条件的舰卡。</li>}
        </ul>
      </section>
    </div>}
  </div>;
}
