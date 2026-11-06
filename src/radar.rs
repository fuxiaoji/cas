//! Fifth Edition surface radar (§5.1.1, §5.2.1–6). Radar samples are kept
//! separately from optical contacts so a radar echo cannot reveal target truth.
use crate::{
    model::{delta, Contact, Data, Ship, CYCLE, E, P, YARD},
    night::{self, Environment},
    world::{roll, World},
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{collections::BTreeMap, sync::OnceLock};

const NMI: f64 = 1852.;
pub(crate) mod mk4;
pub(crate) const RADAR_VERSION: &str = "cas-radar-v3";
pub(crate) const RADAR_DRILL: &str = "radar";
const MK4: &str = "us_mk4_fd";

#[derive(Deserialize)]
struct Rules {
    acquisition: Acquisition,
    surface_los: Horizon,
    clutter: Clutter,
    sets: BTreeMap<String, Set>,
    surface_gunnery: Gunnery,
}

#[derive(Deserialize)]
struct Acquisition {
    chance_by_generation_pct: BTreeMap<u8, u32>,
    tactical_turn_seconds: u32,
    position_share_after_detection_windows: u32,
    surface_class_column: BTreeMap<String, String>,
    target_columns: Vec<String>,
}

#[derive(Deserialize)]
struct Horizon {
    target_columns: Vec<String>,
    observer_rows_nmi: BTreeMap<String, [f64; 4]>,
}

#[derive(Deserialize)]
struct Clutter {
    profiles: Vec<String>,
    resistance_by_generation: BTreeMap<u8, i32>,
    rain_land_half_sector_deg: f64,
    sea_state: BTreeMap<u8, [i32; 2]>,
    precipitation: BTreeMap<String, [i32; 2]>,
    land: BTreeMap<String, [i32; 2]>,
    printed_range_factors: Vec<(i32, i32, f64)>,
}

#[derive(Deserialize)]
struct Set {
    name: String,
    generation: u8,
    surface_range_nmi: [f64; 5],
    clutter_profile: Option<String>,
    #[allow(dead_code)]
    fire_control_modifier_with_visual: Option<i32>,
    #[allow(dead_code)]
    blindfire_capable: Option<bool>,
}

#[derive(Deserialize)]
struct Gunnery {
    modifier_surface_search_data_only: i32,
    #[allow(dead_code)]
    modifier_non_blindfire_gfc_at_muzzle_flash: i32,
    #[allow(dead_code)]
    modifier_land_clutter_gfc: i32,
    #[allow(dead_code)]
    gfc_land_clutter_half_sector_deg: f64,
    #[allow(dead_code)]
    gfc_ignores_low_visibility_modifier: bool,
}

fn rules() -> &'static Rules {
    static RULES: OnceLock<Rules> = OnceLock::new();
    RULES.get_or_init(|| {
        let r: Rules = serde_json::from_str(include_str!("../data/rules/radar-source.json"))
            .expect("checked CAS radar source data");
        assert_eq!(r.acquisition.tactical_turn_seconds, CYCLE);
        assert_eq!(r.acquisition.position_share_after_detection_windows, 1);
        r
    })
}

pub(crate) fn search_fire_modifier() -> i32 {
    rules().surface_gunnery.modifier_surface_search_data_only
}

fn reduced_range(nominal: f64, generation: u8, clutter: i32) -> f64 {
    let c = &rules().clutter;
    let net = clutter - c.resistance_by_generation[&generation];
    if net <= 0 {
        return nominal;
    }
    let multiplier = c
        .printed_range_factors
        .iter()
        .find_map(|(lo, hi, factor)| (*lo <= net && net <= *hi).then_some(*factor))
        .expect("published clutter and resistance stay inside the table");
    nominal * multiplier
}

impl Set {
    fn effective_range(
        &self,
        site: &Site<'_>,
        observer: P,
        target: P,
        observer_size: &str,
        target_size: &str,
    ) -> Option<f64> {
        let r = rules();
        let observer_class = r.acquisition.surface_class_column.get(observer_size)?;
        let target_class = r.acquisition.surface_class_column.get(target_size)?;
        let target_col = r
            .acquisition
            .target_columns
            .iter()
            .position(|c| c == target_class)?;
        let los_col = r
            .surface_los
            .target_columns
            .iter()
            .position(|c| c == target_class)?;
        let horizon = r.surface_los.observer_rows_nmi[observer_class][los_col];
        let profile = r
            .clutter
            .profiles
            .iter()
            .position(|p| Some(p) == self.clutter_profile.as_ref())?;
        if site
            .islands
            .iter()
            .any(|land| ray_blocked(observer, target, land))
        {
            return None;
        }
        let sea = r.clutter.sea_state.get(&site.sea_state.max(1))?[profile];
        let bearing = (target - observer).heading();
        let max_range = self.surface_range_nmi.iter().copied().fold(0., f64::max) * NMI;
        let clutter = site
            .regions
            .iter()
            .filter_map(|region| {
                let (table, is_rain) = match &region.kind {
                    ClutterKind::Land => (&r.clutter.land, false),
                    ClutterKind::Precipitation => (&r.clutter.precipitation, true),
                };
                (is_rain && inside(observer, &region.polygon)
                    || sector_contains_polygon(
                        observer,
                        bearing,
                        r.clutter.rain_land_half_sector_deg,
                        max_range,
                        &region.polygon,
                    ))
                .then(|| table[&region.source_row][profile])
            })
            .fold(sea, i32::max);
        Some(
            horizon.min(reduced_range(
                self.surface_range_nmi[target_col],
                self.generation,
                clutter,
            )) * NMI,
        )
    }
}

fn edges(poly: &[P]) -> impl Iterator<Item = (P, P)> + '_ {
    poly.iter()
        .copied()
        .zip(poly.iter().copied().cycle().skip(1))
}

fn inside(point: P, polygon: &[P]) -> bool {
    edges(polygon)
        .filter(|(a, b)| {
            (a.y > point.y) != (b.y > point.y)
                && point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
        })
        .count()
        % 2
        == 1
}

