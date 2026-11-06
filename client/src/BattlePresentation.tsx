import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { clock } from './engine';
import type { GunMount, LogEvent, Observation, Point, Shell, Ship, Torpedo } from './engine';
import { shipPortrait } from './shipPortraits';
import './battle-presentation.css';

type EventTag = 'sunk' | 'critical' | 'damage' | 'hit' | 'leader';

export function alertKind(event: LogEvent): EventTag | undefined {
  if (event.kind === 'sunk') return 'sunk';
  if (/^(critical|crit|fire_damage|flood_damage)$/.test(event.kind)) return 'critical';
  if (/^(damage|collision|grounding)$/.test(event.kind)) return 'damage';
  if (/^(hit|torpedo_hit)$/.test(event.kind)) return 'hit';
  if (event.kind === 'leader') return 'leader';
  return undefined;
}

const eventTag: Record<EventTag, string> = { sunk: '舰艇沉没', critical: '关键损伤', damage: '舰艇受损', hit: '确认命中', leader: '指挥交接' };
const eventPriority: Record<EventTag, number> = { sunk: 5, critical: 4, leader: 3, damage: 2, hit: 1 };
const alertTtl = 6200;
type Alert = { key: string; event: LogEvent; tag: EventTag; deadline: number };
const eventKey = (event: LogEvent) => event.id != null ? String(event.id) :
  [event.tick, event.kind, event.rule ?? '', event.text, event.x ?? '', event.y ?? ''].join(':');

export function BattleAlerts({ events, tick, session, enabled }: { events: LogEvent[]; tick: number; session: number; enabled: boolean }) {
  const seen = useRef<{ session: number; tick: number; enabled: boolean; keys: Set<string> } | undefined>(undefined);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  useEffect(() => {
    const previous = seen.current;
    if (!previous || previous.session !== session || !previous.enabled || !enabled || previous.tick > tick) {
      seen.current = { session, tick, enabled, keys: new Set(events.map(eventKey)) };
      setAlerts([]);
      return;
    }
    previous.tick = tick;
    const deadline = performance.now() + alertTtl;
    const fresh: Alert[] = [];
    for (const event of events) {
      const key = eventKey(event);
      if (previous.keys.has(key)) continue;
      previous.keys.add(key);
      const tag = alertKind(event);
      // Clock skips can deliver a batch of older log entries. The log keeps
      // those; the live alert only reports events near the current view.
      if (tag && tick - event.tick <= 15) fresh.push({ key, event, tag, deadline });
    }
    if (fresh.length) {
      setAlerts((current) => [...current, ...fresh]
        .filter((item) => item.deadline > performance.now())
        .sort((a, b) => eventPriority[b.tag] - eventPriority[a.tag] || b.event.tick - a.event.tick)
        .slice(0, 3));
    }
  }, [events, tick, session, enabled]);
  useEffect(() => {
    if (!alerts.length) return;
    const timer = window.setTimeout(
      () => setAlerts((current) => current.filter((item) => item.deadline > performance.now())),
      Math.max(0, Math.min(...alerts.map((item) => item.deadline)) - performance.now()) + 2,
    );
    return () => window.clearTimeout(timer);
  }, [alerts]);
  return <div className="battle-alerts" aria-label="战情提醒" aria-live="polite" aria-atomic="false">
    {enabled && alerts.map(({ key, event, tag }) => <div className={'battle-alert ' + tag} key={key} data-event-id={key}>
      <div className="alert-head"><span>{eventTag[tag]}</span><time>{clock(event.tick)}</time></div>
      <span className="alert-text">{event.text}</span>
    </div>)}
  </div>;
}

type ProjectileFrame = Pick<Observation, 'tick' | 'shells' | 'torpedoes'>;
type Projection = { left: number; bottom: number; ratio: number; width: number; height: number };
const interpolate = (a: Point, b: Point, t: number) => ({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });
const project = (p: Point, map: Projection) => ({ x: map.left + p.x * map.ratio, y: map.bottom - p.y * map.ratio });
const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));
const dot = (ctx: CanvasRenderingContext2D, p: Point, radius: number, color: string) => {
  ctx.beginPath(); ctx.arc(p.x, p.y, radius, 0, Math.PI * 2);
  ctx.fillStyle = color; ctx.fill();
};

