//! New, opt-in extraction fiction. No historical ShipDef or old profile is edited.
use crate::{model::*,salvage::{self,Start,Ruin,EnemyTask},world::{World,roll}};
use serde::{Serialize,Deserialize};
use serde_json::{Value,json};
use std::{collections::BTreeMap,sync::OnceLock};
pub const VERSION:&str="cas-adventure-v2";
pub const SCENES:[&str;5]=["sunken_metropolis","cult_relay","storm_wrecks","thermal_vent","refugee_causeway"];
#[derive(Clone,Debug,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config{pub scene:String,#[serde(default)]pub munitions:BTreeMap<String,Munitions>}
fn one()->u32{1}
#[derive(Clone,Debug,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Munitions{pub shell:String,pub torpedo:String,#[serde(default="one")]pub reserve_reloads:u32}
impl Default for Munitions{fn default()->Self{Self{shell:"balanced".into(),torpedo:"standard".into(),reserve_reloads:1}}}
#[derive(Clone,Debug,Serialize)]
pub struct Task{pub id:String,pub kind:String,pub title:String,pub x:f64,pub y:f64,pub radius:u32,pub status:String,pub progress:u32,pub duration:u32,pub effect:String,pub reward_ruin_id:Option<u32>}
#[derive(Clone,Debug)]
pub struct Run{pub config:Config,pub tasks:Vec<Task>,working:Option<(usize,f64)>,pub pressure:u32,base_pressure:i32,pub boss_status:String,pub announce_tick:Option<u32>,pub spawn_tick:Option<u32>,pub boss_ship:Option<u32>,pub boss_p:P,pub naval_budget:u32,pub naval_spent:u32,pub naval_hulls:u32,pub creature_hulls:u32,pub extraction_reduction:u32,pub autopilot:crate::extraction_ai::AutoPilot,defeated:Vec<(usize,u32,Value)>}
#[derive(Clone,Debug,Deserialize)]
pub struct Loot{pub id:String,pub kind:String,pub name:String,pub shape:Vec<[u32;2]>,pub kg:u32,pub value:u32,pub r#use:String}
pub fn loot()->&'static Vec<Loot>{static V:OnceLock<Vec<Loot>>=OnceLock::new();V.get_or_init(||serde_json::from_value(serde_json::from_str::<Value>(include_str!("../data/salvage/loot-v2.json")).unwrap()["items"].clone()).unwrap())}
pub fn loot_item(seed:u32,ruin:u32,k:u32,risk:&str)->crate::salvage_v4::Item {
    let index=if ruin==2000&&k==0{11}else if ruin>=1000&&k==0{13}else if ruin>=1000{10+((seed+ruin+k)%6) as usize}else{((seed.wrapping_mul(7)+ruin*11+k*5)%16) as usize};let row=&loot()[index];
    let factor=match risk{"calm"=>10,"standard"=>14,_=>19};
    crate::salvage_v4::Item{id:format!("v2-{ruin}-{k}"),kind:row.kind.clone(),name:row.name.clone(),shape:row.shape.clone(),kg:row.kg,value:row.value*factor/10,ruin,placement:None,loot_id:row.id.clone()}
}
pub(crate) fn validate(s:&Start)->E<()> {
    if s.content!=crate::salvage_v4::VERSION||s.mission.as_ref().is_none_or(|m|m.kind!="salvage"){return Err("远征v2只支持新搜打撤".into());}
    let c=s.expedition_v2.as_ref().ok_or("远征v2缺少配置")?;
    if !SCENES.contains(&c.scene.as_str())||c.munitions.keys().any(|id|!s.fleet.iter().any(|h|&h.id==id))
        ||c.munitions.values().any(|m|!["balanced","ap","he"].contains(&m.shell.as_str())||!["standard","fast","heavy"].contains(&m.torpedo.as_str())||m.reserve_reloads>2){return Err("远征场景、弹种、备雷或编队身份无效".into());}
    Ok(())
}
impl World {
    pub(crate) fn expedition_v2(&self)->bool{self.salvage.as_ref().is_some_and(|b|[VERSION,crate::amphibious_expedition::VERSION].contains(&b.start.gameplay_profile.as_str()))}
    pub(crate) fn expedition_munitions(&self,s:&Ship)->Munitions{self.expedition.as_ref().and_then(|e|s.character.as_ref().and_then(|id|e.config.munitions.get(id))).cloned().unwrap_or_default()}
    pub(crate) fn expedition_torp_factors(&self,s:&Ship)->(f64,f64,f64,u32){if !self.expedition_v2(){return (1.,1.,1.,0);}match self.expedition_munitions(s).torpedo.as_str(){"fast"=>(1.4,0.70,0.80,20),"heavy"=>(0.8,0.85,1.35,30),_=>(1.,1.,1.,20)}}
    pub(crate) fn expedition_shell_factor(&self,s:&Ship,target:&Ship)->f64{
        if !self.expedition_v2()||s.side!=0{return 1.;}let d=&self.data.ships[target.def];let armored=d.armor_belt>0.||d.id=="CAS-FICTION-rust_crab";
        match (self.expedition_munitions(s).shell.as_str(),armored){("he",false)=>1.3,("he",true)=>0.65,("ap",true)=>1.35,("ap",false)=>0.8,_=>1.}
    }
    fn expedition_water(&self,base:P,clearance:f64,occupied:&[P])->E<P>{
        (0..35).flat_map(|r|(0..16).map(move|a|base+P::bearing(a as f64*22.5)*(r as f64*180.)))
        .find(|p|self.field.contains(*p)&&occupied.iter().all(|q|q.dist(*p)>400.)&&!self.islands.iter().any(|poly|salvage::polygon_near(poly,*p,clearance))).ok_or("远征落点缺少安全水域".into())
    }
    pub(crate) fn init_expedition(&mut self)->E<()> {
        let b=self.salvage.as_ref().unwrap();let config=b.start.expedition_v2.clone().unwrap();let risk=b.start.cargo_v4.as_ref().unwrap().difficulty.clone();
        let points:Value=serde_json::from_str(include_str!("../data/rules/cas-competitive-points-v1.json")).unwrap();
        let deployed:u32=b.start.fleet.iter().map(|h|points["ships"][&h.id]["points"].as_u64().unwrap_or(0) as u32).sum();
        let budget=((deployed*match risk.as_str(){"calm"=>65,"standard"=>100,_=>135}/100)/25*25).clamp(275,30000);
        let mut tasks=vec![];let mut rng=u64::from(self.seed)^0xba47_1395_2cad;
        let mut pool=vec!["relay","survey","rescue","beacon","cache"];
        for i in 0..3 {
            let preferred=match config.scene.as_str(){"cult_relay"=>"relay","storm_wrecks"=>"beacon","thermal_vent"=>"survey","refugee_causeway"=>"rescue",_=>"cache"};
            let kind=pool.remove(if i==0{pool.iter().position(|kind|*kind==preferred).unwrap()}else{(roll(&mut rng,pool.len() as u32)-1) as usize});
            // Every task belongs to the generated connected shipping tree.
            // The nearby introductory site also validates its whole approach;
            // if a future topology closes that extension, retain the anchor.
            let anchor=if i==0{b.ruins[0].p}else{b.ruins[i*2+1].p};
            let candidate=if i==0{anchor+P{x:1800.,y:0.}}else{anchor};
            let steps=(anchor.dist(candidate)/80.).ceil().max(1.) as u32;
            let clear=(0..=steps).all(|j|{let p=anchor+(candidate-anchor)*(j as f64/steps as f64);self.field.contains(p)&&!self.islands.iter().any(|poly|salvage::polygon_near(poly,p,300.))});
            let p=if clear{candidate}else{anchor};
            if self.islands.iter().any(|poly|salvage::polygon_near(poly,p,300.)){return Err("远征任务不在可达安全航道".into());}
            let (title,effect,duration)=match kind{
                "relay"=>("切断拜教中继","警戒降低最多25点，未到场Boss延后60秒",10),"survey"=>("测绘旧世信号","标注附近全部遗迹，留下稀有实物箱",8),"rescue"=>("接回漂流幸存者","撤离等待缩短4秒，留下救援物资箱",12),"beacon"=>("修复引航浮标","开通此处额外撤离点",10),_=>("开启战帮密库","生成一箱封存装备与旧世物资",12)};
            tasks.push(Task{id:format!("task-{}",i+1),kind:kind.into(),title:title.into(),x:p.x,y:p.y,radius:650,status:"offered".into(),progress:0,duration,effect:effect.into(),reward_ruin_id:None});
        }
        let base_pressure=match risk.as_str(){"calm"=>15,"standard"=>30,_=>45};
        let boss_p=b.ruins[8].p;
        let mut run=Run{config,tasks,working:None,pressure:base_pressure as u32,base_pressure,boss_status:"dormant".into(),announce_tick:None,spawn_tick:None,boss_ship:None,boss_p,naval_budget:budget,naval_spent:0,naval_hulls:0,creature_hulls:b.enemy_count as u32,extraction_reduction:0,autopilot:Default::default(),defeated:vec![]};
        // Bounded deterministic budget packing. Repeated hull classes are cult
        // remote vessels, explicitly fictional rather than historical fleets.
        let mut candidates:Vec<_>=self.data.ships.iter().enumerate().filter(|(_,d)|d.id.starts_with("IBS-U-IJN-")&&["DD","CL","CA"].contains(&d.kind.as_str()))
            .filter_map(|(i,d)|points["ships"][&d.id]["points"].as_u64().filter(|&p|p>0).map(|p|(i,p as u32))).collect();
        candidates.sort_by_key(|(i,p)|(*p,self.data.ships[*i].id.clone()));
        for count in 0..12 {
            let left=budget-run.naval_spent;let affordable:Vec<_>=candidates.iter().copied().filter(|(_,p)|*p<=left).collect();if affordable.is_empty(){break;}
            let (index,cost)=affordable[(roll(&mut rng,affordable.len() as u32)-1) as usize];
            let base=if count==0{P{x:6200.+(self.field.width-24000.),y:2200.}}else{self.salvage.as_ref().unwrap().ruins[(count as usize%8)+1].p+P{x:800.,y:300.}};
            let occupied:Vec<_>=self.ships.iter().map(|s|s.p).collect();let p=self.expedition_water(base,180.,&occupied)?;
            let fleet=self.fleets.iter().map(|f|f.id).max().unwrap_or(0)+1;
            let id=self.spawn(index,1,fleet,format!("拜教遥控舰 {:02} · {}",count+1,self.data.ships[index].kind),p,270.)?;
            self.fleets.push(salvage::exploration_fleet(fleet,1,vec![id],"拜教海上巡逻",true));
            self.salvage.as_mut().unwrap().enemies.push(EnemyTask{fleet,role:count as usize%3,home:p,patrol:[p,p+P{x:-1000.,y:0.}],waypoint:1,last_contact:None,chase_started:None,returning:false});
            run.naval_spent+=cost;run.naval_hulls+=1;
        }
        self.owned_growth.resize(self.ships.len(),Default::default());self.salvage.as_mut().unwrap().practice.resize(self.ships.len(),0);
        self.salvage.as_mut().unwrap().enemy_count+=run.naval_hulls as usize;
        self.expedition=Some(run);
        let c=self.salvage.as_ref().unwrap().start.cargo_v4.as_ref().unwrap();
        if c.weather=="auto" {let kind=match self.expedition.as_ref().unwrap().config.scene.as_str(){"storm_wrecks"=>Some("rain"),"thermal_vent"=>Some("fog"),_=>None};if let Some(kind)=kind{self.salvage.as_mut().unwrap().weather=Some(crate::salvage_weather::Timeline::authored(self.seed,kind));}}
        for i in 0..self.ships.len(){if self.ships[i].side!=0{continue;}let m=self.expedition_munitions(&self.ships[i]);
            for j in 0..self.ships[i].torp_reserve.len(){self.ships[i].torp_reserve[j]=self.ships[i].torp_mount_remaining[j]*m.reserve_reloads;}
        }
        Ok(())
    }
    pub(crate) fn expedition_command(&mut self,q:&Value)->E<()> {
        if !self.expedition_v2(){return Err("此操作仅适用于远征v2".into());}
        if q["op"]=="extraction_autopilot"{return crate::extraction_ai::command(&mut self.expedition.as_mut().unwrap().autopilot,q);}
        let id=q["task"].as_str().ok_or("请选择临时任务")?;
        let index=self.expedition.as_ref().unwrap().tasks.iter().position(|t|t.id==id).ok_or("临时任务不存在")?;
        let task=&self.expedition.as_ref().unwrap().tasks[index];
        if q["op"]=="expedition_task"{let action=q["action"].as_str().ok_or("任务操作无效")?;
            if !["accept","abandon"].contains(&action){return Err("任务操作无效".into());}
            if ["complete","abandoned"].contains(&task.status.as_str()){return Err("已完成或放弃的任务不能重复领取".into());}
            if action=="accept"&&["accepted","working"].contains(&task.status.as_str()){return Ok(());}
            let run=self.expedition.as_mut().unwrap();run.tasks[index].status=if action=="accept"{"accepted"}else{"abandoned"}.into();
            if run.working.is_some_and(|(i,_)|i==index){run.working=None;}return Ok(());
        }
        if !["accepted","working"].contains(&task.status.as_str()){return Err("先接取临时任务".into());}
        if task.status=="working"{return Ok(());}
        let p=P{x:task.x,y:task.y};
        if !self.ships.iter().any(|s|s.side==0&&s.alive()&&s.p.dist(p)<650.&&s.speed<=8.){return Err("请靠近任务650米并降至8节以下".into());}
        let hp=self.ships.iter().filter(|s|s.side==0&&s.alive()).map(|s|s.hp).sum();let run=self.expedition.as_mut().unwrap();
        if let Some((old,_))=run.working.filter(|(old,_)|*old!=index){run.tasks[old].status="accepted".into();}
        run.working=Some((index,hp));run.tasks[index].status="working".into();Ok(())
    }
    pub(crate) fn advance_expedition(&mut self){
        if self.result.is_some(){return;}let mut run=self.expedition.take().unwrap();
        if let Some((i,hp))=run.working {
            let t=&mut run.tasks[i];let p=P{x:t.x,y:t.y};let total:f64=self.ships.iter().filter(|s|s.side==0&&s.alive()).map(|s|s.hp).sum();
            if total+0.001<hp||!self.ships.iter().any(|s|s.side==0&&s.alive()&&s.p.dist(p)<650.&&s.speed<=8.){t.status="accepted".into();run.working=None;}
            else{t.progress+=1;if t.progress>=t.duration{
                t.status="complete".into();run.working=None;
                let b=self.salvage.as_mut().unwrap();
                match t.kind.as_str(){"relay"=>{run.base_pressure-=25;if run.boss_status=="announced"{run.spawn_tick=run.spawn_tick.map(|tick|tick+60);}},"survey"=>for n in &mut b.ruins{if n.p.dist(p)<6500.{n.found=true;}},"rescue"=>run.extraction_reduction=4,"beacon"=>b.exits.push(p),_=>{}}
                if t.kind!="beacon"&&t.kind!="relay"{let id=1001+i as u32;b.ruins.push(Ruin{id,p,kind:if t.kind=="cache"{"equipment"}else{"command"}.into(),amount:4,found:true,collected:false});t.reward_ruin_id=Some(id);}
                self.add(1,"expedition_task_complete",format!("{}：{}",t.title,t.effect),Some("CAS-EXTRACTION-02"),Some(p));
            }}
        }
        // Completing the relay does not add the +8 noise of other tasks.
        // These exact thresholds drive real patrol pursuit in salvage.rs.
        run.pressure=(run.base_pressure+(self.tick/15) as i32+run.tasks.iter().filter(|t|t.status=="complete"&&t.kind!="relay").count() as i32*8).clamp(0,100) as u32;
        let delay=if run.tasks.iter().any(|t|t.kind=="relay"&&t.status=="complete"){60}else{0};
        let announce_at=match self.salvage.as_ref().unwrap().start.cargo_v4.as_ref().unwrap().difficulty.as_str(){"calm"=>180,"standard"=>120,_=>90}+delay;
        if run.boss_status=="dormant" && self.tick>=announce_at{
            run.boss_status="announced".into();run.announce_tick=Some(self.tick);run.spawn_tick=Some(self.tick+30);
            self.add(1,"expedition_boss_warning","拜教深海信号正在聚合；30秒后将有大型实体进入标记海域。可以立即撤离。".into(),Some("CAS-EXTRACTION-02"),Some(run.boss_p));
        }
        if run.boss_status=="announced"&&run.spawn_tick.is_some_and(|tick|self.tick>=tick){
            let occupied:Vec<_>=self.ships.iter().filter(|s|s.alive()).map(|s|s.p).collect();
            if let Ok(p)=self.expedition_water(run.boss_p,300.,&occupied){if let Ok(id)=self.add_expedition_creature("leviathan",p){run.boss_ship=Some(id);run.boss_p=p;run.boss_status="active".into();self.salvage.as_mut().unwrap().enemy_count+=1;self.add(1,"expedition_boss_arrived","渊喉已进入海域，击败它可留下核心残骸；携物撤离仍然有效。".into(),Some("CAS-EXTRACTION-02"),Some(p));}}
        }
        if run.boss_status=="active"&&run.boss_ship.is_some_and(|id|self.ship(id).is_none_or(|s|!s.alive())){
            if let Some(p)=run.boss_ship.and_then(|id|self.ship(id)).map(|s|s.p){run.boss_p=p;}
            run.boss_status="defeated".into();self.salvage.as_mut().unwrap().ruins.push(Ruin{id:2000,p:run.boss_p,kind:"equipment".into(),amount:4,found:true,collected:false});
            self.add(1,"expedition_boss_defeated","深海核心残骸已可搜索，仍须实际装载并撤离。".into(),Some("CAS-EXTRACTION-02"),Some(run.boss_p));
        }
        self.expedition=Some(run);
    }
    pub(crate) fn expedition_view(&self,owner:usize,view:&mut Value){
        let Some(run)=&self.expedition else{return;};let contact=run.boss_ship.and_then(|id|self.contacts[owner].iter().find(|c|c.ship==id).map(|c|c.id.clone()));
        view["salvage"]["generatorVersion"]=json!("archipelago-adventure-2");
        view["salvage"]["defeated_entities"]=json!(run.defeated.iter().filter(|(seat,tick,_)|*seat==owner&&self.tick.saturating_sub(*tick)<=5).map(|(_,_,row)|row).collect::<Vec<_>>());
        view["salvage"]["expedition"]=json!({"version":VERSION,"scene":run.config.scene,"tasks":run.tasks,"pressure":run.pressure,"pursuit_seconds":if run.pressure<25{45}else if run.pressure>=65{180}else{120},
            "boss":{"status":run.boss_status,"announce_tick":run.announce_tick,"spawn_tick":run.spawn_tick,"x":run.boss_p.x,"y":run.boss_p.y,"radius":1000,"source_contact":contact},
            "opposition":{"budget":run.naval_budget,"spent":run.naval_spent,"naval_hulls":run.naval_hulls,"creature_hulls":run.creature_hulls},"extraction_seconds":12-run.extraction_reduction,"autopilot":run.autopilot});
        if run.autopilot.version=="cas-extraction-pilot-v3"{
            let count=self.salvage.as_ref().unwrap().start.groups.len().max(1);
            view["salvage"]["expedition"]["mission_fleets"]=json!((1..=count as u32).collect::<Vec<_>>());
        }
        if let Some(extract)=view["salvage"]["extracting"].as_object_mut(){extract.insert("duration".into(),json!(12-run.extraction_reduction));}
        for row in view["ships"].as_array_mut().unwrap(){if let Some(s)=row["id"].as_u64().and_then(|id|self.ship(id as u32)).filter(|s|s.side==owner){let m=self.expedition_munitions(s);let(_,range_factor,_,reload)=self.expedition_torp_factors(s);
            row["navigation"]=json!({"turn_advance_m":self.data.ships[s.def].turn_advance_yards*YARD});
            row["torpedoRange"]=json!(self.data.ships[s.def].torpedo.as_ref().map_or(0.,|t|t.range_yd*YARD*range_factor));
            row["expedition_munitions"]=json!({"shell":m.shell,"torpedo":m.torpedo,"reserve_reloads":m.reserve_reloads,"torpedo_loaded":s.ammo,"torpedo_reserve":s.torp_reserve.iter().sum::<u32>(),"reload_seconds":reload,"mounts":s.torp_mount_remaining.iter().enumerate().map(|(i,n)|json!({"loaded":n,"reserve":s.torp_reserve[i],"ready_in":s.torp_reload_at[i].saturating_sub(self.tick)})).collect::<Vec<_>>()});}}
        for (row,contact) in view["contacts"].as_array_mut().unwrap().iter_mut().zip(&self.contacts[owner]){
            let Some(s)=self.ship(contact.ship)else{continue;};let def=&self.data.ships[s.def];if def.id.starts_with("CAS-FICTION-"){continue;}
            row["entityKind"]=json!("naval");row["vessel_type"]=json!(if contact.kind.is_some(){def.kind.to_lowercase()}else{"unknown".into()});
            row["health"]=json!(s.hp.max(0.));row["max_health"]=json!(def.dp);row["health_fraction"]=json!((s.hp/def.dp).clamp(0.,1.));
            let seconds=self.expedition_battery_ready_seconds(s);
            row["attack"]=json!({"kind":"naval_gun","label":"巡逻舰炮击","counter":"避开舷侧火力，利用岛岸遮挡；装甲目标可用穿甲弹","state":if seconds>0{"recover"}else{"approach"},"seconds":seconds,"shape":"circle","radius":0,"range":def.gun.range_yd[3]*YARD});
        }
    }
    pub(crate) fn advance_extraction_ai(&mut self){
        if self.amphibious_expedition.is_some() && self.advance_amphibious_ai(){return;}
        let mut view=self.observation(self.player);
        // The v3 wrapper retains exactly the v2 naval mission schema. Adapt only
        // this local pilot input; the public profile and recorded save stay v3.
        if self.amphibious_expedition.is_some(){view["salvage"]["adventure"]["version"]=json!(VERSION);view["salvage"]["expedition"]["tasks"]=json!([]);
            // Only this new-profile pilot input excludes lost hulls from its
            // remaining-fleet supply assessment. Public loss records and the
            // frozen legacy pilot are untouched.
            if let Some(ships)=view["salvage"]["ships"].as_array_mut(){ships.retain(|s|s["hp"].as_f64().unwrap_or(0.)>0.);}
        }
        let mut state=std::mem::take(&mut self.expedition.as_mut().unwrap().autopilot);let actions=crate::extraction_ai::decide(&view,&mut state);
        self.expedition.as_mut().unwrap().autopilot=state;
        for q in actions{let result=self.dispatch_external(self.player,q.clone(),false);crate::extraction_ai::feedback(&mut self.expedition.as_mut().unwrap().autopilot,&q,result);}
    }
    pub(crate) fn expedition_record_defeat(&mut self,id:u32){
        if self.expedition.is_none(){return;}let Some(s)=self.ship(id)else{return;};let d=&self.data.ships[s.def];let species=d.id.strip_prefix("CAS-FICTION-");let mut rows=vec![];
        for owner in 0..2{if let Some(c)=self.contacts[owner].iter().find(|c|c.ship==id){rows.push((owner,self.tick,json!({"id":c.id,"source_contact":c.id,"species":species,"visualType":species,"entityKind":if species.is_some(){"monster"}else{"naval"},"vessel_type":if c.kind.is_some(){d.kind.to_lowercase()}else{"unknown".into()},"x":s.p.x,"y":s.p.y,"heading":s.h,"death_tick":self.tick})));}}
        let run=self.expedition.as_mut().unwrap();run.defeated.retain(|(_,tick,_)|self.tick.saturating_sub(*tick)<=5);run.defeated.extend(rows);
    }
}

#[cfg(test)]
mod tests{
 use super::*;use crate::Engine;use std::collections::BTreeSet;
 fn start()->Start{serde_json::from_value(json!({"content":"salvage-v4","gameplay_profile":VERSION,"fleet":[{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":100,"level":0}],"mission":{"kind":"salvage","id":"calm","loot_kind":"scrap"},"cargo_v4":{"commander_level":1,"difficulty":"calm","environment":"atoll","weather":"clear","loadouts":{}},"expedition_v2":{"scene":"sunken_metropolis","munitions":{}}})).unwrap()}
 fn complete(w:&mut World,id:&str){let t=w.expedition.as_ref().unwrap().tasks.iter().find(|t|t.id==id).unwrap().clone();w.ship_mut(1).unwrap().p=P{x:t.x,y:t.y};w.ship_mut(1).unwrap().speed=0.;w.external(json!({"op":"expedition_task","task":id,"action":"accept"})).unwrap();w.external(json!({"op":"expedition_interact","task":id})).unwrap();for _ in 0..t.duration{w.tick+=1;w.advance_expedition();}}
 #[test]fn valid_scenes_seeded_tasks_and_real_naval_budgets(){
  let mut geometries=BTreeSet::new();let mut kinds=BTreeSet::new();for scene in SCENES{let mut s=start();s.expedition_v2.as_mut().unwrap().scene=scene.into();let w=World::new_salvage(42,s).unwrap();let r=w.expedition.as_ref().unwrap();assert_eq!(r.tasks.len(),3);assert!(r.naval_hulls>0&&r.naval_spent<=r.naval_budget);assert!(r.creature_hulls>=3);for t in &r.tasks{kinds.insert(t.kind.clone());assert!(!w.islands.iter().any(|poly|salvage::polygon_near(poly,P{x:t.x,y:t.y},300.)));}geometries.insert(serde_json::to_string(&w.islands).unwrap());}
  assert_eq!(geometries.len(),5);for seed in 0..12{let w=World::new_salvage(seed,start()).unwrap();for t in &w.expedition.as_ref().unwrap().tasks{kinds.insert(t.kind.clone());}}assert_eq!(kinds.len(),5);
 }
 #[test]fn task_completion_has_real_effect_and_single_physical_reward(){
  let mut all=BTreeSet::new();for seed in 0..12{let mut w=World::new_salvage(seed,start()).unwrap();let tasks=w.expedition.as_ref().unwrap().tasks.clone();for t in tasks{if all.contains(&t.kind){continue;}let exits=w.salvage.as_ref().unwrap().exits.len();let before=w.salvage.as_ref().unwrap().ruins.len();complete(&mut w,&t.id);assert_eq!(w.expedition.as_ref().unwrap().tasks.iter().find(|x|x.id==t.id).unwrap().status,"complete");assert!(w.salvage.as_ref().unwrap().grid.as_ref().unwrap().items.is_empty());
    match t.kind.as_str(){"relay"=>assert_eq!(w.expedition.as_ref().unwrap().base_pressure,-10),"beacon"=>assert_eq!(w.salvage.as_ref().unwrap().exits.len(),exits+1),"rescue"=>{assert_eq!(w.expedition.as_ref().unwrap().extraction_reduction,4);assert_eq!(w.salvage.as_ref().unwrap().ruins.len(),before+1)},_=>assert_eq!(w.salvage.as_ref().unwrap().ruins.len(),before+1)}
    let count=w.salvage.as_ref().unwrap().ruins.len();assert!(w.external(json!({"op":"expedition_interact","task":t.id})).is_err());assert_eq!(w.salvage.as_ref().unwrap().ruins.len(),count);all.insert(t.kind);
  }if all.len()==5{break;}}assert_eq!(all.len(),5);
 }
 #[test]fn abandon_and_damage_interrupt_never_fabricate_reward(){let mut w=World::new_salvage(43,start()).unwrap();let t=w.expedition.as_ref().unwrap().tasks[0].clone();w.external(json!({"op":"expedition_task","task":t.id,"action":"abandon"})).unwrap();assert!(w.external(json!({"op":"expedition_task","task":t.id,"action":"accept"})).is_err());let t=w.expedition.as_ref().unwrap().tasks[1].clone();w.ship_mut(1).unwrap().p=P{x:t.x,y:t.y};w.external(json!({"op":"expedition_task","task":t.id,"action":"accept"})).unwrap();w.external(json!({"op":"expedition_interact","task":t.id})).unwrap();w.ship_mut(1).unwrap().hp-=1.;w.advance_expedition();assert_eq!(w.expedition.as_ref().unwrap().tasks[1].status,"accepted");assert_eq!(w.expedition.as_ref().unwrap().tasks[1].progress,0);}
 #[test]fn boss_has_advance_notice_spawns_once_and_leaves_one_real_wreck(){let mut w=World::new_salvage(43,start()).unwrap();let count=w.ships.len();w.tick=180;w.advance_expedition();assert_eq!(w.expedition.as_ref().unwrap().boss_status,"announced");assert_eq!(w.ships.len(),count);w.tick=209;w.advance_expedition();assert_eq!(w.ships.len(),count);w.tick=210;w.advance_expedition();let boss=w.expedition.as_ref().unwrap().boss_ship.unwrap();assert_eq!(w.ships.len(),count+1);w.tick=250;w.advance_expedition();assert_eq!(w.ships.len(),count+1);w.ship_mut(boss).unwrap().hp=0.;w.advance_expedition();w.advance_expedition();assert_eq!(w.expedition.as_ref().unwrap().boss_status,"defeated");assert_eq!(w.salvage.as_ref().unwrap().ruins.iter().filter(|r|r.id==2000).count(),1);assert!(w.salvage.as_ref().unwrap().grid.as_ref().unwrap().items.is_empty());}
 #[test]fn cargo_catalog_varies_shapes_weights_values_and_is_deterministic(){let mut ids=BTreeSet::new();let mut shapes=BTreeSet::new();let mut weights=BTreeSet::new();for n in 0..16{let a=loot_item(42,1,n,"calm");let b=loot_item(42,1,n,"hazard");assert_eq!(a.loot_id,b.loot_id);assert!(b.value>a.value);ids.insert(a.loot_id);shapes.insert(serde_json::to_string(&a.shape).unwrap());weights.insert(a.kg);}assert_eq!(ids.len(),16);assert!(shapes.len()>=7&&weights.len()>=12);}
 #[test]fn version_enum_and_foreign_ship_rejection_is_strict(){let mut s=start();s.expedition_v2.as_mut().unwrap().scene="unknown".into();assert!(World::new_salvage(42,s).is_err());for field in ["shell","torpedo","reserve_reloads"]{let mut v=serde_json::to_value(start()).unwrap();v["expedition_v2"]["munitions"]["IBS-U-USN-FLETCHER"]=json!({"shell":"balanced","torpedo":"standard","reserve_reloads":1});v["expedition_v2"]["munitions"]["IBS-U-USN-FLETCHER"][field]=if field=="reserve_reloads"{json!(3)}else{json!("unknown")};assert!(World::new_salvage(42,serde_json::from_value(v).unwrap()).is_err());}let mut s=start();s.gameplay_profile=crate::adventure::VERSION.into();assert!(World::new_salvage(42,s).is_err());}
 #[test]fn optional_profile_and_autopilot_replay_reconstruct_exactly(){let mut e=Engine::default();let ask=|e:&mut Engine,q|{let r=e.handle(q);assert_eq!(r["ok"],true,"{r}");r["data"].clone()};ask(&mut e,json!({"op":"new_salvage","seed":40,"start":start()}));ask(&mut e,json!({"op":"extraction_autopilot","enabled":true,"policy":"cautious"}));let v=ask(&mut e,json!({"op":"step","seconds":4}));let save=ask(&mut e,json!({"op":"save"}));assert_eq!(ask(&mut e,json!({"op":"load","save":save.clone()})),v);assert_eq!(ask(&mut e,json!({"op":"replay","save":save})),v);}
 #[test]fn reserves_cost_real_cargo_space_and_unloaded_tubes_have_no_spares(){let mut s=start();s.expedition_v2.as_mut().unwrap().munitions.insert("IBS-U-USN-FLETCHER".into(),Munitions{reserve_reloads:0,..Default::default()});let none=crate::salvage_v4::budget(&s,crate::salvage_v3::expedition_data().unwrap());s.expedition_v2.as_mut().unwrap().munitions.get_mut("IBS-U-USN-FLETCHER").unwrap().reserve_reloads=2;let full=crate::salvage_v4::budget(&s,crate::salvage_v3::expedition_data().unwrap());assert_eq!(none.max_kg-full.max_kg,220);s.cargo_v4.as_mut().unwrap().loadouts.insert("IBS-U-USN-FLETCHER".into(),crate::salvage_v4::Loadout{torpedoes:false});let w=World::new_salvage(42,s).unwrap();assert_eq!(w.ship(1).unwrap().ammo,0);assert_eq!(w.ship(1).unwrap().torp_reserve.iter().sum::<u32>(),0);}
 #[test]fn only_confirmed_visible_deaths_produce_short_public_animation_evidence(){let mut w=World::new_salvage(42,start()).unwrap();let id=w.contacts[0][0].ship;w.ship_mut(id).unwrap().hp=0.;w.sank(id);assert_eq!(w.observation(0)["salvage"]["defeated_entities"].as_array().unwrap().len(),1);w.tick+=6;assert!(w.observation(0)["salvage"]["defeated_entities"].as_array().unwrap().is_empty());let hidden=w.ships.iter().find(|s|s.side==1&&s.alive()).unwrap().id;w.contacts[0].retain(|c|c.ship!=hidden);w.ship_mut(hidden).unwrap().hp=0.;w.sank(hidden);assert!(w.observation(0)["salvage"]["defeated_entities"].as_array().unwrap().is_empty());}
 #[test]fn every_task_site_is_connected_and_safe_across_scene_seeds(){
  use std::collections::VecDeque;
  for scene in SCENES{for seed in 0..4{let mut s=start();s.expedition_v2.as_mut().unwrap().scene=scene.into();let w=World::new_salvage(seed,s).unwrap();
   let step=300.;let cols=(w.field.width/step) as i32;let rows=(w.field.height/step) as i32;
   let clear=|x:i32,y:i32|{let p=P{x:x as f64*step+150.,y:y as f64*step+150.};w.field.contains(p)&&!w.islands.iter().any(|poly|salvage::polygon_near(poly,p,90.))};
   let spawn=((w.ships[0].p.x/step) as i32,(w.ships[0].p.y/step) as i32);let mut seen=BTreeSet::from([spawn]);let mut queue=VecDeque::from([spawn]);
   while let Some((x,y))=queue.pop_front(){for(dx,dy)in[(1,0),(-1,0),(0,1),(0,-1)]{let q=(x+dx,y+dy);if q.0>=0&&q.1>=0&&q.0<cols&&q.1<rows&&!seen.contains(&q)&&clear(q.0,q.1){seen.insert(q);queue.push_back(q);}}}
   for t in &w.expedition.as_ref().unwrap().tasks{assert!(!w.islands.iter().any(|poly|salvage::polygon_near(poly,P{x:t.x,y:t.y},300.)));assert!(seen.contains(&((t.x/step) as i32,(t.y/step) as i32)),"{scene} {seed} {}",t.id);}
  }}
 }
 #[test]fn relay_reduces_real_pursuit_and_delays_an_already_announced_boss(){
  let mut s=start();s.cargo_v4.as_mut().unwrap().difficulty="standard".into();s.expedition_v2.as_mut().unwrap().scene="cult_relay".into();let mut w=World::new_salvage(40,s).unwrap();w.tick=120;w.advance_expedition();assert_eq!(w.expedition.as_ref().unwrap().spawn_tick,Some(150));assert_eq!(w.observation(0)["salvage"]["expedition"]["pursuit_seconds"],120);
  let id=w.expedition.as_ref().unwrap().tasks[0].id.clone();let before=w.expedition.as_ref().unwrap().pressure;complete(&mut w,&id);let r=w.expedition.as_ref().unwrap();assert_eq!(r.spawn_tick,Some(210));assert_eq!(before-r.pressure,25);assert_eq!(w.observation(0)["salvage"]["expedition"]["pursuit_seconds"],45);
 }
 #[test]fn reserve_cost_blocks_real_grid_cells_even_for_zero_weight_items(){
  let mut w=World::new_salvage(40,start()).unwrap();let g=w.salvage.as_mut().unwrap().grid.as_mut().unwrap();let limit=g.usable_cells;assert!(limit<g.rows*g.cols);g.items.push(crate::salvage_v4::Item{id:"test".into(),kind:"scrap".into(),name:"test".into(),shape:vec![[0,0]],kg:0,value:0,ruin:1,placement:Some([0,0,0]),loot_id:String::new()});
  assert!(w.external(json!({"op":"cargo_place","item":"test","x":limit%8,"y":limit/8,"rotation":0})).is_err());assert!(w.external(json!({"op":"cargo_place","item":"test","x":(limit-1)%8,"y":(limit-1)/8,"rotation":0})).is_ok());assert_eq!(w.observation(0)["salvage"]["cargo_grid"]["usable_cells"],limit);
 }
 #[test]fn lost_naval_contact_cannot_publish_hidden_health_or_cooldown(){
  let mut w=World::new_salvage(42,start()).unwrap();let id=w.contacts[0].iter().find(|c|!w.data.ships[w.ship(c.ship).unwrap().def].id.starts_with("CAS-FICTION-")).unwrap().ship;w.ship_mut(id).unwrap().p=P{x:23000.,y:13500.};w.update_tracks();assert!(!w.contacts[0].iter().any(|c|c.ship==id));let before=w.observation(0);w.ship_mut(id).unwrap().hp-=73.;w.ship_mut(id).unwrap().gun_cycle=Some(9999);assert_eq!(before,w.observation(0));
 }
}

