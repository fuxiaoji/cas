import { useEffect, useState } from 'react';
import { ask, sideNames } from '../../engine';
import type { Profile, Side } from '../../engine';
import { CampaignArchive, CampaignRewardActions, goalText, matchNames } from '../../CampaignArchive';
import type { Archive, Entry, RecordDetail } from '../../CampaignArchive';
import { campaignBest, campaignDifficulties, campaignRewards, campaignRewardText, pendingCampaignRewards } from '../../campaign-progress';
import type { CampaignDifficulty, CampaignLaunch, CampaignProgress } from '../../campaign-progress';
import { CampaignMap, campaignMapStageIds, charts, places } from '../../campaign-map';
import type { CampaignMapSelection } from '../../campaign-map';
import { campaignText } from '../../campaign-labels';
import { DeploymentScreen } from '../formation/DeploymentScreen';
import './campaign-lobby.css';

type Row = { entry: Entry; stageId: string };
type Deploy = { stageId: string; title: string; formation?: { course?: number; speed?: number } };

const sideLabel: Record<Side, string> = { allies: '同盟舰队', axis: '轴心舰队' };
const difficultyNotes: Record<CampaignDifficulty, string> = {
  story: '可借舰编成；敌方协同。',
  standard: '历史编制；敌方炮战。',
  challenge: '历史编制；敌方优先雷击。',
};
const difficulties = Object.keys(campaignDifficulties) as CampaignDifficulty[];