function shellHeight(progress: number, ceiling: number) {
  return 4 * ceiling * progress * (1 - progress);
}
function paintShell(ctx: CanvasRenderingContext2D, shell: Shell, previous: Shell | undefined, blend: number, map: Projection) {
  const groundPoint = interpolate(previous ?? shell.from ?? shell, shell, blend);
  const progress = clamp((previous?.progress ?? (shell.from ? 0 : shell.progress)) * (1 - blend) + shell.progress * blend, 0, 1);
  const ground = project(groundPoint, map);
  const knownGeometry = shell.from && shell.to;
  const ceiling = !knownGeometry ? 0 : shell.arcHeightM !== undefined ?
    Math.min(shell.arcHeightM * map.ratio, map.height * .22) :
    clamp(Math.hypot(shell.from!.x - shell.to!.x, shell.from!.y - shell.to!.y) * map.ratio * .17, 14, 60);
  const airborne = { x: ground.x, y: ground.y - shellHeight(progress, ceiling) };
  const color = shell.own ? '#ffdc9c' : '#ff9f88';
  if (knownGeometry) {
    const start = Math.max(0, progress - .18);
    ctx.beginPath();
    for (let i = 0; i <= 8; i++) {
      const at = start + (progress - start) * i / 8;
      const groundTrail = project(interpolate(shell.from!, shell.to!, at), map);
      const y = groundTrail.y - shellHeight(at, ceiling);
      if (i === 0) ctx.moveTo(groundTrail.x, y);
      else ctx.lineTo(groundTrail.x, y);
    }
    const tail = project(interpolate(shell.from!, shell.to!, start), map);
    const stroke = ctx.createLinearGradient(tail.x, tail.y - shellHeight(start, ceiling), airborne.x, airborne.y);
    stroke.addColorStop(0, '#f2bd6e09'); stroke.addColorStop(1, color);
    ctx.strokeStyle = stroke; ctx.lineWidth = 1.65; ctx.stroke();
    dot(ctx, ground, 1.2, '#ecb27760');
  }
  ctx.shadowColor = color; ctx.shadowBlur = 6;
  dot(ctx, airborne, 2.15, color);
  ctx.shadowBlur = 0;
}

const samePoint = (a: Point, b: Point) => Math.hypot(a.x - b.x, a.y - b.y) < .01;
function pointWithinLeg(point: Point, start: Point, end: Point) {
  const dx = end.x - start.x, dy = end.y - start.y;
  const along = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy);
  return along > 0 && along < 1 && samePoint(point, interpolate(start, end, along));
}

function paintTorpedo(ctx: CanvasRenderingContext2D, torpedo: Torpedo, previous: Torpedo | undefined, blend: number, map: Projection) {
  // An enemy wake has no fallback launch origin. On first contact or reacquisition
  // the renderer can only paint the points the current seat is allowed to see.
  const wake = torpedo.trail?.length ? [...torpedo.trail] : torpedo.own && torpedo.from ? [torpedo.from] : [];
  if (!wake.length || !samePoint(wake[wake.length - 1], torpedo)) wake.push(torpedo);
  let headIndex = wake.length - 1;
  let headPoint: Point = torpedo;
  if (previous && blend < 1) {
    let previousIndex = wake.findIndex((point) => samePoint(point, previous));
    // The engine can compress a straight wake to two endpoints. A previous head
    // outside the currently allowed track must never be used to bridge a gap.
    if (previousIndex < 0) {
      const next = wake.findIndex((point, i) => i > 0 && pointWithinLeg(previous, wake[i - 1], point));
      if (next > 0) {
        wake.splice(next, 0, previous);
        previousIndex = next;
        headIndex++;
      }
    }
    if (previousIndex >= 0 && previousIndex < headIndex) {
      const leg = previousIndex + (headIndex - previousIndex) * blend;
      headIndex = Math.floor(leg);
      headPoint = interpolate(wake[headIndex], wake[headIndex + 1], leg - headIndex);
    }
  }
  const head = project(headPoint, map);
  const start = project(wake[0], map);
  const color = torpedo.own ? '#cfe899' : '#fb9b84';
  if (Math.hypot(head.x - start.x, head.y - start.y) > 1) {
    const trace = ctx.createLinearGradient(start.x, start.y, head.x, head.y);
    trace.addColorStop(0, color + '58'); trace.addColorStop(.7, color + 'a0'); trace.addColorStop(1, color);
    ctx.beginPath(); ctx.moveTo(start.x, start.y);
    for (let i = 1; i <= headIndex; i++) {
      const at = project(wake[i], map);
      ctx.lineTo(at.x, at.y);
    }
    ctx.lineTo(head.x, head.y);
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.lineWidth = 3.5; ctx.strokeStyle = color + '20'; ctx.stroke();
    ctx.lineWidth = 1.45; ctx.strokeStyle = trace; ctx.stroke();
    ctx.lineCap = 'butt'; ctx.lineJoin = 'miter';
  }
  dot(ctx, head, 2, color);
}

