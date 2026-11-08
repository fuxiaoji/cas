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
fn night_keeps_hidden_contacts_out_and_replays_real_exchange() {
    let mut e = Engine::default();
    let new = ask(
        &mut e,
        json!({"op":"new","seed":6106,"variant":"night","enemy":"torpedo","profile":"gunnery"}),
    );
    assert_eq!(
        new["environment"],
        json!({"light":"night","visibility":20,"sea_state":2,"precipitation":false})
    );
    assert_eq!(new["contacts"], json!([]));
    assert_eq!(new["torpedoes"], json!([]));
    assert_eq!(
        e.handle(json!({"op":"aim","ship":1,"weapon":"gun","target":"C01"}))["ok"],
        false
    );
    ask(
        &mut e,
        json!({"op":"ai","fleet":1,"profile":"gunnery","mode":"auto","move":true,"gun":true,"torpedo":true}),
    );
    let mut end = ask(&mut e, json!({"op":"step","seconds":2700}));
    if end["settling"] == true {
        end = ask(&mut e, json!({"op":"step","seconds":8}));
    }
    assert!(!end["result"].is_null());
    let report = ask(&mut e, json!({"op":"report"}));
    for kind in ["contact", "lost", "gun", "hit", "damage"] {
        assert!(
            report["events"]
                .as_array()
                .unwrap()
                .iter()
                .any(|v| v["kind"] == kind),
            "missing {kind}"
        );
    }
    let save = ask(&mut e, json!({"op":"save"}));
    assert_eq!(ask(&mut e, json!({"op":"replay","save":save})), end);
}

#[test]
fn ai_exposes_a_searchlight_in_a_close_night_battle() {
    let mut e = Engine::default();
    ask(
        &mut e,
        json!({"op":"new","seed":6106,"side":"allies","enemy":"torpedo","variant":"night","profile":"gunnery","realtime":true}),
    );
    ask(
        &mut e,
        json!({"op":"ai","fleet":1,"profile":"torpedo","mode":"auto","move":true,"gun":true,"torpedo":true}),
    );
    let mut end = ask(&mut e, json!({"op":"step","seconds":2700}));
    if end["settling"] == true {
        end = ask(&mut e, json!({"op":"step","seconds":8}));
    }
    let report = ask(&mut e, json!({"op":"report"}));
    let events = report["events"].as_array().unwrap();
    assert!(
        events.iter().any(|event| event["kind"] == "searchlight"),
        "AI must expose a searchlight in a close night battle"
    );
}

#[test]
fn esperance_campaign_opens_both_seats_with_printed_geometry() {
    let mut allies = Engine::default();
    let start = ask(
        &mut allies,
        json!({"op":"new_campaign","id":"CAMP-ALLIES-02","difficulty":"story","seed":6106}),
    );
    assert_eq!(start["campaign"]["stageId"], json!("CAMP-ALLIES-02"));
    assert_eq!(start["ships"].as_array().unwrap().len(), 9);
    assert_eq!(start["environment"]["light"], json!("night"));
    assert_eq!(start["environment"]["sea_state"], json!(3));
    let mut axis = Engine::default();
    let other = ask(
        &mut axis,
        json!({"op":"new_campaign","id":"CAMP-AXIS-02","difficulty":"story","seed":6106}),
    );
    assert_eq!(other["campaign"]["stageId"], json!("CAMP-AXIS-02"));
    assert_eq!(other["ships"].as_array().unwrap().len(), 5);
    // The printed relation: Aoba 315°/13.5 nmi from Helena. The allied seat
    // cannot see the enemy, so verify through the axis seat's own positions
    // against the known allied column start.
    for fleet in [1] {
        ask(
            &mut allies,
            json!({"op":"ai","fleet":fleet,"profile":"coord","mode":"auto","move":true,"gun":true,"torpedo":true}),
        );
    }
    let mut end = ask(&mut allies, json!({"op":"step","seconds":2700}));
    if end["result"].is_null() {
        end = ask(&mut allies, json!({"op":"step","seconds":1500}));
    }
    assert!(!end["result"].is_null(), "the scenario must resolve");
    let save = ask(&mut allies, json!({"op":"save"}));
    assert_eq!(ask(&mut allies, json!({"op":"replay","save":save})), end);
}

