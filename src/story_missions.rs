//! Current fictional story lessons. Absence of this explicit profile is the
//! frozen v1 chapter path. CAS scenarios and published ship records are untouched.
use crate::{model::*,salvage::{Start,Hull,Group,Mission},world::World};
use serde_json::{json,Value};
use std::sync::OnceLock;

pub const VERSION:&str="canon-missions-v3";
pub const REFUGEE:&str="CAS-FICTION-REFUGEE-LAUNCH";
const JINTSU:&str="IBS-U-IJN-JINTSU-I";
const RULE:&str="CAS-FICTION-STORY-03";
const IDS:[&str;9]=["c1-breakout","c1-salvage","c1-boss","c2-convoy","c2-relay","c2-warden","c3-crossing","c3-core","c3-breaker"];
#[derive(Clone,Copy)]
struct Stage {title:&'static str,theme:&'static str,weather:&'static str,goal:&'static str,x:f64,escort:bool}
fn stage(id:&str)->E<Stage>{Ok(match id{
    "c1-breakout"=>Stage{title:"返航灯 · 带着人离开这片海",theme:"fractured",weather:"clear",goal:"escort",x:6200.,escort:true},
    "c1-salvage"=>Stage{title:"礼物坐标 · 失落档案",theme:"drowned_city",weather:"clear",goal:"archive",x:5500.,escort:false},
    "c1-boss"=>Stage{title:"返航灯 · 控制环",theme:"fractured",weather:"clear",goal:"boss",x:6800.,escort:false},
    "c2-convoy"=>Stage{title:"盐线回声 · 慢船也必须抵达",theme:"fjord",weather:"fog",goal:"escort",x:7800.,escort:true},
    "c2-relay"=>Stage{title:"盐线回声 · 半淹广播站",theme:"drowned_city",weather:"rain",goal:"archive",x:7400.,escort:false},
    "c2-warden"=>Stage{title:"盐线回声 · 热泉守门者",theme:"atoll",weather:"fog",goal:"boss",x:8600.,escort:false},
    "c3-crossing"=>Stage{title:"白塔外 · 风暴接应",theme:"fjord",weather:"rain",goal:"escort",x:9200.,escort:true},
    "c3-core"=>Stage{title:"堤外观测站 · 旧世记录",theme:"fractured",weather:"fog",goal:"archive",x:9000.,escort:false},
    "c3-breaker"=>Stage{title:"白塔外 · 守闸者",theme:"atoll",weather:"rain",goal:"boss",x:10200.,escort:false},
    _=>return Err("当前正史关卡未登记".into()),
})}
pub(crate) fn active(s:&Start)->bool{s.chapter_profile==VERSION}
pub(crate) fn terrain_salt(s:&Start)->u64{
    if !active(s){return 0;}
    s.mission.as_ref().and_then(|m|IDS.iter().position(|id|*id==m.id)).map_or(0,|i|(i as u64+1)*0x751e_2983)
}
pub(crate) fn shipping_lanes(s:&Start)->Vec<(P,P)>{
    if !active(s){return vec![];}
    let spec=stage(&s.mission.as_ref().unwrap().id).unwrap();
    (0..if spec.escort{3}else{2}).map(|i|(P{x:2200.,y:2200.+i as f64*1000.},P{x:spec.x+1600.,y:1200.+i as f64*1000.})).collect()
}
pub(crate) fn start(id:&str)->E<Start>{
    let spec=stage(id)?;
    let fifth:Vec<String>=["FLETCHER","PERKINS","MAURY","DRAYTON","LAMSON"].iter().map(|s|format!("IBS-U-USN-{s}")).collect();
    let mut identities=fifth.clone();identities.push(JINTSU.into());if spec.escort{identities.push(REFUGEE.into());}
    let mut groups=vec![Group{id:"fifth".into(),name:"第五驱逐舰小队".into(),ships:fifth},Group{id:"jintsu".into(),name:"神通 · 掩护队".into(),ships:vec![JINTSU.into()]}];
    if spec.escort{groups.push(Group{id:"refugees".into(),name:"人类避难船 · 45人".into(),ships:vec![REFUGEE.into()]});}
    Ok(Start{content:crate::salvage_v4::VERSION.into(),chapter_profile:VERSION.into(),
        chapter_version:format!("chapter-0{}-missions-v3",&id[1..2]),
        fleet:identities.into_iter().map(|id|Hull{id,hp:100,ammo:100,level:0,..Default::default()}).collect(),groups,
        weather:Some(crate::salvage_weather::VERSION.into()),gameplay_profile:crate::adventure::VERSION.into(),intel_profile:crate::intel::VERSION.into(),
        mission:Some(Mission{kind:"chapter".into(),id:id.into(),loot_kind:"scrap".into(),player_budget:0,enemy_budget:0}),
        cargo_v4:Some(crate::salvage_v4::Config{commander_level:1,difficulty:if id.starts_with("c1-"){"calm"}else{"standard"}.into(),environment:spec.theme.into(),weather:spec.weather.into(),loadouts:Default::default()}),
        ..Default::default()})
}
pub(crate) fn validate(s:&Start)->E<()>{
    if !active(s){return Err("剧情任务规则未登记".into());}
    let expected=start(&s.mission.as_ref().ok_or("剧情任务配置缺失")?.id)?;
    if serde_json::to_value(s).unwrap()!=serde_json::to_value(expected).unwrap(){return Err("正史教学须使用登记的借用舰队、护送船与当前任务配置".into());}
    Ok(())
}
pub(crate) fn data()->E<&'static Data>{
    static DATA:OnceLock<E<Data>>=OnceLock::new();
    DATA.get_or_init(||{
        let mut data=crate::salvage_v3::data()?.clone();
        // Original fictional civilian rescue launch; no historical hull/table is
        // repurposed. Zero weapons, 65m, 18kt, 220 DP are registered story values.
        let mut launch=data.ships.iter().find(|d|d.id=="CAS-FICTION-scavenger").unwrap().clone();
        launch.id=REFUGEE.into();launch.name="人类避难船 · 45人".into();launch.side="allies".into();launch.kind="AP".into();launch.size="D".into();
        launch.dp=220.;launch.max_knots=18.;launch.length_m=65.;launch.accel_knots_per_turn=20.;launch.accel_high_knots_per_turn=20.;
        launch.torpedo=None;launch.armor_belt=0.;launch.armor_deck=0.;data.ships.push(launch);Ok(data)
    }).as_ref().map_err(Clone::clone)
}
pub(crate) fn creatures(id:&str,dx:f64)->E<Vec<(&'static str,P)>>{
    let s=stage(id)?;
    let kinds:Vec<(&str,f64,f64)>=match id{
        "c1-breakout"=>vec![("aversion",4300.,3000.),("scavenger",7300.,3500.)],
        "c1-salvage"=>vec![("scavenger",8300.,3700.),("spitter",10200.,4800.)],
        "c2-convoy"=>vec![("scavenger",8700.,5300.),("spitter",10900.,6000.),("aversion",13200.,5200.)],
        "c2-relay"=>vec![("spitter",8500.,3900.),("scavenger",10200.,3800.),("warden",12400.,5000.)],
        "c3-crossing"=>vec![("aversion",13200.,5500.),("spitter",11300.,6000.),("scavenger",14100.,5800.),("warden",15300.,6200.)],
        "c3-core"=>vec![("spitter",10200.,4200.),("warden",12400.,4000.),("scavenger",13800.,4800.)],
        "c2-warden"=>vec![("warden",s.x,3200.),("spitter",s.x+1400.,4000.)],
        _=>vec![("leviathan",s.x,3200.),("spitter",s.x+1600.,4500.)],
    };
    Ok(kinds.into_iter().map(|(kind,x,y)|(kind,P{x:x+dx,y})).collect())
}
impl World {
    pub(crate) fn story_mission(&self)->bool{self.salvage.as_ref().is_some_and(|b|active(&b.start))}
    fn story_spec(&self)->Stage{stage(&self.salvage.as_ref().unwrap().start.mission.as_ref().unwrap().id).unwrap()}
    fn story_point(&self)->P{P{x:self.story_spec().x+1000.,y:2200.}}
    fn story_event(&mut self,key:&str,text:&str){
        if self.ecology.as_mut().unwrap().events.insert(key.into()){self.add(1,"story_objective",text.into(),Some(RULE),None);}
    }
    pub(crate) fn init_story_mission(&mut self)->E<()>{
        if !self.story_mission(){return Ok(());}
        let s=self.story_spec();let p=self.story_point();
        let b=self.salvage.as_mut().unwrap();
        // The reserved 2.2km lane remains continuous on every authored map.
        b.ruins[0].p=p;b.ruins[0].found=true;b.ruins[0].kind=if s.goal=="archive"{"archive"}else{"scrap"}.into();
        b.exits=vec![P{x:p.x+1600.,y:2200.}];
        b.west_bounds=Some([p.x-1800.,1100.,p.x+2400.,4600.]);
        b.search_duration=if s.goal=="archive"{8}else{12};
        let eco=self.ecology.as_mut().unwrap();eco.beacon=if s.goal=="escort"{Some(p)}else{None};
        // New-player escorts begin with gun cover. A free-fire torpedo fan can
        // cross the civilian lane; torpedoes stay a deliberate player order.
        for fleet in &mut self.fleets{if fleet.side==0{fleet.ai.torpedo=false;}}
        self.add(1,"story_briefing",format!("{}：神通与第五驱逐舰小队协同行动{}",s.title,if s.escort{"，保护人类避难船抵达归航区"}else if s.goal=="archive"{"，搜索档案并实际装入货舱后撤离"}else{"，观察攻击预警，击败守卫并集结撤离"}),Some(RULE),Some(p));
        Ok(())
    }
    pub(crate) fn story_exit_blocker(&self)->Option<&'static str>{
        let s=self.story_spec();let b=self.salvage.as_ref().unwrap();let events=&self.ecology.as_ref().unwrap().events;
        if s.escort&&self.ships.iter().any(|ship|ship.character.as_deref()==Some(REFUGEE)&&!ship.alive()){return Some("人类避难船失能，护送任务失败");}
        if s.goal=="escort"&&!events.contains("beacon_reached"){return Some("先让掩护舰抵达返航信标，再带三支编队一起集结");}
        if s.goal=="archive"&&!b.grid.as_ref().unwrap().items.iter().any(|i|i.kind=="archive"&&i.placement.is_some()){return Some("档案匣尚未装入货舱：先搜索，再把档案物资拖进格位");}
        if s.goal=="boss"&&!events.contains("boss_defeated"){return Some("守卫仍在封锁航道：击败守卫后才能撤离");}
        None
    }
    pub(crate) fn advance_story_mission(&mut self){
        if self.result.is_some(){return;}
        let s=self.story_spec();
        if s.escort&&self.ships.iter().any(|ship|ship.character.as_deref()==Some(REFUGEE)&&!ship.alive()){
            self.story_event("escort_lost","避难船已失能，护送失败；可以从章节关卡重试");self.finish_salvage(false);return;
        }
        let b=self.salvage.as_ref().unwrap();
        let searched=b.grid.as_ref().unwrap().completed.contains(&1);
        let stowed=b.grid.as_ref().unwrap().items.iter().any(|i|i.kind=="archive"&&i.placement.is_some());
        if searched{self.story_event("archive_searched","档案容器搜索完成；还需要把档案匣放入货舱");}
        if stowed{self.story_event("archive_recovered","档案匣已实际装入本航次货舱");}
    }
    pub(crate) fn story_mission_view(&self,view:&mut Value){
        let b=self.salvage.as_ref().unwrap();let s=self.story_spec();let p=self.story_point();let eco=self.ecology.as_ref().unwrap();
        let escort:Vec<u32>=self.ships.iter().filter(|s|s.character.as_deref()==Some(REFUGEE)).map(|s|s.id).collect();
        let won=self.result.as_ref().is_some_and(|r|r.primary==Some(true));
        let grid=b.grid.as_ref().unwrap();let cargo=grid.items.iter().any(|i|i.kind=="archive"&&i.placement.is_some());
        let started=self.commands.iter().any(|e|e.request["op"]=="route");
        let rally=self.ships.iter().filter(|s|s.side==0&&s.alive()).all(|s|{let z=b.west_bounds.unwrap();s.p.x>=z[0]&&s.p.x<=z[2]&&s.p.y>=z[1]&&s.p.y<=z[3]});
        let mut steps=vec![json!({"id":"move","action":"route","label":"选择舰娘卡并确认航路。自动舰炮掩护已开启，鱼雷由你手动下令","done":started,"point":p,"fleet_id":1})];
        if s.goal=="escort"{steps.push(json!({"id":"escort","action":"route","label":"让神通掩护，带人类避难船靠近返航灯","done":eco.events.contains("beacon_reached"),"point":p,"fleet_id":3,"ship_id":escort.first()}));}
        if s.goal=="archive"{
            steps.push(json!({"id":"search","action":"search_salvage","label":"靠近档案信标，降至8节以下，开始搜索","done":grid.completed.contains(&1),"point":p,"ruin_id":1}));
            steps.push(json!({"id":"stow","action":"cargo_place","label":"打开货舱，将密封档案匣拖进空格；找到不等于带走","done":cargo,"point":p,"ruin_id":1}));
        }
        if s.goal=="boss"{steps.push(json!({"id":"boss","action":"gun","label":"查看敌人攻击预警，横移闪避并集中火力击败守卫","done":eco.events.contains("boss_defeated"),"point":p}));}
        steps.push(json!({"id":"rally","action":"route","label":"让所有可航行舰艇进入同一归航区域","done":rally,"point":b.exits[0]}));
        steps.push(json!({"id":"extract","action":"salvage_extract","label":"开始撤离，并让全舰留在区域内直到倒计时结束","done":won,"point":b.exits[0]}));
        let current=steps.iter().find(|s|s["done"]!=true).map_or("complete",|s|s["id"].as_str().unwrap());
        let complete=steps.iter().filter(|s|s["done"]==true).count();
        view["scenario"]=json!(s.title);
        view["chapter"]["missionProfile"]=json!(VERSION);view["chapter"]["escortShipIds"]=json!(escort);
        view["chapter"]["escortPeople"]=json!(if s.escort{45}else{0});
        view["chapter"]["lessonStage"]=json!(current);
        view["chapter"]["tutorial"]=json!({"currentStep":current,"completeSteps":complete,"totalSteps":steps.len()});
        view["chapter"]["tutorialSteps"]=json!(steps);
        view["chapter"]["objective"]["kind"]=json!(if s.goal=="archive"{"search_stow_extract"}else if s.goal=="escort"{"escort_and_extract"}else{"defeat_boss_and_extract"});
        view["chapter"]["objective"]["archiveRuinId"]=if s.goal=="archive"{json!(1)}else{Value::Null};
        view["chapter"]["objective"]["beacon"]=json!(eco.beacon);
        if let Some(own)=view["ships"].as_array_mut(){for row in own {if row["characterId"]==REFUGEE{row["storyRole"]=json!("refugee_escort");row["people"]=json!(45);}}}
    }
}

