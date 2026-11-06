import { useState } from 'react';
import type { Observation } from '../engine';
import { baixisPortrait as baixiPortrait, prologueArt, prologueVictory } from './art';
import { nextPrologueStep, PROLOGUE_LAST_STEP } from './originalScript';
import { PrologueDialogue } from './PrologueDialogue';
import { PrologueChart, PrologueFilm } from './PrologueFilm';
import { DD_PERSONALITIES } from './story';
import type { PrologueBattleStage, PrologueProgress, StarterDDId } from './story';
import './prologue.css';

type Props = {
  progress: PrologueProgress;
  onProgress: (progress: PrologueProgress) => void;
  onBattle: (stage: PrologueBattleStage, leaderId: StarterDDId) => void;
  onFinish: (leaderId: StarterDDId) => void | Promise<void>;
  onExit: () => void;
  busy?: boolean;
  error?: string;
  recording?: readonly Observation[];
  battle?: Observation;
  radioKey?: string;
  rewards?: readonly string[];
  claimed?: boolean;
};

const exercises: Record<number, { stage: PrologueBattleStage; title: string; instruction: string }> = {
  7: { stage: 'follow', title: '第五驱逐编队 · 侧翼机动', instruction: '选择领舰移动，画出至少两个途经点，核对每艘舰的航迹后下令。用舰上的炮标完成一次实际炮击。' },
  19: { stage: 'sync', title: '总指挥改令 · 同步机动', instruction: '重新画出一条同步航线，确认各舰不会挤到同一个转向点，再下达命令。' },
  24: { stage: 'torpedo', title: '雷击准备 · 检查发射方向', instruction: '拖住雷标，在本方已发现的敌舰上停留。等推荐射向出现后调整角度，再松开下令。完成实际发射即可继续。' },
};

function BridgeBackdrop() {
  return <svg className="prologue-backdrop" viewBox="0 0 1200 600" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
    <defs>
      <linearGradient id="pg-sea" x2=".9" y2="1"><stop stopColor="#112a44"/><stop offset=".57" stopColor="#183c50"/><stop offset="1" stopColor="#060f21"/></linearGradient>
      <radialGradient id="pg-moon"><stop stopColor="#b3c8cd" stopOpacity=".47"/><stop offset="1" stopColor="#a4c4cf" stopOpacity="0"/></radialGradient>
    </defs>
    <path d="M0 0h1200v600H0z" fill="url(#pg-sea)"/>
    <circle cx="786" cy="239" r="208" fill="url(#pg-moon)"/>
    <path d="M0 306h1200v300H0z" fill="#112e42" opacity=".72"/>
    <path d="M0 311q150 16 270 0t380-6 550-4M0 346q125-9 291 0t408-2 501 0M0 391q168 15 426-7t774 8m-1200 33q185-7 386 0t814-2" stroke="#91b9b7" strokeWidth="1.5" fill="none" opacity=".23"/>
    <g fill="#0a1624" stroke="#4d7183" strokeWidth="1.3" opacity=".88">
      <path d="M689 352h70l42-8 44-2v-14h21v-9h37v-9h14v16h15v15h64l16 4 76-6-18 15-28 11H715z"/>
      <path d="M914 313v-39m-11 18h26m-17-4 9-9m-58 56v-22m-9 10h20" fill="none"/>
      <path d="M1115 357h41l18 2 16-4-8 9h-63z"/>
    </g>
    <path d="M838 332h5m13 0h7m12-6h4m15 0h5m34 14h7m9 0h9" stroke="#efc78d" strokeWidth="1.4" opacity=".65"/>
    <path d="M0 0h1200v28H0zM0 0h51l97 600H0zm1200 0h-26l-61 600h87z" fill="#081827" opacity=".78"/>
    <path d="M0 444q192-44 363 0l90 156H0z" fill="#0a1e2f" stroke="#294856" strokeWidth="2"/>
    <path d="M32 472l238-19 67 96-257 14z" fill="#162b39" stroke="#4a6870" strokeWidth="2"/>
    <path d="M103 508l149-19m-128 28 136-14m-159 29 119-10" stroke="#85a4a6" strokeWidth="1.3" opacity=".38"/>
  </svg>;
}

