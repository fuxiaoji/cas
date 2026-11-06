import { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { BattleMap } from './BattleMap';
import { Harbor } from './Harbor';
import { ask, clock, maneuverNames, profileNames, sideNames } from './engine';
import type { AiConfig, LogEvent, Maneuver, Observation, Point, Profile, Request, Result, RoutePreview, Ship, Side, Suggestion, Weapon } from './engine';
import { lessons, loadPort, recordLesson, writePort } from './port';
import type { Lesson, PortLaunch } from './port';
import './style.css';

const SAVE_KEY = 'cas.exercise.autosave.v1';
const options = [1, 2, 4, 8] as const;
type Speed = typeof options[number];
type Tab = 'fleet' | 'ai' | 'log';
interface Replay { data: unknown; end: number }
const defaultSetup = { seed: 6106, side: 'allies' as Side, enemy: 'gunnery' as Profile };
const aimAction: Record<Weapon, string> = { gun: '炮击', torpedo: '雷击' };
const descriptions: Record<Profile, string> = {
  coord: '保持编队，在火力与机动之间取平衡。',
  gunnery: '争取射界和火力距离，集中炮击。',
  torpedo: '优先抢占侧向发射位置，寻找雷击机会。',
};
const errorText = (error: unknown) => error instanceof Error ? error.message : String(error);

function Mark() {
  return <svg viewBox="0 0 40 40" width="37" height="37" aria-hidden="true">
    <circle cx="20" cy="20" r="16.5" stroke="currentColor" fill="none" opacity=".6" />
    <path d="M20 1v5m0 28v5M1 20h5m28 0h5M9 25l11-17 11 17-11-4z" fill="none" stroke="currentColor" />
    <path d="m20 8 11 17-11-4zM15 28l5-4 5 4-5 4z" fill="currentColor" />
  </svg>;
}

function eventTone(event: LogEvent) {
  if (/sunk|damage|hit|impact/i.test(event.kind)) return 'strike';
  if (/gun|torpedo|fire/i.test(event.kind)) return 'fire';
  if (/order|route|accepted/i.test(event.kind)) return 'order';
  return 'plain';
}

function App() {
  const [o, setObservation] = useState<Observation>();
  const [loadError, setLoadError] = useState('');
  const [running, setRunning] = useState(false);
  const [speed, setSpeed] = useState<Speed>(4);
  const [busy, setBusy] = useState(false);
  const [fleetId, setFleetId] = useState<number>();
  const [shipId, setShipId] = useState<number>();
  const [tab, setTab] = useState<Tab>('fleet');
  const [editMode, setEditMode] = useState<Maneuver>();
  const [waypoints, setWaypoints] = useState<Point[]>([]);
  const [cruise, setCruise] = useState<number>();
  const [preview, setPreview] = useState<RoutePreview>();
  const [reformPreview, setReformPreview] = useState<RoutePreview>();
  const [suggestion, setSuggestion] = useState<Suggestion>();
  const [replay, setReplay] = useState<Replay>();
  const [notice, setNotice] = useState('');
  const [dialog, setDialog] = useState(false);
  const [setup, setSetup] = useState(defaultSetup);
  const [resultDismissed, setResultDismissed] = useState(false);
  const [port, setPort] = useState(loadPort);
  const [portOpen, setPortOpen] = useState(false);
  const [portError, setPortError] = useState<string>();
  const [training, setTraining] = useState(false);
  const [presetActive, setPresetActive] = useState(false);
  const inFlight = useRef(false);
  const initialized = useRef(false);
  const timeAccumulator = useRef(0);
  const noticeTimer = useRef<number | undefined>(undefined);
  const clockTick = useRef(0);
  const lastSave = useRef(-1);
  const fleet = o?.fleets.find((value) => value.id === fleetId) ?? o?.fleets[0];
  const ships = fleet && o ? fleet.members.map((id) => o.ships.find((ship) => ship.id === id)).filter((ship): ship is Ship => !!ship) : [];
  const selected = o?.ships.find((ship) => ship.id === shipId) ?? ships.find((ship) => ship.id === fleet?.leader) ?? ships[0];
  const result = o?.result;
  const finished = Boolean(result);
  const contactCount = o?.contacts.length ?? 0;

  function hint(message: string) {
    window.clearTimeout(noticeTimer.current);
    setNotice(message);
    noticeTimer.current = window.setTimeout(() => setNotice(''), 4200);
  }
  function update(observation: Observation) {
    clockTick.current = observation.tick;
    setObservation(observation);
    if (observation.result) setRunning(false);
    if (observation.variant === 'challenge' && observation.result?.primary) {
      setPort((state) => state.challengeClear ? state : { ...state, challengeClear: true });
    }
  }
  function learn(id: Lesson) {
    if (!replay && o?.variant !== 'challenge') setPort((state) => recordLesson(state, id));
  }
  function resetDraft() { setEditMode(undefined); setWaypoints([]); setCruise(undefined); setPreview(undefined); setReformPreview(undefined); }
  function resetPanel() {
    resetDraft(); setFleetId(undefined); setShipId(undefined); setSuggestion(undefined);
    setTab('fleet'); setRunning(false); setReplay(undefined); setResultDismissed(false);
    timeAccumulator.current = 0;
  }
  async function persist(toast = false) {
    try {
      const data = await ask<unknown>({ op: 'save' });
      localStorage.setItem(SAVE_KEY, JSON.stringify(data));
      lastSave.current = clockTick.current;
      if (toast) hint('演习已保存，下次打开可继续。');
    } catch (error) { if (toast) hint('保存失败：' + errorText(error)); }
  }

  useEffect(() => {
    if (initialized.current) return;
    initialized.current = true;
    void (async () => {
      try {
        try {
          const saved = localStorage.getItem(SAVE_KEY);
          if (saved) {
            const observation = await ask<Observation>({ op: 'load', save: JSON.parse(saved) });
            lastSave.current = observation.tick; update(observation); return;
          }
        } catch {
          hint('旧存档无法恢复，已开始新的演习。');
        }
        update(await ask<Observation>({ op: 'new', ...defaultSetup }));
        await persist();
      } catch (error) { setLoadError(errorText(error)); }
    })();
    return () => window.clearTimeout(noticeTimer.current);
  }, []);
  useEffect(() => {
    try { writePort(port); }
    catch { hint('本机无法保存母港进度。'); }
  }, [port]);

  useEffect(() => {
    if (!running || busy || finished) return;
    let disposed = false;
    let lastTime = performance.now();
    const interval = window.setInterval(() => {
      const now = performance.now();
      timeAccumulator.current += Math.min(.35, (now - lastTime) / 1000) * speed;
      lastTime = now;
      if (inFlight.current || document.hidden) return;
      const seconds = Math.min(12, Math.floor(timeAccumulator.current + .01));
      if (seconds < 1) return;
      timeAccumulator.current -= seconds;
      inFlight.current = true;
      const request = replay
        ? { op: 'replay', save: replay.data, tick: Math.min(replay.end, clockTick.current + seconds) }
        : { op: 'step', seconds };
      void ask<Observation>(request).then((observation) => {
        if (disposed && replay) return;
        update(observation);
        if (replay && observation.tick >= replay.end) setRunning(false);
        if (!replay && (observation.result || observation.tick - lastSave.current >= 20)) void persist();
      }, (error) => { if (!disposed) { hint(errorText(error)); setRunning(false); } }).finally(() => { inFlight.current = false; });
    }, 125);
    return () => { disposed = true; window.clearInterval(interval); };
  }, [running, busy, speed, finished, replay]);

  useEffect(() => {
    const hide = () => {
      if (document.hidden) { setRunning(false); if (o && !replay) void persist(); }
    };
    document.addEventListener('visibilitychange', hide);
    return () => document.removeEventListener('visibilitychange', hide);
  }, [o !== undefined, replay]);

  const refreshAt = Math.floor((o?.tick ?? 0) / 3);
  useEffect(() => {
    if (!fleet || !editMode || !waypoints.length || replay) { setPreview(undefined); return; }
    let active = true;
    const timer = window.setTimeout(() => {
      void ask<RoutePreview>({ op: 'preview_route', fleet: fleet.id, mode: editMode, points: waypoints, speed: cruise })
        .then((value) => { if (active) setPreview(value); },
          (error) => { if (active) setPreview({ valid: false, paths: [], speed: cruise ?? fleet.speed, error: errorText(error) }); });
    }, 65);
    return () => { active = false; window.clearTimeout(timer); };
  }, [fleet?.id, editMode, waypoints, cruise, refreshAt, replay]);

  async function command(request: Request, after?: () => void) {
    if (replay || finished) return;
    try {
      update(await ask<Observation>(request));
      after?.();
      void persist();
    } catch (error) { hint(errorText(error)); }
  }

  function selectShip(ship: Ship) {
    setShipId(ship.id);
    if (ship.fleet !== null && ship.fleet !== fleet?.id) {
      setFleetId(ship.fleet);
      resetDraft();
      setSuggestion(undefined);
    }
  }
  function movePoint(index: number, point: Point) {
    setPreview(undefined);
    setWaypoints((list) => list.map((old, i) => i === index ? point : old));
  }
  function addPoint(point: Point) {
    if (waypoints.length >= 10) { hint('一条航线最多 10 个途经点。'); return; }
    setPreview(undefined);
    setWaypoints((list) => [...list, point]);
  }
  function chooseMode(mode: Maneuver) {
    if (editMode === mode) return;
    setReformPreview(undefined);
    setPreview(undefined);
    setEditMode(mode);
  }
  async function checkReform() {
    if (!fleet) return;
    resetDraft();
    try { setReformPreview(await ask<RoutePreview>({ op: 'preview_reform', fleet: fleet.id })); }
    catch (error) { hint(errorText(error)); }
  }
  function changeAi(config: AiConfig) {
    if (!fleet) return;
    setSuggestion(undefined);
    void command({ op: 'ai', fleet: fleet.id, ...config });
  }
  async function askAi() {
    if (!fleet) return;
    try { setSuggestion(await ask<Suggestion>({ op: 'suggest', fleet: fleet.id })); }
    catch (error) { hint(errorText(error)); }
  }
  async function acceptAi() {
    if (!suggestion || replay) return;
    try {
      for (const order of suggestion.orders) update(await ask<Observation>(order));
      hint('已采纳战术建议。'); setSuggestion(undefined); void persist();
    } catch (error) { hint('建议未能全部执行：' + errorText(error)); setSuggestion(undefined); }
  }
  async function newExercise() {
    setBusy(true); setRunning(false);
    try {
      const next = await ask<Observation>({ op: 'new', ...setup });
      resetPanel(); update(next); setDialog(false); setTraining(false); setPresetActive(false);
      await persist();
    } catch (error) { hint(errorText(error)); }
    finally { setBusy(false); }
  }
  async function oneStep() {
    if (busy || !o || o.result || inFlight.current) return;
    if (running) setRunning(false);
    setBusy(true);
    try {
      if (replay) update(await ask<Observation>({ op: 'replay', save: replay.data, tick: Math.min(replay.end, o.tick + 1) }));
      else {
        const next = await ask<Observation>({ op: 'step', seconds: 1 });
        update(next); if (next.result) void persist();
      }
    } catch (error) { hint(errorText(error)); }
    finally { setBusy(false); }
  }
  async function startReplay() {
    if (!o || busy) return;
    setRunning(false); setBusy(true); setResultDismissed(true);
    try {
      const data = await ask<unknown>({ op: 'save' });
      const initial = await ask<Observation>({ op: 'replay', save: data, tick: 0 });
      setReplay({ data, end: o.tick }); update(initial); resetDraft();
    } catch (error) { hint(errorText(error)); }
    finally { setBusy(false); }
  }
  async function replayAt(tick: number) {
    if (!replay) return;
    setRunning(false);
    try { update(await ask<Observation>({ op: 'replay', save: replay.data, tick })); }
    catch (error) { hint(errorText(error)); }
  }
  async function exitReplay() {
    setRunning(false); setBusy(true);
    try { update(await ask<Observation>({ op: 'observe' })); setReplay(undefined); setResultDismissed(true); }
    catch (error) { hint(errorText(error)); }
    finally { setBusy(false); }
  }
  async function exportLog() {
    if (!o) return;
    try {
      const report = replay ? { result: o.result, events: o.events } : await ask<{ result: Result | null; events: LogEvent[] }>({ op: 'report' });
      const title = ['CAS 海图指挥台', '虚构昼间演习', sideNames[o.side], '模拟时间 ' + clock(o.tick)];
      const rows = report.events.map((event) => [clock(event.tick), event.text, event.rule ?? ''].filter(Boolean).join('  '));
      const blob = new Blob(['\uFEFF' + title.concat('', rows).join('\r\n')], { type: 'text/plain;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a'); link.href = url; link.download = 'CAS-战情记录.txt';
      link.click(); window.setTimeout(() => URL.revokeObjectURL(url), 5000);
      hint('已生成本席可见的战情记录。');
    } catch (error) { hint(errorText(error)); }
  }
  function toggleClock() {
    if (busy || (finished && !replay)) return;
    if (replay && o && o.tick >= replay.end) { void replayAt(0); return; }
    timeAccumulator.current = 0;
    setRunning((value) => !value);
  }
  function openSetup() { setRunning(false); setDialog(true); }
  async function launchFromHarbor(launch: PortLaunch) {
    setBusy(true); setPortError(undefined);
    try {
      const { training: isTraining, ...options } = launch;
      const next = await ask<Observation>({ op: 'new', ...defaultSetup, ...options });
      resetPanel(); update(next); setPortOpen(false); setTraining(!!isTraining); setPresetActive(!isTraining);
      await persist();
    } catch (error) { setPortError(errorText(error)); }
    finally { setBusy(false); }
  }
  const tabs: { key: Tab; title: string }[] = [{ key: 'fleet', title: '编队' }, { key: 'ai', title: '战术 AI' }, { key: 'log', title: '战情' }];
  const fire = (ship: number, weapon: Weapon, target: string, heading?: number) => {
    void command({ op: 'fire', ship, weapon, target, heading }, () => {
      hint('已下达' + aimAction[weapon] + '命令，执行进度见战情。');
      if (weapon === 'gun' || heading !== undefined) learn(weapon);
      if (fleet?.ai.mode === 'auto' && fleet.ai[weapon]) learn('override');
    });
  };

  if (portOpen) return <Harbor state={port} change={setPort} onReturn={() => setPortOpen(false)} onLaunch={(options) => void launchFromHarbor(options)} busy={busy} error={portError} />;
  if (!o) return <main className="startup">
    <Mark /><h1>海图指挥台</h1>
    <p>{loadError ? '无法开始演习：' + loadError : '正在打开演习海图…'}</p>
    {loadError && <button type="button" onClick={() => location.reload()}>重新打开</button>}
  </main>;

  const latest = [...o.events].reverse();
  const winner = result?.winner === 'allies' || result?.winner === 'axis' ? sideNames[result.winner] + '胜出' : '双方打平';
  const editing = !!editMode && !replay && !finished;
  const nextLesson = training && lessons.find(({ id }) => !port.lessons.includes(id));
  return <main className="command-shell">
    <header className="masthead">
      <div className="brand"><Mark /><div><span>CAS 战术演习</span><h1>海图指挥台</h1></div></div>
      <div className="exercise-label"><span className="live-dot" data-active={running} />{replay ? '战局重演' : finished ? '演习结束' : running ? '演习进行中' : '演习暂停'}</div>
      <div className="clock-deck">
        <span className="time"><strong>{clock(o.tick)}</strong><small> / {clock(replay?.end ?? o.limit)}</small></span>
        <button className="clock-play" type="button" aria-label={running ? '暂停演习' : '开始演习'} onClick={toggleClock} disabled={busy || (finished && !replay)}>
          <span aria-hidden="true">{running ? 'Ⅱ' : '▶'}</span>{running ? '暂停' : '开始'}
        </button>
        <button className="clock-step" type="button" aria-label="推进一秒" title="推进一模拟秒" onClick={() => void oneStep()} disabled={busy || finished}>▹▏</button>
        <div className="speeds" aria-label="演习倍速">{options.map((value) =>
          <button key={value} type="button" aria-pressed={speed === value} onClick={() => setSpeed(value)}>{value}×</button>
        )}</div>
      </div>
      <div className="header-actions">
        <button type="button" className="new-exercise" onClick={openSetup} aria-label="演习设置">演习设置</button>
        <button type="button" className="harbor-link" onClick={() => { setRunning(false); setPortError(undefined); setPortOpen(true); }}>母港</button>
      </div>
    </header>
    <div className="workspace">
      <section className="chart-column">
        <BattleMap
          observation={o} fleet={fleet} selected={selected?.id} disabled={busy || !!replay || finished}
          editing={editing} waypoints={waypoints} preview={preview} reformPreview={reformPreview} onSelect={selectShip} onAddPoint={addPoint}
          onMovePoint={movePoint} onFire={fire} onCancelFire={() => learn('cancel')} onHint={hint}
        />
        <div className="signal-strip">
          <span className="side-tag">{sideNames[o.side]}</span>
          <span>可见接触 <b>{contactCount}</b></span>
          <span className={'signal-last' + (training ? ' lesson-signal' : '')} title={nextLesson ? nextLesson.detail : latest[0]?.text}>
            {training ? nextLesson ? '实操 · ' + nextLesson.detail : '实操完成 · 回母港领取初始舰队。' :
              latest[0] ? clock(latest[0].tick) + '  ' + latest[0].text : '出航后，命令与战斗事件会记入战情。'}
          </span>
          <button type="button" className="text-button" onClick={() => setTab('log')}>战情记录</button>
        </div>
        {replay && <div className="replay-bar">
          <b>重演</b><input type="range" min={0} max={Math.max(1, replay.end)} value={o.tick} aria-label="重演时间" onChange={(event) => void replayAt(Number(event.target.value))} />
          <span>{clock(o.tick)}</span><button type="button" onClick={() => void exitReplay()}>返回现局</button>
        </div>}
        {!replay && finished && !resultDismissed && <div className="result-screen">
          <div className="result-card">
            <p>{o.variant === 'challenge' ? '少舰迎击 · 挑战结束' : '昼间水面演习结束'}</p>
            <h2>{o.variant === 'challenge' ? (result?.primary ? '挑战目标达成' : '挑战目标未达成') : winner}</h2>
            <div className="score"><span>同盟 {result?.allies}</span><span>轴心 {result?.axis}</span></div>
            <div className="actions"><button type="button" className="primary" onClick={() => void startReplay()}>重演战局</button>
              <button type="button" onClick={() => { setResultDismissed(true); setTab('log'); }}>查看战情</button></div>
          </div>
        </div>}
        {notice && <div className="notice" role="status">{notice}</div>}
      </section>
      <aside className="staff-panel" aria-label="指挥面板">
        <nav className="staff-tabs" aria-label="面板">{tabs.map(({ key, title }) =>
          <button key={key} type="button" aria-pressed={tab === key} onClick={() => setTab(key)}>{title}</button>
        )}</nav>
        <div className="staff-scroll">
          {tab === 'fleet' && fleet && <>
            <div className="group-heading">
              {o.fleets.length > 1 ? <select aria-label="选择编队" value={fleet.id} onChange={(event) => { setFleetId(Number(event.target.value)); setShipId(undefined); resetDraft(); setSuggestion(undefined); }}>
                {o.fleets.map((group) => <option key={group.id} value={group.id}>{group.name}</option>)}
              </select> : <h2>{fleet.name}</h2>}
              <span>{ships.filter((ship) => ship.hp > 0).length} 艘在队</span>
            </div>
            <section className="maneuver-section">
              <div className="section-heading"><h3>编队航线</h3><span>{maneuverNames[fleet.mode]} · {fleet.speed} 节</span></div>
              {fleet.notice && <p className="inline-warning">{fleet.notice}</p>}
              <div className="maneuver-choice">
                <button type="button" aria-pressed={editMode === 'follow'} disabled={finished || !!replay} onClick={() => chooseMode('follow')}>领舰移动</button>
                <button type="button" aria-pressed={editMode === 'sync'} disabled={finished || !!replay} onClick={() => chooseMode('sync')}>同步移动</button>
              </div>
              {!editing && <p className="field-note">选择机动方式，再到海图上添加途经点。</p>}
              {editing && <div className="route-editor">
                <div className="route-progress"><strong>{waypoints.length} 个途经点</strong><span>{preview?.valid ? '航线可用' : waypoints.length ? '校核航线' : '点选海图'}</span></div>
                {preview?.error && <p className="inline-warning">{preview.error}</p>}
                <div className="route-tools">
                  <button type="button" disabled={!waypoints.length} onClick={() => { setPreview(undefined); setWaypoints((list) => list.slice(0, -1)); }}>撤销一点</button>
                  <button type="button" onClick={resetDraft}>取消草稿</button>
                  <button type="button" className="primary" disabled={!preview?.valid || !waypoints.length}
                    onClick={() => void command({ op: 'route', fleet: fleet.id, mode: editMode, points: waypoints, speed: cruise }, () => {
                      if (editMode === 'sync' || (editMode === 'follow' && waypoints.length >= 2)) learn(editMode);
                      if (fleet.ai.mode === 'auto' && fleet.ai.move) learn('override');
                      resetDraft(); hint('新航线已下达。');
                    })}>下达航线</button>
                </div>
                <details className="speed-setting"><summary>调整航速</summary>
                  <label>航速（节） <input type="number" min={0} max={60} step={1} value={cruise ?? fleet.speed}
                    onChange={(event) => { setPreview(undefined); setCruise(event.target.value === '' ? undefined : Number(event.target.value)); }} /></label>
                </details>
              </div>}
              {(fleet.mode === 'sync' || fleet.notice?.includes('重整')) && !reformPreview && <button type="button" className="reform" disabled={finished || !!replay} onClick={() => void checkReform()}>预览重整纵队</button>}
              {reformPreview && <div className="route-editor">
                <div className="route-progress"><strong>重整纵队</strong><span>{reformPreview.valid ? '航线可用' : '不能重整'}</span></div>
                {reformPreview.error && <p className="inline-warning">{reformPreview.error}</p>}
                <div className="route-tools"><button type="button" onClick={() => setReformPreview(undefined)}>取消</button>
                  <button type="button" className="primary" disabled={!reformPreview.valid} onClick={() => void command({ op: 'reform', fleet: fleet.id }, () => { resetDraft(); hint('重整命令已下达。'); })}>下达重整</button></div>
              </div>}
            </section>
            <section className="roster">
              <div className="section-heading"><h3>编队舰艇</h3><span>舰体状态</span></div>
              {ships.map((ship) => <button key={ship.id} type="button" className="roster-ship" aria-pressed={selected?.id === ship.id} onClick={() => selectShip(ship)}>
                <span className="hull-type">{ship.kind.toUpperCase()}</span>
                <span className="ship-title">{ship.name}{ship.id === fleet.leader && <small>领舰</small>}</span>
                <span className="hull-state" title={ship.hp + ' / ' + ship.maxHp}><i style={{ width: Math.min(100, Math.max(0, 100 * ship.hp / ship.maxHp)) + '%' }} /></span>
              </button>)}
              {selected && selected.fleet === fleet.id && <div className="ship-inspect">
                <span>{selected.hp > 0 ? selected.speed.toFixed(0) + ' 节' : '已失能'} · {selected.ammo} 枚雷</span>
                {selected.hp > 0 && selected.id !== fleet.leader && !replay && !finished && <>
                  <button type="button" onClick={() => void command({ op: 'lead', fleet: fleet.id, ship: selected.id }, () => {
                    learn('lead'); hint('已更换领舰。若领舰不在队首，可先重整或选回队首舰。');
                  })}>设为领舰</button>
                  <button type="button" onClick={() => void command({ op: 'detach', fleet: fleet.id, ship: selected.id }, () => hint('该舰已脱离编队。'))}>脱队</button>
                </>}
              </div>}
            </section>
          </>}
          {tab === 'fleet' && !fleet && <p className="empty-state">当前没有可指挥编队。</p>}
          {tab === 'ai' && fleet && <section className="ai-panel">
            <div className="group-heading"><h2>战术指挥官</h2><span>{fleet.name}</span></div>
            <label>AI 风格 <select value={fleet.ai.profile} disabled={!!replay || finished} onChange={(event) => changeAi({ ...fleet.ai, profile: event.target.value as Profile })}>
              {(Object.entries(profileNames) as [Profile, string][]).map(([id, name]) => <option key={id} value={id} disabled={presetActive && !port.profiles.includes(id)}>{name}</option>)}
            </select></label>
            <p className="field-note">{descriptions[fleet.ai.profile]}</p>
            <label>指挥权限 <select value={fleet.ai.mode} disabled={!!replay || finished} onChange={(event) => {
              const mode = event.target.value as AiConfig['mode'];
              changeAi(mode === 'auto' && !fleet.ai.move && !fleet.ai.gun && !fleet.ai.torpedo ? { ...fleet.ai, mode, move: true, gun: true, torpedo: true } : { ...fleet.ai, mode });
            }}>
              <option value="manual">手动</option><option value="suggest">仅建议</option><option value="auto">选择托管项</option>
            </select></label>
            {fleet.ai.mode === 'auto' && <fieldset><legend>允许 AI 执行</legend>
              {([{ key: 'move', title: '编队机动' }, { key: 'gun', title: '炮击' }, { key: 'torpedo', title: '雷击' }] as const).map(({ key, title }) =>
                <label key={key}><input type="checkbox" checked={fleet.ai[key]} disabled={!!replay || finished}
                  onChange={(event) => changeAi({ ...fleet.ai, [key]: event.target.checked })} /> {title}</label>
              )}
              <p className="field-note">手动下令会接管该项；勾选可交还 AI。</p>
            </fieldset>}
            <button type="button" disabled={finished || !!replay} onClick={() => void askAi()}>查看战术建议</button>
            {suggestion && <div className="suggestion"><p>{suggestion.text}</p>
              {suggestion.orders.length > 0 && <button type="button" onClick={() => void acceptAi()}>采纳建议</button>}
            </div>}
          </section>}
          {tab === 'log' && <section className="battle-log">
            <div className="group-heading"><h2>战情记录</h2><span>本席可见</span></div>
            <div className="log-actions">
              <button type="button" onClick={() => void exportLog()}>导出</button>
              {!replay && <button type="button" disabled={o.tick === 0 || busy} onClick={() => void startReplay()}>重演</button>}
            </div>
            {!latest.length && <p className="empty-state">开始演习后，这里会记录接触、开火与战果。</p>}
            <ol>{latest.map((event, index) =>
              <li key={String(event.tick) + ':' + index} className={'log-event ' + eventTone(event)}>
                <time>{clock(event.tick)}</time><div>{event.text}{event.rule && <small>{event.rule}</small>}</div>
              </li>
            )}</ol>
          </section>}
        </div>
        <footer className="staff-footer">
          <span>{replay ? '复盘模式' : '离线演习'}</span>
          <button type="button" className="text-button" disabled={!!replay || busy} onClick={() => void persist(true)}>保存进度</button>
        </footer>
      </aside>
    </div>
    {dialog && <div className="dialog-backdrop" onPointerDown={(event) => { if (event.target === event.currentTarget && !busy) setDialog(false); }}>
      <section className="setup-dialog" role="dialog" aria-modal="true" aria-label="演习设置">
        <p>虚构昼间演习</p><h2>重新部署舰队</h2>
        <label>所属方 <select value={setup.side} onChange={(event) => setSetup({ ...setup, side: event.target.value as Side })}>
          <option value="allies">同盟舰队</option><option value="axis">轴心舰队</option>
        </select></label>
        <label>对手 AI <select value={setup.enemy} onChange={(event) => setSetup({ ...setup, enemy: event.target.value as Profile })}>
          {(Object.entries(profileNames) as [Profile, string][]).map(([id, name]) => <option key={id} value={id}>{name}</option>)}
        </select></label>
        <label>演习编号 <input type="number" min={0} max={4294967295} value={setup.seed} onChange={(event) => setSetup({ ...setup, seed: Math.max(0, Math.min(4294967295, Math.trunc(Number(event.target.value)))) })} /></label>
        <p className="field-note">开始新演习会替换当前本机进度。</p>
        <div className="actions"><button type="button" onClick={() => setDialog(false)} disabled={busy}>返回</button>
          <button type="button" className="primary" onClick={() => void newExercise()} disabled={busy}>开始新演习</button></div>
      </section>
    </div>}
  </main>;
}

createRoot(document.getElementById('root')!).render(<App />);
