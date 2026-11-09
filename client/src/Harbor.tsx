import { useState } from 'react';
import { CampaignArchive } from './CampaignArchive';
import { claimCampaignRewards } from './campaign-progress';
import type { CampaignLaunch } from './campaign-progress';
import { AI_SHOP, aiShopBlockReason, aiShopOwned, aiShopStars, aiShopUnlocked, buyAiShopEntry } from './ai-shop';
import { RecruitArrival } from './RecruitArrival';
import { LocalRecruitDesk } from './LocalRecruitDesk';
import { buyWeeklyTicket, CHALLENGE_WEEKLY_LIMIT, CHALLENGE_WEEKLY_TICKETS, claimRepeat, claimWeeklySupply, WEEKLY_TICKET_PRICE, weeklyStatus } from './activities/week';
import { profileNames } from './engine';
import type { Profile, Side } from './engine';
import { drawRecruit, getGunnery, hulls, lessons, meetsRoster, receiveChallenge, receiveStarter, recruitReceipt, rosters } from './port';
import type { Hull, PortLaunch, PortState } from './port';
import { ChallengeLadder } from './activities/ChallengeLadder';
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
  training: '教学复习', fleet: '舰库与编队', recruit: '征募与补给', challenge: '越级挑战', archive: '战役航图',
};
export function Harbor({ state, change, onReturn, onLaunch, onCampaign, onCourse, onSection, busy, error, online, initialTab = 'training' }: Props) {
  const tab = initialTab;
  const [starterSide, setStarterSide] = useState<Side>(state.preset.side);
  const [pool, setPool] = useState<'standard' | 'up'>('standard');
  const [economy, setEconomy] = useState<'recruit' | 'supply' | 'ai'>('recruit');
  const [aiNotice, setAiNotice] = useState('');
  const [arrival, setArrival] = useState<{ id: number; replay: boolean }>();
  const week = weeklyStatus(state);
  const nextLesson = lessons.find(({ id }) => !state.lessons.includes(id));
  const { preset } = state;
  const canDeploy = state.starter && meetsRoster(state, preset.side);
  // The staged challenge lends its roster from the 202-card registry, so the
  // local dock only has to be unlocked; no own-hull quota applies.
  const canChallenge = state.starter;
  const arrivalReceipts = arrival ? recruitReceipt(state.history, arrival.id) : [];
  function setSide(side: Side) { change((s) => ({ ...s, preset: { ...s.preset, side, leaderSlot: 0 } })); }
  function recruit(count: 1 | 10) {
    if (!state.starter || state.wallet[pool] < count || arrival) return;
    const entropy = crypto.getRandomValues(new Uint32Array(count * 2));
    setArrival({ id: state.sequence + count, replay: false });
    change(current => drawRecruit(current, pool, entropy));
  }
  return <main className="harbor">
    <header className="harbor-head">
      <div><span>母港 · 舰队勤务</span><h1>{sectionNames[tab]}</h1></div>
      <div className="harbor-wallet">
        <span>补给币 <b>{state.credits.toLocaleString()}</b></span><span>征募券 <b>{state.wallet.standard + state.wallet.up}</b></span><span>舰队勋章 <b>{state.marks}</b></span>
      </div>
      <button type="button" onClick={onReturn} disabled={busy}>返回母港</button>
    </header>
    <div className="harbor-body">
      <section className="harbor-content">
        <div className="harbor-hero"><HarborArt /><div><p>停泊区</p><h2>{sectionNames[tab]}</h2></div></div>
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
          <p className="harbor-fine">结业奖励：所选阵营 4 艘驱逐舰和 1 艘轻巡洋舰、常驻券与 UP 券各 10 张。协同 AI 可免费使用。</p>
        </section>}
        {tab === 'fleet' && <section className="harbor-section">
          <div className="harbor-title"><h3>在港舰型</h3><span>四种已核验舰型</span></div>
          <div className="hull-inventory">
            {(Object.entries(hulls) as [Hull, (typeof hulls)[Hull]][]).map(([id, hull]) => <div key={id} className={(state.owned[id] ?? 0) ? '' : 'unowned'}>
              <span>{hull.kind}</span><strong>{hull.name}</strong><small>拥有 {state.owned[id] ?? 0} 艘</small>
            </div>)}
          </div>
          <div className="harbor-title"><h3>出航预设</h3><span>{canDeploy ? '可以出航' : '舰艇不足'}</span></div>
          <div className="harbor-action preset-fields">
            <label>阵营 <select value={preset.side} onChange={(event) => setSide(event.target.value as Side)}>
              <option value="allies">同盟舰队</option><option value="axis">轴心舰队</option>
            </select></label>
            <label>领舰 <select value={preset.leaderSlot} onChange={(event) => {
              const leaderSlot = Number(event.target.value); change((s) => ({ ...s, preset: { ...s.preset, leaderSlot } }));
            }}>
              {rosters[preset.side].map((id, index) => <option key={index} value={index}>{hulls[id].name} · 第 {index + 1} 舰位</option>)}
            </select></label>
            <label>协助风格 <select value={preset.profile} onChange={(event) => {
              const profile = event.target.value as Profile; change((s) => ({ ...s, preset: { ...s.preset, profile } }));
            }}>
              {state.profiles.map((profile) => <option key={profile} value={profile}>{profileNames[profile]}</option>)}
            </select></label>
          </div>
          <p className="harbor-fine">标准演习要求同阵营 4 驱逐舰、1 轻巡。出航后默认手动，可在战斗内开启托管。</p>
          <div className="harbor-action"><button type="button" className="primary" disabled={!canDeploy || busy} onClick={() => onLaunch(preset)}>用预设出航</button>
            <button type="button" disabled={state.marks < 6 || state.profiles.includes('gunnery')}
              onClick={() => change(getGunnery)}>{state.profiles.includes('gunnery') ? '已拥有炮战 AI' : '6 勋章兑换炮战 AI'}</button></div>
        </section>}
        {tab === 'recruit' && <section className="harbor-section">
          <nav className="harbor-action" aria-label="补给分类">
            <button type="button" aria-pressed={economy === 'recruit'} onClick={() => setEconomy('recruit')}>舰船征募</button>
            <button type="button" aria-pressed={economy === 'supply'} onClick={() => setEconomy('supply')}>补给商店</button>
            <button type="button" aria-pressed={economy === 'ai'} onClick={() => setEconomy('ai')}>AI 战术</button>
          </nav>
          {economy === 'recruit' && <LocalRecruitDesk state={state} pool={pool} busy={busy || !!arrival} onPoolChange={setPool}
            onRecruit={recruit} onReview={id => setArrival({ id, replay: true })} onTraining={() => onSection?.('training')}
            onSupply={() => setEconomy('supply')} onCampaign={() => onSection?.('archive')} />}
          {economy === 'supply' && <>
            <div className="harbor-title"><h3>每周常驻券</h3><span>周一北京时间 00:00 刷新</span></div>
            <p className="harbor-fine">单机补给商店每周可兑换 1 张常驻券。</p>
            <div className="harbor-action"><button type="button" disabled={week.ticket || state.credits < WEEKLY_TICKET_PRICE}
              onClick={() => change(s => buyWeeklyTicket(s))}>{week.ticket ? '本周已兑换' : WEEKLY_TICKET_PRICE + ' 补给币兑换'}</button></div>
            <div className="harbor-title"><h3>每周实战补给</h3><span>{Math.min(week.count, 3)} / 3</span></div>
            <p className="harbor-fine">本周达成 3 局越级挑战的主目标，可领取 500 补给币和 3 张常驻券。</p>
            <div className="harbor-action"><button type="button" disabled={week.count < 3 || week.supply}
              onClick={() => change(s => claimWeeklySupply(s))}>{week.supply ? '本周已领取' : '领取每周实战补给'}</button></div>
          </>}
          {economy === 'ai' && <>
            <div className="harbor-title"><h3>AI 战术室</h3><span>已解锁 {AI_SHOP.filter(entry => aiShopUnlocked(entry, state.campaignProgress)).length} / {AI_SHOP.length}</span></div>
            <p className="harbor-fine">三条 evolved 战术为内测暂定强度（provisional），统一消耗常驻征募券；购买记录随本机账号保存，出航或战斗内可在「AI 风格」选用。</p>
            {aiNotice && <p className="harbor-fine" role="status" data-ai-shop-notice>{aiNotice}</p>}
            <div className="ai-shop-grid">
              {AI_SHOP.map(entry => {
                const owned = aiShopOwned(state, entry);
                const unlocked = aiShopUnlocked(entry, state.campaignProgress);
                const reason = aiShopBlockReason(state, entry);
                return <article key={entry.id} className="ai-shop-card" data-ai-profile={entry.id} data-owned={owned} data-unlocked={unlocked}>
                  <header><h4>{entry.name}</h4>{entry.provisional && <span className="ai-shop-provisional">暂定强度</span>}</header>
                  <p className="ai-shop-description">{entry.description}</p>
                  <p className="ai-shop-unlock">解锁：通关「{entry.stageName}」{unlocked ? '（已达成）' : `（当前 ${aiShopStars(entry, state.campaignProgress)} 星）`}</p>
                  <div className="ai-shop-buy">
                    <span>{entry.cost} 常驻征募券</span>
                    <button type="button" className={owned ? '' : 'primary'} disabled={busy || !!reason}
                      onClick={() => {
                        change(current => buyAiShopEntry(current, entry));
                        setAiNotice(`已购入「${entry.name}」，可在出航编队或战斗内选用。`);
                      }}>{owned ? '已拥有' : !unlocked ? '未解锁' : reason ? '征募券不足' : '购买'}</button>
                  </div>
                  {reason && <p className="ai-shop-reason">{reason}</p>}
                </article>;
              })}
            </div>
            <div className="harbor-title"><h3>既有战术</h3><span>舰队勋章</span></div>
            <div className="harbor-action"><button type="button" disabled={state.marks < 6 || state.profiles.includes('gunnery')}
              onClick={() => change(getGunnery)}>{state.profiles.includes('gunnery') ? '已拥有炮战 AI' : '6 勋章兑换炮战 AI'}</button></div>
          </>}
        </section>}
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
          onNight={() => onLaunch({ side: preset.side, profile: preset.profile, leaderSlot: preset.leaderSlot, variant: 'night' })} />}
      </section>
    </div>
    {arrival && arrivalReceipts.length > 0 && <RecruitArrival key={arrival.id} receipts={arrivalReceipts} replay={arrival.replay} onClose={() => setArrival(undefined)} />}
  </main>;
}
