//! Kula Gulf (Rising Sun, PDF 85–86). Loaded only as its own campaign content.
use super::{live::Start, Grade, Outcome};
use crate::{
    model::*,
    night::{Environment, Light},
    world::World,
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{collections::BTreeMap, sync::OnceLock};

pub(crate) const VERSION: &str = "cas-campaign-v9";
pub(crate) const CONTENT: &str = "cas-kula-runtime-v1";
pub(crate) const VARIANT: &str = "kula-gulf-rts";
pub(crate) const LABEL: &str = "库拉湾 · RTS 改编";
pub(crate) const FIELD: Field = Field {
    width: 46_000.,
    height: 50_000.,
    limit: 7200,
};
pub(crate) const ENVIRONMENT: Environment = Environment {
    visibility: 10,
    sea_state: 1,
    light: Light::Night,
    precipitation: false,
};
const NMI: f64 = 1852.;
const SPACING: f64 = 1000. * YARD;
const SUPPLY_DURATION: u32 = 30 * 60;
const FIRST_TRANSPORT: [&str; 3] = ["kula-mochizuki", "kula-mikazuki", "kula-hamakaze"];
const SECOND_TRANSPORT: [&str; 4] = [
    "kula-amagiri",
    "kula-hatsuyuki",
    "kula-nagatsuki",
    "kula-satsuki",
];
const US_COLUMN: [&str; 7] = [
    "kula-nicholas",
    "kula-obannon",
    "kula-honolulu",
    "kula-helena",
    "kula-st-louis",
    "kula-radford",
    "kula-jenkins",
];
const AXIS_SCREEN: [&str; 3] = ["kula-niizuki", "kula-suzukaze", "kula-tanikaze"];

// Pixel centers from the PDF rendered at 2.1 px/pt. The printed scale bar
// measures 177 px per 3 nmi. Its rotated page axes are west/south on the chart.
fn from_chart(page_x: f64, page_y: f64) -> P {
    let metres_per_pixel = 3. * NMI / 177.;
    P {
        x: 1000. + (1540. - page_y) * metres_per_pixel,
        y: 49_000. - (page_x - 150.) * metres_per_pixel,
    }
    .snap()
}

fn vila() -> P {
    (from_chart(1113., 1277.) - P::bearing(0.) * (8.5 * NMI)).snap()
}

fn charted_coast() -> Vec<P> {
    // The southern note is off the chart. Trace only the published shore
    // polygon; the continuation to Vila is represented by the objective area.
    [
        (1148., 1046.),
        (1100., 1055.),
        (1045., 1048.),
        (990., 1057.),
        (935., 1068.),
        (870., 1080.),
        (811., 1096.),
        (764., 1115.),
        (721., 1158.),
        (680., 1205.),
        (644., 1250.),
        (608., 1298.),
        (576., 1347.),
        (558., 1403.),
        (568., 1458.),
        (590., 1535.),
        (1148., 1535.),
    ]
    .into_iter()
    .map(|(x, y)| from_chart(x, y))
    .collect()
}

#[derive(Deserialize)]
struct Instance {
    id: String,
    name: String,
    profile: String,
    radar: Vec<String>,
    supply: bool,
}
#[derive(Deserialize)]
struct Manifest {
    content_version: String,
    profiles: BTreeMap<String, Value>,
    instances: Vec<Instance>,
}
struct Runtime {
    data: Data,
    instances: Vec<Instance>,
}

fn runtime() -> E<&'static Runtime> {
    static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();
    RUNTIME
        .get_or_init(|| {
            let manifest: Manifest =
                serde_json::from_str(include_str!("../../data/campaign/period/kula-runtime.json"))
                    .map_err(|e| format!("无法读取库拉湾时期舰卡：{e}"))?;
            if manifest.content_version != CONTENT {
                return Err("库拉湾内容版本不一致".into());
            }
            let mut ships = Vec::with_capacity(manifest.instances.len());
            for instance in &manifest.instances {
                let mut hull = manifest
                    .profiles
                    .get(&instance.profile)
                    .ok_or("缺少库拉湾舰型")?
                    .clone();
                hull["id"] = json!(instance.id);
                hull["name"] = json!(instance.name);
                ships.push(
                    serde_json::from_value(hull).map_err(|e| format!("库拉湾舰卡无效：{e}"))?,
                );
            }
            let mut data = Data {
                ships,
                rules: World::exercise_data()?.rules.clone(),
            };
            super::fleet::add_registered_cards(&mut data)?;
            Ok(Runtime {
                data,
                instances: manifest.instances,
            })
        })
        .as_ref()
        .map_err(Clone::clone)
}

