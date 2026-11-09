//! Genetic training for the CAS surface AI.
//!
//! The trainer evolves one parameter vector per fleet style. Fitness comes from
//! real headless matches on the same Rust core the game runs (no scripted
//! results, no synthetic scores): each candidate is played on both seats
//! against a fixed builtin opponent on fixed seeds. The winning vectors are
//! written to `data/ai/evolved.json`, which `src/ai.rs` embeds at build time.
//!
//! Everything here is native-only and deterministic: the population, the
//! matches and the reported fitness are reproducible from the recorded config.

use crate::{
    ai::{self, Style},
    model::*,
    world::World,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

pub const TRAINING_SCHEMA: &str = "cas-ai-training-v1";
pub const PROFILE_SCHEMA: &str = "cas-ai-profiles-v1";
pub const ARENA: &str = "fictional-training-2x2";

/// Gene bounds. Each pair is the closed interval a mutation may produce.
const RANGE_BOUNDS: (f64, f64) = (2_600., 8_000.);
const FLANK_BOUNDS: (f64, f64) = (35., 95.);
const SPEED_BOUNDS: (f64, f64) = (20., 32.);
const TORP_FRACTION_BOUNDS: (f64, f64) = (0.45, 0.95);
const PERIOD_BOUNDS: (u32, u32) = (80, 150);
const COORDINATION_BOUNDS: (f64, f64) = (0.05, 1.);
const CROSSFIRE_BOUNDS: (f64, f64) = (0.05, 1.);
const T_HEAD_BOUNDS: (f64, f64) = (0.05, 1.);
const SCREEN_BOUNDS: (f64, f64) = (0.05, 1.);
const SPREAD_BOUNDS: (f64, f64) = (0.05, 1.);
const TORP_ANGLE_BOUNDS: (f64, f64) = (20., 160.);
const FRIENDLY_MARGIN_BOUNDS: (f64, f64) = (600., 2_000.);
const WITHDRAW_BOUNDS: (f64, f64) = (0.08, 0.4);

/// Default withdrawal threshold for evolved styles. The screen objective keeps
/// this fixed so a "survive by running" genome cannot win it; the brawler and
/// kiter objectives evolve their own threshold inside `WITHDRAW_BOUNDS`.
const WITHDRAW_HP: f64 = 0.2;

fn default_withdraw_hp() -> f64 {
    WITHDRAW_HP
}

fn is_default_withdraw_hp(value: &f64) -> bool {
    (*value - WITHDRAW_HP).abs() < 1e-9
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Genome {
    pub range: f64,
    pub flank: f64,
    pub speed: f64,
    pub torp_fraction: f64,
    pub period: u32,
    pub focus: bool,
    pub coordination: f64,
    pub crossfire: f64,
    pub t_head: f64,
    pub screen: f64,
    pub spread: f64,
    pub torp_angle: f64,
    pub friendly_margin: f64,
    /// Per-profile withdrawal threshold. Appended after the original gene
    /// list so the three pre-batch profiles keep their exact encoded keys and
    /// match records (`0.2` is omitted when serialized).
    #[serde(default = "default_withdraw_hp", skip_serializing_if = "is_default_withdraw_hp")]
    pub withdraw_hp: f64,
}

impl Genome {
    pub fn anchor(objective: Objective) -> Self {
        match objective {
            Objective::Screen => Self {
                range: 5_200.,
                flank: 70.,
                speed: 26.,
                torp_fraction: 0.72,
                period: 100,
                focus: true,
                coordination: 0.85,
                crossfire: 0.6,
                t_head: 0.5,
                screen: 0.95,
                spread: 0.55,
                torp_angle: 90.,
                friendly_margin: 1_200.,
                withdraw_hp: WITHDRAW_HP,
            },
            Objective::Torpedo => Self {
                range: 3_400.,
                flank: 64.,
                speed: 28.,
                torp_fraction: 0.9,
                period: 95,
                focus: false,
                coordination: 0.75,
                crossfire: 0.85,
                t_head: 0.3,
                screen: 0.25,
                spread: 0.5,
                torp_angle: 90.,
                friendly_margin: 900.,
                withdraw_hp: WITHDRAW_HP,
            },
            Objective::Gunnery => Self {
                range: 6_850.,
                flank: 82.,
                speed: 25.,
                torp_fraction: 0.66,
                period: 120,
                focus: true,
                coordination: 0.6,
                crossfire: 0.5,
                t_head: 0.95,
                screen: 0.35,
                spread: 0.7,
                torp_angle: 70.,
                friendly_margin: 1_000.,
                withdraw_hp: WITHDRAW_HP,
            },
            Objective::Brawler => Self {
                range: 2_600.,
                flank: 38.,
                speed: 31.,
                torp_fraction: 0.92,
                period: 85,
                focus: true,
                coordination: 0.45,
                crossfire: 0.35,
                t_head: 0.15,
                screen: 0.15,
                spread: 0.3,
                torp_angle: 55.,
                friendly_margin: 700.,
                withdraw_hp: 0.1,
            },
            Objective::Kiter => Self {
                range: 8_000.,
                flank: 58.,
                speed: 31.,
                torp_fraction: 0.75,
                period: 75,
                focus: false,
                coordination: 0.55,
                crossfire: 0.65,
                t_head: 0.4,
                screen: 0.3,
                spread: 0.55,
                torp_angle: 105.,
                friendly_margin: 1_500.,
                withdraw_hp: 0.36,
            },
            Objective::Denial => Self {
                range: 5_800.,
                flank: 60.,
                speed: 28.,
                torp_fraction: 0.95,
                period: 80,
                focus: false,
                coordination: 0.95,
                crossfire: 0.6,
                t_head: 0.3,
                screen: 0.85,
                spread: 0.85,
                torp_angle: 150.,
                friendly_margin: 1_600.,
                withdraw_hp: WITHDRAW_HP,
            },
        }
    }

    pub fn to_style(&self) -> Style {
        Style {
            range: self.range,
            flank: self.flank,
            speed: self.speed,
            torp_fraction: self.torp_fraction,
            period: self.period,
            focus: self.focus,
            withdraw_hp: self.withdraw_hp,
            coordination: self.coordination,
            crossfire: self.crossfire,
            t_head: self.t_head,
            screen: self.screen,
            spread: self.spread,
            torp_angle: self.torp_angle,
            friendly_margin: self.friendly_margin,
            evolved: true,
        }
    }

    pub fn key(&self) -> String {
        self.to_style().encode()
    }

    fn random(rng: &mut Rng) -> Self {
        Self {
            range: rng.range(RANGE_BOUNDS.0, RANGE_BOUNDS.1),
            flank: rng.range(FLANK_BOUNDS.0, FLANK_BOUNDS.1),
            speed: rng.range(SPEED_BOUNDS.0, SPEED_BOUNDS.1),
            torp_fraction: rng.range(TORP_FRACTION_BOUNDS.0, TORP_FRACTION_BOUNDS.1),
            period: rng.range(PERIOD_BOUNDS.0 as f64, PERIOD_BOUNDS.1 as f64) as u32,
            focus: rng.unit() > 0.5,
            coordination: rng.range(COORDINATION_BOUNDS.0, COORDINATION_BOUNDS.1),
            crossfire: rng.range(CROSSFIRE_BOUNDS.0, CROSSFIRE_BOUNDS.1),
            t_head: rng.range(T_HEAD_BOUNDS.0, T_HEAD_BOUNDS.1),
            screen: rng.range(SCREEN_BOUNDS.0, SCREEN_BOUNDS.1),
            spread: rng.range(SPREAD_BOUNDS.0, SPREAD_BOUNDS.1),
            torp_angle: rng.range(TORP_ANGLE_BOUNDS.0, TORP_ANGLE_BOUNDS.1),
            friendly_margin: rng.range(FRIENDLY_MARGIN_BOUNDS.0, FRIENDLY_MARGIN_BOUNDS.1),
            withdraw_hp: WITHDRAW_HP,
        }
        .quantized()
    }

    /// Random seed genome for one objective. The three pre-batch objectives
    /// keep the fixed withdrawal threshold so their GA stream is unchanged;
    /// brawler and kiter search their own threshold.
    fn random_for(objective: Objective, rng: &mut Rng) -> Self {
        let mut genome = Self::random(rng);
        if matches!(
            objective,
            Objective::Brawler | Objective::Kiter | Objective::Denial
        ) {
            let draw = |rng: &mut Rng, bounds: (f64, f64)| rng.range(bounds.0, bounds.1);
            genome.range = draw(rng, objective.range_bounds());
            genome.speed = draw(rng, objective.speed_bounds());
            genome.torp_fraction = draw(rng, objective.torp_fraction_bounds());
            genome.torp_angle = draw(rng, objective.torp_angle_bounds());
            genome.t_head = draw(rng, objective.t_head_bounds());
            genome.coordination = draw(rng, objective.coordination_bounds());
            genome.screen = draw(rng, objective.screen_bounds());
            genome.spread = draw(rng, objective.spread_bounds());
        }
        if objective.evolves_withdrawal() {
            genome.withdraw_hp = rng.range(objective.withdraw_bounds().0, objective.withdraw_bounds().1);
        }
        genome.quantized()
    }

    fn quantized(mut self) -> Self {
        self.range = round_to(self.range, 10.);
        self.flank = round_to(self.flank, 0.5);
        self.speed = round_to(self.speed, 0.5);
        self.torp_fraction = round_to(self.torp_fraction, 0.01);
        self.coordination = round_to(self.coordination, 0.01);
        self.crossfire = round_to(self.crossfire, 0.01);
        self.t_head = round_to(self.t_head, 0.01);
        self.screen = round_to(self.screen, 0.01);
        self.spread = round_to(self.spread, 0.01);
        self.torp_angle = round_to(self.torp_angle, 1.);
        self.friendly_margin = round_to(self.friendly_margin, 50.);
        self.withdraw_hp = round_to(self.withdraw_hp, 0.01);
        self.clamp();
        self
    }

    fn clamp(&mut self) {
        self.range = self.range.clamp(RANGE_BOUNDS.0, RANGE_BOUNDS.1);
        self.flank = self.flank.clamp(FLANK_BOUNDS.0, FLANK_BOUNDS.1);
        self.speed = self.speed.clamp(SPEED_BOUNDS.0, SPEED_BOUNDS.1);
        self.torp_fraction = self
            .torp_fraction
            .clamp(TORP_FRACTION_BOUNDS.0, TORP_FRACTION_BOUNDS.1);
        self.period = self.period.clamp(PERIOD_BOUNDS.0, PERIOD_BOUNDS.1);
        self.coordination = self
            .coordination
            .clamp(COORDINATION_BOUNDS.0, COORDINATION_BOUNDS.1);
        self.crossfire = self.crossfire.clamp(CROSSFIRE_BOUNDS.0, CROSSFIRE_BOUNDS.1);
        self.t_head = self.t_head.clamp(T_HEAD_BOUNDS.0, T_HEAD_BOUNDS.1);
        self.screen = self.screen.clamp(SCREEN_BOUNDS.0, SCREEN_BOUNDS.1);
        self.spread = self.spread.clamp(SPREAD_BOUNDS.0, SPREAD_BOUNDS.1);
        self.torp_angle = self.torp_angle.clamp(TORP_ANGLE_BOUNDS.0, TORP_ANGLE_BOUNDS.1);
        self.friendly_margin = self
            .friendly_margin
            .clamp(FRIENDLY_MARGIN_BOUNDS.0, FRIENDLY_MARGIN_BOUNDS.1);
        self.withdraw_hp = self.withdraw_hp.clamp(WITHDRAW_BOUNDS.0, WITHDRAW_BOUNDS.1);
    }

    fn crossover(a: &Self, b: &Self, rng: &mut Rng) -> Self {
        let pick = |rng: &mut Rng, x: f64, y: f64| if rng.unit() < 0.5 { x } else { y };
        Self {
            range: pick(rng, a.range, b.range),
            flank: pick(rng, a.flank, b.flank),
            speed: pick(rng, a.speed, b.speed),
            torp_fraction: pick(rng, a.torp_fraction, b.torp_fraction),
            period: if rng.unit() < 0.5 { a.period } else { b.period },
            focus: if rng.unit() < 0.5 { a.focus } else { b.focus },
            coordination: pick(rng, a.coordination, b.coordination),
            crossfire: pick(rng, a.crossfire, b.crossfire),
            t_head: pick(rng, a.t_head, b.t_head),
            screen: pick(rng, a.screen, b.screen),
            spread: pick(rng, a.spread, b.spread),
            torp_angle: pick(rng, a.torp_angle, b.torp_angle),
            friendly_margin: pick(rng, a.friendly_margin, b.friendly_margin),
            // Copying (rather than picking) keeps the pre-batch RNG stream
            // untouched for the fixed-threshold objectives; brawler/kiter
            // still mutate their threshold afterwards.
            withdraw_hp: a.withdraw_hp,
        }
        .quantized()
    }

    fn mutate(&mut self, rng: &mut Rng, rate: f64, objective: Objective) {
        let mut jitter = |rng: &mut Rng, value: &mut f64, bounds: (f64, f64)| {
            if rng.unit() < rate {
                let span = bounds.1 - bounds.0;
                *value += gaussian(rng) * span * 0.12;
            }
        };
        jitter(rng, &mut self.range, objective.range_bounds());
        jitter(rng, &mut self.flank, FLANK_BOUNDS);
        jitter(rng, &mut self.speed, objective.speed_bounds());
        jitter(rng, &mut self.torp_fraction, objective.torp_fraction_bounds());
        jitter(rng, &mut self.coordination, objective.coordination_bounds());
        jitter(rng, &mut self.crossfire, CROSSFIRE_BOUNDS);
        jitter(rng, &mut self.t_head, objective.t_head_bounds());
        jitter(rng, &mut self.screen, objective.screen_bounds());
        jitter(rng, &mut self.spread, objective.spread_bounds());
        jitter(rng, &mut self.torp_angle, objective.torp_angle_bounds());
        jitter(rng, &mut self.friendly_margin, FRIENDLY_MARGIN_BOUNDS);
        if objective.evolves_withdrawal() {
            jitter(rng, &mut self.withdraw_hp, objective.withdraw_bounds());
        }
        if rng.unit() < rate {
            self.period = (self.period as i32 + if rng.unit() < 0.5 { -5 } else { 5 })
                .clamp(PERIOD_BOUNDS.0 as i32, PERIOD_BOUNDS.1 as i32)
                as u32;
        }
        if rng.unit() < rate * 0.5 {
            self.focus = !self.focus;
        }
        *self = self.clone().quantized();
        self.clamp_to_objective(objective);
    }

    fn clamp_to_objective(&mut self, objective: Objective) {
        if !matches!(
            objective,
            Objective::Brawler | Objective::Kiter | Objective::Denial
        ) {
            return;
        }
        let clamp = |value: &mut f64, bounds: (f64, f64)| {
            *value = value.clamp(bounds.0, bounds.1);
        };
        clamp(&mut self.range, objective.range_bounds());
        clamp(&mut self.speed, objective.speed_bounds());
        clamp(&mut self.torp_fraction, objective.torp_fraction_bounds());
        clamp(&mut self.torp_angle, objective.torp_angle_bounds());
        clamp(&mut self.t_head, objective.t_head_bounds());
        clamp(&mut self.coordination, objective.coordination_bounds());
        clamp(&mut self.screen, objective.screen_bounds());
        clamp(&mut self.spread, objective.spread_bounds());
        if objective.evolves_withdrawal() {
            clamp(&mut self.withdraw_hp, objective.withdraw_bounds());
        }
    }
}

fn round_to(value: f64, step: f64) -> f64 {
    (value / step).round() * step
}

fn gaussian(rng: &mut Rng) -> f64 {
    (rng.unit() + rng.unit() + rng.unit() - 1.5) * 2.
}

struct Rng(u64);
impl Rng {
    fn new(seed: u64) -> Self {
        Self(seed | 1)
    }
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }
    fn unit(&mut self) -> f64 {
        (self.next() >> 11) as f64 / ((1u64 << 53) as f64)
    }
    fn range(&mut self, low: f64, high: f64) -> f64 {
        low + (high - low) * self.unit()
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n.max(1) as u64) as usize
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Objective {
    Screen,
    Torpedo,
    Gunnery,
    Brawler,
    Kiter,
    Denial,
}

impl Objective {
    fn all() -> [Self; 6] {
        [
            Self::Screen,
            Self::Torpedo,
            Self::Gunnery,
            Self::Brawler,
            Self::Kiter,
            Self::Denial,
        ]
    }
    fn id(self) -> &'static str {
        match self {
            Self::Screen => "evo-screen",
            Self::Torpedo => "evo-torpedo",
            Self::Gunnery => "evo-gunnery",
            Self::Brawler => "evo-brawler",
            Self::Kiter => "evo-kiter",
            Self::Denial => "evo-denial",
        }
    }
    fn name(self) -> &'static str {
        match self {
            Self::Screen => "帷幄 · 屏护协同",
            Self::Torpedo => "夜潮 · 雷击突击",
            Self::Gunnery => "铁幕 · 炮战纵队",
            Self::Brawler => "绞肉 · 近战乱斗",
            Self::Kiter => "拖刀 · 远距风筝",
            Self::Denial => "雷网 · 封走位",
        }
    }
    fn description(self) -> &'static str {
        match self {
            Self::Screen => "以屏护与交叉火力为主：驱逐分队卡在敌雷击队与主力之间，炮战保持射界并抢 T 头。",
            Self::Torpedo => "以雷击为主：分队分头绕向敌纵队侧翼，压缩距离后按侧舷角放雷，炮战只做压制。",
            Self::Gunnery => "以炮战为主：保持远距射界，优先抢占敌纵队的 T 头位置，用交叉火力分散其指挥。",
            Self::Brawler => "以近距乱战为主：高航速贴脸，压缩到 3 公里内炮雷混战，低撤退阈值。",
            Self::Kiter => "以远距风筝为主：保持 6 公里外射界，边打边退维持射程边缘，高撤退阈值。",
            Self::Denial => "以鱼雷扇面封走位为主：高雷击占比、宽扇面与屏护协同，目标不是命中而是逼敌转向。",
        }
    }
    fn role(self) -> &'static str {
        match self {
            Self::Screen => "screen",
            Self::Torpedo => "torpedo",
            Self::Gunnery => "gunnery",
            Self::Brawler => "brawler",
            Self::Kiter => "kiter",
            Self::Denial => "denial",
        }
    }
    fn seal_salt(self) -> u64 {
        match self {
            Self::Screen => 0x51ce_0001,
            Self::Torpedo => 0x70a9_0002,
            Self::Gunnery => 0x6011_0003,
            Self::Brawler => 0x6b7a_0004,
            Self::Kiter => 0x4b17_0005,
            Self::Denial => 0xde41_0006,
        }
    }
    /// Builtin profile this objective is compared against on every report.
    fn baseline(self) -> &'static str {
        match self {
            Self::Screen => "coord",
            Self::Torpedo => "torpedo",
            Self::Gunnery => "gunnery",
            Self::Brawler => "torpedo",
            Self::Kiter => "gunnery",
            Self::Denial => "torpedo",
        }
    }
    /// Catalog-stage key that unlocks this profile. `CAMP-ALLIES-06` only
    /// exists as an archived crosswalk entry without a runnable runtime, so the
    /// kiter uses the existing playable Empress Augusta Bay stage instead; the
    /// substitution is recorded in `data/ai/ai-report.json`.
    fn unlock(self) -> &'static str {
        match self {
            Self::Screen => "campaign:CAMP-ALLIES-02",
            Self::Torpedo => "campaign:CAMP-ALLIES-03",
            Self::Gunnery => "campaign:CAMP-ALLIES-11",
            Self::Brawler => "campaign:CAMP-ALLIES-05",
            Self::Kiter => "campaign:CAMP-ALLIES-11",
            Self::Denial => "campaign:CAMP-ALLIES-10",
        }
    }
    /// Provisional shop price in recruit tickets. The store merge manifest
    /// marks it as pending an economy pass; it is not a balance claim.
    fn cost(self) -> u32 {
        match self {
            Self::Screen => 800,
            Self::Torpedo => 900,
            Self::Gunnery => 1_000,
            Self::Brawler => 900,
            Self::Kiter => 1_100,
            Self::Denial => 1_200,
        }
    }
    /// Brawler and kiter evolve their own withdrawal threshold; the other
    /// four objectives keep the pre-batch fixed 0.2 so their GA stream and
    /// fitness stay byte-identical.
    fn evolves_withdrawal(self) -> bool {
        matches!(self, Self::Brawler | Self::Kiter)
    }

    // Doctrine envelopes. The three pre-batch objectives use the original
    // global bounds, so their random and mutation streams are unchanged. The
    // new objectives search inside a doctrine envelope: the shop description
    // promises a role, and the GA must not hand back a "brawler" that kites.
    fn range_bounds(self) -> (f64, f64) {
        match self {
            Self::Brawler => (2_600., 3_200.),
            Self::Kiter => (7_400., 8_000.),
            Self::Denial => (5_000., 6_500.),
            _ => RANGE_BOUNDS,
        }
    }
    fn speed_bounds(self) -> (f64, f64) {
        match self {
            Self::Brawler | Self::Kiter => (29., 32.),
            Self::Denial => (26., 30.),
            _ => SPEED_BOUNDS,
        }
    }
    fn torp_fraction_bounds(self) -> (f64, f64) {
        match self {
            Self::Brawler => (0.85, 0.95),
            Self::Kiter => (0.6, 0.9),
            Self::Denial => (0.9, 0.95),
            _ => TORP_FRACTION_BOUNDS,
        }
    }
    fn torp_angle_bounds(self) -> (f64, f64) {
        match self {
            Self::Brawler => (40., 80.),
            Self::Kiter => (80., 130.),
            Self::Denial => (140., 160.),
            _ => TORP_ANGLE_BOUNDS,
        }
    }
    fn t_head_bounds(self) -> (f64, f64) {
        match self {
            Self::Brawler => (0.05, 0.35),
            Self::Kiter => (0.6, 1.),
            Self::Denial => (0.1, 0.5),
            _ => T_HEAD_BOUNDS,
        }
    }
    fn coordination_bounds(self) -> (f64, f64) {
        match self {
            Self::Brawler => (0.05, 0.6),
            Self::Kiter => (0.2, 0.8),
            Self::Denial => (0.8, 1.),
            _ => COORDINATION_BOUNDS,
        }
    }
    fn screen_bounds(self) -> (f64, f64) {
        match self {
            Self::Brawler => (0.05, 0.3),
            Self::Kiter => (0.1, 0.5),
            Self::Denial => (0.7, 1.),
            _ => SCREEN_BOUNDS,
        }
    }
    fn spread_bounds(self) -> (f64, f64) {
        match self {
            Self::Brawler => (0.1, 0.5),
            Self::Kiter => (0.3, 0.8),
            Self::Denial => (0.6, 0.9),
            _ => SPREAD_BOUNDS,
        }
    }
    fn withdraw_bounds(self) -> (f64, f64) {
        match self {
            Self::Brawler => (0.08, 0.12),
            Self::Kiter => (0.32, 0.4),
            _ => WITHDRAW_BOUNDS,
        }
    }
    /// Whether this profile's numbers came from the GA. A hand-authored
    /// fallback would be marked `hand_authored` instead of claiming a search.
    fn basis(self) -> &'static str {
        "ga"
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SeedCase {
    pub seed: u32,
    pub opponent: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TrainConfig {
    pub schema: String,
    pub population: usize,
    pub generations: usize,
    pub elitism: usize,
    pub mutation: f64,
    pub crossover: f64,
    pub rng_seed: u64,
    pub train: Vec<SeedCase>,
    pub validation: Vec<SeedCase>,
    pub seats: Vec<usize>,
    pub arena: String,
    pub time_limit_seconds: u32,
    pub match_limit: usize,
}

impl Default for TrainConfig {
    fn default() -> Self {
        Self {
            schema: TRAINING_SCHEMA.into(),
            population: 6,
            generations: 3,
            elitism: 2,
            mutation: 0.35,
            crossover: 0.6,
            rng_seed: 0xC0FFEE_2026,
            train: vec![
                SeedCase { seed: 6106, opponent: "coord".into() },
                SeedCase { seed: 6107, opponent: "gunnery".into() },
            ],
            validation: vec![
                SeedCase { seed: 6111, opponent: "torpedo".into() },
                SeedCase { seed: 6112, opponent: "coord".into() },
                SeedCase { seed: 6113, opponent: "gunnery".into() },
            ],
            seats: vec![0, 1],
            arena: ARENA.into(),
            time_limit_seconds: LIMIT,
            match_limit: 3,
        }
    }
}

impl TrainConfig {
    fn validate(&self) -> E<()> {
        if self.schema != TRAINING_SCHEMA {
            return Err("训练配置 schema 不符".into());
        }
        if self.population < 2 || self.population > 64 {
            return Err("种群规模须在 2 到 64 之间".into());
        }
        if self.generations == 0 || self.generations > 50 {
            return Err("代数须在 1 到 50 之间".into());
        }
        if self.elitism >= self.population {
            return Err("精英个体数必须小于种群".into());
        }
        if !(0. ..=1.).contains(&self.mutation) || !(0. ..=1.).contains(&self.crossover) {
            return Err("变异率或交叉率无效".into());
        }
        if self.train.is_empty() || self.validation.is_empty() || self.seats.is_empty() {
            return Err("训练、验证与席位配置不能为空".into());
        }
        Ok(())
    }
}

/// The fictional 2x2 training arena: two columns per side, each with one
/// light cruiser and two destroyers. It uses only verified `data/stage0.json`
/// hull cards; it is a training fixture, not a historical scenario.
pub(crate) fn training_world(seed: u32) -> E<World> {
    let data = World::exercise_data()?;
    let mut world = World::blank(data, seed, 0, "coord", "", "coord", 0);
    world.field = Field::EXERCISE;
    struct Column {
        side: usize,
        fleet: u32,
        name: &'static str,
        x: f64,
        y: f64,
        heading: f64,
        ships: [&'static str; 3],
    }
    let columns = [
        Column {
            side: 0,
            fleet: 1,
            name: "训练第1分队",
            x: 7_000.,
            y: 5_200.,
            heading: 90.,
            ships: ["cleveland", "fletcher", "fletcher"],
        },
        Column {
            side: 0,
            fleet: 2,
            name: "训练第2分队",
            x: 7_000.,
            y: 8_800.,
            heading: 90.,
            ships: ["fletcher", "fletcher", "fletcher"],
        },
        Column {
            side: 1,
            fleet: 3,
            name: "训练第3分队",
            x: 17_000.,
            y: 5_200.,
            heading: 270.,
            ships: ["agano", "kagero", "kagero"],
        },
        Column {
            side: 1,
            fleet: 4,
            name: "训练第4分队",
            x: 17_000.,
            y: 8_800.,
            heading: 270.,
            ships: ["kagero", "kagero", "kagero"],
        },
    ];
    for column in columns {
        let direction = P::bearing(column.heading);
        let mut members = Vec::new();
        for (slot, class) in column.ships.iter().enumerate() {
            let def = data
                .ships
                .iter()
                .position(|ship| ship.id == *class)
                .ok_or_else(|| format!("训练场缺少已核验舰型 {class}"))?;
            let position = (P { x: column.x, y: column.y }
                - direction * (450. * slot as f64))
                .snap();
            let name = format!("{}{}", data.ships[def].name, slot + 1);
            let id = world.spawn(def, column.side, column.fleet, name, position, column.heading)?;
            members.push(id);
        }
        world.fleets.push(Fleet {
            id: column.fleet,
            side: column.side,
            name: column.name.into(),
            leader: members[0],
            members,
            mode: "follow".into(),
            speed: 24.,
            actual: 0.,
            turn_degrees: 0.,
            points: vec![],
            ai: Ai::new("coord", "auto"),
            notice: None,
            last_ai_route: 0,
            tactic: Tactic::Search,
        });
    }
    world.enable_realtime()?;
    world.add(
        3,
        "start",
        "AI 对抗训练场 · 虚构 2×2 编队（非历史想定）".into(),
        Some("RTS-AI-02"),
        None,
    );
    world.detect(true);
    world.radar_detect();
    Ok(world)
}

/// Three-fleet allied task group used by the role-split tests. The extra
/// destroyer column sits south of the two-column training arena, so the allied
/// side has a flagship (cruiser column), a screen (near destroyers) and a
/// torpedo group (far destroyers) to tell apart.
#[cfg(test)]
pub(crate) fn role_training_world(seed: u32) -> E<World> {
    let mut world = training_world(seed)?;
    let data = world.data;
    let mut members = Vec::new();
    for (slot, class) in ["fletcher", "fletcher", "fletcher"].iter().enumerate() {
        let def = data
            .ships
            .iter()
            .position(|ship| ship.id == *class)
            .ok_or_else(|| format!("训练场缺少已核验舰型 {class}"))?;
        let position = (P { x: 7_000., y: 11_500. } - P::bearing(90.) * (450. * slot as f64)).snap();
        let name = format!("{} 3-{}", data.ships[def].name, slot + 1);
        let id = world.spawn(def, 0, 5, name, position, 90.)?;
        members.push(id);
    }
    world.fleets.push(Fleet {
        id: 5,
        side: 0,
        name: "训练第3分队".into(),
        leader: members[0],
        members,
        mode: "follow".into(),
        speed: 24.,
        actual: 0.,
        turn_degrees: 0.,
        points: vec![],
        ai: Ai::new("coord", "auto"),
        notice: None,
        last_ai_route: 0,
        tactic: Tactic::Search,
    });
    world.detect(true);
    world.radar_detect();
    Ok(world)
}

pub(crate) fn seat_side(seat: usize) -> usize {
    if seat == 0 { 0 } else { 1 }
}

fn prepared_world(seed: u32, candidate: &str, opponent: &str, seat: usize) -> E<World> {
    let mut world = training_world(seed)?;
    let candidate_side = seat_side(seat);
    for fleet in &mut world.fleets {
        let profile = if fleet.side == candidate_side {
            candidate
        } else {
            opponent
        };
        fleet.ai = Ai::new(profile, "auto");
    }
    Ok(world)
}

/// Play one headless match: the candidate profile on `seat`, the opponent on
/// the other side, until the scenario decides or the time limit settles.
pub(crate) fn play(seed: u32, candidate: &str, opponent: &str, seat: usize) -> E<World> {
    Ok(play_traced(seed, candidate, opponent, seat)?.0)
}

/// Real, observed metrics used by the three new doctrines. Every field is
/// sampled from the same headless `World::advance` loop as the match itself;
/// nothing is inferred from the final score alone.
#[derive(Clone, Debug, Default, Serialize)]
pub struct MatchTrace {
    /// Damage actually dealt to the enemy while no candidate hull was farther
    /// than 3 km from the hit position (brawler).
    pub close_damage: f64,
    /// Damage actually dealt to the enemy while the nearest candidate hull was
    /// farther than 6 km (kiter).
    pub far_damage: f64,
    /// Seconds with at least one candidate hull inside 3 km of an enemy.
    pub close_ticks: u32,
    /// Candidate ship-seconds with at least one enemy inside acquisition range.
    pub contact_ship_ticks: u32,
    /// Candidate ship-seconds with the nearest enemy at 6 km or farther.
    pub range_keep_ship_ticks: u32,
    /// Torpedo-salvo × enemy pairs whose straight track covers the enemy's
    /// current course projection within the fan corridor.
    pub denial_coverage: u32,
    /// Distinct enemy hulls whose projected course was covered.
    pub denial_threats: u32,
    /// Observed enemy course change in the 90 s after a covered projection.
    pub denial_turn_degrees: f64,
    /// Mean angular width of the candidate torpedo fan while torpedoes are in
    /// flight (max pairwise heading separation).
    pub denial_fan_degrees: f64,
    /// Candidate torpedo launches observed in the match.
    pub torpedo_launches: u32,
}

const BRAWL_RANGE: f64 = 3_000.;
const KITER_RANGE: f64 = 6_000.;
/// Half-width of the torpedo fan corridor used to call a projected enemy
/// course "covered". A real torpedo body is far narrower; this deliberately
/// measures denial of the *route*, not a hit.
const DENIAL_FAN_RADIUS: f64 = 450.;
const DENIAL_THREAT_WINDOW: u32 = 90;

/// Closest approach between a straight-running torpedo and the enemy hull's
/// current course projection, in metres. `None` when the torpedo is already
/// past its run or has no speed.
fn torpedo_cpa(torpedo: &Torpedo, ship: &Ship) -> Option<f64> {
    let torpedo_speed = torpedo.speed * KNOT;
    if torpedo_speed <= 1e-9 || torpedo.remaining <= 0. {
        return None;
    }
    let relative = ship.p - torpedo.p;
    let velocity = P::bearing(ship.h) * (ship.speed * KNOT)
        - P::bearing(torpedo.h) * torpedo_speed;
    let speed_sq = velocity.dot(velocity);
    let flight = torpedo.remaining / torpedo_speed;
    let time = if speed_sq > 1e-9 {
        -relative.dot(velocity) / speed_sq
    } else {
        0.
    };
    // Only a future crossing covers the enemy's projected route. A torpedo
    // that has already passed the hull (or is opening the range) must not earn
    // "denial" credit merely because it is currently nearby.
    if time <= 0. || time > flight {
        return None;
    }
    Some((relative + velocity * time).len())
}

fn damage_amount(text: &str) -> f64 {
    text.split_whitespace()
        .rev()
        .nth(1)
        .and_then(|value| value.parse::<f64>().ok())
        .unwrap_or(0.)
}

fn play_traced(
    seed: u32,
    candidate: &str,
    opponent: &str,
    seat: usize,
) -> E<(World, MatchTrace)> {
    let mut world = prepared_world(seed, candidate, opponent, seat)?;
    let candidate_side = seat_side(seat);
    let opponent_side = 1 - candidate_side;
    let mut trace = MatchTrace::default();
    let mut seen_events = 0usize;
    let mut covered: BTreeSet<(u32, u32, u64, u32)> = BTreeSet::new();
    let mut threatened: BTreeSet<u32> = BTreeSet::new();
    // ship id -> (window end, accumulated degrees, active)
    let mut threat_state: BTreeMap<u32, (u32, f64, bool)> = BTreeMap::new();
    let mut previous_heading: BTreeMap<u32, f64> = BTreeMap::new();
    let mut fan_sum = 0.;
    let mut fan_ticks = 0u32;
    while world.result.is_none() && world.tick < LIMIT + 60 {
        world.advance();
        let tick = world.tick;
        for event in &world.events[seen_events..] {
            if event.kind != "damage" || event.mask != (1u8 << opponent_side) {
                continue;
            }
            let (Some(x), Some(y)) = (event.x, event.y) else { continue };
            let at = P { x, y };
            let nearest = world
                .ships
                .iter()
                .filter(|ship| ship.side == candidate_side && ship.alive())
                .map(|ship| ship.p.dist(at))
                .fold(f64::INFINITY, f64::min);
            let amount = damage_amount(&event.text);
            if nearest <= BRAWL_RANGE {
                trace.close_damage += amount;
            }
            if nearest > KITER_RANGE {
                trace.far_damage += amount;
            }
        }
        seen_events = world.events.len();
        // Observed course changes of enemy hulls that have a live torpedo
        // threat. The window is fixed at 90 s so the metric cannot be farmed
        // by one long turn late in the match.
        for ship in world
            .ships
            .iter()
            .filter(|ship| ship.side == opponent_side && ship.alive())
        {
            if let Some(previous) = previous_heading.insert(ship.id, ship.h) {
                if let Some((_, accumulated, active)) = threat_state.get_mut(&ship.id) {
                    if *active {
                        *accumulated += delta(previous, ship.h).abs();
                    }
                }
            }
        }
        for (until, accumulated, active) in threat_state.values_mut() {
            if *active && tick >= *until {
                trace.denial_turn_degrees += *accumulated;
                *accumulated = 0.;
                *active = false;
            }
        }
        // Close/keep-range clocks. `contact_ship_ticks` counts one tick per
        // candidate hull that has any live enemy within 25 km, so a kiter is
        // credited per hull-second rather than per fleet.
        let mut any_close = false;
        for ship in world
            .ships
            .iter()
            .filter(|ship| ship.side == candidate_side && ship.alive())
        {
            let nearest = world
                .ships
                .iter()
                .filter(|enemy| enemy.side == opponent_side && enemy.alive())
                .map(|enemy| ship.p.dist(enemy.p))
                .fold(f64::INFINITY, f64::min);
            if nearest <= 25_000. {
                trace.contact_ship_ticks += 1;
                if nearest >= KITER_RANGE {
                    trace.range_keep_ship_ticks += 1;
                }
                if nearest <= BRAWL_RANGE {
                    any_close = true;
                }
            }
        }
        if any_close {
            trace.close_ticks += 1;
        }
        // Denial: does any candidate torpedo's straight track cover the
        // enemy's current course projection? The pair key keeps one credit
        // per salvo/hull even though the geometry is re-checked every tick.
        for torpedo in world
            .torps
            .iter()
            .filter(|torpedo| torpedo.side == candidate_side)
        {
            for enemy in world
                .ships
                .iter()
                .filter(|enemy| enemy.side == opponent_side && enemy.alive())
            {
                let Some(miss) = torpedo_cpa(torpedo, enemy) else { continue };
                if miss > DENIAL_FAN_RADIUS {
                    continue;
                }
                let key = (torpedo.ship, torpedo.born, torpedo.h.to_bits(), enemy.id);
                if !covered.insert(key) {
                    continue;
                }
                trace.denial_coverage += 1;
                if threatened.insert(enemy.id) {
                    trace.denial_threats += 1;
                }
                let state = threat_state.entry(enemy.id).or_insert((0, 0., false));
                if !state.2 {
                    state.0 = tick + DENIAL_THREAT_WINDOW;
                    state.2 = true;
                }
            }
        }
        trace.torpedo_launches += world
            .torps
            .iter()
            .filter(|torpedo| torpedo.side == candidate_side && torpedo.born == tick)
            .count() as u32;
        let headings: Vec<f64> = world
            .torps
            .iter()
            .filter(|torpedo| torpedo.side == candidate_side)
            .map(|torpedo| torpedo.h)
            .collect();
        if headings.len() >= 2 {
            let mut span = 0f64;
            for (index, a) in headings.iter().enumerate() {
                for b in &headings[index + 1..] {
                    span = span.max(delta(*a, *b).abs());
                }
            }
            fan_sum += span;
            fan_ticks += 1;
        }
    }
    for (_, accumulated, active) in threat_state.values() {
        if *active {
            trace.denial_turn_degrees += *accumulated;
        }
    }
    if fan_ticks > 0 {
        trace.denial_fan_degrees = fan_sum / f64::from(fan_ticks);
    }
    Ok((world, trace))
}

/// Deterministic mirrored duel used by the AI behavior tests and by the
/// trainer's `duel` CLI mode. Candidate on the allied seat, builtin `coord` on
/// the axis seat.
pub(crate) fn duel(seed: u32, candidate: &str) -> E<World> {
    play(seed, candidate, "coord", 0)
}

#[derive(Clone, Debug, Serialize)]
pub struct MatchRecord {
    pub seed: u32,
    pub seat: usize,
    pub candidate_side: String,
    pub opponent: String,
    pub winner: Option<String>,
    pub tick: u32,
    pub candidate_sunk: u32,
    pub opponent_sunk: u32,
    pub candidate_damage: f64,
    pub opponent_damage: f64,
    pub candidate_cruiser_survival: f64,
    pub gun_events: u32,
    pub hit_events: u32,
    pub torpedo_events: u32,
    pub torpedo_hits: u32,
    pub friendly_fire: u32,
    pub score: f64,
    /// Doctrine metrics, only populated for the three new objectives. They are
    /// omitted when zero so the pre-batch three profile records stay identical.
    #[serde(skip_serializing_if = "is_zero_f64")]
    pub close_damage: f64,
    #[serde(skip_serializing_if = "is_zero_f64")]
    pub far_damage: f64,
    #[serde(skip_serializing_if = "is_zero_u32")]
    pub close_ticks: u32,
    #[serde(skip_serializing_if = "is_zero_f64")]
    pub range_keep_ratio: f64,
    #[serde(skip_serializing_if = "is_zero_u32")]
    pub denial_coverage: u32,
    #[serde(skip_serializing_if = "is_zero_u32")]
    pub denial_threats: u32,
    #[serde(skip_serializing_if = "is_zero_f64")]
    pub denial_turn_degrees: f64,
    #[serde(skip_serializing_if = "is_zero_f64")]
    pub denial_fan_degrees: f64,
    #[serde(skip_serializing_if = "is_zero_u32")]
    pub torpedo_launches: u32,
}

fn is_zero_f64(value: &f64) -> bool {
    value.abs() < 1e-9
}

fn is_zero_u32(value: &u32) -> bool {
    *value == 0
}

#[derive(Clone, Debug, Serialize)]
pub struct Summary {
    pub mean: f64,
    pub matches: usize,
    pub wins: u32,
    pub losses: u32,
    pub draws: u32,
    pub opponent_sunk: u32,
    pub own_sunk: u32,
    pub friendly_fire: u32,
}

impl Summary {
    fn of(records: &[MatchRecord]) -> Self {
        Self {
            mean: mean_score(records),
            matches: records.len(),
            wins: records.iter().filter(|r| r.score >= 100. || r.result_win()).count() as u32,
            losses: records.iter().filter(|r| r.result_loss()).count() as u32,
            draws: records.iter().filter(|r| !r.result_win() && !r.result_loss()).count() as u32,
            opponent_sunk: records.iter().map(|r| r.opponent_sunk).sum(),
            own_sunk: records.iter().map(|r| r.candidate_sunk).sum(),
            friendly_fire: records.iter().map(|r| r.friendly_fire).sum(),
        }
    }
}

impl MatchRecord {
    fn result_win(&self) -> bool {
        self.winner.as_deref() == Some(&self.candidate_side)
    }
    fn result_loss(&self) -> bool {
        matches!(&self.winner, Some(winner) if winner != "draw" && winner != &self.candidate_side)
    }
}

fn mean_score(records: &[MatchRecord]) -> f64 {
    if records.is_empty() {
        return 0.;
    }
    records.iter().map(|record| record.score).sum::<f64>() / records.len() as f64
}

fn side_damage(world: &World, side: usize) -> f64 {
    let mut total = 0.;
    let mut lost = 0.;
    for ship in world.ships.iter().filter(|ship| ship.side == side) {
        let dp = world.data.ships[ship.def].dp;
        total += dp;
        lost += (dp - ship.hp).max(0.);
    }
    if total > 0. { lost / total } else { 0. }
}

fn cruiser_survival(world: &World, side: usize) -> f64 {
    let cruisers: Vec<&Ship> = world
        .ships
        .iter()
        .filter(|ship| ship.side == side && world.data.ships[ship.def].dp >= 300.)
        .collect();
    if cruisers.is_empty() {
        return 1.;
    }
    cruisers.iter().filter(|ship| ship.alive()).count() as f64 / cruisers.len() as f64
}

fn score_match(
    world: &World,
    trace: &MatchTrace,
    case: &SeedCase,
    seat: usize,
    objective: Objective,
) -> MatchRecord {
    let candidate = seat_side(seat);
    let opponent = 1 - candidate;
    let winner = world.result.as_ref().map(|result| result.winner.clone());
    let win = match winner.as_deref() {
        Some(name) if name == side_name(candidate) => 1.,
        Some("draw") => 0.,
        Some(_) => -1.,
        None => 0.,
    };
    let candidate_sunk = world
        .ships
        .iter()
        .filter(|ship| ship.side == candidate && ship.hp <= 0.)
        .count() as u32;
    let opponent_sunk = world
        .ships
        .iter()
        .filter(|ship| ship.side == opponent && ship.hp <= 0.)
        .count() as u32;
    let own_damage = side_damage(world, candidate);
    let enemy_damage = side_damage(world, opponent);
    let mask = 1u8 << candidate;
    let count = |kind: &str| {
        world
            .events
            .iter()
            .filter(|event| event.mask & mask != 0 && event.kind == kind)
            .count() as u32
    };
    let friendly_fire = world
        .events
        .iter()
        .filter(|event| {
            event.mask & mask != 0 && event.kind == "torpedo_hit" && event.text.contains("友舰误中")
        })
        .count() as u32;
    let mut score = 120. * win + 25. * f64::from(opponent_sunk)
        - 15. * f64::from(candidate_sunk)
        + 70. * (enemy_damage - own_damage)
        - 30. * f64::from(friendly_fire);
    if world.result.is_none() {
        score -= 40.;
    }
    match objective {
        Objective::Screen => {
            score += 40. * cruiser_survival(world, candidate) + 20. * (1. - own_damage);
        }
        Objective::Torpedo => {
            score += 10. * f64::from(count("torpedo_hit"))
                + 3. * f64::from(count("torpedo"))
                + 30. * enemy_damage;
        }
        Objective::Gunnery => {
            score += 2.5 * f64::from(count("hit"))
                + 25. * enemy_damage
                + 20. * f64::from(opponent_sunk);
        }
        Objective::Brawler => {
            // Close-range damage is measured per hit against the firing fleet's
            // actual distance at impact; the engagement clock and kills add
            // pressure to finish fights instead of merely surviving them.
            score += 1.5 * trace.close_damage
                + 0.3 * f64::from(trace.close_ticks)
                + 50. * f64::from(opponent_sunk);
        }
        Objective::Kiter => {
            let keep = f64::from(trace.range_keep_ship_ticks)
                / f64::from(trace.contact_ship_ticks.max(1));
            score += 1.5 * trace.far_damage
                + 150. * keep
                + 60. * (1. - own_damage)
                + 40. * cruiser_survival(world, candidate);
        }
        Objective::Denial => {
            // Coverage of the enemy's projected route is the primary term;
            // hits are deliberately a minor add-on. The observed course change
            // is real enemy behaviour after a covered projection, not a
            // scripted reward.
            score += 30. * f64::from(trace.denial_coverage)
                + 10. * f64::from(trace.denial_threats)
                + 0.6 * trace.denial_turn_degrees
                + 0.5 * trace.denial_fan_degrees
                + 2. * f64::from(trace.torpedo_launches)
                + 8. * f64::from(count("torpedo_hit"));
        }
    }
    let new_doctrine = matches!(
        objective,
        Objective::Brawler | Objective::Kiter | Objective::Denial
    );
    let keep_ratio = f64::from(trace.range_keep_ship_ticks)
        / f64::from(trace.contact_ship_ticks.max(1));
    MatchRecord {
        seed: case.seed,
        seat,
        candidate_side: side_name(candidate).into(),
        opponent: case.opponent.clone(),
        winner,
        tick: world.tick,
        candidate_sunk,
        opponent_sunk,
        candidate_damage: own_damage,
        opponent_damage: enemy_damage,
        candidate_cruiser_survival: cruiser_survival(world, candidate),
        gun_events: count("gun"),
        hit_events: count("hit"),
        torpedo_events: count("torpedo"),
        torpedo_hits: count("torpedo_hit"),
        friendly_fire,
        score,
        close_damage: if new_doctrine { trace.close_damage } else { 0. },
        far_damage: if new_doctrine { trace.far_damage } else { 0. },
        close_ticks: if new_doctrine { trace.close_ticks } else { 0 },
        range_keep_ratio: if new_doctrine { keep_ratio } else { 0. },
        denial_coverage: if new_doctrine { trace.denial_coverage } else { 0 },
        denial_threats: if new_doctrine { trace.denial_threats } else { 0 },
        denial_turn_degrees: if new_doctrine { trace.denial_turn_degrees } else { 0. },
        denial_fan_degrees: if new_doctrine { trace.denial_fan_degrees } else { 0. },
        torpedo_launches: if new_doctrine { trace.torpedo_launches } else { 0 },
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct Evaluation {
    pub mean: f64,
    pub records: Vec<MatchRecord>,
}

fn evaluate_profile(
    profile: &str,
    cases: &[SeedCase],
    seats: &[usize],
    objective: Objective,
) -> E<Evaluation> {
    let mut records = Vec::new();
    for case in cases {
        for &seat in seats {
            let (world, trace) = play_traced(case.seed, profile, &case.opponent, seat)?;
            records.push(score_match(&world, &trace, case, seat, objective));
        }
    }
    let mean = mean_score(&records);
    Ok(Evaluation { mean, records })
}

#[derive(Clone, Debug, Serialize)]
pub struct Generation {
    pub generation: usize,
    pub best: f64,
    pub mean: f64,
    pub evaluated: usize,
    pub best_key: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct ProfileReport {
    pub id: String,
    pub name: String,
    pub description: String,
    pub role: String,
    /// `ga` when the numbers come from the genetic search; `hand_authored`
    /// when a fixed genome was only verified with headless matches.
    pub basis: String,
    pub params: Value,
    pub genome: Value,
    pub fitness: Value,
    pub seeds: Value,
    pub training: Value,
    /// Shop merge fields. This batch only publishes the manifest; the catalog
    /// and Harbor are intentionally untouched.
    pub unlock: String,
    pub cost: u32,
    pub currency: String,
    pub shop_state: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct TrainingLog {
    pub schema: String,
    pub generated_at: String,
    pub engine_version: String,
    pub arena: String,
    pub config: TrainConfig,
    pub runs: Vec<Value>,
    pub profiles: Vec<Value>,
    pub duration_millis: u128,
}

fn now_stamp() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("unix:{secs}")
}

/// Pareto-free tournament selection: best of three random genomes from the
/// sorted generation. Deterministic because the RNG stream is seeded.
fn tournament<'a>(scored: &'a [(f64, Genome)], rng: &mut Rng) -> &'a Genome {
    let mut best: Option<&(f64, Genome)> = None;
    for _ in 0..3 {
        let index = rng.below(scored.len());
        let candidate = &scored[index];
        if best.is_none_or(|current| candidate.0 > current.0) {
            best = Some(candidate);
        }
    }
    &best.expect("scored population").1
}

fn evolve_objective(
    objective: Objective,
    config: &TrainConfig,
    cache: &mut BTreeMap<String, Evaluation>,
) -> E<(Genome, Evaluation, Evaluation, Vec<Generation>)> {
    let mut rng = Rng::new(config.rng_seed ^ objective.seal_salt());
    let mut population: Vec<Genome> = vec![Genome::anchor(objective)];
    while population.len() < config.population {
        population.push(Genome::random_for(objective, &mut rng));
    }
    let mut history = Vec::new();
    let mut scored: Vec<(f64, Genome)> = Vec::new();
    for generation in 0..config.generations {
        scored.clear();
        for genome in &population {
            let key = genome.key();
            let evaluation = match cache.get(&key) {
                Some(found) => found.clone(),
                None => {
                    let found = evaluate_profile(&key, &config.train, &config.seats, objective)?;
                    cache.insert(key, found.clone());
                    found
                }
            };
            scored.push((evaluation.mean, genome.clone()));
        }
        scored.sort_by(|a, b| b.0.total_cmp(&a.0).then_with(|| a.1.key().cmp(&b.1.key())));
        let mean = scored.iter().map(|(score, _)| *score).sum::<f64>() / scored.len() as f64;
        history.push(Generation {
            generation,
            best: scored[0].0,
            mean,
            evaluated: cache.len(),
            best_key: scored[0].1.key(),
        });
        if generation + 1 == config.generations {
            break;
        }
        let mut next: Vec<Genome> = scored
            .iter()
            .take(config.elitism)
            .map(|(_, genome)| genome.clone())
            .collect();
        while next.len() < config.population {
            let a = tournament(&scored, &mut rng).clone();
            let b = tournament(&scored, &mut rng).clone();
            let mut child = if rng.unit() < config.crossover {
                Genome::crossover(&a, &b, &mut rng)
            } else {
                a
            };
            child.mutate(&mut rng, config.mutation, objective);
            next.push(child);
        }
        population = next;
    }
    let (best_score, best) = scored
        .first()
        .cloned()
        .ok_or("训练未产生个体")?;
    let training = cache
        .get(&best.key())
        .cloned()
        .unwrap_or(Evaluation { mean: best_score, records: vec![] });
    let validation = evaluate_profile(
        &best.key(),
        &config.validation,
        &config.seats,
        objective,
    )?;
    Ok((best, training, validation, history))
}

fn profile_report(
    objective: Objective,
    genome: &Genome,
    training: &Evaluation,
    validation: &Evaluation,
    baseline: &Evaluation,
    config: &TrainConfig,
    history: &[Generation],
) -> E<ProfileReport> {
    let style = genome.to_style();
    let params = serde_json::to_value(&style).map_err(|error| format!("参数序列化失败：{error}"))?;
    // One flat, non-empty list of the seeds this profile was scored on. The
    // split is kept in `training.train` / `training.validation`; the profile
    // keeps the flat list so shop listings and audits can show every seed.
    let mut seed_list = Vec::new();
    for case in &config.train {
        seed_list.push(json!({"split": "training", "seed": case.seed, "opponent": case.opponent}));
    }
    for case in &config.validation {
        seed_list.push(json!({"split": "validation", "seed": case.seed, "opponent": case.opponent}));
    }
    let seeds = json!(seed_list);
    let training_config = json!({
        "schema": TRAINING_SCHEMA,
        "arena": config.arena,
        "population": config.population,
        "generations": config.generations,
        "elitism": config.elitism,
        "mutation": config.mutation,
        "crossover": config.crossover,
        "rng_seed": config.rng_seed,
        "objective": objective.role(),
        "train": config.train,
        "validation": config.validation,
        "seats": config.seats,
        "time_limit_seconds": config.time_limit_seconds,
        "match_limit": config.match_limit,
        "basis": objective.basis(),
        "fitness": fitness_definition(objective),
    });
    Ok(ProfileReport {
        id: objective.id().into(),
        name: objective.name().into(),
        description: objective.description().into(),
        role: objective.role().into(),
        basis: objective.basis().into(),
        params,
        genome: serde_json::to_value(genome).map_err(|error| error.to_string())?,
        fitness: json!({
            "objective": objective.role(),
            "basis": objective.basis(),
            "definition": fitness_definition(objective),
            "training": Summary::of(&training.records),
            "validation": Summary::of(&validation.records),
            "builtin_baseline": {
                "profile": objective.baseline(),
                "validation": Summary::of(&baseline.records),
            },
            "validation_matches": validation.records,
            "training_matches": training.records,
        }),
        seeds,
        training: {
            let mut value = training_config;
            value["history"] = json!(history);
            value
        },
        unlock: objective.unlock().into(),
        cost: objective.cost(),
        currency: "recruit_ticket".into(),
        shop_state: "provisional".into(),
    })
}

fn fitness_definition(objective: Objective) -> &'static str {
    match objective {
        Objective::Screen => {
            "120*win + 25*敌沉 - 15*己沉 + 70*(敌损伤率-己损伤率) - 30*友军误击 + 40*己方巡洋存活率 + 20*(1-己损伤率)"
        }
        Objective::Torpedo => {
            "120*win + 25*敌沉 - 15*己沉 + 70*(敌损伤率-己损伤率) - 30*友军误击 + 10*鱼雷命中 + 3*鱼雷发射 + 30*敌损伤率"
        }
        Objective::Gunnery => {
            "120*win + 25*敌沉 - 15*己沉 + 70*(敌损伤率-己损伤率) - 30*友军误击 + 2.5*炮击命中 + 25*敌损伤率 + 20*敌沉"
        }
        Objective::Brawler => {
            "120*win + 25*敌沉 - 15*己沉 + 70*(敌损伤率-己损伤率) - 30*友军误击 + 1.5*3km内实伤 + 0.3*3km内接敌秒 + 50*敌沉"
        }
        Objective::Kiter => {
            "120*win + 25*敌沉 - 15*己沉 + 70*(敌损伤率-己损伤率) - 30*友军误击 + 1.5*6km外实伤 + 150*射程维持率 + 60*(1-己损伤率) + 40*巡洋存活率"
        }
        Objective::Denial => {
            "120*win + 25*敌沉 - 15*己沉 + 70*(敌损伤率-己损伤率) - 30*友军误击 + 30*扇面覆盖预定航路 + 10*被覆盖敌舰 + 0.6*威胁后90秒转向度 + 0.5*扇面宽度 + 2*鱼雷发射 + 8*鱼雷命中"
        }
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct TrainingReport {
    pub config: TrainConfig,
    pub profiles: Vec<ProfileReport>,
    pub log: TrainingLog,
}

impl TrainingReport {
    pub fn evolved_json(&self) -> Value {
        let shop: Vec<Value> = self
            .profiles
            .iter()
            .map(|profile| {
                json!({
                    "id": profile.id,
                    "name": profile.name,
                    "description": profile.description,
                    "unlock": profile.unlock,
                    "cost": profile.cost,
                    "currency": profile.currency,
                    "state": profile.shop_state,
                })
            })
            .collect();
        json!({
            "schema": PROFILE_SCHEMA,
            "generatedBy": "src/bin/ai-trainer.rs",
            "engineVersion": VERSION,
            "arena": ARENA,
            "arenaNote": "虚构训练场，仅使用 data/stage0.json 已核验舰卡，不是历史想定",
            "profiles": self.profiles,
            "shop": {
                "schema": "cas-ai-shop-merge-v1",
                "source": "data/ai/evolved.json",
                "state": "provisional",
                "note": "六条 doctrine 已接入 server/catalog 与 client/src/ai-shop.ts；常驻征募券价格仍为 provisional。",
                "profiles": shop,
            },
        })
    }
}

/// Run the full six-objective training and return the report. This never
/// fabricates a fitness: every reported number comes from `play_traced()`
/// above, on the same headless Rust core the game runs.
pub fn train(config: TrainConfig) -> E<TrainingReport> {
    config.validate()?;
    let started = std::time::Instant::now();
    let mut cache: BTreeMap<String, Evaluation> = BTreeMap::new();
    let mut profiles = Vec::new();
    let mut runs = Vec::new();
    for objective in Objective::all() {
        let (genome, training, validation, history) = evolve_objective(objective, &config, &mut cache)?;
        let baseline = evaluate_profile(
            objective.baseline(),
            &config.validation,
            &config.seats,
            objective,
        )?;
        runs.push(json!({
            "objective": objective.role(),
            "anchor": Genome::anchor(objective),
            "history": history,
            "training": Summary::of(&training.records),
            "validation": Summary::of(&validation.records),
            "builtin_baseline": { "profile": objective.baseline(), "validation": Summary::of(&baseline.records) },
            "training_matches": training.records,
            "validation_matches": validation.records,
        }));
        let style = genome.to_style();
        if !style.sane() || !style.evolved {
            return Err(format!("{} 产出无效参数", objective.id()));
        }
        profiles.push(profile_report(
            objective,
            &genome,
            &training,
            &validation,
            &baseline,
            &config,
            &history,
        )?);
    }
    let log = TrainingLog {
        schema: "cas-ai-training-log-v1".into(),
        generated_at: now_stamp(),
        engine_version: VERSION.into(),
        arena: ARENA.into(),
        config: config.clone(),
        runs,
        profiles: profiles
            .iter()
            .map(|profile| json!({"id": profile.id, "fitness": profile.fitness, "params": profile.params}))
            .collect(),
        duration_millis: started.elapsed().as_millis(),
    };
    Ok(TrainingReport {
        config,
        profiles,
        log,
    })
}

fn write_json(path: &PathBuf, value: &Value) -> E<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|error| format!("无法创建目录 {}：{error}", parent.display()))?;
    }
    let mut text = serde_json::to_string_pretty(value).map_err(|error| error.to_string())?;
    text.push('\n');
    std::fs::write(path, text).map_err(|error| format!("无法写入 {}：{error}", path.display()))
}

fn parse_args(args: &[String]) -> E<Parsed> {
    let mut action = Mode::Evolve;
    let mut config = TrainConfig::default();
    let mut out = PathBuf::from("data/ai/evolved.json");
    let mut log_path = PathBuf::from("data/ai/training-log.json");
    let mut duel = None;
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "evolve" => action = Mode::Evolve,
            "duel" => {
                action = Mode::Duel;
                let profile = args.get(index + 1).ok_or("duel 需要 AI 档案 id")?.clone();
                let seed = args
                    .get(index + 2)
                    .and_then(|value| value.parse::<u32>().ok())
                    .unwrap_or(6111);
                duel = Some((profile, seed));
                index += 2;
            }
            "--population" => {
                index += 1;
                config.population = args
                    .get(index)
                    .and_then(|value| value.parse::<usize>().ok())
                    .ok_or("--population 需要整数")?;
            }
            "--generations" => {
                index += 1;
                config.generations = args
                    .get(index)
                    .and_then(|value| value.parse::<usize>().ok())
                    .ok_or("--generations 需要整数")?;
            }
            "--out" => {
                index += 1;
                out = PathBuf::from(args.get(index).ok_or("--out 需要路径")?);
            }
            "--log" => {
                index += 1;
                log_path = PathBuf::from(args.get(index).ok_or("--log 需要路径")?);
            }
            "--seed" => {
                index += 1;
                config.rng_seed = args
                    .get(index)
                    .and_then(|value| value.parse::<u64>().ok())
                    .ok_or("--seed 需要整数")?;
            }
            "--quiet" => {}
            other => return Err(format!("未知参数：{other}")),
        }
        index += 1;
    }
    Ok(Parsed::Run {
        action,
        config,
        out,
        log_path,
        duel,
    })
}

