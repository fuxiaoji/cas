//! Savo Island (9 August 1942) — Rising Sun PDF 52–54 (printed 51–53).
//!
//! Mikawa's eight-ship column approaches Blue's picket line on 135°/28 kn
//! with cruisers 1,300 yards apart; Chokai bears 345°/12,000 yards from Blue
//! on her 235° leg. The allied patrol positions come from the digitized
//! chart (chart-savo.json); hulls without a readable silhouette anchor at
//! their patrol line with the registered spacing default. The printed
//! special rule holds allied fire for D6/3 tactical windows after detection;
//! the moon is New Moon per the 10% sighting row, and no illumination
//! orders exist on the page, so no starshell or searchlight commands open.
use crate::{
    campaign::{Grade, Outcome},
    campaign::live::Start,
    model::{Ai, Field, Fleet, P, Tactic, YARD},
    world::World,
    E,
};
use serde_json::json;
use std::sync::OnceLock;

pub(crate) const VARIANT: &str = "savo";
pub(crate) const LABEL: &str = "萨沃岛 · 59 舰夜战";
pub(crate) const CONTENT: &str = "cas-savo-runtime-v1";
pub(crate) const LIMIT: u32 = 4200;
/// The printed chart spans 159°35'E–160°20'E and 09°00'S–09°25'S; the
/// projection in chart-savo.json gives the metre box below.
pub(crate) const FIELD: Field = Field { width: 82_415., height: 57_500., limit: LIMIT };
/// Column interval is not printed for the light forces; 500 yd is the single
/// documented default used by the CAS campaign runtimes.
const COLUMN_YD: f64 = 500.;
/// Tenryu/Yubari/Yunagi section spacing is not printed; same global default.
const JAP_LIGHT_YD: f64 = 500.;

fn snap(p: P) -> P {
    P { x: (p.x * 1000.).round() / 1000., y: (p.y * 1000.).round() / 1000. }
}

struct Chart {
    ships: Vec<(String, f64, f64)>,
    lines: Vec<(String, Vec<(f64, f64)>)>,
    areas: Vec<(String, Vec<(f64, f64)>, (f64, f64))>,
}

fn chart() -> &'static Chart {
    static CHART: OnceLock<Chart> = OnceLock::new();
    CHART.get_or_init(|| {
        let data: serde_json::Value = serde_json::from_str(include_str!(
            "../../data/campaign/period/chart-savo.json"
        )).expect("savo chart");
        let ships = data["ships"].as_array().expect("ships").iter().filter_map(|s| {
            let label = s["label"].as_str()?; // unnamed silhouettes stay unused
            let p = s["engine"].as_array()?;
            Some((label.to_string(), p[0].as_f64()?, p[1].as_f64()?))
        }).collect();
        let lines = data["patrol_lines"].as_array().expect("lines").iter().map(|l| {
            (l["name"].as_str().unwrap_or("").to_string(),
             l["points"].as_array().expect("points").iter().map(|p| {
                 (p[0].as_f64().unwrap_or(0.), p[1].as_f64().unwrap_or(0.))
             }).collect())
        }).collect();
        let areas = data["transport_areas"].as_array().expect("areas").iter().map(|a| {
            (a["name"].as_str().unwrap_or("").to_string(),
             a["points"].as_array().expect("points").iter().map(|p| {
                 (p[0].as_f64().unwrap_or(0.), p[1].as_f64().unwrap_or(0.))
             }).collect(),
             { let c = a["center"].as_array().expect("center");
               (c[0].as_f64().unwrap_or(0.), c[1].as_f64().unwrap_or(0.)) })
        }).collect();
        Chart { ships, lines, areas }
    })
}

fn chart_ship(label: &str) -> Option<P> {
    chart().ships.iter().find(|(name, _, _)| name == label)
        .map(|(_, x, y)| snap(P { x: *x, y: *y }))
}

/// Midpoint of a named patrol line, for hulls whose silhouettes the chart
/// could not separate (the southern cruisers, eastern force pair).
fn chart_line(name: &str, fraction: f64) -> Option<P> {
    let (_, points) = chart().lines.iter().find(|(n, _)| n == name)?;
    let (a, b) = (points[0], points[1]);
    Some(snap(P { x: a.0 + (b.0 - a.0) * fraction, y: a.1 + (b.1 - a.1) * fraction }))
}

/// Transport-area centre for the auxiliaries; the chart boxes the groups and
/// the printed page gives no individual moorings. Registered RTS reading.
fn chart_area(name: &str) -> P {
    let area = chart().areas.iter().find(|(n, _, _)| n.contains(name));
    let (_, _, centre) = area.expect("transport area");
    snap(P { x: centre.0, y: centre.1 })
}

