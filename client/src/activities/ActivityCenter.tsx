import {useCallback,useEffect,useRef,useState} from 'react';
import {onlineRequest} from '../online';
import type {OnlineMeta} from '../online';
import type {PortState} from '../port';
import {CHECK_IN_REWARDS,CHECK_IN_SHIP_ID,checkInRewardLabels,checkInStatus,claimRookieCheckIn} from './check-in';
import northCarolina from './assets/north-carolina.webp';
import './activity.css';

type Reward=(typeof CHECK_IN_REWARDS)[number]&{medals?:number};
type OnlineActivity={token:string;onMeta:(meta:OnlineMeta)=>void};
type Status={claimed:number;next?:Reward|null;available:boolean;clockBehind:boolean;shipPending:boolean};
interface CloudStatus {
 version:string;day:string;last_day:string|null;claimed:number;available:boolean;clock_behind:boolean;
 ship_pending:boolean;refresh_at:number;next:Reward|null;rewards:Reward[];
}
type CloudClaim={claimed:boolean;rewards:Reward[];check_in:CloudStatus;meta:OnlineMeta};
interface Props {state:PortState;onClose:()=>void;change:(reducer:(s:PortState)=>PortState)=>void;online?:OnlineActivity}
type ViewProps={onClose:()=>void;online?:boolean;status?:Status;rewards?:Reward[];message?:string;
 error?:boolean;busy?:boolean;action:()=>void;retry?:'同步'|'领取'};
const shipName='北卡罗来纳';
const rewardLabels=(reward:Reward)=>[
 ...checkInRewardLabels(reward,shipName),
 ...(reward.medals?[ `舰队勋章 ×${reward.medals}` ]:[]),
];

function useRefreshAt(refreshAt:number|undefined,refresh:()=>void){
 useEffect(()=>{
  const timer=refreshAt===undefined?undefined:window.setTimeout(refresh,Math.max(0,refreshAt-Date.now())+50);
  const onVisible=()=>{if(!document.hidden)refresh()};
  window.addEventListener('app-foreground',refresh);
  window.addEventListener('focus',refresh);
  document.addEventListener('visibilitychange',onVisible);
  return ()=>{
   window.clearTimeout(timer);window.removeEventListener('app-foreground',refresh);
   window.removeEventListener('focus',refresh);document.removeEventListener('visibilitychange',onVisible);
  };
 },[refreshAt,refresh]);
}

function LocalActivity({state,onClose,change}:Omit<Props,'online'>){
 const [now,setNow]=useState(Date.now),[notice,setNotice]=useState<{text:string;dayEnd:number}>();
 const status=checkInStatus(state,now);
 const refresh=useCallback(()=>setNow(Date.now()),[]);
 useRefreshAt(status.refreshAt,refresh);
 const claim=()=>{
  const time=Date.now(),status=checkInStatus(state,time),dayEnd=status.refreshAt;
  if(status.available&&status.next){
   change(s=>claimRookieCheckIn(s,time));setNotice({text:`已领取${rewardLabels(status.next).join('、')}。`,dayEnd});
  }
  setNow(time);
 };
 return <CheckInView onClose={onClose} status={status} action={claim}
  message={notice?.dayEnd===status.refreshAt?notice.text:undefined}/>;
}

function OnlineActivity({token,onMeta,onClose}:OnlineActivity&{onClose:()=>void}){
 const [remote,setRemote]=useState<CloudStatus>();
 const [notice,setNotice]=useState<{day:string;text:string}>();
 const [problem,setProblem]=useState<{text:string;retry:'同步'|'领取'}>();
 const [busy,setBusy]=useState(true);
 const sequence=useRef(0), active=useRef(false);
 const pending=useRef<{day:string;id:string}|undefined>(undefined);
 const refresh=useCallback(async()=>{
  if(active.current)return;
  const ticket=++sequence.current;
  active.current=true;setBusy(true);setProblem(undefined);
  try{
   const response=await onlineRequest<CloudStatus>('/missions/check-in',token);
   if(ticket===sequence.current)setRemote(response);
  }catch(error){
   if(ticket===sequence.current)setProblem({text:(error as Error).message,retry:'同步'});
  }finally{
   if(ticket===sequence.current){active.current=false;setBusy(false)}
  }
 },[token]);
 useEffect(()=>{
  void refresh();
  return ()=>{++sequence.current;active.current=false};
 },[refresh]);
 useRefreshAt(remote?.refresh_at,refresh);

 async function claim(){
  if(!remote?.available||active.current)return;
  const ticket=++sequence.current;
  if(pending.current?.day!==remote.day)pending.current={day:remote.day,id:crypto.randomUUID()};
  active.current=true;setBusy(true);setProblem(undefined);setNotice(undefined);
  try{
   const response=await onlineRequest<CloudClaim>('/missions/check-in/claim',token,{request_id:pending.current.id});
   // Refresh the wallet even when the player has already left this page.
   onMeta(response.meta);
   if(ticket!==sequence.current)return;
   pending.current=undefined;setRemote(response.check_in);
   if(response.claimed)setNotice({day:response.check_in.day,text:`已领取${response.rewards.flatMap(rewardLabels).join('、')}。`});
  }catch(error){
   if(ticket===sequence.current)setProblem({text:(error as Error).message,retry:'领取'});
  }finally{
   if(ticket===sequence.current){active.current=false;setBusy(false)}
  }
 }
 const status=remote&&{claimed:remote.claimed,next:remote.next,available:remote.available,
  clockBehind:remote.clock_behind,shipPending:remote.ship_pending};
 return <CheckInView online onClose={onClose} status={status} rewards={remote?.rewards} busy={busy}
  error={!!problem} retry={problem?.retry}
  action={()=>void(problem?.retry==='同步'?refresh():claim())}
  message={problem?.text??(notice?.day===remote?.day?notice?.text:undefined)}/>;
}

