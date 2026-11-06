export type Side = 'allies' | 'axis';
export type Profile = 'coord' | 'gunnery' | 'torpedo';
export type Maneuver = 'follow' | 'sync';
export type Weapon = 'gun' | 'torpedo';
export interface Point { x: number; y: number }
export interface Position extends Point { heading: number; speed: number }
export interface Ship extends Position {
  id: number; name: string; kind: 'dd' | 'cl'; fleet: number | null;
  hp: number; maxHp: number; gun: boolean; torpedo: boolean; ammo: number;
  classId?: string; characterId?: string; gunRange?: number; torpedoRange?: number; systems?: ShipSystems;
}
export interface ShipSystems {
  guns: { index: number; barrels: number; destroyed: boolean; arc?: [number, number]; arc2?: [number, number] | null; bearing?: number | null }[];
  tubes: { index: number; tubes: number; spent: boolean }[];
  directorDamaged: boolean; engineeringLevels: number; fires: number; floods: number; maxSpeed: number;
}
export interface Shell extends Point {
  id: number; heading: number; progress: number; from?: Point; to?: Point;
  launchTick: number; impactTick: number; own: boolean; barrels?: number;
}
export interface Torpedo extends Point { id: number; heading: number; own: boolean; from?: Point; count?: number }
export interface Contact extends Position { id: string; kind?: string; name?: string }
export interface Path { ship: number; points: Point[] }
export interface AiConfig {
  profile: Profile; mode: 'manual' | 'suggest' | 'auto'; move: boolean; gun: boolean; torpedo: boolean;
}
export interface Fleet {
  id: number; name: string; leader: number; members: number[];
  mode: Maneuver; speed: number; points: Point[]; paths: Path[]; ai: AiConfig; notice?: string;
}
export interface LogEvent { id?: number | string; tick: number; kind: string; text: string; rule?: string; x?: number; y?: number; voiceCue?: string }
export interface Result { winner: string; allies: number; axis: number; primary?: boolean }
export interface Observation {
  tick: number; limit: number; width: number; height: number; side: Side; scenario: string;
  variant?: string; settling?: boolean;
  ships: Ship[]; fleets: Fleet[]; contacts: Contact[];
  torpedoes: Torpedo[]; shells?: Shell[];
  events: LogEvent[]; result: Result | null; islands: Point[][];
}
export interface RoutePreview { valid: boolean; error?: string; paths: Path[]; speed: number }
export interface Aim {
  heading: number; range: number; arcs: { from: number; to: number }[];
  friendly: boolean; valid: boolean; error?: string; barrels?: number;
}
export interface Suggestion { orders: Request[]; text: string }
export type Request = { op: string; [key: string]: unknown };
type Message = { id: number; response: { ok: true; data: unknown } | { ok: false; error: string } };

export const profileNames: Record<Profile, string> = { coord: '协同', gunnery: '炮战', torpedo: '雷击' };
export const sideNames: Record<Side, string> = { allies: '同盟舰队', axis: '轴心舰队' };
export const maneuverNames: Record<Maneuver, string> = { follow: '领舰移动', sync: '同步移动' };

let worker: Worker | undefined;
let sequence = 0;
const pending = new Map<number, { resolve: (value: unknown) => void; reject: (error: Error) => void }>();

export function ask<T>(request: Request): Promise<T> {
  if (!worker) {
    worker = new Worker(new URL('./engine-worker.js', document.baseURI), { name: 'CAS battle' });
    worker.onmessage = ({ data }: MessageEvent<Message>) => {
      const call = pending.get(data.id);
      if (!call) return;
      pending.delete(data.id);
      if (data.response.ok) call.resolve(data.response.data);
      else call.reject(new Error(data.response.error));
    };
    worker.onerror = () => {
      for (const call of pending.values()) call.reject(new Error('战斗内核没有启动。请重新打开指挥台。'));
      pending.clear();
      worker?.terminate();
      worker = undefined;
    };
  }
  const id = ++sequence;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve: (value) => resolve(value as T), reject });
    worker!.postMessage({ id, request });
  });
}

export function clock(tick: number) {
  const time = Math.max(0, Math.floor(tick));
  return String(Math.floor(time / 60)).padStart(2, '0') + ':' + String(time % 60).padStart(2, '0');
}
