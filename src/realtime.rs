//! Versioned RTS scheduling. CAS supplies range bands, arcs, hit and damage
//! tables. Mechanical delays are explicit simulation policy; see the ledger.
use crate::{
    model::*,
    world::{u, World},
};
use serde_json::{json, Value};

pub(crate) const VERSION: &str = "cas-realtime-v4";
pub(crate) const MAX_FLIGHT: u32 = 120;
const ORDER_TIMEOUT: u32 = 90;

#[derive(Clone, Copy)]
pub(crate) struct Timings {
    pub(crate) reload: u32,
    pub(crate) train: f64,
}

pub(crate) fn timings(class: &str) -> Option<Timings> {
    let (reload, train) = match class {
        "fletcher" => (6, 18.),
        "cleveland" => (10, 10.),
        "kagero" => (9, 9.),
        "sendai" => (12, 7.5),
        _ => return None,
    };
    Some(Timings { reload, train })
}

#[derive(Clone, Debug, Default)]
pub(crate) struct Turret {
    relative: f64,
    ready: u32,
    training: bool,
}

#[derive(Clone, Debug)]
pub(crate) struct Order {
    pub(crate) target: String,
    mounts: Vec<usize>,
    deadline: u32,
    manual: bool,
}

#[derive(Clone, Debug, Default)]
pub(crate) struct Battery {
    turrets: Vec<Turret>,
    pub(crate) order: Option<Order>,
    pub(crate) dice_window: u32,
    pub(crate) hit_roll: Option<u32>,
    pub(crate) deck_roll: Option<u32>,
}

#[derive(Clone)]
pub(crate) struct Volley {
    pub(crate) ship: u32,
    pub(crate) contact: Contact,
    pub(crate) band: usize,
    pub(crate) barrels: u32,
    pub(crate) radar_only: bool,
    pub(crate) battery_barrels: u32,
    pub(crate) reload: u32,
}

fn in_arc(relative: f64, mount: &GunMount) -> bool {
    circle(relative, mount.arc) || mount.arc2.is_some_and(|arc| circle(relative, arc))
}

pub(crate) fn flight(range_m: f64, max_m: f64) -> (u32, f64) {
    // A low ballistic arc with a 35° reference at the last CAS range band.
    // Derive an effective speed for the range, never claim a historical MV.
    let gravity = 9.80665;
    let sin70 = libm::sin(70_f64.to_radians());
    let velocity = libm::sqrt(max_m.max(1.) * gravity / sin70);
    let angle = 0.5 * libm::asin((range_m / max_m.max(1.) * sin70).clamp(0., sin70));
    let time = range_m / (velocity * libm::cos(angle));
    let height = gravity * time * time / 8.;
    (time.ceil().clamp(1., MAX_FLIGHT as f64) as u32, height)
}

impl World {
    pub(crate) fn realtime(&self) -> bool {
        self.version == VERSION
    }

    pub(crate) fn enable_realtime(&mut self) -> E<()> {
        for s in &mut self.ships {
            let def = &self.data.ships[s.def];
            timings(&def.id).ok_or_else(|| format!("{} 的实时炮座配置尚未核准", def.name))?;
            s.battery.turrets = def
                .gun
                .mounts
                .iter()
                .map(|mount| Turret {
                    relative: if circle(0., mount.arc) {
                        0.
                    } else if circle(180., mount.arc) {
                        180.
                    } else {
                        norm(mount.arc[0] + norm(mount.arc[1] - mount.arc[0]) / 2.)
                    },
                    ..Turret::default()
                })
                .collect();
        }
        self.version = VERSION;
        self.enable_realtime_mk4()
    }

    pub(crate) fn realtime_mount_view(&self, s: &Ship, index: usize, json: &mut Value) {
        if let Some(turret) = s.battery.turrets.get(index) {
            json["bearing"] = json!(norm(s.h + turret.relative));
            json["training"] = json!(turret.training && !s.gun_mount_destroyed[index]);
            json["readyTick"] = json!(turret.ready);
        }
    }