function CheckInView({onClose,online,status,rewards=CHECK_IN_REWARDS,message,error,busy,retry,action}:ViewProps){
 const {claimed,next,available,clockBehind,shipPending}=status??{};
 const done=!!status&&!next;
 const dayReward=available&&next?.ship_ids?.length;
  const hint=message||(busy&&online?'正在同步签到…':done?'七天奖励已全部领取。':
  shipPending?(online?'北卡罗来纳舰卡尚未就绪，保留签到进度。':'单机档暂不发放签到舰船，联机内测第七天可领取北卡罗来纳。'):
  clockBehind?(online?'签到日期尚未更新，请稍后再试。':'请检查设备日期和时间。'):
  available?'今天的补给已备好。':'今日已签到，明天可继续。');
 const actionLabel=busy?'请稍候':retry?`重试${retry}`:done?'已全部领取':
  available?`领取第 ${(claimed??0)+1} 天奖励`:shipPending||clockBehind?'暂不能签到':'今日已领取';
 return <main className="activity-center">
  <header className="activity-header">
   <button type="button" onClick={onClose} aria-label="返回"><span aria-hidden="true">‹</span> 返回</button>
   <h1>活动中心</h1>
   <span className="activity-edition">{online?'联机免费内测':'单机航程'}</span>
  </header>
  <div className="activity-scroll">
   <article className="activity-check-in" aria-labelledby="check-in-title">
    <section className="activity-log">
     <div className="activity-title">
      <div><h2 id="check-in-title">新手七日签到</h2><p>每天领一份，漏签可接着领。</p></div>
      <span className="activity-progress" aria-label={claimed===undefined?'正在同步签到进度':`已签到 ${claimed} 天，共 ${rewards.length} 天`}><b>{claimed??'—'}</b> / {rewards.length} 天</span>
     </div>
     <ol className="activity-route" aria-label="七日签到奖励">
      {rewards.map((reward,index)=>{
       const taken=claimed!==undefined&&index<claimed,current=next?.id===reward.id&&available;
       const labels=rewardLabels(reward);
       return <li key={reward.id} className={`activity-day${taken?' is-taken':current?' is-current':''}${reward.ship_ids?' is-flagship':''}`} aria-current={current?'step':undefined}>
        <span className="activity-day-number">{String(index+1).padStart(2,'0')}</span>
        <span className="activity-day-rewards">{labels.map(label=><strong key={label}>{label}</strong>)}</span>
        <small>{taken?'已领':current?'可领':status?'待解锁':'待同步'}</small>
       </li>;
      })}
     </ol>
    </section>
    <aside className="activity-flagship" aria-label={`第七天奖励：战列舰${shipName}`}>
     {rewards.some(reward=>reward.ship_ids?.includes(CHECK_IN_SHIP_ID))&&
      <img src={northCarolina} alt={shipName+'立绘'} data-character={CHECK_IN_SHIP_ID} decoding="async"/>}
     <div className="activity-flagship-caption">
      <span>{done?'七日航程完成':'第 7 天奖励'} <i aria-hidden="true">◆</i> 战列舰</span>
      <h3>{shipName}</h3>
      <small>{done?'第七天奖励已结算':dayReward?'今日可领取':online?'舰卡已核验 · 第 7 天入列':'第 7 天入列，联机内测领取'}</small>
     </div>
    </aside>
   </article>
  </div>
  <footer className="activity-footer">
   <div>
    <p role="status" className={error?'activity-error':undefined}>{hint}</p>
    <small>每天北京时间 00:00 刷新</small>
   </div>
   <button type="button" className="primary" onClick={action} disabled={busy||(!available&&!retry)}>{actionLabel}</button>
  </footer>
 </main>;
}

export function ActivityCenter({online,onClose,...local}:Props){
 return online?<OnlineActivity key={online.token} {...online} onClose={onClose}/>:<LocalActivity {...local} onClose={onClose}/>;
}
