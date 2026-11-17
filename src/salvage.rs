//! Fictional, seed-generated exploration. CAS ship cards and combat remain unchanged.
//! All exploration actions share the combat clock and replay command stream.
use crate::{model::*, world::{roll, World}};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

pub const VARIANT: &str = "salvage-v1";
pub const V2: &str = "salvage-v2";
pub(crate) fn is_variant(id:&str)->bool { matches!(id,VARIANT|V2|crate::salvage_v3::VERSION|crate::salvage_v4::VERSION) }
pub(crate) fn modern(id:&str)->bool { id==V2 || id==crate::salvage_v3::VERSION || id==crate::salvage_v4::VERSION }
pub const LIMIT: u32 = 2700;
const WIDTH: f64 = 24000.;
const HEIGHT: f64 = 14000.;

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Hull {
    pub id: String,
    pub hp: u32,
    pub ammo: u32,
    #[serde(default = "one")]
    pub level: u32,
    #[serde(default)]
    pub equipment: bool,
    #[serde(default)]
    pub command: bool,
    #[serde(default,skip_serializing_if="is_zero")]
    pub mastery:u32,
    #[serde(default,skip_serializing_if="is_zero")]
    pub equipment_bonus_bp:u32,
    #[serde(default,skip_serializing_if="String::is_empty")]
    pub equipment_profile:String,
    #[serde(default,skip_serializing_if="std::collections::BTreeMap::is_empty")]
    pub crew:std::collections::BTreeMap<String,crate::owned_growth::Crew>,
}
fn is_zero(value:&u32)->bool { *value==0 }
fn one() -> u32 { 1 }
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Start {
    pub fleet: Vec<Hull>, pub content: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weather: Option<String>,
    #[serde(default,skip_serializing_if="Vec::is_empty")]
    pub groups:Vec<Group>,
    #[serde(default,skip_serializing_if="String::is_empty")]
    pub owned_growth:String,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub mission:Option<Mission>,
    #[serde(default,skip_serializing_if="String::is_empty")]
    pub chapter_version:String,
    #[serde(default,skip_serializing_if="String::is_empty")]
    pub chapter_profile:String,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub cargo_v4:Option<crate::salvage_v4::Config>,
    #[serde(default,skip_serializing_if="String::is_empty")]
    pub gameplay_profile:String,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub expedition_v2:Option<crate::expedition::Config>,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub amphibious_expedition:Option<crate::amphibious_expedition::Config>,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub fuel_v1:Option<crate::fuel::Config>,
    #[serde(default,skip_serializing_if="String::is_empty")]
    pub intel_profile:String,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub cargo_transfer_v1:Option<crate::cargo_transfer::Config>,
}
#[derive(Clone,Debug,Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub struct Group { #[serde(default)] pub id:String, pub name:String, pub ships:Vec<String> }
#[derive(Clone,Debug,Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub struct Mission { pub kind:String,pub id:String,#[serde(default)] pub player_budget:u32,
    #[serde(default)] pub enemy_budget:u32,#[serde(default)] pub loot_kind:String }
#[derive(Clone, Debug, Serialize)]
pub struct Ruin { pub id: u32, pub p: P, pub kind: String, pub amount: u32, pub found: bool, pub collected: bool }
#[derive(Clone, Debug)]
pub struct Battle {
    pub start: Start,
    pub(crate) weather: Option<crate::salvage_weather::Timeline>,
    pub(crate) practice:Vec<u32>,
    pub(crate) command_rng:u64,
    pub(crate) command_attempts:std::collections::BTreeMap<u32,u32>,
    pub ruins: Vec<Ruin>,
    pub exits: Vec<P>,
    pub west_bounds:Option<[f64;4]>,
    pub cargo: Vec<String>,
    pub capacity: usize,
    pub collecting: Option<(u32, u32, f64)>,
    pub extracting: Option<(usize, u32)>,
    pub extracted: bool,
    pub score: u32,
    pub threat: u32,
    pub enemy_count: usize,
    pub search_duration: u32,
    pub grid:Option<crate::salvage_v4::Grid>,
    pub enemies: Vec<EnemyTask>,
}
impl Battle {
    fn inside_exit(&self,index:usize,p:P)->bool {
        if index==0 {
            if let Some([min_x,min_y,max_x,max_y])=self.west_bounds {
                return p.x>=min_x && p.x<=max_x && p.y>=min_y && p.y<=max_y;
            }
        }
        self.exits.get(index).is_some_and(|exit|p.dist(*exit)<1000.)
    }
}

#[derive(Clone, Debug)]
pub struct EnemyTask {
    pub fleet: u32,
    pub role: usize,
    pub home: P,
    pub patrol: [P; 2],
    pub waypoint: usize,
    pub last_contact: Option<(P, u32)>,
    pub chase_started: Option<u32>,
    pub returning: bool,
}

