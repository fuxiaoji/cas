import { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { BattleMap } from './BattleMap';
import { alertKind, ShipSchematic } from './BattlePresentation';
import { Harbor } from './Harbor';
import type { HarborTab } from './Harbor';
import { CampaignMissionBrief, CampaignResultSummary, CampaignRewardActions } from './CampaignArchive';
import { CampaignEndingGate } from './campaign-ending/CampaignEndingScene';
import { claimCampaignRewards, recordCampaignResult } from './campaign-progress';
import type { CampaignLaunch } from './campaign-progress';
import { campaignObservationLabels, campaignText } from './campaign-labels';
import { GrowthPort } from './GrowthPort';
import type { LobbySection } from './GrowthPort';
import { Login } from './Login';
import { useBattleVoice } from './audio/BattleVoice';
import { useOriginalScore } from './audio/OriginalScore';
import { ActivityCenter } from './activities/ActivityCenter';
import { recordChallengeClear } from './activities/week';
import { PrologueScene, completePrologueBattle, loadPrologue, savePrologue, PROLOGUE_STORAGE_KEY } from './prologue';
import type { StarterDDId } from './prologue';
import { PROLOGUE_HANDOVER_TICK } from './prologue/PrologueFilm';
import { guidedTrainingDone, recordGuidedTrainingSignals, TrainingCoach, trainingCourseDone } from './tutorial';
import type { CourseId, TrainingEvidence, TrainingSignal } from './tutorial';
import { profileKey } from './account';
import type { LocalProfile } from './account';
import { battlePath, OnlineError, onlineBattlePath, onlineMeta, onlineRequest, rankedBudgetTitle, rankedVoided } from './online';
import type { OnlineBattle, OnlineBattleClaim, OnlineBattleSummary, OnlineDuel, OnlineMeta } from './online';
import { OnlineSupply } from './OnlineSupply';
import { OnlineFleetEditor } from './OnlineFleetEditor';
import { OnlineDuelLobby } from './OnlineDuelLobby';
import { ask, clock, closeSession, maneuverNames, profileNames, sideNames } from './engine';
import type { AiConfig, LogEvent, Maneuver, Observation, Point, Profile, Request, Result, RoutePreview, Ship, Side, Suggestion, TorpedoSettings, Weapon } from './engine';
import { grantPrologue, hulls, lessons, loadPort, PORT_KEY, recordLesson, writePort } from './port';
import type { Hull, Lesson, PortLaunch } from './port';
import './style.css';

const SAVE_KEY = 'cas.exercise.autosave.v1';
const options = [1, 2, 4, 8] as const;
type Speed = typeof options[number];
type Tab = 'fleet' | 'ship' | 'ai' | 'log';
interface Replay { data: unknown; end: number }
const defaultSetup = { seed: 6106, side: 'allies' as Side, enemy: 'gunnery' as Profile, variant: '' as '' | 'night' | 'radar', realtime: true };
type LightPreview = { valid: boolean; error?: string; mount?: number };
const aimAction: Record<Weapon, string> = { gun: '炮击', torpedo: '雷击' };
const hullNames = { dd: '驱逐舰', cl: '轻巡洋舰', bb: '战列舰' };
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
  if (alertKind(event)) return 'strike';
  if (/gun|torpedo|fire/i.test(event.kind)) return 'fire';
  if (/order|route|accepted/i.test(event.kind)) return 'order';
  return 'plain';
}