pub(crate) fn is_stage(stage: &str) -> bool {
    matches!(stage, "CAMP-ALLIES-04" | "CAMP-AXIS-04")
}

pub(crate) fn uses_mk4(ship: &str) -> bool {
    matches!(
        ship,
        "kula-nicholas" | "kula-obannon" | "kula-radford" | "kula-jenkins"
    )
}

pub(crate) fn gun_timing(id: &str) -> Option<crate::realtime::Timings> {
    let (reload, train) = match id {
        "kula-nicholas" | "kula-obannon" | "kula-radford" | "kula-jenkins" => (4, 18.),
        "kula-honolulu" | "kula-helena" | "kula-st-louis" => (10, 10.),
        "kula-niizuki" => (6, 12.),
        "kula-suzukaze" | "kula-tanikaze" | "kula-hamakaze" | "kula-amagiri" | "kula-hatsuyuki" => {
            (12, 6.)
        }
        "kula-mochizuki" | "kula-mikazuki" | "kula-nagatsuki" | "kula-satsuki" => (12, 8.),
        _ => return None,
    };
    Some(crate::realtime::Timings { reload, train })
}

fn orders(seat: usize) -> &'static str {
    if seat == 0 {
        "在维拉附近截击东京快车。造成的损伤点多于日军为战术胜利，达到日军的两倍为决定胜利。"
    } else {
        "保持至少三艘运输驱逐舰同时在维拉 1 海里内连续 30 分钟，并击沉至少一艘美军巡洋舰。击沉两艘以上为决定胜利。"
    }
}

pub(crate) fn view(world: &World, start: &Start, owner: usize) -> Value {
    let position = vila();
    let mut mission = json!({
        "stageId": if owner == 0 { "CAMP-ALLIES-04" } else { "CAMP-AXIS-04" },
        "difficulty":start.difficulty,"missionLabel":LABEL,"objectives":orders(owner),
        "supplyZone":{"x":position.x,"y":position.y,"radius":NMI,"label":"维拉卸载区"},
    });
    if owner == 1 {
        let battle = world.kula.as_ref().expect("Kula objective state");
        mission["supplySeconds"] = json!(battle.progress);
        mission["supplyComplete"] = json!(battle.unloaded);
    }
    mission
}

struct Column<'a> {
    owner: usize,
    ids: &'a [&'a str],
    label: &'a str,
    leader: P,
    heading: f64,
    speed: f64,
    run: f64,
    ai_move: bool,
}