impl World {
    pub(crate) fn new_salvage(seed: u32, start: Start) -> E<Self> {
        crate::fuel::validate(&start)?;
        crate::intel::validate(&start.intel_profile)?;
        crate::cargo_transfer::validate(&start)?;
        crate::amphibious_expedition::validate(&start)?;
        let v2=modern(&start.content);
        let v3=[crate::salvage_v3::VERSION,crate::salvage_v4::VERSION].contains(&start.content.as_str());
        crate::salvage_v4::validate(&start)?;
        crate::salvage_v3::validate_start(&start)?;
        crate::adventure::validate(&start)?;
        if !is_variant(&start.content) || start.fleet.is_empty() || (!v2 && start.fleet.len() > 5) {
            return Err("出航需要有效舰娘与正确内容版本；旧版最多5舰".into());
        }
        if !start.owned_growth.is_empty() && (!v2 || start.owned_growth!=crate::owned_growth::VERSION) {
            return Err("不支持的自有舰成长版本".into());
        }
        if start.owned_growth.is_empty() && start.fleet.iter().any(|h|h.mastery>0 || h.equipment_bonus_bp>0 || !h.equipment_profile.is_empty() || !h.crew.is_empty()) {
            return Err("成长词条需要明确的自有舰成长版本".into());
        }
        if !v2 && (!start.groups.is_empty() || start.mission.is_some()) { return Err("旧打捞版本不接受新任务配置".into()); }
        if start.weather.as_deref().is_some_and(|version| version != crate::salvage_weather::VERSION) {
            return Err("不支持的打捞天气版本".into());
        }
        let data = if crate::story_missions::active(&start){crate::story_missions::data()?}else if crate::amphibious_expedition::is_version(&start.gameplay_profile){crate::littoral_v4::extended_data()?}else if start.gameplay_profile==crate::expedition::VERSION{crate::salvage_v3::expedition_data()?}else if v3{crate::salvage_v3::data()?}else{crate::ranked_fleets::data()?};
        let mut seen = std::collections::BTreeSet::new();
        let mut score = 0;
        let points: Value = serde_json::from_str(include_str!("../data/rules/cas-competitive-points-v1.json")).map_err(|e| e.to_string())?;
        for h in &start.fleet {
            if !seen.insert(h.id.clone()) || !data.ships.iter().any(|d| d.id == h.id)
                || h.hp == 0 || h.hp > 100 || h.ammo > 100 || (!v2 && h.level == 0) || h.level > 30
                || h.mastery>1000 || h.equipment_bonus_bp>100 || !crate::owned_growth::gear_profile_valid(&h.equipment_profile) || !crate::owned_growth::validate(&h.crew) {
                return Err("打捞编队有重复、未核验或状态无效的舰娘".into());
            }
            score += points["ships"][&h.id]["points"].as_u64().map(|p|p as u32).or_else(||crate::amphibious_expedition::is_version(&start.gameplay_profile).then(||crate::littoral_v4::ship_points(&h.id)).flatten()).or_else(||(crate::story_missions::active(&start)&&h.id==crate::story_missions::REFUGEE).then_some(200)).ok_or("舰娘缺少登记点价")?
                + (if v2{h.level}else{h.level.saturating_sub(1)}) * 20 + u32::from(h.equipment) * 75 + u32::from(h.command) * 50;
        }
        let mut groups=start.groups.clone();
        if groups.is_empty() { groups.push(Group{id:"legacy".into(),name:"打捞编队".into(),ships:start.fleet.iter().map(|h|h.id.clone()).collect()}); }
        let grouped=groups.iter().flat_map(|g|g.ships.iter()).collect::<Vec<_>>();
        if groups.iter().any(|g|g.ships.is_empty() || g.name.len()>128) || grouped.len()!=start.fleet.len()
            || grouped.iter().collect::<std::collections::BTreeSet<_>>().len()!=grouped.len()
            || grouped.iter().any(|id|!seen.contains(id.as_str())) { return Err("各出航编队须完整且不重复地分配舰娘".into()); }
        if let Some(task)=&start.mission {
            if !["salvage","resources","ladder","chapter"].contains(&task.kind.as_str()) || task.id.len()>80
                || !["scrap","alloy","equipment","command"].contains(&task.loot_kind.as_str()) {return Err("任务配置无效".into());}
            let base_score:u32=start.fleet.iter().map(|h|points["ships"][&h.id]["points"].as_u64().unwrap_or(0) as u32).sum();
            if task.kind=="ladder" && (![1000,2000,3000,5000].contains(&task.player_budget)
                || task.enemy_budget!=task.player_budget*3/2 || base_score>task.player_budget) {return Err("天梯舰队预算无效".into());}
        }
        let threat = if score < 1500 {1} else if score < 3000 {2} else if score < 6000 {3} else {4};
        // Fictional V2 deployment: complete parallel columns, not folded rows.
        // Grow the sea to fit arbitrary owned groups; never squeeze ship spacing.
        let west_extension=if v2{groups.iter().map(|g|g.ships.len()).max().unwrap_or(1).saturating_sub(3) as f64*500.}else{0.};
        let mut w = Self::blank(data, seed, 0, "coord", &start.content, "coord", 0);
        w.field = Field { width: WIDTH+west_extension, height:if v2{HEIGHT.max(4200.+groups.len() as f64*1000.)}else{HEIGHT}, limit: LIMIT };
        // Separate deterministic streams. Loot changes cannot move coastlines or enemies.
        let mut terrain_rng = seed as u64 ^ 0x8957_123a_ace4;
        let mut ruins_rng = seed as u64 ^ 0x1a35_6912_6721;
        let mut loot_rng = seed as u64 ^ 0x61c7_9123_4567;
        let mut enemy_rng = seed as u64 ^ 0x3468_9871_2333;
        // Islands lie in separated cells; a continuous south shipping lane and
        // west/east coast corridors are guaranteed open, including all exits.
        for i in 0..8 {
            let x = 6200. + (i % 4) as f64 * 4400. + roll(&mut terrain_rng, 700) as f64;
            let y = 5200. + (i / 4) as f64 * 4300. + roll(&mut terrain_rng, 650) as f64;
            let radius = 380. + roll(&mut terrain_rng, 260) as f64;
            let poly = (0..9).map(|j| {
                let a = j as f64 * std::f64::consts::TAU / 9.;
                let r = radius * (0.8 + roll(&mut terrain_rng, 35) as f64 / 100.);
                P { x: x + libm::cos(a) * r, y: y + libm::sin(a) * r }
            }).collect();
            w.islands.push(poly);
        }
        let mut ruins = vec![Ruin { id: 1, p: P{x:if v2{2700.}else{3700.},y:2200.}, kind:start.mission.as_ref().filter(|m|m.kind=="resources").map_or("scrap",|m|m.loot_kind.as_str()).into(), amount:if v2{if start.mission.as_ref().is_some_and(|m|m.kind=="resources" && ["equipment","command"].contains(&m.loot_kind.as_str())){1}else{5}}else{3}, found:true, collected:false }];
        for i in 0..9 {
            let kinds = ["scrap", "alloy", "scrap", "equipment", "command"];
            ruins.push(Ruin { id:i+2, p:P{x:5300. + (i % 5) as f64 * 3700. + roll(&mut ruins_rng,700) as f64,
                y:2600. + (i / 5) as f64 * 4600. + roll(&mut ruins_rng,500) as f64},
                kind:kinds[roll(&mut loot_rng,5) as usize-1].into(), amount:if v2{2+roll(&mut loot_rng,3)}else{1+roll(&mut loot_rng,2)}, found:v2&&i<2, collected:false });
        }
        if v3 {crate::salvage_v3::terrain(&mut w,seed,&start,west_extension)?;}
        if [crate::adventure::VERSION,crate::expedition::VERSION,crate::amphibious_expedition::VERSION].contains(&start.gameplay_profile.as_str()) {
            let terrain_seed=if [crate::expedition::VERSION,crate::amphibious_expedition::VERSION].contains(&start.gameplay_profile.as_str()) {seed^((crate::expedition::SCENES.iter().position(|s|Some(*s)==start.expedition_v2.as_ref().map(|c|c.scene.as_str())).unwrap_or(0) as u32+1)*0x7351)}else{seed};
            crate::adventure::terrain(&mut w,terrain_seed,&start,&mut ruins)?;
        }else{validate_sea(&w.islands,&ruins)?;}
        for polygon in &mut w.islands {for p in polygon{p.x+=west_extension;}}
        for ruin in &mut ruins{ruin.p.x+=west_extension;}
        let mut members = vec![];
        for (i, h) in start.fleet.iter().enumerate() {
            let index = data.ships.iter().position(|d| d.id == h.id).unwrap();
            let group=groups.iter().position(|g|g.ships.contains(&h.id)).unwrap() as u32+1;
            let slot=groups[group as usize-1].ships.iter().position(|id|id==&h.id).unwrap();
            let p=if v2 {P{x:2200.+west_extension-slot as f64*500.,y:2200.+f64::from(group-1)*1000.}}else{P{x:2200.-i as f64*220.,y:2200.}};
            let id = w.spawn(index, 0, group, data.ships[index].name.clone(), p,90.)?;
            let ship = w.ship_mut(id).unwrap();
            // The four opt-in carriers use explicit CAS-H/CAS-O identities,
            // whereas the frozen spawn helper only recognizes IBS-U IDs.
            // Preserve the actual owned identity before groups/growth/army
            // resolve it. No implicit identity changes in older sorties.
            if crate::amphibious_expedition::is_version(&start.gameplay_profile)||crate::story_missions::active(&start){ship.character=Some(h.id.clone());}
            ship.hp *= h.hp as f64 / 100.;
            ship.ammo = ship.ammo * h.ammo / 100;
            let mut left = ship.ammo;
            for mount in &mut ship.torp_mount_remaining {
                *mount = (*mount).min(left);
                left -= *mount;
            }
            for reserve in &mut ship.torp_reserve { *reserve = *reserve * h.ammo / 100; }
            // V1 utility is frozen; V2 owned modifiers are applied below without editing ShipDef.
            members.push(id);
        }
        for (i,group) in groups.iter().enumerate() {
            let own=group.ships.iter().map(|identity|members.iter().copied().find(|&id|w.ship(id).unwrap().character.as_ref()==Some(identity)).unwrap()).collect();
            w.fleets.push(exploration_fleet(i as u32+1,0,own,&group.name,false));
        }
        let west_bounds=v2.then(||[
            w.ships.iter().map(|s|s.p.x).fold(f64::INFINITY,f64::min)-500.,
            w.ships.iter().map(|s|s.p.y).fold(f64::INFINITY,f64::min)-500.,
            w.ships.iter().map(|s|s.p.x).fold(f64::NEG_INFINITY,f64::max)+500.,
            w.ships.iter().map(|s|s.p.y).fold(f64::NEG_INFINITY,f64::max)+500.]);
        let west_exit=west_bounds.map_or(P{x:2200.+west_extension,y:2200.},|b|P{x:(b[0]+b[2])/2.,y:(b[1]+b[3])/2.});
        let mut enemy_count = if v2 { (threat as usize+6+start.fleet.len()/3).min(24) } else { threat as usize+2 };
        let ladder=start.mission.as_ref().filter(|m|m.kind=="ladder");
        let mut ladder_ids:Vec<&str>=vec![];
        if let Some(task)=ladder {
            let candidates:Vec<_>=data.ships.iter().filter(|s|s.id.starts_with("IBS-U-IJN-") && ["DD","CL"].contains(&s.kind.as_str()))
                .filter_map(|s|points["ships"][&s.id]["points"].as_u64().filter(|&p|p>0).map(|p|(s.id.as_str(),p as usize))).collect();
            let budget=task.enemy_budget as usize;
            let mut best:Vec<Option<Vec<&str>>>=vec![None;budget+1];best[0]=Some(vec![]);
            for amount in 1..=budget {
                for &(id,cost) in &candidates {
                    if cost>amount {continue;}
                    if let Some(mut fleet)=best[amount-cost].clone().filter(|fleet|fleet.len()<24) {
                        fleet.push(id);
                        if best[amount].as_ref().is_none_or(|old|fleet.len()<old.len()) {best[amount]=Some(fleet);}
                    }
                }
            }
            ladder_ids=best[budget].take().ok_or("没有恰好满足该天梯分数的已核舰卡组合")?;
            enemy_count=ladder_ids.len();
            if enemy_count==0 {return Err("天梯预算无法组成合法敌舰".into());}
        }
        let enemy_ids = ["IBS-U-IJN-KAGERO", "IBS-U-IJN-TAKANAMI", "IBS-U-IJN-KUROSHIO", "IBS-U-IJN-SENDAI"];
        let mut enemies = vec![];
        for i in 0..if v3 && ladder.is_none(){0}else{enemy_count} {
            let identity = if ladder.is_some(){ladder_ids[i]}else{enemy_ids[if threat >= 3 && i == enemy_count-1 {3} else {roll(&mut enemy_rng,3) as usize-1}]};
            let index = data.ships.iter().position(|d| d.id == identity).ok_or("敌舰卡未登记")?;
            let p = if v2 {P{x:9000.+west_extension+(i%4) as f64*3000.+roll(&mut enemy_rng,300) as f64,
                y:[2800.,3800.,6800.,7800.,11200.,12200.][i/4]}} else if i == 0 { P{x:9600. + roll(&mut enemy_rng,500) as f64,y:2800.} } else {
                P{x:11500. + (i%3) as f64*3200. + roll(&mut enemy_rng,500) as f64,
                    y:3000. + (i/3) as f64*4300.}
            };
            let fleet = i as u32 + groups.len() as u32+1;
            let id = w.spawn(index,1,fleet,data.ships[index].name.clone(),p,270.)?;
            let name = match i % 3 {0=>"遗迹守卫",1=>"海域巡逻",_=>"搜索追击"};
            w.fleets.push(exploration_fleet(fleet,1,vec![id],name,true));
            enemies.push(EnemyTask { fleet, role:i%3, home:p,
                patrol:[p, P{x:(p.x-3200.).max(6000.+west_extension),y:p.y}], waypoint:1,
                last_contact:None, chase_started:None, returning:false });
        }
        let capacity = 8 + start.fleet.iter().filter(|h| h.equipment).count()*2;
        let growth: u32 = start.fleet.iter().map(|h|if v2{h.level}else{h.level.saturating_sub(1)}).sum();
        let command = start.fleet.iter().filter(|h| h.command).count();
        let search_duration = if v2{(6.-f64::from(growth)*0.1-command as f64).max(3.).ceil() as u32}else{(12. - f64::from(growth)*0.25 - command as f64).max(4.).ceil() as u32};
        let weather = start.weather.as_ref().map(|_| crate::salvage_weather::Timeline::new(seed));
        let growth:Vec<_>=w.ships.iter().map(|s|start.fleet.iter().find(|h|Some(&h.id)==s.character.as_ref())
            .filter(|_|!start.owned_growth.is_empty() && s.side==0).map(crate::owned_growth::Stats::from_hull).unwrap_or_default()).collect();
        for (ship,stats) in w.ships.iter_mut().zip(&growth) {ship.hp*=stats.hp;}
        w.owned_growth=growth;
        let practice=vec![0;w.ships.len()];
        w.salvage = Some(Battle {start, weather, practice,command_rng:u64::from(seed)^0x69a2_853e_1127,command_attempts:Default::default(), ruins,west_bounds, exits:vec![west_exit,P{x:22000.+west_extension,y:2200.},P{x:2200.+west_extension,y:12000.}],
            grid:None,cargo:vec![],capacity,collecting:None,extracting:None,extracted:false,score,threat,enemy_count,search_duration,enemies});
        if v3 {w.init_ecology(west_extension)?;}
        if w.variant==crate::salvage_v4::VERSION {w.init_cargo_v4()?;}
        if w.adventure() {w.init_adventure()?;}
        if w.expedition_v2() {w.init_expedition()?;}
        w.init_story_mission()?;
        w.init_amphibious_expedition()?;
        w.init_fuel()?;
        w.enable_realtime()?;
        w.detect(true);
        w.add(1,"start","打捞行动开始。搜索遗迹，带回物资；撤离点已标入海图。".into(),Some("CAS-SALVAGE-01"),None);
        Ok(w)
    }

