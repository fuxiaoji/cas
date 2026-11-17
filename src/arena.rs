//! Versioned local bot arena. Fictional deployments, unchanged CAS cards and realtime v10.
use crate::{model::*,world::World};
use serde::{Deserialize,Serialize};
use serde_json::{json,Value};
use std::collections::BTreeSet;
pub(crate) const VERSION:&str="cas-local-arena-v1";
pub(crate) const VARIANT:&str="local-arena-v1";
#[derive(Clone,Debug,Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Group {pub id:String,pub name:String,pub ships:Vec<String>}
#[derive(Clone,Debug,Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Start {
    #[serde(default,skip_serializing_if="String::is_empty")] pub op:String,
    pub seed:u32,pub mode:String,pub arena_version:String,pub groups:Vec<Group>,
}
const BOTS:[&str;24]=["潮汐拾荒者","锈钟值班员","落日信标","蓝鲸邮差","旧港夜航","云下巡逻队","七号码头","失落的罗盘","银鸥补给站","盐风档案员","深海灯塔","远洋听潮人","白浪侦察员","锈湾工程师","晨雾护航队","静海观测员","逆风水手","海盐收藏家","浮城领航员","纸鸢舰桥","碎浪电台","晚星候潮","退潮的船坞","北岸打捞局"];
fn pick(seed:&mut u64,n:usize)->usize{*seed^=*seed<<13;*seed^=*seed>>7;*seed^=*seed<<17;(*seed % n.max(1) as u64) as usize}
pub(crate) fn catalogue()->E<Value>{let data=crate::ranked_fleets::data()?;Ok(json!({"version":VERSION,"budget":10000,"team_player_budget":3400,"max_groups":4,"ships":data.ships.iter().map(|s|json!({"id":s.id,"name":s.name,"kind":s.kind,"points":crate::ranked_fleets::ship_points(s)})).collect::<Vec<_>>(),"bot_ids":BOTS}))}
fn definitions(data:&Data,groups:&[Group],budget:u32)->E<Vec<Vec<usize>>>{
    if !(1..=4).contains(&groups.len()){return Err("请选择1至4个竞技编队".into());}
    let mut ids=BTreeSet::new();let mut group_ids=BTreeSet::new();let mut points=0;
    let result=groups.iter().map(|g|{
        if g.id.is_empty()||!group_ids.insert(&g.id)||g.name.is_empty()||g.name.chars().count()>40||g.ships.is_empty()||g.ships.len()>16{return Err("竞技编队名称、身份或数量无效".into());}
        g.ships.iter().map(|id|{
            if !ids.insert(id){return Err("同一舰娘不能重复部署".into());}
            let def=data.ships.iter().position(|s|s.id==*id).ok_or("未找到竞技舰卡")?;
            points+=crate::ranked_fleets::ship_points(&data.ships[def]);Ok(def)
        }).collect::<E<Vec<_>>>()
    }).collect::<E<Vec<_>>>()?;
    if points>budget{return Err(format!("竞技编成{points}分，超过{budget}分预算"));}if ids.len()>32{return Err("单席最多部署32艘".into());}Ok(result)
}
fn bot_roster(data:&Data,seed:&mut u64,budget:u32,used:&mut BTreeSet<usize>)->Vec<usize>{
    let mut pool:Vec<_>=data.ships.iter().enumerate().filter(|(i,s)|!used.contains(i)&&crate::ranked_fleets::ship_points(s)<=budget).map(|(i,_)|i).collect();
    let mut result=vec![];let mut remaining=budget;
    while !pool.is_empty()&&result.len()<12 {let index=pick(seed,pool.len());let def=pool.swap_remove(index);let cost=crate::ranked_fleets::ship_points(&data.ships[def]);if cost<=remaining {remaining-=cost;used.insert(def);result.push(def);} }
    result
}
impl World {
    pub(crate) fn new_arena(start:Start)->E<Self>{
        if start.arena_version!=VERSION||!matches!(start.mode.as_str(),"ranked"|"team3"){return Err("竞技模式或版本无效".into());}
        let data=crate::ranked_fleets::data()?;let player=definitions(data,&start.groups,if start.mode=="team3"{3400}else{10000})?;
        let mut random=start.seed as u64^0x4af12b9cc6386a2d;
        let mut deployments:Vec<(usize,String,Vec<usize>,bool)>=start.groups.iter().zip(player).map(|(g,defs)|(0,g.name.clone(),defs,false)).collect();
        let mut own_used=deployments.iter().flat_map(|(_,_,v,_)|v.iter().copied()).collect();
        if start.mode=="team3"{for _ in 0..2 {let name=BOTS[pick(&mut random,BOTS.len())].to_owned();let defs=bot_roster(data,&mut random,3300,&mut own_used);deployments.push((0,name,defs,true));}}
        let mut enemy_used=BTreeSet::new();let groups=if start.mode=="team3"{3}else{2+pick(&mut random,3)};
        for slot in 0..groups{let name=BOTS[pick(&mut random,BOTS.len())].to_owned();let budget=10000/groups as u32+if slot==0{10000%groups as u32}else{0};let defs=bot_roster(data,&mut random,budget,&mut enemy_used);deployments.push((1,name,defs,true));}
        if deployments.iter().any(|(_,_,defs,_)|defs.is_empty()){return Err("人机阵容无法在预算内生成".into());}
        let mut w=Self::blank(data,start.seed,0,"coord",VARIANT,"coord",0);w.arena=Some(start);w.field=Field{width:48000.,height:36000.,limit:900};
        let mut slots=[0usize;2];
        for (owner,name,defs,bot) in deployments {
            let id=w.fleets.len() as u32+1;let slot=slots[owner];slots[owner]+=1;
            let heading=if owner==0{90.}else{270.};let x=if owner==0{13000.}else{35000.};let y=3800.+slot as f64*5200.;let mut members=vec![];
            for (i,def) in defs.into_iter().enumerate(){let pos=P{x,y}+P::bearing(heading)*(-(i as f64)*450.);members.push(w.spawn(def,owner,id,data.ships[def].name.clone(),pos,heading)?);}
            w.fleets.push(Fleet{id,side:owner,name,leader:members[0],members,mode:"follow".into(),speed:26.,actual:0.,turn_degrees:0.,points:vec![],ai:Ai::new(["coord","gunnery","torpedo"][pick(&mut random,3)],if bot{"auto"}else{"manual"}),notice:None,last_ai_route:0,tactic:Tactic::Search});
        }
        w.gun_streak.resize(w.ships.len(),(0,0,0));w.surface_damage.resize(w.ships.len(),Default::default());w.init_realtime(crate::realtime::VERSION)?;w.apply_intel(crate::intel::VERSION)?;
        w.add(3,"start","本地人机竞技：十五分钟，按击沉CAS点数决胜。".into(),Some(VERSION),None);w.detect(true);w.refresh_open_intel();Ok(w)
    }
    pub(crate) fn arena_result(&mut self){
        if self.arena.is_none()||self.result.is_some(){return;}
        let wiped=|side| !self.ships.iter().any(|s|s.side==side&&s.alive());
        if !wiped(0)&&!wiped(1)&&!(self.tick>=self.field.limit&&self.shells.is_empty()){return;}
        let points=|side|self.ships.iter().filter(|s|s.side==side&&s.hp<=0.).map(|s|crate::ranked_fleets::ship_points(&self.data.ships[s.def])).sum::<u32>();
        let a=points(1);let b=points(0);let winner=if wiped(1)&&!wiped(0){"allies"}else if wiped(0)&&!wiped(1){"axis"}else if a>b{"allies"}else if b>a{"axis"}else{"draw"};
        self.result=Some(Outcome{winner:winner.into(),allies:a,axis:b,primary:None});self.add(3,"end",format!("竞技结束：击沉分数{a} : {b}"),Some(VERSION),None);
    }
}
pub(crate) fn view(w:&World)->Value{
 let start=w.arena.as_ref().unwrap();
 let player_count=start.groups.iter().map(|g|g.ships.len() as u32).sum::<u32>();
 let player_fleets:Vec<_>=w.fleets.iter().filter(|f|f.side==0&&f.members.iter().all(|id|*id<=player_count)).map(|f|f.id).collect();
 let groups:Vec<_>=w.fleets.iter().map(|f|{let bot=f.side==1||!player_fleets.contains(&f.id);json!({"fleet":f.id,"id":format!("arena-fleet-{}",f.id),"side":side_name(f.side),"name":f.name,"bot":bot,"bot_id":if bot{format!("BOT-{:08}-{:02}",start.seed,f.id)}else{String::new()},"points":f.members.iter().map(|id|w.ship(*id).map(|s|crate::ranked_fleets::ship_points(&w.data.ships[s.def])).unwrap_or(0)).sum::<u32>(),"ships":f.members.iter().filter_map(|id|w.ship(*id)).map(|s|json!({"id":s.character,"ship":s.id,"name":s.name,"points":crate::ranked_fleets::ship_points(&w.data.ships[s.def])})).collect::<Vec<_>>()})}).collect();
 let roster:Vec<_>=w.ships.iter().map(|s|json!({"ship":s.id,"character_id":s.character,"side":side_name(s.side),"fleet":s.fleet,"name":s.name,"points":crate::ranked_fleets::ship_points(&w.data.ships[s.def])})).collect();
 json!({"version":VERSION,"mode":start.mode,"seed":start.seed,"match_id":format!("local-{}-{}",start.mode,start.seed),"budget":10000,"player_budget":if start.mode=="team3"{3400}else{10000},"player_fleets":player_fleets,"groups":groups,"seats":groups,"roster":roster,"scoring":"sunk-cas-points","result":w.result,"finish_reason":if w.result.is_none(){Value::Null}else{json!(if w.ships.iter().filter(|s|s.side==0).all(|s|!s.alive())||w.ships.iter().filter(|s|s.side==1).all(|s|!s.alive()){"annihilation"}else{"time_limit"})}})
}
#[cfg(test)]mod tests{
 use super::*;
 fn request(mode:&str,seed:u32)->Value{json!({"op":"new_arena","arena_version":VERSION,"seed":seed,"mode":mode,"groups":[{"id":"g1","name":"初航驱逐编队","ships":["IBS-U-USN-FLETCHER","IBS-U-USN-PERKINS","IBS-U-USN-MAURY"]}]})}
 #[test]fn arena_random_rosters_stay_in_budget_and_replay_true_battles(){
  for mode in ["ranked","team3"] {let mut engine=crate::Engine::default();let r=engine.handle(request(mode,42));assert!(r["ok"]==true,"{r}");let view=&r["data"];
   assert_eq!(view["variant"],VARIANT);assert_eq!(view["realtimeVersion"].as_str().unwrap_or(crate::realtime::VERSION),crate::realtime::VERSION);
   let groups=view["arena"]["groups"].as_array().unwrap();let enemies=groups.iter().filter(|f|f["side"]=="axis").count();if mode=="team3"{assert_eq!(enemies,3);assert_eq!(groups.iter().filter(|f|f["side"]=="allies"&&f["bot"]==true).count(),2);}
   for side in ["allies","axis"]{assert!(groups.iter().filter(|f|f["side"]==side).map(|f|f["points"].as_u64().unwrap()).sum::<u64>()<=10000);}
   let moved=engine.handle(json!({"op":"step","seconds":40}));let saved=engine.handle(json!({"op":"save"}))["data"].clone();assert_eq!(engine.handle(json!({"op":"load","save":saved})),moved);assert_eq!(engine.handle(json!({"op":"replay","save":saved})),moved);
   let r=engine.handle(json!({"op":"ai","fleet":1,"profile":"coord","mode":"auto","move":true,"gun":true,"torpedo":true}));assert_eq!(r["ok"],true);
   let done=engine.handle(json!({"op":"step","seconds":1200}));assert!(done["data"]["result"].is_object(),"{done}");assert!(done["data"]["arena"]["finish_reason"].is_string());assert_eq!(done["data"]["arena"]["result"],done["data"]["result"]);
   let saved=engine.handle(json!({"op":"save"}))["data"].clone();assert_eq!(engine.handle(json!({"op":"load","save":saved})),done);
  }
 }
 #[test]fn arena_rejects_invalid_lineups_atomically(){let mut e=crate::Engine::default();assert_eq!(e.handle(request("ranked",3))["ok"],true);let previous=e.handle(json!({"op":"observe"}));let mut wrong=request("ranked",4);wrong["groups"][0]["ships"]=json!(["IBS-U-USN-FLETCHER","IBS-U-USN-FLETCHER"]);assert_eq!(e.handle(wrong)["ok"],false);assert_eq!(e.handle(json!({"op":"observe"})),previous);let mut wrong=request("team3",4);wrong["groups"]=json!([]);assert_eq!(e.handle(wrong)["ok"],false);assert_eq!(e.handle(json!({"op":"observe"})),previous);}
 #[test]fn all_catalogue_ships_have_actual_usable_arena_cards(){let catalogue=catalogue().unwrap();for row in catalogue["ships"].as_array().unwrap(){let mut q=request("ranked",1);q["groups"][0]["ships"]=json!([row["id"]]);let mut e=crate::Engine::default();assert_eq!(e.handle(q)["ok"],true,"{}",row["id"]);}}
 #[test]fn teammates_are_independent_bots_and_player_detach_remains_commandable(){let mut e=crate::Engine::default();assert_eq!(e.handle(request("team3",42))["ok"],true);let original=e.handle(json!({"op":"save"}));for q in [json!({"op":"speed","fleet":2,"speed":0}),json!({"op":"ai","fleet":2,"profile":"coord","mode":"manual","move":false,"gun":false,"torpedo":false}),json!({"op":"detach","fleet":2,"ship":4}),json!({"op":"fire","ship":4,"weapon":"gun","target":"C01"})]{assert_eq!(e.handle(q)["ok"],false);assert_eq!(e.handle(json!({"op":"save"})),original);}assert_eq!(e.handle(json!({"op":"detach","fleet":1,"ship":3}))["ok"],true);assert_eq!(e.handle(json!({"op":"speed","fleet":7,"speed":10}))["ok"],true);}
}
