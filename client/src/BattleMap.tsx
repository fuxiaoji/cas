import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { CSSProperties, PointerEvent as ReactPointer } from 'react';
import { ask } from './engine';
import type { Aim, Contact, Fleet, Observation, Point, RoutePreview, Ship, Weapon } from './engine';
import { alertKind, BattleAlerts, BattleProjectiles } from './BattlePresentation';

type MapProps = {
  observation: Observation; fleet?: Fleet; selected?: number; disabled: boolean;
  session: number; running: boolean; speed: number; replaying: boolean;
  editing: boolean; waypoints: Point[]; preview?: RoutePreview; reformPreview?: RoutePreview;
  onSelect: (ship: Ship) => void; onAddPoint: (point: Point) => void;
  onMovePoint: (index: number, point: Point) => void;
  onFire: (ship: number, weapon: Weapon, target: string, heading?: number) => void;
  onCancelFire?: () => void;
  onInspectMap?: () => void;
  onInspectContact?: (id: string) => void;
  onHint: (message: string) => void;
};

interface Gesture {
  pointer: number; ship: number; weapon: Weapon; cursor: Point; start: Point; contact?: Contact;
  anchor?: Point; aim?: Aim; heading?: number; baseHeading?: number; cancelled: boolean; loading?: boolean;
}
type SurfaceDrag =
  | { pointer: number; start: Point; waypoint: number }
  | { pointer: number; start: Point; origin: Point; waypoint?: undefined };

const COLORS = { ocean: '#082533', grid: '#467084', ink: '#9cc0ce', friendly: '#a6dec8', enemy: '#f6a081', gold: '#f5ca79' };
const TAU = Math.PI * 2;
const radians = (degrees: number) => degrees * Math.PI / 180;
const wrap = (heading: number) => ((heading % 360) + 360) % 360;
const distance = (a: Point, b: Point) => Math.hypot(a.x - b.x, a.y - b.y);
const bearing = (from: Point, to: Point) => wrap(Math.atan2(to.x - from.x, from.y - to.y) * 180 / Math.PI);
const onBearing = (from: Point, heading: number, length: number): Point => ({ x: from.x + Math.sin(radians(heading)) * length, y: from.y - Math.cos(radians(heading)) * length });
const inArcs = (heading: number, arcs: Aim['arcs']) => arcs.some(({ from, to }) => Math.abs(to - from) >= 359.9 || wrap(heading - from) <= wrap(to - from) + 0.1);

function pointStyle(point: Point): CSSProperties { return { left: point.x, top: point.y }; }

function TurretBarrel({ at, bearing: next, rest, active }: { at: Point; bearing: number; rest: number; active: boolean }) {
  const barrel = useRef<HTMLSpanElement>(null);
  const last = useRef(rest);
  useLayoutEffect(() => {
    const element = barrel.current!;
    last.current += wrap(next - last.current + 180) - 180;
    element.style.rotate = `${last.current}deg`;
  }, [next]);
  return <span ref={barrel} aria-hidden="true" data-turret-active={active ? 'true' : 'false'}
    className={'tactical-turret' + (active ? ' trained' : '')} style={pointStyle(at)} />;
}

function symbol(context: CanvasRenderingContext2D, at: Point, heading: number, kind: string, color: string, filled: boolean) {
  const cruiser = kind.toLowerCase() === 'cl';
  context.save();
  context.translate(at.x, at.y);
  context.rotate(radians(heading));
  context.strokeStyle = color;
  context.lineWidth = 1.35;
  context.fillStyle = filled ? '#183b47' : '#322b32';
  context.beginPath();
  const length = cruiser ? 14 : 10, beam = cruiser ? 4.6 : 3.65;
  context.moveTo(0, -length);
  context.lineTo(beam, -length * 0.38);
  context.lineTo(beam, length * 0.63);
  context.lineTo(beam * 0.63, length * 0.91);
  context.lineTo(-beam * 0.63, length * 0.91);
  context.lineTo(-beam, length * 0.63);
  context.lineTo(-beam, -length * 0.38);
  context.closePath();
  context.fill();
  context.stroke();
  context.fillStyle = color;
  context.fillRect(-1.65, -length * 0.42, 3.3, length * 0.58);
  context.fillRect(-2.6, length * 0.27, 5.2, 2);
  context.restore();
}

