//! Original, explicitly versioned combined-arms island exercise. It borrows
//! registered ship identity/range/arcs, never changes a historical world.
use crate::model::{norm, E, P, YARD};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeSet, BinaryHeap, VecDeque};
#[path="littoral_v4.rs"]
pub(crate) mod v4;

#[cfg(test)]
mod tests {
    use super::*;
    fn config(mode: &str, roster: &[&str]) -> Config {
        Config {
            mode: mode.into(),
            ships: [
                "IBS-U-USN-ERMA-IOWA",
                "IBS-U-USN-ERMA-DES-MOINES",
                "IBS-U-USN-FLETCHER",
            ]
            .iter()
            .map(|id| Hull {
                id: (*id).into(),
                hp: 100.,
                ammo: 100,
            })
            .collect(),
            roster: roster.iter().map(|id| (*id).into()).collect(),
            unit_condition: vec![],
            transport_preset: "transport".into(),
            defense: vec![],
            company_transports:vec![],lesson:None,company_layout:None,
        }
    }
    fn world(mode: &str, ids: &[&str]) -> Littoral {
        Littoral::new(42, config(mode, ids)).unwrap()
    }
    fn ground(w: &mut Littoral, i: usize, p: P) {
        w.groups[i].stage = "ground";
        w.groups[i].p = p;
        w.spawn_group(i);
    }
    #[test]
    fn clock_rejects_negative_fractional_or_oversized_time() {
        assert_eq!(frames(&json!(0.1)).unwrap(), 1);
        assert_eq!(frames(&json!(2700)).unwrap(), 27000);
        for v in [
            json!(-0.1),
            json!(0.01),
            json!(2700.1),
            json!("1"),
            Value::Null,
        ] {
            assert!(frames(&v).is_err());
        }
    }
    #[test]
    fn registered_transport_capacity_and_ammunition_trade_are_distinct() {
        assert_eq!(capacity("DD", 100), 2);
        assert_eq!(capacity("DD", 40), 5);
        assert_eq!(capacity("BB", 100), 6);
        assert_eq!(capacity("AP", 100), 20);
        assert_eq!(capacity("AK", 40), 19);
        let w = world("raid", &["MCP-022"]);
        assert_eq!(w.ships[0].loaded, 40);
        assert_eq!(w.ships[0].slots, 9);
    }
    #[test]
    fn invalid_identity_condition_and_capacity_are_rejected() {
        let mut c = config("raid", &["MCP-034"]);
        c.ships[0].id = "invented".into();
        assert!(Littoral::new(1, c).is_err());
        let c = config("raid", &["MCP-034", "MCP-034"]);
        assert!(Littoral::new(1, c).is_err());
        let c = config("raid", &["MCP-020"]);
        assert!(Littoral::new(1, c).is_err());
        let mut c = config("raid", &["MCP-034"]);
        c.unit_condition = vec![Condition {
            id: "MCP-034".into(),
            hp: 9.,
        }];
        assert!(Littoral::new(1, c).is_err());
        let mut c = config("raid", &["MCP-034"]);
        c.ships = vec![c.ships[2].clone()];
        c.transport_preset = "combat".into();
        assert!(Littoral::new(1, c).is_err());
    }
    #[test]
    fn rejected_creation_and_commands_do_not_mutate_active_world() {
        let mut e = crate::Engine::default();
        let mut q = json!(config("raid", &["MCP-034"]));
        q["op"] = json!("new_littoral");
        q["version"] = json!(VERSION);
        q["seed"] = json!(42);
        assert_eq!(e.handle(q.clone())["ok"], true);
        let before = e.handle(json!({"op":"observe"}));
        q["roster"] = json!(["MCP-999"]);
        assert_eq!(e.handle(q)["ok"], false);
        assert_eq!(e.handle(json!({"op":"observe"})), before);
        for bad in [
            json!({"op":"step","seconds":0.01}),
            json!({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"insertion":"air"}),
            json!({"op":"route","fleet":1,"points":[{"x":13000,"y":7000}],"speed":25}),
            json!({"op":"littoral_extract"}),
        ] {
            assert_eq!(e.handle(bad)["ok"], false);
            assert_eq!(e.handle(json!({"op":"observe"})), before);
        }
    }
    #[test]
    fn condition_is_absolute_and_abandon_cannot_generate_resources() {
        let mut c = config("raid", &["MCP-034"]);
        c.ships[0].hp = 60.;
        c.unit_condition = vec![Condition {
            id: "MCP-034".into(),
            hp: 60.,
        }];
        let mut w = Littoral::new(1, c).unwrap();
        w.command(&json!({"op":"littoral_abandon"}), true).unwrap();
        let r = w.result.as_ref().unwrap();
        assert_eq!(r["units"][0]["hp_percent"], 60.);
        assert_eq!(r["ships"][0]["hp_percent"], 60.);
        assert_eq!(
            r["resources"],
            json!({"scrap":0,"alloy":0,"protocols":0,"credits":0})
        );
        assert!(w.command(&json!({"op":"littoral_abandon"}), true).is_err());
    }
    #[test]
    fn real_turning_does_not_instantly_rotate_gun_arcs() {
        let mut w = world("raid", &["MCP-034"]);
        let before = w.ships[0].h;
        w.command(
            &json!({"op":"littoral_ship_order","ship":1,"action":"face","heading":270.}),
            true,
        )
        .unwrap();
        assert_eq!(w.ships[0].h, before);
        w.advance();
        assert!((w.ships[0].h - before).abs() <= 6.01);
        for _ in 0..30 {
            w.advance();
        }
        assert_eq!(w.ships[0].h, 270.);
        assert!(w.ships[0].facing.is_none());
    }
    #[test]
    fn naval_support_requires_live_unanchored_loaded_ship_and_real_range() {
        let mut w = world("raid", &["MCP-034"]);
        let p = w.ships[0].p + P { x: 1000., y: 0. };
        w.ships[0].anchor = true;
        assert!(w.naval_fire(0, p).is_err());
        w.ships[0].anchor = false;
        w.ships[0].ammo = 2;
        assert!(w.naval_fire(0, p).is_err());
        assert_eq!(w.ships[0].ammo, 2);
        w.ships[0].ammo = 40;
        w.ships[0].hp = 0.;
        assert!(w.naval_fire(0, p).is_err());
        w.ships[0].hp = w.ships[0].max;
        assert!(w
            .naval_fire(
                0,
                P {
                    x: 100000.,
                    y: 100000.
                }
            )
            .is_err());
        assert!(arc(355., [300., 10.]));
        assert!(!arc(90., [300., 10.]));
    }
    #[test]
    fn insertion_requires_distance_then_real_transit_before_bodies_exist() {
        let mut w = world("tutorial", &["MCP-034"]);
        let q = json!({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"insertion":"landing"});
        assert!(w.command(&q, true).is_err());
        let carrier = w.groups[0].carrier;
        let s = w.ships.iter_mut().find(|s| s.id == carrier).unwrap();
        s.p = Littoral::beach(2).unwrap().0;
        w.command(&q, true).unwrap();
        assert_eq!(w.groups[0].stage, "transit");
        assert!(!w.bodies.iter().any(|b| b.ally));
        w.transports[0].hp *= 0.5;
        for _ in 0..200 {
            w.advance();
        }
        assert_eq!(w.groups[0].stage, "ground");
        assert_eq!(w.bodies.iter().filter(|b| b.ally).count(), 4);
        assert!(w.group_health(0) <= 50.00001);
        assert!(w.command(&q, true).is_err());
    }
    #[test]
    fn five_cards_spawn_real_distinct_units_with_finite_ammunition() {
        let mut w = world(
            "raid",
            &["MCP-001", "MCP-034", "MCP-076", "MCP-009", "MCP-022"],
        );
        for i in 0..w.groups.len() {
            ground(
                &mut w,
                i,
                P {
                    x: 13000.,
                    y: 9800.,
                },
            );
        }
        let kinds: BTreeSet<_> = w.bodies.iter().filter(|b| b.ally).map(|b| b.kind).collect();
        for k in [
            "marine",
            "ifv",
            "vdv",
            "gunship",
            "engineer",
            "tank",
            "helicopter",
        ] {
            assert!(kinds.contains(k));
        }
        assert_eq!(w.bodies.iter().filter(|b| b.ally).count(), 18);
        assert!(w.bodies.iter().all(|b| b.ammo <= 90));
        assert!(
            w.bodies.iter().find(|b| b.kind == "tank").unwrap().damage
                > w.bodies.iter().find(|b| b.kind == "marine").unwrap().damage
        );
    }
    #[test]
    fn anti_air_actually_damages_inserted_air_bodies() {
        let mut w = world("raid", &["MCP-001"]);
        let aa = w.buildings.iter().find(|b| b.kind == "aa").unwrap().p;
        ground(&mut w, 0, aa + P { x: 200., y: 0. });
        let i = w.bodies.iter().position(|b| b.ally && b.air).unwrap();
        let hp = w.bodies[i].hp;
        for _ in 0..80 {
            w.advance();
        }
        assert!(w.bodies[i].hp < hp);
        assert!(w.impacts.iter().any(|e| e["kind"] == "aa"));
    }
    #[test]
    fn ship_loss_removes_support_and_embarked_troops() {
        let mut w = world("raid", &["MCP-034"]);
        let id = w.groups[0].carrier;
        let i = w.ships.iter().position(|s| s.id == id).unwrap();
        w.ships[i].hp = 0.;
        w.advance();
        assert_eq!(w.groups[0].stage, "lost");
        assert_eq!(w.group_health(0), 0.);
        assert!(w
            .naval_fire(
                i,
                P {
                    x: 13000.,
                    y: 9000.
                }
            )
            .is_err());
    }
    #[test]
    fn rescue_slots_are_reserved_when_first_return_transport_departs() {
        let mut w = world("raid", &["MCP-001", "MCP-009"]);
        let land = Littoral::beach(2).unwrap().1;
        for i in 0..2 {
            ground(&mut w, i, land);
            w.groups[i].carrier = 2;
            w.groups[i].order = "retreat".into();
        }
        w.ships[0].p = Littoral::beach(2).unwrap().0;
        w.ships[0].slots = 2;
        w.ships[1].hp = 0.;
        w.ships[2].hp = 0.;
        w.advance();
        assert_eq!(w.transports.iter().filter(|t| t.returning).count(), 1);
        let other = w.groups.iter().position(|g| g.stage == "ground").unwrap();
        assert!(w.return_carrier(other).is_none());
        assert!(w.group_status(other).contains("备用运输舱"));
    }
    #[test]
    fn engineer_search_is_twice_as_fast_and_resources_need_actual_recovery() {
        for (id, frames_needed) in [("MCP-009", 40), ("MCP-034", 80)] {
            let mut w = world("salvage", &[id]);
            w.bodies.clear();
            w.ships.retain(|s| s.ally);
            let p = w.ruins[0].p;
            ground(&mut w, 0, p);
            w.command(
                &json!({"op":"littoral_order","unit_id":id,"action":"search","target":1}),
                true,
            )
            .unwrap();
            for _ in 0..frames_needed - 1 {
                w.advance();
            }
            assert!(!w.ruins[0].searched);
            w.advance();
            assert!(w.ruins[0].searched);
            assert_eq!(w.loot.len(), 1);
            w.finish(true, false);
            assert_eq!(w.result.as_ref().unwrap()["resources"]["scrap"], 0);
            assert_eq!(w.result.as_ref().unwrap()["units"][0]["missing"], true);
        }
    }
    #[test]
    fn defenders_really_unmoor_and_leave_the_port() {
        let mut w = world("raid", &["MCP-034"]);
        let i = w.ships.iter().position(|s| !s.ally).unwrap();
        let origin = w.ships[i].p;
        for _ in 0..500 {
            w.advance();
        }
        assert!(!w.ships[i].anchor);
        assert!(w.ships[i].p.dist(origin) > 100.);
        assert!(w.events.iter().any(|e| e["kind"] == "unmooring"));
    }
    #[test]
    fn save_replay_matches_and_rejects_future_or_unsorted_commands() {
        let mut w = world("raid", &["MCP-034"]);
        w.command(
            &json!({"op":"route","fleet":1,"speed":30,"points":[{"x":13000,"y":11500}]}),
            true,
        )
        .unwrap();
        for _ in 0..100 {
            w.advance();
        }
        w.command(&json!({"op":"speed","fleet":1,"speed":0}), true)
            .unwrap();
        for _ in 0..7 {
            w.advance();
        }
        let saved = w.save();
        assert_eq!(
            Littoral::from_save(saved.clone(), None).unwrap().view(),
            w.view()
        );
        assert!(Littoral::from_save(saved.clone(), Some(saved.frame + 1)).is_err());
        let mut bad = saved.clone();
        bad.commands[0].frame = bad.frame + 1;
        assert!(Littoral::from_save(bad, None).is_err());
        let mut bad = saved.clone();
        bad.commands.swap(0, 1);
        assert!(Littoral::from_save(bad, None).is_err());
        let mut bad = saved;
        bad.tick += 0.1;
        assert!(Littoral::from_save(bad, None).is_err());
    }
    #[test]
    fn timeout_and_entity_budgets_are_true_finite_boundaries() {
        let mut w = world("raid", &["MCP-034"]);
        w.frame = LIMIT - 1;
        w.advance();
        assert_eq!(w.result.as_ref().unwrap()["success"], false);
        let mut w = world("raid", &["MCP-034"]);
        for _ in 0..MAX_PROJECTILES {
            assert!(w.launch(
                true,
                w.ships[0].p,
                P {
                    x: 6000.,
                    y: 13000.
                },
                1.,
                1.,
                1.,
                false,
                "test",
                "test".into()
            ));
        }
        let ammo = w.ships[0].ammo;
        assert!(w
            .naval_fire(
                0,
                P {
                    x: 6000.,
                    y: 13000.
                }
            )
            .is_err());
        assert_eq!(w.ships[0].ammo, ammo);
        assert_eq!(w.shots.len(), RECENT);
        for _ in 0..200 {
            w.body(
                "test".into(),
                false,
                "rifle",
                P {
                    x: 13000.,
                    y: 9000.,
                },
                100.,
            );
        }
        assert_eq!(w.bodies.len(), MAX_BODIES);
    }
    #[test]
    fn independent_modes_replace_one_another_without_residual_state() {
        let mut e = crate::Engine::default();
        let mut q = json!(config("tutorial", &["MCP-034"]));
        q["op"] = json!("new_littoral");
        q["version"] = json!(VERSION);
        q["seed"] = json!(1);
        assert_eq!(e.handle(q.clone())["ok"], true);
        let r=e.handle(json!({"op":"new_tide","seed":42,"version":"cas-event-tide-v1","character_id":"IBS-U-USN-FLETCHER"}));
        assert_eq!(r["ok"], true);
        assert!(r["data"].get("littoral").is_none());
        assert_eq!(e.handle(q)["ok"], true);
        assert!(e.handle(json!({"op":"observe"}))["data"]
            .get("tide")
            .is_none());
    }
    #[test]
    fn engineer_tools_repair_facilities_without_healing_owned_personnel() {
        let mut c = config("defense", &["MCP-009"]);
        c.unit_condition = vec![Condition {
            id: "MCP-009".into(),
            hp: 60.,
        }];
        let mut w = Littoral::new(42, c).unwrap();
        w.ships.retain(|s| s.ally);
        let i = w.buildings.iter().position(|b| b.kind == "hq").unwrap();
        let p = w.buildings[i].p;
        w.groups[0].p = p;
        for b in w.bodies.iter_mut().filter(|b| b.ally) {
            b.p = p;
        }
        w.buildings[i].hp = w.buildings[i].max * 0.2;
        let before = w.buildings[i].hp;
        w.command(
            &json!({"op":"littoral_order","unit_id":"MCP-009","action":"repair","target":"hq"}),
            true,
        )
        .unwrap();
        for _ in 0..150 {
            w.advance();
        }
        assert!(w.buildings[i].hp > before);
        assert_eq!(w.groups[0].supplies, 0);
        assert!((w.group_health(0) - 60.).abs() < 1e-9);
    }
    #[test]
    fn procedural_shorelines_keep_all_designated_entries_and_objectives_legal() {
        for seed in [0, 1, 42, 43, 6106, u32::MAX] {
            let w = Littoral::new(seed, config("raid", &["MCP-034"])).unwrap();
            for id in 1..=3 {
                let (sea, land) = Littoral::beach(id).unwrap();
                assert!(w.walkable(sea, false));
                assert!(w.walkable(land, true));
            }
            for r in &w.ruins {
                assert!(w.walkable(r.p, true));
            }
        }
        assert_ne!(
            Littoral::new(42, config("raid", &["MCP-034"]))
                .unwrap()
                .polygon,
            Littoral::new(43, config("raid", &["MCP-034"]))
                .unwrap()
                .polygon
        );
    }
    #[test]
    fn registered_nisshin_carries_all_five_cards_without_falsifying_her_identity() {
        let mut c = config(
            "raid",
            &["MCP-001", "MCP-034", "MCP-076", "MCP-009", "MCP-022"],
        );
        c.ships = vec![Hull {
            id: "IBS-U-IJN-NISSHIN".into(),
            hp: 100.,
            ammo: 100,
        }];
        c.transport_preset = "combat".into();
        let w = Littoral::new(46, c).unwrap();
        assert_eq!(w.ships[0].slots, 16);
        assert_eq!(w.ships[0].def.kind, "AV");
        assert_eq!(w.ships[0].ammo, 100);
        assert_eq!(w.groups.iter().map(|g| g.card.slots).sum::<u32>(), 14);
        assert!(w.groups.iter().all(|g| g.carrier == 1));
        assert_eq!(w.view()["ships"][0]["transport_role"], "transport_support");
        let actual = crate::salvage_v3::data()
            .unwrap()
            .ships
            .iter()
            .find(|s| s.id == "IBS-U-IJN-NISSHIN")
            .unwrap();
        assert_eq!(w.ships[0].def.gun.caliber_mm, actual.gun.caliber_mm);
        assert_eq!(w.ships[0].max, (actual.dp * 5.).max(300.));
    }
    #[test]
    fn queued_shore_support_owns_the_next_reload_and_remains_cancellable() {
        let mut w = world("raid", &["MCP-034"]);
        let target = w.ships[0].p + P { x: 1000., y: 0. };
        w.ships[0].h = 0.;
        w.ships[0].next = 10;
        let i = w.ships.iter().position(|s| !s.ally).unwrap();
        w.ships[i].anchor = false;
        w.ships[i].ai = false;
        w.ships[i].p = target + P { x: 0., y: 100. };
        let before = w.ships[0].ammo;
        w.command(&json!({"op":"littoral_support","kind":"naval","ship":1,"x":target.x,"y":target.y,"queue":true}),true).unwrap();
        for _ in 0..9 {
            w.advance();
        }
        assert_eq!(w.ships[0].ammo, before);
        assert!(w.ships[0].pending_support.is_some());
        w.advance();
        assert_eq!(w.ships[0].ammo, before - 3);
        assert!(w.ships[0].pending_support.is_none());
        assert!(w.events.iter().any(|e| e["kind"] == "support_fired"));
        w.command(&json!({"op":"littoral_support","kind":"naval","ship":1,"x":target.x,"y":target.y,"queue":true}),true).unwrap();
        w.command(
            &json!({"op":"littoral_ship_order","ship":1,"action":"cancel_support"}),
            true,
        )
        .unwrap();
        assert!(w.ships[0].pending_support.is_none());
        w.command(&json!({"op":"littoral_support","kind":"naval","ship":1,"x":target.x,"y":target.y,"queue":true}),true).unwrap();
        w.ships[0].hp = 0.;
        w.advance();
        assert!(w.ships[0].pending_support.is_none());
    }
}
#[cfg(test)]
mod v2_tests {
    use super::*;
    fn make(ids:&[&str],mode:&str)->Littoral {
        let c=Config{mode:mode.into(),ships:vec![Hull{id:"IBS-U-IJN-NISSHIN".into(),hp:100.,ammo:100}],roster:ids.iter().map(|id|id.to_string()).collect(),unit_condition:vec![],transport_preset:"transport".into(),defense:vec![],company_transports:vec![],lesson:None,company_layout:None};
        Littoral::new_version(42,c,VERSION_V2).unwrap()
    }
    fn ground(w:&mut Littoral,i:usize){w.groups[i].stage="ground";w.groups[i].p=P{x:12600.,y:9000.};w.spawn_group(i);}
    #[test] fn catalogue_and_spawn_use_identical_twenty_profiles(){
        assert_eq!(PROFILES.len(),20);let mut seen=BTreeSet::new();
        for p in PROFILES {assert!(seen.insert(p.id));let mut w=make(&[p.id],"tutorial");ground(&mut w,0);let j=profile_json(&p);let b:Vec<_>=w.bodies.iter().filter(|b|b.ally).collect();assert_eq!(b.len(),p.bodies.len());for(i,b)in b.iter().enumerate(){assert_eq!(b.max,j["bodies"][i]["hp"].as_f64().unwrap());assert_eq!(b.damage,j["bodies"][i]["damage"].as_f64().unwrap());assert_eq!(b.range,j["bodies"][i]["range"].as_f64().unwrap());assert_eq!(b.ammo,j["bodies"][i]["ammo"].as_u64().unwrap() as u32);assert_eq!(b.reload as f64/10.,j["bodies"][i]["reload_seconds"].as_f64().unwrap());}}
    }
    #[test] fn six_group_transport_real_limit_and_v1_rejection(){
        let w=make(&["MCP-001","MCP-034","MCP-009","MCP-011","MCP-018","MCP-203"],"tutorial");assert_eq!(w.groups.len(),6);assert!(Littoral::new(42,w.config.clone()).is_err());let mut c=w.config.clone();c.roster.push("MCP-240".into());assert!(Littoral::new_version(42,c,VERSION_V2).is_err());let mut c=w.config.clone();c.ships[0].id="IBS-U-USN-FLETCHER".into();assert!(Littoral::new_version(42,c,VERSION_V2).is_err());
    }
    #[test] fn queue_is_real_and_replays_while_approaching_and_landed(){
        let mut w=make(&["MCP-034"],"tutorial");let request=json!({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"insertion":"landing","queue":true});let before=w.ships[0].p;w.command(&request,true).unwrap();assert_eq!(w.groups[0].stage,"embarked");assert_eq!(w.ships[0].p,before);for _ in 0..10{w.advance()}assert_eq!(Littoral::from_save(w.save(),None).unwrap().view(),w.view());for _ in 0..390{if w.groups[0].stage=="ground"{break}w.advance()}assert_eq!(w.groups[0].stage,"ground");assert!(w.tick()<=40.);assert_eq!(Littoral::from_save(w.save(),None).unwrap().view(),w.view());
    }
    #[test] fn conflicting_queue_and_invalid_preview_are_atomic(){let mut w=make(&["MCP-034","MCP-009"],"tutorial");w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"insertion":"landing","queue":true}),true).unwrap();let v=w.view();assert!(w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-009","beach":1,"insertion":"landing","queue":true}),true).is_err());assert_eq!(v,w.view());assert_eq!(w.preview_littoral(&json!({"kind":"deploy","unit_id":"MCP-009","x":500,"y":500,"insertion":"landing"})).unwrap()["valid"],false);assert_eq!(v,w.view());}
    #[test] fn manual_hold_cancels_only_unstarted_deployment(){let mut w=make(&["MCP-034"],"tutorial");w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"insertion":"landing","queue":true}),true).unwrap();w.command(&json!({"op":"littoral_ship_order","ship":1,"action":"hold"}),true).unwrap();assert!(w.groups[0].pending.is_none());for _ in 0..400{w.advance()}assert_eq!(w.groups[0].stage,"embarked");}
    #[test] fn aim_is_gradual_and_queued_salvo_spends_real_ammunition(){let mut w=make(&["MCP-034"],"tutorial");let p=P{x:12600.,y:9000.};w.command(&json!({"op":"littoral_ship_order","ship":1,"action":"face","heading":349.38034472384487}),true).unwrap();for _ in 0..50{w.advance()}let before=w.ships[0].h;let ammo=w.ships[0].ammo;w.command(&json!({"op":"littoral_ship_order","ship":1,"action":"aim_land","x":p.x,"y":p.y}),true).unwrap();assert_eq!(w.ships[0].h,before);w.command(&json!({"op":"littoral_support","kind":"naval","ship":1,"x":p.x,"y":p.y,"queue":true}),true).unwrap();assert_eq!(w.ships[0].ammo,ammo);for _ in 0..50{w.advance();if w.ships[0].pending_support.is_none(){break}}assert!(w.ships[0].ammo<ammo);assert!(w.shots.iter().any(|s|s["kind"]=="naval"));assert_eq!(Littoral::from_save(w.save(),None).unwrap().view(),w.view());}
    #[test] fn offensive_skills_use_owned_weapon_ammunition(){for id in ["MCP-001","MCP-034","MCP-076","MCP-027","MCP-063","MCP-087","MCP-145","MCP-184"]{let mut w=make(&[id],"tutorial");ground(&mut w,0);let ammo:u32=w.bodies.iter().filter(|b|b.ally).map(|b|b.ammo).sum();w.command(&json!({"op":"littoral_ability","unit_id":id,"x":12600,"y":8600}),true).unwrap();let cost=if id=="MCP-087"{3}else{1};assert_eq!(w.projectiles.len(),cost);assert_eq!(ammo-w.bodies.iter().filter(|b|b.ally).map(|b|b.ammo).sum::<u32>(),cost as u32);let charges=w.groups[0].ability_charges;assert!(w.command(&json!({"op":"littoral_ability","unit_id":id,"x":12600,"y":8600}),true).is_err());assert_eq!(w.groups[0].ability_charges,charges);}}
    #[test] fn smoke_and_hull_down_have_measured_damage_reduction(){for(id,factor)in[("MCP-011",0.7),("MCP-022",0.6)]{let mut w=make(&[id],"tutorial");ground(&mut w,0);w.command(&json!({"op":"littoral_ability","unit_id":id}),true).unwrap();let b=w.bodies.iter().find(|b|b.ally).unwrap().clone();w.blast(b.p,10.,30.,false,false,"rifle","test");let after=w.bodies.iter().find(|a|a.id==b.id).unwrap();assert!((b.hp-after.hp-10.*b.armor*factor).abs()<1e-6);}}
    #[test] fn resupply_conserves_finite_reserve_and_never_ship_ammo(){let mut w=make(&["MCP-116","MCP-034"],"tutorial");ground(&mut w,0);ground(&mut w,1);for b in w.bodies.iter_mut().filter(|b|b.ally){b.ammo-=30;}let before:u32=w.bodies.iter().filter(|b|b.ally).map(|b|b.ammo).sum();let ship=w.ships[0].ammo;w.command(&json!({"op":"littoral_ability","unit_id":"MCP-116"}),true).unwrap();let after:u32=w.bodies.iter().filter(|b|b.ally).map(|b|b.ammo).sum();assert_eq!(after-before,60);assert_eq!(w.groups[0].reserve_ammo,60);assert_eq!(w.ships[0].ammo,ship);}
    #[test] fn medical_does_not_revive_or_exceed_initial_condition(){let mut w=make(&["MCP-052"],"tutorial");w.groups[0].initial=40.;ground(&mut w,0);let b=w.bodies.iter_mut().find(|b|b.ally).unwrap();b.hp-=10.;let id=b.id;w.command(&json!({"op":"littoral_ability","unit_id":"MCP-052"}),true).unwrap();let b=w.bodies.iter().find(|b|b.id==id).unwrap();assert!(b.hp<=b.max*0.4);w.bodies.iter_mut().find(|b|b.id==id).unwrap().hp=0.;w.frame+=300;assert!(w.command(&json!({"op":"littoral_ability","unit_id":"MCP-052"}),true).is_err());assert_eq!(w.bodies.iter().find(|b|b.id==id).unwrap().hp,0.);}
    #[test] fn all_twenty_have_actual_autofire_not_only_catalogue_values(){for p in PROFILES{let mut w=make(&[p.id],"tutorial");ground(&mut w,0);w.spawn_enemy(P{x:12600.,y:if p.id=="MCP-184"{8550.}else{8400.}},"tank");for _ in 0..30{w.advance()}assert!(w.shots.iter().any(|s|s["side"]=="allies"&&s["source"].as_str().is_some_and(|s|s.starts_with("body:"))),"{} did not really fire",p.id);assert!(w.bodies.iter().filter(|b|b.ally).any(|b|b.ammo<profile_json(&p)["bodies"].as_array().unwrap().iter().find(|v|v["kind"]==b.kind).unwrap()["ammo"].as_u64().unwrap() as u32));}}
    #[test] fn empty_enemy_aircraft_cannot_contest_ground_capture(){let mut w=make(&["MCP-022"],"raid");let hq=w.buildings.iter().find(|b|b.kind=="hq").unwrap().p;w.groups[0].stage="ground";w.groups[0].p=hq;w.spawn_group(0);for b in w.bodies.iter_mut().filter(|b|!b.ally){b.hp=0.;}w.spawn_enemy(hq,"helicopter");w.bodies.last_mut().unwrap().ammo=0;for _ in 0..80{w.advance()}assert!(w.objective_complete());}
    #[test] fn electronic_jam_is_limited_and_delays_real_emplacement(){let mut w=make(&["MCP-041"],"tutorial");ground(&mut w,0);let target=w.buildings.iter().find(|b|b.kind=="turret").unwrap().p;w.groups[0].p=target;w.command(&json!({"op":"littoral_ability","unit_id":"MCP-041","x":target.x,"y":target.y}),true).unwrap();assert_eq!(w.buildings.iter().find(|b|b.kind=="turret").unwrap().next,80);assert_eq!(w.groups[0].ability_charges,2);}
    #[test] fn precision_and_mark_change_actual_projectile_damage(){let mut w=make(&["MCP-128","MCP-018"],"tutorial");ground(&mut w,0);ground(&mut w,1);let p=P{x:12600.,y:8400.};w.spawn_enemy(p,"tank");w.command(&json!({"op":"littoral_ability","unit_id":"MCP-128"}),true).unwrap();w.command(&json!({"op":"littoral_ability","unit_id":"MCP-018","x":p.x,"y":p.y}),true).unwrap();for _ in 0..3{w.advance()}assert!(w.projectiles.iter().any(|s|s.kind=="sniper"&&(s.damage-70.*1.05*1.6).abs()<1e-6));let b=w.bodies.iter().find(|b|!b.ally&&b.kind=="tank").unwrap().clone();w.blast(b.p,10.,10.,true,false,"anti_tank","test");assert!((b.hp-w.bodies.iter().find(|a|a.id==b.id).unwrap().hp-10.*0.8*1.25).abs()<1e-6);}
    #[test] fn command_buff_speeds_real_reload_and_cannot_be_cast_remotely(){let mut w=make(&["MCP-203","MCP-034"],"tutorial");ground(&mut w,0);ground(&mut w,1);assert!(w.command(&json!({"op":"littoral_ability","unit_id":"MCP-203","x":14000,"y":8500}),true).is_err());w.command(&json!({"op":"littoral_ability","unit_id":"MCP-203"}),true).unwrap();w.spawn_enemy(P{x:12600.,y:8400.},"tank");for _ in 0..3{w.advance()}assert!(w.bodies.iter().any(|b|b.group=="MCP-034"&&b.ammo<90&&b.next-w.frame<b.reload));}
    #[test] fn exported_numeric_source_matches_authoritative_catalogue(){
        fn equal(a:&Value,b:&Value){match(a,b){(Value::Object(a),Value::Object(b))=>{assert_eq!(a.len(),b.len());for(k,v)in a{equal(v,&b[k])}},(Value::Array(a),Value::Array(b))=>{assert_eq!(a.len(),b.len());for(a,b)in a.iter().zip(b){equal(a,b)}},(Value::Number(a),Value::Number(b))=>assert!((a.as_f64().unwrap()-b.as_f64().unwrap()).abs()<=1e-9,"numeric source drift: {a} / {b}"),_=>assert_eq!(a,b)}}
        // serde_json's decimal parser can round one ULP differently on import;
        // tolerance only covers that wire representation, never balancing drift.
        let exported:Value=serde_json::from_str(include_str!("../godot/data/tactical-profiles-v2.json")).unwrap();equal(&exported,&catalogue_version(VERSION_V2).unwrap());
    }
    #[test] fn engineering_skill_spends_tools_and_restores_only_real_building(){let mut w=make(&["MCP-009"],"defense");let p=w.buildings.iter().find(|b|b.kind=="hq").unwrap().p;w.groups[0].p=p;let i=w.buildings.iter().position(|b|b.kind=="hq").unwrap();w.buildings[i].hp-=100.;let before=w.buildings[i].hp;let condition=w.group_health(0);let tools=w.groups[0].supplies;w.command(&json!({"op":"littoral_ability","unit_id":"MCP-009"}),true).unwrap();assert_eq!(w.buildings[i].hp,before+80.);assert_eq!(w.groups[0].supplies,tools-2);assert_eq!(w.group_health(0),condition);}
    #[test] fn rapid_march_changes_real_distance_and_expires(){let mut w=make(&["MCP-103"],"tutorial");ground(&mut w,0);w.command(&json!({"op":"littoral_ability","unit_id":"MCP-103"}),true).unwrap();w.command(&json!({"op":"littoral_order","unit_id":"MCP-103","action":"move","x":12600,"y":9400}),true).unwrap();let p=w.groups[0].p;w.advance();assert!((w.groups[0].p.dist(p)-65.*0.1*1.6).abs()<1e-6);for _ in 0..100{w.advance()}assert_eq!(w.view()["littoral"]["groups"][0]["ability"]["active_seconds"],0.);}
}