fn segments_intersect(a: P, b: P, c: P, d: P) -> bool {
    // Include touching endpoints and collinear overlaps.
    let overlap = |a: f64, b: f64, c: f64, d: f64| a.min(b) <= c.max(d) && c.min(d) <= a.max(b);
    if !overlap(a.x, b.x, c.x, d.x) || !overlap(a.y, b.y, c.y, d.y) {
        return false;
    }
    let side = |a: P, b: P, c: P| (b - a).cross(c - a);
    side(a, b, c) * side(a, b, d) <= 0. && side(c, d, a) * side(c, d, b) <= 0.
}

fn ray_blocked(from: P, to: P, polygon: &[P]) -> bool {
    inside(from, polygon)
        || inside(to, polygon)
        || edges(polygon).any(|(a, b)| segments_intersect(from, to, a, b))
}

fn sector_contains_polygon(from: P, bearing: f64, half: f64, range: f64, poly: &[P]) -> bool {
    let within = |p: P| {
        let v = p - from;
        v.len() <= range && (v.len() == 0. || delta(v.heading(), bearing).abs() <= half)
    };
    let left = from + P::bearing(bearing - half) * range;
    let right = from + P::bearing(bearing + half) * range;
    inside(from, poly)
        || edges(poly).any(|(a, b)| {
            let ab = b - a;
            let t = if ab.dot(ab) == 0. {
                0.
            } else {
                (from - a).dot(ab) / ab.dot(ab)
            };
            within(a)
                || within(a + ab * t.clamp(0., 1.))
                || segments_intersect(from, left, a, b)
                || segments_intersect(from, right, a, b)
        })
}

enum ClutterKind {
    Land,
    Precipitation,
}

struct Region {
    kind: ClutterKind,
    source_row: String,
    polygon: Vec<P>,
}

struct Site<'a> {
    sea_state: u8,
    islands: &'a [Vec<P>],
    regions: &'a [Region],
}

#[derive(Clone, Copy)]
struct Sample {
    side: usize,
    observer: u32,
    target: u32,
    first_tick: u32,
    seen_tick: u32,
    position: P,
    window_position: P,
    window_tick: u32,
    previous_window: Option<(u32, P)>,
}

/// Acquired by this firing ship's own lookouts, with a visual rather than
/// muzzle-flash range. A seat's shared plot alone does not establish this.
#[derive(Clone, Copy)]
struct OwnVisual {
    original_base_yd: u32,
    acquisition_range_yd: u32,
}

#[derive(Clone)]
struct Device {
    key: String,
    powered: bool,
    disabled: bool,
}

#[derive(Clone)]
struct OtherSensor {
    name: &'static str,
    destroyed: bool,
}

type TrackKey = (u32, usize, u32); // detector hull, installed device, target hull

pub(crate) struct RadarState {
    rng: u64,
    last_detection: Option<u32>,
    mk4_optics_rng: u64,
    mk4_visual_window: Option<u32>,
    mk4_visual: BTreeMap<(u32, u32), OwnVisual>,
    devices: BTreeMap<u32, Vec<Device>>,
    full_sensor_inventory: BTreeMap<u32, Vec<OtherSensor>>,
    direct: BTreeMap<TrackKey, Sample>,
    waiting_to_share: [BTreeMap<u32, Sample>; 2],
    shared: [BTreeMap<u32, Sample>; 2],
    ids: [BTreeMap<u32, String>; 2],
    next_ids: [u32; 2],
    regions: Vec<Region>,
}

impl RadarState {
    pub(crate) fn new(seed: u32) -> Self {
        Self {
            rng: u64::from(seed) ^ 0x9bc98e18e65ab026,
            last_detection: None,
            mk4_optics_rng: u64::from(seed) ^ 0xe128313b02f740af,
            mk4_visual_window: None,
            mk4_visual: BTreeMap::new(),
            devices: BTreeMap::new(),
            full_sensor_inventory: BTreeMap::new(),
            direct: BTreeMap::new(),
            waiting_to_share: Default::default(),
            shared: Default::default(),
            ids: Default::default(),
            next_ids: [1, 1],
            regions: Vec::new(),
        }
    }

    /// Attach only an independently verified and frozen scenario fit.
    pub(crate) fn equip(&mut self, ship: u32, key: &str) -> E<()> {
        if rules()
            .sets
            .get(key)
            .is_none_or(|set| set.clutter_profile.is_none())
        {
            return Err("此雷达缺少已核验且已启用的搜索参数".into());
        }
        self.equip_device(ship, key)
    }

    fn equip_device(&mut self, ship: u32, key: &str) -> E<()> {
        let devices = self.devices.entry(ship).or_default();
        if devices.iter().any(|d| d.key == key) {
            return Err("雷达配置重复".into());
        }
        devices.push(Device {
            key: key.into(),
            powered: true,
            disabled: false,
        });
        Ok(())
    }

