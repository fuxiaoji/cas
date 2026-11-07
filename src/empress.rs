//! Empress Augusta Bay (2 November 1943) — the surface-closure fixture.
//!
//! Three columns per side, 22 named hulls, night with 10% visibility and
//! showers, Haguro capped at 30 knots after the 0130 bombing. The scenario
//! exercises the v10 surface rules: radar, starshells, searchlights, smoke,
//! secondary batteries, torpedo reloads, bridge/rudder/weapon criticals and
//! the Cape Torokina bearing.
use crate::{
    campaign::{Grade, Outcome},
    campaign::live::Start,
    model::{Ai, Field, Fleet, P, Tactic, YARD},
    world::World,
    E,
};
use serde_json::json;

pub(crate) const VARIANT: &str = "empress";
pub(crate) const LABEL: &str = "奥古斯塔皇后湾 · 22 舰夜战";
pub(crate) const CONTENT: &str = "cas-empress-runtime-v1";
pub(crate) const LIMIT: u32 = 4200;
const CAPE: P = P { x: 9_000., y: 2_000. };

struct Column {
    fleet: u32,
    side: usize,
    name: &'static str,
    ships: &'static [(&'static str, &'static str)],
    x: f64,
    y: f64,
    heading: f64,
    speed: f64,
    spacing: f64,
}

fn columns() -> Vec<Column> {
    vec![
        Column { fleet: 1, side: 0, name: "第45驱逐分队", ships: &[
            ("fletcher", "奥兹本"), ("fletcher", "戴森"), ("fletcher", "斯坦利"), ("fletcher", "克拉克斯顿")],
            x: 9_000., y: 4_500., heading: 345., speed: 20., spacing: 350. },
        Column { fleet: 2, side: 0, name: "第12巡洋分队", ships: &[
            ("cleveland_empress", "蒙彼利埃"), ("cleveland_empress", "克利夫兰"),
            ("cleveland_empress", "哥伦比亚"), ("cleveland_empress", "丹佛")],
            x: 8_000., y: 3_500., heading: 345., speed: 20., spacing: 400. },
        Column { fleet: 3, side: 0, name: "第46驱逐分队", ships: &[
            ("fletcher", "斯彭斯"), ("fletcher", "撒切尔"), ("fletcher", "康弗斯"), ("fletcher", "富特")],
            x: 7_000., y: 4_000., heading: 345., speed: 20., spacing: 350. },
        Column { fleet: 4, side: 1, name: "第五战队", ships: &[
            ("myoko", "妙高"), ("myoko", "羽黑")],
            x: 15_000., y: 9_500., heading: 140., speed: 30., spacing: 500. },
        Column { fleet: 5, side: 1, name: "第三水雷战队", ships: &[
            ("sendai", "川内"), ("shiratsuyu", "时雨"), ("shiratsuyu", "五月雨"), ("shiratsuyu", "白露")],
            x: 18_000., y: 8_000., heading: 140., speed: 30., spacing: 350. },
        Column { fleet: 6, side: 1, name: "第十水雷战队", ships: &[
            ("agano", "阿贺野"), ("yugumo", "长波"), ("kagero", "初风"), ("akizuki", "若月")],
            x: 14_000., y: 11_000., heading: 140., speed: 30., spacing: 350. },
    ]
}

fn heading_step(heading: f64, distance: f64) -> (f64, f64) {
    let radians = heading.to_radians();
    (radians.sin() * distance, radians.cos() * distance)
}

pub(crate) fn fill(w: &mut World) -> E<()> {
    let player = w.player;
    for column in columns() {
        let mut members = Vec::new();
        for (index, (class, name)) in column.ships.iter().enumerate() {
            let def = w
                .data
                .ships
                .iter()
                .position(|d| d.id == *class)
                .ok_or_else(|| format!("缺少已核验舰型 {class}"))?;
            let position = P {
                x: column.x + heading_step(column.heading, -column.spacing * index as f64).0,
                y: column.y + heading_step(column.heading, -column.spacing * index as f64).1,
            };
            members.push(w.spawn(def, column.side, column.fleet, name.to_string(), position, column.heading)?);
        }
        w.fleets.push(Fleet {
            id: column.fleet,
            side: column.side,
            name: column.name.into(),
            leader: members[0],
            members,
            mode: "follow".into(),
            speed: column.speed,
            actual: 0.,
            turn_degrees: 0.,
            points: vec![],
            ai: if column.side == player {
                Ai::new(w.profile.as_str(), "manual")
            } else {
                Ai::new(w.enemy.as_str(), "auto")
            },
            notice: None,
            last_ai_route: 0,
            tactic: Tactic::Search,
        });
    }
    // Haguro had been bombed at 0130; her speed is capped at 30 knots.
    if let Some(id) = w.ships.iter().find(|s| s.name == "羽黑").map(|s| s.id) {
        w.ship_mut(id).unwrap().speed_cap = Some(30.);
    }
    w.enable_realtime()?;
    // A course for every column so the battle closes without player input.
    for column in columns() {
        let (dx, dy) = heading_step(column.heading, 6_000.);
        let x = (column.x + dx).clamp(1_000., 23_000.);
        let y = (column.y + dy).clamp(1_000., 13_000.);
        w.route(
            column.side,
            &json!({"op":"route","fleet":column.fleet,"mode":"follow","speed":column.speed,
                    "points":[{"x":x,"y":y}]}),
            column.side == player,
        )?;
    }
    w.add(
        3,
        "start",
        format!("{LABEL} · 1943-11-02 0227，能见度 10%，阵雨"),
        Some("CAS-RS-EMP-01"),
        None,
    );
    Ok(())
}

