//! Fictional cargo decisions. Never consumed by historical or frozen v1-v3 voyages.
use crate::{model::*,salvage::Start,world::World};
use serde::{Deserialize,Serialize};
use serde_json::{json,Value};
use std::collections::BTreeMap;
pub const VERSION:&str="salvage-v4";
#[derive(Clone,Debug,Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub struct Config {pub commander_level:u32,pub difficulty:String,pub environment:String,pub weather:String,#[serde(default)]pub loadouts:BTreeMap<String,Loadout>}
#[derive(Clone,Debug,Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub struct Loadout {pub torpedoes:bool}
#[derive(Clone,Debug,Deserialize,Serialize)]
pub struct Item {pub id:String,pub kind:String,pub name:String,pub shape:Vec<[u32;2]>,pub kg:u32,pub value:u32,pub ruin:u32,pub placement:Option<[u32;3]>,#[serde(default,skip_serializing_if="String::is_empty")]pub loot_id:String}
#[derive(Clone,Debug)]
pub struct Search {ruin:u32,progress:u32,hp:f64}
#[derive(Clone,Debug)]
pub struct Grid {pub cols:u32,pub rows:u32,pub usable_cells:u32,pub max_kg:u32,pub ships:Vec<Value>,pub items:Vec<Item>,pub search:Option<Search>,pub completed:Vec<u32>,pub revealed:BTreeMap<u32,u32>}
pub fn validate(start:&Start)->E<()> {
    if start.content!=VERSION {if start.cargo_v4.is_some(){return Err("旧版本不能添加新货舱配置".into());}return Ok(());}
    let c=start.cargo_v4.as_ref().ok_or("新货舱需要完整版本配置")?;
    if !(1..=20).contains(&c.commander_level)||!["calm","standard","hazard"].contains(&c.difficulty.as_str())||!["atoll","fractured","fjord","drowned_city"].contains(&c.environment.as_str())||!["auto","clear","rain","fog"].contains(&c.weather.as_str())||start.mission.as_ref().is_none_or(|m|m.kind!="salvage"&&!(m.kind=="chapter"&&crate::story_missions::active(start))) {return Err("货舱、难度、海域或天气配置无效".into());}
    if start.fleet.iter().any(|h|h.ammo<20)||c.loadouts.keys().any(|id|!start.fleet.iter().any(|h|&h.id==id)){return Err("至少装载20%炮弹，装载身份须属于本航次".into());}Ok(())
}
#[cfg(test)]
mod tests {
 use super::*;use crate::salvage::Hull;use crate::Engine;
 fn start()->Start{serde_json::from_value(json!({"content":VERSION,"fleet":[{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":50,"level":0}],"mission":{"kind":"salvage","id":"calm","loot_kind":"scrap"},"cargo_v4":{"commander_level":1,"difficulty":"calm","environment":"atoll","weather":"clear","loadouts":{"IBS-U-USN-FLETCHER":{"torpedoes":false}}}})).unwrap()}
 fn ready()->World{let mut w=World::new_salvage(40,start()).unwrap();let p=w.salvage.as_ref().unwrap().ruins[0].p;let ship=w.ship_mut(1).unwrap();ship.p=p;ship.speed=0.;w}
 #[test] fn capacity_and_real_loadout(){
  let w=ready();let s=w.ship(1).unwrap();assert_eq!(s.ammo,0);assert!(s.torp_mount_remaining.iter().all(|&n|n==0));assert!(s.torp_reserve.iter().all(|&n|n==0));
  let b=w.salvage.as_ref().unwrap();assert_eq!(b.grid.as_ref().unwrap().max_kg,26*55);assert_eq!(b.grid.as_ref().unwrap().ships[0]["tonnage_status"],"source_registered");
  let mut heavier=start();heavier.cargo_v4.as_mut().unwrap().commander_level=5;assert!(budget(&heavier,w.data).max_kg>b.grid.as_ref().unwrap().max_kg);
  let mut full=start();full.fleet[0].ammo=100;full.cargo_v4.as_mut().unwrap().loadouts.clear();assert_eq!(budget(&full,w.data).max_kg+6*55,b.grid.as_ref().unwrap().max_kg);
  let mut transport=start();transport.fleet=vec![Hull{id:"IBS-U-IJN-MONCHIZUKI".into(),hp:100,ammo:100,level:0,..Default::default()}];transport.cargo_v4.as_mut().unwrap().loadouts.clear();let g=budget(&transport,w.data);assert_eq!(g.ships[0]["transport"],true);assert!(g.max_kg>budget(&full,w.data).max_kg);
 }
 #[test] fn search_grid_atomicity_rotation_and_discard(){
  let mut w=ready();let cmd=json!({"op":"search_salvage","ruin":1});w.external(cmd.clone()).unwrap();
  for _ in 0..7{w.advance_cargo_v4();}assert_eq!(w.salvage.as_ref().unwrap().grid.as_ref().unwrap().items.len(),3);
  w.external(cmd.clone()).unwrap();w.advance_cargo_v4();assert_eq!(w.salvage.as_ref().unwrap().grid.as_ref().unwrap().items.len(),4);assert!(w.salvage.as_ref().unwrap().cargo.is_empty());assert!(w.external(cmd).is_err());
  let place=|id:&str,x,y,r|json!({"op":"cargo_place","item":id,"x":x,"y":y,"rotation":r});
  w.external(place("v4-1-0",0,0,0)).unwrap();let prior=w.observation(0)["salvage"].clone();
  assert!(w.external(place("v4-1-1",0,0,0)).is_err());assert_eq!(prior,w.observation(0)["salvage"]);
  assert!(w.external(place("v4-1-0",8,0,0)).is_err());assert!(w.external(place("v4-1-0",0,0,4)).is_err());
  w.external(place("v4-1-0",7,0,1)).unwrap();w.external(json!({"op":"cargo_sort"})).unwrap();assert_eq!(w.salvage.as_ref().unwrap().cargo.len(),1);
  w.external(json!({"op":"cargo_drop","item":"v4-1-0"})).unwrap();assert!(w.salvage.as_ref().unwrap().cargo.is_empty());assert!(w.external(place("v4-1-0",0,0,0)).is_err());
 }
 #[test] fn search_cancel_and_damage_no_fabricated_loot(){let mut w=ready();w.external(json!({"op":"search_salvage","ruin":1})).unwrap();w.advance_cargo_v4();w.external(json!({"op":"cancel_search"})).unwrap();for _ in 0..12{w.advance_cargo_v4();}assert!(w.salvage.as_ref().unwrap().grid.as_ref().unwrap().items.is_empty());w.external(json!({"op":"search_salvage","ruin":1})).unwrap();w.ship_mut(1).unwrap().hp-=1.;w.advance_cargo_v4();assert!(w.salvage.as_ref().unwrap().grid.as_ref().unwrap().search.is_none());}
 #[test] fn version_and_config_validation(){let mut s=start();s.content="salvage-v3".into();assert!(validate(&s).is_err());s.cargo_v4=None;assert!(validate(&s).is_ok());s.content=VERSION.into();assert!(validate(&s).is_err());}
 #[test] fn engine_replay_search_in_progress(){let mut e=Engine::default();let q=|e:&mut Engine,v:Value|{let r=e.handle(v);assert_eq!(r["ok"],true,"{r}");r["data"].clone()};q(&mut e,json!({"op":"new_salvage","seed":40,"start":start()}));let state=q(&mut e,json!({"op":"save"}));let before=q(&mut e,json!({"op":"step","seconds":2}));let saved=q(&mut e,json!({"op":"save"}));assert_eq!(q(&mut e,json!({"op":"load","save":saved.clone()})),before);assert_eq!(q(&mut e,json!({"op":"replay","save":saved})),before);assert!(state["salvage"]["cargo_v4"].is_object());}
}
fn registry()->Value {serde_json::from_str(include_str!("../data/salvage/cargo-tonnage-v1.json")).unwrap()}
pub fn budget(start:&Start,data:&Data)->Grid {
    let c=start.cargo_v4.as_ref().unwrap();let registry=registry();let mut cells=16+c.commander_level*2;let mut ships=vec![];
    for h in &start.fleet {
        let d=data.ships.iter().find(|d|d.id==h.id).unwrap();let record=&registry["ships"][&h.id];
        let verified=record["tons"].as_u64();let tons=verified.unwrap_or(match d.kind.as_str(){"BB"|"BC"=>30000,"CA"=>10000,"CL"=>6500,"CV"=>20000,"APD"=>1400,_=>2000}) as u32;
        let transport=["APD","AP","AK","AO","AE"].contains(&d.kind.as_str())||record["cargo_role"]=="transport";
        let light=(100-h.ammo)/25;let unarmed=c.loadouts.get(&h.id).is_some_and(|l|!l.torpedoes)&&d.torpedo.is_some();
        let share=((tons as f64/1000.).sqrt().floor() as u32*2).max(2)+if transport{12}else{0}+light+if unarmed{4}else{0};cells+=share;
        let reserve_cost=if [crate::expedition::VERSION,crate::amphibious_expedition::VERSION].contains(&start.gameplay_profile.as_str())&&!unarmed&&d.torpedo.is_some(){start.expedition_v2.as_ref().and_then(|e|e.munitions.get(&h.id)).cloned().unwrap_or_default().reserve_reloads*2}else{0};cells=cells.saturating_sub(reserve_cost);
        let mut row=json!({"id":h.id,"kind":d.kind,"tons":tons,"tonnage_status":if verified.is_some(){"source_registered"}else{"fictional_budget_fallback"},"source":record["source"],"cells":share,"transport":transport,"ammo":h.ammo,"torpedoes":!unarmed});
        if [crate::expedition::VERSION,crate::amphibious_expedition::VERSION].contains(&start.gameplay_profile.as_str()){row["reserve_cells"]=json!(reserve_cost);}ships.push(row);
    }
    let cols=8;let rows=cells.div_ceil(cols);let usable_cells=if [crate::expedition::VERSION,crate::amphibious_expedition::VERSION].contains(&start.gameplay_profile.as_str()){cells}else{cols*rows};Grid{cols,rows,usable_cells,max_kg:cells*55,ships,items:vec![],search:None,completed:vec![],revealed:BTreeMap::new()}
}
fn cells(item:&Item,p:[u32;3])->Vec<[u32;2]>{
    let max_x=item.shape.iter().map(|p|p[0]).max().unwrap_or(0);let max_y=item.shape.iter().map(|p|p[1]).max().unwrap_or(0);
    item.shape.iter().map(|q|{let[x,y]=match p[2]%4{0=>*q,1=>[max_y-q[1],q[0]],2=>[max_x-q[0],max_y-q[1]],_=>[q[1],max_x-q[0]]};[p[0]+x,p[1]+y]}).collect()
}
fn fits(g:&Grid,index:usize,p:[u32;3])->bool {
    let item=&g.items[index];let target=cells(item,p);if p[2]>3||target.iter().any(|p|p[0]>=g.cols||p[1]>=g.rows||p[1]*g.cols+p[0]>=g.usable_cells){return false;}
    let weight:u32=g.items.iter().enumerate().filter(|(i,it)|*i!=index&&it.placement.is_some()).map(|(_,it)|it.kg).sum();
    if weight+item.kg>g.max_kg{return false;}
    !g.items.iter().enumerate().filter(|(i,_)|*i!=index).any(|(_,it)|it.placement.is_some_and(|p|cells(it,p).iter().any(|q|target.contains(q))))
}
fn sync(w:&mut World){let b=w.salvage.as_mut().unwrap();b.cargo=b.grid.as_ref().unwrap().items.iter().filter(|i|i.placement.is_some()).map(|i|i.kind.clone()).collect();}
impl World {
 pub(crate) fn init_cargo_v4(&mut self)->E<()> {
    let start=self.salvage.as_ref().unwrap().start.clone();let c=start.cargo_v4.as_ref().unwrap();let grid=budget(&start,self.data);
    for ship in &mut self.ships {if ship.side==0&&ship.character.as_ref().is_some_and(|id|c.loadouts.get(id).is_some_and(|l|!l.torpedoes)){ship.ammo=0;ship.torp_mount_remaining.fill(0);ship.torp_reserve.fill(0);}}
    let first=self.ships.iter().find(|s|s.side==0).unwrap().p;let dx=match c.difficulty.as_str(){"calm"=>750.,"standard"=>1000.,_=>1450.};
    let b=self.salvage.as_mut().unwrap();b.capacity=grid.usable_cells as usize;b.grid=Some(grid);b.search_duration=match c.difficulty.as_str(){"calm"=>8,"standard"=>12,_=>16};
    b.ruins[0].p=P{x:first.x+dx,y:first.y};b.ruins[0].amount=match c.difficulty.as_str(){"calm"=>4,"standard"=>5,_=>6};
    b.exits[0]=b.ruins[0].p;b.west_bounds=Some([first.x-500.,first.y-600.,first.x+dx+650.,first.y+600.]);
    if c.weather!="auto"{b.weather=Some(crate::salvage_weather::Timeline::authored(self.seed,&c.weather));}
    self.init_transferred_cargo()?;
    Ok(())
 }
 fn init_transferred_cargo(&mut self)->E<()>{let imported=self.salvage.as_ref().unwrap().start.cargo_transfer_v1.as_ref().map(|c|c.items.clone()).unwrap_or_default();let g=self.salvage.as_mut().unwrap().grid.as_mut().unwrap();for mut item in imported{let p=item.placement.take().unwrap();g.items.push(item);let i=g.items.len()-1;if !fits(g,i,p){return Err("带入货物超出可用货舱、载重或格位重叠".into());}g.items[i].placement=Some(p);}sync(self);Ok(())}
 pub(crate) fn cargo_command(&mut self,r:&Value)->E<()> {
    if self.variant!=VERSION{return Err("此操作仅支持新版货舱".into());}
    let op=r["op"].as_str().unwrap_or("");
    if ["search_salvage","salvage_collect"].contains(&op){
        let id=crate::world::u(r,"ruin")?;let b=self.salvage.as_ref().unwrap();let n=b.ruins.iter().find(|n|n.id==id&&n.found).ok_or("尚未发现这处遗迹")?;
        if b.grid.as_ref().unwrap().completed.contains(&id){return Err("此遗迹已搜索，请在货舱查看已发现物资".into());}
        if !self.ships.iter().any(|s|s.side==0&&s.alive()&&s.p.dist(n.p)<750.&&s.speed<=8.){return Err("请进入遗迹750米范围，航速降至8节以下".into());}
        let hp=self.ships.iter().filter(|s|s.side==0&&s.alive()).map(|s|s.hp).sum();let b=self.salvage.as_mut().unwrap();b.extracting=None;
        if !b.grid.as_ref().unwrap().search.as_ref().is_some_and(|s|s.ruin==id){b.grid.as_mut().unwrap().search=Some(Search{ruin:id,progress:0,hp});}return Ok(());
    }
    if ["cancel_search","salvage_cancel"].contains(&op){let b=self.salvage.as_mut().unwrap();b.grid.as_mut().unwrap().search=None;b.extracting=None;return Ok(());}
    if op=="cargo_place" {
        let b=self.salvage.as_ref().unwrap();let it=b.grid.as_ref().unwrap().items.iter().find(|it|Some(it.id.as_str())==r["item"].as_str()).ok_or("找不到该物资")?;
        if it.placement.is_none(){let p=b.ruins.iter().find(|n|n.id==it.ruin).unwrap().p;if !self.ships.iter().any(|s|s.side==0&&s.alive()&&s.p.dist(p)<750.&&s.speed<=8.){return Err("返回遗迹旁才能装载未入舱物资".into());}}
    }
    let b=self.salvage.as_mut().unwrap();let g=b.grid.as_mut().unwrap();let mut feedback="cargo_repacked";
    if op=="cargo_sort" {
        let before=g.items.clone();let selected:Vec<_>=g.items.iter().enumerate().filter(|(_,i)|i.placement.is_some()).map(|(i,_)|i).collect();
        for &i in &selected{g.items[i].placement=None;}
        let mut order=selected;order.sort_by_key(|&i|std::cmp::Reverse(g.items[i].shape.len()));
        for i in order {let mut found=None;'scan:for y in 0..g.rows{for x in 0..g.cols{for rot in 0..4{let p=[x,y,rot];if fits(g,i,p){found=Some(p);break 'scan;}}}}if let Some(p)=found{g.items[i].placement=Some(p);}else{g.items=before;return Err("未找到更紧凑排布；原货舱已保留".into());}}
    }else {
        let id=r["item"].as_str().ok_or("请选择一件物资")?;let i=g.items.iter().position(|it|it.id==id).ok_or("找不到该物资")?;
        if op=="cargo_place" {let p=[crate::world::u(r,"x")?,crate::world::u(r,"y")?,crate::world::u(r,"rotation")?];if !fits(g,i,p){return Err("无法装入：检查形状、重叠、边界和载重".into());}feedback=if g.items[i].placement.is_some(){"cargo_repacked"}else{"cargo_stowed"};g.items[i].placement=Some(p);}
        else if ["cargo_drop","salvage_drop"].contains(&op){g.items.remove(i);feedback="cargo_dropped";}
        else{return Err("不支持的货舱命令".into());}
    }
    sync(self);self.add(1,feedback,"货舱安排已更新".into(),Some("CAS-SALVAGE-01"),None);Ok(())
 }
 pub(crate) fn advance_cargo_v4(&mut self){
    if self.result.is_some(){return;}let b=self.salvage.as_ref().unwrap();let Some(search)=b.grid.as_ref().unwrap().search.clone() else{return;};
    let n=b.ruins.iter().find(|n|n.id==search.ruin).unwrap();let alive:Vec<_>=self.ships.iter().filter(|s|s.side==0&&s.alive()).collect();
    let valid=alive.iter().any(|s|s.p.dist(n.p)<750.&&s.speed<=8.)&&alive.iter().map(|s|s.hp).sum::<f64>()+0.001>=search.hp;
    let expedition=self.expedition_v2();let b=self.salvage.as_mut().unwrap();let g=b.grid.as_mut().unwrap();if !valid {g.search=None;return;}
    let next=search.progress+1;g.search.as_mut().unwrap().progress=next;
    let n=b.ruins.iter_mut().find(|n|n.id==search.ruin).unwrap();let count=match b.start.cargo_v4.as_ref().unwrap().difficulty.as_str(){"calm"=>4,"standard"=>5,_=>6};
    let factor=match count{4=>10,5=>14,_=>19};
    let previous=*g.revealed.get(&n.id).unwrap_or(&0);let now=(next*count/b.search_duration).min(count);
    for k in previous..now {if expedition{let mut item=crate::expedition::loot_item(self.seed,n.id,k,&b.start.cargo_v4.as_ref().unwrap().difficulty);if let Some(c)=&b.start.cargo_transfer_v1{item.id=format!("{}/{}",c.pickup_namespace,item.id);}g.items.push(item);continue;}let kind=if k==0{n.kind.as_str()}else{["scrap","alloy","equipment","command"][(self.seed as usize+n.id as usize+k as usize)%4]};
        let(shape,name,kg,value)=match kind{"archive" if crate::story_missions::active(&b.start)=>(vec![[0,0],[1,0],[0,1]],"密封档案匣",20,0),"alloy"=>(vec![[0,0],[1,0],[0,1],[1,1]],"旧世合金",120,220),"equipment"=>(vec![[0,0],[0,1],[1,1]],"封存舰装",90,360),"command"=>(vec![[0,0],[1,0],[2,0]],"航海手册",35,300),_=>(vec![[0,0],[1,0]],"可用零件",55,100)};
        g.items.push(Item{id:format!("v4-{}-{}",n.id,k),kind:kind.into(),name:name.into(),shape,kg,value:value*factor/10,ruin:n.id,placement:None,loot_id:String::new()});
    }
    if now>previous{g.revealed.insert(n.id,now);}
    let p=n.p;
    let complete=next>=b.search_duration;
    if complete{g.completed.push(n.id);n.collected=true;n.amount=0;g.search=None;}
    if now>previous{self.add(1,"cargo_revealed",format!("搜索发现物资 {now}/{count}，可在货舱安排装载"),Some("CAS-SALVAGE-01"),Some(p));}
    if complete{self.add(1,"cargo_search_complete",format!("搜索完成，共发现{count}件物资"),Some("CAS-SALVAGE-01"),Some(p));}
 }
 pub(crate) fn cargo_view(&self,view:&mut Value){
    let b=self.salvage.as_ref().unwrap();let g=b.grid.as_ref().unwrap();let c=b.start.cargo_v4.as_ref().unwrap();
    view["salvage"]["generatorVersion"]=json!(if self.adventure(){"archipelago-adventure-1"}else{"archipelago-4"});view["salvage"]["difficulty"]=json!(c.difficulty);view["salvage"]["environment"]=json!(c.environment);
    view["salvage"]["search"]=g.search.as_ref().map_or(Value::Null,|s|json!({"ruin":s.ruin,"progress":s.progress,"duration":b.search_duration,"revealed":g.revealed.get(&s.ruin).unwrap_or(&0)}));
    view["salvage"]["cargo_grid"]=json!({"cols":g.cols,"rows":g.rows,"max_kg":g.max_kg,"kg":g.items.iter().filter(|i|i.placement.is_some()).map(|i|i.kg).sum::<u32>(),"items":g.items,"ships":g.ships,"completed":g.completed,"commander_level":c.commander_level});
    if self.expedition_v2(){view["salvage"]["cargo_grid"]["usable_cells"]=json!(g.usable_cells);}
 }
}

