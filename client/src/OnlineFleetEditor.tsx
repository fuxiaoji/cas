import { useEffect, useId, useRef, useState } from 'react';
import type { FormEvent } from 'react';
import { OnlineError, onlineMeta, onlineRequest } from './online';
import type { OnlineMeta } from './online';
import './online-fleet.css';

const budgets = [1000, 1500, 2000, 2500, 3000, 5000, 10000] as const;
type Budget = typeof budgets[number];
type Side = 'allies' | 'axis';
type Ship = { id: string; name: string; side: Side; type: string; combat_ready: boolean };
type Catalog = { ships: Ship[]; ai_profiles: { id: string; name: string }[] };
type Draft = { id: string; name: string; side: Side; budget: Budget; ship_ids: string[];
  ai_profile: string; leader_id: string | null; cost_version: null };
type Validation = { structure_valid: boolean; combat_ready: boolean; ranked_ready: boolean;
  unavailable_ship_ids: string[]; cost: number | null; point_table_version: string | null; blocking_reasons: string[] };
type Entry = { fleet: Draft; validation: Validation };
type FleetBook = { fleets: Entry[]; active_fleet_id: string | null; point_table_version: string | null; ranked_available: boolean };
type Data = { catalog: Catalog; meta: OnlineMeta; book: FleetBook };
type Editor = { draft: Draft; dirty: boolean };
type Tab = 'roster' | 'presets';
type Props = { token: string; onBack?: () => void; onRanked?: () => void };

const sideNames = { allies: '同盟', axis: '轴心' };
const roleNames: Record<string, string> = { DD: '驱逐舰', CL: '轻巡洋舰', CA: '重巡洋舰', BB: '战列舰' };
const rules = {
  3000: { title: '3000 分护航战', count: 6, description: '3 至 6 艘，至少 2 艘驱逐舰，轻巡和重巡合计最多 2 艘。' },
  10000: { title: '10000 分战列舰交战', count: 8, description: '3 至 8 艘，1 至 2 艘战列舰，至少 2 艘护航舰，驱逐舰最多 4 艘。' },
};
const ruleFor = (budget: Budget) => budget === 3000 || budget === 10000 ? rules[budget] : undefined;
const errorMessage = (error: unknown) => error instanceof Error ? error.message : '读取舰队失败，请重试。';
const validationText = (entry: Entry | undefined) => {
  if (!entry) return '';
  const { validation, fleet } = entry;
  if (validation.ranked_ready && validation.cost != null)
    return `排位核验通过：点价 ${validation.cost} 分（${fleet.budget} 分档上限），可入队。`;
  if (!validation.blocking_reasons.length) return '';
  const price = validation.cost != null ? `点价 ${validation.cost} 分，` : '';
  if (validation.blocking_reasons.includes('cas_point_table_unavailable') && fleet.budget === 10000)
    return '10000 分档尚未开放排位，可先保存个人草案。';
  return `${price}暂不可入队：${validation.blocking_reasons.join('；')}。`;
};
const newDraft = (profiles: string[]): Draft => ({
  id: 'fleet-' + crypto.randomUUID(), name: '我的同盟舰队', side: 'allies', budget: 2000,
  ship_ids: [], ai_profile: profiles[0] ?? '', leader_id: null, cost_version: null,
});

