import { useState } from 'react';
import { CampaignArchive } from './CampaignArchive';
import { claimCampaignRewards } from './campaign-progress';
import type { CampaignLaunch } from './campaign-progress';
import { CHALLENGE_WEEKLY_LIMIT, CHALLENGE_WEEKLY_TICKETS, claimRepeat, weeklyStatus } from './activities/week';
import { profileNames } from './engine';
import type { Profile, Side } from './engine';
import {
  defaultFleet, fleetPoints, getGunnery, lessons, meetsRoster, ownedShips, receiveChallenge, receiveStarter,
} from './port';
import type { PortLaunch, PortState } from './port';
import { shipCard, shipName, shipRarityName, shipTypeName } from './ship-catalog';
import { shipPortraitById } from './shipPortraits';
import { ChallengeLadder } from './activities/ChallengeLadder';
import { Quartermaster } from './screens/quartermaster/Quartermaster';
import type { QuartermasterCounter } from './screens/quartermaster/counters';
import { RecruitScreen } from './screens/recruit/RecruitScreen';
import { WalletBar } from './widgets/economy';
import './harbor.css';

export type HarborTab = 'training' | 'fleet' | 'recruit' | 'challenge' | 'archive';
type Props = { state: PortState; change: (reducer: (current: PortState) => PortState) => void;
  onReturn: () => void; onLaunch: (options: PortLaunch) => void; onCourse: (id: 'day' | 'night', side?: Side) => void;
  onCampaign?: (launch: CampaignLaunch) => void; onSection?: (section: HarborTab) => void;
  busy: boolean; error?: string; initialTab?: HarborTab; online?: boolean };
function HarborArt() {
  return <svg className="harbor-art" aria-hidden="true" viewBox="0 0 800 275" preserveAspectRatio="xMidYMax slice">
    <defs>
      <linearGradient id="harbor-sky" x1="0" x2="1" y1=".8" y2="0"><stop stopColor="#0f293b"/><stop offset=".58" stopColor="#254d5a"/><stop offset="1" stopColor="#8b806d"/></linearGradient>
      <linearGradient id="harbor-sea" x1="0" x2="0" y1="0" y2="1"><stop stopColor="#4b7072"/><stop offset="1" stopColor="#133744"/></linearGradient>
    </defs>
    <path d="M0 0h800v275H0z" fill="url(#harbor-sky)" />
    <circle cx="659" cy="80" r="45" fill="#e8c88a" opacity=".77"/>
    <path d="M0 153l99-16 61 10 69-24 61 10 78 6 45-11 84 11 47-9 65 2 79-12 112 22v133H0z" fill="#294e58"/>
    <path d="M0 167h800v108H0z" fill="url(#harbor-sea)"/>
    <path d="M16 222h115m16 0h26m17 0h188m50-8h88m29 0h183m-17 19h74m-283 12h203m-125 15h84m-501-2h55m-213-15h107M25 191h136m435-7h141" fill="none" stroke="#b2c4b3" opacity=".28"/>
    <g fill="#183643" stroke="#84a39d" strokeWidth="1">
      <path d="M293 194h72l31-7h25v-6h51v-8h18v-14h25v13h13v-11h21v18h18l16 8h15v5h26l72-10-15 15-41 11-285 3-44-7z"/>
      <path d="M505 160v-29m-13 15h27m19 17v-23m-6 11h15m19 29h19m30 12h14m-237 0h-40" fill="none"/>
      <path d="M593 189l1-9m4 7v-7m-200 9v-5m7 3v-4" fill="none"/>
    </g>
    <path d="M322 216h359m-341 4h258m36 0h50" stroke="#d0d0a8" opacity=".37" fill="none"/>
  </svg>;
}

