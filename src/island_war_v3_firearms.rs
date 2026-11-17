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
            "../docs/design/tactical-v3-weapon-models.json"
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
        let total_before = self.firearm_total(id, w);
        self.last_fire.insert(id, self.frame());
        let frame = self.frame();
        let state = self
            .firearms
            .entry((id, w.id))
            .or_insert_with(|| FireState::new(w, total_before));
        state.fired(w, total_before.saturating_sub(1), frame, haste);
        if state.reload_until > frame && reload_scale < 1. {
            self.metrics.insert("supply_network".into());
            state.reload_until = frame + ticks(w.cadence.magazine_reload_s, haste * reload_scale);
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
#[cfg(test)]
mod tests {
    use super::*;
    fn battle(id: &str) -> (Battle, usize, P) {
        let fixture: Value = serde_json::from_str(include_str!(
            "../artifacts/island-war-v2/core/exercise-terminal.json"
        ))
        .unwrap();
        let mut q = fixture["initial_request"].clone();
        q["roster"] = json!([id]);
        q["defender"]["roster"] = json!(["MCP-034"]);
        for k in ["op", "version", "seed"] {
            q.as_object_mut().unwrap().remove(k);
        }
        let mut b = Battle::new(714, q).unwrap();
        let ci = b.base.companies.iter().position(|c| c.side == 0).unwrap();
        let p = b.base.free_spawn(b.base.objective(), "infantry").unwrap();
        b.base.companies[ci].p = p;
        b.base.companies[ci].stage = "active";
        for a in &mut b.base.actors {
            a.seen = [true, true];
        }
        for body in &mut b.base.base.core.ground.bodies {
            body.active = false;
        }
        let own = b.base.companies[ci].bodies[0];
        let body = b.base.body_mut(own).unwrap();
        body.p = p;
        body.active = true;
        body.next = 0;
        (b, ci, p)
    }
    #[test]
    fn models_are_distinct_complete_and_actual_clock_budgets_are_bounded() {
        let mut keys = BTreeSet::new();
        for w in models() {
            assert!(keys.insert(w.id));
            assert!(w.owner.is_some());
            for t in [
                w.cadence.fire_interval_s,
                w.cadence.burst_interval_s,
                w.cadence.magazine_reload_s,
            ] {
                assert!(
                    (t * 10. - (t * 10.).round()).abs() < 1e-6,
                    "{} has unsupported sub-frame authored timing",
                    w.id
                );
            }
            assert!(
                w.cadence.magazine_capacity > 0 && w.cadence.magazine_capacity <= w.ammo_capacity
            );
            assert!(matches!(
                w.cadence.fire_mode,
                "single" | "burst" | "automatic"
            ));
            if w.cadence.fire_mode == "single" {
                assert_eq!(w.cadence.burst_size, 1);
                assert_eq!(w.cadence.burst_interval_s, w.cadence.fire_interval_s);
            }
            let base = weapon(w.family_id);
            let mut state = FireState::new(w, w.ammo_capacity);
            let mut total = w.ammo_capacity;
            let mut shots = 0;
            let mut last = 0;
            for frame in 0..200000 {
                state.advance(w, total, frame);
                if state.ready(total, frame) {
                    total -= 1;
                    shots += 1;
                    last = frame;
                    state.fired(w, total, frame, 1.);
                }
                if total == 0 {
                    break;
                }
            }
            assert_eq!(
                shots, w.ammo_capacity,
                "every actual projectile consumes exactly one round"
            );
            let sustained =
                shots.saturating_sub(1) as f64 * w.damage / (last as f64 / 10.).max(0.1);
            let ratio = sustained / (base.damage / base.reload_s);
            assert!(
                (0.78..=1.24).contains(&ratio),
                "{} simulated sustained ratio {}",
                w.id,
                ratio
            );
            let potential =
                w.ammo_capacity as f64 * w.damage / (base.ammo_capacity as f64 * base.damage);
            assert!(
                (0.8..=1.2).contains(&potential),
                "{} total damage budget",
                w.id
            );
        }
        for u in PROFILES {
            for k in 0..u.people as usize {
                let (f, _) = loadout(&u, k);
                assert_eq!(model(u.id, f).owner, Some(u.id));
            }
        }
        let dmr = [
            model("MCP-018", "dmr"),
            model("MCP-128", "dmr"),
            model("MCP-203", "dmr"),
        ];
        assert!(dmr[0].id != dmr[1].id && dmr[1].id != dmr[2].id);
        assert!(dmr[0].damage != dmr[1].damage || dmr[0].range_m != dmr[1].range_m);
    }
    #[test]
    fn smg_bursts_dmr_taps_and_empty_magazine_reloads_without_creating_rounds() {
        for (unit, family) in [("MCP-011", "smg"), ("MCP-203", "dmr")] {
            let w = model(unit, family);
            let mut total = w.ammo_capacity;
            let mut state = FireState::new(w, total);
            let mut frames = vec![];
            let mut saw_reload = false;
            for frame in 0..2000 {
                state.advance(w, total, frame);
                assert_eq!(
                    state.view(total, frame, 0)["magazine_ammo"]
                        .as_u64()
                        .unwrap()
                        + state.view(total, frame, 0)["reserve_ammo"]
                            .as_u64()
                            .unwrap(),
                    total as u64
                );
                if state.reload_until > frame {
                    saw_reload = true;
                    assert!(!state.ready(total, frame));
                }
                if state.ready(total, frame) {
                    total -= 1;
                    frames.push(frame);
                    state.fired(w, total, frame, 1.);
                }
            }
            assert!(saw_reload);
            assert_eq!(total + frames.len() as u32, w.ammo_capacity);
            if family == "smg" {
                assert_eq!(&frames[..3], &[0, 1, 2]);
                assert!(frames[3] - frames[2] > 1);
            } else {
                assert!(frames.windows(2).all(|f| f[1] - f[0] >= 10));
            }
        }
    }
    #[test]
    fn live_shooting_emits_each_burst_round_and_obeys_magazine_timer() {
        let (mut b, ci, p) = battle("MCP-011");
        let id = b.base.companies[ci].bodies[0];
        let enemy = b
            .base
            .companies
            .iter()
            .find(|c| c.side == 1)
            .unwrap()
            .bodies[0];
        {
            let e = b.base.body_mut(enemy).unwrap();
            e.active = true;
            e.p = p + P { x: 40., y: 0. };
            e.hp = 10000.;
        }
        let w = b.loadouts[&id].weapon;
        let initial = b.base.body(id).unwrap().ammo;
        let mut shots = vec![];
        for frame in 0..500 {
            b.base.base.core.ground.frame = frame;
            b.tick_firearms();
            let before = b.base.body(id).unwrap().ammo;
            b.shoot();
            if b.base.body(id).unwrap().ammo < before {
                shots.push(frame);
            }
            let state = b.firearms.get(&(id, w.id)).unwrap();
            if state.reload_until > frame {
                assert_eq!(
                    b.base.body(id).unwrap().ammo,
                    before.saturating_sub(u32::from(shots.last() == Some(&frame)))
                );
            }
            b.projectiles();
        }
        assert_eq!(&shots[..3], &[0, 1, 2]);
        assert_eq!(initial - b.base.body(id).unwrap().ammo, shots.len() as u32);
        assert!(b
            .base
            .base
            .core
            .ground
            .shots
            .iter()
            .any(|s| s["weapon_id"] == w.id && s["weapon_family_id"] == "smg"));
    }
    #[test]
    fn active_rocket_skill_uses_one_round_and_cannot_bypass_empty_or_reload() {
        let (mut b, ci, p) = battle("MCP-063");
        let id = b.base.companies[ci].bodies[0];
        let w = b.loadouts[&id].weapon;
        b.base.body_mut(id).unwrap().ammo = 2;
        b.firearms.insert((id, w.id), FireState::new(w, 2));
        b.role_skill(ci, p).unwrap();
        assert_eq!(b.base.body(id).unwrap().ammo, 1);
        assert_eq!(b.base.companies[ci].charges, 2);
        b.base.companies[ci].next = 0;
        let charges = b.base.companies[ci].charges;
        assert!(b.role_skill(ci, p).is_err());
        assert_eq!(b.base.body(id).unwrap().ammo, 1);
        assert_eq!(b.base.companies[ci].charges, charges);
        b.base.base.core.ground.frame = 200;
        b.tick_firearms();
        b.role_skill(ci, p).unwrap();
        assert_eq!(b.base.body(id).unwrap().ammo, 0);
        b.base.companies[ci].next = 0;
        b.base.base.core.ground.frame = 400;
        b.tick_firearms();
        assert!(b.role_skill(ci, p).is_err());
    }
    #[test]
    fn supply_buff_changes_reload_without_transferring_or_generating_rounds() {
        let (mut b, ci, p) = battle("MCP-116");
        let friend = b
            .base
            .companies
            .iter()
            .enumerate()
            .find(|(i, c)| *i != ci && c.side == 0)
            .unwrap()
            .0;
        let id = b.base.companies[friend].bodies[0];
        let w = b.loadouts[&id].weapon;
        b.base.body_mut(id).unwrap().active = true;
        b.base.body_mut(id).unwrap().p = p;
        let total = b.base.body(id).unwrap().ammo;
        let all_before = b
            .base
            .base
            .core
            .ground
            .bodies
            .iter()
            .map(|b| b.ammo)
            .sum::<u32>();
        b.role_skill(ci, p).unwrap();
        assert_eq!(
            all_before,
            b.base
                .base
                .core
                .ground
                .bodies
                .iter()
                .map(|b| b.ammo)
                .sum::<u32>()
        );
        assert_eq!(b.base.companies[ci].reserve, 0);
        b.firearms.insert(
            (id, w.id),
            FireState {
                magazine: 1,
                reload_until: 0,
                next: 0,
                burst_left: 0,
            },
        );
        b.consume_shot(id, w, 1.);
        assert_eq!(b.base.body(id).unwrap().ammo, total - 1);
        assert_eq!(
            b.firearms[&(id, w.id)].reload_until - b.frame(),
            ticks(w.cadence.magazine_reload_s, 0.8)
        );
        assert!(b.metrics.contains("supply_network"));
    }
    #[test]
    fn sidearm_and_vehicle_magazines_are_separate_finite_real_streams() {
        let (mut b, ci, _) = battle("MCP-063");
        let id = b.base.companies[ci].bodies[0];
        let primary = b.loadouts[&id].weapon;
        let side = b.secondary[&id].weapon;
        b.consume_shot(id, primary, 1.);
        let main = b.base.body(id).unwrap().ammo;
        assert!(!b.firearm_ready(id, primary, main, b.base.body(id).unwrap().next));
        assert!(
            !b.firearm_ready(id, side, b.secondary[&id].ammo, 0),
            "one body cannot fire a second weapon in the same frame"
        );
        b.base.base.core.ground.frame += 1;
        let pistol = b.secondary[&id].ammo;
        b.consume_shot(id, side, 1.);
        assert_eq!(b.secondary[&id].ammo, pistol - 1);
        assert_eq!(b.base.body(id).unwrap().ammo, main);
        let (mut a, aci, _) = battle("MCP-087");
        let vi = a.vehicles.iter().position(|v| v.company == aci).unwrap();
        let vid = a.vehicles[vi].id;
        let operator = a.vehicles[vi].operator;
        let w = model("MCP-087", "howitzer");
        let initial = a.vehicles[vi].ammo;
        let body_ammo = a.base.body(operator).unwrap().ammo;
        for n in 0..3 {
            a.base.base.core.ground.frame = n * 80;
            a.tick_firearms();
            assert!(a.firearm_ready(vid, w, a.vehicles[vi].ammo, a.vehicles[vi].next));
            a.consume_shot(vid, w, 1.);
        }
        assert_eq!(a.vehicles[vi].ammo, initial - 3);
        assert_eq!(a.base.body(operator).unwrap().ammo, body_ammo);
        assert!(!a.firearm_ready(vid, w, a.vehicles[vi].ammo, 0));
        assert_eq!(a.firearms[&(vid, w.id)].magazine, 0);
    }
    #[test]
    fn actual_battle_save_and_replay_restore_magazines_bursts_and_reload() {
        let doc: Value =
            serde_json::from_str(include_str!("../godot/data/tactical-training-v3.json")).unwrap();
        let (seed, config) = Battle::decode(doc["lessons"]["weapons"]["request"].clone()).unwrap();
        let mut b = Battle::new(seed, config).unwrap();
        b.execute(&json!({"op":"island_autonomy","enabled":true}))
            .unwrap();
        let mut found = false;
        for _ in 0..70 {
            b.execute(&json!({"op":"step","seconds":1})).unwrap();
            if b.firearms.values().any(|s| s.reload_until > b.frame()) {
                found = true;
                break;
            }
        }
        assert!(found, "a real combat reload must exist before save");
        let saved = b.save();
        let mut loaded = Battle::from_save(saved.clone(), None).unwrap();
        assert_eq!(b.view(), loaded.view());
        b.execute(&json!({"op":"step","seconds":3})).unwrap();
        loaded.execute(&json!({"op":"step","seconds":3})).unwrap();
        assert_eq!(b.view(), loaded.view());
        let mut replay = Replay::open(saved.clone(), saved.frame).unwrap();
        assert_eq!(
            replay.battle.view(),
            Battle::from_save(saved, None).unwrap().view()
        );
        let _ = &mut replay;
    }
    #[test]
    fn auxiliary_ammo_not_dead_primary_rounds_drives_v3_withdrawal() {
        let (mut b, ci, _) = battle("MCP-063");
        b.base.auto = true;
        b.base.base.core.ground.frame = 40;
        for id in b.base.companies[ci].bodies.clone() {
            let body = b.base.body_mut(id).unwrap();
            body.active = true;
            body.ammo = 0;
        }
        let charges = b
            .base
            .companies
            .iter()
            .map(|c| c.charges)
            .collect::<Vec<_>>();
        b.base_ai_v3(&charges);
        assert_eq!(
            b.base.companies[ci].stage, "active",
            "live sidearm ammo prevents erroneous retreat"
        );
        for s in b.secondary.values_mut() {
            s.ammo = 0;
        }
        let dead = b.base.companies[ci].bodies[1];
        b.base.body_mut(dead).unwrap().hp = 0.;
        b.base.body_mut(dead).unwrap().ammo = 50;
        b.base_ai_v3(&charges);
        assert_eq!(
            b.base.companies[ci].order, "extract",
            "dead shooter's rounds cannot keep the living empty company in combat"
        );
        let (mut supply, sci, _) = battle("MCP-116");
        supply.base.auto = true;
        supply.base.base.core.ground.frame = 40;
        for id in supply.base.companies[sci].bodies.clone() {
            let body = supply.base.body_mut(id).unwrap();
            body.active = true;
            body.ammo = 0;
        }
        supply.base.companies[sci].reserve = 10;
        supply.base.companies[sci].charges = 0;
        let charges = supply
            .base
            .companies
            .iter()
            .map(|c| c.charges)
            .collect::<Vec<_>>();
        supply.base_ai_v3(&charges);
        assert_eq!(
            supply.base.companies[sci].order, "extract",
            "exhausted supply skills cannot prevent empty retreat"
        );
        let (mut artillery, aci, _) = battle("MCP-087");
        artillery.base.auto = true;
        artillery.base.base.core.ground.frame = 40;
        for v in &mut artillery.vehicles {
            if v.company == aci {
                v.ammo = 0;
            }
        }
        let charges = artillery
            .base
            .companies
            .iter()
            .map(|c| c.charges)
            .collect::<Vec<_>>();
        artillery.base_ai_v3(&charges);
        assert_eq!(
            artillery.base.companies[aci].order, "extract",
            "empty main gun must not loiter at 1100m because guards still carry pistols"
        );
    }
    #[test]
    fn reloading_main_weapons_hold_instead_of_advancing_into_known_fire() {
        let (mut b, ci, p) = battle("MCP-011");
        b.base.auto = true;
        b.base.base.core.ground.frame = 40;
        let id = b.base.companies[ci].bodies[0];
        let w = b.loadouts[&id].weapon;
        let state = b.firearms.get_mut(&(id, w.id)).unwrap();
        state.magazine = 0;
        state.reload_until = 60;
        let enemy = b
            .base
            .companies
            .iter()
            .find(|c| c.side == 1)
            .unwrap()
            .bodies[0];
        let body = b.base.body_mut(enemy).unwrap();
        body.active = true;
        body.p = p + P { x: 250., y: 0. };
        b.roles_ai();
        assert_eq!(b.base.companies[ci].order, "reload_hold");
        assert!(b.base.companies[ci].goal.dist(p) < 0.01);
    }
    #[test]
    fn zero_ammo_supply_stays_only_with_real_support_target_and_charges(){
        let (mut b,ci,p)=battle("MCP-116");b.base.auto=true;b.base.base.core.ground.frame=40;
        for id in b.base.companies[ci].bodies.clone(){let body=b.base.body_mut(id).unwrap();body.active=true;body.ammo=0;}
        let fi=b.base.companies.iter().enumerate().find(|(i,c)|*i!=ci&&c.side==0).unwrap().0;
        let friend=b.base.companies[fi].bodies[0];b.base.body_mut(friend).unwrap().active=true;b.base.body_mut(friend).unwrap().p=p+P{x:40.,y:0.};
        let charges=b.base.companies.iter().map(|c|c.charges).collect::<Vec<_>>();
        assert!(b.supply_target(ci));b.base_ai_v3(&charges);assert_eq!(b.base.companies[ci].stage,"active");
        for (i,c) in b.base.companies.clone().into_iter().enumerate(){if c.side==0&&i!=ci{for id in c.bodies{b.base.body_mut(id).unwrap().active=false;}}}
        assert!(!b.supply_target(ci));b.base_ai_v3(&charges);assert_eq!(b.base.companies[ci].order,"extract");
    }
}