    /// Allows the §8.3 critical when the entire sensor fit is known. These
    /// slots compete with the search radars even before their own rules exist.
    pub(crate) fn confirm_sensor_inventory(&mut self, ship: u32, other: &[&'static str]) {
        self.full_sensor_inventory.insert(
            ship,
            other
                .iter()
                .map(|&name| OtherSensor {
                    name,
                    destroyed: false,
                })
                .collect(),
        );
    }

    /// American Fleets A-17; named mid-war Form 10s confirm these four slots.
    pub(crate) fn equip_fletcher_1943(&mut self, ship: u32) -> E<()> {
        self.equip(ship, "us_sg")?;
        self.equip(ship, "us_sc2")?;
        self.confirm_sensor_inventory(ship, &["Mk4 (FD)", "Early QC sonar"]);
        Ok(())
    }

    fn activate_fletcher_mk4(&mut self, ship: u32) -> E<()> {
        if self
            .devices
            .get(&ship)
            .is_some_and(|d| d.iter().any(|d| d.key == MK4))
        {
            return Ok(());
        }
        self.equip_device(ship, MK4)?;
        // Keep the same real four-sensor inventory. Mk4 was already a
        // damage slot in v3, but only in v4 is it also an operable device.
        self.confirm_sensor_inventory(ship, &["Early QC sonar"]);
        Ok(())
    }

    fn has_mk4(&self, ship: u32) -> bool {
        self.devices
            .get(&ship)
            .is_some_and(|d| d.iter().any(|d| d.key == MK4))
    }

    fn mk4_working(&self, ship: u32) -> bool {
        self.devices
            .get(&ship)
            .is_some_and(|d| d.iter().any(|d| d.key == MK4 && d.powered && !d.disabled))
    }

    /// Register a terrain or precipitation polygon against an original table row.
    /// Scenario authoring must supply the real type; visibility % is not rain strength.
    pub(crate) fn add_clutter(&mut self, land: bool, row: &str, polygon: Vec<P>) -> E<()> {
        let kind = if land {
            ClutterKind::Land
        } else {
            ClutterKind::Precipitation
        };
        let table = if land {
            &rules().clutter.land
        } else {
            &rules().clutter.precipitation
        };
        if !table.contains_key(row)
            || polygon.len() < 3
            || polygon.iter().any(|p| !p.x.is_finite() || !p.y.is_finite())
        {
            return Err("雷达杂波范围缺少有效地物或天气数据".into());
        }
        self.regions.push(Region {
            kind,
            source_row: row.into(),
            polygon,
        });
        Ok(())
    }

    fn power(&mut self, ship: u32, key: &str, powered: bool) -> E<()> {
        let (index, device) = self
            .devices
            .get_mut(&ship)
            .and_then(|a| a.iter_mut().enumerate().find(|(_, d)| d.key == key))
            .ok_or("该舰没有这个已启用的雷达")?;
        if device.disabled && powered {
            return Err("雷达已失能".into());
        }
        device.powered = powered;
        if !powered {
            self.direct
                .retain(|(from, dev, _), _| (*from, *dev) != (ship, index));
        }
        Ok(())
    }

    pub(crate) fn disable(&mut self, ship: u32, key: &str) {
        if self.power(ship, key, false).is_ok() {
            let d = self
                .devices
                .get_mut(&ship)
                .unwrap()
                .iter_mut()
                .find(|d| d.key == key)
                .unwrap();
            d.disabled = true;
        }
    }

    fn sensor_choices(&self, ship: u32) -> Option<Vec<(bool, usize)>> {
        let other = self.full_sensor_inventory.get(&ship)?;
        let mut choices: Vec<_> = self
            .devices
            .get(&ship)
            .into_iter()
            .flatten()
            .enumerate()
            .filter_map(|(i, d)| (!d.disabled).then_some((true, i)))
            .collect();
        choices.extend(
            other
                .iter()
                .enumerate()
                .filter_map(|(i, s)| (!s.destroyed).then_some((false, i))),
        );
        Some(choices)
    }

    fn sensor_destroy(&mut self, ship: u32, choice: (bool, usize)) -> String {
        if choice.0 {
            let key = self.devices[&ship][choice.1].key.clone();
            self.disable(ship, &key);
            rules().sets[&key].name.clone()
        } else {
            let sensor = &mut self.full_sensor_inventory.get_mut(&ship).unwrap()[choice.1];
            sensor.destroyed = true;
            sensor.name.into()
        }
    }

    fn in_range(site: &Site<'_>, set: &Set, data: &Data, observer: &Ship, target: &Ship) -> bool {
        set.effective_range(
            site,
            observer.p,
            target.p,
            &data.ships[observer.def].size,
            &data.ships[target.def].size,
        )
        .is_some_and(|r| observer.p.dist(target.p) <= r)
    }

    fn optical_geometry(
        env: Environment,
        data: &Data,
        observer: &Ship,
        contact: &Contact,
        target: &Ship,
    ) -> (f64, u32) {
        let distance_yd = observer.p.dist(contact.p()) / YARD;
        let base = night::surface_base_range_yd(
            env,
            &data.ships[observer.def].size,
            &data.ships[target.def].size,
            contact.speed,
            false,
            false,
        );
        (distance_yd, base)
    }

    fn own_visual_now(
        &self,
        env: Environment,
        data: &Data,
        observer: &Ship,
        contact: &Contact,
        target: &Ship,
    ) -> bool {
        let (distance_yd, base) = Self::optical_geometry(env, data, observer, contact, target);
        distance_yd < f64::from(night::automatic_visual_yd())
            || self
                .mk4_visual
                .get(&(observer.id, target.id))
                .is_some_and(|sample| {
                    base >= sample.original_base_yd
                        && distance_yd <= f64::from(sample.acquisition_range_yd)
                })
    }

    fn refresh_mk4_optics(
        &mut self,
        tick: u32,
        env: Environment,
        data: &Data,
        ships: &[Ship],
        contacts: &[Vec<Contact>; 2],
        islands: &[Vec<P>],
    ) {
        if !tick.is_multiple_of(CYCLE) || self.mk4_visual_window == Some(tick) {
            return;
        }
        self.mk4_visual_window = Some(tick);
        let previous = std::mem::take(&mut self.mk4_visual);
        for observer in ships.iter().filter(|s| s.alive()) {
            if !self.has_mk4(observer.id) {
                continue;
            }
            // §5.4.1: one roll per observed formation for this observer, not
            // a new roll per ship or gun salvo. This stream doesn't change
            // existing seat-level optical contacts or their RNG sequence.
            let mut dice = BTreeMap::new();
            for contact in &contacts[observer.side] {
                let Some(target) = ships
                    .get((contact.ship - 1) as usize)
                    .filter(|s| s.alive() && s.side != observer.side)
                else {
                    continue;
                };
                if islands
                    .iter()
                    .any(|p| ray_blocked(observer.p, contact.p(), p))
                {
                    continue;
                }
                let key = (observer.id, target.id);
                let (distance_yd, base) =
                    Self::optical_geometry(env, data, observer, contact, target);
                if let Some(sample) = previous.get(&key).copied().filter(|sample| {
                    base >= sample.original_base_yd
                        && distance_yd <= f64::from(sample.acquisition_range_yd)
                }) {
                    self.mk4_visual.insert(key, sample);
                    continue;
                }
                let automatic = night::automatic_visual_yd();
                if distance_yd < f64::from(automatic) || distance_yd > f64::from(base) {
                    continue;
                }
                let cue = self
                    .newest_direct(observer.side, observer.id, target.id)
                    .is_some()
                    || contact.first_cycle < tick / CYCLE;
                let fired = observer.gun_cycle == Some(tick / CYCLE)
                    || observer.illumination_cycle == Some(tick / CYCLE);
                let formation = (
                    target.fleet,
                    if target.fleet.is_none() { target.id } else { 0 },
                );
                let die = *dice
                    .entry(formation)
                    .or_insert_with(|| roll(&mut self.mk4_optics_rng, 100));
                let limit = night::surface_detection_range_yd(
                    base,
                    die as i32 + night::visual_d100_modifier(env, cue, false, fired),
                );
                if distance_yd <= f64::from(limit) {
                    self.mk4_visual.insert(
                        key,
                        OwnVisual {
                            original_base_yd: base,
                            acquisition_range_yd: limit,
                        },
                    );
                }
            }
        }
    }

    fn prune_mk4_optics(
        &mut self,
        env: Environment,
        data: &Data,
        ships: &[Ship],
        contacts: &[Vec<Contact>; 2],
        islands: &[Vec<P>],
    ) {
        self.mk4_visual.retain(|&(from, to), sample| {
            let Some(observer) = ships.get((from - 1) as usize).filter(|s| s.alive()) else {
                return false;
            };
            let Some(target) = ships.get((to - 1) as usize).filter(|s| s.alive()) else {
                return false;
            };
            let Some(contact) = contacts[observer.side].iter().find(|c| c.ship == to) else {
                return false;
            };
            let (distance_yd, base) = Self::optical_geometry(env, data, observer, contact, target);
            base >= sample.original_base_yd
                && distance_yd <= f64::from(sample.acquisition_range_yd)
                && !islands
                    .iter()
                    .any(|p| ray_blocked(observer.p, contact.p(), p))
        });
    }

    fn prune(&mut self, tick: u32, data: &Data, ships: &[Ship], islands: &[Vec<P>], sea_state: u8) {
        let site = Site {
            islands,
            sea_state,
            regions: &self.regions,
        };
        let devices = &self.devices;
        self.direct.retain(|&(from, index, target), sample| {
            let Some(o) = ships.get((from - 1) as usize).filter(|s| s.alive()) else {
                return false;
            };
            let Some(t) = ships.get((target - 1) as usize).filter(|s| s.alive()) else {
                return false;
            };
            let d = &devices[&from][index];
            let valid = d.powered
                && !d.disabled
                && Self::in_range(&site, &rules().sets[&d.key], data, o, t);
            if valid {
                sample.position = t.p;
                sample.seen_tick = tick;
            }
            valid
        });
    }

    fn detect(
        &mut self,
        tick: u32,
        data: &Data,
        ships: &[Ship],
        islands: &[Vec<P>],
        sea_state: u8,
    ) {
        if !tick.is_multiple_of(CYCLE) || self.last_detection == Some(tick) {
            return;
        }
        self.last_detection = Some(tick);
        self.prune(tick, data, ships, islands, sea_state);
        self.shared = std::mem::take(&mut self.waiting_to_share);
        let site = Site {
            islands,
            sea_state,
            regions: &self.regions,
        };
        for (ship, devices) in &self.devices {
            let Some(o) = ships.get((*ship - 1) as usize).filter(|s| s.alive()) else {
                continue;
            };
            for (index, d) in devices.iter().enumerate().filter(|(_, d)| {
                d.powered && !d.disabled && rules().sets[&d.key].clutter_profile.is_some()
            }) {
                let set = &rules().sets[&d.key];
                for t in ships.iter().filter(|t| t.side != o.side && t.alive()) {
                    if !Self::in_range(&site, set, data, o, t) {
                        continue;
                    }
                    let key = (*ship, index, t.id);
                    if let Some(sample) = self.direct.get_mut(&key) {
                        sample.previous_window = Some((sample.window_tick, sample.window_position));
                        sample.window_position = t.p;
                        sample.window_tick = tick;
                        sample.position = t.p;
                        sample.seen_tick = tick;
                    } else if roll(&mut self.rng, 100)
                        <= rules().acquisition.chance_by_generation_pct[&set.generation]
                    {
                        self.direct.insert(
                            key,
                            Sample {
                                side: o.side,
                                observer: o.id,
                                target: t.id,
                                first_tick: tick,
                                seen_tick: tick,
                                position: t.p,
                                window_position: t.p,
                                window_tick: tick,
                                previous_window: None,
                            },
                        );
                    }
                }
            }
        }
        for sample in self.direct.values() {
            let side = sample.side;
            self.waiting_to_share[side]
                .entry(sample.target)
                .or_insert(*sample);
            self.ids[side].entry(sample.target).or_insert_with(|| {
                let next = self.next_ids[side];
                self.next_ids[side] += 1;
                format!("R{next:02}")
            });
        }
        for side in 0..2 {
            self.ids[side].retain(|t, _| {
                self.waiting_to_share[side].contains_key(t) || self.shared[side].contains_key(t)
            });
        }
    }

    fn newest_direct(&self, owner: usize, ship: u32, target: u32) -> Option<&Sample> {
        self.direct
            .values()
            .filter(|s| s.side == owner && s.observer == ship && s.target == target)
            .min_by_key(|s| (s.first_tick, std::cmp::Reverse(s.seen_tick)))
    }

    fn for_gun(&self, ship: &Ship, id: &str) -> Option<Contact> {
        let target = self.ids[ship.side]
            .iter()
            .find_map(|(&ship, tag)| (tag == id).then_some(ship))?;
        let sample = self.newest_direct(ship.side, ship.id, target)?;
        Some(Contact {
            id: id.into(),
            x: sample.position.x,
            y: sample.position.y,
            heading: 0.,
            speed: 0.,
            kind: None,
            name: None,
            ship: target,
            first_cycle: sample.first_tick / CYCLE,
            acquisition_base_yd: 0,
            acquisition_range_yd: 0,
        })
    }

    fn for_torpedo(&self, ship: &Ship, id: &str) -> Option<Contact> {
        let mut contact = self.for_gun(ship, id)?;
        let sample = self.direct.iter()
            .filter(|((observer, _, target), s)| *observer == ship.id && *target == contact.ship &&
                s.previous_window.is_some_and(|(prev, _)| s.window_tick.checked_sub(prev) == Some(CYCLE)))
            .map(|(_, s)| s)
            .min_by_key(|s| s.first_tick)?;
        let (previous_tick, previous) = sample.previous_window?;
        let latest_tick = self.last_detection?;
        if latest_tick.checked_sub(previous_tick)? != CYCLE { return None; }
        let moved = sample.window_position - previous;
        contact.x = sample.position.x;
        contact.y = sample.position.y;
        contact.heading = moved.heading();
        contact.speed = moved.len() / (f64::from(CYCLE) * crate::model::KNOT);
        contact.first_cycle = sample.first_tick / CYCLE;
        Some(contact)
    }

    pub(crate) fn own_observation(&self, ship: u32) -> Vec<Value> {
        self.devices.get(&ship).into_iter().flatten().map(|device| {
            let set = &rules().sets[&device.key];
            json!({"id":device.key, "name":set.name, "powered":device.powered, "disabled":device.disabled})
        }).collect()
    }

    pub(crate) fn observation(&self, owner: usize, ships: &[Ship]) -> Vec<Value> {
        let mut reports = Vec::new();
        for (&target, id) in &self.ids[owner] {
            let direct: Vec<_> = ships
                .iter()
                .filter(|s| s.side == owner && s.alive())
                .filter_map(|s| self.newest_direct(owner, s.id, target))
                .collect();
            let shared = self.shared[owner].get(&target);
            let Some(sample) = direct.first().copied().or(shared) else {
                continue;
            };
            reports.push(json!({
                "id":id, "x":sample.position.x, "y":sample.position.y,
                "lastSeenTick":sample.seen_tick, "direct":!direct.is_empty(),
                "usableForShipIds":direct.iter().map(|s| s.observer).collect::<Vec<_>>(),
                "shared":shared.map(|s| json!({"x":s.position.x, "y":s.position.y, "lastSeenTick":s.seen_tick})),
            }));
        }
        reports
    }
}

impl World {
    pub(crate) fn radar_enabled(&self) -> bool {
        self.version == RADAR_VERSION || (self.realtime() && matches!(self.variant.as_str(), RADAR_DRILL | crate::campaign::live::VARIANT | crate::illumination::RADAR_TRAINING))
    }