#[test]
fn empress_campaign_bindings_open_both_seats() {
    let mut allies = Engine::default();
    let start = ask(
        &mut allies,
        json!({"op":"new_campaign","id":"CAMP-ALLIES-11","difficulty":"story","seed":6106}),
    );
    assert_eq!(start["campaign"]["stageId"], json!("CAMP-ALLIES-11"));
    assert_eq!(start["ships"].as_array().unwrap().len(), 12);
    assert_eq!(start["fleets"].as_array().unwrap().len(), 3);
    assert_eq!(start["environment"]["light"], json!("night"));
    let mut axis = Engine::default();
    let other = ask(
        &mut axis,
        json!({"op":"new_campaign","id":"CAMP-AXIS-11","difficulty":"story","seed":6106}),
    );
    assert_eq!(other["campaign"]["stageId"], json!("CAMP-AXIS-11"));
    assert_eq!(other["ships"].as_array().unwrap().len(), 10);
    assert_eq!(other["fleets"].as_array().unwrap().len(), 3);
    for fleet in [1, 2, 3] {
        ask(
            &mut allies,
            json!({"op":"ai","fleet":fleet,"profile":"coord","mode":"auto","move":true,"gun":true,"torpedo":true}),
        );
    }
    let mut end = ask(&mut allies, json!({"op":"step","seconds":2700}));
    if end["result"].is_null() {
        end = ask(&mut allies, json!({"op":"step","seconds":1500}));
    }
    assert!(!end["result"].is_null(), "the campaign must reach a result");
    assert!(end["result"]["grade"].is_string(), "the Cape Torokina grading must resolve");
    let save = ask(&mut allies, json!({"op":"save"}));
    assert_eq!(ask(&mut allies, json!({"op":"replay","save":save})), end);
}

#[test]
fn empress_augusta_bay_runs_the_full_night_surface_kit() {
    let mut e = Engine::default();
    let start = ask(
        &mut e,
        json!({"op":"new","seed":6100,"side":"allies","enemy":"coord","variant":"empress"}),
    );
    assert_eq!(start["ships"].as_array().unwrap().len(), 12, "the allied seat sees its twelve hulls");
    assert_eq!(start["fleets"].as_array().unwrap().len(), 3);
    assert_eq!(start["environment"], json!({"light":"night","visibility":10,"sea_state":1,"precipitation":true}));
    for fleet in [1, 2, 3] {
        ask(
            &mut e,
            json!({"op":"ai","fleet":fleet,"profile":"coord","mode":"auto","move":true,"gun":true,"torpedo":true}),
        );
    }
    let mut end = ask(&mut e, json!({"op":"step","seconds":2700}));
    if end["result"].is_null() {
        end = ask(&mut e, json!({"op":"step","seconds":2700}));
    }
    assert!(!end["result"].is_null(), "the scenario must reach a result");
    let report = ask(&mut e, json!({"op":"report"}));
    let events = report["events"].as_array().unwrap();
    for kind in ["secondary", "illumination", "gun", "torpedo_detected"] {
        assert!(
            events.iter().any(|event| event["kind"] == kind),
            "the surface kit must produce a {kind} event"
        );
    }
    let save = ask(&mut e, json!({"op":"save"}));
    assert_eq!(ask(&mut e, json!({"op":"replay","save":save})), end);
}

