import { useEffect, useState } from 'react';
import { ask } from './engine';

type Match = 'exact_historical_counterpart' | 'related_alternate' | 'unverified' | 'ibs_original_or_absent';
type Reference = { document: string; pdf_pages: number[]; printed_pages: number[] };
type Entry = {
  ibs_id: string; ibs_title: string; ibs_date: string; ibs_kind: string; stage_ids: string[];
  classification: Match; cas: null | { title: string; source: Reference; verification: string; import: string | null };
  playable: boolean; note: string;
};
interface Archive { schema_version: number; content_version: string; scenarios: Entry[] }

const matchNames: Record<Match, string> = {
  exact_historical_counterpart: '同一历史战斗', related_alternate: '相关改编',
  unverified: '尚待核对', ibs_original_or_absent: '旧作想定或未找到',
};
const sources: Record<string, string> = { rising_sun_5e: 'Rising Sun（第五版）', steel_typhoon_5e: 'Steel Typhoon（第五版）' };

export function CampaignArchive({ onNight, busy }: { onNight: () => void; busy: boolean }) {
  const [archive, setArchive] = useState<Archive>();
  const [error, setError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [filter, setFilter] = useState<'all' | Match>('all');
  useEffect(() => {
    let active = true;
    void ask<Archive>({ op: 'campaign' }).then((value) => {
      if (active) setArchive(value);
    }, () => { if (active) setError(true); });
    return () => { active = false; };
  }, [attempt]);
  const exactCount = archive?.scenarios.filter((entry) => entry.classification === 'exact_historical_counterpart').length ?? 0;
  const visible = archive?.scenarios.filter((entry) => filter === 'all' || entry.classification === filter) ?? [];

  return <section className="harbor-section campaign-archive" aria-label="CAS 战役档案">
    <div className="night-card">
      <div><span>独立练习 · 虚构夜战</span><h3>夜航接敌</h3><p>5 对 5 目视搜索演习。靠近敌舰才能建立接触。</p></div>
      <button type="button" className="primary" onClick={onNight} disabled={busy}>开始夜航演习</button>
    </div>
    <div className="harbor-title"><h3>历史想定对照</h3>{archive && <span>{archive.scenarios.length} 项 · {exactCount} 项对应原书</span>}</div>
    <p className="harbor-fine">档案供查阅。对应同一场历史战斗只代表已找到来源，历史关卡须完成编制、胜利条件和规则验证后才能出航。</p>
    {error && <div className="harbor-action" role="status"><span>档案未能载入。</span><button type="button" onClick={() => { setError(false); setAttempt((n) => n + 1); }}>重新载入</button></div>}
    {!archive && !error && <p className="harbor-fine" role="status">正在查阅档案…</p>}
    {archive && <>
      <div className="archive-toolbar"><label>档案范围 <select value={filter} onChange={(event) => setFilter(event.target.value as typeof filter)}>
        <option value="all">全部</option>
        {Object.entries(matchNames).map(([id, name]) => <option key={id} value={id}>{name}</option>)}
      </select></label></div>
      <ul className="archive-list">
        {visible.map((entry) => <li key={entry.ibs_id}>
          <details>
            <summary>
              <span className="archive-name"><time>{entry.ibs_date || '日期待定'}</time><strong>{entry.ibs_title}</strong></span>
              <span className={'archive-tag ' + entry.classification}>{matchNames[entry.classification]}</span>
              <span className="archive-lock">{entry.playable ? '已验证关卡' : '未开放'}</span>
            </summary>
            <div className="archive-detail">
              {entry.cas && <p><strong>{entry.cas.title}</strong><br />{sources[entry.cas.source.document] ?? entry.cas.source.document}
                {entry.cas.source.pdf_pages.length > 0 && ' · PDF 第 ' + entry.cas.source.pdf_pages.join('、') + ' 页'}
                {entry.cas.source.printed_pages.length > 0 && '（书页 ' + entry.cas.source.printed_pages.join('、') + '）'}</p>}
              <p>{entry.note}</p>
              <small>旧作关卡：{entry.stage_ids.join(' / ')}</small>
            </div>
          </details>
        </li>)}
      </ul>
    </>}
  </section>;
}
