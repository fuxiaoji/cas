// Story mode: explicitly fictional chapters, kept apart from the CAS campaign
// atlas. New chapters are appended to `storyChapters`; each one only needs an
// id the prologue-style scene can resume.
import { PROLOGUE_LAST_STEP } from '../prologue/originalScript';
import type { PrologueProgress } from '../prologue';
import './story-mode.css';

export type StoryChapter = {
  id: 'prologue';
  title: string;
  subtitle: string;
  summary: string;
  available: boolean;
};

export const storyChapters: readonly StoryChapter[] = [
  {
    id: 'prologue',
    title: '序章 · 未明的海',
    subtitle: '架空剧情 · 1942 年秋',
    summary: '白汐把第五驱逐小队交到你手上。从第一道航路口令开始，跟着她完成夜航、同步机动与编队雷击。',
    available: true,
  },
];

function progressText(progress: PrologueProgress) {
  if (progress.step >= PROLOGUE_LAST_STEP) return '已完成';
  return progress.step > 0 ? '进行中' : '未开始';
}

export function StoryMode({ progress, onOpen, onBack }: {
  progress: PrologueProgress;
  onOpen: (chapter: StoryChapter) => void;
  onBack: () => void;
}) {
  const finished = progress.step >= PROLOGUE_LAST_STEP;
  return <main className="story-mode" aria-label="剧情模式">
    <div className="story-sky" aria-hidden="true" />
    <header className="story-header">
      <button type="button" onClick={onBack}>返回港口</button>
      <div><span>架空剧情</span><h1>剧情模式</h1></div>
      <p>与历史战役分开记录。这里的舰、人物与结局为虚构，后续章节会继续追加。</p>
    </header>
    <section className="story-chapters" aria-label="剧情章节">
      <div className="story-chapter-head"><h2>章节</h2><span>{storyChapters.length} 章 · 独立存档</span></div>
      <ol>
        {storyChapters.map((chapter, index) => <li key={chapter.id}>
          <button type="button" disabled={!chapter.available}
            onClick={() => onOpen(chapter)} aria-label={`${chapter.title}，${progressText(progress)}`}>
            <span className="story-index">{String(index + 1).padStart(2, '0')}</span>
            <span className="story-copy">
              <small>{chapter.subtitle}</small>
              <strong>{chapter.title}</strong>
              <p>{chapter.summary}</p>
            </span>
            <span className="story-status" data-done={finished}>{progressText(progress)}<b>›</b></span>
          </button>
        </li>)}
        <li className="story-next">
          <div><span>后续剧情</span><strong>新章节将在这里追加</strong>
            <p>剧情模式使用独立的架空存档，不参与战役航图、星级与历史核验。</p></div>
        </li>
      </ol>
    </section>
    <footer className="story-foot"><span>架空剧情 · 不属于 CAS 历史战役档案</span><span>进度只保存在本机</span></footer>
  </main>;
}
