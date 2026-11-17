//! Optional fictional fleet fuel. Absence is the frozen legacy path.
use crate::{model::*,salvage::Start,world::World};
use serde::{Deserialize,Serialize};
use serde_json::{json,Value};
pub const VERSION:&str="fleet-fuel-v1";
#[derive(Clone,Debug,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config{pub version:String,pub initial:u32}
#[derive(Clone,Debug)]
pub struct Tank{pub initial:u32,pub remaining_milli:u64,pub capacity:u32,pub exhausted_at:Option<u32>,pub warned:bool,pub ships:Vec<Value>}
pub fn preview(start:&Start)->E<Value>{
 let records:Value=serde_json::from_str(include_str!("../data/salvage/cargo-tonnage-v1.json")).unwrap();
 let data=if crate::amphibious_expedition::is_version(&start.gameplay_profile){crate::littoral_v4::extended_data()?}else{crate::salvage_v3::expedition_data()?};let mut ships=vec![];let mut rate=0u32;
 for h in &start.fleet{let d=data.ships.iter().find(|d|d.id==h.id).ok_or("油料预览舰船身份未登记")?;let row=&records["ships"][&h.id];let verified=row["tons"].as_u64();let tons=verified.unwrap_or(match d.kind.as_str(){"BB"|"BC"=>30000,"CA"=>10000,"CL"=>6500,"CV"=>20000,"APD"=>1400,_=>2000}) as u32;let units=tons.div_ceil(1000);rate+=units;
  ships.push(json!({"id":h.id,"tons":tons,"tonnage_status":if verified.is_some(){"source_registered"}else{"fictional_budget_fallback"},"cruise_per_minute":units}));}
 if ships.is_empty(){return Err("油料预览需要编队".into());}
 Ok(json!({"version":VERSION,"capacity":rate*12,"recommended":rate*8,"cruise_per_minute":rate,"idle_per_minute":rate as f64*0.2,"ships":ships}))
}
#[cfg(test)]mod tests{use super::*;
 fn start(id:&str,initial:u32)->Start{serde_json::from_value(json!({"content":"salvage-v4","gameplay_profile":"cas-adventure-v2","fleet":[{"id":id,"hp":100,"ammo":100,"level":0}],"mission":{"kind":"salvage","id":"calm","loot_kind":"scrap"},"cargo_v4":{"commander_level":1,"difficulty":"calm","environment":"atoll","weather":"clear","loadouts":{}},"expedition_v2":{"scene":"sunken_metropolis","munitions":{}},"fuel_v1":{"version":VERSION,"initial":initial}})).unwrap()}
 #[test]fn tonnage_and_quadratic_speed_change_real_consumption(){let mut dd=World::new_salvage(42,start("IBS-U-USN-FLETCHER",10)).unwrap();let bbstart=start("IBS-U-USN-WASHINGTON",10);let mut bb=World::new_salvage(42,bbstart).unwrap();for w in [&mut dd,&mut bb]{w.ships[0].speed=20.;for _ in 0..10{w.tick+=1;w.advance_fuel();}}assert!(bb.fuel.as_ref().unwrap().remaining_milli<dd.fuel.as_ref().unwrap().remaining_milli);dd.ships[0].speed=10.;let slow=dd.fuel_rate_milli();dd.ships[0].speed=30.;assert!(dd.fuel_rate_milli()>slow*3);}
 #[test]fn empty_tank_stops_propulsion_and_rescue_is_real_failure(){let mut w=World::new_salvage(42,start("IBS-U-USN-FLETCHER",0)).unwrap();assert!(w.external(json!({"op":"route","fleet":1,"mode":"follow","speed":20,"points":[{"x":6000,"y":2200}]})).is_err());for _ in 0..61{w.tick+=1;w.advance_fuel();}assert_eq!(w.result.as_ref().unwrap().primary,Some(false));assert_eq!(w.observation(0)["fuel_receipt"]["remaining"],0);}
 #[test]fn preview_rejects_overfill_and_unknown_version(){let mut s=start("IBS-U-USN-FLETCHER",100000);assert!(validate(&s).is_err());s.fuel_v1.as_mut().unwrap().initial=1;s.fuel_v1.as_mut().unwrap().version="unknown".into();assert!(validate(&s).is_err());}
}
pub fn validate(start:&Start)->E<()>{if let Some(c)=&start.fuel_v1{let p=preview(start)?;if c.version!=VERSION||c.initial>p["capacity"].as_u64().unwrap() as u32{return Err("油料版本或初始装载量无效".into());}if !crate::salvage::modern(&start.content){return Err("旧v1行动不能启用新油料规则".into());}}Ok(())}
impl World{
 pub(crate) fn init_fuel(&mut self)->E<()>{let b=self.salvage.as_ref().unwrap();if let Some(c)=&b.start.fuel_v1{let p=preview(&b.start)?;self.fuel=Some(Tank{initial:c.initial,remaining_milli:c.initial as u64*1000,capacity:p["capacity"].as_u64().unwrap() as u32,exhausted_at:None,warned:false,ships:p["ships"].as_array().unwrap().clone()});}Ok(())}
 pub(crate) fn fuel_empty(&self)->bool{self.fuel.as_ref().is_some_and(|f|f.remaining_milli==0)}
 fn fuel_rate_milli(&self)->u64{let Some(f)=&self.fuel else{return 0;};f.ships.iter().map(|row|{let id=row["id"].as_str().unwrap();let speed=self.ships.iter().find(|s|s.side==self.player&&s.character.as_deref()==Some(id)&&s.alive()).map(|s|s.speed);speed.map_or(0.,|k|row["cruise_per_minute"].as_f64().unwrap()*(200.+800.*(k/20.)*(k/20.))/60.)}).sum::<f64>().ceil() as u64}
 pub(crate) fn advance_fuel(&mut self){
  if self.result.is_some(){return;}let rate=self.fuel_rate_milli();let f=self.fuel.as_mut().unwrap();f.remaining_milli=f.remaining_milli.saturating_sub(rate);
  let low=f.remaining_milli*5<=f.capacity as u64*1000;let emit_low=low&&!f.warned;f.warned|=low;let emit_empty=f.remaining_milli==0&&f.exhausted_at.is_none();if emit_empty{f.exhausted_at=Some(self.tick);}let rescue=f.exhausted_at.is_some_and(|t|self.tick.saturating_sub(t)>=60);
  if f.remaining_milli==0{for fleet in &mut self.fleets{if fleet.side==self.player{fleet.speed=0.;}}}
  if emit_low{self.add(1,"fuel_low","舰队油料偏低，请检查返航余量。".into(),Some(VERSION),None);}
  if emit_empty{self.add(1,"fuel_empty","油料耗尽，推进停止；60秒后拖救队接管。附近撤离点仍可使用。".into(),Some(VERSION),None);}
  if rescue{self.finish_salvage(false);}
 }
 pub(crate) fn fuel_view(&self,view:&mut Value){let Some(f)=&self.fuel else{return;};let rate=self.fuel_rate_milli();let ships:Vec<_>=self.ships.iter().filter(|s|s.side==self.player&&s.alive()).collect();
  let distance=self.salvage.as_ref().map_or(0.,|b|b.exits.iter().map(|p|ships.iter().map(|s|s.p.dist(*p)).fold(0.,f64::max)).fold(f64::INFINITY,f64::min));let return_seconds=(distance/(20.*KNOT*if self.adventure(){10.}else{1.})).ceil() as u32+20;
  let state=if f.remaining_milli==0{"empty"}else if f.remaining_milli*5<=f.capacity as u64*1000{"low"}else{"normal"};
  let cruise:f64=f.ships.iter().map(|r|r["cruise_per_minute"].as_f64().unwrap()).sum();
  view["fuel"]=json!({"version":VERSION,"loaded":f.initial,"remaining":f.remaining_milli as f64/1000.,"refundable":f.remaining_milli/1000,"consumed":f.initial-(f.remaining_milli/1000) as u32,"capacity":f.capacity,"fraction":f.remaining_milli as f64/(f.capacity as f64*1000.).max(1.),"state":state,"rate_per_minute":rate as f64*60./1000.,"estimated_seconds":if rate==0{0}else{f.remaining_milli/rate},"return_seconds":return_seconds,"return_required":(cruise*return_seconds as f64/60.*1.5).ceil() as u32,"rescue_in":f.exhausted_at.map(|t|60-self.tick.saturating_sub(t).min(60)),"ships":f.ships});
  if self.result.is_some(){view["fuel_receipt"]=json!({"version":VERSION,"loaded":f.initial,"remaining":f.remaining_milli/1000,"consumed":f.initial-(f.remaining_milli/1000) as u32});}
 }
}
