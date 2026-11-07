use serde::{Deserialize, Serialize};
use std::ops::{Add, Mul, Sub};

pub const LIMIT: u32 = 2700;
pub const CYCLE: u32 = 180;
pub const WIDTH: f64 = 24_000.;
pub const HEIGHT: f64 = 14_000.;
pub const KNOT: f64 = 1852. / 3600.;
pub const YARD: f64 = 0.9144;
pub const LEGACY_VERSION: &str = "cas-stage0-v1";
pub const VERSION: &str = "cas-battle-v2";
pub const SHELL_FLIGHT: u32 = 8;
pub const SCENARIO: &str = "白昼接敌 · 5 对 5 演习";
pub type E<T> = Result<T, String>;

#[derive(Clone, Copy)]
pub(crate) struct Field {
    pub width: f64,
    pub height: f64,
    pub limit: u32,
}
impl Field {
    pub const EXERCISE: Self = Self { width: WIDTH, height: HEIGHT, limit: LIMIT };

    pub fn contains(self, p: P) -> bool {
        (50. ..=self.width - 50.).contains(&p.x)
            && (50. ..=self.height - 50.).contains(&p.y)
    }
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, PartialEq)]
pub struct P {
    pub x: f64,
    pub y: f64,
}
impl Add for P {
    type Output = Self;
    fn add(self, r: Self) -> Self {
        Self {
            x: self.x + r.x,
            y: self.y + r.y,
        }
    }
}
impl Sub for P {
    type Output = Self;
    fn sub(self, r: Self) -> Self {
        Self {
            x: self.x - r.x,
            y: self.y - r.y,
        }
    }
}
impl Mul<f64> for P {
    type Output = Self;
    fn mul(self, k: f64) -> Self {
        Self {
            x: self.x * k,
            y: self.y * k,
        }
    }
}
impl P {
    pub fn dot(self, r: Self) -> f64 {
        self.x * r.x + self.y * r.y
    }
    pub fn cross(self, r: Self) -> f64 {
        self.x * r.y - self.y * r.x
    }
    pub fn len(self) -> f64 {
        libm::sqrt(self.dot(self))
    }
    pub fn dist(self, r: Self) -> f64 {
        (self - r).len()
    }
    pub fn unit(self) -> Self {
        let d = self.len();
        if d > 0. {
            self * (1. / d)
        } else {
            self
        }
    }
    pub fn heading(self) -> f64 {
        norm(libm::atan2(self.x, self.y).to_degrees())
    }
    pub fn bearing(h: f64) -> Self {
        let h = h.to_radians();
        Self {
            x: libm::sin(h),
            y: libm::cos(h),
        }
    }
    pub fn snap(self) -> Self {
        Self {
            x: libm::round(self.x * 1e6) / 1e6,
            y: libm::round(self.y * 1e6) / 1e6,
        }
    }
}
pub fn norm(h: f64) -> f64 {
    let h = h % 360.;
    if h < 0. {
        h + 360.
    } else {
        h
    }
}
pub fn delta(a: f64, b: f64) -> f64 {
    norm(b - a + 180.) - 180.
}
pub fn circle(heading: f64, arc: [f64; 2]) -> bool {
    if arc[1] - arc[0] >= 360. {
        return true;
    }
    norm(heading - arc[0]) <= norm(arc[1] - arc[0]) + 1e-7
}
pub fn side(s: &str) -> E<usize> {
    match s {
        "allies" => Ok(0),
        "axis" => Ok(1),
        _ => Err("未知阵营".into()),
    }
}
pub fn side_name(s: usize) -> &'static str {
    if s == 0 {
        "allies"
    } else {
        "axis"
    }
}

