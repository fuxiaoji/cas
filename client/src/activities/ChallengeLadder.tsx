import type { PortLaunch, PortState } from '../port';
import {
  beginChallengeStage,
  challengeLadder,
  challengeProgress,
  selectChallengeStage,
  selectedChallengeStage,
  stageUnlocked,
} from './challenge';
import {
  challengeRewards,
  challengeShipNames,
  challengeStages,
} from './challenge-stages';
import type { ChallengeFleet, ChallengeStage } from './challenge-stages';
import './challenge.css';

type Props = {
  state: PortState;
  change: (reducer: (current: PortState) => PortState) => void;
  onLaunch: (options: PortLaunch) => void;
  busy: boolean;
  ready: boolean;
};

const orderedStages: readonly ChallengeStage[] = [...challengeStages].sort((a, b) => a.order - b.order);

function stageBadge(stage: ChallengeStage, state: PortState): { label: string; tone: string } {
  const ladder = challengeLadder(state);
  if (stage.status === 'blocked') return { label: '未开放', tone: 'blocked' };
  if (ladder.cleared.includes(stage.id)) return { label: '已通关', tone: 'cleared' };
  if (!stageUnlocked(ladder, stage)) return { label: '未解锁', tone: 'locked' };
  return ladder.selected === stage.id ? { label: '当前', tone: 'current' } : { label: '可出击', tone: 'ready' };
}

function profileName(profile: ChallengeStage['profile']): string {
  if (profile === 'gunnery') return '炮战';
  if (profile === 'torpedo') return '雷击';
  return '协同';
}

function fleetLabel(fleet: ChallengeFleet): string {
  return fleet.ships.map((id) => challengeShipNames[id] ?? id).join('、');
}

function minutes(limit: number): string {
  return `${Math.round(limit / 60)} 分钟`;
}

function sideName(side: 'allies' | 'axis'): string {
  return side === 'allies' ? '同盟' : '轴心';
}

export function ChallengeLadder({ state, change, onLaunch, busy, ready }: Props) {
  const ladder = challengeLadder(state);
  const selected = selectedChallengeStage(state);
  const progress = challengeProgress(state);
  const side = state.preset.side;
  const selectedUnlocked = selected ? stageUnlocked(ladder, selected) : false;
  const canLaunch = ready && !!selected && selected.status === 'playable' && selectedUnlocked;
  const selectedCleared = selected ? ladder.cleared.includes(selected.id) : false;

  function launch() {
    if (!selected || !canLaunch) return;
    const fleet = selected.player[side];
    change((current) => beginChallengeStage(current, selected.id));
    onLaunch({
      ...state.preset,
      leaderSlot: fleet.leader_slot,
      profile: selected.profile,
      variant: 'challenge',
      stage: selected.id,
      seed: selected.seed,
      enemy: selected.enemy_profile,
    });
  }

  return <div className="challenge-ladder">
    <div className="harbor-title"><h3>挑战模式 · 五关</h3><span>{progress.cleared} / {progress.total} 已通关</span></div>
    <p className="harbor-fine">架空挑战梯度，不映射历史战役，不计历史星级。前 3 关只出驱逐舰与轻巡洋舰；第 4–5 关为战列舰 + 驱逐舰编队，海图与时限随编制扩大。本席编成为关卡配发，不需要自备同型舰。</p>
    <ol className="challenge-stage-list" aria-label="挑战关卡">
      {orderedStages.map((stage) => {
        const badge = stageBadge(stage, state);
        const unlocked = stageUnlocked(ladder, stage);
        return <li key={stage.id}>
          <button type="button" className={`challenge-stage-card ${badge.tone} ${selected?.id === stage.id ? 'selected' : ''}`}
            aria-pressed={selected?.id === stage.id}
            disabled={stage.status === 'playable' && !unlocked}
            onClick={() => change((current) => selectChallengeStage(current, stage.id))}>
            <span className="challenge-stage-order">{String(stage.order).padStart(2, '0')}</span>
            <span className="challenge-stage-copy"><strong>{stage.name}</strong><small>{stage.tier} · 上限 {stage.budget} 分 · {stage.player[side].ships.length} 对 {stage.enemy[side === 'allies' ? 'axis' : 'allies'].ships.length} 舰</small></span>
            <em>{badge.label}</em>
          </button>
        </li>;
      })}
    </ol>

    {selected && <section className="challenge-detail" aria-label="当前关卡">
      <header><span>{selected.tier}</span><h4>{selected.name}</h4>{selectedCleared && <b>已通关</b>}</header>
      <p>{selected.objective}</p>
      {selected.status === 'playable' ? <>
        <dl>
          <div><dt>本席 {sideName(side)} 编制</dt><dd>{fleetLabel(selected.player[side])}</dd></div>
          <div><dt>本席点价</dt><dd>{selected.player[side].points} / {selected.budget}</dd></div>
          <div><dt>敌方 {sideName(side === 'allies' ? 'axis' : 'allies')} 编制</dt><dd>{fleetLabel(selected.enemy[side === 'allies' ? 'axis' : 'allies'])}</dd></div>
          <div><dt>敌方点价</dt><dd>{selected.enemy[side === 'allies' ? 'axis' : 'allies'].points}</dd></div>
          <div><dt>领舰</dt><dd>第 {selected.player[side].leader_slot + 1} 舰位</dd></div>
          <div><dt>本席 AI 风格</dt><dd>{profileName(selected.profile)}</dd></div>
          <div><dt>敌方 AI</dt><dd>{profileName(selected.enemy_profile)}</dd></div>
          <div><dt>海图 / 时限</dt><dd>{Math.round(selected.field.width / 1000)}×{Math.round(selected.field.height / 1000)} 码 · {minutes(selected.field.limit)}</dd></div>
          <div><dt>击沉目标</dt><dd>至少 {selected.required_enemy_losses} 艘</dd></div>
          <div><dt>实测</dt><dd>种子 {selected.evidence.seed} · 敌损 {selected.evidence.result.allies} / 我损 {selected.evidence.result.axis}</dd></div>
        </dl>
        <p className="challenge-note">实测为本席与敌方均由 auto AI 操作、步进至时限的结果；手动操作可改变战果。敌编成允许越级，预算只约束本席。</p>
      </> : <>
        <p className="challenge-blocker" role="status">{selected.blocker}</p>
      </>}
      <div className="harbor-action">
        <button type="button" className="primary" disabled={!canLaunch || busy} onClick={launch}>出航挑战</button>
        {!ready && <span className="challenge-lock-note">需要先领取初始舰队，才能借用关卡配发的本席编成。</span>}
      </div>
      <p className="harbor-fine">首通与周复战奖励沿用现有挑战规则：{challengeRewards.first_clear}；{challengeRewards.repeat}。关卡梯度只记录通关进度，不新增货币。</p>
    </section>}
  </div>;
}