function FleetEditor({ token, onBack, onRanked }: Props) {
  const [data, setData] = useState<Data>();
  const [editor, setEditor] = useState<Editor>();
  const [tab, setTab] = useState<Tab>('roster');
  const [filter, setFilter] = useState('');
  const [refresh, setRefresh] = useState(0);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const formId = useId();
  const locked = useRef(false);
  const pending = useRef<{ key: string; id: string } | undefined>(undefined);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError('');
    void Promise.all([onlineRequest<Catalog>('/catalog'), onlineMeta(token), onlineRequest<FleetBook>('/fleets', token)])
      .then(([catalog, meta, book]) => {
        if (!active) return;
        setData({ catalog, meta, book });
        setEditor(current => {
          if (current?.dirty) return current;
          const id = current?.draft.id ?? book.active_fleet_id;
          const entry = book.fleets.find(item => item.fleet.id === id);
          return { draft: entry?.fleet ?? newDraft(meta.ai_profiles), dirty: false };
        });
      })
      .catch(reason => { if (active) setError(errorMessage(reason)); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [token, refresh]);

  const draft = editor?.draft;
  const busy = loading || saving;
  const saved = draft && !editor.dirty ? data?.book.fleets.find(item => item.fleet.id === draft.id) : undefined;
  const rule = draft && ruleFor(draft.budget);
  const maxShips = rule?.count ?? (draft && draft.budget > 2000 ? 12 : 6);
  const ships = new Map(data?.catalog.ships.map(ship => [ship.id, ship]));
  const owns = new Set(data?.meta.owned_ships);
  const lineup = (draft?.ship_ids ?? []).flatMap(id => {
    const ship = ships.get(id);
    return ship ? [ship] : [];
  });
  const term = filter.trim().toLowerCase();
  const roster = (data?.catalog.ships ?? []).filter(ship => owns.has(ship.id) && ship.side === draft?.side &&
    [ship.name, ship.type, roleNames[ship.type], ship.id].some(value => value?.toLowerCase().includes(term)));
  const profiles = data?.meta.ai_profiles.map(id => ({ id, label: data.catalog.ai_profiles.find(a => a.id === id)?.name ?? id })) ?? [];
  const shipsPending = saved?.validation.unavailable_ship_ids.length ?? lineup.filter(ship => !ship.combat_ready).length;

  function edit(change: (draft: Draft) => Draft) {
    setEditor(current => current ? { draft: change(current.draft), dirty: true } : current);
    setNotice('');
    setError('');
  }

  function selectShip(id: string) {
    edit(current => {
      const ship_ids = current.ship_ids.includes(id) ? current.ship_ids.filter(ship => ship !== id) : [...current.ship_ids, id];
      const leader_id = current.leader_id && ship_ids.includes(current.leader_id) ? current.leader_id : ship_ids[0] ?? null;
      return { ...current, ship_ids, leader_id };
    });
  }

  function loadPreset(entry: Entry) {
    setEditor({ draft: entry.fleet, dirty: false });
    setFilter('');
    setError('');
    setNotice('已载入「' + entry.fleet.name + '」。');
  }

  function startDraft() {
    if (!data) return;
    setEditor({ draft: newDraft(data.meta.ai_profiles), dirty: true });
    setTab('roster');
    setFilter('');
    setNotice('');
    setError('');
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!draft || busy || locked.current || !draft.name.trim() || !draft.ship_ids.length || !draft.ai_profile) return;
    const fleet = { ...draft, name: draft.name.trim() };
    const key = JSON.stringify(fleet);
    const request_id = pending.current?.key === key ? pending.current.id : crypto.randomUUID();
    pending.current = { key, id: request_id };
    locked.current = true;
    setSaving(true);
    setError('');
    setNotice('');
    try {
      const answer = await onlineRequest<Entry & { active_fleet_id: string; meta: OnlineMeta }>('/fleets', token, { request_id, fleet });
      pending.current = undefined;
      const entry = { fleet: answer.fleet, validation: answer.validation };
      setData(current => current && ({ ...current, meta: answer.meta, book: {
        ...current.book, active_fleet_id: answer.active_fleet_id,
        fleets: [...current.book.fleets.filter(item => item.fleet.id !== entry.fleet.id), entry],
      } }));
      setEditor({ draft: entry.fleet, dirty: false });
      setNotice('已保存「' + entry.fleet.name + '」，并设为当前预设。');
    } catch (reason) {
      if (reason instanceof OnlineError && reason.status && reason.status < 500) pending.current = undefined;
      setError(errorMessage(reason));
    } finally {
      locked.current = false;
      setSaving(false);
    }
  }

  return <main className="online-fleet" aria-label="云端个人编队">
    <header className="online-fleet__header">
      {onBack && <button type="button" onClick={onBack}>‹ 返回母港</button>}
      <h1>云端编队</h1>
      <span>个人预设</span>
      <button type="button" disabled={busy} onClick={() => setRefresh(value => value + 1)}>刷新</button>
    </header>

    {data && draft ? <div className="online-fleet__workspace">
      <section className="online-fleet__roster" aria-label="舰船与预设">
        <nav aria-label="编队名册">
          <button type="button" aria-pressed={tab === 'roster'} onClick={() => setTab('roster')}>舰船名册</button>
          <button type="button" aria-pressed={tab === 'presets'} onClick={() => setTab('presets')}>已保存预设 <small>{data.book.fleets.length}</small></button>
        </nav>
        <div className="online-fleet__scroll">
          {tab === 'roster' ? <>
            <label className="online-fleet__search">筛选已拥有舰船
              <input type="search" value={filter} onChange={e => setFilter(e.target.value)} placeholder="舰名或舰种" />
            </label>
            <p className="online-fleet__caption">{sideNames[draft.side]}舰船，可编入云端草案。</p>
            {roster.length ? <ul className="online-fleet__rows">{roster.map(ship => {
              const chosen = draft.ship_ids.includes(ship.id);
              return <li key={ship.id}><button type="button" aria-pressed={chosen}
                aria-label={(chosen ? '移出 ' : '编入 ') + ship.name}
                disabled={busy || (!chosen && lineup.length >= maxShips)} onClick={() => selectShip(ship.id)}>
                <span className="online-fleet__hull-code">{ship.type}</span><strong>{ship.name}</strong>
                <small>{chosen ? '已编入' : '编入'}</small>
              </button></li>;
            })}</ul> : <p className="online-fleet__empty">{term ? '没有符合筛选条件的舰船。' : '本账号尚无该阵营舰船。可在征募或新手赠礼中获得。'}</p>}
          </> : <>
            <div className="online-fleet__preset-tools"><h2>云端预设</h2><button type="button" onClick={startDraft} disabled={busy}>新建预设</button></div>
            {data.book.fleets.length ? <ul className="online-fleet__rows">{data.book.fleets.map(entry => {
              const fleet = entry.fleet;
              const validation = entry.validation;
              return <li key={fleet.id}><button type="button" aria-pressed={fleet.id === draft.id} disabled={busy}
                aria-label={'载入 ' + fleet.name} onClick={() => loadPreset(entry)}>
                <svg className="online-fleet__preset-icon" viewBox="0 0 24 24" aria-hidden="true">
                  <circle cx="12" cy="4" r="2" /><path d="M12 6v14M8 9h8M3 14a9 6 0 0 0 18 0m-18 0 3 1m15-1-3 1" />
                </svg>
                <span><strong>{fleet.name}</strong>
                  <small>{sideNames[fleet.side]} {fleet.budget} 分 · {fleet.ship_ids.length} 艘 ·
                    {' '}{validation.ranked_ready && validation.cost != null ? `点价 ${validation.cost} 分 · 可入队` : '暂不可入队'}</small></span>
                <small>{data.book.active_fleet_id === fleet.id ? '当前预设' : '载入'}</small>
              </button></li>;
            })}</ul> : <p className="online-fleet__empty">保存第一支编队后，可在这里载入。</p>}
          </>}
        </div>
      </section>

      <section className="online-fleet__builder" aria-label="出战编制草案">
        <header><h2>出战编制</h2><span>{lineup.length} / {maxShips} 艘</span></header>
        <form id={formId} className="online-fleet__scroll" onSubmit={save}>
          <fieldset disabled={busy}>
            <div className="online-fleet__fields">
              <label className="online-fleet__name">编队名称<input maxLength={80} value={draft.name}
                onChange={e => edit(current => ({ ...current, name: e.target.value }))} /></label>
              <label>阵营<select value={draft.side} onChange={e => {
                const side = e.target.value as Side;
                edit(current => ({ ...current, side, ship_ids: [], leader_id: null }));
                setFilter('');
              }}><option value="allies">同盟</option><option value="axis">轴心</option></select></label>
              <label>编制档位<select value={draft.budget} onChange={e => {
                const budget = Number(e.target.value) as Budget;
                edit(current => ({ ...current, budget }));
              }}>{budgets.map(budget => <option value={budget} key={budget}>{ruleFor(budget)?.title ?? `${budget} 分个人草案`}</option>)}</select></label>
              <label>编队领舰<select value={draft.leader_id ?? ''} disabled={!lineup.length}
                onChange={e => edit(current => ({ ...current, leader_id: e.target.value }))}>
                {!lineup.length && <option value="">先编入舰船</option>}
                {lineup.map(ship => <option key={ship.id} value={ship.id}>{ship.name}</option>)}
              </select></label>
              <label>AI 指挥风格<select value={draft.ai_profile} onChange={e => edit(current => ({ ...current, ai_profile: e.target.value }))}>
                {profiles.length ? profiles.map(profile => <option key={profile.id} value={profile.id}>{profile.label}</option>) : <option value="">尚未解锁</option>}
              </select></label>
            </div>
            <p className="online-fleet__rule">{rule?.description ?? `该档位最多编入 ${maxShips} 艘。`} 更换阵营会清空当前选舰。</p>
            {lineup.length ? <ol className="online-fleet__lineup" aria-label="当前编入舰船">{lineup.map(ship => <li key={ship.id}>
              <span>{ship.name}{ship.id === draft.leader_id && <small>领舰</small>}</span>
              <button type="button" onClick={() => selectShip(ship.id)} aria-label={'从编制移出 ' + ship.name}>移出</button>
            </li>)}</ol> : <p className="online-fleet__empty">从舰船名册选舰，随后选择领舰。</p>}
          </fieldset>
        </form>
      </section>
    </div> : <p className="online-fleet__loading" role="status">{loading ? '正在读取云端舰库和预设。' : '无法读取云端编队，请刷新。'}</p>}

    <footer className="online-fleet__footer">
      <div className="online-fleet__feedback">
        <p>{saved?.validation.structure_valid ? '编制校验通过，已保存为云端草案。' : '保存时校验舰种和数量。'}
          {saved && validationText(saved)}{!saved && data?.book.ranked_available && ' 排位点表已接入，保存 3000／10000 分档后由服务端核价。'}
          {shipsPending > 0 && ` ${shipsPending} 艘舰的个人出战配置待核验。`}</p>
        {error ? <p role="alert" className="online-fleet__error">{error}</p> : notice && <p role="status">{notice}</p>}
      </div>
      <div className="online-fleet__actions">
        {data?.book.ranked_available ?
          <button type="button" onClick={() => onRanked?.()}>前往排位入队</button> :
          <button type="button" disabled>排位未开放</button>}
        <button className="primary" type="submit" form={formId}
          disabled={busy || !draft?.ship_ids.length || !draft.name.trim() || !draft.ai_profile}>{saving ? '正在保存' : '保存为当前预设'}</button>
      </div>
    </footer>
  </main>;
}

export function OnlineFleetEditor(props: Props) {
  return <FleetEditor key={props.token} {...props} />;
}