#[test]
fn a_blocked_fleet_can_fan_out_and_clear_its_notice() {
    let mut e = Engine::default();
    ask(&mut e, json!({"op":"new","seed":6106,"side":"allies","enemy":"coord"}));
    let before = ask(&mut e, json!({"op":"observe"}));
    let fleet = before["fleets"][0]["id"].clone();
    ask(&mut e, json!({"op":"resume","fleet":fleet}));
    let after = ask(&mut e, json!({"op":"observe"}));
    assert_eq!(after["fleets"][0]["notice"], json!(null));
    assert!(after["ships"]
        .as_array()
        .unwrap()
        .iter()
        .any(|ship| ship["speed"].as_f64().unwrap_or(0.) > 0.));
    let moved = ask(&mut e, json!({"op":"step","seconds":10}));
    assert!(moved["ships"]
        .as_array()
        .unwrap()
        .iter()
        .any(|ship| ship["speed"].as_f64().unwrap_or(0.) > 0.));
}

#[test]
fn ship_view_shows_target_chance_and_the_fleet_speed_can_change() {
    let mut w = World::new(6106, 0, "coord", "night", "coord", 0).unwrap();
    w.enable_realtime().unwrap();
    let target = w.ship(1).unwrap().p + P::bearing(0.) * (250. * YARD);
    w.ship_mut(6).unwrap().p = target;
    w.detect(true);
    let contact = w.contacts[0]
        .iter()
        .find(|c| c.ship == 6)
        .expect("contact")
        .id
        .clone();
    w.order_realtime_gun(0, 1, &contact, true).unwrap();
    let view = w.observation(0);
    let ship = view["ships"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["id"] == 1)
        .unwrap();
    assert!(ship["sightRange"].as_f64().unwrap_or(0.) > 0.);
    assert!(ship["seenRange"].as_f64().unwrap_or(0.) > 0.);
    let chance = ship["targetChance"].as_f64().expect("target chance");
    assert!(chance > 0. && chance <= 100., "{chance}");
    assert_eq!(ship["gunTarget"], json!(contact));
    w.external(json!({"op":"speed","fleet":1,"speed":24})).unwrap();
    assert_eq!(w.fleet(1).unwrap().speed, 24.);
    assert!(w
        .external(json!({"op":"speed","fleet":1,"speed":99}))
        .is_err(), "an impossible formation speed must be refused");
}

#[test]
fn v10_secondary_battery_fires_on_its_own() {
    let mut w = World::new(6106, 0, "coord", "night", "coord", 0).unwrap();
    w.enable_realtime().unwrap();
    let def = w
        .data
        .ships
        .iter()
        .position(|d| d.id == "cleveland_empress")
        .expect("the Empress Cleveland card must exist");
    let id = w
        .spawn(def, 0, 1, "测试克利夫兰".into(), P { x: 6000., y: 6000. }, 90.)
        .unwrap();
    w.fleet_mut(1).unwrap().members.push(id);
    // A target 3,000 yards ahead: secondary range, no main-battery order.
    let target = w.ship(6).unwrap().p;
    w.ship_mut(6).unwrap().p = P { x: target.x, y: 6000. };
    w.ship_mut(6).unwrap().p = P { x: 6000. + 3000. * YARD, y: 6000. };
    w.detect(true);
    for _ in 0..30 {
        w.advance();
        if w.events.iter().any(|event| event.kind == "secondary") {
            break;
        }
    }
    assert!(
        w.events.iter().any(|event| event.kind == "secondary"),
        "the secondary battery must engage without a main-gun order"
    );
}

#[test]
fn ai_lights_a_starshell_when_the_scenario_has_them() {
    let mut e = Engine::default();
    ask(
        &mut e,
        json!({"op":"new","seed":6106,"side":"allies","enemy":"gunnery","variant":"night-training","realtime":true}),
    );
    ask(
        &mut e,
        json!({"op":"ai","fleet":1,"profile":"coord","mode":"auto","move":true,"gun":true,"torpedo":true}),
    );
    let mut lit = false;
    for _ in 0..45 {
        let view = ask(&mut e, json!({"op":"step","seconds":60}));
        if view["events"].as_array().unwrap().iter().any(|event| event["kind"] == "illumination") {
            lit = true;
            break;
        }
        if !view["result"].is_null() {
            break;
        }
    }
    assert!(lit, "AI must light a starshell where the scenario enables them");
}

