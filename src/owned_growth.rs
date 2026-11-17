//! Small, versioned modifiers for owned hulls in fictional PvE only.
//! No registered ShipDef or historical scenario is modified.
use crate::{model::Ship, world::World};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub(crate) const VERSION: &str = "cas-owned-growth-v1";
pub(crate) fn gear_profile_valid(profile:&str)->bool { ["","fire_control","propulsion","bulkhead","balanced","ballistics"].contains(&profile) }

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Crew {
    pub primary: String,
    pub primary_bp: u32,
    pub secondary: String,
    pub secondary_bp: u32,
}

#[derive(Clone,Debug,Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub struct CampaignGrowth { pub version:String,pub hulls:Vec<crate::salvage::Hull> }

pub(crate) fn validate(crew: &BTreeMap<String,Crew>) -> bool {
    crew.iter().all(|(slot,item)| ["helmsman","gunnery","damage_control","command"].contains(&slot.as_str())
        && ["hp","speed","firepower","command"].contains(&item.primary.as_str())
        && ["hp","speed","firepower","command"].contains(&item.secondary.as_str())
        && item.primary_bp.saturating_add(item.secondary_bp)<=25)
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct Stats { pub hp:f64, pub speed:f64, pub firepower:f64, pub base_hit:f64, pub command:f64 }
impl Default for Stats {
    fn default()->Self { Self{hp:1.,speed:1.,firepower:1.,base_hit:1.,command:1.} }
}
impl Stats {
    pub(crate) fn from_hull(h:&crate::salvage::Hull)->Self {
        let level=0.05*f64::from(h.level)/30.;
        let gear=f64::from(h.equipment_bonus_bp)/10000.;
        let mut s=Self{hp:1.+level+gear,speed:1.+level+gear,firepower:1.+level+gear,
            base_hit:1.+0.10*f64::from(h.mastery)/1000.,command:0.35};
        if !h.equipment_profile.is_empty() {
            s.hp-=gear;s.speed-=gear;s.firepower-=gear;
            match h.equipment_profile.as_str() {
                "fire_control"=>s.base_hit+=gear,"propulsion"=>s.speed+=gear,"bulkhead"=>s.hp+=gear,
                "balanced"=>{s.hp+=gear*0.34;s.speed+=gear*0.33;s.firepower+=gear*0.33;},
                "ballistics"=>s.firepower+=gear,_=>()
            }
        }
        for item in h.crew.values() {
            for (stat,bp) in [(&item.primary,item.primary_bp),(&item.secondary,item.secondary_bp)] {
                let bonus=f64::from(bp)/10000.;
                match stat.as_str() { "hp"=>s.hp+=bonus,"speed"=>s.speed+=bonus,
                    "firepower"=>s.firepower+=bonus,"command"=>s.command+=bonus,_=>() }
            }
        }
        s
    }
}
impl World {
    pub(crate) fn apply_campaign_growth(&mut self)->crate::E<()> {
        let Some(growth)=self.campaign.as_ref().and_then(|s|s.owned_growth.clone()) else{return Ok(());};
        let start=self.campaign.as_ref().unwrap();
        if growth.version!=VERSION || start.difficulty!="story" || (start.fleet.is_none()&&start.groups.is_none()) {
            return Err("自有舰成长仅允许显式编成的战役演练，不改变历史预设".into());
        }
        let ids:std::collections::BTreeSet<_>=growth.hulls.iter().map(|h|h.id.as_str()).collect();
        let own:Vec<_>=self.ships.iter().filter(|s|s.side==self.player).collect();
        if ids.len()!=growth.hulls.len() || own.len()!=ids.len() || growth.hulls.iter().any(|h|h.level>30 || h.mastery>1000 || h.equipment_bonus_bp>100 || !gear_profile_valid(&h.equipment_profile) || !validate(&h.crew))
            || own.iter().any(|s|!s.character.as_ref().is_some_and(|id|ids.contains(id.as_str()))) {
            return Err("战役演练成长快照须逐舰匹配自有身份且词条合法".into());
        }
        self.owned_growth=self.ships.iter().map(|s|growth.hulls.iter().find(|h|Some(&h.id)==s.character.as_ref())
            .filter(|_|s.side==self.player).map(Stats::from_hull).unwrap_or_default()).collect();
        for (s,stats) in self.ships.iter_mut().zip(&self.owned_growth){s.hp*=stats.hp;}
        self.owned_practice=vec![0;self.ships.len()];
        Ok(())
    }
    pub(crate) fn advance_owned_practice(&mut self) {
        for s in &self.ships {
            if s.side==self.player && s.alive() && (s.speed>0.5 || s.gun_cycle==Some(self.tick/crate::model::CYCLE) || s.torp_cycle==Some(self.tick/crate::model::CYCLE)) {
                if let Some(value)=self.owned_practice.get_mut(s.id as usize-1){*value+=1;}
            }
        }
    }
    pub(crate) fn sync_chance(&self, fleet:u32, mode:&str)->Option<f64> {
        if mode!="sync" || !self.salvage.as_ref().is_some_and(|b|b.start.owned_growth==VERSION) {return None;}
        let f=self.fleets.iter().find(|f|f.id==fleet && f.side==0)?;
        self.ship(f.leader).map(|s|self.owned_stats(s).command)
    }
    pub(crate) fn owned_stats(&self, ship:&Ship)->Stats {
        self.owned_growth.get(ship.id as usize-1).copied().unwrap_or_default()
    }
    pub(crate) fn hull_max_hp(&self,ship:&Ship)->f64 { self.data.ships[ship.def].dp*self.owned_stats(ship).hp }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{model::*,salvage::{Start,Hull,Group,Mission,V2},world::roll};
    use serde_json::{json,Value};
    fn start()->Start {Start{content:V2.into(),owned_growth:super::VERSION.into(),fleet:vec![Hull{id:"IBS-U-USN-FLETCHER".into(),hp:100,ammo:100,..Default::default()}],..Default::default()}}
    fn close(a:f64,b:f64){assert!((a-b).abs()<1e-9,"{a} != {b}");}
    #[test]
    fn typed_equipment_has_one_percent_total_budget_and_preserves_legacy() {
        let mut hull=Hull{equipment_bonus_bp:100,level:0,..Default::default()};
        let legacy=Stats::from_hull(&hull);close(legacy.hp,1.01);close(legacy.speed,1.01);close(legacy.firepower,1.01);
        assert!(serde_json::to_value(&hull).unwrap().get("equipment_profile").is_none());
        for profile in ["fire_control","propulsion","bulkhead","balanced","ballistics"] {
            hull.equipment_profile=profile.into();let stats=Stats::from_hull(&hull);
            close((stats.hp-1.)+(stats.speed-1.)+(stats.firepower-1.)+(stats.base_hit-1.),0.01);
            if profile=="fire_control" {close(stats.base_hit,1.01);close(stats.speed,1.);}
            if profile=="propulsion" {close(stats.speed,1.01);close(stats.firepower,1.);}
        }
        let mut request=start();request.fleet[0].equipment_profile="unknown".into();
        assert!(World::new_salvage(42,request).is_err());
    }
    fn firing(mastered:bool)->World {
        let mut request=start();if mastered {request.fleet[0].mastery=1000;}
        let mut w=World::new_salvage(42,request).unwrap();w.islands.clear();
        for s in &mut w.ships{s.p=P{x:20000.,y:12000.};}
        w.ships[0].p=P{x:2200.,y:2200.};w.ships[0].h=0.;
        w.ships[1].p=P{x:7200.,y:2200.};w.ships[1].h=0.;w.ships[1].speed=15.;
        w.contacts[0]=vec![Contact{id:"C01".into(),ship:2,x:7200.,y:2200.,heading:0.,speed:15.,kind:None,name:None,first_cycle:0,acquisition_base_yd:0,acquisition_range_yd:0}];w.contacts[1].clear();w
    }
    #[test]
    fn owned_level_equipment_crew_caps_and_registered_cards_unchanged(){
        let low=World::new_salvage(42,start()).unwrap();let mut request=start();
        request.fleet[0].level=30;request.fleet[0].equipment_bonus_bp=100;
        for slot in ["helmsman","gunnery","damage_control","command"] {request.fleet[0].crew.insert(slot.into(),Crew{primary:"hp".into(),primary_bp:18,secondary:"speed".into(),secondary_bp:7});}
        let high=World::new_salvage(42,request.clone()).unwrap();
        close(high.ships[0].hp/low.ships[0].hp,1.0672);close(high.max_speed(&high.ships[0])/low.max_speed(&low.ships[0]),1.0628);
        close(high.owned_stats(&high.ships[0]).firepower,1.06);
        assert_eq!(format!("{:?}",low.data.ships),format!("{:?}",high.data.ships));
        assert_eq!(high.owned_stats(&high.ships[1]).hp,1.);
        request.fleet[0].crew.get_mut("command").unwrap().primary_bp=19;assert!(World::new_salvage(42,request).is_err());
        let mut bad=start();bad.fleet[0].mastery=1001;assert!(World::new_salvage(42,bad).is_err());
    }
    #[test]
    fn mastery_multiplies_base_term_not_final_chance_and_actual_fire_agrees(){
        let low=firing(false);let aim=json!({"ship":1,"weapon":"gun","target":"C01"});
        let baseline=low.preview_aim(0,&aim).unwrap()["chance"].as_f64().unwrap();
        for hit in [true,false] {
            let mut high=firing(true);let preview=high.preview_aim(0,&aim).unwrap();
            let chance=preview["chance"].as_f64().unwrap();
            let def=&high.data.ships[high.ships[0].def];let distance=5000./YARD;
            let band=def.gun.range_yd.iter().position(|&max|distance<=max).unwrap();
            let base=high.data.rules["gun_base_hit"][def.gun.gs.to_string()][band].as_f64().unwrap();
            close(chance-baseline,base*0.10);assert!((chance-baseline-10.).abs()>0.01);
            let barrels=preview["barrels"].as_u64().unwrap() as u32;
            high.ships[0].battery.hit_roll=Some(chance.floor() as u32+u32::from(!hit));
            high.fire_realtime_volleys(vec![crate::realtime::Volley{ship:1,contact:high.contacts[0][0].clone(),band,barrels,battery_barrels:barrels,radar_only:false,reload:4}]);
            high.tick+=crate::realtime::MAX_FLIGHT;high.advance_shells();assert_eq!(high.surface_damage[1].total>0.,hit);
        }
    }
    #[test]
    fn owned_artillery_damage_has_five_percent_level_difference(){
        let mut low=firing(false);let mut high=firing(false);high.owned_growth[0].firepower=1.05;
        let shot=|w:&mut World| {let aim=w.preview_aim(0,&json!({"ship":1,"weapon":"gun","target":"C01"})).unwrap();let barrels=aim["barrels"].as_u64().unwrap() as u32;
            let def=&w.data.ships[w.ships[0].def];let band=def.gun.range_yd.iter().position(|&r|5000./YARD<=r).unwrap();w.ships[0].battery.hit_roll=Some(1);
            w.fire_realtime_volleys(vec![crate::realtime::Volley{ship:1,contact:w.contacts[0][0].clone(),band,barrels,battery_barrels:barrels,radar_only:false,reload:4}]);w.tick+=crate::realtime::MAX_FLIGHT;w.advance_shells();w.surface_damage[1].total};
        let a=shot(&mut low);let b=shot(&mut high);assert!(a>0.);close(b/a,1.05);
    }
    #[test]
    fn unlimited_owned_groups_are_real_and_invalid_partition_rejected(){
        let mut request=start();let data=crate::ranked_fleets::data().unwrap();
        request.fleet=data.ships.iter().filter(|s|s.id.starts_with("IBS-U-USN-")).take(15).map(|s|Hull{id:s.id.clone(),hp:100,ammo:100,..Default::default()}).collect();
        request.groups=request.fleet.chunks(8).enumerate().map(|(i,h)|Group{id:i.to_string(),name:format!("group {i}"),ships:h.iter().map(|h|h.id.clone()).collect()}).collect();
        let mut w=World::new_salvage(42,request.clone()).unwrap();assert_eq!(w.fleets.iter().filter(|f|f.side==0).count(),2);assert_eq!(w.ships.iter().filter(|s|s.side==0).count(),15);
        for f in w.fleets.iter().filter(|f|f.side==0){assert!([7,8].contains(&f.members.len()));}
        for s in &w.ships {assert!(s.p.x>0. && s.p.x<w.field.width && s.p.y>0. && s.p.y<w.field.height);}
        for id in [1,2] {
            let p=w.ship(w.fleet(id).unwrap().leader).unwrap().p;
            w.external(json!({"op":"route","fleet":id,"mode":"follow","speed":6,"points":[{"x":p.x+1000.,"y":p.y}]})).unwrap();
        }
        let exit=w.salvage.as_ref().unwrap().exits[0];
        for s in w.ships.iter_mut().filter(|s|s.side==0){s.p=exit;s.track=None;s.speed=0.;}
        // Every navigable hull in every selected group must return, not just the first leader.
        w.ships[14].p.x=w.salvage.as_ref().unwrap().west_bounds.unwrap()[2]+1.;assert!(w.external(json!({"op":"salvage_extract","exit":0})).is_err());
        w.ships[14].p=exit;w.external(json!({"op":"salvage_extract","exit":0})).unwrap();
        request.groups[1].ships[0]=request.groups[0].ships[0].clone();assert!(World::new_salvage(42,request).is_err());
    }
    #[test]
    fn ladder_exact_registered_budget_and_win_requires_actual_enemy_destruction(){
        let points:Value=serde_json::from_str(include_str!("../data/rules/cas-competitive-points-v1.json")).unwrap();
        for budget in [1000,2000,3000,5000] {
            let mut request=start();request.mission=Some(Mission{kind:"ladder".into(),id:format!("ladder-{budget}"),player_budget:budget,enemy_budget:budget*3/2,loot_kind:"scrap".into()});
            let mut w=World::new_salvage(42,request).unwrap();
            let score:u64=w.ships.iter().filter(|s|s.side==1).map(|s|points["ships"][&w.data.ships[s.def].id]["points"].as_u64().unwrap()).sum();assert_eq!(score,u64::from(budget*3/2));
            assert!(w.external(json!({"op":"salvage_extract","exit":0})).is_err());w.advance_salvage();assert!(w.result.is_none());
            for s in &mut w.ships {if s.side==1{s.hp=0.;}}
            w.advance_salvage();assert_eq!(w.result.unwrap().primary,Some(true));
        }
    }
    #[test]
    fn command_failure_is_visible_keeps_route_and_replay_uses_independent_rng(){
        let mut outcomes=[false;2];
        for seed in 0..40 {
            let mut w=World::new_salvage(seed,start()).unwrap();let rng=(w.rng,w.optics_rng,w.surface_critical_rng);
            let command=json!({"op":"route","fleet":1,"mode":"sync","speed":6,"points":[{"x":3000,"y":2200}]});
            let preview=w.preview(0,&command).unwrap();assert_eq!(preview["executionChance"],0.35);
            let mut copy=w.salvage.as_ref().unwrap().command_rng;let success=roll(&mut copy,10000)<=3500;
            w.external(command.clone()).unwrap();outcomes[usize::from(success)]=true;
            assert_eq!(w.ships[0].track.is_some(),success);assert_eq!(w.events.iter().any(|e|e.kind=="command_failed"),!success);
            assert_eq!((w.rng,w.optics_rng,w.surface_critical_rng),rng);assert!(w.external(command).is_err());
            let restored=World::from_save(w.save(),w.tick).unwrap();assert_eq!(restored.observation(0),w.observation(0));
        }
        assert_eq!(outcomes,[true,true]);
    }
    #[test]
    fn owned_campaign_snapshot_replays_without_modifying_historical_or_enemy_force(){
        use crate::campaign::live::{Start as CampaignStart,GroupPick};
        let mut request=CampaignStart::new("CAMP-ALLIES-02","story");
        request.groups=Some(vec![GroupPick{position:0,ships:vec!["IBS-U-USN-FLETCHER".into()]}]);
        let plain=World::new_campaign(42,request.clone(),"coord").unwrap();
        let mut hull=start().fleet.remove(0);hull.level=30;hull.mastery=1000;
        request.owned_growth=Some(CampaignGrowth{version:super::VERSION.into(),hulls:vec![hull]});
        let mut grown=World::new_campaign(42,request.clone(),"coord").unwrap();
        for (a,b) in plain.ships.iter().zip(&grown.ships){assert_eq!((a.p,a.h,a.speed),(b.p,b.h,b.speed));close(b.hp/a.hp,if a.side==plain.player{1.05}else{1.});}
        assert_eq!(format!("{:?}",plain.data.ships),format!("{:?}",grown.data.ships));
        for _ in 0..60{grown.advance();}
        assert!(grown.observation(0)["ownedGrowth"]["ships"][0]["practice"].as_u64().unwrap()>0);
        assert_eq!(World::from_save(grown.save(),grown.tick).unwrap().observation(0),grown.observation(0));
        let historical=World::new_campaign(42,CampaignStart::new("CAMP-ALLIES-02","standard"),"coord").unwrap();assert!(historical.owned_growth.is_empty());
        request.difficulty="standard".into();assert!(World::new_campaign(42,request,"coord").is_err());
    }
    #[test]
    fn mastery_requires_real_simulated_participation_and_resource_loop_replays(){
        let mut request=start();request.mission=Some(Mission{kind:"resources".into(),id:"equipment".into(),player_budget:0,enemy_budget:0,loot_kind:"equipment".into()});
        let mut w=World::new_salvage(42,request).unwrap();for _ in 0..30{w.advance();}
        assert_eq!(w.salvage_view()["ships"][0]["practice"],0);
        w.external(json!({"op":"route","fleet":1,"mode":"follow","speed":6,"points":[{"x":3000,"y":2200}]})).unwrap();
        for _ in 0..60{w.advance();}
        assert!(w.salvage_view()["ships"][0]["practice"].as_u64().unwrap()>=1);
        w.external(json!({"op":"salvage_collect","ruin":1})).unwrap();for _ in 0..6{w.advance();}
        assert_eq!(w.salvage_view()["loot"]["equipment"],1);
        w.external(json!({"op":"salvage_extract","exit":0})).unwrap();for _ in 0..12{w.advance();}
        assert_eq!(w.result.as_ref().unwrap().primary,Some(true));
        assert_eq!(World::from_save(w.save(),w.tick).unwrap().observation(0),w.observation(0));
    }
}