function Compass() {
  return <svg viewBox="0 0 64 64" width="54" height="54" aria-hidden="true">
    <circle cx="32" cy="32" r="20" fill="none" stroke="currentColor" opacity=".42" />
    <path d="M32 11v42M11 32h42M18 18l28 28m0-28L18 46" stroke="currentColor" opacity=".28" />
    <path d="M32 15l5 17-5 10-5-10z" fill="none" stroke="currentColor" />
    <path d="M32 15l5 17-5-3z" fill="#e9c78e" />
    <text x="32" y="9" textAnchor="middle" fill="#e9c78e" fontSize="8">N</text>
  </svg>;
}

export function BattleMap(props: MapProps) {
  const { observation: o, fleet, selected, disabled, editing, waypoints, preview, reformPreview, session, running, speed, replaying } = props;
  const viewport = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const cancelWell = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ w: 1, h: 1 });
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState<Point>({ x: 0, y: 0 });
  const [rangesVisible, setRangesVisible] = useState(true);
  const [gesture, setGesture] = useState<Gesture>();
  const [mapPointer, setMapPointer] = useState<Point>();
  const gestureRef = useRef<Gesture | undefined>(undefined);
  const surface = useRef<SurfaceDrag | undefined>(undefined);
  const hold = useRef<number | undefined>(undefined);
  const aimSequence = useRef(0);
  const aimTimer = useRef<number | undefined>(undefined);
  const mapRatio = Math.min(Math.max(1, size.w - 65) / o.width, Math.max(1, size.h - 42) / o.height) * zoom;
  const left = (size.w - o.width * mapRatio) / 2 + pan.x;
  const bottom = (size.h + o.height * mapRatio) / 2 + pan.y;
  const screen = (point: Point): Point => ({ x: left + point.x * mapRatio, y: bottom - point.y * mapRatio });
  const world = (point: Point): Point => ({ x: Math.round((point.x - left) / mapRatio), y: Math.round((bottom - point.y) / mapRatio) });
  const inside = (point: Point) => point.x >= 0 && point.x <= o.width && point.y >= 0 && point.y <= o.height;
  const scaleMeters = (mapRatio * 1000 > 47 ? 1000 : mapRatio * 2000 > 43 ? 2000 : 5000);
  const activeShip = o.ships.find((ship) => ship.id === gesture?.ship);
  const rangedShip = o.ships.find((ship) => ship.id === selected && ship.hp > 0);
  const gunRange = rangedShip?.gunRange ?? 0;
  const torpedoRange = rangedShip?.torpedoRange ?? 0;
  const tracks = [...o.contacts, ...(o.radarContacts ?? []).map((report) => ({ ...report, heading: 0, speed: 0, kind: 'radar', name: undefined }))];
  const target = tracks.find((contact) => contact.id === gesture?.contact?.id);
  const night = ['night', 'night-training', 'radar'].includes(o.variant ?? '');
  const labelLanes: Point[][] = [[], [], [], [], []];
  const contacts = tracks.map((contact) => {
    const at = screen(contact);
    const lane = labelLanes.findIndex((points) => points.every((point) => Math.abs(at.x - point.x) >= 26 || Math.abs(at.y - point.y) >= 40));
    if (lane !== -1) labelLanes[lane].push(at);
    return { contact, at, lane };
  });

  function update(next: Gesture | undefined) {
    gestureRef.current = next;
    setGesture(next ? { ...next } : undefined);
  }
  function clearGesture() {
    window.clearTimeout(hold.current);
    window.clearTimeout(aimTimer.current);
    hold.current = undefined;
    aimTimer.current = undefined;
    aimSequence.current++;
    update(undefined);
  }
  function cancelAll() { clearGesture(); surface.current = undefined; }

  useLayoutEffect(() => {
    const element = viewport.current!;
    const resize = () => setSize({ w: element.clientWidth, h: element.clientHeight });
    const observer = new ResizeObserver(resize);
    observer.observe(element);
    resize();
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const escape = (event: KeyboardEvent) => { if (event.key === 'Escape') cancelAll(); };
    const hide = () => { if (document.hidden) cancelAll(); };
    window.addEventListener('keydown', escape);
    window.addEventListener('blur', cancelAll);
    document.addEventListener('visibilitychange', hide);
    return () => {
      window.removeEventListener('keydown', escape);
      window.removeEventListener('blur', cancelAll);
      document.removeEventListener('visibilitychange', hide);
      window.clearTimeout(hold.current);
      window.clearTimeout(aimTimer.current);
      aimTimer.current = undefined;
    };
  }, []);
  useEffect(() => { if (disabled) cancelAll(); }, [disabled]);
  useEffect(() => {
    if (gesture?.contact && !target && !gesture.cancelled) {
      window.clearTimeout(hold.current);
      window.clearTimeout(aimTimer.current);
      aimSequence.current++;
      update({ ...gesture, contact: undefined, aim: undefined, anchor: undefined, heading: undefined, baseHeading: undefined, loading: false });
    }
  }, [target, gesture?.contact?.id]);

  useLayoutEffect(() => {
    const element = canvas.current!;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    element.width = Math.ceil(size.w * dpr);
    element.height = Math.ceil(size.h * dpr);
    const ctx = element.getContext('2d');
    if (!ctx) return;
    ctx.scale(dpr, dpr);
    const north = bottom - o.height * mapRatio;
    const ocean = ctx.createLinearGradient(0, 0, 0, size.h);
    ocean.addColorStop(0, night ? '#18293e' : '#133849'); ocean.addColorStop(1, night ? '#0b1a2e' : COLORS.ocean);
    ctx.fillStyle = night ? '#0c1728' : '#0b2432'; ctx.fillRect(0, 0, size.w, size.h);
    ctx.fillStyle = ocean; ctx.fillRect(left, north, o.width * mapRatio, o.height * mapRatio);
    ctx.strokeStyle = '#6f93a244'; ctx.lineWidth = 1;
    ctx.strokeRect(left + .5, north + .5, o.width * mapRatio, o.height * mapRatio);
    ctx.save();
    ctx.beginPath(); ctx.rect(left, north, o.width * mapRatio, o.height * mapRatio); ctx.clip();
    ctx.font = '9px ui-monospace, Consolas, monospace'; ctx.fillStyle = '#96b9c081';
    const grid = 1000 * mapRatio < 22 ? 2000 : 1000;
    for (let x = grid; x < o.width; x += grid) {
      const px = screen({ x, y: 0 }).x;
      if (px < 0 || px > size.w) continue;
      ctx.beginPath(); ctx.moveTo(px + .5, north); ctx.lineTo(px + .5, bottom);
      ctx.strokeStyle = x % 5000 === 0 ? '#8aadb54a' : '#7398a624'; ctx.stroke();
      if (x % 5000 === 0) ctx.fillText(String(x / 1000) + 'E', px + 4, Math.max(12, north + 11));
    }
    for (let y = grid; y < o.height; y += grid) {
      const py = screen({ x: 0, y }).y;
      if (py < 0 || py > size.h) continue;
      ctx.beginPath(); ctx.moveTo(left, py + .5); ctx.lineTo(left + o.width * mapRatio, py + .5);
      ctx.strokeStyle = y % 5000 === 0 ? '#8aadb54a' : '#7398a624'; ctx.stroke();
      if (y % 5000 === 0) ctx.fillText(String(y / 1000) + 'N', Math.max(5, left + 5), py - 4);
    }
    ctx.restore();
    for (const island of o.islands) {
      if (!island.length) continue;
      ctx.beginPath(); island.forEach((point, i) => { const p = screen(point); if (i) ctx.lineTo(p.x, p.y); else ctx.moveTo(p.x, p.y); });
      ctx.closePath(); ctx.fillStyle = '#5a674e'; ctx.fill(); ctx.strokeStyle = '#a2b18a'; ctx.stroke();
    }
    if (rangedShip && rangesVisible && !gesture && !editing && !reformPreview) {
      const at = screen(rangedShip);
      ctx.save();
      ctx.beginPath(); ctx.rect(left, north, o.width * mapRatio, o.height * mapRatio); ctx.clip();
      for (const [range, color, pattern] of [[gunRange, '#80cde2a8', [4, 4]], [torpedoRange, '#dfb872bc', [10, 4]]] as const) {
        if (range <= 0) continue;
        ctx.beginPath(); ctx.arc(at.x, at.y, range * mapRatio, 0, TAU);
        ctx.setLineDash([...pattern]); ctx.strokeStyle = color; ctx.lineWidth = 1.1; ctx.stroke();
      }
      ctx.restore();
    }
    function line(points: Point[], color: string, width: number, dash: number[] = []) {
      if (points.length < 2) return;
      ctx!.beginPath(); ctx!.setLineDash(dash); ctx!.lineWidth = width; ctx!.strokeStyle = color;
      points.forEach((p, i) => { if (i) ctx!.lineTo(p.x, p.y); else ctx!.moveTo(p.x, p.y); });
      ctx!.stroke(); ctx!.setLineDash([]);
    }
    for (const group of o.fleets) {
      for (const path of group.paths) {
        const ship = o.ships.find((item) => item.id === path.ship);
        if (ship) line([ship, ...path.points].map(screen), group.id === fleet?.id ? '#91dbc592' : '#8fb8c54f', ship.id === group.leader ? 1.8 : 1, [6, 4]);
      }
    }
    const lead = o.ships.find((ship) => ship.id === fleet?.leader);
    if (editing && lead && waypoints.length) {
      for (const path of preview?.paths ?? []) {
        const ship = o.ships.find((item) => item.id === path.ship);
        if (ship) line([ship, ...path.points].map(screen), preview?.valid ? '#f7c77072' : '#ed876883', 1, [3, 5]);
      }
      line([lead, ...waypoints].map(screen), preview?.valid === false ? COLORS.enemy : COLORS.gold, 1.8, [7, 3]);
      waypoints.forEach((point, index) => {
        const at = screen(point); ctx.beginPath(); ctx.arc(at.x, at.y, 10, 0, TAU);
        ctx.fillStyle = '#122a35'; ctx.fill(); ctx.lineWidth = 1.4; ctx.strokeStyle = COLORS.gold; ctx.stroke();
        ctx.fillStyle = COLORS.gold; ctx.font = 'bold 10px ui-monospace, Consolas, monospace';
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(String(index + 1), at.x, at.y);
        ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
      });
    }
    if (reformPreview) {
      for (const path of reformPreview.paths) {
        const ship = o.ships.find((item) => item.id === path.ship);
        if (ship) line([ship, ...path.points].map(screen), reformPreview.valid ? '#f7c770b0' : '#ed8768a0', 1.5, [4, 4]);
      }
    }
    for (const event of o.events.slice(-25)) {
      const age = o.tick - event.tick;
      const splash = event.kind === 'splash';
      if (age < 0 || age > 7 || event.x == null || event.y == null || (!splash && !alertKind(event))) continue;
      const p = screen({ x: event.x, y: event.y });
      ctx.beginPath(); ctx.arc(p.x, p.y, 6 + age * 3, 0, TAU); ctx.strokeStyle = splash ? '#c6d9df' : COLORS.enemy;
      ctx.globalAlpha = .85 - age * .1; ctx.stroke(); ctx.globalAlpha = 1;
    }
    for (const mark of o.illuminations ?? []) {
      const p = screen(mark);
      const radius = Math.max(5, mark.radius * mapRatio);
      const glow = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, radius);
      glow.addColorStop(0, '#f8dfa683'); glow.addColorStop(1, '#ffe0a800');
      ctx.beginPath(); ctx.arc(p.x, p.y, radius, 0, TAU); ctx.fillStyle = glow; ctx.fill();
      ctx.strokeStyle = '#ffe0a87d'; ctx.stroke();
    }
    for (const contact of tracks) {
      const p = screen(contact);
      ctx.beginPath(); ctx.arc(p.x, p.y, target?.id === contact.id ? 21 : 14, 0, TAU);
      ctx.strokeStyle = target?.id === contact.id ? (gesture?.aim?.valid === false ? COLORS.enemy : COLORS.gold) : '#efae875c';
      ctx.setLineDash([3, 3]); ctx.stroke(); ctx.setLineDash([]);
      if (contact.kind && /^(dd|cl)$/i.test(contact.kind)) symbol(ctx, p, contact.heading, contact.kind, COLORS.enemy, false);
      else {
        ctx.beginPath(); ctx.moveTo(p.x, p.y - 8); ctx.lineTo(p.x + 7, p.y); ctx.lineTo(p.x, p.y + 8); ctx.lineTo(p.x - 7, p.y); ctx.closePath();
        ctx.fillStyle = contact.kind === 'radar' ? '#254a5a' : '#502e31'; ctx.fill();
        ctx.strokeStyle = contact.kind === 'radar' ? '#8dd6ef' : COLORS.enemy; ctx.stroke();
      }
    }
    for (const ship of o.ships) {
      const p = screen(ship);
      if (ship.hp <= 0) continue;
      const focused = ship.id === selected;
      if (focused) {
        ctx.beginPath(); ctx.arc(p.x, p.y, 19, 0, TAU); ctx.lineWidth = 1.2; ctx.strokeStyle = COLORS.gold; ctx.stroke();
        line([{ x: p.x - 24, y: p.y }, { x: p.x - 17, y: p.y }], COLORS.gold, 1);
        line([{ x: p.x + 17, y: p.y }, { x: p.x + 24, y: p.y }], COLORS.gold, 1);
      }
      if (ship.speed > 0) line([onBearing(p, ship.heading + 180, 31), onBearing(p, ship.heading + 180, 12)], '#add3c77a', 1, [3, 3]);
      symbol(ctx, p, ship.heading, ship.kind, focused ? COLORS.gold : COLORS.friendly, true);
      if (ship.hp < ship.maxHp) {
        ctx.fillStyle = '#172833'; ctx.fillRect(p.x - 12, p.y + 14, 24, 3);
        ctx.fillStyle = ship.hp / ship.maxHp > .4 ? COLORS.friendly : COLORS.enemy; ctx.fillRect(p.x - 12, p.y + 14, 24 * ship.hp / ship.maxHp, 3);
      }
    }
    if (gesture && activeShip) {
      const from = screen(activeShip);
      if (gesture.weapon === 'torpedo' && gesture.aim && gesture.heading !== undefined && target) {
        const extent = Math.max(19, gesture.aim.range * mapRatio);
        const acceptable = inArcs(gesture.heading, gesture.aim.arcs) && !gesture.cancelled;
        const arcs = new Map(gesture.aim.arcs.map((arc) => [String(arc.from) + ':' + String(arc.to), arc]));
        for (const arc of arcs.values()) {
          const sector = Math.min(360, Math.abs(arc.to - arc.from) >= 359.9 ? 360 : wrap(arc.to - arc.from));
          ctx.beginPath(); ctx.moveTo(from.x, from.y);
          ctx.arc(from.x, from.y, Math.min(extent, Math.hypot(size.w, size.h)), radians(arc.from - 90), radians(arc.from + sector - 90));
          ctx.closePath(); ctx.fillStyle = '#ddbf6c15'; ctx.fill(); ctx.strokeStyle = '#eac17663'; ctx.stroke();
        }
        const end = onBearing(from, gesture.heading, extent);
        line([from, end], acceptable ? COLORS.gold : COLORS.enemy, 2, [9, 5]);
        const handle = onBearing(from, gesture.heading, Math.min(70, extent));
        ctx.beginPath(); ctx.arc(handle.x, handle.y, 4, 0, TAU); ctx.fillStyle = acceptable ? COLORS.gold : COLORS.enemy; ctx.fill();
        line([screen(target), gesture.cursor], '#f6d4977a', 1, [2, 5]);
      } else {
        line([from, target ? screen(target) : gesture.cursor], gesture.cancelled || gesture.aim?.valid === false ? COLORS.enemy : COLORS.gold, 1.6, [6, 4]);
      }
    }
  });

  const relative = (event: ReactPointer): Point => {
    const box = viewport.current!.getBoundingClientRect();
    return { x: event.clientX - box.left, y: event.clientY - box.top };
  };
  const overCancel = (event: ReactPointer) => {
    const box = cancelWell.current?.getBoundingClientRect();
    return !!box && event.clientX >= box.left && event.clientX <= box.right && event.clientY >= box.top && event.clientY <= box.bottom;
  };
  function nearestContact(point: Point, touch: boolean, gunFrom?: number) {
    let closest: Contact | undefined; let best = touch ? 28 : 22;
    for (const contact of tracks) {
      if (contact.kind === 'radar' && (gunFrom === undefined || !o.radarContacts?.find(report => report.id === contact.id)?.usableForShipIds.includes(gunFrom))) continue;
      const gap = distance(screen(contact), point);
      if (gap < best) { best = gap; closest = contact; }
    }
    return closest;
  }
  function aimAt(ship: number, id: string, weapon: Weapon, heading?: number) {
    const nonce = ++aimSequence.current;
    void ask<Aim>({ op: 'aim', ship, target: id, weapon, ...(heading !== undefined ? { heading } : {}) }).then((aim) => {
      const current = gestureRef.current;
      if (!current || current.contact?.id !== id || nonce !== aimSequence.current) return;
      update({ ...current, loading: false, aim, heading: heading === undefined ? aim.heading : current.heading, baseHeading: current.baseHeading ?? aim.heading });
    }, (error: Error) => {
      const current = gestureRef.current;
      if (!current || current.contact?.id !== id || nonce !== aimSequence.current) return;
      update({ ...current, loading: false, aim: { heading: 0, range: 0, arcs: [], valid: false, friendly: false, error: error.message } });
    });
  }
  function start(event: ReactPointer<HTMLButtonElement>, ship: Ship, weapon?: Weapon) {
    if (event.button !== 0 || disabled) return;
    event.stopPropagation();
    props.onSelect(ship);
    if (!weapon) return;
    event.preventDefault();
    const start = relative(event);
    viewport.current!.setPointerCapture(event.pointerId);
    update({ pointer: event.pointerId, ship: ship.id, weapon, start, cursor: start, cancelled: false });
  }
  function pointerDown(event: ReactPointer<HTMLDivElement>) {
    if (disabled || event.button !== 0 || event.target !== canvas.current) return;
    const start = relative(event);
    const waypoint = editing ? waypoints.findIndex((point) => distance(screen(point), start) <= (event.pointerType === 'touch' ? 19 : 13)) : -1;
    surface.current = waypoint >= 0 ? { pointer: event.pointerId, start, waypoint } : { pointer: event.pointerId, start, origin: pan };
    viewport.current!.setPointerCapture(event.pointerId);
  }
  function pointerMove(event: ReactPointer<HTMLDivElement>) {
    const p = relative(event);
    if (!gestureRef.current) setMapPointer(world(p));
    const active = gestureRef.current;
    if (active && active.pointer === event.pointerId) {
      const cancelled = overCancel(event);
      if (active.weapon === 'gun') {
        const hit = cancelled ? undefined : nearestContact(p, event.pointerType === 'touch', active.ship);
        const changed = hit?.id !== active.contact?.id;
        update({ ...active, cursor: p, contact: hit, cancelled, aim: changed ? undefined : active.aim, loading: changed ? !!hit : active.loading });
        if (changed && hit) aimAt(active.ship, hit.id, 'gun');
        return;
      }
      if (active.anchor && active.contact) {
        const origin = o.ships.find((ship) => ship.id === active.ship);
        let heading = active.heading;
        if (!cancelled && origin && active.baseHeading !== undefined) {
          const from = screen(origin);
          const delta = distance(p, active.anchor) < 7 ? 0 : bearing(from, p) - bearing(from, active.anchor);
          heading = Math.round(wrap(active.baseHeading + delta) * 10) / 10;
          if (heading !== active.heading && aimTimer.current === undefined) {
            aimTimer.current = window.setTimeout(() => {
              aimTimer.current = undefined;
              const latest = gestureRef.current;
              if (latest?.contact && latest.heading !== undefined && !latest.cancelled) aimAt(latest.ship, latest.contact.id, 'torpedo', latest.heading);
            }, 80);
          }
        }
        update({ ...active, cursor: p, heading, cancelled });
        return;
      }
      const hit = cancelled ? undefined : nearestContact(p, event.pointerType === 'touch');
      if (hit?.id !== active.contact?.id) {
        window.clearTimeout(hold.current);
        if (hit) hold.current = window.setTimeout(() => {
          const latest = gestureRef.current;
          if (latest?.contact?.id !== hit.id || latest.cancelled) return;
          update({ ...latest, anchor: latest.cursor, loading: true });
          aimAt(latest.ship, hit.id, 'torpedo');
        }, 250);
      }
      update({ ...active, cursor: p, contact: hit, cancelled });
      return;
    }
    const drag = surface.current;
    if (!drag || drag.pointer !== event.pointerId) return;
    if (drag.waypoint !== undefined) { const point = world(p); if (inside(point)) props.onMovePoint(drag.waypoint, point); }
    else if (!editing && distance(drag.start, p) > 4) setPan({ x: drag.origin.x + p.x - drag.start.x, y: drag.origin.y + p.y - drag.start.y });
  }
  function pointerUp(event: ReactPointer<HTMLDivElement>) {
    const p = relative(event);
    const active = gestureRef.current;
    if (active?.pointer === event.pointerId) {
      const cancelled = overCancel(event);
      clearGesture();
      if (cancelled) { props.onCancelFire?.(); return; }
      if (disabled) return;
      if (active.weapon === 'gun') {
        const hit = nearestContact(p, event.pointerType === 'touch', active.ship);
        if (hit && active.contact?.id === hit.id && active.aim?.valid === false) props.onHint(active.aim.error ?? '此目标当前不可炮击。');
        else if (hit) props.onFire(active.ship, active.weapon, hit.id);
        else if (distance(p, active.start) > 10) props.onHint('没有下令。请拖到一个可见敌舰。');
      } else if (active.anchor && active.contact && active.aim && active.heading !== undefined) {
        const adjusted = active.baseHeading !== undefined && Math.abs(active.heading - active.baseHeading) > .15;
        if (!o.contacts.some((contact) => contact.id === active.contact!.id)) props.onHint('未发射：接触已经丢失。');
        else if (!inArcs(active.heading, active.aim.arcs)) props.onHint('未发射：鱼雷航向超出发射扇区。');
        else if (!adjusted && !active.aim.valid) props.onHint(active.aim.error ?? '推荐射向当前不可用。');
        else props.onFire(active.ship, active.weapon, active.contact.id, adjusted ? active.heading : undefined);
      } else if (distance(p, active.start) > 10) props.onHint(active.aim?.error ?? '未发射：在敌舰上短暂停留，等推荐射向出现。');
      return;
    }
    const drag = surface.current;
    if (drag?.pointer === event.pointerId) {
      surface.current = undefined;
      if (editing && drag.waypoint === undefined && distance(drag.start, p) < 8) {
        const point = world(p);
        if (inside(point)) props.onAddPoint(point);
        else props.onHint('航点须落在演习海域内。');
      } else if (!editing && distance(drag.start, p) < 8) {
        const contact = nearestContact(p, event.pointerType === 'touch');
        if (contact && props.onInspectContact) props.onInspectContact(contact.id);
        else props.onInspectMap?.();
      }
    }
  }

  const aimInArc = gesture?.aim && gesture.heading !== undefined && inArcs(gesture.heading, gesture.aim.arcs);
  return <div
    className={'battle-map' + (editing ? ' map-editing' : '')}
    ref={viewport} aria-label="战术海图"
    onPointerDown={pointerDown} onPointerMove={pointerMove} onPointerUp={pointerUp} onPointerCancel={cancelAll}
    onLostPointerCapture={(event) => { if (gestureRef.current?.pointer === event.pointerId || surface.current?.pointer === event.pointerId) cancelAll(); }}
    onPointerLeave={() => setMapPointer(undefined)}
    onWheel={(event) => { if (!gestureRef.current) setZoom((value) => Math.max(.75, Math.min(4, value * (event.deltaY < 0 ? 1.12 : 1 / 1.12)))); }}
  >
    <canvas ref={canvas} aria-hidden="true" />
    <BattleProjectiles key={session} observation={o} map={{ left, bottom, ratio: mapRatio, width: size.w, height: size.h }} running={running} speed={speed} />
    {contacts.map(({ contact, at, lane }) => <div key={contact.id} data-contact={contact.id}
      className={'contact-label' + (target?.id === contact.id ? ' targeted' : '')} style={pointStyle(at)}>
      <span style={{ top: lane < 0 ? 23 : 17 + 11 * lane }} hidden={lane < 0 && target?.id !== contact.id}>
        {target?.id === contact.id && contact.name ? contact.name + ' · ' + contact.id : contact.id}
      </span>
    </div>)}
    {o.ships.filter((ship) => ship.hp > 0).map((ship) => {
      const point = screen(ship);
      const focused = ship.id === selected;
      const canGun = ship.gun && !disabled;
      const canTorpedo = ship.torpedo && !disabled;
      const title = ship.name;
      return <div key={ship.id} className={'map-ship' + (focused ? ' focused' : '')}
        data-ship={ship.id} style={pointStyle(point)}>
        {(focused || gesture?.ship === ship.id || ship.systems?.guns.some((mount) => mount.bearing != null)) && ship.systems?.guns.map((mount, index, mounts) => {
          if (mount.destroyed) return null;
          const fraction = (index + .5) / mounts.length;
          const offset = (0.5 - fraction) * (ship.kind === 'cl' ? 24 : 18);
          const rest = wrap(ship.heading + (fraction > .5 ? 180 : 0));
          const previewBearing = gesture?.ship === ship.id && gesture.weapon === 'gun' && gesture.aim?.valid && target ? bearing(point, screen(target)) : undefined;
          const relative = previewBearing === undefined ? 0 : wrap(previewBearing - ship.heading);
          const canTrack = previewBearing !== undefined && [mount.arc, mount.arc2].some((arc) => arc && inArcs(relative, [{ from: arc[0], to: arc[1] }]));
          const trained = (canTrack ? previewBearing : undefined) ?? mount.bearing;
          return <TurretBarrel key={mount.index} at={onBearing({ x: 0, y: 0 }, ship.heading, offset)}
            bearing={trained ?? rest} rest={rest} active={trained != null} />;
        })}
        <button type="button" className="ship-hull" aria-label={title}
          onPointerDown={(event) => start(event, ship, canGun === canTorpedo ? undefined : canGun ? 'gun' : 'torpedo')}
          onClick={() => !disabled && props.onSelect(ship)} />
        {(canGun || canTorpedo) && <div className="weapon-badges">
          {canGun && <button type="button" className="weapon gun" aria-label={title + ' 炮击'} title={title + '：拖至敌舰炮击'}
            onPointerDown={(event) => start(event, ship, 'gun')}>炮</button>}
          {canTorpedo && <button type="button" className="weapon torpedo" aria-label={title + ' 雷击'} title={title + '：拖至敌舰瞄准鱼雷'}
            onPointerDown={(event) => start(event, ship, 'torpedo')}>雷</button>}
        </div>}
        <span className="map-ship-name">{ship.id === fleet?.leader ? '⚑ ' : ''}{title}</span>
      </div>;
    })}
    <div className="map-compass"><Compass /></div>
    <BattleAlerts events={o.events} tick={o.tick} session={session} enabled={!replaying} />
    <div className="map-note">
      <strong>{editing ? '在海图点选途经点' : reformPreview ? '重整纵队预览' : night ? '夜航接敌' : o.variant === 'challenge' ? '少舰迎击' : '昼间水面演习'}</strong>
      <span>{editing ? '拖动编号航点可修正航线' : o.variant === 'radar' ? '虚构夜间演习 · 雷达回波 R' : night ? '虚构夜间演习 · 目视搜索' : '虚构演习 · 开阔水域'}</span>
    </div>
    {gesture && <div className={'gesture-tip' + (gesture.aim?.friendly || gesture.aim?.valid === false || (gesture.weapon === 'torpedo' && aimInArc === false) ? ' warning' : '')}>
      <strong>{gesture.weapon === 'gun' ? (target ? '炮击 ' + (target.name ?? target.id) : '炮击 · 拖向敌舰') :
        gesture.loading ? '正在计算推荐射向' : gesture.aim && gesture.heading !== undefined ? '鱼雷瞄准 ' + String(Math.round(gesture.heading) % 360).padStart(3, '0') + '°' :
        target ? '在接触上短暂停留' : '鱼雷 · 拖向敌舰'}</strong>
      <span>{gesture.cancelled ? '松手取消，不消耗弹药' :
        gesture.weapon === 'gun' && target ? (gesture.aim?.error || (gesture.aim?.barrels ? String(gesture.aim.barrels) + ' 门炮可用 · 松手下令' : '正在校核射界')) :
        gesture.aim?.friendly ? '注意：已知友舰可能进入雷迹' :
        aimInArc === false ? (gesture.aim?.error ?? '射向超出扇区') : gesture.aim ? (gesture.aim.error ?? '拖动微调，松手下令') :
        target && gesture.weapon === 'gun' ? '松手下令' : '可拖至取消区'}</span>
    </div>}
    <div ref={cancelWell} className={'cancel-well' + (gesture ? ' visible' : '') + (gesture?.cancelled ? ' hot' : '')} aria-hidden={!gesture}>
      <span>×</span> {gesture?.cancelled ? '松手取消' : '拖到这里取消'}
    </div>
    <div className="map-tools">
      <div className="scale-bar"><span style={{ width: Math.min(150, scaleMeters * mapRatio) }} />{scaleMeters / 1000} km</div>
      <button type="button" onClick={() => setZoom((value) => Math.min(4, value * 1.25))} aria-label="放大海图">+</button>
      <button type="button" onClick={() => setZoom((value) => Math.max(.75, value / 1.25))} aria-label="缩小海图">−</button>
      <button type="button" onClick={() => { setZoom(1); setPan({ x: 0, y: 0 }); }} aria-label="恢复海图范围">◎</button>
      <button type="button" className="range-toggle" onClick={() => setRangesVisible((value) => !value)}
        aria-pressed={rangesVisible} aria-label="显示所选舰射程">射程</button>
    </div>
    <div className="map-legend">
      <span><i />己方</span><span><i />敌方接触</span><span><i />计划航线</span>
      {mapPointer && inside(mapPointer) && <output>{(mapPointer.x / 1000).toFixed(1)}E {(mapPointer.y / 1000).toFixed(1)}N</output>}
    </div>
    {rangesVisible && !editing && !reformPreview && !gesture && (gunRange > 0 || torpedoRange > 0) && <div className="range-legend" aria-label="所选舰最大射程">
      {gunRange > 0 && <span><i className="gun-ring" />舰炮 {(gunRange / 1000).toFixed(1)} km</span>}
      {torpedoRange > 0 && <span><i className="torpedo-ring" />鱼雷 {(torpedoRange / 1000).toFixed(1)} km</span>}
    </div>}
  </div>;
}
