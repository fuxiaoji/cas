use crate::{
    model::{Casualty, Ship, CYCLE},
    world::World,
};
use serde_json::Value;

const INTERMEDIATE: u32 = 1_800;
const FIRST_CONTROL: u32 = 3 * CYCLE;

fn ratio_row(ratio: f64) -> usize {
    (ratio.min(1.) * 10. + 1e-9).floor() as usize
}

fn severity_column(size: &str, year: u32, percentage: f64) -> usize {
    let base = if size == "B" {
        [10, 15, 17]
    } else {
        [8, 12, 14]
    };
    let age = if year <= 1924 {
        -1
    } else if year >= 1942 {
        1
    } else {
        0
    };
    base.iter()
        .position(|&ceiling| percentage <= (ceiling + age) as f64 + 1e-9)
        .unwrap_or(3)
}

fn roll_index(v: &Value, row: usize, die: u32) -> i32 {
    v[row][(die - 1) as usize].as_i64().unwrap_or(0) as i32
}

fn reduction_dice(v: &Value, die: u32, level: usize) -> i32 {
    v[(die - 1) as usize][level].as_i64().unwrap_or(0) as i32
}

fn damage_due(casualties: &mut [Casualty], tick: u32) -> f64 {
    casualties
        .iter_mut()
        .filter(|c| c.next_damage <= tick)
        .map(|c| {
            c.next_damage += INTERMEDIATE;
            (c.amount + 1e-9).floor()
        })
        .sum()
}

fn control_due(casualties: &mut [Casualty], tick: u32) -> bool {
    let mut due = false;
    for c in casualties.iter_mut().filter(|c| c.next_control <= tick) {
        c.next_control += INTERMEDIATE;
        due = true;
    }
    due
}

fn adjust_casualties(casualties: &mut Vec<Casualty>, delta: f64) {
    // CAS supplies a change to the total per category. Apply reductions to the oldest
    // casualties first so their separate damage clocks do not depend on map iteration.
    if delta < 0. {
        let mut left = -delta;
        for c in casualties.iter_mut() {
            let cut = left.min(c.amount);
            c.amount -= cut;
            left -= cut;
            if left <= 1e-9 {
                break;
            }
        }
        casualties.retain(|c| c.amount > 1e-9);
    } else if let Some(oldest) = casualties.first_mut() {
        oldest.amount += delta;
    }
}

impl World {
    pub(crate) fn flooding_speed_limit(&self, ship: &Ship) -> f64 {
        let def = &self.data.ships[ship.def];
        let flooding = ship.flooding.iter().map(|c| c.amount).sum::<f64>() * 100. / def.dp;
        if severity_column(&def.size, def.in_service_year, flooding) >= 1 {
            15.
        } else {
            f64::INFINITY
        }
    }

    pub(crate) fn critical_phase(
        &mut self,
        victim: u32,
        phase_dp: f64,
        torpedo: bool,
        penetrated: bool,
    ) {
        self.critical_phase_fraction(victim, phase_dp, torpedo, if penetrated { 1. } else { 0. });
    }

