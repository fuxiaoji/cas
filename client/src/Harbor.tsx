import { useState } from 'react';
import { CampaignArchive } from './CampaignArchive';
import { profileNames, sideNames } from './engine';
import type { Profile, Side } from './engine';
import { drawRecruit, getGunnery, hulls, lessons, meetsRoster, receiveChallenge, receiveStarter, rosters } from './port';
import type { Hull, PortLaunch, PortState } from './port';
import './harbor.css';

type HarborTab = 'training' | 'fleet' | 'recruit' | 'challenge' | 'archive';
type Props = { state: PortState; change: (reducer: (current: PortState) => PortState) => void;
  onReturn: () => void; onLaunch: (options: PortLaunch) => void; busy: boolean; error?: string };
const tabs: { id: HarborTab; name: string }[] = [
  { id: 'training', name: '舰桥学堂' }, { id: 'fleet', name: '舰库与编队' },
  { id: 'recruit', name: '本机征募' }, { id: 'challenge', name: '越级挑战' },
  { id: 'archive', name: 'CAS 战役档案' },
];
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

export function Harbor({ state, change, onReturn, onLaunch, busy, error }: Props) {
  const [tab, setTab] = useState<HarborTab>('training');
  const [starterSide, setStarterSide] = useState<Side>(state.preset.side);
  const [pool, setPool] = useState<'standard' | 'up'>('standard');
  const nextLesson = lessons.find(({ id }) => !state.lessons.includes(id));
  const { preset } = state;
  const canDeploy = state.starter && meetsRoster(state, preset.side);
  const canChallenge = state.starter && meetsRoster(state, preset.side, true);
  const last = state.history.find((draw) => draw.pool === pool);
  function setSide(side: Side) { change((s) => ({ ...s, preset: { ...s.preset, side, leaderSlot: 0 } })); }
  return <main className="harbor">
    <header className="harbor-head">
      <div><span>CAS 舰队勤务</span><h1>母港</h1></div>
      <div className="harbor-wallet">
        <span>常驻券 <b>{state.wallet.standard}</b></span><span>UP 券 <b>{state.wallet.up}</b></span><span>舰队勋章 <b>{state.marks}</b></span>
      </div>
      <button type="button" onClick={onReturn} disabled={busy}>返回海图</button>
    </header>
    <div className="harbor-body">
      <nav className="harbor-tabs" aria-label="母港区域">
        {tabs.map(({ id, name }) => <button key={id} type="button" aria-pressed={tab === id} onClick={() => setTab(id)}>{name}</button>)}
        <span>离线演习进度</span>
      </nav>
      <section className="harbor-content">
        <div className="harbor-hero"><HarborArt /><div><p>停泊区</p><h2>{tabs.find(({ id }) => id === tab)?.name}</h2></div></div>
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
            {nextLesson && <button type="button" className="primary" disabled={busy} onClick={() => onLaunch({ side: starterSide, profile: 'coord', leaderSlot: 0, training: true })}>进入实操演习</button>}
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
          <div className="harbor-title"><h3>演习舰招募</h3><span>本机体验池</span></div>
          <div className="harbor-action">
            <button type="button" aria-pressed={pool === 'standard'} onClick={() => setPool('standard')}>常驻池</button>
            <button type="button" aria-pressed={pool === 'up'} onClick={() => setPool('up')}>阵营 UP 池</button>
          </div>
          <p className="harbor-fine">{pool === 'standard' ? '常驻池可招募两个阵营，阵营等概率。' : 'UP 池当前招募：' + sideNames[state.upSide] + '，补充初始舰队以外的舰型。'}
            驱逐舰 85%，轻巡洋舰 15%；连续 9 次未获得轻巡时，第 10 次必出。两池独立计数。</p>
          <div className="harbor-action">
            <button type="button" className="primary" disabled={!state.starter || state.wallet[pool] < 1} onClick={() => change((s) => drawRecruit(s, pool))}>用 1 张{pool === 'standard' ? '常驻' : ' UP '}券征募</button>
            <span>距离保底至多 {10 - state.pity[pool]} 抽</span>
          </div>
          {last && <div className="recruit-result" role="status">
            <span>{last.guaranteed ? '保底到港' : '最新到港'}</span><strong>{hulls[last.hull].name}</strong>
            <small>{last.duplicate ? '该舰型仓位已满，已转换为舰队勋章。' : '已编入本机舰库。'}</small>
          </div>}
        </section>}
        {tab === 'challenge' && <section className="harbor-section">
          <div className="harbor-title"><h3>少舰迎击</h3><span>3 对 5</span></div>
          <p className="harbor-fine">带领 2 艘驱逐舰和 1 艘轻巡作战。击沉至少 2 艘敌舰，且至少保留 1 艘己方舰艇，即达成挑战目标。</p>
          <p className="harbor-fine">{sideNames[preset.side]} · 三舰沿用预设前 3 舰位；若预设领舰不在前三位，由第一舰位接任。</p>
          <div className="harbor-action"><button type="button" className="primary" disabled={busy || !canChallenge}
            onClick={() => onLaunch({ ...preset, leaderSlot: preset.leaderSlot < 3 ? preset.leaderSlot : 0, variant: 'challenge' })}>出航挑战</button>
            <button type="button" disabled={!state.challengeClear || state.challengeClaim} onClick={() => change(receiveChallenge)}>
              {state.challengeClaim ? '已领取挑战奖励' : '领取挑战奖励'}</button></div>
          <p className="harbor-fine">首通奖励：雷击 AI 与 2 张常驻券。</p>
        </section>}
        {tab === 'archive' && <CampaignArchive busy={busy} onNight={() => onLaunch({ side: preset.side, profile: preset.profile, leaderSlot: preset.leaderSlot, variant: 'night' })} />}
      </section>
    </div>
  </main>;
}