    pub(crate) fn salvage_command(&mut self, r: &Value) -> E<()> {
        if self.variant==crate::salvage_v4::VERSION && ["salvage_collect","salvage_drop","salvage_cancel"].contains(&r["op"].as_str().unwrap_or("")){return self.cargo_command(r);}
        let battle = self.salvage.as_ref().ok_or("当前不是打捞行动")?;
        let alive:Vec<_> = self.ships.iter().filter(|s|s.side==0 && s.alive() && self.max_speed(s)>=4.).collect();
        if alive.is_empty() {return Err("打捞编队已失能".into());}
        match r["op"].as_str().unwrap_or("") {
            "salvage_abandon"=>{
                self.salvage.as_mut().unwrap().collecting=None;
                self.salvage.as_mut().unwrap().extracting=None;
                self.finish_salvage(false);
                return Ok(());
            }
            "salvage_collect"=>{
                let id = crate::world::u(r,"ruin")?;
                let ruin = battle.ruins.iter().find(|n|n.id==id && n.found && !n.collected).ok_or("遗迹尚未发现或已搜空")?;
                if !alive.iter().any(|s|s.p.dist(ruin.p)<750. && s.speed<=8.) {return Err("请靠近遗迹 750 米内并降速至 8 节以下".into());}
                if battle.cargo.len() >= battle.capacity {return Err("货舱已满，请先弃置货物或撤离".into());}
                let hp = alive.iter().map(|s|s.hp).sum();
                let b=self.salvage.as_mut().unwrap();
                b.extracting=None;
                // Duplicate UI submissions must not reset an in-progress timer.
                if !b.collecting.is_some_and(|(active,_,_)|active==id) { b.collecting=Some((id,0,hp)); }
            }
            "salvage_extract"=>{
                if let Some(reason)=self.amphibious_extract_blocker(){return Err(reason.into());}
                if battle.start.mission.as_ref().is_some_and(|m|m.kind=="ladder") {return Err("天梯须击败全部敌舰，不能以撤离领取胜利".into());}
                if let Some(reason)=self.chapter_exit_blocker(){return Err(reason.into());}
                let exit = crate::world::u(r,"exit")? as usize;
                battle.exits.get(exit).ok_or("撤离点不存在")?;
                if !alive.iter().all(|s|battle.inside_exit(exit,s.p)) {return Err(if exit==0 && battle.west_bounds.is_some(){"所有可航行舰娘须进入西侧集结撤离区"}else{"所有可航行舰娘须进入同一撤离点 1000 米范围"}.into());}
                let b=self.salvage.as_mut().unwrap();
                b.collecting=None;
                if let Some(grid)=b.grid.as_mut(){grid.search=None;}
                if !b.extracting.is_some_and(|(active,_)|active==exit) { b.extracting=Some((exit,0)); }
            }
            "salvage_cancel"=>{
                let b=self.salvage.as_mut().unwrap();b.collecting=None;b.extracting=None;
            }
            "salvage_drop"=>{
                let index=crate::world::u(r,"index")? as usize;
                if index>=battle.cargo.len() {return Err("该货物不存在".into());}
                self.salvage.as_mut().unwrap().cargo.remove(index);
            }
            _=>return Err("打捞命令无效".into()),
        }
        Ok(())
    }

