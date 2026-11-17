//! Explicit arcade event v2. Identity metadata is borrowed; combat and growth
//! belong only to this run. The v1 implementation and its replay stay intact.
use crate::{
    model::{E, P},
    world::roll,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet, VecDeque};

pub const VERSION: &str = "cas-event-tide-v2";
pub const HZ: u32 = 10;
const DURATION: u32 = 180;
const MAX_FOES: usize = 96;
const MAX_BOLTS: usize = 192;
const MAX_DROPS: usize = 48;
const RECENT: usize = 64;
const DT: f64 = 0.1;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub character_id: String,
    pub roster: Vec<String>,
    pub difficulty: String,
    pub intel_profile: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> Config {
        Config {
            character_id: "IBS-U-USN-FLETCHER".into(),
            roster: vec!["IBS-U-USN-ERMA-IOWA".into(), "IBS-U-USN-PENSACOLA".into()],
            difficulty: "normal".into(),
            intel_profile: crate::intel::VERSION.into(),
        }
    }
    fn new() -> Tide {
        Tide::new(42, config()).unwrap()
    }

    #[test]
    fn fractional_clock_rejects_bad_input_without_mutating_the_run() {
        let mut engine = crate::Engine::default();
        assert_eq!(engine.handle(json!({"op":"new_tide","version":VERSION,"seed":42,"character_id":"IBS-U-USN-FLETCHER","roster":[]}))["ok"],true);
        engine.handle(json!({"op":"route","fleet":1,"speed":60,"points":[{"x":18000,"y":7000}]}));
        let v = engine.handle(json!({"op":"step","seconds":0.1}))["data"].clone();
        assert_eq!(v["tick"], 0.1);
        assert_eq!(v["tide"]["frame"], 1);
        assert!(
            (v["ships"][0]["x"].as_f64().unwrap() - 12000. - 60. * crate::model::KNOT).abs() < 1e-7
        );
        for seconds in [
            json!(-0.1),
            json!(0.15),
            json!(2700.1),
            json!("0.1"),
            Value::Null,
        ] {
            assert_eq!(
                engine.handle(json!({"op":"step","seconds":seconds}))["ok"],
                false
            );
            assert_eq!(engine.handle(json!({"op":"observe"}))["data"], v);
        }
        for q in [
            json!({"op":"route","fleet":2,"points":[{"x":10000,"y":7000}]}),
            json!({"op":"speed","fleet":2,"speed":60}),
            json!({"op":"new_tide","version":VERSION,"seed":42,"character_id":"IBS-U-USN-FLETCHER","roster":["IBS-U-USN-FLETCHER"]}),
            json!({"op":"new_tide","version":VERSION,"seed":42,"character_id":"IBS-U-USN-FLETCHER","roster":["fabricated"]}),
        ] {
            assert_eq!(engine.handle(q)["ok"], false);
            assert_eq!(engine.handle(json!({"op":"observe"}))["data"], v);
        }
        let mut saved = engine.handle(json!({"op":"save"}))["data"].clone();
        saved["frame"] = json!(2);
        assert_eq!(
            engine.handle(json!({"op":"load","save":saved}))["ok"],
            false
        );
        assert_eq!(engine.handle(json!({"op":"observe"}))["data"], v);
    }

    #[test]
    fn save_replay_preserves_microframes_same_frame_order_and_stop() {
        let mut w = new();
        w.command(
            &json!({"op":"route","fleet":1,"speed":60,"points":[{"x":18000,"y":7000}]}),
            true,
        )
        .unwrap();
        for _ in 0..3 {
            w.advance();
        }
        w.command(&json!({"op":"speed","fleet":1,"speed":0}), true)
            .unwrap();
        w.command(&json!({"op":"speed","fleet":1,"speed":10}), true)
            .unwrap();
        w.advance();
        w.command(&json!({"op":"speed","fleet":1,"speed":0}), true)
            .unwrap();
        let before = w.center();
        w.advance();
        assert_eq!(w.center().x, before.x);
        let saved = w.save();
        assert_eq!(saved.frame, 5);
        assert_eq!(saved.tick, 0.5);
        assert_eq!(
            Tide::from_save(saved.clone(), None).unwrap().view(),
            w.view()
        );
        assert_eq!(Tide::from_save(saved.clone(), Some(3)).unwrap().frame, 3);
        let mut invalid = saved.clone();
        invalid.frame = 1801;
        invalid.tick = 180.1;
        assert!(Tide::from_save(invalid, None).is_err());
        let mut invalid = saved.clone();
        invalid.commands[0].frame = 6;
        assert!(Tide::from_save(invalid, None).is_err());
        let mut invalid = saved;
        invalid.commands.swap(0, 2);
        assert!(Tide::from_save(invalid, None).is_err());
    }

    #[test]
    fn reinforcement_requires_a_real_current_offer_and_can_be_declined() {
        let mut w = new();
        let forged =
            json!({"op":"tide_choose","offer_id":0,"upgrade":"reinforce:IBS-U-USN-ERMA-IOWA"});
        let before = w.view();
        assert!(w.command(&forged, true).is_err());
        assert_eq!(w.view(), before);
        w.frame = 249;
        w.level = 2;
        w.xp = w.xp_required();
        w.offer();
        assert_eq!(w.offer_kind, "upgrade");
        w.choices.clear();
        w.frame = 250;
        w.xp = w.xp_required();
        w.offer();
        assert_eq!(w.offer_kind, "reinforcement");
        let decline = w
            .choices
            .iter()
            .find(|c| !c.starts_with("reinforce:"))
            .unwrap()
            .clone();
        let remaining = w.reserves.len();
        w.command(
            &json!({"op":"tide_choose","offer_id":w.offer,"upgrade":decline}),
            true,
        )
        .unwrap();
        assert_eq!(w.members.len(), 1);
        assert_eq!(w.reserves.len(), remaining);
        w.xp = w.xp_required();
        w.offer();
        let q = json!({"op":"tide_choose","offer_id":w.offer,"upgrade":"reinforce:IBS-U-USN-ERMA-IOWA"});
        w.command(&q, true).unwrap();
        assert_eq!(w.members.len(), 2);
        assert_eq!(w.members[1].id, 2);
        assert_eq!(w.members[1].hull.identity, "IBS-U-USN-ERMA-IOWA");
        assert_eq!(w.members[1].joined, 250);
        assert_eq!(w.reserves.len(), remaining - 1);
        let before = w.view();
        assert!(w.command(&q, true).is_err());
        assert_eq!(w.view(), before);
        let frame = w.frame;
        w.xp = w.xp_required();
        w.offer();
        assert_eq!(w.offer_kind, "upgrade");
        assert!(w.view()["tide"]["choices"].as_array().unwrap().iter().all(|c| c["kind"] == "upgrade"));
        w.advance();
        assert_eq!(w.frame, frame);
    }

    #[test]
    fn role_profiles_drive_real_distinct_volleys_and_shared_growth() {
        let mut w = new();
        w.foes.clear();
        w.spawn("warden", w.center() + P { x: 1700., y: 0. }, true, false);
        let hulls = [
            w.members[0].hull.clone(),
            w.reserves[1].clone(),
            w.reserves[0].clone(),
        ];
        assert_eq!(
            hulls.iter().map(|h| h.kind.as_str()).collect::<Vec<_>>(),
            vec!["dd", "ca", "bb"]
        );
        for (i, hull) in hulls.into_iter().enumerate() {
            let mut m = w.members[0].clone();
            m.id = i as u32 + 1;
            m.hull = hull;
            m.gun = 0;
            m.torp = 0;
            if i == 0 {
                w.members[0] = m;
            } else {
                w.members.push(m);
            }
        }
        w.advance();
        let shots: Vec<_> = w.shots.iter().filter(|s| s["kind"] == "gun").collect();
        assert_eq!(shots.len(), 3);
        assert_eq!(
            shots
                .iter()
                .map(|s| s["count"].as_u64().unwrap())
                .collect::<Vec<_>>(),
            vec![3, 4, 2]
        );
        assert_eq!(shots[2]["radius"], 420.);
        assert_eq!(
            w.members.iter().map(|m| m.gun).collect::<Vec<_>>(),
            vec![9, 8, 13]
        );
        let torps: Vec<_> = w.shots.iter().filter(|s| s["kind"] == "torpedo").collect();
        assert_eq!(torps.len(), 2);
        assert_eq!(torps[0]["count"], 3);
        assert_eq!(torps[1]["count"], 1);
        for m in &w.members {
            let profile = m.hull.attack(w.attack_ranks());
            let actual: Vec<_> = w
                .bolts
                .iter()
                .filter(|b| b.own == m.id && b.kind == "gun")
                .collect();
            assert_eq!(actual.len(), profile.gun_count as usize);
            assert!(actual
                .iter()
                .all(|b| b.damage == profile.gun_damage && b.radius == profile.blast_radius));
        }
        w.upgrades.insert("damage".into(), 2);
        w.upgrades.insert("multishot".into(), 1);
        let v = w.view();
        assert_eq!(v["ships"][0]["attack_profile"]["gun_damage"], 76.);
        assert_eq!(v["ships"][1]["attack_profile"]["gun_damage"], 72.);
        assert_eq!(v["ships"][2]["attack_profile"]["gun_damage"], 122.);
        assert_eq!(v["ships"][2]["attack_profile"]["gun_count"], 3);
    }

    #[test]
    fn budgets_conserve_xp_and_reserve_room_for_the_real_boss() {
        let mut w = new();
        for _ in 0..200 {
            w.spawn("scavenger", w.center(), false, false);
        }
        assert_eq!(w.foes.len(), MAX_FOES);
        w.spawn("leviathan", w.center() + P { x: 1600., y: 0. }, false, true);
        assert_eq!(w.foes.len(), MAX_FOES);
        assert_eq!(w.foes.iter().filter(|f| f.boss).count(), 1);
        assert_eq!(w.kills, 0);
        assert_eq!(w.retired, 1);
        for i in 0..1000 {
            w.drop_xp(
                P {
                    x: (i % 100) as f64 * 500.,
                    y: (i / 100) as f64 * 500.,
                },
                3,
            );
        }
        assert_eq!(w.drops.len(), MAX_DROPS);
        assert_eq!(w.drops.iter().map(|d| d.value).sum::<u32>(), 3000);
        for _ in 0..300 {
            w.shoot(1, w.center(), 90., "gun", 44., 260.);
        }
        assert_eq!(w.bolts.len(), MAX_BOLTS);
        for i in 0..500 {
            w.event("test", &i.to_string(), w.center());
        }
        assert_eq!(w.events.len(), RECENT);
        assert_eq!(w.view()["events"].as_array().unwrap().len(), 40);
    }

    #[test]
    fn real_enemy_damage_and_missing_boss_are_failures_and_quitting_pays_zero() {
        let mut w = new();
        w.foes.clear();
        w.hp = 1.;
        w.spawn("warden", w.center(), true, false);
        w.foes[0].warning = Some((w.center(), 1));
        w.advance();
        assert_eq!(w.result.as_ref().unwrap()["success"], false);
        assert_eq!(w.result.as_ref().unwrap()["duration"], 0.1);
        let mut w = new();
        w.frame = 1799;
        w.advance();
        assert_eq!(w.result.as_ref().unwrap()["success"], false);
        assert_eq!(w.result.as_ref().unwrap()["boss_defeated"], false);
        let mut w = new();
        w.command(&json!({"op":"tide_abandon"}), true).unwrap();
        assert_eq!(w.result.as_ref().unwrap()["event_tokens"], 0);
        assert_eq!(Tide::from_save(w.save(), None).unwrap().view(), w.view());
    }

    #[test]
    fn v1_wrapper_remains_identical_and_world_switches_clear_the_activity() {
        let mut engine = crate::Engine::default();
        let mut old = crate::tide::Tide::new(
            42,
            crate::tide::Config {
                character_id: config().character_id,
                difficulty: "normal".into(),
                intel_profile: crate::intel::VERSION.into(),
            },
        )
        .unwrap();
        assert_eq!(
            engine.handle(json!({"op":"new_tide","seed":42,"character_id":"IBS-U-USN-FLETCHER"}))
                ["data"],
            old.view()
        );
        for _ in 0..3 {
            old.advance();
            assert_eq!(
                engine.handle(json!({"op":"step","seconds":1}))["data"],
                old.view()
            );
        }
        assert_eq!(
            engine.handle(json!({"op":"save"}))["data"],
            json!(old.save())
        );
        assert_eq!(
            engine.handle(json!({"op":"step","seconds":0.1}))["ok"],
            false
        );
        assert_eq!(engine.handle(json!({"op":"new_tide","version":VERSION,"seed":42,"character_id":"IBS-U-USN-FLETCHER","roster":[]}))["ok"],true);
        let tide = engine.handle(json!({"op":"save"}))["data"].clone();
        assert_eq!(engine.handle(json!({"op":"new","seed":42}))["ok"], true);
        assert!(engine.tide.is_none());
        assert!(engine.world.is_some());
        assert_eq!(engine.handle(json!({"op":"load","save":tide}))["ok"], true);
        assert!(engine.tide.is_some());
        assert!(engine.world.is_none());
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Command {
    pub frame: u32,
    pub request: Value,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Saved {
    pub version: String,
    pub seed: u32,
    pub config: Config,
    pub frame: u32,
    pub tick: f64,
    pub commands: Vec<Command>,
}
#[derive(Clone, Debug)]
struct Hull {
    identity: String,
    name: String,
    kind: String,
    caliber: f64,
}
#[derive(Clone, Copy)]
struct AttackProfile {
    gun_count: u32,
    gun_interval: u32,
    gun_damage: f64,
    blast_radius: f64,
    torpedo_count: u32,
    torpedo_interval: u32,
}
impl Hull {
    fn role(&self) -> &'static str {
        match self.kind.as_str() {
            "dd" | "de" | "dl" => "torpedo",
            "bb" | "bc" => "heavy",
            _ => "barrage",
        }
    }
    fn specialty(&self) -> &'static str {
        match self.role() {
            "torpedo" => "雷击扇面：三束快炮与三枚扇形鱼雷",
            "heavy" => "重炮轰击：两束高伤炮击，爆炸范围更大",
            _ => "密集炮幕：四束快炮持续清扫敌群",
        }
    }
    fn attack(&self, ranks: [u32; 5]) -> AttackProfile {
        let [damage, haste, multishot, torpedo, blast] = ranks;
        let (count, interval, damage_base, radius, torps, torp_interval) = match self.role() {
            "torpedo" => (3, 8u32, 44., 260., 3, 25u32),
            "heavy" => (2, 12u32, 90., 420., 0, 35u32),
            _ => (4, 7u32, 40., 260., 1, 30u32),
        };
        AttackProfile {
            gun_count: count + multishot,
            gun_interval: interval.saturating_sub(haste).max(3),
            gun_damage: damage_base + damage as f64 * 16.,
            blast_radius: radius + blast as f64 * 100.,
            torpedo_count: torps + torpedo,
            torpedo_interval: torp_interval.saturating_sub(torpedo * 4).max(12),
        }
    }
}
impl AttackProfile {
    fn view(self) -> Value {
        json!({"gun_count":self.gun_count,"gun_damage":self.gun_damage,"gun_interval_seconds":self.gun_interval as f64/HZ as f64,"blast_radius":self.blast_radius,"torpedo_count":self.torpedo_count,"torpedo_interval_seconds":self.torpedo_interval as f64/HZ as f64})
    }
}
#[derive(Clone, Debug)]
struct Member {
    id: u32,
    hull: Hull,
    p: P,
    h: f64,
    joined: u32,
    gun: u32,
    torp: u32,
}
#[derive(Clone, Debug)]
struct Foe {
    id: u32,
    kind: &'static str,
    p: P,
    h: f64,
    hp: f64,
    max: f64,
    speed: f64,
    damage: f64,
    next: u32,
    warning: Option<(P, u32)>,
    elite: bool,
    boss: bool,
    hurt: u32,
    born: u32,
}
#[derive(Clone, Debug)]
struct Bolt {
    id: u32,
    own: u32,
    p: P,
    h: f64,
    speed: f64,
    damage: f64,
    radius: f64,
    life: u32,
    kind: &'static str,
}
#[derive(Clone, Debug, Serialize)]
struct Drop {
    id: u32,
    x: f64,
    y: f64,
    value: u32,
}
const UPGRADES: [(&str, &str, &str); 11] = [
    ("damage", "过载炮膛", "每发炮击伤害+16，所有队员共享"),
    ("haste", "协同装填", "炮击间隔缩短0.1秒，最低0.3秒"),
    ("multishot", "交叉火线", "每舰每轮增加一束真实炮击"),
    ("torpedo", "潮汐雷阵", "增加雷击扇面与发射频率"),
    ("magnet", "信号牵引", "经验牵引范围+450米"),
    ("shield", "应急装甲", "全队耐久上限+100并修复140"),
    ("maneuver", "跃浪推进", "全队航速提高12%"),
    ("blast", "破片扩散", "每发爆炸半径+100米"),
    ("repair", "纳米修补", "全队每秒恢复2点耐久"),
    ("chain", "电弧接力", "命中后连锁打击更多附近敌人"),
    ("orbit", "共鸣脉冲", "每半秒清扫舰队周围的近身敌群"),
];