    pub(crate) fn radar_detect(&mut self) {
        if self.radar_enabled() {
            self.radar.detect(
                self.tick,
                self.data,
                &self.ships,
                &self.islands,
                self.environment().sea_state,
            );
        }
        self.refresh_realtime_mk4_optics();
    }

    pub(crate) fn radar_prune(&mut self) {
        if self.radar_enabled() {
            self.radar.prune(
                self.tick,
                self.data,
                &self.ships,
                &self.islands,
                self.environment().sea_state,
            );
        }
        if self.mk4_rules_enabled() {
            self.radar.prune_mk4_optics(
                self.environment(),
                self.data,
                &self.ships,
                &self.contacts,
                &self.islands,
            );
        }
    }

    fn mk4_rules_enabled(&self) -> bool {
        self.realtime() && matches!(self.variant.as_str(), RADAR_DRILL | crate::campaign::live::VARIANT)
    }

    pub(crate) fn enable_realtime_mk4(&mut self) -> E<()> {
        if self.mk4_rules_enabled() {
            for s in &self.ships {
                // Only the separately verified 1943 fit in this drill.
                if s.side == 0 && (self.data.ships[s.def].id == "fletcher" || self.variant == crate::campaign::live::VARIANT) {
                    self.radar.activate_fletcher_mk4(s.id)?;
                }
            }
            self.refresh_realtime_mk4_optics();
        }
        Ok(())
    }

