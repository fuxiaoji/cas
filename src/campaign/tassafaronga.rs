//! Tassafaronga (30 November 1942) — Rising Sun PDF 75–76 (printed 74–75).
//!
//! US Task Force 67.2 in a 320/20 knot cruiser column with four van and two
//! trailing destroyers; Tanaka's Reinforcement Unit on 140/12 knots with a
//! seven-ship column and Takanami on the port bow. Six destroyers carry drum
//! strings; only Naganami and Takanami keep torpedo reloads. The three
//! Resupply Points are a chart registration (the printed page marks them but
//! prints no coordinates); the radius, capacity, two-knot limit and one string
//! per tactical window are the printed values.
use crate::{
    campaign::{Grade, Outcome},
    campaign::live::Start,
    model::{Ai, Field, Fleet, P, Tactic, YARD},
    world::World,
    E,
};
use serde_json::json;
use std::sync::OnceLock;

pub(crate) const VARIANT: &str = "tassafaronga";
pub(crate) const LABEL: &str = "塔萨法隆格 · 19 舰夜战";
pub(crate) const CONTENT: &str = "cas-tassafaronga-runtime-v1";
pub(crate) const LIMIT: u32 = 4200;
pub(crate) const FIELD: Field = Field { width: 76_000., height: 75_000., limit: LIMIT };
const NMI_M: f64 = 1852.;
const COLUMN_YD: f64 = 500.;
const CRUISER_YD: f64 = 1_000.;
/// PDF 76 marks three Resupply Points but prints no coordinates. These are
/// the registered RTS chart positions along the Guadalcanal north coast.
pub(crate) const RESUPPLY: [(f64, f64); 3] = [(30_000., 54_000.), (38_000., 55_000.), (46_000., 56_000.)];
pub(crate) const RESUPPLY_RADIUS_M: f64 = 1.5 * NMI_M;

fn snap(p: P) -> P {
    P { x: (p.x * 1000.).round() / 1000., y: (p.y * 1000.).round() / 1000. }
}
fn offset(from: P, bearing: f64, distance_m: f64) -> P {
    snap(from + P::bearing(bearing) * distance_m)
}

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
    let minneapolis = P { x: 52_000., y: 50_000. };
    let naganami = offset(minneapolis, 283., 11.9 * NMI_M);
    let cruiser = |i: usize| offset(minneapolis, 320., -(i as f64) * CRUISER_YD * YARD);
    let van_lead = offset(minneapolis, 290., 4_000. * YARD);
    let trail_lead = offset(offset(minneapolis, 320., -4. * CRUISER_YD * YARD), 185., 2_000. * YARD);
    let takanami = offset(naganami, 110., 4_000. * YARD);
    let transport1 = offset(naganami, 140., -2. * COLUMN_YD * YARD);
    let transport2 = offset(transport1, 140., -3. * COLUMN_YD * YARD);
    vec![
        Column { fleet: 1, side: 0, name: "TG 67.2 巡洋舰纵队", ships: &[
            ("tass_minneapolis", "明尼阿波利斯"), ("tass_new_orleans", "新奥尔良"),
            ("tass_pensacola", "彭萨科拉"), ("tass_honolulu", "火奴鲁鲁"),
            ("tass_northampton", "北安普敦")],
            x: cruiser(0).x, y: cruiser(0).y, heading: 320., speed: 20., spacing: CRUISER_YD * YARD },
        Column { fleet: 2, side: 0, name: "第67.2.4支队 · 前卫", ships: &[
            ("tass_fletcher", "弗莱彻"), ("tass_perkins", "帕金斯"),
            ("tass_maury", "莫里"), ("tass_drayton", "德雷顿")],
            x: van_lead.x, y: van_lead.y, heading: 320., speed: 20., spacing: COLUMN_YD * YARD },
        Column { fleet: 3, side: 0, name: "第67.2.4支队 · 后卫", ships: &[
            ("tass_lamson", "拉姆森"), ("tass_lardner", "拉德纳")],
            x: trail_lead.x, y: trail_lead.y, heading: 320., speed: 20., spacing: COLUMN_YD * YARD },
        Column { fleet: 4, side: 1, name: "第二水雷战队 · 警戒队", ships: &[
            ("tass_naganami", "长波"), ("tass_makinami", "卷波")],
            x: naganami.x, y: naganami.y, heading: 140., speed: 12., spacing: COLUMN_YD * YARD },
        Column { fleet: 5, side: 1, name: "运输一队", ships: &[
            ("tass_oyashio", "亲潮"), ("tass_kuroshio", "黑潮"), ("tass_kagero", "阳炎")],
            x: transport1.x, y: transport1.y, heading: 140., speed: 12., spacing: COLUMN_YD * YARD },
        Column { fleet: 6, side: 1, name: "运输二队", ships: &[
            ("tass_kawakaze", "川风"), ("tass_suzukaze", "凉风")],
            x: transport2.x, y: transport2.y, heading: 140., speed: 12., spacing: COLUMN_YD * YARD },
        // Takanami is detached from the column, 4,000 yards off Naganami's
        // port bow; it is a one-ship fleet so the column itself stays intact.
        Column { fleet: 7, side: 1, name: "高波 · 瞭望哨", ships: &[("tass_takanami", "高波")],
            x: takanami.x, y: takanami.y, heading: 140., speed: 12., spacing: COLUMN_YD * YARD },
    ]
}