#[cfg(test)]
mod v3_tests {
    use super::*;
    fn config(ids:&[&str],mode:&str)->Config {
        Config{mode:mode.into(),ships:["IBS-U-IJN-NISSHIN","IBS-U-USN-ERMA-IOWA"].iter().map(|id|Hull{id:(*id).into(),hp:100.,ammo:100}).collect(),roster:ids.iter().map(|id|(*id).into()).collect(),unit_condition:vec![],transport_preset:"transport".into(),defense:vec![],company_transports:vec![],lesson:if mode=="tutorial"{Some("landing".into())}else{None},company_layout:None}
    }
    fn make(ids:&[&str],mode:&str)->Littoral {Littoral::new_version(42,config(ids,mode),VERSION_V3).unwrap()}
    fn nearby(w:&mut Littoral){for s in w.ships.iter_mut().filter(|s|s.ally){s.p=P{x:13000.,y:11500.};}}
    fn ground(w:&mut Littoral,i:usize){w.groups[i].stage="ground";w.groups[i].p=P{x:12600.,y:9000.};w.spawn_group(i);}
    #[test] fn legacy_decoder_field_set_and_error_text_are_frozen(){
        let mut v=json!(config(&["MCP-034","MCP-001"],"raid"));v.as_object_mut().unwrap().remove("lesson");v["client_type"]=json!("fake");
        let error=decode_config(v,VERSION).unwrap_err().to_string();assert_eq!(error,"unknown field `client_type`, expected one of `mode`, `ships`, `roster`, `unit_condition`, `transport_preset`, `defense`");
        let mut v=json!(config(&["MCP-034","MCP-001"],"raid"));v["company_transports"]=json!([]);assert!(decode_config(v,VERSION_V2).is_err());
    }
    #[test] fn strict_two_to_five_companies_and_transport_identity_validation(){
        assert!(Littoral::new_version(42,config(&["MCP-034"],"raid"),VERSION_V3).is_err());
        assert!(Littoral::new_version(42,config(&["MCP-034","MCP-009","MCP-011","MCP-018","MCP-052","MCP-203"],"raid"),VERSION_V3).is_err());
        for variants in [vec![("MCP-034","landing_craft")],vec![("MCP-034","landing_craft"),("MCP-034","landing_craft")],vec![("MCP-034","helicopter"),("MCP-001","helicopter")]] {
            let mut c=config(&["MCP-034","MCP-001"],"tutorial");c.company_transports=variants.into_iter().map(|(id,kind)|CompanyTransport{id:id.into(),kind:kind.into()}).collect();assert!(Littoral::new_version(42,c,VERSION_V3).is_err());
        }
    }
    #[test] fn all_twenty_default_companies_have_six_to_ten_real_bodies(){
        let catalogue=catalogue_version(VERSION_V3).unwrap();assert_eq!(catalogue["cards"].as_array().unwrap().len(),20);
        let mut vehicles=BTreeSet::new();
        for p in PROFILES {let other=if p.id=="MCP-034"{"MCP-001"}else{"MCP-034"};let mut w=make(&[p.id,other],"tutorial");ground(&mut w,0);let card=catalogue["cards"].as_array().unwrap().iter().find(|c|c["id"]==p.id).unwrap();let bodies:Vec<_>=w.bodies.iter().filter(|b|b.group==p.id).collect();assert!((6..=10).contains(&bodies.len()));assert_eq!(bodies.len(),card["entity_count"].as_u64().unwrap() as usize);assert!(vehicles.insert(card["vehicle_id"].as_str().unwrap().to_string()));for (b,j) in bodies.iter().zip(card["bodies"].as_array().unwrap()){assert!((b.max-j["hp"].as_f64().unwrap()).abs()<1e-9);assert!((b.damage-j["damage"].as_f64().unwrap()).abs()<1e-9);assert!((b.range-j["range"].as_f64().unwrap()).abs()<1e-9);assert_eq!(b.ammo,j["ammo"].as_u64().unwrap() as u32);assert_eq!(b.reload as f64/10.,j["reload_seconds"].as_f64().unwrap());}}
    }
    #[test] fn five_full_companies_spawn_fifty_individuals_without_truncation(){
        let w=make(&["MCP-034","MCP-009","MCP-011","MCP-018","MCP-052"],"defense");let bodies:Vec<_>=w.bodies.iter().filter(|b|b.ally).collect();assert_eq!(bodies.len(),50);assert_eq!(bodies.iter().map(|b|b.id).collect::<BTreeSet<_>>().len(),50);for g in &w.groups{assert_eq!(bodies.iter().filter(|b|b.group==g.card.id).count(),10);}assert_eq!(w.view()["littoral"]["budget"]["friendly_bodies"],50);
    }
    #[test] fn transport_choices_trade_personnel_protection_and_actual_movement(){
        let mut speeds=vec![];let mut health=vec![];let mut counts=vec![];let mut armor=vec![];
        for kind in ["landing_craft","amphibious_vehicle","helicopter"] {let mut c=config(&["MCP-001","MCP-034"],"tutorial");c.company_transports=vec![CompanyTransport{id:"MCP-001".into(),kind:kind.into()},CompanyTransport{id:"MCP-034".into(),kind:"landing_craft".into()}];let mut w=Littoral::new_version(42,c,VERSION_V3).unwrap();nearby(&mut w);w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-001","beach":2,"insertion":"landing"}),true).unwrap();let p=w.transports[0].p;let hp=w.transports[0].hp;w.advance();speeds.push(w.transports[0].p.dist(p)/DT);health.push(hp);counts.push(w.groups[0].card.count);let p=w.transports[0].p;w.blast(p,10.,5.,false,false,"rifle","test");armor.push((hp-w.transports[0].hp)/10.);}
        assert!(speeds[0]<speeds[1]&&speeds[1]<speeds[2]);assert!(health[1]>health[0]&&health[0]>health[2]);assert!(counts[0]>counts[1]&&counts[1]>=counts[2]);assert!(armor[1]<armor[0]);
    }
    #[test] fn destroyed_transport_does_not_spawn_or_recover_its_personnel(){
        let mut w=make(&["MCP-034","MCP-001"],"tutorial");nearby(&mut w);w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"insertion":"landing"}),true).unwrap();let p=w.transports[0].p;w.blast(p,10000.,10.,false,false,"anti_tank","test");w.advance();assert_eq!(w.groups[0].stage,"lost");assert!(!w.bodies.iter().any(|b|b.group=="MCP-034"));assert_eq!(w.group_health(0),0.);
    }
    #[test] fn damaged_transport_keeps_damage_on_actual_arriving_company(){
        let mut w=make(&["MCP-034","MCP-001"],"tutorial");nearby(&mut w);w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"insertion":"landing"}),true).unwrap();w.transports[0].hp=w.transports[0].max/2.;w.transports[0].p=w.transports[0].goal;w.advance();assert_eq!(w.groups[0].stage,"ground");for b in w.bodies.iter().filter(|b|b.group=="MCP-034"){assert!((b.hp/b.max-0.5).abs()<1e-9);}
    }
    #[test] fn gunship_transport_uses_all_twelve_rounds_then_stops_without_refresh(){
        let mut w=make(&["MCP-027","MCP-034"],"tutorial");w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-027","beach":2,"insertion":"landing"}),true).unwrap();
        let origin=w.transports[0].p;let target=origin+P{x:0.,y:-700.};for b in &mut w.buildings{b.hp=0.}for b in w.bodies.iter_mut().filter(|b|!b.ally){b.hp=0.}for s in &mut w.ships{s.ai=false;}w.buildings[0].p=target;w.buildings[0].ally=false;w.buildings[0].hp=10000.;w.buildings[0].max=10000.;
        w.transports[0].goal=origin+P{x:0.,y:20000.};
        // A stable range fixture isolates weapon conservation from flight geometry.
        for _ in 0..160{w.transports[0].p=origin;w.advance()}
        assert_eq!(w.groups[0].vehicle_ammo,0);let count=w.shots.iter().filter(|s|s["kind"]=="transport_gunship").count();assert_eq!(count,12);let hp=w.buildings[0].hp;for _ in 0..40{w.transports[0].p=origin;w.advance()}assert_eq!(w.shots.iter().filter(|s|s["kind"]=="transport_gunship").count(),12);assert!(w.buildings[0].hp<=hp);assert_eq!(w.groups[1].vehicle_ammo,0);
    }
    #[test] fn combined_training_requires_distinct_landings_real_shore_hits_and_search(){
        let mut c=config(&["MCP-034","MCP-001","MCP-022"],"tutorial");c.lesson=Some("combined".into());let mut w=Littoral::new_version(42,c,VERSION_V3).unwrap();w.ruins[0].searched=true;assert!(!w.objective_complete());ground(&mut w,0);ground(&mut w,1);assert!(!w.objective_complete());let p=w.ships.iter().find(|s|!s.ally).unwrap().p;w.blast(p,10.,10.,true,false,"naval","test");assert_eq!(w.shore_support_hits,0);let p=w.buildings[0].p;w.blast(p,10.,10.,true,false,"naval","test");assert!(w.shore_support_hits>0);assert!(w.objective_complete());
    }
    #[test] fn sea_control_requires_actual_enemy_sink_and_does_not_require_fake_landings(){
        let mut c=config(&["MCP-034","MCP-001"],"tutorial");c.lesson=Some("sea_control".into());let mut w=Littoral::new_version(42,c,VERSION_V3).unwrap();assert!(!w.objective_complete());for s in w.ships.iter_mut().filter(|s|!s.ally){s.hp=0.;}assert!(w.objective_complete());assert!(w.landed_companies.is_empty());assert!(w.command(&json!({"op":"littoral_extract"}),true).is_err());
    }
    #[test] fn v3_speed_and_reload_match_published_multipliers(){
        let mut w=make(&["MCP-034","MCP-001"],"tutorial");ground(&mut w,0);w.command(&json!({"op":"littoral_order","unit_id":"MCP-034","action":"move","x":12600,"y":9400}),true).unwrap();let p=w.groups[0].p;w.advance();assert!((w.groups[0].p.dist(p)-profile("MCP-034").unwrap().speed*2.5*DT).abs()<1e-9);let body=w.bodies.iter().find(|b|b.group=="MCP-034").unwrap();let old_reload=(body_stats(body.kind).3 as f64*profile("MCP-034").unwrap().reload_scale).round();assert_eq!(body.reload,(old_reload/1.8).round() as u32);
    }
    #[test] fn queued_companies_save_and_replay_exactly_with_distinct_vehicles(){
        let mut w=make(&["MCP-034","MCP-001","MCP-022"],"tutorial");for id in ["MCP-034","MCP-001","MCP-022"]{w.command(&json!({"op":"littoral_deploy","unit_id":id,"beach":2,"insertion":"landing","queue":true}),true).unwrap();}for frame in 0..450{w.advance();if [1,75,275,449].contains(&frame){assert_eq!(Littoral::from_save(w.save(),None).unwrap().view(),w.view());}}assert_eq!(w.landed_companies.len(),3);
    }
    #[test] fn ship_move_preview_is_pure_and_rejects_land(){
        let w=make(&["MCP-034","MCP-001"],"tutorial");let before=w.view();assert_eq!(w.preview_littoral(&json!({"kind":"ship_move","ship":1,"x":14000,"y":13000})).unwrap()["valid"],true);assert_eq!(w.preview_littoral(&json!({"kind":"ship_move","ship":1,"x":13000,"y":8000})).unwrap()["valid"],false);assert_eq!(w.view(),before);
    }
    #[test] fn exported_v3_numeric_source_is_authoritative(){
        fn eq(a:&Value,b:&Value){match(a,b){(Value::Object(a),Value::Object(b))=>{assert_eq!(a.len(),b.len());for(k,v)in a{eq(v,&b[k]);}},(Value::Array(a),Value::Array(b))=>{assert_eq!(a.len(),b.len());for(a,b)in a.iter().zip(b){eq(a,b);}},(Value::Number(a),Value::Number(b))=>assert!((a.as_f64().unwrap()-b.as_f64().unwrap()).abs()<1e-9),_=>assert_eq!(a,b)}}let exported:Value=serde_json::from_str(include_str!("../godot/data/tactical-profiles-v3.json")).unwrap();eq(&exported,&catalogue_version(VERSION_V3).unwrap());
    }
}