enum Mode {
    Evolve,
    Duel,
}

enum Parsed {
    Run {
        action: Mode,
        config: TrainConfig,
        out: PathBuf,
        log_path: PathBuf,
        duel: Option<(String, u32)>,
    },
}

/// Entry point used by `src/bin/ai-trainer.rs`.
pub fn run_cli() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Parsed::Run {
        action,
        config,
        out,
        log_path,
        duel,
    } = parse_args(&args)?;
    match action {
        Mode::Duel => {
            let (profile, seed) = duel.ok_or("duel 参数缺失")?;
            let world = duel_match(seed, &profile)?;
            let report = duel_report(&world, seed, &profile);
            println!(
                "{}",
                serde_json::to_string_pretty(&report).map_err(|error| error.to_string())?
            );
        }
        Mode::Evolve => {
            let report = train(config)?;
            let evolved = report.evolved_json();
            write_json(&out, &evolved)?;
            write_json(
                &log_path,
                &serde_json::to_value(&report.log).map_err(|error| error.to_string())?,
            )?;
            for profile in &report.profiles {
                println!(
                    "{}  {:<12} 训练 {:.2}  验证 {:.2}  内置 {} {:.2}",
                    profile.id,
                    profile.name,
                    profile.fitness["training"]["mean"].as_f64().unwrap_or(0.),
                    profile.fitness["validation"]["mean"].as_f64().unwrap_or(0.),
                    profile.fitness["builtin_baseline"]["profile"].as_str().unwrap_or(""),
                    profile.fitness["builtin_baseline"]["validation"]["mean"]
                        .as_f64()
                        .unwrap_or(0.),
                );
            }
            println!("已写入 {}", out.display());
            println!("训练日志 {}", log_path.display());
        }
    }
    Ok(())
}

