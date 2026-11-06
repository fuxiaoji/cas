use crate::{model::*, world::World};
use serde_json::{json, Value};

#[derive(Clone)]
struct Doctrine {
    range: f64,
    flank: f64,
    speed: f64,
    torp_fraction: f64,
    period: u32,
    focus: bool,
    withdraw_hp: f64,
}
fn doctrine(key: &str) -> Doctrine {
    match key {
        "gunnery" => Doctrine {
            range: 6850.,
            flank: 82.,
            speed: 25.,
            torp_fraction: 0.66,
            period: 135,
            focus: true,
            withdraw_hp: 0.27,
        },
        "torpedo" => Doctrine {
            range: 3200.,
            flank: 64.,
            speed: 28.,
            torp_fraction: 0.88,
            period: 95,
            focus: false,
            withdraw_hp: 0.15,
        },
        _ => Doctrine {
            range: 4650.,
            flank: 75.,
            speed: 26.,
            torp_fraction: 0.78,
            period: 115,
            focus: true,
            withdraw_hp: 0.23,
        },
    }
}
impl World {
    fn evaluate_tactic(&self, f: &Fleet) -> Tactic {
        let policy = doctrine(&f.ai.profile);
        let ratio = f
            .members
            .iter()
            .filter_map(|&id| self.ship(id))
            .map(|s| s.hp / self.data.ships[s.def].dp)
            .sum::<f64>()
            / (f.members.len().max(1) as f64);
        if ratio < policy.withdraw_hp || f.tactic == Tactic::Withdraw {
            return Tactic::Withdraw;
        }
        let Some(lead) = self.ship(f.leader) else {
            return Tactic::Search;
        };
        let range = self.contacts[f.side]
            .iter()
            .map(Contact::p)
            .chain(self.radar_navigation_reports(lead))
            .map(|p| lead.p.dist(p))
            .fold(f64::INFINITY, f64::min);
        if range.is_infinite() {
            Tactic::Search
        } else if range
            < policy.range
                + if f.tactic == Tactic::Engage {
                    1700.
                } else {
                    900.
                }
        {
            Tactic::Engage
        } else {
            Tactic::Approach
        }
    }
    pub fn suggestions(&self, owner: usize, fid: u32) -> E<Vec<Value>> {
        let fleet = self.fleet_for(owner, fid)?;
        let leader = self.ship_for(owner, fleet.leader)?;
        let style = doctrine(&fleet.ai.profile);
        let tactic = self.evaluate_tactic(fleet);
        let c = &self.contacts[owner];
        let auto = fleet.ai.mode == "auto";
        let mut orders = Vec::new();
        let going = leader.track.as_ref().is_some_and(|t| !t.done());
        let chosen = c
            .iter()
            .map(Contact::p)
            .chain(self.radar_navigation_reports(leader))
            .min_by(|a, b| leader.p.dist(*a).total_cmp(&leader.p.dist(*b)));
        if (!auto || fleet.ai.r#move)
            && (!going || self.tick.saturating_sub(fleet.last_ai_route) >= style.period)
        {
            let target = chosen.unwrap_or(P {
                x: if owner == 0 { WIDTH - 5000. } else { 5000. },
                y: if owner == 0 { 5800. } else { 8000. },
            });
            let angle = (target - leader.p).heading();
            let range = target.dist(leader.p);
            let prefer = if leader.p.y < HEIGHT * 0.52 { 1. } else { -1. };
            let look = match tactic {
                Tactic::Search => angle,
                Tactic::Approach => {
                    angle
                        + prefer
                            * if fleet.ai.profile == "torpedo" {
                                17.
                            } else {
                                7.
                            }
                }
                Tactic::Engage => angle + prefer * style.flank,
                Tactic::Withdraw => angle + prefer * 148.,
            };
            let stride = match tactic {
                Tactic::Search => 5000.,
                Tactic::Approach => (range - style.range + 1000.).clamp(2400., 6400.),
                Tactic::Engage => 3600.,
                Tactic::Withdraw => 4400.,
            };
            let k = fleet
                .members
                .iter()
                .filter_map(|i| self.ship_for(owner, *i).ok())
                .map(|s| self.max_speed(s))
                .fold(style.speed, f64::min);
            if k >= 4. {
                let choose = |x: f64| leader.p + P::bearing(x) * stride;
                let mut tries = vec![
                    look,
                    if range > style.range {
                        angle
                    } else {
                        angle - prefer * style.flank
                    },
                    look + 35.,
                    look - 35.,
                    leader.h + 35.,
                    leader.h - 35.,
                    leader.h,
                ];
                if tactic == Tactic::Engage && range < style.range - 1500. {
                    tries.insert(0, angle + prefer * 125.);
                }
                'routes: for h in tries {
                    let p = choose(h);
                    let p = P {
                        x: p.x.clamp(2100., WIDTH - 2100.),
                        y: p.y.clamp(1650., HEIGHT - 1650.),
                    };
                    if p.dist(leader.p) < 400. {
                        continue;
                    }
                    let modes = if range < style.range + 1000. && fleet.ai.profile == "gunnery" {
                        ["sync", "follow"]
                    } else {
                        ["follow", "sync"]
                    };
                    for mode in modes {
                        let r =
                            json!({"op":"route","fleet":fid,"mode":mode,"points":[p],"speed":k});
                        if self.preview(owner, &r).is_ok_and(|v| v["valid"] == true) {
                            orders.push(r);
                            break 'routes;
                        }
                    }
                }
            }
        }
        for id in &fleet.members {
            let Ok(s) = self.ship_for(owner, *id) else {
                continue;
            };
            let mut targets: Vec<_> = c.iter().collect();
            targets.sort_by(|a, b| {
                let score = |t: &Contact| {
                    let d = s.p.dist(t.p());
                    if style.focus {
                        d + leader.p.dist(t.p()) * 0.7
                            - if t.kind.as_deref() == Some("cl") {
                                550.
                            } else {
                                0.
                            }
                    } else {
                        d
                    }
                };
                score(a).total_cmp(&score(b)).then_with(|| a.id.cmp(&b.id))
            });
            if (!auto || fleet.ai.gun) && self.can_gun(s) {
                let radar;
                let chosen = if let Some(t) = targets.iter().find(|c| self.gun_candidate(s, c)) {
                    Some(t.id.as_str())
                } else {
                    radar = self
                        .radar_gun_contacts(s)
                        .filter(|t| self.gun_candidate(s, t))
                        .min_by(|a, b| {
                            s.p.dist(a.p())
                                .total_cmp(&s.p.dist(b.p()))
                                .then_with(|| a.id.cmp(&b.id))
                        });
                    radar.as_ref().map(|r| r.id.as_str())
                };
                if let Some(t) = chosen {
                    orders.push(json!({"op":"fire","ship":id,"target":t,"weapon":"gun"}));
                }
            }
            if (!auto || fleet.ai.torpedo)
                && tactic != Tactic::Withdraw
                && self.tick % CYCLE >= 160
                && self.can_torp(s)
            {
                for t in &targets {
                    let mut request = json!({"op":"aim","ship":id,"target":t.id});
                    if let Ok(a) = self.preview_aim(owner, &request) {
                        let max = a["range"].as_f64().unwrap_or(0.);
                        if a["valid"] == true
                            && a["friendly"] == false
                            && s.p.dist(t.p()) <= max * style.torp_fraction
                        {
                            request["op"] = json!("fire");
                            request["weapon"] = json!("torpedo");
                            request["heading"] = a["heading"].clone();
                            orders.push(request);
                            break;
                        }
                    }
                }
            }
        }
        Ok(orders)
    }
    pub fn drive_ai(&mut self) {
        let task: Vec<_> = self
            .fleets
            .iter()
            .filter(|f| f.ai.mode == "auto")
            .map(|f| (f.side, f.id))
            .collect();
        for (owner, id) in task {
            if let Ok(f) = self.fleet_for(owner, id) {
                let next = self.evaluate_tactic(f);
                if f.tactic != next {
                    let text = format!("{} · AI 转入{}", f.name, next.label());
                    self.fleet_mut(id).unwrap().tactic = next;
                    self.add(1 << owner, "ai_state", text, Some("RTS-AI-01"), None);
                }
            }
            if let Ok(orders) = self.suggestions(owner, id) {
                for r in orders {
                    match r["op"].as_str() {
                        Some("route") => {
                            let _ = self.route(owner, &r, false);
                        }
                        Some("fire") => {
                            let _ = self.queue_fire(owner, &r, false);
                        }
                        _ => {}
                    }
                }
            }
        }
    }
}