#[cfg(test)]
mod tests{
    use super::*;use crate::Engine;
    #[test]fn all_current_maps_have_jintsu_and_true_current_cargo(){
        let mut layouts=std::collections::BTreeSet::new();
        for id in IDS{let w=World::new_salvage(6109,start(id).unwrap()).unwrap();let v=w.observation(0);
            assert!(w.ships.iter().any(|s|s.character.as_deref()==Some(JINTSU)));assert!(v["salvage"]["cargo_grid"].is_object());assert_eq!(v["chapter"]["missionProfile"],VERSION);
            assert_eq!(v["chapter"]["escortShipIds"].as_array().unwrap().len(),usize::from(stage(id).unwrap().escort));
            assert!(v["chapter"]["tutorialSteps"].as_array().unwrap().len()>=4);
            layouts.insert(serde_json::to_string(&w.islands).unwrap());
            assert!(!w.islands.iter().any(|poly|crate::salvage::polygon_near(poly,w.story_point(),250.)),"{id}");
        }assert_eq!(layouts.len(),9);
    }
    #[test]fn archive_requires_search_then_real_grid_placement_and_survives_replay(){
        let mut e=Engine::default();let q=|e:&mut Engine,r:Value|{let r=e.handle(r);assert_eq!(r["ok"],true,"{r}");r["data"].clone()};
        q(&mut e,json!({"op":"new_chapter","id":"c1-salvage","seed":6109,"chapter_profile":VERSION}));
        // An engine request cannot forge a pickup or bypass the placement check.
        assert_eq!(e.handle(json!({"op":"salvage_extract","exit":0}))["ok"],false);
        let mut w=World::new_salvage(6109,start("c1-salvage").unwrap()).unwrap();let p=w.story_point();
        w.ship_mut(1).unwrap().p=p;w.external(json!({"op":"search_salvage","ruin":1})).unwrap();
        for _ in 0..8{w.advance_cargo_v4();w.advance_story_mission();}
        assert!(w.story_exit_blocker().is_some());assert!(w.salvage.as_ref().unwrap().cargo.is_empty());
        let item=w.salvage.as_ref().unwrap().grid.as_ref().unwrap().items.iter().find(|i|i.kind=="archive").unwrap().id.clone();
        w.external(json!({"op":"cargo_place","item":item,"x":0,"y":0,"rotation":0})).unwrap();w.advance_story_mission();
        assert!(w.story_exit_blocker().is_none());assert!(w.ecology.as_ref().unwrap().events.contains("archive_recovered"));
        // Normal unmodified engine saves reconstruct the new profile, including
        // in-progress tutorial states, via the ordinary command replay path.
        q(&mut e,json!({"op":"step","seconds":5}));let save=q(&mut e,json!({"op":"save"}));let before=q(&mut e,json!({"op":"observe"}));
        assert_eq!(q(&mut e,json!({"op":"load","save":save.clone()})),before);assert_eq!(q(&mut e,json!({"op":"replay","save":save})),before);
    }
    #[test]fn escort_loss_is_real_and_other_ship_loss_is_not_a_fake_convoy_failure(){
        let mut w=World::new_salvage(7,start("c2-convoy").unwrap()).unwrap();w.ship_mut(2).unwrap().hp=0.;w.advance_story_mission();assert!(w.result.is_none());
        let id=w.ships.iter().find(|s|s.character.as_deref()==Some(REFUGEE)).unwrap().id;w.ship_mut(id).unwrap().hp=0.;w.advance_story_mission();assert_eq!(w.result.as_ref().unwrap().primary,Some(false));
    }
    #[test]fn old_request_remains_frozen_and_new_profile_cannot_replace_the_roster(){
        let old=crate::salvage_v3::chapter_start("c1-salvage").unwrap();assert!(serde_json::to_value(old).unwrap().get("chapter_profile").is_none());
        let mut s=start("c1-salvage").unwrap();s.fleet[0].hp=1;assert!(World::new_salvage(7,s).is_err());
        let mut e=Engine::default();assert_eq!(e.handle(json!({"op":"new_chapter","id":"c1-breakout","seed":7,"chapter_profile":"unknown"}))["ok"],false);
    }
}
