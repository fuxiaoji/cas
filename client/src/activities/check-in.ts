// Reward schedule and Beijing day boundary from 铁底湾 mobile/src/activities/check-in.ts.
import type { PortState } from '../port';

const DAY_MS=86400000, BEIJING_OFFSET=8*3600000;
const beijingDay=(now:number)=>Math.floor((now+BEIJING_OFFSET)/DAY_MS);
type Reward={id:string;credits?:number;standard_tickets?:number;up_tickets?:number;ship_ids?:string[]};
export const CHECK_IN_SHIP_ID='IBS-U-USN-UNNAMED-T01-R03';
const SCHEDULE:Omit<Reward,'id'>[]=[
 {credits:500,standard_tickets:2}, {up_tickets:2}, {credits:800,standard_tickets:3}, {up_tickets:3},
 {credits:1200,standard_tickets:5}, {up_tickets:5}, {ship_ids:[CHECK_IN_SHIP_ID]},
];
export const CHECK_IN_REWARDS=SCHEDULE.map((reward,index)=>({...reward,id:`rookie-check-in-v1:${index+1}`}));

export function checkInStatus(state:PortState,now=Date.now()){
 const day=beijingDay(now),claimed=state.attendance.length,latest=state.attendance.at(-1)??-Infinity;
 const next=CHECK_IN_REWARDS[claimed];
 return {claimed,next,available:!!next&&day>latest&&!next.ship_ids,clockBehind:day<latest,
  shipPending:!!next?.ship_ids,refreshAt:(day+1)*DAY_MS-BEIJING_OFFSET};
}
export function checkInRewardLabels(reward:Reward,shipName:string){
 const labels:string[]=[];
 if(reward.credits)labels.push(`补给币 ×${reward.credits.toLocaleString()}`);
 if(reward.standard_tickets)labels.push(`常驻券 ×${reward.standard_tickets}`);
 if(reward.up_tickets)labels.push(`UP券 ×${reward.up_tickets}`);
 if(reward.ship_ids?.length)labels.push(shipName);
 return labels;
}
export function claimRookieCheckIn(state:PortState,now:number):PortState{
 const {next,available}=checkInStatus(state,now);
 if(!next||!available)return state;
 return {...state,attendance:[...state.attendance,beijingDay(now)],credits:state.credits+(next.credits??0),
  wallet:{standard:state.wallet.standard+(next.standard_tickets??0),up:state.wallet.up+(next.up_tickets??0)}};
}
