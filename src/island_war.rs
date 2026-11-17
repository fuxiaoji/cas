//! Original fictional island attack/defence, opt-in only. All historical and
//! published littoral versions retain their byte-level response contract.
use super::*;
use serde::{Deserialize, Serialize};
#[path = "island_war_v2.rs"]
pub(crate) mod v2;
#[path = "island_war_v4_base.rs"]
pub(crate) mod v4_base;

pub(crate) const VERSION: &str = "cas-island-war-v1";
const MAX_FRAME: u32 = 9000;
#[derive(Clone, Debug, Serialize, Deserialize, Default, PartialEq)]
#[serde(deny_unknown_fields)]
pub(crate) struct Stock {
    #[serde(default)]
    pub credits: u32,
    #[serde(default)]
    pub scrap: u32,
    #[serde(default)]
    pub alloy: u32,
    #[serde(default)]
    pub protocols: u32,
}
impl Stock {
    fn part(&self, part: u32, total: u32) -> Self {
        Self {
            credits: self.credits * part / total,
            scrap: self.scrap * part / total,
            alloy: self.alloy * part / total,
            protocols: self.protocols * part / total,
        }
    }
    fn add(&mut self, o: &Self) {
        self.credits += o.credits;
        self.scrap += o.scrap;
        self.alloy += o.alloy;
        self.protocols += o.protocols;
    }
    fn bounded(&self) -> bool {
        self.credits <= 10_000_000
            && self.scrap <= 10_000_000
            && self.alloy <= 10_000_000
            && self.protocols <= 100_000
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Growth {
    pub id: String,
    pub level: u32,
    #[serde(default)]
    pub ascension: u32,
    #[serde(default)]
    pub specialization: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Island {
    pub npc_id: String,
    pub island_level: u32,
    #[serde(default)]
    pub forts: Vec<Fort>,
    #[serde(default)]
    pub storage: Option<Stock>,
    #[serde(default)]
    pub unit_growth: Vec<Growth>,
}
#[derive(Clone, Debug, Serialize)]
pub(crate) struct Start {
    #[serde(flatten)]
    pub base: Config,
    pub island: Island,
}
impl<'de> Deserialize<'de> for Start {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let mut v = Value::deserialize(d)?;
        let island = v
            .as_object_mut()
            .and_then(|v| v.remove("island"))
            .ok_or_else(|| serde::de::Error::custom("缺少岛屿配置"))?;
        let island = Island::deserialize(island).map_err(serde::de::Error::custom)?;
        let base = decode_config(v, super::VERSION).map_err(serde::de::Error::custom)?;
        Ok(Self { base, island })
    }
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

#[derive(Clone)]
pub(crate) struct Geometry {
    pub level: u32,
    pub center: P,
    pub half_width: f64,
    pub half_height: f64,
}
impl Geometry {
    fn coast_landing(&self,id:u32)->E<(P,P)>{
        let (sea,land)=self.beach(id)?;let mut lo=sea;let mut hi=land;
        for _ in 0..40 {let p=(lo+hi)*0.5;if inside(&self.polygon(),p){hi=p}else{lo=p}}
        let dir=(land-sea).unit();Ok((lo-dir*8.,hi+dir*28.))
    }
    pub fn new(level: u32) -> Self {
        Self {
            level,
            center: P {
                x: 14600.,
                y: 13000.,
            },
            half_width: 1250. + level.saturating_sub(1) as f64 * 165.,
            half_height: 1650. + level.saturating_sub(1) as f64 * 175.,
        }
    }
    fn polygon(&self) -> Vec<P> {
        [
            (-1., 0.),
            (-0.96, -0.55),
            (-0.5, -0.95),
            (0.3, -1.),
            (0.9, -0.7),
            (1., 0.1),
            (0.7, 0.8),
            (0., 1.),
            (-0.8, 0.7),
        ]
        .into_iter()
        .map(|(x, y)| P {
            x: self.center.x + x * self.half_width,
            y: self.center.y + y * self.half_height,
        })
        .collect()
    }
    pub fn beach(&self, id: u32) -> E<(P, P)> {
        if !(1..=3).contains(&id) {
            return Err("滩头不存在".into());
        }
        let y = self.center.y + (id as f64 - 2.) * self.half_height * 0.35;
        Ok((
            P {
                x: self.center.x - self.half_width - 800.,
                y,
            },
            P {
                x: self.center.x - self.half_width * 0.78,
                y,
            },
        ))
    }
    pub fn exit(&self) -> P {
        P {
            x: self.center.x - self.half_width - 3000.,
            y: self.center.y,
        }
    }
    pub fn origin(&self) -> P {
        P {
            x: self.center.x - self.half_width - 200.,
            y: self.center.y - self.half_height - 200.,
        }
    }
    pub fn grid(&self) -> (usize, usize) {
        (
            ((self.half_width * 2. + 400.) / 40.).ceil() as usize,
            ((self.half_height * 2. + 400.) / 40.).ceil() as usize,
        )
    }
    fn point(&self, x: f64, y: f64) -> P {
        P {
            x: self.center.x + (x - 0.5) * self.half_width * 1.5,
            y: self.center.y + (y - 0.5) * self.half_height * 1.5,
        }
    }
    pub fn elevation(&self, p: P) -> f64 {
        let x = (p.x - self.center.x) / self.half_width;
        let y = (p.y - self.center.y) / self.half_height;
        let ramp = ((x - 0.05) / 0.25).clamp(0., 1.);
        let edge = ((0.78 - y.abs()) / 0.2).clamp(0., 1.);
        80. * ramp * edge
    }
    pub fn cover(&self, p: P) -> f64 {
        1. - self.elevation(p) * 0.0025
    }
    fn view(&self) -> Value {
        let ridge = vec![
            self.point(0.55, 0.15),
            self.point(0.95, 0.15),
            self.point(0.95, 0.85),
            self.point(0.55, 0.85),
        ];
        json!({"height_model":"island-ramp-v1","elevation_zones":[{"id":"plain","polygon":self.polygon(),"height_m":0,"level":0,"cover_multiplier":1},{"id":"ridge","polygon":ridge,"height_m":80,"level":2,"cover_multiplier":0.8,"blend_width_m":self.half_width*0.25}],"ramps":[{"points":[self.point(0.52,0.5),self.point(0.7,0.5)],"width":300,"from_level":0,"to_level":2}],"height_los":false,"effect":"连续高地减免至多20%地面直射伤害；舰炮与航空不减免"})
    }
}
#[derive(Clone, Copy)]
struct Spec {
    kind: &'static str,
    name: &'static str,
    hp: f64,
    damage: f64,
    range: f64,
    min: f64,
    reload: u32,
    ammo: u32,
    radius: f64,
    speed: f64,
    armor: &'static str,
    role: &'static str,
}
const SPECS: [Spec; 8] = [
    Spec {
        kind: "hq",
        name: "指挥核心",
        hp: 1800.,
        damage: 0.,
        range: 0.,
        min: 0.,
        reload: 0,
        ammo: 0,
        radius: 0.,
        speed: 0.,
        armor: "reinforced",
        role: "objective",
    },
    Spec {
        kind: "warehouse",
        name: "可夺取仓库",
        hp: 650.,
        damage: 0.,
        range: 0.,
        min: 0.,
        reload: 0,
        ammo: 0,
        radius: 0.,
        speed: 0.,
        armor: "light",
        role: "storage",
    },
    Spec {
        kind: "machine_gun",
        name: "双联机枪塔",
        hp: 440.,
        damage: 12.,
        range: 1000.,
        min: 0.,
        reload: 6,
        ammo: 240,
        radius: 32.,
        speed: 1200.,
        armor: "light",
        role: "anti_infantry",
    },
    Spec {
        kind: "cannon",
        name: "反装甲加农炮",
        hp: 720.,
        damage: 90.,
        range: 1900.,
        min: 0.,
        reload: 38,
        ammo: 45,
        radius: 65.,
        speed: 1000.,
        armor: "reinforced",
        role: "anti_armor",
    },
    Spec {
        kind: "mortar",
        name: "曲射迫击炮",
        hp: 400.,
        damage: 42.,
        range: 2450.,
        min: 350.,
        reload: 42,
        ammo: 40,
        radius: 135.,
        speed: 350.,
        armor: "light",
        role: "indirect",
    },
    Spec {
        kind: "air_defense",
        name: "近程防空塔",
        hp: 520.,
        damage: 40.,
        range: 2450.,
        min: 0.,
        reload: 14,
        ammo: 90,
        radius: 85.,
        speed: 1500.,
        armor: "medium",
        role: "anti_air",
    },
    Spec {
        kind: "anti_ship",
        name: "岸防反舰炮",
        hp: 850.,
        damage: 24.,
        range: 7000.,
        min: 500.,
        reload: 65,
        ammo: 32,
        radius: 80.,
        speed: 900.,
        armor: "reinforced",
        role: "anti_ship",
    },
    Spec {
        kind: "repair",
        name: "有限抢修节点",
        hp: 480.,
        damage: 22.,
        range: 950.,
        min: 0.,
        reload: 30,
        ammo: 35,
        radius: 0.,
        speed: 0.,
        armor: "light",
        role: "repair",
    },
];
fn kind(k: &str) -> &str {
    match k {
        "turret" => "machine_gun",
        "aa" => "air_defense",
        "depot" => "warehouse",
        _ => k,
    }
}
fn spec(k: &str) -> Option<Spec> {
    SPECS.iter().find(|s| s.kind == kind(k)).copied()
}
pub(crate) fn body_damage_factor(kind: &str, armor: f64) -> f64 {
    if matches!(kind, "cannon" | "anti_tank" | "naval") {
        armor.max(0.85)
    } else {
        armor
    }
}
pub(crate) fn structure_damage_factor(weapon: &str, target: &str) -> f64 {
    let armor = spec(target).map_or("light", |s| s.armor);
    match (weapon, armor) {
        ("marine" | "rifle" | "scout" | "engineer" | "sniper", "reinforced") => 0.32,
        ("marine" | "rifle" | "scout" | "engineer" | "sniper", "medium") => 0.65,
        ("anti_tank" | "tank" | "howitzer" | "cannon" | "naval" | "air_strike", _) => 1.15,
        _ => 1.,
    }
}
const NPCS: [(&str, &str, u32, &str, &str); 6] = [
    ("shoal_watch", "浅滩哨所", 1, "coral", "IBS-U-USN-FLETCHER"),
    ("rust_quay", "锈港回收站", 2, "ochre", "IBS-U-USN-FLETCHER"),
    ("cloudbreak", "断云航空站", 3, "mint", "IBS-U-USN-PENSACOLA"),
    (
        "iron_citadel",
        "铁潮要塞",
        5,
        "cobalt",
        "IBS-U-USN-PENSACOLA",
    ),
    (
        "storm_relay",
        "风暴中继岛",
        7,
        "coral",
        "IBS-U-USN-PENSACOLA",
    ),
    ("old_arsenal", "旧世军械岛", 10, "ochre", SHOKAKU),
];
fn npc(id: &str) -> E<usize> {
    NPCS.iter()
        .position(|n| n.0 == id)
        .ok_or("人机岛屿未登记".into())
}
fn default_forts(index: usize) -> Vec<Fort> {
    let mut rows = vec![
        ("hq", 0.78, 0.5),
        ("warehouse", 0.53, 0.28),
        ("warehouse", 0.56, 0.73),
        ("machine_gun", 0.37, 0.42),
        ("machine_gun", 0.37, 0.62),
    ];
    if index >= 1 {
        rows.push(("cannon", 0.61, 0.5));
        rows.push(("mortar", 0.78, 0.26));
    }
    if index >= 2 {
        rows.push(("air_defense", 0.67, 0.72));
    }
    if index >= 3 {
        rows.push(("anti_ship", 0.35, 0.20));
        rows.push(("repair", 0.81, 0.68));
    }
    if index >= 4 {
        rows.push(("cannon", 0.56, 0.86));
        rows.push(("air_defense", 0.71, 0.32));
    }
    if index >= 5 {
        rows.push(("mortar", 0.86, 0.78));
        rows.push(("anti_ship", 0.31, 0.82));
    }
    rows.into_iter()
        .enumerate()
        .map(|(i, (k, x, y))| Fort {
            id: format!("fort-{}", i + 1),
            kind: k.into(),
            x,
            y,
            level: (1 + index as u32 / 2),
            hp: 100.,
        })
        .collect()
}
pub(crate) fn catalogue() -> Value {
    let towers:Vec<_>=SPECS.iter().map(|s|json!({"kind":s.kind,"name":s.name,"hp":s.hp,"damage":s.damage,"range_m":s.range,"min_range_m":s.min,"reload_seconds":s.reload as f64/10.,"ammo":s.ammo,"radius_m":s.radius,"projectile_speed_mps":s.speed,"armor":s.armor,"role":s.role,"level_hp_damage_step":0.12,"width_m":if s.kind=="hq"{70}else if s.kind=="warehouse"{50}else{20}})).collect();
    let islands:Vec<_>=NPCS.iter().enumerate().map(|(i,n)|{let g=Geometry::new(n.2);json!({"id":n.0,"name":n.1,"level":n.2,"palette":n.3,"garrison":garrison(i),"forts":default_forts(i),"storage":npc_stock(i),"width_m":g.half_width*2.,"height_m":g.half_height*2.,"land_personnel":18+i*7,"recommended_points":1500+i*900,"local_simulation":true})}).collect();
    json!({"version":VERSION,"source_kind":"original_fictional","simulation_hz":10,"max_seconds":900,"max_island_level":10,"tower_types":towers,"islands":islands,"growth":{"max_level":30,"max_ascension":2,"max_hp_bonus":0.05,"max_damage_bonus":0.05,"max_utility_bonus":0.01,"specializations":["assault","vanguard","support","mobility","precision","logistics"]},"replay":{"version":VERSION,"source":"seed_configuration_and_validated_commands","seek_resolution_seconds":0.1,"read_only":true}})
}
fn npc_stock(i: usize) -> Stock {
    Stock {
        credits: 300 + i as u32 * 180,
        scrap: 120 + i as u32 * 70,
        alloy: 30 + i as u32 * 25,
        protocols: if i >= 3 { 1 } else { 0 },
    }
}
fn garrison(i: usize) -> Vec<&'static str> {
    let mut v = vec![NPCS[i].4];
    if i >= 2 {
        v.push("IBS-U-USN-FLETCHER")
    }
    if i >= 4 {
        v.push("IBS-U-USN-PENSACOLA")
    }
    v
}
#[derive(Clone)]
struct Ware {
    building: usize,
    stock: Stock,
    progress: u32,
    holder: Option<String>,
    captured: bool,
    destroyed_fraction: bool,
}
#[derive(Clone)]
struct FortShot {
    id: String,
    p: P,
    goal: P,
    ally: bool,
    kind: &'static str,
    damage: f64,
    radius: f64,
    speed: f64,
    source: String,
}
#[derive(Clone)]
struct Anchorage {
    ship: u32,
    side: usize,
    phase: &'static str,
    ready: u32,
}
#[derive(Clone)]
struct Landing {
    carrier: u32,
    body: Option<u32>,
    landed: bool,
    personnel: u32,
    start: u32,
    beach: u32,
}
pub(crate) struct Battle {
    core: super::Battle,
    start: Start,
    commands: Vec<Command>,
    geometry: Geometry,
    npc: usize,
    warehouses: Vec<Ware>,
    shots: Vec<FortShot>,
    anchors: Vec<Anchorage>,
    landings: Vec<Landing>,
    commander: Option<autonomy::Commander>,
    capture: u32,
    stock: Stock,
    plundered: Stock,
    growth_ids: BTreeSet<u32>,
    capture_holder: Option<String>,
    defender_paths: BTreeMap<u32, (P, Vec<P>)>,
}
impl Battle {
    pub(crate) fn decode(mut q: Value) -> E<(u32, Start)> {
        let seed = crate::world::u(&q, "seed")?;
        if q["version"] != VERSION {
            return Err("海岛攻防版本无效".into());
        }
        for k in ["op", "seed", "version"] {
            q.as_object_mut().ok_or("海岛配置无效")?.remove(k);
        }
        let island: Island = serde_json::from_value(
            q.as_object_mut()
                .unwrap()
                .remove("island")
                .ok_or("缺少岛屿配置")?,
        )
        .map_err(|e| format!("岛屿配置无效：{e}"))?;
        let base = decode_config(q, super::VERSION).map_err(|e| format!("海岛编队无效：{e}"))?;
        Ok((seed, Start { base, island }))
    }
    pub(crate) fn new(seed: u32, start: Start) -> E<Self> {
        Self::new_geometry(seed, start, None)
    }
    fn new_geometry(seed: u32, start: Start, geometry: Option<Geometry>) -> E<Self> {
        let coordinate_range=if geometry.is_some(){-1.0..=2.0}else{0.05..=0.95};
        if !["raid", "defense"].contains(&start.base.mode.as_str()) {
            return Err("海岛攻防仅允许raid或defense".into());
        }
        let index = npc(&start.island.npc_id)?;
        let level = start.island.island_level;
        if !(1..=10).contains(&level) {
            return Err("岛权等级须为1–10".into());
        }
        if start.base.company_layout.as_deref() != Some(MULTI) {
            return Err("新海岛攻防须使用multi-company-v1真实多连".into());
        }
        let mut seen = BTreeSet::new();
        for g in &start.island.unit_growth {
            if !start.base.roster.contains(&g.id)
                || !seen.insert(&g.id)
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
                return Err("战术成长身份、等级、突破或专精无效".into());
            }
        }
        let stock = start
            .island
            .storage
            .clone()
            .unwrap_or_else(|| npc_stock(index));
        if !stock.bounded() {
            return Err("可掠仓储超出单场安全预算".into());
        }
        let forts = if start.island.forts.is_empty() {
            default_forts(index)
        } else {
            start.island.forts.clone()
        };
        if forts.len() > 48
            || forts.iter().filter(|f| f.kind == "hq").count() != 1
            || !forts.iter().any(|f| kind(&f.kind) == "warehouse")
        {
            return Err("岛屿须有一个指挥部和至少一个仓库，至多48设施".into());
        }
        seen.clear();
        for f in &forts {
            if !seen.insert(&f.id)
                || f.id.is_empty()
                || spec(&f.kind).is_none()
                || !(1..=10).contains(&f.level)
                || !f.x.is_finite()
                || !f.y.is_finite()
                || !coordinate_range.contains(&f.x)
                || !coordinate_range.contains(&f.y)
                || !f.hp.is_finite()
                || !(0. ..=100.).contains(&f.hp)
            {
                return Err("岛屿设施类型、位置、等级或状态无效".into());
            }
        }
        let defense = start.base.mode == "defense";
        let mut base = start.base.clone();
        base.defense.clear();
        base.lesson = None;
        let mut core = super::Battle::new(seed, base)?;
        let geometry = geometry.unwrap_or_else(|| Geometry::new(level));
        let g = &mut core.ground;
        g.island_geometry = Some(geometry.clone());
        g.config.mode = "island_war".into();
        g.polygon = geometry.polygon();
        g.obstacles.clear();
        g.bodies.clear();
        g.buildings.clear();
        g.mines.clear();
        g.loot.clear();
        g.ruins = vec![Ruin {
            id: 1,
            p: geometry.point(0.78, 0.5),
            progress: 0,
            searched: false,
        }];
        g.events.clear();
        g.landed_companies.clear();
        g.v4_body_paths.clear();
        for f in forts {
            let s = spec(&f.kind).unwrap();
            let max = s.hp * (1. + (f.level - 1) as f64 * 0.12);
            let p = geometry.point(f.x, f.y);
            if !g.walkable(p, true) {
                return Err("设施必须位于真实陆地内".into());
            }
            if g.buildings.iter().any(|b| b.p.dist(p) < 65.) {
                return Err("设施占地重叠，请调整布局".into());
            }
            g.buildings.push(Building {
                id: f.id,
                kind: s.kind.into(),
                ally: defense,
                p,
                hp: max * f.hp / 100.,
                max,
                level: f.level,
                ammo: s.ammo,
                next: 20,
            });
        }
        let wh: Vec<_> = g
            .buildings
            .iter()
            .enumerate()
            .filter(|(_, b)| b.kind == "warehouse")
            .map(|(i, _)| i)
            .collect();
        let count = wh.len() as u32;
        let mut allocated = Stock::default();
        let mut warehouses = vec![];
        for (n, i) in wh.into_iter().enumerate() {
            let amount = if n + 1 == count as usize {
                Stock {
                    credits: stock.credits - allocated.credits,
                    scrap: stock.scrap - allocated.scrap,
                    alloy: stock.alloy - allocated.alloy,
                    protocols: stock.protocols - allocated.protocols,
                }
            } else {
                stock.part(1, count)
            };
            allocated.add(&amount);
            warehouses.push(Ware {
                building: i,
                stock: amount,
                progress: 0,
                holder: None,
                captured: false,
                destroyed_fraction: false,
            });
        }
        let own_ids: BTreeSet<_> = core
            .naval
            .ships
            .iter()
            .filter(|s| s.side == 0)
            .map(|s| s.id)
            .collect();
        core.naval.ships.retain(|s| s.side == 0);
        core.naval.fleets.retain(|f| f.side == 0);
        core.squadrons.retain(|s| own_ids.contains(&s.carrier));
        core.ground.ships.retain(|s| s.ally);
        core.naval.contacts = [vec![], vec![]];
        core.naval.next_contacts = [1, 1];
        let sea = geometry.beach(2)?.0;
        let mut anchors = vec![];
        for (i, s) in core.naval.ships.iter_mut().enumerate() {
            s.p = P {
                x: sea.x - 250. - (i % 2) as f64 * 230.,
                y: sea.y + (i as f64 - 1.) * 220.,
            };
            s.h = 270.;
            s.speed = 0.;
            if defense {
                anchors.push(Anchorage {
                    ship: s.id,
                    side: 0,
                    phase: "anchored",
                    ready: 0,
                });
            }
        }
        for f in &mut core.naval.fleets {
            f.points.clear();
            f.speed = 0.;
            f.actual = 0.;
            f.ai = crate::model::Ai::new("coord", "manual");
        }
        core.naval.islands = vec![core.ground.polygon.clone()];
        core.sync_from_naval();
        if defense {
            for i in 0..core.ground.groups.len() {
                let p = geometry.point(0.38 + (i % 4) as f64 * 0.08, 0.28 + (i / 4) as f64 * 0.12);
                core.ground.groups[i].p = p;
                core.ground.groups[i].stage = "ground";
                core.ground.groups[i].path.clear();
                core.ground.spawn_group(i);
            }
        } else {
            for group in &mut core.ground.groups {
                group.p = core
                    .ground
                    .ships
                    .iter()
                    .find(|s| s.id == group.carrier)
                    .unwrap()
                    .p;
            }
        }
        let mut landings = vec![];
        let cards = garrison(index);
        let enemy_count = cards.len();
        for (i, identity) in cards.into_iter().enumerate() {
            let def = core
                .naval
                .data
                .ships
                .iter()
                .position(|s| s.id == identity)
                .ok_or("人机守舰舰卡缺失")?;
            let fleet = 100 + i as u32;
            let p = P {
                x: sea.x - if defense { 2200. } else { 2400. },
                y: sea.y + (i as f64 - 0.5) * 700.,
            };
            let id = core.naval.spawn(
                def,
                1,
                fleet,
                format!("{}守舰{}", NPCS[index].1, i + 1),
                p,
                90.,
            )?;
            core.naval.fleets.push(crate::model::Fleet {
                id: fleet,
                side: 1,
                name: "人机独立守舰".into(),
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
            let d = core.naval.data.ships[def].clone();
            let hp = d.dp;
            core.ground.ships.push(SeaShip {
                id,
                def: d,
                ally: false,
                p,
                h: 90.,
                facing: None,
                pending_support: None,
                aim_target: None,
                deployment_route: false,
                hp,
                max: hp,
                initial: 100.,
                requested: 70,
                loaded: 70,
                ammo: 70,
                slots: 0,
                speed: 0.,
                path: vec![],
                next: 0,
                anchor: !defense,
                unmoor: 0,
                ai: false,
                last_plan: 0,
            });
            core.naval.v4_gun_supply.as_mut().unwrap().insert(id, 70);
            if identity == SHOKAKU || identity == ENTERPRISE {
                for (model, role) in if identity == SHOKAKU {
                    [
                        ("A6M2", "fighter"),
                        ("D3A2", "dive_bomber"),
                        ("B5N2", "torpedo_bomber"),
                    ]
                } else {
                    [
                        ("F4F", "fighter"),
                        ("SBD", "dive_bomber"),
                        ("TBD", "torpedo_bomber"),
                    ]
                } {
                    core.squadrons.push(Squadron {
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
                        health: vec![if role == "fighter" { 90. } else { 120. }; 3],
                    });
                }
            }
            if !defense {
                anchors.push(Anchorage {
                    ship: id,
                    side: 1,
                    phase: "anchored",
                    ready: 0,
                });
            } else {
                landings.push(Landing {
                    carrier: id,
                    body: None,
                    landed: false,
                    personnel: ((18 + index * 7 + enemy_count - 1) / enemy_count) as u32,
                    start: 0,
                    beach: 2,
                });
            }
        }
        if !defense {
            let defenders = 18 + index * 7;
            for i in 0..defenders {
                let fort = &core.ground.buildings[i % core.ground.buildings.len()];
                let p = fort.p
                    + P {
                        x: (i % 3) as f64 * 70. - 70.,
                        y: (i / 3 % 3) as f64 * 70. - 70.,
                    };
                if core.ground.walkable(p, true) {
                    core.ground.body(
                        format!("npc-defender-{i}"),
                        false,
                        if i % 9 == 0 {
                            "anti_tank"
                        } else if i % 13 == 0 {
                            "aa_team"
                        } else {
                            "rifle"
                        },
                        p,
                        100.,
                    );
                }
            }
        }
        core.naval.init_realtime(crate::realtime::VERSION)?;
        core.naval.refresh_open_intel();
        let mut w = Self {
            core,
            start,
            commands: vec![],
            geometry,
            npc: index,
            warehouses,
            shots: vec![],
            anchors,
            landings,
            commander: None,
            capture: 0,
            stock,
            plundered: Stock::default(),
            growth_ids: BTreeSet::new(),
            capture_holder: None,
            defender_paths: BTreeMap::new(),
        };
        w.grow_bodies();
        w.build_town();
        w.core.ground.event(
            "island_start",
            "原创人机海岛攻防；真实驻舰、有限守军与可夺取仓储",
            w.geometry.center,
        );
        Ok(w)
    }
    fn defense(&self) -> bool {
        self.start.base.mode == "defense"
    }
    fn grow_bodies(&mut self) {
        for b in &mut self.core.ground.bodies {
            if !b.ally || !self.growth_ids.insert(b.id) {
                continue;
            }
            if let Some(g) = self
                .start
                .island
                .unit_growth
                .iter()
                .find(|g| g.id == unit_id(&b.group))
            {
                let hp = 1. + 0.035 * (g.level - 1) as f64 / 29. + 0.015 * g.ascension as f64 / 2.;
                let fire = 1. + 0.03 * (g.level - 1) as f64 / 29. + 0.02 * g.ascension as f64 / 2.;
                b.max *= hp;
                b.hp *= hp;
                b.damage *= fire;
                if g.specialization == "precision" {
                    b.range *= 1.01;
                }
                if g.specialization == "logistics" {
                    b.ammo = (b.ammo as f64 * 1.01).floor() as u32;
                }
            }
        }
        for g in &mut self.core.ground.groups {
            if self
                .start
                .island
                .unit_growth
                .iter()
                .any(|x| x.id == unit_id(g.card.id) && x.specialization == "mobility")
                && g.card.speed == profile(g.card.id).unwrap().speed * 2.5
            {
                g.card.speed *= 1.01;
            }
        }
    }
    fn build_town(&mut self) {
        let mut rng = self.core.ground.seed as u64 ^ 0x919a_c712;
        let mut buildings = vec![];
        let mut roads = vec![];
        let g = &mut self.core.ground;
        for y in [0.25, 0.5, 0.75] {
            roads.push(json!({"points":[self.geometry.point(0.1,y),self.geometry.point(0.92,y)],"width":22}));
        }
        for x in [0.32, 0.55, 0.78] {
            roads.push(json!({"points":[self.geometry.point(x,0.1),self.geometry.point(x,0.9)],"width":20}));
        }
        for i in 0..25 + self.geometry.level as usize * 4 {
            let x = 0.15 + (crate::world::roll(&mut rng, 700) as f64 / 1000.);
            let y = 0.1 + crate::world::roll(&mut rng, 800) as f64 / 1000.;
            let p = self.geometry.point(x, y);
            if g.buildings.iter().any(|b| b.p.dist(p) < 170.)
                || g.groups
                    .iter()
                    .any(|c| c.stage == "ground" && c.p.dist(p) < 200.)
                || (1..=3).any(|b| self.geometry.beach(b).unwrap().1.dist(p) < 250.)
                || [0.25, 0.5, 0.75].iter().any(|r| (y - r).abs() < 0.04)
                || [0.32, 0.55, 0.78].iter().any(|r| (x - r).abs() < 0.04)
            {
                continue;
            }
            let w = 30. + crate::world::roll(&mut rng, 45) as f64;
            let h = 30. + crate::world::roll(&mut rng, 35) as f64;
            let poly = vec![
                p + P {
                    x: -w / 2.,
                    y: -h / 2.,
                },
                p + P {
                    x: w / 2.,
                    y: -h / 2.,
                },
                p + P {
                    x: w / 2.,
                    y: h / 2.,
                },
                p + P {
                    x: -w / 2.,
                    y: h / 2.,
                },
            ];
            if poly.iter().any(|p| !g.walkable(*p, true)) {
                continue;
            }
            g.obstacles.push(poly.clone());
            buildings.push(json!({"id":format!("island-town-{i}"),"footprint":poly,"width_m":w,"length_m":h,"height_m":9.6,"floors":3,"art_variant":crate::world::roll(&mut rng,12)-1,"roof_style":"gable","palette":NPCS[self.npc].3,"elevation_m":self.geometry.elevation(p)}));
        }
        self.core.town = json!({"version":"island-town-v1","units":"metres","roads":roads,"buildings":buildings});
    }
    fn complete(&self) -> bool {
        let hq = self
            .core
            .ground
            .buildings
            .iter()
            .find(|b| b.kind == "hq")
            .unwrap();
        if self.defense() {
            self.core.ground.frame >= 600
                && hq.hp > 0.
                && self
                    .core
                    .naval
                    .ships
                    .iter()
                    .filter(|s| s.side == 1)
                    .all(|s| !s.alive())
                && self
                    .core
                    .ground
                    .bodies
                    .iter()
                    .filter(|b| !b.ally && b.active)
                    .all(|b| b.hp <= 0.)
                && self
                    .landings
                    .iter()
                    .all(|l| l.landed || self.core.naval.ship(l.carrier).is_none_or(|s| !s.alive()))
        } else {
            self.capture >= 100
                && self.warehouses.iter().all(|w| w.captured)
                && self
                    .core
                    .naval
                    .ships
                    .iter()
                    .filter(|s| s.side == 1)
                    .all(|s| !s.alive())
        }
    }
    fn finish(&mut self, success: bool, abandoned: bool) {
        if self.core.ground.result.is_some() {
            return;
        }
        let mode = self.core.ground.config.mode.clone();
        self.core.ground.config.mode = self.start.base.mode.clone();
        self.core.ground.finish(success, abandoned);
        self.core.ground.config.mode = mode;
        let mut resources = Stock::default();
        if self.defense() {
            if success {
                resources = Stock {
                    credits: 80 + self.npc as u32 * 40,
                    scrap: 20 + self.npc as u32 * 10,
                    alloy: 0,
                    protocols: 0,
                };
            }
        } else {
            let units = &self.core.ground.result.as_ref().unwrap()["units"];
            for w in &self.warehouses {
                if w.captured
                    && w.holder.as_ref().is_some_and(|id| {
                        units.as_array().unwrap().iter().any(|u| {
                            u["id"] == *id
                                && u["recovered"] == true
                                && u["hp_percent"].as_f64().unwrap_or(0.) > 0.
                        })
                    })
                {
                    let stock = if w.destroyed_fraction {
                        w.stock.part(1, 4)
                    } else {
                        w.stock.clone()
                    };
                    resources.add(&stock);
                }
            }
            if !success || abandoned {
                resources = Stock::default();
            }
        }
        let objective = self.complete();
        let defense = self.defense();
        let result = self.core.ground.result.as_mut().unwrap();
        result["version"] = json!(VERSION);
        result["mode"] = json!(self.start.base.mode);
        result["objective_complete"] = json!(objective);
        result["resources"] = json!(resources);
        result["island_secured"] = json!(success && !defense);
        result["island_war"] = json!({"version":VERSION,"npc_id":self.start.island.npc_id,"island_level":self.geometry.level,"local_simulation":true,"plundered":self.plundered,"initial_exposed":self.stock,"hq_capture":self.capture as f64/100.,"warehouses_captured":self.warehouses.iter().filter(|w|w.captured).count(),"unit_xp":if success{40+self.npc as u32*15}else{10},"source_kind":"original_fictional"});
    }
    fn order(&mut self, q: &Value, record: bool) -> E<Value> {
        if self.core.ground.result.is_some() {
            return Err("海岛攻防已经结束".into());
        }
        if record && self.commands.len() >= 15000 {
            return Err("海岛指令记录达到上限".into());
        }
        let op = q["op"].as_str().ok_or("缺少操作")?;
        let requires_unmoored = op == "route"
            || op == "fire"
            || op == "littoral_support" && q["kind"] == "naval"
            || op == "littoral_ship_order" && q["action"] == "move"
            || op == "speed" && q["speed"].as_f64().unwrap_or(0.) > 0.;
        if requires_unmoored {
            let members = q["fleet"]
                .as_u64()
                .and_then(|id| self.core.naval.fleets.iter().find(|f| f.id as u64 == id))
                .map(|f| f.members.as_slice())
                .unwrap_or(&[]);
            if self.anchors.iter().any(|a| {
                a.side == 0
                    && a.phase != "active"
                    && a.phase != "sunk"
                    && (q["ship"].as_u64() == Some(a.ship as u64) || members.contains(&a.ship))
            }) {
                return Err(
                    "驻舰正在完成六秒起锚，完成后即可航行或开火；停止与取消指令仍可使用".into(),
                );
            }
        }
        match op {
            "littoral_autonomy" | "island_autonomy" => {
                if q["version"] != VERSION && q["version"] != autonomy::VERSION {
                    return Err("海岛托管版本无效".into());
                }
                let enabled = q["enabled"].as_bool().ok_or("托管开关须为真假值")?;
                let posture = q
                    .get("posture")
                    .and_then(Value::as_str)
                    .unwrap_or("mission");
                if !["mission", "withdraw"].contains(&posture) {
                    return Err("托管姿态无效".into());
                }
                self.commander
                    .get_or_insert_with(autonomy::Commander::default)
                    .configure(enabled, posture, self.core.ground.frame);
            }
            "littoral_extract" => {
                if self.defense() {
                    if !self.complete() {
                        return Err("仍有真实来袭舰队或登陆部队，不能提前宣布守岛成功".into());
                    }
                } else {
                    if self
                        .core
                        .ground
                        .groups
                        .iter()
                        .any(|g| !["embarked", "recovered", "lost"].contains(&g.stage))
                    {
                        return Err("尚有部队没有实际撤回舰上".into());
                    }
                    if self.core.aircraft.iter().any(|a| {
                        a.hp > 0. && self.core.naval.ship(a.carrier).is_some_and(|s| s.side == 0)
                    }) {
                        return Err("仍有航空中队在空，须真实返舰".into());
                    }
                    if self
                        .core
                        .naval
                        .ships
                        .iter()
                        .filter(|s| s.side == 0 && s.alive())
                        .any(|s| s.p.dist(self.geometry.exit()) > 1600.)
                    {
                        return Err("舰队尚未实际到达撤离海域".into());
                    }
                    if !self.complete() {
                        return Err("指挥部、仓库与制海权目标尚未全部完成；可撤退放弃".into());
                    }
                }
                self.finish(true, false);
            }
            "littoral_abandon" => self.finish(false, true),
            _ => {
                self.core.command(q, false)?;
                if record {
                    if let Some(ai) = &mut self.commander {
                        ai.manual_takeover(self.core.ground.frame);
                    }
                }
            }
        }
        if record {
            self.commands.push(Command {
                frame: self.core.ground.frame,
                request: q.clone(),
            });
        }
        Ok(self.view())
    }
    pub(crate) fn execute(&mut self, q: &Value) -> E<Value> {
        match q["op"].as_str().ok_or("缺少操作")? {
            "observe" => Ok(self.view()),
            "save" => Ok(json!(self.save())),
            "report" => {
                Ok(json!({"result":self.view()["result"],"island_war":self.view()["island_war"]}))
            }
            "step" => {
                let n = frames(&q["seconds"])?;
                for _ in 0..n {
                    if self.core.ground.result.is_some() {
                        break;
                    }
                    self.advance();
                }
                Ok(self.view())
            }
            "presentation" => Ok(self.core.naval.projectile_presentation(0)),
            "littoral_preview" => self.core.preview(q),
            "preview_route" => self.core.naval.preview(0, q),
            "preview_reform" => self.core.naval.preview_reform(0, q),
            "aim" => self.core.naval.preview_aim(0, q),
            "illumination_preview" => self.core.naval.preview_illumination(0, q),
            _ => self.order(q, true),
        }
    }
    pub(crate) fn save(&self) -> Saved {
        Saved {
            version: VERSION.into(),
            seed: self.core.ground.seed,
            config: self.start.clone(),
            frame: self.core.ground.frame,
            tick: self.core.ground.tick(),
            commands: self.commands.clone(),
        }
    }
    fn advance(&mut self) {
        if self.core.ground.result.is_some() {
            return;
        }
        self.anchorage();
        self.enemy_landings();
        self.enemy_land_ai();
        self.core.advance();
        self.grow_bodies();
        self.towers();
        self.projectiles();
        self.capture_stores();
        self.core.sync_to_naval();
        self.core.record_corpses();
        let hq_alive = self
            .core
            .ground
            .buildings
            .iter()
            .any(|b| b.kind == "hq" && b.hp > 0.);
        if self.defense() {
            if !hq_alive {
                self.finish(false, false);
            } else if self.complete() {
                self.finish(true, false);
            } else if self.core.ground.frame >= MAX_FRAME {
                self.finish(false, false);
            }
        } else if self
            .core
            .naval
            .ships
            .iter()
            .filter(|s| s.side == 0)
            .all(|s| !s.alive())
            || self.core.ground.frame >= MAX_FRAME
        {
            self.finish(false, false);
        }
        self.autonomy();
    }
    fn anchorage(&mut self) {
        let frame = self.core.ground.frame;
        let mut notices = vec![];
        for anchor in &mut self.anchors {
            let Some(ship) = self.core.naval.ship(anchor.ship) else {
                continue;
            };
            if !ship.alive() {
                anchor.phase = "sunk";
                continue;
            }
            if anchor.phase == "anchored" {
                let seen = if frame % 20 == 0 {
                    self.core.naval.observation(anchor.side)
                } else {
                    Value::Null
                };
                if seen["contacts"].as_array().is_some_and(|rows| {
                    rows.iter().any(|c| {
                        ship.p.dist(P {
                            x: c["x"].as_f64().unwrap_or(0.),
                            y: c["y"].as_f64().unwrap_or(0.),
                        }) < 8500.
                    })
                }) {
                    anchor.phase = "unmooring";
                    anchor.ready = frame + 60;
                    notices.push((ship.p, "锚泊舰队发现公开接触，开始六秒起锚"));
                }
            }
            let activated = anchor.phase == "unmooring" && frame >= anchor.ready;
            if activated {
                anchor.phase = "active";
                notices.push((ship.p, "锚泊舰队已真实完成起锚，出港迎击"));
            }
            if let Some(fleet) = self
                .core
                .naval
                .fleets
                .iter_mut()
                .find(|f| f.leader == anchor.ship)
            {
                if anchor.phase != "active" {
                    fleet.speed = 0.;
                    fleet.actual = 0.;
                    fleet.points.clear();
                    fleet.ai = crate::model::Ai::new("coord", "manual");
                } else if anchor.side == 1 || activated {
                    fleet.ai = crate::model::Ai::new("coord", "auto");
                    fleet.ai.torpedo = false;
                }
            }
        }
        for (p, t) in notices {
            self.core.ground.event("unmooring", t, p)
        }
        if self.defense() && frame % 40 == 0 {
            let view = self.core.naval.observation(1);
            let rows = view["ships"].as_array().cloned().unwrap_or_default();
            let sea = self.geometry.beach(2).unwrap().0;
            for s in rows {
                let id = s["id"].as_u64().unwrap() as u32;
                let needs_landing = self
                    .landings
                    .iter()
                    .any(|l| l.carrier == id && !l.landed && l.body.is_none());
                if !needs_landing {
                    continue;
                }
                let fleet = s["fleet"].clone();
                let max = s["systems"]["maxSpeed"].as_f64().unwrap_or(25.);
                if max < 4. {
                    continue;
                }
                let q = json!({"op":"route","fleet":fleet,"mode":"follow","points":[sea],"speed":max.min(25.)});
                let _ = self.core.naval.route(1, &q, false);
                if let Some(f) = self
                    .core
                    .naval
                    .fleets
                    .iter_mut()
                    .find(|f| Some(f.id as u64) == fleet.as_u64())
                {
                    f.ai = crate::model::Ai::new("coord", "auto");
                    f.ai.r#move = false;
                    f.ai.torpedo = false;
                }
            }
        }
    }
    fn enemy_landings(&mut self) {
        if !self.defense() {
            return;
        }
        let frame = self.core.ground.frame;
        for i in 0..self.landings.len() {
            let l = self.landings[i].clone();
            if l.landed {
                continue;
            }
            let (sea, land) = self.geometry.beach(l.beach).unwrap();
            if let Some(body) = l.body {
                let Some(index) = self.core.ground.bodies.iter().position(|b| b.id == body) else {
                    continue;
                };
                if self.core.ground.bodies[index].hp <= 0. {
                    self.landings[i].landed = true;
                    continue;
                }
                let p = self.core.ground.bodies[index].p;
                let d = p.dist(land);
                if d < 15. {
                    let condition = (self.core.ground.bodies[index].hp
                        / self.core.ground.bodies[index].max
                        * 100.)
                        .clamp(0., 100.);
                    self.core.ground.bodies[index].active = false;
                    self.landings[i].landed = true;
                    for n in 0..l.personnel {
                        let p = land
                            + P {
                                x: (n % 5) as f64 * 55.,
                                y: (n / 5) as f64 * 55. - 100.,
                            };
                        if self.core.ground.walkable(p, true) {
                            self.core.ground.body(
                                format!("npc-invader-{i}-{n}"),
                                false,
                                if n % 8 == 0 {
                                    "anti_tank"
                                } else if n % 11 == 0
                                    && self.core.naval.ship(l.carrier).is_some_and(|s| {
                                        matches!(
                                            carrier_category(&self.core.naval.data.ships[s.def].id),
                                            "CV" | "LHA" | "APV"
                                        )
                                    })
                                {
                                    "ifv"
                                } else {
                                    "rifle"
                                },
                                p,
                                condition,
                            );
                        }
                    }
                    self.core.ground.event(
                        "enemy_landed",
                        "实际存活的敌登陆艇抵岸，有限登陆人员展开",
                        land,
                    );
                } else {
                    self.core.ground.bodies[index].p = p + (land - p) * (75. * DT / d).min(1.);
                }
            } else if let Some(ship) = self.core.naval.ship(l.carrier).filter(|s| s.alive()) {
                if ship.p.dist(sea) <= 900. && frame >= l.start {
                    let p = ship.p;
                    self.core.ground.body(
                        format!("npc-landing-{i}"),
                        false,
                        "landing_craft",
                        p,
                        100.,
                    );
                    let body = self.core.ground.bodies.last_mut().unwrap();
                    body.hp = 360.;
                    body.max = 360.;
                    body.damage = 0.;
                    body.ammo = 0;
                    body.armor = 0.75;
                    let id = body.id;
                    self.landings[i].body = Some(id);
                    self.core.ground.event(
                        "enemy_launch",
                        "来袭运输舰进入近岸范围，真实发出登陆艇",
                        p,
                    );
                }
            }
        }
    }
    fn enemy_land_ai(&mut self) {
        let frame = self.core.ground.frame;
        if frame % 20 != 0 {
            let goals: Vec<_> = self
                .defender_paths
                .iter()
                .map(|(id, (p, _))| (*id, *p))
                .collect();
            for (id, goal) in goals {
                if let Some(i) = self
                    .core
                    .ground
                    .bodies
                    .iter()
                    .position(|b| b.id == id && b.hp > 0. && b.active)
                {
                    let speed = if self.core.ground.bodies[i].kind == "ifv" {
                        100.
                    } else {
                        72.
                    };
                    self.core.ground.v4_step_body(i, goal, speed);
                }
            }
            return;
        }
        let view = self.view();
        let bodies = view["littoral"]["land"]["entities"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        let buildings = view["littoral"]["land"]["buildings"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        let defense = self.defense();
        let mut plans = vec![];
        for b in bodies
            .iter()
            .filter(|b| b["side"] == "axis" && b["kind"] != "landing_craft")
        {
            let id = b["id"].as_u64().unwrap() as u32;
            let p = point(b);
            let range = b["range"].as_f64().unwrap_or(700.);
            let closest = bodies
                .iter()
                .filter(|t| t["side"] == "allies")
                .min_by(|a, b| p.dist(point(a)).total_cmp(&p.dist(point(b))));
            let friendly_fort = buildings
                .iter()
                .filter(|f| f["side"] == "axis" && f["hp"].as_f64().unwrap_or(0.) > 0.)
                .min_by(|a, b| p.dist(point(a)).total_cmp(&p.dist(point(b))));
            let goal = if b["hp"].as_f64().unwrap() / b["max_hp"].as_f64().unwrap() < 0.3 {
                friendly_fort.map(point)
            } else if let Some(t) =
                closest.filter(|t| p.dist(point(t)) < if defense { 2200. } else { 1300. })
            {
                let t = point(t);
                if p.dist(t) > range * 0.72 {
                    Some(t)
                } else {
                    None
                }
            } else if defense {
                let stores = buildings.iter().filter(|f| {
                    f["side"] == "allies"
                        && f["kind"] == "warehouse"
                        && self.warehouses.iter().any(|w| {
                            self.core.ground.buildings[w.building].id == f["id"].as_str().unwrap()
                                && !w.captured
                        })
                });
                stores
                    .min_by(|a, b| p.dist(point(a)).total_cmp(&p.dist(point(b))))
                    .or_else(|| buildings.iter().find(|f| f["kind"] == "hq"))
                    .map(point)
            } else {
                friendly_fort.map(point)
            };
            if let Some(goal) = goal {
                if p.dist(goal) > 60. {
                    plans.push((id, goal));
                }
            }
        }
        self.defender_paths.clear();
        for (id, goal) in plans {
            self.defender_paths.insert(id, (goal, vec![]));
            if let Some(i) = self.core.ground.bodies.iter().position(|b| b.id == id) {
                let speed = if self.core.ground.bodies[i].kind == "ifv" {
                    100.
                } else {
                    72.
                };
                self.core.ground.v4_step_body(i, goal, speed);
            }
        }
    }
    fn towers(&mut self) {
        let frame = self.core.ground.frame;
        let mut fire = vec![];
        let mut repairs = vec![];
        for (i, b) in self.core.ground.buildings.iter().enumerate() {
            let Some(s) = spec(&b.kind) else { continue };
            if b.hp <= 0. || b.ammo == 0 || frame < b.next || s.damage == 0. {
                continue;
            }
            if s.kind == "repair" {
                if let Some(target) = self
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
                    .min_by(|(_, a), (_, c)| (a.hp / a.max).total_cmp(&(c.hp / c.max)))
                {
                    repairs.push((i, target.0, s.damage * (1. + (b.level - 1) as f64 * 0.12)));
                }
                continue;
            }
            let target = if s.kind == "anti_ship" {
                self.core
                    .naval
                    .ships
                    .iter()
                    .filter(|t| {
                        (t.side == 0) != b.ally
                            && t.alive()
                            && t.p.dist(b.p) <= s.range
                            && t.p.dist(b.p) >= s.min
                    })
                    .min_by(|a, c| a.p.dist(b.p).total_cmp(&c.p.dist(b.p)))
                    .map(|t| t.p)
            } else {
                let air = s.kind == "air_defense";
                self.core
                    .ground
                    .bodies
                    .iter()
                    .filter(|t| {
                        t.ally != b.ally
                            && t.active
                            && t.hp > 0.
                            && (!air || t.air)
                            && t.p.dist(b.p) <= s.range
                            && t.p.dist(b.p) >= s.min
                            && (air
                                || s.kind == "mortar"
                                || t.kind == "landing_craft"
                                || self.core.ground.clear(b.p, t.p, true))
                    })
                    .min_by(|a, c| a.p.dist(b.p).total_cmp(&c.p.dist(b.p)))
                    .map(|t| t.p)
                    .or_else(|| {
                        if air {
                            self.core
                                .aircraft
                                .iter()
                                .filter(|a| {
                                    a.hp > 0.
                                        && self
                                            .core
                                            .naval
                                            .ship(a.carrier)
                                            .is_some_and(|c| (c.side == 0) != b.ally)
                                        && a.p.dist(b.p) <= s.range
                                })
                                .min_by(|a, c| a.p.dist(b.p).total_cmp(&c.p.dist(b.p)))
                                .map(|a| a.p)
                        } else {
                            None
                        }
                    })
                    .or_else(|| {
                        if air && !b.ally {
                            self.core
                                .ground
                                .transports
                                .iter()
                                .filter(|t| t.hp > 0. && t.air && t.p.dist(b.p) <= s.range)
                                .min_by(|a, c| a.p.dist(b.p).total_cmp(&c.p.dist(b.p)))
                                .map(|t| t.p)
                        } else {
                            None
                        }
                    })
            };
            if let Some(p) = target {
                fire.push((i, p, s));
            }
        }
        for (i, j, hp) in repairs {
            if self.core.ground.buildings[i].hp <= 0. || self.core.ground.buildings[i].ammo == 0 {
                continue;
            }
            let b = &mut self.core.ground.buildings[j];
            b.hp = (b.hp + hp).min(b.max);
            let p = b.p;
            let source = &mut self.core.ground.buildings[i];
            source.ammo -= 1;
            source.next = frame + 30;
            self.core.ground.event(
                "fort_repair",
                "抢修节点消耗一份有限备件，修复实际受损设施",
                p,
            );
        }
        for (i, p, s) in fire {
            if self.shots.len() + self.core.ground.projectiles.len() >= 512 {
                break;
            }
            let b = &mut self.core.ground.buildings[i];
            b.ammo -= 1;
            b.next = frame + s.reload;
            let shot = FortShot {
                id: format!("fort-{}-{frame}", b.id),
                p: b.p,
                goal: p,
                ally: b.ally,
                kind: s.kind,
                damage: s.damage * (1. + (b.level - 1) as f64 * 0.12),
                radius: s.radius,
                speed: s.speed,
                source: b.id.clone(),
            };
            bounded(
                &mut self.core.ground.shots,
                json!({"id":format!("fort-{}-{frame}",shot.source),"frame":frame,"tick":frame as f64/10.,"kind":shot.kind,"source":shot.source,"side":if shot.ally{"allies"}else{"axis"},"x":shot.p.x,"y":shot.p.y,"target_x":p.x,"target_y":p.y,"damage":shot.damage,"radius":shot.radius,"speed":shot.speed}),
            );
            self.shots.push(shot);
        }
    }
    fn projectiles(&mut self) {
        let mut impacts = vec![];
        for s in &mut self.shots {
            let d = s.p.dist(s.goal);
            if d <= s.speed * DT {
                s.p = s.goal;
                impacts.push(s.clone());
            } else {
                s.p = s.p + (s.goal - s.p) * (s.speed * DT / d);
            }
        }
        self.shots.retain(|s| s.p.dist(s.goal) > 0.01);
        for shot in impacts {
            if shot.kind == "anti_ship" {
                let mut hits = 0;
                for ship in &mut self.core.naval.ships {
                    if (ship.side == 0) == shot.ally
                        || !ship.alive()
                        || ship.p.dist(shot.goal)
                            > shot.radius + self.core.naval.data.ships[ship.def].length_m / 2.
                    {
                        continue;
                    }
                    let armor = self.core.naval.data.ships[ship.def].armor_belt;
                    let damage = shot.damage * (1. / (1. + armor * 0.10)).max(0.22);
                    ship.hp = (ship.hp - damage).max(0.);
                    hits += 1;
                }
                if hits > 0 {
                    bounded(
                        &mut self.core.ground.impacts,
                        json!({"id":format!("fort-hit-{}-{}",shot.source,self.core.ground.frame),"frame":self.core.ground.frame,"kind":"anti_ship","x":shot.goal.x,"y":shot.goal.y,"radius":shot.radius,"hits":hits,"source":shot.source}),
                    );
                }
                self.core.sync_from_naval();
            } else {
                self.core.ground.blast(
                    shot.goal,
                    shot.damage,
                    shot.radius,
                    shot.ally,
                    shot.kind == "air_defense",
                    shot.kind,
                    &shot.source,
                );
                if shot.kind == "air_defense" {
                    for a in &mut self.core.aircraft {
                        if self
                            .core
                            .naval
                            .ship(a.carrier)
                            .is_some_and(|c| (c.side == 0) != shot.ally)
                            && a.hp > 0.
                            && a.p.dist(shot.goal) <= shot.radius + 60.
                        {
                            a.hp = (a.hp - shot.damage).max(0.);
                        }
                    }
                }
            }
        }
    }
    fn capture_stores(&mut self) {
        let defense = self.defense();
        let attacking_ally = !defense;
        let frame = self.core.ground.frame;
        let mut events = vec![];
        for w in &mut self.warehouses {
            if w.captured {
                continue;
            }
            let p = self.core.ground.buildings[w.building].p;
            let attackers: Vec<_> = self
                .core
                .ground
                .bodies
                .iter()
                .filter(|b| {
                    b.ally == attacking_ally
                        && b.hp > 0.
                        && b.active
                        && !b.air
                        && b.kind != "landing_craft"
                        && b.p.dist(p) <= 300.
                })
                .collect();
            let contested = self.core.ground.bodies.iter().any(|b| {
                b.ally != attacking_ally && b.hp > 0. && b.active && !b.air && b.p.dist(p) <= 500.
            });
            if attackers.is_empty() || contested {
                continue;
            }
            w.progress = (w.progress + 1).min(60);
            w.holder = Some(attackers[0].group.clone());
            if w.progress >= 60 {
                w.captured = true;
                w.destroyed_fraction = self.core.ground.buildings[w.building].hp <= 0.;
                let stock = if w.destroyed_fraction {
                    w.stock.part(1, 4)
                } else {
                    w.stock.clone()
                };
                self.plundered.add(&stock);
                events.push((
                    p,
                    if w.destroyed_fraction {
                        "仓库废墟已实际控制，只能回收四分之一残存物资"
                    } else {
                        "仓库已由实际登陆人员控制，完整暴露物资被夺取"
                    },
                ));
            }
        }
        let hq = self
            .core
            .ground
            .buildings
            .iter()
            .find(|b| b.kind == "hq")
            .unwrap();
        let hqpos = hq.p;
        let near = self.core.ground.bodies.iter().find(|b| {
            b.ally == attacking_ally
                && b.active
                && b.hp > 0.
                && !b.air
                && b.kind != "landing_craft"
                && b.p.dist(hqpos) < 420.
        });
        let contested = self.core.ground.bodies.iter().any(|b| {
            b.ally != attacking_ally && b.active && b.hp > 0. && !b.air && b.p.dist(hqpos) < 500.
        });
        if !contested {
            if let Some(b) = near {
                self.capture = (self.capture + 1).min(100);
                self.capture_holder = Some(b.group.clone());
            }
        }
        if defense && self.capture >= 100 {
            self.finish(false, false);
        }
        for (p, t) in events {
            self.core.ground.event("warehouse_captured", t, p)
        }
        if frame % 10 == 0 {
            self.core.ground.capture = self.capture.min(80);
        }
    }
    fn autonomy(&mut self) {
        if self.core.ground.result.is_some()
            || self.core.ground.frame % 20 != 0
            || !self.commander.as_ref().is_some_and(|ai| ai.enabled)
        {
            return;
        }
        let mut v = self.view();
        v["littoral"]["land"]["buildings"]
            .as_array_mut()
            .unwrap()
            .retain(|b| b["kind"] != "warehouse");
        let frame = self.core.ground.frame;
        if self.defense() {
            let target = v["littoral"]["objectives"][0].clone();
            let groups = v["littoral"]["groups"].as_array().unwrap().clone();
            for g in groups {
                if g["stage"] == "ground" && g["hp_percent"].as_f64().unwrap_or(0.) > 0. {
                    let p = point(&g);
                    let threat = v["littoral"]["land"]["entities"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .filter(|b| b["side"] == "axis" && b["kind"] != "landing_craft")
                        .min_by(|a, b| p.dist(point(a)).total_cmp(&p.dist(point(b))))
                        .filter(|b| p.dist(point(b)) < 1800.);
                    let goal = threat.map(point).unwrap_or_else(|| point(&target));
                    let _=self.order(&json!({"op":"littoral_order","company_id":g["company_id"],"action":"defend","x":goal.x,"y":goal.y}),false);
                    if g["ability"]["available"] == true
                        && ["resupply", "triage", "field_repair"]
                            .contains(&g["ability"]["id"].as_str().unwrap_or(""))
                    {
                        let _ = self.order(
                            &json!({"op":"littoral_ability","company_id":g["company_id"]}),
                            false,
                        );
                    }
                }
            }
        }
        let mut ai = self.commander.take().unwrap();
        for mut proposal in ai.plan(&v) {
            if self.defense()
                && [
                    "littoral_order",
                    "littoral_recover",
                    "littoral_extract",
                    "littoral_abandon",
                ]
                .contains(&proposal.order["op"].as_str().unwrap_or(""))
            {
                continue;
            }
            if proposal.order["op"] == "ai" {
                proposal.order["torpedo"] = json!(false);
                if self.defense() {
                    proposal.order["move"] = json!(true);
                }
            }
            if self.core.ground.result.is_some() {
                break;
            }
            if proposal.order["op"] == "littoral_ship_order" && proposal.order["action"] == "move" {
                if let Some(ship) = v["ships"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .find(|s| s["id"] == proposal.order["ship"])
                {
                    let max = ship["systems"]["maxSpeed"].as_f64().unwrap_or(25.);
                    proposal.order["speed"] = json!(max.min(25.).max(4.));
                }
            }
            let result = self.order(&proposal.order, false).map(|_| ());
            ai.feedback(frame, proposal, result);
        }
        self.commander = Some(ai);
    }
    pub(crate) fn view(&self) -> Value {
        let mut v = self.core.view();
        self.motion_view(&mut v);
        v["scenario"] = json!(format!(
            "{} · {}",
            NPCS[self.npc].1,
            if self.defense() {
                "岛屿防卫"
            } else {
                "联合突袭"
            }
        ));
        v["version"] = json!(VERSION);
        v["limit"] = json!(MAX_FRAME / 10);
        v["naval_world"] = json!(true);
        v["littoral"]["mode"] = json!(self.start.base.mode);
        v["littoral"]["land"]["bounds"] = json!({"x":self.geometry.origin().x,"y":self.geometry.origin().y,"width":self.geometry.half_width*2.+400.,"height":self.geometry.half_height*2.+400.});
        v["littoral"]["land"]["terrain"] = self.geometry.view();
        let complete = self.complete();
        let hq = self
            .core
            .ground
            .buildings
            .iter()
            .find(|b| b.kind == "hq")
            .unwrap();
        let target = if !self.defense() && self.capture >= 100 {
            self.warehouses
                .iter()
                .find(|w| !w.captured)
                .map_or(hq.p, |w| self.core.ground.buildings[w.building].p)
        } else {
            hq.p
        };
        v["littoral"]["objectives"] = json!([{"id":"island_primary","kind":if self.defense(){"repel_actual_invasion"}else{"secure_hq_and_warehouses"},"x":target.x,"y":target.y,"progress":self.capture as f64/100.,"complete":complete}]);
        v["littoral"]["training"]["complete"] = json!(complete);
        v["littoral"]["budget"]["enemy_bodies"] = json!(64);
        if let Some(ai) = &self.commander {
            v["littoral"]["autonomy"] = ai.view();
            v["littoral"]["autonomy"]["version"] = json!(VERSION);
            if self.defense() && ai.enabled {
                v["littoral"]["autonomy"]["status"] =
                    json!("守备部队拦截可见来袭实体，舰队与航空兵协同防卫");
            }
        }
        for b in v["littoral"]["land"]["buildings"].as_array_mut().unwrap() {
            let s = spec(b["kind"].as_str().unwrap()).unwrap();
            b["name"] = json!(s.name);
            b["armor_type"] = json!(s.armor);
            b["range"] = json!(s.range);
            b["min_range"] = json!(s.min);
            b["damage"] = json!(s.damage * (1. + (b["level"].as_u64().unwrap() - 1) as f64 * 0.12));
            b["reload_seconds"] = json!(s.reload as f64 / 10.);
            b["width_m"] = json!(if s.kind == "hq" {
                70.
            } else if s.kind == "warehouse" {
                50.
            } else {
                20.
            });
            b["length_m"] = json!(if s.kind == "hq" {
                50.
            } else if s.kind == "warehouse" {
                35.
            } else {
                20.
            });
            b["elevation_m"] = json!(self.geometry.elevation(point(b)));
        }
        for b in v["littoral"]["land"]["entities"].as_array_mut().unwrap() {
            let p = point(b);
            if let Some(body) = self
                .core
                .ground
                .bodies
                .iter()
                .find(|x| b["id"].as_u64() == Some(x.id as u64))
            {
                b["armor_multiplier"] = json!(body.armor);
                b["ready_in"] =
                    json!(body.next.saturating_sub(self.core.ground.frame) as f64 / 10.);
            }
            b["elevation_m"] = json!(self.geometry.elevation(p));
            b["cover_multiplier"] = json!(self.geometry.cover(p));
        }
        for a in &self.anchors {
            if a.side == 0 {
                if let Some(s) = v["ships"]
                    .as_array_mut()
                    .unwrap()
                    .iter_mut()
                    .find(|s| s["id"].as_u64() == Some(a.ship as u64))
                {
                    s["anchored"] = json!(a.phase != "active" && a.phase != "sunk");
                    s["unmooring"] = json!(a.phase == "unmooring");
                    s["unmoor_seconds"] =
                        json!(a.ready.saturating_sub(self.core.ground.frame) as f64 / 10.);
                }
            } else {
                if let Some(c) = v["contacts"]
                    .as_array_mut()
                    .unwrap()
                    .iter_mut()
                    .find(|c| c["ship_id"].as_u64() == Some(a.ship as u64))
                {
                    c["anchored"] = json!(a.phase != "active" && a.phase != "sunk");
                    c["unmooring"] = json!(a.phase == "unmooring");
                }
            }
        }
        let warehouses:Vec<_>=self.warehouses.iter().map(|w|{let b=&self.core.ground.buildings[w.building];json!({"id":b.id,"x":b.p.x,"y":b.p.y,"progress":w.progress as f64/60.,"captured":w.captured,"holder":w.holder,"exposed":w.stock,"recovery_fraction":if b.hp<=0.{0.25}else{1.}})}).collect();
        let garrison:Vec<_>=self.anchors.iter().map(|a|json!({"ship":a.ship,"side":a.side,"phase":a.phase,"ready_tick":a.ready as f64/10.})).collect();
        let outcome = v["result"]
            .get("island_war")
            .cloned()
            .unwrap_or(Value::Null);
        let landing_transports: Vec<_> = self.landings.iter().filter_map(|l| {
            let b = self.core.ground.bodies.iter().find(|b| Some(b.id) == l.body)?;
            let (_, goal) = self.geometry.beach(l.beach).ok()?;
            let velocity = if b.active && b.hp > 0. { (goal-b.p).unit()*75. } else { P::default() };
            Some(json!({"id":b.id,"carrier":l.carrier,"kind":"landing_craft","side":"axis",
                "x":b.p.x,"y":b.p.y,"goal":goal,"heading":(goal-b.p).heading(),"velocity":velocity,
                "hp":b.hp,"max":b.max,"personnel":l.personnel,"status":if b.hp<=0.{"destroyed"}else if l.landed{"landed"}else{"sailing"}}))
        }).collect();
        v["island_war"] = json!({"version":VERSION,"local_simulation":true,"npc_id":self.start.island.npc_id,"island_level":self.geometry.level,"width_m":self.geometry.half_width*2.,"height_m":self.geometry.half_height*2.,"source_kind":"original_fictional","garrison":garrison,"warehouses":warehouses,"exposed":self.stock,"plundered":self.plundered,"hq_capture":self.capture as f64/100.,"unit_growth":self.start.island.unit_growth,"outcome":outcome,"remaining_invasion_landings":self.landings.iter().filter(|l|!l.landed&&self.core.naval.ship(l.carrier).is_some_and(|s|s.alive())).count(),"replay":{"version":VERSION,"command_count":self.commands.len(),"frame":self.core.ground.frame,"source":"seed_configuration_and_validated_commands"}});
        v["littoral"]["outcome"] = v["result"].clone();
        v["island_war"]["landing_transports"] = json!(landing_transports);
        v
    }
    fn motion_view(&self, v: &mut Value) {
        for (i, t) in self.core.ground.transports.iter().enumerate() {
            let speed = transport_stats(
                self.core.ground.groups[t.group].card.id,
                self.core.ground.groups[t.group].transport_kind,
            )
            .2;
            let dir = (t.goal - t.p).unit();
            v["littoral"]["transports"][i]["heading"] = json!(dir.heading());
            v["littoral"]["transports"][i]["velocity"] = json!(dir * speed);
            v["littoral"]["transports"][i]["remaining_seconds"] = json!(t.p.dist(t.goal) / speed);
        }
        for (i, a) in self.core.aircraft.iter().filter(|a| a.hp > 0.).enumerate() {
            v["littoral"]["aviation"]["aircraft"][i]["speed"] = json!(a.speed);
            v["littoral"]["aviation"]["aircraft"][i]["velocity"] =
                json!(P::bearing(a.heading) * a.speed);
        }
        for shot in v["littoral"]["shots"].as_array_mut().unwrap() {
            let p = point(shot);
            let target = P {
                x: shot["target_x"].as_f64().unwrap_or(p.x),
                y: shot["target_y"].as_f64().unwrap_or(p.y),
            };
            let speed = shot["speed"].as_f64().unwrap_or_else(|| {
                if shot["kind"] == "naval" {
                    900.
                } else if shot["kind"] == "aa" {
                    1500.
                } else {
                    1200.
                }
            });
            shot["launch_point"] = json!(p);
            shot["impact_point"] = json!(target);
            shot["speed"] = json!(speed);
            shot["heading"] = json!((target - p).heading());
            shot["flight_seconds"] = json!(p.dist(target) / speed);
            shot["velocity"] = json!((target - p).unit() * speed);
        }
        let mut projectiles:Vec<_>=self.core.ground.projectiles.iter().map(|p|json!({"id":p.id,"kind":p.kind,"source":p.source,"side":if p.ally{"allies"}else{"axis"},"x":p.p.x,"y":p.p.y,"impact_point":p.goal,"speed":p.speed,"heading":(p.goal-p.p).heading(),"velocity":(p.goal-p.p).unit()*p.speed,"remaining_seconds":p.p.dist(p.goal)/p.speed})).collect();
        projectiles.extend(self.shots.iter().map(|p|json!({"id":p.id,"kind":p.kind,"source":p.source,"side":if p.ally{"allies"}else{"axis"},"x":p.p.x,"y":p.p.y,"impact_point":p.goal,"speed":p.speed,"heading":(p.goal-p.p).heading(),"velocity":(p.goal-p.p).unit()*p.speed,"remaining_seconds":p.p.dist(p.goal)/p.speed})));
        v["littoral"]["projectiles"] = json!(projectiles);
    }
    pub(crate) fn validate_save(s: &Saved) -> E<()> {
        if s.version != VERSION
            || s.frame > MAX_FRAME
            || !s.tick.is_finite()
            || (s.tick - s.frame as f64 / 10.).abs() > 1e-6
            || s.commands.len() > 15000
            || s.commands.iter().any(|c| c.frame > s.frame)
            || s.commands.windows(2).any(|p| p[0].frame > p[1].frame)
        {
            return Err("海岛录像版本、时钟或指令日志无效".into());
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
    fn replay_to(&mut self, commands: &[Command], cursor: &mut usize, end: u32) -> E<()> {
        loop {
            while *cursor < commands.len()
                && commands[*cursor].frame == self.core.ground.frame
                && commands[*cursor].frame <= end
            {
                self.order(&commands[*cursor].request, true)?;
                *cursor += 1;
            }
            if self.core.ground.frame >= end {
                break;
            }
            if self.core.ground.result.is_some() {
                return Err("海岛录像越过真实终局".into());
            }
            self.advance();
        }
        Ok(())
    }
}
fn point(v: &Value) -> P {
    P {
        x: v["x"].as_f64().unwrap_or(0.),
        y: v["y"].as_f64().unwrap_or(0.),
    }
}
/// Separate, read-only cursor. It owns the complete future command log and never
/// replaces the active battle; forward seeks are O(delta), backward seeks rebuild.
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
        let mut replay = Self {
            key,
            source: saved,
            battle,
            cursor: 0,
        };
        replay.seek(end)?;
        Ok(replay)
    }
    pub(crate) fn matches(&self, saved: &Saved) -> bool {
        serde_json::to_string(saved).is_ok_and(|s| s == self.key)
    }
    pub(crate) fn seek(&mut self, end: u32) -> E<Value> {
        if end > self.source.frame {
            return Err("不能重演未来时刻".into());
        }
        if end < self.battle.core.ground.frame {
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
    fn request(mode: &str, npc: &str) -> Value {
        json!({"op":"new_island_battle","version":VERSION,"seed":714,"mode":mode,"ships":[{"id":"IBS-U-USN-ERMA-IOWA","hp":100,"ammo":100},{"id":ENTERPRISE,"hp":100,"ammo":100}],"roster":["MCP-034","MCP-001","MCP-009"],"transport_preset":"combat","company_layout":MULTI,"island":{"npc_id":npc,"island_level":NPCS[super::npc(npc).unwrap()].2}})
    }
    fn battle(mode: &str, npc: &str) -> Battle {
        let (seed, start) = Battle::decode(request(mode, npc)).unwrap();
        Battle::new(seed, start).unwrap()
    }
    fn advance(w: &mut Battle, n: u32) {
        for _ in 0..n {
            if w.core.ground.result.is_some() {
                break;
            }
            w.advance();
        }
    }
    fn ai(w: &mut Battle) {
        w.order(
            &json!({"op":"littoral_autonomy","version":VERSION,"enabled":true}),
            true,
        )
        .unwrap();
    }
    #[test]
    fn geometry_really_grows_and_all_three_beaches_paths_are_legal() {
        let mut sizes = vec![];
        for level in [1, 5, 10] {
            let mut q = request("raid", "shoal_watch");
            q["island"]["island_level"] = json!(level);
            let (seed, start) = Battle::decode(q).unwrap();
            let w = Battle::new(seed, start).unwrap();
            let poly = &w.core.ground.polygon;
            let min = poly.iter().map(|p| p.x).fold(f64::INFINITY, f64::min);
            let max = poly.iter().map(|p| p.x).fold(0., f64::max);
            sizes.push(max - min);
            for b in 1..=3 {
                let (s, l) = w.core.ground.beach_for(b).unwrap();
                assert!(w.core.ground.walkable(s, false));
                assert!(w.core.ground.walkable(l, true));
                assert!(w
                    .core
                    .ground
                    .path(l, w.core.ground.buildings[0].p, true)
                    .is_ok());
            }
            assert!(w.core.ground.walkable(w.geometry.exit(), false));
        }
        assert!(sizes[0] < sizes[1] && sizes[1] < sizes[2]);
    }
    #[test]
    fn actual_garrison_unmoors_and_fires_only_after_its_countdown() {
        let mut w = battle("raid", "shoal_watch");
        assert_eq!(w.anchors[0].phase, "anchored");
        advance(&mut w, 1);
        assert_eq!(w.anchors[0].phase, "unmooring");
        let enemy = w.anchors[0].ship;
        assert_eq!(w.core.naval.ship(enemy).unwrap().speed, 0.);
        advance(&mut w, 59);
        assert_eq!(w.anchors[0].phase, "unmooring");
        advance(&mut w, 30);
        assert_eq!(w.anchors[0].phase, "active");
        assert!(
            w.core
                .naval
                .fleets
                .iter()
                .find(|f| f.side == 1)
                .unwrap()
                .ai
                .gun
        );
    }
    #[test]
    fn six_towers_have_real_ammo_armor_and_finite_repairs() {
        let mut w = battle("raid", "old_arsenal");
        let mg = w
            .core
            .ground
            .buildings
            .iter()
            .position(|b| b.kind == "machine_gun")
            .unwrap();
        let p = w.core.ground.buildings[mg].p;
        w.core.ground.body(
            "test-marine".into(),
            true,
            "marine",
            p + P { x: -100., y: 0. },
            100.,
        );
        let before = w.core.ground.buildings[mg].ammo;
        w.core.ground.frame = 20;
        w.towers();
        assert!(w.core.ground.buildings[mg].ammo < before);
        assert!(!w.shots.is_empty());
        let body = w
            .core
            .ground
            .bodies
            .iter()
            .find(|b| b.group == "test-marine")
            .unwrap()
            .id;
        let hp = w
            .core
            .ground
            .bodies
            .iter()
            .find(|b| b.id == body)
            .unwrap()
            .hp;
        for _ in 0..50 {
            w.projectiles();
        }
        assert!(
            w.core
                .ground
                .bodies
                .iter()
                .find(|b| b.id == body)
                .unwrap()
                .hp
                < hp
        );
        w.core.ground.buildings[mg].ammo = 0;
        w.shots.clear();
        w.towers();
        assert!(!w
            .shots
            .iter()
            .any(|s| s.source == w.core.ground.buildings[mg].id));
        assert!(
            structure_damage_factor("rifle", "cannon")
                < structure_damage_factor("anti_tank", "cannon")
        );
        assert!(body_damage_factor("machine_gun", 0.3) < body_damage_factor("cannon", 0.3));
        let repair = w
            .core
            .ground
            .buildings
            .iter()
            .position(|b| b.kind == "repair")
            .unwrap();
        w.core.ground.buildings[mg].p = w.core.ground.buildings[repair].p + P { x: 100., y: 0. };
        w.core.ground.buildings[mg].hp = 100.;
        w.core.ground.buildings[repair].ammo = 1;
        w.core.ground.buildings[repair].next = 0;
        w.towers();
        let repaired = w.core.ground.buildings[mg].hp;
        assert!(repaired > 100.);
        assert_eq!(w.core.ground.buildings[repair].ammo, 0);
        w.core.ground.frame += 100;
        w.towers();
        assert_eq!(w.core.ground.buildings[mg].hp, repaired);
    }
    #[test]
    fn warehouse_capture_requires_real_people_and_destroyed_stock_is_not_free_reward() {
        let mut w = battle("raid", "shoal_watch");
        let i = w.warehouses[0].building;
        let p = w.core.ground.buildings[i].p;
        w.core.ground.bodies.clear();
        for _ in 0..65 {
            w.capture_stores();
        }
        assert!(!w.warehouses[0].captured);
        w.core
            .ground
            .body("MCP-034-C01".into(), true, "marine", p, 100.);
        w.core.ground.buildings[i].hp = 0.;
        for _ in 0..60 {
            w.capture_stores();
        }
        assert!(w.warehouses[0].captured);
        assert_eq!(w.plundered, w.warehouses[0].stock.part(1, 4));
        w.finish(false, true);
        assert_eq!(w.view()["result"]["resources"], json!(Stock::default()));
    }
    #[test]
    fn new_growth_is_bounded_and_applied_to_newly_landed_bodies_once() {
        let mut q = request("defense", "shoal_watch");
        q["island"]["unit_growth"] =
            json!([{"id":"MCP-034","level":30,"ascension":2,"specialization":"precision"}]);
        let (seed, start) = Battle::decode(q).unwrap();
        let mut w = Battle::new(seed, start).unwrap();
        let b = w
            .core
            .ground
            .bodies
            .iter()
            .find(|b| unit_id(&b.group) == "MCP-034")
            .unwrap()
            .clone();
        assert!((b.max - 105.).abs() < 1e-8);
        assert!((b.damage - 23.1).abs() < 1e-8);
        w.grow_bodies();
        assert_eq!(
            w.core
                .ground
                .bodies
                .iter()
                .find(|x| x.id == b.id)
                .unwrap()
                .hp,
            b.hp
        );
    }
    #[test]
    fn full_multi_company_attack_extracts_real_loot_and_replays_exactly() {
        let mut w = battle("raid", "shoal_watch");
        ai(&mut w);
        advance(&mut w, 6000);
        let v = w.view();
        assert_eq!(
            v["result"]["success"], true,
            "{}",
            v["littoral"]["autonomy"]
        );
        assert!(v["result"]["resources"]["credits"].as_u64().unwrap() > 0);
        assert_eq!(v["result"]["units"].as_array().unwrap().len(), 3);
        assert!(w.warehouses.iter().all(|w| w.captured));
        assert!(w
            .core
            .ground
            .groups
            .iter()
            .all(|g| matches!(g.stage, "recovered" | "lost")));
        assert!(w.core.aircraft.is_empty());
        assert_eq!(Battle::from_save(w.save(), None).unwrap().view(), v);
    }
    #[test]
    fn defense_cannot_win_by_waiting_180_seconds_and_losses_are_actual() {
        let mut q = request("defense", "old_arsenal");
        q["ships"] = json!([{"id":"IBS-U-USN-FLETCHER","hp":30,"ammo":0}]);
        q["roster"] = json!(["MCP-034", "MCP-009"]);
        q["island"]["storage"] = json!({"credits":100,"scrap":40,"alloy":20,"protocols":1});
        let (seed, start) = Battle::decode(q).unwrap();
        let mut w = Battle::new(seed, start).unwrap();
        advance(&mut w, 1850);
        assert!(w
            .core
            .ground
            .result
            .as_ref()
            .is_none_or(|r| r["success"] != true));
        advance(&mut w, 7150);
        assert!(w.core.ground.result.is_some());
        assert!(w.plundered.credits <= 100 && w.plundered.protocols <= 1);
        assert_eq!(Battle::from_save(w.save(), None).unwrap().view(), w.view());
    }
    #[test]
    fn replay_cursor_keeps_future_commands_and_never_changes_live_battle() {
        let mut e = crate::Engine::default();
        assert_eq!(e.handle(request("raid", "shoal_watch"))["ok"], true);
        e.handle(json!({"op":"step","seconds":2}));
        e.handle(json!({"op":"littoral_autonomy","version":VERSION,"enabled":true}));
        e.handle(json!({"op":"step","seconds":20}));
        e.handle(json!({"op":"littoral_autonomy","version":VERSION,"enabled":false}));
        e.handle(json!({"op":"step","seconds":8}));
        let live = e.handle(json!({"op":"observe"}));
        let save = e.handle(json!({"op":"save"}))["data"].clone();
        for tick in [0, 5, 20, 7, 29, 30] {
            let actual = e.handle(json!({"op":"replay","save":save,"tick":tick}));
            assert_eq!(actual["ok"], true, "{actual}");
            let s: Saved = serde_json::from_value(save.clone()).unwrap();
            assert_eq!(
                actual["data"],
                Battle::from_save(s, Some(tick * 10)).unwrap().view()
            );
        }
        assert_eq!(e.handle(json!({"op":"observe"})), live);
    }
    #[test]
    fn invalid_new_configuration_does_not_silently_change_old_v4() {
        let mut q = request("raid", "shoal_watch");
        q["island"]["island_level"] = json!(11);
        let (seed, start) = Battle::decode(q).unwrap();
        assert!(Battle::new(seed, start).is_err());
        let mut q = request("raid", "shoal_watch");
        q["island"]["unit_growth"] = json!([{"id":"MCP-034","level":31,"ascension":0}]);
        let (seed, start) = Battle::decode(q).unwrap();
        assert!(Battle::new(seed, start).is_err());
        let v = catalogue();
        assert_eq!(v["islands"].as_array().unwrap().len(), 6);
        assert_eq!(v["tower_types"].as_array().unwrap().len(), 8);
    }
    #[test]
    fn anchored_orders_reject_without_canceling_ai_then_allow_manual_takeover() {
        let mut w = battle("defense", "shoal_watch");
        ai(&mut w);
        let command = json!({"op":"littoral_ship_order","ship":1,"action":"move",
            "x":w.geometry.exit().x,"y":w.geometry.exit().y,"speed":12});
        assert!(w.order(&command, true).is_err());
        assert!(w.commander.as_ref().unwrap().enabled);
        advance(&mut w, 70);
        assert!(w.order(&command, true).is_ok());
        assert!(!w.commander.as_ref().unwrap().enabled);
        assert_eq!(Battle::from_save(w.save(), None).unwrap().view(), w.view());
    }
    #[test]
    fn landing_craft_is_a_real_target_and_its_damage_is_not_healed_on_landing() {
        let mut w = battle("defense", "shoal_watch");
        let (sea, land) = w.geometry.beach(2).unwrap();
        let carrier = w.landings[0].carrier;
        w.core
            .naval
            .ships
            .iter_mut()
            .find(|s| s.id == carrier)
            .unwrap()
            .p = sea;
        w.enemy_landings();
        let id = w.landings[0].body.unwrap();
        let b = w
            .core
            .ground
            .bodies
            .iter_mut()
            .find(|b| b.id == id)
            .unwrap();
        b.hp = 180.;
        b.p = land;
        w.enemy_landings();
        assert!(w.landings[0].landed);
        assert!(
            !w.core
                .ground
                .bodies
                .iter()
                .find(|b| b.id == id)
                .unwrap()
                .active
        );
        let invaders: Vec<_> = w
            .core
            .ground
            .bodies
            .iter()
            .filter(|b| b.group.starts_with("npc-invader-0-"))
            .collect();
        assert!(!invaders.is_empty());
        assert!(invaders.iter().all(|b| (b.hp / b.max - 0.5).abs() < 1e-8));
        w.core.ground.bodies.clear();
        let beach = P {
            x: w.geometry.center.x - w.geometry.half_width + 100.,
            y: w.geometry.center.y,
        };
        let water = P {
            x: beach.x - 200.,
            y: beach.y,
        };
        assert!(w.core.ground.walkable(water, false));
        w.core
            .ground
            .body("friendly".into(), true, "rifle", beach, 100.);
        w.core
            .ground
            .body("craft".into(), false, "landing_craft", water, 100.);
        w.core.ground.bodies[1].damage = 0.;
        w.core.ground.bodies[1].ammo = 0;
        let hp = w.core.ground.bodies[1].hp;
        for _ in 0..25 {
            w.core.ground.advance();
        }
        assert!(
            w.core.ground.bodies[1].hp < hp,
            "shore infantry must be able to hit an actual visible landing craft at sea"
        );
    }
    #[test]
    fn physical_invasion_can_seize_exposed_stores_and_destroy_a_weak_defense() {
        let mut q = request("defense", "old_arsenal");
        q["ships"] = json!([{"id":"CAS-O-APV-TIDEBRIDGE","hp":10,"ammo":0}]);
        q["roster"] = json!(["MCP-034", "MCP-009"]);
        q["unit_condition"] = json!([{"id":"MCP-034","hp":10},{"id":"MCP-009","hp":10}]);
        q["island"]["forts"] = json!([{"id":"hq","kind":"hq","x":0.8,"y":0.5,"level":1,"hp":100},
            {"id":"warehouse","kind":"warehouse","x":0.5,"y":0.5,"level":1,"hp":100}]);
        q["island"]["storage"] = json!({"credits":100,"scrap":40,"alloy":20,"protocols":1});
        let (seed, start) = Battle::decode(q).unwrap();
        let mut w = Battle::new(seed, start).unwrap();
        ai(&mut w);
        advance(&mut w, 9000);
        let v = w.view();
        assert_eq!(v["result"]["success"], false);
        assert!(w.landings.iter().any(|l| l.landed));
        assert!(w.plundered.credits > 0 && w.plundered.credits <= 100);
        assert_eq!(v["result"]["resources"], json!(Stock::default()));
        assert!(v["result"]["units"]
            .as_array()
            .unwrap()
            .iter()
            .any(|u| u["hp_percent"].as_f64().unwrap() < 10.));
        assert_eq!(Battle::from_save(w.save(), None).unwrap().view(), v);
    }
}