pub(crate) fn open(seed: u32, start: Start, player: usize, enemy: &str, profile: &str) -> E<World> {
    let runtime = runtime()?;
    let mut world = World::blank(&runtime.data, seed, player, enemy, VARIANT, profile, 0);
    world.field = FIELD;
    world.islands.push(charted_coast());
    world.campaign = Some(start);
    let nicholas = from_chart(334., 579.);
    let niizuki = nicholas + P::bearing(205.) * (12. * NMI);
    let columns = [
        Column {
            owner: 0,
            ids: &US_COLUMN,
            label: "第 36.1 特混编队",
            leader: nicholas,
            heading: 292.,
            speed: 25.,
            run: 17_000.,
            ai_move: true,
        },
        Column {
            owner: 1,
            ids: &AXIS_SCREEN,
            label: "第 3 驱逐舰分队 · 屏护",
            leader: niizuki,
            heading: 350.,
            speed: 21.,
            run: 13_000.,
            ai_move: true,
        },
        Column {
            owner: 1,
            ids: &SECOND_TRANSPORT,
            label: "第二运输队",
            leader: niizuki - P::bearing(350.) * (AXIS_SCREEN.len() as f64 * SPACING),
            heading: 350.,
            speed: 21.,
            run: 13_000.,
            ai_move: false,
        },
        Column {
            owner: 1,
            ids: &FIRST_TRANSPORT,
            label: "第一运输队 · 维拉",
            leader: vila() + P::bearing(350.) * (500. * YARD),
            heading: 350.,
            speed: 0.,
            run: 0.,
            ai_move: false,
        },
    ];
    let mut supply_ids = Vec::new();
    for column in columns {
        let fleet = world.fleets.len() as u32 + 1;
        let heading = P::bearing(column.heading);
        let mut members = Vec::new();
        for (index, id) in column.ids.iter().enumerate() {
            let spacing = if column.run == 0. {
                500. * YARD
            } else {
                SPACING
            };
            let p = (column.leader - heading * (index as f64 * spacing)).snap();
            let def = runtime
                .instances
                .iter()
                .position(|entry| entry.id == *id)
                .ok_or("缺少库拉湾具名舰")?;
            let instance = &runtime.instances[def];
            let ship = world.spawn(
                def,
                column.owner,
                fleet,
                instance.name.clone(),
                p,
                column.heading,
            )?;
            if uses_mk4(id) {
                world.radar.equip_fletcher_1943(ship)?;
            } else {
                for radar in &instance.radar {
                    world.radar.equip(ship, radar)?;
                }
            }
            if instance.supply {
                supply_ids.push(ship);
            }
            let current = world.ship_mut(ship).unwrap();
            current.speed = column.speed;
            if column.run > 0. {
                let end = (p + heading * column.run).snap();
                if !FIELD.contains(end) {
                    return Err("库拉湾初始航路超出海图".into());
                }
                current.track = Some(Track::new(vec![p, end], 0., p.dist(end)));
            }
            members.push(ship);
        }
        let mut ai = Ai::new(
            if column.owner == player {
                profile
            } else {
                enemy
            },
            if column.owner == player {
                "manual"
            } else {
                "auto"
            },
        );
        if !column.ai_move {
            ai.r#move = false;
        }
        let leader = members[0];
        let points = world
            .ship(leader)
            .unwrap()
            .track
            .as_ref()
            .map_or(Vec::new(), Track::remaining);
        world.fleets.push(Fleet {
            id: fleet,
            side: column.owner,
            name: column.label.into(),
            leader,
            members,
            mode: "follow".into(),
            speed: column.speed.max(4.),
            actual: column.speed,
            turn_degrees: 0.,
            points,
            ai,
            notice: None,
            last_ai_route: 0,
            tactic: Tactic::Search,
        });
    }
    if world.ships.len() != runtime.instances.len() || supply_ids.len() != 7 {
        return Err("库拉湾编成和卸载编制不完整".into());
    }
    world.kula = Some(Battle {
        supply: supply_ids.into_iter().map(|id| (id, 0)).collect(),
        progress: 0,
        unloaded: false,
        damage: [0.; 2],
    });
    world.gun_streak.resize(world.ships.len(), (0, 0, 0));
    world
        .surface_damage
        .resize(world.ships.len(), Default::default());
    world.init_realtime(VERSION)?;
    for seat in 0..2 {
        world.add(
            1 << seat,
            "start",
            format!("{LABEL}｜{}", orders(seat)),
            Some("CAS-RS-P84"),
            None,
        );
    }
    world.detect(true);
    world.radar_detect();
    Ok(world)
}

#[derive(Debug)]
pub(crate) struct Battle {
    supply: Vec<(u32, u32)>,
    progress: u32,
    unloaded: bool,
    damage: [f64; 2],
}

impl Battle {
    pub(crate) fn credit(&mut self, attacker: usize, victim: usize, effective_dp: f64) {
        if attacker != victim {
            self.damage[attacker] += effective_dp;
        }
    }
}

pub(crate) fn tick(world: &mut World) {
    let Some(battle) = &mut world.kula else {
        return;
    };
    if battle.unloaded {
        return;
    }
    let center = vila();
    let mut longest = [0; 3];
    for (ship, seconds) in &mut battle.supply {
        let in_zone = world
            .ships
            .get((*ship - 1) as usize)
            .is_some_and(|s| s.alive() && s.p.dist(center) <= NMI);
        *seconds = if in_zone { *seconds + 1 } else { 0 };
        if *seconds > longest[0] {
            longest[0] = *seconds;
            longest.sort_unstable();
        }
    }
    battle.progress = longest[0];
    if battle.progress >= SUPPLY_DURATION {
        battle.unloaded = true;
        world.add(
            2,
            "objective",
            "三艘运输驱逐舰已在维拉连续停留 30 分钟，卸载目标达成。".into(),
            Some("CAS-RS-P84"),
            Some(center),
        );
    }
}

fn assess(damage: [f64; 2], unloaded: bool, cruisers_sunk: usize) -> Outcome {
    let allies = if damage[0] > 0. && damage[0] >= 2. * damage[1] {
        Grade::Decisive
    } else if damage[0] > damage[1] {
        Grade::Tactical
    } else {
        Grade::None
    };
    let axis = match (unloaded, cruisers_sunk) {
        (true, 2..) => Grade::Decisive,
        (true, 1) => Grade::Tactical,
        _ => Grade::None,
    };
    Outcome { allies, axis }
}

