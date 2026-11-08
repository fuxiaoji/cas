import { useEffect, useState } from 'react';
import { baixisPortrait } from '../prologue/art';
import { trainingCourses, trainingStepDone } from './curriculum';
import type { CourseId, TrainingEvidence } from './curriculum';
import { guidedTrainingProgress, guideSelectors } from './guide';
import './training-coach.css';

type Props = { course: CourseId; evidence: TrainingEvidence; onFinish: () => void; onExit: () => void; onAdvance?: () => void;
  onGuide?: (selector: string) => void; lightingAvailable?: boolean; guided?: boolean; radar?: boolean };

function findGuideTarget(selectors: readonly string[]) {
  for (const selector of selectors) {
    for (const element of document.querySelectorAll<HTMLElement>(selector)) {
      if (!element.getClientRects().length || getComputedStyle(element).visibility !== 'visible' ||
        element.matches(':disabled,[aria-disabled="true"]') || element.closest('[inert],[aria-hidden="true"]')) continue;
      const marker = element.closest('.map-ship,.contact-label');
      const map = marker?.closest('.battle-map');
      if (map) {
        const point = element.getBoundingClientRect(), bounds = map.getBoundingClientRect();
        if (point.right < bounds.left || point.left > bounds.right || point.bottom < bounds.top || point.top > bounds.bottom) continue;
      }
      return element;
    }
  }
}

export function TrainingCoach({ course, evidence, onFinish, onExit, onAdvance, onGuide, lightingAvailable = true, guided = false, radar = false }: Props) {
  const [expanded, setExpanded] = useState(true);
  const [pulse, setPulse] = useState(0);
  const { title, steps } = trainingCourses[course];
  const guidance = guided ? guidedTrainingProgress(course, evidence, { radar }) : undefined;
  const complete = guidance ? guidance.complete : steps.filter((item) => trainingStepDone(item, evidence)).length;
  const total = guidance?.total ?? steps.length;
  const current = guidance ? guidance.current : steps.find((item) => !trainingStepDone(item, evidence));
  const missingLight = current?.id === 'campaign-night-light' && !lightingAvailable;
  const selectorList = [...(guidance?.cue?.controls.flatMap(guideSelectors) ?? []), ...(current ? [current.guide] : [])];
  const selectorKey = selectorList.join('\n');

  useEffect(() => {
    if (!selectorKey || missingLight || !expanded || (!guided && (!pulse || onGuide))) return;
    const selectors = selectorKey.split('\n');
    let target: HTMLElement | undefined;
    let frame = 0;
    function retarget() {
      const next = findGuideTarget(selectors);
      if (next === target) return;
      target?.classList.remove('training-target');
      target?.removeAttribute('data-guide-active');
      target = next;
      target?.classList.add('training-target');
      target?.setAttribute('data-guide-active', '');
    }
    retarget();
    if (guided) {
      // The correct control may mount after a tab opens or an actual contact appears.
      // Observe those changes without interfering with map gestures or moving focus.
      const observer = new MutationObserver(() => {
        window.cancelAnimationFrame(frame);
        frame = window.requestAnimationFrame(retarget);
      });
      observer.observe(document.querySelector('.command-shell') ?? document.body, { childList: true, subtree: true,
        attributes: true, attributeFilter: ['disabled', 'hidden', 'aria-disabled', 'aria-hidden', 'aria-pressed', 'inert'] });
      return () => {
        observer.disconnect(); window.cancelAnimationFrame(frame);
        target?.classList.remove('training-target'); target?.removeAttribute('data-guide-active');
      };
    }
    const timer = window.setTimeout(() => {
      target?.classList.remove('training-target'); target?.removeAttribute('data-guide-active');
    }, 1600);
    return () => {
      window.clearTimeout(timer);
      target?.classList.remove('training-target'); target?.removeAttribute('data-guide-active');
    };
  }, [pulse, selectorKey, onGuide, guided, expanded, missingLight]);

  function pointOutControl() {
    const target = findGuideTarget(selectorList);
    if (onGuide && selectorList[0]) onGuide(selectorList[0]);
    else {
      target?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
      setPulse(n => n + 1);
    }
  }

  return <section className={'training-coach' + (expanded ? ' expanded' : '')} aria-label="白汐实操引导"
    data-guide-next={guidance?.next}>
    <div className="training-coach-head">
      <img src={baixisPortrait} alt="" />
      <div><span>{title}</span><h2>{current?.title ?? '实操完成'}</h2></div>
      <div className="training-coach-toggle">
        <span aria-label="教学进度">{complete}/{total}</span>
        <button type="button" aria-expanded={expanded} aria-label={expanded ? '收起实操引导' : '展开实操引导'} onClick={() => setExpanded((open) => !open)}>{expanded ? '⌃' : '⌄'}</button>
      </div>
    </div>
    {expanded && <>
      {current ? <div className="training-coach-instruction" aria-live="polite">
        <p>{missingLight ? '当前演习未开放照明命令。这一步必须等待实际照明，暂时不能结课。' :
          guidance?.cue?.instruction ?? current.instruction}</p>
        {!missingLight && <details><summary>为什么这样做</summary>
          {guidance?.cue && <p>{current.instruction}</p>}
          <p>{current.reason}</p>
        </details>}
      </div> : <p className="training-coach-result" role="status">所需操作均已记录。炮击和雷击不要求命中。</p>}
      <div className="training-coach-actions">
        <button type="button" onClick={onExit}>退出实操</button>
        {!current ? <button type="button" className="primary" onClick={onFinish}>{course === 'day' || course === 'night' ? '完成课程' : '继续序章'}</button> : <>
          {onAdvance && <button type="button" className="primary" onClick={onAdvance}>继续（固定流程）</button>}
          <button type="button" disabled={missingLight} onClick={pointOutControl}>指出操作位置</button>
        </>}
      </div>
    </>}
    {!expanded && !current && <button type="button" className="training-coach-compact-finish primary" onClick={onFinish}>{course === 'day' || course === 'night' ? '完成课程' : '继续序章'}</button>}
  </section>;
}