    pub(crate) fn turret_loaded(&self, s: &Ship, index: usize) -> bool {
        !self.realtime()
            || s.battery
                .turrets
                .get(index)
                .is_some_and(|t| t.ready <= self.tick)
    }

    pub(crate) fn reserve_illumination_mount(&mut self, id: u32, index: usize) {
        if !self.realtime() {
            return;
        }
        let tick = self.tick;
        let reload = timings(&self.data.ships[self.ship(id).unwrap().def].id)
            .unwrap()
            .reload;
        let s = self.ship_mut(id).unwrap();
        s.battery.turrets[index].ready = tick + reload;
    }

    pub(crate) fn illumination_aligned(&self, ship: &Ship, index: usize, bearing: f64) -> bool {
        !self.realtime()
            || ship
                .battery
                .turrets
                .get(index)
                .is_some_and(|t| delta(t.relative, norm(bearing - ship.h)).abs() <= 1e-7)
    }

    pub(crate) fn train_illumination_mount(&mut self, id: u32, index: usize, bearing: f64) {
        let s = self.ship(id).unwrap();
        let train = timings(&self.data.ships[s.def].id).unwrap().train;
        let goal = norm(bearing - s.h);
        let turret = &mut self.ship_mut(id).unwrap().battery.turrets[index];
        let change = delta(turret.relative, goal);
        turret.relative = norm(turret.relative + change.clamp(-train, train));
        turret.training = change.abs() > train + 1e-7;
    }

    pub(crate) fn clear_turret_training(&mut self) {
        for s in &mut self.ships {
            for turret in &mut s.battery.turrets {
                turret.training = false;
            }
        }
    }

    fn gun_obstructed(&self, ship: &Ship, target: &Contact) -> bool {
        let gun = &self.data.ships[ship.def].gun;
        let target_offset = target.p() - ship.p;
        let heading = target_offset.heading();
        let target_range = ship.p.dist(target.p());
        let obstructs = |p: P| {
            let distance = ship.p.dist(p);
            distance < target_range
                && distance <= gun.range_yd[1] * YARD
                && delta(heading, (p - ship.p).heading()).abs() <= 10. + 1e-7
        };
        // Use the same known friendly positions and visual contacts for
        // preview, AI and execution. Never probe a concealed ship by aiming.
        self.ships
            .iter()
            .any(|s| s.side == ship.side && s.id != ship.id && s.alive() && obstructs(s.p))
            || self.contacts[ship.side]
                .iter()
                .any(|c| c.ship != target.ship && obstructs(c.p()))
    }

    fn solution(&self, ship: &Ship, contact: &Contact) -> Option<(usize, f64, Vec<usize>)> {
        if self.gun_obstructed(ship, contact) {
            return None;
        }
        let gun = &self.data.ships[ship.def].gun;
        let range = ship.p.dist(contact.p()) / YARD;
        let band = gun.range_yd.iter().position(|max| range <= *max)?;
        let relative = norm((contact.p() - ship.p).heading() - ship.h);
        let eligible: Vec<_> = gun
            .mounts
            .iter()
            .enumerate()
            .filter(|(i, m)| {
                !ship.gun_mount_destroyed[*i]
                    && !self.mount_lighting(ship.id, *i)
                    && !self.mount_preparing_illumination(ship.id, *i)
                    && in_arc(relative, m)
            })
            .map(|(i, _)| i)
            .collect();
        (!eligible.is_empty()).then_some((band, relative, eligible))
    }

    pub(crate) fn realtime_gun_candidate(&self, ship: &Ship, contact: &Contact) -> bool {
        self.solution(ship, contact).is_some()
    }