function errorText(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

function yearOf(entry: Entry) {
  return entry.ibs_date?.slice(0, 4) || '日期待定';
}

export function CampaignLobby({
  busy, progress, online, profileId, profiles, defaultProfile,
  onCampaign, onClaim, onReturn, onStory, onReview, onNight, error: launchError,
}: {
  busy: boolean; progress?: CampaignProgress; online: boolean;
  profileId: string; profiles: Profile[]; defaultProfile: Profile;
  onCampaign?: (launch: CampaignLaunch) => void;
  onClaim: (stageId: string) => void;
  onReturn?: () => void; onStory?: () => void; onReview?: () => void; onNight: () => void;
  error?: string;
}) {
  const [archive, setArchive] = useState<Archive>();
  const [error, setError] = useState('');
  const [attempt, setAttempt] = useState(0);
  const [side, setSide] = useState<Side>('allies');
  const [difficulty, setDifficulty] = useState<CampaignDifficulty>('story');
  const [selectedId, setSelectedId] = useState<string>();
  const [mapSelection, setMapSelection] = useState<CampaignMapSelection>({ region: 'overview' });
  const [detail, setDetail] = useState<RecordDetail>();
  const [detailError, setDetailError] = useState('');
  const [detailAttempt, setDetailAttempt] = useState(0);
  const [deploy, setDeploy] = useState<Deploy>();
  const [archiveOpen, setArchiveOpen] = useState(false);

  useEffect(() => {
    let active = true;
    setArchive(undefined);
    setError('');
    void ask<Archive>({ op: 'campaign' }).then((value) => {
      if (active) setArchive(value);
    }, (failure) => {
      if (active) setError(errorText(failure));
    });
    return () => { active = false; };
  }, [attempt]);

  const matchingEntries = archive?.scenarios ?? [];
  const stagePrefix = side === 'allies' ? 'CAMP-ALLIES-' : 'CAMP-AXIS-';
  const mapStageIds = new Set(campaignMapStageIds(matchingEntries, side, mapSelection));
  const visible = matchingEntries.flatMap((entry) => {
    const stageId = entry.stage_ids.find((id) => id.startsWith(stagePrefix) && mapStageIds.has(id));
    return stageId ? [{ entry, stageId }] : [];
  });
  const allStages = matchingEntries.flatMap((entry) => {
    const stageId = entry.stage_ids.find((id) => id.startsWith(stagePrefix));
    return stageId ? [{ entry, stageId }] : [];
  });
  const selected = visible.find((row) => row.entry.ibs_id === selectedId) ?? visible[0];
  const visibleKey = visible.map((row) => row.entry.ibs_id + ':' + row.stageId).join('|');
  const earned = allStages.reduce((sum, row) => sum + (campaignBest(progress, row.stageId) ?? 0), 0);
  const title = mapSelection.place ? places[mapSelection.place].label
    : mapSelection.region === 'overview' ? '全战线' : charts[mapSelection.region].label;

  function launchable(entry: Entry) {
    return entry.playable && !(online && entry.runtime?.localOnly);
  }

  function blockText(entry: Entry) {
    if (!entry.playable) return '档案整理中';
    if (online && entry.runtime?.localOnly) return '仅离线开放';
    return '';
  }

  function statusFor(entry: Entry, stageId: string) {
    const pending = pendingCampaignRewards(progress, stageId).length;
    const best = campaignBest(progress, stageId) ?? 0;
    if (pending) return { text: '奖励待领', tone: 'is-pending' };
    if (!launchable(entry)) return { text: blockText(entry), tone: 'is-muted' };
    if (best > 0) return { text: '★'.repeat(best) + '☆'.repeat(3 - best), tone: 'is-done' };
    return { text: '可出击', tone: 'is-ready' };
  }

  useEffect(() => {
    if (!visible.length) {
      setSelectedId(undefined);
      return;
    }
    if (selectedId && visible.some((row) => row.entry.ibs_id === selectedId)) return;
    const first = visible.find((row) => launchable(row.entry)) ?? visible[0];
    setSelectedId(first.entry.ibs_id);
  }, [visibleKey, selectedId, online]);

  useEffect(() => {
    setDifficulty('story');
  }, [selected?.stageId]);

  useEffect(() => {
    const id = selected?.stageId;
    setDetail(undefined);
    setDetailError('');
    if (!id) return;
    let active = true;
    void ask<RecordDetail>({ op: 'campaign_detail', id }).then((value) => {
      if (active) setDetail(value);
    }, (failure) => {
      if (active) setDetailError(errorText(failure));
    });
    return () => { active = false; };
  }, [selected?.stageId, detailAttempt]);

  function chooseSide(next: Side) {
    setSide(next);
    setSelectedId(undefined);
    setMapSelection({ region: 'overview' });
  }

  function startDeploy(row: Row) {
    if (!onCampaign || busy || !launchable(row.entry)) return;
    const setup = (detail?.record?.setup?.[side] ?? undefined) as { course_deg?: number; speed_knots?: number } | undefined;
    setDeploy({
      stageId: row.stageId,
      title: row.entry.runtime?.label ?? row.entry.ibs_title,
      formation: setup && (setup.course_deg !== undefined || setup.speed_knots !== undefined)
        ? { course: setup.course_deg, speed: setup.speed_knots } : undefined,
    });
  }

  function launchDirect(row: Row) {
    if (!onCampaign || busy || !launchable(row.entry)) return;
    onCampaign({ stageId: row.stageId, difficulty });
  }

  if (deploy) return <DeploymentScreen
    stageId={deploy.stageId} difficulty="story" side={side}
    stageTitle={deploy.title} formation={deploy.formation}
    profileId={profileId} profiles={profiles} defaultProfile={defaultProfile}
    busy={busy} error={launchError}
    onBack={() => setDeploy(undefined)}
    onLaunch={({ fleet, groups, profile }) => {
      if (!onCampaign) return;
      onCampaign({
        stageId: deploy.stageId, difficulty: 'story',
        ...(fleet?.length ? { fleet } : {}),
        ...(groups?.length ? { groups, taskForce: true } : {}),
        profile,
      });
    }} />;

  if (archiveOpen) return <CampaignArchive
    busy={busy} progress={online ? undefined : progress} online={online}
    onCampaign={onCampaign} onClaim={onClaim}
    onReturn={() => setArchiveOpen(false)} onStory={onStory} onReview={onReview} onNight={onNight} />;

  const playableRows = visible.filter((row) => row.entry.playable).sort((a, b) => a.entry.ibs_date.localeCompare(b.entry.ibs_date));
  const archiveRows = visible.filter((row) => !row.entry.playable);
  const years = [...new Set(playableRows.map((row) => yearOf(row.entry)))];
  const record = detail?.record;
  const objective = record?.objectives?.[side];
  const environment = record?.environment;
  const start = record?.start;
  const best = selected ? campaignBest(progress, selected.stageId, difficulty) ?? 0 : 0;
  const rewards = selected ? campaignRewards(selected.stageId) : [];
  const pending = selected ? pendingCampaignRewards(progress, selected.stageId) : [];
  const starRows = [
    { stars: 1, label: '完成作战', detail: '首次通关', earned: best >= 1 },
    { stars: 2, label: '战术胜利', detail: objective?.tactical ? goalText(objective.tactical) : '按原页条件', earned: best >= 2 },
    { stars: 3, label: '决定性胜利', detail: objective?.decisive ? goalText(objective.decisive) : '按原页条件', earned: best >= 3 },
  ];
  const envChips = [
    environment?.light === 'night' ? '夜间' : environment?.light === 'day' ? '昼间' : environment?.light === 'twilight' ? '晨昏' : '',
    environment?.visibility_pct !== undefined ? `能见度 ${environment.visibility_pct}%` : '',
    environment?.sea_state !== undefined ? `海况 ${environment.sea_state}` : '',
  ].filter(Boolean);
  const canGo = !!selected && launchable(selected.entry);
  const deployable = canGo && !online && difficulty === 'story' && !!record && !!onCampaign;
  const direct = canGo && !deployable;
  const ctaLabel = !selected ? '选择关卡' : !canGo ? blockText(selected.entry)
    : deployable ? '编成出击' : difficulty === 'story' ? '按历史编制出击' : `${campaignDifficulties[difficulty]}难度出击`;

  return <main className="campaign-lobby" data-faction={side}>
    <header className="cl-top">
      {onReturn && <button type="button" className="cl-back" onClick={onReturn}>‹ 母港</button>}
      <div className="cl-title"><h1>战役 · {title}</h1><small>CAMPAIGN ATLAS</small></div>
      <div className="cl-side-tabs" role="group" aria-label="战役阵营">
        {(['allies', 'axis'] as const).map((value) =>
          <button key={value} type="button" aria-pressed={side === value} onClick={() => chooseSide(value)}>
            {value === 'allies' ? '同盟战线' : '轴心战线'}
          </button>)}
      </div>
      <span className="cl-stars" aria-label={`本阵营 ${earned} / ${allStages.length * 3} 星`}>★ {earned} / {allStages.length * 3}</span>
      <button type="button" className="cl-utility" onClick={() => setArchiveOpen(true)}>史料馆</button>
      {onStory && <button type="button" className="cl-utility" onClick={onStory}>剧情模式</button>}
      {onReview && <button type="button" className="cl-utility" onClick={onReview}>操作复习</button>}
    </header>

    {launchError && <p className="cl-launch-error" role="alert">{launchError}</p>}

    {!archive && !error && <p className="cl-loading" role="status">正在查阅战役档案…</p>}
    {error && <div className="cl-alert" role="alert"><span>档案未能载入。</span>
      <button type="button" onClick={() => setAttempt((value) => value + 1)}>重新载入</button></div>}

    {archive && <div className="cl-body">
      <aside className="cl-rail" aria-label="关卡列表">
        <header className="cl-rail-head">
          <div><h2>{mapSelection.place ? places[mapSelection.place].label : mapSelection.region === 'overview' ? '全战线' : charts[mapSelection.region].label}</h2>
            <small>{playableRows.length} 个可出击关卡</small></div>
          <span>{sideLabel[side]}</span>
        </header>

        {years.map((year) => <section className="cl-year" key={year}>
          <h3>{year}</h3>
          <ol>
            {playableRows.filter((row) => yearOf(row.entry) === year).map((row) => {
              const status = statusFor(row.entry, row.stageId);
              return <li key={row.entry.ibs_id}>
                <button type="button" className={'cl-row' + (selected?.entry.ibs_id === row.entry.ibs_id ? ' is-selected' : '') + ' ' + status.tone}
                  aria-pressed={selected?.entry.ibs_id === row.entry.ibs_id}
                  data-stage-id={row.stageId} data-playable={row.entry.playable}
                  onClick={() => setSelectedId(row.entry.ibs_id)}>
                  <span className="cl-row-num">{row.stageId.slice(-2)}</span>
                  <span className="cl-row-copy">
                    <strong>{row.entry.ibs_title}</strong>
                    <small>{row.entry.ibs_date || '日期待定'} · {matchNames[row.entry.classification]}</small>
                  </span>
                  <span className="cl-row-status">{status.text}</span>
                </button>
              </li>;
            })}
          </ol>
        </section>)}

        {!playableRows.length && <p className="cl-empty">此战区暂无可出击关卡。</p>}

        {archiveRows.length > 0 && <details className="cl-archive-only">
          <summary>档案整理中 · {archiveRows.length}</summary>
          <ul>
            {archiveRows.map((row) => <li key={row.entry.ibs_id}>
              <button type="button" className={'cl-row is-muted' + (selected?.entry.ibs_id === row.entry.ibs_id ? ' is-selected' : '')}
                aria-pressed={selected?.entry.ibs_id === row.entry.ibs_id}
                data-stage-id={row.stageId} data-playable={row.entry.playable}
                onClick={() => setSelectedId(row.entry.ibs_id)}>
                <span className="cl-row-num">{row.stageId.slice(-2)}</span>
                <span className="cl-row-copy"><strong>{row.entry.ibs_title}</strong>
                  <small>{row.entry.ibs_date || '日期待定'} · {matchNames[row.entry.classification]}</small></span>
                <span className="cl-row-status">档案中</span>
              </button>
            </li>)}
          </ul>
        </details>}
      </aside>

      <section className="cl-map" aria-label="战役海图">
        <CampaignMap entries={matchingEntries} side={side} selection={mapSelection}
          onSelectionChange={setMapSelection} activeScenarioId={selected?.entry.ibs_id} />
      </section>

      <aside className="cl-detail" aria-label="关卡详情">
        <div className="cl-detail-scroll">
          {!selected ? <p className="cl-empty">选择一处交战海域查看关卡。</p> : <>
            <header className="cl-detail-head">
              <span className="cl-kicker">{matchNames[selected.entry.classification]} · {sideLabel[side]}</span>
              <h2>{selected.entry.runtime?.label ?? selected.entry.ibs_title}</h2>
              <p className="cl-meta">
                {start?.date_local ?? (selected.entry.ibs_date || '日期待定')}
                {start?.time_local ? ' ' + start.time_local : ''}
                {start?.location ? ' · ' + campaignText(start.location) : ''}
              </p>
              {envChips.length > 0 && <div className="cl-env">{envChips.map((chip) => <span key={chip}>{chip}</span>)}</div>}
            </header>

            {detailError ? <div className="cl-detail-error" role="alert">{detailError}
              <button type="button" onClick={() => setDetailAttempt((value) => value + 1)}>重读</button></div>
              : !detail ? <p className="cl-loading" role="status">正在载入想定记录…</p>
                : detail.legacy && !record ? <p className="cl-legacy">原剧本开局阵位，详细部署与来源见「史料馆」。</p>
                  : record ? <>
                    <section className="cl-section">
                      <h3>作战目标</h3>
                      <dl className="cl-objectives">
                        <div><dt>命令</dt><dd>{objective?.orders ? campaignText(objective.orders) : '待核对'}</dd></div>
                        <div><dt>决定胜利</dt><dd>{objective ? goalText(objective.decisive) : '待核对'}</dd></div>
                        <div><dt>战术胜利</dt><dd>{objective ? goalText(objective.tactical) : '待核对'}</dd></div>
                      </dl>
                    </section>

                    <section className="cl-section">
                      <h3>星级条件</h3>
                      <ul className="cl-star-rows">
                        {starRows.map((row) => <li key={row.stars} data-earned={row.earned}>
                          <span className="cl-star">{'★'.repeat(row.stars)}</span>
                          <b>{row.label}</b>
                          <small>{row.earned ? '已达成' : row.detail}</small>
                        </li>)}
                      </ul>
                    </section>

                    <section className="cl-section">
                      <h3>首通与星级奖励</h3>
                      <ul className="cl-rewards">
                        {rewards.map((reward) => <li key={reward.stars}>
                          <span className="cl-reward-star">{'★'.repeat(reward.stars)}</span>
                          <b>{reward.title}</b>
                          <small>{campaignRewardText(reward)}</small>
                        </li>)}
                      </ul>
                      {!online && selected && <CampaignRewardActions stageId={selected.stageId} progress={progress}
                        busy={busy} onClaim={() => onClaim(selected.stageId)} />}
                    </section>

                    <section className="cl-section">
                      <h3>难度</h3>
                      <div className="cl-diff" role="group" aria-label="战役难度">
                        {difficulties.map((option) => {
                          const stars = campaignBest(progress, selected.stageId, option) ?? 0;
                          return <button key={option} type="button" aria-pressed={difficulty === option}
                            onClick={() => setDifficulty(option)}>
                            <b>{campaignDifficulties[option]}</b>
                            <small>{stars > 0 ? '★ ' + stars : '—'}</small>
                            <em>{difficultyNotes[option]}</em>
                          </button>;
                        })}
                      </div>
                    </section>

                    {record.special_rules?.length ? <details className="cl-details">
                      <summary>想定特例 · {record.special_rules.length}</summary>
                      <ul>{record.special_rules.map((rule, index) =>
                        <li key={index}>{campaignText(typeof rule === 'string' ? rule : rule.rule)}</li>)}</ul>
                    </details> : null}

                    {record.blockers?.length ? <details className="cl-details">
                      <summary>档案缺口 · {record.blockers.length}</summary>
                      <ul>{record.blockers.map((blocker, index) =>
                        <li key={index}>{campaignText(typeof blocker === 'string' ? blocker : blocker.detail)}</li>)}</ul>
                    </details> : null}
                  </> : <p className="cl-legacy">想定记录不完整，详细来源见史料馆。</p>}

            {selected.entry.note && <p className="cl-note">{campaignText(selected.entry.note)}</p>}
          </>}
        </div>

        <footer className="cl-detail-foot">
          {selected && <p className="cl-foot-note">
            {canGo ? `最佳 ${best > 0 ? '★'.repeat(best) : '—'} · ${campaignDifficulties[difficulty]}难度`
              : blockText(selected.entry)}
          </p>}
          <button type="button" className="cl-cta" disabled={busy || !canGo || !onCampaign}
            onClick={() => {
              if (!selected) return;
              if (deployable) startDeploy(selected);
              else if (direct) launchDirect(selected);
            }}>{ctaLabel}</button>
          <div className="cl-foot-links">
            <button type="button" onClick={() => setArchiveOpen(true)}>本关史料</button>
            {onReview && <button type="button" onClick={onReview}>操作复习</button>}
          </div>
        </footer>
      </aside>
    </div>}
  </main>;
}
