use crate::{
    model::{Contact, Ship, Torpedo, CYCLE, LEGACY_VERSION, YARD},
    night::{self, Environment, WakePropulsion},
    world::{roll, seat_ids, World},
};

impl World {
    pub(crate) fn environment(&self) -> Environment {
        if self.variant == "night" || self.radar_enabled() || self.has_starshells() {
            Environment::NIGHT
        } else {
            Environment::DAY
        }
    }

    fn fired_this_turn(&self, ship: &Ship) -> bool {
        ship.gun_cycle == Some(self.tick / CYCLE) || ship.illumination_cycle == Some(self.tick/CYCLE)
    }

    fn night_range(&self, observer: &Ship, target: &Ship) -> u32 {
        let observer_def = &self.data.ships[observer.def];
        let target_def = &self.data.ships[target.def];
        night::surface_base_range_yd(
            self.environment(),
            &observer_def.size,
            &target_def.size,
            target.speed,
            target_def.gun.caliber_mm >= 75. && self.fired_this_turn(target),
            !target.fires.is_empty(),
        )
    }

    fn night_track_valid(&self, owner: usize, contact: &Contact) -> bool {
        let Some(target) = self.ship(contact.ship).filter(|t| t.alive()) else {
            return false;
        };
        self.ships
            .iter()
            .filter(|o| o.side == owner && o.alive())
            .any(|o| {
                let distance = o.p.dist(target.p) / YARD;
                distance < f64::from(night::automatic_visual_yd())
                    || (distance <= f64::from(contact.acquisition_range_yd)
                        && self.night_range(o, target) >= contact.acquisition_base_yd)
            })
    }

    pub(crate) fn update_night_tracks(&mut self) {
        for owner in 0..2 {
            let old = std::mem::take(&mut self.contacts[owner]);
            for mut contact in old {
                if self.night_track_valid(owner, &contact) {
                    let target = self.ship(contact.ship).unwrap();
                    (contact.x, contact.y, contact.heading, contact.speed) =
                        (target.p.x, target.p.y, target.h, target.speed);
                    self.contacts[owner].push(contact);
                } else {
                    self.add(
                        1 << owner,
                        "lost",
                        "丢失一个夜间水面接触".into(),
                        Some("CAS-5.4.1.1"),
                        None,
                    );
                }
            }
        }
    }

    pub(crate) fn detect_night(&mut self) {
        // One visual roll per enemy formation and observing seat per detection phase.
        for owner in 0..2 {
            let observers: Vec<_> = self
                .ships
                .iter()
                .filter(|o| o.side == owner && o.alive())
                .cloned()
                .collect();
            let targets: Vec<_> = self
                .ships
                .iter()
                .filter(|t| t.side != owner && t.alive() && !self.knows(owner, t.id))
                .cloned()
                .collect();
            let mut rolls = Vec::new();
            for target in targets {
                let group = (
                    target.fleet,
                    if target.fleet.is_none() { target.id } else { 0 },
                );
                let automatic = night::automatic_visual_yd();
                let cue = target.fleet.is_some_and(|fleet| {
                    self.contacts[owner]
                        .iter()
                        .any(|c| self.ship(c.ship).is_some_and(|v| v.fleet == Some(fleet)))
                });
                let mut acquisition = None;
                for o in &observers {
                    let distance = o.p.dist(target.p) / YARD;
                    let base = self.night_range(o, &target);
                    let limit = if distance < f64::from(automatic) {
                        automatic
                    } else if distance <= f64::from(base) {
                        let d = if let Some((_, d)) = rolls.iter().find(|(key, _)| *key == group) {
                            *d
                        } else {
                            let d = roll(&mut self.optics_rng, 100) as i32;
                            rolls.push((group, d));
                            d
                        };
                        night::surface_detection_range_yd(
                            base,
                            d + night::visual_d100_modifier(
                                self.environment(),
                                cue,
                                false,
                                self.fired_this_turn(o),
                            ),
                        )
                    } else {
                        continue;
                    };
                    if distance <= f64::from(limit)
                        && acquisition.is_none_or(|(b, r)| (limit, base) > (r, b))
                    {
                        acquisition = Some((base, limit));
                    }
                }
                let Some((base, range)) = acquisition else {
                    continue;
                };
                let id = format!("C{:02}", self.next_contacts[owner]);
                self.next_contacts[owner] += 1;
                self.add(
                    1 << owner,
                    "contact",
                    format!("发现夜间水面接触 {id}"),
                    Some("CAS-5.4.1.1"),
                    Some(target.p),
                );
                let def = &self.data.ships[target.def];
                self.contacts[owner].push(Contact {
                    id,
                    x: target.p.x,
                    y: target.p.y,
                    heading: target.h,
                    speed: target.speed,
                    kind: Some(def.kind.to_ascii_lowercase()),
                    name: Some(def.name.clone()),
                    ship: target.id,
                    first_cycle: self.tick / CYCLE,
                    acquisition_base_yd: base,
                    acquisition_range_yd: range,
                });
            }
        }
    }