export function BattleProjectiles({ observation, map, running, speed }: {
  observation: ProjectileFrame; map: Projection; running: boolean; speed: number;
}) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const frames = useRef<{ previous?: ProjectileFrame; current?: ProjectileFrame; started: number }>({ started: 0 });
  useLayoutEffect(() => {
    const frame = frames.current;
    if (frame.current && observation.tick !== frame.current.tick) {
      frame.previous = observation.tick > frame.current.tick ? frame.current : undefined;
      frame.started = performance.now();
    }
    frame.current = observation;
  }, [observation]);
  useLayoutEffect(() => {
    const element = canvas.current!;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const width = Math.ceil(map.width * dpr);
    const height = Math.ceil(map.height * dpr);
    if (element.width !== width) element.width = width;
    if (element.height !== height) element.height = height;
    const ctx = element.getContext('2d');
    if (!ctx) return;
    const previous = frames.current.previous;
    const delta = observation.tick - (previous?.tick ?? observation.tick);
    const animate = running && delta >= 1 && delta <= 8 && !window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const shells = observation.shells ?? [];
    const torpedoes = observation.torpedoes;
    const prevShells = new Map(previous?.shells?.map((shell) => [shell.id, shell]));
    const prevTorpedoes = new Map(previous?.torpedoes.map((torpedo) => [torpedo.id, torpedo]));
    const duration = clamp(delta / speed * 1000, 80, 1000);
    const start = frames.current.started;
    let raf = 0;
    function paint(now: number) {
      const blend = animate ? clamp((now - start) / duration, 0, 1) : 1;
      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx!.clearRect(0, 0, map.width, map.height);
      for (const shell of shells) paintShell(ctx!, shell, animate ? prevShells.get(shell.id) : undefined, blend, map);
      for (const torpedo of torpedoes) paintTorpedo(ctx!, torpedo, animate ? prevTorpedoes.get(torpedo.id) : undefined, blend, map);
      if (animate && blend < 1 && (shells.length || torpedoes.length)) raf = requestAnimationFrame(paint);
    }
    paint(performance.now());
    return () => cancelAnimationFrame(raf);
  }, [observation, map.left, map.bottom, map.ratio, map.width, map.height, running, speed]);
  return <canvas ref={canvas} className="projectile-layer" aria-hidden="true"
    data-shells={observation.shells?.length ?? 0} data-torpedoes={observation.torpedoes.length}
    data-torpedo-trails={observation.torpedoes.filter((torpedo) => (torpedo.trail?.length ?? 0) > 1).length} />;
}

export function mountStatus(mount: GunMount, tick: number) {
  const remaining = Math.max(0, (mount.readyTick ?? tick) - tick);
  return mount.destroyed ? 'lost' : mount.training ? 'turning' : remaining ? 'loading' : 'ready';
}

function GunMountReadiness({ mount, slot, tick }: { mount: GunMount; slot: number; tick: number }) {
  const state = mountStatus(mount, tick);
  const remaining = Math.max(0, (mount.readyTick ?? tick) - tick);
  const reload = remaining > 0 ? `装填 ${remaining} 秒` : '';
  const status = state === 'lost' ? '损毁' : state === 'turning' ? (reload ? `转炮 · ${reload}` : '转炮') : reload || '就绪';
  return <li className={'mount-readiness ' + state} data-gun-mount={mount.index} data-ready-tick={mount.readyTick}>
    <span>炮座 {slot + 1} <small>{mount.barrels} 门</small></span><b>{status}</b>
  </li>;
}