    pub(crate) fn realtime_aim(&self, ship: &Ship, target: &str) -> E<Value> {
        let (contact, radar_only) = self.gun_contact(ship, target)?;
        let def = &self.data.ships[ship.def];
        let timing = timings(&def.id).ok_or("本舰实时炮座未核准")?;
        let mut solution = json!({
            "heading":(contact.p()-ship.p).heading(),"range":def.gun.range_yd[3]*YARD,
            "arcs":[],"friendly":false,"valid":false,"barrels":0,"mounts":[],
            "error": "目标超出射程或没有可用炮座",
        });
        if radar_only {
            solution["targetSource"] = json!("surface_radar");
        }
        if self.gun_obstructed(ship, &contact) {
            solution["error"] = json!("近、中射程内有已知舰艇遮挡射线");
            return Ok(solution);
        }
        let Some((_, relative, eligible)) = self.solution(ship, &contact) else {
            return Ok(solution);
        };
        let mut barrels = 0;
        let mounts: Vec<_> = eligible
            .into_iter()
            .map(|i| {
                barrels += def.gun.mounts[i].barrels;
                let t = &ship.battery.turrets[i];
                let seconds = (delta(t.relative, relative).abs() / timing.train).ceil() as u32;
                json!({"index":i,"turnSeconds":seconds,"readyTick":t.ready.max(self.tick + seconds.max(1))})
            })
            .collect();
        solution["valid"] = json!(ship.battery.order.is_none());
        solution["barrels"] = json!(barrels);
        solution["mounts"] = json!(mounts);
        solution["error"] = if ship.battery.order.is_some() {
            json!("本舰已有待发炮击，可先取消")
        } else {
            Value::Null
        };
        Ok(solution)
    }

    pub(crate) fn order_realtime_gun(
        &mut self,
        owner: usize,
        ship: u32,
        target: &str,
        manual: bool,
    ) -> E<()> {
        let s = self.ship_for(owner, ship)?;
        if s.battery.order.is_some() {
            return Err("本舰已有待发炮击，可先取消".into());
        }
        let (c, _) = self.gun_contact(s, target)?;
        if self.gun_obstructed(s, &c) {
            return Err("近、中射程内有已知舰艇遮挡射线".into());
        }
        let (_, _, mounts) = self.solution(s, &c).ok_or("目标超出射程或没有可用炮座")?;
        let (name, fleet) = (s.name.clone(), s.fleet);
        let deadline = self.tick + ORDER_TIMEOUT;
        self.ship_mut(ship).unwrap().battery.order = Some(Order {
            target: target.into(),
            mounts,
            deadline,
            manual,
        });
        if manual {
            if let Some(f) = fleet.and_then(|i| self.fleet_mut(i)) {
                f.ai.gun = false;
            }
            self.add(
                1 << owner,
                "ordered",
                format!("{name} · 炮击已下令，等待炮座转向与装填"),
                Some("RTS-GUN-04"),
                None,
            );
        }
        Ok(())
    }

    pub(crate) fn cancel_realtime_gun(&mut self, owner: usize, request: &Value) -> E<()> {
        if !self.realtime() {
            return Err("旧演习没有逐炮座待发指令".into());
        }
        let id = u(request, "ship")?;
        let ship = self.ship_for(owner, id)?;
        let (name, fleet) = (ship.name.clone(), ship.fleet);
        let b = &mut self.ship_mut(id).unwrap().battery;
        if b.order.take().is_none() {
            return Err("本舰没有待发炮击".into());
        }
        for t in &mut b.turrets {
            t.training = false;
        }
        if let Some(fleet) = fleet.and_then(|id| self.fleet_mut(id)) {
            fleet.ai.gun = false;
        }
        self.add(
            1 << owner,
            "fire_held",
            format!("{name} · 已取消尚未发射的炮击"),
            Some("RTS-GUN-04"),
            None,
        );
        Ok(())
    }