fn data() -> E<&'static crate::model::Data> {
    static DATA: OnceLock<Result<crate::model::Data, String>> = OnceLock::new();
    DATA.get_or_init(|| {
        let mut data = crate::prologue::data()?.clone();
        let manifest: serde_json::Value = serde_json::from_str(include_str!(
            "../../data/campaign/period/tassafaronga-runtime.json"
        )).map_err(|e| format!("无法载入塔萨法隆格舰卡：{e}"))?;
        let ships: Vec<crate::model::ShipDef> = serde_json::from_value(manifest["ships"].clone())
            .map_err(|e| format!("塔萨法隆格舰卡格式有误：{e}"))?;
        for ship in ships {
            if !data.ships.iter().any(|existing| existing.id == ship.id) {
                data.ships.push(ship);
            }
        }
        Ok(data)
    })
    .as_ref()
    .map_err(Clone::clone)
}

fn islands() -> Vec<Vec<P>> {
    let chart: serde_json::Value = serde_json::from_str(include_str!(
        "../../data/campaign/period/chart-tassafaronga.json"
    )).expect("tassafaronga chart");
    chart["islands"].as_array().expect("islands").iter().map(|island| {
        island["points"].as_array().expect("points").iter()
            .map(|pt| P { x: pt[0].as_f64().unwrap_or(0.), y: pt[1].as_f64().unwrap_or(0.) })
            .collect()
    }).collect()
}

pub(crate) fn fill(w: &mut World) -> E<()> {
    w.field = FIELD;
    w.islands = islands();
    w.resupply = RESUPPLY.iter().map(|&(x, y)| crate::model::ResupplyPoint {
        x, y, radius: RESUPPLY_RADIUS_M, capacity: 3,
    }).collect();
    let player = w.player;
    for column in columns() {
        let mut members = Vec::new();
        for (index, (class, name)) in column.ships.iter().enumerate() {
            let def = w.data.ships.iter().position(|d| d.id == *class)
                .ok_or_else(|| format!("缺少已核验舰型 {class}"))?;
            let position = offset(P { x: column.x, y: column.y }, column.heading,
                -(index as f64) * column.spacing);
            let id = w.spawn(def, column.side, column.fleet, name.to_string(), position, column.heading)?;
            let ship = w.ship_mut(id).unwrap();
            ship.speed = column.speed;
            ship.free_speed = column.speed;
            // Six drum carriers: Oyashio, Kuroshio, Kagero, Kawakaze,
            // Suzukaze, Makinami. Each carries five strings.
            if matches!(name.as_ref(), "亲潮" | "黑潮" | "阳炎" | "川风" | "凉风" | "卷波") {
                w.drum_strings[(id - 1) as usize] = 5;
            }
            members.push(id);
        }
        w.fleets.push(Fleet {
            id: column.fleet, side: column.side, name: column.name.into(), leader: members[0],
            members, mode: "follow".into(), speed: column.speed, actual: column.speed,
            turn_degrees: 0., points: vec![],
            ai: if column.side == player { Ai::new(w.profile.as_str(), "manual") }
                else { Ai::new(w.enemy.as_str(), "auto") },
            notice: None, last_ai_route: 0, tactic: Tactic::Search,
        });
    }
    // US SG/SC-2 surface search; Japanese Type 21 is air-search only.
    for id in w.ships.iter().filter(|s| s.side == 0).map(|s| s.id).collect::<Vec<_>>() {
        w.radar.equip(id, "us_sg")?;
        w.radar.equip(id, "us_sc2")?;
    }
    w.enable_realtime()?;
    // A short opening leg keeps the printed courses moving; a leg that would
    // cross the charted coast is skipped and left to the player/AI.
    for column in columns() {
        let rad = column.heading.to_radians();
        let point = snap(P { x: column.x + rad.sin() * 2_500., y: column.y + rad.cos() * 2_500. });
        let _ = w.route(column.side, &json!({"op":"route","fleet":column.fleet,"mode":"follow",
            "speed":column.speed,"points":[point]}), column.side == player);
    }
    w.add(3, "start", format!("{LABEL} · 1942-11-30 23:08，能见度 10%，海况 0"),
        Some("CAS-RS-TASS-01"), None);
    Ok(())
}