    pub(crate) fn advance_salvage(&mut self) {
        if self.result.is_some() { return; }
        self.protect_salvage_hulls();
        let Some(mut b)=self.salvage.take() else {return};
        let alive:Vec<_>=self.ships.iter().filter(|s|s.side==0 && s.alive() && self.max_speed(s)>=4.).map(|s|(s.p,s.speed,s.hp)).collect();
        if modern(&b.start.content) {
            for ship in self.ships.iter().filter(|s|s.side==0 && s.alive()) {
                if ship.speed>0.5 || ship.gun_cycle.is_some_and(|cycle|cycle==self.tick/CYCLE)
                    || ship.torp_cycle.is_some_and(|cycle|cycle==self.tick/CYCLE) {
                    b.practice[ship.id as usize-1]=b.practice[ship.id as usize-1].saturating_add(1);
                }
            }
        }
        for ruin in &mut b.ruins {if alive.iter().any(|s|s.0.dist(ruin.p)<4000.) {ruin.found=true;}}
        if let Some((id,progress,hp))=b.collecting {
            if let Some(n)=b.ruins.iter_mut().find(|n|n.id==id) {
                if alive.iter().map(|s|s.2).sum::<f64>()+0.001<hp || !alive.iter().any(|s|s.0.dist(n.p)<750. && s.1<=8.) {
                    b.collecting=None;
                } else if b.cargo.len()>=b.capacity {
                    // Keep the container unopened until the player makes room.
                    b.collecting=None;
                } else if progress+1>=b.search_duration {
                    let count=(n.amount as usize).min(b.capacity-b.cargo.len());
                    b.cargo.extend(std::iter::repeat(n.kind.clone()).take(count));
                    n.amount-=count as u32;n.collected=n.amount==0;b.collecting=None;
                    self.add(1,"salvage",format!("已装载 {count} 件打捞物"),Some("CAS-SALVAGE-01"),Some(n.p));
                } else {b.collecting=Some((id,progress+1,hp));}
            }
        }
        if let Some((exit,progress))=b.extracting {
            if alive.is_empty() || !alive.iter().all(|s|b.inside_exit(exit,s.0)) {b.extracting=None;}
            else if progress>=if modern(&b.start.content){11-self.expedition.as_ref().map_or(0,|e|e.extraction_reduction)}else{19} {b.extracted=true;b.extracting=None;}
            else {b.extracting=Some((exit,progress+1));}
        }
        // Only enemy-seat contacts enter task decisions. No hidden ship position,
        // cargo value, clicked exit or future player route is inspected.
        if self.tick%20==1 {
            let known=self.contacts[1].iter().map(|c|P{x:c.x,y:c.y}).collect::<Vec<_>>();
            for task in &mut b.enemies {
                let Some(fleet)=self.fleet(task.fleet) else {continue};
                let Some(ship)=self.ship(fleet.leader).filter(|s|s.alive()) else {continue};
                let position=ship.p;
                let leader=fleet.leader;
                let sight=known.iter().filter(|p|p.dist(position)<7000. && (task.role!=0 || p.dist(task.home)<4000.))
                    .min_by(|a,b|a.dist(position).total_cmp(&b.dist(position))).copied();
                if !task.returning {
                    if let Some(p)=sight {
                        task.last_contact=Some((p,self.tick));
                        task.chase_started.get_or_insert(self.tick);
                    }
                }
                let pursuit=self.expedition.as_ref().map_or(if task.role==0 {90}else{120},|e|if e.pressure<25{45}else if e.pressure>=65{180}else{120});
                let chased=task.chase_started.is_some_and(|t|self.tick.saturating_sub(t)>=pursuit);
                let stale=task.last_contact.is_some_and(|(_,t)|self.tick.saturating_sub(t)>120);
                if chased || stale || task.role==0 && position.dist(task.home)>4000. {
                    task.returning=true;task.last_contact=None;task.chase_started=None;
                }
                if task.returning && position.dist(task.home)<500. {
                    task.returning=false;
                }
                let fleet_id=task.fleet;
                let defend=sight.is_some() && (!task.returning || sight.is_some_and(|p|p.dist(position)<3000.));
                if let Some(f)=self.fleet_mut(fleet_id) {f.ai.gun=defend;f.ai.torpedo=defend;}
                let target=if task.returning { task.home }
                    else if let Some((p,_))=task.last_contact {p}
                    else if task.role==0 {task.home}
                    else {
                        if position.dist(task.patrol[task.waypoint])<500. {task.waypoint=1-task.waypoint;}
                        task.patrol[task.waypoint]
                    };
                if position.dist(target)>400. {
                    let _=self.route(1,&json!({"fleet":task.fleet,"mode":"follow",
                        "speed":if task.last_contact.is_some(){24}else{14},"points":[target]}),false);
                } else if task.role==0 && task.last_contact.is_none() {
                    // A guard at home stays there instead of extending its old route.
                    if let Some(s)=self.ship_mut(leader) { s.track=None;s.speed=0.; }
                }
            }
        }
        let failed=alive.is_empty() || self.tick>=LIMIT;
        if b.start.mission.as_ref().is_some_and(|m|m.kind=="ladder") && !self.ships.iter().any(|s|s.side==1 && s.alive()) {b.extracted=true;}
        let extracted=b.extracted;
        self.salvage=Some(b);
        if extracted || failed { self.finish_salvage(extracted); }
    }