    pub(crate) fn resolve_realtime_guns(&mut self) {
        let tick = self.tick;
        let mut volleys = Vec::new();
        let ids: Vec<_> = self
            .ships
            .iter()
            .filter(|s| s.battery.order.is_some())
            .map(|s| s.id)
            .collect();
        for id in ids {
            let s = self.ship(id).unwrap();
            let order = s.battery.order.as_ref().unwrap().clone();
            let owner = s.side;
            let name = s.name.clone();
            let gun = &self.data.ships[s.def].gun;
            let timing = timings(&self.data.ships[s.def].id).unwrap();
            let contact = self
                .gun_contact(s, &order.target)
                .ok()
                .map(|(track, radar)| (track.into_owned(), radar));
            let solution = contact.as_ref().and_then(|(c, _)| self.solution(s, c));
            let obstructed = contact
                .as_ref()
                .is_some_and(|(c, _)| self.gun_obstructed(s, c));
            let eligible_barrels = solution
                .as_ref()
                .map(|(_, _, m)| m.iter().map(|&i| gun.mounts[i].barrels).sum())
                .unwrap_or(0);
            let barrel_counts: Vec<_> = gun.mounts.iter().map(|m| m.barrels).collect();
            let destroyed = s.gun_mount_destroyed.clone();
            let fail = if !s.alive() || order.mounts.iter().all(|i| destroyed[*i]) {
                Some("待发炮座已失能")
            } else if contact.is_none() {
                Some("目标接触丢失")
            } else if tick > order.deadline {
                Some(if obstructed {
                    "近、中射程内的已知舰艇一直遮挡射线"
                } else {
                    "转炮／装填或射界等待超时"
                })
            } else {
                None
            };
            let b = &mut self.ship_mut(id).unwrap().battery;
            if let Some(reason) = fail {
                b.order = None;
                if order.manual {
                    self.add(
                        1 << owner,
                        "rejected",
                        format!("{name} · 未开火：{reason}"),
                        Some("RTS-GUN-04"),
                        None,
                    );
                }
                continue;
            }
            let mut remaining = Vec::new();
            let mut barrels = 0;
            for i in order.mounts {
                if destroyed[i] {
                    continue;
                }
                if let Some((_, relative, eligible)) = &solution {
                    if eligible.contains(&i) {
                        let turret = &mut b.turrets[i];
                        let change = delta(turret.relative, *relative);
                        turret.relative =
                            norm(turret.relative + change.clamp(-timing.train, timing.train));
                        turret.training = change.abs() > timing.train + 1e-7;
                        if !turret.training && turret.ready <= tick {
                            barrels += barrel_counts[i];
                            turret.ready = tick + timing.reload;
                            continue;
                        }
                    }
                }
                remaining.push(i);
            }
            if barrels > 0 {
                let (contact, radar_only) = contact.unwrap();
                let band = solution.unwrap().0;
                volleys.push(Volley {
                    ship: id,
                    contact,
                    band,
                    barrels,
                    radar_only,
                    battery_barrels: eligible_barrels,
                    reload: timing.reload,
                });
            }
            b.order = (!remaining.is_empty()).then(|| Order {
                mounts: remaining,
                ..order
            });
        }
        self.fire_realtime_volleys(volleys);
    }