pub(crate) fn outcome(world: &World) -> Outcome {
    let battle = world.kula.as_ref().expect("Kula objective state");
    let cruisers_sunk = world
        .ships
        .iter()
        .filter(|s| s.side == 0 && s.hp <= 0. && world.data.ships[s.def].kind == "CL")
        .count();
    assess(battle.damage, battle.unloaded, cruisers_sunk)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Engine;

    fn ask(engine: &mut Engine, request: Value) -> Value {
        let response = engine.handle(request);
        assert_eq!(response["ok"], true, "{response}");
        response["data"].clone()
    }

    #[test]
    fn chart_columns_and_current_three_ship_unload_interval() {
        let mut world = open(4, Start::new("CAMP-AXIS-04", "story"), 1, "coord", "coord").unwrap();
        let position = |id: usize| world.ships[id].p;
        let difference = position(7) - position(0);
        assert!((difference.len() - 12. * NMI).abs() < 1e-5);
        assert!((difference.heading() - 205.).abs() < 1e-5);
        assert_eq!((world.ships[0].h, world.ships[0].speed), (292., 25.));
        assert_eq!((world.ships[7].h, world.ships[7].speed), (350., 21.));
        assert_eq!(world.data.ships[world.ships[5].def].id, "kula-radford");
        assert_eq!(world.data.ships[world.ships[6].def].id, "kula-jenkins");
        assert_eq!(world.data.ships[world.ships[2].def].dp, 388.);
        assert_eq!(world.data.ships[world.ships[3].def].dp, 396.);
        let mut first_transport = world.ships.iter().filter(|ship| ship.fleet == Some(4));
        assert!(first_transport.all(|ship| ship.p.dist(vila()) <= NMI));
        for _ in 0..1799 {
            tick(&mut world);
        }
        assert!(!world.kula.as_ref().unwrap().unloaded);
        let former = world.ships[15].p;
        world.ships[15].p = vila() + P::bearing(90.) * (NMI + 1.);
        tick(&mut world);
        assert_eq!(world.kula.as_ref().unwrap().progress, 0);
        world.ships[15].p = former;
        for _ in 0..1800 {
            tick(&mut world);
        }
        assert!(world.kula.as_ref().unwrap().unloaded);
        assert!(world.observation(0)["campaign"]["supplySeconds"].is_null());
        assert_eq!(world.observation(1)["campaign"]["supplySeconds"], 1800);
        assert_eq!(assess([0., 0.], false, 0).allies, Grade::None);
        assert_eq!(assess([100., 50.], true, 1).allies, Grade::Decisive);
        assert_eq!(assess([99., 50.], true, 1).allies, Grade::Tactical);
        assert_eq!(assess([99., 50.], true, 1).axis, Grade::Tactical);
        assert_eq!(assess([99., 50.], false, 2).axis, Grade::None);
    }

    #[test]
    fn both_campaign_seats_score_actual_combat_and_replay() {
        for (stage, difficulty, seed, side) in [
            ("CAMP-ALLIES-04", "standard", 6106, 0),
            ("CAMP-AXIS-04", "challenge", 2, 1),
        ] {
            let mut engine = Engine::default();
            let opened = ask(
                &mut engine,
                json!({"op":"new_campaign","id":stage,"difficulty":difficulty,"seed":seed,"profile":if side == 0 { "gunnery" } else { "torpedo" }}),
            );
            for fleet in opened["fleets"].as_array().unwrap() {
                let id = fleet["id"].as_u64().unwrap();
                let profile = if id == 2 { "torpedo" } else { "gunnery" };
                ask(
                    &mut engine,
                    json!({"op":"ai","fleet":id,"profile":profile,"mode":"auto","move":side == 0,"gun":true,"torpedo":true}),
                );
            }
            let first = ask(&mut engine, json!({"op":"step","seconds":1800}));
            assert_eq!(
                first["campaign"]["supplyComplete"],
                if side == 1 { json!(true) } else { Value::Null }
            );
            for _ in 0..2 {
                ask(&mut engine, json!({"op":"step","seconds":2700}));
            }
            let finished = ask(&mut engine, json!({"op":"step","seconds":120}));
            assert_eq!(
                finished["result"]["grade"],
                if side == 0 { "decisive" } else { "tactical" }
            );
            let report = ask(&mut engine, json!({"op":"report"}));
            let events = report["events"].as_array().unwrap();
            let needed = if side == 0 {
                ["gun", "damage"]
            } else {
                ["objective", "torpedo_hit"]
            };
            assert!(needed
                .into_iter()
                .all(|kind| events.iter().any(|event| event["kind"] == kind)));
            let save = ask(&mut engine, json!({"op":"save"}));
            assert_eq!(save["version"], VERSION);
            assert_eq!(
                ask(&mut engine, json!({"op":"replay","save":save})),
                finished
            );
            assert_eq!(ask(&mut engine, json!({"op":"load","save":save})), finished);
        }
    }
}