function App({ profile, onLogout }: { profile: LocalProfile; onLogout: () => void }) {
  const accountSaveKey = profileKey(profile, SAVE_KEY);
  const accountPortKey = profileKey(profile, PORT_KEY);
  const storyKey = profileKey(profile, PROLOGUE_STORAGE_KEY);
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
  const [seenCampaignEndings, setSeenCampaignEndings] = useState<ReadonlySet<string>>(() => new Set());
  const [session, setSession] = useState(0);
  const [port, setPort] = useState(() => loadPort(accountPortKey));
  const [cloudMeta, setCloudMeta] = useState<OnlineMeta>();
  const [cloudError, setCloudError] = useState<string>();
  const [cloudBattle, setCloudBattle] = useState<OnlineBattle | OnlineDuel>();
  const [onlineList, setOnlineList] = useState<OnlineBattleSummary[]>();
  const [cloudClaimed, setCloudClaimed] = useState(false);
  const [confirmSurrender, setConfirmSurrender] = useState(false);
  const cloud = useRef<OnlineBattle | OnlineDuel | undefined>(undefined);
  const cloudSending = useRef(false);
  const cloudPending = useRef(new Map<string, { request_id: string; revision: number }>());
  const cloudLaunch = useRef<{ stageId: string; difficulty: string; id: string } | undefined>(undefined);
  const cloudToken = profile.online?.token;
  const [portOpen, setPortOpen] = useState(true);
  const [section, setSection] = useState<HarborTab | 'activities' | 'fleet-editor' | 'duel'>();
  const [duelTab, setDuelTab] = useState<'casual' | 'ranked'>('casual');
  const [mainMenu, setMainMenu] = useState(false);
  const [portError, setPortError] = useState<string>();
  const [training, setTraining] = useState(false);
  const [storyOpen, setStoryOpen] = useState(false);
  const [story, setStory] = useState(() => loadPrologue(storyKey));
  const storyLive = useRef(false);
  const storyBattleKey = storyKey + ':battle';
  const [course, setCourse] = useState<CourseId>();
  const [evidence, setEvidence] = useState<TrainingEvidence>({});
  const [nightTarget, setNightTarget] = useState('');
  const [lightPreview, setLightPreview] = useState<LightPreview>();
  const [torpedoSettings, setTorpedoSettings] = useState<Record<number, TorpedoSettings>>({});
  const courseLive = useRef<CourseId | undefined>(undefined);
  const courseEvent = useRef(0);
  const savedExercise = useRef<unknown>(undefined);
  const challengeId = useRef<string | undefined>(undefined);
  const campaignId = useRef<string | undefined>(undefined);
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
  const onlineDuel = cloudBattle && 'match_id' in cloudBattle ? cloudBattle : undefined;
  const duelVoided = onlineDuel ? rankedVoided(onlineDuel) : false;
  const result = o?.result;
  const finished = Boolean(result) || duelVoided;
  const nightRadar = o?.variant === 'night-radar-training';
  const guided = nightRadar || o?.variant === 'prologue';
  const radioKey = profile.id + ':fleet-radio';
  const radio = useBattleVoice({ session, observation: o, live: !portOpen, replaying: !!replay,
    paused: !cloudBattle && !running && !finished, settingsKey: radioKey });
  const contactCount = (o?.contacts.length ?? 0) + (o?.radarContacts?.length ?? 0);
  const music = useOriginalScore({ settingsKey: profile.id + ':score',
    scene: storyOpen ? 'prologue' : portOpen || replay ? 'off' : result ? (result.winner === o?.side ? 'victory' : 'defeat')
      : contactCount ? 'engagement' : 'maneuver' });

  function record(...signals: TrainingSignal[]) {
    const active = courseLive.current;
    if (!active || !signals.length) return;
    setEvidence((value) => guided ? recordGuidedTrainingSignals(active, value, signals, { radar: nightRadar })
      : signals.every(signal => value[signal]) ? value :
      { ...value, ...Object.fromEntries(signals.map(signal => [signal, true])) });
  }

  function hint(message: string) {
    window.clearTimeout(noticeTimer.current);
    setNotice(o?.campaign ? campaignText(message) : message);
    noticeTimer.current = window.setTimeout(() => setNotice(''), 4200);
  }
  function update(observation: Observation, live = true) {
    clockTick.current = observation.tick;
    setObservation(campaignObservationLabels(observation));
    if (observation.result) setRunning(false);
    if (live && courseLive.current) {
      const trainingIds = observation.fleets[0]?.members ?? [];
      const newEvents = observation.events.filter(event => Number(event.id) > courseEvent.current);
      courseEvent.current = Math.max(courseEvent.current, ...newEvents.map(event => Number(event.id)));
      const kinds = new Set(newEvents.filter(event => observation.variant !== 'prologue'
        || event.own_ship !== undefined && trainingIds.includes(event.own_ship)).map(event => event.kind));
      const events: TrainingSignal[] = [];
      if (kinds.has('gun')) events.push('gunFired');
      if (kinds.has('torpedo')) events.push('torpedoFired');
      if (kinds.has('illumination')) events.push('lightApplied');
      if (observation.result) events.push('finished');
      record(...events);
    }
    if (live && observation.variant === 'challenge' && observation.result?.primary) {
      const id = challengeId.current;
      const now = Date.now();
      setPort((state) => recordChallengeClear(state, id, now));
    }
    if (live && !courseLive.current && campaignId.current && observation.campaign && observation.result?.grade) {
      const campaign = observation.campaign;
      const outcome = observation.result;
      setPort(state => recordCampaignResult(state, campaign, outcome));
    }
  }
  function learn(id: Lesson) {
    if (!replay && (!o?.variant || courseLive.current === 'day')) setPort((state) => recordLesson(state, id));
  }
  function resetDraft() { setEditMode(undefined); setWaypoints([]); setCruise(undefined); setPreview(undefined); setReformPreview(undefined); }
  function resetPanel() {
    setSession((value) => value + 1);
    resetDraft(); setFleetId(undefined); setShipId(undefined); setSuggestion(undefined);
    setTab('fleet'); setRunning(false); setReplay(undefined); setResultDismissed(false); setConfirmSurrender(false);
    setNightTarget(''); setLightPreview(undefined);
    setTorpedoSettings({});
    window.clearTimeout(noticeTimer.current);
    setNotice('');
    timeAccumulator.current = 0;
  }
  async function persist(toast = false) {
    if (courseLive.current || storyLive.current || cloud.current) return;
    const id = challengeId.current;
    const localCampaignId = campaignId.current;
    try {
      const data = await ask<Record<string, unknown>>({ op: 'save' });
      localStorage.setItem(accountSaveKey, JSON.stringify(id && data.variant === 'challenge'
        ? { ...data, localChallengeId: id }
        : localCampaignId && data.campaign ? { ...data, localCampaignId } : data));
      lastSave.current = typeof data.tick === 'number' ? data.tick : clockTick.current;
      if (toast) hint('演习已保存，下次打开可继续。');
    } catch (error) { if (toast) hint('保存失败：' + errorText(error)); }
  }

  useEffect(() => {
    if (initialized.current) return;
    initialized.current = true;
    void (async () => {
      try {
        try {
          const saved = localStorage.getItem(accountSaveKey);
          if (saved) {
            const { localChallengeId, localCampaignId, ...save } = JSON.parse(saved);
            const observation = await ask<Observation>({ op: 'load', save });
            if (observation.variant === 'challenge' && typeof localChallengeId === 'string' && /^[0-9a-f-]{36}$/i.test(localChallengeId)) {
              challengeId.current = localChallengeId;
            }
            if (observation.campaign && typeof localCampaignId === 'string' && /^[0-9a-f-]{36}$/i.test(localCampaignId)) {
              campaignId.current = localCampaignId;
            }
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
    try { writePort(port, accountPortKey); }
    catch { hint('本机无法保存母港进度。'); }
  }, [port]);
  useEffect(() => {
    if (!cloudToken) return;
    let live = true;
    void onlineMeta(cloudToken).then(value => { if (live) setCloudMeta(value); },
      err => { if (live) setCloudError(errorText(err)); });
    return () => { live = false; };
  }, [cloudToken]);
  function syncBattle(next: OnlineBattle | OnlineDuel, open = false) {
    const old = cloud.current;
    if (!open && (!old || onlineBattlePath(old) !== onlineBattlePath(next) || old.revision > next.revision
      || old.view.tick > next.view.tick || (old.status === 'complete' && next.status !== 'complete'))) return;
    cloud.current = next; setCloudBattle(next);
    update(next.view, false);
  }
  function clearCloud() {
    cloud.current = undefined; setCloudBattle(undefined); setCloudClaimed(false); cloudPending.current.clear();
  }
  async function inspectBattle<T>(request: Request): Promise<T> {
    const active = cloud.current;
    if (!active || !cloudToken) return ask<T>(request);
    return onlineRequest<T>(onlineBattlePath(active) + '/inspect', cloudToken, { command: request });
  }
  async function sendBattle(request: Request) {
    const active = cloud.current;
    if (!active || !cloudToken) return update(await ask<Observation>(request));
    if (cloudSending.current) throw new Error('上一条联机命令正在确认。');
    cloudSending.current = true;
    const path = onlineBattlePath(active);
    const key = path + ':' + JSON.stringify(request);
    const attempt = cloudPending.current.get(key) ?? { request_id: crypto.randomUUID(), revision: active.revision };
    cloudPending.current.set(key, attempt);
    try {
      const next = await onlineRequest<OnlineBattle | OnlineDuel>(path + '/commands', cloudToken,
        { ...attempt, command: request });
      cloudPending.current.delete(key); syncBattle(next);
    } catch (e) {
      if (e instanceof OnlineError && e.status && e.status < 500) cloudPending.current.delete(key);
      if (e instanceof OnlineError && e.status === 409) {
        const next = await onlineRequest<OnlineBattle | OnlineDuel>(path, cloudToken).catch(() => undefined);
        if (next) syncBattle(next);
      }
      throw e;
    } finally { cloudSending.current = false; }
  }
  const cloudPath = cloudBattle && onlineBattlePath(cloudBattle);
  useEffect(() => {
    if (!cloudToken || !cloudPath || portOpen || cloudBattle?.status === 'complete') return;
    let cancelled = false; let fetching = false; let showedError = false;
    const interval = window.setInterval(() => {
      if (fetching || cloudSending.current || document.hidden) return;
      fetching = true;
      void onlineRequest<OnlineBattle | OnlineDuel>(cloudPath, cloudToken).then(next => {
        if (!cancelled) { syncBattle(next); if (showedError) hint('已恢复联机战局。'); showedError = false; }
      }, error => {
        if (!cancelled && !showedError) { hint(errorText(error)); showedError = true; }
      }).finally(() => { fetching = false; });
    }, 450);
    return () => { cancelled = true; window.clearInterval(interval); };
  }, [cloudToken, cloudPath, cloudBattle?.status, portOpen]);
  useEffect(() => {
    try { savePrologue(story, storyKey); }
    catch { setPortError('本机无法保存序章进度。'); }
  }, [story, storyKey]);

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
        update(observation, !replay);
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
      void inspectBattle<RoutePreview>({ op: 'preview_route', fleet: fleet.id, mode: editMode, points: waypoints, speed: cruise })
        .then((value) => { if (active) {
          setPreview(value);
          if (value.valid && (editMode === 'sync' || waypoints.length >= 2)) record(editMode === 'follow' ? 'followPreview' : 'syncPreview');
        } },
          (error) => { if (active) setPreview({ valid: false, paths: [], speed: cruise ?? fleet.speed, error: errorText(error) }); });
    }, 65);
    return () => { active = false; window.clearTimeout(timer); };
  }, [fleet?.id, editMode, waypoints, cruise, refreshAt, replay]);

  useEffect(() => {
    if (!(o?.variant === 'night-training' || nightRadar) || !selected || !nightTarget || !o.contacts.some(c => c.id === nightTarget) || replay) {
      setLightPreview(undefined); return;
    }
    let active = true;
    void ask<LightPreview>({ op: 'illumination_preview', ship: selected.id, target: nightTarget })
      .then(value => { if (active) setLightPreview(value); }, error => { if (active) setLightPreview({ valid: false, error: errorText(error) }); });
    return () => { active = false; };
  }, [o?.variant, selected?.id, nightTarget, refreshAt, replay, o?.events.at(-1)?.id]);

  async function command(request: Request, after?: () => void) {
    if (replay || finished) return;
    try {
      await sendBattle(request);
      after?.();
      void persist();
    } catch (error) { hint(errorText(error)); }
  }

  function selectShip(ship: Ship) {
    if (o?.variant === 'prologue' && ship.fleet !== 1) {
      hint('其他编队由总指挥调度。请指挥第五驱逐小队。');
      return;
    }
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
    record('routePoint');
  }
  function chooseMode(mode: Maneuver) {
    if (editMode === mode) return;
    setReformPreview(undefined);
    setPreview(undefined);
    setEditMode(mode);
    record(mode === 'follow' ? 'followMode' : 'syncMode');
  }
  async function checkReform() {
    if (!fleet) return;
    resetDraft();
    try { setReformPreview(await inspectBattle<RoutePreview>({ op: 'preview_reform', fleet: fleet.id })); }
    catch (error) { hint(errorText(error)); }
  }
  function changeAi(config: AiConfig) {
    if (!fleet) return;
    setSuggestion(undefined);
    void command({ op: 'ai', fleet: fleet.id, ...config });
  }
  async function askAi() {
    if (!fleet) return;
    try { setSuggestion(await inspectBattle<Suggestion>({ op: 'suggest', fleet: fleet.id })); }
    catch (error) { hint(errorText(error)); }
  }
  async function acceptAi() {
    if (!suggestion || replay) return;
    try {
      for (const order of suggestion.orders) await sendBattle(order);
      hint('已采纳战术建议。'); setSuggestion(undefined); void persist();
    } catch (error) { hint('建议未能全部执行：' + errorText(error)); setSuggestion(undefined); }
  }
  async function newExercise() {
    setBusy(true); setRunning(false);
    try {
      const next = await ask<Observation>({ op: 'new', ...setup });
      challengeId.current = undefined;
      campaignId.current = undefined;
      await persist();
      resetPanel(); update(next); setDialog(false); setTraining(false); setPresetActive(false);
    } catch (error) { hint(errorText(error)); }
    finally { setBusy(false); }
  }
  async function oneStep() {
    if (busy || !o || o.result || inFlight.current) return;
    if (running) { setRunning(false); record('paused'); }
    setBusy(true);
    try {
      if (replay) update(await ask<Observation>({ op: 'replay', save: replay.data, tick: Math.min(replay.end, o.tick + 1) }), false);
      else {
        const next = await ask<Observation>({ op: 'step', seconds: 1 });
        update(next); record('stepped'); if (next.result) void persist();
      }
    } catch (error) { hint(errorText(error)); }
    finally { setBusy(false); }
  }
  async function nextNightWindow() {
    if (!nightRadar || busy || !o || o.result || inFlight.current) return;
    setBusy(true); setRunning(false);
    try { update(await ask<Observation>({ op: 'step', seconds: 180 - o.tick % 180 })); }
    catch (error) { hint(errorText(error)); }
    finally { setBusy(false); }
  }
  async function startReplay() {
    if (!o || busy) return;
    setRunning(false); setBusy(true); setResultDismissed(true);
    try {
      const data = await ask<unknown>({ op: 'save' });
      const initial = await ask<Observation>({ op: 'replay', save: data, tick: 0 });
      setReplay({ data, end: o.tick }); update(initial, false); resetDraft();
    } catch (error) { hint(errorText(error)); }
    finally { setBusy(false); }
  }
  async function replayAt(tick: number) {
    if (!replay) return;
    setRunning(false);
    try { update(await ask<Observation>({ op: 'replay', save: replay.data, tick }), false); }
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
      const report = replay ? { result: o.result, events: o.events } : cloud.current && cloudToken ?
        await onlineRequest<{ result: Result | null; events: LogEvent[] }>(onlineBattlePath(cloud.current) + '/report', cloudToken) :
        await ask<{ result: Result | null; events: LogEvent[] }>({ op: 'report' });
      const title = ['CAS 海图指挥台', o.scenario, sideNames[o.side], '模拟时间 ' + clock(o.tick)];
      const rows = report.events.map((event) => [clock(event.tick), o.campaign ? campaignText(event.text) : event.text, event.rule ?? ''].filter(Boolean).join('  '));
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
    if (running) record('paused');
    setRunning((value) => !value);
  }
  function openSetup() { setRunning(false); setSetup((current) => ({ ...current, variant: o?.variant === 'night' ? 'night' : o?.variant === 'radar' ? 'radar' : '' })); setDialog(true); }
  async function openStory() {
    if (busy || !o || storyLive.current) return;
    setBusy(true); setRunning(false); setPortError(undefined);
    try {
      const previous = await ask<unknown>({ op: 'save' });
      let observation: Observation | undefined;
      if (story.step > 0) {
        try {
          const save = JSON.parse(localStorage.getItem(storyBattleKey) ?? 'null');
          if (save?.variant === 'prologue') observation = await ask<Observation>({ op: 'load', save });
        } catch { /* Reopen the handover when an earlier story has no compatible battle. */ }
      }
      if (!observation) {
        await ask({ op: 'new', ...defaultSetup, variant: 'prologue' });
        observation = await ask<Observation>({ op: 'step', seconds: PROLOGUE_HANDOVER_TICK });
      }
      savedExercise.current = previous; storyLive.current = true;
      resetPanel(); update(observation); setStoryOpen(true);
    } catch (error) { setPortError(errorText(error)); }
    finally { setBusy(false); }
  }
  async function saveStoryBattle() {
    localStorage.setItem(storyBattleKey, JSON.stringify(await ask({ op: 'save' })));
  }
  async function closeStory() {
    if (!storyLive.current || busy) return;
    setBusy(true); setRunning(false);
    try {
      await saveStoryBattle();
      const next = await ask<Observation>({ op: 'load', save: savedExercise.current });
      storyLive.current = false; savedExercise.current = undefined;
      resetPanel(); update(next); setStoryOpen(false); setPortError(undefined);
    } catch (error) { setPortError(errorText(error)); }
    finally { setBusy(false); }
  }
  async function startCourse(id: CourseId, side: Side = 'allies', leader?: StarterDDId) {
    if (busy || !o || courseLive.current) return;
    setBusy(true); setRunning(false); setPortError(undefined);
    try {
      let next: Observation;
      if (leader && storyLive.current && o.variant === 'prologue') {
        const chosen = o.ships.find(ship => ship.characterId === leader);
        const squadron = o.fleets[0];
        next = id === 'follow' && o.tick === PROLOGUE_HANDOVER_TICK && chosen && squadron.leader !== chosen.id
          ? await ask<Observation>({ op: 'lead', fleet: squadron.id, ship: chosen.id }) : o;
      } else {
        savedExercise.current = await ask<unknown>({ op: 'save' });
        next = await ask<Observation>({ op: 'new', ...defaultSetup, side, variant: id === 'night' ? 'night-radar-training' : '' });
      }
      clearCloud();
      setEvidence({}); courseLive.current = id; courseEvent.current = Math.max(0, ...next.events.map(event => Number(event.id) || 0)); setCourse(id);
      resetPanel(); update(next); setPortOpen(false); setStoryOpen(false); setTraining(false); setPresetActive(false);
    } catch (error) { setPortError(errorText(error)); }
    finally { setBusy(false); }
  }
  async function leaveCourse(complete: boolean) {
    const id = courseLive.current;
    const done = id && (guided ? guidedTrainingDone(id, evidence, { radar: nightRadar }) : trainingCourseDone(id, evidence));
    if (!id || busy || (complete && !done)) return;
    setRunning(false); setBusy(true);
    try {
      if (storyLive.current) {
        if (complete) await saveStoryBattle();
        courseLive.current = undefined; setCourse(undefined);
        resetPanel(); setPortOpen(true); setSection(undefined); setStoryOpen(true);
        if (complete && id !== 'day' && id !== 'night') setStory(progress => completePrologueBattle(progress, id));
        return;
      }
      const saved = savedExercise.current;
      const exercise = saved ? await ask<Observation>({ op: 'load', save: saved }) : await ask<Observation>({ op: 'new', ...defaultSetup });
      courseLive.current = undefined; savedExercise.current = undefined;
      resetPanel(); update(exercise); setCourse(undefined); setPortOpen(true);
      if (id === 'day' || id === 'night') {
        setSection('training');
        if (complete) setPort(state => state.courses.includes(id) ? state : { ...state, courses: [...state.courses, id] });
      } else {
        setSection(undefined); setStoryOpen(true);
        if (complete) setStory(progress => completePrologueBattle(progress, id));
      }
      void persist();
    } catch (error) { hint('未能返回：' + errorText(error)); }
    finally { setBusy(false); }
  }
  async function launchFromHarbor(launch: PortLaunch) {
    setBusy(true); setPortError(undefined);
    try {
      const { training: isTraining, ...options } = launch;
      const next = await ask<Observation>({ op: 'new', ...defaultSetup, ...options });
      clearCloud();
      challengeId.current = options.variant === 'challenge' ? crypto.randomUUID() : undefined;
      campaignId.current = undefined;
      await persist();
      resetPanel(); update(next); setPortOpen(false); setTraining(!!isTraining); setPresetActive(!isTraining && launch.variant !== 'night');
    } catch (error) { setPortError(errorText(error)); }
    finally { setBusy(false); }
  }
  async function launchCampaign({stageId, difficulty}: CampaignLaunch) {
    if (busy) return;
    setBusy(true); setPortError(undefined); setRunning(false);
    try {
      if (cloudToken) {
        const previous = cloudLaunch.current;
        const id = previous?.stageId === stageId && previous.difficulty === difficulty ? previous.id : crypto.randomUUID();
        cloudLaunch.current = { stageId, difficulty, id };
        let next: OnlineBattle;
        try {
          next = await onlineRequest<OnlineBattle>('/battles', cloudToken, { request_id: id, stage_id: stageId, difficulty });
        } catch (e) {
          if (e instanceof OnlineError && e.status && e.status < 500) cloudLaunch.current = undefined;
          throw e;
        }
        cloudLaunch.current = undefined; setCloudClaimed(false); cloudPending.current.clear();
        resetPanel(); syncBattle(next, true); setPortOpen(false); setTraining(false); setPresetActive(false);
        return;
      }
      const next = await ask<Observation>({ op: 'new_campaign', id: stageId, difficulty, seed: defaultSetup.seed, profile: port.preset.profile });
      challengeId.current = undefined;
      campaignId.current = crypto.randomUUID();
      await persist();
      resetPanel(); update(next); setPortOpen(false); setTraining(false); setPresetActive(false);
    } catch (error) { setPortError(errorText(error)); }
    finally { setBusy(false); }
  }
  async function resumeCloud(id: string) {
    if (!cloudToken || busy) return;
    setBusy(true); setCloudError(undefined);
    try {
      const next = await onlineRequest<OnlineBattle>(battlePath(id), cloudToken);
      resetPanel(); setCloudClaimed(false); syncBattle(next, true); setTraining(false); setPresetActive(false);
      setPortOpen(false); setMainMenu(false);
    } catch (e) { setCloudError(errorText(e)); } finally { setBusy(false); }
  }
  async function openMainMenu() {
    setMainMenu(true);
    if (!cloudToken) return;
    try { setOnlineList(await onlineRequest<OnlineBattleSummary[]>('/battles', cloudToken)); }
    catch (e) { setCloudError(errorText(e)); }
  }
  async function claimCloud() {
    const active = cloud.current;
    if (!active || 'match_id' in active || !cloudToken || busy) return;
    setBusy(true);
    try {
      const claim = await onlineRequest<OnlineBattleClaim>(battlePath(active.battle_id) + '/claim', cloudToken,
        { request_id: 'stage-claim-' + active.battle_id });
      setCloudMeta(claim.meta); setCloudClaimed(true);
      hint(claim.claimed ? '联机战役奖励已入账。' : '本局没有新的星级奖励。');
    } catch (e) { hint(errorText(e)); } finally { setBusy(false); }
  }
  function openDuel(next: OnlineDuel) {
    clearCloud(); resetPanel(); syncBattle(next, true);
    setSection(undefined); setPortOpen(false); setMainMenu(false); setTraining(false); setPresetActive(false);
  }
  function returnToDuelLobby() {
    openPort(); setSection('duel'); setConfirmSurrender(false);
  }
  async function surrenderDuel() {
    if (!onlineDuel || !cloudToken || busy || cloudSending.current || finished) return;
    const path = onlineBattlePath(onlineDuel) + '/surrender';
    const attempt = cloudPending.current.get(path) ?? { request_id: crypto.randomUUID(), revision: onlineDuel.revision };
    cloudPending.current.set(path, attempt);
    cloudSending.current = true; setBusy(true);
    try {
      syncBattle(await onlineRequest<OnlineDuel>(path, cloudToken, { request_id: attempt.request_id }));
      cloudPending.current.delete(path); setConfirmSurrender(false);
    } catch (error) {
      if (error instanceof OnlineError && error.status && error.status < 500) cloudPending.current.delete(path);
      hint(errorText(error));
    } finally { cloudSending.current = false; setBusy(false); }
  }
  function navigateLobby(value: LobbySection) {
    const sections = { academy: 'training', campaign: 'archive', challenge: 'challenge', fleet: 'fleet', economy: 'recruit', activities: 'activities' } as const;
    setPortError(undefined); setSection(sections[value]);
  }
  function openPort() {
    if (courseLive.current) { void leaveCourse(false); return; }
    setRunning(false); setPortError(undefined); setSection(undefined); setPortOpen(true);
  }
  function showTab(next: Tab) {
    setTab(next);
    if (next === 'fleet') record('fleetViewed');
    if (next === 'log') record('reportViewed');
    if (next === 'ship') record('radarViewed');
  }
  const tabs: { key: Tab; title: string }[] = [
    { key: 'fleet', title: '编队' }, { key: 'ship', title: '舰况' }, { key: 'ai', title: '战术 AI' }, { key: 'log', title: '战情' },
  ];
  const fire = (ship: number, weapon: Weapon, target: string, heading?: number, torpedo?: TorpedoSettings) => {
    void command({ op: 'fire', ship, weapon, target, heading, ...torpedo }, () => {
      hint(weapon === 'gun' && o?.realtimeGunnery ? '已下达炮击命令，炮座转向并装填完成后各自发射。' :
        '已下达' + aimAction[weapon] + '命令，执行进度见战情。');
      if (weapon === 'gun' || heading !== undefined) learn(weapon);
      if (weapon === 'gun') record('gunOrdered');
      else record('torpedoAimed', 'torpedoOrdered', ...(heading === undefined ? [] : ['torpedoAdjusted' as const]));
      if (fleet?.ai.mode === 'auto' && fleet.ai[weapon]) { learn('override'); record('override'); }
    });
  };

  if (portOpen) {
    if (cloudToken && section === 'duel') return <OnlineDuelLobby token={cloudToken} initialTab={duelTab}
      onBack={() => setSection(undefined)} onBattle={openDuel} />;
    if (cloudToken && section === 'fleet-editor') return <OnlineFleetEditor token={cloudToken}
      onBack={() => setSection('fleet')} onRanked={() => { setDuelTab('ranked'); setSection('duel'); }} />;
    if (cloudToken && (section === 'recruit' || section === 'fleet')) return <OnlineSupply key={section} token={cloudToken}
      meta={cloudMeta} onMeta={meta => {setCloudMeta(meta);setCloudError(undefined);}}
      onBack={() => setSection(undefined)} onFleetEditor={() => setSection('fleet-editor')}
      initialTab={section === 'fleet' ? 'fleet' : 'recruit'} />;
    if (storyOpen) return <PrologueScene progress={story} onProgress={setStory} busy={busy || !o} radioKey={radioKey}
      battle={o?.variant === 'prologue' ? o : undefined}
      error={portError ?? loadError} claimed={port.prologueReward}
      rewards={['同盟演习舰队（首次领取初始舰队时）', '补给币 2,000', '常驻券与 UP 券各 10 张（首次领取初始舰队时）']}
      onBattle={(stage, leader) => void startCourse(stage, 'allies', leader)}
      onFinish={async () => { setPort(grantPrologue); await closeStory(); }}
      onExit={() => void closeStory()} />;
    if (section === 'activities') return <ActivityCenter state={port} change={setPort} onClose={() => setSection(undefined)}
      online={cloudToken ? {token:cloudToken,onMeta:meta => {setCloudMeta(meta);setCloudError(undefined);}} : undefined} />;
    if (section && section !== 'fleet-editor' && section !== 'duel') return <Harbor key={section} initialTab={section} state={port} change={setPort} onReturn={() => setSection(undefined)} onLaunch={(options) => void launchFromHarbor(options)} onCampaign={(options) => void launchCampaign(options)} onCourse={(id, side) => void startCourse(id, side)} busy={busy || !o} error={portError} online={!!cloudToken} />;
    return <>
      <GrowthPort state={port} onNavigate={navigateLobby} onHome={() => void openMainMenu()}
        online={cloudToken ? {meta:cloudMeta,error:cloudError} : undefined}
        onReplayPrologue={() => void openStory()}
        onWatch={id => setPort(s => Object.hasOwn(hulls,id) && (s.owned[id as Hull] ?? 0) > 0 ? { ...s, watch: id as Hull } : s)} />
      {mainMenu && <div className="dialog-backdrop" onClick={e=>{if(e.target===e.currentTarget)setMainMenu(false);}}>
        <section className="setup-dialog" role="dialog" aria-modal="true" aria-label="主菜单">
          <h2>主菜单</h2><p className="field-note">当前指挥官：{profile.name}</p>
          {loadError && <p role="alert">无法打开海图：{loadError}</p>}
          {cloudError && <p role="status">{cloudError}</p>}
          {cloudToken && !!onlineList?.length && <div className="online-battle-list" aria-label="我的联机战役">
            {onlineList.slice(0, 8).map(battle => <button type="button" key={battle.battle_id} disabled={busy}
              onClick={() => void resumeCloud(battle.battle_id)}>
              {battle.status === 'active' ? '继续战役' : '查看战果'} · {battle.stage_id.includes('ALLIES') ? '同盟' : '轴心'} · {clock(battle.tick)}
            </button>)}
          </div>}
          <div className="actions">
            <button type="button" onClick={()=>setMainMenu(false)}>返回母港</button>
            {cloudToken && <button type="button" onClick={() => { setMainMenu(false); setSection('duel'); }}>线上舰桥</button>}
            {!cloudBattle && <button type="button" className="primary" disabled={!o || busy} onClick={()=>{setMainMenu(false);setPortOpen(false);}}>继续演习</button>}
            <button type="button" onClick={onLogout}>退出登录</button>
          </div>
        </section>
      </div>}
    </>;
  }
  if (!o) return <main className="startup">
    <Mark /><h1>海图指挥台</h1>
    <p>{loadError ? '无法开始演习：' + loadError : '正在打开演习海图…'}</p>
    {loadError && <button type="button" onClick={() => location.reload()}>重新打开</button>}
  </main>;

  const latest = [...o.events].reverse();
  const winner = result?.winner === 'allies' || result?.winner === 'axis' ? sideNames[result.winner] + '胜出' : '双方打平';
  const endingKey = cloud.current ? onlineBattlePath(cloud.current) : (campaignId.current ?? 'session-' + session);
  const editing = !!editMode && !replay && !finished;
  const courseDone = course && (guided ? guidedTrainingDone(course, evidence, { radar: nightRadar }) : trainingCourseDone(course, evidence));
  const nextLesson = training && lessons.find(({ id }) => !port.lessons.includes(id));
  return <main className={'command-shell' + (o.environment?.light === 'night' ? ' night-exercise' : '')}>
    <header className="masthead">
      <div className="brand"><Mark /><div><span>CAS 战术演习</span><h1>海图指挥台</h1></div></div>
      <div className="exercise-label"><span className="live-dot" data-active={running} />
        {replay ? '战局重演' : finished ? '战局结束' : o.settling ? '末批炮弹飞行中' :
          onlineDuel ? (onlineDuel.mode === 'ranked' ? '排位战进行中 · ' + (onlineDuel.budget ?? 0) + ' 分' : '线上约战进行中') :
          cloudBattle ? '联机战役进行中' : running ? '演习进行中' : '演习暂停'}
        {o.realtimeGunnery && <small className="realtime-badge">实时主炮</small>}</div>
      <div className="clock-deck">
        <span className="time"><strong>{clock(o.tick)}</strong><small> / {clock(replay?.end ?? o.limit)}</small></span>
        {cloudBattle ? <span className="field-note">联机时钟 · 4×</span> : <><button className="clock-play" type="button" aria-label={running ? '暂停演习' : '开始演习'} onClick={toggleClock} disabled={busy || (finished && !replay)}>
          <span aria-hidden="true">{running ? 'Ⅱ' : '▶'}</span>{running ? '暂停' : '开始'}
        </button>
        <button className="clock-step" type="button" aria-label="推进一秒" title="推进一模拟秒" onClick={() => void oneStep()} disabled={busy || finished}>▹▏</button>
        <div className="speeds" aria-label="演习倍速">{options.map((value) =>
          <button key={value} type="button" aria-pressed={speed === value} onClick={() => setSpeed(value)}>{value}×</button>
        )}</div></>}
      </div>
      <div className="header-actions">
        {!course && !cloudBattle && <button type="button" className="new-exercise" onClick={openSetup} aria-label="演习设置">演习设置</button>}
        <button type="button" className="harbor-link" disabled={busy} onClick={onlineDuel ? returnToDuelLobby : openPort}>{course ? '退出课程' : onlineDuel ? '线上舰桥' : '母港'}</button>
      </div>
    </header>
    <div className="workspace">
      <section className="chart-column">
        <BattleMap
          observation={o} fleet={fleet} selected={selected?.id} disabled={busy || !!replay || finished}
          cameraCue={o.variant === 'prologue' ? { id: '第五驱逐小队', fleet: 1, zoom: 1.22 } : undefined}
          session={session} running={cloudBattle ? !finished : running} speed={cloudBattle ? 4 : speed} replaying={!!replay}
          requestAim={inspectBattle}
          torpedoSettings={o.torpedoDepths ? torpedoSettings : undefined}
          editing={editing} waypoints={waypoints} preview={preview} reformPreview={reformPreview} onSelect={selectShip} onAddPoint={addPoint}
          onMovePoint={movePoint} onFire={fire} onCancelFire={() => { learn('cancel'); record('fireCancelled'); }} onHint={hint}
          onTorpedoAim={(adjusted) => record(adjusted ? 'torpedoAdjusted' : 'torpedoAimed')}
          onInspectMap={course ? () => record('mapViewed') : undefined}
          onInspectContact={course === 'night' ? (id) => {
            if (id.startsWith('R')) {
              if (o.radarContacts?.find(contact => contact.id === id)?.usableForShipIds.includes(selected?.id ?? -1)) {
                record('radarContactViewed');
                hint('已检查本舰直接取得的雷达回波。');
              } else hint('这处位置来自友舰共享。请选择本舰直接取得的雷达回波。');
            } else { setNightTarget(id); record('contactViewed'); }
          } : undefined}
        />
        <div className="signal-strip">
          <span className="side-tag">{sideNames[o.side]}</span>
          <span>可见接触 <b>{contactCount}</b></span>
          <span className={'signal-last' + (training ? ' lesson-signal' : '')} title={nextLesson ? nextLesson.detail : latest[0]?.text}>
            {training ? nextLesson ? '实操 · ' + nextLesson.detail : '实操完成 · 回母港领取初始舰队。' :
              latest[0] ? clock(latest[0].tick) + '  ' + latest[0].text : '出航后，命令与战斗事件会记入战情。'}
          </span>
          <button type="button" className="text-button" onClick={() => showTab('log')}>战情记录</button>
        </div>
        {replay && <div className="replay-bar">
          <b>重演</b><input type="range" min={0} max={Math.max(1, replay.end)} value={o.tick} aria-label="重演时间" onChange={(event) => void replayAt(Number(event.target.value))} />
          <span>{clock(o.tick)}</span><button type="button" onClick={() => void exitReplay()}>返回现局</button>
        </div>}
        {!course && !replay && finished && !resultDismissed && (duelVoided ? <div className="result-screen">
          <div className="result-card" role="alert">
            <p>排位战局已结束</p>
            <h2>本局作废、积分不变</h2>
            <p>服务故障导致本局未能完成评分，双方积分保持不变。本局不可再下达命令。</p>
            {onlineDuel?.own_fleet && <p>本席舰队 {onlineDuel.own_fleet.name} · 点价 {onlineDuel.fleet_cost ?? '—'} 分 ·
              {' '}{rankedBudgetTitle(onlineDuel.budget ?? 0)} · 赛季 {onlineDuel.season_id}</p>}
            <div className="actions">
              <button type="button" className="primary" onClick={returnToDuelLobby}>返回线上舰桥</button>
              <button type="button" onClick={() => { setResultDismissed(true); setTab('log'); }}>查看战情</button>
            </div>
          </div>
        </div> : <CampaignEndingGate key={endingKey} observation={o}
          seen={seenCampaignEndings.has(endingKey)} onContinue={() => setSeenCampaignEndings(seen => new Set([...seen, endingKey]))}>{reopen => <div className="result-screen">
          <div className="result-card">
            <p>{onlineDuel ? (onlineDuel.mode === 'ranked' ? '排位战果' : '线上约战结束') : o.campaign ? o.campaign.missionLabel : o.variant === 'challenge' ? '少舰迎击 · 挑战结束' : o.variant === 'night' ? '夜航接敌 · 演习结束' : '昼间水面演习结束'}</p>
            {o.campaign && result ? <CampaignResultSummary campaign={o.campaign} result={result} /> :
              <h2>{o.variant === 'challenge' ? (result?.primary ? '挑战目标达成' : '挑战目标未达成') : winner}</h2>}
            <div className="score"><span>同盟 {result?.allies}</span><span>轴心 {result?.axis}</span></div>
            {onlineDuel?.end_reason === 'surrender' && <p>一方投降</p>}
            {onlineDuel?.mode === 'ranked' && <div className="ranked-report" aria-label="排位战果">
              <p>{rankedBudgetTitle(onlineDuel.budget ?? 0)} · 赛季 {onlineDuel.season_id} · 点表 {onlineDuel.point_table_version ?? '—'}</p>
              <p>本席舰队 {onlineDuel.own_fleet?.name ?? '—'} · 点价 {onlineDuel.fleet_cost ?? '—'} 分</p>
              {onlineDuel.rated === true && onlineDuel.rating ? <p>积分 {onlineDuel.rating.before} → {onlineDuel.rating.after}
                （{onlineDuel.rating.delta >= 0 ? '+' + onlineDuel.rating.delta : onlineDuel.rating.delta} · {onlineDuel.rating.rank}）</p> :
                <p>本局作废、积分不变</p>}
            </div>}
            {cloudBattle && result?.grade && result.grade !== 'none' && <button type="button" className="primary" disabled={busy || cloudClaimed}
              onClick={() => void claimCloud()}>{cloudClaimed ? '本局已结算' : '领取联机战役奖励'}</button>}
            {o.campaign && !cloudBattle && campaignId.current && <CampaignRewardActions stageId={o.campaign.stageId} progress={port.campaignProgress} busy={busy}
              onClaim={() => { const id = o.campaign!.stageId; setPort(state => claimCampaignRewards(state, id)); }} />}
            <div className="actions">{!cloudBattle && <button type="button" className="primary" onClick={() => void startReplay()}>重演战局</button>}
              {reopen && <button type="button" onClick={reopen}>回看结局</button>}
              {o.campaign && <button type="button" onClick={openPort}>返回母港</button>}
              {onlineDuel && <button type="button" onClick={returnToDuelLobby}>返回线上舰桥</button>}
              <button type="button" onClick={() => { setResultDismissed(true); setTab('log'); }}>查看战情</button></div>
          </div>
        </div>}</CampaignEndingGate>)}
        {notice && <div className="notice" role="status">{notice}</div>}
      </section>
      <aside className="staff-panel" aria-label="指挥面板">
        <nav className="staff-tabs" aria-label="面板">{tabs.map(({ key, title }) =>
          <button key={key} type="button" aria-pressed={tab === key} data-guide-control={key === 'log' ? 'battle-log' : key + '-tab'} onClick={() => showTab(key)}>{title}</button>
        )}</nav>
        <div className="staff-scroll">
          {o.campaign && <CampaignMissionBrief campaign={o.campaign} />}
          {course && <TrainingCoach course={course} evidence={evidence} guided={guided} radar={nightRadar}
            onExit={() => void leaveCourse(false)} onFinish={() => void leaveCourse(true)} />}
          {nightRadar && course === 'night' && <button type="button" className="training-window" data-guide-control="clock-window"
            disabled={busy || finished} onClick={() => void nextNightWindow()}>推进到下一探测窗口</button>}
          {course && finished && !courseDone && <p className="inline-warning">演习已结束。退出后可重新开始本课。</p>}
          {!!selected?.gunTarget && !replay && !finished && <section className="night-tools" aria-label="本舰待发炮击">
            <h3>待发炮击 <small>{selected.name} → {selected.gunTarget}</small></h3>
            <button type="button" disabled={busy} onClick={() => void command({ op: 'gun_cancel', ship: selected.id }, () => hint('已撤销尚未发射的炮座。'))}>取消待发炮击</button>
          </section>}
          {(o.variant === 'night-training' || nightRadar) && !replay && <section className="night-tools" aria-label="照明" data-guide-control="illumination">
            <h3>照明弹 <small>{selected?.name}</small></h3>
            <label>可见接触 <select value={o.contacts.some(c => c.id === nightTarget) ? nightTarget : ''}
              onChange={event => { setLightPreview(undefined); setNightTarget(event.target.value); if (event.target.value) record('contactViewed'); }}>
              <option value="">{o.contacts.length ? '选择接触' : '尚无目视接触'}</option>
              {o.contacts.map(c => <option key={c.id} value={c.id}>{c.name ? c.name + ' · ' : ''}{c.id}</option>)}
            </select></label>
            {lightPreview?.error && <p className="field-note">{lightPreview.error}</p>}
            <button type="button" disabled={busy || finished || !selected || !lightPreview?.valid}
              onClick={() => selected && void command({ op: 'illuminate', ship: selected.id, target: nightTarget }, () => {
                setLightPreview(undefined); record('lightAccepted'); hint('照明弹已下令；等待火力窗口。');
              })}>下达照明弹{lightPreview?.valid && lightPreview.mount !== undefined ? ' · 炮座 ' + (lightPreview.mount + 1) : ''}</button>
          </section>}
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
                  <button type="button" data-guide-control="route-cancel" onClick={() => { if (waypoints.length && editMode === 'follow') record('draftCancelled'); resetDraft(); }}>取消草稿</button>
                  <button type="button" className="primary" data-guide-control="route-commit" disabled={!preview?.valid || !waypoints.length}
                    onClick={() => void command({ op: 'route', fleet: fleet.id, mode: editMode, points: waypoints, speed: cruise }, () => {
                      if (editMode === 'sync' || (editMode === 'follow' && waypoints.length >= 2)) {
                        learn(editMode); record(editMode === 'follow' ? 'followAccepted' : 'syncAccepted');
                      }
                      if (fleet.ai.mode === 'auto' && fleet.ai.move) { learn('override'); record('override'); }
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
                <span className="hull-type">{hullNames[ship.kind]}</span>
                <span className="ship-title">{ship.name}{ship.id === fleet.leader && <small>领舰</small>}</span>
                <span className="hull-state" title={ship.hp + ' / ' + ship.maxHp}><i style={{ width: Math.min(100, Math.max(0, 100 * ship.hp / ship.maxHp)) + '%' }} /></span>
              </button>)}
              {selected && selected.fleet === fleet.id && <div className="ship-inspect">
                <span>{selected.hp > 0 ? selected.speed.toFixed(0) + ' 节' : '已失能'} · {selected.ammo} 枚雷</span>
                <button type="button" onClick={() => setTab('ship')}>舰体示意</button>
                {selected.hp > 0 && selected.id !== fleet.leader && !replay && !finished && <>
                  <button type="button" data-guide-control="set-leader" onClick={() => void command({ op: 'lead', fleet: fleet.id, ship: selected.id }, () => {
                    learn('lead'); record('lead'); hint('已更换领舰。若领舰不在队首，可先重整或选回队首舰。');
                  })}>设为领舰</button>
                  <button type="button" onClick={() => void command({ op: 'detach', fleet: fleet.id, ship: selected.id }, () => hint('该舰已脱离编队。'))}>脱队</button>
                </>}
              </div>}
            </section>
          </>}
          {tab === 'fleet' && !fleet && <p className="empty-state">当前没有可指挥编队。</p>}
          {tab === 'ship' && (selected ? <><ShipSchematic ship={selected} ships={o.ships} select={selectShip} tick={o.tick}
            torpedo={o.torpedoDepths && !finished && !replay ? {
              settings: torpedoSettings[selected.id] ?? {},
              change: (settings) => setTorpedoSettings(current => ({ ...current, [selected.id]: settings })),
            } : undefined} />
            {!!selected.systems?.radars?.length && <section className="night-tools" aria-label="舰上雷达">
              <h3>舰上雷达</h3>{selected.systems.radars.map(set => <button key={set.id} type="button"
                aria-pressed={set.powered} disabled={set.disabled || finished || !!replay}
                data-guide-control={!set.powered && !set.disabled ? 'radar' : undefined}
                onClick={() => void command({ op: 'radar_set', ship: selected.id, radar: set.id, powered: !set.powered },
                  () => { if (!set.powered && (set.id === 'us_sg' || set.id === 'us_sc2')) record('radarPowered'); })}>{set.name} · {set.disabled ? '失能' : set.powered ? '开启' : '关闭'}</button>)}
            </section>}</> :
            <p className="empty-state">本席没有可查看的舰艇。</p>)}
          {tab === 'ai' && fleet && <section className="ai-panel">
            <div className="group-heading"><h2>战术指挥官</h2><span>{fleet.name}</span></div>
            {onlineDuel?.mode === 'ranked' ? <>
              <p className="field-note" role="status">排位战局：指挥风格已冻结为「{profileNames[fleet.ai.profile] ?? fleet.ai.profile}」，本局不可更换。</p>
              <p className="field-note">指挥权限固定为手动，战术建议仅供参考，需本人确认下令。</p>
            </> : <>
              <label>AI 风格 <select value={fleet.ai.profile} disabled={!!replay || finished} onChange={(event) => changeAi({ ...fleet.ai, profile: event.target.value as Profile })}>
                {(Object.entries(profileNames) as [Profile, string][]).map(([id, name]) => <option key={id} value={id} disabled={presetActive && !port.profiles.includes(id)}>{name}</option>)}
              </select></label>
              <p className="field-note">{descriptions[fleet.ai.profile]}</p>
              <label>指挥权限 <select value={fleet.ai.mode} disabled={!!replay || finished} onChange={(event) => {
                const mode = event.target.value as AiConfig['mode'];
                changeAi(mode === 'auto' && !fleet.ai.move && !fleet.ai.gun && !fleet.ai.torpedo ? { ...fleet.ai, mode, move: true, gun: true, torpedo: true } : { ...fleet.ai, mode });
              }}>
                <option value="manual">手动</option><option value="suggest">仅建议</option>{!onlineDuel && <option value="auto">选择托管项</option>}
              </select></label>
              {fleet.ai.mode === 'auto' && <fieldset><legend>允许 AI 执行</legend>
                {([{ key: 'move', title: '编队机动' }, { key: 'gun', title: '炮击' }, { key: 'torpedo', title: '雷击' }] as const).map(({ key, title }) =>
                  <label key={key}><input type="checkbox" checked={fleet.ai[key]} disabled={!!replay || finished}
                    onChange={(event) => changeAi({ ...fleet.ai, [key]: event.target.checked })} /> {title}</label>
                )}
                <p className="field-note">手动下令会接管该项；勾选可交还 AI。</p>
              </fieldset>}
            </>}
            <button type="button" disabled={finished || !!replay} onClick={() => void askAi()}>查看战术建议</button>
            {suggestion && <div className="suggestion"><p>{suggestion.text}</p>
              {suggestion.orders.length > 0 && <button type="button" onClick={() => void acceptAi()}>采纳建议</button>}
            </div>}
          </section>}
          {tab === 'log' && <section className="battle-log">
            <div className="group-heading"><h2>战情记录</h2><span>本席可见</span></div>
            <div className="log-actions">
              <button type="button" onClick={() => void exportLog()}>导出</button>
              {!replay && !cloudBattle && <button type="button" disabled={o.tick === 0 || busy} onClick={() => void startReplay()}>重演</button>}
            </div>
            {radio.available && <label className="radio-toggle"><input type="checkbox" checked={radio.enabled}
              onChange={event => radio.setEnabled(event.target.checked)} /> 舰队电台语音</label>}
            {!latest.length && <p className="empty-state">开始演习后，这里会记录接触、开火与战果。</p>}
            <ol>{latest.map((event, index) =>
              <li key={event.id ?? (String(event.tick) + ':' + index)} className={'log-event ' + eventTone(event)}>
                <time>{clock(event.tick)}</time><div>{event.text}{event.rule && <small>{event.rule}</small>}</div>
              </li>
            )}</ol>
          </section>}
        </div>
        <footer className="staff-footer">
          <span>{replay ? '复盘模式' : cloudBattle ? '联机进度已由服务器保存' : '离线演习'}</span>
          {onlineDuel && !finished && (confirmSurrender ? <>
            <button type="button" className="text-button" disabled={busy} onClick={() => void surrenderDuel()}>确认投降</button>
            <button type="button" className="text-button" disabled={busy} onClick={() => setConfirmSurrender(false)}>取消</button>
          </> : <button type="button" className="text-button" disabled={busy} onClick={() => setConfirmSurrender(true)}>投降</button>)}
          {!course && !cloudBattle && <button type="button" className="text-button" disabled={!!replay || busy} onClick={() => void persist(true)}>保存进度</button>}
        </footer>
      </aside>
    </div>
    {dialog && <div className="dialog-backdrop" onPointerDown={(event) => { if (event.target === event.currentTarget && !busy) setDialog(false); }}>
      <section className="setup-dialog" role="dialog" aria-modal="true" aria-label="演习设置">
        <p>虚构水面演习</p><h2>重新部署舰队</h2>
        <label>演习时段 <select value={setup.variant} onChange={(event) => setSetup({ ...setup, variant: event.target.value as typeof setup.variant })}>
          <option value="">昼间水面演习</option><option value="night">夜航接敌演习</option><option value="radar">1943 夜间雷达演习</option>
        </select></label>
        <label className="realtime-option"><input type="checkbox" checked={setup.realtime} onChange={event => setSetup({ ...setup, realtime: event.target.checked })} /> 实时主炮</label>
        <p className="field-note">装填和转向决定开火时点。CAS 火力表决定命中和伤害，伤害按战术回合分摊。已有资料的炮座采用参考射速，其余沿用暂定节奏。关闭实时主炮后使用旧版计划火力窗口。</p>
        <label>所属方 <select value={setup.side} onChange={(event) => setSetup({ ...setup, side: event.target.value as Side })}>
          <option value="allies">同盟舰队</option><option value="axis">轴心舰队</option>
        </select></label>
        <label>对手 AI <select value={setup.enemy} onChange={(event) => setSetup({ ...setup, enemy: event.target.value as Profile })}>
          {(Object.entries(profileNames) as [Profile, string][]).map(([id, name]) => <option key={id} value={id}>{name}</option>)}
        </select></label>
        <label>演习编号 <input type="number" min={0} max={4294967295} value={setup.seed} onChange={(event) => setSetup({ ...setup, seed: Math.max(0, Math.min(4294967295, Math.trunc(Number(event.target.value)))) })} /></label>
        {radio.available && <label>电台音量 <input type="range" min={0} max={1} step={0.05} value={radio.volume}
          onChange={event => radio.setVolume(Number(event.target.value))} /></label>}
        <label><input type="checkbox" checked={music.enabled} onChange={event => music.setEnabled(event.target.checked)} /> 战斗配乐</label>
        <label>配乐音量 <input type="range" min={0} max={1} step={0.05} value={music.volume}
          onChange={event => music.setVolume(Number(event.target.value))} /></label>
        <p className="field-note">开始新演习会替换当前本机进度。</p>
        <div className="actions"><button type="button" onClick={() => setDialog(false)} disabled={busy}>返回</button>
          <button type="button" className="primary" onClick={() => void newExercise()} disabled={busy}>开始新演习</button></div>
      </section>
    </div>}
  </main>;
}

function Entry() {
  const [profile,setProfile]=useState<LocalProfile>();
  return profile ? <App key={profile.id} profile={profile} onLogout={()=>{
    if (profile.online) void onlineRequest('/auth/logout', profile.online.token, {}).catch(() => {});
    closeSession();setProfile(undefined);
  }} /> : <Login onLogin={setProfile} />;
}

createRoot(document.getElementById('root')!).render(<Entry />);