    pub(crate) fn critical_phase_fraction(
        &mut self,
        victim: u32,
        phase_dp: f64,
        torpedo: bool,
        penetrating_fraction: f64,
    ) {
        let Some(s) = self.ship(victim).filter(|s| s.alive()) else {
            return;
        };
        let def = &self.data.ships[s.def];
        let minimum = self.data.rules["critical_damage_min_ratio"]
            .as_f64()
            .unwrap_or(0.01);
        if phase_dp < def.dp * minimum {
            return;
        }
        let ratio = phase_dp / s.hp;
        if ratio >= 3. {
            // A high ratio uses the massive-damage rule rather than an extrapolated roll.
            let max_remaining = def.dp * 0.10;
            let s = self.ship_mut(victim).unwrap();
            s.hp = s.hp.min(max_remaining);
            self.damage_message(victim, "船体遭受重大损伤，武器失效".into(), "CAS-8.1.10");
            return;
        }
        let column = if torpedo {
            "underwater"
        } else if def.size == "B" {
            "major_surface"
        } else {
            "minor_surface"
        };
        let die = self.d(6);
        let count = roll_index(
            &self.data.rules["critical_damage_ratio_d6"],
            ratio_row(ratio),
            die,
        ) + (((ratio - 1.).max(0.) / 0.2) + 1e-9).floor() as i32;
        let penetrations = (count as f64 * penetrating_fraction.clamp(0., 1.)).round() as i32;
        for i in 0..count {
            if !self.ship(victim).is_some_and(|s| s.alive()) {
                break;
            }
            let die = self.d(20) as usize;
            let Some(kind) = self.data.rules["critical_hit_d20"][column][die - 1]
                .as_str()
                .map(str::to_owned)
            else {
                continue;
            };
            let penetrated = i < penetrations;
            let name = kind.trim_end_matches('*');
            if name == "main_battery" {
                // A director hit explicitly does not require penetration (§8.3).
                self.main_battery_critical(victim, penetrated || !kind.ends_with('*'));
                continue;
            }
            if kind.ends_with('*') && !penetrated {
                continue;
            } // Becomes light AA: out of this scenario.
            match name {
                "fire" => self.add_casualty(victim, false, false, penetrated, 0, false),
                "flooding" => self.add_casualty(victim, true, torpedo, penetrated, 0, false),
                "engineering" => self.engineering_critical(victim, penetrated),
                "sensor_comms" => self.radar_sensor_critical(victim),
                // Systems below are identified by the source table but have no effect
                // in this subset. No placeholder penalty is imposed on other systems.
                _ => (),
            }
        }
    }

    pub(crate) fn torpedo_automatic_flooding(&mut self, victim: u32, hits: u32, penetrated: bool) {
        for _ in 0..hits {
            if !self.ship(victim).is_some_and(|s| s.alive()) {
                break;
            }
            self.add_casualty(victim, true, true, penetrated, 0, false);
        }
    }

    fn add_casualty(
        &mut self,
        victim: u32,
        flood: bool,
        immediate: bool,
        penetrated: bool,
        modifier: i32,
        half: bool,
    ) {
        let Some(s) = self.ship(victim).filter(|s| s.alive()) else {
            return;
        };
        let (dp, year) = {
            let d = &self.data.ships[s.def];
            (d.dp, d.in_service_year)
        };
        let entry =
            &self.data.rules["flooding_severity"][if year <= 1924 { "1924" } else { "1925" }];
        let dice = entry["dice"].as_u64().unwrap_or(1);
        let bonus = entry["bonus"].as_i64().unwrap_or(0) as i32;
        let mut percentage = bonus + modifier + (0..dice).map(|_| self.d(6) as i32).sum::<i32>();
        if !penetrated {
            percentage /= 2;
        }
        if half {
            percentage /= 2;
        }
        if percentage <= 0 {
            return;
        }
        let amount = dp * percentage as f64 / 100.;
        let next_control = self.tick.div_ceil(CYCLE) * CYCLE + FIRST_CONTROL;
        let next_damage = if immediate {
            // The first flood damage from a torpedo is applied now, and future damage
            // uses the intermediate clock. Damage control still starts on the third turn.
            self.tick + INTERMEDIATE
        } else {
            next_control
        };
        let casualty = Casualty {
            next_damage,
            next_control,
            amount,
        };
        let s = self.ship_mut(victim).unwrap();
        let side = s.side;
        if flood {
            s.flooding.push(casualty);
        } else {
            s.fires.push(casualty);
        }
        let label = if flood { "进水" } else { "起火" };
        self.damage_message(victim, format!("{label} · 严重度 {percentage}%"), "CAS-8.2");
        if !flood {
            self.last_voice(side, Some("fire"));
        }
        if immediate {
            self.secondary_loss(victim, (amount + 1e-9).floor(), "鱼雷进水");
        }
    }

    fn main_battery_critical(&mut self, victim: u32, penetrated: bool) {
        let result = self.d(10);
        if result <= 2 {
            self.ship_mut(victim).unwrap().fire_control_damage = true;
            self.damage_message(
                victim,
                "主炮射击指挥仪失效，剩余炮位改用本地瞄准".into(),
                "CAS-8.3",
            );
            return;
        }
        if !penetrated {
            return;
        }
        if self.d(10) == 10 {
            self.damage_message(victim, "主炮弹药库爆炸".into(), "CAS-8.3");
            self.ship_mut(victim).unwrap().hp = 0.;
            self.sank(victim);
            return;
        }
        let count = self.ship(victim).unwrap().gun_mount_destroyed.len() as u32;
        if count > 0 {
            let mount = (self.d(count) - 1) as usize;
            let disabled = &mut self.ship_mut(victim).unwrap().gun_mount_destroyed[mount];
            if !*disabled {
                *disabled = true;
                self.damage_message(victim, format!("主炮座 {} 失效", mount + 1), "CAS-8.3");
            }
        }
    }

