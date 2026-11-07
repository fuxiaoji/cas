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
            let target = chosen.unwrap_or(if self.variant == crate::campaign::live::VARIANT && owner == 0 {
                // Published interception area, not an unobserved hull position.
                P { x: 24_500., y: 14_800. }
            } else { P {
                x: if owner == 0 { self.field.width - 5000. } else { 5000. },
                y: if owner == 0 { 5800. } else { 8000. },
            } });
            let angle = (target - leader.p).heading();
            let range = target.dist(leader.p);
            let prefer = if leader.p.y < self.field.height * 0.52 { 1. } else { -1. };
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
                        x: p.x.clamp(2100., self.field.width - 2100.),
                        y: p.y.clamp(1650., self.field.height - 1650.),
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
                // cas-realtime-v10: hold fire unless the next volley can
                // actually hit — a 0% threshold means the shot is wasted.
                let gate = |w: &Self, c: &Contact, radar_only: bool| {
                    !w.v10_family() || w.volley_chance(s, c, radar_only).is_some_and(|chance| chance > 0.)
                };
                let radar;
                let chosen = if let Some(t) = targets.iter().find(|c| self.gun_candidate(s, c) && gate(self, c, false)) {
                    Some(t.id.as_str())
                } else {
                    radar = self
                        .radar_gun_contacts(s)
                        .filter(|t| self.gun_candidate(s, t) && gate(self, t, true))
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
                && (self.tick % CYCLE >= 160 || self.immediate_torpedoes())
                && self.can_torp(s)
            {
                let radar: Vec<_> = self.radar_torp_contacts(s).collect();
                for t in targets.iter().copied().chain(radar.iter()) {
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
    /// cas-realtime-v10 家族：夜战时 AI 舰组自行接通本舰未损坏的水面搜索
    /// 雷达。更早版本保持原行为（AI 从不开机），以保证旧局按原时序重演。
    /// 只在 drive_ai 执行路径生效，不进入给玩家的建议列表。
    fn radar_orders(&self, owner: usize, fid: u32) -> Vec<Value> {
        if !self.v10_family() || !self.radar_enabled() || self.environment().light != crate::night::Light::Night {
            return vec![];
        }
        let Ok(fleet) = self.fleet_for(owner, fid) else {
            return vec![];
        };
        let mut orders = vec![];
        for id in &fleet.members {
            for device in self.radar.own_observation(*id) {
                if device["powered"] == json!(false) && device["disabled"] == json!(false) {
                    orders.push(json!({"op":"radar_set","ship":id,"radar":device["id"],"powered":true}));
                }
            }
        }
        orders
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
            for r in self.radar_orders(owner, id) {
                if r["op"].as_str() == Some("radar_set") {
                    let _ = self.radar_power(owner, &r);
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