export function PrologueScene({ progress, onProgress, onBattle, onFinish, onExit, busy = false, error, recording, battle, radioKey, rewards, claimed }: Props) {
  const [reviewing, setReviewing] = useState(false);
  const [claiming, setClaiming] = useState(false);
  const [localError, setLocalError] = useState('');
  const step = progress.step;
  const leader = DD_PERSONALITIES.find((ship) => ship.id === progress.leaderId) ?? DD_PERSONALITIES[0];
  const chapter = step < 7 ? '交接指挥' : step < 18 ? '侧翼机动' : step < 24 ? '改令同步' : step < 29 ? '编队雷击' : '黎明归港';
  const exercise = exercises[step];

  function patch(next: Partial<PrologueProgress>) { onProgress({ ...progress, ...next }); }
  function advance(flag?: string) {
    patch({ step: nextPrologueStep(step), dialogue: 0, flags: { ...progress.flags, ...(flag ? { [flag]: true } : {}) } });
  }
  async function finish() {
    if (claiming || busy) return;
    if (claimed) { onExit(); return; }
    setLocalError(''); setClaiming(true);
    try { await onFinish(leader.id); }
    catch (failure) { setLocalError(failure instanceof Error ? failure.message : '未能领取，请重试。'); }
    finally { setClaiming(false); }
  }

  return <main className={'prologue-scene' + (step === PROLOGUE_LAST_STEP && !reviewing ? ' prologue-victory-mode' : '')} aria-label="序章：未明的海">
    <header className="prologue-header">
      <div className="prologue-wordmark"><span>序章</span><strong>未明的海</strong><small>{reviewing ? '回看开场' : chapter}</small></div>
      <nav aria-label="序章操作">
        {step > 0 && <button type="button" disabled={busy || claiming} onClick={() => setReviewing((current) => !current)}>{reviewing ? '返回剧情' : '回看开场'}</button>}
        <button type="button" disabled={busy || claiming} onClick={onExit}>离开序章</button>
      </nav>
    </header>
    <div className="prologue-deck">
      {battle && step > 0 && step < PROLOGUE_LAST_STEP && !reviewing
        ? <div className="prologue-film"><PrologueChart frame={battle} focus /></div>
        : <BridgeBackdrop />}
      {(step === 0 || reviewing) && <>
        <PrologueFilm key={reviewing ? 'review' : 'opening'} opening radioKey={radioKey} />
        <section className="prologue-cinematic">
          <div><span>第五驱逐编队</span><h1>未明的海</h1><p>海面正在燃烧，而你的记忆停在了炮声之前。</p></div>
          <button type="button" className="primary" disabled={busy} onClick={() => reviewing ? setReviewing(false) : advance('cinema-0')}>{reviewing ? '返回当前剧情' : '进入舰桥'}</button>
        </section>
      </>}
      {!reviewing && <PrologueDialogue progress={progress} onProgress={onProgress} placement={battle ? 'chart' : 'scene'} />}
      {!reviewing && step === 3 && <>
        <img className="prologue-speaker-art" src={baixiPortrait} alt="白汐" />
        <section className="prologue-note prologue-binding">
          <span>辅助连接已建立</span><h1>白汐</h1><p>我会为你整理舰队情报、核对航路和火力。每一道命令，仍由你决定。</p>
          <button type="button" className="primary" onClick={() => advance('assistant-bound')}>接入辅助</button>
        </section>
      </>}
      {!reviewing && step === 5 && <section className="prologue-roster" aria-label="选定剧情领舰">
        <div><h1>选一位，升起领舰旗</h1><p>五位舰娘都已在同一片海上。选一艘舰带第五驱逐小队出航。</p></div>
        <div className="prologue-roster-list">
          {DD_PERSONALITIES.map((ship) => <button key={ship.id} type="button" className="prologue-character" aria-pressed={leader.id === ship.id}
            aria-label={ship.name} onClick={() => patch({ leaderId: ship.id })}>
            <img src={prologueArt(ship.portrait)} alt=""/><strong>{ship.name}</strong><small>{ship.role}</small>
          </button>)}
        </div>
        <button type="button" className="primary" onClick={() => advance('leader-selected')}>任命{leader.name}为领舰</button>
      </section>}
      {!reviewing && exercise && <section className="prologue-note prologue-exercise" aria-label="序章实操">
        <span>白汐 · 实操引导</span><h1>{exercise.title}</h1><p>{exercise.instruction}</p>
        <button type="button" className="primary" disabled={busy} onClick={() => onBattle(exercise.stage, leader.id)}>前往海图实操</button>
      </section>}
      {!reviewing && (step === 11 || step === 22 || step === 28) && <>
        {!battle && <PrologueFilm key={step} recording={recording} />}
        <section className="prologue-cinematic">
          <div><span>第五驱逐编队</span><h1>{step === 11 ? '领舰航线确认' : step === 22 ? '同步航线确认' : '鱼雷已实际发射'}</h1>
            <p>{step === 11 ? '尾舰沿领舰实际航迹机动。' : step === 22 ? '每艘舰保持自己的航迹，按同一时点转向。' : '保留本方真实战情。发射与命中分别记录。'}</p></div>
          <button type="button" className="primary" onClick={() => advance('cinema-' + step)}>返回剧情</button>
        </section>
      </>}
      {!reviewing && step === PROLOGUE_LAST_STEP && <section className="prologue-victory">
        <img src={prologueVictory} alt="黎明甲板上，弗莱彻牵住指挥官的手，白汐和其余驱逐舰迎接归队" />
        <div className="prologue-victory-text"><span>序章完成</span><h1>我们，一起回港</h1><p>五艘驱逐舰，和一个新的开始。</p>
          <ul className="prologue-victory-roster" aria-label="剧情编队">{DD_PERSONALITIES.map((ship) => <li key={ship.id}>{ship.name}{ship.id === leader.id ? ' · 剧情领舰' : ''}</li>)}</ul>
          <p className="prologue-reward-note">剧情角色按原身份记录；见面礼使用当前可出战的 CAS 舰型。</p>
          {rewards?.length ? <ul aria-label="序章见面礼">{rewards.map((item) => <li key={item}>{item}</li>)}</ul> : null}
          <button type="button" className="primary" disabled={busy || claiming} onClick={() => void finish()}>{busy || claiming ? '正在记录航程…' : claimed ? '返回母港' : '领取序章奖励'}</button>
        </div>
      </section>}
      {(error || localError) && <p className="prologue-error" role="alert">{error || localError}</p>}
    </div>
  </main>;
}
