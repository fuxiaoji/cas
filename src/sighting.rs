use crate::{
    model::{Contact, Ship, Torpedo, CYCLE, LEGACY_VERSION, YARD},
    night::{self, Environment, WakePropulsion},
    world::{roll, seat_ids, World},
};

impl World {
    pub(crate) fn environment(&self) -> Environment {
        if self.variant == crate::campaign::channel::VARIANT {
            crate::campaign::channel::ENVIRONMENT
        } else if self.variant == crate::campaign::kula::VARIANT {
            crate::campaign::kula::ENVIRONMENT
        } else if self.campaign.is_some() {
            crate::campaign::live::environment()
        } else if self.variant == "night" || self.radar_enabled() || self.has_starshells() {
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

    /// cas-realtime-v10: per-second acquisition. The printed per-phase chance
    /// is integrated into a per-second hazard rate, so the chance that a
    /// formation is detected by the end of a 180-second phase matches the
    /// window roll exactly, while first contact may happen at any second.
    pub(crate) fn detect_night_realtime(&mut self) {
        let mut observers: Vec<_> = self
            .ships
            .iter()
            .filter(|o| o.side as usize == 0 && o.alive())
            .map(|o| (o.id, o.p, self.night_range(o, o).to_string()))
            .collect();
        observers.clear();
        for owner in 0..2usize {
            let observers: Vec<_> = self
                .ships
                .iter()
                .filter(|o| o.side == owner && o.alive())
                .cloned()
                .collect();
            if observers.is_empty() {
                continue;
            }
            let mut targets: Vec<_> = self
                .ships
                .iter()
                .filter(|t| t.side != owner && t.alive() && !self.knows(owner, t.id))
                .cloned()
                .collect();
            targets.sort_by_key(|t| (t.fleet, t.id));
            // One hazard roll per formation per second, shared by its members.
            let mut groups: Vec<(Option<u32>, bool, Vec<_>)> = Vec::new();
            for target in targets {
                let key = (target.fleet, target.fleet.is_none());
                match groups.iter_mut().find(|(g, solo, _)| (*g, *solo) == key) {
                    Some((_, _, list)) => list.push(target),
                    None => groups.push((key.0, key.1, vec![target])),
                }
            }
            for (fleet_key, _, members) in groups {
                let cue = fleet_key.is_some_and(|fleet| {
                    self.contacts[owner]
                        .iter()
                        .any(|c| self.ship(c.ship).is_some_and(|v| v.fleet == Some(fleet)))
                });
                let modifier = night::visual_d100_modifier(
                    self.environment(),
                    cue,
                    false,
                    false,
                );
                let mut views: Vec<(night::DetectionView, u32)> = Vec::new();
                for target in &members {
                    for o in &observers {
                        let distance = o.p.dist(target.p) / YARD;
                        let base = self.night_range(o, target);
                        let modifier = night::visual_d100_modifier(
                            self.environment(),
                            cue,
                            false,
                            self.fired_this_turn(o),
                        );
                        views.push(((base, distance as u32, modifier), target.id));
                    }
                }
                let window_chance = night::formation_detection_chance(
                    &views.iter().map(|(view, _)| *view).collect::<Vec<_>>(),
                );
                let per_second = night::per_second_chance(window_chance, 1.);
                if roll(&mut self.optics_rng, 10_000) as f64 / 10_000. >= per_second {
                    continue;
                }
                // Acquisition: draw the confirming die and record each observer
                // whose own base range reaches their target.
                let die = roll(&mut self.optics_rng, 100) as i32;
                for target in &members {
                    if self.knows(owner, target.id) {
                        continue;
                    }
                    let def = &self.data.ships[target.def];
                    let mut best = None;
                    for (view, view_target) in &views {
                        if *view_target != target.id {
                            continue;
                        }
                        let (base, distance, modifier) = *view;
                        let limit =
                            night::surface_detection_range_yd(base, die + modifier);
                        if (distance as f64) <= f64::from(limit)
                            && best.is_none_or(|(b, r)| (limit, base) > (r, b))
                        {
                            best = Some((base, limit));
                        }
                    }
                    let Some((base, range)) = best else { continue };
                    let id = format!("C{:02}", self.next_contacts[owner]);
                    self.next_contacts[owner] += 1;
                    self.add(
                        1 << owner,
                        "contact",
                        format!("发现夜间水面接触 {id}"),
                        Some("CAS-5.4.1.1"),
                        Some(target.p),
                    );
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
            torpedo.first_visible = None;
        } else if self.tick % CYCLE == 0
            && torpedo.view_ids[owner].is_none()
            && roll(&mut self.optics_rng, 100) <= chance
        {
            torpedo.view_ids[owner] = seat_ids(1 << owner, &mut self.torp_ids)[owner];
            torpedo.first_visible = Some(torpedo.p);
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