const sectionNames: Record<HarborTab, string> = {
  training: '教学复习', fleet: '舰库与编队', recruit: '军需处', challenge: '越级挑战', archive: '战役航图',
};
const mobileTabs: { id: HarborTab; icon: string; label: string }[] = [
  { id: 'training', icon: '⌂', label: '母港' },
  { id: 'fleet', icon: '▦', label: '编队' },
  { id: 'recruit', icon: '✦', label: '军需' },
  { id: 'challenge', icon: '⚑', label: '挑战' },
  { id: 'archive', icon: '▤', label: '战役' },
];
export function Harbor({ state, change, onReturn, onLaunch, onCampaign, onCourse, onSection, busy, error, online, initialTab = 'training' }: Props) {
  const tab = initialTab;
  const [starterSide, setStarterSide] = useState<Side>(state.preset.side);
  const [quarterCounter, setQuarterCounter] = useState<QuartermasterCounter>('ships');
  const [recruitOpen, setRecruitOpen] = useState(false);
  const week = weeklyStatus(state);
  const nextLesson = lessons.find(({ id }) => !state.lessons.includes(id));
  const { preset } = state;
  const owned = ownedShips(state);
  const sideOwned = ownedShips(state, preset.side);
  const ready = meetsRoster(state);
  const canDeploy = state.starter && ready;
  const filled = preset.ships.filter(id => state.owned[id] === true).length;
  const totalPoints = fleetPoints(preset.ships);
  // The staged challenge lends its roster from the 202-card registry, so the
  // local dock only has to be unlocked; no own-hull quota applies.
  const canChallenge = state.starter;
  function setSide(side: Side) {
    change((s) => ({ ...s, preset: { ...s.preset, side, leaderSlot: 0, ships: defaultFleet(s, side) } }));
  }
  function setSlot(index: number, id: string) {
    if (!id) return;
    change((s) => {
      const ships = [...s.preset.ships];
      ships[index] = id;
      return { ...s, preset: { ...s.preset, ships } };
    });
  }
  function setLeader(leaderSlot: number) {
    change((s) => ({ ...s, preset: { ...s.preset, leaderSlot } }));
  }
  return <main className={'harbor' + (tab === 'recruit' ? ' harbor--quartermaster' : '')}>
    <header className="harbor-head">
      <div><span>母港 · 舰队勤务</span><h1>{sectionNames[tab]}</h1></div>
      {tab !== 'recruit' && <WalletBar className="harbor-wallet" items={[
        { key: 'credits', label: '补给币', value: state.credits, icon: '◈', tone: 'credits' },
        { key: 'tickets', label: '征募券', value: state.wallet.standard + state.wallet.up, icon: '▱', tone: 'ticket' },
        { key: 'marks', label: '舰队勋章', value: state.marks, icon: '✧', tone: 'marks' },
      ]} />}
      <button type="button" onClick={onReturn} disabled={busy}>返回母港</button>
    </header>
    <div className="harbor-body">
      <section className={'harbor-content' + (tab === 'recruit' ? ' harbor-content--quartermaster' : '')}>
        {tab !== 'recruit' && <div className="harbor-hero"><HarborArt /><div><p>停泊区</p><h2>{sectionNames[tab]}</h2></div></div>}
        {error && <p className="harbor-error" role="alert">{error}</p>}
        {tab === 'training' && <section className="harbor-section">
          <div className="harbor-title"><h3>入门实操</h3><span>{state.lessons.length} / {lessons.length} 完成</span></div>
          <ol className="lesson-list">
            {lessons.map(({ id, name, detail }, index) => <li key={id} className={nextLesson?.id === id ? 'active-lesson' : ''}>
              <span>{state.lessons.includes(id) ? '✓' : String(index + 1).padStart(2, '0')}</span><div><strong>{name}</strong><p>{detail}</p></div>
            </li>)}
          </ol>
          <div className="harbor-action">
            {!state.starter && <label>初始阵营 <select value={starterSide} onChange={(event) => setStarterSide(event.target.value as Side)}>
              <option value="allies">同盟舰队</option><option value="axis">轴心舰队</option>
            </select></label>}
            <button type="button" className="primary" disabled={busy} onClick={() => onCourse('day', starterSide)}>{state.courses.includes('day') ? '复习昼间实操' : '进入实操演习'}</button>
            <button type="button" disabled={busy} onClick={() => onCourse('night')}>{state.courses.includes('night') ? '复习夜战教学' : '夜战教学'}</button>
            <button type="button" className={!nextLesson && !state.starter ? 'primary' : ''} disabled={!!nextLesson || state.starter}
              onClick={() => change((s) => receiveStarter(s, starterSide))}>{state.starter ? '已领取初始舰队' : '领取初始舰队'}</button>
          </div>
          <p className="harbor-fine">结业奖励：所选阵营 5 艘已核验单舰（逐舰 identity）、常驻券与 UP 券各 10 张。协同 AI 可免费使用。</p>
        </section>}
        {tab === 'fleet' && <section className="harbor-section">
          <div className="harbor-title"><h3>在港单舰</h3><span>{owned.length} 艘已拥有</span></div>
          <div className="ship-inventory" data-ship-inventory data-owned-count={owned.length}>
            {owned.map(card => {
              const art = shipPortraitById(card.id);
              return <article key={card.id} className="ship-card" data-owned-ship={card.id}>
                {art ? <img src={art.src} alt={art.name + '舰娘立绘'} loading="lazy" /> : <span className="ship-card__noart">舰影</span>}
                <span>{shipTypeName(card.type)} · {shipRarityName(card.gachaRarity)}</span>
                <strong>{card.name}</strong>
                <small>{card.class ?? '舰级未登记'}</small>
                <em>{card.points ?? 0} 点 · 已拥有</em>
              </article>;
            })}
            {!owned.length && <p className="harbor-fine">尚无单舰。完成初始舰队或到军港征募后，单舰会出现在这里。</p>}
          </div>
          <div className="harbor-title"><h3>出航预设</h3><span>{canDeploy ? '可以出航' : ready ? '领取初始舰队后可出航' : '舰艇不足'}</span></div>
          <div className="harbor-action preset-fields">
            <label>阵营 <select value={preset.side} onChange={(event) => setSide(event.target.value as Side)}>
              <option value="allies">同盟舰队</option><option value="axis">轴心舰队</option>
            </select></label>
            <label>领舰 <select data-fleet-leader value={preset.leaderSlot} onChange={(event) => setLeader(Number(event.target.value))}>
              {preset.ships.map((id, index) => <option key={index} value={index} disabled={!id}>
                {index + 1} 舰位 · {id ? shipName(id) : '空舰位'}
              </option>)}
            </select></label>
            <label>协助风格 <select value={preset.profile} onChange={(event) => {
              const profile = event.target.value as Profile; change((s) => ({ ...s, preset: { ...s.preset, profile } }));
            }}>
              {state.profiles.map((profile) => <option key={profile} value={profile}>{profileNames[profile]}</option>)}
            </select></label>
          </div>
          <div className="fleet-slots" data-fleet-slots>
            {preset.ships.map((id, index) => {
              const card = shipCard(id);
              const used = new Set(preset.ships.filter((_, slot) => slot !== index));
              return <label key={index} className="fleet-slot" data-slot={index} data-filled={!!card}>
                <span>舰位 {index + 1}</span>
                <select value={card ? id : ''} aria-label={`舰位 ${index + 1}`} onChange={(event) => setSlot(index, event.target.value)}>
                  {!card && <option value="">选择舰船</option>}
                  {sideOwned.map(option => <option key={option.id} value={option.id} disabled={used.has(option.id)}>
                    {option.name} · {shipTypeName(option.type)} · {option.points ?? 0} 点
                  </option>)}
                  {card && state.owned[id] !== true && <option value={id}>{card.name} · {shipTypeName(card.type)} · 未拥有</option>}
                </select>
                <small>{card ? `${shipTypeName(card.type)} · ${card.points ?? 0} 点 · ${state.owned[id] ? '已拥有' : '未拥有'}` : '空舰位'}</small>
              </label>;
            })}
          </div>
          <div className="fleet-summary" data-fleet-summary data-ready={ready}>
            <span>总点价 <b>{totalPoints}</b></span>
            <span>已拥有舰位 <b>{filled} / 5</b></span>
            <span className={ready ? 'ok' : 'bad'}>{ready ? '5 舰齐全 · 可以出航' : `还差 ${Math.max(0, 5 - filled)} 艘已拥有单舰`}</span>
          </div>
          <div className="harbor-action"><button type="button" className="primary" data-launch-preset disabled={!canDeploy || busy}
            onClick={() => onLaunch({ ...preset, ships: [...preset.ships] })}>用预设出航</button>
            <button type="button" disabled={state.marks < 6 || state.profiles.includes('gunnery')}
              onClick={() => change(getGunnery)}>{state.profiles.includes('gunnery') ? '已拥有炮战 AI' : '6 勋章兑换炮战 AI'}</button></div>
          <p className="harbor-fine">出航预设从已拥有单舰中选 5 个同阵营舰位，领舰任选；总点价按排位点表计算。抽卡不要求先完成教学。</p>
        </section>}
        {tab === 'recruit' && <Quartermaster state={state} change={change} busy={busy}
          counter={quarterCounter} onCounter={setQuarterCounter} onRecruit={() => setRecruitOpen(true)}
          onCampaign={() => onSection?.('archive')} />}
        {tab === 'challenge' && <section className="harbor-section">
          <ChallengeLadder state={state} change={change} onLaunch={onLaunch} busy={busy} ready={canChallenge} />
          <div className="harbor-title"><h3>挑战奖励</h3><span>首通</span></div>
          <p className="harbor-fine">首通奖励：雷击 AI 与 2 张常驻券。关卡梯度只记录通关，不改变既有奖励口径。</p>
          <div className="harbor-action"><button type="button" disabled={!state.challengeClear || state.challengeClaim} onClick={() => change(receiveChallenge)}>
            {state.challengeClaim ? '已领取挑战奖励' : '领取挑战奖励'}</button></div>
          <div className="harbor-title"><h3>复战周奖励</h3><span>{week.claimed} / {CHALLENGE_WEEKLY_LIMIT}</span></div>
          <p className="harbor-fine">首通后每次达成主目标可领 {CHALLENGE_WEEKLY_TICKETS} 张常驻券，每周最多 {CHALLENGE_WEEKLY_LIMIT} 次。周一北京时间 00:00 刷新。</p>
          <div className="harbor-action"><button type="button" disabled={!week.pending.length || week.claimed >= CHALLENGE_WEEKLY_LIMIT}
            onClick={() => change(s => claimRepeat(s))}>领取复战奖励</button></div>
        </section>}
        {tab === 'archive' && <CampaignArchive busy={busy} progress={online ? undefined : state.campaignProgress} onCampaign={onCampaign} online={online}
          onClaim={(stageId) => change(current => claimCampaignRewards(current, stageId))}
          onNight={() => onLaunch({ side: preset.side, profile: preset.profile, leaderSlot: preset.leaderSlot, variant: 'night',
            ...(canDeploy ? { ships: [...preset.ships] } : {}) })} />}
      </section>
    </div>
    <nav className="harbor-mobile-nav" aria-label="母港区域">
      {mobileTabs.map(item => <button key={item.id} type="button" aria-pressed={tab === item.id}
        onClick={() => onSection?.(item.id)}><i aria-hidden="true">{item.icon}</i><span>{item.label}</span></button>)}
      <button type="button" className="harbor-mobile-nav__draw" data-mobile-draw onClick={() => setRecruitOpen(true)}>
        <i aria-hidden="true">✦</i><span>征募</span></button>
    </nav>
    {recruitOpen && <RecruitScreen state={state} change={change} busy={busy}
      onClose={() => setRecruitOpen(false)}
      onQuartermaster={(counter) => { setRecruitOpen(false); setQuarterCounter(counter); }} />}
  </main>;
}
