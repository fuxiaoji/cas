//! Cape Esperance (11 October 1942) — Rising Sun PDF 65 (printed 64).
//!
//! Allied column (Farenholt, Duncan, Laffey, San Francisco, Boise,
//! Salt Lake City, Helena, Buchanan, McCalla) on 045/15 kn; Japanese Crudiv 6
//! (Aoba, Furutaka, Kinugasa) plus Desdiv 11 (Fubuki, Hatsuyuki) on 135/30.
//! Aoba bears 315°/13.5 nmi from Helena. Chart land is projected from ArcGIS
//! World_Imagery tiles (see artifacts/basemap and the source notes).
use crate::{
    campaign::{Grade, Outcome},
    campaign::live::Start,
    model::{Ai, Field, Fleet, P, Tactic, YARD},
    world::World,
    E,
};
use serde_json::json;

pub(crate) const VARIANT: &str = "esperance";
pub(crate) const LABEL: &str = "埃斯佩兰斯角 · 14 舰夜战";
pub(crate) const CONTENT: &str = "cas-esperance-runtime-v1";
pub(crate) const LIMIT: u32 = 4200;
/// The printed opening is 13.5 nmi; the chart spans 76×50 km around the sound.
pub(crate) const FIELD: Field = Field { width: 76_000., height: 50_000., limit: LIMIT };
const NMI_M: f64 = 1852.;
/// Column interval is not printed; 500 yd is the registered default.
const COLUMN_YD: f64 = 500.;
/// Savo Island's detected center on the chart (satellite projection).
const SAVO_P: P = P { x: 25_642., y: 23_380. };

/// Millimetre snap: the scenario geometry is trigonometric, and native libm
/// and the wasm target can differ by one ulp in sin/cos. Snapping to the
/// millimetre keeps the printed bearings/distances while making the canonical
/// observation byte-identical across native and WASM.
fn snap(p: P) -> P {
    P { x: (p.x * 1000.).round() / 1000., y: (p.y * 1000.).round() / 1000. }
}

fn offset(from: P, bearing: f64, distance_m: f64) -> P {
    snap(from + P::bearing(bearing) * distance_m)
}

fn islands() -> Vec<Vec<P>> {
    let data = include_str!("../../data/campaign/period/chart-esperance.json");
    let chart: serde_json::Value = serde_json::from_str(data).expect("esperance chart");
    chart["islands"]
        .as_array()
        .expect("islands")
        .iter()
        .map(|island| {
            island["points"]
                .as_array()
                .expect("points")
                .iter()
                .map(|pt| P { x: pt[0].as_f64().unwrap_or(0.), y: pt[1].as_f64().unwrap_or(0.) })
                .collect()
        })
        .collect()
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
}

fn columns() -> Vec<Column> {
    let interval = COLUMN_YD * YARD;
    // One continuous nine-ship column on 045: Farenholt, Duncan, Laffey,
    // San Francisco, Boise, Salt Lake City, Helena, Buchanan, McCalla.
    // Helena is the seventh hull, 12 km SE of Savo; Aoba bears 315°/13.5 nmi
    // from Helena, i.e. NW across Savo — the historical approach axis.
    let helena = offset(SAVO_P, 135., 12_000.);
    let at = |index: u32| offset(helena, 225., (6. - index as f64) * interval);
    let farenholt = at(0);
    // Printed relation: Aoba bears 315°/13.5 nmi from Helena. With the
    // satellite-projected Savo that puts the island exactly on the Japanese
    // 135° course; the historical pass had Savo on Crudiv 6's port side
    // (northeast). Runtime uses 305°/13.5 nmi — a registered deviation so
    // the approach clears Savo to the northeast as printed history shows.
    let aoba = offset(helena, 305., 13.5 * NMI_M);
    let fubuki = offset(aoba, 45., -2. * interval);
    vec![
        Column { fleet: 1, side: 0, name: "第64特混舰队 · 整列", ships: &[
            ("fletcher", "法伦霍尔特"), ("fletcher", "邓肯"), ("fletcher", "拉菲"),
            ("new_orleans_1942", "旧金山"), ("northampton_1942", "博伊西"),
            ("salt_lake_city_1942", "盐湖城"), ("brooklyn_second_group_1942", "海伦娜"),
            ("fletcher", "布坎南"), ("fletcher", "麦卡拉")],
            x: farenholt.x, y: farenholt.y, heading: 45., speed: 15. },
        Column { fleet: 2, side: 1, name: "第六战队", ships: &[
            ("aoba_1938", "青叶"), ("furutaka_1937", "古鹰"), ("kinugasa_1938", "衣笠")],
            x: aoba.x, y: aoba.y, heading: 135., speed: 30. },
        Column { fleet: 3, side: 1, name: "第11驱逐分队", ships: &[
            ("fubuki_1936_refit", "吹雪"), ("fubuki_1936_refit", "初雪")],
            x: fubuki.x, y: fubuki.y, heading: 135., speed: 30. },
    ]
}