pub const VERSION: &str = "cas-littoral-v1";
pub const VERSION_V2: &str = "cas-littoral-v2";
pub const VERSION_V3: &str = "cas-littoral-v3";
const HZ: u32 = 10;
const DT: f64 = 0.1;
const LIMIT: u32 = 4800;
const WIDTH: f64 = 24000.;
const HEIGHT: f64 = 16000.;
const MAX_BODIES: usize = 96;
const MAX_PROJECTILES: usize = 256;
const RECENT: usize = 96;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Hull {
    pub id: String,
    pub hp: f64,
    pub ammo: u32,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Condition {
    pub id: String,
    pub hp: f64,
}
#[derive(Clone,Debug,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CompanyTransport {pub id:String,pub kind:String}
fn full() -> f64 {
    100.
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Fort {
    pub id: String,
    pub kind: String,
    pub x: f64,
    pub y: f64,
    pub level: u32,
    #[serde(default = "full")]
    pub hp: f64,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub mode: String,
    pub ships: Vec<Hull>,
    pub roster: Vec<String>,
    #[serde(default)]
    pub unit_condition: Vec<Condition>,
    pub transport_preset: String,
    #[serde(default)]
    pub defense: Vec<Fort>,
    #[serde(default,skip_serializing_if="Vec::is_empty")]
    pub company_transports:Vec<CompanyTransport>,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub lesson:Option<String>,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub company_layout:Option<String>,
}
// Keep the original schema's rejection text and accepted field set frozen.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyConfig {
    mode:String, ships:Vec<Hull>, roster:Vec<String>,
    #[serde(default)] unit_condition:Vec<Condition>,
    transport_preset:String,
    #[serde(default)] defense:Vec<Fort>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PreviousConfig {
    mode:String, ships:Vec<Hull>, roster:Vec<String>,
    #[serde(default)] unit_condition:Vec<Condition>,
    transport_preset:String,
    #[serde(default)] defense:Vec<Fort>,
    #[serde(default)] company_transports:Vec<CompanyTransport>,
    #[serde(default)] lesson:Option<String>,
}
pub fn decode_config(value:Value,version:&str)->Result<Config,serde_json::Error>{
    if version==v4::VERSION{return serde_json::from_value(value)}
    if version==VERSION_V3{let c:PreviousConfig=serde_json::from_value(value)?;return Ok(Config{mode:c.mode,ships:c.ships,roster:c.roster,unit_condition:c.unit_condition,transport_preset:c.transport_preset,defense:c.defense,company_transports:c.company_transports,lesson:c.lesson,company_layout:None})}
    let c:LegacyConfig=serde_json::from_value(value)?;
    Ok(Config{mode:c.mode,ships:c.ships,roster:c.roster,unit_condition:c.unit_condition,
        transport_preset:c.transport_preset,defense:c.defense,company_transports:vec![],lesson:None,company_layout:None})
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Command {
    pub frame: u32,
    pub request: Value,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Saved {
    pub version: String,
    pub seed: u32,
    pub config: Config,
    pub frame: u32,
    pub tick: f64,
    pub commands: Vec<Command>,
}
#[derive(Clone, Copy)]
struct Card {
    id: &'static str,
    name: &'static str,
    role: &'static str,
    slots: u32,
    count: u32,
    speed: f64,
    air: bool,
    specialty: &'static str,
}
const CARDS: [Card; 5] = [
    Card {
        id: "MCP-001",
        name: "第1空中特勤旅 · 云隼",
        role: "helicopter",
        slots: 2,
        count: 3,
        speed: 65.,
        air: true,
        specialty: "双特勤步兵与一架武装直升机；可空中插入，怕防空",
    },
    Card {
        id: "MCP-034",
        name: "第34海军派遣团 · 礁刃",
        role: "marine",
        slots: 3,
        count: 4,
        speed: 48.,
        air: false,
        specialty: "三名陆战步兵与一辆步战车，滩头持续火力",
    },
    Card {
        id: "MCP-076",
        name: "第76近卫空降群 · 冬鸢",
        role: "vdv",
        slots: 3,
        count: 4,
        speed: 58.,
        air: true,
        specialty: "三名空降兵与一架火力支援机；可空插，反装甲火力",
    },
    Card {
        id: "MCP-009",
        name: "第9滨海工兵营 · 汐锚",
        role: "engineer",
        slots: 2,
        count: 4,
        speed: 45.,
        air: false,
        specialty: "四名工兵，双倍遗迹搜索；有限工具排雷和修复设施",
    },
    Card {
        id: "MCP-022",
        name: "第22远征装甲连 · 铁潮",
        role: "armor",
        slots: 4,
        count: 3,
        speed: 38.,
        air: false,
        specialty: "两辆装甲战车与一名护卫，装甲抗轻武器，怕反坦克火力",
    },
];
fn card(id: &str) -> E<Card> {
    CARDS
        .iter()
        .find(|c| c.id == id)
        .copied()
        .ok_or_else(|| "该MCP尚未整编开放".into())
}

// All values below belong only to the explicit v2 original mode. The five
// published v1 cards and their body table remain the compatibility baseline.
#[derive(Clone, Copy, Serialize)]
struct Profile {
    id:&'static str,name:&'static str,role:&'static str,nato_type:&'static str,
    bodies:&'static [&'static str],slots:u32,speed:f64,air:bool,
    hp_scale:f64,damage_scale:f64,range_scale:f64,reload_scale:f64,ammo:u32,
    ability:&'static str,charges:u32,cooldown:f64,ability_range:f64,ability_radius:f64,
    readable:&'static str,
}
macro_rules! profile_row {
    ($id:literal,$name:literal,$role:literal,$nato:literal,$bodies:expr,$slots:expr,$speed:expr,$air:expr,$hp:expr,$damage:expr,$range:expr,$reload:expr,$ammo:expr,$ability:literal,$charges:expr,$cooldown:expr,$arange:expr,$radius:expr,$readable:literal)=>{
        Profile{id:$id,name:$name,role:$role,nato_type:$nato,bodies:$bodies,slots:$slots,speed:$speed,air:$air,hp_scale:$hp,damage_scale:$damage,range_scale:$range,reload_scale:$reload,ammo:$ammo,ability:$ability,charges:$charges,cooldown:$cooldown,ability_range:$arange,ability_radius:$radius,readable:$readable}
    }
}
const PROFILES:[Profile;20]=[
    profile_row!("MCP-001","云隼","air_assault","airmobile_infantry",&["marine","marine","helicopter"],2,65.,true,1.,1.,1.,1.,0,"air_rockets",3,18.,1200.,130.,"两名特勤与旋翼机；有限空地火箭，防空威胁大"),
    profile_row!("MCP-034","礁刃","marine","mechanized_infantry",&["marine","marine","marine","ifv"],3,48.,false,1.,1.,1.,1.,0,"suppression",3,16.,1100.,180.,"三步兵与步战车；近岸压制齐射，持续火力稳定"),
    profile_row!("MCP-076","冬鸢","airborne","airborne_infantry",&["vdv","vdv","vdv","gunship"],3,58.,true,1.,1.,1.,1.,0,"air_rockets",3,20.,1400.,110.,"三空降兵与支援机；空中插入，精确反装甲"),
    profile_row!("MCP-009","汐锚","engineer","engineer",&["engineer","engineer","engineer","engineer"],2,45.,false,1.,1.,1.,1.,0,"field_repair",3,15.,600.,500.,"四工兵；双倍搜索排雷，有限工具修复己方设施"),
    profile_row!("MCP-022","铁潮","armor","armor",&["tank","tank","marine"],4,38.,false,1.,1.,1.,1.,0,"hull_down",3,24.,0.,650.,"双装甲车与护卫；抗轻武器，短时阵地防护"),
    profile_row!("MCP-011","灯鲨","marine","naval_infantry",&["marine","marine","marine","scout"],2,62.,false,0.9,1.05,0.95,0.95,80,"smoke",3,20.,0.,600.,"轻装渗透；快速夺点，烟幕换取短时近岸生存"),
    profile_row!("MCP-018","苔原","recon","recon",&["scout","scout","scout","scout"],2,72.,false,0.9,0.9,1.1,0.9,80,"recon_mark",3,18.,1800.,550.,"四侦察体；速度快、搜索快，标定区增强友军命中火力"),
    profile_row!("MCP-027","赤隼","gunship","aviation",&["gunship","helicopter","marine"],4,55.,true,1.1,1.1,1.,1.1,50,"air_rockets",3,24.,1600.,200.,"双旋翼装备；强区域火力，占舱多且受防空克制"),
    profile_row!("MCP-041","雾雀","electronic","electronic_warfare",&["engineer","marine","scout"],2,52.,false,0.95,0.8,1.1,1.,70,"jam",3,25.,1300.,1000.,"电子战小队；限次干扰区延缓敌炮塔和防空装填"),
    profile_row!("MCP-052","白鹭","medic","medical",&["marine","marine","engineer"],2,50.,false,1.05,0.65,0.9,1.,70,"triage",3,25.,600.,600.,"医疗撤收；有限医包止损，不能复活或超过出航整备"),
    profile_row!("MCP-063","断浪","antiarmor","anti_tank",&["anti_tank","anti_tank","marine"],3,44.,false,1.,1.2,1.2,1.,60,"at_missile",3,22.,1700.,100.,"双反装甲组；远距穿甲导弹，近距离持续火力弱"),
    profile_row!("MCP-087","砾火","artillery","artillery",&["howitzer","howitzer","marine"],4,30.,false,1.,1.,1.,1.,45,"barrage",2,30.,2600.,180.,"双火箭炮；越障远射与三发弹幕，500米内无法主炮射击"),
    profile_row!("MCP-103","潮梭","transport","transport",&["ifv","marine","marine"],2,65.,false,0.9,0.8,0.9,0.95,80,"rapid_march",3,18.,0.,650.,"浅滩输送；登陆艇加速，短时机动掩护回收"),
    profile_row!("MCP-116","银脉","logistics","supply",&["marine","marine","marine","engineer"],3,42.,false,1.,0.75,0.95,1.1,110,"resupply",3,20.,550.,550.,"前线补给；携120发有限补充弹药，按真实库存分配"),
    profile_row!("MCP-128","夜莺","sniper","sniper",&["sniper","sniper","sniper","scout"],3,40.,false,0.9,1.05,1.,1.,36,"precision",3,24.,0.,800.,"三狙击与观察员；远程精确，近战脆弱且弹量少"),
    profile_row!("MCP-145","苍穹","airdefense","air_defense",&["aa_team","aa_team","marine"],3,40.,false,1.05,1.,1.,1.,60,"aa_burst",3,20.,2100.,220.,"双防空组；真实可对空，限次区域防空弹幕"),
    profile_row!("MCP-167","苇影","riverine","naval_infantry",&["marine","marine","marine","ifv"],2,68.,false,0.85,0.85,0.9,0.9,80,"smoke",2,22.,0.,500.,"河口快艇；登陆与撤收更快，牺牲装甲换机动"),
    profile_row!("MCP-184","烬羽","breacher","assault_infantry",&["marine","marine","marine","engineer"],3,52.,false,1.1,1.25,0.65,0.9,70,"breach",2,25.,700.,220.,"废城突击；近程高伤爆破，必须靠近才能破障"),
    profile_row!("MCP-203","星桅","command","command",&["marine","marine","marine"],2,46.,false,0.95,0.8,1.,1.,80,"coordination",2,28.,0.,900.,"协同指挥；区域加速装填与行军，本人直接火力较弱"),
    profile_row!("MCP-240","雨燕","rescue","rescue",&["marine","marine","helicopter"],3,70.,true,0.85,0.8,0.95,0.9,55,"rescue",2,24.,500.,500.,"空中撤收；快速回舰与有限急救，不凭空复活身体"),
];
fn profile(id:&str)->Option<&'static Profile>{PROFILES.iter().find(|p|p.id==v4::unit_id(id))}
fn default_transport(id:&str)->&'static str{match v4::unit_id(id){"MCP-001"|"MCP-076"|"MCP-027"|"MCP-240"=>"helicopter","MCP-022"|"MCP-103"=>"amphibious_vehicle",_=>"landing_craft"}}
fn company_kind(config:&Config,id:&str)->E<&'static str>{
    let kind=config.company_transports.iter().find(|x|x.id==id).map_or(default_transport(id),|x|x.kind.as_str());
    let p=profile(id).ok_or("连队身份无效")?;
    match kind{"landing_craft"=>Ok("landing_craft"),"amphibious_vehicle"=>Ok("amphibious_vehicle"),"helicopter" if p.air||["MCP-018","MCP-041","MCP-052","MCP-128","MCP-203"].contains(&id)=>Ok("helicopter"),_=>Err("该连队不能搭乘所选载具".into())}
}
fn company_count(id:&str,kind:&str)->usize{if v4::unit_id(id)!=id{return v4::company_layout(id).1 as usize}let base=if ["MCP-001","MCP-076","MCP-022","MCP-027","MCP-041","MCP-063","MCP-087","MCP-128","MCP-145","MCP-203","MCP-240"].contains(&id){8}else{10};match kind{"helicopter"=>6,"amphibious_vehicle"=>(base-2).max(6),_=>base}}
fn company_bodies(id:&str,kind:&str)->Vec<&'static str>{let p=profile(id).unwrap();let mut v=p.bodies.to_vec();let filler=match p.role{"engineer"|"electronic"|"medic"=>"engineer","recon"=>"scout","airborne"=>"vdv","sniper"=>"sniper",_=>"marine"};v.resize(company_count(id,kind),filler);v}
fn vehicle_meta(id:&str)->(&'static str,&'static str){match v4::unit_id(id){
"MCP-001"=>("云隼轻型突击直升机","light_assault_helicopter"),"MCP-034"=>("礁刃重载登陆艇","heavy_landing_boat"),"MCP-076"=>("冬鸢倾转旋翼机","tiltrotor"),"MCP-009"=>("汐锚抢修登陆艇","engineering_landing_boat"),"MCP-022"=>("铁潮重装两栖战车","heavy_amphibious_tank"),"MCP-011"=>("灯鲨高速冲滩艇","fast_assault_boat"),"MCP-018"=>("苔原侦察气垫艇","recon_hovercraft"),"MCP-027"=>("赤隼武装直升机","attack_helicopter"),"MCP-041"=>("雾雀电子战登陆艇","electronic_warfare_boat"),"MCP-052"=>("白鹭战地救护艇","medical_landing_boat"),"MCP-063"=>("断浪导弹登陆艇","missile_landing_boat"),"MCP-087"=>("砾火火箭支援艇","rocket_support_boat"),"MCP-103"=>("潮梭轮式两栖输送车","wheeled_amphibious_carrier"),"MCP-116"=>("银脉装甲补给艇","armored_supply_boat"),"MCP-128"=>("夜莺低噪潜入艇","stealth_insertion_boat"),"MCP-145"=>("苍穹防空登陆艇","air_defense_boat"),"MCP-167"=>("苇影浅吃水河口艇","shallow_river_boat"),"MCP-184"=>("烬羽破障突击艇","breaching_assault_boat"),"MCP-203"=>("星桅指挥登陆艇","command_landing_boat"),_=>("雨燕救援直升机","rescue_helicopter")}}
fn transport_stats(id:&str,kind:&str)->(f64,f64,f64,bool){
    let (hp,armor,speed,air)=match kind{"helicopter"=>(160.,0.9,320.,true),"amphibious_vehicle"=>(460.,0.42,150.,false),_=>(300.,1.,90.,false)};
    let(h,s)=match v4::unit_id(id){"MCP-001"=>(0.94,1.125),"MCP-034"=>(1.2,0.9),"MCP-076"=>(1.06,0.94),"MCP-009"=>(1.1,0.95),"MCP-022"=>(1.2,0.82),"MCP-011"=>(0.85,1.22),"MCP-018"=>(0.82,1.3),"MCP-027"=>(1.4,0.88),"MCP-041"=>(0.92,1.02),"MCP-052"=>(1.03,1.05),"MCP-063"=>(1.12,0.92),"MCP-087"=>(1.25,0.8),"MCP-103"=>(0.9,1.25),"MCP-116"=>(1.35,0.86),"MCP-128"=>(0.78,1.18),"MCP-145"=>(1.18,0.93),"MCP-167"=>(0.8,1.4),"MCP-184"=>(1.15,1.1),"MCP-203"=>(1.08,0.98),_=>(0.9,1.2)};(hp*h,armor,speed*s,air)
}
fn company_slots(id:&str,kind:&str)->u32{if v4::unit_id(id)!=id{return v4::company_personnel_slots(id,kind,v4::company_layout(id).1).unwrap()}profile(id).unwrap().slots+match kind{"landing_craft"=>2,"amphibious_vehicle"=>3,_=>1}}
fn config_card(config:&Config,id:&str,version:&str)->E<Card>{let mut c=card_for(id,version)?;if matches!(version,VERSION_V3|v4::VERSION){let kind=company_kind(config,id)?;c.count=company_count(id,kind) as u32;c.slots=company_slots(id,kind);c.speed*=2.5;c.air=kind=="helicopter";}Ok(c)}
fn card_for(id:&str,version:&str)->E<Card>{
    if v4::unit_id(id)!=id{return Err("MCP身份未登记".into())}
    if version==VERSION{return card(id)}
    let p=profile(id).ok_or("MCP身份未登记")?;
    if let Ok(c)=card(id){return Ok(c)}
    Ok(Card{id:p.id,name:p.name,role:p.role,slots:p.slots,count:p.bodies.len() as u32,speed:p.speed,air:p.air,specialty:p.readable})
}
fn body_stats(kind:&str)->(f64,f64,f64,u32,f64,bool){
    match kind {
        "marine"=>(100.,22.,700.,15,1.,false),"vdv"=>(95.,30.,850.,18,0.9,false),
        "engineer"=>(95.,16.,600.,18,1.,false),"ifv"=>(260.,42.,1100.,20,0.45,false),
        "tank"=>(420.,100.,1600.,40,0.28,false),"gunship"=>(180.,55.,1400.,18,1.,true),
        "helicopter"=>(150.,32.,1200.,15,1.,true),"anti_tank"=>(110.,80.,900.,35,1.,false),
        "scout"=>(85.,15.,800.,14,1.,false),"sniper"=>(75.,70.,1800.,35,1.,false),
        "howitzer"=>(180.,72.,2400.,55,0.65,false),"aa_team"=>(130.,45.,1800.,20,1.,false),
        _=>(90.,15.,650.,20,1.,false),
    }
}
fn profile_json(p:&Profile)->Value{
    let mut value=json!(p);
    value["entity_count"]=json!(p.bodies.len());value["air_insertion"]=json!(p.air);value["released"]=json!(true);
    value["transport_slots"]=json!(p.slots);value["brief"]=json!(p.readable);
    value["role_label"]=json!(match p.role {"air_assault"=>"空中特勤","marine"=>"海军派遣","airborne"=>"近卫空降","engineer"=>"工兵","armor"=>"装甲","recon"=>"侦察","gunship"=>"旋翼火力","electronic"=>"电子战","medic"=>"医疗","antiarmor"=>"反装甲","artillery"=>"火箭炮","transport"=>"浅滩输送","logistics"=>"后勤","sniper"=>"狙击","airdefense"=>"防空","riverine"=>"河口","breacher"=>"突击","command"=>"指挥",_=>"救援"});
    value["body_kinds"]=value["bodies"].clone();
    value["bodies"]=json!(p.bodies.iter().map(|kind|{let(hp,damage,range,reload,armor,air)=body_stats(kind);json!({"kind":kind,"hp":hp*p.hp_scale,"damage":damage*p.damage_scale,"range":range*p.range_scale,"reload_seconds":((reload as f64*p.reload_scale).round().max(1.))/10.,"speed":p.speed,"armor":armor,"airborne":air,"ammo":if p.ammo>0{p.ammo}else if air{45}else{90}})}).collect::<Vec<_>>());
    value["ability"]=json!({"id":p.ability,"name":ability_name(p.ability),"charges":p.charges,"cooldown":p.cooldown,"range":p.ability_range,"radius":p.ability_radius});
    value
}
fn ability_name(kind:&str)->&'static str{match kind{"air_rockets"=>"空地火箭","suppression"=>"压制齐射","field_repair"=>"应急工程","hull_down"=>"车体掩护","smoke"=>"近岸烟幕","recon_mark"=>"目标标定","jam"=>"链路干扰","triage"=>"战地急救","at_missile"=>"反装甲导弹","barrage"=>"火箭弹幕","rapid_march"=>"快速转进","resupply"=>"前线补弹","precision"=>"精确射击","aa_burst"=>"防空弹幕","breach"=>"爆破突入","coordination"=>"协同指挥",_=>"紧急撤收"}}
pub fn catalogue_version(version:&str)->E<Value>{
    if version==VERSION{return catalogue()}
    if matches!(version,VERSION_V3|v4::VERSION){
        let mut v=catalogue()?;v["version"]=json!(VERSION_V3);v["min_groups"]=json!(2);v["max_groups"]=json!(5);v["friendly_body_budget"]=json!(50);v["body_budget"]=json!(128);v["projectile_budget"]=json!(384);v["ground_speed_multiplier"]=json!(2.5);v["ground_reload_multiplier"]=json!(1./1.8);v["lessons"]=json!(["sea_control","landing","combined"]);
        v["cards"]=json!(PROFILES.iter().map(|p|{let mut row=profile_json(p);let options:Vec<_>=["landing_craft","amphibious_vehicle","helicopter"].into_iter().filter(|kind|*kind!="helicopter"||p.air||["MCP-018","MCP-041","MCP-052","MCP-128","MCP-203"].contains(&p.id)).map(|kind|{let(hp,armor,speed,air)=transport_stats(p.id,kind);let bodies:Vec<_>=company_bodies(p.id,kind).iter().map(|k|{let(hp,damage,range,reload,armor,air)=body_stats(k);json!({"kind":k,"hp":hp*p.hp_scale,"damage":damage*p.damage_scale,"range":range*p.range_scale,"reload_seconds":((reload as f64*p.reload_scale).round().max(1.)/1.8).round().max(1.)/10.,"speed":p.speed*2.5,"armor":armor,"airborne":air,"ammo":if p.ammo>0{p.ammo}else if air{45}else{90}})}).collect();json!({"kind":kind,"personnel_count":bodies.len(),"entity_count":bodies.len(),"transport_slots":company_slots(p.id,kind),"hp":hp,"armor":armor,"speed":speed,"airborne":air,"bodies":bodies,"vehicle_id":format!("{}-{}",p.id,kind),"visual_id":format!("{}-{}",p.id,kind),"vehicle_name":if kind==default_transport(p.id){vehicle_meta(p.id).0}else{p.name},"art_variant":if kind==default_transport(p.id){vehicle_meta(p.id).1}else{kind},"weapon":if p.id=="MCP-027"&&kind=="helicopter"{json!({"ammo":12,"damage":60,"range":1400,"reload_seconds":1.2})}else{Value::Null}})}).collect();let selected=options.iter().find(|x|x["kind"]==default_transport(p.id)).unwrap();row["default_transport"]=json!(default_transport(p.id));row["transport_options"]=json!(options);for key in ["entity_count","transport_slots","bodies"]{row[key]=selected[key].clone();}row["vehicle_id"]=selected["vehicle_id"].clone();row["vehicle_name"]=selected["vehicle_name"].clone();row["art_variant"]=selected["art_variant"].clone();row["company_count"]=json!(1);row["speed"]=json!(p.speed*2.5);row}).collect::<Vec<_>>());return Ok(v)
    }
    if version!=VERSION_V2{return Err("两栖规则版本无效".into())}
    let mut v=catalogue()?;v["version"]=json!(VERSION_V2);v["max_groups"]=json!(6);v["friendly_body_budget"]=json!(32);v["cards"]=json!(PROFILES.iter().map(profile_json).collect::<Vec<_>>());Ok(v)
}
fn capacity(kind: &str, ammo: u32) -> u32 {
    let base = match kind.to_ascii_lowercase().as_str() {
        "ap" | "apa" | "lst" | "lsi" | "lsd" => 20,
        "ak" | "aka" | "transport" | "tr" | "av" => 16,
        "bb" | "bc" => 6,
        "ca" | "cl" | "cv" | "cvl" => 4,
        _ => 2,
    };
    base + (100 - ammo) / 20
}
fn transport_role(kind: &str) -> &'static str {
    if [
        "ap",
        "apa",
        "lst",
        "lsi",
        "lsd",
        "ak",
        "aka",
        "transport",
        "tr",
        "av",
    ]
    .contains(&kind.to_ascii_lowercase().as_str())
    {
        "transport_support"
    } else {
        "warship"
    }
}
pub fn catalogue() -> E<Value> {
    let d = crate::salvage_v3::data()?;
    Ok(
        json!({"version":VERSION,"simulation_hz":HZ,"duration":480,"modes":["tutorial","raid","defense","salvage"],"cards":CARDS.iter().map(|c|json!({"id":c.id,"name":c.name,"role":c.role,"slots":c.slots,"entity_count":c.count,"air_insertion":c.air,"specialty":c.specialty,"released":true})).collect::<Vec<_>>(),"ships":d.ships.iter().filter(|s|s.id.starts_with("IBS-U-")).map(|s|json!({"id":s.id,"name":s.name,"kind":s.kind,"transport_role":transport_role(&s.kind),"slots_combat":capacity(&s.kind,100),"slots_balanced":capacity(&s.kind,70),"slots_transport":capacity(&s.kind,40)})).collect::<Vec<_>>(),"presets":{"combat":100,"balanced":70,"transport":40}}),
    )
}
pub fn frames(v: &Value) -> E<u32> {
    let n = v.as_f64().ok_or("两栖推进秒数无效")?;
    if !n.is_finite() || !(0. ..=2700.).contains(&n) || (n * 10. - (n * 10.).round()).abs() > 1e-6 {
        return Err("两栖推进须为0.1秒的非负倍数".into());
    }
    Ok((n * 10.).round() as u32)
}
fn inside(poly: &[P], p: P) -> bool {
    let mut yes = false;
    for i in 0..poly.len() {
        let a = poly[i];
        let b = poly[(i + 1) % poly.len()];
        if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
            yes = !yes;
        }
    }
    yes
}
fn bounded(list: &mut VecDeque<Value>, v: Value) {
    if list.len() == RECENT {
        list.pop_front();
    }
    list.push_back(v);
}
fn arc(a: f64, r: [f64; 2]) -> bool {
    if (r[1] - r[0]).abs() >= 359.9 {
        return true;
    }
    let a = norm(a);
    let l = norm(r[0]);
    let h = norm(r[1]);
    if l <= h {
        a >= l && a <= h
    } else {
        a >= l || a <= h
    }
}
#[derive(Clone)]
struct SeaShip {
    id: u32,
    def: crate::model::ShipDef,
    ally: bool,
    p: P,
    h: f64,
    facing: Option<f64>,
    pending_support: Option<(P, u32)>,
    aim_target:Option<P>,
    deployment_route:bool,
    hp: f64,
    max: f64,
    initial: f64,
    requested: u32,
    loaded: u32,
    ammo: u32,
    slots: u32,
    speed: f64,
    path: Vec<P>,
    next: u32,
    anchor: bool,
    unmoor: u32,
    ai: bool,
    last_plan: u32,
}
#[derive(Clone)]
struct Body {
    id: u32,
    group: String,
    ally: bool,
    kind: &'static str,
    p: P,
    hp: f64,
    max: f64,
    ammo: u32,
    damage: f64,
    range: f64,
    reload: u32,
    next: u32,
    armor: f64,
    air: bool,
    active: bool,
}
#[derive(Clone)]
struct Group {
    card: Card,
    carrier: u32,
    stage: &'static str,
    insertion: &'static str,
    p: P,
    path: Vec<P>,
    order: String,
    target: Option<u32>,
    initial: f64,
    transit_health: f64,
    supplies: u32,
    beach: u32,
    pending: Option<(u32, bool)>,
    ability_charges: u32,
    ability_next: u32,
    buff_until: u32,
    buff_point:P,
    reserve_ammo: u32,
    transport_kind:&'static str,
    vehicle_ammo:u32,vehicle_next:u32,
}
#[derive(Clone)]
struct Transport {
    id: u32,
    group: usize,
    carrier: u32,
    p: P,
    goal: P,
    hp: f64,
    max: f64,
    air: bool,
    returning: bool,
}
#[derive(Clone)]
struct Building {
    id: String,
    kind: String,
    ally: bool,
    p: P,
    hp: f64,
    max: f64,
    level: u32,
    ammo: u32,
    next: u32,
}
#[derive(Clone)]
struct Ruin {
    id: u32,
    p: P,
    progress: u32,
    searched: bool,
}
#[derive(Clone)]
struct Mine {
    id: u32,
    p: P,
    active: bool,
}
#[derive(Clone, Serialize)]
struct Loot {
    id: String,
    kind: String,
    amount: u32,
    holder: String,
}
#[derive(Clone)]
struct Projectile {
    id: u32,
    ally: bool,
    p: P,
    goal: P,
    speed: f64,
    damage: f64,
    radius: f64,
    air_only: bool,
    kind: &'static str,
    source: String,
}