    pub(crate) fn finish_salvage(&mut self, success:bool) {
        if self.result.is_some() {return;}
        self.result=Some(Outcome{winner:if success{"allies"}else{"axis"}.into(),allies:0,axis:0,primary:Some(success)});
        self.add(1,"end",if success{"撤离完成，打捞物资已封存"}else{"行动结束，救援队已出动；未撤出货物损失"}.into(),Some("CAS-SALVAGE-01"),None);
    }

    fn protect_salvage_hulls(&mut self) {
        let ids:Vec<_>=self.ships.iter().filter(|s|s.side==0 && !s.escaped && (s.hp<=0. || self.max_speed(s)<4.)).map(|s|s.id).collect();
        for id in ids {
            let ship=self.ship_mut(id).unwrap();
            ship.escaped=true;ship.track=None;ship.speed=0.;ship.battery.order=None;
            let name=ship.name.clone();
            self.add(1,"protected",format!("{name} 已进入保护状态，回港后需要维修"),Some("CAS-SALVAGE-01"),None);
        }
        for fleet in &mut self.fleets {
            if fleet.side==0 && !self.ships.iter().any(|s|s.id==fleet.leader && s.alive()) {
                if let Some(ship)=self.ships.iter().find(|s|s.fleet==Some(fleet.id) && s.alive()) {fleet.leader=ship.id;}
            }
        }
    }

