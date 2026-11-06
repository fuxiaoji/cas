// Mother-port view copied from 铁底湾 mobile/src/progression/GrowthPort.tsx at 3ba9c5b.
// Keep the original mother-port structure; the adapter reads only the CAS account.
import {useEffect,useRef,useState} from 'react';
import {hulls,lessons} from './port';
import type {PortState} from './port';
import type {OnlineMeta} from './online';
import {shipPortrait} from './shipPortraits';
import './growth-port.css';

export type LobbySection='academy'|'campaign'|'challenge'|'fleet'|'economy'|'activities';
interface Props {state:PortState;onNavigate:(section:LobbySection)=>void;onHome:()=>void;onReplayPrologue:()=>void;onWatch:(id:string)=>void;online?:{meta?:OnlineMeta;error?:string};}
function DockIcon({kind}:{kind:string}){return <svg viewBox="0 0 40 40" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">{kind==='fleet'?<><path d="M5 25h30l-5 8H11zM13 25V14h14v11M18 14V7h4v7M8 20h5m14 0h5M5 36h30"/><path d="M17 19h6"/></>:kind==='academy'?<><path d="m3 15 17-8 17 8-17 8zM10 20v10q10 7 20 0V20M36 16v15"/></>:kind==='supply'?<><path d="m8 13 12-6 12 6v18l-12 6-12-6zM8 13l12 6 12-6M20 19v18M14 10l12 6v9"/></>:kind==='online'?<><circle cx="20" cy="20" r="14"/><path d="M6 20h28M20 6c-10 10-10 18 0 28 10-10 10-18 0-28M10 11q10 7 20 0M10 29q10-7 20 0"/></>:<><circle cx="20" cy="20" r="13"/><path d="m20 8 4 12-4 12-4-12zM5 20h7m16 0h7M20 3v3m0 28v3"/></>}</svg>}
export function GrowthPort({state,onNavigate,onHome,onReplayPrologue,onWatch,online}:Props){
 const offlineBeta=true;
 const stepTotal=lessons.length;
 const meta={completed_steps:state.lessons,completed_courses:state.courses,
  owned_ships:Object.entries(state.owned).flatMap(([id,count])=>Array.from({length:count},()=>id)),
  wallet:online?online.meta?.wallet:{credits:state.credits,up_tickets:state.wallet.up,standard_tickets:state.wallet.standard,tickets:0,medals:state.marks}};
 const entries=Object.entries(hulls).flatMap(([id,hull])=>{const art=shipPortrait(id);return art?[{id,name:art.name,type:hull.kind,portrait:art.src,personality:id==='fletcher'?'有主见的先锋，遇事先把同伴护在身后。':undefined}]:[]});
 const availableWatch=entries.filter(ship=>meta.owned_ships.includes(ship.id));
 const activeWatch=availableWatch.find(ship=>ship.id===state.watch)??availableWatch[0];
 const watch=activeWatch??entries.find(ship=>ship.id==='fletcher');
 const [watchSearch,setWatchSearch]=useState('');
 const watchDialog=useRef<HTMLDialogElement>(null);
 const searchTerm=watchSearch.trim().toLowerCase();
 const visibleWatch=availableWatch.filter(ship=>[ship.name,ship.id,ship.type].some(value=>value.toLowerCase().includes(searchTerm)));
 function openWatchPicker(){setWatchSearch('');watchDialog.current?.showModal();}
 function selectWatch(id:string){onWatch(id);watchDialog.current?.close();}
 useEffect(()=>{const closeOnBack=(event:Event)=>{if(watchDialog.current?.open){event.stopImmediatePropagation();watchDialog.current.close();}};window.addEventListener('hardware-back',closeOnBack,true);return()=>window.removeEventListener('hardware-back',closeOnBack,true);},[]);
 return <div className="growth-shell">
<main className="growth-port">
  <div className="growth-harbor" aria-hidden="true"/>
  <header className="growth-header"><button onClick={onHome} aria-label="打开主菜单">‹ 主菜单</button><div className="growth-port-title"><strong>母港</strong><span>铁底湾的回响</span></div>
   <div className="growth-wallet" aria-label="航程资源">
    <span><i aria-hidden="true">◈</i><b>{meta.wallet?.credits.toLocaleString()??'—'}</b><small>补给币</small></span>
    <span><i aria-hidden="true">▱</i><b>{meta.wallet?.up_tickets??'—'}</b><small>UP券</small></span>
    <span><i aria-hidden="true">▱</i><b>{meta.wallet?.standard_tickets??'—'}</b><small>常驻券</small></span>
    {!!meta.wallet?.tickets&&<span><i aria-hidden="true">▱</i><b>{meta.wallet.tickets}</b><small>旧通用券</small></span>}
    <span><i aria-hidden="true">✧</i><b>{meta.wallet?.medals??'—'}</b><small>舰队勋章</small></span>
   </div>
  </header>
  <section className="growth-welcome">
   <aside className="growth-orders"><div className="growth-watch"><span className="growth-beacon"/>夜航值更中</div><div className="growth-welcome-copy"><p>欢迎回港，指挥官</p><h1>灯火已亮，<br/>舰队待命。</h1><p>{meta.completed_courses.length?'沿历史航线出击，在夜海中写下自己的战果。':'从第一道航路口令开始。澪教官会陪你完成初航。'}</p></div><button className="growth-lesson" onClick={()=>onNavigate('academy')}><DockIcon kind="academy"/><span><strong>{meta.completed_courses.length===3?'学堂全课结业':'初航训练计划'}</strong><small>实操进度 {meta.completed_steps.length} / {stepTotal}</small><progress value={meta.completed_steps.length} max={stepTotal}/></span><b>›</b></button><div className="growth-fleet-status"><small>舰库整备</small><strong>{meta.owned_ships.length}<span> 艘舰船已入列</span></strong></div></aside>
   <div className="growth-officer"><div className="growth-bearing" aria-hidden="true"><span>北</span><i/><b>铁底湾泊地</b></div>
    <img key={watch?.id} src={watch?.portrait} alt={(watch?.name||'值更舰')+'立绘'}/>
    <div className="growth-nameplate"><span>{activeWatch?'值更舰':'港口看板'}</span><strong>{watch?.name||'弗莱彻'}</strong><small>{watch?.personality||watch?.type||'值更教官'}</small>
     <button type="button" className="growth-watch-choose" onClick={openWatchPicker} aria-haspopup="dialog" aria-controls="growth-watch-picker">选择值更舰</button>
    </div>
   </div>
   <nav className="growth-operations" aria-label="出击任务"><button className="growth-campaign-entry" data-guide="campaign" onClick={()=>onNavigate('campaign')}><small>历史战役</small><h2>战役航线</h2><p>同盟与轴心 · 三档难度</p><span className="growth-sortie"><DockIcon kind="compass"/>出击</span></button><button className="growth-challenge-entry" data-guide="challenge" onClick={()=>onNavigate('challenge')}><div><small>以少胜多，赢取新舰</small><h2>越级挑战</h2><p>每周可领 3 次复战奖励</p></div><b>›</b></button><button className="growth-next" onClick={()=>onNavigate(meta.completed_courses.length?'campaign':'academy')}>{meta.completed_courses.length?'继续战役':'登舰上课'}<span>›</span></button></nav>
  </section>
  <nav className={`growth-dock${offlineBeta?' growth-dock-with-activities':''}`} aria-label="母港功能">
   <button data-guide="fleet" onClick={()=>onNavigate('fleet')}><DockIcon kind="fleet"/><span><strong>{online?'舰船收藏':'舰库与编队'}</strong><small>{online?`已收藏 ${online.meta?.owned_ships.length??'—'} 艘`:'查看舰船 · 整备出战'}</small></span></button>
   <button data-guide="economy" onClick={()=>onNavigate('economy')}><DockIcon kind="supply"/><span><strong>征募与补给</strong><small>{online?'双池征募 · 商店与邮箱':'新舰入列 · 战术包兑换'}</small></span></button>
   {offlineBeta&&<button onClick={()=>onNavigate('activities')}><svg viewBox="0 0 40 40" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><path d="M10 6h23v29H10zM7 9h3m-3 7h3m-3 7h3m-3 7h3m5-16h13m-13 6h13m-13 6h6"/><path d="m24 27 2 2 4-5"/></svg><span><strong>活动中心</strong><small>新手七日签到</small></span></button>}
   <button onClick={()=>onNavigate('academy')}><DockIcon kind="academy"/><span><strong>教学复习</strong><small>{meta.completed_courses.length}/3 门实操课程</small></span></button>
   <button onClick={onReplayPrologue}><DockIcon kind="compass"/><span><strong>序章</strong><small>未明的海 · 白汐教学</small></span></button>
  </nav>
  <footer className="growth-foot"><span><i/>{online?(online.error?'联机钱包暂不可用':'联机账号已登录'):'本机航程已保存'}</span><span>{online?'免费内测 · 教学与练习保存在本机':'单机内测 · 无需联网'}</span></footer>
  <dialog ref={watchDialog} id="growth-watch-picker" className="growth-watch-dialog" aria-labelledby="growth-watch-title">
   <header className="growth-watch-dialog-head">
    <div>
     <h2 id="growth-watch-title">选择值更舰</h2>
     {activeWatch&&<p>当前值更：{activeWatch.name}</p>}
    </div>
    <button type="button" onClick={()=>watchDialog.current?.close()}>关闭</button>
   </header>
   {availableWatch.length>0&&<label className="growth-watch-search">
    <span>查找舰船</span>
    <input type="search" value={watchSearch} onChange={event=>setWatchSearch(event.target.value)} placeholder="输入舰名或舰种"/>
   </label>}
   <div className="growth-watch-options">
    {availableWatch.length===0?<p className="growth-watch-empty">舰库还没有带立绘的舰船。获得后即可安排值更。</p>:
     visibleWatch.length===0?<p className="growth-watch-empty" role="status">没有找到匹配的舰船。</p>:
     <ul>{visibleWatch.map(ship=>{
      const selected=ship.id===activeWatch?.id;
      return <li key={ship.id}>
       <button type="button" className="growth-watch-option" aria-pressed={selected} onClick={()=>selectWatch(ship.id)}>
        <img src={ship.portrait} alt="" loading="lazy"/>
        <span><strong>{ship.name}</strong><small>{selected?'当前值更':ship.type}</small></span>
       </button>
      </li>;
     })}</ul>}
   </div>
  </dialog>
 </main>
 </div>;
}
