//! Original v3 distinct weapon models and deterministic magazine/burst state.
use super::*;
use std::sync::OnceLock;
#[derive(Clone, Copy, Serialize)]
pub(super) struct Cadence {
    pub fire_mode: &'static str,
    pub fire_interval_s: f64,
    pub burst_size: u32,
    pub burst_interval_s: f64,
    pub magazine_capacity: u32,
    pub magazine_reload_s: f64,
}
impl Cadence {
    pub const fn single(interval: f64) -> Self {
        Self {
            fire_mode: "single",
            fire_interval_s: interval,
            burst_size: 1,
            burst_interval_s: interval,
            magazine_capacity: 1,
            magazine_reload_s: interval,
        }
    }
    pub fn mean_interval(self) -> f64 {
        let burst = self.burst_size.max(1);
        let capacity = self.magazine_capacity.max(1);
        let between = (1..capacity)
            .map(|i| {
                if i % burst == 0 {
                    self.burst_interval_s
                } else {
                    self.fire_interval_s
                }
            })
            .sum::<f64>();
        let last_gap = if capacity % burst == 0 {
            self.burst_interval_s
        } else {
            self.fire_interval_s
        };
        (between + last_gap.max(self.magazine_reload_s)) / capacity as f64
    }
}
fn intern(s: &str) -> &'static str {
    Box::leak(s.to_owned().into_boxed_str())
}
pub(super) fn models() -> &'static [Weapon] {
    static MODELS: OnceLock<Vec<Weapon>> = OnceLock::new();
    MODELS.get_or_init(|| {
        let data: Value = serde_json::from_str(include_str!(
            "../docs/design/tactical-v4-weapon-models.json"
        ))
        .expect("registered weapon model design");
        data["models"]
            .as_array()
            .expect("weapon model array")
            .iter()
            .map(|r| {
                let family = r["family_id"].as_str().unwrap();
                let base = WEAPONS
                    .iter()
                    .find(|w| w.family_id == family)
                    .expect("registered weapon family");
                let mut w = *base;
                w.id = intern(r["id"].as_str().unwrap());
                w.name = intern(r["name"].as_str().unwrap());
                w.owner = Some(intern(r["unit_id"].as_str().unwrap()));
                w.damage = r["damage"].as_f64().unwrap();
                w.range_m = r["range_m"].as_f64().unwrap();
                w.ammo_capacity = r["ammo_capacity"].as_u64().unwrap() as u32;
                w.accuracy_scale = r["accuracy_scale"].as_f64().unwrap_or(1.);
                w.cadence = Cadence {
                    fire_mode: intern(r["fire_mode"].as_str().unwrap()),
                    fire_interval_s: r["fire_interval_s"].as_f64().unwrap(),
                    burst_size: r["burst_size"].as_u64().unwrap() as u32,
                    burst_interval_s: r["burst_interval_s"].as_f64().unwrap(),
                    magazine_capacity: r["magazine_capacity"].as_u64().unwrap() as u32,
                    magazine_reload_s: r["magazine_reload_s"].as_f64().unwrap(),
                };
                // Compatibility/AI field: mean sustained firing interval, never a magazine timer.
                w.reload_s = w.cadence.mean_interval();
                w
            })
            .collect()
    })
}
pub(super) fn model(unit_id: &str, family: &str) -> &'static Weapon {
    models()
        .iter()
        .find(|w| w.owner == Some(unit_id) && w.family_id == family)
        .unwrap_or_else(|| weapon(family))
}
#[derive(Clone, Debug)]
pub(super) struct FireState {
    pub magazine: u32,
    pub reload_until: u32,
    pub next: u32,
    pub burst_left: u32,
}
fn ticks(seconds: f64, haste: f64) -> u32 {
    (seconds * haste * 10.).ceil().max(1.) as u32
}
impl FireState {
    pub fn new(w: &Weapon, total: u32) -> Self {
        Self {
            magazine: total.min(w.cadence.magazine_capacity),
            reload_until: 0,
            next: 0,
            burst_left: 0,
        }
    }
    pub fn advance(&mut self, w: &Weapon, total: u32, frame: u32) {
        self.magazine = self.magazine.min(total);
        if self.reload_until > 0 && frame >= self.reload_until {
            self.magazine = total.min(w.cadence.magazine_capacity);
            self.reload_until = 0;
            self.burst_left = 0;
        }
        if total > 0 && self.magazine == 0 && self.reload_until == 0 {
            self.reload_until = frame + ticks(w.cadence.magazine_reload_s, 1.);
            self.burst_left = 0;
        }
    }
    pub fn ready(&self, total: u32, frame: u32) -> bool {
        total > 0 && self.magazine > 0 && self.reload_until == 0 && frame >= self.next
    }
    pub fn fired(&mut self, w: &Weapon, total_after: u32, frame: u32, haste: f64) {
        assert!(self.magazine > 0);
        self.magazine -= 1;
        if self.burst_left == 0 {
            self.burst_left = w.cadence.burst_size.max(1);
        }
        self.burst_left -= 1;
        let delay = if self.burst_left > 0 {
            w.cadence.fire_interval_s
        } else {
            w.cadence.burst_interval_s
        };
        self.next = frame + ticks(delay, haste);
        if self.magazine == 0 && total_after > 0 {
            self.reload_until = frame + ticks(w.cadence.magazine_reload_s, haste);
            self.burst_left = 0;
        }
    }
    pub fn view(&self, total: u32, frame: u32, gate: u32) -> Value {
        json!({"magazine_ammo":self.magazine.min(total),"reserve_ammo":total.saturating_sub(self.magazine),
            "reloading_in":self.reload_until.saturating_sub(frame)as f64/10.,
            "burst_remaining":self.burst_left,
            "ready_in":self.next.max(self.reload_until).max(gate).saturating_sub(frame)as f64/10.})
    }
}
impl Battle {
    fn firearm_total(&self, id: u32, w: &Weapon) -> u32 {
        if let Some(v) = self.vehicles.iter().find(|v| v.id == id) {
            return v.ammo;
        }
        if self.loadouts.get(&id).is_some_and(|l| l.weapon.id == w.id) {
            return self.base.body(id).map_or(0, |b| b.ammo);
        }
        if let Some(s) = self.secondary.get(&id).filter(|s| s.weapon.id == w.id) {
            return s.ammo;
        }
        self.base.body(id).map_or(0, |b| b.ammo)
    }
    pub(super) fn base_ai_v3(&mut self, available_charges: &[u32]) {
        let protected = (0..self.base.companies.len())
            .filter(|&ci| {
                let c = &self.base.companies[ci];
                let primary = c
                    .bodies
                    .iter()
                    .filter_map(|id| self.base.body(*id))
                    .filter(|b| b.hp > 0.)
                    .map(|b| b.ammo)
                    .sum::<u32>();
                let extra = c.bodies.iter().any(|id| {
                    self.base.body(*id).is_some_and(|b| b.hp > 0.)
                        && self.secondary.get(id).is_some_and(|s| s.ammo > 0)
                }) || self
                    .vehicles
                    .iter()
                    .any(|v| v.company == ci && v.active && v.hp > 0. && v.ammo > 0)
                    || c.unit.ability == "supply_network"
                        && self.supply_target(ci)
                        && available_charges.get(ci).copied().unwrap_or(0) > 0;
                let health = c
                    .bodies
                    .iter()
                    .filter_map(|id| self.base.body(*id))
                    .map(|b| b.hp / b.max)
                    .sum::<f64>()
                    / c.bodies.len().max(1) as f64;
                let fuel = self
                    .base
                    .actors
                    .iter()
                    .filter(|a| a.company == ci)
                    .map(|a| a.fuel)
                    .fold(f64::INFINITY, f64::min);
                let capable_vehicle=self.vehicles.iter().any(|v|v.company==ci&&v.active&&v.hp/v.max>=0.23&&v.ammo>0);
                c.stage == "active"
                    && (primary == 0 && extra && health >= 0.23 || capable_vehicle)
                    && !(c.unit.class == "air" && fuel < 5000.)
                    && !(c.side == self.base.attack() && self.base.land_complete())
                    && !(c.side == 0 && self.base.posture == "withdraw")
            })
            .collect::<Vec<_>>();
        let empty = (0..self.base.companies.len())
            .filter(|&ci| {
                let c = &self.base.companies[ci];
                c.stage == "active"
                    && (c.side != 0 || self.base.auto)
                    && (if c.unit.role == "artillery" {
                        !self
                            .vehicles
                            .iter()
                            .any(|v| v.company == ci && v.active && v.hp > 0. && v.ammo > 0)
                    } else {
                        !protected.contains(&ci)
                            && c.bodies.iter().all(|id| {
                                self.base
                                    .body(*id)
                                    .is_none_or(|b| b.hp <= 0. || b.ammo == 0)
                            })
                    })
            })
            .collect::<Vec<_>>();
        for ci in empty {
            let _ = self.base.withdraw(ci);
        }
        // An internal dispatch guard only: no observable phase/body/ammo is changed.
        for &ci in &protected {
            self.base.companies[ci].stage = "inserting";
        }
        self.base.ai();
        for &ci in &protected {
            self.base.companies[ci].stage = "active";
        }
    }
    pub(super) fn primary_reloading(&self, ci: usize) -> bool {
        let c = &self.base.companies[ci];
        if c.unit.role == "artillery" {
            let rows = self
                .vehicles
                .iter()
                .filter(|v| v.company == ci && v.active && v.hp > 0. && v.ammo > 0)
                .collect::<Vec<_>>();
            return !rows.is_empty()
                && rows.iter().all(|v| {
                    self.firearms
                        .get(&(v.id, model(c.unit.id, "howitzer").id))
                        .is_some_and(|s| s.reload_until > self.frame())
                });
        }
        let rows = c
            .bodies
            .iter()
            .filter_map(|id| {
                self.base
                    .body(*id)
                    .filter(|b| b.hp > 0. && b.active && b.ammo > 0)
                    .map(|_| *id)
            })
            .collect::<Vec<_>>();
        !rows.is_empty()
            && rows.iter().all(|id| {
                self.firearms
                    .get(&(*id, self.loadouts[id].weapon.id))
                    .is_some_and(|s| s.reload_until > self.frame())
            })
    }
    pub(super) fn refill_recovered_air(&mut self) {
        if self.frame() % 40 != 0 || self.base.land_complete() || self.base.posture == "withdraw" {
            return;
        }
        for ci in 0..self.base.companies.len() {
            let c = self.base.companies[ci].clone();
            if c.stage != "recovered"
                || c.unit.class != "air"
                || c.reserve == 0
                || self.frame() < c.next
                || (c.side == 0 && !self.base.auto)
            {
                continue;
            }
            let mut pool = c.reserve;
            for id in &c.bodies {
                let cap = self.loadouts[id].weapon.ammo_capacity;
                if let Some(b) = self.base.body_mut(*id) {
                    if b.hp > 0. {
                        let n = cap.saturating_sub(b.ammo).min(pool);
                        b.ammo += n;
                        pool -= n;
                    }
                }
                if let Some(a) = self.base.actors.iter_mut().find(|a| a.id == *id) {
                    a.fuel = 24000.;
                }
            }
            self.base.companies[ci].reserve = pool;
            let _ = self.base.deploy(ci, c.beach, None);
        }
    }
    pub(super) fn tick_firearms(&mut self) {
        let frame = self.frame();
        let mut rows = self
            .loadouts
            .iter()
            .map(|(&id, l)| (id, l.weapon))
            .collect::<Vec<_>>();
        rows.extend(self.secondary.iter().map(|(&id, s)| (id, s.weapon)));
        rows.extend(self.vehicles.iter().map(|v| {
            (
                v.id,
                model(
                    self.base.companies[v.company].unit.id,
                    vehicles::spec(self.base.companies[v.company].unit.id)
                        .unwrap()
                        .weapon,
                ),
            )
        }));
        rows.extend(self.aa_turrets.iter().map(|t| {
            (
                t.id,
                model(self.base.companies[t.company].unit.id, "aa_cannon"),
            )
        }));
        for (id, w) in rows {
            let total = self.firearm_total(id, w);
            self.firearms
                .entry((id, w.id))
                .or_insert_with(|| FireState::new(w, total))
                .advance(w, total, frame);
        }
    }
    pub(super) fn firearm_ready(&self, id: u32, w: &Weapon, total: u32, gate: u32) -> bool {
        !self.last_fire.get(&id).is_some_and(|f| *f == self.frame())
            && gate <= self.frame()
            && self
                .firearms
                .get(&(id, w.id))
                .map_or(total > 0, |s| s.ready(total, self.frame()))
    }
    pub(super) fn consume_shot(&mut self, id: u32, w: &Weapon, haste: f64) {
        let reload_scale = self
            .base
            .body(id)
            .and_then(|b| {
                self.base
                    .actors
                    .iter()
                    .find(|a| a.id == id)
                    .map(|a| (b.p, self.base.companies[a.company].side))
            })
            .or_else(|| {
                self.vehicles
                    .iter()
                    .find(|v| v.id == id)
                    .map(|v| (v.p, self.base.companies[v.company].side))
            })
            .map_or(1., |(p, side)| {
                if self.effects.iter().any(|e| {
                    e.kind == "supply_network"
                        && e.side == side
                        && e.end > self.frame()
                        && e.p.dist(p) < e.radius
                }) {
                    0.8
                } else {
                    1.
                }
            });
        let passive_rate = self.last_stand(id).1;
        let total_before = self.firearm_total(id, w);
        self.last_fire.insert(id, self.frame());
        let frame = self.frame();
        let state = self
            .firearms
            .entry((id, w.id))
            .or_insert_with(|| FireState::new(w, total_before));
        state.fired(w, total_before.saturating_sub(1), frame, haste);
        if passive_rate > 1. && state.reload_until > frame {
            state.reload_until = frame + ticks(w.cadence.magazine_reload_s, haste * passive_rate);
        }
        if state.reload_until > frame && reload_scale < 1. {
            self.metrics.insert("supply_network".into());
            state.reload_until = frame + ticks(w.cadence.magazine_reload_s, haste * passive_rate * reload_scale);
        }
        let next = state.next.max(state.reload_until);
        if let Some(v) = self.vehicles.iter_mut().find(|v| v.id == id) {
            v.ammo -= 1;
            v.next = next;
        } else if self.loadouts.get(&id).is_some_and(|l| l.weapon.id == w.id) {
            let b = self.base.body_mut(id).unwrap();
            b.ammo -= 1;
            b.next = next;
        } else if let Some(s) = self.secondary.get_mut(&id).filter(|s| s.weapon.id == w.id) {
            s.ammo -= 1;
            s.next = next;
        } else if let Some(b) = self.base.body_mut(id) {
            b.ammo -= 1;
            b.next = next;
        }
    }
    pub(super) fn firearm_view(&self, id: u32, w: &Weapon, total: u32, gate: u32) -> Value {
        self.firearms
            .get(&(id, w.id))
            .cloned()
            .unwrap_or_else(|| FireState::new(w, total))
            .view(total, self.frame(), gate)
    }
}
