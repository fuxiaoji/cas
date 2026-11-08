import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import './guided-tutorial.css';

export type GuidedStep = {
  selector: string;
  title: string;
  text: string;
  action: () => void;
};

function findTarget(selector: string) {
  for (const element of document.querySelectorAll<HTMLElement>(selector)) {
    if (!element.getClientRects().length) continue;
    return element;
  }
  return undefined;
}

/**
 * Hand-held tutorial: the coach spotlights exactly one control and the next
 * step only starts when the player clicks it. Clicks anywhere else are
 * swallowed, so the course cannot drift into free play.
 */
export function GuidedTutorial({ steps, onFinish }: { steps: readonly GuidedStep[]; onFinish: () => void }) {
  const [index, setIndex] = useState(0);
  const [rect, setRect] = useState<DOMRect>();
  const [wrong, setWrong] = useState(false);
  const step = steps[Math.min(index, steps.length - 1)];
  const target = useRef<HTMLElement | undefined>(undefined);
  const advancing = useRef(false);

  useLayoutEffect(() => {
    let frame = 0;
    const measure = () => {
      target.current = step ? findTarget(step.selector) : undefined;
      const next = target.current?.getBoundingClientRect();
      if (next && (next.top < 8 || next.bottom > window.innerHeight - 8 || next.left < 8 || next.right > window.innerWidth - 8)) {
        target.current?.scrollIntoView({ block: 'center', inline: 'center' });
      }
      setRect(target.current?.getBoundingClientRect());
      frame = window.requestAnimationFrame(measure);
    };
    measure();
    return () => window.cancelAnimationFrame(frame);
  }, [step?.selector]);

  function advance() {
    if (advancing.current) return;
    advancing.current = true;
    setWrong(false);
    try { step.action(); } catch (error) { console.error('guided action failed', error); }
    if (index + 1 >= steps.length) onFinish();
    else setIndex(index + 1);
    window.setTimeout(() => { advancing.current = false; }, 220);
  }

  useEffect(() => {
    function click(event: MouseEvent) {
      const node = event.target as Element | null;
      // The transparent proxy is the only enabled clickable surface; let its
      // own handler run and block every other click.
      if (node?.closest?.('.guided-proxy')) return;
      event.preventDefault();
      event.stopPropagation();
      setWrong(true);
    }
    document.addEventListener('click', click, true);
    return () => document.removeEventListener('click', click, true);
  }, []);

  if (!step) return null;
  return <div className="guided-tutorial" role="dialog" aria-modal="true" aria-label="手把手教学">
    <div className="guided-mask" />
    {rect && <button type="button" className="guided-proxy" aria-label={step.title} style={{
      left: rect.left - 7, top: rect.top - 7, width: rect.width + 14, height: rect.height + 14,
    }} onClick={event => { event.preventDefault(); event.stopPropagation(); advance(); }} />}
    {rect && <div className="guided-spot" style={{
      left: rect.left - 7, top: rect.top - 7, width: rect.width + 14, height: rect.height + 14,
    }} />}
    <section className="guided-panel">
      <span>教官标注 · 第 {index + 1} / {steps.length} 步</span>
      <h2>{step.title}</h2>
      <p>{step.text}</p>
      <small className={wrong ? 'guided-wrong' : ''}>{wrong ? '请点击高亮的控制。' : '点击高亮处继续。'}</small>
    </section>
  </div>;
}
