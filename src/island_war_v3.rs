//! Explicit original per-body weapons. Published v2 execution remains frozen.
use super::*;
#[path = "island_war_v3_roles.rs"]
mod roles;
use roles::{AaTurret, Effect, Secondary};
const PROFILES: [Unit; 22] = [
    Unit {
        hp: 95.0,
        armor: 0.95,
        speed: 85.0,
        transport: "transport_helicopter",
        ability: "suppression",
        range: 950.0,
        ..UNITS[0]
    },
    Unit {
        hp: 110.0,
        armor: 0.85,
        speed: 75.0,
        transport: "landing_craft",
        ability: "suppression",
        range: 950.0,
        ..UNITS[1]
    },
    Unit {
        hp: 95.0,
        armor: 1.0,
        speed: 80.0,
        transport: "parachute_aircraft",
        ability: "at_missile",
        range: 1550.0,
        ..UNITS[2]
    },
    Unit {
        hp: 100.0,
        armor: 0.95,
        speed: 72.0,
        transport: "armored_boat",
        ability: "demolition",
        range: 220.0,
        ..UNITS[3]
    },
    Unit {
        class: "infantry",
        hp: 110.,
        armor: 0.85,
        speed: 70.,
        transport: "heavy_lander",
        ability: "hull_down",
        range: 1700.0,
        ..UNITS[4]
    },
    Unit {
        hp: 85.0,
        armor: 1.1,
        speed: 95.0,
        transport: "kayak",
        ability: "smoke",
        range: 450.0,
        ..UNITS[5]
    },
    Unit {
        hp: 80.0,
        armor: 1.1,
        speed: 100.0,
        transport: "fast_boat",
        ability: "recon_mark",
        range: 1900.0,
        ..UNITS[6]
    },
    Unit {
        class: "infantry",
        hp: 95.,
        armor: 0.95,
        speed: 82.,
        transport: "attack_helicopter",
        ability: "air_rockets",
        range: 1500.0,
        ..UNITS[7]
    },
    Unit {
        hp: 90.0,
        armor: 1.0,
        speed: 78.0,
        transport: "landing_craft",
        ability: "jam",
        range: 550.0,
        ..UNITS[8]
    },
    Unit {
        hp: 100.0,
        armor: 0.95,
        speed: 76.0,
        transport: "landing_craft",
        ability: "triage",
        range: 220.0,
        ..UNITS[9]
    },
    Unit {
        hp: 90.0,
        armor: 0.95,
        speed: 65.0,
        transport: "landing_craft",
        ability: "at_missile",
        range: 1550.0,
        ..UNITS[10]
    },
    Unit {
        hp: 100.0,
        armor: 1.0,
        speed: 62.0,
        transport: "heavy_lander",
        ability: "barrage",
        range: 220.0,
        ..UNITS[11]
    },
    Unit {
        class: "infantry",
        hp: 105.,
        armor: 0.9,
        speed: 75.,
        transport: "amphibious_vehicle",
        ability: "rapid_march",
        range: 1200.0,
        ..UNITS[12]
    },
    Unit {
        hp: 105.0,
        armor: 0.9,
        speed: 66.0,
        transport: "armored_boat",
        ability: "supply_network",
        range: 550.0,
        ..UNITS[13]
    },
    Unit {
        hp: 75.0,
        armor: 1.15,
        speed: 95.0,
        transport: "fast_boat",
        ability: "support_designation",
        range: 2300.0,
        ..UNITS[14]
    },
    Unit {
        hp: 100.0,
        armor: 0.9,
        speed: 70.0,
        transport: "landing_craft",
        ability: "deploy_aa_turret",
        range: 1800.0,
        ..UNITS[15]
    },
    Unit {
        hp: 90.0,
        armor: 1.05,
        speed: 90.0,
        transport: "fast_boat",
        ability: "smoke",
        range: 950.0,
        ..UNITS[16]
    },
    Unit {
        hp: 135.0,
        armor: 0.65,
        speed: 70.0,
        transport: "landing_craft",
        ability: "grenade",
        range: 450.0,
        ..UNITS[17]
    },
    Unit {
        hp: 100.0,
        armor: 0.9,
        speed: 95.0,
        transport: "landing_craft",
        ability: "command_network",
        range: 1250.0,
        ..UNITS[18]
    },
    Unit {
        hp: 85.0,
        armor: 1.1,
        speed: 95.0,
        transport: "transport_helicopter",
        ability: "rescue",
        range: 220.0,
        ..UNITS[19]
    },
    Unit {
        hp: 85.0,
        armor: 1.05,
        speed: 88.0,
        transport: "parachute_aircraft",
        ability: "drop_smoke",
        range: 950.0,
        ..UNITS[20]
    },
    Unit {
        class: "infantry",
        hp: 90.,
        armor: 1.0,
        speed: 88.,
        transport: "attack_helicopter",
        ability: "air_coordination",
        range: 1500.0,
        ..UNITS[21]
    },
];
fn profile(id: &str) -> &'static Unit {
    PROFILES.iter().find(|u| u.id == id).unwrap()
}
#[path = "island_war_v3_accuracy.rs"]
mod accuracy;
#[path = "island_war_v3_firearms.rs"]
mod firearms;
#[path = "island_war_v3_vehicles.rs"]
mod vehicles;
use firearms::{Cadence, FireState};
pub(crate) const VERSION: &str = "cas-island-war-v3";
const EQUIPMENT: &str = "tactical-vehicles-v3";

#[derive(Clone, Copy, Serialize)]
struct Multipliers {
    unarmored: f64,
    light_armor: f64,
    heavy_armor: f64,
    aircraft: f64,
    helicopter: f64,
    parachuting: f64,
}
#[derive(Clone, Copy, Serialize)]
struct Weapon {
    id: &'static str,
    name: &'static str,
    family_id: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    owner: Option<&'static str>,
    #[serde(flatten)]
    cadence: Cadence,
    accuracy_scale: f64,
    damage: f64,
    range_m: f64,
    reload_s: f64,
    ammo_capacity: u32,
    projectile_speed_mps: f64,
    blast_radius_m: f64,
    multipliers: Multipliers,
}
macro_rules! weapon {
    ($id:literal,$name:literal,$d:expr,$r:expr,$t:expr,$a:expr,$s:expr,$b:expr,[$u:expr,$l:expr,$h:expr,$f:expr,$c:expr,$p:expr]) => {
        Weapon {
            id: $id,
            name: $name,
            family_id: $id,
            owner: None,
            cadence: Cadence::single($t),
            accuracy_scale: 1.,
            damage: $d,
            range_m: $r,
            reload_s: $t,
            ammo_capacity: $a,
            projectile_speed_mps: $s,
            blast_radius_m: $b,
            multipliers: Multipliers {
                unarmored: $u,
                light_armor: $l,
                heavy_armor: $h,
                aircraft: $f,
                helicopter: $c,
                parachuting: $p,
            },
        }
    };
}
const WEAPONS: [Weapon; 18] = [
    weapon!(
        "rifle",
        "制式步枪",
        12.,
        750.,
        1.2,
        90,
        8500.,
        0.,
        [1., 0.12, 0.018, 0.012, 0.035, 1.]
    ),
    weapon!(
        "carbine",
        "轻型卡宾枪",
        7.,
        550.,
        1.5,
        72,
        8500.,
        0.,
        [1., 0.10, 0.012, 0.01, 0.025, 1.]
    ),
    weapon!(
        "pistol",
        "自卫手枪",
        4.,
        220.,
        2.,
        36,
        6000.,
        0.,
        [1., 0.06, 0.005, 0.005, 0.012, 1.]
    ),
    weapon!(
        "smg",
        "近距冲锋枪",
        9.,
        450.,
        0.8,
        120,
        8500.,
        0.,
        [1., 0.08, 0.008, 0.008, 0.022, 1.]
    ),
    weapon!(
        "sniper",
        "精确狙击步枪",
        55.,
        1900.,
        5.5,
        24,
        11000.,
        0.,
        [1., 0.22, 0.025, 0.018, 0.045, 1.]
    ),
    weapon!(
        "lmg",
        "班用轻机枪",
        16.,
        950.,
        1.5,
        100,
        8500.,
        0.,
        [1., 0.18, 0.022, 0.018, 0.05, 1.]
    ),
    weapon!(
        "rocket",
        "反装甲火箭筒",
        150.,
        1550.,
        6.,
        6,
        650.,
        55.,
        [0.7, 1.5, 1.15, 0.02, 0.08, 0.7]
    ),
    weapon!(
        "tank_gun",
        "重装甲主炮",
        120.,
        1700.,
        5.,
        28,
        1200.,
        65.,
        [0.9, 1.25, 1., 0.005, 0.025, 0.9]
    ),
    weapon!(
        "autocannon",
        "两栖战车机关炮",
        30.,
        1200.,
        1.8,
        72,
        1800.,
        22.,
        [1., 0.9, 0.2, 0.035, 0.12, 1.]
    ),
    weapon!(
        "howitzer",
        "自行榴弹炮",
        165.,
        3200.,
        8.,
        16,
        650.,
        105.,
        [1., 0.85, 0.32, 0., 0., 1.]
    ),
    weapon!(
        "helicopter_cannon",
        "武直机炮",
        32.,
        1500.,
        1.8,
        42,
        2200.,
        28.,
        [1., 0.85, 0.18, 0.15, 0.45, 1.]
    ),
    weapon!(
        "aa_missile",
        "便携防空导弹",
        85.,
        2600.,
        5.,
        8,
        1400.,
        45.,
        [0.25, 0.1, 0.02, 1.8, 1.5, 1.]
    ),
    weapon!(
        "dmr",
        "精确射手步枪",
        26.,
        1250.,
        2.6,
        48,
        11000.,
        0.,
        [1., 0.15, 0.018, 0.012, 0.035, 1.]
    ),
    weapon!(
        "heavy_sniper",
        "重型狙击步枪",
        95.,
        2300.,
        7.5,
        18,
        13000.,
        0.,
        [1., 0.35, 0.06, 0.02, 0.06, 1.]
    ),
    weapon!(
        "shotgun",
        "攻坚霰弹枪",
        62.,
        320.,
        2.2,
        30,
        5000.,
        28.,
        [1., 0.08, 0.008, 0.003, 0.008, 1.]
    ),
    weapon!(
        "aa_cannon",
        "部署式防空炮",
        24.,
        1800.,
        1.,
        16,
        2400.,
        22.,
        [0., 0., 0., 1.4, 1.2, 1.]
    ),
    weapon!(
        "grenade",
        "攻坚手雷",
        90.,
        450.,
        18.,
        3,
        160.,
        65.,
        [1., 0.25, 0.04, 0., 0., 1.]
    ),
    weapon!(
        "demolition_charge",
        "工程爆破炸药",
        105.,
        180.,
        21.,
        3,
        120.,
        45.,
        [0.65, 0.9, 0.4, 0., 0., 0.65]
    ),
];
fn weapon(id: &str) -> &'static Weapon {
    WEAPONS
        .iter()
        .find(|w| w.id == id)
        .or_else(|| firearms::models().iter().find(|w| w.id == id))
        .expect("registered weapon")
}
fn loadout(u: &Unit, k: usize) -> (&'static str, bool) {
    match u.id {
        "MCP-076" | "MCP-063" => {
            if k == 0 {
                ("rocket", true)
            } else {
                ("carbine", false)
            }
        }
        "MCP-145" => {
            if k < 2 {
                ("aa_missile", true)
            } else {
                ("rifle", false)
            }
        }
        "MCP-128" => {
            if k == 0 {
                ("heavy_sniper", true)
            } else {
                ("dmr", false)
            }
        }
        "MCP-018" => {
            if k == 0 {
                ("sniper", true)
            } else {
                ("dmr", false)
            }
        }
        "MCP-184" => {
            if k < 2 {
                ("shotgun", true)
            } else {
                ("smg", false)
            }
        }
        "MCP-203" => ("dmr", false),
        "MCP-052" | "MCP-087" | "MCP-240" => ("pistol", false),
        "MCP-009" | "MCP-022" | "MCP-103" => ("rifle", false),
        "MCP-011" => ("smg", false),
        "MCP-041" | "MCP-116" => ("carbine", false),
        "MCP-027" | "MCP-006" => ("carbine", false),
        "MCP-001" | "MCP-088" | "MCP-167" => {
            if k == 0 {
                ("lmg", true)
            } else {
                ("carbine", false)
            }
        }
        _ => {
            if k == 0 {
                ("lmg", true)
            } else {
                ("rifle", false)
            }
        }
    }
}

