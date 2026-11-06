import { useEffect, useState } from 'react';
import { baixisPortrait } from '../prologue/art';
import { trainingCourses, trainingStepDone } from './curriculum';
import type { CourseId, TrainingEvidence } from './curriculum';
import './training-coach.css';

type Props = { course: CourseId; evidence: TrainingEvidence; onFinish: () => void; onExit: () => void;
  onGuide?: (selector: string) => void; lightingAvailable?: boolean };

export function TrainingCoach({ course, evidence, onFinish, onExit, onGuide, lightingAvailable = true }: Props) {
  const [expanded, setExpanded] = useState(true);
  const [pulse, setPulse] = useState(0);
  const { title, steps } = trainingCourses[course];
  const complete = steps.filter((item) => trainingStepDone(item, evidence)).length;
  const current = steps.find((item) => !trainingStepDone(item, evidence));

  useEffect(() => {
    if (!pulse || !current || onGuide) return;
    const target = document.querySelector<HTMLElement>(current.guide);
    if (!target) return;
    target.classList.add('training-target');
    target.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    const timer = window.setTimeout(() => target.classList.remove('training-target'), 1600);
    return () => { window.clearTimeout(timer); target.classList.remove('training-target'); };
  }, [pulse, current?.id, onGuide]);

  const missingLight = current?.id === 'campaign-night-light' && !lightingAvailable;
  return <section className={'training-coach' + (expanded ? ' expanded' : '')} aria-label="白汐实操引导">
    <div className="training-coach-head">
      <img src={baixisPortrait} alt="" />
      <div><span>{title}</span><h2>{current?.title ?? '实操完成'}</h2></div>
      <div className="training-coach-toggle">
        <span aria-label="教学进度">{complete}/{steps.length}</span>
        <button type="button" aria-expanded={expanded} aria-label={expanded ? '收起实操引导' : '展开实操引导'} onClick={() => setExpanded((open) => !open)}>{expanded ? '⌃' : '⌄'}</button>
      </div>
    </div>
    {expanded && <>
      {current ? <div className="training-coach-instruction" aria-live="polite">
        <p>{missingLight ? '当前演习未开放照明命令。这一步必须等待实际照明，暂时不能结课。' : current.instruction}</p>
        {!missingLight && <details><summary>为什么这样做</summary><p>{current.reason}</p></details>}
      </div> : <p className="training-coach-result" role="status">所需操作均已记录。炮击和雷击不要求命中。</p>}
      <div className="training-coach-actions">
        <button type="button" onClick={onExit}>退出实操</button>
        {!current ? <button type="button" className="primary" onClick={onFinish}>{course === 'day' || course === 'night' ? '完成课程' : '继续序章'}</button> :
          <button type="button" disabled={missingLight} onClick={() => onGuide ? onGuide(current.guide) : setPulse((n) => n + 1)}>指出操作位置</button>}
      </div>
    </>}
    {!expanded && !current && <button type="button" className="training-coach-compact-finish primary" onClick={onFinish}>{course === 'day' || course === 'night' ? '完成课程' : '继续序章'}</button>}
  </section>;
}