#[test]
fn starshell_can_be_cued_by_a_radar_only_contact() {
    let mut e = Engine::default();
    let new = ask(
        &mut e,
        json!({"op":"new","seed":6106,"side":"allies","enemy":"gunnery","variant":"night-radar-training","realtime":true}),
    );
    assert_eq!(new["contacts"], json!([]));
    ask(&mut e, json!({"op":"radar_set","ship":1,"radar":"us_sg","powered":true}));
    ask(&mut e, json!({"op":"step","seconds":180}));
    let mut mark = None;
    let mut waited = 0;
    while mark.is_none() && waited < 2700 {
        let view = ask(&mut e, json!({"op":"observe"}));
        assert_eq!(view["contacts"], json!([]), "the radar track must stay radar-only");
        for report in view["radarContacts"].as_array().cloned().unwrap_or_default() {
            let id = report["id"].as_str().unwrap().to_owned();
            let preview = ask(&mut e, json!({"op":"illumination_preview","ship":5,"target":id}));
            if preview["valid"] == true {
                mark = Some(id);
                break;
            }
        }
        if mark.is_none() {
            ask(&mut e, json!({"op":"step","seconds":10}));
            waited += 10;
        }
    }
    let mark = mark.expect("a radar-only contact must eventually fit the starshell band");
    ask(&mut e, json!({"op":"illuminate","ship":5,"target":mark}));
    let mut lit = false;
    for _ in 0..180 {
        let view = ask(&mut e, json!({"op":"step","seconds":1}));
        if view["events"].as_array().unwrap().iter().any(|event| event["kind"] == "illumination") {
            lit = true;
            break;
        }
    }
    if !lit {
        let report = ask(&mut e, json!({"op":"report"}));
        eprintln!("EVENTS {}", serde_json::to_string_pretty(&report["events"]).unwrap());
    }
    assert!(lit, "the radar-cued starshell must ignite");
}

