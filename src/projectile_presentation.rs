//! Opt-in, own-seat visual data, separate from all authoritative observations
//! and saves. Reading this API cannot consume dice, advance clocks or commands.
use crate::{model::{P, Ship}, world::World};
use serde_json::{json, Value};

pub(crate) const VERSION: &str = "projectile-fx-v1";
const SECONDARY_RETENTION_SECONDS: u32 = 4;

#[derive(Default)]
pub(crate) struct Presentation {
    secondary_ids: [u64; 2],
    secondaries: Vec<Secondary>,
}

struct Secondary {
    id: u64,
    tick: u32,
    owner: usize,
    own_ship: u32,
    caliber_mm: f64,
    barrels: u32,
    from: P,
    to: P,
}

impl World {
    pub(crate) fn record_secondary_presentation(&mut self, ship: &Ship, caliber_mm: f64, barrels: u32, plot: P) {
        let fx = &mut self.projectile_fx;
        fx.secondaries.retain(|shot| self.tick.saturating_sub(shot.tick) <= SECONDARY_RETENTION_SECONDS);
        fx.secondary_ids[ship.side] += 1;
        fx.secondaries.push(Secondary {
            id:fx.secondary_ids[ship.side], tick:self.tick, owner:ship.side,
            own_ship:ship.id, caliber_mm, barrels, from:ship.p, to:plot,
        });
    }