    fn engineering_critical(&mut self, victim: u32, penetrated: bool) {
        let explosion = self.d(10) == 10;
        let def = &self.data.ships[self.ship(victim).unwrap().def];
        let multiplier = usize::from(def.engineering_speed_multiplier.unwrap_or(1));
        self.ship_mut(victim).unwrap().engineering_speed_levels += multiplier * if explosion { 2 } else { 1 };
        self.damage_message(victim, "轮机受损，降低最大航速".into(), "CAS-8.3");
        if explosion {
            let dp = self.data.ships[self.ship(victim).unwrap().def].dp;
            self.secondary_loss(victim, (dp * 0.15).floor(), "锅炉爆炸");
        }
        if self.ship(victim).is_some_and(|s| s.alive()) {
            self.add_casualty(victim, false, false, penetrated, 0, !explosion);
        }
    }

    pub(crate) fn resolve_damage_control(&mut self) {
        let tick = self.tick;
        for index in 0..self.ships.len() {
            let s = &mut self.ships[index];
            if !s.alive() {
                continue;
            }
            let def = &self.data.ships[s.def];
            let (id, dp) = (s.id, def.dp);
            let fire_due = control_due(&mut s.fires, tick);
            let flood_due = control_due(&mut s.flooding, tick);
            // Each category gets one roll. Both use the pre-control combined severity.
            let burden = s
                .fires
                .iter()
                .chain(&s.flooding)
                .map(|c| c.amount)
                .sum::<f64>()
                * 100.
                / dp;
            let level = severity_column(&def.size, def.in_service_year, burden);
            let fire_dp = damage_due(&mut s.fires, tick);
            let flood_dp = damage_due(&mut s.flooding, tick);
            if fire_dp + flood_dp > 0. {
                self.secondary_loss(id, fire_dp + flood_dp, "火灾／进水");
                self.critical_phase(id, fire_dp + flood_dp, false, true);
            }
            if !self.ship(id).is_some_and(|s| s.alive()) {
                continue;
            }
            if fire_due {
                self.damage_control_roll(id, false, level, dp);
            }
            if flood_due {
                self.damage_control_roll(id, true, level, dp);
            }
        }
    }

    fn damage_control_roll(&mut self, id: u32, flood: bool, level: usize, dp: f64) {
        let die = self.d(10);
        let dice = reduction_dice(&self.data.rules["damage_control_d6"], die, level);
        let percentage = (0..dice.unsigned_abs())
            .map(|_| self.d(6) as i32)
            .sum::<i32>()
            * dice.signum();
        let s = self.ship_mut(id).unwrap();
        adjust_casualties(
            if flood { &mut s.flooding } else { &mut s.fires },
            dp * percentage as f64 / 100.,
        );
        if percentage != 0 {
            self.damage_message(
                id,
                format!(
                    "{}损管 · 严重度 {percentage:+}%",
                    if flood { "进水" } else { "火灾" }
                ),
                "CAS-8.2",
            );
        }
    }

    fn damage_message(&mut self, victim: u32, text: String, rule: &'static str) {
        let Some(s) = self.ship(victim) else { return };
        self.add(
            1 << s.side,
            "critical",
            format!("{} · {text}", s.name),
            Some(rule),
            Some(s.p),
        );
    }