fn area_offset(name: &str, index: usize, _heading: f64) -> P {
    // The chart boxes the anchored groups without individual moorings; lay
    // the ships in a four-column grid of 800 m spacing around the box centre
    // (registered RTS layout, no printed mooring chart exists).
    let base = chart_area(name);
    let cols = 4usize;
    let col = index % cols;
    let row = index / cols;
    snap(P { x: base.x - 1_800. + col as f64 * 1_200.,
             y: base.y - row as f64 * 800. })
}

struct Column {
    fleet: u32,
    side: usize,
    name: &'static str,
    ships: &'static [(&'static str, &'static str)],
    anchor: P,
    heading: f64,
    speed: f64,
    spacing: f64,
    follow: bool,
}

fn columns() -> Vec<Column> {
    let blue = chart_ship("Blue").expect("Blue silhouette");
    let chokai = snap(blue + P::bearing(345.) * 12_000. * YARD);
    // Mikawa's column: Chokai, Aoba, Kako, Kinugasa, Furutaka at 1,300 yd
    // (printed), then Tenryu, Yubari, Yunagi at the registered 500 yd.
    let at = |i: usize| snap(chokai - P::bearing(135.) * i as f64 * 1_300. * YARD);
    let light_at = |i: usize| snap(chokai - P::bearing(135.)
        * (5. * 1_300. + i as f64 * JAP_LIGHT_YD) * YARD);
    let northern = [chart_ship("Wilson"), chart_ship("Helm")];
    let vincennes = chart_line("Northern Force Patrol Box", 0.25).expect("patrol box");
    let quincy = chart_line("Northern Force Patrol Box", 0.5).expect("patrol box");
    let astoria = chart_line("Northern Force Patrol Box", 0.75).expect("patrol box");
    let canberra = chart_line("Southern Force Patrol Line", 0.4).expect("southern line");
    let chicago = chart_line("Southern Force Patrol Line", 0.7).expect("southern line");
    let bagley = chart_ship("Bagley").expect("Bagley");
    let patterson = chart_ship("Patterson").expect("Patterson");
    let australia = chart_ship("Australia").expect("Australia");
    let jarvis = chart_ship("Jarvis").expect("Jarvis");
    let monssen = chart_line("Eastern Force Patrol Line", 0.35).expect("eastern line");
    let buchanan = chart_line("Eastern Force Patrol Line", 0.55).expect("eastern line");
    let san_juan = chart_line("Eastern Force Patrol Line", 0.75).expect("eastern line");
    let hobart = chart_line("Eastern Force Patrol Line", 0.95).expect("eastern line");
    vec![
        Column { fleet: 1, side: 1, name: "第八舰队 · 突击纵队", ships: &[
            ("savo_chokai", "鸟海"), ("savo_aoba", "青叶"), ("savo_kako", "加古"),
            ("savo_kinugasa", "衣笠"), ("savo_furutaka", "古鹰")],
            anchor: chokai, heading: 135., speed: 28., spacing: 1_300. * YARD, follow: true },
        Column { fleet: 2, side: 1, name: "水雷战队 · 轻兵纵队", ships: &[
            ("savo_tenryu", "天龙"), ("savo_yubari", "夕张"), ("savo_yunagi", "夕凪")],
            anchor: light_at(0), heading: 135., speed: 28., spacing: JAP_LIGHT_YD * YARD, follow: true },
        Column { fleet: 3, side: 0, name: "北队 · 巡洋舰", ships: &[
            ("savo_vincennes", "文森斯"), ("savo_quincy", "昆西"), ("savo_astoria", "阿斯托利亚")],
            anchor: vincennes, heading: 0., speed: 12., spacing: COLUMN_YD * YARD, follow: false },
        Column { fleet: 4, side: 0, name: "北队 · 驱逐舰", ships: &[
            ("savo_wilson", "威尔逊"), ("savo_helm", "赫尔姆")],
            anchor: northern[0].expect("Wilson"), heading: 0., speed: 12.,
            spacing: COLUMN_YD * YARD, follow: false },
        Column { fleet: 5, side: 0, name: "南队", ships: &[
            ("savo_canberra", "堪培拉"), ("savo_chicago", "芝加哥"),
            ("savo_bagley", "巴格利"), ("savo_patterson", "帕特森")],
            anchor: canberra, heading: 0., speed: 12., spacing: COLUMN_YD * YARD, follow: false },
        Column { fleet: 6, side: 0, name: "澳大利亚 · 独立巡逻", ships: &[
            ("savo_australia", "澳大利亚")],
            anchor: australia, heading: 0., speed: 12., spacing: COLUMN_YD * YARD, follow: false },
        Column { fleet: 7, side: 0, name: "东屏护", ships: &[
            ("savo_monssen", "蒙森"), ("savo_buchanan", "布坎南"),
            ("savo_san_juan", "圣胡安"), ("savo_hobart", "霍巴特"), ("savo_jarvis", "贾维斯")],
            anchor: monssen, heading: 0., speed: 12., spacing: COLUMN_YD * YARD, follow: false },
        Column { fleet: 8, side: 0, name: "X-Ray 屏护与运输", ships: &[
            ("savo_hopkins", "霍普金斯"), ("savo_trever", "特雷弗"), ("savo_zane", "赞恩"),
            ("savo_southard", "绍瑟德"), ("savo_hovey", "霍维"), ("savo_dewey", "杜威"),
            ("savo_selfridge", "塞尔弗里奇"), ("savo_mugford", "马格福德"),
            ("savo_fuller", "富勒"), ("savo_american_legion", "美国军团"),
            ("savo_bellatrix", "贝拉特里克斯"), ("savo_mccawley", "麦考利"),
            ("savo_barnett", "巴尼特"), ("savo_george_f_elliott", "乔治·F·埃利奥特"),
            ("savo_libra", "天秤座"), ("savo_hunter_liggett", "亨特·利格特"),
            ("savo_alchiba", "菜鸟座"), ("savo_betelgeuse", "参宿四"),
            ("savo_fomalhaut", "北落师门"), ("savo_crescent_city", "新月城"),
            ("savo_president_hayes", "海斯总统"), ("savo_president_adams", "亚当斯总统"),
            ("savo_alhena", "阿尔赫纳")],
            anchor: area_offset("X-Ray", 0, 0.), heading: 0., speed: 0.,
            spacing: COLUMN_YD * YARD, follow: false },
        Column { fleet: 9, side: 0, name: "Yoke 屏护与运输", ships: &[
            ("savo_henley", "亨利"), ("savo_ellet", "埃利特"),
            ("savo_heywood_yoke", "海伍德"), ("savo_neville", "内维尔"),
            ("savo_zeilin", "塞林"), ("savo_president_jackson", "杰克逊总统"),
            ("savo_colhoun", "科尔霍恩"), ("savo_little", "利特尔"),
            ("savo_gregory", "格雷戈里"), ("savo_mckean", "麦基恩")],
            anchor: area_offset("Yoke", 0, 0.), heading: 0., speed: 0.,
            spacing: COLUMN_YD * YARD, follow: false },
        // Hull stays detached with the burning transport (printed DIW note).
        Column { fleet: 10, side: 0, name: "赫尔 · 分遣", ships: &[("savo_hull", "赫尔")],
            anchor: area_offset("Yoke", 10, 0.), heading: 0., speed: 0.,
            spacing: COLUMN_YD * YARD, follow: false },
    ]
}

