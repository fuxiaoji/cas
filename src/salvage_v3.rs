//! Authored water-world PvE. These are fictional creature parameters, not CAS
//! ship records. Frozen v1/v2 never load this data, RNG or mission state.
use crate::{model::*,salvage::{self,Start,Hull,Mission},world::{World,roll}};
use serde::Deserialize;
use serde_json::{json,Value};
use std::{collections::BTreeSet,sync::OnceLock};
pub const VERSION:&str="salvage-v3";
pub const CHAPTER:&str="chapter-01-v1";
const RULE:&str="CAS-FICTION-SEA-01";
#[derive(Clone,Debug,Deserialize)]
struct Species {id:String,name:String,hp:f64,speed_knots:f64,length_m:f64,attack_range_m:f64,radius_m:f64,damage:f64,warning_seconds:u32,cooldown_seconds:u32}
fn species()->&'static Vec<Species> {
    static DATA:OnceLock<Vec<Species>>=OnceLock::new();
    DATA.get_or_init(||serde_json::from_value(serde_json::from_str::<Value>(include_str!("../data/salvage/creatures-v3.json")).unwrap()["species"].clone()).unwrap())
}
fn extra_species()->&'static Vec<Species>{static S:OnceLock<Vec<Species>>=OnceLock::new();S.get_or_init(||serde_json::from_value(json!([
    {"id":"rust_crab","name":"锈壳采掘蟹","hp":320,"speed_knots":7,"length_m":90,"attack_range_m":1800,"radius_m":210,"damage":18,"warning_seconds":6,"cooldown_seconds":18},
    {"id":"cult_ray","name":"祭潮鳐","hp":170,"speed_knots":14,"length_m":95,"attack_range_m":4000,"radius_m":190,"damage":14,"warning_seconds":6,"cooldown_seconds":16}])).unwrap())}
