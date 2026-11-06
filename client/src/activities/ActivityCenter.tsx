import {useEffect,useState} from 'react';
import type {PortState} from '../port';
import {CHECK_IN_REWARDS,checkInRewardLabels,checkInStatus,claimRookieCheckIn} from './check-in';
import './activity.css';

interface Props {state:PortState;onClose:()=>void;change:(reducer:(s:PortState)=>PortState)=>void}
export function ActivityCenter({state,onClose,change}:Props) {
 const [now,setNow]=useState(Date.now),[notice,setNotice]=useState<{text:string;error:boolean;dayEnd:number}>();
 const {claimed,next,available,clockBehind,shipPending,refreshAt}=checkInStatus(state,now);
 const message=notice?.dayEnd===refreshAt?notice:undefined;
 const shipName='北卡罗来纳';
 const done=!next;
 useEffect(()=>{
  const refresh=()=>setNow(Date.now());
  const timer=window.setTimeout(refresh,Math.max(0,refreshAt-Date.now())+50);
  window.addEventListener('app-foreground',refresh);
  window.addEventListener('focus',refresh);
  return ()=>{window.clearTimeout(timer);window.removeEventListener('app-foreground',refresh);window.removeEventListener('focus',refresh)};
 },[refreshAt]);
 const claim=()=>{
  const time=Date.now(),status=checkInStatus(state,time),dayEnd=status.refreshAt;
  if(status.available&&status.next){change(s=>claimRookieCheckIn(s,time));setNotice({text:`已领取${checkInRewardLabels(status.next,shipName).join('、')}。`,error:false,dayEnd});}
  setNow(time);
 };
 return <main className="activity-center">
  <header className="activity-header">
   <button type="button" onClick={onClose} aria-label="返回"><span aria-hidden="true">‹</span> 返回</button>
   <h1>活动中心</h1>
   <span className="activity-edition">单机航程</span>
  </header>
  <div className="activity-scroll">
   <article className="activity-check-in" aria-labelledby="check-in-title">
    <section className="activity-log">
     <div className="activity-title">
      <div><h2 id="check-in-title">新手七日签到</h2><p>每天领一份，漏签可接着领。</p></div>
      <span className="activity-progress" aria-label={`已签到 ${claimed} 天，共 ${CHECK_IN_REWARDS.length} 天`}><b>{claimed}</b> / {CHECK_IN_REWARDS.length} 天</span>
     </div>
     <ol className="activity-route" aria-label="七日签到奖励">
      {CHECK_IN_REWARDS.map((reward,index)=>{
       const taken=index<claimed,current=next?.id===reward.id&&available;
       const labels=checkInRewardLabels(reward,shipName);
       return <li key={reward.id} className={`activity-day${taken?' is-taken':current?' is-current':''}${reward.ship_ids?' is-flagship':''}`} aria-current={current?'step':undefined}>
        <span className="activity-day-number">{String(index+1).padStart(2,'0')}</span>
        <span className="activity-day-rewards">{labels.map(label=><strong key={label}>{label}</strong>)}</span>
        <small>{taken?'已领':current?'可领':'待解锁'}</small>
       </li>;
      })}
     </ol>
    </section>
    <aside className="activity-flagship" aria-label={`第七天奖励：战列舰${shipName}`}>
     <div className="activity-flagship-caption">
      <span>{done?'七日航程完成':'第 7 天入列'} <i aria-hidden="true">◆</i> 战列舰</span>
      <h3>{shipName}</h3>
      <small>舰卡核验完成后开放领取</small>
     </div>
    </aside>
   </article>
  </div>
  <footer className="activity-footer">
   <div>
    <p role="status" className={message?.error?'activity-error':undefined}>{message?.text||(done?'七天奖励已全部领取。':shipPending?'北卡罗来纳舰卡尚未就绪，保留签到进度。':clockBehind?'请检查设备日期和时间。':available?'今天的补给已备好。':'今日已签到，明天可继续。')}</p>
    <small>每天北京时间 00:00 刷新</small>
   </div>
   <button type="button" className="primary" onClick={claim} disabled={!available}>{done?'已全部领取':available?`领取第 ${claimed+1} 天奖励`:shipPending||clockBehind?'暂不能签到':'今日已领取'}</button>
  </footer>
 </main>;
}