pub struct Tide {
    pub seed: u32,
    pub config: Config,
    pub frame: u32,
    pub result: Option<Value>,
    members: Vec<Member>,
    reserves: Vec<Hull>,
    hp: f64,
    maxhp: f64,
    speed: f64,
    route: Vec<P>,
    foes: Vec<Foe>,
    bolts: Vec<Bolt>,
    drops: Vec<Drop>,
    dead: VecDeque<Value>,
    events: VecDeque<Value>,
    shots: VecDeque<Value>,
    impacts: VecDeque<Value>,
    next_event: u32,
    next_id: u32,
    rng: u64,
    upgrades: BTreeMap<String, u32>,
    choices: Vec<String>,
    offer: u32,
    offer_kind: &'static str,
    level: u32,
    xp: u32,
    kills: u32,
    elite_kills: u32,
    boss_dead: bool,
    boss_spawned: bool,
    spawned: u32,
    retired: u32,
    commands: Vec<Command>,
}

fn bounded(list: &mut VecDeque<Value>, value: Value) {
    if list.len() == RECENT {
        list.pop_front();
    }
    list.push_back(value);
}
pub fn frames(seconds: &Value) -> E<u32> {
    let n = seconds.as_f64().ok_or("活动推进秒数无效")?;
    let f = n * HZ as f64;
    if !n.is_finite() || !(0. ..=2700.).contains(&n) || (f - f.round()).abs() > 0.000001 {
        return Err("新版活动推进须为0.1秒的非负倍数".into());
    }
    Ok(f.round() as u32)
}
impl Tide {
    pub fn new(seed: u32, config: Config) -> E<Self> {
        if !["normal", "hard"].contains(&config.difficulty.as_str())
            || config.intel_profile != crate::intel::VERSION
            || config.roster.len() > 64
        {
            return Err("活动难度、敌情版本或后备人数无效".into());
        }
        let mut seen = BTreeSet::new();
        let data = crate::salvage_v3::data()?;
        let mut hulls = Vec::new();
        for identity in std::iter::once(&config.character_id).chain(config.roster.iter()) {
            if !seen.insert(identity) {
                return Err("首舰和后备舰娘身份不能重复".into());
            }
            let def = data
                .ships
                .iter()
                .find(|d| d.id == *identity && d.id.starts_with("IBS-U-"))
                .ok_or("活动舰娘身份未登记")?;
            hulls.push(Hull {
                identity: identity.clone(),
                name: def.name.clone(),
                kind: def.kind.to_lowercase(),
                caliber: def.gun.caliber_mm,
            });
        }
        let leader = Member {
            id: 1,
            hull: hulls.remove(0),
            p: P {
                x: 12000.,
                y: 7000.,
            },
            h: 90.,
            joined: 0,
            gun: 0,
            torp: 20,
        };
        let mut w = Self {
            seed,
            config,
            frame: 0,
            result: None,
            members: vec![leader],
            reserves: hulls,
            hp: 500.,
            maxhp: 500.,
            speed: 38.,
            route: vec![],
            foes: vec![],
            bolts: vec![],
            drops: vec![],
            dead: VecDeque::new(),
            events: VecDeque::new(),
            shots: VecDeque::new(),
            impacts: VecDeque::new(),
            next_event: 0,
            next_id: 0,
            rng: seed as u64 ^ 0x5251_f738_abcd,
            upgrades: BTreeMap::new(),
            choices: vec![],
            offer: 0,
            offer_kind: "upgrade",
            level: 1,
            xp: 0,
            kills: 0,
            elite_kills: 0,
            boss_dead: false,
            boss_spawned: false,
            spawned: 0,
            retired: 0,
            commands: vec![],
        };
        w.event(
            "start",
            "潮汐突围：移动清扫敌群，升级构筑并从自选后备中呼叫援军。全队共享耐久，强化仅限本局。",
            w.center(),
        );
        w.swarm(16);
        Ok(w)
    }
    pub fn tick(&self) -> f64 {
        self.frame as f64 / HZ as f64
    }
    fn center(&self) -> P {
        self.members[0].p
    }
    fn id(&mut self) -> u32 {
        self.next_id += 1;
        self.next_id
    }
    fn rank(&self, key: &str) -> u32 {
        *self.upgrades.get(key).unwrap_or(&0)
    }
    fn attack_ranks(&self) -> [u32; 5] {
        [
            self.rank("damage"),
            self.rank("haste"),
            self.rank("multishot"),
            self.rank("torpedo"),
            self.rank("blast"),
        ]
    }
    fn event(&mut self, kind: &str, text: &str, p: P) {
        self.next_event += 1;
        bounded(
            &mut self.events,
            json!({"id":self.next_event,"frame":self.frame,"tick":(self.frame as f64 / HZ as f64),"kind":kind,"text":text,"x":p.x,"y":p.y}),
        );
    }
    fn xp_required(&self) -> u32 {
        20 + self.level * 8
    }
    fn spawn(&mut self, kind: &'static str, p: P, elite: bool, boss: bool) {
        if self.foes.len() >= MAX_FOES {
            // Priority enemies must still enter a saturated arena. Retire one
            // ordinary enemy without awarding a kill or XP; never exceed cap.
            if (elite || boss) && self.foes.iter().any(|f| !f.elite && !f.boss) {
                let i = self.foes.iter().position(|f| !f.elite && !f.boss).unwrap();
                self.foes.remove(i);
                self.retired += 1;
            } else {
                return;
            }
        }
        let hard = if self.config.difficulty == "hard" {
            1.35
        } else {
            1.
        };
        let hp = if boss {
            4200.
        } else if elite {
            260. + (self.frame as f64 / HZ as f64) * 2.
        } else {
            22. + (self.frame / (60 * HZ)) as f64 * 4.
        } * hard;
        let id = self.id();
        self.foes.push(Foe {
            id,
            kind,
            p: P {
                x: p.x.clamp(500., 23500.),
                y: p.y.clamp(500., 13500.),
            },
            h: 0.,
            hp,
            max: hp,
            speed: if boss {
                205.
            } else if elite {
                205.
            } else {
                190.
            },
            damage: if boss {
                62.
            } else if elite {
                28.
            } else {
                9.
            } * hard,
            next: self.frame + 18,
            warning: None,
            elite,
            boss,
            hurt: 0,
            born: self.frame,
        });
        self.spawned += 1;
    }
    fn swarm(&mut self, count: u32) {
        let center = self.center();
        for i in 0..count.min((MAX_FOES - self.foes.len()) as u32) {
            let a = (i as f64 * 360. / count as f64 + roll(&mut self.rng, 35) as f64) % 360.;
            let r = if self.frame == 0 {
                700. + roll(&mut self.rng, 750) as f64
            } else {
                1050. + roll(&mut self.rng, 1000) as f64
            };
            self.spawn(
                ["scavenger", "spitter", "cult_ray"][(i as usize + self.frame as usize / 20) % 3],
                center + P::bearing(a) * r,
                false,
                false,
            );
        }
    }
    fn offer(&mut self) {
        if self.xp < self.xp_required() || !self.choices.is_empty() || self.result.is_some() {
            return;
        }
        self.xp -= self.xp_required();
        self.level += 1;
        self.offer += 1;
        let recruit = self.members.len() < 6
            && !self.reserves.is_empty()
            && self.level >= 3 + (self.members.len() as u32 - 1) * 2
            && self.frame >= 25 * HZ * self.members.len() as u32;
        if recruit {
            self.offer_kind = "reinforcement";
            self.choices = self
                .reserves
                .iter()
                .map(|h| format!("reinforce:{}", h.identity))
                .collect();
            self.choices.push(
                UPGRADES
                    .iter()
                    .find(|u| self.rank(u.0) < 4)
                    .map_or("restore", |u| u.0)
                    .into(),
            );
        } else {
            self.offer_kind = "upgrade";
            let mut pool: Vec<String> = UPGRADES
                .iter()
                .filter(|u| self.rank(u.0) < 4)
                .map(|u| u.0.into())
                .collect();
            if self.level <= 4 {
                let attacks: Vec<_> = pool
                    .iter()
                    .enumerate()
                    .filter(|(_, id)| {
                        ["damage", "haste", "multishot", "blast", "chain", "orbit"]
                            .contains(&id.as_str())
                    })
                    .map(|(i, _)| i)
                    .collect();
                if !attacks.is_empty() {
                    let i = attacks[(roll(&mut self.rng, attacks.len() as u32) - 1) as usize];
                    self.choices.push(pool.remove(i));
                }
            }
            while self.choices.len() < 3 && !pool.is_empty() {
                let i = (roll(&mut self.rng, pool.len() as u32) - 1) as usize;
                self.choices.push(pool.remove(i));
            }
            if self.choices.is_empty() {
                self.choices.push("restore".into());
            }
        }
        self.event(
            "tide_level",
            if recruit {
                "援军信号接通：选择一名已选后备舰娘，或继续强化"
            } else {
                "共鸣增强：选择一项本局强化"
            },
            self.center(),
        );
    }
    pub fn paused(&self) -> bool {
        !self.choices.is_empty()
    }
    fn finish(&mut self, success: bool) {
        if self.result.is_some() {
            return;
        }
        let tokens = (if success { 100 } else { 15 }
            + self.kills.min(2000) / 10
            + self.elite_kills.min(20) * 5
            + if self.boss_dead { 40 } else { 0 })
        .min(1000);
        self.result = Some(
            json!({"success":success,"event_tokens":tokens,"score":(self.kills*10+self.elite_kills*100+if self.boss_dead{1000}else{0}).min(999999),"kills":self.kills,"elite_kills":self.elite_kills,"boss_defeated":self.boss_dead,"duration":(self.frame as f64 / HZ as f64),"members":self.members.len(),"reinforcements":self.members.len()-1}),
        );
        self.choices.clear();
        self.event(
            "end",
            if success {
                "敌群已清退，舰队与回响结晶一同回收"
            } else {
                "共鸣中断，全队已回收"
            },
            self.center(),
        );
    }
    pub fn command(&mut self, q: &Value, record: bool) -> E<Value> {
        if self.result.is_some() {
            return Err("活动已经结束".into());
        }
        if record && self.commands.len() >= 10000 {
            return Err("活动命令数量已达上限，请结束本局".into());
        }
        match q["op"].as_str().ok_or("活动操作无效")? {
            "tide_choose" => {
                let offer = q["offer_id"].as_u64().ok_or("缺少强化批次")?;
                let id = q["upgrade"].as_str().ok_or("请选择强化或援军")?;
                if offer != self.offer as u64 || !self.choices.iter().any(|choice| choice == id) {
                    return Err("强化或援军选项已过期或不存在".into());
                }
                if let Some(identity) = id.strip_prefix("reinforce:") {
                    let index = self
                        .reserves
                        .iter()
                        .position(|h| h.identity == identity)
                        .ok_or("援军身份不在本局后备中")?;
                    if self.members.len() >= 6 {
                        return Err("本局编队已满".into());
                    }
                    let hull = self.reserves.remove(index);
                    let number = self.members.len() as u32 + 1;
                    let p = self.center() - P::bearing(self.members[0].h) * 650.;
                    self.members.push(Member {
                        id: number,
                        hull,
                        p: P {
                            x: p.x.clamp(300., 23700.),
                            y: p.y.clamp(300., 13700.),
                        },
                        h: self.members[0].h,
                        joined: self.frame,
                        gun: self.frame,
                        torp: self.frame + 5,
                    });
                    self.maxhp += 80.;
                    self.hp = (self.hp + 120.).min(self.maxhp);
                    self.event(
                        "tide_reinforcement",
                        &format!(
                            "{} 已加入编队，全队共享局内强化",
                            self.members.last().unwrap().hull.name
                        ),
                        p,
                    );
                } else if id == "restore" {
                    self.hp = (self.hp + 140.).min(self.maxhp);
                    self.event("tide_upgrade", "应急修复完成", self.center());
                } else {
                    let title = UPGRADES.iter().find(|u| u.0 == id).ok_or("强化不存在")?.1;
                    *self.upgrades.entry(id.into()).or_default() += 1;
                    if id == "shield" {
                        self.maxhp += 100.;
                        self.hp = (self.hp + 140.).min(self.maxhp);
                    }
                    self.event("tide_upgrade", &format!("获得强化：{title}"), self.center());
                }
                self.choices.clear();
                self.offer();
            }
            "route" => {
                let points: Vec<P> =
                    serde_json::from_value(q["points"].clone()).map_err(|_| "活动航点无效")?;
                let speed = q
                    .get("speed")
                    .map_or(Some(self.speed), Value::as_f64)
                    .ok_or("速度无效")?;
                if points.is_empty()
                    || points.len() > 10
                    || points.iter().any(|p| {
                        !p.x.is_finite()
                            || !p.y.is_finite()
                            || !(300. ..=23700.).contains(&p.x)
                            || !(300. ..=13700.).contains(&p.y)
                    })
                    || !speed.is_finite()
                    || !(4. ..=60.).contains(&speed)
                    || q.get("fleet").is_some_and(|v| v.as_u64() != Some(1))
                {
                    return Err("航路超出活动海域或编队/速度无效".into());
                }
                self.route = points;
                self.speed = speed;
            }
            "speed" => {
                let n = q["speed"].as_f64().ok_or("速度无效")?;
                if !n.is_finite()
                    || !(0. ..=60.).contains(&n)
                    || q.get("fleet").is_some_and(|v| v.as_u64() != Some(1))
                {
                    return Err("活动速度须为0–60，编队须为1".into());
                }
                self.speed = n;
            }
            "tide_abandon" => {
                self.finish(false);
                let r = self.result.as_mut().unwrap();
                r["abandoned"] = json!(true);
                r["event_tokens"] = json!(0);
            }
            _ => return Err("此指令不属于潮汐突围".into()),
        }
        if record {
            self.commands.push(Command {
                frame: self.frame,
                request: q.clone(),
            });
        }
        Ok(self.view())
    }
    fn shoot(&mut self, own: u32, p: P, h: f64, kind: &'static str, damage: f64, radius: f64) {
        if self.bolts.len() >= MAX_BOLTS {
            return;
        }
        let id = self.id();
        self.bolts.push(Bolt {
            id,
            own,
            p,
            h,
            speed: if kind == "gun" { 2400. } else { 1250. },
            damage,
            radius,
            life: if kind == "gun" { 30 } else { 55 },
            kind,
        });
    }
    fn impact(&mut self, p: P, damage: f64, radius: f64, kind: &str, own: u32) {
        let mut hits = 0;
        let mut kills = 0;
        for f in &mut self.foes {
            if f.hp > 0. && f.p.dist(p) <= radius {
                f.hp -= damage;
                f.hurt = self.frame;
                hits += 1;
                kills += u32::from(f.hp <= 0.);
            }
        }
        if hits > 0 {
            let id = self.id();
            bounded(
                &mut self.impacts,
                json!({"id":id,"frame":self.frame,"tick":(self.frame as f64 / HZ as f64),"ship_id":own,"x":p.x,"y":p.y,"radius":radius,"damage":damage,"kind":kind,"hits":hits,"kills":kills}),
            );
        }
    }
    fn drop_xp(&mut self, p: P, value: u32) {
        if let Some(d) = self
            .drops
            .iter_mut()
            .find(|d| P { x: d.x, y: d.y }.dist(p) < 350.)
        {
            d.value += value;
            return;
        }
        if self.drops.len() >= MAX_DROPS {
            let d = self
                .drops
                .iter_mut()
                .min_by(|a, b| {
                    P { x: a.x, y: a.y }
                        .dist(p)
                        .total_cmp(&P { x: b.x, y: b.y }.dist(p))
                })
                .unwrap();
            d.value += value;
            return;
        }
        let id = self.id();
        self.drops.push(Drop {
            id,
            x: p.x,
            y: p.y,
            value,
        });
    }
    pub fn advance(&mut self) {
        if self.result.is_some() || self.paused() {
            return;
        }
        self.frame += 1;
        let velocity =
            self.speed * crate::model::KNOT * 10. * (1. + self.rank("maneuver") as f64 * 0.12);
        let mut travel = velocity * DT;
        while travel > 0. && !self.route.is_empty() {
            let target = self.route[0];
            let d = self.center().dist(target);
            if d < 0.0001 {
                self.route.remove(0);
                continue;
            }
            let m = &mut self.members[0];
            m.h = (target - m.p).heading();
            if d <= travel {
                m.p = target;
                self.route.remove(0);
                travel -= d;
            } else {
                m.p = m.p + (target - m.p) * (travel / d);
                travel = 0.;
            }
        }
        let center = self.center();
        let heading = self.members[0].h;
        for (i, m) in self.members.iter_mut().enumerate().skip(1) {
            let row = i.div_ceil(2) as f64;
            let side = if i % 2 == 0 { 1. } else { -1. };
            let goal = center - P::bearing(heading) * (400. * row)
                + P::bearing(heading + 90.) * (330. * side);
            let d = m.p.dist(goal);
            if d > 0.001 {
                m.h = (goal - m.p).heading();
                m.p = m.p + (goal - m.p) * ((velocity.max(220.) * 1.5 * DT) / d).min(1.);
            }
        }
        self.hp = (self.hp + self.rank("repair") as f64 * 2. * DT).min(self.maxhp);
        if self.frame % 20 == 0 && self.frame < DURATION * HZ {
            self.swarm(8 + self.frame / (30 * HZ) * 2);
        }
        if self.frame % (30 * HZ) == 0 && self.frame < 150 * HZ {
            self.spawn("warden", center + P { x: 1500., y: 700. }, true, false);
            self.event("tide_elite", "精英信号进入海域", center);
        }
        if self.frame == 150 * HZ {
            self.boss_spawned = true;
            self.spawn("leviathan", center + P { x: 1600., y: 0. }, false, true);
            self.event(
                "tide_boss",
                "回响核心显形，击败它并带领编队坚持至回收",
                center,
            );
        }
        let positions: Vec<P> = self.members.iter().map(|m| m.p).collect();
        for foe in &mut self.foes {
            if foe.hp <= 0. {
                continue;
            }
            let target = *positions
                .iter()
                .min_by(|a, b| a.dist(foe.p).total_cmp(&b.dist(foe.p)))
                .unwrap();
            let d = foe.p.dist(target);
            foe.h = (target - foe.p).heading();
            if foe.warning.is_none() && d > 280. {
                foe.p = foe.p + (target - foe.p) * (foe.speed * DT / d).min(1.);
            }
            if let Some((p, due)) = foe.warning {
                if self.frame >= due {
                    if positions.iter().any(|point| {
                        point.dist(p)
                            <= if foe.boss {
                                500.
                            } else if foe.elite {
                                280.
                            } else {
                                180.
                            }
                    }) {
                        self.hp -= foe.damage;
                    }
                    foe.warning = None;
                    foe.next = self.frame + if foe.boss { 28 } else { 30 };
                }
            } else if self.frame >= foe.next && d < if foe.boss { 2800. } else { 1050. } {
                foe.warning = Some((target, self.frame + 12));
            }
        }
        let attack_ranks = self.attack_ranks();
        let torp_damage = 100. + self.rank("torpedo") as f64 * 20.;
        let torp_radius = 480. + self.rank("blast") as f64 * 70.;
        let mut volleys = vec![];
        for m in &mut self.members {
            let profile = m.hull.attack(attack_ranks);
            let target = self
                .foes
                .iter()
                .filter(|f| f.hp > 0. && f.p.dist(m.p) < 4200.)
                .min_by(|a, b| a.p.dist(m.p).total_cmp(&b.p.dist(m.p)));
            if let Some(target) = target {
                if self.frame >= m.gun {
                    volleys.push((
                        m.id,
                        m.p,
                        target.p,
                        "gun",
                        profile.gun_count,
                        profile.gun_damage,
                        profile.blast_radius,
                        m.hull.caliber,
                    ));
                    m.gun = self.frame + profile.gun_interval;
                }
                if profile.torpedo_count > 0 && self.frame >= m.torp {
                    volleys.push((
                        m.id,
                        m.p,
                        target.p,
                        "torpedo",
                        profile.torpedo_count,
                        torp_damage,
                        torp_radius,
                        m.hull.caliber,
                    ));
                    m.torp = self.frame + profile.torpedo_interval;
                }
            }
        }
        for (own, p, target, kind, count, damage, radius, caliber) in volleys {
            let before = self.bolts.len();
            for i in 0..count {
                self.shoot(
                    own,
                    p,
                    (target - p).heading()
                        + (i as f64 - (count - 1) as f64 / 2.)
                            * if kind == "gun" { 5. } else { 12. },
                    kind,
                    damage,
                    radius,
                );
            }
            let emitted = self.bolts.len() - before;
            if emitted > 0 {
                let id = self.id();
                bounded(
                    &mut self.shots,
                    json!({"id":id,"frame":self.frame,"tick":(self.frame as f64 / HZ as f64),"ship_id":own,"kind":kind,"x":p.x,"y":p.y,"target_x":target.x,"target_y":target.y,"count":emitted,"radius":radius,"caliber_mm":caliber}),
                );
            }
        }
        let mut impacts = vec![];
        for bolt in &mut self.bolts {
            let end = bolt.p + P::bearing(bolt.h) * bolt.speed * DT;
            let hit = self
                .foes
                .iter()
                .filter(|f| {
                    f.hp > 0. && crate::adventure::segment_distance(f.p, bolt.p, end) < 100.
                })
                .min_by(|a, b| a.p.dist(bolt.p).total_cmp(&b.p.dist(bolt.p)))
                .map(|f| f.p);
            bolt.p = end;
            bolt.life = bolt.life.saturating_sub(1);
            if let Some(p) = hit {
                impacts.push((p, bolt.damage, bolt.radius, bolt.kind, bolt.own));
                bolt.life = 0;
            }
        }
        self.bolts.retain(|b| b.life > 0);
        let chain = self.rank("chain");
        for (p, damage, radius, kind, own) in impacts {
            self.impact(p, damage, radius, kind, own);
            let mut origin = p;
            for _ in 0..chain * 2 {
                let next = self
                    .foes
                    .iter()
                    .filter(|f| f.hp > 0. && f.p.dist(origin) < 750.)
                    .min_by(|a, b| a.p.dist(origin).total_cmp(&b.p.dist(origin)))
                    .map(|f| f.p);
                let Some(next) = next else {
                    break;
                };
                self.impact(next, damage * 0.65, 100., "chain", own);
                let id = self.id();
                bounded(
                    &mut self.shots,
                    json!({"id":id,"frame":self.frame,"tick":(self.frame as f64 / HZ as f64),"ship_id":own,"kind":"chain","x":origin.x,"y":origin.y,"target_x":next.x,"target_y":next.y,"count":1,"radius":100}),
                );
                origin = next;
            }
        }
        if self.rank("orbit") > 0 && self.frame % 5 == 0 {
            self.impact(
                center,
                16. + self.rank("orbit") as f64 * 12.,
                500. + self.rank("orbit") as f64 * 180.,
                "pulse",
                1,
            );
        }
        let killed: Vec<_> = self.foes.iter().filter(|f| f.hp <= 0.).cloned().collect();
        self.foes.retain(|f| f.hp > 0.);
        for f in killed {
            self.kills += 1;
            self.elite_kills += u32::from(f.elite);
            self.boss_dead |= f.boss;
            self.drop_xp(
                f.p,
                if f.boss {
                    50
                } else if f.elite {
                    15
                } else {
                    3
                },
            );
            bounded(
                &mut self.dead,
                json!({"id":format!("T{}",f.id),"source_contact":format!("T{}",f.id),"species":f.kind,"visualType":f.kind,"entityKind":"monster","x":f.p.x,"y":f.p.y,"heading":f.h,"death_tick":(self.frame as f64 / HZ as f64),"death_frame":self.frame}),
            );
        }
        let radius = 1200. + self.rank("magnet") as f64 * 450.;
        let mut picked = 0;
        for d in &mut self.drops {
            let p = P { x: d.x, y: d.y };
            let distance = p.dist(center);
            if distance < radius && distance > 120. {
                let next = p + (center - p) * (1500. * DT / distance).min(1.);
                d.x = next.x;
                d.y = next.y;
            }
        }
        self.drops.retain(|d| {
            if (P { x: d.x, y: d.y }).dist(center) < 150. {
                picked += d.value;
                false
            } else {
                true
            }
        });
        self.xp += picked;
        let before = self.foes.len();
        let frame = self.frame;
        self.foes
            .retain(|f| f.boss || f.elite || f.p.dist(center) < 6500. || frame - f.born < 200);
        self.retired += (before - self.foes.len()) as u32;
        self.dead
            .retain(|d| self.frame - d["death_frame"].as_u64().unwrap() as u32 <= 20);
        if self.hp <= 0. {
            self.hp = 0.;
            self.finish(false);
        } else if self.frame >= DURATION * HZ {
            self.finish(self.boss_dead);
        } else {
            self.offer();
        }
    }
    pub fn save(&self) -> Saved {
        Saved {
            version: VERSION.into(),
            seed: self.seed,
            config: self.config.clone(),
            frame: self.frame,
            tick: (self.frame as f64 / HZ as f64),
            commands: self.commands.clone(),
        }
    }
    pub fn from_save(s: Saved, target: Option<u32>) -> E<Self> {
        if s.version != VERSION
            || s.frame > DURATION * HZ
            || !s.tick.is_finite()
            || (s.tick - s.frame as f64 / HZ as f64).abs() > 0.000001
            || s.commands.len() > 10000
            || s.commands.iter().any(|c| c.frame > s.frame)
            || s.commands.windows(2).any(|p| p[0].frame > p[1].frame)
        {
            return Err("活动存档版本、微步时钟或命令序列无效".into());
        }
        let target = target.unwrap_or(s.frame).min(s.frame);
        let mut w = Self::new(s.seed, s.config)?;
        let mut commands = s.commands.into_iter().peekable();
        loop {
            while commands
                .peek()
                .is_some_and(|c| c.frame == w.frame && c.frame <= target)
            {
                let c = commands.next().unwrap();
                w.command(&c.request, true)?;
            }
            if w.frame >= target {
                break;
            }
            if w.paused() || w.result.is_some() {
                return Err("活动重演在选择或终局后越过时钟".into());
            }
            w.advance();
        }
        Ok(w)
    }
    pub fn preview(&self, q: &Value) -> Value {
        let Ok(points) = serde_json::from_value::<Vec<P>>(q["points"].clone()) else {
            return json!({"valid":false,"paths":[],"error":"航点无效"});
        };
        let speed = q.get("speed").map_or(Some(self.speed), Value::as_f64);
        if points.is_empty()
            || points.len() > 10
            || points.iter().any(|p| {
                !p.x.is_finite()
                    || !p.y.is_finite()
                    || !(300. ..=23700.).contains(&p.x)
                    || !(300. ..=13700.).contains(&p.y)
            })
            || speed.is_none_or(|n| !n.is_finite() || !(4. ..=60.).contains(&n))
            || q.get("fleet").is_some_and(|v| v.as_u64() != Some(1))
        {
            return json!({"valid":false,"paths":[],"error":"航点或速度无效"});
        }
        json!({"valid":true,"speed":speed,"error":null,"paths":self.members.iter().map(|m|{let mut path=vec![m.p];path.extend(points.iter().copied());json!({"ship":m.id,"points":path})}).collect::<Vec<_>>()})
    }
    pub fn view(&self) -> Value {
        let choices:Vec<_>=self.choices.iter().map(|id| {
            if let Some(identity)=id.strip_prefix("reinforce:") {let h=self.reserves.iter().find(|h|h.identity==identity).unwrap();json!({"id":id,"kind":"reinforcement","character_id":identity,"name":h.name,"role":h.role(),"attack_profile":h.attack(self.attack_ranks()).view(),"description":format!("{}；独立自动攻击并共享强化，全队耐久+80并修复120",h.specialty()),"icon":"reinforce","rank":1})}
            else {let u=UPGRADES.iter().find(|u|u.0==id);json!({"id":id,"kind":"upgrade","name":u.map_or("应急修复",|u|u.1),"description":u.map_or("修复全队140耐久",|u|u.2),"icon":id,"rank":self.rank(id)+1})}
        }).collect();
        let ships:Vec<_>=self.members.iter().map(|m|json!({"id":m.id,"name":m.hull.name,"characterId":m.hull.identity,"kind":m.hull.kind,"tide_role":m.hull.role(),"attack_profile":m.hull.attack(self.attack_ranks()).view(),"fleet":1,"x":m.p.x,"y":m.p.y,"heading":m.h,"speed":if self.route.is_empty(){0.}else{self.speed},"hp":self.hp,"maxHp":self.maxhp,"hullLengthM":100,"gunRange":4200,"torpedoRange":6000,"gun":true,"torpedo":m.hull.attack(self.attack_ranks()).torpedo_count>0,"ammo":999,"mainCaliberMm":m.hull.caliber,"systems":{"guns":[],"tubes":[],"maxSpeed":60}})).collect();
        let contacts:Vec<_>=self.foes.iter().map(|f|json!({"id":format!("T{}",f.id),"x":f.p.x,"y":f.p.y,"heading":f.h,"speed":f.speed/(crate::model::KNOT*10.),"kind":"monster","name":if f.boss{"回响核心"}else if f.elite{"精英礁脊"}else{"潮汐异种"},"entityKind":"monster","species":f.kind,"visualType":f.kind,"boss":f.boss,"elite":f.elite,"health":f.hp,"max_health":f.max,"health_fraction":f.hp/f.max,"hurt_tick":f.hurt as f64/HZ as f64,"attack":{"kind":"pulse","state":if f.warning.is_some(){"windup"}else if self.frame<f.next{"recover"}else{"approach"},"label":"回响冲击","counter":"移动离开锁定点，用爆炸与连锁清扫包围","seconds":f.warning.map_or(f.next.saturating_sub(self.frame),|(_,due)|due.saturating_sub(self.frame)) as f64/HZ as f64,"range":if f.boss{2800}else{1050},"radius":if f.boss{500}else if f.elite{280}else{180},"shape":"circle"},"intelligence":{"speed_max":f.speed/(crate::model::KNOT*10.),"attack_damage":f.damage,"attack_range":if f.boss{2800}else{1050},"attack_cooldown":3,"armor":0,"weaknesses":"普通敌人可一击清除，移动拾取经验并呼叫援军"}})).collect();
        let warnings:Vec<_>=self.foes.iter().filter_map(|f|f.warning.map(|(p,due)|json!({"id":f.id,"source_contact":format!("T{}",f.id),"kind":"pulse","name":"回响冲击","counter":"离开标记范围","shape":"circle","x":p.x,"y":p.y,"radius":if f.boss{500}else if f.elite{280}else{180},"start_tick":(due-12) as f64/HZ as f64,"impact_tick":due as f64/HZ as f64,"exempt_ship_id":null}))).collect();
        let members:Vec<_>=self.members.iter().map(|m|json!({"ship_id":m.id,"character_id":m.hull.identity,"name":m.hull.name,"kind":m.hull.kind,"role":m.hull.role(),"attack_profile":m.hull.attack(self.attack_ranks()).view(),"joined_tick":m.joined as f64/HZ as f64,"joined_frame":m.joined,"joined_sequence":m.id})).collect();
        let reserves: Vec<_> = self
            .reserves
            .iter()
            .map(|h| json!({"character_id":h.identity,"name":h.name,"kind":h.kind,"role":h.role(),"attack_profile":h.attack(self.attack_ranks()).view()}))
            .collect();
        let paths: Vec<_> = self
            .members
            .iter()
            .map(|m| {
                let mut p = vec![m.p];
                p.extend(self.route.iter().copied());
                json!({"ship":m.id,"points":p})
            })
            .collect();
        let result=self.result.as_ref().map(|r|json!({"winner":if r["success"]==true{"allies"}else{"axis"},"primary":r["success"],"allies":self.kills,"axis":0}));
        let activity = json!({"version":VERSION,"duration":DURATION,"frame":self.frame,"simulation_hz":HZ,"team_hp":self.hp,"team_max_hp":self.maxhp,"members":members,"reserves":reserves,"slots":{"used":self.members.len(),"max":6,"available":6-self.members.len()},"wave":(self.frame/(30*HZ)+1).min(6),"kills":self.kills,"elite_kills":self.elite_kills,"boss_defeated":self.boss_dead,"boss_spawned":self.boss_spawned,"level":self.level,"xp":self.xp,"xp_required":self.xp_required(),"drops":self.drops,"upgrades":self.upgrades,"choices":choices,"offer_id":self.offer,"offer_kind":self.offer_kind,"paused":self.paused(),"shots":self.shots,"impacts":self.impacts,"aura_radius":if self.rank("orbit")>0 {500.+self.rank("orbit") as f64*180.}else{0.},"budget":{"foes":MAX_FOES,"bolts":MAX_BOLTS,"drops":MAX_DROPS,"recent_effects":RECENT},"spawned":self.spawned,"retired":self.retired,"outcome":self.result});
        json!({"version":VERSION,"scenario":"潮汐突围","tick":(self.frame as f64 / HZ as f64),"limit":DURATION,"width":24000,"height":14000,"side":"allies","intel_profile":crate::intel::VERSION,"islands":[],"ships":ships,"fleets":[{"id":1,"leader":1,"members":self.members.iter().map(|m|m.id).collect::<Vec<_>>(),"name":"回响编队","mode":"follow","speed":self.speed,"actual":if self.route.is_empty(){0.}else{self.speed},"maxSpeed":60,"points":self.route,"paths":paths}],"contacts":contacts,"shells":self.bolts.iter().filter(|b|b.kind=="gun").map(|b|json!({"id":b.id,"x":b.p.x,"y":b.p.y,"heading":b.h,"side":"allies","own_ship":b.own})).collect::<Vec<_>>(),"torpedoes":self.bolts.iter().filter(|b|b.kind=="torpedo").map(|b|json!({"id":b.id,"x":b.p.x,"y":b.p.y,"heading":b.h,"side":"allies","own":true,"own_ship":b.own})).collect::<Vec<_>>(),"events":self.events.iter().rev().take(40).collect::<Vec<_>>(),"result":result,"salvage":{"content":VERSION,"generatorVersion":"archipelago-tide-2","terrainTheme":"atoll","landmarks":[],"telegraphs":warnings,"defeated_entities":self.dead,"adventure":{"version":VERSION,"movement_multiplier":10}},"tide":activity})
    }
}