export function ShipSchematic({ ship, ships, select, tick = 0 }: { ship: Ship; ships: Ship[]; select: (ship: Ship) => void; tick?: number }) {
  const systems = ship.systems;
  const timedGuns = systems?.guns.some((mount) => mount.readyTick !== undefined || mount.training !== undefined);
  const portrait = shipPortrait(ship.classId, ship.characterId);
  const hp = Math.round(ship.hp * 10) / 10;
  const damagePercent = clamp((ship.hp / ship.maxHp) * 100, 0, 100);
  const chooseShip = (id: string) => {
    const next = ships.find((item) => item.id === Number(id));
    if (next) select(next);
  };
  return <section className="ship-schematic" aria-label="舰艇状态">
    <div className="schematic-head">
      <div><span>{ship.kind === 'cl' ? '轻巡洋舰' : '驱逐舰'}</span><h2>{ship.name}</h2></div>
      {ships.length > 1 && <select aria-label="查看舰艇" value={ship.id} onChange={(event) => chooseShip(event.target.value)}>
        {ships.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
      </select>}
    </div>
    <div className={'ship-overview' + (portrait ? ' with-portrait' : '')}>
      {portrait && <figure className="ship-portrait" data-character={portrait.id}>
        <img key={portrait.id} src={portrait.src} alt={portrait.name + '舰娘立绘'} decoding="async" />
        <figcaption><strong>{portrait.name}</strong>{portrait.representative && <span>舰型代表</span>}</figcaption>
      </figure>}
      <div className="ship-overview-state">
        <div className="hull-meter"><span>舰体耐久</span><b>{hp} / {ship.maxHp} DP</b></div>
        <div className="hull-meter-track"><i style={{ width: damagePercent + '%' }} /></div>
        {systems && <div className="schematic-plate">
          <svg viewBox="0 0 260 74" aria-label="舰体侧向示意图" role="img">
            <path d="M9 49l15-8h31l21-5h23v-7h28v-9h20v10h19v8h31l21 3 33-7-13 14-15 7H29z" fill="#15343c" stroke="#9daba0" strokeWidth="1.25"/>
            <path d="M25 48h208M96 62h63m-33-42V12m-8 6h18m22 19v-14m-6 7h12M47 62H22m200 0h22" fill="none" stroke="#587782"/>
            <path d="M220 11h18m-4-3 5 3-5 3" fill="none" stroke="#e8c589"/>
            <path d="M40 53h181" stroke={systems.floods > 0 ? '#79cce5' : '#476878'} strokeDasharray="3 2" strokeWidth={systems.floods > 0 ? 2 : 1}/>
            {systems.fires > 0 && <path d="M124 44c-5-6 6-5 5-13 4 4 1 6 5 9 2-4 6 4 2 6-4 3-9 2-12-2z" fill="#f09969"/>}
          </svg>
          <div className="schematic-caption"><span>舰体示意</span><span>舰首 →</span></div>
        </div>}
      </div>
    </div>
    {systems ? <>
      <div className="mount-rows">
        {timedGuns ? <div className="gun-readiness">
          <div className="gun-readiness-heading"><span>主炮状态</span>{ship.gunTarget && <b>待发目标 {ship.gunTarget}</b>}</div>
          <ul aria-label="炮座状态">{systems.guns.map((mount, slot) => <GunMountReadiness mount={mount} slot={slot} tick={tick} key={mount.index} />)}</ul>
        </div> : <div className="mount-row"><span>炮座</span><div>
          {systems.guns.length ? systems.guns.map((gun, slot) => <span key={gun.index} className={'mount-icon ' + (gun.destroyed ? 'lost' : 'ready')}
            aria-label={'炮座 ' + (slot + 1) + '，' + gun.barrels + ' 门炮，' + (gun.destroyed ? '损毁' : '完好')}
            title={gun.destroyed ? '炮座已损毁' : '炮座完好'}>{gun.destroyed ? '×' : gun.barrels}</span>) : <small>未装</small>}
        </div></div>}
        <div className="mount-row"><span>鱼雷管</span><div>
          {systems.tubes.length ? systems.tubes.map((tube, slot) => <span key={tube.index} className={'mount-icon tube ' + (tube.spent ? 'spent' : 'ready')}
            aria-label={'鱼雷座 ' + (slot + 1) + '，' + tube.tubes + ' 联装，' + (tube.spent ? '不可用' : '未使用')}
            title={tube.spent ? '该座已使用或不可用' : '该座尚未使用'}>{tube.spent ? '−' : tube.tubes}</span>) : <small>未装</small>}
        </div></div>
      </div>
      <dl className="system-status">
        <div><dt>火控</dt><dd className={systems.directorDamaged ? 'system-warning' : ''}>{systems.directorDamaged ? '受损' : '正常'}</dd></div>
        <div><dt>动力</dt><dd className={systems.engineeringLevels > 0 ? 'system-warning' : ''}>{systems.engineeringLevels > 0 ? '受损 ' + systems.engineeringLevels + ' 级' : '正常'}</dd></div>
        <div><dt>火灾</dt><dd className={systems.fires > 0 ? 'system-warning' : ''}>{systems.fires ? systems.fires + ' 处' : '无'}</dd></div>
        <div><dt>进水</dt><dd className={systems.floods > 0 ? 'system-flood' : ''}>{systems.floods ? systems.floods + ' 处' : '无'}</dd></div>
      </dl>
      <p className="schematic-foot">现速 {ship.speed.toFixed(1)} 节 · 可用上限 {systems.maxSpeed.toFixed(1)} 节 · 余雷 {ship.ammo} 枚</p>
    </> : <p className="schematic-foot">当前战斗记录没有提供分系统状态。</p>}
  </section>;
}