    pub(crate) fn realtime_fire_dice(&mut self, id: u32, deck_needed: bool) -> (u32, Option<u32>) {
        let cycle = self.tick / CYCLE;
        let b = &mut self.ship_mut(id).unwrap().battery;
        if b.dice_window != cycle {
            b.dice_window = cycle;
            b.hit_roll = None;
            b.deck_roll = None;
        }
        let hit = b.hit_roll;
        let deck = b.deck_roll;
        let hit = hit.unwrap_or_else(|| self.d(100));
        let deck = deck.or_else(|| deck_needed.then(|| self.d(100)));
        let b = &mut self.ship_mut(id).unwrap().battery;
        b.hit_roll = Some(hit);
        b.deck_roll = deck;
        (hit, deck)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> World {
        let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
        w.enable_realtime().unwrap();
        for fleet in &mut w.fleets {
            fleet.ai = Ai::new("coord", "manual");
        }
        w
    }

    fn target_at(w: &mut World, bearing: f64, range: f64) -> String {
        let p = w.ship(1).unwrap().p + P::bearing(bearing) * range;
        w.ship_mut(6).unwrap().p = p;
        w.detect(true);
        w.contacts[0]
            .iter()
            .find(|c| c.ship == 6)
            .unwrap()
            .id
            .clone()
    }

    #[test]
    fn switch_sides_trains_cancel_preserves_angle_and_reload_releases_before_window() {
        let mut w = fixture();
        let north = target_at(&mut w, 0., 2_500.);
        w.order_realtime_gun(0, 1, &north, true).unwrap();
        for _ in 0..12 {
            w.advance();
        }
        assert_eq!(w.ship(1).unwrap().battery.turrets[2].relative, 270.);
        assert!(w.events.iter().any(|e| e.kind == "gun" && e.tick < CYCLE));
        let south = target_at(&mut w, 180., 2_500.);
        let ready = w.realtime_aim(w.ship(1).unwrap(), &south).unwrap();
        let amidships = ready["mounts"]
            .as_array()
            .unwrap()
            .iter()
            .find(|m| m["index"] == 2)
            .unwrap();
        assert_eq!(amidships["turnSeconds"], 10);
        w.order_realtime_gun(0, 1, &south, true).unwrap();
        let initial = w.ship(1).unwrap().battery.turrets[2].clone();
        w.advance();
        let turning = w.ship(1).unwrap().battery.turrets[2].clone();
        assert!(turning.training);
        assert_eq!(delta(initial.relative, turning.relative).abs(), 18.);
        w.cancel_realtime_gun(0, &json!({"ship":1})).unwrap();
        w.advance();
        let after_cancel = &w.ship(1).unwrap().battery.turrets[2];
        assert_eq!(after_cancel.relative, turning.relative);
        assert_eq!(after_cancel.ready, initial.ready);
        assert!(!after_cancel.training);

        w.order_realtime_gun(0, 1, &south, true).unwrap();
        for _ in 0..9 {
            w.advance();
        }
        let first_south_fire = w.tick;
        assert_eq!(w.ship(1).unwrap().battery.turrets[2].relative, 90.);
        assert_eq!(w.ship(1).unwrap().battery.turrets[2].ready, w.tick + 6);
        w.order_realtime_gun(0, 1, &south, true).unwrap();
        for _ in 0..5 {
            w.advance();
        }
        assert_eq!(
            w.ship(1).unwrap().battery.turrets[2].ready,
            first_south_fire + 6
        );
        w.advance();
        assert_eq!(
            w.ship(1).unwrap().battery.turrets[2].ready,
            first_south_fire + 12
        );
    }

    #[test]
    fn same_window_dice_and_range_based_flight() {
        let mut w = fixture();
        let rolled = w.realtime_fire_dice(1, true);
        let rng = w.rng;
        w.tick = 149;
        assert_eq!(w.realtime_fire_dice(1, true), rolled);
        assert_eq!(w.rng, rng);
        w.tick = CYCLE;
        w.realtime_fire_dice(1, true);
        assert_ne!(w.rng, rng);
        let (near, near_height) = flight(2_500., 18_200. * YARD);
        let (far, far_height) = flight(14_000., 18_200. * YARD);
        assert!(far > 4 * near && far_height > near_height);
    }

    #[test]
    fn known_intervening_ship_blocks_but_hidden_ship_cannot_be_probed() {
        let mut w = fixture();
        let target = target_at(&mut w, 20., 5_000.);
        let shooter = w.ship(1).unwrap().p;
        let blocker = shooter + P::bearing(30.) * 2_000.;
        w.ship_mut(2).unwrap().p = blocker;
        let aim = |w: &World| w.realtime_aim(w.ship(1).unwrap(), &target).unwrap();
        assert_eq!(aim(&w)["valid"], false);
        assert!(aim(&w)["error"].as_str().unwrap().contains("遮挡"));
        w.ship_mut(2).unwrap().p = shooter + P::bearing(30.01) * 2_000.;
        assert_eq!(aim(&w)["valid"], true);
        w.ship_mut(7).unwrap().p = blocker;
        w.contacts[0].retain(|c| c.ship != 7);
        assert_eq!(aim(&w)["valid"], true);
        w.detect(true);
        assert_eq!(aim(&w)["valid"], false);
        w.ship_mut(7).unwrap().p = shooter + P::bearing(20.) * 5_500.;
        w.detect(true);
        assert_eq!(aim(&w)["valid"], true);
    }

    #[test]
    fn first_launch_and_midflight_replay_have_same_shell_and_turret_state() {
        let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
        w.enable_realtime().unwrap();
        let c = w.contacts[0]
            .iter()
            .find(|c| c.ship == 6)
            .unwrap()
            .id
            .clone();
        w.external(json!({"op":"fire","ship":1,"weapon":"gun","target":c}))
            .unwrap();
        while w.shells.is_empty() && w.tick < 40 {
            w.advance();
        }
        let observed = w.observation(0);
        assert_eq!(observed["version"], VERSION);
        let shell = &observed["shells"][0];
        assert_eq!(shell["launchTick"], w.tick);
        assert_eq!(shell["progress"], 0.);
        assert!(shell["arcHeightM"].as_f64().unwrap() > 0.);
        let impact_tick = shell["impactTick"].as_u64().unwrap() as u32;
        assert!(impact_tick - w.tick > 8);
        w.advance();
        let midflight = w.observation(0);
        let progress = midflight["shells"][0]["progress"].as_f64().unwrap();
        assert!(progress > 0. && progress < 1.);
        let replay = World::from_save(w.save(), w.tick).unwrap();
        assert_eq!(replay.observation(0), midflight);
        assert_eq!(replay.observation(1), w.observation(1));
    }

    #[test]
    fn cancelling_ai_fire_keeps_guns_manual_until_explicit_handover() {
        let mut w = fixture();
        let target = target_at(&mut w, 0., 2_500.);
        w.external(json!({"op":"ai","fleet":1,"profile":"coord","mode":"auto","move":true,"gun":true,"torpedo":true})).unwrap();
        w.order_realtime_gun(0, 1, &target, false).unwrap();
        w.external(json!({"op":"gun_cancel","ship":1})).unwrap();
        let ai = &w.fleets[0].ai;
        assert!(ai.r#move && !ai.gun && ai.torpedo);
        for _ in 0..15 {
            w.advance();
        }
        assert!(w.ship(1).unwrap().battery.order.is_none());
        assert!(!w.events.iter().any(|e| e.kind == "gun" && e.mask == 1));
    }

    #[test]
    fn enemy_torpedo_trail_starts_at_first_visible_sample_and_resets_on_loss() {
        let mut w = fixture();
        let origin = w.ship(1).unwrap().p;
        let visible_at = w.ship(6).unwrap().p + P::bearing(180.) * 800.;
        let mut torp = Torpedo {
            side: 0,
            ship: 1,
            p: origin,
            h: 90.,
            remaining: 2_000.,
            speed: 23.,
            warhead: 87.,
            count: 5,
            traveled: 0.,
            born: 0,
            origin,
            view_ids: [Some(1), None],
            first_visible: None,
            launch_sighted: true,
            impact_sighted: true,
            contact_fuze: true,
            single_mode: false,
            tested: Vec::new(),
        };
        w.torps.push(torp.clone());
        assert_eq!(w.observation(1)["torpedoes"], json!([]));
        assert_eq!(w.observation(0)["torpedoes"][0]["trail"][0], json!(origin));

        torp.p = visible_at;
        for cycle in 1..=8 {
            w.tick = cycle * CYCLE;
            w.observe_torpedo_wake(&mut torp);
            if torp.first_visible.is_some() {
                break;
            }
        }
        assert_eq!(torp.first_visible, Some(visible_at));
        let seen_id = torp.view_ids[1].unwrap();
        torp.p = visible_at + P::bearing(90.) * 23.;
        w.torps[0] = torp.clone();
        let shown = &w.observation(1)["torpedoes"][0];
        assert_eq!(shown["trail"], json!([visible_at, torp.p]));
        assert!(shown.get("from").is_none() && shown.get("count").is_none());

        torp.p = origin;
        w.tick += 1;
        w.observe_torpedo_wake(&mut torp);
        assert_eq!(torp.first_visible, None);
        assert_eq!(torp.view_ids[1], None);
        let next_sample = visible_at + P::bearing(90.) * 46.;
        torp.p = next_sample;
        for _ in 0..8 {
            w.tick += CYCLE - w.tick % CYCLE;
            w.observe_torpedo_wake(&mut torp);
            if torp.first_visible.is_some() {
                break;
            }
        }
        assert_eq!(torp.first_visible, Some(next_sample));
        assert_ne!(torp.view_ids[1], Some(seen_id));
    }
}
