use crate::{model::*, world::World, Engine};
use serde_json::{json, Value};

fn ask(e: &mut Engine, r: Value) -> Value {
    let v = e.handle(r);
    assert_eq!(v["ok"], true, "{v}");
    v["data"].clone()
}
fn battle(seed: u32, side: &str, enemy: &str) -> Engine {
    let mut e = Engine::default();
    ask(
        &mut e,
        json!({"op":"new","seed":seed,"side":side,"enemy":enemy}),
    );
    e
}
#[test]
fn sync_translates_and_follow_waits_for_turn_point() {
    let points = json!([{"x":6600,"y":6550},{"x":6600,"y":9400}]);
    let mut ends = vec![];
    for mode in ["follow", "sync"] {
        let mut e = battle(6106, "allies", "coord");
        let p = ask(
            &mut e,
            json!({"op":"preview_route","fleet":1,"mode":mode,"points":points}),
        );
        assert_eq!(p["valid"], true, "{p}");
        assert_eq!(p["paths"].as_array().unwrap().len(), 5);
        ask(
            &mut e,
            json!({"op":"route","fleet":1,"mode":mode,"points":points}),
        );
        let v = ask(&mut e, json!({"op":"step","seconds":450}));
        let own = v["ships"].as_array().unwrap();
        assert!(own[0]["y"].as_f64().unwrap() > 6550.);
        if mode == "follow" {
            assert!((own[4]["heading"].as_f64().unwrap() - 90.).abs() < 1e-5);
            assert_eq!(own[4]["y"], json!(6550.0));
        } else {
            assert!(
                (own[4]["x"].as_f64().unwrap() - own[0]["x"].as_f64().unwrap() + 1800.).abs()
                    < 1e-5
            );
            assert_eq!(own[4]["y"], own[0]["y"]);
        }
        ends.push(v);
    }
    assert_ne!(ends[0]["ships"], ends[1]["ships"]);
}
#[test]
fn invalid_draft_is_non_mutating_and_cross_side_orders_are_rejected() {
    let mut e = battle(6106, "allies", "coord");
    let before = ask(&mut e, json!({"op":"save"}));
    let p = ask(
        &mut e,
        json!({"op":"preview_route","fleet":1,"mode":"sync","points":[{"x":300,"y":1000}]}),
    );
    assert_eq!(p["valid"], false);
    assert_eq!(
        e.handle(json!({"op":"route","fleet":2,"mode":"follow","points":[{"x":15500,"y":7150}]}))
            ["ok"],
        false
    );
    assert_eq!(
        e.handle(json!({"op":"fire","ship":6,"weapon":"gun","target":"C01"}))["ok"],
        false
    );
    assert_eq!(ask(&mut e, json!({"op":"save"})), before);
}
#[test]
fn manual_order_revokes_only_its_own_delegation_and_fires_on_window() {
    let mut e = battle(6106, "allies", "coord");
    ask(
        &mut e,
        json!({"op":"ai","fleet":1,"profile":"coord","mode":"auto","move":true,"gun":true,"torpedo":true}),
    );
    let r = ask(
        &mut e,
        json!({"op":"route","fleet":1,"mode":"follow","points":[{"x":6500,"y":6550}]}),
    );
    assert_eq!(r["fleets"][0]["ai"]["move"], false);
    assert_eq!(r["fleets"][0]["ai"]["gun"], true);
    let id = r["contacts"][0]["id"].clone();
    let aim = ask(
        &mut e,
        json!({"op":"aim","ship":1,"weapon":"gun","target":id}),
    );
    assert_eq!(aim["valid"], true, "{aim}");
    let accepted = ask(
        &mut e,
        json!({"op":"fire","ship":1,"weapon":"gun","target":id}),
    );
    assert_eq!(accepted["fleets"][0]["ai"]["gun"], false);
    assert_eq!(accepted["fleets"][0]["ai"]["torpedo"], true);
    assert!(accepted["events"]
        .as_array()
        .unwrap()
        .iter()
        .all(|e| e["kind"] != "gun"));
    let before = ask(&mut e, json!({"op":"step","seconds":179}));
    assert!(before["events"]
        .as_array()
        .unwrap()
        .iter()
        .all(|e| e["kind"] != "gun"));
    let after = ask(&mut e, json!({"op":"step","seconds":1}));
    assert!(after["events"]
        .as_array()
        .unwrap()
        .iter()
        .any(|e| e["kind"] == "gun" && e["tick"] == 180));
}
#[test]
fn duel_has_exchange_and_full_replay() {
    let mut w = World::new(6106, 0, "torpedo", "", "gunnery", 0).unwrap();
    w.external(json!({"op":"ai","fleet":1,"profile":"gunnery","mode":"auto","move":true,"gun":true,"torpedo":true})).unwrap();
    while w.result.is_none() {
        w.advance()
    }
    for mask in [1, 2] {
        assert!(w.events.iter().any(|e| e.mask == mask && e.kind == "gun"));
        assert!(w
            .events
            .iter()
            .any(|e| e.mask == mask && e.kind == "damage"));
    }
    assert!(w.events.iter().any(|e| e.kind == "torpedo"));
    let end = w.tick;
    let replay = World::from_save(w.save(), end).unwrap();
    for side in 0..2 {
        assert_eq!(w.observation(side), replay.observation(side))
    }
    assert_eq!(w.result, replay.result);
}
#[test]
fn close_range_torpedo_uses_actual_mount_and_advancing_spread() {
    let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
    w.fleets[1].ai = Ai::new("coord", "manual");
    w.ship_mut(1).unwrap().p = P { x: 6000., y: 6200. };
    w.ship_mut(6).unwrap().p = P { x: 6000., y: 7430. };
    w.detect(true);
    let target = w.contacts[0]
        .iter()
        .find(|c| c.ship == 6)
        .unwrap()
        .id
        .clone();
    w.tick = 179;
    let aim = w
        .preview_aim(0, &json!({"ship":1,"target":target}))
        .unwrap();
    assert_eq!(aim["valid"], true, "{aim}");
    let bad = w.queue_fire(
        0,
        &json!({"ship":1,"weapon":"torpedo","target":target,"heading":90.}),
        true,
    );
    assert!(bad.is_err());
    let ammo = w.ship(1).unwrap().ammo;
    assert!(w.torps.is_empty());
    w.external(json!({"op":"fire","ship":1,"weapon":"torpedo","target":target,"heading":0.}))
        .unwrap();
    assert_eq!(w.ship(1).unwrap().ammo, ammo);
    w.advance();
    assert_eq!(w.torps.len(), 1);
    assert_eq!(w.torps[0].p, w.ship(1).unwrap().p);
    assert_eq!(w.ship(1).unwrap().ammo, ammo - 5);
    for _ in 0..100 {
        w.advance();
    }
    assert!(w.events.iter().any(|e| e.kind == "torpedo_hit"));
    assert!(w.ship(6).unwrap().hp < w.data.ships[w.ship(6).unwrap().def].dp);
}
#[test]
fn distant_undetected_truth_does_not_appear_in_preview_or_observation() {
    let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
    for s in &mut w.ships {
        if s.side == 1 {
            s.p = P {
                x: 50_000.,
                y: 55_000.,
            }
        }
    }
    w.detect(false);
    let v = w.observation(0);
    assert!(v["contacts"].as_array().unwrap().is_empty());
    assert_eq!(v["ships"].as_array().unwrap().len(), 5);
    let route = w
        .preview(
            0,
            &json!({"fleet":1,"mode":"follow","points":[{"x":6000,"y":6550}]}),
        )
        .unwrap();
    assert_eq!(route["valid"], true);
    assert!(!v.to_string().contains("阳炎"));
}
#[test]
fn challenge_has_real_three_ship_roster_and_selected_leader() {
    let mut e = Engine::default();
    let r = ask(
        &mut e,
        json!({"op":"new","seed":1,"side":"allies","enemy":"coord","variant":"challenge","profile":"torpedo","leaderSlot":1}),
    );
    assert_eq!(r["ships"].as_array().unwrap().len(), 3);
    assert_eq!(r["ships"][0]["kind"], "cl");
    assert_eq!(r["fleets"][0]["ai"]["profile"], "torpedo");
    let save = ask(&mut e, json!({"op":"save"}));
    let rebuilt = ask(&mut e, json!({"op":"load","save":save}));
    assert_eq!(r, rebuilt);
}

#[test]
fn deployment_lead_change_keeps_route_available() {
    let mut e = battle(6106, "allies", "coord");
    let v = ask(&mut e, json!({"op":"lead","fleet":1,"ship":3}));
    assert_eq!(v["fleets"][0]["leader"], 3);
    assert_eq!(v["ships"][2]["x"], 4200.);
    let p = ask(
        &mut e,
        json!({"op":"preview_route","fleet":1,"mode":"follow","points":[{"x":6800,"y":6550}]}),
    );
    assert_eq!(p["valid"], true, "{p}");
}