    pub(crate) fn projectile_presentation(&self, owner: usize) -> Value {
        let mut shots = self.main_projectile_presentation(owner);
        shots.extend(self.projectile_fx.secondaries.iter()
            .filter(|shot| shot.owner == owner && self.tick.saturating_sub(shot.tick) <= SECONDARY_RETENTION_SECONDS)
            .map(|shot| json!({
                "id":format!("secondary:{}",shot.id), "tick":shot.tick,
                "own_ship":shot.own_ship, "battery":"secondary", "caliber_mm":shot.caliber_mm,
                "barrels":shot.barrels, "from":shot.from, "to":shot.to,
            })));
        json!({"version":VERSION,"tick":self.tick,"shots":shots})
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{model::{norm,YARD}, Engine};

    fn secondary_world(seed: u32) -> (World, u32, P) {
        let mut w = World::new(seed, 0, "coord", "night", "coord", 0).unwrap();
        w.enable_realtime().unwrap();
        for ship in &mut w.ships { ship.secondary_ready = u32::MAX; }
        let def = w.data.ships.iter().position(|d| d.id == "cleveland_empress").unwrap();
        let id = w.spawn(def, 0, 1, "Presentation Cleveland".into(), P { x:6000.,y:6000. }, 90.).unwrap();
        w.fleet_mut(1).unwrap().members.push(id);
        w.ship_mut(6).unwrap().p = P { x:6000. + 3000. * YARD, y:6000. };
        w.detect(true);
        w.contacts[0].retain(|c| c.ship == 6);
        // Deliberately stale/noisy public plot differs from the true hull.
        let plot = P { x:8750.,y:6125. };
        w.contacts[0][0].x=plot.x;
        w.contacts[0][0].y=plot.y;
        w.tick=1;
        (w,id,plot)
    }

    #[test]
    fn every_real_secondary_discharge_including_a_miss_uses_only_own_contact_plot() {
        let mut found_miss=false;
        for seed in 1..=64 {
            let (mut w,id,plot)=secondary_world(seed);
            let s=w.ship(id).unwrap().clone();
            let gun=w.data.ships[s.def].secondary.as_ref().unwrap().clone();
            let relative=norm((w.ship(6).unwrap().p-s.p).heading()-s.h);
            let in_arc=|arc:[f64;2]| { let h=norm(relative); if arc[0]<=arc[1] { h>=arc[0]&&h<=arc[1] } else {h>=arc[0]||h<=arc[1]} };
            let expected:u32=gun.mounts.iter().filter(|m|in_arc(m.arc)||m.arc2.is_some_and(in_arc)).map(|m|m.barrels).sum();
            let hp=w.ship(6).unwrap().hp;
            let before=w.events.len();
            w.resolve_secondaries();
            let v=w.projectile_presentation(0);
            let shots=v["shots"].as_array().unwrap();
            assert_eq!(shots.len(),1);
            let shot=&shots[0];
            assert_eq!(shot["own_ship"],id);
            assert_eq!(shot["battery"],"secondary");
            assert_eq!(shot["caliber_mm"],gun.caliber_mm);
            assert_eq!(shot["barrels"],expected);
            assert_eq!(shot["from"],json!(s.p));
            assert_eq!(shot["to"],json!(plot));
            assert_ne!(shot["to"],json!(w.ship(6).unwrap().p));
            assert_eq!(shot.as_object().unwrap().len(),8,"no target identity or hit outcome");
            assert_eq!(w.projectile_presentation(1)["shots"],json!([]));
            assert!(w.ship(id).unwrap().secondary_ready>w.tick);
            if !w.events[before..].iter().any(|e|e.kind=="secondary") {
                assert_eq!(w.ship(6).unwrap().hp,hp);
                found_miss=true;
                break;
            }
        }
        assert!(found_miss,"a genuine missed discharge must still have visible FX");
    }

    #[test]
    fn secondary_ids_are_unique_pruned_and_never_replayed_by_reading() {
        let (mut w,id,_)=secondary_world(3);
        w.resolve_secondaries();
        let first=w.projectile_presentation(0);
        assert_eq!(w.projectile_presentation(0),first);
        w.tick=5;
        assert_eq!(w.projectile_presentation(0),json!({"version":VERSION,"tick":5,"shots":first["shots"]}));
        w.tick=6;
        assert_eq!(w.projectile_presentation(0)["shots"],json!([]));
        w.ship_mut(id).unwrap().secondary_ready=6;
        w.resolve_secondaries();
        let second=w.projectile_presentation(0);
        assert_ne!(second["shots"][0]["id"],first["shots"][0]["id"]);
        assert_eq!(w.projectile_fx.secondaries.len(),1);
    }

    #[test]
    fn single_triple_main_mount_matches_its_existing_public_shell_and_truth_caliber() {
        let (mut w,id,_)=secondary_world(6106);
        w.init_realtime(w.version).unwrap();
        w.contacts[0][0].x=w.ship(6).unwrap().p.x;
        w.contacts[0][0].y=w.ship(6).unwrap().p.y;
        let contact=w.contacts[0][0].id.clone();
        for (index,destroyed) in w.ship_mut(id).unwrap().gun_mount_destroyed.iter_mut().enumerate() {
            *destroyed=index!=0;
        }
        w.order_realtime_gun(0,id,&contact,true).unwrap();
        let s=w.ship(id).unwrap();
        let gun=&w.data.ships[s.def].gun;
        let (caliber,barrels)=(gun.caliber_mm,gun.mounts[0].barrels);
        assert_eq!(barrels,3);
        for _ in 0..120 {
            w.resolve_realtime_guns();
            if !w.shells.is_empty() {break;}
            w.tick+=1;
        }
        let shots=w.projectile_presentation(0)["shots"].as_array().unwrap().clone();
        let shot=shots.iter().find(|s|s["battery"]=="main").expect("real triple discharge");
        let public=w.shell_observation(0);
        let shell=public.iter().find(|s|s["id"]==shot["shell_id"]).unwrap();
        assert_eq!(shot["own_ship"],id);
        assert_eq!(shot["barrels"],barrels);
        assert_eq!(shell["barrels"],barrels);
        assert_eq!(shot["caliber_mm"],caliber);
        assert_eq!(shot["from"],shell["from"]);
        assert_eq!(shot["to"],shell["to"]);
        assert_eq!(shot["tick"],shell["launchTick"]);
        assert_eq!(w.projectile_presentation(1)["shots"],json!([]));
        assert!(w.shell_observation(1).iter().all(|s|s.get("caliber_mm").is_none()));
    }

    #[test]
    fn optional_api_does_not_mutate_clock_rng_old_view_save_or_command_log() {
        let mut e=Engine::default();
        assert_eq!(e.handle(json!({"op":"new","seed":6106,"side":"allies","realtime":true}))["ok"],true);
        e.handle(json!({"op":"fire","ship":1,"weapon":"gun","target":"C01"}));
        e.handle(json!({"op":"step","seconds":1}));
        let before_view=e.handle(json!({"op":"observe"}));
        let before_save=e.handle(json!({"op":"save"}));
        let w=e.world.as_ref().unwrap();
        let rng=(w.tick,w.rng,w.optics_rng,w.surface_critical_rng);
        let response=e.handle(json!({"op":"presentation"}));
        assert_eq!(response["ok"],true);
        for _ in 0..50 {assert_eq!(e.handle(json!({"op":"presentation"})),response);}
        let w=e.world.as_ref().unwrap();
        assert_eq!((w.tick,w.rng,w.optics_rng,w.surface_critical_rng),rng);
        assert_eq!(e.handle(json!({"op":"observe"})),before_view);
        assert_eq!(e.handle(json!({"op":"save"})),before_save);
        assert!(before_view["data"].get("presentation").is_none());
        assert!(before_save["data"].get("presentation").is_none());
        assert_eq!(e.handle(json!({"op":"load","save":before_save["data"]})),before_view);
    }

    #[test]
    fn standalone_tide_api_is_safe_and_empty_without_changing_old_observation() {
        let mut e=Engine::default();
        let old=e.handle(json!({"op":"new_tide","seed":42,"character_id":"IBS-U-USN-FLETCHER"}));
        assert_eq!(old["ok"],true);
        assert_eq!(e.handle(json!({"op":"presentation"})),json!({"ok":true,"data":{"version":VERSION,"tick":0,"shots":[]}}));
        assert_eq!(e.handle(json!({"op":"observe"})),old);
    }
}