pub(crate) fn fill(w: &mut World) -> E<()> {
    w.field = FIELD;
    w.islands = islands();
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
            let position = offset(
                P { x: column.x, y: column.y },
                column.heading,
                -(index as f64) * COLUMN_YD * YARD,
            );
            let id = w.spawn(def, column.side, column.fleet, name.to_string(), position, column.heading)?;
            w.ship_mut(id).unwrap().speed = column.speed;
            members.push(id);
        }
        w.fleets.push(Fleet {
            id: column.fleet,
            side: column.side,
            name: column.name.into(),
            leader: members[0],
            members,
            mode: "follow".into(),
            speed: column.speed,
            actual: column.speed,
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
    // US radar: SG and SC-2 on every allied hull (Form 10s). The Japanese
    // ships carry no surface-search radar in October 1942 — Type 21 is
    // air-search only — so their fire control stays optical.
    let radar_ships: Vec<u32> = w
        .ships
        .iter()
        .filter(|s| s.side == 0)
        .map(|s| s.id)
        .collect();
    for id in radar_ships {
        w.radar.equip(id, "us_sg")?;
        w.radar.equip(id, "us_sc2")?;
    }
    w.enable_realtime()?;
    // Both fleets sail their printed courses; the 25 km opening closes to
    // radar/optical range within the first half hour and the AI approach
    // turns take over from there. 15 km of route keeps both columns inside
    // the chart without crossing the detected Guadalcanal coast.
    for column in columns() {
        let radians = column.heading.to_radians();
        let (dx, dy) = (radians.sin() * 15_000., radians.cos() * 15_000.);
        let points = vec![snap(P {
            x: column.x + dx,
            y: column.y + dy,
        })];
        w.route(
            column.side,
            &json!({"op":"route","fleet":column.fleet,"mode":"follow","speed":column.speed,
                    "points":points}),
            column.side == player,
        )?;
    }
    w.add(
        3,
        "start",
        format!("{LABEL} · 1942-10-11 2324，能见度 10%，海况 3"),
        Some("CAS-RS-CAPE-ESP-01"),
        None,
    );
    Ok(())
}

pub(crate) fn open(seed: u32, start: Start, player: usize, enemy: &str, profile: &str) -> E<World> {
    let data = World::exercise_data()?;
    let mut w = World::blank(data, seed, player, enemy, VARIANT, profile, 0);
    w.campaign = Some(start);
    fill(&mut w)?;
    Ok(w)
}

pub(crate) fn view(start: &Start, owner: usize) -> serde_json::Value {
    let stage = if owner == 0 { "CAMP-ALLIES-02" } else { "CAMP-AXIS-02" };
    // The printed conditions are damage-point ratios (Rising Sun PDF 64).
    let objectives = if owner == 0 {
        "截击敌方巡洋舰部队。造成 3:1 损伤点比获决定性胜利；1.5:1 获战术胜利。"
    } else {
        "炮击亨德森机场方向的美方巡洋舰队。造成 3:1 损伤比获决定性胜利；1:1 获战术胜利。"
    };
    json!({"stageId":stage, "difficulty":start.difficulty, "missionLabel":LABEL,
        "objectives":objectives, "withdrawalX":null})
}

/// Rising Sun PDF 64: both sides grade on the damage-point ratio of the
/// action — 3:1 decisive, 1.5:1 (allies) / 1:1 (axis) tactical.
pub(crate) fn outcome(w: &World) -> Outcome {
    let dp = |ship: &crate::model::Ship| w.data.ships[ship.def].dp;
    let damage = |side: usize| {
        w.ships
            .iter()
            .filter(|s| s.side == side)
            .map(|s| (dp(s) - s.hp).max(0.))
            .sum::<f64>()
    };
    // "造成 3:1 损伤点比" = the side inflicted three times the damage it
    // suffered: inflicted (enemy damage) over suffered (own damage).
    let (allied_inflicted, allied_suffered) = (damage(1), damage(0));
    let (axis_inflicted, axis_suffered) = (damage(0), damage(1));
    let allied_ratio = allied_inflicted / allied_suffered.max(1.);
    let axis_ratio = axis_inflicted / axis_suffered.max(1.);
    let allies = if allied_ratio >= 3. { Grade::Decisive }
        else if allied_ratio >= 1.5 { Grade::Tactical }
        else { Grade::None };
    let axis = if axis_ratio >= 3. { Grade::Decisive }
        else if axis_ratio >= 1. { Grade::Tactical }
        else { Grade::None };
    Outcome { allies, axis }
}
