//! An RTS shell volley has an explicit life from muzzle to impact. CAS still
//! determines hit and damage. Older saves retain their eight-second flight;
//! real-time batteries use a range-based trajectory.
use crate::{
    combat::Impact,
    model::*,
    world::{seat_ids, World},
};
use serde_json::{json, Value};

#[derive(Clone)]
pub(crate) struct Shell {
    view_ids: [Option<u32>; 2],
    from: P,
    to: P,
    launch_tick: u32,
    impact_tick: u32,
    owner: usize,
    barrels: u32,
    reaction: bool,
    impact: Option<Impact>,
    arc_height_m: Option<f64>,
}

impl World {
    pub(crate) fn launch_shell(
        &mut self,
        from: &Ship,
        target: &Ship,
        barrels: u32,
        reaction: bool,
        impact: Option<Impact>,
    ) {
        let initial_bearing = (target.p - from.p).heading();
        let mut to = target.p + P::bearing(target.h) * (target.speed * KNOT * SHELL_FLIGHT as f64);
        if impact.is_none() {
            // Scatter makes missed volleys legible. It consumes no rule dice and
            // never turns a CAS miss into damage.
            let sign = if (from.id + target.id + self.tick).is_multiple_of(2) {
                1.
            } else {
                -1.
            };
            to = to + P::bearing(initial_bearing + 90.) * (sign * 480.);
        }
        to = P {
            x: to.x.clamp(0., self.field.width),
            y: to.y.clamp(0., self.field.height),
        }
        .snap();
        let mask = (1 << from.side)
            | if self.knows(target.side, from.id) {
                1 << target.side
            } else {
                0
            };
        let view_ids = seat_ids(mask, &mut self.shell_ids);
        self.shells.push(Shell {
            view_ids,
            from: from.p,
            to,
            launch_tick: self.tick,
            impact_tick: self.tick + SHELL_FLIGHT,
            owner: from.side,
            barrels,
            reaction,
            impact,
            arc_height_m: None,
        });
    }

    pub(crate) fn launch_realtime_shell(
        &mut self,
        from: &Ship,
        target: &Ship,
        contact: &Contact,
        barrels: u32,
        impact: Option<Impact>,
    ) {
        let max = self.data.ships[from.def].gun.range_yd[3] * YARD;
        let velocity = P::bearing(contact.heading) * (contact.speed * KNOT);
        let known = contact.p();
        let mut plotted = known;
        // Iterate the intercept using only this seat's plot. Radar echoes have
        // position only, so they contribute no heading or speed here.
        for _ in 0..3 {
            let (duration, _) = crate::realtime::flight(from.p.dist(plotted), max);
            plotted = known + velocity * f64::from(duration);
        }
        // Both results fly on the same public trajectory; an observer must
        // not learn the adjudicated hit or miss before impact.
        let to = P { x: plotted.x.clamp(0., self.field.width), y: plotted.y.clamp(0., self.field.height) }.snap();
        let (duration, arc_height) = crate::realtime::flight(from.p.dist(to), max);
        let mask = (1 << from.side) | if self.knows(target.side, from.id) { 1 << target.side } else { 0 };
        let view_ids = seat_ids(mask, &mut self.shell_ids);
        self.shells.push(Shell {
            view_ids, from: from.p, to, launch_tick: self.tick, impact_tick: self.tick + duration,
            owner: from.side, barrels, reaction: false, impact, arc_height_m: Some(arc_height),
        });
    }

    pub(crate) fn shell_observation(&self, owner: usize) -> Vec<Value> {
        self.shells.iter().filter_map(|shell|{
            let id=shell.view_ids[owner]?;
            let duration = shell.impact_tick - shell.launch_tick;
            let progress=(self.tick.saturating_sub(shell.launch_tick) as f64/duration as f64).clamp(0.,1.);
            let xy=(shell.from+(shell.to-shell.from)*progress).snap();
            let mut view = json!({
                "id":id,"x":xy.x,"y":xy.y,"heading":(shell.to-shell.from).heading(),
                "progress":progress,"from":shell.from,"to":shell.to,"launchTick":shell.launch_tick,
                "impactTick":shell.impact_tick,"own":shell.owner==owner,"barrels":shell.barrels,
            });
            if let Some(height) = shell.arc_height_m {
                view["arcHeightM"] = json!(libm::round(height * 1000.) / 1000.);
            }
            Some(view)
        }).collect()
    }

    pub(crate) fn advance_shells(&mut self) {
        if self.shells.is_empty() {
            return;
        }
        let old = std::mem::take(&mut self.shells);
        // Batches preserve simultaneous impacts within each CAS fire window and
        // planned-before-reaction ordering if they share a tick.
        let mut phases: Vec<(u32, bool, Vec<Impact>)> = vec![];
        for mut shell in old {
            if shell.impact_tick > self.tick {
                self.shells.push(shell);
                continue;
            }
            if let Some(mut impact) = shell.impact.take() {
                if let Some(target) = self.ship(impact.victim).filter(|s| s.alive()) {
                    impact.at = target.p;
                    if let Some((_, _, batch)) = phases.iter_mut().find(|(tick, reaction, _)| {
                        *tick == shell.impact_tick && *reaction == shell.reaction
                    }) {
                        batch.push(impact);
                    } else {
                        phases.push((shell.impact_tick, shell.reaction, vec![impact]));
                    }
                    continue;
                }
            }
            let mask = shell.view_ids.iter().enumerate().fold(0, |m, (side, id)| {
                m | if id.is_some() { 1 << side } else { 0 }
            });
            self.add(
                mask,
                "splash",
                "炮弹落水".into(),
                Some("RTS-SHELL-01"),
                Some(shell.to),
            );
        }
        phases.sort_by_key(|(tick, reaction, _)| (*tick, *reaction));
        for (_, _, impacts) in phases {
            self.apply_impacts(impacts);
        }
    }
}