    fn refresh_realtime_mk4_optics(&mut self) {
        if self.mk4_rules_enabled() {
            self.radar.refresh_mk4_optics(
                self.tick,
                self.environment(),
                self.data,
                &self.ships,
                &self.contacts,
                &self.islands,
            );
        }
    }

    pub(crate) fn mk4_gun_aid(
        &self,
        shooter: &Ship,
        contact: &Contact,
        search_only: bool,
    ) -> Option<mk4::Aid> {
        if !self.mk4_rules_enabled()
            || search_only
            || shooter.fire_control_damage
            || !self.radar.mk4_working(shooter.id)
            || !shooter.alive()
        {
            return None;
        }
        // A same-seat contact ID and the actual independently held local
        // visual plot are both required. Never discover a hull through aim.
        let optical = self.contacts[shooter.side]
            .iter()
            .find(|c| c.id == contact.id && c.ship == contact.ship)?;
        let target = self
            .ship(optical.ship)
            .filter(|t| t.alive() && t.side != shooter.side)?;
        if !self
            .radar
            .own_visual_now(self.environment(), self.data, shooter, optical, target)
        {
            return None;
        }
        mk4::evaluate(mk4::CuedShot {
            observer: shooter.p,
            observer_heading: shooter.h,
            observer_size: &self.data.ships[shooter.def].size,
            target: optical.p(),
            target_size: &self.data.ships[target.def].size,
            cue: mk4::Cue::Visual,
            director_usable: true,
            land: &self.islands,
        })
    }

    pub(crate) fn radar_power(&mut self, owner: usize, request: &Value) -> E<()> {
        if !self.radar_enabled() {
            return Err("本想定未启用雷达".into());
        }
        let ship = crate::world::u(request, "ship")?;
        self.ship_for(owner, ship)?;
        let key = request["radar"].as_str().ok_or("请选择本舰雷达")?;
        let powered = request["powered"].as_bool().ok_or("缺少雷达开关状态")?;
        self.radar.power(ship, key, powered)
    }

