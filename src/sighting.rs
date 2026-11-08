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
        } else if self.variant == crate::empress::VARIANT {
            Environment { light: night::Light::Night, visibility: 10, sea_state: 1, precipitation: true }
        } else if self.variant == crate::campaign::esperance::VARIANT {
            Environment { light: night::Light::Night, visibility: 10, sea_state: 3, precipitation: false }
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
            // cas-realtime-v10: a ship trailing smoke beyond the sighting cap
            // loses its night track (5.4.5: sighting in smoke is capped).
            let mut smoked_off: Vec<u32> = vec![];
            for target in &targets {
                let still_seen = observers.iter().any(|o| {
                    let cap = self.smoke_cap_yd(target).unwrap_or_else(|| {
                        // a smoke screen crossing the ray caps sighting the
                        // same way as a smoking ship (5.4.5; 500 yd at night)
                        if self.smoke_blocks_ray(o.p, target.p) { 500 } else { u32::MAX }
                    });
                    o.p.dist(target.p) <= f64::from(cap) * YARD
                });
                if !still_seen && self.knows(owner, target.id) {
                    smoked_off.push(target.id);
                }
            }
            if !smoked_off.is_empty() {
                self.contacts[owner].retain(|c| !smoked_off.contains(&c.ship));
                for id in smoked_off {
                    self.add(1 << owner, "lost", "目标进入烟幕，接触丢失".into(), Some("RTS-SMOKE-01"), None);
                }
            }
            // cas-realtime-v10: own-side searchlights auto-acquire their lit
            // targets inside the light's illumination range (5.4.4.1), and a
            // lit ship is auto-detected by every enemy hull within the light's
            // source range (five times the fixture; x3 with precipitation) —
            // the classic backlighting risk. Other views add the printed +20
            // induced-search penalty against a lit ship.
            let mut direct: Vec<(u32, u32, f64)> = vec![];
            for target in &targets {
                if let Some((fixture, range_yd)) = self.searchlight_lit(owner, target.id) {
                    if let Some(o) = observers.iter().find(|o| o.p.dist(target.p) <= f64::from(range_yd) * YARD) {
                        direct.push((target.id, fixture, o.p.dist(target.p)));
                    }
                }
                if target.searchlight.is_some() {
                    let env = self.environment();
                    let fixture: u32 = if target.side == 0 { 8000 } else { 7000 };
                    let source = night::searchlight_source_range_yd(
                        env, fixture, &self.data.ships[observers[0].def].size, &self.data.ships[target.def].size,
                    );
                    if let Some(o) = observers.iter().find(|o| o.p.dist(target.p) <= f64::from(source) * YARD) {
                        direct.push((target.id, fixture, o.p.dist(target.p)));
                    }
                }
            }
            // Direct acquisition: lit targets and ships inside a searchlight's
            // source range are found without the hazard roll.
            for (lit_id, _fixture, _distance) in &direct {
                if self.knows(owner, *lit_id) {
                    continue;
                }
                let Some(target) = targets.iter().find(|t| t.id == *lit_id) else { continue };
                let def = &self.data.ships[target.def];
                let mut best = None;
                for o in &observers {
                    let distance = o.p.dist(target.p) / YARD;
                    let base = self.night_range(o, target);
                    if best.is_none_or(|(b, _)| base > b) {
                        best = Some((base, base));
                    }
                    let _ = distance;
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
            // One hazard roll per formation per second, shared by its members.
            let mut groups: Vec<(Option<u32>, bool, Vec<_>)> = Vec::new();
            for target in targets {
                if direct.iter().any(|(lit, _, _)| *lit == target.id) {
                    continue;
                }
                // Known ships are maintained, not re-rolled (5.4.1.7): the
                // hazard draws only cover hulls the formation does not hold.
                if self.knows(owner, target.id) {
                    continue;
                }
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
                ) + 20 * i32::from(members.iter().any(|m| m.searchlight.is_some()));
                let mut views: Vec<(night::DetectionView, u32, bool)> = Vec::new();
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
                        let blocked = self.smoke_blocks_ray(o.p, target.p);
                        views.push(((base, distance as u32, modifier), target.id, blocked));
                    }
                }
                let window_chance = night::formation_detection_chance(
                    &views.iter().map(|(view, _, _)| *view).collect::<Vec<_>>(),
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
                    for (view, view_target, blocked) in &views {
                        if *view_target != target.id {
                            continue;
                        }
                        let (base, distance, modifier) = *view;
                        let cap = self
                            .smoke_cap_yd(target)
                            .or(blocked.then_some(500));
                        let limit = cap.map_or(
                            night::surface_detection_range_yd(base, die + modifier),
                            |cap| night::surface_detection_range_yd(base, die + modifier).min(cap),
                        );
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