#[derive(Clone, Debug, Deserialize)]
pub struct Data {
    pub ships: Vec<ShipDef>,
    #[serde(default)]
    pub rules: serde_json::Value,
}
#[derive(Clone, Debug, Deserialize)]
pub struct ShipDef {
    pub id: String,
    pub name: String,
    pub side: String,
    pub kind: String,
    pub size: String,
    pub max_knots: f64,
    pub dp: f64,
    #[serde(default)]
    pub damage_speed: Vec<DamageSpeed>,
    #[serde(default)]
    pub engineering_speed_multiplier: Option<u8>,
    pub turn_advance_yards: f64,
    pub speed_loss_knots: f64,
    pub accel_knots_per_turn: f64,
    pub gun: GunDef,
    /// cas-realtime-v10 (CAS 6.1.5): secondary battery used against surface
    /// targets. It fires on its own reload cycle at the main battery's target.
    #[serde(default)]
    pub secondary: Option<GunDef>,
    pub torpedo: Option<TorpedoDef>,
    #[serde(default)]
    pub length_m: f64,
    pub armor_belt: f64,
    pub armor_deck: f64,
    #[serde(default)]
    pub torpedo_protection_dp: f64,
    pub in_service_year: u32,
    pub accel_high_knots_per_turn: f64,
    pub brake_knots_per_turn: f64,
}
#[derive(Clone, Debug, Deserialize)]
pub struct DamageSpeed {
    pub damage: f64,
    pub knots: f64,
}
#[derive(Clone, Debug, Deserialize)]
pub struct GunDef {
    pub name: String,
    #[serde(default)]
    pub caliber_mm: f64,
    pub range_yd: Vec<f64>,
    pub damage: Vec<f64>,
    pub barrels: u32,
    pub gs: u32,
    #[serde(default)]
    pub mounts: Vec<GunMount>,
    pub pen_belt: Vec<Option<f64>>,
    pub pen_deck: Vec<Option<f64>>,
    pub armor_piercing: bool,
    /// cas-realtime-v10: the forward main-battery director's relative arc.
    /// Aft mounts outside it fall to local control.
    #[serde(default)]
    pub director_arc: Option<[f64; 2]>,
    /// Seconds between secondary salvos (CAS 6.1.5 rate).
    #[serde(default)]
    pub reload_seconds: Option<u32>,
}
#[derive(Clone, Debug, Deserialize)]
pub struct GunMount {
    pub barrels: u32,
    pub arc: [f64; 2],
    pub arc2: Option<[f64; 2]>,
}
#[derive(Clone, Debug, Deserialize)]
pub struct TorpedoDef {
    pub name: String,
    pub speed_knots: f64,
    pub range_yd: f64,
    pub warhead: f64,
    pub tubes: u32,
    pub contact_fuze: bool,
    #[serde(default)]
    pub mounts: Vec<TorpedoMount>,
    /// cas-realtime-v10: seconds to refill a mount from its reserve.
    #[serde(default)]
    pub reload_seconds: Option<u32>,
}
#[derive(Clone, Debug, Deserialize)]
pub struct TorpedoMount {
    pub tubes: u32,
    pub arc: [f64; 2],
    pub arc2: Option<[f64; 2]>,
    /// Reload torpedoes stowed for this mount (CAS 6.3).
    #[serde(default)]
    pub reserve: u32,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Track {
    pub nodes: Vec<P>,
    pub len: Vec<f64>,
    pub pos: f64,
    pub end: f64,
}
impl Track {
    pub fn new(nodes: Vec<P>, pos: f64, end: f64) -> Self {
        let mut len = vec![0.];
        for w in nodes.windows(2) {
            len.push(len[len.len() - 1] + w[0].dist(w[1]));
        }
        Self {
            nodes,
            len,
            pos,
            end,
        }
    }
    pub fn at(&self, m: f64) -> (P, f64) {
        let m = m.clamp(0., *self.len.last().unwrap_or(&0.));
        if self.nodes.len() < 2 {
            return (self.nodes.first().copied().unwrap_or_default(), 0.);
        }
        let i = self
            .len
            .partition_point(|v| *v <= m)
            .saturating_sub(1)
            .min(self.nodes.len() - 2);
        let d = self.len[i + 1] - self.len[i];
        let v = self.nodes[i + 1] - self.nodes[i];
        let p = if d > 0. {
            self.nodes[i] + v * ((m - self.len[i]) / d)
        } else {
            self.nodes[i]
        };
        (p.snap(), v.heading())
    }
    pub fn remaining(&self) -> Vec<P> {
        if self.nodes.is_empty() {
            return Vec::new();
        }
        let mut p = vec![self.at(self.pos).0];
        for (i, l) in self.len.iter().enumerate() {
            if *l > self.pos && *l < self.end {
                p.push(self.nodes[i]);
            }
        }
        if self.end > self.pos {
            p.push(self.at(self.end).0);
        }
        p
    }
    pub fn to(&self, m: f64) -> P {
        self.at(m.min(self.end)).0
    }
    pub fn done(&self) -> bool {
        self.pos + 1e-6 >= self.end
    }
}

#[derive(Clone, Debug)]
pub struct Casualty {
    pub next_damage: u32,
    pub next_control: u32,
    pub amount: f64,
}

/// cas-realtime-v10: one smoke-screen puff laid by a destroyer (5.4.5).
#[derive(Clone, Debug)]
pub struct SmokeCloud {
    pub p: P,
    pub born: u32,
    pub expires: u32,
}

#[derive(Clone, Debug)]
pub struct Ship {
    pub escaped: bool,
    pub id: u32,
    pub def: usize,
    pub side: usize,
    pub fleet: Option<u32>,
    pub name: String,
    pub p: P,
    pub h: f64,
    pub speed: f64,
    pub hp: f64,
    pub ammo: u32,
    pub gun_cycle: Option<u32>,
    pub illumination_cycle: Option<u32>,
    pub torp_cycle: Option<u32>,
    pub torp_mount_remaining: Vec<u32>,
    pub torpedo_protection: [f64; 2],
    pub track: Option<Track>,
    pub free_speed: f64,
    pub fires: Vec<Casualty>,
    pub flooding: Vec<Casualty>,
    pub fire_control_damage: bool,
    pub gun_mount_destroyed: Vec<bool>,
    pub gun_mount_bearings: Vec<Option<f64>>,
    pub gun_bearing_until: u32,
    pub(crate) battery: crate::realtime::Battery,
    pub engineering_speed_levels: usize,
    pub jammed_until: u32,
    /// cas-realtime-v10: searchlight lit on this target ship while Some
    /// (5.4.4.1: the light itself is visible at five times its range).
    pub searchlight: Option<u32>,
    pub searchlight_die: u32,
    pub searchlight_since: u32,
    /// cas-realtime-v10: the ship is trailing a smoke screen (5.4.5).
    pub smoking: bool,
    /// cas-realtime-v10 (CAS 8.3, Form 10): a jammed rudder circles the ship
    /// at its current speed. +1 = starboard, -1 = port; None = steerable.
    pub rudder_jam: Option<f64>,
    /// A bridge critical circles the ship (or holds course on the "maintains
    /// current movement" result). Same sign convention as `rudder_jam`.
    pub bridge_circle: Option<f64>,
    /// Torpedo mounts lost to a weapon critical (CAS 8.3).
    pub torp_mount_destroyed: Vec<bool>,
    /// cas-realtime-v10: reserve torpedoes per mount and the tick each mount
    /// finishes its next reload (0 = no reload running).
    pub torp_reserve: Vec<u32>,
    pub torp_reload_at: Vec<u32>,
    /// Tick when the secondary battery can fire its next salvo.
    pub secondary_ready: u32,
    /// Scenario-imposed speed ceiling (e.g. Haguro after the 0130 bombing).
    pub speed_cap: Option<f64>,
}
impl Ship {
    pub fn alive(&self) -> bool {
        self.hp > 0. && !self.escaped
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct Ai {
    pub profile: String,
    pub mode: String,
    pub r#move: bool,
    pub gun: bool,
    pub torpedo: bool,
}
impl Ai {
    pub fn new(profile: &str, mode: &str) -> Self {
        Self {
            profile: profile.into(),
            mode: mode.into(),
            r#move: mode == "auto",
            gun: mode == "auto",
            torpedo: mode == "auto",
        }
    }
    pub fn validate(&self) -> E<()> {
        if !matches!(self.profile.as_str(), "coord" | "gunnery" | "torpedo") {
            return Err("未知 AI 风格".into());
        }
        if !matches!(self.mode.as_str(), "manual" | "suggest" | "auto") {
            return Err("未知 AI 指挥模式".into());
        }
        Ok(())
    }
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Tactic {
    Search,
    Approach,
    Engage,
    Withdraw,
}
impl Tactic {
    pub fn label(self) -> &'static str {
        match self {
            Self::Search => "搜索",
            Self::Approach => "接敌",
            Self::Engage => "交战",
            Self::Withdraw => "保存兵力",
        }
    }
}

#[derive(Clone, Debug)]
pub struct Fleet {
    pub id: u32,
    pub side: usize,
    pub name: String,
    pub leader: u32,
    pub members: Vec<u32>,
    pub mode: String,
    pub speed: f64,
    pub actual: f64,
    pub turn_degrees: f64,
    pub points: Vec<P>,
    pub ai: Ai,
    pub notice: Option<String>,
    pub last_ai_route: u32,
    pub tactic: Tactic,
}
#[derive(Clone, Debug, Serialize)]
pub struct Contact {
    pub id: String,
    pub x: f64,
    pub y: f64,
    pub heading: f64,
    pub speed: f64,
    pub kind: Option<String>,
    pub name: Option<String>,
    #[serde(skip)]
    pub ship: u32,
    #[serde(skip)]
    pub first_cycle: u32,
    #[serde(skip)]
    pub acquisition_base_yd: u32,
    #[serde(skip)]
    pub acquisition_range_yd: u32,
}
impl Contact {
    pub fn p(&self) -> P {
        P {
            x: self.x,
            y: self.y,
        }
    }
}
#[derive(Clone, Debug)]
pub struct Torpedo {
    pub side: usize,
    pub ship: u32,
    pub p: P,
    pub h: f64,
    pub remaining: f64,
    pub speed: f64,
    pub warhead: f64,
    pub count: u32,
    pub traveled: f64,
    pub born: u32,
    pub origin: P,
    pub view_ids: [Option<u32>; 2],
    pub(crate) first_visible: Option<P>,
    pub launch_sighted: bool,
    pub impact_sighted: bool,
    pub contact_fuze: bool,
    pub deep: bool,
    pub single_mode: bool,
    pub tested: Vec<u32>,
}
#[derive(Clone, Debug)]
pub struct Fire {
    pub side: usize,
    pub ship: u32,
    pub weapon: String,
    pub target: String,
    pub heading: Option<f64>,
    pub expires: u32,
    pub torpedo: TorpedoOrder,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct TorpedoOrder {
    pub deep: bool,
    pub mount: Option<usize>,
    pub count: Option<u32>,
}

#[derive(Clone, Debug, Serialize)]
pub struct Event {
    #[serde(skip)]
    pub view_ids: [Option<u32>; 2],
    #[serde(skip)]
    pub voice_cues: [Option<&'static str>; 2],
    pub tick: u32,
    pub kind: &'static str,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub own_ship: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rule: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub x: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub y: Option<f64>,
    #[serde(skip)]
    pub mask: u8,
}
#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct Outcome {
    pub winner: String,
    pub allies: u32,
    pub axis: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub primary: Option<bool>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Entry {
    pub tick: u32,
    pub request: serde_json::Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub seat: Option<String>,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Saved {
    pub version: String,
    pub seed: u32,
    pub side: String,
    pub enemy: String,
    #[serde(default)]
    pub variant: String,
    #[serde(default)]
    pub profile: String,
    #[serde(default)]
    pub leader_slot: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub campaign: Option<crate::campaign::live::Start>,
    pub tick: u32,
    pub commands: Vec<Entry>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub duel: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ranked: Option<RankedFleetMatch>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RankedFleetMatch {
    pub budget: u32,
    pub points_version: String,
    pub fleets: RankedFleets,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RankedFleets {
    pub allies: RankedFleet,
    pub axis: RankedFleet,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RankedFleet {
    pub ship_ids: Vec<String>,
    pub leader_id: String,
    pub ai_profile: String,
}
