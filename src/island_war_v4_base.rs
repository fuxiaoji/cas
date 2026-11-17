//! Opt-in original tactical roles. Never used by published v1/v4 battles.
use super::*;
#[path = "island_war_v4.rs"]
pub(crate) mod v4;
pub(crate) const VERSION: &str = "cas-island-war-v4-base";
const LIMIT: u32 = 12000;
fn v4_geometry(level:u32)->Geometry {
    let step=level.clamp(1,5)-1;
    Geometry{level,center:P{x:14600.,y:13000.},half_width:1600.+600.*step as f64,half_height:2200.+700.*step as f64}
}
fn v4_terrain_view(g:&Geometry,t:&Terrain)->Value {
    let mut v=g.view();v["version"]=json!("tactical-terrain-v4");v["features"]=json!(t.regions);v["height_los"]=json!(true);
    v["elevation_zones"]=json!(t.regions.iter().filter(|r|matches!(r.kind,"highland"|"lowland"|"ramp")).map(|r|json!({"id":r.id,"polygon":r.polygon,"height_m":r.elevation_m,"level":(r.elevation_m/40.) as i32,"cover_multiplier":r.cover_multiplier})).collect::<Vec<_>>());
    v["ramps"]=json!(t.regions.iter().filter(|r|r.kind=="ramp").map(|r|json!({"id":r.id,"polygon":r.polygon,"width":180.,"from_level":0,"to_level":2})).collect::<Vec<_>>());
    v["effect"]=json!("高地真实掩护；多处坡道连通，悬崖阻断移动与直射，公路桥跨河通车");
    v["roads"]=json!([{"id":"main-crossing","points":[g.point(0.14,0.5),g.point(0.57,0.5),g.point(0.88,0.5)],"width":24.}]);v
}
pub(crate) fn home_preview(q:&Value)->E<Value>{
    let level=q["hq_level"].as_u64().filter(|n|(1..=5).contains(n)).ok_or("总部等级须为1–5")? as u32;
    let seed=q.get("seed").and_then(Value::as_u64).filter(|n|*n<=u32::MAX as u64).unwrap_or(1) as u32;
    let g=v4_geometry(level);let t=Terrain::new(&g,seed);let origin=P{x:13880.,y:12460.};let size=120.;
    let point=|cell:&Value|->E<P>{let x=cell["x"].as_i64().ok_or("建设横格无效")?;let y=cell["y"].as_i64().ok_or("建设纵格无效")?;if x.abs()>100||y.abs()>100{return Err("建设格超出范围".into())}Ok(origin+P{x:(x as f64+0.5)*size,y:(y as f64+0.5)*size})};
    let legal=|p:P|inside(&g.polygon(),p)&&(0..8).all(|n|{let p=p+P::bearing(n as f64*45.)*40.;inside(&g.polygon(),p)&&t.speed(p,"infantry")>0.&&t.speed(p,"armor")>0.});
    let mut buildings=vec![];
    for row in q["buildings"].as_array().into_iter().flatten(){let p=point(&row["cell"])?;let mut r=row.clone();r["x"]=json!(p.x);r["y"]=json!(p.y);r["world_position"]=json!(p);r["terrain_buildable"]=json!(legal(p));buildings.push(r);}
    let minx=((g.center.x-g.half_width-origin.x)/size).ceil() as i32;let miny=((g.center.y-g.half_height-origin.y)/size).ceil() as i32;
    let maxx=((g.center.x+g.half_width-origin.x)/size).floor() as i32;let maxy=((g.center.y+g.half_height-origin.y)/size).floor() as i32;
    let mut cells=vec![];for y in miny..maxy{for x in minx..maxx{if legal(origin+P{x:(x as f64+0.5)*size,y:(y as f64+0.5)*size}){cells.push(json!({"x":x,"y":y}));}}}
    let mut result=json!({"island_war":{"version":v4::VERSION,"placement":{"origin":g.point(0.,0.),"width_m":g.half_width*1.5,"height_m":g.half_height*1.5},"width_m":g.half_width*2.,"height_m":g.half_height*2.},"littoral":{"version":"cas-littoral-v4","land":{"bounds":{"x":g.origin().x,"y":g.origin().y,"width":g.half_width*2.+400.,"height":g.half_height*2.+400.},"polygon":g.polygon(),"terrain":v4_terrain_view(&g,&t),"buildings":buildings}},"construction_grid":{"origin":origin,"cell_size_m":size,"bounds":{"x":minx,"y":miny,"width":maxx-minx,"height":maxy-miny},"buildable_cells":cells}});
    if let Some(c)=q.get("candidate"){let p=point(&c["cell"])?;let occupied=buildings.iter().any(|b|b["cell"]==c["cell"]&&b["id"]!=c["id"]);let valid=legal(p)&&!occupied;result["candidate"]=json!({"valid":valid,"reason":if occupied{"此格已有设施"}else if !legal(p){"此处海水、河流或悬崖不适合建设"}else{""},"world_position":p});}Ok(result)
}
#[derive(Clone, Copy)]
struct Unit {
    id: &'static str,
    name: &'static str,
    designation: &'static str,
    role: &'static str,
    class: &'static str,
    companies: u32,
    people: u32,
    hp: f64,
    damage: f64,
    range: f64,
    reload: u32,
    ammo: u32,
    speed: f64,
    armor: f64,
    vision: f64,
    transport: &'static str,
    ability: &'static str,
}
macro_rules! unit {
    ($id:literal,$name:literal,$designation:literal,$role:literal,$class:literal,$companies:expr,$people:expr,$hp:expr,$damage:expr,$range:expr,$reload:expr,$ammo:expr,$speed:expr,$armor:expr,$vision:expr,$transport:literal,$ability:literal) => {
        Unit {
            id: $id,
            name: $name,
            designation: $designation,
            role: $role,
            class: $class,
            companies: $companies,
            people: $people,
            hp: $hp,
            damage: $damage,
            range: $range,
            reload: $reload,
            ammo: $ammo,
            speed: $speed,
            armor: $armor,
            vision: $vision,
            transport: $transport,
            ability: $ability,
        }
    };
}
const UNITS: [Unit; 28] = [
    unit!(
        "MCP-001",
        "云隼",
        "第一空中特勤旅",
        "air_assault",
        "infantry",
        3,
        8,
        95.,
        18.,
        700.,
        12,
        80,
        85.,
        1.,
        1500.,
        "transport_helicopter",
        "suppression"
    ),
    unit!(
        "MCP-034",
        "礁刃",
        "第34海军派遣团",
        "marine",
        "infantry",
        5,
        9,
        110.,
        22.,
        800.,
        13,
        100,
        75.,
        0.9,
        1500.,
        "landing_craft",
        "suppression"
    ),
    unit!(
        "MCP-076",
        "冬鸢",
        "第76空降突击旅",
        "airborne",
        "infantry",
        3,
        8,
        95.,
        24.,
        850.,
        16,
        75,
        80.,
        1.,
        1600.,
        "parachute_aircraft",
        "at_missile"
    ),
    unit!(
        "MCP-009",
        "汐锚",
        "第9海岸工兵营",
        "engineer",
        "infantry",
        2,
        6,
        100.,
        14.,
        650.,
        15,
        80,
        72.,
        1.,
        1400.,
        "armored_boat",
        "field_repair"
    ),
    unit!(
        "MCP-022",
        "铁潮",
        "第22重装甲旅",
        "armor",
        "armor",
        3,
        6,
        600.,
        140.,
        1500.,
        42,
        36,
        45.,
        0.32,
        1700.,
        "heavy_lander",
        "hull_down"
    ),
    unit!(
        "MCP-011",
        "灯鲨",
        "第11轻装海军陆战团",
        "marine",
        "infantry",
        4,
        8,
        85.,
        23.,
        650.,
        11,
        85,
        95.,
        1.1,
        1600.,
        "fast_boat",
        "smoke"
    ),
    unit!(
        "MCP-018",
        "苔原",
        "第18远海侦察营",
        "recon",
        "infantry",
        2,
        6,
        80.,
        16.,
        1000.,
        13,
        60,
        100.,
        1.1,
        2400.,
        "fast_boat",
        "recon_mark"
    ),
    unit!(
        "MCP-027",
        "赤隼",
        "第27武装航空旅",
        "gunship",
        "air",
        2,
        6,
        210.,
        78.,
        1550.,
        24,
        16,
        260.,
        0.95,
        2200.,
        "attack_helicopter",
        "air_rockets"
    ),
    unit!(
        "MCP-041",
        "雾雀",
        "第41电子战营",
        "electronic",
        "infantry",
        2,
        6,
        90.,
        12.,
        700.,
        16,
        65,
        78.,
        1.,
        1900.,
        "landing_craft",
        "jam"
    ),
    unit!(
        "MCP-052",
        "白鹭",
        "第52海上医疗团",
        "medic",
        "infantry",
        3,
        8,
        100.,
        10.,
        600.,
        17,
        55,
        76.,
        1.,
        1450.,
        "landing_craft",
        "triage"
    ),
    unit!(
        "MCP-063",
        "断浪",
        "第63反装甲营",
        "antiarmor",
        "infantry",
        3,
        8,
        90.,
        95.,
        1650.,
        34,
        28,
        65.,
        1.1,
        1700.,
        "landing_craft",
        "at_missile"
    ),
    unit!(
        "MCP-087",
        "砾火",
        "第87岸战炮兵团",
        "artillery",
        "armor",
        3,
        6,
        300.,
        115.,
        2600.,
        48,
        30,
        36.,
        0.6,
        1600.,
        "heavy_lander",
        "barrage"
    ),
    unit!(
        "MCP-103",
        "潮梭",
        "第103两栖机动团",
        "transport",
        "amphibious",
        4,
        8,
        360.,
        55.,
        1100.,
        22,
        60,
        72.,
        0.52,
        1600.,
        "amphibious_vehicle",
        "rapid_march"
    ),
    unit!(
        "MCP-116",
        "银脉",
        "第116战地补给团",
        "logistics",
        "infantry",
        4,
        9,
        105.,
        13.,
        700.,
        17,
        120,
        66.,
        0.95,
        1400.,
        "armored_boat",
        "resupply"
    ),
    unit!(
        "MCP-128",
        "夜莺",
        "第128精确射手营",
        "sniper",
        "infantry",
        2,
        6,
        75.,
        72.,
        1850.,
        31,
        36,
        62.,
        1.15,
        2300.,
        "fast_boat",
        "precision"
    ),
    unit!(
        "MCP-145",
        "苍穹",
        "第145机动防空团",
        "airdefense",
        "infantry",
        3,
        8,
        100.,
        45.,
        2100.,
        18,
        60,
        65.,
        0.95,
        2400.,
        "landing_craft",
        "aa_burst"
    ),
    unit!(
        "MCP-167",
        "苇影",
        "第167河口陆战团",
        "riverine",
        "river_infantry",
        4,
        9,
        90.,
        19.,
        750.,
        12,
        85,
        90.,
        1.05,
        1700.,
        "fast_boat",
        "smoke"
    ),
    unit!(
        "MCP-184",
        "烬羽",
        "第184破障突击团",
        "breacher",
        "infantry",
        3,
        8,
        125.,
        38.,
        550.,
        13,
        70,
        80.,
        0.85,
        1400.,
        "armored_boat",
        "breach"
    ),
    unit!(
        "MCP-203",
        "星桅",
        "第203联合指挥营",
        "command",
        "infantry",
        2,
        6,
        100.,
        13.,
        750.,
        16,
        80,
        72.,
        1.,
        1900.,
        "landing_craft",
        "coordination"
    ),
    unit!(
        "MCP-240",
        "雨燕",
        "第240空中救护团",
        "rescue",
        "infantry",
        3,
        6,
        85.,
        12.,
        650.,
        14,
        60,
        85.,
        1.1,
        1650.,
        "transport_helicopter",
        "rescue"
    ),
    unit!(
        "MCP-088",
        "霜铃",
        "近卫第88伞降旅",
        "airborne",
        "infantry",
        5,
        10,
        85.,
        26.,
        850.,
        14,
        80,
        88.,
        1.15,
        1750.,
        "parachute_aircraft",
        "drop_smoke"
    ),
    unit!(
        "MCP-006",
        "夜枭",
        "第6海上空中突击营",
        "gunship",
        "air",
        1,
        6,
        155.,
        60.,
        1450.,
        18,
        12,
        310.,
        1.2,
        2300.,
        "attack_helicopter",
        "air_coordination"
    ),
    Unit{id:"MCP-301",name:"榛穗",designation:"第301 海岸步枪团",role:"marine",class:"infantry",companies:4,people:8,hp:112.,damage:16.,range:950.,reload:14,ammo:90,speed:78.,armor:0.9,vision:1500.,transport:"landing_craft",ability:"command_network"},
    Unit{id:"MCP-302",name:"雪栀",designation:"第302 重装登陆营",role:"assault",class:"infantry",companies:3,people:8,hp:145.,damage:16.,range:950.,reload:14,ammo:90,speed:58.,armor:0.62,vision:1250.,transport:"landing_craft",ability:"grenade"},
    Unit{id:"MCP-303",name:"栗遥",designation:"第303 轻装机动步兵团",role:"recon",class:"infantry",companies:5,people:6,hp:78.,damage:16.,range:950.,reload:14,ammo:90,speed:108.,armor:1.18,vision:1750.,transport:"landing_craft",ability:"recon_mark"},
    Unit{id:"MCP-304",name:"雾棠",designation:"第304 两栖轮式突击营",role:"amphibious",class:"amphibious",companies:2,people:6,hp:100.,damage:16.,range:950.,reload:14,ammo:90,speed:84.,armor:0.95,vision:1450.,transport:"amphibious_vehicle",ability:"rapid_march"},
    Unit{id:"MCP-305",name:"霜岑",designation:"第305 两栖履带火力营",role:"armor",class:"amphibious",companies:2,people:6,hp:108.,damage:16.,range:950.,reload:14,ammo:90,speed:72.,armor:0.9,vision:1500.,transport:"amphibious_vehicle",ability:"hull_down"},
    Unit{id:"MCP-306",name:"芷宁",designation:"第6步兵团",role:"marine",class:"infantry",companies:2,people:10,hp:90.,damage:26.,range:1250.,reload:24,ammo:60,speed:80.,armor:0.95,vision:1550.,transport:"landing_craft",ability:"self_dressing"},
];
fn unit(id: &str) -> E<&'static Unit> {
    UNITS
        .iter()
        .find(|u| u.id == id)
        .ok_or_else(|| "新版战术人格未登记".into())
}
#[derive(Clone, Copy)]
struct Vehicle {
    kind: &'static str,
    capacity: u32,
    hp: f64,
    armor: f64,
    speed: f64,
    air: bool,
}
fn vehicle(kind: &str) -> E<Vehicle> {
    let (c, h, a, s, air) = match kind {
        "landing_craft" => (12, 340., 0.9, 90., false),
        "fast_boat" => (6, 200., 1.15, 145., false),
        "armored_boat" => (9, 520., 0.55, 65., false),
        "heavy_lander" => (6, 800., 0.42, 42., false),
        "transport_helicopter" => (8, 180., 1.15, 330., true),
        "parachute_aircraft" => (10, 240., 1.3, 410., true),
        "amphibious_vehicle" => (1, 360., 0.52, 85., false),
        "attack_helicopter" => (1, 155., 1.2, 310., true),
        _ => return Err("登陆载具类型未登记".into()),
    };
    let key = match kind {
        "fast_boat" => "fast_boat",
        "armored_boat" => "armored_boat",
        "heavy_lander" => "heavy_lander",
        "transport_helicopter" => "transport_helicopter",
        "parachute_aircraft" => "parachute_aircraft",
        "amphibious_vehicle" => "amphibious_vehicle",
        "attack_helicopter" => "attack_helicopter",
        _ => "landing_craft",
    };
    Ok(Vehicle {
        kind: key,
        capacity: c,
        hp: h,
        armor: a,
        speed: s,
        air,
    })
}
fn allowed(u: &Unit, kind: &str) -> bool {
    if u.class == "air" {
        kind == "attack_helicopter"
    } else if u.class == "amphibious" {
        kind == "amphibious_vehicle"
    } else if u.class == "armor" {
        kind == "heavy_lander"
    } else if u.id == "MCP-088" || u.id == "MCP-076" {
        kind == "parachute_aircraft"
    } else if matches!(u.id, "MCP-001" | "MCP-240") {
        kind == "transport_helicopter"
    } else {
        matches!(kind, "landing_craft" | "fast_boat" | "armored_boat")
    }
}
fn vehicle_json(v: Vehicle) -> Value {
    json!({"id":v.kind,"kind":v.kind,"capacity":v.capacity,"hp":v.hp,"armor":v.armor,"speed":v.speed,"airborne":v.air,"transport_role":if matches!(v.kind,"amphibious_vehicle"|"attack_helicopter"){"combat_same_actor"}else if v.kind=="parachute_aircraft"{"insertion_only"}else{"both"}})
}
pub(crate) fn catalogue() -> Value {
    let mut v = super::catalogue();
    v["version"] = json!(VERSION);
    v["cards"]=json!(UNITS.iter().map(|u|{let options=["landing_craft","fast_boat","armored_boat","heavy_lander","transport_helicopter","parachute_aircraft","amphibious_vehicle","attack_helicopter"].into_iter().filter(|k|allowed(u,k)).map(|k|vehicle_json(vehicle(k).unwrap())).collect::<Vec<_>>();json!({"id":u.id,"name":u.name,"designation":u.designation,"role":u.role,"nato_type":if u.class=="air"{"aviation"}else if u.class=="armor"{"armor"}else if u.role=="airborne"{"airborne_infantry"}else{u.role},"echelon":if u.designation.ends_with('旅'){"X"}else if u.designation.ends_with('团'){"III"}else{"II"},"company_count":u.companies,"personnel_per_company":u.people,"entity_count":u.people,"body_count":u.people*u.companies,"speed":u.speed,"default_transport":u.transport,"transport":vehicle_json(vehicle(u.transport).unwrap()),"transport_options":options,"combat":{"class":u.class,"vehicle_id":if matches!(u.class,"air"|"armor"|"amphibious"){Some(format!("{}-{}",u.id,u.transport))}else{None},"hp":u.hp,"damage":u.damage,"range":u.range,"reload_seconds":u.reload as f64/10.,"ammo":u.ammo,"speed":u.speed,"armor":u.armor,"vision":u.vision},"ability":{"id":u.ability,"name":ability_name_v2(u.ability),"charges":3,"cooldown":20.,"range":1600.,"radius":350.},"source_kind":"original_fictional","recovery_transport":if u.transport=="parachute_aircraft"{"landing_craft"}else{u.transport},"embodiment":if u.class=="air"{"one_female_body_drives_one_aircraft"}else if matches!(u.class,"armor"|"amphibious"){"one_female_body_operates_one_vehicle"}else{"female_infantry"}})}).collect::<Vec<_>>());
    v["deployables"] = json!([{"kind":"land_mine","charges":1,"damage":140,"radius_m":100},{"kind":"sea_mine","charges":1,"damage":180,"radius_m":180},{"kind":"beach_position","hp":450,"radius_m":140,"cover_multiplier":0.65}]);
    v["modes"] = json!(["raid", "defense", "exercise"]);
    v["limits"] = json!({"ships_per_side":6,"roster_per_side":27,"bodies_per_side":600,"companies_per_side":96,"projectiles":512,"match_seconds":1200});
    for c in v["cards"].as_array_mut().unwrap() {
        let id = c["id"].as_str().unwrap().to_string();
        let u = unit(&id).unwrap();
        c["personnel_cap"] = json!(if id == "MCP-088" {
            3000
        } else if id == "MCP-006" {
            1200
        } else {
            1000 + u.companies * 600
        });
        c["combat"]["vehicle_id"] = json!(combat_visual(u));
        c["combat"]["collision_radius_m"] = json!(body_radius(u.class));
        c["ability"]["description"] = json!(ability_description(u.ability));
        c["ability"]["radius"] = json!(match u.ability {
            "triage" | "rescue" | "field_repair" | "suppression" | "jam" => 400.,
            "resupply" => 450.,
            "at_missile" => 80.,
            "air_rockets" => 180.,
            "barrage" | "aa_burst" => 240.,
            "precision" => 35.,
            "breach" => 150.,
            "coordination" | "air_coordination" => 700.,
            "recon_mark" => 1800.,
            _ => 350.,
        });
        c["ability"]["duration_s"] = json!(match u.ability {
            "suppression" => 3.5,
            "smoke" | "drop_smoke" | "hull_down" | "recon_mark" | "jam" | "rapid_march"
            | "coordination" | "air_coordination" => 12.,
            _ => 0.,
        });
    }
    v
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Force {
    pub ships: Vec<Hull>,
    pub roster: Vec<String>,
    #[serde(default)]
    pub unit_condition: Vec<Condition>,
    #[serde(default)]
    pub unit_growth: Vec<Growth>,
    #[serde(default)]
    pub company_transports: Vec<CompanyTransport>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct DeployPick {
    pub id: String,
    pub kind: String,
    pub x: f64,
    pub y: f64,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct IslandConfig {
    pub npc_id: String,
    pub island_level: u32,
    #[serde(default)]
    pub forts: Vec<Fort>,
    #[serde(default)]
    pub storage: Option<Stock>,
    #[serde(default)]
    pub unit_growth: Vec<Growth>,
    #[serde(default)]
    pub deployables: Vec<DeployPick>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Start {
    pub mode: String,
    pub ships: Vec<Hull>,
    pub roster: Vec<String>,
    #[serde(default)]
    pub unit_condition: Vec<Condition>,
    pub transport_preset: String,
    #[serde(default)]
    pub defense: Vec<Fort>,
    #[serde(default)]
    pub company_transports: Vec<CompanyTransport>,
    #[serde(default)]
    pub company_layout: Option<String>,
    pub island: IslandConfig,
    #[serde(default)]
    pub defender: Option<Force>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Saved {
    pub version: String,
    pub seed: u32,
    pub config: Start,
    pub frame: u32,
    pub tick: f64,
    pub commands: Vec<Command>,
}
#[derive(Clone, Serialize)]
struct Region {
    id: String,
    kind: &'static str,
    polygon: Vec<P>,
    elevation_m: f64,
    movement: Value,
    vision_multiplier: f64,
    cover_multiplier: f64,
}
struct Terrain {
    regions: Vec<Region>,
}

#[derive(Clone)]
struct Company {
    id: String,
    unit: &'static Unit,
    side: u32,
    carrier: u32,
    bodies: Vec<u32>,
    stage: &'static str,
    p: P,
    goal: P,
    rally: Option<P>,
    path: Vec<P>,
    transport: Vehicle,
    beach: u32,
    order: String,
    charges: u32,
    next: u32,
    tools: u32,
    reserve: u32,
    initial: f64,
    pending: bool,
    initial_count: u32,
    buff_until: u32,
    speed_scale: f64,
    support_scale: f64,
}
#[derive(Clone)]
struct Actor {
    id: u32,
    company: usize,
    phase: &'static str,
    heading: f64,
    velocity: P,
    altitude: f64,
    air_until: u32,
    knock_until: u32,
    knock_velocity: P,
    seen: [bool; 2],
    fuel: f64,
    offset: P,
    blocked_frames: u32,
    last_waypoint: Option<P>,
}

// Original continuous-disc local steering; no upstream engine code is copied.
// Tactical spacing is deliberately independent from the physical footprint.
fn body_radius(class: &str) -> f64 {
    match class {
        "armor" | "amphibious" => 3.,
        "air" => 6.,
        _ => 0.45,
    }
}
fn spread(seed: u32, company: usize, index: usize, class: &str) -> P {
    let hash = seed
        .wrapping_mul(747796405)
        .wrapping_add((company as u32).wrapping_mul(29807592))
        .wrapping_add((index as u32).wrapping_mul(7919));
    let angle = index as f64 * 2.399963229728653 + (hash % 1000) as f64 * 0.001;
    let spacing = match class {
        "armor" | "amphibious" => 23.,
        "air" => 49.,
        _ => 10.,
    };
    let r = spacing * (index as f64 + 0.5).sqrt() * (0.83 + (hash % 31) as f64 * 0.007);
    let company_angle = company as f64 * 2.399963229728653 + (seed % 71) as f64 * 0.017;
    let company_radius = 26. * ((company % 23) as f64 + 0.5).sqrt();
    P {
        x: libm::cos(angle) * r,
        y: libm::sin(angle) * r,
    } + P {
        x: libm::cos(company_angle) * company_radius,
        y: libm::sin(company_angle) * company_radius,
    }
}
#[derive(Clone, Copy)]
struct Disc {
    id: u32,
    p: P,
    radius: f64,
    layer: u8,
}
struct Occupancy {
    discs: Vec<Disc>,
    origins: Vec<P>,
    cells: BTreeMap<(i32, i32, u8), Vec<usize>>,
}
impl Occupancy {
    fn cell(p: P, layer: u8) -> (i32, i32, u8) {
        (
            (p.x / 32.).floor() as i32,
            (p.y / 32.).floor() as i32,
            layer,
        )
    }
    fn new(discs: Vec<Disc>) -> Self {
        let mut s = Self {
            origins: discs.iter().map(|d| d.p).collect(),
            discs,
            cells: BTreeMap::new(),
        };
        for (i, d) in s.discs.iter().enumerate() {
            s.cells.entry(Self::cell(d.p, d.layer)).or_default().push(i);
        }
        s
    }
    fn update(&mut self, id: u32, p: P) {
        if let Some(i) = self.discs.iter().position(|d| d.id == id) {
            let old = Self::cell(self.discs[i].p, self.discs[i].layer);
            let new = Self::cell(p, self.discs[i].layer);
            if old != new {
                for x in old.0.min(new.0)..=old.0.max(new.0) {
                    for y in old.1.min(new.1)..=old.1.max(new.1) {
                        let rows = self.cells.entry((x, y, new.2)).or_default();
                        if !rows.contains(&i) {
                            rows.push(i);
                        }
                    }
                }
            }
            self.discs[i].p = p;
        }
    }
    fn clear(&self, id: u32, a: P, b: P, radius: f64, layer: u8) -> bool {
        let lo = Self::cell(
            P {
                x: a.x.min(b.x) - radius - 7.,
                y: a.y.min(b.y) - radius - 7.,
            },
            layer,
        );
        let hi = Self::cell(
            P {
                x: a.x.max(b.x) + radius + 7.,
                y: a.y.max(b.y) + radius + 7.,
            },
            layer,
        );
        let v = b - a;
        for x in lo.0..=hi.0 {
            for y in lo.1..=hi.1 {
                if let Some(rows) = self.cells.get(&(x, y, layer)) {
                    for i in rows {
                        let d = self.discs[*i];
                        if d.id == id {
                            continue;
                        }
                        let origin = self.origins[*i];
                        let relative = a - origin;
                        let relative_v = v - (d.p - origin);
                        let relative_l2 = relative_v.x * relative_v.x + relative_v.y * relative_v.y;
                        let t = if relative_l2 > 1e-12 {
                            (-(relative.x * relative_v.x + relative.y * relative_v.y) / relative_l2)
                                .clamp(0., 1.)
                        } else {
                            0.
                        };
                        let limit = radius + d.radius + 0.02;
                        if (relative + relative_v * t).dist(P::default()) < limit {
                            return false;
                        }
                    }
                }
            }
        }
        true
    }
}
#[derive(Clone)]
struct Transit {
    id: u32,
    company: usize,
    passengers: Vec<u32>,
    vehicle: Vehicle,
    phase: &'static str,
    goal: P,
    heading: f64,
    returning: bool,
    drop: bool,
}
#[derive(Clone)]
struct Emplacement {
    id: String,
    kind: &'static str,
    side: u32,
    p: P,
    hp: f64,
    active: bool,
}
#[derive(Clone)]
struct ShellMeta {
    id: u32,
    caliber: f64,
    mount: u32,
    barrel: u32,
    count: u32,
    origin: P,
    goal: P,
    radius: f64,
    damage: f64,
    impulse: f64,
    flight: f64,
}
pub(crate) struct Battle {
    base: super::Battle,
    start: Start,
    commands: Vec<Command>,
    companies: Vec<Company>,
    actors: Vec<Actor>,
    transit: Vec<Transit>,
    terrain: Terrain,
    training_shore_scale:f64,
    deployables: Vec<Emplacement>,
    shells: BTreeMap<u32, ShellMeta>,
    result: Option<Value>,
    auto: bool,
    posture: String,
    last_ai: u32,
    captured: u32,
    warehouse_capture: Vec<u32>,
    captured_store: BTreeSet<usize>,
    plundered: Stock,
    revealed: [BTreeSet<u32>; 2],
    next_transport: u32,
}
impl Battle {
    pub(crate) fn decode(mut q: Value) -> E<(u32, Start)> {
        if q["version"] != VERSION {
            return Err("请选择显式cas-island-war-v4-base".into());
        }
        let seed = q.get("seed").map_or(Ok(1), |s| {
            s.as_u64()
                .filter(|n| *n <= u32::MAX as u64)
                .map(|n| n as u32)
                .ok_or("种子无效")
        })?;
        let o = q.as_object_mut().ok_or("新局参数无效")?;
        for k in ["op", "version", "seed"] {
            o.remove(k);
        }
        let s = serde_json::from_value(q).map_err(|e| format!("新版海岛配置无效：{e}"))?;
        Ok((seed, s))
    }
    fn force(&self) -> Force {
        Force {
            ships: self.start.ships.clone(),
            roster: self.start.roster.clone(),
            unit_condition: self.start.unit_condition.clone(),
            unit_growth: self.start.island.unit_growth.clone(),
            company_transports: self.start.company_transports.clone(),
        }
    }
    fn validate_force(f: &Force) -> E<()> {
        if f.ships.is_empty() || f.ships.len() > 6 || f.roster.is_empty() || f.roster.len() > 27 {
            return Err("每侧需要1–6艘真实舰、1–27个不同战术人格".into());
        }
        let mut ids = BTreeSet::new();
        for h in &f.ships {
            if !ids.insert(&h.id)
                || !h.hp.is_finite()
                || !(1. ..=100.).contains(&h.hp)
                || h.ammo > 100
            {
                return Err("舰艇本人、HP或弹药不合法".into());
            }
        }
        ids.clear();
        let mut n = 0;
        for id in &f.roster {
            let u = unit(id)?;
            if !ids.insert(id) {
                return Err("同侧战术人格不得重复".into());
            }
            n += u.companies * u.people;
        }
        if n > 600 {
            return Err("单侧身体超过600安全预算".into());
        }
        let mut conditions = BTreeSet::new();
        let mut growths = BTreeSet::new();
        let mut transports = BTreeSet::new();
        for c in &f.unit_condition {
            if !conditions.insert(&c.id)
                || !f.roster.contains(&c.id)
                || !c.hp.is_finite()
                || !(0. ..=100.).contains(&c.hp)
            {
                return Err("单位整备身份或HP无效".into());
            }
        }
        for g in &f.unit_growth {
            if !growths.insert(&g.id)
                || !f.roster.contains(&g.id)
                || !(1..=30).contains(&g.level)
                || g.ascension > 2
                || ![
                    "",
                    "assault",
                    "vanguard",
                    "support",
                    "mobility",
                    "precision",
                    "logistics",
                ]
                .contains(&g.specialization.as_str())
            {
                return Err("单位成长不合法".into());
            }
        }
        for t in &f.company_transports {
            if !transports.insert(&t.id)
                || !f.roster.contains(&t.id)
                || !allowed(unit(&t.id)?, &t.kind)
            {
                return Err("本人不能使用该运输或作战载具".into());
            }
        }
        Ok(())
    }
    pub(crate) fn new(seed: u32, start: Start) -> E<Self> {
        if !["raid", "defense", "exercise"].contains(&start.mode.as_str()) {
            return Err("新版模式须raid/defense/exercise".into());
        }
        if start.company_layout.as_deref() != Some(MULTI) {
            return Err("新版须使用multi-company-v1".into());
        }
        let force = Force {
            ships: start.ships.clone(),
            roster: start.roster.clone(),
            unit_condition: start.unit_condition.clone(),
            unit_growth: start.island.unit_growth.clone(),
            company_transports: start.company_transports.clone(),
        };
        Self::validate_force(&force)?;
        if start.mode == "exercise" {
            Self::validate_force(
                start
                    .defender
                    .as_ref()
                    .ok_or("演习须明确传入真实驻防，不能回退人机模板")?,
            )?;
        }
        let base_start = super::Start {
            base: Config {
                mode: if start.mode == "defense" {
                    "defense"
                } else {
                    "raid"
                }
                .into(),
                ships: start.ships.clone(),
                roster: vec!["MCP-034".into(), "MCP-009".into()],
                unit_condition: vec![],
                transport_preset: start.transport_preset.clone(),
                defense: vec![],
                company_transports: vec![],
                lesson: None,
                company_layout: Some(MULTI.into()),
            },
            island: super::Island {
                npc_id: if start.mode == "exercise" {
                    "shoal_watch".into()
                } else {
                    start.island.npc_id.clone()
                },
                island_level: start.island.island_level,
                forts: start.island.forts.clone(),
                storage: start.island.storage.clone(),
                unit_growth: vec![],
            },
        };
        let geometry = v4_geometry(start.island.island_level);
        let mut base = super::Battle::new_geometry(seed, base_start, Some(geometry))?;
        base.core.ground.groups.clear();
        base.core.ground.bodies.clear();
        base.core.ground.transports.clear();
        base.core.ground.config.roster.clear();
        base.core.ground.config.mode = "raid".into();
        base.core.ground.ruins.clear();
        base.core.ground.loot.clear();
        base.core.ground.mines.clear();
        base.commander = None;
        base.landings.clear();
        let mut terrain = Terrain::new(&base.geometry, seed);
        let wh = base.warehouses.len();
        let mut w = Self {
            base,
            start,
            commands: vec![],
            companies: vec![],
            actors: vec![],
            transit: vec![],
            terrain,
            training_shore_scale:1.,
            deployables: vec![],
            shells: BTreeMap::new(),
            result: None,
            auto: false,
            posture: "mission".into(),
            last_ai: 0,
            captured: 0,
            warehouse_capture: vec![0; wh],
            captured_store: BTreeSet::new(),
            plundered: Stock::default(),
            revealed: [BTreeSet::new(), BTreeSet::new()],
            next_transport: 2_000_000,
        };
        if w.start.mode == "exercise" {
            let f = w.start.defender.clone().unwrap();
            w.replace_defender(&f)?;
        }
        let enemy = if let Some(f) = w
            .start
            .defender
            .clone()
            .filter(|_| w.start.mode == "exercise")
        {
            f
        } else {
            let ships = w
                .base
                .core
                .ground
                .ships
                .iter()
                .filter(|s| !s.ally)
                .map(|s| Hull {
                    id: s.def.id.clone(),
                    hp: 100.,
                    ammo: 70,
                })
                .collect();
            let roster = if w.start.mode == "defense" {
                vec!["MCP-034".into(), "MCP-009".into()]
            } else if w.start.island.island_level >= 7 {
                vec!["MCP-034".into(), "MCP-063".into(), "MCP-145".into()]
            } else {
                vec!["MCP-034".into(), "MCP-009".into()]
            };
            Force {
                ships,
                roster,
                unit_condition: vec![],
                unit_growth: vec![],
                company_transports: vec![],
            }
        };
        w.add_force(0, &force, w.start.mode == "defense")?;
        w.add_force(1, &enemy, w.start.mode != "defense")?;
        let owner = if w.start.mode == "defense" { 0 } else { 1 };
        for p in w.start.island.deployables.clone() {
            if !p.x.is_finite()
                || !p.y.is_finite()
                || !(-0.6..=1.2).contains(&p.x)
                || !(-0.6..=1.2).contains(&p.y)
            {
                return Err("初始阵地坐标无效".into());
            }
            let pos = w.base.geometry.point(p.x, p.y);
            w.add_deployable(p.id, &p.kind, owner, pos)?;
        }
        w.observe_visibility();
        Ok(w)
    }
    fn replace_defender(&mut self, f: &Force) -> E<()> {
        let n = &mut self.base.core.naval;
        n.ships.retain(|s| s.side == 0);
        n.fleets.retain(|f| f.side == 0);
        n.contacts = [vec![], vec![]];
        n.next_contacts = [1, 1];
        self.base.core.ground.ships.retain(|s| s.ally);
        self.base.anchors.retain(|a| a.side == 0);
        let sea = self.base.geometry.beach(2)?.0;
        for (i, h) in f.ships.iter().enumerate() {
            let def = n
                .data
                .ships
                .iter()
                .position(|d| d.id == h.id)
                .ok_or("驻防舰舰卡未登记")?;
            let d = n.data.ships[def].clone();
            let fleet = 1000 + i as u32;
            let p = P {
                x: sea.x - 2100.,
                y: sea.y + (i as f64 - 1.) * 550.,
            };
            let id = n.spawn(def, 1, fleet, d.name.clone(), p, 90.)?;
            let s = n.ship_mut(id).unwrap();
            s.hp = d.dp * h.hp / 100.;
            s.character = Some(h.id.clone());
            for x in &mut s.torp_mount_remaining {
                *x = *x * h.ammo / 100;
            }
            for x in &mut s.torp_reserve {
                *x = *x * h.ammo / 100;
            }
            s.ammo = s.torp_mount_remaining.iter().sum();
            n.fleets.push(crate::model::Fleet {
                id: fleet,
                side: 1,
                name: format!("驻防{}", d.name),
                leader: id,
                members: vec![id],
                mode: "follow".into(),
                speed: 0.,
                actual: 0.,
                turn_degrees: 0.,
                points: vec![],
                ai: crate::model::Ai::new("coord", "manual"),
                notice: None,
                last_ai_route: 0,
                tactic: crate::model::Tactic::Search,
            });
            let mut sea_ship = self.base.core.ground.ships[0].clone();
            sea_ship.id = id;
            sea_ship.def = d.clone();
            sea_ship.ally = false;
            sea_ship.p = p;
            sea_ship.h = 90.;
            sea_ship.hp = d.dp * h.hp / 100.;
            sea_ship.max = d.dp;
            sea_ship.initial = h.hp;
            sea_ship.ammo = h.ammo;
            sea_ship.loaded = h.ammo;
            sea_ship.requested = h.ammo;
            sea_ship.ai = false;
            sea_ship.aim_target = None;
            sea_ship.path.clear();
            self.base.core.ground.ships.push(sea_ship);
            n.v4_gun_supply
                .get_or_insert_with(BTreeMap::new)
                .insert(id, h.ammo);
            self.base.anchors.push(super::Anchorage {
                ship: id,
                side: 1,
                phase: "anchored",
                ready: 0,
            });
        }
        n.init_realtime(crate::realtime::VERSION)?;
        n.refresh_open_intel();
        self.base
            .core
            .squadrons
            .retain(|q| n.ship(q.carrier).is_some_and(|s| s.side == 0));
        let carriers: Vec<_> = n
            .ships
            .iter()
            .filter(|s| {
                s.side == 1 && matches!(carrier_category(&n.data.ships[s.def].id), "CV" | "LHA")
            })
            .map(|s| (s.id, n.data.ships[s.def].id.clone()))
            .collect();
        for (id, identity) in carriers {
            let models: Vec<(&'static str, &'static str)> = if identity == SHOKAKU {
                vec![
                    ("A6M2", "fighter"),
                    ("D3A2", "dive_bomber"),
                    ("B5N2", "torpedo_bomber"),
                ]
            } else if identity == LHA {
                vec![("support_helicopter", "helicopter")]
            } else {
                vec![
                    ("F4F", "fighter"),
                    ("SBD", "dive_bomber"),
                    ("TBD", "torpedo_bomber"),
                ]
            };
            for (model, role) in models {
                self.base.core.squadrons.push(Squadron {
                    id: format!("air-{id}-{model}"),
                    carrier: id,
                    model,
                    role,
                    total: 3,
                    available: 3,
                    lost: 0,
                    ready: 0,
                    stock: 18,
                    range: 18000.,
                    health: vec![120.; 3],
                });
            }
        }
        Ok(())
    }
    fn add_force(&mut self, side: u32, f: &Force, stationed: bool) -> E<()> {
        let ships: Vec<_> = self
            .base
            .core
            .ground
            .ships
            .iter()
            .filter(|s| s.ally == (side == 0) && s.hp > 0.)
            .map(|s| (s.id, s.def.id.clone(), s.loaded, s.p))
            .collect();
        if ships.is_empty() {
            return Err("本侧缺少存活载舰".into());
        }
        let mut free: Vec<u32> = ships
            .iter()
            .map(|(_, id, ammo, _)| {
                let base = match carrier_category(id) {
                    "CV" => 180,
                    "LHA" | "APV" => 240,
                    _ => 120,
                };
                base + (100 - ammo) / 10
            })
            .collect();
        let mut ordered = f.roster.iter().collect::<Vec<_>>();
        ordered.sort_by_key(|id| {
            let u = unit(id).unwrap();
            if vehicle(
                f.company_transports
                    .iter()
                    .find(|t| t.id.as_str() == id.as_str())
                    .map_or(u.transport, |t| t.kind.as_str()),
            )
            .unwrap()
            .air
            {
                0
            } else if matches!(u.class, "armor" | "amphibious") {
                1
            } else {
                2
            }
        });
        for id in ordered {
            let u = unit(id)?;
            let t = vehicle(
                f.company_transports
                    .iter()
                    .find(|t| t.id == *id)
                    .map_or(u.transport, |t| t.kind.as_str()),
            )?;
            if !allowed(u, t.kind) {
                return Err("运输方式与部队类型不兼容".into());
            }
            let hp = f
                .unit_condition
                .iter()
                .find(|c| c.id == *id)
                .map_or(100., |c| c.hp);
            let growth = f.unit_growth.iter().find(|g| g.id == *id);
            let scale = growth.map_or(1., |g| {
                1. + 0.035 * (g.level - 1) as f64 / 29. + 0.015 * g.ascension as f64 / 2.
            });
            let fire = growth.map_or(1., |g| {
                1. + 0.03 * (g.level - 1) as f64 / 29. + 0.02 * g.ascension as f64 / 2.
            });
            for c in 1..=u.companies {
                let slots = u.people
                    * if u.class == "armor" || u.class == "amphibious" {
                        4
                    } else if t.air {
                        3
                    } else {
                        1
                    };
                let slot = if stationed {
                    0
                } else {
                    (0..ships.len())
                        .filter(|i| {
                            free[*i] >= slots
                                && match u.class {
                                    "air" => matches!(carrier_category(&ships[*i].1), "CV" | "LHA"),
                                    "armor" | "amphibious" => matches!(
                                        carrier_category(&ships[*i].1),
                                        "CV" | "LHA" | "APV"
                                    ),
                                    _ if t.air => {
                                        matches!(carrier_category(&ships[*i].1), "CV" | "LHA")
                                    }
                                    _ => true,
                                }
                        })
                        .max_by_key(|i| free[*i])
                        .ok_or("真实身体舱位不足或载舰资格不符")?
                };
                if !stationed {
                    free[slot] -= slots;
                }
                let carrier = ships[slot].0;
                let ci = self.companies.len();
                let company_id = format!("{}{}-C{c:02}", if side == 1 { "D-" } else { "" }, u.id);
                let mut p = if stationed {
                    self.base.geometry.point(
                        0.35 + ci as f64 % 4. * 0.1,
                        0.28 + (ci / 4 % 4) as f64 * 0.13,
                    )
                } else {
                    ships[slot].3
                };
                if stationed && !self.traversable(p, u.class) {
                    'search: for ring in 1..=12 {
                        for angle in 0..16 {
                            let q = p + P::bearing(angle as f64 * 22.5) * (ring as f64 * 45.);
                            if self.traversable(q, u.class) {
                                p = q;
                                break 'search;
                            }
                        }
                    }
                }
                let mut ids = vec![];
                for k in 0..u.people {
                    let kind = if u.class == "air" {
                        "gunship"
                    } else if u.class == "armor" {
                        if u.role == "artillery" {
                            "howitzer"
                        } else {
                            "tank"
                        }
                    } else if u.class == "amphibious" {
                        "ifv"
                    } else if u.role == "airdefense" {
                        "aa_team"
                    } else if u.role == "antiarmor" {
                        "anti_tank"
                    } else if u.role == "sniper" {
                        "sniper"
                    } else if matches!(u.role, "engineer" | "medic" | "rescue") {
                        "engineer"
                    } else {
                        "marine"
                    };
                    let offset = spread(self.base.core.ground.seed, ci, k as usize, u.class);
                    let position = if stationed {
                        self.free_spawn(p + offset, u.class)
                            .ok_or("驻防地形容纳不下独立身体")?
                    } else {
                        p
                    };
                    let bid = self.base.core.ground.id();
                    self.base.core.ground.bodies.push(Body {
                        id: bid,
                        group: company_id.clone(),
                        ally: side == 0,
                        kind,
                        p: position,
                        hp: u.hp,
                        max: u.hp,
                        ammo: u.ammo,
                        damage: u.damage,
                        range: u.range,
                        reload: u.reload,
                        next: 3,
                        armor: u.armor,
                        air: u.class == "air",
                        active: stationed,
                    });
                    let b = self.base.core.ground.bodies.last_mut().unwrap();
                    b.max = u.hp * scale;
                    b.hp = b.max * hp / 100.;
                    b.damage = u.damage * fire;
                    b.range = u.range;
                    if growth.is_some_and(|g| {
                        matches!(g.specialization.as_str(), "assault" | "precision")
                    }) {
                        b.range *= 1.01;
                    }
                    b.reload = u.reload;
                    b.ammo = u.ammo;
                    b.armor = u.armor;
                    if growth.is_some_and(|g| g.specialization == "vanguard") {
                        b.armor *= 0.99;
                    }
                    b.air = u.class == "air";
                    b.active = stationed;
                    let bid = b.id;
                    ids.push(bid);
                    self.actors.push(Actor {
                        id: bid,
                        company: ci,
                        phase: if stationed { "active" } else { "embarked" },
                        heading: 90.,
                        velocity: P::default(),
                        altitude: if b.air && stationed { 80. } else { 0. },
                        air_until: 0,
                        knock_until: 0,
                        knock_velocity: P::default(),
                        seen: [side == 0, side == 1],
                        fuel: 24000.,
                        offset,
                        blocked_frames: 0,
                        last_waypoint: None,
                    });
                }
                self.companies.push(Company {
                    id: company_id,
                    unit: u,
                    side,
                    carrier,
                    bodies: ids,
                    stage: if stationed { "active" } else { "embarked" },
                    p,
                    goal: p,
                    rally: None,
                    path: vec![],
                    transport: t,
                    beach: 2,
                    order: "hold".into(),
                    charges: 3,
                    next: 0,
                    tools: if u.role == "engineer" { 8 } else { 2 },
                    reserve: (if u.role == "logistics" {
                        180
                    } else {
                        u.people * u.ammo * 2
                    }) + if growth.is_some_and(|g| g.specialization == "logistics") {
                        (u.people * u.ammo * 2 / 100).max(1)
                    } else {
                        0
                    },
                    initial: hp,
                    pending: false,
                    initial_count: u.people,
                    buff_until: 0,
                    speed_scale: if growth.is_some_and(|g| g.specialization == "mobility") {
                        1.01
                    } else {
                        1.
                    },
                    support_scale: if growth.is_some_and(|g| g.specialization == "support") {
                        1.01
                    } else {
                        1.
                    },
                });
            }
        }
        Ok(())
    }
    fn add_deployable(&mut self, id: String, kind: &str, side: u32, p: P) -> E<()> {
        if self.deployables.len() >= 128
            || id.is_empty()
            || self.deployables.iter().any(|d| d.id == id)
        {
            return Err("阵地编号重复或超过预算".into());
        }
        let land = inside(&self.base.core.ground.polygon, p);
        let k = match kind {
            "land_mine" if land => "land_mine",
            "beach_position"
                if land
                    && (self.terrain.regions.iter().any(|r| {
                        matches!(r.kind, "beach" | "landing_zone") && inside(&r.polygon, p)
                    }) || self.base.core.ground.polygon.iter().enumerate().any(
                        |(i, a)| {
                            let b = self.base.core.ground.polygon
                                [(i + 1) % self.base.core.ground.polygon.len()];
                            let ab = b - *a;
                            let d = p - *a;
                            let n = (d.x * ab.x + d.y * ab.y) / (ab.x * ab.x + ab.y * ab.y);
                            p.dist(*a + ab * n.clamp(0., 1.)) <= 350.
                        },
                    )) =>
            {
                "beach_position"
            }
            "sea_mine" if !land && self.base.core.naval.field.contains(p) => "sea_mine",
            _ => return Err("地雷/阵地须在陆地，水雷须在海水".into()),
        };
        if self.deployables.iter().any(|d| d.p.dist(p) < 35.) {
            return Err("布防设施过于接近".into());
        }
        self.deployables.push(Emplacement {
            id,
            kind: k,
            side,
            p,
            hp: if k == "beach_position" { 450. } else { 30. },
            active: true,
        });
        Ok(())
    }
    fn body(&self, id: u32) -> Option<&Body> {
        self.base.core.ground.bodies.iter().find(|b| b.id == id)
    }
    fn body_mut(&mut self, id: u32) -> Option<&mut Body> {
        self.base.core.ground.bodies.iter_mut().find(|b| b.id == id)
    }
    fn frame(&self) -> u32 {
        self.base.core.ground.frame
    }
    fn guard(&self) -> u32 {
        if self.start.mode == "defense" {
            0
        } else {
            1
        }
    }
    fn attack(&self) -> u32 {
        1 - self.guard()
    }
    fn traversable(&self, p: P, class: &str) -> bool {
        class == "air"
            || (inside(&self.base.core.ground.polygon, p)
                && self.terrain.speed(p, class) > 0.
                && !self.base.core.ground.obstacles.iter().any(|o| inside(o, p)))
    }
    fn traversable_disc(&self, p: P, class: &str) -> bool {
        if class == "air" {
            return true;
        }
        let r = body_radius(class);
        self.traversable(p, class)
            && (0..8).all(|i| self.traversable(p + P::bearing(i as f64 * 45.) * r, class))
    }
    fn occupancy(&self) -> Occupancy {
        Occupancy::new(
            self.actors
                .iter()
                .filter_map(|a| {
                    let b = self.body(a.id)?;
                    if b.hp <= 0. || !b.active {
                        return None;
                    }
                    let class = self.companies.get(a.company).map_or(
                        if matches!(b.kind, "tank" | "howitzer" | "ifv") {
                            "armor"
                        } else if b.kind == "gunship" {
                            "air"
                        } else {
                            "infantry"
                        },
                        |c| c.unit.class,
                    );
                    Some(Disc {
                        id: a.id,
                        p: b.p,
                        radius: body_radius(class),
                        layer: if class == "air" { 1 } else { 0 },
                    })
                })
                .collect(),
        )
    }
    fn free_spawn(&self, p: P, class: &str) -> Option<P> {
        let occ = self.occupancy();
        let spawn_clearance = match class {
            "air" => 18.,
            "armor" | "amphibious" => 10.,
            _ => 7.55,
        };
        let layer = if class == "air" { 1 } else { 0 };
        for i in 0..512 {
            let q = if i == 0 {
                p
            } else {
                p + P::bearing(i as f64 * 137.507764) * (spawn_clearance * 1.1 * (i as f64).sqrt())
            };
            if self.traversable_disc(q, class) && occ.clear(u32::MAX, q, q, spawn_clearance, layer)
            {
                return Some(q);
            }
        }
        None
    }
    fn straight(&self, a: P, b: P, class: &str) -> bool {
        self.surface_line(a, b, class, false)
    }
    fn surface_disc(&self, p: P, class: &str, sea: bool) -> bool {
        if class == "air" {
            return true;
        }
        let legal = |q: P| {
            (sea && !inside(&self.base.core.ground.polygon, q)) || self.traversable(q, class)
        };
        legal(p) && (0..8).all(|i| legal(p + P::bearing(i as f64 * 45.) * body_radius(class)))
    }
    fn surface_line(&self, a: P, b: P, class: &str, sea: bool) -> bool {
        let n = (a.dist(b) / 30.).ceil().max(1.) as u32;
        (1..=n).all(|i| self.surface_disc(a + (b - a) * (i as f64 / n as f64), class, sea))
    }
    fn surface_step(&self, a: P, b: P, class: &str, sea: bool) -> bool {
        let n = (a.dist(b) / body_radius(class).max(0.5)).ceil().max(1.) as u32;
        (1..=n).all(|i| self.surface_disc(a + (b - a) * (i as f64 / n as f64), class, sea))
    }
    fn path(&self, a: P, b: P, class: &str) -> E<Vec<P>> {
        self.surface_path(a, b, class, false)
    }
    fn surface_path(&self, a: P, b: P, class: &str, sea: bool) -> E<Vec<P>> {
        if !self.surface_disc(b, class, sea) {
            return Err("该兵种不能通过目标地形".into());
        }
        if class == "air" || self.surface_line(a, b, class, sea) {
            return Ok(vec![b]);
        }
        // The 24m bridges remain reachable even though the coarse route grid
        // is 80m: insert their actual endpoints instead of widening the river.
        for bridge in self.terrain.regions.iter().filter(|r|r.kind=="ford") {
            let p=bridge.polygon.iter().copied().fold(P::default(),|a,b|a+b)*(1./bridge.polygon.len() as f64);
            let left=p+P{x:-self.base.geometry.half_width*0.105,y:0.};let right=p+P{x:self.base.geometry.half_width*0.105,y:0.};
            let (entry,exit)=if a.x<b.x{(left,right)}else{(right,left)};
            if self.surface_line(a,entry,class,sea)&&self.surface_line(entry,exit,class,sea)&&self.surface_line(exit,b,class,sea){return Ok(vec![entry,exit,b])}
        }
        // Weighted deterministic grid search is per company/order, never per body/frame.
        let g = &self.base.geometry;
        let step = 80.;
        let o = P {
            x: if sea {
                (g.center.x - g.half_width).min(a.x).min(b.x) - 160.
            } else {
                g.center.x - g.half_width - 80.
            },
            y: if sea {
                (g.center.y - g.half_height).min(a.y).min(b.y) - 160.
            } else {
                g.center.y - g.half_height - 80.
            },
        };
        let width = if sea {
            (((g.center.x + g.half_width).max(a.x).max(b.x) + 160. - o.x) / step).ceil() as i32
        } else {
            ((g.half_width * 2. + 160.) / step).ceil() as i32
        };
        let height = if sea {
            (((g.center.y + g.half_height).max(a.y).max(b.y) + 160. - o.y) / step).ceil() as i32
        } else {
            ((g.half_height * 2. + 160.) / step).ceil() as i32
        };
        let cell = |p: P| {
            (
                ((p.x - o.x) / step).round() as i32,
                ((p.y - o.y) / step).round() as i32,
            )
        };
        let point = |(x, y): (i32, i32)| {
            o + P {
                x: x as f64 * step,
                y: y as f64 * step,
            }
        };
        let start = cell(a);
        let finish = cell(b);
        let mut queue = std::collections::VecDeque::from([start]);
        let mut prev = BTreeMap::new();
        prev.insert(start, start);
        let mut found = None;
        while let Some(c) = queue.pop_front() {
            if c == finish
                || (point(c).dist(b) < step * 1.5 && self.surface_line(point(c), b, class, sea))
            {
                found = Some(c);
                break;
            }
            for (dx, dy) in [
                (1, 0),
                (0, 1),
                (-1, 0),
                (0, -1),
                (1, 1),
                (-1, 1),
                (1, -1),
                (-1, -1),
            ] {
                let n = (c.0 + dx, c.1 + dy);
                if n.0 < 0 || n.1 < 0 || n.0 > width || n.1 > height || prev.contains_key(&n) {
                    continue;
                }
                if self.surface_disc(point(n), class, sea)
                    && self.surface_line(point(c), point(n), class, sea)
                {
                    prev.insert(n, c);
                    queue.push_back(n);
                }
            }
        }
        let mut c = found.ok_or("没有该兵种可通行的陆路")?;
        let mut route = vec![b];
        while c != start {
            route.push(point(c));
            c = prev[&c];
        }
        route.reverse();
        let mut simple = vec![];
        let mut p = a;
        let mut at = 0;
        while at < route.len() {
            let mut j = at;
            while j + 1 < route.len() && self.surface_line(p, route[j + 1], class, sea) {
                j += 1
            }
            simple.push(route[j]);
            p = route[j];
            at = j + 1;
        }
        Ok(simple)
    }
    fn los(&self, a: P, b: P) -> bool {
        let n = (a.dist(b) / 50.).ceil().max(1.) as u32;
        !(1..n).any(|i| {
            let p = a + (b - a) * (i as f64 / n as f64);
            self.terrain
                .regions
                .iter()
                .any(|r| r.kind == "cliff" && inside(&r.polygon, p))
        })
    }
    fn observe_visibility(&mut self) {
        let alive = self
            .actors
            .iter()
            .filter_map(|a| {
                self.body(a.id).filter(|b| b.active && b.hp > 0.).map(|b| {
                    (
                        a.id,
                        self.companies[a.company].side,
                        b.p,
                        self.companies[a.company].unit.vision,
                        b.air,
                    )
                })
            })
            .collect::<Vec<_>>();
        let sights = self
            .actors
            .iter()
            .map(|a| {
                let Some(b) = self.body(a.id) else {
                    return (a.id, [false; 2]);
                };
                let own = self.companies[a.company].side;
                let mut seen = [own == 0, own == 1];
                for side in 0..2u32 {
                    if side == own {
                        continue;
                    }
                    let mut conceal = if b.air {
                        1.
                    } else {
                        self.terrain.concealment(b.p)
                    };
                    if self.companies.iter().any(|c| {
                        c.side == own
                            && c.buff_until > self.frame()
                            && matches!(c.unit.ability, "smoke" | "drop_smoke" | "jam")
                            && c.p.dist(b.p) < 350.
                    }) {
                        conceal *= 0.6;
                    }
                    let marked = self.companies.iter().any(|c| {
                        c.side == side
                            && c.buff_until > self.frame()
                            && c.unit.ability == "recon_mark"
                            && c.p.dist(b.p) < 1800.
                    });
                    seen[side as usize] = b.active
                        && b.hp > 0.
                        && (marked
                            || alive.iter().any(|(_, s, p, v, air)| {
                                *s == side
                                    && p.dist(b.p) <= v * conceal
                                    && (*air || self.los(*p, b.p))
                            })
                            || self.base.core.ground.buildings.iter().any(|t| {
                                t.ally == (side == 0)
                                    && t.hp > 0.
                                    && t.p.dist(b.p)
                                        <= spec(&t.kind).map_or(1000., |s| s.range.max(1000.))
                                            * conceal
                                    && self.los(t.p, b.p)
                            }));
                }
                (a.id, seen)
            })
            .collect::<Vec<_>>();
        for (id, seen) in sights {
            if let Some(a) = self.actors.iter_mut().find(|a| a.id == id) {
                a.seen = seen;
            }
            for s in 0..2 {
                if seen[s] {
                    self.revealed[s].insert(id);
                }
            }
        }
    }
    fn company_index(&self, q: &Value, side: u32) -> E<usize> {
        let key = q
            .get("company_id")
            .or_else(|| q.get("unit_id"))
            .and_then(Value::as_str)
            .ok_or("请选择行动连")?;
        let rows = self
            .companies
            .iter()
            .enumerate()
            .filter(|(_, c)| c.side == side && (c.id == key || c.unit.id == key))
            .collect::<Vec<_>>();
        if rows.len() != 1 {
            return Err("请选择具体行动连编号".into());
        }
        Ok(rows[0].0)
    }
    fn route_carrier(&mut self, ci: usize, goal: P) -> E<()> {
        let c = &self.companies[ci];
        let s = self
            .base
            .core
            .naval
            .ship(c.carrier)
            .filter(|s| s.alive())
            .ok_or("载舰已损失")?;
        let f = s.fleet.ok_or("载舰没有真实编队")?;
        let side = c.side;
        let speed = self.base.core.naval.data.ships[s.def].max_knots.min(30.);
        let p=s.p;let forward=P::bearing(s.h);let lateral=P{x:forward.y,y:-forward.x};
        let q = json!({"op":"route","fleet":f,"mode":"follow","points":[goal],"speed":speed});
        if self.base.core.naval.route(side as usize, &q, false).is_err(){
            let mut routed=false;
            'search: for radius in [1200.,2400.,3600.,4800.] {for sign in [1.,-1.] {
                let a=p+forward*radius;let b=a+lateral*(radius*sign);let c=goal+lateral*(radius*sign);
                let q=json!({"op":"route","fleet":f,"mode":"follow","points":[a,b,c,goal],"speed":speed});
                if self.base.core.naval.route(side as usize,&q,false).is_ok(){routed=true;break 'search}
            }}
            if !routed{return Err("载舰没有足够的安全转向海域，请手动安排外侧航线".into())}
        }
        if let Some(f) = self.base.core.naval.fleet_mut(f) {
            f.ai = crate::model::Ai::new("coord", "manual");
        }
        Ok(())
    }
    fn deploy(&mut self, ci: usize, beach: u32, goal: Option<P>) -> E<()> {
        let c = self.companies[ci].clone();
        if !["embarked", "recovered"].contains(&c.stage) {
            return Err("行动连已经投送或正在行动".into());
        }
        let (ship_p, alive) = self
            .base
            .core
            .naval
            .ship(c.carrier)
            .map(|s| (s.p, s.alive()))
            .ok_or("载舰不存在")?;
        if !alive {
            return Err("载舰已损失".into());
        }
        let (sea, land) = self.base.geometry.beach(beach)?;
        let dest = goal.unwrap_or(land);
        if !self.traversable(dest, c.unit.class) {
            return Err("投送落点不可通行".into());
        }
        if c.transport.air && ship_p.dist(dest) > 9000. {
            return Err("投送落点超出航空航程".into());
        }
        if !c.transport.air && c.transport.kind != "amphibious_vehicle" && ship_p.dist(sea) > 900. {
            self.route_carrier(ci, sea)?;
        }
        let cc = &mut self.companies[ci];
        cc.beach = beach;
        cc.rally = goal;
        cc.goal = if !c.transport.air && c.transport.kind!="amphibious_vehicle" { self.base.geometry.coast_landing(beach)?.0 } else { dest };
        cc.order = "advance".into();
        cc.pending = true;
        self.launch_pending(ci);
        Ok(())
    }
    fn launch_pending(&mut self, ci: usize) {
        let c = self.companies[ci].clone();
        if !c.pending {
            return;
        }
        let Some(s) = self.base.core.naval.ship(c.carrier).filter(|s| s.alive()) else {
            return;
        };
        let ship_p = s.p;
        let sea = self.base.geometry.beach(c.beach).unwrap().0;
        if !c.transport.air && c.transport.kind != "amphibious_vehicle" && ship_p.dist(sea) > 900. {
            return;
        }
        self.companies[ci].pending = false;
        self.companies[ci].stage = "inserting";
        if matches!(c.unit.class, "air" | "amphibious") {
            for id in &c.bodies {
                let occupancy = self.occupancy();
                let radius = body_radius(c.unit.class);
                let position = (0..512)
                    .map(|n| {
                        ship_p
                            + P::bearing(n as f64 * 137.507764) * (radius * 2.2 * (n as f64).sqrt())
                    })
                    .find(|p| {
                        self.surface_disc(*p, c.unit.class, true)
                            && occupancy.clear(
                                *id,
                                *p,
                                *p,
                                radius,
                                if c.unit.class == "air" { 1 } else { 0 },
                            )
                    });
                let Some(position) = position else { continue };
                if let Some(b) = self.body_mut(*id) {
                    if b.hp > 0. {
                        b.active = true;
                        b.p = position;
                    }
                }
                if let Some(a) = self.actors.iter_mut().find(|a| a.id == *id) {
                    a.phase = "inserting";
                    a.altitude = if c.unit.class == "air" { 80. } else { 0. };
                }
            }
            self.companies[ci].path = self
                .surface_path(ship_p, c.goal, c.unit.class, c.unit.class == "amphibious")
                .unwrap_or(vec![c.goal]);
            return;
        }
        let ids = c
            .bodies
            .iter()
            .filter(|id| self.body(**id).is_some_and(|b| b.hp > 0.))
            .copied()
            .collect::<Vec<_>>();
        for batch in ids.chunks(c.transport.capacity as usize) {
            let id = self.base.core.ground.id();
            self.base.core.ground.bodies.push(Body {
                id,
                group: format!("transport:{}", c.id),
                ally: c.side == 0,
                kind: if c.transport.air {
                    "helicopter"
                } else {
                    "landing_craft"
                },
                p: ship_p,
                hp: c.transport.hp,
                max: c.transport.hp,
                ammo: 0,
                damage: 0.,
                range: 0.,
                reload: 100,
                next: 0,
                armor: c.transport.armor,
                air: c.transport.air,
                active: true,
            });
            self.transit.push(Transit {
                id,
                company: ci,
                passengers: batch.to_vec(),
                vehicle: c.transport,
                phase: "inserting",
                goal: c.goal,
                heading: 90.,
                returning: false,
                drop: c.transport.kind == "parachute_aircraft",
            });
        }
        self.base
            .core
            .ground
            .event("deploy", "行动连实际分批离舰；载具按真实容量搭载", ship_p);
    }
    fn set_goal(&mut self, ci: usize, goal: P, order: &str) -> E<()> {
        let c = &self.companies[ci];
        if !["active", "ground"].contains(&c.stage) {
            return Err("行动连尚未抵达战区".into());
        };
        let path = self.path(c.p, goal, c.unit.class)?;
        let c = &mut self.companies[ci];
        c.goal = goal;
        c.path = path;
        c.order = order.into();
        Ok(())
    }
    fn withdraw(&mut self, ci: usize) -> E<()> {
        let c = self.companies[ci].clone();
        if ["embarked", "recovered", "lost"].contains(&c.stage) {
            return Ok(());
        }
        let s = self
            .base
            .core
            .naval
            .ship(c.carrier)
            .filter(|s| s.alive())
            .ok_or("无法撤收：载舰已损失")?;
        let ship_p = s.p;
        self.companies[ci].pending = false;
        self.companies[ci].order = "extract".into();
        if matches!(c.unit.class, "air" | "amphibious") {
            let path =
                self.surface_path(c.p, ship_p, c.unit.class, c.unit.class == "amphibious")?;
            self.companies[ci].goal = ship_p;
            self.companies[ci].path = path;
            self.companies[ci].stage = "returning";
            for a in self.actors.iter_mut().filter(|a| a.company == ci) {
                a.phase = "returning";
            }
            return Ok(());
        }
        let (sea, _) = self.base.geometry.beach(c.beach)?;
        let land = self.base.geometry.coast_landing(c.beach)?.1;
        let path = self.path(c.p, land, c.unit.class)?;
        self.companies[ci].goal = land;
        self.companies[ci].path = path;
        self.companies[ci].stage = "withdrawing";
        if ship_p.dist(sea) > 900. {
            self.route_carrier(ci, sea)?;
        }
        Ok(())
    }
    fn move_transports(&mut self) {
        let frame = self.frame();
        for i in 0..self.transit.len() {
            let t = self.transit[i].clone();
            if ["lost", "recovered"].contains(&t.phase) {
                continue;
            }
            let Some(b) = self.body(t.id).cloned() else {
                continue;
            };
            if b.hp <= 0. {
                self.transit[i].phase = "lost";
                for id in &t.passengers {
                    if let Some(b) = self.body_mut(*id) {
                        b.hp = 0.;
                        b.active = true;
                    }
                    if let Some(a) = self.actors.iter_mut().find(|a| a.id == *id) {
                        a.phase = "dead";
                    }
                }
                continue;
            }
            let carrier = self
                .base
                .core
                .naval
                .ship(self.companies[t.company].carrier)
                .filter(|s| s.alive())
                .map(|s| s.p);
            let goal = if t.returning {
                carrier.unwrap_or(t.goal)
            } else {
                t.goal
            };
            let delta = goal - b.p;
            let distance = delta.dist(P::default());
            let p = if distance > 0.1 {
                b.p + delta * (t.vehicle.speed * DT / distance).min(1.)
            } else {
                goal
            };
            if let Some(b) = self.body_mut(t.id) {
                b.p = p;
            }
            self.transit[i].heading = delta.heading();
            for id in &t.passengers {
                if let Some(b) = self.body_mut(*id) {
                    if !b.active {
                        b.p = p;
                    }
                }
            }
            if p.dist(goal) <= 25. {
                if t.returning {
                    if carrier.is_some() {
                        for id in &t.passengers {
                            if let Some(b) = self.body_mut(*id) {
                                b.active = false;
                            }
                            if let Some(a) = self.actors.iter_mut().find(|a| a.id == *id) {
                                a.phase = "recovered";
                            }
                        }
                        self.transit[i].phase = "recovered";
                        if let Some(b) = self.body_mut(t.id) {
                            b.active = false;
                        }
                    }
                } else {
                    let c = self.companies[t.company].clone();
                    for id in &t.passengers {
                        let offset = self.actors.iter().find(|a| a.id == *id).unwrap().offset;
                        let position = self
                            .free_spawn(p + offset, c.unit.class)
                            .unwrap_or(p + offset);
                        if let Some(b) = self.body_mut(*id) {
                            b.active = true;
                            b.p = position;
                            b.air = t.drop;
                        }
                        if let Some(a) = self.actors.iter_mut().find(|a| a.id == *id) {
                            let drop_frames = 80
                                + c.bodies.iter().position(|n| n == id).unwrap_or(0) as u32 * 2
                                + (t.company % 5) as u32 * 3;
                            a.phase = if t.drop { "parachuting" } else { "active" };
                            a.altitude = if t.drop { drop_frames as f64 * 3. } else { 0. };
                            a.air_until = if t.drop { frame + drop_frames } else { 0 };
                        }
                    }
                    self.companies[t.company].stage = "active";
                    let positions=t.passengers.iter().filter_map(|id|self.body(*id).map(|b|b.p)).collect::<Vec<_>>();
                    let landed=if positions.is_empty(){p}else{positions.iter().copied().fold(P::default(),|a,b|a+b)*(1./positions.len() as f64)};
                    self.companies[t.company].p = landed;
                    let rally = self.companies[t.company].rally.unwrap_or(p);
                    let path = self.path(landed, rally, c.unit.class).unwrap_or_default();
                    self.companies[t.company].goal = rally;
                    self.companies[t.company].path = path;
                    self.transit[i].returning = true;
                    self.transit[i].passengers.clear();
                    self.transit[i].goal = carrier.unwrap_or(p);
                    self.transit[i].phase = "returning";
                    self.base.core.ground.event(
                        if t.drop { "parachute" } else { "landed" },
                        if t.drop {
                            "真实伞降开始；下降时不能开火并暴露于防空"
                        } else {
                            "运输载具已完成投送，空载返舰"
                        },
                        p,
                    );
                    let _ = c;
                }
            }
        }
    }
    fn move_companies(&mut self) {
        let frame = self.frame();
        let mut occupancy = self.occupancy();
        for i in 0..self.actors.len() {
            if self.actors[i].phase == "recovered" {
                let a = self.actors[i].clone();
                let ship = self
                    .base
                    .core
                    .naval
                    .ship(self.companies[a.company].carrier)
                    .filter(|s| s.alive())
                    .map(|s| s.p);
                if let Some(b) = self.body_mut(a.id) {
                    if let Some(p) = ship {
                        b.p = p;
                    } else {
                        b.hp = 0.;
                        b.active = true;
                    }
                }
                if ship.is_none() {
                    self.actors[i].phase = "dead";
                }
            }
        }
        for ci in 0..self.companies.len() {
            self.launch_pending(ci);
            let c = self.companies[ci].clone();
            if ["lost", "recovered", "embarked"].contains(&c.stage) {
                if matches!(c.stage, "embarked" | "recovered") {
                    if let Some(p) = self.base.core.naval.ship(c.carrier).map(|s| s.p) {
                        for id in &c.bodies {
                            if let Some(b) = self.body_mut(*id) {
                                b.p = p;
                            }
                        }
                    }
                }
                if self
                    .base
                    .core
                    .naval
                    .ship(c.carrier)
                    .is_none_or(|s| !s.alive())
                    && matches!(c.stage, "embarked" | "recovered")
                {
                    for id in &c.bodies {
                        if let Some(b) = self.body_mut(*id) {
                            b.hp = 0.;
                            b.active = true;
                        }
                    }
                    self.companies[ci].stage = "lost";
                }
                continue;
            }
            let positions = c
                .bodies
                .iter()
                .filter_map(|id| {
                    self.body(*id)
                        .filter(|b| b.hp > 0. && b.active)
                        .map(|b| b.p)
                })
                .collect::<Vec<_>>();
            if c.stage == "returning"
                && c.unit.class != "air"
                && c.unit.class != "amphibious"
                && c.bodies.iter().all(|id| {
                    self.body(*id).is_none_or(|b| b.hp <= 0.)
                        || self
                            .actors
                            .iter()
                            .any(|a| a.id == *id && a.phase == "recovered")
                })
            {
                self.companies[ci].stage = "recovered";
                continue;
            }
            if positions.is_empty() {
                if c.bodies
                    .iter()
                    .all(|id| self.body(*id).is_none_or(|b| b.hp <= 0.))
                {
                    self.companies[ci].stage = "lost";
                }
                continue;
            }
            let center =
                positions.iter().fold(P::default(), |p, q| p + *q) * (1. / positions.len() as f64);
            self.companies[ci].p = center;
            if c.stage == "withdrawing" && positions.iter().any(|p| p.dist(c.goal) < 90.) {
                let s = self
                    .base
                    .core
                    .naval
                    .ship(c.carrier)
                    .filter(|s| s.alive())
                    .map(|s| s.p);
                if s.is_some_and(|p| p.dist(self.base.geometry.beach(c.beach).unwrap().0) <= 900.)
                    && !self.transit.iter().any(|t| {
                        t.company == ci
                            && t.returning
                            && !t.passengers.is_empty()
                            && t.phase != "recovered"
                    })
                {
                    let v = vehicle(if c.transport.kind == "parachute_aircraft" {
                        "landing_craft"
                    } else {
                        c.transport.kind
                    })
                    .unwrap();
                    for batch in c.bodies.chunks(v.capacity as usize) {
                        let passengers = batch
                            .iter()
                            .filter(|id| {
                                self.body(**id).is_some_and(|b| {
                                    b.hp > 0. && b.active && b.p.dist(c.goal) < 90.
                                })
                            })
                            .copied()
                            .collect::<Vec<_>>();
                        if passengers.is_empty() {
                            continue;
                        }
                        let boarding = passengers
                            .iter()
                            .filter_map(|id| self.body(*id))
                            .fold(P::default(), |p, b| p + b.p)
                            * (1. / passengers.len() as f64);
                        let id = self.base.core.ground.id();
                        self.base.core.ground.bodies.push(Body {
                            id,
                            group: format!("recovery:{}", c.id),
                            ally: c.side == 0,
                            kind: if v.air { "helicopter" } else { "landing_craft" },
                            p: boarding,
                            hp: v.hp,
                            max: v.hp,
                            ammo: 0,
                            damage: 0.,
                            range: 0.,
                            reload: 100,
                            next: 0,
                            armor: v.armor,
                            air: v.air,
                            active: true,
                        });
                        for bid in &passengers {
                            if let Some(b) = self.body_mut(*bid) {
                                b.active = false;
                            }
                            if let Some(a) = self.actors.iter_mut().find(|a| a.id == *bid) {
                                a.phase = "returning";
                            }
                        }
                        self.transit.push(Transit {
                            id,
                            company: ci,
                            passengers,
                            vehicle: v,
                            phase: "returning",
                            goal: s.unwrap(),
                            heading: 270.,
                            returning: true,
                            drop: false,
                        });
                    }
                    if c.bodies.iter().all(|id| {
                        self.body(*id).is_none_or(|b| b.hp <= 0.)
                            || self.actors.iter().any(|a| {
                                a.id == *id && matches!(a.phase, "returning" | "recovered")
                            })
                    }) {
                        self.companies[ci].stage = "returning";
                    }
                }
            }
            if c.stage == "returning" && c.unit.class != "air" && c.unit.class != "amphibious" {
                if c.bodies.iter().all(|id| {
                    self.body(*id).is_none_or(|b| b.hp <= 0.)
                        || self
                            .actors
                            .iter()
                            .any(|a| a.id == *id && a.phase == "recovered")
                }) {
                    self.companies[ci].stage = "recovered";
                    self.companies[ci].next = frame + 200;
                }
                continue;
            }
            if c.stage == "returning" && matches!(c.unit.class, "air" | "amphibious") {
                if let Some(p) = self
                    .base
                    .core
                    .naval
                    .ship(c.carrier)
                    .filter(|s| s.alive())
                    .map(|s| s.p)
                {
                    self.companies[ci].goal = p;
                    if c.unit.class == "air" || self.companies[ci].path.is_empty() {
                        self.companies[ci].path = vec![p];
                    } else if let Some(last) = self.companies[ci].path.last_mut() {
                        *last = p;
                    }
                    for id in &c.bodies {
                        if !self
                            .body(*id)
                            .is_some_and(|b| b.hp > 0. && b.active && b.p.dist(p) < 120.)
                        {
                            continue;
                        }
                        if let Some(b) = self.body_mut(*id) {
                            b.active = false;
                        }
                        if let Some(a) = self.actors.iter_mut().find(|a| a.id == *id) {
                            a.phase = "recovered";
                        }
                    }
                    if c.bodies.iter().all(|id| {
                        self.body(*id).is_none_or(|b| b.hp <= 0.)
                            || self
                                .actors
                                .iter()
                                .any(|a| a.id == *id && a.phase == "recovered")
                    }) {
                        self.companies[ci].stage = "recovered";
                        self.companies[ci].next = frame + 200;
                        continue;
                    }
                }
            }
            let target = c.path.first().copied().unwrap_or(c.goal);
            if !c.path.is_empty()
                && c.bodies
                    .iter()
                    .filter(|id| self.body(**id).is_some_and(|b| b.active && b.hp > 0.))
                    .all(|id| {
                        self.actors.iter().any(|a| {
                            a.id == *id && a.last_waypoint.is_some_and(|p| p.dist(target) < 0.1)
                        })
                    })
            {
                self.companies[ci].path.remove(0);
            }
            if c.stage == "inserting"
                && matches!(c.unit.class, "air" | "amphibious")
                && center.dist(c.goal) < 90.
            {
                self.companies[ci].stage = "active";
                for a in self.actors.iter_mut().filter(|a| a.company == ci) {
                    a.phase = "active";
                }
            }
            for id in &c.bodies {
                let Some(old) = self.body(*id).cloned() else {
                    continue;
                };
                if old.hp <= 0. || !old.active {
                    continue;
                }
                let ai = self.actors.iter().position(|a| a.id == *id).unwrap();
                let mut a = self.actors[ai].clone();
                if a.phase == "parachuting" {
                    a.altitude = (3. * (a.air_until.saturating_sub(frame)) as f64).max(0.);
                    if frame >= a.air_until {
                        a.phase = "active";
                        if let Some(b) = self.body_mut(*id) {
                            b.air = false;
                        }
                    }
                    self.actors[ai] = a;
                    continue;
                }
                let mut goal = if c.path.len() > 1 {
                    if old.p.dist(target) < 35. + body_radius(c.unit.class) * 3. {
                        a.last_waypoint = Some(target);
                    }
                    if a.last_waypoint.is_some_and(|p| p.dist(target) < 0.1) {
                        c.path[1]
                    } else {
                        target
                    }
                } else {
                    if matches!(c.stage, "returning" | "withdrawing") {
                        target
                    } else {
                        target + a.offset
                    }
                };
                if !self.traversable_disc(goal, c.unit.class)
                    || !self.straight(old.p, goal, c.unit.class)
                {
                    // Collapse through constrained terrain before fanning out again.
                    goal = target;
                }
                if c.path.is_empty() && c.order == "hold" {
                    goal = old.p;
                }
                let delta = goal - old.p;
                let mut speed = c.unit.speed * c.speed_scale;
                if c.unit.class == "amphibious" && !inside(&self.base.core.ground.polygon, old.p) {
                    speed = vehicle("amphibious_vehicle").unwrap().speed;
                } else {
                    speed *= self.terrain.speed(old.p, c.unit.class);
                }
                if c.buff_until > frame && matches!(c.unit.ability, "rapid_march" | "coordination")
                {
                    speed *= 1.3;
                }
                let radius = body_radius(c.unit.class);
                let layer = if c.unit.class == "air" { 1 } else { 0 };
                let length = delta.dist(P::default());
                let step = (speed * DT).min(length);
                let sea =
                    matches!(c.stage, "inserting" | "returning") && c.unit.class == "amphibious";
                let mut next = old.p;
                if a.knock_until <= frame && length > 0.2 {
                    // Consistent right-hand yielding breaks two-company head-on symmetry.
                    // Short alternatives fit into queues; segment checks prevent tunnelling.
                    'steer: for fraction in [1., 0.5, 0.2] {
                        for angle in [0., 30., -30., 60., -60., 90., -90., 120., -120.] {
                            let candidate =
                                old.p + P::bearing(delta.heading() + angle) * (step * fraction);
                            let terrain_ok = self.surface_disc(candidate, c.unit.class, sea)
                                && self.surface_step(old.p, candidate, c.unit.class, sea);
                            if terrain_ok && occupancy.clear(*id, old.p, candidate, radius, layer) {
                                next = candidate;
                                break 'steer;
                            }
                        }
                    }
                    if next.dist(old.p) < 0.001 {
                        a.blocked_frames += 1;
                    } else {
                        a.blocked_frames = 0;
                    }
                }
                a.velocity = (next - old.p) * (1. / DT);
                if next.dist(old.p) > 0.01 {
                    a.heading = (next - old.p).heading();
                }
                if c.unit.class == "air" {
                    a.fuel = (a.fuel - next.dist(old.p) - 3.).max(0.);
                    if a.fuel <= 0. {
                        if let Some(b) = self.body_mut(*id) {
                            b.hp = 0.;
                        }
                    }
                }
                if let Some(b) = self.body_mut(*id) {
                    b.p = next;
                }
                occupancy.update(*id, next);
                self.actors[ai] = a;
            }
        }
    }
}
impl Terrain {
    fn new(g: &Geometry, seed: u32) -> Self {
        let mut regions = vec![];
        let mut rect = |kind: &'static str,
                        x: f64,
                        y: f64,
                        w: f64,
                        h: f64,
                        m: [f64; 3],
                        vision: f64,
                        cover: f64| {
            let p = g.point(x, y);
            let wx = w * g.half_width * 2.;
            let hy = h * g.half_height * 2.;
            regions.push(Region {
                id: format!("{kind}-{}", regions.len()),
                kind,
                polygon: vec![
                    p + P {
                        x: -wx / 2.,
                        y: -hy / 2.,
                    },
                    p + P {
                        x: wx / 2.,
                        y: -hy / 2.,
                    },
                    p + P {
                        x: wx / 2.,
                        y: hy / 2.,
                    },
                    p + P {
                        x: -wx / 2.,
                        y: hy / 2.,
                    },
                ],
                elevation_m: if kind == "cliff" { 70. } else { 0. },
                movement: json!({"infantry":m[0],"armor":m[1],"amphibious":m[2],"air":1.}),
                vision_multiplier: vision,
                cover_multiplier: cover,
            });
        };
        rect("beach", 0.10, 0.50, 0.16, 0.60, [1., 0.7, 0.9], 1., 1.);
        rect(
            "landing_zone",
            0.14,
            0.50,
            0.20,
            0.16,
            [1., 0.8, 1.],
            1.,
            1.,
        );
        rect("cliff", 0.30, 0.21, 0.035, 0.20, [0., 0., 0.], 1., 0.8);
        rect("cliff", 0.30, 0.80, 0.035, 0.16, [0., 0., 0.], 1., 0.8);
        let offset = (seed % 13) as f64 * 0.003;
        rect(
            "swamp",
            0.47,
            0.29 + offset,
            0.17,
            0.14,
            [0.48, 0.18, 0.85],
            0.85,
            0.9,
        );
        rect("river", 0.57, 0.50, 0.035, 0.75, [0., 0., 0.8], 1., 1.);
        rect("ford", 0.57, 0.50, 0.055, 0.13, [0.5, 0., 0.9], 1., 1.);
        rect("ford",0.57,0.27,0.08,0.11,[0.6,0.4,0.9],1.,1.);
        rect("ford",0.57,0.73,0.08,0.11,[0.6,0.4,0.9],1.,1.);
        rect(
            "forest",
            0.70,
            0.25,
            0.20,
            0.15,
            [0.7, 0.35, 0.5],
            0.48,
            0.65,
        );
        rect(
            "forest",
            0.76,
            0.74,
            0.15,
            0.16,
            [0.7, 0.35, 0.5],
            0.48,
            0.65,
        );
        rect("bush", 0.42, 0.63, 0.18, 0.12, [0.85, 0.75, 0.8], 0.62, 0.8);
        rect("lowland",0.25,0.5,0.20,0.28,[1.,1.,1.],1.,1.);
        rect("highland",0.78,0.27,0.19,0.15,[0.9,0.8,0.85],1.,0.8);
        rect("highland",0.78,0.75,0.16,0.17,[0.85,0.72,0.8],1.,0.75);
        rect("ramp",0.67,0.27,0.055,0.09,[0.85,0.7,0.85],1.,0.9);
        rect("ramp",0.67,0.75,0.055,0.09,[0.85,0.7,0.85],1.,0.9);
        rect("road",0.51,0.5,0.555,12./g.half_height,[1.,1.,1.],1.,1.);
        for r in &mut regions {if r.kind=="highland" {r.elevation_m=if r.id.ends_with("12"){80.}else{120.};}else if r.kind=="ramp"{r.elevation_m=40.;}}
        for (index, r) in regions.iter_mut().enumerate() {
            if r.kind == "river" {
                let mut left = vec![];
                let mut right = vec![];
                for k in 0..=12 {
                    let ny = 0.125 + k as f64 * 0.0625;
                    let phase = (k * 3 + seed as usize % 17) as f64 * 0.45;
                    let nx = 0.57 + libm::sin(phase) * 0.018;
                    left.push(g.point(nx - 0.0175, ny));
                    right.push(g.point(nx + 0.0175, ny));
                }
                right.reverse();
                left.extend(right);
                r.polygon = left;
            } else if matches!(r.kind, "forest" | "bush" | "swamp" | "cliff" | "beach" | "landing_zone" | "highland" | "lowland" | "ramp") {
                let minx = r.polygon.iter().map(|p| p.x).fold(f64::INFINITY, f64::min);
                let maxx = r
                    .polygon
                    .iter()
                    .map(|p| p.x)
                    .fold(f64::NEG_INFINITY, f64::max);
                let miny = r.polygon.iter().map(|p| p.y).fold(f64::INFINITY, f64::min);
                let maxy = r
                    .polygon
                    .iter()
                    .map(|p| p.y)
                    .fold(f64::NEG_INFINITY, f64::max);
                let center = P {
                    x: (minx + maxx) / 2.,
                    y: (miny + maxy) / 2.,
                };
                r.polygon = (0..10)
                    .map(|k| {
                        let angle = k as f64 * std::f64::consts::TAU / 10.;
                        let hash = seed
                            .wrapping_mul(1664525)
                            .wrapping_add((index as u32 + 1) * 1013)
                            .wrapping_add(k as u32 * 7919);
                        let radius = 0.78 + (hash % 23) as f64 / 100.;
                        center
                            + P {
                                x: libm::cos(angle) * (maxx - minx) / 2. * radius,
                                y: libm::sin(angle) * (maxy - miny) / 2. * radius,
                            }
                    })
                    .collect();
            }
            if r.kind == "ford" {
                let p = r.polygon.iter().copied().fold(P::default(),|a,b|a+b)*0.25;
                r.polygon = vec![
                    p + P {
                        x: -g.half_width * 0.10,
                        y: -12.,
                    },
                    p + P {
                        x: g.half_width * 0.10,
                        y: -12.,
                    },
                    p + P {
                        x: g.half_width * 0.10,
                        y: 12.,
                    },
                    p + P {
                        x: -g.half_width * 0.10,
                        y: 12.,
                    },
                ];
                r.movement = json!({"infantry":0.6,"armor":0.4,"amphibious":0.9,"air":1});
            }
        }
        Self { regions }
    }
    fn speed(&self, p: P, class: &str) -> f64 {
        if class == "air" {
            return 1.;
        }
        let ford = self
            .regions
            .iter()
            .any(|r| matches!(r.kind,"ford"|"road") && inside(&r.polygon, p));
        let key = if class == "armor" {
            "armor"
        } else if class == "amphibious" || class == "river_infantry" {
            "amphibious"
        } else {
            "infantry"
        };
        self.regions
            .iter()
            .filter(|r| inside(&r.polygon, p) && !(ford && r.kind == "river"))
            .fold(1f64, |a, r| a.min(r.movement[key].as_f64().unwrap_or(1.)))
    }
    fn concealment(&self, p: P) -> f64 {
        self.regions
            .iter()
            .filter(|r| inside(&r.polygon, p))
            .fold(1f64, |a, r| a.min(r.vision_multiplier))
    }
    fn cover(&self, p: P) -> f64 {
        self.regions
            .iter()
            .filter(|r| inside(&r.polygon, p))
            .fold(1f64, |a, r| a.min(r.cover_multiplier))
    }
}

impl Battle {
    fn advance_knockback(&mut self) {
        let frame = self.frame();
        let mut occupancy = self.occupancy();
        for i in 0..self.actors.len() {
            let a = self.actors[i].clone();
            if a.knock_until <= frame {
                continue;
            }
            if let Some(b) = self.body(a.id) {
                let old = b.p;
                let alive = b.hp > 0.;
                let class = self.companies[a.company].unit.class;
                let goal = old + a.knock_velocity * DT;
                let next = if !alive
                    || (self.surface_step(old, goal, class, false)
                        && occupancy.clear(
                            a.id,
                            old,
                            goal,
                            body_radius(class),
                            if class == "air" { 1 } else { 0 },
                        )) {
                    goal
                } else {
                    old
                };
                if let Some(b) = self.body_mut(a.id) {
                    b.p = next;
                }
                occupancy.update(a.id, next);
            }
            self.actors[i].knock_velocity = a.knock_velocity * 0.88;
        }
    }
    fn apply_blast(
        &mut self,
        p: P,
        damage: f64,
        radius: f64,
        side: u32,
        air_only: bool,
        kind: &str,
        source: &str,
        impulse: f64,
    ) {
        let frame = self.frame();
        let buffs = self
            .companies
            .iter()
            .filter(|c| c.buff_until > frame)
            .map(|c| (c.side, c.unit.ability, c.p))
            .collect::<Vec<_>>();
        let positions = self
            .deployables
            .iter()
            .filter(|d| d.active && d.hp > 0. && d.kind == "beach_position")
            .map(|d| (d.side, d.p))
            .collect::<Vec<_>>();
        let mut affected = vec![];
        for i in 0..self.base.core.ground.bodies.len() {
            let b = &self.base.core.ground.bodies[i];
            if b.ally == (side == 0)
                || !b.active
                || b.hp <= 0.
                || air_only && !b.air
                || b.p.dist(p) > radius + 20.
            {
                continue;
            }
            let id = b.id;
            let point = b.p;
            let dist = point.dist(p);
            let mut factor = body_damage_factor(kind, b.armor);
            if b.air && !air_only && kind != "air_weapon" {
                factor *= 0.3;
            }
            if self
                .actors
                .iter()
                .any(|a| a.id == id && a.phase == "parachuting")
            {
                factor *= if air_only { 2.5 } else { 1.3 };
            }
            let indirect = matches!(
                kind,
                "naval" | "mortar" | "howitzer" | "air_strike" | "mine"
            );
            if !indirect && !b.air {
                factor *= self.terrain.cover(point);
                factor *= positions
                    .iter()
                    .filter(|(s, q)| *s != side && q.dist(point) <= 140.)
                    .map(|_| 0.65f64)
                    .fold(1., f64::min);
                factor *= buffs
                    .iter()
                    .filter(|(s, k, q)| {
                        *s != side
                            && matches!(*k, "smoke" | "drop_smoke" | "hull_down")
                            && q.dist(point) < 350.
                    })
                    .map(|(_, k, _)| if *k == "hull_down" { 0.55f64 } else { 0.65 })
                    .fold(1., f64::min);
            }
            let dealt = damage * factor * (1. - 0.55 * (dist / radius.max(1.)).min(1.));
            let b = &mut self.base.core.ground.bodies[i];
            let actual = dealt.min(b.hp);
            b.hp = (b.hp - dealt).max(0.);
            affected.push(json!({"id":id,"damage":actual,"hp":b.hp,"killed":b.hp<=0.}));
            if impulse > 0. {
                if let Some(a) = self.actors.iter_mut().find(|a| a.id == id) {
                    let c = &self.companies[a.company];
                    if !matches!(c.unit.class, "air" | "armor" | "amphibious") {
                        let delta = point - p;
                        let direction = if delta.dist(P::default()) > 1. {
                            delta.unit()
                        } else {
                            P::bearing((id * 79 % 360) as f64)
                        };
                        a.knock_until = frame + 10;
                        a.knock_velocity =
                            direction * (impulse * (1. - 0.5 * (dist / radius.max(1.)).min(1.)));
                    }
                }
            }
        }
        if !air_only {
            for b in &mut self.base.core.ground.buildings {
                if b.ally != (side == 0) && b.hp > 0. && b.p.dist(p) <= radius + 60. {
                    let d = damage * structure_damage_factor(kind, &b.kind);
                    b.hp = (b.hp - d).max(0.);
                }
            }
            for d in &mut self.deployables {
                if d.side != side && d.active && d.p.dist(p) <= radius + 15. {
                    d.hp = (d.hp - damage).max(0.);
                    if d.hp <= 0. {
                        d.active = false;
                    }
                }
            }
        }
        if air_only {
            for a in &mut self.base.core.aircraft {
                if a.hp > 0.
                    && self
                        .base
                        .core
                        .naval
                        .ship(a.carrier)
                        .is_some_and(|c| c.side != side as usize)
                    && a.p.dist(p) <= radius + 45.
                {
                    a.hp = (a.hp - damage).max(0.);
                }
            }
        }
        let impact_id = self.base.core.ground.impacts.len();
        bounded(
            &mut self.base.core.ground.impacts,
            json!({"id":format!("v2-hit-{frame}-{impact_id}"),"frame":frame,"tick":frame as f64/10.,"kind":kind,"source":source,"x":p.x,"y":p.y,"radius":radius,"blast_radius_m":radius,"damage":damage,"hits":affected.len(),"affected_bodies":affected,"knockback_m":impulse}),
        );
    }
    fn shoot(&mut self) {
        let frame = self.frame();
        let mut fire = vec![];
        for a in &self.actors {
            let Some(b) = self.body(a.id) else { continue };
            let c = &self.companies[a.company];
            if !b.active
                || b.hp <= 0.
                || b.ammo == 0
                || b.next > frame
                || a.phase == "parachuting"
                || a.knock_until > frame
                || matches!(c.stage, "returning" | "withdrawing")
            {
                continue;
            }
            let side = c.side;
            let target = self
                .base
                .core
                .ground
                .bodies
                .iter()
                .filter(|t| {
                    t.ally != b.ally
                        && t.active
                        && t.hp > 0.
                        && t.p.dist(b.p) <= b.range
                        && self.actors.iter().find(|a| a.id == t.id).map_or_else(
                            || t.p.dist(b.p) < c.unit.vision,
                            |a| a.seen[side as usize],
                        )
                        && (c.unit.role == "airdefense"
                            || !t.air
                            || c.unit.class == "air"
                            || t.p.dist(b.p) < 650.)
                        && (c.unit.role == "artillery" || b.air || self.los(b.p, t.p))
                })
                .min_by(|a, d| {
                    let priority = |t: &Body| {
                        if c.unit.role == "airdefense" && t.air {
                            0.
                        } else if c.unit.role == "antiarmor" && t.armor < 0.7 {
                            0.
                        } else {
                            10000.
                        }
                    };
                    (priority(a) + a.p.dist(b.p)).total_cmp(&(priority(d) + d.p.dist(b.p)))
                })
                .map(|t| (t.p, t.air));
            let target = target.or_else(|| {
                if c.unit.role == "airdefense" {
                    None
                } else {
                    self.base
                        .core
                        .ground
                        .buildings
                        .iter()
                        .filter(|t| {
                            t.ally != b.ally
                                && t.hp > 0.
                                && t.p.dist(b.p) <= b.range
                                && (b.air || self.los(b.p, t.p))
                        })
                        .min_by(|a, d| a.p.dist(b.p).total_cmp(&d.p.dist(b.p)))
                        .map(|t| (t.p, false))
                }
            });
            if let Some((p, air)) = target {
                let (kind, radius, speed) = match c.unit.role {
                    "artillery" => ("howitzer", 150., 650.),
                    "antiarmor" => ("anti_tank", 55., 480.),
                    "airdefense" => ("air_defense", 100., 1000.),
                    "gunship" => ("air_weapon", 75., 700.),
                    _ if c.unit.class == "armor" => ("tank", 90., 1000.),
                    _ => ("rifle", 22., 1500.),
                };
                fire.push((
                    a.id,
                    b.ally,
                    b.p,
                    p,
                    b.damage,
                    radius,
                    speed,
                    air && c.unit.role == "airdefense",
                    kind,
                    c.id.clone(),
                    if self.companies.iter().any(|support| {
                        support.side == side
                            && support.buff_until > frame
                            && matches!(support.unit.ability, "coordination" | "air_coordination")
                            && support.p.dist(b.p) < 700.
                    }) {
                        (b.reload as f64 * 0.75).ceil() as u32
                    } else {
                        b.reload
                    },
                ));
            }
        }
        for (id, ally, p, target, damage, radius, speed, air, kind, source, reload) in fire {
            if self.base.shots.len() + self.base.core.ground.projectiles.len() >= 512 {
                break;
            }
            if self
                .base
                .core
                .ground
                .launch(ally, p, target, damage, radius, speed, air, kind, source)
            {
                if let Some(b) = self.body_mut(id) {
                    b.ammo -= 1;
                    b.next = frame + reload;
                }
            }
        }
    }
    fn step_projectiles(&mut self) {
        let mut impact = vec![];
        for s in &mut self.base.core.ground.projectiles {
            let delta = s.goal - s.p;
            let distance = delta.dist(P::default());
            if distance <= s.speed * DT {
                s.p = s.goal;
                impact.push(s.clone());
            } else {
                s.p = s.p + delta * (s.speed * DT / distance);
            }
        }
        self.base
            .core
            .ground
            .projectiles
            .retain(|s| s.p.dist(s.goal) > 0.01);
        for s in impact {
            let meta = self.shells.get(&s.id).cloned();
            self.apply_blast(
                s.goal,
                s.damage,
                s.radius,
                if s.ally { 0 } else { 1 },
                s.air_only,
                s.kind,
                &s.source,
                meta.as_ref().map_or(0., |m| m.impulse),
            );
        }
        let mut fort_impact = vec![];
        for s in &mut self.base.shots {
            let d = s.p.dist(s.goal);
            if d <= s.speed * DT {
                s.p = s.goal;
                fort_impact.push(s.clone());
            } else {
                s.p = s.p + (s.goal - s.p) * (s.speed * DT / d);
            }
        }
        self.base.shots.retain(|s| s.p.dist(s.goal) > 0.01);
        for s in fort_impact {
            if s.kind == "anti_ship" {
                for ship in &mut self.base.core.naval.ships {
                    if ship.side != if s.ally { 0 } else { 1 }
                        && ship.alive()
                        && ship.p.dist(s.goal)
                            <= s.radius + self.base.core.naval.data.ships[ship.def].length_m / 2.
                    {
                        let armor = self.base.core.naval.data.ships[ship.def].armor_belt;
                        ship.hp =
                            (ship.hp - s.damage * (1. / (1. + armor * 0.1)).max(0.22)).max(0.);
                    }
                }
            } else {
                self.apply_blast(
                    s.goal,
                    s.damage,
                    s.radius,
                    if s.ally { 0 } else { 1 },
                    s.kind == "air_defense",
                    s.kind,
                    &s.source,
                    if matches!(s.kind, "mortar" | "cannon") {
                        65.
                    } else {
                        0.
                    },
                );
            }
        }
        let active = self
            .base
            .core
            .ground
            .projectiles
            .iter()
            .map(|s| s.id)
            .collect::<BTreeSet<_>>();
        if self.shells.len() > 1024 {
            self.shells.retain(|id, _| active.contains(id));
        }
    }
    fn queue_shore(&mut self, side: usize, id: u32, p: P) -> E<()> {
        if !inside(&self.base.core.ground.polygon, p) {
            return Err("炮援必须指向真实陆地".into());
        }
        let s = self
            .base
            .core
            .naval
            .ship(id)
            .filter(|s| s.side == side && s.alive())
            .ok_or("炮援舰艇无效")?;
        let d = &self.base.core.naval.data.ships[s.def];
        if self.base.core.naval.salvage_gun_supply(s) == 0 || s.p.dist(p) > d.gun.range_yd[3] * YARD
        {
            return Err("舰炮缺弹或超出实际射程".into());
        }
        let relative = norm((p - s.p).heading() - s.h);
        if !d.gun.mounts.iter().enumerate().any(|(i, m)| {
            !s.gun_mount_destroyed[i]
                && (arc(relative, m.arc) || m.arc2.is_some_and(|a| arc(relative, a)))
        }) {
            return Err("目标不在实际炮座射界内".into());
        }
        self.base.core.shore.retain(|o| o.ship != id);
        self.base.core.shore.push(Shore {
            ship: id,
            target: p,
            expires: self.frame() + 900,
        });
        let _ = self
            .base
            .core
            .naval
            .cancel_realtime_gun(side, &json!({"ship":id}));
        if let Some(g) = self.base.core.ground.ships.iter_mut().find(|s| s.id == id) {
            g.aim_target = Some(p);
        }
        Ok(())
    }
    fn shore(&mut self) {
        let orders = self.base.core.shore.clone();
        for order in orders {
            let Some(ship) = self
                .base
                .core
                .naval
                .ship(order.ship)
                .filter(|s| s.alive())
                .cloned()
            else {
                self.base.core.shore.retain(|o| o.ship != order.ship);
                continue;
            };
            if self.frame() >= order.expires {
                self.base.core.shore.retain(|o| o.ship != order.ship);
                continue;
            }
            let d = self.base.core.naval.data.ships[ship.def].clone();
            let bearing = (order.target - ship.p).heading();
            let relative = norm(bearing - ship.h);
            let ready = d
                .gun
                .mounts
                .iter()
                .enumerate()
                .filter(|(i, m)| {
                    !ship.gun_mount_destroyed[*i]
                        && (arc(relative, m.arc) || m.arc2.is_some_and(|a| arc(relative, a)))
                })
                .map(|(i, m)| (i, m.barrels))
                .collect::<Vec<_>>();
            for (i, _) in &ready {
                self.base
                    .core
                    .naval
                    .train_illumination_mount(ship.id, *i, bearing);
            }
            let ready = ready
                .into_iter()
                .filter(|(i, _)| {
                    let s = self.base.core.naval.ship(ship.id).unwrap();
                    self.base.core.naval.turret_loaded(s, *i)
                        && self.base.core.naval.illumination_aligned(s, *i, bearing)
                })
                .collect::<Vec<_>>();
            let count = ready.iter().map(|(_, n)| *n).sum::<u32>();
            if count == 0
                || self.base.shots.len() + self.base.core.ground.projectiles.len() + count as usize
                    > 512
                || self.base.core.naval.salvage_gun_supply(&ship) == 0
            {
                continue;
            }
            let caliber = d.gun.caliber_mm;
            let damage = 0.012 * libm::pow(caliber, 1.8);
            let radius = (caliber * 0.55).max(35.);
            let impulse = (caliber * 0.7).min(300.);
            for (i, n) in ready {
                self.base.core.naval.reserve_illumination_mount(ship.id, i);
                for barrel in 0..n {
                    let target = order.target
                        + P {
                            x: (barrel as f64 - (n - 1) as f64 / 2.) * 12.,
                            y: 0.,
                        };
                    if !self.base.core.ground.launch(
                        ship.side == 0,
                        ship.p,
                        target,
                        damage,
                        radius,
                        900.,
                        false,
                        "naval",
                        format!("ship:{}", ship.id),
                    ) {
                        continue;
                    }
                    let shot = self.base.core.ground.projectiles.last().unwrap();
                    let meta = ShellMeta {
                        id: shot.id,
                        caliber,
                        mount: i as u32,
                        barrel,
                        count: 1,
                        origin: ship.p,
                        goal: target,
                        radius,
                        damage,
                        impulse,
                        flight: ship.p.dist(target) / 900.,
                    };
                    self.shells.insert(shot.id, meta.clone());
                    let row = self.base.core.ground.shots.back_mut().unwrap();
                    row["caliber_mm"] = json!(caliber);
                    row["mount"] = json!(i);
                    row["barrel"] = json!(barrel);
                    row["barrels"] = json!(n);
                    row["shell_count"] = json!(1);
                    row["launch_point"] = json!(ship.p);
                    row["impact_point"] = json!(target);
                    row["flight_seconds"] = json!(meta.flight);
                    row["blast_radius_m"] = json!(radius);
                    row["knockback_m"] = json!(impulse);
                }
            }
            self.base.core.shore.retain(|o| o.ship != ship.id);
            self.base.core.ground.event(
                "support_fired",
                "真实各炮管分别发射岸援炮弹，消耗共享舰炮弹药",
                order.target,
            );
        }
    }
    fn tower_step(&mut self) {
        let frame = self.frame();
        let mut fires = vec![];
        let mut repairs = vec![];
        for (i, b) in self.base.core.ground.buildings.iter().enumerate() {
            let Some(s) = spec(&b.kind) else { continue };
            if b.hp <= 0. || b.ammo == 0 || frame < b.next || s.damage == 0. {
                continue;
            }
            let side = if b.ally { 0 } else { 1 };
            if s.kind == "repair" {
                if let Some((j, _)) = self
                    .base
                    .core
                    .ground
                    .buildings
                    .iter()
                    .enumerate()
                    .filter(|(j, t)| {
                        *j != i
                            && t.ally == b.ally
                            && t.hp > 0.
                            && t.hp < t.max
                            && t.p.dist(b.p) <= s.range
                    })
                    .min_by(|(_, a), (_, d)| (a.hp / a.max).total_cmp(&(d.hp / d.max)))
                {
                    repairs.push((i, j, s.damage));
                }
                continue;
            }
            let target = if s.kind == "anti_ship" {
                let contacts = &self.base.core.naval.contacts[side];
                self.base
                    .core
                    .naval
                    .ships
                    .iter()
                    .filter(|t| {
                        t.side != side
                            && t.alive()
                            && t.p.dist(b.p) <= s.range
                            && t.p.dist(b.p) >= s.min
                            && contacts.iter().any(|c| c.ship == t.id)
                    })
                    .min_by(|a, d| a.p.dist(b.p).total_cmp(&d.p.dist(b.p)))
                    .map(|t| t.p)
            } else {
                self.base
                    .core
                    .ground
                    .bodies
                    .iter()
                    .filter(|t| {
                        t.ally != b.ally
                            && t.hp > 0.
                            && t.active
                            && (s.kind != "air_defense" || t.air)
                            && t.p.dist(b.p)
                                <= s.range
                                    * (if t.air {
                                        1.
                                    } else {
                                        self.terrain.concealment(t.p)
                                    })
                            && t.p.dist(b.p) >= s.min
                            && (s.kind == "mortar" || t.air || self.los(b.p, t.p))
                            && self
                                .actors
                                .iter()
                                .find(|a| a.id == t.id)
                                .is_none_or(|a| a.seen[side])
                    })
                    .min_by(|a, d| a.p.dist(b.p).total_cmp(&d.p.dist(b.p)))
                    .map(|t| t.p)
                    .or_else(|| {
                        if s.kind == "air_defense" {
                            self.base
                                .core
                                .aircraft
                                .iter()
                                .filter(|a| {
                                    a.hp > 0.
                                        && self
                                            .base
                                            .core
                                            .naval
                                            .ship(a.carrier)
                                            .is_some_and(|c| c.side != side)
                                        && a.p.dist(b.p) <= s.range
                                })
                                .min_by(|a, d| a.p.dist(b.p).total_cmp(&d.p.dist(b.p)))
                                .map(|a| a.p)
                        } else {
                            None
                        }
                    })
            };
            if let Some(p) = target {
                fires.push((i, p, s));
            }
        }
        for (i, j, hp) in repairs {
            let b = &mut self.base.core.ground.buildings[j];
            b.hp = (b.hp + hp).min(b.max);
            let source = &mut self.base.core.ground.buildings[i];
            source.ammo -= 1;
            source.next = frame + 30;
        }
        for (i, p, s) in fires {
            if self.base.shots.len() + self.base.core.ground.projectiles.len() >= 512 {
                break;
            }
            let b = &mut self.base.core.ground.buildings[i];
            b.ammo -= 1;
            b.next = frame + s.reload;
            let shot = FortShot {
                id: format!("fort-{}-{frame}", b.id),
                p: b.p,
                goal: p,
                ally: b.ally,
                kind: s.kind,
                damage: s.damage * (1. + (b.level - 1) as f64 * 0.12) * if b.ally {1.}else{self.training_shore_scale},
                radius: s.radius,
                speed: s.speed,
                source: b.id.clone(),
            };
            bounded(
                &mut self.base.core.ground.shots,
                json!({"id":shot.id,"frame":frame,"tick":frame as f64/10.,"kind":shot.kind,"source":shot.source,"side":if shot.ally{"allies"}else{"axis"},"x":shot.p.x,"y":shot.p.y,"target_x":p.x,"target_y":p.y,"damage":shot.damage,"radius":shot.radius,"speed":shot.speed}),
            );
            self.base.shots.push(shot);
        }
    }
    fn mines(&mut self) {
        let triggers =
            self.deployables
                .iter()
                .enumerate()
                .filter(|(_, d)| d.active && d.hp > 0. && d.kind != "beach_position")
                .filter_map(|(i, d)| {
                    let hit =
                        if d.kind == "sea_mine" {
                            self.base.core.naval.ships.iter().any(|s| {
                                s.side != d.side as usize && s.alive() && s.p.dist(d.p) < 100.
                            })
                        } else {
                            self.base.core.ground.bodies.iter().any(|b| {
                                b.ally != (d.side == 0)
                                    && b.active
                                    && b.hp > 0.
                                    && !b.air
                                    && b.p.dist(d.p) < 65.
                            })
                        };
                    hit.then_some((i, d.kind, d.p, d.side, d.id.clone()))
                })
                .collect::<Vec<_>>();
        for (i, k, p, side, id) in triggers {
            self.deployables[i].active = false;
            if k == "sea_mine" {
                for s in &mut self.base.core.naval.ships {
                    if s.side != side as usize && s.alive() && s.p.dist(p) < 180. {
                        s.hp = (s.hp - 180.).max(0.);
                    }
                }
            } else {
                self.apply_blast(p, 140., 100., side, false, "mine", &id, 90.);
            }
            self.base.core.ground.event(
                "mine_triggered",
                "已布设的有限地雷/水雷被实际接近实体触发",
                p,
            );
        }
    }
    fn ability(&mut self, ci: usize, p: P) -> E<()> {
        let c = self.companies[ci].clone();
        let frame = self.frame();
        if c.stage != "active"
            || c.charges == 0
            || frame < c.next
            || p.dist(c.p) > 1600.
            || !self.actors.iter().any(|a| {
                a.company == ci
                    && a.phase == "active"
                    && self.body(a.id).is_some_and(|b| b.active && b.hp > 0.)
            })
        {
            return Err("技能未就绪、未上岸或目标超距".into());
        }
        let kind = c.unit.ability;
        match kind {
            "triage" | "rescue" | "field_repair" => {
                let mut pool = (if kind == "field_repair" { 500. } else { 250. }) * c.support_scale;
                for b in &mut self.base.core.ground.bodies {
                    if pool <= 0. {
                        break;
                    }
                    if b.ally == (c.side == 0) && b.active && b.hp > 0. && b.p.dist(p) < 400. {
                        let need = (b.max - b.hp).min(pool).min(b.max * 0.35);
                        b.hp += need;
                        pool -= need;
                    }
                }
            }
            "resupply" => {
                let mut reserve = self.companies[ci].reserve;
                for b in &mut self.base.core.ground.bodies {
                    if b.ally == (c.side == 0) && b.active && b.hp > 0. && b.p.dist(p) < 450. {
                        let need = 40u32.saturating_sub(b.ammo).min(reserve);
                        b.ammo += need;
                        reserve -= need;
                    }
                }
                self.companies[ci].reserve = reserve;
            }
            "at_missile" | "air_rockets" | "barrage" | "precision" | "breach" | "aa_burst" => {
                let (damage, radius, air) = match kind {
                    "at_missile" => (150., 80., false),
                    "air_rockets" => (100., 180., false),
                    "barrage" => (180., 240., false),
                    "precision" => (180., 35., false),
                    "aa_burst" => (130., 240., true),
                    _ => (220., 150., false),
                };
                if self.companies[ci].bodies.iter().all(|id| {
                    self.body(*id)
                        .is_none_or(|b| !b.active || b.hp <= 0. || b.ammo < 2)
                }) {
                    return Err("技能需要实际弹药".into());
                }
                let bid = self.companies[ci]
                    .bodies
                    .iter()
                    .copied()
                    .find(|id| self.body(*id).is_some_and(|b| b.hp > 0. && b.ammo >= 2))
                    .unwrap();
                if self.base.shots.len() + self.base.core.ground.projectiles.len() >= 512
                    || !self.base.core.ground.launch(
                        c.side == 0,
                        c.p,
                        p,
                        damage,
                        radius,
                        600.,
                        air,
                        if air { "air_defense" } else { "ability" },
                        c.id.clone(),
                    )
                {
                    return Err("飞行弹药预算已满".into());
                }
                self.body_mut(bid).unwrap().ammo -= 2;
            }
            _ => {
                self.companies[ci].buff_until = frame + 120;
                if matches!(kind, "recon_mark" | "jam") {
                    for a in &mut self.actors {
                        if let Some(b) = self.base.core.ground.bodies.iter().find(|b| b.id == a.id)
                        {
                            if b.ally != (c.side == 0) && b.p.dist(p) < 600. {
                                a.seen[c.side as usize] = true;
                                self.revealed[c.side as usize].insert(b.id);
                            }
                        }
                    }
                }
                if matches!(kind, "suppression" | "jam") {
                    for b in &mut self.base.core.ground.bodies {
                        if b.ally != (c.side == 0) && b.active && b.hp > 0. && b.p.dist(p) < 400. {
                            b.next = b.next.max(frame + 35);
                        }
                    }
                }
            }
        }
        self.companies[ci].charges -= 1;
        self.companies[ci].next = frame + 200;
        self.base
            .core
            .ground
            .event("tactical_ability", ability_name_v2(kind), p);
        Ok(())
    }
}
fn ability_description(id: &str) -> &str {
    match id {
        "triage" | "rescue" => {
            "400米内共享250点有限治疗量，每个存活身体最多恢复35%耐久；不能复活。"
        }
        "field_repair" => "400米内共享500点有限抢修量，每个存活身体最多恢复35%耐久；不能重造。",
        "resupply" => "450米内从本连有限储备补充弹药，每个身体最多补至40发。",
        "at_missile" => "实际消耗2发弹药，发射150伤害、80米爆炸半径的导弹。",
        "air_rockets" => "实际消耗2发弹药，发射100伤害、180米爆炸半径的火箭弹。",
        "barrage" => "实际消耗2发弹药，发射180伤害、240米爆炸半径的间接火力。",
        "precision" => "实际消耗2发弹药，发射180伤害、35米爆炸半径的精确弹。",
        "aa_burst" => "实际消耗2发弹药，发射130伤害、240米作用半径的对空弹；只攻击空中实体。",
        "breach" => "实际消耗2发弹药，发射220伤害、150米爆炸半径的破障弹。",
        "smoke" | "drop_smoke" => "持续12秒：350米内友方直射受伤系数降至65%，并降低被发现距离；舰炮、迫击炮等间接爆炸不受此减伤。",
        "hull_down" => "持续12秒：350米内友方直射受伤系数降至55%；间接爆炸不受此减伤。",
        "suppression" => "400米内敌方下一次开火最少推迟3.5秒；不凭空造成伤害。",
        "jam" => "400米内敌方开火最少推迟3.5秒，持续12秒降低本连被发现距离。",
        "recon_mark" => "持续12秒获得本连1800米内实际实体的主动侦察回波；普通被动观察仍受地形视线限制。",
        "rapid_march" => "持续12秒：本连移动速度提高30%，仍受地形与碰撞限制。",
        "coordination" => "持续12秒：700米内友军装填时间缩至75%，本连移动速度提高30%。",
        "air_coordination" => "持续12秒：700米内友军装填时间缩至75%；六机使用自身有限弹药。",
        _ => "有限次数的战术技能。",
    }
}
fn ability_name_v2(id: &str) -> &str {
    match id {
        "self_dressing" => "战地自救",
        "drop_smoke" => "伞降烟幕",
        "air_coordination" => "六机协同",
        "suppression" => "压制射击",
        "field_repair" => "战地抢修",
        "hull_down" => "稳固车体",
        "smoke" => "烟幕掩护",
        "recon_mark" => "前沿侦察",
        "air_rockets" => "火箭齐射",
        "jam" => "电磁压制",
        "triage" => "战地救护",
        "at_missile" => "反装甲导弹",
        "barrage" => "炮兵急袭",
        "rapid_march" => "两栖突进",
        "resupply" => "有限弹药补给",
        "precision" => "精确狙击",
        "aa_burst" => "防空拦截",
        "breach" => "爆破破障",
        "coordination" => "联合指挥",
        "rescue" => "空中救护",
        _ => "战术协同",
    }
}

impl Battle {
    fn objective(&self) -> P {
        self.base
            .warehouses
            .iter()
            .enumerate()
            .find(|(i, _)| !self.captured_store.contains(i))
            .map(|(_, w)| self.base.core.ground.buildings[w.building].p)
            .unwrap_or_else(|| {
                self.base
                    .core
                    .ground
                    .buildings
                    .iter()
                    .find(|b| b.kind == "hq")
                    .unwrap()
                    .p
            })
    }
    fn land_complete(&self) -> bool {
        self.captured >= 100 && self.captured_store.len() == self.base.warehouses.len()
    }
    fn all_recovered(&self, side: u32) -> bool {
        self.companies
            .iter()
            .filter(|c| c.side == side)
            .all(|c| ["recovered", "embarked", "lost"].contains(&c.stage))
    }
    fn captures(&mut self) {
        let side = self.attack();
        let frame = self.frame();
        let alive = self
            .actors
            .iter()
            .filter_map(|a| {
                self.body(a.id)
                    .filter(|b| b.active && b.hp > 0. && !b.air && a.phase == "active")
                    .map(|b| (self.companies[a.company].side, b.p, a.company))
            })
            .collect::<Vec<_>>();
        let hq = self
            .base
            .core
            .ground
            .buildings
            .iter()
            .find(|b| b.kind == "hq")
            .unwrap()
            .p;
        let control = |p: P| {
            alive.iter().any(|(s, q, _)| *s == side && q.dist(p) < 270.)
                && !alive.iter().any(|(s, q, _)| *s != side && q.dist(p) < 400.)
        };
        if control(hq) {
            self.captured = (self.captured + 1).min(100);
        }
        for i in 0..self.base.warehouses.len() {
            if self.captured_store.contains(&i) {
                continue;
            }
            let p = self.base.core.ground.buildings[self.base.warehouses[i].building].p;
            if control(p) {
                self.warehouse_capture[i] += 1;
                if self.warehouse_capture[i] >= 60 {
                    self.captured_store.insert(i);
                    let mut stock = self.base.warehouses[i].stock.clone();
                    if self.base.core.ground.buildings[self.base.warehouses[i].building].hp <= 0. {
                        stock = stock.part(1, 4);
                    }
                    self.plundered.add(&stock);
                    self.base.warehouses[i].captured = true;
                    self.base.warehouses[i].holder = alive
                        .iter()
                        .find(|(s, q, _)| *s == side && q.dist(p) < 270.)
                        .map(|(_, _, ci)| self.companies[*ci].id.clone());
                    self.base.core.ground.event(
                        "warehouse_captured",
                        "实际控制仓储，有限物资等待撤收",
                        p,
                    );
                }
            } else {
                self.warehouse_capture[i] = self.warehouse_capture[i].saturating_sub(1);
            }
        }
        if self.start.mode == "defense" && self.captured >= 100 {
            self.finish(false, false);
            return;
        }
        let attacker_alive = self.companies.iter().filter(|c| c.side == side).any(|c| {
            c.bodies
                .iter()
                .any(|id| self.body(*id).is_some_and(|b| b.hp > 0.))
        });
        let enemy_fleet = self
            .base
            .core
            .naval
            .ships
            .iter()
            .any(|s| s.side == side as usize && s.alive());
        if self.start.mode == "defense"
            && (!attacker_alive
                || self.all_recovered(side)
                    && self
                        .companies
                        .iter()
                        .filter(|c| c.side == side)
                        .any(|c| c.stage == "recovered"))
            && !enemy_fleet
        {
            self.finish(true, false);
        } else if self.start.mode != "defense"
            && self.land_complete()
            && self.all_recovered(0)
            && self
                .base
                .core
                .naval
                .ships
                .iter()
                .filter(|s| s.side == 1)
                .all(|s| !s.alive())
        {
            self.finish(true, false);
        } else if self
            .base
            .core
            .naval
            .ships
            .iter()
            .filter(|s| s.side == 0)
            .all(|s| !s.alive())
            || frame >= LIMIT
        {
            self.finish(false, false);
        }
    }
    fn finish(&mut self, success: bool, abandoned: bool) {
        if self.result.is_some() {
            return;
        }
        let mut units = vec![];
        let mut company_rows = vec![];
        for c in self.companies.iter().filter(|c| c.side == 0) {
            let sum = c
                .bodies
                .iter()
                .filter_map(|id| self.body(*id))
                .map(|b| b.hp)
                .sum::<f64>();
            let max = c
                .bodies
                .iter()
                .filter_map(|id| self.body(*id))
                .map(|b| b.max)
                .sum::<f64>();
            let survivors = c
                .bodies
                .iter()
                .filter(|id| self.body(**id).is_some_and(|b| b.hp > 0.))
                .count();
            let recovered = c.stage == "recovered"
                || c.stage == "embarked"
                || self.start.mode == "defense" && success;
            company_rows.push(json!({"id":c.id,"company_id":c.id,"unit_id":c.unit.id,"company_name":format!("{} 第{}连",c.unit.designation,c.id.rsplit('C').next().unwrap_or("01")),"hp_percent":if recovered{sum/max.max(1.)*100.}else{0.},"field_hp_percent":sum/max.max(1.)*100.,"initial_hp_percent":c.initial,"initial_count":c.initial_count,"surviving_count":survivors,"recovered":recovered,"missing":!recovered&&survivors>0,"incapacitated":sum/max.max(1.)<0.1}));
        }
        for id in &self.start.roster {
            let rows = company_rows
                .iter()
                .filter(|r| r["unit_id"] == *id)
                .collect::<Vec<_>>();
            let total = rows
                .iter()
                .map(|r| r["initial_count"].as_u64().unwrap())
                .sum::<u64>();
            let hp = rows
                .iter()
                .map(|r| {
                    r["hp_percent"].as_f64().unwrap() * r["initial_count"].as_u64().unwrap() as f64
                })
                .sum::<f64>()
                / total.max(1) as f64;
            units.push(json!({"id":id,"unit_id":id,"hp_percent":hp,"initial_hp_percent":rows[0]["initial_hp_percent"],"initial_count":total,"surviving_count":rows.iter().map(|r|r["surviving_count"].as_u64().unwrap()).sum::<u64>(),"recovered":rows.iter().any(|r|r["recovered"]==true),"recovered_hp_percent":hp,"missing":!rows.iter().any(|r|r["recovered"]==true)&&rows.iter().any(|r|r["missing"]==true),"partial_missing":rows.iter().any(|r|r["missing"]==true),"incapacitated":hp<10.,"companies":rows}));
        }
        let exercise = self.start.mode == "exercise";
        let resources = if exercise || !success || abandoned {
            Stock::default()
        } else if self.start.mode == "defense" {
            Stock {
                credits: 80 + self.base.npc as u32 * 40,
                scrap: 20 + self.base.npc as u32 * 10,
                ..Stock::default()
            }
        } else {
            self.plundered.clone()
        };
        let ships=self.base.core.naval.ships.iter().filter(|s|s.side==0).map(|s|json!({"id":self.base.core.naval.data.ships[s.def].id,"ship":s.id,"hp_percent":s.hp/self.base.core.naval.data.ships[s.def].dp*100.,"ammo_percent":self.base.core.naval.salvage_gun_supply(s),"lost":!s.alive(),"recovered":s.alive()})).collect::<Vec<_>>();
        self.result = Some(
            json!({"version":VERSION,"mode":self.start.mode,"success":success,"abandoned":abandoned,"tick":self.frame()as f64/10.,"units":units,"companies":company_rows,"ships":ships,"buildings":self.base.core.ground.buildings.iter().map(|b|json!({"id":b.id,"kind":b.kind,"hp_percent":b.hp/b.max*100.,"hp":b.hp,"max_hp":b.max,"destroyed":b.hp<=0.})).collect::<Vec<_>>(),"company_layout":MULTI,"objective_complete":self.land_complete(),"island_secured":success&&self.start.mode!="defense","resources":resources,"exercise":exercise,"settle_allowed":!exercise,"island_war":{"version":VERSION,"npc_id":self.start.island.npc_id,"island_level":self.base.geometry.level,"local_simulation":true,"exercise":exercise,"plundered":if exercise{Stock::default()}else{self.plundered.clone()},"initial_exposed":self.base.stock,"hq_capture":self.captured as f64/100.,"warehouses_captured":self.captured_store.len(),"unit_xp":if exercise{0}else if success{50}else{10},"source_kind":"original_fictional"}}),
        );
    }
    fn ai(&mut self) {
        let frame = self.frame();
        if frame % 40 != 0 {
            return;
        }
        self.last_ai = frame;
        let objective = self.objective();
        let complete = self.land_complete();
        let mut routed=BTreeSet::new();
        for ci in 0..self.companies.len(){let c=self.companies[ci].clone();
            if !c.pending||(c.side==0&&!self.auto)||!routed.insert(c.carrier)||self.companies.iter().any(|o|o.carrier==c.carrier&&matches!(o.stage,"withdrawing"|"returning")){continue}
            let sea=self.base.geometry.beach(c.beach).unwrap().0;
            if self.base.core.naval.ship(c.carrier).is_some_and(|s|s.alive()&&s.p.dist(sea)>900.&&s.fleet.and_then(|f|self.base.core.naval.fleet(f)).is_some_and(|f|f.points.is_empty())){let _=self.route_carrier(ci,sea);}
        }
        for ci in 0..self.companies.len() {
            let c = self.companies[ci].clone();
            if c.side == 0 && !self.auto {
                continue;
            }
            if c.stage == "recovered"
                && c.unit.class == "air"
                && !complete
                && self.posture != "withdraw"
                && c.reserve > 0
                && frame >= c.next
            {
                let mut reserve = c.reserve;
                for id in &c.bodies {
                    if let Some(b) = self.body_mut(*id) {
                        if b.hp > 0. {
                            let n = c.unit.ammo.saturating_sub(b.ammo).min(reserve);
                            b.ammo += n;
                            reserve -= n;
                        }
                    }
                    if let Some(a) = self.actors.iter_mut().find(|a| a.id == *id) {
                        a.fuel = 24000.;
                    }
                }
                self.companies[ci].reserve = reserve;
                let _ = self.deploy(ci, c.beach, None);
                continue;
            }
            if c.stage == "embarked" && !c.pending {
                if self.posture == "withdraw" && c.side == 0 {
                    continue;
                }
                let ship=self.base.core.naval.ship(c.carrier).map_or(c.p,|s|s.p);
                let beach=(1..=3).min_by(|a,b|ship.dist(self.base.geometry.beach(*a).unwrap().0).total_cmp(&ship.dist(self.base.geometry.beach(*b).unwrap().0))).unwrap();
                let _ = self.deploy(ci, beach, None);
                continue;
            }
            if c.stage == "inserting"
                || c.stage == "returning"
                || c.stage == "withdrawing"
                || c.stage == "lost"
                || c.stage == "recovered"
            {
                continue;
            }
            let health = c
                .bodies
                .iter()
                .filter_map(|id| self.body(*id))
                .map(|b| b.hp / b.max)
                .sum::<f64>()
                / c.bodies.len().max(1) as f64;
            let ammo = c
                .bodies
                .iter()
                .filter_map(|id| self.body(*id))
                .map(|b| b.ammo)
                .sum::<u32>();
            let fuel = self
                .actors
                .iter()
                .filter(|a| a.company == ci)
                .map(|a| a.fuel)
                .fold(f64::INFINITY, f64::min);
            if (c.side == 0 && self.posture == "withdraw")
                || (c.side == self.attack() && complete)
                || health < 0.23
                || ammo == 0
                || c.unit.class == "air" && fuel < 5000.
            {
                let _ = self.withdraw(ci);
                continue;
            }
            let target = self
                .actors
                .iter()
                .filter(|a| a.seen[c.side as usize])
                .filter_map(|a| {
                    self.body(a.id)
                        .filter(|b| b.ally != (c.side == 0) && b.active && b.hp > 0.)
                        .map(|b| b.p)
                })
                .min_by(|a, b| a.dist(c.p).total_cmp(&b.dist(c.p)));
            let goal = if let Some(t) = target {
                let d = c.p.dist(t);
                if d <= c.unit.range * 0.7 {
                    c.p
                } else {
                    t + (c.p - t).unit() * (c.unit.range * 0.55)
                }
            } else if c.side == self.attack() {
                objective
            } else {
                self.base
                    .core
                    .ground
                    .buildings
                    .iter()
                    .filter(|b| b.kind == "hq")
                    .map(|b| b.p)
                    .next()
                    .unwrap()
            };
            if goal.dist(c.goal) > 110. || c.path.is_empty() && c.p.dist(goal) > 100. {
                let _ = self.set_goal(
                    ci,
                    goal,
                    if target.is_some() {
                        "attack"
                    } else {
                        "advance"
                    },
                );
            }
            if c.charges > 0 && frame >= c.next {
                let skillpoint = target.unwrap_or(c.p);
                let _ = self.ability(ci, skillpoint);
            }
            if c.unit.role == "engineer"
                && c.tools > 0
                && frame % 200 == 0
                && self.traversable(c.p, "infantry")
            {
                let kind = if c.side == self.guard() {
                    "beach_position"
                } else {
                    "land_mine"
                };
                let id = format!("ai-{}-{frame}", c.id);
                if self.add_deployable(id, kind, c.side, c.p).is_ok() {
                    self.companies[ci].tools -= 1;
                }
            }
        }
        // Actual ships use the unchanged naval World. A carrier transporting a
        // queued company keeps its explicit approach route; other ships may fight.
        for side in 0..2usize {
            if side == 0 && !self.auto {
                continue;
            }
            let occupied = self
                .companies
                .iter()
                .filter(|c| {
                    c.side == side as u32
                        && (c.pending || matches!(c.stage, "withdrawing" | "returning"))
                })
                .map(|c| c.carrier)
                .collect::<BTreeSet<_>>();
            for f in &mut self.base.core.naval.fleets {
                if f.side != side || occupied.contains(&f.leader) {
                    continue;
                }
                f.ai = crate::model::Ai::new("coord", "auto");
                f.ai.torpedo = false;
            }
            let contacts = self.base.core.naval.observation(side)["contacts"]
                .as_array()
                .cloned()
                .unwrap_or_default();
            let target = self
                .actors
                .iter()
                .filter(|a| a.seen[side])
                .filter_map(|a| {
                    self.body(a.id)
                        .filter(|b| b.ally != (side == 0) && b.hp > 0. && b.active)
                        .map(|b| b.p)
                })
                .next()
                .or_else(|| (side as u32 == self.attack()).then_some(objective));
            if side == 0 {
                if let Some(p) = target {
                    let ships = self
                        .base
                        .core
                        .naval
                        .ships
                        .iter()
                        .filter(|s| s.side == 0 && s.alive())
                        .map(|s| s.id)
                        .collect::<Vec<_>>();
                    for id in ships {
                        if self.base.core.shore.iter().any(|o| o.ship == id) {
                            continue;
                        }
                        if self.base.core.shore_plan(id, p).is_ok() {
                            let _ = self.queue_shore(0, id, p);
                        }
                    }
                }
            } else if let Some(p) = target {
                let ships = self
                    .base
                    .core
                    .naval
                    .ships
                    .iter()
                    .filter(|s| s.side == side && s.alive())
                    .map(|s| s.id)
                    .collect::<Vec<_>>();
                for id in ships {
                    if !self.base.core.shore.iter().any(|o| o.ship == id) {
                        let _ = self.queue_shore(side, id, p);
                    }
                }
            }
            let ready = self
                .base
                .core
                .squadrons
                .iter()
                .enumerate()
                .filter(|(_, s)| {
                    self.base
                        .core
                        .naval
                        .ship(s.carrier)
                        .is_some_and(|c| c.side == side && c.alive())
                        && !(side==0&&self.base.core.carrier_is_v3())
                        && s.available > 0
                        && s.stock > 0
                        && s.ready <= frame
                })
                .map(|(i, _)| i)
                .collect::<Vec<_>>();
            for i in ready {
                let shipcontact = contacts.first();
                if let Some(c) = shipcontact {
                    let _ = self.base.core.launch_air(
                        i,
                        "strike",
                        point(c),
                        "ship".into(),
                        c["id"].clone(),
                    );
                } else if let Some(p) = target {
                    let _ = self
                        .base
                        .core
                        .launch_air(i, "strike", p, "land".into(), Value::Null);
                }
            }
        }
        if self.auto
            && self.posture == "withdraw"
            && self.all_recovered(0)
            && !self.base.core.aircraft.iter().any(|a| {
                self.base
                    .core
                    .naval
                    .ship(a.carrier)
                    .is_some_and(|s| s.side == 0)
            })
        {
            self.finish(false, false);
        }
    }
    fn advance(&mut self) {
        if self.result.is_some() {
            return;
        }
        self.base.core.ground.frame += 1;
        if self.transit.len() > 128 {
            let retired = self
                .transit
                .iter()
                .filter(|t| matches!(t.phase, "lost" | "recovered"))
                .map(|t| t.id)
                .collect::<BTreeSet<_>>();
            self.base
                .core
                .ground
                .bodies
                .retain(|b| !retired.contains(&b.id));
            self.transit.retain(|t| !retired.contains(&t.id));
        }
        self.base.anchorage();
        if self.frame() % 10 == 0 {
            self.base.core.naval.advance();
            self.base.core.sync_from_naval();
            self.shore();
        }
        self.move_transports();
        self.advance_knockback();
        self.move_companies();
        self.observe_visibility();
        self.shoot();
        if self.frame() % 10 == 0 {
            self.tower_step();
        }
        self.step_projectiles();
        self.mines();
        if self.base.core.carrier_is_v3(){self.base.core.carrier_v3_observe_land(self.view());}
        self.base.core.advance_air();
        self.base.core.sync_to_naval();
        self.base.core.record_corpses();
        for row in &mut self.base.core.corpses {
            if let Some(b) = row["id"].as_u64().and_then(|id| {
                self.base
                    .core
                    .ground
                    .bodies
                    .iter()
                    .find(|b| b.id as u64 == id)
            }) {
                row["x"] = json!(b.p.x);
                row["y"] = json!(b.p.y);
            }
        }
        self.captures();
        if self.result.is_none() {
            self.ai();
        }
    }
}

impl Battle {
    fn position(q: &Value) -> E<P> {
        let x = q["x"]
            .as_f64()
            .filter(|n| n.is_finite())
            .ok_or("目标横坐标无效")?;
        let y = q["y"]
            .as_f64()
            .filter(|n| n.is_finite())
            .ok_or("目标纵坐标无效")?;
        Ok(P { x, y })
    }
    fn order(&mut self, q: &Value, record: bool) -> E<Value> {
        if self.result.is_some() {
            return Err("海岛行动已经结束".into());
        }
        if record && self.commands.len() >= 15000 {
            return Err("指令日志达到上限".into());
        }
        let op = q["op"].as_str().ok_or("缺少操作")?;
        match op {
            "littoral_support" if q["kind"] == "naval" => {
                let id = crate::world::u(q, "ship")?;
                let p = Self::position(q)?;
                self.queue_shore(0, id, p)?;
            }
            "island_autonomy" | "littoral_autonomy" => {
                if q["version"] != VERSION {
                    return Err("请选择新版战术托管规则".into());
                }
                let enabled = q["enabled"].as_bool().ok_or("托管开关无效")?;
                let posture = q
                    .get("posture")
                    .and_then(Value::as_str)
                    .unwrap_or("mission");
                if !["mission", "withdraw"].contains(&posture) {
                    return Err("托管姿态无效".into());
                }
                self.auto = enabled;
                self.posture = posture.into();
            }
            "littoral_deploy" => {
                let ci = self.company_index(q, 0)?;
                let beach = q.get("beach").and_then(Value::as_u64).unwrap_or(2);
                if !(1..=3).contains(&beach) {
                    return Err("滩头不存在".into());
                }
                let goal = if q.get("x").is_some() {
                    Some(Self::position(q)?)
                } else {
                    None
                };
                self.deploy(ci, beach as u32, goal)?;
            }
            "littoral_cancel_deploy" => {
                let ci = self.company_index(q, 0)?;
                if !self.companies[ci].pending {
                    return Err("没有待投送指令".into());
                }
                self.companies[ci].pending = false;
            }
            "littoral_order" => {
                let ci = self.company_index(q, 0)?;
                if let Some(id) = q.get("target").and_then(Value::as_u64) {
                    if self
                        .actors
                        .iter()
                        .find(|a| a.id as u64 == id)
                        .is_none_or(|a| !a.seen[0])
                    {
                        return Err("不能锁定当前未探测的战术实体".into());
                    }
                }
                let action = q["action"].as_str().unwrap_or("move");
                match action {
                    "extract" | "return" => self.withdraw(ci)?,
                    "hold" | "stop" => {
                        let p = self.companies[ci].p;
                        self.set_goal(ci, p, "hold")?;
                    }
                    "move" | "attack" | "advance" | "search" | "defend" => {
                        let p = Self::position(q)?;
                        self.set_goal(ci, p, action)?;
                    }
                    _ => return Err("行动连指令无效".into()),
                }
            }
            "littoral_ability" => {
                let ci = self.company_index(q, 0)?;
                let p = if q.get("x").is_some() {
                    Self::position(q)?
                } else {
                    self.companies[ci].p
                };
                self.ability(ci, p)?;
            }
            "island_place" => {
                let ci = self.company_index(q, 0)?;
                let c = self.companies[ci].clone();
                let p = Self::position(q)?;
                if c.stage != "active" || c.tools == 0 || c.p.dist(p) > 450. {
                    return Err("必须由在场行动连使用有限布防工具".into());
                }
                let kind = q["kind"].as_str().ok_or("请选择布防种类")?;
                let id = format!("placed-{}-{}", self.frame(), self.deployables.len());
                self.add_deployable(id, kind, 0, p)?;
                self.companies[ci].tools -= 1;
            }
            "littoral_extract" => {
                let indices = self
                    .companies
                    .iter()
                    .enumerate()
                    .filter(|(_, c)| {
                        c.side == 0 && !matches!(c.stage, "embarked" | "recovered" | "lost")
                    })
                    .map(|(i, _)| i)
                    .collect::<Vec<_>>();
                for i in indices {
                    self.withdraw(i)?;
                }
                self.auto = true;
                self.posture = "withdraw".into();
                if self.all_recovered(0) {
                    self.finish(self.land_complete(), false);
                }
            }
            "littoral_abandon" => self.finish(false, true),
            _ => {
                self.base.core.command(q, false)?;
                if self.base.core.carrier_is_v3(){self.base.core.carrier_v3_observe_land(self.view());}
            }
        }
        if record {
            if !matches!(
                op,
                "island_autonomy" | "littoral_autonomy" | "littoral_extract"
            ) {
                if !self.base.core.carrier_v3_keeps_ground_ai(q){self.auto = false;}
            }
            self.commands.push(Command {
                frame: self.frame(),
                request: q.clone(),
            });
        }
        Ok(self.view())
    }
    fn preview(&self, q: &Value) -> E<Value> {
        let kind = q["kind"].as_str().unwrap_or("deploy");
        let result = (|| -> E<()> {
            if kind == "place" {
                let ci = self.company_index(q, 0)?;
                let c = &self.companies[ci];
                let p = Self::position(q)?;
                if c.tools == 0 || c.stage != "active" || c.p.dist(p) > 450. {
                    return Err("没有就位的布防工具".into());
                }
                let k = q
                    .get("place_kind")
                    .or_else(|| q.get("deployable_kind"))
                    .and_then(Value::as_str)
                    .ok_or("请选择地雷或阵地")?;
                if k == "sea_mine" {
                    if inside(&self.base.core.ground.polygon, p) {
                        return Err("水雷必须在海水中".into());
                    }
                } else if !self.traversable(p, "infantry") {
                    return Err("布防点不是可通行陆地".into());
                }
                return Ok(());
            }
            let ci = self.company_index(q, 0)?;
            let c = &self.companies[ci];
            match kind {
                "deploy" => {
                    if !matches!(c.stage, "embarked" | "recovered") {
                        return Err("行动连已在场".into());
                    }
                    let s = self
                        .base
                        .core
                        .naval
                        .ship(c.carrier)
                        .filter(|s| s.alive())
                        .ok_or("载舰已损失")?;
                    if c.transport.air && s.p.dist(self.base.geometry.beach(2)?.1) > 9000. {
                        return Err("超出航程".into());
                    }
                }
                "move" | "order" => {
                    let _ = self.path(c.p, Self::position(q)?, c.unit.class)?;
                }
                "ability" => {
                    if c.stage != "active" || c.charges == 0 || c.next > self.frame() {
                        return Err("技能未就绪".into());
                    }
                }
                _ => return Err("预览种类无效".into()),
            }
            Ok(())
        })();
        let reason = result.err();
        Ok(
            json!({"valid":reason.is_none(),"reason":reason,"version":VERSION,"preview":true,"kind":kind}),
        )
    }
    pub(crate) fn execute(&mut self, q: &Value) -> E<Value> {
        match q["op"].as_str().ok_or("缺少操作")? {
            "observe" => Ok(self.view()),
            "save" => Ok(json!(self.save())),
            "report" => Ok(json!({"result":self.result,"littoral":self.view()["littoral"]})),
            "presentation" => Ok(self.base.core.naval.projectile_presentation(0)),
            "step" => {
                let n = frames(&q["seconds"])?;
                for _ in 0..n {
                    if self.result.is_some() {
                        break;
                    }
                    self.advance();
                }
                Ok(self.view())
            }
            "littoral_preview" => self.preview(q),
            "carrier_preview"|"carrier_mission_preview" => self.base.core.execute(q),
            "preview_route" => self.base.core.naval.preview(0, q),
            "preview_reform" => self.base.core.naval.preview_reform(0, q),
            "aim" => self.base.core.naval.preview_aim(0, q),
            "illumination_preview" => self.base.core.naval.preview_illumination(0, q),
            _ => self.order(q, true),
        }
    }
    pub(crate) fn save(&self) -> Saved {
        Saved {
            version: VERSION.into(),
            seed: self.base.core.ground.seed,
            config: self.start.clone(),
            frame: self.frame(),
            tick: self.frame() as f64 / 10.,
            commands: self.commands.clone(),
        }
    }
    fn validate_save(s: &Saved) -> E<()> {
        if s.version != VERSION
            || s.frame > LIMIT
            || !s.tick.is_finite()
            || (s.tick - s.frame as f64 / 10.).abs() > 1e-6
            || s.commands.len() > 15000
            || s.commands.iter().any(|c| c.frame > s.frame)
            || s.commands.windows(2).any(|w| w[0].frame > w[1].frame)
        {
            return Err("新版海岛录像版本、时钟或指令日志无效".into());
        }
        Ok(())
    }
    fn replay_to(&mut self, commands: &[Command], cursor: &mut usize, end: u32) -> E<()> {
        loop {
            while *cursor < commands.len()
                && commands[*cursor].frame == self.frame()
                && commands[*cursor].frame <= end
            {
                self.order(&commands[*cursor].request, true)?;
                *cursor += 1;
            }
            if self.frame() >= end {
                break;
            }
            if self.result.is_some() {
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
        let mut w = Self::new(s.seed, s.config)?;
        let mut cursor = 0;
        w.replay_to(&s.commands, &mut cursor, end)?;
        Ok(w)
    }
    pub(crate) fn view(&self) -> Value {
        let mut v = self.base.core.view();
        self.base.motion_view(&mut v);
        let frame = self.frame();
        v["version"] = json!(VERSION);
        v["naval_world"] = json!(true);
        v["scenario"] = json!(if self.start.mode == "exercise" {
            "本港海陆空攻防演习"
        } else if self.start.mode == "defense" {
            "海陆空联合岛防"
        } else {
            "海陆空联合突袭"
        });
        v["limit"] = json!(LIMIT / 10);
        v["result"] = self.result.clone().unwrap_or(Value::Null);
        let l = &mut v["littoral"];
        l["version"] = json!("cas-littoral-v4");
        l["mode"] = json!(self.start.mode);
        l["outcome"] = self.result.clone().unwrap_or(Value::Null);
        l["land"]["bounds"] = json!({"x":self.base.geometry.origin().x,"y":self.base.geometry.origin().y,"width":self.base.geometry.half_width*2.+400.,"height":self.base.geometry.half_height*2.+400.});
        let terrain = v4_terrain_view(&self.base.geometry,&self.terrain);
        l["land"]["terrain"] = terrain;
        let groups=self.companies.iter().filter(|c|c.side==0).map(|c|{let hp=c.bodies.iter().filter_map(|id|self.body(*id)).map(|b|b.hp).sum::<f64>();let max=c.bodies.iter().filter_map(|id|self.body(*id)).map(|b|b.max).sum::<f64>();let count=c.bodies.iter().filter(|id|self.body(**id).is_some_and(|b|b.hp>0.)).count();let ammo=c.bodies.iter().filter_map(|id|self.body(*id)).map(|b|b.ammo).sum::<u32>();let stage=match c.stage{"active"=>"ground","inserting"=>"transit","withdrawing"=>"returning",s=>s};json!({"id":c.id,"company_id":c.id,"unit_id":c.unit.id,"name":c.unit.name,"designation":c.unit.designation,"company_name":format!("{} · 第{}连",c.unit.designation,c.id.rsplit('C').next().unwrap_or("01")),"company_count":c.unit.companies,"personnel_per_company":c.unit.people,"personnel":count,"personnel_count":count,"entity_count":count,"initial_count":c.initial_count,"stage":stage,"phase":c.stage,"carrier":c.carrier,"x":c.p.x,"y":c.p.y,"position":if matches!(c.stage,"embarked"|"recovered"){self.base.core.naval.ship(c.carrier).map_or(c.p,|s|s.p)}else{c.p},"insertion":if c.transport.air{"air"}else{"landing"},"path":c.path,"goal":c.goal,"order":c.order,"hp":hp,"max_hp":max,"health":hp/max.max(1.),"hp_percent":hp/max.max(1.)*100.,"ammo":ammo,"ammo_capacity":c.unit.ammo*c.unit.people,"transport_kind":c.transport.kind,"vehicle_id":combat_visual(c.unit),"art_version":"tactical-art-v2","transport_capacity":c.transport.capacity,"carrier_requirement":if c.transport.air{"CV/LHA"}else if matches!(c.unit.class,"armor"|"amphibious"){"CV/LHA/APV"}else{"ANY"},"deployment_range":if c.transport.air{9000.}else{900.},"pending_deploy":if c.pending{json!({"beach":c.beach,"range_limit":if c.transport.air{9000.}else{900.}})}else{Value::Null},"ability":{"id":c.unit.ability,"name":ability_name_v2(c.unit.ability),"charges":c.charges,"ready_in":c.next.saturating_sub(frame)as f64/10.,"available":c.stage=="active"&&c.charges>0&&frame>=c.next},"tools":c.tools,"nato_type":c.unit.role,"echelon":"I"})}).collect::<Vec<_>>();
        l["groups"] = json!(groups);
        let entities=self.actors.iter().filter_map(|a|{let b=self.body(a.id)?;if !b.active{return None}let c=&self.companies[a.company];Some(json!({"id":b.id,"unit_id":c.unit.id,"company_id":c.id,"side":if c.side==0{"allies"}else{"axis"},"kind":b.kind,"x":b.p.x,"y":b.p.y,"hp":b.hp,"max_hp":b.max,"ammo":b.ammo,"range":b.range,"damage":b.damage,"ready_in":b.next.saturating_sub(frame)as f64/10.,"air":b.air,"phase":if b.hp<=0.{"dead"}else{a.phase},"physical_class":c.unit.class,"collision_radius_m":body_radius(c.unit.class),"avoidance_radius_m":body_radius(c.unit.class)+1.,"steering_wait_frames":a.blocked_frames,"vehicle_id":combat_visual(c.unit),"art_version":"tactical-art-v2","heading":a.heading,"velocity":a.velocity,"altitude_m":a.altitude,"visible":a.seen[0],"known":self.revealed[0].contains(&a.id),"fuel_remaining":if c.unit.class=="air"{Some(a.fuel)}else{None},"cover_multiplier":self.terrain.cover(b.p),"movement_multiplier":self.terrain.speed(b.p,c.unit.class),"knockback":if a.knock_until>frame{json!({"tick":a.knock_until.saturating_sub(10)as f64/10.,"duration_s":1.,"remaining_s":a.knock_until.saturating_sub(frame)as f64/10.,"height_m":a.knock_velocity.dist(P::default())*0.12,"velocity":a.knock_velocity})}else{Value::Null}}))}).collect::<Vec<_>>();
        l["land"]["entities"] = json!(entities);
        let transports=self.transit.iter().filter_map(|t|{let b=self.body(t.id)?;let c=&self.companies[t.company];Some(json!({"id":t.id,"company_id":c.id,"unit_id":c.unit.id,"side":if c.side==0{"allies"}else{"axis"},"carrier":c.carrier,"kind":t.vehicle.kind,"vehicle_id":format!("{}-{}",c.unit.id,t.vehicle.kind),"visual_id":format!("{}-{}",c.unit.id,t.vehicle.kind),"x":b.p.x,"y":b.p.y,"goal":t.goal,"heading":t.heading,"velocity":P::bearing(t.heading)*if b.active&&b.hp>0.{t.vehicle.speed}else{0.},"hp":b.hp,"max_hp":b.max,"max":b.max,"air":t.vehicle.air,"phase":t.phase,"returning":t.returning,"personnel_count":t.passengers.len(),"capacity":t.vehicle.capacity,"transport_role":if t.drop{"insertion_only"}else if t.returning&&c.transport.kind=="parachute_aircraft"{"recovery_only"}else{"both"},"status":if b.hp<=0.{"destroyed"}else if b.active{"sailing"}else{"recovered"}}))}).collect::<Vec<_>>();
        l["transports"] = json!(transports);
        l["land"]["deployables"]=json!(self.deployables.iter().map(|d|json!({"id":d.id,"kind":d.kind,"side":if d.side==0{"allies"}else{"axis"},"x":d.p.x,"y":d.p.y,"hp":d.hp,"active":d.active})).collect::<Vec<_>>());
        l["objectives"] = json!([{"id":"island_primary","kind":"secure_hq_and_warehouses","x":self.objective().x,"y":self.objective().y,"progress":self.captured as f64/100.,"complete":self.land_complete()}]);
        l["autonomy"] = json!({"version":VERSION,"enabled":self.auto,"posture":self.posture,"status":if self.auto{"海陆空指挥中"}else{"手动指挥"},"last_plan_tick":self.last_ai as f64/10.,"observation_policy":"current_side_detection_and_known_static_objectives"});
        l["budget"] = json!({"bodies":1400,"friendly_bodies":600,"enemy_bodies":600,"companies":192,"projectiles":512});
        l["shots"] = json!(self.base.core.ground.shots);
        l["impacts"] = json!(self.base.core.ground.impacts);
        for row in l["corpses"].as_array_mut().unwrap() {
            if let Some(id) = row["id"].as_u64() {
                if let Some(a) = self.actors.iter().find(|a| a.id as u64 == id) {
                    let c = &self.companies[a.company];
                    row["unit_id"] = json!(c.unit.id);
                    row["company_id"] = json!(c.id);
                    row["art_version"] = json!("tactical-art-v2");
                    row["vehicle_id"] = json!(combat_visual(c.unit));
                    row["knockback"] = if a.knock_until > frame {
                        json!({"tick":a.knock_until.saturating_sub(10)as f64/10.,"duration_s":1.,"height_m":a.knock_velocity.dist(P::default())*0.12,"remaining_s":a.knock_until.saturating_sub(frame)as f64/10.})
                    } else {
                        Value::Null
                    };
                } else if let Some(t) = self.transit.iter().find(|t| t.id as u64 == id) {
                    let c = &self.companies[t.company];
                    row["unit_id"] = json!(c.unit.id);
                    row["company_id"] = json!(c.id);
                    row["vehicle_id"] = json!(format!("{}-{}", c.unit.id, t.vehicle.kind));
                    row["kind"] = json!("transport_wreck");
                }
            }
        }
        let origin = self.base.geometry.point(0., 0.);
        let outcome = self
            .result
            .as_ref()
            .map(|r| r["island_war"].clone())
            .unwrap_or(Value::Null);
        v["island_war"] = json!({"version":VERSION,"local_simulation":true,"exercise":self.start.mode=="exercise","npc_id":self.start.island.npc_id,"island_level":self.base.geometry.level,"width_m":self.base.geometry.half_width*2.,"height_m":self.base.geometry.half_height*2.,"placement":{"origin":origin,"width_m":self.base.geometry.half_width*1.5,"height_m":self.base.geometry.half_height*1.5},"source_kind":"original_fictional","garrison":self.base.anchors.iter().map(|a|json!({"ship":a.ship,"side":a.side,"phase":a.phase,"ready_tick":a.ready as f64/10.})).collect::<Vec<_>>(),"deployables":self.deployables.iter().map(|d|json!({"id":d.id,"kind":d.kind,"x":d.p.x,"y":d.p.y,"side":d.side,"hp":d.hp,"active":d.active})).collect::<Vec<_>>(),"warehouses":self.base.warehouses.iter().enumerate().map(|(i,w)|{let b=&self.base.core.ground.buildings[w.building];json!({"id":b.id,"x":b.p.x,"y":b.p.y,"progress":self.warehouse_capture[i]as f64/60.,"captured":self.captured_store.contains(&i),"holder":w.holder,"exposed":w.stock})}).collect::<Vec<_>>(),"hq_capture":self.captured as f64/100.,"exposed":self.base.stock,"plundered":self.plundered,"outcome":outcome,"landing_transports":transports.iter().filter(|t|t["side"]=="axis").collect::<Vec<_>>(),"replay":{"version":VERSION,"command_count":self.commands.len(),"frame":frame,"source":"seed_configuration_and_validated_commands"}});
        v
    }
}
fn combat_visual(u: &Unit) -> Option<String> {
    match u.class {
        "air" => Some(format!("{}-attack_helicopter", u.id)),
        "armor" => Some(format!(
            "{}-{}",
            u.id,
            if u.role == "artillery" {
                "howitzer"
            } else {
                "tank"
            }
        )),
        "amphibious" => Some(format!("{}-amphibious_vehicle", u.id)),
        _ => None,
    }
}
pub(crate) struct Replay {
    key: String,
    source: Saved,
    battle: Battle,
    cursor: usize,
}
impl Replay {
    pub(crate) fn open(saved: Saved, end: u32) -> E<Self> {
        Battle::validate_save(&saved)?;
        if end > saved.frame {
            return Err("不能重演未来时刻".into());
        }
        let key = serde_json::to_string(&saved).map_err(|_| "录像编码无效")?;
        let battle = Battle::new(saved.seed, saved.config.clone())?;
        let mut r = Self {
            key,
            source: saved,
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