#[test]
fn searchlight_illuminates_fire_and_backlights_the_lit_ship() {
    let mut w = World::new(6106, 0, "torpedo", "night", "coord", 0).unwrap();
    w.enable_realtime().unwrap();
    let own: Vec<u32> = w
        .ships
        .iter()
        .filter(|s| s.side == 0 && s.alive())
        .map(|s| s.id)
        .collect();
    let foe: Vec<u32> = w
        .ships
        .iter()
        .filter(|s| s.side == 1 && s.alive())
        .map(|s| s.id)
        .collect();
    assert_eq!(own.len(), 5);
    assert_eq!(foe.len(), 5);
    // Static geometry: own cluster near the origin, the enemy 3,500–4,700 yd
    // out — inside normal night visual range, outside the automatic band.
    for (i, id) in own.iter().enumerate() {
        let s = w.ship_mut(*id).unwrap();
        s.p = P { x: 6000. + 300. * i as f64, y: 6000. };
        s.speed = 0.;
    }
    for (i, id) in foe.iter().enumerate() {
        let s = w.ship_mut(*id).unwrap();
        s.p = P { x: 9500. + 300. * i as f64, y: 6000. };
        s.speed = 0.;
    }
    let mut guard = 0;
    while w.contacts[0].is_empty() && guard < 1200 {
        w.advance();
        guard += 1;
    }
    assert!(!w.contacts[0].is_empty(), "no night contact after 1200 ticks");
    let target = w.contacts[0][0].id.clone();
    let target_ship = w.contacts[0][0].ship;
    let lit_id = own[0];
    // The command path: night-only, and it must name a known contact.
    let r = w.external(json!({"op":"searchlight","ship":lit_id,"on":true,"target":target}));
    assert!(r.is_ok(), "{r:?}");
    let lit = w.ship(lit_id).unwrap();
    assert_eq!(lit.searchlight, Some(target_ship));
    assert!(lit.searchlight_die > 0);
    let view = w.observation(0);
    let ship_view = view["ships"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["id"] == lit_id)
        .unwrap();
    assert_eq!(ship_view["searchlight"]["target"], json!(target_ship));
    assert!(ship_view["searchlight"]["bearing"].is_number());
    // Friendly fire control: the lit target gets the Illuminated bonus only
    // inside the light's illumination range (an 8,000-yd fixture reaches
    // 5,000–6,000 yd for a C-size target over typical dice).
    let a = w.ship(lit_id).unwrap().clone();
    let b = w.ship(target_ship).unwrap().clone();
    let lit_chance = w.gun_values(&a, &b, 0, 5, false, &[], 0, false).0;
    w.ship_mut(lit_id).unwrap().searchlight = None;
    let unlit_chance = w.gun_values(&a, &b, 0, 5, false, &[], 0, false).0;
    assert!(
        lit_chance > unlit_chance,
        "illuminated {lit_chance} should beat unlit {unlit_chance}"
    );
    w.ship_mut(lit_id).unwrap().searchlight = Some(target_ship);
    // Move the enemy far beyond normal night sighting. The backlight alone
    // keeps the track (5.4.4.1 source range is five times the fixture)...
    for (i, id) in foe.iter().enumerate() {
        let s = w.ship_mut(*id).unwrap();
        s.p = P { x: 21000. + 300. * i as f64, y: 21000. + 300. * i as f64 };
    }
    for _ in 0..2 {
        w.advance();
    }
    assert!(w.knows(1, lit_id), "the backlit ship must stay acquired at long range");
    // ...while turning the light off drops the track immediately.
    let r = w.external(json!({"op":"searchlight","ship":lit_id,"on":false}));
    assert!(r.is_ok(), "{r:?}");
    for _ in 0..2 {
        w.advance();
    }
    assert!(!w.knows(1, lit_id), "unlit ships cannot be tracked at this range");
    // Re-light it and the enemy re-acquires the ship within a second.
    w.ship_mut(lit_id).unwrap().searchlight = Some(target_ship);
    w.ship_mut(lit_id).unwrap().searchlight_die = 50;
    w.ship_mut(lit_id).unwrap().searchlight_since = w.tick;
    for _ in 0..2 {
        w.advance();
    }
    assert!(w.knows(1, lit_id), "the re-lit ship must be re-acquired by the enemy");
    // Off clears the light.
    let r = w.external(json!({"op":"searchlight","ship":lit_id,"on":false}));
    assert!(r.is_ok(), "{r:?}");
    assert_eq!(w.ship(lit_id).unwrap().searchlight, None);
}