/// The Cape Torokina bearing: Japanese heavy cruisers count as "between the
/// American cruisers and the cape" when they lie on the cape side of the
/// allied cruiser line and within the scenario's bearing wedge.
pub(crate) fn axis_cruisers_inside(w: &World) -> bool {
    let allies: Vec<&crate::model::Ship> = w
        .ships
        .iter()
        .filter(|s| s.side == 0 && s.alive() && w.data.ships[s.def].kind == "CL")
        .collect();
    let heavies: Vec<&crate::model::Ship> = w
        .ships
        .iter()
        .filter(|s| s.side == 1 && s.alive() && w.data.ships[s.def].kind == "CA")
        .collect();
    if allies.is_empty() || heavies.is_empty() {
        return false;
    }
    let allied_line = allies.iter().map(|s| s.p).fold((0., 0.), |(x, y), p| (x + p.x, y + p.y));
    let allied_line = P { x: allied_line.0 / allies.len() as f64, y: allied_line.1 / allies.len() as f64 };
    heavies.iter().any(|heavy| {
        let to_cape = CAPE - heavy.p;
        let to_line = allied_line - heavy.p;
        to_cape.dot(to_line) > 0. && heavy.p.dist(CAPE) < 12_000. * YARD
    })
}


/// Campaign entry: the same roster as the exercise, with the campaign seat,
/// stage and 4,200-second limit (0227-0337).
pub(crate) fn open(seed: u32, start: Start, player: usize, enemy: &str, profile: &str) -> E<World> {
    let data = World::exercise_data()?;
    let mut w = World::blank(data, seed, player, enemy, VARIANT, profile, 0);
    w.field = Field { width: 24_000., height: 14_000., limit: LIMIT };
    w.campaign = Some(start);
    fill(&mut w)?;
    Ok(w)
}

pub(crate) fn view(start: &Start, owner: usize) -> serde_json::Value {
    let (stage, objectives) = if owner == 0 {
        (
            "CAMP-ALLIES-11",
            "击沉三艘日舰并把日方重巡压在海角外侧，达成决定性胜利；三艘日舰损伤过半且重巡仍在外侧，达成战术胜利。",
        )
    } else {
        (
            "CAMP-AXIS-11",
            "重创三艘美巡并让本方重巡切入美巡与托罗基纳角之间，达成决定性胜利；对美方造成的损伤超过本方所受损伤，达成战术胜利。",
        )
    };
    json!({"stageId":stage, "difficulty":start.difficulty, "missionLabel":LABEL,
        "objectives":objectives, "withdrawalX":null})
}

/// CAS Rising Sun 90: the historical victory conditions on both sides.
pub(crate) fn outcome(w: &World) -> Outcome {
    let dp = |ship: &crate::model::Ship| w.data.ships[ship.def].dp;
    let damage = |ship: &crate::model::Ship| (dp(ship) - ship.hp).max(0.);
    let sunk = |side: usize| w.ships.iter().filter(|s| s.side == side && s.hp <= 0.).count() as u32;
    let half = |side: usize, kind: Option<&str>| {
        w.ships
            .iter()
            .filter(|s| s.side == side && s.hp <= dp(s) * 0.5)
            .filter(|s| kind.is_none_or(|k| w.data.ships[s.def].kind == k))
            .count() as u32
    };
    let inside = axis_cruisers_inside(w);
    let axis_sunk = sunk(1);
    let axis_half = half(1, None);
    let us_cruisers_half = half(0, Some("CL"));
    let allies = if axis_sunk >= 3 && !inside {
        Grade::Decisive
    } else if axis_half >= 3 && !inside {
        Grade::Tactical
    } else {
        Grade::None
    };
    let axis_damage: f64 = w.ships.iter().filter(|s| s.side == 1).map(&damage).sum();
    let allied_damage: f64 = w.ships.iter().filter(|s| s.side == 0).map(&damage).sum();
    let axis = if us_cruisers_half >= 3 && inside {
        Grade::Decisive
    } else if axis_damage > allied_damage {
        Grade::Tactical
    } else {
        Grade::None
    };
    Outcome { allies, axis }
}