    fn secondary_loss(&mut self, victim: u32, amount: f64, cause: &str) {
        let Some(s) = self.ship_mut(victim).filter(|s| s.alive()) else {
            return;
        };
        s.hp = (s.hp - amount).max(0.);
        let sunk = !s.alive();
        self.damage_message(victim, format!("{cause} · 损失 {amount:.0} DP"), "CAS-8.2");
        if sunk {
            self.sank(victim);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn home_fleet_jk_engineering_critical_doubles_speed_steps_only() {
        use crate::campaign::live::Start;
        let mut w = World::new_campaign(53, Start::new("CAMP-ALLIES-01", "story"), "coord").unwrap();
        for (id, step_loss, speed) in [(4, 2, 18.), (1, 1, 29.)] {
            w.rng = 1; // D10 = 2; no boiler explosion.
            let full = w.ship(id).unwrap().hp;
            w.engineering_critical(id, true);
            let ship = w.ship(id).unwrap();
            assert_eq!(ship.engineering_speed_levels, step_loss);
            assert_eq!(w.max_speed(ship), speed);
            assert_eq!(ship.hp, full);
        }
        let explosion_seed = (1..100).find(|seed| {
            w.rng = *seed;
            w.d(10) == 10
        }).unwrap();
        w.rng = explosion_seed;
        w.engineering_critical(5, true);
        let ship = w.ship(5).unwrap();
        assert_eq!(ship.engineering_speed_levels, 4);
        assert_eq!(ship.hp, 121. - (121_f64 * 0.15).floor());
    }

    #[test]
    fn fletcher_printed_damage_ratio_and_age_thresholds() {
        assert_eq!(ratio_row(22. / (144. - 22.)), 1);
        assert_eq!(ratio_row(0.10), 1);
        assert_eq!(ratio_row(0.099_999), 0);
        assert_eq!(severity_column("B", 1920, 9.), 0);
        assert_eq!(severity_column("B", 1920, 10.), 1);
        assert_eq!(severity_column("B", 1920, 17.), 3);
        assert_eq!(severity_column("C", 1942, 9.), 0);
        assert_eq!(severity_column("C", 1942, 16.), 3);
    }

    #[test]
    fn recurring_damage_and_control_have_independent_clocks() {
        let mut casualties = [Casualty {
            next_damage: 1800,
            next_control: 540,
            amount: 26.31,
        }];
        assert_eq!(damage_due(&mut casualties, 540), 0.);
        assert!(control_due(&mut casualties, 540));
        assert_eq!(damage_due(&mut casualties, 1800), 26.);
        assert_eq!(damage_due(&mut casualties, 1800), 0.);
        assert!(control_due(&mut casualties, 2340));
        assert_eq!(damage_due(&mut casualties, 3600), 26.);
    }

    #[test]
    fn torpedo_impact_damages_immediately_without_charging_again_at_first_control() {
        let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
        w.rng = 1; // First D6 is 4; Fletcher loses floor(144 * 4%).
        w.tick = 71;
        w.torpedo_automatic_flooding(1, 1, true);
        let s = w.ship(1).unwrap();
        assert_eq!(s.hp, 139.);
        assert_eq!(s.flooding[0].next_control, 720);
        assert_eq!(s.flooding[0].next_damage, 1871);
        w.tick = 720;
        w.resolve_damage_control();
        assert_eq!(w.ship(1).unwrap().hp, 139.);
    }

    #[test]
    fn flooding_cap_is_based_on_floods_alone() {
        let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
        let nine_percent = 144. * 0.09;
        let s = w.ship_mut(1).unwrap();
        let c = Casualty {
            next_damage: 540,
            next_control: 540,
            amount: nine_percent,
        };
        s.flooding.push(c.clone());
        s.fires.push(c);
        assert_eq!(w.flooding_speed_limit(w.ship(1).unwrap()), f64::INFINITY);
        w.ship_mut(1).unwrap().flooding[0].amount = 144. * 0.10;
        assert_eq!(w.flooding_speed_limit(w.ship(1).unwrap()), 15.);
    }

    #[test]
    fn nonpenetrating_hit_can_break_director_but_not_destroy_turret() {
        let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
        w.rng = 1; // D10 = 2: the director is exposed even when armor holds.
        w.main_battery_critical(1, false);
        assert!(w.ship(1).unwrap().fire_control_damage);
        assert!(w.ship(1).unwrap().gun_mount_destroyed.iter().all(|&v| !v));
        w.rng = 3; // D10 = 4, D10 = 9, D5 = 4: turret 4, no magazine explosion.
        w.main_battery_critical(1, false);
        assert!(w.ship(1).unwrap().gun_mount_destroyed.iter().all(|&v| !v));
        w.rng = 3;
        w.main_battery_critical(1, true);
        assert_eq!(
            w.ship(1).unwrap().gun_mount_destroyed,
            [false, false, false, true, false]
        );
    }
}