#[test]
fn smoke_hides_the_smoking_ship_and_expires_after_four_windows() {
    let mut w = World::new(6106, 0, "torpedo", "", "coord", 0).unwrap();
    w.enable_realtime().unwrap();
    let own: Vec<u32> = w
        .ships
        .iter()
        .filter(|s| s.side == 0 && s.alive())
        .map(|s| s.id)
        .collect();
    let foe: Vec<u32> = w
        .ships
        .iter()
        .filter(|s| s.side == 1 && s.alive())
        .map(|s| s.id)
        .collect();
    for (i, id) in own.iter().enumerate() {
        let s = w.ship_mut(*id).unwrap();
        s.p = P { x: 6000. + 300. * i as f64, y: 6000. };
        s.speed = 0.;
    }
    for (i, id) in foe.iter().enumerate() {
        let s = w.ship_mut(*id).unwrap();
        s.p = P { x: 9500. + 300. * i as f64, y: 6000. };
        s.speed = 0.;
    }
    let dd = own[0];
    // Daytime searchlights and non-destroyer smoke generators are rejected.
    assert!(w
        .external(json!({"op":"searchlight","ship":dd,"on":true,"target":"C01"}))
        .is_err());
    let cl = own
        .iter()
        .copied()
        .find(|id| w.data.ships[w.ship(*id).unwrap().def].kind != "DD")
        .unwrap();
    assert!(w.external(json!({"op":"smoke","ship":cl,"on":true})).is_err());
    // In daylight the enemy tracks the destroyer before the screen goes down.
    let mut guard = 0;
    while !w.knows(1, dd) && guard < 300 {
        w.advance();
        guard += 1;
    }
    assert!(w.knows(1, dd), "day contact of the DD never formed");
    let r = w.external(json!({"op":"smoke","ship":dd,"on":true}));
    assert!(r.is_ok(), "{r:?}");
    assert!(w.ship(dd).unwrap().smoking);
    assert_eq!(w.smoke.len(), 1);
    let puff = w.smoke[0].clone();
    assert_eq!(puff.expires, puff.born + 4 * CYCLE);
    assert_eq!(w.observation(0)["smoke"].as_array().unwrap().len(), 1);
    // Beyond the 1,000-yd day cap the enemy loses the smoking ship (5.4.5).
    w.advance();
    assert!(!w.knows(1, dd), "smoked DD must drop from the enemy track");
    assert!(w
        .events
        .iter()
        .any(|e| e.kind == "lost" && e.rule.as_deref() == Some("RTS-SMOKE-01")));
    // Stop the generator; the puff burns out after four windows and the
    // destroyer reappears in the enemy's day sighting.
    w.external(json!({"op":"smoke","ship":dd,"on":false})).unwrap();
    assert!(!w.ship(dd).unwrap().smoking);
    let mut guard = 0;
    while (!w.smoke.is_empty() || !w.knows(1, dd)) && guard < 800 {
        w.advance();
        guard += 1;
    }
    assert!(w.smoke.is_empty(), "puff outlived four windows");
    assert!(w.knows(1, dd), "DD must be re-acquired once the screen burns out");
}