    /// Fictional sortie supply: one percentage point per actual main-gun salvo.
    /// CAS's historical gun tables and historical scenarios are untouched.
    pub(crate) fn salvage_gun_supply(&self, ship:&Ship) -> u32 {
        if let Some(supply)=self.v4_gun_supply.as_ref().filter(|_|ship.side==0){
            let initial=supply.get(&ship.id).copied().unwrap_or(0);
            let fired=self.events.iter().filter(|e|matches!(e.kind,"gun"|"secondary")&&e.own_ship==Some(ship.id)).count() as u32;
            let torpedo_spent=self.data.ships[ship.def].torpedo.as_ref().map_or(0,|t|{let total=t.tubes+t.mounts.iter().map(|m|m.reserve).sum::<u32>();let loaded=t.mounts.iter().map(|m|m.tubes*initial/100+m.reserve*initial/100).sum::<u32>();let remaining=ship.ammo+ship.torp_reserve.iter().sum::<u32>();loaded.saturating_sub(remaining).saturating_mul(100).div_ceil(total.max(1))});
            return initial.saturating_sub(fired.saturating_add(torpedo_spent));
        }
        let Some(b)=self.salvage.as_ref().filter(|_|ship.side==0) else {return 100;};
        let initial=b.start.fleet.iter().find(|h|Some(&h.id)==ship.character.as_ref()).map_or(0,|h|h.ammo);
        let gun_spent=self.events.iter().filter(|e|e.kind=="gun" && e.own_ship==Some(ship.id)).count() as u32;
        let torpedo_spent=if let Some(t)=&self.data.ships[ship.def].torpedo {
            let disabled=b.start.cargo_v4.as_ref().and_then(|c|ship.character.as_ref().and_then(|id|c.loadouts.get(id))).is_some_and(|l|!l.torpedoes);
            let reloads=if self.expedition_v2(){self.expedition_munitions(ship).reserve_reloads}else{0};
            let initial_loaded=if disabled{0}else if self.expedition_v2(){t.tubes*initial/100*(1+reloads)}else{t.tubes*initial/100 + t.mounts.iter().map(|m|m.reserve*initial/100).sum::<u32>()};
            let remaining=ship.ammo+ship.torp_reserve.iter().sum::<u32>();
            let spent=initial_loaded.saturating_sub(remaining);
            let total=(if self.expedition_v2(){t.tubes*(1+reloads)}else{t.tubes+t.mounts.iter().map(|m|m.reserve).sum::<u32>()}).max(1);
            (spent*100+total-1)/total
        } else {0};
        initial.saturating_sub(gun_spent.saturating_add(torpedo_spent))
    }

    pub(crate) fn salvage_view(&self) -> Value {
        let b=self.salvage.as_ref().unwrap();
        let own:Vec<_>=self.ships.iter().filter(|s|s.side==0).map(|s|{
            json!({"id":s.character,"hp":(s.hp.max(0.)/self.hull_max_hp(s)*100.).floor().min(100.),
                "ammo":self.salvage_gun_supply(s),"protected":!s.alive(),
                "canNavigate":s.alive() && self.max_speed(s)>=4.,"practice":b.practice.get(s.id as usize-1).copied().unwrap_or(0).saturating_div(30).min(30)})
        }).collect();
        let mut loot=serde_json::Map::new();
        for kind in &b.cargo {*loot.entry(kind).or_insert(json!(0))=json!(loot.get(kind).and_then(Value::as_u64).unwrap_or(0)+1);}
        let mut view=json!({"content":b.start.content,"score":b.score,"threat":b.threat,"capacity":b.capacity,"cargo":b.cargo,
            "ruins":b.ruins.iter().filter(|n|n.found).collect::<Vec<_>>(),"exits":b.exits,
            "collecting":b.collecting.map(|(id,p,_)|json!({"ruin":id,"progress":p,"duration":b.search_duration})),
            "extracting":b.extracting.map(|(id,p)|json!({"exit":id,"progress":p,"duration":if modern(&b.start.content){12}else{20}})),
            "extracted":b.extracted,"searchDuration":b.search_duration,"generatorVersion":"archipelago-1","loot":loot,"ships":own,"enemyBudgetHulls":b.enemy_count});
        // Preserve old observations byte-for-byte; new practice belongs only to v2.
        if !modern(&b.start.content) {for ship in view["ships"].as_array_mut().unwrap(){ship.as_object_mut().unwrap().remove("practice");}}
        else {
            view["mission"]=json!(b.start.mission);view["encounterVersion"]=json!(b.start.content);
            for (index,exit) in view["exits"].as_array_mut().unwrap().iter_mut().enumerate() {
                if let Some(bounds)=b.west_bounds.filter(|_|index==0) {
                    exit["shape"]=json!("rectangle");exit["bounds"]=json!({"min_x":bounds[0],"min_y":bounds[1],"max_x":bounds[2],"max_y":bounds[3]});
                }else{exit["shape"]=json!("circle");exit["radius"]=json!(1000);}
            }
        }
        view
    }
}

pub(crate) fn exploration_fleet(id:u32,side:usize,members:Vec<u32>,name:&str,enemy:bool)->Fleet {
    let mut ai=Ai::new("coord","auto");ai.r#move=false;
    if enemy {ai.gun=false;ai.torpedo=false;}
    Fleet{id,side,name:name.into(),leader:members[0],members,mode:"follow".into(),speed:if enemy{14.}else{0.},actual:0.,turn_degrees:0.,points:vec![],ai,notice:None,last_ai_route:0,tactic:Tactic::Search}
}


/// Reserved 600 m wide shipping corridors connect every ruin and exit.
/// Validate the generated polygons before a caller commits sortie inventory.
fn validate_sea(islands:&[Vec<P>], ruins:&[Ruin]) -> E<()> {
    let start=P{x:2200.,y:2200.};
    let mut destinations:Vec<_>=ruins.iter().map(|r|r.p).collect();
    destinations.extend([P{x:2200.,y:2200.},P{x:22000.,y:2200.},P{x:2200.,y:12000.}]);
    for destination in destinations {
        let lane=if destination.y>4000. {7300.} else {2200.};
        let points=[start,P{x:2200.,y:lane},P{x:destination.x,y:lane},destination];
        for segment in points.windows(2) {
            let steps=(segment[0].dist(segment[1])/100.).ceil().max(1.) as u32;
            for i in 0..=steps {
                let p=segment[0]+(segment[1]-segment[0])*(f64::from(i)/f64::from(steps));
                if p.x<300. || p.x>WIDTH-300. || p.y<300. || p.y>HEIGHT-300.
                    || islands.iter().any(|poly| polygon_near(poly,p,300.)) {
                    return Err("海域生成失败：主航路未通过通行校验，出航物资未提交".into());
                }
            }
        }
    }
    Ok(())
}

