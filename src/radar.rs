//! Fifth Edition surface radar (§5.1.1, §5.2.1–6). Radar samples are kept
//! separately from optical contacts so a radar echo cannot reveal target truth.
use crate::{
    model::{delta, Contact, Data, Ship, CYCLE, E, P},
    world::{roll, World},
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{collections::BTreeMap, sync::OnceLock};

const NMI: f64 = 1852.;
// The Mk4 source evaluator is staged until the historic fire-control mode is wired.
#[allow(dead_code)]
pub(crate) mod mk4;
pub(crate) const RADAR_VERSION: &str = "cas-radar-v3";
pub(crate) const RADAR_DRILL: &str = "radar";

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
            for (index, d) in devices
                .iter()
                .enumerate()
                .filter(|(_, d)| d.powered && !d.disabled)
            {
                let set = &rules().sets[&d.key];
                for t in ships.iter().filter(|t| t.side != o.side && t.alive()) {
                    if !Self::in_range(&site, set, data, o, t) {
                        continue;
                    }
                    let key = (*ship, index, t.id);
                    if let Some(sample) = self.direct.get_mut(&key) {
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
        self.version == RADAR_VERSION
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
    }
}