const ARTILLERY_FOOT: Unit = Unit {
    class: "infantry",
    hp: 100.,
    damage: 4.,
    range: 220.,
    reload: 20,
    ammo: 36,
    speed: 62.,
    armor: 1.,
    ..PROFILES[11]
};
fn armor_class(u: &Unit) -> &'static str {
    match u.class {
        "air" => "helicopter",
        "armor" if u.role != "artillery" => "heavy_armor",
        "amphibious" => "light_armor",
        _ => "unarmored",
    }
}
fn factor(w: &Weapon, kind: &str) -> f64 {
    if matches!(w.family_id, "aa_missile" | "aa_cannon")
        && !matches!(kind, "aircraft" | "helicopter" | "parachuting")
    {
        return 0.;
    }
    let m = w.multipliers;
    match kind {
        "light_armor" => m.light_armor,
        "heavy_armor" => m.heavy_armor,
        "aircraft" => m.aircraft,
        "helicopter" => m.helicopter,
        "parachuting" => m.parachuting,
        _ => m.unarmored,
    }
}
fn kayak() -> Vehicle {
    Vehicle {
        kind: "kayak",
        capacity: 2,
        hp: 110.,
        armor: 1.,
        speed: 180.,
        air: false,
    }
}
fn exposure(kind: &str) -> f64 {
    match kind {
        "kayak" => 1.,
        "fast_boat" => 0.65,
        "landing_craft" => 0.45,
        "armored_boat" => 0.18,
        "heavy_lander" => 0.08,
        _ => 0.,
    }
}
pub(crate) fn catalogue() -> Value {
    let mut v = super::catalogue();
    v["version"] = json!(VERSION);
    v["equipment_version"] = json!(EQUIPMENT);
    v["weapon_families"] = json!(WEAPONS.iter().map(accuracy::view).collect::<Vec<_>>());
    v["weapons"] = json!(firearms::models()
        .iter()
        .map(accuracy::view)
        .collect::<Vec<_>>());
    for row in v["cards"].as_array_mut().unwrap() {
        let id = row["id"].as_str().unwrap().to_owned();
        let u = profile(&id);
        let hp = if u.role == "artillery" { 100. } else { u.hp };
        row["body_stats"] = json!({"hp":hp,"armor_class":armor_class(u),"armor_multiplier":if u.role=="artillery"{1.}else{u.armor},"speed":if u.role=="artillery"{62.}else{u.speed}});
        row["weapon_composition"]=json!((0..u.people as usize).map(|k|{let(f,s)=loadout(u,k);let w=firearms::model(u.id,f);json!({"body_index":k,"weapon_id":w.id,"weapon_family_id":w.family_id,"specialist":s,"secondary_weapon_id":if matches!(f,"rocket"|"aa_missile"){Some(firearms::model(u.id,"pistol").id)}else{None},"secondary_weapon_family_id":if matches!(f,"rocket"|"aa_missile"){Some("pistol")}else{None},"operator_vehicle":Value::Null})}).collect::<Vec<_>>());
        row["combat_vehicles"] = if let Some(spec) = vehicles::spec(u.id) {
            let w = firearms::model(u.id, spec.weapon);
            json!([{"kind":spec.kind,"count_per_company":1,"hp":spec.hp,"armor_multiplier":spec.armor,"armor_class":spec.armor_class,"speed":spec.speed,"collision_radius_m":spec.radius,"weapon_id":w.id,"weapon_family_id":w.family_id,"min_crew":0,"shared_consciousness":true,"passenger_seats":if u.id=="MCP-022"{0}else{u.people},"separate_vehicle_hp":true,"repair_cost_full":{"scrap":60,"alloy":20,"credits":120}}])
        } else {
            json!([])
        };
        row["ability"]["id"] = json!(u.ability);
        row["default_transport"] = json!(u.transport);
        row["transport"] = vehicle_json(if u.transport == "kayak" {
            kayak()
        } else {
            vehicle(u.transport).unwrap()
        });
        if matches!(u.id,"MCP-103"|"MCP-027"|"MCP-006"){let s=vehicles::spec(u.id).unwrap();row["transport"]=json!({"id":u.transport,"kind":u.transport,"capacity":u.people,"hp":s.hp,"armor":s.armor,"speed":s.speed,"water_speed":if u.id=="MCP-103"{85.}else{s.speed},"airborne":s.class=="air","transport_role":"independent_persistent_combat_vehicle"});}
        row["transport_options"] = json!([row["transport"].clone()]);
        row["fixed_transport"] = json!(true);
        row["embodiment"] = json!("same_female_consciousness_independent_bodies_and_equipment");
        row["combat"]["hp"] = json!(hp);
        row["combat"]["armor"] = json!(u.armor);
        row["combat"]["speed"] = json!(u.speed);
        row["speed"] = json!(u.speed);
        row["equipment_version"] = json!(EQUIPMENT);
        let main = firearms::model(u.id, loadout(u, 0).0);
        row["combat"]["damage"] = json!(main.damage);
        row["combat"]["range"] = json!(main.range_m);
        row["combat"]["reload_seconds"] = json!(main.cadence.magazine_reload_s);
        row["combat"]["mean_fire_interval_s"] = json!(main.reload_s);
        row["combat"]["weapon_id"] = json!(main.id);
        row["combat"]["weapon_family_id"] = json!(main.family_id);
        row["combat"]["ammo"] = json!(main.ammo_capacity);
        row["combat"]["collision_radius_m"] = json!(if u.role == "artillery" {
            0.45
        } else {
            body_radius(u.class)
        });
        if u.role == "artillery" {
            row["combat"]["vehicle_id"] = Value::Null;
        }
        row["combat"]["class"] = json!(if u.role == "artillery" {
            "infantry"
        } else {
            u.class
        });
        roles::catalogue_ability(row, u);
        for t in row["transport_options"].as_array_mut().unwrap() {
            t["passenger_exposure"] = json!(exposure(t["kind"].as_str().unwrap_or("")));
        }
    }
    v["firing_model"] = json!({"version":"finite-magazine-burst-v1","simulation_tick_s":0.1,"cadence_quantization":"authored intervals are positive whole 0.1-second frames","ammo_capacity":"total initial rounds including loaded magazine","reserve_ammo":"ammo minus magazine_ammo, including during reload","reload_rule":"empty magazine auto reload; next shot waits for max(cadence due, reload completion); no free ammo","burst_interval":"previous burst last shot to next burst first shot","mean_fire_interval_formula":"(sum i=1..magazine_capacity-1 of (i%burst_size==0?burst_interval_s:fire_interval_s) + max(magazine_capacity%burst_size==0?burst_interval_s:fire_interval_s,magazine_reload_s))/magazine_capacity","legacy_reload_s":"compatibility sustained mean interval; use magazine_reload_s for actual reload duration"});
    v["damage_model"] = json!({"version":"typed-weapons-v3","parachuting_uses_full_small_arms_damage":true,"passengers_use_own_hp":true,"projectile_budget":512,"source_kind":"original_fictional"});
    v
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Saved {
    pub version: String,
    pub seed: u32,
    pub config: Value,
    pub frame: u32,
    pub tick: f64,
    pub commands: Vec<Command>,
}
#[derive(Clone)]
struct Loadout {
    weapon: &'static Weapon,
    specialist: bool,
    fire_scale: f64,
}
#[derive(Clone)]
struct CombatVehicle {
    id: u32,
    operator: u32,
    company: usize,
    p: P,
    hp: f64,
    max: f64,
    ammo: u32,
    next: u32,
    heading: f64,
    active: bool,
    destroyed: bool,
    route: Vec<P>,
    goal: P,
    kind: &'static str,
    class: &'static str,
    armor_class: &'static str,
    speed: f64,
    radius: f64,
    capacity: u32,
    phase: &'static str,
    passengers: Vec<u32>,
    action: &'static str,
    ready_at: u32,
    carried_by: Option<u32>,
    velocity: P,
    manual: bool,
}
#[derive(Clone)]
struct ShotInfo {
    weapon: &'static Weapon,
    target: Option<u32>,
    operator: u32,
    target_class: String,
    hit: bool,
    probability: f64,
    tracking_offset: P,
}
pub(crate) struct Battle {
    base: super::Battle,
    config: Value,
    loadouts: BTreeMap<u32, Loadout>,
    vehicles: Vec<CombatVehicle>,
    shots: BTreeMap<u32, ShotInfo>,
    metrics: BTreeSet<String>,
    lesson: Option<String>,
    kayaks: BTreeSet<usize>,
    unloading: BTreeMap<u32, u32>,
    secondary: BTreeMap<u32, Secondary>,
    effects: Vec<Effect>,
    aa_turrets: Vec<AaTurret>,
    air_adjusted: BTreeSet<u32>,
    designated_air: BTreeSet<u32>,
    firearms: BTreeMap<(u32, &'static str), FireState>,
    last_fire: BTreeMap<u32, u32>,
    body_routes:BTreeMap<u32,(P,Vec<P>)>,
    body_pressure:BTreeMap<u32,u32>,
    tank_tactics:BTreeMap<u32,(u32,&'static str,P)>,
}
impl Battle {
    pub(crate) fn decode(mut q: Value) -> E<(u32, Value)> {
        if q["version"] != VERSION {
            return Err("请选择显式cas-island-war-v3".into());
        }
        let seed = q.get("seed").map_or(Ok(1), |v| {
            v.as_u64()
                .filter(|n| *n <= u32::MAX as u64)
                .map(|n| n as u32)
                .ok_or("种子无效")
        })?;
        let obj = q.as_object_mut().ok_or("v3配置无效")?;
        for k in ["op", "version", "seed"] {
            obj.remove(k);
        }
        Ok((seed, q))
    }
    pub(crate) fn new(seed: u32, config: Value) -> E<Self> {
        let mut normalized = config.clone();
        for force in [&mut normalized] {
            force
                .as_object_mut()
                .ok_or("配置无效")?
                .remove("vehicle_condition");
            if let Some(d) = force.get_mut("defender").and_then(Value::as_object_mut) {
                d.remove("vehicle_condition");
            }
        }

        let delay = normalized
            .as_object_mut()
            .ok_or("v3配置无效")?
            .remove("training_delay_seconds")
            .map(|v| v.as_u64().filter(|n| *n <= 120).ok_or("教学准备期无效"))
            .transpose()?
            .unwrap_or(0) as u32;
        let lesson = normalized
            .as_object_mut()
            .ok_or("v3配置无效")?
            .remove("lesson")
            .map(|l| l.as_str().map(str::to_owned).ok_or("教学名称无效"))
            .transpose()?;
        if lesson.as_ref().is_some_and(|s| {
            ![
                "weapons",
                "landing",
                "artillery",
                "airborne",
                "roles",
                "combined_arms",
            ]
            .contains(&s.as_str())
        }) {
            return Err("未登记的v3教学".into());
        }
        for force in [Some(&config), config.get("defender")]
            .into_iter()
            .flatten()
        {
            if let Some(rows) = force.get("company_transports").and_then(Value::as_array) {
                for r in rows {
                    let id = r["id"].as_str().ok_or("固定投送人格无效")?;
                    let u = PROFILES
                        .iter()
                        .find(|u| u.id == id)
                        .ok_or("固定投送人格未登记")?;
                    if r["kind"] != u.transport {
                        return Err(format!("{}投送固定为{}，不能改选载具", id, u.transport));
                    }
                }
            }
        }
        // Apply only v3 defaults to the normalized construction request. Keep
        // original exact configuration separately for save/account signatures.
        fn defaults(force: &mut Value) {
            let roster = force["roster"].as_array().cloned().unwrap_or_default();
            if force.get("company_transports").is_none() {
                force["company_transports"] = json!([]);
            }
            if let Some(rows) = force["company_transports"].as_array_mut() {
                for id in roster {
                    if let Some(id) = id.as_str() {
                        if !rows.iter().any(|r| r["id"] == id) {
                            rows.push(json!({"id":id,"kind":PROFILES.iter().find(|u|u.id==id).map_or("landing_craft",|u|u.transport)}));
                        }
                    }
                }
            }
        }
        defaults(&mut normalized);
        if let Some(d) = normalized.get_mut("defender") {
            if d.is_object() {
                defaults(d);
            }
        }
        let mut choices = BTreeSet::new();
        for (side, field) in [(0, "company_transports"), (1, "defender")] {
            let arr = if side == 0 {
                normalized.get_mut(field).and_then(Value::as_array_mut)
            } else {
                normalized
                    .get_mut(field)
                    .and_then(|d| d.get_mut("company_transports"))
                    .and_then(Value::as_array_mut)
            };
            if let Some(arr) = arr {
                for row in arr {
                    if row["kind"] == "kayak" {
                        let id = row["id"].as_str().ok_or("皮划艇人格无效")?.to_owned();
                        if !allowed(unit(&id)?, "fast_boat") {
                            return Err("该编制不能使用皮划艇".into());
                        }
                        choices.insert((side, id));
                        row["kind"] = json!("fast_boat");
                    }
                }
            }
        }
        let start: Start =
            serde_json::from_value(normalized).map_err(|e| format!("v3配置无效：{e}"))?;
        if lesson.is_some() && start.mode != "exercise" {
            return Err("教学须使用无损演习模式".into());
        }
        let mut base = super::Battle::new(seed, start)?;
        let mut loadouts = BTreeMap::new();
        let mut vehicles = vec![];
        let mut kayaks = BTreeSet::new();
        for ci in 0..base.companies.len() {
            let c = base.companies[ci].clone();
            if c.unit.id == "MCP-116" {
                base.companies[ci].reserve = 0;
            }
            if choices.contains(&(c.side, c.unit.id.into())) {
                base.companies[ci].transport = vehicle("fast_boat")?;
                base.companies[ci].transport.capacity = 2;
                base.companies[ci].transport.hp = 110.;
                base.companies[ci].transport.armor = 1.;
                base.companies[ci].transport.speed = 180.;
                kayaks.insert(ci);
            }
            if matches!(c.unit.id, "MCP-103" | "MCP-027" | "MCP-006") {
                base.companies[ci].transport.capacity = c.bodies.len() as u32;
            }
            if c.unit.role == "artillery" {
                base.companies[ci].unit = &ARTILLERY_FOOT;
            }
            for (k, id) in c.bodies.iter().enumerate() {
                let (w, specialist) = loadout(c.unit, k);
                let w = firearms::model(c.unit.id, w);
                let b = base.body_mut(*id).unwrap();
                let fire_scale = b.damage / c.unit.damage.max(0.01);
                if c.unit.role == "artillery" {
                    let health = b.hp / b.max;
                    b.max = 100. * (b.max / c.unit.hp);
                    b.hp = b.max * health;
                    b.kind = "marine";
                    b.armor = 1.;
                }
                b.ammo = w.ammo_capacity;
                b.damage = w.damage * fire_scale;
                b.range = w.range_m;
                b.reload = (w.reload_s * 10.) as u32;
                loadouts.insert(
                    *id,
                    Loadout {
                        weapon: w,
                        specialist,
                        fire_scale,
                    },
                );
            }
            if let Some(spec) = vehicles::spec(c.unit.id) {
                let operator = c.bodies[0];
                let b = base.body(operator).unwrap().clone();
                let health = b.hp / b.max;
                let id = base.base.core.ground.id();
                let active = c.stage == "active";
                let p = if active {
                    base.free_spawn(c.p, spec.class).unwrap_or(c.p)
                } else {
                    b.p
                };
                vehicles.push(CombatVehicle {
                    id,
                    operator,
                    company: ci,
                    p,
                    hp: spec.hp * health,
                    max: spec.hp,
                    ammo: firearms::model(c.unit.id, spec.weapon).ammo_capacity,
                    next: 0,
                    heading: 90.,
                    active,
                    destroyed: false,
                    route: vec![],
                    goal: p,
                    kind: spec.kind,
                    class: spec.class,
                    armor_class: spec.armor_class,
                    speed: spec.speed,
                    radius: spec.radius,
                    capacity: if c.unit.id == "MCP-022" {
                        0
                    } else {
                        c.bodies.len() as u32
                    },
                    phase: if active { "active" } else { "aboard" },
                    passengers: vec![],
                    action: "follow",
                    ready_at: 0,
                    carried_by: None,
                    velocity: P::default(),
                    manual: false,
                });
            }
        }
        // A named airborne lesson starts the explicit defender's real para
        // company aboard its real carrier, then lets normal AI fly the insertion.
        if lesson.as_deref() == Some("airborne") {
            for ci in 0..base.companies.len() {
                if base.companies[ci].side == 1 && base.companies[ci].unit.id == "MCP-088" {
                    let c = base.companies[ci].clone();
                    base.companies[ci].stage = "embarked";
                    for id in c.bodies {
                        if let Some(b) = base.body_mut(id) {
                            b.active = false;
                        }
                        if let Some(a) = base.actors.iter_mut().find(|a| a.id == id) {
                            a.phase = "embarked";
                        }
                    }
                }
            }
        }
        let mut result = Self {
            base,
            config,
            loadouts,
            vehicles,
            shots: BTreeMap::new(),
            metrics: BTreeSet::new(),
            lesson,
            kayaks,
            unloading: BTreeMap::new(),
            secondary: BTreeMap::new(),
            effects: vec![],
            aa_turrets: vec![],
            air_adjusted: BTreeSet::new(),
            designated_air: BTreeSet::new(),
            firearms: BTreeMap::new(),
            last_fire: BTreeMap::new(),
            body_routes:BTreeMap::new(),
            body_pressure:BTreeMap::new(),
            tank_tactics:BTreeMap::new(),
        };
        result.apply_profiles();
        result.apply_vehicle_condition()?;
        result.init_vehicle_mirrors();
        result.tick_firearms();
        if delay > 0 {
            if result.lesson.is_none() {
                return Err("准备期仅限显式无损教学".into());
            }
            for v in &mut result.vehicles {if result.base.companies[v.company].side==1 {v.next=v.next.max(delay*10);}}
            for b in &mut result.base.base.core.ground.bodies {
                if !b.ally {
                    b.next = b.next.max(delay * 10);
                }
            }
            for f in &mut result.base.base.core.ground.buildings {
                if !f.ally {
                    f.next = f.next.max(delay * 10);
                }
            }
        }
        Ok(result)
    }
    fn frame(&self) -> u32 {
        self.base.frame()
    }
    fn seated(&self, id: u32) -> bool {
        self.vehicles
            .iter()
            .any(|v| v.passengers.contains(&id) && v.active && v.hp > 0.)
    }
    fn target_class(&self, id: u32) -> &'static str {
        if let Some(v) = self.vehicle_at(id) {
            return v.armor_class;
        }
        if let Some(a) = self.base.actors.iter().find(|a| a.id == id) {
            if a.phase == "parachuting" {
                return "parachuting";
            }
            return armor_class(self.base.companies[a.company].unit);
        }
        if self.base.transit.iter().any(|t| t.id == id) {
            return "light_armor";
        }
        "unarmored"
    }
    fn passenger(&self, id: u32) -> Option<(&Transit, f64)> {
        self.base
            .transit
            .iter()
            .find(|t| {
                !matches!(t.phase, "lost" | "recovered")
                    && t.passengers.contains(&id)
                    && self.base.body(t.id).is_some_and(|b| b.active && b.hp > 0.)
            })
            .map(|t| {
                (
                    t,
                    if self.kayaks.contains(&t.company) {
                        1.
                    } else {
                        exposure(t.vehicle.kind)
                    },
                )
            })
    }
    fn known(&self, id: u32, side: u32) -> bool {
        if let Some(t) = self.base.transit.iter().find(|t| t.id == id) {
            let Some(target) = self.base.body(t.id) else {
                return false;
            };
            return self
                .base
                .actors
                .iter()
                .filter(|a| self.base.companies[a.company].side == side)
                .any(|a| {
                    self.base.body(a.id).is_some_and(|b| {
                        b.active
                            && b.hp > 0.
                            && b.p.dist(target.p) < self.base.companies[a.company].unit.vision
                            && (target.air || self.base.los(b.p, target.p))
                    })
                });
        }
        self.base
            .actors
            .iter()
            .find(|a| a.id == id)
            .map_or(true, |a| a.seen[side as usize])
    }
    fn vehicle_at(&self, id: u32) -> Option<&CombatVehicle> {
        self.vehicles.iter().find(|v| v.id == id)
    }
    fn launch(
        &mut self,
        id: u32,
        side: u32,
        p: P,
        target: P,
        target_id: Option<u32>,
        target_class: &str,
        w: &'static Weapon,
        scale: f64,
        source: String,
    ) -> bool {
        if self.base.base.core.ground.projectiles.len() + self.base.base.shots.len() >= 512 {
            return false;
        }
        let (target,target_id,target_class)=if !accuracy::indirect(w)&&!matches!(target_class,"aircraft"|"helicopter"|"parachuting") {
            if let Some(v)=self.blocking_vehicle(p,target,target_id){
                if self.base.companies[v.company].side==side{return false}
                (v.p,Some(v.id),v.armor_class)
            }else{(target,target_id,target_class)}
        }else{(target,target_id,target_class)};
        let scale_spread = self.spread_scale(side, p, false);
        let moving = self.vehicles.iter().find(|v|v.id==id)
            .map(|v|v.velocity.dist(P::default())>2.)
            .unwrap_or_else(||self.base.actors.iter().find(|a|a.id==id).is_some_and(|a|a.velocity.dist(P::default())>2.));
        let chance = accuracy::probability(w, p.dist(target), moving, scale_spread);
        let angle = ((self.frame().wrapping_mul(73) + id.wrapping_mul(109)) % 360) as f64;
        let key = self.base.base.core.ground.next_id;
        let tracking_offset = if accuracy::indirect(w) {
            accuracy::scatter(w, chance, self.base.base.core.ground.seed, key)
        } else {
            P::default()
        };
        let velocity = target_id.map_or(P::default(), |id| self.target_velocity(id));
        let lead = if accuracy::indirect(w) && w.family_id != "aa_missile" {
            velocity * (p.dist(target) / w.projectile_speed_mps)
        } else {
            P::default()
        };
        let target = target + tracking_offset + lead;
        if scale_spread < 1. && side == 0 {
            self.metrics.insert("command_network".into());
        }
        let before = self.base.base.core.ground.projectiles.len();
        let kind = match w.family_id {
            "grenade" => "grenade",
            "howitzer" => "howitzer",
            "rocket" => "anti_tank",
            "tank_gun" => "tank",
            "helicopter_cannon" => "air_weapon",
            "aa_missile" => "air_defense",
            _ => "rifle",
        };
        if !self.base.base.core.ground.launch(
            side == 0,
            p,
            target,
            w.damage * scale,
            w.blast_radius_m.max(12.),
            w.projectile_speed_mps,
            false,
            kind,
            source,
        ) {
            return false;
        }
        let shot = self.base.base.core.ground.projectiles[before].id;
        let hit =
            accuracy::indirect(w) || accuracy::roll(self.base.base.core.ground.seed, shot) < chance;
        let target = if hit {
            target
        } else {
            target + P::bearing(angle + 90.) * (w.blast_radius_m + 85.)
        };
        self.base.base.core.ground.projectiles[before].goal = target;
        self.shots.insert(
            shot,
            ShotInfo {
                weapon: w,
                target: target_id,
                operator: id,
                target_class: target_class.into(),
                hit,
                probability: chance,
                tracking_offset,
            },
        );
        if let Some(row) = self.base.base.core.ground.shots.back_mut() {
            row["hit_probability"] = if accuracy::indirect(w) {
                Value::Null
            } else {
                json!(chance)
            };
            row["accuracy_quality"] = json!(chance);
            row["application"] = json!(if accuracy::indirect(w) {
                "indirect_spread"
            } else {
                "direct_probability"
            });
            row["accuracy_application"] = json!(if accuracy::indirect(w) {
                "indirect_spread"
            } else {
                "direct_probability"
            });
            row["effective_range_m"] = json!(accuracy::effective(w));
            row["target_x"] = json!(target.x);
            row["target_y"] = json!(target.y);
            row["weapon_id"] = json!(w.id);
            row["weapon_family_id"] = json!(w.family_id);
            row["operator_id"] = json!(id);
            row["target_id"] = json!(target_id);
            row["target_armor_class"] = json!(target_class);
            row["equipment_version"] = json!(EQUIPMENT);
            row["shell_count"] = json!(1);
            row["launch_point"] = json!(p);
            row["impact_point"] = json!(target);
            row["flight_seconds"] = json!(p.dist(target) / w.projectile_speed_mps);
        }
        true
    }
    fn targets(&self, p: P, side: u32, w: &Weapon) -> Vec<(f64, u32, P, &'static str)> {
        let mut out = vec![];
        for b in &self.base.base.core.ground.bodies {
            if b.hp <= 0.
                || b.ally == (side == 0)
                || self.seated(b.id)
                || self.vehicles.iter().any(|v| v.id == b.id)
            {
                continue;
            }
            let passenger = self.passenger(b.id);
            if !b.active && passenger.is_none() {
                continue;
            }
            let class = if passenger.is_some() {
                "unarmored"
            } else {
                self.target_class(b.id)
            };
            let position = passenger
                .and_then(|(t, _)| self.base.body(t.id))
                .map_or(b.p, |b| b.p);
            let seen = passenger.map_or(self.known(b.id, side), |(t, _)| self.known(t.id, side));
            if !seen
                || p.dist(position) > w.range_m
                || factor(w, class) <= 0.
                || w.family_id != "howitzer" && !self.base.los(p, position) && !b.air
            {
                continue;
            }
            let useful =
                w.damage * factor(w, class) * accuracy::probability(w, p.dist(position), false, 1.);
            let score = (b.hp / useful.max(0.001)) * w.reload_s
                + p.dist(position) / 500.
                + if w.family_id == "rocket" && !matches!(class, "light_armor" | "heavy_armor") {
                    1000.
                } else {
                    0.
                };
            out.push((score, b.id, position, class));
        }
        for v in &self.vehicles {
            let c = &self.base.companies[v.company];
            if c.side == side
                || !v.active
                || v.hp <= 0.
                || !self.vehicle_known(v.id, side)
                || p.dist(v.p) > w.range_m
                || w.family_id != "howitzer" && !self.base.los(p, v.p)
            {
                continue;
            }
            out.push((
                v.hp / (w.damage
                    * factor(w, v.armor_class)
                    * accuracy::probability(w, p.dist(v.p), false, 1.))
                .max(0.001)
                    * w.reload_s
                    + p.dist(v.p) / 500.,
                v.id,
                v.p,
                v.armor_class,
            ));
        }
        for a in &self.base.base.core.aircraft {
            if a.hp > 0.
                && self
                    .base
                    .base
                    .core
                    .naval
                    .ship(a.carrier)
                    .is_some_and(|s| s.side != side as usize)
                && p.dist(a.p) <= w.range_m
                && p.dist(a.p) < 2600.
                && factor(w, "aircraft") > 0.
            {
                out.push((
                    a.hp / (w.damage
                        * factor(w, "aircraft")
                        * accuracy::probability(w, p.dist(a.p), false, 1.))
                    .max(0.001)
                        * w.reload_s
                        + p.dist(a.p) / 500.,
                    1_000_000_000 + a.id,
                    a.p,
                    "aircraft",
                ));
            }
        }
        out.sort_by(|a, b| a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)));
        out
    }
    fn shoot(&mut self) {
        let frame = self.frame();
        let mut fire = vec![];
        for a in &self.base.actors {
            let b = self.base.body(a.id).unwrap();
            let c = &self.base.companies[a.company];
            if !b.active
                || b.hp <= 0.
                || (b.ammo == 0 && self.secondary.get(&a.id).is_none_or(|s| s.ammo == 0))
                || (b.next > frame && self.secondary.get(&a.id).is_none_or(|s| s.next > frame))
                || a.phase == "parachuting"
                || a.knock_until > frame
                || matches!(c.stage, "returning" | "withdrawing")
                || self.seated(a.id)
            {
                continue;
            }
            let l = &self.loadouts[&a.id];
            let mut options = vec![];
            if self.firearm_ready(a.id, l.weapon, b.ammo, b.next) {
                options.push(l.weapon);
            }
            if let Some(secondary) = self.secondary.get(&a.id) {
                if self.firearm_ready(a.id, secondary.weapon, secondary.ammo, secondary.next) {
                    options.push(secondary.weapon);
                }
            }
            let choice = options
                .into_iter()
                .filter_map(|w| {
                    let t = self
                        .targets(b.p, c.side, w)
                        .first()
                        .cloned()
                        .map(|(score, id, p, k)| (score, Some(id), p, k))
                        .or_else(|| {
                            self.base
                                .base
                                .core
                                .ground
                                .buildings
                                .iter()
                                .filter(|t| {
                                    t.ally != b.ally
                                        && t.hp > 0.
                                        && t.p.dist(b.p) <= w.range_m
                                        && (w.family_id == "howitzer"
                                            || b.air
                                            || self.base.los(b.p, t.p))
                                        && factor(w, "light_armor") > 0.
                                })
                                .min_by(|a, d| a.p.dist(b.p).total_cmp(&d.p.dist(b.p)))
                                .map(|t| {
                                    (
                                        t.hp / (w.damage * factor(w, "light_armor")).max(0.01)
                                            * w.reload_s,
                                        None,
                                        t.p,
                                        "light_armor",
                                    )
                                })
                        });
                    t.map(|(score, id, p, k)| (score, w, id, p, k))
                })
                .min_by(|a, b| a.0.total_cmp(&b.0));
            let Some((_, w, target, p, kind)) = choice else {
                continue;
            };
            let t = Some((target, p, kind));
            if let Some((target, p, kind)) = t {
                fire.push((
                    a.id,
                    c.side,
                    b.p,
                    p,
                    target,
                    kind,
                    w,
                    l.fire_scale,
                    c.id.clone(),
                    false,
                ));
            }
        }
        for v in &self.vehicles {
            let c = &self.base.companies[v.company];
            if !v.active
                || v.hp <= 0.
                || v.ammo == 0
                || frame < v.next
                || matches!(c.stage, "returning" | "withdrawing")
            {
                continue;
            }
            let w = firearms::model(c.unit.id, vehicles::spec(c.unit.id).unwrap().weapon);
            if !self.firearm_ready(v.id, w, v.ammo, v.next) {
                continue;
            }
            let t = self
                .targets(v.p, c.side, w)
                .first()
                .cloned()
                .map(|(_, id, p, k)| (Some(id), p, k))
                .or_else(|| {
                    self.base
                        .base
                        .core
                        .ground
                        .buildings
                        .iter()
                        .filter(|b| {
                            b.ally != (c.side == 0) && b.hp > 0. && b.p.dist(v.p) <= w.range_m
                        })
                        .min_by(|a, b| a.p.dist(v.p).total_cmp(&b.p.dist(v.p)))
                        .map(|b| (None, b.p, "light_armor"))
                });
            if let Some((target, p, kind)) = t {
                fire.push((
                    v.id,
                    c.side,
                    v.p,
                    p,
                    target,
                    kind,
                    w,
                    1.,
                    c.id.clone(),
                    true,
                ));
            }
        }
        for (id, side, p, t, target, kind, w, scale, source, _is_vehicle) in fire {
            let haste = if self.base.companies.iter().any(|c| {
                c.side == side
                    && c.buff_until > frame
                    && matches!(c.unit.ability, "air_coordination" | "coordination")
                    && c.p.dist(p) < 700.
            }) {
                0.75
            } else {
                1.
            };
            if self.launch(id, side, p, t, target, kind, w, scale, source) {
                self.consume_shot(id, w, haste);
                if side == 0 {
                    self.metrics.insert(
                        if self.vehicle_at(id).is_some() {
                            "vehicle_fired"
                        } else {
                            "body_fired"
                        }
                        .into(),
                    );
                }
            }
        }
    }
    fn resolve(
        &mut self,
        p: P,
        damage: f64,
        radius: f64,
        side: u32,
        info: Option<&ShotInfo>,
        kind: &str,
        source: &str,
        air_only: bool,
        impulse: f64,
    ) {
        let Some(info) = info else {
            let direct_origin=matches!(kind,"machine_gun"|"rifle"|"scout"|"sniper").then(||self.base.base.core.ground.buildings.iter().find(|b|b.id==source).map(|b|b.p)).flatten();
            let protected = self
                .base
                .actors
                .iter()
                .filter(|a| {
                    self.seated(a.id)
                        || direct_origin.is_some_and(|from|self.base.body(a.id).is_some_and(|b|self.blocking_vehicle(from,b.p,Some(b.id)).is_some()))
                        || kind == "naval"
                            && self
                                .base
                                .body(a.id)
                                .is_some_and(|b| b.air && a.phase != "parachuting")
                })
                .map(|a| a.id)
                .collect::<Vec<_>>();
            let mut protected = protected;
            protected.extend(self.vehicles.iter().map(|v| v.id));
            let old_active = protected
                .iter()
                .filter_map(|id| self.base.body(*id).map(|b| (*id, b.active)))
                .collect::<Vec<_>>();
            for (id, _) in &old_active {
                self.base.body_mut(*id).unwrap().active = false;
            }
            let shield = self.begin_legacy_protection();
            self.base
                .apply_blast(p, damage, radius, side, air_only, kind, source, impulse);
            self.end_legacy_protection(shield);
            for (id, active) in old_active {
                self.base.body_mut(id).unwrap().active = active;
            }
            self.passenger_damage(p, damage, radius, side, None, source);
            for i in 0..self.vehicles.len() {
                let v = &self.vehicles[i];
                if v.active
                    && v.hp > 0.
                    && self.base.companies[v.company].side != side
                    && (!air_only || v.class == "air")
                    && !(kind == "naval"
                        && v.class == "air"
                        && !matches!(v.phase, "loading" | "unloading"))
                    && v.p.dist(p) < radius + 3.
                {
                    self.hurt_vehicle(
                        i,
                        damage
                            * vehicles::spec(self.base.companies[v.company].unit.id).unwrap().armor
                            * self.incoming_scale(self.base.companies[v.company].side,v.p),
                    );
                }
            }
            return;
        };
        let w = info.weapon;
        if !info.hit {
            self.base.base.core.ground.event(
                "weapon_miss",
                "实际有限弹药未命中；距离与射手状态已参与裁决",
                p,
            );
            return;
        }
        let direct = !accuracy::indirect(w);
        let mut hits = vec![];
        for a in &mut self.base.base.core.aircraft {
            if a.hp > 0.
                && self
                    .base
                    .base
                    .core
                    .naval
                    .ship(a.carrier)
                    .is_some_and(|s| s.side != side as usize)
                && (!direct || info.target == Some(1_000_000_000 + a.id))
                && (direct || a.p.dist(p) <= radius + 45.)
            {
                let falloff = if direct {
                    1.
                } else {
                    1. - 0.5 * (a.p.dist(p) / radius.max(1.)).min(1.)
                };
                let actual = (damage * factor(w, "aircraft") * falloff).min(a.hp);
                if side == 0 && actual > 0. && w.family_id == "aa_cannon" {
                    self.metrics.insert("aa_turret_hit".into());
                }
                a.hp -= actual;
                hits.push(json!({"id":a.id,"aircraft":true,"damage":actual,"hp":a.hp,"armor_class":"aircraft"}));
                if side == 0
                    && actual > 0.
                    && [
                        "rifle",
                        "carbine",
                        "pistol",
                        "lmg",
                        "sniper",
                        "smg",
                        "dmr",
                        "heavy_sniper",
                    ]
                    .contains(&w.family_id)
                {
                    self.metrics.insert("light_air".into());
                }
            }
        }
        let ids = self
            .base
            .base
            .core
            .ground
            .bodies
            .iter()
            .filter(|b| b.ally != (side == 0) && b.hp > 0.)
            .map(|b| b.id)
            .collect::<Vec<_>>();
        for id in ids {
            if self.seated(id) || self.vehicles.iter().any(|v| v.id == id) {
                continue;
            }
            let Some(b) = self.base.body(id).cloned() else {
                continue;
            };
            let aboard = self.passenger(id).map(|(t, e)| (t.id, e));
            if !b.active && aboard.is_none() {
                continue;
            }
            if direct && info.target != Some(id) {
                continue;
            }
            let position = aboard
                .and_then(|(tid, _)| self.base.body(tid))
                .map_or(b.p, |b| b.p);
            let distance = if direct { 0. } else { position.dist(p) };
            if !direct && distance > radius + 10. {
                continue;
            }
            let class = if aboard.is_some() {
                "unarmored"
            } else {
                self.target_class(id)
            };
            let cover = if w.family_id == "howitzer" || b.air || aboard.is_some() {
                1.
            } else {
                self.base.terrain.cover(position)
            };
            let defensive = if matches!(w.family_id, "howitzer" | "grenade") || b.air {
                1.
            } else {
                self.base
                    .companies
                    .iter()
                    .filter(|c| {
                        c.side != side && c.buff_until > self.frame() && c.p.dist(position) < 350.
                    })
                    .map(|c| match c.unit.ability {
                        "smoke" | "drop_smoke" => 0.65f64,
                        "hull_down" => 0.55,
                        _ => 1.,
                    })
                    .fold(1., f64::min)
            };
            let protection = self
                .effects
                .iter()
                .filter(|e| {
                    e.kind == "supply_network"
                        && e.side != side
                        && e.end > self.frame()
                        && e.p.dist(position) < e.radius
                })
                .map(|_| 0.9f64)
                .fold(1., f64::min);
            let amount = damage
                * protection
                * defensive
                * if class == "unarmored" || class == "parachuting" {
                    b.armor
                } else {
                    1.
                }
                * factor(w, class)
                * cover
                * aboard.map_or(1., |(_, e)| e)
                * if direct {
                    1.
                } else {
                    1. - 0.5 * (distance / radius.max(1.)).min(1.)
                };
            let actual = amount.min(b.hp);
            if protection < 1. && actual > 0. {
                self.metrics.insert("supply_network".into());
            }
            self.base.body_mut(id).unwrap().hp = (b.hp - amount).max(0.);
            if actual>0.{self.body_pressure.insert(id,self.frame()+20);}
            hits.push(json!({"id":id,"damage":actual,"hp":(b.hp-amount).max(0.),"killed":amount>=b.hp,"armor_class":class,"aboard":aboard.is_some()}));
            if side == 0 && actual > 0. {
                if w.family_id == "aa_cannon" {
                    self.metrics.insert("aa_turret_hit".into());
                }
                self.metrics.insert(format!("hit:{}", w.family_id));
                self.metrics.insert(format!("hit_class:{class}"));
                if w.family_id == "rocket" && matches!(class, "light_armor" | "heavy_armor") {
                    self.metrics.insert("rocket_armor".into());
                }
                if [
                    "rifle",
                    "carbine",
                    "pistol",
                    "lmg",
                    "sniper",
                    "smg",
                    "dmr",
                    "heavy_sniper",
                ]
                .contains(&w.family_id)
                {
                    self.metrics.insert("light_hit".into());
                    if matches!(class, "helicopter" | "aircraft") {
                        self.metrics.insert("light_air".into());
                    }
                    if class == "parachuting" {
                        self.metrics.insert("light_para".into());
                    }
                }
                if w.family_id == "howitzer" {
                    self.metrics.insert("spg_hit".into());
                }
                if w.family_id == "aa_cannon" {
                    self.metrics.insert("aa_turret_hit".into());
                }
            }
        }
        for i in 0..self.vehicles.len() {
            let v = &self.vehicles[i];
            if !v.active
                || v.hp <= 0.
                || self.base.companies[v.company].side == side
                || direct && info.target != Some(v.id)
                || (!direct && v.p.dist(p) > radius + 3.)
            {
                continue;
            }
            let shield = if self.effects.iter().any(|e| {
                e.kind == "supply_network"
                    && e.side == self.base.companies[v.company].side
                    && e.end > self.frame()
                    && e.p.dist(v.p) < e.radius
            }) {
                0.9
            } else {
                1.
            };
            let amount = damage
                * vehicles::spec(self.base.companies[v.company].unit.id)
                    .unwrap()
                    .armor
                * shield
                * factor(w, v.armor_class)
                * if direct {
                    1.
                } else {
                    1. - 0.5 * (v.p.dist(p) / radius.max(1.)).min(1.)
                };
            let actual = amount.min(v.hp);
            let id = v.id;let vclass=v.armor_class;
            self.hurt_vehicle(i, amount);
            hits.push(json!({"id":id,"damage":actual,"vehicle":true,"armor_class":vclass}));
            if side == 0 && actual > 0. {
                self.metrics.insert(format!("hit:{}",w.family_id));
                if w.family_id=="aa_cannon"{self.metrics.insert("aa_turret_hit".into());}
                if ["rifle","carbine","pistol","lmg","sniper","smg","dmr","heavy_sniper"].contains(&w.family_id)&&vclass=="helicopter"{self.metrics.insert("light_air".into());}
                if w.family_id == "rocket" {
                    self.metrics.insert("rocket_armor".into());
                }
                if w.family_id == "howitzer" {
                    self.metrics.insert("spg_hit".into());
                }
            }
        }
        if !direct || info.target.is_none() {
            for b in &mut self.base.base.core.ground.buildings {
                if b.ally != (side == 0) && b.hp > 0. && b.p.dist(p) < radius.max(12.) + 60. {
                    let amount = damage
                        * if w.family_id == "demolition_charge" {
                            2.8
                        } else {
                            factor(w, "light_armor")
                        };
                    b.hp = (b.hp - amount).max(0.);
                    if side == 0 && amount > 0. {
                        self.metrics.insert(format!("hit:{}", w.family_id));
                        if w.family_id == "howitzer" {
                            self.metrics.insert("spg_hit".into());
                        }
                        if [
                            "rifle",
                            "carbine",
                            "pistol",
                            "lmg",
                            "sniper",
                            "smg",
                            "dmr",
                            "heavy_sniper",
                        ]
                        .contains(&w.family_id)
                        {
                            self.metrics.insert("light_hit".into());
                        }
                    }
                }
            }
        }
        let frame = self.frame();
        let impact_id = self.base.base.core.ground.impacts.len();
        bounded(
            &mut self.base.base.core.ground.impacts,
            json!({"id":format!("v3-hit-{frame}-{impact_id}"),"tick":frame as f64/10.,"frame":frame,"x":p.x,"y":p.y,"kind":kind,"weapon_id":w.id,"weapon_family_id":w.family_id,"source":source,"operator_id":info.operator,"target_armor_class":info.target_class,"damage":damage,"radius":radius,"blast_radius_m":w.blast_radius_m,"hits":hits.len(),"affected_bodies":hits,"equipment_version":EQUIPMENT}),
        );
    }
    fn passenger_damage(
        &mut self,
        p: P,
        damage: f64,
        radius: f64,
        side: u32,
        w: Option<&Weapon>,
        source: &str,
    ) {
        let mut hits = vec![];
        let ids = self
            .base
            .transit
            .iter()
            .filter(|t| {
                self.base.companies[t.company].side != side
                    && !matches!(t.phase, "lost" | "recovered")
            })
            .filter_map(|t| {
                self.base
                    .body(t.id)
                    .filter(|b| b.active && b.hp > 0. && b.p.dist(p) <= radius + 20.)
                    .map(|_| {
                        (
                            t.passengers.clone(),
                            if self.kayaks.contains(&t.company) {
                                1.
                            } else {
                                exposure(t.vehicle.kind)
                            },
                            self.incoming_scale(self.base.companies[t.company].side,self.base.body(t.id).unwrap().p),
                        )
                    })
            })
            .collect::<Vec<_>>();
        for (ids, exposed, protection) in ids {
            if exposed <= 0. {
                continue;
            }
            for id in ids {
                if let Some(b) = self.base.body_mut(id) {
                    if b.hp <= 0. || b.active {
                        continue;
                    }
                    let actual =
                        (damage * exposed * protection * w.map_or(1., |w| factor(w, "unarmored"))).min(b.hp);
                    b.hp -= actual;
                    hits.push(
                        json!({"id":id,"damage":actual,"hp":b.hp,"killed":b.hp<=0.,"aboard":true}),
                    );
                }
            }
        }
        if !hits.is_empty() {
            let frame = self.frame();
            if side == 1 {
                self.metrics.insert("passenger_exposed".into());
            }
            let impact_index = self.base.base.core.ground.impacts.len();
            bounded(
                &mut self.base.base.core.ground.impacts,
                json!({"id":format!("v3-passenger-{frame}-{impact_index}"),"tick":frame as f64/10.,"frame":frame,"kind":"passenger_hit","source":source,"x":p.x,"y":p.y,"radius":radius,"affected_bodies":hits}),
            );
        }
    }
    fn target_position(&self, id: u32) -> Option<P> {
        if id >= 1_000_000_000 {
            return self
                .base
                .base
                .core
                .aircraft
                .iter()
                .find(|a| a.id == id - 1_000_000_000 && a.hp > 0.)
                .map(|a| a.p);
        }
        if let Some(v) = self
            .vehicles
            .iter()
            .find(|v| v.id == id && v.active && v.hp > 0.)
        {
            return Some(v.p);
        }
        self.base.body(id).filter(|b| b.hp > 0.).map(|b| {
            self.passenger(id)
                .and_then(|(t, _)| self.base.body(t.id))
                .map_or(b.p, |t| t.p)
        })
    }
    fn target_velocity(&self, id: u32) -> P {
        if id >= 1_000_000_000 {
            return self
                .base
                .base
                .core
                .aircraft
                .iter()
                .find(|a| a.id == id - 1_000_000_000)
                .map_or(P::default(), |a| P::bearing(a.heading) * a.speed);
        }
        if let Some(v) = self.vehicle_at(id) {
            return v.velocity;
        }
        if let Some((t, _)) = self.passenger(id) {
            return P::bearing(t.heading) * t.vehicle.speed;
        }
        self.base
            .actors
            .iter()
            .find(|a| a.id == id)
            .map_or(P::default(), |a| a.velocity)
    }
    fn projectiles(&mut self) {
        let guided = self
            .shots
            .iter()
            .filter_map(|(id, info)| {
                (info.weapon.family_id == "aa_missile")
                    .then(|| {
                        info.target
                            .and_then(|target| self.target_position(target))
                            .map(|p| (*id, p + info.tracking_offset))
                    })
                    .flatten()
            })
            .collect::<BTreeMap<_, _>>();
        let mut impacts = vec![];
        for s in &mut self.base.base.core.ground.projectiles {
            if let Some(goal) = guided.get(&s.id) {
                s.goal = *goal;
            }
            let d = s.p.dist(s.goal);
            if d <= s.speed * DT {
                s.p = s.goal;
                impacts.push(s.clone());
            } else {
                s.p = s.p + (s.goal - s.p) * (s.speed * DT / d);
            }
        }
        self.base
            .base
            .core
            .ground
            .projectiles
            .retain(|s| s.p.dist(s.goal) > 0.01);
        for s in impacts {
            let info = self.shots.remove(&s.id);
            let impulse = self.base.shells.get(&s.id).map_or(0., |m| m.impulse);
            let point = info
                .as_ref()
                .filter(|i| i.hit && !accuracy::indirect(i.weapon))
                .and_then(|i| i.target.and_then(|id| self.target_position(id)))
                .unwrap_or(s.goal);
            self.resolve(
                point,
                s.damage,
                s.radius,
                if s.ally { 0 } else { 1 },
                info.as_ref(),
                s.kind,
                &s.source,
                s.air_only,
                impulse,
            );
        }
        let mut impacts = vec![];
        for s in &mut self.base.base.shots {
            let d = s.p.dist(s.goal);
            if d <= s.speed * DT {
                s.p = s.goal;
                impacts.push(s.clone());
            } else {
                s.p = s.p + (s.goal - s.p) * (s.speed * DT / d);
            }
        }
        self.base.base.shots.retain(|s| s.p.dist(s.goal) > 0.01);
        for s in impacts {
            if s.kind == "anti_ship" {
                for ship in &mut self.base.base.core.naval.ships {
                    if ship.side != if s.ally { 0 } else { 1 }
                        && ship.alive()
                        && ship.p.dist(s.goal)
                            <= s.radius
                                + self.base.base.core.naval.data.ships[ship.def].length_m / 2.
                    {
                        let armor = self.base.base.core.naval.data.ships[ship.def].armor_belt;
                        ship.hp =
                            (ship.hp - s.damage * (1. / (1. + armor * 0.1)).max(0.22)).max(0.);
                    }
                }
            } else {
                self.resolve(
                    s.goal,
                    s.damage,
                    s.radius,
                    if s.ally { 0 } else { 1 },
                    None,
                    s.kind,
                    &s.source,
                    s.kind == "air_defense",
                    if matches!(s.kind, "mortar" | "cannon") {
                        65.
                    } else {
                        0.
                    },
                );
            }
        }
    }
    fn shore(&mut self) {
        // Surface gunfire cannot deliberately track an airborne helicopter.
        let airborne = self
            .base
            .actors
            .iter()
            .filter_map(|a| {
                self.base
                    .body(a.id)
                    .filter(|b| b.air && b.hp > 0.)
                    .map(|b| b.p)
            })
            .collect::<Vec<_>>();
        self.base
            .base
            .core
            .shore
            .retain(|o| !airborne.iter().any(|p| p.dist(o.target) < 80.));
        let existing = self
            .base
            .base
            .core
            .ground
            .projectiles
            .iter()
            .map(|s| s.id)
            .collect::<BTreeSet<_>>();
        self.base.shore();
        let frame = self.frame();
        let ids = self
            .base
            .base
            .core
            .ground
            .projectiles
            .iter()
            .filter(|s| !existing.contains(&s.id) && s.kind == "naval")
            .map(|s| (s.id, s.goal, if s.ally { 0 } else { 1 }))
            .collect::<Vec<_>>();
        for (id, aim, side) in ids {
            let spread = self.spread_scale(side, aim, true);
            let target = aim
                + P::bearing(((id.wrapping_mul(73) + frame.wrapping_mul(37)) % 360) as f64)
                    * 110.
                    * spread;
            if let Some(s) = self
                .base
                .base
                .core
                .ground
                .projectiles
                .iter_mut()
                .find(|s| s.id == id)
            {
                s.goal = target;
            }
            if let Some(meta) = self.base.shells.get_mut(&id) {
                meta.goal = target;
                meta.flight = meta.origin.dist(target) / 900.;
            }
            if let Some(row) = self
                .base
                .base
                .core
                .ground
                .shots
                .iter_mut()
                .find(|r| r["id"].as_u64() == Some(id as u64))
            {
                row["target_x"] = json!(target.x);
                row["target_y"] = json!(target.y);
                row["impact_point"] = json!(target);
                row["aim_point"] = json!(aim);
                row["spread_multiplier"] = json!(spread);
            }
            if side == 0
                && self.effects.iter().any(|e| {
                    e.kind == "support_designation"
                        && e.side == side
                        && e.end > self.frame()
                        && e.p.dist(aim) < e.radius
                })
            {
                self.metrics.insert("support_designation".into());
            }
        }
    }
    fn resume_stragglers(&mut self) {
        for ci in 0..self.base.companies.len() {
            let c = &self.base.companies[ci];
            if matches!(c.stage,"withdrawing"|"returning")&&c.bodies.iter().all(|id|self.base.body(*id).is_none_or(|b|b.hp<=0.)||self.base.actors.iter().any(|a|a.id==*id&&a.phase=="recovered")){self.base.companies[ci].stage="recovered";continue;}
            if c.stage=="active"&&c.order=="extract" {
                if let Ok((_,land))=self.base.base.geometry.beach(c.beach){
                    self.base.companies[ci].stage="withdrawing";
                    self.base.companies[ci].goal=land;
                    self.base.companies[ci].path=vec![land];
                }
            }
            let c=&self.base.companies[ci];
            if c.stage == "returning"
                && !matches!(c.unit.class, "air" | "amphibious")
                && c.bodies.iter().any(|id| {
                    self.base.body(*id).is_some_and(|b| b.active && b.hp > 0.)
                        && self
                            .base
                            .actors
                            .iter()
                            .any(|a| a.id == *id && !matches!(a.phase, "returning" | "recovered"))
                })
            {
                self.base.companies[ci].stage = "withdrawing";
            }
        }
        if self.frame() % 40 == 0 {
            for ci in 0..self.base.companies.len() {
                let c = self.base.companies[ci].clone();
                if c.stage != "withdrawing" {
                    continue;
                }
                let positions = c
                    .bodies
                    .iter()
                    .filter_map(|id| {
                        self.base
                            .body(*id)
                            .filter(|b| b.active && b.hp > 0.)
                            .map(|b| b.p)
                    })
                    .collect::<Vec<_>>();
                if positions.is_empty() {
                    continue;
                }
                let center = positions.iter().fold(P::default(), |a, p| a + *p)
                    * (1. / positions.len() as f64);
                if let Ok(path) = self.precise_route(center,c.goal,c.unit.class,false) {
                    self.base.companies[ci].path = path;
                    for a in self.base.actors.iter_mut().filter(|a| a.company == ci) {
                        a.last_waypoint = None;
                    }
                }
            }
        }
    }
    fn move_transports(&mut self) {
        let frame = self.frame();
        let mut extra = vec![];
        for i in 0..self.base.transit.len() {
            let t = self.base.transit[i].clone();
            if !self.kayaks.contains(&t.company) || matches!(t.phase, "recovered" | "lost") {
                continue;
            }
            let id = t.id;
            let rest = t
                .passengers
                .chunks(2)
                .map(|x| x.to_vec())
                .collect::<Vec<_>>();
            self.base.transit[i].vehicle = kayak();
            if let Some(b) = self.base.body_mut(id) {
                let ratio = b.hp / b.max;
                b.max = 110.;
                b.hp = 110. * ratio;
                b.armor = 1.;
            }
            if rest.len() > 1 {
                self.base.transit[i].passengers = rest[0].clone();
                for passengers in rest.into_iter().skip(1) {
                    let mut n = t.clone();
                    n.id = self.base.base.core.ground.id();
                    n.passengers = passengers;
                    n.vehicle = kayak();
                    let mut b = self.base.body(id).unwrap().clone();
                    b.id = n.id;
                    extra.push((n, b));
                }
            }
        }
        for (t, b) in extra {
            self.base.transit.push(t);
            self.base.base.core.ground.bodies.push(b);
        }
        let mut held = vec![];
        for i in 0..self.base.transit.len() {
            let t = self.base.transit[i].clone();
            if t.returning || t.passengers.is_empty() || matches!(t.phase, "recovered" | "lost") {
                continue;
            }
            let Some(b) = self.base.body(t.id).cloned() else {
                continue;
            };
            if b.hp <= 0. {
                continue;
            }
            let duration = if self.kayaks.contains(&t.company) {
                5
            } else if t.vehicle.air {
                0
            } else if t.vehicle.kind == "heavy_lander" {
                35
            } else if t.vehicle.kind == "armored_boat" {
                20
            } else {
                15
            };
            if duration > 0 && b.p.dist(t.goal) <= t.vehicle.speed * DT + 25. {
                let end = *self.unloading.entry(t.id).or_insert(frame + duration);
                if frame < end {
                    held.push((i, t.goal, t.vehicle.speed));
                    self.base.transit[i].goal = b.p + P { x: 100., y: 0. };
                    self.base.transit[i].vehicle.speed = 0.;
                }
            }
        }
        self.base.move_transports();
        for t in &mut self.base.transit {
            if t.phase == "lost" {
                t.passengers.clear();
            }
        }
        for (i, goal, speed) in held {
            self.base.transit[i].goal = goal;
            self.base.transit[i].vehicle.speed = speed;
        }
    }
    fn advance(&mut self) {
        if self.base.result.is_some() {
            return;
        }
        let health_before=self.base.actors.iter().filter_map(|a|self.base.body(a.id).map(|b|(a.id,b.hp))).collect::<BTreeMap<_,_>>();
        self.base.base.core.ground.frame += 1;
        self.base.base.anchorage();
        if self.frame() % 10 == 0 {
            self.base.base.core.naval.advance();
            self.base.base.core.sync_from_naval();
            self.shore();
        }
        // Unloading remains a real timed state; kayak requires five 0.1s frames.
        let _old = self
            .vehicles
            .iter()
            .filter_map(|v| self.base.body(v.operator).map(|b| (v.operator, b.p)))
            .collect::<BTreeMap<_, _>>();
        self.move_transports();
        self.base.advance_knockback();
        // v2 remains frozen: only v3 resumes actual on-land stragglers after
        // another subset of the same company already boarded a return boat.
        self.resume_stragglers();
        self.move_people_with_vehicles();
        self.convert_vehicle_transports();
        self.step_vehicles();
        for (ci, c) in self.base.companies.iter().enumerate() {
            if c.side == 0 && c.stage == "active" {
                self.metrics.insert("landed".into());
                if self.kayaks.contains(&ci) {
                    self.metrics.insert("kayak_landed".into());
                }
                if c.unit.id == "MCP-088"
                    && c.bodies.iter().all(|id| {
                        self.base
                            .actors
                            .iter()
                            .find(|a| a.id == *id)
                            .is_none_or(|a| a.phase != "parachuting")
                    })
                {
                    self.metrics.insert("para_landed".into());
                }
            }
        }
        if self.vehicles.iter().any(|v| {
            let c = &self.base.companies[v.company];
            c.side == 0
                && c.unit.id == "MCP-022"
                && v.active
                && v.hp > 0.
                && c.bodies
                    .iter()
                    .all(|id| self.base.body(*id).is_some_and(|b| b.hp > 0. && b.active))
        }) {
            self.metrics.insert("vehicle_infantry".into());
        }
        self.tick_firearms();
        self.tick_roles();
        self.base.observe_visibility();
        self.shoot();
        if self.frame() % 10 == 0 {
            self.base.tower_step();
        }
        self.projectiles();
        let shield=self.begin_legacy_protection();
        self.base.mines();
        self.end_legacy_protection(shield);
        self.import_vehicle_damage();
        if self.base.base.core.carrier_is_v3(){self.base.base.core.carrier_v3_observe_land(self.view());}
        self.advance_air_v3();
        self.import_vehicle_damage();
        for (id,hp) in health_before {
            if let Some(b)=self.base.body(id){if b.hp<hp {
                let protected=b.ally&&self.incoming_scale(0,b.p)<1.;
                self.body_pressure.insert(id,self.frame()+20);
                if protected{self.metrics.insert("supply_network".into());}
            }}
        }
        self.base.base.core.sync_to_naval();
        self.base.base.core.record_corpses();
        for (id, l) in &self.loadouts {
            if let Some(b) = self.base.body_mut(*id) {
                b.ammo = b.ammo.min(l.weapon.ammo_capacity);
            }
        }
        if self
            .base
            .base
            .core
            .ground
            .buildings
            .iter()
            .any(|b| !b.ally && b.hp <= 0. && spec(&b.kind).is_some_and(|s| s.damage > 0.))
        {
            self.metrics.insert("shore_cleared".into());
        }
        let prior = self.base.captured;
        let warehouses = self.base.warehouse_capture.clone();
        self.base.captures();
        if self.frame() % 4 == 0 {
            let boosted = |position: P| {
                self.base.companies.iter().any(|c| {
                    c.side == self.base.attack()
                        && c.p.dist(position) < 270.
                        && self.effects.iter().any(|e| {
                            e.kind == "command_network"
                                && e.side == c.side
                                && e.end > self.frame()
                                && e.p.dist(c.p) < e.radius
                        })
                })
            };
            let hq = self
                .base
                .base
                .core
                .ground
                .buildings
                .iter()
                .find(|b| b.kind == "hq")
                .unwrap()
                .p;
            let hq_extra = self.base.captured > prior && boosted(hq);
            let extra = warehouses
                .iter()
                .enumerate()
                .filter_map(|(i, p)| {
                    let position = self.base.base.core.ground.buildings
                        [self.base.base.warehouses[i].building]
                        .p;
                    (self.base.warehouse_capture[i] > *p && boosted(position)).then_some(i)
                })
                .collect::<Vec<_>>();
            if hq_extra {
                self.base.captured = (self.base.captured + 1).min(100);
                self.metrics.insert("command_network".into());
            }
            for i in extra {
                self.base.warehouse_capture[i] = (self.base.warehouse_capture[i] + 1).min(60);
                self.metrics.insert("command_network".into());
            }
        }

        if self.base.result.is_none() {
            let charges = self
                .base
                .companies
                .iter()
                .map(|c| c.charges)
                .collect::<Vec<_>>();
            for c in &mut self.base.companies {
                if matches!(
                    c.unit.ability,
                    "command_network"
                        | "grenade"
                        | "deploy_aa_turret"
                        | "support_designation"
                        | "at_missile"
                        | "barrage"
                        | "air_rockets"
                        | "demolition"
                        | "supply_network"
                ) {
                    c.charges = 0;
                }
            }
            self.refill_recovered_air();
            self.base_ai_v3(&charges);
            for (i, c) in self.base.companies.iter_mut().enumerate() {
                if matches!(
                    c.unit.ability,
                    "command_network"
                        | "grenade"
                        | "deploy_aa_turret"
                        | "support_designation"
                        | "at_missile"
                        | "barrage"
                        | "air_rockets"
                        | "demolition"
                        | "supply_network"
                ) {
                    c.charges = charges[i];
                }
            }
            self.roles_ai();
        }
        if self
            .base
            .result
            .as_ref()
            .is_some_and(|r| r["success"] == true)
            && self.vehicles.iter().any(|v| {
                self.base.companies[v.company].side == 0 && v.hp > 0. && !self.vehicle_safe(v)
            })
        {
            if self.frame()>=LIMIT {self.base.finish(false,false);}else{self.base.result = None;}
        }
        self.normalize_result();
    }
    fn normalize_result(&mut self) {
        let vehicles = self.vehicle_outcomes();
        if let Some(r) = &mut self.base.result {
            r["version"] = json!(VERSION);
            r["island_war"]["version"] = json!(VERSION);
            r["equipment_version"] = json!(EQUIPMENT);
            r["island_war"]["vehicles"] = vehicles.clone();
            r["vehicles"] = vehicles;
        }
    }
    pub(crate) fn execute(&mut self, q: &Value) -> E<Value> {
        if q["op"]=="littoral_ability_preview" {
            let r=self.base.company_index(q,0).and_then(|ci|{
                let p=if q.get("x").is_some(){super::Battle::position(q)?}else{self.base.companies[ci].p};
                self.validate_role_skill(ci,p)
            });
            return Ok(match r{Ok(())=>json!({"valid":true,"reason":""}),Err(reason)=>json!({"valid":false,"reason":reason})});
        }
        if self.base.base.core.carrier_is_v3(){self.base.base.core.carrier_v3_observe_land(self.view());}
        if q["op"] == "littoral_support" && q["kind"] == "helicopter" {
            return Err("新版武直支援必须指挥本连真实载具，不能另生支援平台".into());
        }
        if q["op"] == "littoral_vehicle_preview" {
            return Ok(self.vehicle_preview(q));
        }
        if q["op"] == "littoral_vehicle_order" {
            self.vehicle_order(q, 0)?;
            self.base.auto = false;
            self.base.commands.push(Command {
                frame: self.frame(),
                request: q.clone(),
            });
            return Ok(self.view());
        }
        if q["op"] == "littoral_order"
            && matches!(q["action"].as_str(), Some("hold" | "stop"))
        {
            if self.base.result.is_some() { return Err("行动已结束".into()); }
            let ci = self.base.company_index(q, 0)?;
            let c = &mut self.base.companies[ci];
            if !matches!(c.stage,"active"|"ground") {
                return Err("行动连尚未抵达战区".into());
            }
            // Holding requires no route from the arithmetic company center:
            // that center can lie inside an obstacle between legal bodies.
            // Each body keeps her actual position rather than reforming.
            c.path.clear();
            c.goal=c.p;
            c.order="hold".into();
            for a in self.base.actors.iter_mut().filter(|a|a.company==ci) {
                a.velocity=P::default();
                a.last_waypoint=None;
            }
            self.base.auto=false;
            self.base.commands.push(Command{frame:self.frame(),request:q.clone()});
            return Ok(self.view());
        }
        if q["op"] == "littoral_ability" {
            let ci = self.base.company_index(q, 0)?;
            if matches!(
                self.base.companies[ci].unit.ability,
                "command_network"
                    | "grenade"
                    | "deploy_aa_turret"
                    | "support_designation"
                    | "at_missile"
                    | "barrage"
                    | "air_rockets"
                    | "demolition"
                    | "supply_network"
            ) {
                if self.base.result.is_some() {
                    return Err("行动已结束".into());
                }
                let p = if q.get("x").is_some() {
                    super::Battle::position(q)?
                } else {
                    self.base.companies[ci].p
                };
                self.role_skill(ci, p)?;
                self.base.auto = false;
                self.base.commands.push(Command {
                    frame: self.frame(),
                    request: q.clone(),
                });
                return Ok(self.view());
            }
        }
        match q["op"].as_str().ok_or("缺少操作")? {
            "observe" => Ok(self.view()),
            "save" => Ok(json!(self.save())),
            "step" => {
                let n = frames(&q["seconds"])?;
                for _ in 0..n {
                    if self.base.result.is_some() {
                        break;
                    }
                    self.advance();
                }
                Ok(self.view())
            }
            "report" => {
                Ok(json!({"result":self.view()["result"],"littoral":self.view()["littoral"]}))
            }
            "presentation" => self.base.execute(q),
            "littoral_preview"
            | "carrier_preview"
            | "carrier_mission_preview"
            | "preview_route"
            | "preview_reform"
            | "aim"
            | "illumination_preview" => self.base.execute(q),
            _ => {
                let mut translated = q.clone();
                if matches!(
                    q["op"].as_str(),
                    Some("island_autonomy" | "littoral_autonomy")
                ) {
                    if q.get("version").is_some() && q["version"] != VERSION {
                        return Err("请选择显式v3托管规则".into());
                    }
                    translated["version"] = json!(super::VERSION);
                }
                self.base.order(&translated, true)?;
                if self.base.base.core.carrier_is_v3(){self.base.base.core.carrier_v3_observe_land(self.view());}
                self.convert_vehicle_transports();
                if let Some(last) = self.base.commands.last_mut() {
                    last.request = q.clone();
                }
                self.normalize_result();
                Ok(self.view())
            }
        }
    }
    pub(crate) fn save(&self) -> Saved {
        Saved {
            version: VERSION.into(),
            seed: self.base.base.core.ground.seed,
            config: self.config.clone(),
            frame: self.frame(),
            tick: self.frame() as f64 / 10.,
            commands: self.base.commands.clone(),
        }
    }
    fn validate_save(s: &Saved) -> E<()> {
        if s.version != VERSION
            || s.frame > LIMIT
            || !s.tick.is_finite()
            || (s.tick - s.frame as f64 / 10.).abs() > 1e-6
            || s.commands.len() > 15000
            || s.commands.iter().any(|c| c.frame > s.frame)
            || s.commands.windows(2).any(|a| a[0].frame > a[1].frame)
        {
            return Err("v3录像版本、时钟或日志无效".into());
        }
        Ok(())
    }
    fn replay_to(&mut self, commands: &[Command], cursor: &mut usize, end: u32) -> E<()> {
        loop {
            while *cursor < commands.len()
                && commands[*cursor].frame == self.frame()
                && commands[*cursor].frame <= end
            {
                self.execute(&commands[*cursor].request)?;
                *cursor += 1;
            }
            if self.frame() >= end {
                break;
            }
            if self.base.result.is_some() {
                return Err("不能重演真实终局之后".into());
            }
            self.advance();
        }
        Ok(())
    }
    pub(crate) fn from_save(s: Saved, target: Option<u32>) -> E<Self> {
        Self::validate_save(&s)?;
        let end = target.unwrap_or(s.frame);
        if end > s.frame {
            return Err("不能重演未来时刻".into());
        }
        let mut b = Self::new(s.seed, s.config)?;
        let mut cursor = 0;
        b.replay_to(&s.commands, &mut cursor, end)?;
        Ok(b)
    }
    fn training(&self) -> Value {
        let Some(lesson) = &self.lesson else {
            return Value::Null;
        };
        let recovered = self.base.all_recovered(0);
        let requirements: Vec<(&str, &str, &str, &str, bool)> = match lesson.as_str() {
            "combined_arms" => vec![
                (
                    "vehicle_infantry",
                    "坦克与步兵真实协同",
                    "固定重艇将1辆坦克与原6名步枪身体送抵陆地",
                    "MCP-022",
                    self.metrics.contains("vehicle_infantry"),
                ),
                (
                    "disembark",
                    "身体真实下车",
                    "选中103/087/027/006连，将卸载卡拖至合法陆地",
                    "MCP-103",
                    self.metrics.contains("vehicle_disembarked"),
                ),
                (
                    "embark",
                    "身体真实接近登载",
                    "将本连身体卡拖到本连载具，身体实际走到后进入",
                    "MCP-103",
                    self.metrics.contains("vehicle_embarked"),
                ),
                (
                    "independent_fire",
                    "车人与各自武器开火",
                    "车炮和地面人员分别发射真实有限弹药",
                    "MCP-022",
                    self.metrics.contains("vehicle_fired") && self.metrics.contains("body_fired"),
                ),
                (
                    "recover",
                    "车人与人员真实回收",
                    "完成目标后回收所有存活身体与车机",
                    "",
                    recovered
                        && self
                            .vehicles
                            .iter()
                            .filter(|v| self.base.companies[v.company].side == 0 && v.hp > 0.)
                            .all(|v| self.vehicle_safe(v)),
                ),
            ],
            "roles" => vec![
                (
                    "demolition_charge",
                    "工兵实际爆破工事",
                    "先接近180米内，再向敌方工事投放有限炸药",
                    "MCP-009",
                    self.metrics.contains("hit:demolition_charge"),
                ),
                (
                    "supply_network",
                    "保障增益实际消费",
                    "在友军附近开启保障网，让友军实际换弹或承伤消费增益",
                    "MCP-116",
                    self.metrics.contains("supply_network"),
                ),
                (
                    "command_network",
                    "指挥网络真实生效",
                    "使友军实际移动、射击或执行任务时消费增益",
                    "MCP-203",
                    self.metrics.contains("command_network"),
                ),
                (
                    "grenade",
                    "手雷实际命中",
                    "贴近发挥霰弹/SMG优势，再投有限手雷",
                    "MCP-184",
                    self.metrics.contains("hit:grenade"),
                ),
                (
                    "deploy_aa_turret",
                    "炮台实际对空",
                    "部署防空炮台并真实命中空中目标",
                    "MCP-145",
                    self.metrics.contains("aa_turret_hit"),
                ),
                (
                    "support_designation",
                    "标记实际影响炮援",
                    "标记目标后让舰炮或航空实际发射并缩小散布",
                    "MCP-128",
                    self.metrics.contains("support_designation"),
                ),
            ],
            "landing" => vec![
                (
                    "kayak",
                    "皮划艇实际登陆",
                    "将步兵卡拖到合法滩头；清除岸防后再接近",
                    "MCP-011",
                    self.metrics.contains("kayak_landed"),
                ),
                (
                    "shore",
                    "清除真实岸防",
                    "舰炮或部队摧毁至少一处有火力的岸防",
                    "",
                    self.metrics.contains("shore_cleared"),
                ),
                (
                    "recover",
                    "人员真实回收",
                    "完成目标后撤回实际存活身体",
                    "",
                    recovered && self.metrics.contains("landed"),
                ),
            ],
            "artillery" => vec![
                (
                    "spg",
                    "自行炮真实命中",
                    "展开炮车并使其实际命中目标",
                    "MCP-087",
                    self.metrics.contains("spg_hit"),
                ),
                (
                    "escort",
                    "手枪人员实际部署",
                    "自行炮与原有手枪身体独立协同，可真实上下车",
                    "MCP-087",
                    self.base
                        .companies
                        .iter()
                        .any(|c| c.side == 0 && c.unit.id == "MCP-087" && c.stage != "embarked"),
                ),
                (
                    "recover",
                    "炮队真实回收",
                    "将炮队存活人员撤回载舰",
                    "MCP-087",
                    recovered && self.metrics.contains("landed"),
                ),
            ],
            "airborne" => vec![
                (
                    "air",
                    "轻武器实际对空",
                    "步枪可攻击武直，但实际伤害显著衰减",
                    "",
                    self.metrics.contains("light_air"),
                ),
                (
                    "para",
                    "伞兵真实投送",
                    "让伞兵实际抵达并完成下降；下降时不能还击",
                    "MCP-088",
                    self.metrics.contains("para_landed"),
                ),
            ],
            _ => vec![
                (
                    "light",
                    "轻武器实际命中",
                    "用普通步兵射击未装甲目标",
                    "",
                    self.metrics.contains("light_hit"),
                ),
                (
                    "antiarmor",
                    "单火箭手实际破甲",
                    "每连只有一名火箭筒手；让她命中装甲目标",
                    "MCP-063",
                    self.metrics.contains("rocket_armor"),
                ),
            ],
        };
        let complete = requirements.iter().all(|r| r.4);
        json!({"lesson":lesson,"checks":requirements.into_iter().map(|(id,label,instruction,unit_id,done)|json!({"id":id,"label":label,"instruction":instruction,"unit_id":unit_id,"done":done})).collect::<Vec<_>>(),"complete":complete,"preparation_remaining_s":self.config["training_delay_seconds"].as_u64().unwrap_or(0).saturating_sub(self.frame()as u64/10),"evidence":self.metrics,"source":"actual_simulation_events"})
    }
    pub(crate) fn view(&self) -> Value {
        let mut v = self.base.view();
        v["version"] = json!(VERSION);
        v["island_war"]["version"] = json!(VERSION);
        v["island_war"]["replay"]["version"] = json!(VERSION);
        v["littoral"]["autonomy"]["version"] = json!(VERSION);
        v["littoral"]["land"]["equipment_version"] = json!(EQUIPMENT);
        v["littoral"]["training"] = self.training();
        let frame = self.frame();
        for a in &self.base.actors {
            if self.seated(a.id) {
                let b = self.base.body(a.id).unwrap();
                let c = &self.base.companies[a.company];
                v["littoral"]["land"]["entities"].as_array_mut().unwrap().push(json!({"id":a.id,"unit_id":c.unit.id,"company_id":c.id,"side":if c.side==0{"allies"}else{"axis"},"x":b.p.x,"y":b.p.y,"hp":b.hp,"max_hp":b.max,"ammo":b.ammo,"phase":"in_vehicle","physical_class":"infantry","air":false,"visible":c.side==0,"art_version":"tactical-art-v2"}));
            }
        }
        for row in v["littoral"]["land"]["entities"].as_array_mut().unwrap() {
            if let Some(id) = row["id"].as_u64() {
                if let Some(l) = self.loadouts.get(&(id as u32)) {
                    row["weapon_id"] = json!(l.weapon.id);
                    row["weapon_family_id"] = json!(l.weapon.family_id);
                    let body = self.base.body(id as u32).unwrap();
                    row.as_object_mut().unwrap().extend(
                        self.firearm_view(id as u32, l.weapon, body.ammo, body.next)
                            .as_object()
                            .unwrap()
                            .clone(),
                    );
                    row["weapon"] = accuracy::compact(l.weapon);
                    row["specialist"] = json!(l.specialist);
                    if let Some((vehicle,state,goal))=self.tank_tactics.get(&(id as u32)){
                        row["cover_vehicle_id"]=json!(vehicle);row["tactical_state"]=json!(state);row["tactical_goal"]=json!(goal);
                    }
                    row["equipment_version"] = json!(EQUIPMENT);
                    row["armor_class"] = json!(self.target_class(id as u32));
                    row["seated"] = json!(self.seated(id as u32));
                    row["render_as_infantry"] = json!(!self.seated(id as u32));
                    row["in_vehicle"] = json!(self
                        .vehicles
                        .iter()
                        .find(|v| v.passengers.contains(&(id as u32)) && v.active && v.hp > 0.)
                        .map(|v| v.id));
                }
            }
        }
        let vehicles = self.vehicles_view();
        v["littoral"]["land"]["entities"]
            .as_array_mut()
            .unwrap()
            .extend(vehicles.clone());
        v["littoral"]["land"]["combat_vehicles"] = json!(vehicles);
        for row in v["littoral"]["groups"].as_array_mut().unwrap() {
            if let Some(ci) = self.base.companies.iter().position(|c| row["id"] == c.id) {
                let c = &self.base.companies[ci];
                row["ammo_capacity"] = json!(c
                    .bodies
                    .iter()
                    .map(|id| self.loadouts[id].weapon.ammo_capacity)
                    .sum::<u32>());
                if self.kayaks.contains(&ci) {
                    row["transport_kind"] = json!("kayak");
                }
                if vehicles::spec(c.unit.id).is_some() {
                    row["carrier_requirement"] =
                        json!(if matches!(c.unit.id, "MCP-027" | "MCP-006") {
                            "CV/LHA"
                        } else {
                            "CV/LHA/APV"
                        });
                    row["vehicle_id"] = Value::Null;
                    row["combat_vehicle_count"] = json!(1);
                }
            }
        }
        for row in v["littoral"]["transports"].as_array_mut().unwrap() {
            let id = row["id"].as_u64().unwrap_or(0) as u32;
            if let Some(t) = self.base.transit.iter().find(|t| t.id == id) {
                row["equipment_version"] = json!(EQUIPMENT);
                row["passenger_ids"] = json!(t.passengers);
                row["passengers"] = json!(t
                    .passengers
                    .iter()
                    .filter_map(|id| self.base.body(*id))
                    .map(|b| json!({"id":b.id,"hp":b.hp,"max_hp":b.max,"alive":b.hp>0.}))
                    .collect::<Vec<_>>());
                row["passenger_exposure"] = json!(if self.kayaks.contains(&t.company) {
                    1.
                } else {
                    exposure(t.vehicle.kind)
                });
                if self.kayaks.contains(&t.company) {
                    row["kind"] = json!("kayak");
                    row["vehicle_id"] =
                        json!(format!("{}-kayak", self.base.companies[t.company].unit.id));
                }
            }
        }
        v["island_war"]["landing_transports"] = json!(v["littoral"]["transports"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|t| t["side"] == "axis")
            .collect::<Vec<_>>());
        v["littoral"]["support"]["helicopter"] =
            json!({"available":false,"reason":"通过本连真实独立武直下令"});
        self.roles_view(&mut v);
        v
    }
}
pub(crate) struct Replay {
    key: String,
    source: Saved,
    battle: Battle,
    cursor: usize,
}
impl Replay {
    pub(crate) fn open(s: Saved, end: u32) -> E<Self> {
        Battle::validate_save(&s)?;
        if end > s.frame {
            return Err("不能重演未来时刻".into());
        }
        let key = serde_json::to_string(&s).map_err(|_| "录像编码失败")?;
        let battle = Battle::new(s.seed, s.config.clone())?;
        let mut r = Self {
            key,
            source: s,
            battle,
            cursor: 0,
        };
        r.seek(end)?;
        Ok(r)
    }
    pub(crate) fn matches(&self, s: &Saved) -> bool {
        serde_json::to_string(s).is_ok_and(|v| v == self.key)
    }
    pub(crate) fn seek(&mut self, end: u32) -> E<Value> {
        if end > self.source.frame {
            return Err("不能重演未来时刻".into());
        }
        if end < self.battle.frame() {
            self.battle = Battle::new(self.source.seed, self.source.config.clone())?;
            self.cursor = 0;
        }
        self.battle
            .replay_to(&self.source.commands, &mut self.cursor, end)?;
        Ok(self.battle.view())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn config(roster: &[&str]) -> Value {
        let mut q: Value = serde_json::from_str(include_str!(
            "../artifacts/island-war-v2/core/exercise-terminal.json"
        ))
        .unwrap();
        let mut q = q["initial_request"].take();
        q["roster"] = json!(roster);
        for k in ["op", "seed", "version"] {
            q.as_object_mut().unwrap().remove(k);
        }
        q
    }
    fn battle(roster: &[&str]) -> Battle {
        Battle::new(714, config(roster)).unwrap()
    }
    #[test]
    fn matrix_has_real_counters_and_full_paratrooper_small_arms() {
        let r = weapon("rifle");
        assert!(factor(r, "heavy_armor") < 0.03);
        assert!(factor(r, "aircraft") < 0.02);
        assert!(factor(r, "helicopter") < 0.05);
        assert_eq!(factor(r, "parachuting"), factor(r, "unarmored"));
        assert!(factor(weapon("rocket"), "heavy_armor") > 1.);
        assert!(factor(weapon("aa_missile"), "aircraft") > 1.);
    }
    #[test]
    fn each_at_company_has_one_finite_rocket_and_other_weak_bodies() {
        let b = battle(&["MCP-063"]);
        for c in b.base.companies.iter().filter(|c| c.side == 0) {
            assert_eq!(
                c.bodies
                    .iter()
                    .filter(|id| b.loadouts[id].weapon.family_id == "rocket")
                    .count(),
                1
            );
            assert_eq!(b.base.body(c.bodies[0]).unwrap().ammo, 6);
            assert!(c
                .bodies
                .iter()
                .skip(1)
                .all(|id| b.loadouts[id].weapon.family_id == "carbine"));
        }
    }
    #[test]
    fn artillery_is_three_vehicles_eighteen_pistol_bodies() {
        let b = battle(&["MCP-087"]);
        assert_eq!(b.vehicles.len(), 3);
        let own = b
            .base
            .companies
            .iter()
            .filter(|c| c.side == 0)
            .flat_map(|c| c.bodies.iter())
            .collect::<Vec<_>>();
        assert_eq!(own.len(), 18);
        assert!(own
            .iter()
            .all(|id| b.loadouts[id].weapon.family_id == "pistol"));
        assert!(b.vehicles.iter().all(
            |v| v.hp == 460. && v.ammo == firearms::model("MCP-087", "howitzer").ammo_capacity
        ));
    }
    #[test]
    fn catalogue_retains_sizes_and_single_source_composition() {
        let v = catalogue();
        assert_eq!(v["cards"].as_array().unwrap().len(), 22);
        for c in v["cards"].as_array().unwrap() {
            assert_eq!(
                c["weapon_composition"].as_array().unwrap().len() as u64,
                c["personnel_per_company"].as_u64().unwrap()
            );
        }
        let c = v["cards"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["id"] == "MCP-088")
            .unwrap();
        assert_eq!(c["body_count"], 50);
        let c = v["cards"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["id"] == "MCP-006")
            .unwrap();
        assert_eq!(c["body_count"], 6);
    }
    #[test]
    fn armor_and_medical_have_material_weapon_differences() {
        let a = loadout(unit("MCP-022").unwrap(), 0);
        let s = loadout(unit("MCP-052").unwrap(), 0);
        assert_eq!(a.0, "rifle");
        assert_eq!(s.0, "pistol");
        assert!(
            weapon(vehicles::spec("MCP-022").unwrap().weapon).damage > 10. * weapon(s.0).damage
        );
        assert!(weapon("sniper").range_m > 2. * weapon("rifle").range_m);
        assert!(weapon("sniper").reload_s > 4. * weapon("rifle").reload_s);
    }
    #[test]
    fn kayaking_is_two_people_and_direct_passenger_hp_is_not_boat_hp() {
        let mut c = config(&["MCP-011"]);
        c["company_transports"] = json!([{"id":"MCP-011","kind":"kayak"}]);
        let mut b = Battle::new(714, c).unwrap();
        let ci = 0;
        let company = b.base.companies[ci].clone();
        let pid = company.bodies[0];
        let p = b.base.body(pid).unwrap().p;
        let id = b.base.base.core.ground.id();
        b.base.base.core.ground.bodies.push(Body {
            id,
            group: "test boat".into(),
            ally: true,
            kind: "landing_craft",
            p,
            hp: 110.,
            max: 110.,
            ammo: 0,
            damage: 0.,
            range: 0.,
            reload: 1,
            next: 0,
            armor: 1.,
            air: false,
            active: true,
        });
        b.base.transit.push(Transit {
            id,
            company: ci,
            passengers: vec![pid],
            vehicle: kayak(),
            phase: "inserting",
            goal: p,
            heading: 0.,
            returning: false,
            drop: false,
        });
        let before = b.base.body(pid).unwrap().hp;
        b.passenger_damage(p, 30., 50., 1, None, "shore-mg");
        assert_eq!(b.base.body(pid).unwrap().hp, before - 30.);
        assert_eq!(b.base.body(id).unwrap().hp, 110.);
        assert_eq!(kayak().capacity, 2);
        b.passenger_damage(p, 999., 50., 1, None, "shore-mg");
        assert_eq!(b.base.body(pid).unwrap().hp, 0.);
        b.passenger_damage(p, 999., 50., 1, None, "shore-mg");
        assert_eq!(b.base.body(pid).unwrap().hp, 0.);
    }
    #[test]
    fn empty_vehicle_loss_never_hurts_an_independent_infantry_body() {
        let mut b = battle(&["MCP-087"]);
        b.vehicles[0].active = true;
        let op = b.vehicles[0].operator;
        let count = b.base.actors.len();
        b.hurt_vehicle(0, 9999.);
        assert_eq!(b.vehicles[0].hp, 0.);
        assert!(!b.seated(op));
        assert_eq!(b.base.body(op).unwrap().hp, 100.);
        assert_eq!(count, b.base.actors.len());
        b.hurt_vehicle(0, 9999.);
        assert_eq!(b.base.body(op).unwrap().hp, 100.);
    }
    #[test]
    fn v3_save_keeps_exact_configuration_and_replay_byte_values() {
        let mut b = battle(&["MCP-034", "MCP-063"]);
        b.execute(&json!({"op":"island_autonomy","enabled":true}))
            .unwrap();
        for _ in 0..50 {
            b.advance();
        }
        let saved = b.save();
        assert_eq!(saved.config, config(&["MCP-034", "MCP-063"]));
        assert_eq!(Battle::from_save(saved, None).unwrap().view(), b.view());
    }
    #[test]
    fn manual_exercise_starts_no_autonomy_and_zero_settlement() {
        let mut b = battle(&["MCP-034"]);
        assert!(!b.base.auto);
        b.execute(&json!({"op":"littoral_abandon"})).unwrap();
        let r = b.view()["result"].clone();
        assert_eq!(r["version"], VERSION);
        assert_eq!(r["settle_allowed"], false);
        assert_eq!(r["resources"], json!(Stock::default()));
        assert_eq!(r["units"][0]["initial_count"], 45);
    }
    #[test]
    fn no_shots_from_seated_driver_or_zero_ammunition() {
        let mut b = battle(&["MCP-087"]);
        let op = b.vehicles[0].operator;
        b.vehicles[0].active = true;
        b.base.body_mut(op).unwrap().active = true;
        b.base.body_mut(op).unwrap().next = 0;
        for x in &mut b.base.base.core.ground.bodies {
            x.ammo = 0;
        }
        for v in &mut b.vehicles {
            v.ammo = 0;
        }
        b.shoot();
        assert!(b.shots.is_empty());
    }
}