pub(crate) fn polygon_near(poly:&[P],p:P,clearance:f64)->bool {
    let mut inside=false;
    for i in 0..poly.len() {
        let a=poly[i];let b=poly[(i+1)%poly.len()];
        if (a.y>p.y)!=(b.y>p.y) && p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x {inside=!inside;}
        let line=b-a;
        let t=if line.len()>0. {((p-a).dot(line)/(line.len()*line.len())).clamp(0.,1.)} else {0.};
        if (a+line*t).dist(p)<clearance {return true;}
    }
    inside
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Engine;
    fn start(count:usize)->Start {
        Start{content:VARIANT.into(),weather:None,fleet:["IBS-U-USN-FLETCHER","IBS-U-USN-PERKINS","IBS-U-USN-MAURY"]
            .iter().take(count).map(|id|Hull{id:(*id).into(),hp:100,ammo:100,level:1,equipment:false,command:false,..Default::default()}).collect(),..Default::default()}
    }
    fn call(e:&mut Engine,v:Value)->Value {
        let r=e.handle(v);assert_eq!(r["ok"],true,"{r}");r["data"].clone()
    }
    #[test]
    fn generated_corridors_and_seeded_streams_are_stable() {
        let mut prior=None;
        for seed in [0,1,2,42,6106,6111,u32::MAX] {
            let a=World::new_salvage(seed,start(3)).unwrap();
            let b=World::new_salvage(seed,start(3)).unwrap();
            assert_eq!(a.observation(0),b.observation(0));
            let battle=a.salvage.as_ref().unwrap();
            validate_sea(&a.islands,&battle.ruins).unwrap();
            assert_eq!(battle.ruins.len(),10);assert_eq!(battle.exits.len(),3);
            assert_eq!(battle.enemies.len(),battle.enemy_count);
            for ship in &a.ships {assert!(!a.islands.iter().any(|poly|polygon_near(poly,ship.p,150.)));}
            let terrain=json!(a.islands);
            if let Some(previous)=prior {assert_ne!(previous,terrain);}
            prior=Some(terrain);
            assert_eq!(a.observation(0)["salvage"]["ruins"].as_array().unwrap().len(),1);
        }
    }
    #[test]
    fn no_collection_before_range_speed_or_repeated_loot() {
        let mut w=World::new_salvage(6106,start(1)).unwrap();
        let cmd=json!({"op":"salvage_collect","ruin":1});
        assert!(w.external(cmd.clone()).is_err());
        w.ship_mut(1).unwrap().p=P{x:3700.,y:2200.};
        w.ship_mut(1).unwrap().speed=9.;assert!(w.external(cmd.clone()).is_err());
        w.ship_mut(1).unwrap().speed=0.;
        w.external(cmd.clone()).unwrap();
        for _ in 0..6 {w.tick+=1;w.advance_salvage();}
        w.external(cmd.clone()).unwrap();
        assert_eq!(w.salvage.as_ref().unwrap().collecting.unwrap().1,6);
        for _ in 0..6 {w.tick+=1;w.advance_salvage();}
        assert_eq!(w.salvage.as_ref().unwrap().cargo.len(),3);
        assert!(w.external(cmd).is_err());
    }
    #[test]
    fn damage_interrupts_collection_and_full_cargo_preserves_container() {
        let mut w=World::new_salvage(6106,start(1)).unwrap();
        w.ship_mut(1).unwrap().p=P{x:3700.,y:2200.};
        w.external(json!({"op":"salvage_collect","ruin":1})).unwrap();
        w.ship_mut(1).unwrap().hp-=1.;w.advance_salvage();
        assert!(w.salvage.as_ref().unwrap().collecting.is_none());
        let b=w.salvage.as_mut().unwrap();b.cargo=vec!["scrap".into();b.capacity];
        assert!(w.external(json!({"op":"salvage_collect","ruin":1})).is_err());
        assert_eq!(w.salvage.as_ref().unwrap().ruins[0].amount,3);
    }
    #[test]
    fn extraction_requires_all_navigable_hulls_and_protection_is_explicit() {
        let mut w=World::new_salvage(6106,start(3)).unwrap();
        w.ship_mut(3).unwrap().p=P{x:9000.,y:9000.};
        assert!(w.external(json!({"op":"salvage_extract","exit":0})).is_err());
        w.ship_mut(3).unwrap().speed_cap=Some(0.);w.advance_salvage();
        assert!(w.ship(3).unwrap().escaped);
        w.external(json!({"op":"salvage_extract","exit":0})).unwrap();
        for _ in 0..10 {w.tick+=1;w.advance_salvage();}
        w.external(json!({"op":"salvage_extract","exit":0})).unwrap();
        assert_eq!(w.salvage.as_ref().unwrap().extracting.unwrap().1,10);
        w.ship_mut(2).unwrap().p=P{x:9000.,y:9000.};w.advance_salvage();
        assert!(w.salvage.as_ref().unwrap().extracting.is_none());
        w.ship_mut(2).unwrap().hp=0.;w.advance_salvage();
        w.external(json!({"op":"salvage_extract","exit":0})).unwrap();
        for _ in 0..20 {w.tick+=1;w.advance_salvage();}
        assert_eq!(w.result.as_ref().unwrap().primary,Some(true));
        assert_eq!(w.salvage_view()["ships"][1]["protected"],true);
    }
    #[test]
    fn growth_changes_utility_score_without_changing_cas_ship_card() {
        let low=World::new_salvage(42,start(1)).unwrap();
        let mut upgraded=start(1);upgraded.fleet[0].level=30;upgraded.fleet[0].equipment=true;upgraded.fleet[0].command=true;
        let high=World::new_salvage(42,upgraded).unwrap();
        assert_eq!(format!("{:?}",low.data.ships),format!("{:?}",high.data.ships));
        let (a,b)=(low.salvage.unwrap(),high.salvage.unwrap());
        assert_eq!(b.score-a.score,580+75+50);assert_eq!(a.capacity,8);assert_eq!(b.capacity,10);
        assert_eq!(a.search_duration,12);assert_eq!(b.search_duration,4);
    }
    #[test]
    fn invalid_fleet_and_save_content_are_rejected() {
        let mut bad=start(1);bad.fleet[0].level=31;assert!(World::new_salvage(42,bad).is_err());
        let mut bad=start(1);bad.fleet.push(bad.fleet[0].clone());assert!(World::new_salvage(42,bad).is_err());
        let mut e=Engine::default();call(&mut e,json!({"op":"new_salvage","seed":42,"start":start(1)}));
        let mut save=call(&mut e,json!({"op":"save"}));save["salvage"]["content"]=json!("future-version");
        assert_eq!(e.handle(json!({"op":"load","save":save}))["ok"],false);
    }
    #[test]
    fn actual_navigation_collection_extraction_and_replay() {
        let mut e=Engine::default();
        call(&mut e,json!({"op":"new_salvage","seed":6106,"start":start(1)}));
        call(&mut e,json!({"op":"route","fleet":1,"mode":"follow","speed":6,"points":[{"x":3700,"y":2200}]}));
        call(&mut e,json!({"op":"step","seconds":490}));
        call(&mut e,json!({"op":"salvage_collect","ruin":1}));
        let halfway=call(&mut e,json!({"op":"step","seconds":6}));
        let save=call(&mut e,json!({"op":"save"}));
        assert_eq!(halfway,call(&mut e,json!({"op":"load","save":save})));
        let collected=call(&mut e,json!({"op":"step","seconds":6}));
        assert_eq!(collected["salvage"]["loot"]["scrap"],3);
        // The first ruin lies inside the west exit's 1000 m radius at x=3000.
        call(&mut e,json!({"op":"route","fleet":1,"mode":"follow","speed":6,
            "points":[{"x":4600,"y":3200},{"x":2600,"y":3200},{"x":2200,"y":2200}]}));
        let returned=call(&mut e,json!({"op":"step","seconds":1600}));
        assert!(returned["result"].is_null(),"{returned}");
        call(&mut e,json!({"op":"salvage_extract","exit":0}));
        let final_view=call(&mut e,json!({"op":"step","seconds":20}));
        assert_eq!(final_view["salvage"]["extracted"],true);
        let save=call(&mut e,json!({"op":"save"}));
        assert_eq!(final_view,call(&mut e,json!({"op":"replay","save":save})));
        assert_eq!(call(&mut e,json!({"op":"step","seconds":10})),final_view);
        assert_eq!(e.handle(json!({"op":"salvage_collect","ruin":1}))["ok"],false);
    }
    #[test]
    fn abandon_is_logged_and_replayable_and_all_protected_fails() {
        let mut e=Engine::default();call(&mut e,json!({"op":"new_salvage","seed":42,"start":start(1)}));
        let abandoned=call(&mut e,json!({"op":"salvage_abandon"}));
        let save=call(&mut e,json!({"op":"save"}));
        assert_eq!(abandoned,call(&mut e,json!({"op":"replay","save":save})));
        assert_eq!(abandoned["salvage"]["extracted"],false);assert!(!abandoned["result"].is_null());
        let mut w=World::new_salvage(42,start(1)).unwrap();w.ship_mut(1).unwrap().hp=0.;w.advance_salvage();
        assert_eq!(w.result.unwrap().primary,Some(false));
    }
    #[test]
    fn hull_projection_length_matches_registered_collision_clearance() {
        let w=World::new_salvage(6106,start(3)).unwrap();
        let view=w.observation(0);
        for own in view["ships"].as_array().unwrap() {
            let ship=w.ship(own["id"].as_u64().unwrap() as u32).unwrap();
            let length=w.data.ships[ship.def].length_m;
            assert_eq!(own["hullLengthM"],length.max(75.));
            assert_eq!(own["hullLengthSource"],if length>=75. {"registered"} else {"engine-clearance-default"});
        }
        for contact in view["contacts"].as_array().unwrap() {assert!(contact.get("hullLengthM").is_none());}
    }

    #[test]
    fn unused_supply_survives_discrete_torpedo_loading_rounding() {
        let mut supply=start(3);for hull in &mut supply.fleet {hull.ammo=60;}
        let w=World::new_salvage(6106,supply).unwrap();
        for hull in w.salvage_view()["ships"].as_array().unwrap() {assert_eq!(hull["ammo"],60);}
    }

    #[test]
    fn actual_main_gun_salvo_consumes_supply_and_stops_at_zero() {
        let mut supply=start(1);supply.fleet[0].ammo=1;
        let mut w=World::new_salvage(6106,supply).unwrap();
        w.ship_mut(2).unwrap().p=P{x:4200.,y:2200.};
        w.contacts[0].clear();
        w.contacts[0].push(Contact{id:"C01".into(),x:4200.,y:2200.,heading:270.,speed:0.,
            kind:Some("dd".into()),name:None,ship:2,first_cycle:0,acquisition_base_yd:0,acquisition_range_yd:0});
        w.external(json!({"op":"fire","ship":1,"weapon":"gun","target":"C01"})).unwrap();
        for _ in 0..60 {if w.result.is_none(){w.advance();}}
        assert_eq!(w.events.iter().filter(|e|e.kind=="gun" && e.own_ship==Some(1)).count(),1);
        assert_eq!(w.salvage_gun_supply(w.ship(1).unwrap()),0);
        assert_eq!(w.salvage_view()["ships"][0]["ammo"],0);
        assert!(w.external(json!({"op":"fire","ship":1,"weapon":"gun","target":"C01"})).is_err());
    }

    #[test]
    fn enemy_tasks_have_bounded_pursuit_without_new_contacts() {
        let mut w=World::new_salvage(42,start(1)).unwrap();
        for task in &mut w.salvage.as_mut().unwrap().enemies {
            task.chase_started=Some(1);task.last_contact=Some((P{x:2200.,y:2200.},1));
        }
        w.contacts[1].clear();w.tick=141;w.advance_salvage();
        for task in &w.salvage.as_ref().unwrap().enemies {assert!(task.last_contact.is_none());assert!(task.chase_started.is_none());}
    }
}