    pub(crate) fn observe_torpedo_launch(&mut self, torpedo: &mut Torpedo) {
        if self.version == LEGACY_VERSION {
            return;
        }
        let owner = 1 - torpedo.side;
        let env = self.environment();
        let firing = self
            .ship(torpedo.ship)
            .is_some_and(|s| self.fired_this_turn(s));
        let chance = self
            .ships
            .iter()
            .filter(|o| o.side == owner && o.alive())
            .map(|o| {
                night::launch_sighting_chance(
                    env,
                    &self.data.ships[o.def].size,
                    o.p.dist(torpedo.p) / YARD,
                    true,
                    firing,
                    torpedo.count,
                )
            })
            .max()
            .unwrap_or(0);
        if chance > 0 && roll(&mut self.optics_rng, 100) <= chance {
            torpedo.launch_sighted = true;
            // A launch signature is not a confirmed wake or live track.
            self.add(
                1 << owner,
                "torpedo_detected",
                "瞭望报告鱼雷发射迹象，尚未确认尾迹".into(),
                Some("CAS-5.4.1.5"),
                None,
            );
        }
    }

    pub(crate) fn observe_torpedo_wake(&mut self, torpedo: &mut Torpedo) {
        if self.version == LEGACY_VERSION {
            return;
        }
        let owner = 1 - torpedo.side;
        let env = self.environment();
        let chance = self
            .ships
            .iter()
            .filter(|o| o.side == owner && o.alive())
            .map(|o| {
                night::wake_sighting_chance(
                    env,
                    &self.data.ships[o.def].size,
                    o.p.dist(torpedo.p) / YARD,
                    WakePropulsion::Unspecified,
                    torpedo.launch_sighted,
                    torpedo.impact_sighted,
                )
            })
            .max()
            .unwrap_or(0);
        if chance == 0 {
            torpedo.view_ids[owner] = None;
        } else if self.tick % CYCLE == 0
            && torpedo.view_ids[owner].is_none()
            && roll(&mut self.optics_rng, 100) <= chance
        {
            torpedo.view_ids[owner] = seat_ids(1 << owner, &mut self.torp_ids)[owner];
            self.add(
                1 << owner,
                "torpedo_detected",
                "发现来袭鱼雷尾迹".into(),
                Some("CAS-5.4.1.6"),
                Some(torpedo.p),
            );
            if let Some(o) = self
                .ships
                .iter()
                .filter(|o| o.side == owner && o.alive())
                .min_by(|a, b| a.p.dist(torpedo.p).total_cmp(&b.p.dist(torpedo.p)))
            {
                let rel = crate::model::delta(o.h, (torpedo.p - o.p).heading());
                let cue = if rel.abs() <= 45. {
                    "torpedo_warning"
                } else if rel.abs() >= 135. {
                    "torpedo_warning_back"
                } else if rel > 0. {
                    "torpedo_warning_right"
                } else {
                    "torpedo_warning_left"
                };
                self.last_voice(owner, Some(cue));
            }
        }
    }
}