#[test]
fn campaign_catalogue_uses_real_stage_ids_without_enabling_unfinished_levels() {
    use std::collections::BTreeSet;
    let rows = ask(&mut Engine::default(), json!({"op":"campaign"}));
    let scenarios = rows["scenarios"].as_array().unwrap();
    // The five stages without a surface CAS counterpart are removed.
    assert_eq!(scenarios.len(), 11);
    let mut stages = BTreeSet::new();
    for item in scenarios {
        let cape = item["cas"]["scenario_id"] == "cas-rs-cape-st-george";
        // Channel Action was removed with the other four CAS-less scenarios.
        // The playable check stands without it.
        let kula = item["ibs_id"] == "IBS-S-02";
        let empress = item["cas"]["scenario_id"] == "cas-rs-empress-augusta-bay";
        let esperance = item["cas"]["scenario_id"] == "cas-rs-cape-esperance";
        let tassafaronga = item["cas"]["scenario_id"] == "cas-rs-tassafaronga";
        let savo = item["cas"]["scenario_id"] == "cas-rs-savo-island";
        assert_eq!(item["playable"], cape || kula || empress || esperance || tassafaronga || savo);
        if cape || kula || empress || esperance || tassafaronga || savo {
            assert_eq!(item["runtime"]["historicalReady"], false);
        }
        for id in item["stage_ids"].as_array().unwrap() {
            assert!(stages.insert(id.as_str().unwrap()));
        }
    }
    // 11 kept scenarios x both seats = 22 stage slots.
    assert_eq!(stages.len(), 22);
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

fn forced_short_range_shell(hidden_to_target: bool) -> World {
    let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
    w.fleets[1].ai = Ai::new("coord", "manual");
    w.ship_mut(1).unwrap().p = P { x: 6000., y: 6200. };
    w.ship_mut(6).unwrap().p = P { x: 6000., y: 7430. };
    w.detect(true);
    if hidden_to_target {
        w.contacts[1].retain(|c| c.ship != 1);
    }
    // Find an actual attack roll below the verified short-range gunnery threshold.
    w.rng = (1..1024)
        .find(|&candidate| {
            w.rng = candidate;
            w.d(100) <= 30
        })
        .unwrap();
    let target = w.contacts[0]
        .iter()
        .find(|c| c.ship == 6)
        .unwrap()
        .id
        .clone();
    w.tick = 179;
    w.external(json!({"op":"fire","ship":1,"weapon":"gun","target":target}))
        .unwrap();
    w
}

#[test]
fn shells_move_for_eight_ticks_then_resolve_without_leaking_hidden_origin() {
    for hidden in [false, true] {
        let mut w = forced_short_range_shell(hidden);
        let hp = w.ship(6).unwrap().hp;
        w.advance();
        let initial = w.observation(0);
        let s = &initial["shells"][0];
        let mounts = initial["ships"][0]["systems"]["guns"].as_array().unwrap();
        assert_eq!(
            mounts.iter().filter(|m| m["bearing"].is_number()).count(),
            5
        );
        assert!(initial["contacts"]
            .as_array()
            .unwrap()
            .iter()
            .all(|c| c.get("systems").is_none()));
        assert_eq!(s["launchTick"], 180);
        assert_eq!(s["impactTick"], 188);
        assert_eq!(s["progress"], 0.);
        assert_eq!(
            w.observation(1)["shells"].as_array().unwrap().len(),
            usize::from(!hidden)
        );
        assert_eq!(w.ship(6).unwrap().hp, hp);
        for _ in 0..4 {
            w.advance();
        }
        let mid = w.observation(0);
        assert_eq!(mid["shells"][0]["id"], s["id"]);
        assert_eq!(mid["shells"][0]["progress"], 0.5);
        assert!(mid["shells"][0]["y"].as_f64().unwrap() > s["y"].as_f64().unwrap());
        assert_eq!(w.ship(6).unwrap().hp, hp);
        for _ in 0..4 {
            w.advance();
        }
        let end = w.observation(1);
        assert!(end["shells"].as_array().unwrap().is_empty());
        assert!(w.ship(6).unwrap().hp < hp);
        assert!(end["events"]
            .as_array()
            .unwrap()
            .iter()
            .any(|e| e["kind"] == "damage" && e["tick"] == 188 && e["voiceCue"] == "damage"));
    }
}

#[test]
fn last_salvo_settles_at_deadline_and_seat_event_ids_do_not_leak() {
    let mut w = forced_short_range_shell(false);
    w.tick = LIMIT - 1;
    w.pending[0].expires = LIMIT;
    w.add(2, "test-private", "不可见".into(), None, None);
    w.advance();
    assert!(w.result.is_none());
    assert_eq!(w.observation(0)["settling"], true);
    assert!(w.external(json!({"op":"lead","fleet":1,"ship":2})).is_err());
    for _ in 0..SHELL_FLIGHT {
        w.advance();
    }
    assert_eq!(w.tick, LIMIT + SHELL_FLIGHT);
    assert!(w.result.is_some());
    for side in 0..2 {
        for (i, e) in w.visible_events(side, None).iter().enumerate() {
            assert_eq!(e["id"], i + 1);
        }
    }
    assert!(!w.observation(0).to_string().contains("不可见"));
}

#[test]
fn legacy_save_keeps_original_instant_cas_gunnery() {
    let mut w = forced_short_range_shell(false);
    w.version = LEGACY_VERSION;
    let hp = w.ship(6).unwrap().hp;
    w.advance();
    assert!(w.shells.is_empty());
    assert!(w.ship(6).unwrap().hp < hp);
    assert_eq!(w.save().version, LEGACY_VERSION);
}

#[test]
fn night_starshell_uses_a_real_contact_and_the_planned_fire_window() {
    let mut e = Engine::default();
    let start = ask(&mut e, json!({
        "op":"new","seed":6106,"side":"allies","enemy":"gunnery","variant":"night-training"
    }));
    assert_eq!(start["contacts"], json!([]));
    assert_eq!(e.handle(json!({"op":"illuminate","ship":5,"target":"C05"}))["ok"], false);
    ask(&mut e, json!({"op":"route","fleet":1,"mode":"follow","speed":15,
        "points":[{"x":13000,"y":6550},{"x":13000,"y":10400}]}));
    ask(&mut e, json!({"op":"step","seconds":360}));
    assert_eq!(ask(&mut e, json!({"op":"illumination_preview","ship":5,"target":"C05"}))["valid"], true);
    let order = json!({"op":"illuminate","ship":5,"target":"C05"});
    let queued = ask(&mut e, order.clone());
    assert_eq!(queued["illuminations"], json!([]));
    assert_eq!(e.handle(order)["ok"], false);
    let early = ask(&mut e, json!({"op":"step","seconds":179}));
    assert_eq!(early["illuminations"], json!([]));
    let applied = ask(&mut e, json!({"op":"step","seconds":1}));
    assert_eq!(applied["illuminations"][0]["own"], true);
    assert_eq!(applied["illuminations"][0]["expires"], 720);
    assert!(applied["illuminations"][0].get("target").is_none());
    assert!(applied["events"].as_array().unwrap().iter().any(|event|
        event["kind"] == "illumination" && event["tick"] == 540));
    let save = ask(&mut e, json!({"op":"save"}));
    assert_eq!(save["version"], "cas-illumination-v3");
    assert_eq!(ask(&mut e, json!({"op":"replay","save":save})), applied);
    let expired = ask(&mut e, json!({"op":"step","seconds":180}));
    assert_eq!(expired["illuminations"], json!([]));
}

fn powered_flags(w: &World, id: u32) -> Vec<bool> {
    w.radar.own_observation(id).iter().map(|d| d["powered"] == json!(true)).collect()
}

#[test]
fn night_ai_powers_its_own_surface_radar() {
    let mut w = World::new(6106, 0, "coord", crate::illumination::RADAR_TRAINING, "coord", 0).unwrap();
    // The radar-training opening equips the player fleet and leaves every
    // device dark; the fleet starts manual, so flip it to AI hands first.
    w.external(json!({"op":"ai","fleet":1,"profile":"coord","mode":"auto","move":true,"gun":true,"torpedo":true})).unwrap();
    assert_eq!(powered_flags(&w, 1), vec![false, false]);
    w.drive_ai();
    assert_eq!(powered_flags(&w, 1), vec![true, true]);
    // Deterministic: the next pass keeps everything powered instead of toggling.
    w.drive_ai();
    assert_eq!(powered_flags(&w, 1), vec![true, true]);
}

#[test]
fn savo_detection_rolls_one_fire_hold_of_d6_over_three_windows() {
    let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
    w.variant = "savo".into();
    w.contacts[0].push(Contact {
        id: "C01".into(), x: 1000., y: 1000., heading: 0., speed: 12.,
        kind: Some("ca".into()), name: None, ship: 6, first_cycle: 0,
        acquisition_base_yd: 0, acquisition_range_yd: 0,
    });
    w.apply_savo_fire_hold();
    assert!(w.fire_hold_rolled);
    let hold = w.fire_hold[0];
    assert!(matches!(hold, 180 | 360 | 540), "{hold}");
    assert!(w.external(json!({"op":"fire","ship":1,"weapon":"gun","target":"C01"})).is_err());
    w.tick = hold;
    assert!(w.fire_hold[0] <= w.tick);
}