fn spec(id:&str)->&'static Species {species().iter().chain(extra_species()).find(|s|s.id==id).unwrap()}
fn attack_window(id:&str,phase:u32)->u32 {match id{"rust_crab"|"cult_ray"=>6,"scavenger"=>4,"aversion"=>5,"spitter"=>6,"warden"=>7,_=>if phase>=2{6}else{8}}}
fn attack_cooldown(id:&str,phase:u32)->u32 {match id{"rust_crab"=>18,"cult_ray"=>16,"scavenger"=>12,"aversion"=>14,"spitter"=>16,"warden"=>18,_=>if phase>=2{16}else{20}}}
fn attack_read(id:&str,phase:u32)->(&'static str,&'static str,&'static str){match id{
    "scavenger"=>("rush","直线扑击","横向驶离长条预警"),
    "aversion"=>("rush","憎恶突进","领舰不会被选中；带其他舰横向闪避"),
    "spitter"=>("pulse","腐蚀喷吐","离开圆形落点，不要原地停泊"),
    "warden"=>("pulse","礁脊震荡","拉开队形，避开较大的圆形震荡"),
    "rust_crab"=>("rush","锈壳掘击","横移离开长条，穿甲弹更有效"),
    "cult_ray"=>("pulse","祭潮喷流","驶离落点，高爆弹更有效"),
    _=>if phase>=3{("barrage","三重深渊","多个落点同时锁定，向侧翼水道撤开")}else{("pulse","深渊潮汐","先离开落点，再集中炮击；破环后注意援兽")}
}}
pub(crate) fn data()->E<&'static Data> {
    static DATA:OnceLock<E<Data>>=OnceLock::new();
    DATA.get_or_init(||{
        let mut data=crate::ranked_fleets::data()?.clone();
        for s in species() {
            let def:ShipDef=serde_json::from_value(json!({"id":format!("CAS-FICTION-{}",s.id),"name":s.name,
                "side":"axis","kind":if s.id=="aversion"{"aberrant"}else{"monster"},"size":if s.id=="leviathan"{"A"}else{"C"},
                "max_knots":s.speed_knots,"dp":s.hp,"turn_advance_yards":100,"speed_loss_knots":0,"accel_knots_per_turn":30,
                "gun":{"name":"无舰炮 · 原创生物攻击","range_yd":[0,0,0,0],"damage":[0,0,0,0],"barrels":0,"gs":0,"mounts":[],"pen_belt":[null,null,null,null],"pen_deck":[null,null,null,null],"armor_piercing":false},
                "torpedo":null,"length_m":s.length_m,"armor_belt":0,"armor_deck":0,"in_service_year":0,"accel_high_knots_per_turn":30,"brake_knots_per_turn":60})).map_err(|e|e.to_string())?;
            data.ships.push(def);
        }Ok(data)
    }).as_ref().map_err(Clone::clone)
}
pub(crate) fn expedition_data()->E<&'static Data>{static D:OnceLock<E<Data>>=OnceLock::new();D.get_or_init(||{
    let mut d=data()?.clone();let base=d.ships.iter().find(|s|s.id=="CAS-FICTION-scavenger").unwrap().clone();
    for s in extra_species(){let mut def=base.clone();def.id=format!("CAS-FICTION-{}",s.id);def.name=s.name.clone();def.dp=s.hp;def.max_knots=s.speed_knots;def.length_m=s.length_m;def.armor_belt=if s.id=="rust_crab"{2.}else{0.};d.ships.push(def);}Ok(d)
}).as_ref().map_err(Clone::clone)}
pub(crate) fn chapter_start(id:&str)->E<Start> {
    if !["c1-breakout","c1-salvage","c1-boss","c2-convoy","c2-relay","c2-warden","c3-crossing","c3-core","c3-breaker"].contains(&id){return Err("章节实战不存在".into());}
    Ok(Start{content:VERSION.into(),chapter_version:if id.starts_with("c2-"){"chapter-02-v1"}else if id.starts_with("c3-"){"chapter-03-v1"}else{CHAPTER}.into(),weather:Some(crate::salvage_weather::VERSION.into()),
        fleet:["FLETCHER","PERKINS","MAURY","DRAYTON","LAMSON"].iter().map(|id|Hull{id:format!("IBS-U-USN-{id}"),hp:100,ammo:100,level:0,..Default::default()}).collect(),
        mission:Some(Mission{kind:"chapter".into(),id:id.into(),player_budget:0,enemy_budget:0,loot_kind:"scrap".into()}),..Default::default()})
}
pub(crate) fn validate_start(start:&Start)->E<()> {
    if !start.chapter_profile.is_empty(){return crate::story_missions::validate(start);}
    let chapter=start.mission.as_ref().is_some_and(|m|m.kind=="chapter");
    if chapter {
        let expected=chapter_start(&start.mission.as_ref().unwrap().id)?;
        if start.content!=VERSION || start.chapter_version!=expected.chapter_version || !start.owned_growth.is_empty()
            || !start.groups.is_empty() || serde_json::to_value(&start.fleet).unwrap()!=serde_json::to_value(expected.fleet).unwrap() {
            return Err("章节须使用登记的第五驱逐小队与冻结章节版本".into());
        }
    }else if !start.chapter_version.is_empty(){return Err("非章节行动不得携带章节版本".into());}
    Ok(())
}
#[derive(Clone,Debug)]
struct Creature {ship:u32,species:String,phase:u32,next_attack:u32,summoned:bool}
#[derive(Clone,Debug)]
struct Warning {id:u32,source:u32,kind:&'static str,p:P,origin:P,radius:f64,damage:f64,start:u32,impact:u32,spares:u32}
#[derive(Clone,Debug,Default)]
pub(crate) struct Ecology {pub(crate) theme:String,pub(crate) landmarks:Vec<Value>,pub(crate) layout:String,creatures:Vec<Creature>,warnings:Vec<Warning>,next_warning:u32,pub(crate) events:BTreeSet<String>,pub(crate) beacon:Option<P>}

/// Bounded procedural shapes occupy the same certified cells, keeping the
/// continuous shipping lanes. City blocks are real collision islands; their
/// inset building footprints cannot extend into otherwise passable water.
pub(crate) fn terrain(w:&mut World,seed:u32,start:&Start,offset:f64)->E<()> {
    let theme=if [crate::expedition::VERSION,crate::amphibious_expedition::VERSION].contains(&start.gameplay_profile.as_str()){match start.expedition_v2.as_ref().unwrap().scene.as_str(){"sunken_metropolis"=>"drowned_city","cult_relay"=>"fractured","thermal_vent"=>"atoll",_=>"fjord"}}else if let Some(c)=&start.cargo_v4{c.environment.as_str()}else if start.mission.as_ref().is_some_and(|m|m.kind=="chapter"){match start.mission.as_ref().unwrap().id.as_str(){"c1-breakout"|"c3-core"=>"fractured","c1-salvage"|"c2-relay"=>"drowned_city","c2-warden"|"c3-breaker"=>"atoll",_=>"fjord"}}else{["atoll","fractured","fjord","drowned_city"][(seed%4) as usize]};
    let mut rng=u64::from(seed)^0x5824_f53a_c913;
    let mut eco=Ecology{theme:theme.into(),..Default::default()};
    w.islands.clear();
    let mut shapes:Vec<Vec<P>>=vec![];
    let jitter=|rng:&mut u64,span:u32|roll(rng,span) as f64-span as f64/2.;
    let rock=|rng:&mut u64,c:P,rx:f64,ry:f64|->Vec<P>{(0..11).map(|k|{let a=k as f64*std::f64::consts::TAU/11.;let r=0.82+roll(rng,18) as f64/100.;c+P{x:libm::cos(a)*rx*r,y:libm::sin(a)*ry*r}}).collect()};
    match theme {
        "atoll"=>{
            // Real annular coral segments: center lagoon and the omitted east
            // sector are water in the authority, not painted water over land.
            for anchor in [P{x:7600.,y:4900.},P{x:15000.,y:10300.},P{x:20200.,y:4900.}] {
                let c=anchor+P{x:jitter(&mut rng,700),y:jitter(&mut rng,300)};
                let radius=1000.+roll(&mut rng,160) as f64;
                for j in 1..8 {
                    let a=j as f64*std::f64::consts::TAU/8.;let da:f64=0.30;
                    let mut segment=vec![];
                    for k in 0..6 {let angle=a-da+2.*da*k as f64/5.;segment.push(c+P::bearing(angle.to_degrees())*(radius-180.+jitter(&mut rng,24)));}
                    for k in (0..6).rev() {let angle=a-da+2.*da*k as f64/5.;segment.push(c+P::bearing(angle.to_degrees())*(radius+150.+jitter(&mut rng,30)));}
                    shapes.push(segment);
                }
            }
        },
        "fjord"=>{
            // Broad shore masses with alternating headlands create a sinuous
            // real channel, retaining the guaranteed central shipping lane.
            for (x,y,upper) in [(5700.,4300.,true),(14500.,4300.,true),(7400.,10500.,false),(16100.,10500.,false)] {
                let x=x+jitter(&mut rng,450);let mut edge=vec![];
                for k in 0..6 {edge.push(P{x:x+k as f64*1000.,y:if upper{5900.+roll(&mut rng,650) as f64}else{8200.+roll(&mut rng,650) as f64}});}
                if upper {edge.extend([P{x:x+5000.,y:y-200.},P{x,y:y-500.}]);}else{edge.extend([P{x:x+5000.,y:y+1500.},P{x,y:y+900.}]);}
                shapes.push(edge);
            }
        },
        "fractured"=>{
            for (i,anchor) in [P{x:7200.,y:5000.},P{x:17000.,y:5100.},P{x:10400.,y:10600.},P{x:19500.,y:10500.}].iter().enumerate() {
                let c=*anchor+P{x:jitter(&mut rng,900),y:jitter(&mut rng,250)};
                shapes.push(rock(&mut rng,c,if i%2==0{1050.}else{690.},800.));
                for j in 0..3 {let p=c+P{x:if j==0{-1700.}else{1400.+j as f64*450.},y:if j%2==0{-300.}else{650.}};shapes.push(rock(&mut rng,p,220.+j as f64*70.,160.+j as f64*40.));}
            }
        },
        _=>{
            // Two sunken urban districts, unequal street blocks, occasional
            // surviving hills. Physical canals separate every building base.
            for (district,anchor) in [P{x:8500.,y:4900.},P{x:17600.,y:10400.}].iter().enumerate() {
                let c=*anchor+P{x:jitter(&mut rng,1200),y:jitter(&mut rng,250)};
                shapes.push(rock(&mut rng,c+P{x:-2400.,y:300.},750.,650.));
                let count=9+roll(&mut rng,4) as usize;
                for j in 0..count {
                    let center=c+P{x:(j%4) as f64*950.-900.+jitter(&mut rng,140),y:(j/4) as f64*620.-620.+jitter(&mut rng,120)};
                    let rx=150.+roll(&mut rng,140) as f64;let ry=130.+roll(&mut rng,80) as f64;
                    let skew=if (j+district)%3==0{100.}else{0.};
                    shapes.push(vec![center+P{x:-rx+skew,y:-ry},center+P{x:rx,y:-ry},center+P{x:rx-skew,y:ry},center+P{x:-rx,y:ry}]);
                }
            }
        }
    }
    for (index,polygon) in shapes.into_iter().enumerate() {
        let center=polygon.iter().copied().fold(P::default(),|a,b|a+b)*(1./polygon.len() as f64);
        let place=match theme {"drowned_city"=>polygon.len()==4,"atoll"=>index%7==3,"fractured"=>index%4==0,_=>true};
        if place {
            let kind=if theme=="drowned_city"{["drowned_tower","industrial_ruin","flooded_dock"][index%3]}
                else{["radio_mast","cult_pylon","industrial_ruin","drowned_tower","flooded_dock"][(index+seed as usize)%5]};
            let scale=if theme=="fjord"{0.10}else{0.55};
            let footprint:Vec<_>=polygon.iter().map(|p|center+(*p-center)*scale).collect();
            if footprint.iter().all(|p|salvage::polygon_near(&polygon,*p,0.)) {
                let footprint:Vec<_>=footprint.into_iter().map(|p|p+P{x:offset,y:0.}).collect();
                eco.landmarks.push(json!({"id":index+1,"kind":kind,"x":center.x+offset,"y":center.y,"seed":roll(&mut rng,u32::MAX),
                    "island_index":index,"height_m":if kind=="drowned_tower"{90+roll(&mut rng,80)}else{20+roll(&mut rng,45)},"flood":0.35+roll(&mut rng,40) as f64/100.,
                    "footprint":footprint,"charted":true,"collision":"island"}));
            }
        }
        w.islands.push(polygon);
    }
    w.ecology=Some(eco);Ok(())
}
impl World {
    pub(crate) fn creature_intelligence(&self,id:u32)->Option<Value>{let eco=self.ecology.as_ref()?;let c=eco.creatures.iter().find(|c|c.ship==id)?;let s=spec(&c.species);Some(json!({"speed_max":s.speed_knots,"attack_damage":s.damage,"attack_range":s.attack_range_m,"attack_cooldown":if self.adventure(){attack_cooldown(&c.species,c.phase)}else{s.cooldown_seconds},"armor":if c.species=="rust_crab"{2}else{0},"weaknesses":attack_read(&c.species,c.phase).2,"warning_seconds":if self.adventure(){attack_window(&c.species,c.phase)}else{s.warning_seconds}}))}
    pub(crate) fn add_expedition_creature(&mut self,kind:&str,p:P)->E<u32>{let id=self.spawn_creature(kind,p)?;self.ecology.as_mut().unwrap().creatures.push(Creature{ship:id,species:kind.into(),phase:1,next_attack:self.tick+6,summoned:false});Ok(id)}
    fn spawn_creature(&mut self,species:&str,p:P)->E<u32> {
        let d=self.data.ships.iter().position(|d|d.id==format!("CAS-FICTION-{species}")).ok_or("怪物配置不存在")?;
        let fleet=self.fleets.iter().map(|f|f.id).max().unwrap_or(0)+1;
        let id=self.spawn(d,1,fleet,spec(species).name.clone(),p,270.)?;
        self.fleets.push(salvage::exploration_fleet(fleet,1,vec![id],&spec(species).name,true));
        self.owned_growth.resize(self.ships.len(),Default::default());
        if let Some(b)=&mut self.salvage {b.practice.resize(self.ships.len(),0);}
        Ok(id)
    }
    pub(crate) fn init_ecology(&mut self,offset:f64)->E<()> {
        let mission=self.salvage.as_ref().unwrap().start.mission.clone();
        if mission.as_ref().is_some_and(|m|m.kind=="ladder"){return Ok(());}
        let chapter=mission.as_ref().filter(|m|m.kind=="chapter").map(|m|m.id.as_str());
        let mut eco=self.ecology.take().unwrap();
        let mut list:Vec<(&str,P)>=match chapter {
            Some("c1-breakout")|Some("c2-convoy")|Some("c3-crossing")=>vec![("aversion",P{x:4300.+offset,y:3000.}),("scavenger",P{x:6100.+offset,y:2800.}),("spitter",P{x:7800.+offset,y:3300.})],
            Some("c1-salvage")|Some("c2-relay")|Some("c3-core")=>vec![("scavenger",P{x:6800.+offset,y:3000.}),("spitter",P{x:8400.+offset,y:3400.}),("warden",P{x:10000.+offset,y:2800.})],
            Some("c2-warden")=>vec![("warden",P{x:6900.+offset,y:2800.}),("spitter",P{x:8500.+offset,y:3600.})],
            Some("c1-boss")|Some("c3-breaker")=>vec![("leviathan",P{x:7600.+offset,y:3200.})],
            _=>(0..7).map(|i|(["scavenger","spitter","warden","scavenger","spitter","warden","leviathan"][i],P{x:if i==6{18800.+offset}else{7800.+offset+(i%3) as f64*3900.},y:if i<3{3000.}else{7800.}})).collect()
        };
        // New fictional resource tiers preserve all frozen mission ecologies.
        if let Some(m)=mission.as_ref().filter(|m|m.kind=="resources") {
            if ["silver-t2","training-t2","equipment-t2","crew-t2"].contains(&m.id.as_str()) {
                list.extend([("warden",P{x:5200.+offset,y:3000.}),("spitter",P{x:6200.+offset,y:3500.})]);
            } else if ["silver-t3","training-t3","equipment-t3","crew-t3"].contains(&m.id.as_str()) {
                list.extend([("warden",P{x:4400.+offset,y:3000.}),("spitter",P{x:5300.+offset,y:2900.}),("leviathan",P{x:6700.+offset,y:3400.}),("scavenger",P{x:6000.+offset,y:4100.})]);
            }
        }
        if let Some(c)=&self.salvage.as_ref().unwrap().start.cargo_v4 {
            if c.difficulty=="calm" {list=vec![("scavenger",P{x:6500.+offset,y:3300.}),("scavenger",P{x:10000.+offset,y:7800.}),("spitter",P{x:12500.+offset,y:6500.})];}
            else if c.difficulty=="hazard" {list.extend([("warden",P{x:4500.+offset,y:3600.}),("spitter",P{x:5700.+offset,y:3200.}),("scavenger",P{x:8000.+offset,y:4400.}),("leviathan",P{x:16800.+offset,y:9800.})]);}
        }
        if self.expedition_v2(){let count=match self.salvage.as_ref().unwrap().start.cargo_v4.as_ref().unwrap().difficulty.as_str(){"calm"=>3,"standard"=>4,_=>5};list.truncate(count);list[0].0="rust_crab";list[1].0="cult_ray";if self.salvage.as_ref().unwrap().start.expedition_v2.as_ref().unwrap().scene=="thermal_vent"&&count>3{list[3].0="rust_crab";}}
        if crate::story_missions::active(&self.salvage.as_ref().unwrap().start){list=crate::story_missions::creatures(chapter.unwrap(),offset)?;}
        for (kind,p) in list {let ship=self.spawn_creature(kind,p)?;eco.creatures.push(Creature{ship,species:kind.into(),phase:1,next_attack:if self.adventure(){6}else{30},summoned:false});}
        let b=self.salvage.as_mut().unwrap();b.enemy_count=eco.creatures.len();
        if let Some(m)=mission.as_ref().filter(|m|m.kind=="resources") {
            if ["silver-t2","training-t2","equipment-t2","crew-t2"].contains(&m.id.as_str()) {
                b.ruins[0].p=P{x:4800.+offset,y:2200.};
                b.exits[0]=P{x:4800.+offset,y:2200.};b.west_bounds=Some([4000.+offset,1700.,5600.+offset,2700.]);
            } else if ["silver-t3","training-t3","equipment-t3","crew-t3"].contains(&m.id.as_str()) {
                b.ruins[0].p=P{x:5800.+offset,y:2200.};
                b.exits[0]=P{x:5800.+offset,y:2200.};b.west_bounds=Some([5000.+offset,1700.,6600.+offset,2700.]);
            }
        }
        if let Some(id)=chapter {
            if ["c3-crossing","c2-warden"].contains(&id){b.weather=Some(crate::salvage_weather::Timeline::authored(self.seed,if id=="c3-crossing"{"rain"}else{"fog"}));}
            b.capacity=12;
            if ["c1-breakout","c2-convoy","c3-crossing"].contains(&id) {
                let beacon=P{x:6200.+offset,y:2200.};eco.beacon=Some(beacon);
                b.exits[0]=beacon;b.west_bounds=Some([beacon.x-2300.,1200.,beacon.x+600.,3400.]);
            }else if ["c1-salvage","c2-relay","c3-core"].contains(&id) {
                b.ruins[0].p=P{x:5500.+offset,y:2200.};b.ruins[0].kind="archive".into();b.ruins[0].amount=1;
                let end=P{x:6500.+offset,y:2200.};b.exits[0]=end;b.west_bounds=Some([end.x-2300.,1200.,end.x+600.,3400.]);
            }
        }
        self.ecology=Some(eco);Ok(())
    }
    pub(crate) fn chapter_exit_blocker(&self)->Option<&'static str> {
        if self.story_mission(){return self.story_exit_blocker();}
        let b=self.salvage.as_ref()?;
        if b.start.content==VERSION && b.start.mission.as_ref().is_some_and(|m|m.kind=="resources" && ["silver-t2","training-t2","equipment-t2","crew-t2","silver-t3","training-t3","equipment-t3","crew-t3"].contains(&m.id.as_str())) && b.cargo.is_empty(){return Some("先从遗迹装载物资，再到接驳点撤离");}
        let m=b.start.mission.as_ref().filter(|m|m.kind=="chapter")?;
        let events=&self.ecology.as_ref()?.events;
        if m.id=="c2-convoy"&&self.ships.iter().any(|s|s.side==0&&!s.alive()){return Some("护航小队必须全员存活抵达");}
        match m.id.as_str(){"c1-breakout"|"c2-convoy"|"c3-crossing" if !events.contains("beacon_reached")=>Some("先抵达突破信标，再带领小队集结撤离"),"c1-salvage"|"c2-relay"|"c3-core" if !b.cargo.iter().any(|s|s=="archive")=>Some("须实际收回旧信标档案才能完成本关"),"c1-boss"=>Some("须击败开门派控制的渊喉"),"c2-warden"|"c3-breaker"=>Some("须击败此海域的拜教控制实体"),_=>None}
    }
    pub(crate) fn advance_ecology(&mut self) {
        if self.result.is_some(){return;}
        let Some(mut eco)=self.ecology.take() else{return};
        let adventure=self.adventure();
        // Damage uses true positions only at impact, never to retarget a warning.
        let due:Vec<_>=eco.warnings.iter().filter(|w|w.impact<=self.tick).cloned().collect();
        eco.warnings.retain(|w|w.impact>self.tick && self.ship(w.source).is_some_and(|s|s.alive()));
        for warning in due {
            if !self.ship(warning.source).is_some_and(|s|s.alive()){continue;}
            let hits:Vec<_>=self.ships.iter().filter(|s|s.side==0&&s.alive()&&s.id!=warning.spares
                && (if adventure&&warning.kind=="rush" {crate::adventure::segment_distance(s.p,warning.origin,warning.p)}else{s.p.dist(warning.p)})<=warning.radius).map(|s|s.id).collect();
            for id in hits {
                let s=self.ship_mut(id).unwrap();s.hp=(s.hp-warning.damage).max(0.);let name=s.name.clone();let p=s.p;
                self.add(1,"creature_hit",format!("{name} 受到生物冲击 {:.0} 耐久",warning.damage),Some(RULE),Some(p));
            }
            self.add(1,"creature_impact","生物冲击已落下".into(),Some(RULE),Some(warning.p));
        }
        let known=self.contacts[1].clone();
        let mut summons=vec![];
        for creature in &mut eco.creatures {
            let Some(ship)=self.ship(creature.ship).filter(|s|s.alive())else{if creature.species=="leviathan"||creature.species=="warden"&&self.salvage.as_ref().is_some_and(|b|b.start.mission.as_ref().is_some_and(|m|m.id=="c2-warden")){eco.events.insert("boss_defeated".into());}continue;};
            let def=spec(&creature.species);let p=ship.p;let fleet=ship.fleet.unwrap();
            let phase=if creature.species=="leviathan"{if ship.hp/def.hp<=0.3{3}else if ship.hp/def.hp<=0.65{2}else{1}}else{1};
            creature.phase=phase;
            if phase>=2 && !creature.summoned {
                creature.summoned=true;eco.events.insert("gatekeepers_control_link".into());
                if self.contacts[0].iter().any(|c|c.ship==creature.ship) {self.add(1,"boss_phase",if adventure{"渊喉控制环过载，呼唤拾骸兽；注意连续落点"}else{"渊喉控制环过载，呼唤拾骸兽；冲击预警缩短至40秒"}.into(),Some(RULE),Some(p));}
                for dy in [-600.,600.] {let q=p+P{x:900.,y:dy};if self.field.contains(q)&&!self.islands.iter().any(|poly|salvage::polygon_near(poly,q,150.)){summons.push(q);}}
            }
            if creature.species=="aversion" && self.contacts[0].iter().any(|c|c.ship==creature.ship)
                && known.iter().any(|c|c.ship==1&&c.p().dist(p)<=def.attack_range_m) {
                if eco.events.insert("aversion_spared_flagship".into()){self.add(1,"aversion_spared_flagship","憎恶巡游者越过领舰，仍在追击其他队员".into(),Some(RULE),Some(p));}
            }
            let target=known.iter().filter(|c|creature.species!="aversion"||c.ship!=1).filter(|c|self.ship(c.ship).is_some_and(|s|s.alive()))
                .filter(|c|c.p().dist(p)<def.attack_range_m+3500.).min_by(|a,b|a.p().dist(p).total_cmp(&b.p().dist(p)));
            let Some(target)=target else{continue};
            if self.tick%if adventure{3}else{20}==1 && p.dist(target.p())>900.
                && (!adventure||!eco.warnings.iter().any(|w|w.source==creature.ship)) {
                let _=self.route(1,&json!({"fleet":fleet,"mode":"follow","speed":def.speed_knots,"points":[target.p()]}),false);
            }
            if self.tick>=creature.next_attack && p.dist(target.p())<=def.attack_range_m {
                let kind=if phase==3{"barrage"}else if ["scavenger","aversion","rust_crab"].contains(&creature.species.as_str()){"rush"}else{"pulse"};
                let centers=if phase==3{vec![target.p(),target.p()+P{x:380.,y:0.},target.p()+P{x:-380.,y:0.}]}else{vec![target.p()]};
                for center in centers {
                    // A fictional rush cannot cut through an island. Its public
                    // capsule and damage stop at the same last clear point.
                    let center=if adventure&&kind=="rush" {
                        let count=(p.dist(center)/60.).ceil().max(1.) as u32;let mut end=p;
                        for i in 1..=count{let q=p+(center-p)*(i as f64/count as f64);
                            if self.islands.iter().any(|poly|salvage::polygon_near(poly,q,def.radius_m)){break;}end=q;}
                        end
                    }else{center};
                    eco.next_warning+=1;eco.warnings.push(Warning{id:eco.next_warning,source:creature.ship,kind,p:center,origin:p,radius:def.radius_m,
                        damage:def.damage,start:self.tick,impact:self.tick+if adventure{attack_window(&creature.species,phase)}else if phase>=2{40}else{def.warning_seconds},spares:if creature.species=="aversion"{1}else{0}});
                }
                creature.next_attack=self.tick+if adventure{attack_cooldown(&creature.species,phase)}else if phase>=2{75}else{def.cooldown_seconds};
                if adventure {if let Some(f)=self.fleets.iter_mut().find(|f|f.id==fleet){f.actual=0.;}if let Some(s)=self.ship_mut(creature.ship){s.track=None;s.speed=0.;}}
                if self.contacts[0].iter().any(|c|c.ship==creature.ship) {self.add(1,"creature_warning",format!("{}：冲击预警，离开标记区域",def.name),Some(RULE),Some(target.p()));}
            }
        }
        for p in summons {if let Ok(ship)=self.spawn_creature("scavenger",p){eco.creatures.push(Creature{ship,species:"scavenger".into(),phase:1,next_attack:self.tick+45,summoned:false});}}
        if eco.beacon.is_some_and(|p|self.ships.iter().any(|s|s.side==0&&s.alive()&&s.p.dist(p)<650.)){eco.events.insert("beacon_reached".into());}
        if self.salvage.as_ref().is_some_and(|b|b.cargo.iter().any(|s|s=="archive")){eco.events.insert("archive_recovered".into());}
        let boss_win=self.salvage.as_ref().and_then(|b|b.start.mission.as_ref()).is_some_and(|m|m.kind=="chapter"&&["c1-boss","c2-warden","c3-breaker"].contains(&m.id.as_str()))&&eco.events.contains("boss_defeated");
        let convoy_lost=self.salvage.as_ref().is_some_and(|b|b.start.mission.as_ref().is_some_and(|m|m.id=="c2-convoy"))&&self.ships.iter().any(|s|s.side==0&&!s.alive());
        self.ecology=Some(eco);
        if boss_win && !self.story_mission(){self.finish_salvage(true);}
        if convoy_lost && !self.story_mission(){self.finish_salvage(false);}
    }
    pub(crate) fn ecology_view(&self,owner:usize,view:&mut Value) {
        let eco=self.ecology.as_ref().unwrap();
        view["salvage"]["generatorVersion"]=json!("archipelago-3");view["salvage"]["terrainTheme"]=json!(eco.theme);view["salvage"]["landmarks"]=json!(eco.landmarks);
        view["salvage"]["telegraphs"]=json!(eco.warnings.iter().filter_map(|w|self.contacts[owner].iter().find(|c|c.ship==w.source).map(|c|{
            let mut row=json!({"id":w.id,"kind":w.kind,"x":w.p.x,"y":w.p.y,"radius":w.radius,"start_tick":w.start,"impact_tick":w.impact,"source_contact":c.id});
            if self.adventure()||self.open_intel(){let cr=eco.creatures.iter().find(|cr|cr.ship==w.source).unwrap();let (_,name,counter)=attack_read(&cr.species,cr.phase);
                row["shape"]=json!(if w.kind=="rush"{"capsule"}else{"circle"});row["origin_x"]=json!(w.origin.x);row["origin_y"]=json!(w.origin.y);row["name"]=json!(name);row["counter"]=json!(counter);row["exempt_ship_id"]=if w.spares==0{Value::Null}else{json!(w.spares)};}
            row
        })).collect::<Vec<_>>());
        for (row,contact) in view["contacts"].as_array_mut().unwrap().iter_mut().zip(&self.contacts[owner]) {
            if let Some(creature)=eco.creatures.iter().find(|c|c.ship==contact.ship) {
                let def=spec(&creature.species);let ship=self.ship(creature.ship).unwrap();
                row["entityKind"]=json!(if creature.species=="aversion"{"aberrant"}else{"monster"});row["species"]=json!(creature.species);row["visualType"]=json!(creature.species);
                row["boss"]=json!(creature.species=="leviathan"||creature.species=="warden"&&self.salvage.as_ref().unwrap().start.mission.as_ref().is_some_and(|m|m.id=="c2-warden"));row["health_fraction"]=json!((ship.hp/def.hp).clamp(0.,1.));row["phase"]=json!(creature.phase);row["name"]=json!(def.name);
                if self.adventure()||self.open_intel(){
                    let (kind,label,counter)=attack_read(&creature.species,creature.phase);
                    let warning=eco.warnings.iter().find(|w|w.source==creature.ship);
                    let state=if warning.is_some(){"windup"}else if self.tick<creature.next_attack{"recover"}else{"approach"};
                    let seconds=warning.map_or(creature.next_attack.saturating_sub(self.tick),|w|w.impact.saturating_sub(self.tick));
                    row["health"]=json!(ship.hp.max(0.));row["max_health"]=json!(def.hp);
                    row["attack"]=json!({"kind":kind,"label":label,"counter":counter,"state":state,"seconds":seconds,"radius":def.radius_m,"range":def.attack_range_m,"shape":if kind=="rush"{"capsule"}else{"circle"}});
                }
            }
        }
        if let Some(m)=self.salvage.as_ref().unwrap().start.mission.as_ref().filter(|m|m.kind=="chapter") {
            let won=self.result.as_ref().is_some_and(|r|r.winner=="allies"&&r.primary==Some(true));
            view["chapter"]=json!({"chapterId":if m.id.starts_with("c2-"){"chapter-02"}else if m.id.starts_with("c3-"){"chapter-03"}else{"chapter-01"},"chapterVersion":self.salvage.as_ref().unwrap().start.chapter_version,"stageId":m.id,"status":if self.result.is_none(){"active"}else if won{"won"}else{"lost"},"protagonistShipId":1,"events":eco.events,
                "objective":{"kind":match m.id.as_str(){"c1-breakout"|"c2-convoy"|"c3-crossing"=>"reach_and_extract","c1-salvage"|"c2-relay"|"c3-core"=>"archive_and_extract",_=>"defeat_boss"},"beacon":eco.beacon,"archiveRuinId":if ["c1-salvage","c2-relay","c3-core"].contains(&m.id.as_str()){Some(1)}else{None},"bossSpecies":if m.id=="c2-warden"{Some("warden")}else if ["c1-boss","c3-breaker"].contains(&m.id.as_str()){Some("leviathan")}else{None}}});
            view["scenario"]=json!(match m.id.as_str(){"c1-breakout"=>"返航灯 · 突破重围","c1-salvage"=>"返航灯 · 旧信标档案","c2-convoy"=>"盐线回声 · 护送流民","c2-relay"=>"盐线回声 · 沉城中继","c2-warden"=>"盐线回声 · 热泉守卫","c3-crossing"=>"逆潮灯火 · 风暴接应","c3-core"=>"逆潮灯火 · 旧世核心","c3-breaker"=>"逆潮灯火 · 潮闸决战",_=>"返航灯 · 开门派"});
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn new_chapters_have_real_boss_targets_and_convoy_loss_condition() {
        for (id,version) in [("c2-convoy","chapter-02-v1"),("c2-relay","chapter-02-v1"),("c2-warden","chapter-02-v1"),("c3-crossing","chapter-03-v1"),("c3-core","chapter-03-v1"),("c3-breaker","chapter-03-v1")] {
            let mut s=chapter_start(id).unwrap();s.gameplay_profile=crate::adventure::VERSION.into();s.intel_profile=crate::intel::VERSION.into();
            let mut w=World::new_salvage(6109,s).unwrap();let v=w.observation(0);assert_eq!(v["chapter"]["chapterVersion"],version);
            if ["c2-warden","c3-breaker"].contains(&id){assert!(v["contacts"].as_array().unwrap().iter().any(|c|c["boss"]==true&&c["health"].as_f64().unwrap()>0.));}
            if id=="c2-convoy"{w.ship_mut(2).unwrap().hp=0.;w.advance_ecology();assert_eq!(w.result.as_ref().unwrap().primary,Some(false));}
        }
    }
    #[test]
    fn seeded_geometry_keeps_landmarks_and_all_initial_hulls_legal() {
        let mut fingerprints=BTreeSet::new();
        for seed in 0..100 {
            let mut start=chapter_start("c1-salvage").unwrap();start.mission=None;start.chapter_version.clear();
            let w=World::new_salvage(seed,start.clone()).unwrap();
            assert_eq!(w.islands,World::new_salvage(seed,start).unwrap().islands);
            fingerprints.insert(serde_json::to_string(&w.islands).unwrap());
            for s in &w.ships {assert!(w.field.contains(s.p));assert!(!w.islands.iter().any(|p|salvage::polygon_near(p,s.p,55.)));}
            for mark in &w.ecology.as_ref().unwrap().landmarks {
                let index=mark["island_index"].as_u64().unwrap() as usize;
                for point in mark["footprint"].as_array().unwrap() {
                    let p:P=serde_json::from_value(point.clone()).unwrap();assert!(salvage::polygon_near(&w.islands[index],p,0.));
                }
            }
        }
        assert_eq!(fingerprints.len(),100);
    }
    #[test]
    fn warnings_use_fixed_impact_space_and_aversion_spares_only_flagship() {
        let mut w=World::new_salvage(6109,chapter_start("c1-breakout").unwrap()).unwrap();
        let source=w.ecology.as_ref().unwrap().creatures.iter().find(|c|c.species=="aversion").unwrap().ship;
        let p=w.ship(1).unwrap().p;
        w.ship_mut(2).unwrap().p=p;
        let first=w.ship(1).unwrap().hp;let second=w.ship(2).unwrap().hp;
        w.ecology.as_mut().unwrap().warnings.push(Warning{id:1,source,kind:"rush",p,origin:p,radius:170.,damage:10.,start:0,impact:45,spares:1});
        w.tick=44;w.advance_ecology();assert_eq!(w.ship(2).unwrap().hp,second);
        w.tick=45;w.advance_ecology();assert_eq!(w.ship(1).unwrap().hp,first);assert_eq!(w.ship(2).unwrap().hp,second-10.);
        w.ecology.as_mut().unwrap().warnings.push(Warning{id:2,source,kind:"rush",p,origin:p,radius:170.,damage:10.,start:45,impact:90,spares:1});
        w.ship_mut(2).unwrap().p.x+=171.;w.tick=90;w.advance_ecology();assert_eq!(w.ship(2).unwrap().hp,second-10.);
    }
    #[test]
    fn monster_information_requires_a_real_visible_contact() {
        let mut w=World::new_salvage(6109,chapter_start("c1-boss").unwrap()).unwrap();
        w.tick=30;w.advance_ecology();
        assert!(!w.observation(0)["salvage"]["telegraphs"].as_array().unwrap().is_empty());
        w.contacts[0].clear();let view=w.observation(0);
        assert!(view["contacts"].as_array().unwrap().is_empty());assert!(view["salvage"]["telegraphs"].as_array().unwrap().is_empty());
        assert!(!view["salvage"].as_object().unwrap().contains_key("creatures"));
    }
    #[test]
    fn chapter_payload_cannot_replace_borrowed_roster_or_fake_version() {
        let mut start=chapter_start("c1-boss").unwrap();start.fleet[0].hp=1;assert!(World::new_salvage(42,start).is_err());
        let mut start=chapter_start("c1-boss").unwrap();start.content=salvage::V2.into();assert!(World::new_salvage(42,start).is_err());
        let mut start=chapter_start("c1-boss").unwrap();start.chapter_version="future".into();assert!(World::new_salvage(42,start).is_err());
    }
    #[test]
    fn adventure_rush_hits_fixed_capsule_and_can_be_dodged_perpendicularly() {
        let mut start=chapter_start("c1-breakout").unwrap();start.gameplay_profile=crate::adventure::VERSION.into();
        let mut w=World::new_salvage(6109,start).unwrap();
        let source=w.ecology.as_ref().unwrap().creatures[0].ship;
        let origin=P{x:4000.,y:2200.};let end=P{x:2200.,y:2200.};
        w.ship_mut(2).unwrap().p=P{x:3200.,y:2200.};w.ship_mut(3).unwrap().p=P{x:3200.,y:2371.};
        let hp2=w.ship(2).unwrap().hp;let hp3=w.ship(3).unwrap().hp;
        let hp1=w.ship(1).unwrap().hp;
        w.ecology.as_mut().unwrap().warnings.push(Warning{id:500,source,kind:"rush",p:end,origin,radius:170.,damage:10.,start:0,impact:4,spares:1});
        let v=w.observation(0);assert_eq!(v["salvage"]["telegraphs"].as_array().unwrap().iter().find(|t|t["id"]==500).unwrap()["exempt_ship_id"],1);
        w.tick=3;w.advance_ecology();assert_eq!(w.ship(2).unwrap().hp,hp2);
        // It does not follow the source or re-lock onto a moving target.
        w.ship_mut(source).unwrap().p.y+=1000.;w.tick=4;w.advance_ecology();
        assert_eq!(w.ship(1).unwrap().hp,hp1);assert_eq!(w.ship(2).unwrap().hp,hp2-10.);assert_eq!(w.ship(3).unwrap().hp,hp3);
    }
}


