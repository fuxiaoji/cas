import { useEffect, useRef, useState } from 'react';
import { prologueArt } from './art';
import { nextPrologueStep } from './originalScript';
import type { DialogueLine } from './originalScript';
import { storyDialogue } from './story';
import type { PrologueProgress } from './story';
import './prologue.css';

const memoryChoices = [
  ['lost', '我……什么都想不起来。'],
  ['duty', '先告诉我，舰队怎么样了？'],
  ['trust', '你是谁？我能相信你吗？'],
] as const;

type Props = {
  progress: PrologueProgress;
  onProgress: (progress: PrologueProgress) => void;
  placement?: 'scene' | 'chart';
};

export function hasPrologueDialogue(progress: PrologueProgress) {
  return storyDialogue(progress).length > 0;
}

export function PrologueDialogue({ progress, onProgress, placement = 'scene' }: Props) {
  const lines = storyDialogue(progress);
  const index = Math.min(progress.dialogue, lines.length - 1);
  const line = lines[index];
  if (!line) return null;

  const wantsAnswer = progress.step === 1 && index === lines.length - 1;
  function nextLine() {
    if (index + 1 < lines.length) onProgress({ ...progress, dialogue: index + 1 });
    else if (!wantsAnswer) onProgress({ ...progress, step: nextPrologueStep(progress.step), dialogue: 0 });
  }
  function answer(memory: string) {
    onProgress({ ...progress, step: 2, dialogue: 0, answers: { ...progress.answers, memory } });
  }

  return <DialogueFrame key={progress.step + ':' + index + ':' + line.text} line={line}
    placement={placement} wantsAnswer={wantsAnswer} onNext={nextLine} onAnswer={answer} />;
}

function DialogueFrame({ line, placement, wantsAnswer, onNext, onAnswer }: {
  line: DialogueLine; placement: NonNullable<Props['placement']>; wantsAnswer: boolean;
  onNext: () => void; onAnswer: (answer: string) => void;
}) {
  const [visible, setVisible] = useState(0);
  const panel = useRef<HTMLElement>(null);
  const letters = Array.from(line.text);
  const complete = visible >= letters.length;
  const artwork = prologueArt(line.portrait);
  const [speaker, role] = line.speaker.split(' · ');

  useEffect(() => {
    if (placement === 'chart') panel.current?.focus({ preventScroll: true });
  }, [placement]);
  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setVisible(letters.length);
      return;
    }
    let count = 0;
    const timer = window.setInterval(() => {
      ++count;
      setVisible(previous => Math.max(previous, count));
      if (count >= letters.length) window.clearInterval(timer);
    }, 22);
    return () => window.clearInterval(timer);
  }, [letters.length]);

  function continueDialogue() {
    if (complete) onNext();
    else setVisible(letters.length);
  }

  return <div className={`prologue-dialogue-layer prologue-dialogue-${placement}`}>
    {artwork && <img className={'prologue-speaker-art' + (line.shipId ? ' destroyer' : '')} src={artwork} alt="" />}
    <section ref={panel} tabIndex={placement === 'chart' ? -1 : undefined} className="prologue-dialogue" aria-label="剧情对话">
      <div className="prologue-speaker">
        <h2>{speaker}</h2>{role && <small>{role}</small>}
      </div>
      <span className="prologue-accessible-line" aria-live="polite">{line.text}</span>
      <p aria-hidden="true">{letters.slice(0, visible).join('')}</p>
      {wantsAnswer && complete ? <div className="prologue-answers" aria-label="回应白汐">
        {memoryChoices.map(([id, text]) => <button key={id} type="button" onClick={() => onAnswer(id)}>{text}</button>)}
      </div> : <button type="button" className="prologue-next" onClick={continueDialogue}>{complete ? '继续对话' : '显示整句'}</button>}
    </section>
  </div>;
}