    pub(crate) fn radar_gun_contact(&self, ship: &Ship, id: &str) -> Option<Contact> {
        self.radar_enabled()
            .then(|| self.radar.for_gun(ship, id))
            .flatten()
    }

    pub(crate) fn radar_gun_contacts<'a>(
        &'a self,
        ship: &'a Ship,
    ) -> impl Iterator<Item = Contact> + 'a {
        self.radar.ids[ship.side]
            .values()
            .filter_map(move |id| self.radar_gun_contact(ship, id))
    }

    pub(crate) fn radar_torp_contact(&self, ship: &Ship, id: &str) -> Option<Contact> {
        if self.variant != crate::campaign::live::VARIANT { return None; }
        self.radar.for_torpedo(ship, id)
    }

    pub(crate) fn radar_torp_contacts<'a>(&'a self, ship: &'a Ship) -> impl Iterator<Item = Contact> + 'a {
        self.radar.ids[ship.side].values().filter_map(move |id| self.radar_torp_contact(ship, id))
    }

    pub(crate) fn radar_navigation_reports<'a>(
        &'a self,
        ship: &'a Ship,
    ) -> impl Iterator<Item = P> + 'a {
        self.radar.ids[ship.side].keys().filter_map(move |&target| {
            self.radar
                .newest_direct(ship.side, ship.id, target)
                .or_else(|| self.radar.shared[ship.side].get(&target))
                .map(|s| s.position)
        })
    }

    pub(crate) fn radar_sensor_critical(&mut self, ship: u32) {
        if !self.radar_enabled() {
            return;
        }
        let Some(choices) = self.radar.sensor_choices(ship) else {
            return;
        };
        // A result of 4–6 is communications; that subsystem is not yet active.
        if choices.is_empty() || self.d(6) > 3 {
            return;
        }
        let choice = choices[self.d(choices.len() as u32) as usize - 1];
        let sensor = self.radar.sensor_destroy(ship, choice);
        let (side, p, name) = {
            let s = self.ship(ship).unwrap();
            (s.side, s.p, s.name.clone())
        };
        self.add(
            1 << side,
            "critical",
            format!("{name} · {sensor} 失能"),
            Some("CAS-8.3.3"),
            Some(p),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        model::{VERSION, YARD},
        Engine,
    };

    fn point(x: f64, y: f64) -> P {
        P { x, y }
    }

    fn box_at(x: f64, y: f64, r: f64) -> Vec<P> {
        vec![
            point(x - r, y - r),
            point(x + r, y - r),
            point(x + r, y + r),
            point(x - r, y + r),
        ]
    }

    #[test]
    fn annex_sets_horizon_and_worst_eligible_clutter() {
        let open = Site {
            sea_state: 1,
            islands: &[],
            regions: &[],
        };
        let sets = &rules().sets;
        let from = point(0., 0.);
        let to = point(0., 9. * NMI);
        assert_eq!(
            sets["us_sg"].effective_range(&open, from, to, "C", "D"),
            Some(15. * NMI)
        );
        assert_eq!(
            sets["us_sg"].effective_range(&open, from, to, "E", "A"),
            Some(19. * NMI)
        );
        assert_eq!(
            sets["us_sc2"].effective_range(&open, from, to, "C", "D"),
            Some(10. * NMI)
        );
        assert_eq!(
            sets["jp_type22_ss"].effective_range(&open, from, to, "C", "D"),
            Some(4. * NMI)
        );
        assert_eq!(
            sets["us_sg"].effective_range(&open, from, to, "C", "G"),
            None
        );
        assert_eq!(reduced_range(4., 1, 7), 1.6); // Printed SC example, PDF 40.
        assert_eq!(reduced_range(15., 2, 6), 12.75); // Printed SGb example rounds to 12.8.

        let mut radar = RadarState::new(10);
        radar
            .add_clutter(
                false,
                "moderate_rain_or_heavy_fog",
                box_at(0., 12. * NMI, 100.),
            )
            .unwrap();
        radar
            .add_clutter(
                true,
                "flat_land_brush_or_light_woods",
                box_at(0., 20. * NMI, 100.),
            )
            .unwrap();
        radar
            .add_clutter(false, "torrential_rain", box_at(4. * NMI, 10. * NMI, 100.))
            .unwrap(); // Outside ±5°.
        let mut rough = Site {
            sea_state: 4,
            islands: &[],
            regions: &radar.regions,
        };
        assert_eq!(
            sets["us_sg"].effective_range(&rough, from, to, "C", "C"),
            Some(7.5 * NMI)
        );
        // SC-2 uses its primary AS clutter row and nominal maximum of 12 nmi.
        assert_eq!(
            sets["us_sc2"].effective_range(&rough, from, to, "C", "C"),
            Some(7. * NMI)
        );
        let land = [box_at(0., 2. * NMI, 100.)];
        rough.islands = &land;
        assert_eq!(
            sets["us_sg"].effective_range(&rough, from, to, "C", "C"),
            None
        );
        let mut local_rain = RadarState::new(10);
        local_rain
            .add_clutter(false, "heavy_rain", box_at(0., 0., 100.))
            .unwrap();
        let rainy = Site {
            sea_state: 1,
            islands: &[],
            regions: &local_rain.regions,
        };
        assert_eq!(
            sets["us_sg"].effective_range(&rainy, from, point(0., -2000.), "C", "C"),
            Some(15. * 0.35 * NMI)
        );
    }

    fn sparse() -> World {
        let mut world = World::new(6106, 0, "coord", RADAR_DRILL, "coord", 0).unwrap();
        world.contacts = Default::default();
        for s in &mut world.ships {
            if !matches!(s.id, 1 | 2 | 6) {
                s.hp = 0.;
            }
            s.p = match s.id {
                1 => point(5000., 6500.),
                2 => point(5300., 6000.),
                _ => point(12_000., 6500.),
            };
        }
        world.radar = RadarState::new(6106);
        world.radar.equip_fletcher_1943(1).unwrap();
        let rng = (1..)
            .find(|&state| roll(&mut state.clone(), 100) <= 60)
            .unwrap();
        world.radar.rng = rng;
        world
    }

    #[test]
    fn search_retries_only_next_window_keeps_track_and_shares_only_prior_sample() {
        let mut world = sparse();
        world.radar_detect();
        let a = world.observation(0);
        let echo = &a["radarContacts"][0];
        assert_eq!(echo["usableForShipIds"], json!([1]));
        assert!(echo["shared"].is_null());
        for hidden in ["ship", "name", "kind", "speed", "heading"] {
            assert!(echo.get(hidden).is_none(), "{echo}");
        }
        assert_eq!(world.observation(1)["radarContacts"], json!([]));
        let id = echo["id"].as_str().unwrap();
        let aim = |ship| json!({"ship":ship,"target":id,"weapon":"gun"});
        assert_eq!(
            world.preview_aim(0, &aim(1)).unwrap()["targetSource"],
            "surface_radar"
        );
        assert!(world.preview_aim(0, &aim(2)).is_err());
        assert!(world.preview_aim(1, &aim(6)).is_err());
        assert!(world
            .preview_aim(0, &json!({"ship":1,"target":id,"weapon":"torpedo"}))
            .is_err());

        let prior_rng = world.radar.rng;
        world.radar_detect();
        world.tick = 179;
        world.radar_detect();
        assert_eq!(world.radar.rng, prior_rng);
        world.ship_mut(6).unwrap().p.x += 450.;
        world.radar_prune();
        assert_eq!(world.observation(0)["radarContacts"][0]["x"], 12_450.);
        assert!(world.observation(0)["radarContacts"][0]["shared"].is_null());

        world.tick = 180;
        world.radar_detect();
        let e = &world.observation(0)["radarContacts"][0];
        assert_eq!(e["x"], 12_450.);
        assert_eq!(e["shared"]["x"], 12_000.);
        assert_eq!(e["shared"]["lastSeenTick"], 0);
        world.radar.disable(1, "us_sg");
        world.radar.disable(1, "us_sc2");
        assert!(world.radar.power(1, "us_sg", true).is_err());
        assert!(world.preview_aim(0, &aim(1)).is_err());
        let e = &world.observation(0)["radarContacts"][0];
        assert_eq!(e["direct"], false);
        assert_eq!(e["x"], 12_000.);
        world.tick = 360;
        world.radar_detect();
        assert_eq!(world.observation(0)["radarContacts"][0]["x"], 12_450.);
        world.tick = 540;
        world.radar_detect();
        assert_eq!(world.observation(0)["radarContacts"], json!([]));
    }

    #[test]
    fn radar_gun_uses_authorized_echo_without_visual_leak() {
        let mut world = sparse();
        world.radar_detect();
        let v = world.observation(0);
        let id = &v["radarContacts"][0]["id"];
        assert!(world.ship(1).unwrap().p.dist(world.ship(6).unwrap().p) / YARD < 11_000.);
        let gun = json!({"op":"fire","ship":1,"weapon":"gun","target":id});
        assert_eq!(world.preview_aim(0, &gun).unwrap()["valid"], true);
        let orders = world.suggestions(0, 1).unwrap();
        assert!(orders
            .iter()
            .any(|o| o["weapon"] == "gun" && o["ship"] == 1 && o["target"] == *id));
        world.external(gun).unwrap();
        let hp = world.ship(6).unwrap().hp;
        world.rng = (1..)
            .find(|&state| roll(&mut state.clone(), 100) == 1)
            .unwrap();
        world.tick = CYCLE;
        world.resolve_fire(true);
        assert_eq!(world.ship(1).unwrap().gun_cycle, Some(1));
        assert!(world.ship(6).unwrap().hp < hp);
        assert!(world.observation(0)["shells"]
            .as_array()
            .unwrap()
            .is_empty());
        let guns: Vec<_> = world
            .visible_events(0, None)
            .into_iter()
            .filter(|e| e["kind"] == "gun")
            .collect();
        assert_eq!(guns.len(), 1);
        assert!(guns[0]["text"]
            .as_str()
            .unwrap()
            .contains("本舰水面搜索雷达"));
        assert!(!guns[0]["text"].as_str().unwrap().contains("D100"));
        assert!(world
            .visible_events(0, None)
            .iter()
            .all(|e| e["kind"] != "hit" && e["kind"] != "sunk"));
    }

    #[test]
    fn realtime_mk4_needs_its_own_held_optical_track_and_forward_director() {
        let mut world = sparse();
        let p = world.ship(1).unwrap().p;
        let place = |world: &mut World, yards: f64| {
            let q = p + P::bearing(90.) * (yards * YARD);
            world.ship_mut(6).unwrap().p = q;
            world.contacts[0] = vec![Contact {
                id: "C01".into(),
                x: q.x,
                y: q.y,
                heading: 270.,
                speed: 25.,
                kind: Some("dd".into()),
                name: None,
                ship: 6,
                first_cycle: 0,
                acquisition_base_yd: 10_000,
                acquisition_range_yd: 10_000,
            }];
        };
        let aid = |world: &World, radar_only| {
            world.mk4_gun_aid(world.ship(1).unwrap(), &world.contacts[0][0], radar_only)
        };
        place(&mut world, 800.);
        assert!(world
            .radar
            .own_observation(1)
            .iter()
            .all(|d| d["id"] != MK4));
        assert_eq!(aid(&world, false), None);

        world.tick = 1;
        world.enable_realtime().unwrap();
        world.enable_realtime_mk4().unwrap();
        assert!(world
            .radar
            .own_observation(1)
            .iter()
            .any(|d| d["id"] == MK4));
        assert!(!world.radar.has_mk4(2));
        assert!(!world.radar.has_mk4(6));
        // A same-seat optics report is not independent visual confirmation.
        assert_eq!(aid(&world, false), None);
        world.radar.mk4_optics_rng = (1..)
            .find(|&seed| roll(&mut seed.clone(), 100) == 1)
            .unwrap();
        world.tick = CYCLE;
        world.radar_detect();
        assert_eq!(aid(&world, false).unwrap().fire_control_modifier, 2);
        assert_eq!(aid(&world, true), None);
        assert!(world
            .radar
            .direct
            .keys()
            .all(|&(ship, device, _)| world.radar.devices[&ship][device].key != MK4));

        let fire = || json!({"op":"fire","ship":1,"weapon":"gun","target":"C01"});
        world.rng = (1..)
            .find(|&seed| roll(&mut seed.clone(), 100) == 60)
            .unwrap();
        let intact_hp = world.ship(6).unwrap().hp;
        world.external(fire()).unwrap();
        world.resolve_realtime_guns();
        assert!(world.visible_events(0, None).iter().any(|e| {
            e["kind"] == "gun"
                && e["text"]
                    .as_str()
                    .unwrap_or_default()
                    .contains("火控雷达 Mk4")
        }));
        assert!(world.visible_events(1, None).iter().all(|e| {
            !e["text"]
                .as_str()
                .unwrap_or_default()
                .contains("火控雷达 Mk4")
        }));

        let optical_rng = world.radar.mk4_optics_rng;
        world.radar_detect();
        assert_eq!(world.radar.mk4_optics_rng, optical_rng);
        world.ship_mut(1).unwrap().h = 270.;
        assert_eq!(aid(&world, false), None);
        world.ship_mut(1).unwrap().h = 90.;
        world.ship_mut(1).unwrap().fire_control_damage = true;
        assert_eq!(aid(&world, false), None);
        world.ship_mut(1).unwrap().fire_control_damage = false;
        world
            .radar_power(0, &json!({"ship":1,"radar":MK4,"powered":false}))
            .unwrap();
        assert_eq!(aid(&world, false), None);
        world.tick += 6;
        world.advance_shells();
        let hit_hp = world.ship(6).unwrap().hp;
        assert!(
            hit_hp < intact_hp,
            "D100 60 hits with Mk4; 20% night penalty waived"
        );
        world.external(fire()).unwrap();
        world.resolve_realtime_guns();
        let own_guns: Vec<_> = world
            .visible_events(0, None)
            .into_iter()
            .filter(|e| e["kind"] == "gun")
            .collect();
        assert_eq!(own_guns.len(), 2);
        assert!(!own_guns.last().unwrap()["text"]
            .as_str()
            .unwrap_or_default()
            .contains("火控雷达 Mk4"));
        world.tick += 6;
        world.advance_shells();
        assert_eq!(
            world.ship(6).unwrap().hp,
            hit_hp,
            "same D100 60 misses without Mk4"
        );
        world
            .radar_power(0, &json!({"ship":1,"radar":MK4,"powered":true}))
            .unwrap();
        assert!(aid(&world, false).is_some());

        place(&mut world, 10_500.);
        world.ship_mut(6).unwrap().gun_cycle = Some(world.tick / CYCLE);
        world.radar_prune();
        assert_eq!(aid(&world, false), None);
        place(&mut world, 800.);
        assert_eq!(
            aid(&world, false),
            None,
            "lost visual does not silently reacquire"
        );
        place(&mut world, 299.);
        assert!(aid(&world, false).is_some());
        world.islands = vec![box_at(p.x + 80., p.y, 5.)];
        assert_eq!(
            aid(&world, false),
            None,
            "near range does not see through land"
        );
        world.islands.clear();
        world.radar.disable(1, MK4);
        assert!(world
            .radar_power(0, &json!({"ship":1,"radar":MK4,"powered":true}))
            .is_err());
        assert_eq!(aid(&world, false), None);
    }

    #[test]
    fn recorded_power_and_contact_history_replay_identically_without_upgrading_legacy() {
        let mut e = Engine::default();
        let ask = |e: &mut Engine, r| {
            let v = e.handle(r);
            assert_eq!(v["ok"], true, "{v}");
            v["data"].clone()
        };
        let start = ask(&mut e, json!({"op":"new","variant":"radar"}));
        assert_eq!(start["version"], RADAR_VERSION);
        assert!(!start["radarContacts"].as_array().unwrap().is_empty());
        assert_eq!(start["ships"][0]["systems"]["radars"][0]["powered"], true);
        let switched = ask(
            &mut e,
            json!({"op":"radar_set","ship":1,"radar":"us_sg","powered":false}),
        );
        assert_eq!(
            switched["ships"][0]["systems"]["radars"][0]["powered"],
            false
        );
        let view = ask(&mut e, json!({"op":"step","seconds":540}));
        let save = ask(&mut e, json!({"op":"save"}));
        assert_eq!(view, ask(&mut e, json!({"op":"replay","save":save})));
        let mut mislabeled = save;
        mislabeled["version"] = json!(VERSION);
        assert_eq!(
            e.handle(json!({"op":"load","save":mislabeled}))["ok"],
            false
        );
        let old = ask(&mut e, json!({"op":"new","variant":"night"}));
        assert_eq!(old["version"], VERSION);
        assert!(old.get("radarContacts").is_none());
        assert!(old["ships"][0]["systems"].get("radars").is_none());

        let live = ask(
            &mut e,
            json!({"op":"new","variant":"radar","realtime":true}),
        );
        assert_eq!(live["version"], crate::realtime::VERSION);
        assert_eq!(live["ships"][0]["systems"]["radars"][2]["id"], MK4);
        ask(
            &mut e,
            json!({"op":"radar_set","ship":1,"radar":MK4,"powered":false}),
        );
        let stepped = ask(&mut e, json!({"op":"step","seconds":540}));
        let saved = ask(&mut e, json!({"op":"save"}));
        assert_eq!(stepped, ask(&mut e, json!({"op":"replay","save":saved})));
        assert_eq!(
            stepped["ships"][0]["systems"]["radars"][2]["powered"],
            false
        );
    }
}
