import { useEffect, useState } from 'react';
import { BattleMap } from '../BattleMap';
import { clock } from '../engine';
import type { Observation, Request } from '../engine';

const noAction = () => undefined;
type Receipt = { id: number; response: { ok: true; data: Observation } | { ok: false; error: string } };

async function captureFilm(worker: Worker): Promise<Observation[]> {
  let id = 0;
  const call = (request: Request) => new Promise<Observation>((resolve, reject) => {
    const sequence = ++id;
    worker.onmessage = ({ data }: MessageEvent<Receipt>) => {
      if (data.id !== sequence) return;
      if (data.response.ok) resolve(data.response.data);
      else reject(new Error(data.response.error));
    };
    worker.onerror = () => reject(new Error('开场战斗记录暂时不能播放。'));
    worker.postMessage({ id: sequence, request });
  });
  const initial = await call({ op: 'new', seed: 6106, side: 'axis', enemy: 'gunnery', profile: 'torpedo' });
  await call({ op: 'ai', fleet: initial.fleets[0].id, profile: 'torpedo', mode: 'auto', move: true, gun: true, torpedo: true });
  // Two cuts of the same CAS exercise. Everything is from a single seat;
  // neither the footage nor its commands modify the player's current battle.
  const result = [await call({ op: 'step', seconds: 177 })];
  for (let i = 0; i < 12; i++) result.push(await call({ op: 'step', seconds: 1 }));
  result.push(await call({ op: 'step', seconds: 715 - result.at(-1)!.tick }));
  for (let i = 0; i < 28; i++) result.push(await call({ op: 'step', seconds: i < 10 ? 1 : 4 }));
  return result;
}

export function PrologueFilm({ recording, opening }: { recording?: readonly Observation[]; opening?: boolean }) {
  const [captured, setCaptured] = useState<Observation[]>([]);
  const [failed, setFailed] = useState(false);
  const [cursor, setCursor] = useState(0);
  const [playing, setPlaying] = useState(true);
  const frames = opening ? captured : recording ?? [];
  const frame = frames[Math.min(cursor, frames.length - 1)];
  useEffect(() => {
    if (!opening) return;
    let active = true;
    const worker = new Worker(new URL('./engine-worker.js', document.baseURI), { name: 'CAS prologue film' });
    const deadline = window.setTimeout(() => { if (active) setFailed(true); }, 8500);
    void captureFilm(worker).then((clip) => { if (active) setCaptured(clip); }, () => { if (active) setFailed(true); })
      .finally(() => { window.clearTimeout(deadline); worker.terminate(); });
    return () => { active = false; window.clearTimeout(deadline); worker.terminate(); };
  }, [opening]);
  useEffect(() => {
    if (!playing || cursor + 1 >= frames.length || !frames.length) return;
    const timer = window.setTimeout(() => setCursor((current) => current + 1), 180);
    return () => window.clearTimeout(timer);
  }, [cursor, frames.length, playing]);
  return <div className="prologue-film" aria-label={opening ? 'CAS 演习开场回放' : '本局行动回放'}>
    {frame ? <>
      <div className="prologue-film-map" aria-hidden="true"><BattleMap observation={frame} fleet={frame.fleets[0]}
        disabled session={-1} running={playing} speed={8} replaying editing={false} waypoints={[]} onSelect={noAction}
        onAddPoint={noAction} onMovePoint={noAction} onFire={noAction} onHint={noAction} /></div>
      <div className="prologue-film-strip"><span>{opening ? 'CAS 实战片段 · 虚构 5 对 5 演习 · 轴心席' : '本局实录 · 本方视角'} <time>{clock(frame.tick)}</time></span>
        <button type="button" onClick={() => { if (cursor + 1 >= frames.length) { setCursor(0); setPlaying(true); } else setPlaying((active) => !active); }}>
          {cursor + 1 >= frames.length ? '重播' : playing ? '暂停回放' : '继续回放'}
        </button></div>
    </> : <div className="prologue-film-message" role="status">{failed ? '演习记录未能打开。你可以进入舰桥继续剧情。' : opening ? '正在打开 CAS 演习记录…' : '本局操作已通过战斗裁决，发射时点与方向可在战情中查阅。'}</div>}
  </div>;
}