fn duel_match(seed: u32, profile: &str) -> E<World> {
    let mut world = training_world(seed)?;
    let candidate = ai::style(profile);
    let key = if candidate.evolved {
        profile.to_string()
    } else {
        profile.to_string()
    };
    for fleet in &mut world.fleets {
        let chosen = if fleet.side == 0 { key.clone() } else { "coord".to_string() };
        fleet.ai = Ai::new(&chosen, "auto");
    }
    while world.result.is_none() && world.tick < LIMIT + 60 {
        world.advance();
    }
    Ok(world)
}

/// Public match report for the CLI/evidence path.
fn duel_report(world: &World, seed: u32, profile: &str) -> Value {
    let sunk = |side: usize| {
        world
            .ships
            .iter()
            .filter(|ship| ship.side == side && ship.hp <= 0.)
            .count()
    };
    let events = |kind: &str| {
        world
            .events
            .iter()
            .filter(|event| event.kind == kind)
            .count()
    };
    json!({
        "schema": "cas-ai-duel-v1",
        "seed": seed,
        "profile": profile,
        "arena": ARENA,
        "engineVersion": VERSION,
        "result": world.result,
        "tick": world.tick,
        "ships": world.ships.len(),
        "sunk": { "allies": sunk(0), "axis": sunk(1) },
        "events": {
            "gun": events("gun"),
            "hit": events("hit"),
            "torpedo": events("torpedo"),
            "torpedo_hit": events("torpedo_hit"),
            "sunk": events("sunk"),
        },
        "damage": { "allies": side_damage(world, 0), "axis": side_damage(world, 1) },
        "aiStates": world.fleets.iter().map(|fleet| json!({
            "fleet": fleet.id, "side": side_name(fleet.side), "name": fleet.name,
            "profile": fleet.ai.profile, "tactic": fleet.tactic.label(),
        })).collect::<Vec<_>>(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn training_world_builds_two_columns_per_side() {
        let world = training_world(6106).unwrap();
        assert_eq!(world.fleets.len(), 4);
        assert_eq!(world.ships.len(), 12);
        assert!(world.contacts[0].len() >= 2, "both sides must open in contact");
        assert!(world.contacts[1].len() >= 1);
        assert!(world.v10_family(), "training uses the realtime v10 family");
        assert!(world.result.is_none());
    }

    #[test]
    fn genome_round_trips_through_a_profile_key() {
        let genome = Genome::anchor(Objective::Torpedo);
        let key = genome.key();
        let parsed = Style::parse(&key).expect("genome key parses");
        assert_eq!(parsed, genome.to_style());
        assert!(parsed.evolved);
        assert!(parsed.sane());
    }

    #[test]
    fn mutation_stays_inside_the_declared_bounds() {
        let mut rng = Rng::new(7);
        for _ in 0..200 {
            let mut genome = Genome::random(&mut rng);
            genome.mutate(&mut rng, 1., Objective::Brawler);
            assert!((RANGE_BOUNDS.0..=RANGE_BOUNDS.1).contains(&genome.range));
            assert!((WITHDRAW_BOUNDS.0..=WITHDRAW_BOUNDS.1).contains(&genome.withdraw_hp));
            assert!((FLANK_BOUNDS.0..=FLANK_BOUNDS.1).contains(&genome.flank));
            assert!((SPEED_BOUNDS.0..=SPEED_BOUNDS.1).contains(&genome.speed));
            assert!((TORP_FRACTION_BOUNDS.0..=TORP_FRACTION_BOUNDS.1).contains(&genome.torp_fraction));
            assert!((PERIOD_BOUNDS.0..=PERIOD_BOUNDS.1).contains(&genome.period));
            assert!((COORDINATION_BOUNDS.0..=COORDINATION_BOUNDS.1).contains(&genome.coordination));
            assert!((CROSSFIRE_BOUNDS.0..=CROSSFIRE_BOUNDS.1).contains(&genome.crossfire));
            assert!((T_HEAD_BOUNDS.0..=T_HEAD_BOUNDS.1).contains(&genome.t_head));
            assert!((SCREEN_BOUNDS.0..=SCREEN_BOUNDS.1).contains(&genome.screen));
            assert!((SPREAD_BOUNDS.0..=SPREAD_BOUNDS.1).contains(&genome.spread));
            assert!((TORP_ANGLE_BOUNDS.0..=TORP_ANGLE_BOUNDS.1).contains(&genome.torp_angle));
            assert!((FRIENDLY_MARGIN_BOUNDS.0..=FRIENDLY_MARGIN_BOUNDS.1).contains(&genome.friendly_margin));
            assert!(genome.to_style().sane());
        }
    }

    #[test]
    fn one_evolved_match_produces_real_combat_metrics() {
        let world = play(6106, &Genome::anchor(Objective::Gunnery).key(), "coord", 0).unwrap();
        let record = score_match(
            &world,
            &MatchTrace::default(),
            &SeedCase { seed: 6106, opponent: "coord".into() },
            0,
            Objective::Gunnery,
        );
        assert!(record.gun_events > 0);
        assert!(record.tick > 0);
        assert!(record.score.is_finite());
        assert!(record.opponent_damage >= 0.);
    }

    #[test]
    fn a_small_training_run_writes_six_distinct_profiles() {
        let mut config = TrainConfig::default();
        config.population = 3;
        config.generations = 1;
        config.elitism = 1;
        config.train = vec![SeedCase { seed: 6106, opponent: "coord".into() }];
        config.validation = vec![SeedCase { seed: 6112, opponent: "coord".into() }];
        let report = train(config).unwrap();
        assert_eq!(report.profiles.len(), 6);
        for profile in &report.profiles {
            assert!(profile.fitness["validation"]["mean"].as_f64().is_some());
            assert!(profile.training["schema"] == json!(TRAINING_SCHEMA));
            assert_eq!(profile.basis, "ga");
        }
        let ids: Vec<&str> = report.profiles.iter().map(|p| p.id.as_str()).collect();
        assert_eq!(
            ids,
            [
                "evo-screen",
                "evo-torpedo",
                "evo-gunnery",
                "evo-brawler",
                "evo-kiter",
                "evo-denial"
            ]
        );
    }

    #[test]
    fn new_doctrine_anchors_express_their_range_and_torpedo_roles() {
        let brawler = Genome::anchor(Objective::Brawler);
        assert!(brawler.range <= 2_800., "{}", brawler.range);
        assert!(brawler.withdraw_hp <= 0.12, "{}", brawler.withdraw_hp);
        assert!(brawler.torp_fraction >= 0.9);
        let kiter = Genome::anchor(Objective::Kiter);
        assert!(kiter.range >= 7_800., "{}", kiter.range);
        assert!(kiter.withdraw_hp >= 0.34, "{}", kiter.withdraw_hp);
        assert!(kiter.speed >= 30.);
        let denial = Genome::anchor(Objective::Denial);
        assert!(denial.torp_fraction >= 0.95);
        assert!(denial.torp_angle >= 140.);
        assert!(denial.coordination >= 0.9);
        assert!(denial.screen >= 0.8);
        assert!(denial.spread >= 0.8);
        for objective in [Objective::Brawler, Objective::Kiter, Objective::Denial] {
            assert!(Genome::anchor(objective).to_style().sane());
            assert_eq!(objective.basis(), "ga");
        }
    }

    #[test]
    fn new_doctrine_headless_matches_measure_real_doctrine_metrics() {
        for (objective, seed) in [
            (Objective::Brawler, 6106u32),
            (Objective::Kiter, 6107u32),
            (Objective::Denial, 6112u32),
        ] {
            let genome = Genome::anchor(objective);
            let (world, trace) =
                play_traced(seed, &genome.key(), objective.baseline(), 0).unwrap();
            assert!(trace.contact_ship_ticks > 0, "{objective:?} never made contact");
            if objective != Objective::Kiter {
                // A kiter can legitimately hold outside torpedo range and
                // fight with guns only; brawler and denial must launch.
                assert!(trace.torpedo_launches > 0, "{objective:?} never launched a torpedo");
            }
            let record = score_match(
                &world,
                &trace,
                &SeedCase { seed, opponent: objective.baseline().into() },
                0,
                objective,
            );
            assert!(record.score.is_finite());
            match objective {
                Objective::Brawler => {
                    assert!(trace.close_ticks > 0, "brawler never closed to 3 km");
                    assert!(trace.close_damage > 0., "brawler dealt no damage inside 3 km");
                }
                Objective::Kiter => {
                    assert!(trace.range_keep_ship_ticks > 0, "kiter never kept 6 km");
                }
                Objective::Denial => {
                    assert!(trace.denial_coverage > 0, "denial never covered a projected route");
                    assert!(trace.denial_threats > 0);
                    assert!(
                        trace.denial_coverage > record.torpedo_hits,
                        "coverage must measure route denial, not just torpedo hits ({} vs {})",
                        trace.denial_coverage,
                        record.torpedo_hits
                    );
                    assert!(trace.denial_turn_degrees > 0., "no observed threat turn");
                }
                _ => unreachable!(),
            }
        }
    }
}