pub(crate) fn open(seed: u32, start: Start, player: usize, enemy: &str, profile: &str) -> E<World> {
    let mut w = World::blank(data()?, seed, player, enemy, VARIANT, profile, 0);
    w.campaign = Some(start);
    fill(&mut w)?;
    Ok(w)
}

pub(crate) fn view(start: &Start, owner: usize) -> serde_json::Value {
    let (stage, objectives) = if owner == 0 {
        ("CAMP-ALLIES-05", "阻止日军卸下补给。日方卸货不超过 120 分且至多一艘美重巡损伤 50% 以上，获决定性胜利；不超过 240 分且至多一艘重巡被击沉，获战术胜利。")
    } else {
        ("CAMP-AXIS-05", "在瓜岛北岸三处补给点卸下补给桶，天亮前脱离。总分 500 以上获决定性胜利，250 以上获战术胜利。")
    };
    json!({"stageId":stage,"difficulty":start.difficulty,"missionLabel":LABEL,
        "objectives":objectives,"withdrawalX":null})
}

fn damage(w: &World, side: usize) -> f64 {
    w.ships.iter().filter(|s| s.side == side)
        .map(|s| (w.data.ships[s.def].dp - s.hp).max(0.)).sum()
}

/// The printed US conditions use delivered supply points and heavy-cruiser
/// damage; Japanese total = delivered supply points + damage inflicted on US.
pub(crate) fn outcome(w: &World) -> Outcome {
    let delivered = w.supply_score;
    let us_damage = damage(w, 0);
    let heavy = |predicate: &dyn Fn(&crate::model::Ship) -> bool| w.ships.iter()
        .filter(|s| s.side == 0 && w.data.ships[s.def].kind == "CA" && predicate(s)).count() as u32;
    let crippled = heavy(&|s| s.hp <= w.data.ships[s.def].dp * 0.5);
    let sunk = heavy(&|s| s.hp <= 0.);
    let allies = if delivered <= 120 && crippled <= 1 { Grade::Decisive }
        else if delivered <= 240 && sunk <= 1 { Grade::Tactical } else { Grade::None };
    let total = delivered as f64 + us_damage;
    let axis = if total >= 500. { Grade::Decisive } else if total >= 250. { Grade::Tactical } else { Grade::None };
    Outcome { allies, axis }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_stopped_drum_carrier_unloads_one_string_per_window() {
        let mut start = Start::new("CAMP-AXIS-05", "story");
        start.content_version = CONTENT.into();
        let mut w = open(6106, start, 1, "coord", "coord").unwrap();
        let point = RESUPPLY[0];
        let id = w.ships.iter().find(|s| s.name == "亲潮").unwrap().id;
        let ship = w.ship_mut(id).unwrap();
        ship.p = P { x: point.0, y: point.1 };
        ship.speed = 0.;
        ship.track = None;
        w.advance();
        for _ in 1..180 { w.advance(); }
        assert_eq!(w.supply_score, 20);
        assert_eq!(w.drum_strings[(id - 1) as usize], 4);
    }

    #[test]
    fn both_seats_open_with_nineteen_printed_hulls_and_six_drum_carriers() {
        for seat in 0..2 {
            let mut start = Start::new(if seat == 0 { "CAMP-ALLIES-05" } else { "CAMP-AXIS-05" }, "story");
            start.content_version = CONTENT.into();
            let w = open(6106, start, seat, "coord", "coord").unwrap();
            assert_eq!(w.ships.len(), 19);
            assert_eq!(w.ships.iter().filter(|s| s.side == 0).count(), 11);
            assert_eq!(w.drum_strings.iter().filter(|&&n| n == 5).count(), 6);
            assert_eq!(w.resupply.len(), 3);
        }
    }
}