pub struct Littoral {
    version: &'static str,
    pub seed: u32,
    pub config: Config,
    pub frame: u32,
    pub result: Option<Value>,
    polygon: Vec<P>,
    obstacles: Vec<Vec<P>>,
    ships: Vec<SeaShip>,
    groups: Vec<Group>,
    bodies: Vec<Body>,
    transports: Vec<Transport>,
    v4_transport_losses: Vec<Transport>,
    buildings: Vec<Building>,
    ruins: Vec<Ruin>,
    mines: Vec<Mine>,
    loot: Vec<Loot>,
    projectiles: Vec<Projectile>,
    events: VecDeque<Value>,
    shots: VecDeque<Value>,
    impacts: VecDeque<Value>,
    commands: Vec<Command>,
    next_id: u32,
    capture: u32,
    landed_companies:BTreeSet<String>,
    shore_support_hits:u32,
    enemy_dead: u32,
    v4_body_paths:std::collections::BTreeMap<u32,(P,u32,Vec<P>)>,
    island_geometry:Option<v4::island_war::Geometry>,
}
impl Littoral {
    fn body_limit(&self)->usize{if self.version==v4::VERSION&&self.config.company_layout.as_deref()==Some(v4::MULTI){return 320}if matches!(self.version,VERSION_V3|v4::VERSION){128}else{MAX_BODIES}}
    fn projectile_limit(&self)->usize{if self.version==v4::VERSION&&self.config.company_layout.as_deref()==Some(v4::MULTI){return 512}if matches!(self.version,VERSION_V3|v4::VERSION){384}else{MAX_PROJECTILES}}
    fn lesson(&self)->&str{self.config.lesson.as_deref().unwrap_or("landing")}
    pub fn new(seed: u32, config: Config) -> E<Self> {
        Self::new_version(seed, config, VERSION)
    }
    pub fn new_version(seed: u32, config: Config, version: &str) -> E<Self> {
        let version=match version {VERSION=>VERSION,VERSION_V2=>VERSION_V2,VERSION_V3=>VERSION_V3,v4::VERSION=>v4::VERSION,_=>return Err("两栖规则版本无效".into())};
        if !["tutorial", "raid", "defense", "salvage"].contains(&config.mode.as_str())
            || config.ships.is_empty()
            || config.ships.len() > 6
            || config.roster.is_empty()
            || config.roster.len() > if version==VERSION_V2 {6} else {5}
            || matches!(version,VERSION_V3|v4::VERSION) && config.roster.len()<2
            || config.defense.len() > 16
        {
            return Err("两栖任务、舰数、部队或设施数量无效".into());
        }
        if let Some(layout)=&config.company_layout{if version!=v4::VERSION||layout!=v4::MULTI{return Err("连队编制版本无效".into())}}
        let cap = match config.transport_preset.as_str() {
            "combat" => 100,
            "balanced" => 70,
            "transport" => 40,
            _ => return Err("运输预设无效".into()),
        };
        let mut seen = BTreeSet::new();
        let data = if version==v4::VERSION {v4::extended_data()?}else{crate::salvage_v3::data()?};
        let mut ships = vec![];
        for (i, h) in config.ships.iter().enumerate() {
            if !seen.insert(&h.id)
                || !h.hp.is_finite()
                || !(1. ..=100.).contains(&h.hp)
                || h.ammo > 100
            {
                return Err("舰娘重复、耐久或弹药无效".into());
            }
            let def = data
                .ships
                .iter()
                .find(|s| s.id == h.id && (s.id.starts_with("IBS-U-")||version==v4::VERSION&&[v4::ENTERPRISE,v4::SHOKAKU,v4::LHA,v4::APV].contains(&s.id.as_str())))
                .ok_or("舰娘身份未登记")?
                .clone();
            let loaded = h.ammo.min(cap);
            let max = if version==v4::VERSION {def.dp}else{(def.dp * 5.).max(300.)};
            let p = if version!=VERSION && config.mode=="tutorial" {P{x:12000.+i as f64*220.,y:12200.+i as f64*180.}}else if config.mode == "defense" {
                P {
                    x: 18500. + i as f64 * 300.,
                    y: 6800. + i as f64 * 250.,
                }
            } else {
                P {
                    x: 5500. + i as f64 * 300.,
                    y: 13000. + i as f64 * 220.,
                }
            };
            ships.push(SeaShip {
                id: i as u32 + 1,
                slots: if version==v4::VERSION {v4::carrier_capacity(&h.id,loaded)?}else{capacity(&def.kind, loaded)},
                def,
                ally: true,
                p,
                h: 90.,
                facing: None,
                pending_support: None,
                aim_target:None,
                deployment_route:false,
                hp: max * h.hp / 100.,
                max,
                initial: h.hp,
                requested: h.ammo,
                loaded,
                ammo: loaded,
                speed: 0.,
                path: vec![],
                next: 0,
                anchor: config.mode == "defense",
                unmoor: 0,
                ai: config.mode == "defense",
                last_plan: 0,
            });
        }
        seen.clear();
        for id in &config.roster {
            if !seen.insert(id) {
                return Err("MCP部署不能重复".into());
            }
            card_for(id,version)?;
        }
        if !config.unit_condition.is_empty() {
            let set: BTreeSet<_> = config.unit_condition.iter().map(|c| &c.id).collect();
            if set != seen
                || set.len() != config.unit_condition.len()
                || config
                    .unit_condition
                    .iter()
                    .any(|c| !c.hp.is_finite() || !(10. ..=100.).contains(&c.hp))
            {
                return Err("部队整备率须与部署身份一致且至少10%".into());
            }
        }
        let mut slots: Vec<u32> = ships.iter().map(|s| s.slots).collect();
        let mut groups = vec![];
        if !matches!(version,VERSION_V3|v4::VERSION) && (!config.company_transports.is_empty()||config.lesson.is_some()){return Err("新连队/训练配置只用于v3".into())}
        if let Some(lesson)=&config.lesson{if config.mode!="tutorial"||!["sea_control","landing","combined"].contains(&lesson.as_str()){return Err("训练课程无效".into())}}
        if !config.company_transports.is_empty(){let a:BTreeSet<_>=config.company_transports.iter().map(|x|x.id.as_str()).collect();let b:BTreeSet<_>=config.roster.iter().map(String::as_str).collect();if a!=b||a.len()!=config.company_transports.len(){return Err("连队载具配置须与本次身份集精确一致".into())}}
        let mut ids = config.roster.clone();
        ids.sort_by_key(|id| std::cmp::Reverse(config_card(&config,id,version).map_or(0,|c|c.slots)));
        for id in ids {
            let c = config_card(&config,&id,version)?;
            let index = if config.mode == "defense" {
                0
            } else {
                slots
                    .iter()
                    .enumerate()
                    .filter(|(i, n)| **n >= c.slots && (version!=v4::VERSION || v4::carrier_eligibility(&id,company_kind(&config,&id).unwrap_or("landing_craft"),&ships[*i].def.id).is_ok()))
                    .max_by_key(|(i, n)| {
                        (
                            transport_role(&ships[*i].def.kind) == "transport_support",
                            **n,
                        )
                    })
                    .map(|(i, _)| i)
                    .ok_or("运输舱不足；少装炮弹、增加舰船或减少部队")?
            };
            if config.mode != "defense" {
                slots[index] -= c.slots;
            }
            let initial = config
                .unit_condition
                .iter()
                .find(|n| n.id == id)
                .map_or(100., |n| n.hp);
            groups.push(Group {
                card: c,
                carrier: ships[index].id,
                stage: "embarked",
                insertion: "landing",
                p: ships[index].p,
                path: vec![],
                order: "hold".into(),
                target: None,
                initial,
                transit_health: 1.,
                supplies: 12,
                beach: 2,
                pending:None,
                ability_charges: if version!=VERSION {profile(&id).unwrap().charges} else {0},
                ability_next:0,
                buff_until:0,
                buff_point:ships[index].p,
                reserve_ammo:if version!=VERSION && id=="MCP-116" {120} else {0},
                transport_kind:if matches!(version,VERSION_V3|v4::VERSION) {company_kind(&config,&id)?}else{"legacy"},
                vehicle_ammo:if matches!(version,VERSION_V3|v4::VERSION)&&id=="MCP-027"&&company_kind(&config,&id)?=="helicopter"{12}else{0},vehicle_next:0,
            });
        }
        groups.sort_by_key(|g| config.roster.iter().position(|s| s == g.card.id).unwrap());
        let mut rng = seed as u64 ^ 0x6b92_7cd5_4183;
        let mut jitter = || crate::world::roll(&mut rng, 301) as f64 - 150.;
        let polygon = [
            (8700., 4800.),
            (10000., 3500.),
            (13000., 3000.),
            (16000., 3400.),
            (17600., 5000.),
            (17900., 7600.),
            (16400., 9700.),
            (13000., 10300.),
            (10000., 9700.),
            (8500., 7800.),
        ]
        .iter()
        .map(|(x, y)| P {
            x: x + jitter(),
            y: y + jitter(),
        })
        .collect();
        let obstacles = vec![
            vec![
                P {
                    x: 11200.,
                    y: 6700.,
                },
                P {
                    x: 11900.,
                    y: 6700.,
                },
                P {
                    x: 11900.,
                    y: 7100.,
                },
                P {
                    x: 11200.,
                    y: 7100.,
                },
            ],
            vec![
                P {
                    x: 14500.,
                    y: 7400.,
                },
                P {
                    x: 15000.,
                    y: 7400.,
                },
                P {
                    x: 15000.,
                    y: 8000.,
                },
                P {
                    x: 14500.,
                    y: 8000.,
                },
            ],
        ];
        let mut w = Self {
            version,
            seed,
            config,
            frame: 0,
            result: None,
            polygon,
            obstacles,
            ships,
            groups,
            bodies: vec![],
            transports: vec![],
            buildings: vec![],
            ruins: vec![
                Ruin {
                    id: 1,
                    p: P {
                        x: 12600.,
                        y: 9000.,
                    },
                    progress: 0,
                    searched: false,
                },
                Ruin {
                    id: 2,
                    p: P {
                        x: 15100.,
                        y: 6500.,
                    },
                    progress: 0,
                    searched: false,
                },
                Ruin {
                    id: 3,
                    p: P {
                        x: 10400.,
                        y: 5500.,
                    },
                    progress: 0,
                    searched: false,
                },
            ],
            mines: vec![],
            loot: vec![],
            projectiles: vec![],
            events: VecDeque::new(),
            shots: VecDeque::new(),
            impacts: VecDeque::new(),
            commands: vec![],
            next_id: 100,
            capture: 0,
            landed_companies:BTreeSet::new(),shore_support_hits:0,
            enemy_dead: 0,
            v4_body_paths:Default::default(),
            island_geometry:None,
            v4_transport_losses:vec![],
        };
        let forts = if w.config.defense.is_empty() {
            vec![
                Fort {
                    id: "hq".into(),
                    kind: "hq".into(),
                    x: 0.55,
                    y: 0.3,
                    level: 1,
                    hp: 100.,
                },
                Fort {
                    id: "aa".into(),
                    kind: "aa".into(),
                    x: 0.75,
                    y: 0.55,
                    level: 1,
                    hp: 100.,
                },
                Fort {
                    id: "turret".into(),
                    kind: "turret".into(),
                    x: 0.3,
                    y: 0.7,
                    level: 1,
                    hp: 100.,
                },
            ]
        } else {
            w.config.defense.clone()
        };
        let mut fort_ids = BTreeSet::new();
        for f in forts {
            if !fort_ids.insert(f.id.clone())
                || f.id.is_empty()
                || f.id.len() > 64
                || !["hq", "turret", "aa", "depot"].contains(&f.kind.as_str())
                || !(1..=3).contains(&f.level)
                || ![f.x, f.y, f.hp].iter().all(|n| n.is_finite())
                || !(0. ..=1.).contains(&f.x)
                || !(0. ..=1.).contains(&f.y)
                || !(0. ..=100.).contains(&f.hp)
            {
                return Err("设施身份、类型、位置、等级或耐久无效".into());
            }
            let p = P {
                x: 10300. + f.x * 3800.,
                y: 5000. + f.y * 3600.,
            };
            if !inside(&w.polygon, p) {
                return Err("设施位置不在岛内".into());
            }
            let max = match f.kind.as_str() {
                "hq" => 900.,
                "aa" => 260.,
                "turret" => 320.,
                _ => 350.,
            } * f.level as f64;
            w.buildings.push(Building {
                id: f.id,
                kind: f.kind,
                ally: w.config.mode == "defense",
                p,
                hp: max * f.hp / 100.,
                max,
                level: f.level,
                ammo: 100,
                next: 20,
            });
        }
        if w.buildings.iter().filter(|b| b.kind == "hq").count() != 1 {
            return Err("岛屿必须恰有一个指挥部".into());
        }
        if w.config.mode == "defense" {
            for i in 0..w.groups.len() {
                w.groups[i].p = P {
                    x: 12400. + i as f64 * 180.,
                    y: 6500.,
                };
                w.groups[i].stage = "ground";
                w.groups[i].order = "defend".into();
                w.spawn_group(i);
            }
        } else {
            for i in 0..if w.config.mode == "tutorial" {if matches!(w.version,VERSION_V3|v4::VERSION)&&w.lesson()=="combined"{6}else{3}} else if matches!(w.version,VERSION_V3|v4::VERSION){18}else{9} {
                let p = P {
                    x: 11800. + (i % 3) as f64 * 700.,
                    y: 7100. + (i / 3) as f64 * 600.,
                };
                w.spawn_enemy(p, if i % 4 == 3 { "anti_tank" } else { "rifle" });
            }
            if w.config.mode != "tutorial" {
                for i in 0..4 {
                    w.mines.push(Mine {
                        id: i + 1,
                        p: P {
                            x: 11900. + i as f64 * 450.,
                            y: 8500.,
                        },
                        active: true,
                    });
                }
            }
        }
        let enemy_count = if w.config.mode == "tutorial" { 1 } else { 2 };
        for i in 0..enemy_count {
            let def = data
                .ships
                .iter()
                .find(|s| {
                    s.id == if i == 0 {
                        "IBS-U-USN-FLETCHER"
                    } else {
                        "IBS-U-USN-PENSACOLA"
                    }
                })
                .unwrap()
                .clone();
            let max = if matches!(w.version,VERSION_V3|v4::VERSION)&&w.config.mode=="tutorial"&&w.lesson()=="sea_control" {600.}else if w.config.mode == "tutorial" {
                160.
            } else {
                (def.dp * 2.5).max(280.)
            };
            let p = if matches!(w.version,VERSION_V3|v4::VERSION)&&w.config.mode=="tutorial"&&w.lesson()=="sea_control"{P{x:17000.,y:14000.}}else if w.config.mode == "defense" {
                P {
                    x: 18500. + i as f64 * 800.,
                    y: 13600.,
                }
            } else {
                P {
                    x: 18700. + i as f64 * 350.,
                    y: 6500. + i as f64 * 400.,
                }
            };
            w.ships.push(SeaShip {
                id: 1001 + i,
                def,
                ally: false,
                p,
                h: 180.,
                facing: None,
                pending_support: None,
                aim_target:None,
                deployment_route:false,
                hp: max,
                max,
                initial: 100.,
                requested: 70,
                loaded: 70,
                ammo: 70,
                slots: 0,
                speed: 0.,
                path: vec![],
                next: 60,
                anchor: true,
                unmoor: 0,
                ai: true,
                last_plan: 0,
            });
        }
        w.event(
            "start",
            "装载已冻结；选择滩头，真实运输登陆，保留炮弹支援并撤收。",
            P {
                x: 13000.,
                y: 10000.,
            },
        );
        Ok(w)
    }
    pub fn tick(&self) -> f64 {
        self.frame as f64 / 10.
    }
    fn id(&mut self) -> u32 {
        self.next_id += 1;
        self.next_id
    }
    fn event(&mut self, kind: &str, text: &str, p: P) {
        let id = self.id();
        bounded(
            &mut self.events,
            json!({"id":id,"kind":kind,"text":text,"tick":self.frame as f64/10.,"frame":self.frame,"x":p.x,"y":p.y}),
        );
    }
    fn beach(id: u32) -> E<(P, P)> {
        match id {
            1 => Ok((
                P {
                    x: 10000.,
                    y: 11000.,
                },
                P {
                    x: 10400.,
                    y: 9300.,
                },
            )),
            2 => Ok((
                P {
                    x: 13000.,
                    y: 11500.,
                },
                P {
                    x: 13000.,
                    y: 9800.,
                },
            )),
            3 => Ok((
                P {
                    x: 16400.,
                    y: 10900.,
                },
                P {
                    x: 15800.,
                    y: 9400.,
                },
            )),
            _ => Err("滩头不存在".into()),
        }
    }
    fn beach_for(&self,id:u32)->E<(P,P)>{if let Some(g)=&self.island_geometry{return g.beach(id)}let(a,b)=Self::beach(id)?;Ok(if self.version==v4::VERSION{(v4::map_position(a),v4::map_position(b))}else{(a,b)})}
    fn position_for(&self,q:&Value)->E<P>{if self.version!=v4::VERSION{return Self::position(q)}let p=P{x:q["x"].as_f64().ok_or("缺少目标横坐标")?,y:q["y"].as_f64().ok_or("缺少目标纵坐标")?};if !p.x.is_finite()||!p.y.is_finite()||p.x<200.||p.x>v4::MAP_WIDTH-200.||p.y<200.||p.y>v4::MAP_HEIGHT-200.{return Err("目标坐标超出战场".into())}Ok(p)}
    fn walkable(&self, p: P, land: bool) -> bool {
        p.x.is_finite()
            && p.y.is_finite()
            && (200. ..=if self.version==v4::VERSION{v4::MAP_WIDTH-200.}else{WIDTH-200.}).contains(&p.x)
            && (200. ..=if self.version==v4::VERSION{v4::MAP_HEIGHT-200.}else{HEIGHT-200.}).contains(&p.y)
            && inside(&self.polygon, p) == land
            && (!land || self.obstacles.iter().all(|o| if self.version==v4::VERSION{!v4::strict_inside(o,p)}else{!inside(o, p)}))
    }
    fn clear(&self, a: P, b: P, land: bool) -> bool {
        if self.version==v4::VERSION&&land{return v4::clear_ground(self,a,b)}
        let n = (a.dist(b) / 70.).ceil().max(1.) as u32;
        (0..=n).all(|i| self.walkable(a + (b - a) * (i as f64 / n as f64), land))
    }
    fn path(&self, start: P, goal: P, land: bool) -> E<Vec<P>> {
        if !self.walkable(goal, land) {
            return Err(if land {
                "目标不在可通行陆地"
            } else {
                "目标不在可航行水面"
            }
            .into());
        }
        if self.clear(start, goal, land) {
            return Ok(vec![goal]);
        }
        let fine=self.version==v4::VERSION&&land;
        let cell=if fine{40.}else{400.};
        let origin=if let Some(g)=&self.island_geometry{g.origin()}else if fine{P{x:9600.,y:9800.}}else{P{x:0.,y:0.}};
        let nx:usize=if let Some(g)=&self.island_geometry{g.grid().0}else if fine{145}else if self.version==v4::VERSION{75}else{60};
        let ny:usize=if let Some(g)=&self.island_geometry{g.grid().1}else if fine{170}else if self.version==v4::VERSION{63}else{40};
        let point = |n: usize| P {
            x: origin.x+(n % nx) as f64 * cell + cell / 2.,
            y: origin.y+(n / nx) as f64 * cell + cell / 2.,
        };
        let nearest = |p: P| -> Option<usize> {
            (0..nx * ny)
                .filter(|n| {
                    point(*n).dist(p) < 1000.
                        && self.walkable(point(*n), land)
                        && self.clear(p, point(*n), land)
                })
                .min_by(|a, b| point(*a).dist(p).total_cmp(&point(*b).dist(p)))
        };
        let s = nearest(start).ok_or("起点没有可用通路")?;
        let t = nearest(goal).ok_or("终点没有可用通路")?;
        let mut cost = vec![u32::MAX; nx * ny];
        let mut prev = vec![usize::MAX; nx * ny];
        let mut open = BinaryHeap::new();
        cost[s] = 0;
        open.push((std::cmp::Reverse(0u32), std::cmp::Reverse(s)));
        while let Some((_, std::cmp::Reverse(n))) = open.pop() {
            if n == t {
                break;
            }
            for (dx, dy) in [
                (-1, -1),
                (-1, 0),
                (-1, 1),
                (0, -1),
                (0, 1),
                (1, -1),
                (1, 0),
                (1, 1),
            ] {
                let x = n % nx;
                let y = n / nx;
                let a = x as i32 + dx;
                let b = y as i32 + dy;
                if a < 0 || b < 0 || a >= nx as i32 || b >= ny as i32 {
                    continue;
                }
                let next = b as usize * nx + a as usize;
                if !self.clear(point(n), point(next), land) {
                    continue;
                }
                let c = cost[n] + if dx != 0 && dy != 0 { 14 } else { 10 };
                if c < cost[next] {
                    cost[next] = c;
                    prev[next] = n;
                    let h = (point(next).dist(point(t)) / cell * 10.) as u32;
                    open.push((std::cmp::Reverse(c + h), std::cmp::Reverse(next)));
                }
            }
        }
        if cost[t] == u32::MAX {
            return Err("没有可行通路".into());
        }
        let mut nodes = vec![goal];
        let mut n = t;
        while n != s {
            nodes.push(point(n));
            n = prev[n];
        }
        nodes.push(point(s));
        nodes.reverse();
        let mut simple = vec![];
        let mut p = start;
        let mut i = 0;
        while i < nodes.len() {
            let mut j = nodes.len() - 1;
            while j > i && !self.clear(p, nodes[j], land) {
                j -= 1;
            }
            simple.push(nodes[j]);
            p = nodes[j];
            i = j + 1;
        }
        Ok(simple)
    }
    fn v4_step_body(&mut self,index:usize,goal:P,speed:f64){
        let b=&self.bodies[index];let id=b.id;let origin=b.p;let air=b.air;
        let waypoint=if air||self.clear(origin,goal,true){self.v4_body_paths.remove(&id);Some(goal)}else{
            let stale=self.v4_body_paths.get(&id).is_none_or(|(old,t,path)|old.dist(goal)>300.||path.is_empty()||self.frame>*t+60);
            if stale {if let Ok(path)=self.path(origin,goal,true){self.v4_body_paths.insert(id,(goal,self.frame,path));}else{return}}
            let Some((_,_,path))=self.v4_body_paths.get_mut(&id)else{return};while path.first().is_some_and(|p|p.dist(origin)<speed*DT+1.){path.remove(0);}path.first().copied().or(Some(goal))};
        if let Some(p)=waypoint{let d=origin.dist(p);if d>0.01{let next=origin+(p-origin)*(speed*DT/d).min(1.);if air||self.clear(origin,next,true){self.bodies[index].p=next;}}}
    }
    fn body(&mut self, group: String, ally: bool, kind: &'static str, p: P, condition: f64) {
        if self.bodies.len() >= self.body_limit() {
            return;
        }
        let (mut hp, mut damage, mut range, mut reload, armor, air) = body_stats(kind);
        let mut ammo=if air {45}else{90};
        if self.version!=VERSION && ally {
            if let Some(p)=profile(&group){hp*=p.hp_scale;damage*=p.damage_scale;range*=p.range_scale;reload=(reload as f64*p.reload_scale).round().max(1.) as u32;if p.ammo>0{ammo=p.ammo}}
        }
        if matches!(self.version,VERSION_V3|v4::VERSION){reload=(reload as f64/1.8).round().max(1.) as u32;}
        let id = self.id();
        self.bodies.push(Body {
            id,
            group,
            ally,
            kind,
            p,
            hp: hp * condition / 100.,
            max: hp,
            ammo,
            damage,
            range,
            reload,
            next: self.frame + 3,
            armor,
            air,
            active: true,
        });
    }
    fn spawn_group(&mut self, index: usize) {
        let g = self.groups[index].clone();
        let kinds: Vec<_> = if matches!(self.version,VERSION_V3|v4::VERSION){company_bodies(g.card.id,g.transport_kind)}else if self.version!=VERSION {profile(g.card.id).unwrap().bodies.to_vec()}else{match g.card.role {
            "helicopter" => vec!["marine", "marine", "helicopter"],
            "marine" => vec!["marine", "marine", "marine", "ifv"],
            "vdv" => vec!["vdv", "vdv", "vdv", "gunship"],
            "engineer" => vec!["engineer"; 4],
            _ => vec!["tank", "tank", "marine"],
        }};
        for (i, k) in kinds.into_iter().enumerate() {
            let p = g.p
                + P {
                    x: if matches!(self.version,VERSION_V3|v4::VERSION){(i%3) as f64*65.-65.}else{(i % 2) as f64 * 90. - 45.},
                    y: if matches!(self.version,VERSION_V3|v4::VERSION){(i/3) as f64*65.-65.}else{(i / 2) as f64 * 90. - 45.},
                };
            let p = if self.walkable(p, true) { p } else { g.p };
            self.body(g.card.id.into(), true, k, p, g.initial * g.transit_health);
        }
        if matches!(self.version,VERSION_V3|v4::VERSION){self.landed_companies.insert(g.card.id.into());}
        self.event("landed", &format!("{} 已实际到达陆地", g.card.name), g.p);
    }
    fn spawn_enemy(&mut self, p: P, kind: &'static str) {
        let p=if self.version==v4::VERSION&&self.frame>0{v4::map_position(p)}else{p};
        if self.bodies.iter().filter(|b| !b.ally && b.hp > 0.).count() < 64
            && self.walkable(p, true)
        {
            let group = format!("defender-{}", self.next_id);
            self.body(group, false, kind, p, 100.);
        }
    }
    fn group_health(&self, i: usize) -> f64 {
        let g = &self.groups[i];
        if g.stage == "lost" {
            return 0.;
        }
        let actors: Vec<_> = self
            .bodies
            .iter()
            .filter(|b| b.group == g.card.id && b.ally)
            .collect();
        if actors.is_empty() {
            g.initial * g.transit_health
        } else {
            actors.iter().map(|b| b.hp.max(0.)).sum::<f64>()
                / actors.iter().map(|b| b.max).sum::<f64>()
                * 100.
        }
    }
    fn gun_arcs(s: &SeaShip) -> Vec<[f64; 2]> {
        if s.def.gun.mounts.is_empty() {
            vec![[0., 360.]]
        } else {
            s.def
                .gun
                .mounts
                .iter()
                .flat_map(|m| std::iter::once(m.arc).chain(m.arc2))
                .collect()
        }
    }
    fn gun_error(&self, index: usize, p: P, waiting: bool) -> Option<String> {
        let s = &self.ships[index];
        if s.hp <= 0. {
            return Some("支援舰已经沉没".into());
        }
        if s.def.gun.barrels == 0 {
            return Some("该舰没有可用舰炮".into());
        }
        if s.ammo < Self::gun_cost(s) {
            return Some("舰炮弹药已耗尽".into());
        }
        if s.anchor {
            return Some("先起锚才可提供炮火支援".into());
        }
        if !waiting && self.frame < s.next {
            return Some("舰炮仍在装填".into());
        }
        let range = s.def.gun.range_yd.last().copied().unwrap_or(0.) * YARD;
        if s.p.dist(p) > range {
            return Some("目标超出该舰真实炮程".into());
        }
        let a = (p - s.p).heading() - s.h;
        if !waiting && !Self::gun_arcs(s).iter().any(|r| arc(a, *r)) {
            return Some("目标不在该舰当前炮座射界内".into());
        }
        None
    }
    fn launch(
        &mut self,
        ally: bool,
        p: P,
        goal: P,
        damage: f64,
        radius: f64,
        speed: f64,
        air_only: bool,
        kind: &'static str,
        source: String,
    ) -> bool {
        if self.projectiles.len() >= self.projectile_limit() {
            return false;
        }
        let id = self.id();
        self.projectiles.push(Projectile {
            id,
            ally,
            p,
            goal,
            speed,
            damage,
            radius,
            air_only,
            kind,
            source: source.clone(),
        });
        bounded(
            &mut self.shots,
            json!({"id":id,"frame":self.frame,"tick":self.frame as f64/10.,"kind":kind,"source":source,"side":if ally{"allies"}else{"axis"},"x":p.x,"y":p.y,"target_x":goal.x,"target_y":goal.y,"radius":radius,"damage":damage}),
        );
        true
    }
    fn naval_fire(&mut self, index: usize, p: P) -> E<()> {
        if let Some(e) = self.gun_error(index, p, false) {
            return Err(e);
        }
        let s = &self.ships[index];
        let damage = (s.def.gun.caliber_mm * 0.35 + s.def.gun.barrels as f64 * 4.).clamp(35., 250.);
        let ally = s.ally;
        let origin = s.p;
        let id = s.id;
        let caliber = s.def.gun.caliber_mm;
        let radius = (caliber * 0.65).clamp(100., 300.);
        if !self.launch(
            ally,
            origin,
            p,
            damage,
            radius,
            900.,
            false,
            "naval",
            format!("ship:{id}"),
        ) {
            return Err("弹体预算暂满".into());
        }
        let s = &mut self.ships[index];
        s.ammo -= Self::gun_cost(s);
        s.next = self.frame + if caliber >= 300. { 100 } else { 70 };
        Ok(())
    }
    fn gun_cost(s: &SeaShip) -> u32 {
        if s.def.gun.caliber_mm >= 300. {
            3
        } else if s.def.gun.caliber_mm >= 180. {
            2
        } else {
            1
        }
    }
    fn position(q: &Value) -> E<P> {
        let p = P {
            x: q["x"].as_f64().ok_or("缺少目标横坐标")?,
            y: q["y"].as_f64().ok_or("缺少目标纵坐标")?,
        };
        if !p.x.is_finite()
            || !p.y.is_finite()
            || !(200. ..=WIDTH - 200.).contains(&p.x)
            || !(200. ..=HEIGHT - 200.).contains(&p.y)
        {
            return Err("目标坐标超出战场".into());
        }
        Ok(p)
    }
    fn route(&mut self, points: Vec<P>, speed: f64) -> E<()> {
        if points.is_empty()
            || points.len() > 12
            || !speed.is_finite()
            || !(4. ..=40.).contains(&speed)
        {
            return Err("海上航点或速度无效".into());
        }
        let lead = self
            .ships
            .iter()
            .find(|s| s.ally && s.hp > 0.)
            .ok_or("没有存活舰艇")?
            .p;
        let mut paths = vec![];
        for (i, s) in self
            .ships
            .iter()
            .enumerate()
            .filter(|(_, s)| s.ally && s.hp > 0.)
        {
            let offset = s.p - lead;
            let mut path = vec![];
            let mut last = s.p;
            for p in &points {
                let goal = *p + offset;
                let next = self.path(last, goal, false)?;
                path.extend(next);
                last = goal;
            }
            paths.push((i, path));
        }
        for (i, path) in paths {
            let s = &mut self.ships[i];
            s.path = path;
            s.facing = None;
            s.speed = speed.min(s.def.max_knots);
            s.anchor = false;
            s.ai = false;
        }
        Ok(())
    }
    pub fn preview(&self, q: &Value) -> Value {
        let Ok(points) = serde_json::from_value::<Vec<P>>(q["points"].clone()) else {
            return json!({"valid":false,"paths":[],"error":"海上航点无效"});
        };
        let speed = q.get("speed").map_or(Some(25.), Value::as_f64);
        if points.is_empty()
            || points.len() > 12
            || speed.is_none_or(|n| !n.is_finite() || !(4. ..=40.).contains(&n))
            || q.get("fleet").is_some_and(|v| v.as_u64() != Some(1))
        {
            return json!({"valid":false,"paths":[],"error":"编队或速度无效"});
        }
        let mut paths = vec![];
        let lead = self
            .ships
            .iter()
            .find(|s| s.ally && s.hp > 0.)
            .map(|s| s.p)
            .unwrap_or_default();
        for s in self.ships.iter().filter(|s| s.ally && s.hp > 0.) {
            let mut last = s.p;
            let mut path = vec![s.p];
            for p in &points {
                let goal = *p + s.p - lead;
                match self.path(last, goal, false) {
                    Ok(next) => path.extend(next),
                    Err(e) => return json!({"valid":false,"paths":[],"error":e}),
                }
                last = goal;
            }
            paths.push(json!({"ship":s.id,"points":path}));
        }
        json!({"valid":true,"paths":paths,"error":null,"speed":speed})
    }
    fn deployment_plan(&self,q:&Value)->E<(usize,usize,u32,bool,Vec<P>)>{
        let id=q["unit_id"].as_str().ok_or("请选择MCP部队")?;
        let gi=self.groups.iter().position(|g|g.card.id==id).ok_or("部队不在本次部署中")?;
        let g=&self.groups[gi];
        if !["embarked","recovered"].contains(&g.stage)||self.bodies.iter().any(|b|b.group==id){return Err("该部队已登陆、运输中或损失，不能重复插入".into())}
        let beach=if let Some(v)=q.get("beach"){let n=v.as_u64().and_then(|n|u32::try_from(n).ok()).ok_or("滩头无效")?;self.beach_for(n)?;n}else{
            let p=self.position_for(q)?;if !inside(&self.polygon,p){return Err("请把部队拖到岛屿陆地上".into())}
            (1..=3).min_by(|a,b|self.beach_for(*a).unwrap().1.dist(p).total_cmp(&self.beach_for(*b).unwrap().1.dist(p))).unwrap()
        };
        let air=if matches!(self.version,VERSION_V3|v4::VERSION) {g.transport_kind=="helicopter"}else{match q["insertion"].as_str(){Some("air") if g.card.air=>true,Some("landing")=>false,_=>return Err("该部队不能采用此插入方式".into())}};
        let si=self.ships.iter().position(|s|s.id==g.carrier&&s.ally&&s.hp>0.).ok_or("运输载舰已损失")?;
        if self.groups.iter().enumerate().any(|(i,other)|i!=gi&&other.carrier==g.carrier&&other.pending.is_some_and(|(b,_)|b!=beach)){return Err("同一载舰已在接近另一滩头；先取消该登陆队列".into())}
        let(sea,land)=self.beach_for(beach)?;let limit=if air{if self.version==v4::VERSION{v4::flight_range(g.card.id)}else{6000.}}else{900.};
        let path=if self.ships[si].p.dist(if air{land}else{sea})>limit{self.path(self.ships[si].p,sea,false)?}else{vec![]};
        Ok((gi,si,beach,air,path))
    }
    fn aim_heading(&self,si:usize,p:P)->E<f64>{
        if !inside(&self.polygon,p){return Err("炮援指向须落在岛上".into())}
        if let Some(e)=self.gun_error(si,p,true){if !self.ships[si].anchor{return Err(e)}else{let s=&self.ships[si];if s.hp<=0.||s.def.gun.barrels==0||s.ammo<Self::gun_cost(s)||s.p.dist(p)>s.def.gun.range_yd.last().copied().unwrap_or(0.)*YARD{return Err(e)}}}
        let s=&self.ships[si];let bearing=(p-s.p).heading();let arcs=Self::gun_arcs(s);
        if arcs.iter().any(|r|arc(bearing-s.h,*r)){return Ok(s.h)}
        (0..360).map(|r|r as f64).filter(|relative|arcs.iter().any(|r|arc(*relative,*r)))
            .map(|relative|norm(bearing-relative)).min_by(|a,b|(norm(*a-s.h+180.)-180.).abs().total_cmp(&(norm(*b-s.h+180.)-180.).abs())).ok_or("该舰没有合法对岸炮向".into())
    }
    pub fn preview_littoral(&self,q:&Value)->E<Value>{
        if self.version==VERSION{return Err("此拖动预览只用于v2两栖行动".into())}
        let plan: E<Value>=(||match q["kind"].as_str(){
            Some("ship_move") if matches!(self.version,VERSION_V3|v4::VERSION)=>{let id=q["ship"].as_u64().ok_or("请选择舰艇")?;let si=self.ships.iter().position(|s|s.id as u64==id&&s.ally&&s.hp>0.).ok_or("舰艇不存在或已沉没")?;let p=self.position_for(q)?;let path=self.path(self.ships[si].p,p,false)?;Ok(json!({"valid":true,"ship":id,"target":p,"path":path,"reason":"真实航线可达"}))},
            Some("deploy")=>{let(gi,si,beach,air,path)=self.deployment_plan(q)?;let(sea,land)=self.beach_for(beach)?;let distance=self.ships[si].p.dist(if air{land}else{sea});let limit=if air{6000.}else{900.};Ok(json!({"valid":true,"unit_id":self.groups[gi].card.id,"beach":beach,"sea":sea,"land":land,"carrier":self.ships[si].id,"path":path,"distance":distance,"range_limit":limit,"can_launch_now":distance<=limit,"reason":if distance<=limit{"已在真实插入范围"}else{"载舰将真实驶近选定滩头"}}))},
            Some("aim_land")|Some("naval")=>{let id=q["ship"].as_u64().ok_or("请选择舰艇")?;let si=self.ships.iter().position(|s|s.id as u64==id&&s.ally).ok_or("舰艇不存在")?;let p=self.position_for(q)?;let heading=self.aim_heading(si,p)?;let reason=self.gun_error(si,p,false);Ok(json!({"valid":true,"ship":id,"target":p,"target_heading":heading,"distance":self.ships[si].p.dist(p),"range":self.ships[si].def.gun.range_yd.last().copied().unwrap_or(0.)*YARD,"ready_for_target":reason.is_none(),"reason":reason,"ready_in":self.ships[si].next.saturating_sub(self.frame) as f64/10.}))},
            _=>Err("拖动预览类型无效".into()),
        })();
        Ok(plan.unwrap_or_else(|e|json!({"valid":false,"reason":e,"error":e})))
    }
    fn cancel_deployment_ship(&mut self,ship:u32){
        for g in &mut self.groups{if g.carrier==ship{g.pending=None}}
        if let Some(s)=self.ships.iter_mut().find(|s|s.id==ship){s.deployment_route=false;}
    }
    fn queue_deployment(&mut self,q:&Value)->E<()>{
        let(gi,si,beach,air,path)=self.deployment_plan(q)?;
        self.groups[gi].pending=Some((beach,air));
        if !path.is_empty(){let s=&mut self.ships[si];s.path=path;s.speed=25f64.min(s.def.max_knots);s.anchor=false;s.facing=None;s.ai=false;s.deployment_route=true;}
        self.event("deploy_queued","登陆指令已排队，只有载舰实际进入范围才发出运输载具",self.ships[si].p);Ok(())
    }
    fn advance_deployments(&mut self){
        let pending:Vec<_>=self.groups.iter().enumerate().filter_map(|(i,g)|g.pending.map(|p|(i,p))).collect();
        for(gi,(beach,air))in pending{
            let carrier=self.groups[gi].carrier;
            let Some(si)=self.ships.iter().position(|s|s.id==carrier&&s.hp>0.)else{self.groups[gi].pending=None;continue};
            let(sea,land)=self.beach_for(beach).unwrap();
            if self.ships[si].p.dist(if air{land}else{sea})<=if air{if self.version==v4::VERSION{v4::flight_range(self.groups[gi].card.id)}else{6000.}}else{900.}{
                let request=json!({"op":"littoral_deploy","unit_id":self.groups[gi].card.id,"beach":beach,"insertion":if air{"air"}else{"landing"}});
                if self.command(&request,false).is_ok(){self.groups[gi].pending=None;}
            }
            if !self.groups.iter().any(|g|g.carrier==carrier&&g.pending.is_some())&&self.ships[si].deployment_route{
                let s=&mut self.ships[si];s.path.clear();s.speed=0.;s.deployment_route=false;
            }
        }
    }
    fn ability(&mut self,q:&Value)->E<()>{
        if self.version==VERSION{return Err("技能只用于v2两栖行动".into())}
        let id=q["unit_id"].as_str().ok_or("请选择部队")?;let gi=self.groups.iter().position(|g|g.card.id==id&&g.stage=="ground").ok_or("技能需要存活部队实际登陆")?;
        let g=self.groups[gi].clone();let p=*profile(id).ok_or("部队身份无效")?;
        if self.group_health(gi)<=0.||g.ability_charges==0||self.frame<g.ability_next{return Err("技能次数耗尽、部队失能或尚未冷却".into())}
        let target=if q.get("x").is_some()||q.get("y").is_some(){self.position_for(q)?}else{g.p};
        if !inside(&self.polygon,target)||p.ability_range>0.&&g.p.dist(target)>p.ability_range||p.ability_range==0.&&g.p.dist(target)>1.{return Err("技能落点不在真实作用范围内".into())}
        match p.ability{
            "air_rockets"|"suppression"|"at_missile"|"barrage"|"aa_burst"|"breach"=>{
                let index=self.bodies.iter().position(|b|b.group==id&&b.active&&b.hp>0.&&b.ammo>=if p.ability=="barrage"{3}else{1}&&match p.ability{"air_rockets"=>b.air,"barrage"=>b.kind=="howitzer","suppression"=>b.kind=="ifv","at_missile"=>b.kind=="anti_tank","aa_burst"=>b.kind=="aa_team","breach"=>b.kind=="engineer",_=>true}).ok_or("技能所需武器或实际弹药不可用")?;
                let count=if p.ability=="barrage"{3}else{1};if self.projectiles.len()+count>self.projectile_limit(){return Err("弹体预算暂满".into())}
                let origin=self.bodies[index].p;let damage=match p.ability{"air_rockets"=>100.,"suppression"=>70.,"at_missile"=>150.,"barrage"=>95.,"aa_burst"=>95.,_=>220.};
                for n in 0..count{let offset=if count>1{P{x:(n as f64-1.)*100.,y:0.}}else{P::default()};self.launch(true,origin,target+offset,damage,p.ability_radius,1200.,p.ability=="aa_burst",if p.ability=="at_missile"{"anti_tank"}else{"skill"},id.into());}
                self.bodies[index].ammo-=count as u32;
            },
            "jam"=>{let targets:Vec<_>=self.buildings.iter().enumerate().filter(|(_,b)|!b.ally&&b.hp>0.&&["aa","turret"].contains(&b.kind.as_str())&&b.p.dist(target)<=p.ability_radius).map(|(i,_)|i).collect();if targets.is_empty(){return Err("干扰范围内没有敌方火控设施".into())}for i in targets{self.buildings[i].next=self.buildings[i].next.max(self.frame+80);}},
            "triage"|"rescue"=>{let amount=if p.ability=="triage"{35.}else{20.};let mut heals=vec![];for(i,b)in self.bodies.iter().enumerate().filter(|(_,b)|b.ally&&b.active&&b.hp>0.&&b.p.dist(g.p)<=p.ability_radius){let group=self.groups.iter().find(|g|g.card.id==b.group).unwrap();let ceiling=b.max*group.initial/100.*group.transit_health;let hp=(b.hp+amount).min(ceiling);if hp>b.hp{heals.push((i,hp))}}if heals.is_empty(){return Err("范围内没有可急救的存活伤员，不能复活或超出初始整备".into())}for(i,hp)in heals{self.bodies[i].hp=hp;}if p.ability=="rescue"{self.groups[gi].buff_until=self.frame+100;}},
            "resupply"=>{let mut remaining=g.reserve_ammo.min(60);let mut transfers=vec![];for(i,b)in self.bodies.iter().enumerate().filter(|(_,b)|b.ally&&b.active&&b.hp>0.&&b.p.dist(g.p)<=p.ability_radius){let cap=profile(&b.group).map_or(if b.air{45}else{90},|p|if p.ammo>0{p.ammo}else if b.air{45}else{90});let n=cap.saturating_sub(b.ammo).min(20).min(remaining);if n>0{transfers.push((i,n));remaining-=n;}}let spent=g.reserve_ammo.min(60)-remaining;if spent==0{return Err("补充弹药已用尽或范围内不缺弹".into())}for(i,n)in transfers{self.bodies[i].ammo+=n;}self.groups[gi].reserve_ammo-=spent;},
            "field_repair"=>{if g.supplies<2{return Err("工程补给不足".into())}let targets:Vec<_>=self.buildings.iter().enumerate().filter(|(_,b)|b.ally&&b.hp>0.&&b.hp<b.max&&b.p.dist(g.p)<=p.ability_radius).map(|(i,_)|i).collect();if targets.is_empty(){return Err("范围内没有损坏的己方设施".into())}for i in targets{let b=&mut self.buildings[i];b.hp=(b.hp+80.).min(b.max)}self.groups[gi].supplies-=2;},
            _=>{self.groups[gi].buff_until=self.frame+if p.ability=="hull_down"||p.ability=="smoke"||p.ability=="precision"{80}else{100};self.groups[gi].buff_point=target;},
        }
        self.groups[gi].ability_charges-=1;self.groups[gi].ability_next=self.frame+(p.cooldown*10.) as u32;
        self.event("ability",&format!("{}：{}，消耗一次有限技能",g.card.name,ability_name(p.ability)),target);Ok(())
    }
    pub fn command(&mut self, q: &Value, record: bool) -> E<Value> {
        if self.result.is_some() {
            return Err("两栖行动已经结束".into());
        }
        if record && self.commands.len() >= 15000 {
            return Err("两栖指令数量达到上限".into());
        }
        match q["op"].as_str().ok_or("两栖操作无效")? {
            "route" => {
                if q.get("fleet").is_some_and(|v| v.as_u64() != Some(1)) {
                    return Err("两栖海军编队须为1".into());
                }
                let points = serde_json::from_value(q["points"].clone()).map_err(|_| "航点无效")?;
                let speed = q
                    .get("speed")
                    .map_or(Some(25.), Value::as_f64)
                    .ok_or("速度无效")?;
                self.route(points, speed)?;
                if self.version!=VERSION {let ids:Vec<_>=self.ships.iter().filter(|s|s.ally).map(|s|s.id).collect();for id in ids{self.cancel_deployment_ship(id);}}
            }
            "speed" => {
                let speed = q["speed"].as_f64().ok_or("速度无效")?;
                if !speed.is_finite()
                    || !(0. ..=40.).contains(&speed)
                    || q.get("fleet").is_some_and(|v| v.as_u64() != Some(1))
                {
                    return Err("编队或速度无效".into());
                }
                for s in self.ships.iter_mut().filter(|s| s.ally && s.hp > 0.) {
                    s.speed = speed.min(s.def.max_knots);
                    s.ai = false;
                    if speed > 0. {
                        s.anchor = false;
                    }
                }
                if self.version!=VERSION {let ids:Vec<_>=self.ships.iter().filter(|s|s.ally).map(|s|s.id).collect();for id in ids{self.cancel_deployment_ship(id);}}
            }
            "littoral_ship_order" => {
                let id = q["ship"].as_u64().ok_or("请选择舰艇")?;
                let i = self
                    .ships
                    .iter()
                    .position(|s| s.id as u64 == id && s.ally && s.hp > 0.)
                    .ok_or("舰艇不存在或已沉没")?;
                match q["action"].as_str().ok_or("请选择海上指令")? {
                    "move" => {
                        let p = self.position_for(q)?;
                        let path = self.path(self.ships[i].p, p, false)?;
                        self.ships[i].path = path;
                        self.ships[i].facing = None;
                        self.ships[i].speed = 25f64.min(self.ships[i].def.max_knots);
                        self.ships[i].anchor = false;
                    }
                    "hold" => {
                        self.ships[i].path.clear();
                        self.ships[i].facing = None;
                        self.ships[i].speed = 0.;
                    }
                    "anchor" => {
                        self.ships[i].path.clear();
                        self.ships[i].facing = None;
                        self.ships[i].speed = 0.;
                        self.ships[i].anchor = true;
                    }
                    "face" => {
                        let h = q["heading"].as_f64().ok_or("请给航向")?;
                        if !h.is_finite() {
                            return Err("航向无效".into());
                        }
                        self.ships[i].facing = Some(norm(h));
                        self.ships[i].path.clear();
                        self.ships[i].speed = 0.;
                        self.ships[i].anchor = false;
                    }
                    "cancel_support" => self.ships[i].pending_support = None,
                    "aim_land" if self.version!=VERSION => {
                        let p=self.position_for(q)?;let heading=self.aim_heading(i,p)?;
                        self.ships[i].aim_target=Some(p);self.ships[i].facing=Some(heading);
                        self.ships[i].path.clear();self.ships[i].speed=0.;self.ships[i].anchor=false;
                    },
                    _ => return Err("海上指令不存在".into()),
                }
                self.ships[i].ai = false;
                if self.version!=VERSION && q["action"]!="cancel_support" {let ship=self.ships[i].id;self.cancel_deployment_ship(ship);if q["action"]!="aim_land" {self.ships[i].aim_target=None;}}
            }
            "littoral_cancel_deploy" if self.version!=VERSION => {
                let id=q["unit_id"].as_str().ok_or("请选择部队")?;let gi=self.groups.iter().position(|g|g.card.id==id).ok_or("部队不在本局")?;
                if self.groups[gi].pending.is_none(){return Err("该部队没有待登陆队列".into())}
                self.groups[gi].pending=None;let ship=self.groups[gi].carrier;
                if !self.groups.iter().any(|g|g.carrier==ship&&g.pending.is_some()){if let Some(s)=self.ships.iter_mut().find(|s|s.id==ship){if s.deployment_route{s.path.clear();s.speed=0.;s.deployment_route=false;}}}
            },
            "littoral_ability" if self.version!=VERSION => self.ability(q)?,
            "littoral_deploy" if self.version!=VERSION && q.get("queue").is_some_and(|v|v!=false) => {
                if q["queue"]!=true{return Err("待登陆开关须为真假值".into())}self.queue_deployment(q)?;
            },
            "littoral_deploy" => {
                let id = q["unit_id"].as_str().ok_or("请选择MCP部队")?;
                let i = self
                    .groups
                    .iter()
                    .position(|g| g.card.id == id)
                    .ok_or("部队不在本次部署中")?;
                if !["embarked", "recovered"].contains(&self.groups[i].stage) {
                    return Err("部队已在岸上、运输中或损失".into());
                }
                if self.bodies.iter().any(|b| b.group == id) {
                    return Err("本版每支部队只能登陆一次".into());
                }
                let beach = q["beach"]
                    .as_u64()
                    .and_then(|n| u32::try_from(n).ok())
                    .ok_or("请选择滩头")?;
                let (sea, land) = self.beach_for(beach)?;
                let insertion = q["insertion"].as_str().ok_or("请选择登陆方式")?;
                let air = if matches!(self.version,VERSION_V3|v4::VERSION) {self.groups[i].transport_kind=="helicopter"}else{match insertion {
                    "air" if self.groups[i].card.air => true,
                    "landing" => false,
                    _ => return Err("该部队不能采用此插入方式".into()),
                }};
                let ship = self
                    .ships
                    .iter()
                    .find(|s| s.id == self.groups[i].carrier && s.hp > 0.)
                    .ok_or("运输舰已损失")?;
                if ship.p.dist(if air { land } else { sea }) > if air { if self.version==v4::VERSION {v4::flight_range(self.groups[i].card.id)}else{6000.} } else { 900. } {
                    return Err(if air {
                        "载舰距离空插点超过6000米"
                    } else {
                        "载舰须靠近滩头海上接驳点900米以内"
                    }
                    .into());
                }
                let origin = ship.p;
                let carrier = ship.id;
                let id = self.id();
                self.transports.push(Transport {
                    id,
                    group: i,
                    carrier,
                    p: origin,
                    goal: land,
                    hp: if matches!(self.version,VERSION_V3|v4::VERSION) {transport_stats(self.groups[i].card.id,self.groups[i].transport_kind).0}else if air { 130. } else { 220. },
                    max: if matches!(self.version,VERSION_V3|v4::VERSION) {transport_stats(self.groups[i].card.id,self.groups[i].transport_kind).0}else if air { 130. } else { 220. },
                    air,
                    returning: false,
                });
                let g = &mut self.groups[i];
                g.stage = "transit";
                g.insertion = if air { "air" } else { "landing" };
                g.beach = beach;
                g.p = origin;
                self.event("deploy", "运输载具已出发，途中仍会受到敌火威胁", origin);
            }
            "littoral_order" => {
                let id = q["unit_id"].as_str().ok_or("请选择MCP部队")?;
                let i = self
                    .groups
                    .iter()
                    .position(|g| g.card.id == id && g.stage == "ground")
                    .ok_or("部队尚未登陆或已无法行动")?;
                let action = q["action"].as_str().ok_or("请选择地面指令")?;
                let (target, goal) = match action {
                    "move" | "attack" | "defend" => (None, Some(self.position_for(q)?)),
                    "hold" => (None, None),
                    "retreat" => (None, Some(self.beach_for(self.groups[i].beach)?.1)),
                    "search" => {
                        let id = q["target"]
                            .as_u64()
                            .and_then(|n| u32::try_from(n).ok())
                            .ok_or("请选择陆地遗迹")?;
                        let r = self
                            .ruins
                            .iter()
                            .find(|r| r.id == id && !r.searched)
                            .ok_or("遗迹不存在或已经搜索")?;
                        (Some(id), Some(r.p))
                    }
                    "repair" => {
                        if self.groups[i].card.role != "engineer" {
                            return Err("只有工兵能修复设施".into());
                        }
                        let id = q["target"].as_str().ok_or("请选择设施身份")?;
                        let b = self
                            .buildings
                            .iter()
                            .position(|b| b.id == id && b.ally)
                            .ok_or("只能修复己方设施")?;
                        (Some(b as u32), Some(self.buildings[b].p))
                    }
                    _ => return Err("地面指令不存在".into()),
                };
                let path = goal
                    .map(|p| self.path(self.groups[i].p, p, true))
                    .transpose()?
                    .unwrap_or_default();
                let g = &mut self.groups[i];
                g.path = path;
                g.order = action.into();
                g.target = target;
                if self.version!=VERSION {let p=g.p;self.event("unit_ordered",&format!("{}：{}",id,action),p);}
            }
            "littoral_support" => {
                let p = self.position_for(q)?;
                match q["kind"].as_str().ok_or("请选择支援类型")? {
                    "naval" => {
                        let id = q["ship"].as_u64().ok_or("请选择支援舰")?;
                        let i = self
                            .ships
                            .iter()
                            .position(|s| s.id as u64 == id && s.ally)
                            .ok_or("支援舰不存在")?;
                        let queue = match q.get("queue") {
                            None => false,
                            Some(Value::Bool(b)) => *b,
                            _ => return Err("待发开关须为真假值".into()),
                        };
                        if queue {
                            if let Some(e) = self.gun_error(i, p, true) {
                                return Err(e);
                            }
                            if self.version!=VERSION && !Self::gun_arcs(&self.ships[i]).iter().any(|r|arc((p-self.ships[i].p).heading()-self.ships[i].h,*r)) && !self.ships[i].aim_target.is_some_and(|a|a.dist(p)<1.) {return Err("请先把该舰对准同一岸援落点".into())}
                            self.ships[i].pending_support = Some((p, self.frame + 900));
                        } else {
                            self.naval_fire(i, p)?;
                            self.ships[i].pending_support = None;
                        }
                    }
                    "helicopter" => {
                        let id = q["unit_id"].as_str().ok_or("请选择空中部队")?;
                        let index = self
                            .bodies
                            .iter()
                            .position(|b| {
                                b.ally
                                    && b.active
                                    && b.hp > 0.
                                    && b.air
                                    && b.group == id
                                    && b.ammo > 0
                                    && self.frame >= b.next
                            })
                            .ok_or("支援直升机不在场、无弹或正在装填")?;
                        let b = &self.bodies[index];
                        if b.p.dist(p) > b.range {
                            return Err("目标超出直升机真实火力范围".into());
                        }
                        let (origin, damage, source) = (b.p, b.damage, b.group.clone());
                        if !self.launch(
                            true,
                            origin,
                            p,
                            damage,
                            120.,
                            1000.,
                            false,
                            "air_support",
                            source,
                        ) {
                            return Err("弹体预算暂满".into());
                        }
                        let b = &mut self.bodies[index];
                        b.ammo -= 1;
                        b.next = self.frame + b.reload;
                    }
                    _ => return Err("支援类型不存在".into()),
                }
            }
            "littoral_extract" => {
                if !self.objective_complete() {
                    return Err("主要目标尚未完成".into());
                }
                if self.groups.iter().enumerate().any(|(i, g)| {
                    self.group_health(i) > 0. && !["embarked", "recovered"].contains(&g.stage)
                }) && self.config.mode != "defense"
                {
                    return Err("仍有存活部队未实际撤回载舰".into());
                }
                if self.ships.iter().filter(|s| s.ally && s.hp > 0.).any(|s| {
                    s.p.dist(self.exit_point()) > 1600.
                }) && self.config.mode != "defense"
                {
                    return Err("所有存活舰艇须实际进入南侧撤离区".into());
                }
                self.finish(true, false);
            }
            "littoral_abandon" => self.finish(false, true),
            _ => return Err("此指令不属于两栖行动".into()),
        }
        if record {
            self.commands.push(Command {
                frame: self.frame,
                request: q.clone(),
            });
        }
        Ok(self.view())
    }
    fn exit_point(&self)->P {if let Some(g)=&self.island_geometry{return g.exit()}if self.version==v4::VERSION {P{x:8500.,y:13000.}}else{P{x:5500.,y:13500.}}}
    fn objective_complete(&self) -> bool {
        if matches!(self.version,VERSION_V3|v4::VERSION)&&self.config.mode=="tutorial"{match self.lesson(){"sea_control"=>return self.ships.iter().filter(|s|!s.ally).all(|s|s.hp<=0.),"combined"=>return self.landed_companies.len()>=2&&self.shore_support_hits>0&&self.ruins.iter().any(|r|r.searched),_=>{}}}
        match self.config.mode.as_str() {
            "raid" => self.capture >= 80,
            "defense" => {
                self.frame >= 1800
                    && self
                        .buildings
                        .iter()
                        .any(|b| b.kind == "hq" && b.ally && b.hp > 0.)
            }
            _ => self.ruins.iter().any(|r| r.searched),
        }
    }
    fn blast(
        &mut self,
        p: P,
        damage: f64,
        radius: f64,
        ally: bool,
        air_only: bool,
        kind: &str,
        source: &str,
    ) {
        let mut hits = 0;
        let mut kills = 0;
        let mut shore_hits=0;
        let marked=if self.version!=VERSION && ally && self.groups.iter().any(|g|g.buff_until>self.frame&&profile(g.card.id).is_some_and(|d|d.ability=="recon_mark"&&g.buff_point.dist(p)<=d.ability_radius)){1.25}else{1.};
        let damage=damage*marked;
        let cover:Vec<_>=if self.version!=VERSION {self.groups.iter().filter(|g|g.stage=="ground"&&g.buff_until>self.frame).filter_map(|g|profile(g.card.id).and_then(|d|match d.ability{"smoke"=>Some((g.p,d.ability_radius,0.7f64)),"hull_down"=>Some((g.p,d.ability_radius,0.6f64)),_=>None})).collect()}else{vec![]};
        for s in &mut self.ships {
            if !air_only
                && s.ally != ally
                && s.hp > 0.
                && s.p.dist(p) <= radius + s.def.length_m.max(80.) / 2.
            {
                s.hp = (s.hp - damage).max(0.);
                hits += 1;
                if s.hp == 0. {
                    kills += 1;
                }
            }
        }
        for b in &mut self.bodies {
            if b.ally != ally
                && b.hp > 0.
                && b.active
                && (!air_only || b.air)
                && b.p.dist(p) <= radius + 25.
            {
                let factor = if self.island_geometry.is_some(){v4::island_war::body_damage_factor(kind,b.armor)}else if kind == "anti_tank" || kind == "naval" {
                    b.armor.max(0.8)
                } else {
                    b.armor
                };
                let terrain_reduction=if self.version==v4::VERSION&&!b.air&&!["naval","air_strike","air_weapon","mine"].contains(&kind){self.island_geometry.as_ref().map_or_else(||v4::cover_multiplier(b.p),|g|g.cover(b.p))}else{1.};
                let reduction=if b.ally {cover.iter().filter(|(p,r,_)|p.dist(b.p)<=*r).map(|(_,_,f)|*f).fold(1f64,f64::min)}else{1.};
                b.hp = (b.hp - damage * factor * reduction * terrain_reduction).max(0.);
                if !b.ally {shore_hits+=1;}
                hits += 1;
                if b.hp == 0. {
                    kills += 1;
                    if !b.ally {
                        self.enemy_dead += 1;
                    }
                }
            }
        }
        for b in &mut self.buildings {
            if !air_only && b.ally != ally && b.hp > 0. && b.p.dist(p) <= radius + 80. {
                b.hp = (b.hp - damage*if self.island_geometry.is_some(){v4::island_war::structure_damage_factor(kind,&b.kind)}else{1.}).max(0.);
                if !b.ally {shore_hits+=1;}
                hits += 1;
                if b.hp == 0. {
                    kills += 1;
                }
            }
        }
        for t in &mut self.transports {
            if !ally && t.hp > 0. && (!air_only || t.air) && t.p.dist(p) <= radius + 35. {
                let armor=if matches!(self.version,VERSION_V3|v4::VERSION) {let a=transport_stats(self.groups[t.group].card.id,self.groups[t.group].transport_kind).1;if kind=="anti_tank"||kind=="naval"{a.max(0.8)}else{a}}else{1.};
                t.hp = (t.hp - damage*armor).max(0.);
                hits += 1;
            }
        }
        if matches!(self.version,VERSION_V3|v4::VERSION)&&ally&&kind=="naval" {self.shore_support_hits+=shore_hits;}
        if hits > 0 {
            let id = self.id();
            bounded(
                &mut self.impacts,
                json!({"id":id,"frame":self.frame,"tick":self.frame as f64/10.,"kind":kind,"source":source,"x":p.x,"y":p.y,"radius":radius,"damage":damage,"hits":hits,"kills":kills}),
            );
        }
    }
    pub fn advance(&mut self) {
        if self.result.is_some() {
            return;
        }
        self.frame += 1;
        if self.version!=v4::VERSION {
        // The same authoritative ships move, spend ammunition and provide support.
        let mut ai_routes = vec![];
        let mut notices = vec![];
        for (i, s) in self
            .ships
            .iter()
            .enumerate()
            .filter(|(_, s)| s.hp > 0. && s.ai)
        {
            if self.version!=VERSION && self.config.mode=="tutorial" && !s.ally && self.frame<600 {continue;}
            let target = self
                .ships
                .iter()
                .filter(|o| o.ally != s.ally && o.hp > 0.)
                .min_by(|a, b| a.p.dist(s.p).total_cmp(&b.p.dist(s.p)))
                .map(|o| o.p);
            if let Some(p) = target {
                if s.anchor && (s.p.dist(p) < 8500. || self.frame >= 300) {
                    notices.push(i);
                } else if !s.anchor && self.frame >= s.last_plan + 50 && s.p.dist(p) > 3200. {
                    let direction = (p - s.p).unit();
                    let desired = p - direction * 2800.;
                    if let Ok(path) = self.path(s.p, desired, false) {
                        ai_routes.push((i, path));
                    }
                }
            }
        }
        for i in notices {
            if self.ships[i].unmoor == 0 {
                self.ships[i].unmoor = self.frame;
                let p = self.ships[i].p;
                self.event("unmooring", "锚泊守舰发现来袭舰队，正在起锚出港", p);
            } else if self.frame >= self.ships[i].unmoor + 60 {
                self.ships[i].anchor = false;
                self.ships[i].speed = 25.;
            }
        }
        for (i, path) in ai_routes {
            self.ships[i].path = path;
            self.ships[i].last_plan = self.frame;
            self.ships[i].speed = 25f64.min(self.ships[i].def.max_knots);
        }
        for i in 0..self.ships.len() {
            if self.ships[i].hp <= 0. || self.ships[i].anchor {
                continue;
            }
            if let Some(heading) = self.ships[i].facing {
                let delta = norm(heading - self.ships[i].h + 180.) - 180.;
                self.ships[i].h = norm(self.ships[i].h + delta.clamp(-6., 6.));
                if delta.abs() <= 6. {
                    self.ships[i].facing = None;
                }
                continue;
            }
            let target = self.ships[i].path.first().copied();
            if let Some(p) = target {
                let s = &mut self.ships[i];
                let d = s.p.dist(p);
                let bearing = (p - s.p).heading();
                let delta = (norm(bearing - s.h + 180.) - 180.).clamp(-6., 6.);
                s.h = norm(s.h + delta);
                let distance = s.speed * crate::model::KNOT * 8. * DT;
                if d <= distance {
                    s.p = p;
                    s.path.remove(0);
                } else if (norm(bearing - s.h + 180.) - 180.).abs() < 25. {
                    s.p = s.p + (p - s.p) * (distance / d);
                }
            } else if self.ships[i].ai {
                let s = &self.ships[i];
                let target = self
                    .ships
                    .iter()
                    .filter(|o| o.ally != s.ally && o.hp > 0.)
                    .min_by(|a, b| a.p.dist(s.p).total_cmp(&b.p.dist(s.p)))
                    .map(|o| o.p);
                if let Some(p) = target {
                    let h = (p - s.p).heading() - 90.;
                    let delta = (norm(h - s.h + 180.) - 180.).clamp(-6., 6.);
                    self.ships[i].h = norm(self.ships[i].h + delta);
                }
            }
        }
        for i in 0..self.ships.len() {
            if self.version!=VERSION && self.config.mode=="tutorial" && !self.ships[i].ally && self.frame<600 {continue;}
            if let Some((goal, expires)) = self.ships[i].pending_support {
                if self.frame >= expires
                    || self.ships[i].hp <= 0.
                    || self.ships[i].ammo < Self::gun_cost(&self.ships[i])
                {
                    self.ships[i].pending_support = None;
                    self.event(
                        "support_cancelled",
                        "岸援待发已因超时、舰损或弹药不足取消",
                        goal,
                    );
                } else if self.naval_fire(i, goal).is_ok() {
                    self.ships[i].pending_support = None;
                    self.event("support_fired", "待发岸援已按真实射界和装填状态开火", goal);
                }
                // Waiting support owns this ship's next valid salvo. Automatic
                // sea fire must not consume its newly completed reload first.
                continue;
            }
            if self.ships[i].hp <= 0. {
                continue;
            }
            let p = self.ships[i].p;
            let ally = self.ships[i].ally;
            let target = self
                .ships
                .iter()
                .filter(|s| s.ally != ally && s.hp > 0. && self.clear(p, s.p, false))
                .min_by(|a, b| a.p.dist(p).total_cmp(&b.p.dist(p)))
                .map(|s| s.p);
            if let Some(goal) = target {
                let _ = self.naval_fire(i, goal);
            }
        }
        }
        if self.version!=VERSION {self.advance_deployments();}
        // A ship loss destroys embarked personnel, while landed groups may seek
        // an alternative surviving carrier with actual spare transport slots.
        for i in 0..self.groups.len() {
            if ["embarked", "recovered"].contains(&self.groups[i].stage)
                && !self
                    .ships
                    .iter()
                    .any(|s| s.id == self.groups[i].carrier && s.hp > 0.)
            {
                self.groups[i].stage = "lost";
                for b in self
                    .bodies
                    .iter_mut()
                    .filter(|b| b.group == self.groups[i].card.id)
                {
                    b.hp = 0.;
                    b.active = false;
                }
                let p = self.groups[i].p;
                self.event("transport_loss", "载舰沉没，舰上部队失去战斗能力", p);
            }
        }
        let mut arrived = vec![];
        let mut lost = vec![];
        for (i, t) in self.transports.iter_mut().enumerate() {
            if t.hp <= 0. {
                lost.push(i);
                continue;
            }
            if t.returning {
                if let Some(s) = self.ships.iter().find(|s| s.id == t.carrier && s.hp > 0.) {
                    t.goal = s.p;
                } else {
                    lost.push(i);
                    continue;
                }
            }
            let d = t.p.dist(t.goal);
            let multiplier=if self.version==VERSION_V2 {match self.groups[t.group].card.id{"MCP-103"=>1.35,"MCP-167"=>1.5,"MCP-240" if t.returning=>1.4,_=>1.}}else{1.};
            let step = if matches!(self.version,VERSION_V3|v4::VERSION) {transport_stats(self.groups[t.group].card.id,self.groups[t.group].transport_kind).2}else if t.air { 220. } else { 95. } * DT * multiplier;
            if d <= step + 60. {
                t.p = t.goal;
                arrived.push(i);
            } else {
                t.p = t.p + (t.goal - t.p) * (step / d);
            }
            self.groups[t.group].p = t.p;
        }
        if matches!(self.version,VERSION_V3|v4::VERSION){
            let mut firing=vec![];
            for t in self.transports.iter().filter(|t|t.hp>0.&&t.air){let g=&self.groups[t.group];if g.vehicle_ammo==0||self.frame<g.vehicle_next{continue}let target=self.bodies.iter().filter(|b|!b.ally&&b.active&&b.hp>0.&&b.p.dist(t.p)<=1400.).min_by(|a,b|a.p.dist(t.p).total_cmp(&b.p.dist(t.p))).map(|b|b.p).or_else(||self.buildings.iter().filter(|b|!b.ally&&b.hp>0.&&b.p.dist(t.p)<=1400.).min_by(|a,b|a.p.dist(t.p).total_cmp(&b.p.dist(t.p))).map(|b|b.p));if let Some(p)=target{firing.push((t.group,t.p,p));}}
            for(gi,p,target)in firing{if self.launch(true,p,target,60.,120.,1200.,false,"transport_gunship",self.groups[gi].card.id.into()){self.groups[gi].vehicle_ammo-=1;self.groups[gi].vehicle_next=self.frame+12;}}
        }
        for i in &lost {
            if self.version==v4::VERSION { self.v4_transport_losses.push(self.transports[*i].clone()); }
            let g = self.transports[*i].group;
            self.groups[g].stage = "lost";
            for b in self
                .bodies
                .iter_mut()
                .filter(|b| b.group == self.groups[g].card.id)
            {
                b.hp = 0.;
                b.active = false;
            }
            let p = self.transports[*i].p;
            self.event("insertion_lost", "运输载具遭摧毁，所载部队失去战斗能力", p);
        }
        for i in &arrived {
            let t = self.transports[*i].clone();
            let g = t.group;
            if lost.contains(i) {
                continue;
            }
            if t.returning {
                for b in self
                    .bodies
                    .iter_mut()
                    .filter(|b| b.group == self.groups[g].card.id)
                {
                    b.hp *= t.hp / t.max;
                    b.active = false;
                }
                self.groups[g].stage = "recovered";
                self.groups[g].carrier = t.carrier;
                self.groups[g].p = t.p;
                self.event("recovered", "部队和携带物资已实际返回载舰", t.p);
            } else {
                self.groups[g].stage = "ground";
                self.groups[g].transit_health = t.hp / t.max;
                self.groups[g].p = t.p;
                self.spawn_group(g);
            }
        }
        self.transports = self
            .transports
            .iter()
            .enumerate()
            .filter(|(i, _)| !arrived.contains(i) && !lost.contains(i))
            .map(|(_, t)| t.clone())
            .collect();
        // Move a card's actual bodies in a compact ground formation. The route
        // graph is computed on orders, not rebuilt from history every microstep.
        let mut returning = vec![];
        let mut searches = vec![];
        let mut repairs = vec![];
        for i in 0..self.groups.len() {
            if self.groups[i].stage != "ground" {
                continue;
            }
            if self.group_health(i) <= 0. {
                self.groups[i].stage = "lost";
                continue;
            }
            if self.groups[i].card.role == "engineer" && self.groups[i].supplies > 0 {
                let p = self.groups[i].p;
                for m in &mut self.mines {
                    if m.active && m.p.dist(p) < 260. {
                        m.active = false;
                        self.groups[i].supplies -= 1;
                        if self.groups[i].supplies == 0 {
                            break;
                        }
                    }
                }
            }
            let movement=if self.version!=VERSION {self.groups.iter().filter(|g|g.stage=="ground"&&g.buff_until>self.frame&&g.p.dist(self.groups[i].p)<=profile(g.card.id).unwrap().ability_radius).map(|g|match profile(g.card.id).unwrap().ability{"rapid_march"=>1.6f64,"coordination"=>1.2,"rescue" if g.card.id==self.groups[i].card.id=>1.5,_=>1.}).fold(1f64,f64::max)}else{1.};
            let goal = self.groups[i].path.first().copied();
            if let Some(p) = goal {
                let g = &mut self.groups[i];
                let d = g.p.dist(p);
                let step = g.card.speed * DT * movement;
                if d <= step {
                    g.p = p;
                    g.path.remove(0);
                } else {
                    g.p = g.p + (p - g.p) * (step / d);
                }
            }
            let g = self.groups[i].clone();
            let anchor = g.p;
            let body_speed=g.card.speed*1.4*movement;
            let ids: Vec<_> = self
                .bodies
                .iter()
                .enumerate()
                .filter(|(_, b)| b.ally && b.group == g.card.id && b.hp > 0. && b.active)
                .map(|(i, _)| i)
                .collect();
            for (n, index) in ids.into_iter().enumerate() {
                let b = &self.bodies[index];
                let desired = anchor
                    + P {
                        x: if matches!(self.version,VERSION_V3|v4::VERSION){(n%3) as f64*65.-65.}else{(n % 2) as f64 * 90. - 45.},
                        y: if matches!(self.version,VERSION_V3|v4::VERSION){(n/3) as f64*65.-65.}else{(n / 2) as f64 * 90. - 45.},
                    };
                let desired = if b.air || self.walkable(desired, true) {
                    desired
                } else {
                    anchor
                };
                if self.version==v4::VERSION {self.v4_step_body(index,desired,body_speed);continue;}
                let d = b.p.dist(desired);
                if d > 0.01 {
                    let next = b.p + (desired - b.p) * ((g.card.speed * 1.4 * DT * movement) / d).min(1.);
                    if b.air || self.walkable(next, true) {
                        self.bodies[index].p = next;
                    }
                }
            }
            let g = &self.groups[i];
            if g.path.is_empty() {
                match g.order.as_str() {
                    "retreat" => returning.push(i),
                    "search" => searches.push(i),
                    "repair" => repairs.push(i),
                    _ => {}
                }
            }
        }
        for i in returning {
            let carrier = self.return_carrier(i);
            if let Some(carrier) = carrier {
                let s = self.ships.iter().find(|s| s.id == carrier).unwrap();
                if s.p.dist(self.groups[i].p)
                    <= if self.groups[i].insertion == "air" {
                        6000.
                    } else {
                        3000.
                    }
                {
                    let goal = s.p;
                    let p = self.groups[i].p;
                    let air = self.groups[i].insertion == "air";
                    let id = self.id();
                    self.transports.push(Transport {
                        id,
                        group: i,
                        carrier,
                        p,
                        goal,
                        hp: if matches!(self.version,VERSION_V3|v4::VERSION) {transport_stats(self.groups[i].card.id,self.groups[i].transport_kind).0}else if air { 130. } else { 220. },
                        max: if matches!(self.version,VERSION_V3|v4::VERSION) {transport_stats(self.groups[i].card.id,self.groups[i].transport_kind).0}else if air { 130. } else { 220. },
                        air,
                        returning: true,
                    });
                    self.groups[i].stage = "returning";
                    // Reserve this carrier's slots immediately, before another
                    // group can select the same spare capacity in this frame.
                    self.groups[i].carrier = carrier;
                    for b in self
                        .bodies
                        .iter_mut()
                        .filter(|b| b.group == self.groups[i].card.id)
                    {
                        b.active = false;
                    }
                }
            }
        }
        for i in searches {
            let g = &self.groups[i];
            if self
                .bodies
                .iter()
                .any(|b| !b.ally && b.active && b.hp > 0. && b.p.dist(g.p) < 450.)
            {
                continue;
            }
            if let Some(r) = self
                .ruins
                .iter_mut()
                .find(|r| Some(r.id) == g.target && !r.searched && r.p.dist(g.p) < 230.)
            {
                r.progress = (r.progress + (if g.card.role == "engineer" || self.version!=VERSION&&v4::unit_id(g.card.id)=="MCP-018" { 2 } else { 1 })*if matches!(self.version,VERSION_V3|v4::VERSION){2}else{1}).min(80);
                if r.progress == 80 {
                    r.searched = true;
                    let (kind, amount) = match r.id {
                        1 => ("scrap", 60),
                        2 => ("alloy", 25),
                        _ => ("protocols", 1),
                    };
                    self.loot.push(Loot {
                        id: format!("littoral-{}-ruin{}", self.seed, r.id),
                        kind: kind.into(),
                        amount,
                        holder: g.card.id.into(),
                    });
                    let p = r.p;
                    self.event("searched", "陆地遗迹已实际搜索；物资仍须随部队撤回", p);
                }
            }
        }
        for i in repairs {
            let g = &mut self.groups[i];
            if g.supplies > 0 {
                if let Some(b) = g.target.and_then(|n| self.buildings.get_mut(n as usize)) {
                    if b.ally && b.p.dist(g.p) < 450. && b.hp < b.max {
                        b.hp = (b.hp + 2.).min(b.max);
                        if self.frame % 10 == 0 {
                            g.supplies -= 1;
                        }
                    }
                }
            }
        }
        let mut explosions = vec![];
        for m in &mut self.mines {
            if m.active
                && self
                    .bodies
                    .iter()
                    .any(|b| b.ally && b.active && b.hp > 0. && !b.air && b.p.dist(m.p) < 90.)
            {
                m.active = false;
                explosions.push(m.p);
            }
        }
        for p in explosions {
            self.blast(p, 110., 160., false, false, "mine", "minefield");
        }
        // Finite attacker waves in a home-defense exercise.
        if self.config.mode == "defense" && [300, 600, 900, 1200].contains(&self.frame) {
            for n in 0..5 {
                self.spawn_enemy(
                    P {
                        x: 11200. + n as f64 * 500.,
                        y: 4100.,
                    },
                    if n == 2 { "anti_tank" } else { "rifle" },
                );
            }
        }
        if self.version!=VERSION && self.config.mode!="tutorial" && self.frame==1200 {self.spawn_enemy(P{x:13200.,y:5200.},"helicopter");}
        let friendly_positions: Vec<_> = self
            .bodies
            .iter()
            .filter(|b| b.ally && b.active && b.hp > 0. && !b.air)
            .map(|b| b.p)
            .collect();
        let hq = self
            .buildings
            .iter()
            .find(|b| b.kind == "hq" && b.ally && b.hp > 0.)
            .map(|b| b.p);
        for i in 0..self.bodies.len() {
            let b = &self.bodies[i];
            if b.ally || !b.active || b.hp <= 0. || self.island_geometry.is_some() {
                continue;
            }
            let target = friendly_positions
                .iter()
                .copied()
                .min_by(|a, bp| a.dist(b.p).total_cmp(&bp.dist(b.p)))
                .or(hq);
            if let Some(goal) = target {
                let d = b.p.dist(goal);
                if d > b.range * 0.75 {
                    if self.version==v4::VERSION {self.v4_step_body(i,goal,80.);continue;}
                    let next = b.p + (goal - b.p) * (32. * DT * if matches!(self.version,VERSION_V3|v4::VERSION){2.5}else{1.} / d).min(1.);
                    if self.version!=VERSION&&b.air || self.walkable(next, true) {
                        self.bodies[i].p = next;
                    }
                }
            }
        }
        let mut firing = vec![];
        for (i, b) in self
            .bodies
            .iter()
            .enumerate()
            .filter(|(_, b)| b.active && b.hp > 0. && b.ammo > 0 && self.frame >= b.next)
        {
            let precision=self.version!=VERSION&&b.ally&&self.groups.iter().any(|g|g.card.id==b.group&&g.buff_until>self.frame&&profile(g.card.id).unwrap().ability=="precision");
            let range=b.range*if precision{1.15}else{1.};
            let target = self
                .bodies
                .iter()
                .filter(|t| {
                    t.active
                        && t.hp > 0.
                        && t.ally != b.ally
                        && (!t.air || b.air || self.version!=VERSION&&b.kind=="aa_team")
                        && t.p.dist(b.p) <= range
                        && (self.version==VERSION||b.kind!="howitzer"||t.p.dist(b.p)>=500.)
                        && (b.air || self.version!=VERSION&&b.kind=="howitzer" || self.island_geometry.is_some()&&t.kind=="landing_craft" || self.clear(b.p, t.p, true))
                })
                .min_by(|a, c| a.p.dist(b.p).total_cmp(&c.p.dist(b.p)))
                .map(|t| t.p)
                .or_else(|| {
                    self.buildings
                        .iter()
                        .filter(|t| {
                            t.hp > 0.
                                && t.ally != b.ally
                                && t.p.dist(b.p) <= range
                                && (self.version==VERSION||b.kind!="howitzer"||t.p.dist(b.p)>=500.)
                                && (b.air || self.version!=VERSION&&b.kind=="howitzer" || self.clear(b.p, t.p, true))
                        })
                        .min_by(|a, c| a.p.dist(b.p).total_cmp(&c.p.dist(b.p)))
                        .map(|t| t.p)
                });
            if let Some(p) = target {
                firing.push((i, p));
            }
        }
        for (i, p) in firing {
            let b = self.bodies[i].clone();
            let radius = if self.version!=VERSION&&b.kind=="howitzer" {180.}else if ["tank", "ifv", "gunship"].contains(&b.kind) {
                110.
            } else {
                55.
            };
            if self.launch(
                b.ally,
                b.p,
                p,
                b.damage * if self.version!=VERSION&&b.ally&&self.groups.iter().any(|g|g.card.id==b.group&&g.buff_until>self.frame&&profile(g.card.id).unwrap().ability=="precision"){1.6}else{1.},
                radius,
                1200.,
                false,
                b.kind,
                format!("body:{}", b.id),
            ) {
                self.bodies[i].ammo -= 1;
                let coordinated=self.version!=VERSION&&b.ally&&self.groups.iter().any(|g|g.stage=="ground"&&g.buff_until>self.frame&&profile(g.card.id).unwrap().ability=="coordination"&&g.p.dist(b.p)<=900.);
                self.bodies[i].next = self.frame + if coordinated{(b.reload as f64*0.65).ceil() as u32}else{b.reload};
            }
        }
        let mut batteries = vec![];
        for (i, b) in self.buildings.iter().enumerate().filter(|(_, b)| {
            b.hp > 0.
                && b.ammo > 0
                && self.frame >= b.next
                && ["aa", "turret"].contains(&b.kind.as_str())
        }) {
            let aa = b.kind == "aa";
            let range = if aa { 2600. } else { 1700. };
            let target = self
                .bodies
                .iter()
                .filter(|t| {
                    t.ally != b.ally
                        && t.active
                        && t.hp > 0.
                        && (!aa || t.air)
                        && t.p.dist(b.p) <= range
                })
                .min_by(|a, c| a.p.dist(b.p).total_cmp(&c.p.dist(b.p)))
                .map(|t| t.p)
                .or_else(|| {
                    if aa && !b.ally {
                        self.transports
                            .iter()
                            .filter(|t| t.air && t.hp > 0. && t.p.dist(b.p) < range)
                            .min_by(|a, c| a.p.dist(b.p).total_cmp(&c.p.dist(b.p)))
                            .map(|t| t.p)
                    } else {
                        None
                    }
                });
            if let Some(p) = target {
                batteries.push((i, p));
            }
        }
        for (i, p) in batteries {
            let b = self.buildings[i].clone();
            let aa = b.kind == "aa";
            if self.launch(
                b.ally,
                b.p,
                p,
                (if aa { 45. } else { 28. }) * b.level as f64,
                if aa { 190. } else { 130. },
                1500.,
                aa,
                if aa { "aa" } else { "turret" },
                b.id,
            ) {
                self.buildings[i].ammo -= 1;
                self.buildings[i].next = self.frame + 30;
            }
        }
        let mut hits = vec![];
        for p in &mut self.projectiles {
            let d = p.p.dist(p.goal);
            let step = p.speed * DT;
            if d <= step {
                p.p = p.goal;
                hits.push(p.clone());
            } else {
                p.p = p.p + (p.goal - p.p) * (step / d);
            }
        }
        self.projectiles.retain(|p| p.p.dist(p.goal) > 0.01);
        for p in hits {
            self.blast(
                p.goal, p.damage, p.radius, p.ally, p.air_only, p.kind, &p.source,
            );
        }
        if self.config.mode == "raid" {
            if let Some(hq) = self.buildings.iter().find(|b| b.kind == "hq") {
                let near = self
                    .bodies
                    .iter()
                    .any(|b| b.ally && b.active && b.hp > 0. && !b.air && b.p.dist(hq.p) < 500.);
                let contested = self
                    .bodies
                    .iter()
                    .any(|b| !b.ally && b.active && b.hp > 0. && (self.version==VERSION||!b.air) && b.p.dist(hq.p) < 550.);
                if near && !contested {
                    let bonus=self.version!=VERSION&&self.groups.iter().any(|g|["MCP-011","MCP-203"].contains(&v4::unit_id(g.card.id))&&g.stage=="ground"&&g.p.dist(hq.p)<500.&&self.group_health(self.groups.iter().position(|a|a.card.id==g.card.id).unwrap())>0.);
                    self.capture = (self.capture + (if bonus{2}else{1})*if matches!(self.version,VERSION_V3|v4::VERSION){2}else{1}).min(80);
                }
            }
        }
        if self.island_geometry.is_some(){return}
        if self.config.mode != "defense" && self.ships.iter().filter(|s| s.ally).all(|s| s.hp <= 0.)
            || self.config.mode == "defense"
                && !self.buildings.iter().any(|b| b.kind == "hq" && b.hp > 0.)
        {
            self.finish(false, false);
        } else if self.config.mode == "defense" && self.frame >= 1800 {
            self.finish(true, false);
        } else if self.frame >= if self.version==v4::VERSION{18000}else{LIMIT} {
            self.finish(false, false);
        }
    }
    fn finish(&mut self, success: bool, abandoned: bool) {
        if self.result.is_some() {
            return;
        }
        let defense = self.config.mode == "defense";
        let units:Vec<_>=self.groups.iter().enumerate().map(|(i,g)|{let recovered=defense&&success||["embarked","recovered"].contains(&g.stage)&&self.ships.iter().any(|s|s.id==g.carrier&&s.hp>0.);let missing=!recovered&&self.group_health(i)>0.;let hp=if missing{0.}else{self.group_health(i)};let surviving=self.bodies.iter().filter(|b|b.group==g.card.id&&b.hp>0.).count();json!({"id":g.card.id,"hp_percent":hp,"initial_hp_percent":g.initial,"incapacitated":hp<10.,"recovered":recovered,"missing":missing,"carrier":g.carrier,"initial_count":g.card.count,"surviving_count":if surviving==0&&hp>0.{g.card.count as usize}else{surviving}})}).collect();
        let ships:Vec<_>=self.ships.iter().filter(|s|s.ally).map(|s|json!({"id":s.def.id,"ship_id":s.id,"hp_percent":s.hp.max(0.)/s.max*100.,"initial_hp_percent":s.initial,"ammo_percent":s.ammo,"requested_ammo_percent":s.requested,"loaded_ammo_percent":s.loaded,"unloaded_ammo_percent":s.requested-s.loaded,"ammo_spent_percent":s.loaded-s.ammo,"sunk":s.hp<=0.,"recovered":s.hp>0.&&(defense&&success||s.p.dist(self.exit_point())<=1600.)})).collect();
        let mut scrap = 0;
        let mut alloy = 0;
        let mut protocols = 0;
        let mut credits = 0;
        if success && !abandoned {
            for item in &self.loot {
                if units.iter().any(|u| {
                    u["id"] == item.holder
                        && u["recovered"] == true
                        && u["hp_percent"].as_f64().unwrap_or(0.) > 0.
                }) {
                    match item.kind.as_str() {
                        "scrap" => scrap += item.amount,
                        "alloy" => alloy += item.amount,
                        "protocols" => protocols += item.amount,
                        _ => {}
                    }
                }
            }
            if self.config.mode == "raid" {
                scrap += 40;
                credits = 80;
            }
            if defense {
                scrap += 30;
                credits = 50;
            }
        }
        let buildings: Vec<_> = self
            .buildings
            .iter()
            .map(|b| json!({"id":b.id,"hp_percent":b.hp.max(0.)/b.max*100.,"destroyed":b.hp<=0.}))
            .collect();
        self.result = Some(
            json!({"version":self.version,"mode":self.config.mode,"success":success,"abandoned":abandoned,"duration":self.tick(),"frame":self.frame,"resources":{"scrap":scrap,"alloy":alloy,"protocols":protocols,"credits":credits},"ships":ships,"units":units,"buildings":buildings,"objective_complete":self.objective_complete(),"island_secured":success&&self.config.mode=="raid","searched_ruins":self.ruins.iter().filter(|r|r.searched).count(),"enemy_defeated":self.enemy_dead}),
        );
        if matches!(self.version,VERSION_V3|v4::VERSION){let result=self.result.as_mut().unwrap();result["lesson"]=json!(self.config.lesson);result["landed_company_ids"]=json!(self.landed_companies);result["shore_support_hits"]=json!(self.shore_support_hits);for(i,g)in self.groups.iter().enumerate(){result["units"][i]["company_id"]=json!(g.card.id);result["units"][i]["transport_kind"]=json!(g.transport_kind);}}
        self.event(
            "end",
            if success {
                "本次目标与回收已由实际战况确认"
            } else {
                "行动结束，真实伤亡与消耗已保留"
            },
            P {
                x: 13000.,
                y: 8000.,
            },
        );
    }
    pub fn save(&self) -> Saved {
        Saved {
            version: self.version.into(),
            seed: self.seed,
            config: self.config.clone(),
            frame: self.frame,
            tick: self.tick(),
            commands: self.commands.clone(),
        }
    }
    pub fn from_save(s: Saved, target: Option<u32>) -> E<Self> {
        if ![VERSION,VERSION_V2,VERSION_V3].contains(&s.version.as_str())
            || s.frame > LIMIT
            || !s.tick.is_finite()
            || (s.tick - s.frame as f64 / 10.).abs() > 1e-6
            || s.commands.len() > 15000
            || s.commands.iter().any(|c| c.frame > s.frame)
            || s.commands.windows(2).any(|c| c[0].frame > c[1].frame)
        {
            return Err("两栖存档版本、时钟或命令日志无效".into());
        }
        let target = target.unwrap_or(s.frame);
        if target > s.frame {
            return Err("不能重演到存档之后的未来时刻".into());
        }
        let mut w = Self::new_version(s.seed, s.config,&s.version)?;
        let mut commands = s.commands.into_iter().peekable();
        loop {
            while commands
                .peek()
                .is_some_and(|c| c.frame == w.frame && c.frame <= target)
            {
                let c = commands.next().unwrap();
                w.command(&c.request, true)?;
            }
            if w.frame >= target {
                break;
            }
            if w.result.is_some() {
                return Err("两栖重演越过真实终局".into());
            }
            w.advance();
        }
        Ok(w)
    }
    fn return_carrier(&self, index: usize) -> Option<u32> {
        let g = &self.groups[index];
        if self.version == v4::VERSION {
            let accepts = |s: &&SeaShip| {
                if !s.ally || s.hp <= 0. || v4::carrier_eligibility(g.card.id, g.transport_kind, &s.def.id).is_err() { return false; }
                let used: u32 = self.groups.iter().enumerate()
                    .filter(|(i, other)| *i != index && other.carrier == s.id && other.stage != "lost"
                        && (self.config.mode != "defense" || ["embarked", "transit", "returning", "recovered"].contains(&other.stage)))
                    .map(|(_, other)| other.card.slots).sum();
                s.slots.saturating_sub(used) >= g.card.slots
            };
            return self.ships.iter().filter(accepts)
                .min_by_key(|s| (s.id != g.carrier, s.id)).map(|s| s.id);
        }
        self.ships
            .iter()
            .find(|s| s.id == g.carrier && s.hp > 0.)
            .map(|s| s.id)
            .or_else(|| {
                self.ships
                    .iter()
                    .filter(|s| s.ally && s.hp > 0. && (self.version!=v4::VERSION || v4::carrier_eligibility(g.card.id,g.transport_kind,&s.def.id).is_ok()))
                    .find(|s| {
                        let used: u32 = self
                            .groups
                            .iter()
                            .filter(|g| g.carrier == s.id && g.stage != "lost")
                            .map(|g| g.card.slots)
                            .sum();
                        s.slots.saturating_sub(used) >= g.card.slots
                    })
                    .map(|s| s.id)
            })
    }
    fn group_status(&self, index: usize) -> &'static str {
        let g = &self.groups[index];
        if g.stage == "ground" && g.order == "retreat" && g.path.is_empty() {
            if self.return_carrier(index).is_none() {
                if self.version == v4::VERSION { "没有兼容且身体舱位足够的存活载舰" } else { "载舰已损失，其他存活舰没有足够备用运输舱" }
            } else {
                "等待载舰驶近滩头接驳范围"
            }
        } else {
            match g.stage {
                "transit" => "真实运输载具正在驶向登陆点",
                "returning" => "运输载具正在返回存活载舰",
                "ground" => "部队在岸上执行地面指令",
                "lost" => "部队已经失去战斗能力",
                "recovered" => "部队已实际撤回载舰",
                _ => "部队在载舰上待命",
            }
        }
    }
    pub fn view(&self) -> Value {
        let ships:Vec<_>=self.ships.iter().filter(|s|s.ally).map(|s|json!({"id":s.id,"name":s.def.name,"characterId":s.def.id,"kind":s.def.kind.to_lowercase(),"transport_role":transport_role(&s.def.kind),"fleet":1,"x":s.p.x,"y":s.p.y,"heading":s.h,"target_heading":s.facing,"speed":if s.path.is_empty()||s.anchor{0.}else{s.speed},"hp":s.hp,"maxHp":s.max,"ammo":s.ammo,"mainCaliberMm":s.def.gun.caliber_mm,"gunRange":s.def.gun.range_yd.last().copied().unwrap_or(0.)*YARD,"hullLengthM":s.def.length_m,"anchored":s.anchor,"unmooring":s.unmoor>0&&s.anchor,"transport_slots":s.slots,"gun":s.def.gun.barrels>0,"torpedo":false,"systems":{"guns":[],"tubes":[],"maxSpeed":s.def.max_knots}})).collect();
        let contacts:Vec<_>=self.ships.iter().filter(|s|!s.ally&&s.hp>0.).map(|s|json!({"id":format!("L{}",s.id),"ship_id":s.id,"name":s.def.name,"kind":s.def.kind.to_lowercase(),"entityKind":"ship","x":s.p.x,"y":s.p.y,"heading":s.h,"target_heading":s.facing,"speed":if s.anchor||s.path.is_empty(){0.}else{s.speed},"health":s.hp,"max_health":s.max,"anchored":s.anchor,"unmooring":s.unmoor>0&&s.anchor,"identified":true,"intelligence":{"attack_range":s.def.gun.range_yd.last().copied().unwrap_or(0.)*YARD,"speed_max":s.def.max_knots}})).collect();
        let groups:Vec<_>=self.groups.iter().enumerate().map(|(i,g)|{let p=if ["embarked","recovered"].contains(&g.stage){self.ships.iter().find(|s|s.id==g.carrier).map_or(g.p,|s|s.p)}else{g.p};json!({"id":g.card.id,"name":g.card.name,"role":g.card.role,"carrier":g.carrier,"insertion":g.insertion,"stage":g.stage,"position":p,"hp_percent":self.group_health(i),"initial_hp_percent":g.initial,"order":g.order,"target":g.target,"transport_slots":g.card.slots,"supplies":g.supplies,"beach":g.beach,"status_reason":self.group_status(i)})}).collect();
        let entities:Vec<_>=self.bodies.iter().filter(|b|b.active&&b.hp>0.).map(|b|json!({"id":b.id,"unit_id":b.group,"side":if b.ally{"allies"}else{"axis"},"kind":b.kind,"presentation":"female_android","x":b.p.x,"y":b.p.y,"hp":b.hp,"max_hp":b.max,"ammo":b.ammo,"airborne":b.air,"range":b.range,"damage":b.damage,"reload_seconds":b.reload as f64/10.,"order":self.groups.iter().find(|g|g.card.id==b.group).map_or("attack",|g|g.order.as_str())})).collect();
        let buildings:Vec<_>=self.buildings.iter().map(|b|json!({"id":b.id,"side":if b.ally{"allies"}else{"axis"},"kind":b.kind,"x":b.p.x,"y":b.p.y,"hp":b.hp,"max_hp":b.max,"level":b.level,"ammo":b.ammo})).collect();
        let ruins:Vec<_>=self.ruins.iter().map(|r|json!({"id":r.id,"x":r.p.x,"y":r.p.y,"progress":r.progress as f64/80.,"searched":r.searched,"loot":match r.id{1=>json!({"scrap":60}),2=>json!({"alloy":25}),_=>json!({"protocols":1})}})).collect();
        let transports:Vec<_>=self.transports.iter().map(|t|json!({"id":t.id,"unit_id":self.groups[t.group].card.id,"carrier":t.carrier,"kind":if t.air{"helicopter"}else{"landing_craft"},"x":t.p.x,"y":t.p.y,"target":t.goal,"hp":t.hp,"max_hp":t.max,"returning":t.returning})).collect();
        let naval:Vec<_>=self.ships.iter().filter(|s|s.ally).map(|s|json!({"ship":s.id,"ammo":s.ammo,"range":s.def.gun.range_yd.last().copied().unwrap_or(0.)*YARD,"arcs":Self::gun_arcs(s),"alive":s.hp>0.,"anchored":s.anchor,"ready_in":s.next.saturating_sub(self.frame) as f64/10.,"pending_target":s.pending_support.map(|(p,_)|p),"pending_expires_tick":s.pending_support.map(|(_,frame)|frame as f64/10.)})).collect();
        let helicopter:Vec<_>=self.groups.iter().filter(|g|g.card.air).map(|g|{let b=self.bodies.iter().find(|b|b.group==g.card.id&&b.air&&b.hp>0.&&b.active);json!({"unit_id":g.card.id,"available":b.is_some_and(|b|b.ammo>0),"ammo":b.map_or(0,|b|b.ammo)})}).collect();
        let hq = self.buildings.iter().find(|b| b.kind == "hq").unwrap();
        let objective = json!({"id":"primary","kind":match self.config.mode.as_str(){"raid"=>"capture_hq","defense"=>"hold_hq",_=>"search_ruin"},"x":if ["raid","defense"].contains(&self.config.mode.as_str()){hq.p.x}else{self.ruins[0].p.x},"y":if ["raid","defense"].contains(&self.config.mode.as_str()){hq.p.y}else{self.ruins[0].p.y},"progress":match self.config.mode.as_str(){"raid"=>self.capture as f64/80.,"defense"=>(self.frame as f64/1800.).min(1.),_=>if self.ruins.iter().any(|r|r.searched){1.}else{0.}},"complete":self.objective_complete()});
        let phase = if self.result.is_some() {
            "finished"
        } else if !self.transports.is_empty() {
            "landing"
        } else if self.groups.iter().any(|g| g.stage == "ground") {
            "ground"
        } else if self.objective_complete() {
            "extracting"
        } else {
            "embarked"
        };
        let mut activity = json!({"version":self.version,"mode":self.config.mode,"frame":self.frame,"simulation_hz":HZ,"phase":phase,"beaches":(1..=3).map(|id|{let(sea,land)=self.beach_for(id).unwrap();json!({"id":id,"name":format!("{}号滩头",id),"sea":sea,"land":land})}).collect::<Vec<_>>(),"groups":groups,"transports":transports,"land":{"bounds":{"x":8000,"y":2500,"width":10500,"height":8500},"polygon":self.polygon,"obstacles":self.obstacles,"entities":entities,"buildings":buildings,"ruins":ruins,"mines":self.mines.iter().map(|m|json!({"id":m.id,"x":m.p.x,"y":m.p.y,"active":m.active})).collect::<Vec<_>>()},"objectives":[objective],"cargo":self.loot,"exit":{"x":5500,"y":13500,"radius":1600},"support":{"naval":naval,"helicopter":helicopter},"shots":self.shots,"impacts":self.impacts,"budget":{"friendly_bodies":32,"enemy_bodies":64,"projectiles":MAX_PROJECTILES,"transports":5,"recent_records":RECENT},"outcome":self.result});
        if self.version!=VERSION {
            activity["budget"]["transports"]=json!(6);
            for (i,g) in self.groups.iter().enumerate(){
                let p=profile(g.card.id).unwrap();
                activity["groups"][i]["role"]=json!(p.role);
                activity["groups"][i]["pending_deploy"]=g.pending.map_or(Value::Null,|(beach,air)|{let(sea,land)=self.beach_for(beach).unwrap();let ship=self.ships.iter().find(|s|s.id==g.carrier).unwrap();json!({"beach":beach,"insertion":if air{"air"}else{"landing"},"status":"approaching","distance":ship.p.dist(if air{land}else{sea}),"range_limit":if air{6000}else{900},"reason":"载舰正驶近真实接驳范围"})});
                activity["groups"][i]["ability"]=json!({"id":p.ability,"name":ability_name(p.ability),"charges":g.ability_charges,"ready_in":g.ability_next.saturating_sub(self.frame) as f64/10.,"available":g.stage=="ground"&&g.ability_charges>0&&self.frame>=g.ability_next&&self.group_health(i)>0.,"range":p.ability_range,"radius":p.ability_radius,"active_seconds":g.buff_until.saturating_sub(self.frame) as f64/10.,"reserve_ammo":g.reserve_ammo});
            }
            for(i,s)in self.ships.iter().filter(|s|s.ally).enumerate(){
                let si=self.ships.iter().position(|a|a.id==s.id).unwrap();
                let reason=s.aim_target.and_then(|p|self.gun_error(si,p,false));
                activity["support"]["naval"][i]["aim_target"]=json!(s.aim_target);
                activity["support"]["naval"][i]["aim_state"]=json!(if s.aim_target.is_none(){"unassigned"}else if s.facing.is_some(){"turning"}else if reason.is_none(){"ready"}else{"waiting"});
                activity["support"]["naval"][i]["ready_for_target"]=json!(s.aim_target.is_some()&&reason.is_none());
                activity["support"]["naval"][i]["reason"]=json!(reason);
            }
        }
        if matches!(self.version,VERSION_V3|v4::VERSION) {
            activity["budget"]["friendly_bodies"]=json!(50);activity["budget"]["enemy_bodies"]=json!(64);activity["budget"]["bodies"]=json!(128);activity["budget"]["projectiles"]=json!(384);activity["budget"]["transports"]=json!(5);
            activity["ground_speed_multiplier"]=json!(2.5);activity["ground_reload_multiplier"]=json!(1./1.8);
            activity["training"]=json!({"lesson":self.lesson(),"enemies_afloat":self.ships.iter().filter(|s|!s.ally&&s.hp>0.).count(),"landed_company_ids":self.landed_companies,"shore_support_hits":self.shore_support_hits,"searched_ruins":self.ruins.iter().filter(|r|r.searched).count(),"complete":self.objective_complete()});
            if self.config.mode=="tutorial"{activity["objectives"][0]["kind"]=json!(match self.lesson(){"sea_control"=>"sea_control","combined"=>"combined_training",_=>"search_ruin"});activity["objectives"][0]["progress"]=json!(if self.objective_complete(){1.}else if self.lesson()=="combined"{(self.landed_companies.len().min(2) as f64/2.+if self.shore_support_hits>0{1.}else{0.}+if self.ruins.iter().any(|r|r.searched){1.}else{0.})/3.}else{0.});}
            for(i,g)in self.groups.iter().enumerate(){let(hp,armor,speed,_)=transport_stats(g.card.id,g.transport_kind);let alive=self.bodies.iter().filter(|b|b.group==g.card.id&&b.hp>0.).count();activity["groups"][i]["company_id"]=json!(g.card.id);activity["groups"][i]["company_count"]=json!(1);activity["groups"][i]["personnel_count"]=json!(g.card.count);activity["groups"][i]["surviving_personnel"]=json!(if self.bodies.iter().any(|b|b.group==g.card.id){alive}else if g.stage=="lost"{0}else{g.card.count as usize});activity["groups"][i]["transport_kind"]=json!(g.transport_kind);activity["groups"][i]["transport_stats"]=json!({"hp":hp,"armor":armor,"speed":speed});activity["groups"][i]["vehicle_id"]=json!(format!("{}-{}",g.card.id,g.transport_kind));activity["groups"][i]["vehicle_ammo"]=json!(g.vehicle_ammo);}
            for e in activity["land"]["entities"].as_array_mut().unwrap(){e["company_id"]=e["unit_id"].clone();e["equipment_kind"]=e["kind"].clone();}
            for(i,t)in self.transports.iter().enumerate(){let g=&self.groups[t.group];let(_,armor,speed,_)=transport_stats(g.card.id,g.transport_kind);activity["transports"][i]["kind"]=json!(g.transport_kind);activity["transports"][i]["personnel_count"]=json!(g.card.count);activity["transports"][i]["armor"]=json!(armor);activity["transports"][i]["speed"]=json!(speed);activity["transports"][i]["vehicle_id"]=json!(format!("{}-{}",g.card.id,g.transport_kind));activity["transports"][i]["visual_id"]=json!(format!("{}-{}",g.card.id,g.transport_kind));activity["transports"][i]["vehicle_name"]=json!(vehicle_meta(g.card.id).0);activity["transports"][i]["art_variant"]=json!(if g.transport_kind==default_transport(g.card.id){vehicle_meta(g.card.id).1}else{g.transport_kind});activity["transports"][i]["ammo"]=json!(g.vehicle_ammo);}
        }
        if self.version==v4::VERSION {activity["exit"]=json!({"x":self.exit_point().x,"y":self.exit_point().y,"radius":1600});}
        let leader = self
            .ships
            .iter()
            .find(|s| s.ally && s.hp > 0.)
            .or(self.ships.first())
            .unwrap();
        let result=self.result.as_ref().map(|r|json!({"winner":if r["success"]==true{"allies"}else{"axis"},"primary":r["success"],"allies":self.enemy_dead,"axis":0}));
        json!({"version":self.version,"scenario":"岛屿海陆空协同行动","tick":self.tick(),"limit":480,"width":WIDTH,"height":HEIGHT,"side":"allies","intel_profile":crate::intel::VERSION,"islands":[self.polygon],"ships":ships,"contacts":contacts,"fleets":[{"id":1,"name":"两栖远征编队","leader":leader.id,"members":self.ships.iter().filter(|s|s.ally).map(|s|s.id).collect::<Vec<_>>(),"speed":leader.speed,"actual":if leader.path.is_empty(){0.}else{leader.speed},"mode":"follow","maxSpeed":40,"points":leader.path,"paths":self.ships.iter().filter(|s|s.ally).map(|s|json!({"ship":s.id,"points":std::iter::once(s.p).chain(s.path.iter().copied()).collect::<Vec<_>>()})).collect::<Vec<_>>() }],"shells":self.projectiles.iter().map(|p|json!({"id":p.id,"x":p.p.x,"y":p.p.y,"heading":(p.goal-p.p).heading(),"side":if p.ally{"allies"}else{"axis"},"kind":p.kind})).collect::<Vec<_>>(),"torpedoes":[],"events":self.events.iter().rev().take(48).collect::<Vec<_>>(),"result":result,"littoral":activity})
    }
}
