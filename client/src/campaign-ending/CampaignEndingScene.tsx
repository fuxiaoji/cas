// Fullscreen artwork, cast toggle and zoom adapted from the original 0.6.11 scene.
import { useEffect, useId, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { campaignText } from '../campaign-labels';
import type { Observation } from '../engine';
import { campaignEndingFor, endingLayout } from './ending';
import type { EndingFrame } from './ending';
import './campaign-ending.css';

function CampaignEndingArtwork({ frame, showNames }: { frame: EndingFrame; showNames: boolean }) {
  const placements = useMemo(() => endingLayout(frame), [frame]);
  const [failedArt, setFailedArt] = useState<ReadonlySet<string>>(() => new Set());
  const fullArt = frame.illustration && !failedArt.has(frame.illustration) ? frame.illustration : undefined;
  const source = fullArt ?? frame.plate;
  return <div className={`campaign-ending__frame campaign-art--${frame.outcome}`} data-cast={frame.actors.length}
    data-art-kind={fullArt ? 'illustration' : 'ensemble'}>
    {source && !failedArt.has(source) && <img className="campaign-ending__plate" src={source}
      alt={fullArt ? frame.outcome === 'defeat' ? '本方舰娘漂抵海滩的战败插画' : '本方舰娘在甲板庆祝的胜利插画' : ''}
      fetchPriority="high" draggable={false} onError={() => setFailedArt(previous => new Set([...previous, source]))} />}
    {!fullArt && <div className="campaign-ending__ensemble" aria-hidden="true">
      {placements.map(({ actor, x, y, width, height, angle }) => actor.portrait &&
        <div className="campaign-ending__actor" key={actor.id} style={{ left: `${x}%`, top: `${y}%`, width: `${width}%`, height: `${height}%` }}>
          <img src={actor.portrait} alt="" draggable={false} decoding="async" style={{ rotate: `${angle}deg` }} />
        </div>)}
    </div>}
    <ol className="campaign-ending__cast-list" hidden={!showNames} aria-label="本方参战舰娘">
      {frame.actors.map(actor => <li data-ship-id={actor.id} key={actor.id}>{actor.name}</li>)}
    </ol>
  </div>;
}

function CampaignEndingScene({ frame, onContinue }: { frame: EndingFrame; onContinue: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const viewport = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const [zoom, setZoom] = useState(false);
  const [showNames, setShowNames] = useState(false);
  useEffect(() => {
    const element = dialog.current;
    element?.showModal();
    return () => element?.close();
  }, []);
  useEffect(() => {
    const back = (event: Event) => {
      event.stopImmediatePropagation();
      onContinue();
    };
    window.addEventListener('hardware-back', back, true);
    return () => window.removeEventListener('hardware-back', back, true);
  }, [onContinue]);

  return <dialog ref={dialog} className={`campaign-ending campaign-ending--${frame.outcome}`} aria-labelledby={titleId}
    data-stage-id={frame.stageId} data-side={frame.side} data-outcome={frame.outcome}
    onCancel={event => { event.preventDefault(); onContinue(); }}>
    <div className="campaign-ending__layout">
      <figure className="campaign-ending__art">
        <div className="campaign-ending__viewport" ref={viewport} data-zoom={zoom || undefined}>
          <CampaignEndingArtwork frame={frame} showNames={showNames} />
        </div>
      </figure>
      <footer className="campaign-ending__footer">
        <div className="campaign-ending__text">
          <div className="campaign-ending__title"><h2 id={titleId}>{frame.outcome === 'victory' ? '战斗胜利' : '战斗失利'}</h2>
            <span>{frame.stageTitle}</span></div>
          <p>{frame.side === 'allies' ? '同盟' : '轴心'}战线 · 本方 {frame.actors.length} 舰参战</p>
          {frame.resultText && <p>{campaignText(frame.resultText)}</p>}
        </div>
        <div className="campaign-ending__actions">
          <button type="button" aria-pressed={showNames} onClick={() => setShowNames(value => !value)}>{showNames ? '隐藏舰名' : '舰名'}</button>
          <button type="button" aria-pressed={zoom} onClick={() => { viewport.current?.scrollTo(0, 0); setZoom(value => !value); }}>{zoom ? '全景' : '放大'}</button>
          <button type="button" className="primary" autoFocus onClick={onContinue}>查看战果</button>
        </div>
      </footer>
    </div>
  </dialog>;
}

export function CampaignEndingGate({ observation, seen, onContinue, children }: {
  observation: Observation; seen: boolean; onContinue: () => void; children: ReactNode;
}) {
  const frame = useMemo(() => campaignEndingFor(observation), [observation]);
  return frame && !seen ? <CampaignEndingScene frame={frame} onContinue={onContinue} /> : <>{children}</>;
}