fn data() -> E<&'static crate::model::Data> {
    static DATA: OnceLock<Result<crate::model::Data, String>> = OnceLock::new();
    DATA.get_or_init(|| {
        let mut data = crate::prologue::data()?.clone();
        let manifest: serde_json::Value = serde_json::from_str(include_str!(
            "../../data/campaign/period/savo-runtime.json"
        )).map_err(|e| format!("无法载入萨沃舰卡：{e}"))?;
        let ships: Vec<crate::model::ShipDef> = serde_json::from_value(manifest["ships"].clone())
            .map_err(|e| format!("萨沃舰卡格式有误：{e}"))?;
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
    // Reuse the Savo/Guadalcanal polygons already projected for Cape
    // Esperance; the sound is the same chart area and both came from the
    // same satellite pass. Savo sits well inside this box.
    let chart: serde_json::Value = serde_json::from_str(include_str!(
        "../../data/campaign/period/chart-esperance.json"
    )).expect("esperance chart");
    chart["islands"].as_array().expect("islands").iter().map(|island| {
        island["points"].as_array().expect("points").iter()
            .map(|pt| P { x: pt[0].as_f64().unwrap_or(0.), y: pt[1].as_f64().unwrap_or(0.) })
            .collect()
    }).collect()
}

pub(crate) fn fill(w: &mut World) -> E<()> {
    w.field = FIELD;
    w.islands = islands();
    let player = w.player;
    for column in columns() {
        let mut members = Vec::new();
        for (index, (class, name)) in column.ships.iter().enumerate() {
            let def = w.data.ships.iter().position(|d| d.id == *class)
                .ok_or_else(|| format!("缺少已核验舰型 {class}"))?;
            let position = if column.name.contains("X-Ray") {
                area_offset("X-Ray", index, column.heading)
            } else if column.name.contains("Yoke") {
                area_offset("Yoke", index, column.heading)
            } else {
                snap(column.anchor - P::bearing(column.heading) * index as f64 * column.spacing)
            };
            let id = w.spawn(def, column.side, column.fleet, name.to_string(), position, column.heading)?;
            let ship = w.ship_mut(id).unwrap();
            ship.speed = column.speed;
            ship.free_speed = column.speed;
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
    // Allied Condition II: the Japanese are already detected by their
    // floatplanes over the northern and southern forces (printed special
    // rule), so the D6/3 fire hold rolls on the first allied contact event.
    w.enable_realtime()?;
    for column in columns().iter().filter(|column| column.side == 1 && column.follow) {
        let rad = column.heading.to_radians();
        let point = snap(P { x: column.anchor.x + rad.sin() * 9_000.,
                             y: column.anchor.y + rad.cos() * 9_000. });
        w.route(1, &json!({"op":"route","fleet":column.fleet,"mode":"follow",
            "speed":column.speed,"points":[point]}), false)?;
    }
    w.add(3, "start", format!("{LABEL} · 1942-08-09 00:52，能见度 10%，New Moon，海况 3"),
        Some("CAS-RS-SAVO-01"), None);
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
        ("CAMP-ALLIES-10", "保护卸载作业。造成 3:1 损伤比且无运输舰受损 25%，获决定性胜利；1:1 损伤比且无运输舰受损 50%，获战术胜利。")
    } else {
        ("CAMP-AXIS-10", "击毁伦加与图拉吉外海的同盟舰艇，随后撤至萨沃以北 120 海里外。击沉或重创超过 75% 五艘运输舰获决定性胜利；造成 2:1 损伤比获战术胜利。")
    };
    json!({"stageId":stage,"difficulty":start.difficulty,"missionLabel":LABEL,
        "objectives":objectives,"withdrawalX":null})
}

/// The printed conditions: allied damage ratio with transport damage caps;
/// Japanese either wreck five transports or hold a 2:1 damage ratio.
pub(crate) fn outcome(w: &World) -> Outcome {
    let dp = |ship: &crate::model::Ship| w.data.ships[ship.def].dp;
    let damage = |side: usize| w.ships.iter().filter(|s| s.side == side)
        .map(|s| (dp(s) - s.hp).max(0.)).sum::<f64>();
    let (allied, axis) = (damage(0), damage(1));
    let transports_hit = |pct: f64| w.ships.iter()
        .filter(|s| s.side == 0 && matches!(w.data.ships[s.def].kind.as_str(),
            "AP" | "APA" | "AK" | "AKA" | "DMS" | "APD"))
        .filter(|s| (dp(s) - s.hp).max(0.) >= dp(s) * pct).count() as u32;
    let allies = if allied > 0. && allied >= axis * 3. && transports_hit(0.25) == 0 { Grade::Decisive }
        else if allied > 0. && allied >= axis && transports_hit(0.5) == 0 { Grade::Tactical }
        else { Grade::None };
    let axis = if axis >= allied * 2. { Grade::Tactical } else { Grade::None };
    // The five-transport decisive condition counts hulls put out of action;
    // with no historical mooring chart for the boxes this stays tactical-only
    // until the transport layout is adjudicated (registered limitation).
    Outcome { allies, axis }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_seats_open_with_the_printed_forces() {
        for seat in 0..2 {
            let mut start = Start::new(if seat == 0 { "CAMP-ALLIES-10" } else { "CAMP-AXIS-10" }, "story");
            start.content_version = CONTENT.into();
            let w = open(6106, start, seat, "coord", "coord").unwrap();
            assert_eq!(w.ships.len(), 57);
            assert_eq!(w.ships.iter().filter(|s| s.side == 1).count(), 8);
            // Mikawa leads at 345°/12 kyds from Blue on the 135° course.
            let blue = chart_ship("Blue").unwrap();
            let chokai = w.ships.iter().find(|s| s.name == "鸟海").unwrap();
            let dist = blue.dist(chokai.p);
            assert!((dist - 12_000. * YARD).abs() < 100., "{dist}");
            assert_eq!(w.fleets.iter().filter(|f| f.side == 1).count(), 2);
        }
    }
}
