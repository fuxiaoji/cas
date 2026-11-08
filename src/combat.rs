use crate::{
    model::*,
    world::{u, World},
};
use serde_json::{json, Value};

fn n(v: &Value) -> f64 {
    v.as_f64().unwrap_or(0.)
}
fn gun_multiplier(rules: &Value, barrels: u32, band: usize) -> f64 {
    n(&rules["gun_damage_multiplier"][((barrels.clamp(1, 16) - 1) / 2) as usize][band])
}
fn m_arc(a: f64, a1: [f64; 2], a2: Option<[f64; 2]>) -> bool {
    circle(a, a1) || a2.is_some_and(|b| circle(a, b))
}
fn aspect(heading: f64, bearing: f64) -> usize {
    let d = delta(heading, bearing).abs();
    if !(20. ..=160.).contains(&d) {
        2
    } else if (60. ..=120.).contains(&d) {
        0
    } else {
        1
    }
}
fn intercept(shooter: P, c: &Contact, weapon_speed: f64) -> (f64, f64) {
    let q = c.p() - shooter;
    let v = P::bearing(c.heading) * (c.speed * KNOT);
    let a = v.dot(v) - weapon_speed * weapon_speed;
    let b = 2. * q.dot(v);
    let d = q.dot(q);
    let discriminant = b * b - 4. * a * d;
    let mut t: f64 = 0.;
    if a.abs() > 1e-8 && discriminant >= 0. {
        let r = libm::sqrt(discriminant);
        let t0 = (-b + r) / (2. * a);
        let t1 = (-b - r) / (2. * a);
        t = if t0 > 0. && t1 > 0. {
            t0.min(t1)
        } else {
            t0.max(t1).max(0.)
        };
    } else if b < -1e-8 {
        t = -d / b;
    }
    let v = q + v * t;
    (v.heading(), v.len())
}

#[derive(Clone)]
struct Shot {
    ship: u32,
    target: u32,
    band: usize,
    barrels: u32,
    reaction: bool,
    radar_only: bool,
}
#[derive(Clone)]
pub(crate) struct Impact {
    pub(crate) victim: u32,
    amount: f64,
    owner: usize,
    torpedo: bool,
    pub(crate) at: P,
    penetrated: bool,
    flood_hits: u32,
}

impl Impact {
    pub(crate) fn gun(target: &Ship, amount: f64, owner: usize, penetrated: bool) -> Self {
        Self { victim: target.id, amount, owner, torpedo: false, at: target.p, penetrated, flood_hits: 0 }
    }
}

#[derive(Clone)]
struct Launch {
    ship: u32,
    side: usize,
    h: f64,
    mount: usize,
    count: u32,
    deep: bool,
}

impl World {
    pub(crate) fn torpedo_depths(&self) -> bool {
        matches!(
            self.version,
            crate::realtime::VERSION | crate::realtime::WINDOW_TORPEDO_VERSION
                | crate::campaign::live::VERSION | crate::campaign::live::WINDOW_TORPEDO_VERSION
        )
    }

    /// The v10 rule families: per-second torpedo launches, per-volley dice and
    /// the AI fire discipline. Earlier versions replay their frozen timing.
    pub(crate) fn v10_family(&self) -> bool {
        matches!(self.version, crate::realtime::VERSION | crate::campaign::live::VERSION)
    }

    /// v10 families fire torpedoes the moment the order is legal; earlier
    /// versions keep the CAS window-end launch. See the realtime torpedo ledger.
    pub(crate) fn immediate_torpedoes(&self) -> bool {
        self.v10_family()
    }

    /// The threshold the next volley from `s` at `c` would roll a fresh D100
    /// against in the real-time resolution. None when no gun bears or the
    /// contact has no live hull; the AI fire gate and the seat view use it.
    pub(crate) fn volley_chance(&self, s: &Ship, c: &Contact, radar_only: bool) -> Option<f64> {
        let (b, barrels) = self.gun_band(s, c)?;
        let t = self.ship(c.ship)?;
        let aid = self.mk4_gun_aid(s, c, radar_only);
        let modifier = aid.as_ref().map_or(0, |aid| {
            let env = self.environment();
            let visibility = if aid.ignore_low_visibility_modifier && env.light == crate::night::Light::Night
                && self.illumination_modifier(s, t).is_none() {
                crate::night::night_gun_modifier(env, crate::night::Lighting::None)
            } else { 0 };
            aid.fire_control_modifier + aid.land_clutter_modifier - visibility
        });
        let (chance, _) = self.gun_values(s, t, b, barrels, radar_only, &[], modifier, false);
        Some(chance)
    }

    fn torpedo_order(&self, request: &Value) -> E<TorpedoOrder> {
        let specified = ["depth", "mount", "count"].iter().any(|key| request.get(key).is_some());
        if specified && !self.torpedo_depths() {
            return Err("本局规则版本使用默认浅航整座齐射".into());
        }
        let deep = match request.get("depth") {
            None => false,
            Some(value) if value == "shallow" => false,
            Some(value) if value == "deep" => true,
            _ => return Err("鱼雷定深无效".into()),
        };
        let mount = request.get("mount").map(|_| u(request, "mount").map(|mount| mount as usize)).transpose()?;
        let count = request.get("count").map(|value| {
            value.as_u64().filter(|count| (1..=6).contains(count)).map(|count| count as u32)
                .ok_or("单座齐射须选择 1 至 6 枚鱼雷")
        }).transpose()?;
        Ok(TorpedoOrder { deep, mount, count })
    }

    fn torpedo_can_hit(&self, ship: &Ship, deep: bool) -> bool {
        match self.data.ships[ship.def].size.as_str() {
            "A" | "B" => true,
            "F" | "G" => !self.curved_movement(),
            _ => !deep,
        }
    }

    pub fn detect(&mut self, initial: bool) {
        if self.environment().light == crate::night::Light::Night {
            if self.v10_family() && !initial {
                // cas-realtime-v10: per-second hazard-rate acquisition.
                self.detect_night_realtime();
            } else {
                self.detect_night();
            }
            return;
        }
        if self.v10_family() && !initial {
            self.detect_day_realtime();
            return;
        }
        let rules = &self.data.rules;
        let full_sizes = self.curved_movement();
        for s in 0..2 {
            let observers: Vec<_> = self
                .ships
                .iter()
                .filter(|v| v.side == s && v.alive())
                .map(|v| (v.p, self.data.ships[v.def].size.clone()))
                .collect();
            let enemy: Vec<_> = self
                .ships
                .iter()
                .filter(|v| v.side != s && v.alive())
                .cloned()
                .collect();
            let old = std::mem::take(&mut self.contacts[s]);
            for t in &enemy {
                let def = &self.data.ships[t.def];
                let mut margin = f64::NEG_INFINITY;
                let known = old.iter().find(|c| c.ship == t.id);
                let automatic = n(&rules["visual_automatic_yd"]);
                let die = if known.is_some()
                    || observers
                        .iter()
                        .any(|(p, _)| p.dist(t.p) <= automatic * YARD)
                {
                    1
                } else {
                    self.d(100)
                };
                let column = rules["visual_roll_columns"]
                    .as_array()
                    .and_then(|a| {
                        a.iter()
                            .position(|x| x.as_u64().is_some_and(|k| die as u64 <= k))
                    })
                    .unwrap_or(4);
                for (p, size) in &observers {
                    let d = t.p.dist(*p) / YARD;
                    let base = if full_sizes {
                        u64::from(crate::night::surface_base_range_yd(
                            self.environment(), size, &def.size, t.speed, false, false,
                        ))
                    } else {
                        rules["visual_base_yd"][size][&def.size].as_u64().unwrap_or(0)
                    };
                    let limit = if known.is_some() {
                        base as f64
                    } else if full_sizes {
                        f64::from(crate::night::surface_detection_range_yd(base as u32, die as i32))
                    } else {
                        n(&rules["visual_chance_yd"][base.to_string()][column])
                    };
                    margin = margin.max(limit.max(automatic) - d);
                }
                if margin < 0. {
                    if known.is_some() {
                        self.add(
                            1 << s,
                            "lost",
                            "丢失一个水面接触".into(),
                            Some("CAS-5.4.1"),
                            None,
                        );
                    }
                    continue;
                }
                let id = known.map(|c| c.id.clone()).unwrap_or_else(|| {
                    let k = self.next_contacts[s];
                    self.next_contacts[s] += 1;
                    format!("C{k:02}")
                });
                if known.is_none() {
                    self.add(
                        1 << s,
                        "contact",
                        format!("发现水面接触 {id}"),
                        Some("CAS-5.4.1"),
                        Some(t.p),
                    );
                }
                self.contacts[s].push(Contact {
                    id,
                    x: t.p.x,
                    y: t.p.y,
                    heading: t.h,
                    speed: t.speed,
                    kind: Some(def.kind.to_ascii_lowercase()),
                    name: None,
                    ship: t.id,
                    first_cycle: known.map_or(if initial { 0 } else { self.tick / CYCLE }, |x| {
                        x.first_cycle
                    }),
                    acquisition_base_yd: 0,
                    acquisition_range_yd: 0,
                });
            }
        }
    }
    /// cas-realtime-v10: per-second day visual detection. The deterministic
    /// parts (known hulls, the automatic band, base range) resolve every
    /// second; the printed dice column becomes a per-second hazard rate whose
    /// per-window integral matches the CAS roll exactly.
    pub fn detect_day_realtime(&mut self) {
        let initial = false;
        let rules = &self.data.rules;
        let full_sizes = self.curved_movement();
        let automatic = n(&rules["visual_automatic_yd"]);
        for s in 0..2 {
            let observers: Vec<_> = self
                .ships
                .iter()
                .filter(|v| v.side == s && v.alive())
                .map(|v| (v.p, self.data.ships[v.def].size.clone()))
                .collect();
            if observers.is_empty() {
                continue;
            }
            let enemy: Vec<_> = self
                .ships
                .iter()
                .filter(|v| v.side != s && v.alive())
                .cloned()
                .collect();
            let old = std::mem::take(&mut self.contacts[s]);
            for t in &enemy {
                let def = &self.data.ships[t.def];
                let known = old.iter().find(|c| c.ship == t.id);
                // cas-realtime-v10 (5.4.5): a smoking target, or one hidden
                // behind a smoke screen, may only be sighted out to the
                // smoke cap (1,000 yd day / 500 yd night).
                let closest = observers
                    .iter()
                    .map(|(p, _)| *p)
                    .min_by(|a, b| a.dist(t.p).total_cmp(&b.dist(t.p)))
                    .unwrap_or(t.p);
                let smoke_limit: Option<u32> = if self.smoke_cap_yd(t).is_some()
                    || self.smoke_blocks_ray(closest, t.p)
                {
                    Some(if self.environment().light == crate::night::Light::Night {
                        500
                    } else {
                        1000
                    })
                } else {
                    None
                };
                let mut margin = f64::NEG_INFINITY;
                let mut in_automatic = false;
                for (p, size) in &observers {
                    let d = t.p.dist(*p) / YARD;
                    let base = if full_sizes {
                        u64::from(crate::night::surface_base_range_yd(
                            self.environment(), size, &def.size, t.speed, false, false,
                        ))
                    } else {
                        rules["visual_base_yd"][size][&def.size].as_u64().unwrap_or(0)
                    };
                    let cap = smoke_limit
                        .map_or(base as f64, |cap| (base as f64).min(f64::from(cap)));
                    margin = margin.max(cap - d);
                    if d <= automatic { in_automatic = true; }
                }
                let detected = if known.is_some() || in_automatic {
                    margin >= 0.
                } else if margin < 0. {
                    false
                } else {
                    // Marginal band: integrate the printed dice column over the
                    // current geometry into a per-second hazard rate.
                    let mut hits = 0u32;
                    for die in 1..=100i32 {
                        let column = rules["visual_roll_columns"]
                            .as_array()
                            .and_then(|a| {
                                a.iter().position(|x| x.as_u64().is_some_and(|k| die as u64 <= k))
                            })
                            .unwrap_or(4);
                        let reached = observers.iter().any(|(p, size)| {
                            let d = t.p.dist(*p) / YARD;
                            let base = if full_sizes {
                                u64::from(crate::night::surface_base_range_yd(
                                    self.environment(), size, &def.size, t.speed, false, false,
                                ))
                            } else {
                                rules["visual_base_yd"][size][&def.size].as_u64().unwrap_or(0)
                            };
                            let limit = if full_sizes {
                                f64::from(crate::night::surface_detection_range_yd(base as u32, die))
                            } else {
                                n(&rules["visual_chance_yd"][base.to_string()][column])
                            };
                            let limit = smoke_limit.map_or(limit, |cap| limit.min(f64::from(cap)));
                            limit.max(automatic) >= d
                        });
                        if reached { hits += 1; }
                    }
                    let window_chance = hits as f64 / 100.;
                    let per_second = crate::night::per_second_chance(window_chance, 1.);
                    (self.d(10_000) as f64 / 10_000.) < per_second
                };
                if !detected {
                    // cas-realtime-v10 (5.4.5): a tracked contact that drops
                    // behind smoke reports a lost track, like the night path.
                    if known.is_some() && smoke_limit.is_some() {
                        self.add(
                            1 << s,
                            "lost",
                            "目标进入烟幕，接触丢失".into(),
                            Some("RTS-SMOKE-01"),
                            Some(t.p),
                        );
                    }
                    continue;
                }
                let id = known.map(|c| c.id.clone()).unwrap_or_else(|| {
                    let k = self.next_contacts[s];
                    self.next_contacts[s] += 1;
                    format!("C{k:02}")
                });
                if known.is_none() {
                    self.add(
                        1 << s,
                        "contact",
                        format!("发现水面接触 {id}"),
                        Some("CAS-5.4.1"),
                        Some(t.p),
                    );
                }
                self.contacts[s].push(Contact {
                    id,
                    x: t.p.x,
                    y: t.p.y,
                    heading: t.h,
                    speed: t.speed,
                    kind: Some(def.kind.to_ascii_lowercase()),
                    name: None,
                    ship: t.id,
                    first_cycle: known.map_or(if initial { 0 } else { self.tick / CYCLE }, |x| {
                        x.first_cycle
                    }),
                    acquisition_base_yd: 0,
                    acquisition_range_yd: 0,
                });
            }
        }
    }

    pub fn update_tracks(&mut self) {
        let environment = self.environment();
        if environment.light == crate::night::Light::Night {
            self.update_night_tracks();
            return;
        }
        // A contact can be tracked continuously once spotted; checks are still only made on CAS intervals.
        let full_sizes = self.curved_movement();
        for s in 0..2 {
            let mut lost = 0;
            let ships = &self.ships;
            let data = self.data;
            self.contacts[s].retain_mut(|c| {
                let t = &ships[(c.ship - 1) as usize];
                let visible = t.alive()
                    && ships.iter().filter(|o| o.side == s && o.alive()).any(|o| {
                        let (observer, target) = (&data.ships[o.def].size, &data.ships[t.def].size);
                        let range = if full_sizes {
                            f64::from(crate::night::surface_base_range_yd(
                                environment, observer, target, t.speed, false, false,
                            )).max(f64::from(crate::night::automatic_visual_yd()))
                        } else {
                            n(&data.rules["visual_base_yd"][observer][target])
                        };
                        o.p.dist(t.p) <= YARD * range
                    });
                if visible {
                    c.x = t.p.x;
                    c.y = t.p.y;
                    c.heading = t.h;
                    c.speed = t.speed;
                } else {
                    lost += 1;
                }
                visible
            });
            for _ in 0..lost {
                self.add(
                    1 << s,
                    "lost",
                    "丢失一个水面接触".into(),
                    Some("CAS-5.4.1"),
                    None,
                );
            }
        }
    }
    fn gun_band(&self, s: &Ship, c: &Contact) -> Option<(usize, u32)> {
        let d = &self.data.ships[s.def];
        let dist = s.p.dist(c.p()) / YARD;
        let band = d.gun.range_yd.iter().position(|&max| dist <= max)?;
        let direction = norm((c.p() - s.p).heading() - s.h);
        let barrels: u32 = d
            .gun
            .mounts
            .iter()
            .enumerate()
            .filter(|(i, m)| !s.gun_mount_destroyed[*i] && !self.mount_lighting(s.id,*i) && m_arc(direction, m.arc, m.arc2))
            .map(|(_, m)| m.barrels)
            .sum();
        (barrels > 0).then_some((band, barrels))
    }
    fn is_reaction(&self, c: &Contact) -> bool {
        self.tick >= CYCLE && c.first_cycle == self.tick / CYCLE
    }
    pub fn gun_candidate(&self, s: &Ship, c: &Contact) -> bool {
        if self.realtime() {
            self.realtime_gun_candidate(s, c)
        } else {
            self.gun_band(s, c).is_some()
                && (!self.is_reaction(c) || s.gun_cycle != Some(self.tick / CYCLE))
        }
    }
    pub(crate) fn gun_contact(&self, s: &Ship, target: &str) -> E<(std::borrow::Cow<'_, Contact>, bool)> {
        match self.contact(s.side, target) {
            Ok(visual) => return Ok((std::borrow::Cow::Borrowed(visual), false)),
            Err(e) if !self.radar_enabled() => return Err(e),
            Err(_) => (),
        }
        self.radar_gun_contact(s, target)
            .map(|track| (std::borrow::Cow::Owned(track), true))
            .ok_or_else(|| "本舰没有可用的目标接触".into())
    }
    pub fn can_gun(&self, s: &Ship) -> bool {
        s.alive()
            && s.battery.order.is_none()
            && !self
                .pending
                .iter()
                .any(|p| p.ship == s.id && p.weapon == "gun")
            && (self.contacts[s.side].iter().any(|c| self.gun_candidate(s, c))
                || self.radar_gun_contacts(s).any(|c| self.gun_candidate(s, &c)))
    }
    pub fn can_torp(&self, s: &Ship) -> bool {
        s.alive()
            && s.ammo > 0
            && !self
                .pending
                .iter()
                .any(|p| p.ship == s.id && p.weapon == "torpedo")
            && (self.contacts[s.side].iter().any(|c| self.torp_candidate(s, c))
                || self.radar_torp_contacts(s).any(|c| self.torp_candidate(s, &c)))
    }
    fn torp_candidate(&self, s: &Ship, c: &Contact) -> bool {
        let (a, b) = self.project_launch(s, c);
        !self.is_reaction(c) && self.torp_solution(&a, &b, None, TorpedoOrder::default()).3.is_none()
    }
    fn torpedo_contact(&self, s: &Ship, target: &str) -> E<std::borrow::Cow<'_, Contact>> {
        if let Ok(c) = self.contact(s.side, target) { return Ok(std::borrow::Cow::Borrowed(c)); }
        if self.campaign.is_some() && target.starts_with('R') {
            return self.radar_torp_contact(s, target).map(std::borrow::Cow::Owned)
                .ok_or_else(|| "本舰没有连续的直接雷达位置，无法解算鱼雷交会".into());
        }
        Err("目标接触已丢失".into())
    }
    fn mount(&self, s: &Ship, h: f64, order: TorpedoOrder) -> Option<(usize, u32)> {
        let def = self.data.ships[s.def].torpedo.as_ref()?;
        let a = norm(h - s.h);
        def.mounts
            .iter()
            .enumerate()
            .filter(|(i, m)| order.mount.is_none_or(|mount| *i == mount) && m_arc(a, m.arc, m.arc2))
            .find_map(|(i, _)| {
                let remaining = s.torp_mount_remaining[i].min(s.ammo).min(6);
                let count = order.count.unwrap_or(remaining);
                (count > 0 && count <= remaining).then_some((i, count))
            })
    }
    fn friendly_torp(&self, s: &Ship, h: f64, r: f64, v: f64, deep: bool) -> bool {
        let forward = P::bearing(h);
        self.ships
            .iter()
            .filter(|t| t.id != s.id && t.side == s.side && t.alive())
            .filter(|t| !self.torpedo_depths() || self.torpedo_can_hit(t, deep))
            .any(|t| {
                let vel = P::bearing(t.h) * (t.speed * KNOT);
                let offset = t.p - s.p;
                let den = v - vel.dot(forward);
                if den <= 0. {
                    return false;
                }
                let time = offset.dot(forward) / den;
                time > 0.
                    && time * v <= r
                    && (offset + vel * time).cross(forward).abs() <= 500. * YARD
            })
    }
    fn torp_solution(
        &self,
        s: &Ship,
        c: &Contact,
        angle: Option<f64>,
        order: TorpedoOrder,
    ) -> (f64, f64, bool, Option<String>) {
        let Some(t) = &self.data.ships[s.def].torpedo else {
            return (0., 0., false, Some("这艘舰未装鱼雷".into()));
        };
        let range = t.range_yd * YARD;
        let (suggest, intercept_range) = intercept(s.p, c, t.speed_knots * KNOT);
        let h = norm(angle.unwrap_or(suggest));
        let reason = if s.ammo == 0 {
            Some("鱼雷已耗尽")
        } else if c.kind.is_some() && self.ship(c.ship).is_some_and(|target| !self.torpedo_can_hit(target, order.deep))
        {
            Some(if order.deep { "深航直航鱼雷无法击中此吃水级别" } else { "直航鱼雷无法击中这类小艇" })
        } else if self.is_reaction(c) {
            Some("刚发现的接触不能在此窗口放雷")
        } else if angle.is_none() && intercept_range > range {
            Some("预计交会点超出鱼雷航程")
        } else if self.mount(s, h, order).is_none() {
            Some(if order.count.is_some() || order.mount.is_some() {
                "指定齐射数量超出可用发射管，或射向超出该座射界"
            } else { "射向不在剩余发射管的可用扇区" })
        } else {
            None
        };
        (
            h,
            range,
            self.friendly_torp(s, h, range, t.speed_knots * KNOT, order.deep),
            reason.map(str::to_owned),
        )
    }
    pub fn preview_aim(&self, owner: usize, r: &Value) -> E<Value> {
        let id = u(r, "ship")?;
        let s = self.ship_for(owner, id)?;
        let target = r["target"].as_str().ok_or("请选择一个敌方接触")?;
        if r["weapon"] == "gun" {
            if self.realtime() {
                return self.realtime_aim(s, target);
            }
            let (c, radar_only) = self.gun_contact(s, target)?;
            let d = &self.data.ships[s.def];
            let barrels = self.gun_band(s, &c).map_or(0, |(_, k)| k);
            let error = if barrels == 0 {
                Some("目标超出射程或没有炮位能对准")
            } else if self
                .pending
                .iter()
                .any(|p| p.ship == s.id && p.weapon == "gun")
            {
                Some("该舰已有待执行的炮击")
            } else if self.is_reaction(&c) && s.gun_cycle == Some(self.tick / CYCLE) {
                Some("该舰本窗口已开炮")
            } else {
                None
            };
            let mut solution = json!({"valid":error.is_none(),"barrels":barrels,"error":error,"heading":(c.p()-s.p).heading(),"arcs":[],"range":d.gun.range_yd[3]*YARD,"friendly":false});
            if radar_only {
                solution["targetSource"] = json!("surface_radar");
            }
            return Ok(solution);
        }
        let c = self.torpedo_contact(s, target)?;
        let order = self.torpedo_order(r)?;
        let angle = r
            .get("heading")
            .map(|h| h.as_f64().filter(|v| v.is_finite()).ok_or("射向无效"))
            .transpose()?;
        let (future, projected) = if self.immediate_torpedoes() {
            // The salvo leaves this second; the preview shows the launch-moment
            // solution instead of the window-end projection.
            (s.clone(), c.into_owned())
        } else {
            self.project_launch(s, &c)
        };
        let (h, range, friendly, error) = self.torp_solution(&future, &projected, angle, order);
        let arcs: Vec<_> = self.data.ships[s.def]
            .torpedo
            .iter()
            .flat_map(|t| t.mounts.iter().enumerate())
            .filter(|(i, _)| order.mount.is_none_or(|mount| *i == mount)
                && s.torp_mount_remaining[*i].min(s.ammo) >= order.count.unwrap_or(1))
            .flat_map(|(_, m)| [Some(m.arc), m.arc2])
            .flatten()
            .map(|a| json!({"from":norm(a[0]+future.h),"to":norm(a[1]+future.h)}))
            .collect();
        let mut view = json!({"heading":h,"range":range,"arcs":arcs,"friendly":friendly,"valid":error.is_none(),"error":error});
        if self.torpedo_depths() {
            view["depth"] = json!(if order.deep { "deep" } else { "shallow" });
            if let Some((mount, count)) = self.mount(&future, h, order) {
                view["torpedoMount"] = json!(mount);
                view["torpedoCount"] = json!(count);
            }
        }
        Ok(view)
    }
    pub fn queue_fire(&mut self, owner: usize, r: &Value, manual: bool) -> E<()> {
        let id = u(r, "ship")?;
        let s = self.ship_for(owner, id)?;
        let target = r["target"].as_str().ok_or("请把火力拖向一个接触")?;
        let weapon = r["weapon"].as_str().ok_or("武器不可用")?;
        if self.fire_hold[owner] > self.tick {
            return Err("日军刚被发现，本席在 D6/3 战术窗口内不能开火".into());
        }
        if weapon == "gun" && self.realtime() {
            return self.order_realtime_gun(owner, id, target, manual);
        }
        if weapon == "torpedo" && self.immediate_torpedoes() {
            return self.order_immediate_torpedo(owner, r, id, target, manual);
        }
        if self
            .pending
            .iter()
            .any(|p| p.ship == id && p.weapon == weapon)
        {
            return Err("该武器已有一条待执行命令".into());
        }
        let mut heading = None;
        let mut reaction = false;
        let mut torpedo = TorpedoOrder::default();
        match weapon {
            "gun" => {
                let (c, _) = self.gun_contact(s, target)?;
                self.gun_band(s, &c).ok_or("目标超出射程或没有炮位能对准")?;
                reaction = self.is_reaction(&c);
                if reaction && s.gun_cycle == Some(self.tick / CYCLE) {
                    return Err("该舰本战术窗口已开炮".into());
                }
            }
            "torpedo" => {
                let c = self.torpedo_contact(s, target)?;
                torpedo = self.torpedo_order(r)?;
                let angle = r
                    .get("heading")
                    .map(|h| h.as_f64().filter(|v| v.is_finite()).ok_or("射向无效"))
                    .transpose()?;
                let (future, projected) = self.project_launch(s, &c);
                let (h, _, friendly, err) = self.torp_solution(&future, &projected, angle, torpedo);
                if let Some(e) = err {
                    return Err(e);
                }
                if friendly && !manual {
                    return Err("AI 不向已知友舰航迹放雷".into());
                }
                if self.torpedo_depths() {
                    let (mount, count) = self.mount(&future, h, torpedo).ok_or("指定发射座不可用")?;
                    torpedo.mount = Some(mount);
                    torpedo.count = Some(count);
                }
                heading = Some(h);
            }
            _ => return Err("武器不可用".into()),
        };
        let fleet = s.fleet;
        let expires = (self.tick / CYCLE + 1) * CYCLE;
        let source = s.name.clone();
        self.pending.push(Fire {
            side: owner,
            ship: id,
            weapon: weapon.into(),
            target: target.into(),
            heading,
            expires,
            torpedo,
        });
        if manual {
            if let Some(f) = fleet.and_then(|i| self.fleet_mut(i)) {
                if weapon == "gun" {
                    f.ai.gun = false
                } else {
                    f.ai.torpedo = false
                }
            }
        }
        self.add(
            1 << owner,
            "ordered",
            format!(
                "{source} · {}已下令，等待{}",
                if weapon == "gun" { "炮击" } else { "鱼雷" },
                if reaction {
                    "反应火力窗口"
                } else {
                    "计划火力窗口"
                }
            ),
            Some("RTS-FIRE-01"),
            None,
        );
        Ok(())
    }
    fn validate_shot(&self, p: &Fire, planned: bool) -> E<Option<Shot>> {
        let s = self.ship_for(p.side, p.ship)?;
        let (c, radar_only) = self.gun_contact(s, &p.target)?;
        if !self.ship(c.ship).is_some_and(Ship::alive) {
            return Err("目标已失效".into());
        }
        let reaction = !planned;
        if reaction && !self.is_reaction(&c) {
            return Ok(None);
        }
        if s.gun_cycle == Some(self.tick / CYCLE) {
            return Err("本窗口炮位已使用".into());
        }
        let (band, barrels) = self.gun_band(s, &c).ok_or("执行时目标已超出射程或射界")?;
        Ok(Some(Shot {
            ship: s.id,
            target: c.ship,
            band,
            barrels,
            reaction,
            radar_only,
        }))
    }
    pub fn resolve_fire(&mut self, planned: bool) {
        self.resolve_illumination(planned);
        if self.pending.is_empty() {
            return;
        }
        let mut pending = std::mem::take(&mut self.pending);
        pending.sort_by(|a, b| (a.ship, &a.weapon).cmp(&(b.ship, &b.weapon)));
        let mut shots = vec![];
        let mut launches = vec![];
        for p in pending {
            let hold = !planned && self.immediate_torpedoes() && p.weapon == "torpedo";
            if hold && p.expires < self.tick {
                if p.side == 0 || self.fleets.iter().any(|f| f.members.contains(&p.ship) && f.ai.mode == "manual") {
                    self.add(1 << p.side, "rejected", "鱼雷射向始终未到或目标丢失，未消耗鱼雷".into(),
                        Some("RTS-TORP-01"), None);
                }
                continue;
            }
            let run = if planned {
                p.expires <= self.tick
            } else if hold {
                true
            } else if !self.radar_enabled() {
                p.weapon == "gun" && self.contact(p.side, &p.target).is_ok_and(|c| self.is_reaction(c))
            } else {
                p.weapon == "gun"
                    && self
                        .ship_for(p.side, p.ship)
                        .ok()
                        .and_then(|s| self.gun_contact(s, &p.target).ok())
                        .is_some_and(|(c, _)| self.is_reaction(&c))
            };
            if !run {
                self.pending.push(p);
                continue;
            }
            let fail = if p.weapon == "gun" {
                match self.validate_shot(&p, planned) {
                    Ok(Some(s)) => {
                        shots.push(s);
                        None
                    }
                    Ok(None) => {
                        self.pending.push(p.clone());
                        None
                    }
                    Err(e) => Some(e),
                }
            } else {
                match self.validate_launch(&p) {
                    Ok(l) => {
                        launches.push(l);
                        None
                    }
                    Err(e) => {
                        // A held v10 salvo keeps waiting while only its tubes
                        // fail to bear; any other refusal drops the order.
                        if hold && e.contains("射向") {
                            self.pending.push(p);
                            continue;
                        }
                        Some(e)
                    }
                }
            };
            if let Some(e) = fail {
                self.add(
                    1 << p.side,
                    "rejected",
                    format!("未开火：{e}"),
                    Some("RTS-FIRE-01"),
                    None,
                );
            }
        }
        let planned_targets: Vec<u32> = shots.iter().map(|s| s.target).collect();
        let mut impacts = vec![];
        for s in shots {
            if let Some(i) = self.fire_gun(s, &planned_targets) {
                impacts.push(i)
            }
        }
        for l in launches {
            self.fire_torp(l);
        }
        self.apply_impacts(impacts);
    }
    /// cas-realtime-v10 家族的逐秒鱼雷：下令当秒发射，射向按发射时刻真实
    /// 位置解算；CAS §6.3 的交会、舷向、概率与实际命中时刻不变。更早版本
    /// 保持窗末发射的登记时序，见实时鱼雷台账。
    fn order_immediate_torpedo(&mut self, owner: usize, r: &Value, id: u32, target: &str, manual: bool) -> E<()> {
        let s = self.ship_for(owner, id)?;
        let c = self.torpedo_contact(s, target)?;
        let torpedo = self.torpedo_order(r)?;
        let angle = r
            .get("heading")
            .map(|h| h.as_f64().filter(|v| v.is_finite()).ok_or("射向无效"))
            .transpose()?;
        if s.jammed_until > self.tick {
            return Err("该舰正在处理转向损伤".into());
        }
        let explicit = torpedo.mount.is_some() || torpedo.count.is_some();
        let (h, _, friendly, err) = self.torp_solution(s, &c, angle, torpedo);
        if let Some(e) = &err {
            // cas-realtime-v10: an automatic salvo whose tubes simply do not
            // bear yet is held, not refused; every other refusal stands.
            let arcs_not_bearing = e.contains("射向") && !explicit;
            if !arcs_not_bearing {
                return Err(e.clone());
            }
        }
        if friendly && !manual {
            return Err("AI 不向已知友舰航迹放雷".into());
        }
        match self.mount(s, h, torpedo) {
            Some((mount, count)) if count > 0 => {
                let fleet = s.fleet;
                let side = s.side;
                self.fire_torp(Launch { ship: id, side, h, mount, count, deep: torpedo.deep });
                if manual {
                    if let Some(f) = fleet.and_then(|i| self.fleet_mut(i)) {
                        f.ai.torpedo = false;
                    }
                }
                Ok(())
            }
            _ if explicit => Err("指定齐射数量超出可用发射管，或射向超出该座射界".into()),
            _ => {
                // The tubes cannot bear this second — the ship is mid-turn.
                // Hold the order and launch the moment the arcs come round;
                // an unfired order never expends a torpedo.
                let fleet = s.fleet;
                self.pending.push(Fire {
                    side: owner,
                    ship: id,
                    weapon: "torpedo".into(),
                    target: target.into(),
                    heading: Some(h),
                    expires: self.tick + crate::realtime::TORPEDO_HOLD,
                    torpedo,
                });
                if manual {
                    if let Some(f) = fleet.and_then(|i| self.fleet_mut(i)) {
                        f.ai.torpedo = false;
                    }
                }
                Ok(())
            }
        }
    }

    fn validate_launch(&self, p: &Fire) -> E<Launch> {
        let s = self.ship_for(p.side, p.ship)?;
        let c = self.torpedo_contact(s, &p.target)?;
        if !self.ship(c.ship).is_some_and(Ship::alive) {
            return Err("鱼雷的原目标已失效".into());
        }
        if s.jammed_until > self.tick {
            return Err("该舰正在处理转向损伤".into());
        }
        let (h, _, _, e) = self.torp_solution(s, &c, p.heading, p.torpedo);
        if let Some(e) = e {
            return Err(e);
        }
        let (mount, count) = self.mount(s, h, p.torpedo).ok_or("发射管已不可用")?;
        if count == 0 {
            return Err("发射管没有鱼雷".into());
        }
        Ok(Launch {
            ship: s.id,
            side: s.side,
            h,
            mount,
            count,
            deep: p.torpedo.deep,
        })
    }
    /// CAS 5.1.2 / 6.1: at long and extreme range, every additional ship
    /// firing at the same target costs -1 (over-concentration).
    fn over_concentration(&self, s: &Ship, t: &Ship) -> i32 {
        self.ships
            .iter()
            .filter(|o| o.side == s.side && o.id != s.id && o.alive())
            .filter(|o| {
                o.battery.order.as_ref().is_some_and(|order| {
                    self.contact(o.side, &order.target)
                        .ok()
                        .is_some_and(|contact| contact.ship == t.id)
                })
            })
            .count() as i32
    }

    pub(crate) fn gun_values(&self,s:&Ship,t:&Ship,b:usize,barrels:u32,radar_only:bool,planned_targets:&[u32],extra:i32,prelight:bool)->(f64,u32){
        let td = &self.data.ships[t.def];
        let gun = &self.data.ships[s.def].gun;
        let base = n(&self.data.rules["gun_base_hit"][gun.gs.to_string()][b]);
        let mut modifiers = extra;
        modifiers += ((barrels.saturating_sub(1) / 2).min(5)) as i32;
        modifiers += if t.speed < 0.05 {
            2
        } else if t.speed <= 10. {
            1
        } else if t.speed < 25. {
            0
        } else if t.speed < 35. {
            -2
        } else {
            -3
        };
        let target_aspect = aspect(t.h, (s.p - t.p).heading());
        modifiers += if td.size == "B" || self.curved_movement() && td.size == "A" {
            [1, 0, -1][target_aspect]
        } else {
            [0, -1, -2][target_aspect]
        };
        if self.v10_family() && b >= 2 {
            modifiers -= self.over_concentration(s, t);
        }
        // CAS 6.1.1: a single forward director cannot control aft mounts once
        // the target falls outside its arc; those mounts use local control (-2).
        if self.v10_family() {
            if let Some(arc) = gun.director_arc {
                let relative = norm((t.p - s.p).heading() - s.h);
                if !circle(relative, arc) && gun.mounts.iter().any(|mount| {
                    let center = norm(mount.arc[0] + norm(mount.arc[1] - mount.arc[0]) / 2.);
                    (90. ..270.).contains(&center)
                }) {
                    modifiers -= 2;
                }
            }
        }
        if self.environment().light == crate::night::Light::Night {
            let mut lighting = (!prelight).then(||self.illumination_modifier(s,t)).flatten();
            // cas-realtime-v10 (5.4.4.1): a target held in a friendly
            // searchlight is Illuminated; the ship firing with its own light on
            // suffers the UsingSearchlight penalty on top.
            if lighting.is_none() {
                if let Some((_, range_yd)) = self.searchlight_lit(s.side, t.id) {
                    if s.p.dist(t.p) / YARD <= f64::from(range_yd) {
                        lighting = Some(crate::night::night_gun_modifier(self.environment(), crate::night::Lighting::Illuminated));
                    }
                }
            }
            modifiers += lighting.unwrap_or_else(||crate::night::night_gun_modifier(self.environment(), crate::night::Lighting::None));
            if s.searchlight.is_some() {
                modifiers += crate::night::night_gun_modifier(self.environment(), crate::night::Lighting::UsingSearchlight);
            }
        } else if if self.realtime() {
            self.realtime_point_blank(s, t)
        } else {
            s.p.dist(t.p) / YARD <= gun.range_yd[0] / 2.
        } {
            modifiers += 4;
        }
        if s.fire_control_damage {
            modifiers -= 2;
        }
        if radar_only {
            modifiers += crate::radar::search_fire_modifier();
        }
        if !planned_targets.contains(&s.id) && !self.incoming_this_cycle.contains(&s.id) {
            modifiers += 1;
        }
        let cycle = self.tick / CYCLE;
        let old = self.gun_streak[(s.id - 1) as usize];
        let streak = if old.0 == t.id && old.1 + 1 >= cycle {
            old.2 + u32::from(!self.realtime() || old.1 != cycle)
        } else {
            1
        };
        if streak == 1 && b >= 2 {
            modifiers -= 2
        }
        if streak >= 3 {
            modifiers += 1
        }
        ((base + modifiers as f64 * if b <= 1 { 4. } else { 2. }).clamp(0., 90.),streak)
    }

    fn realtime_point_blank(&self, s: &Ship, target: &Ship) -> bool {
        let env = self.environment();
        let gun = &self.data.ships[s.def].gun;
        let cutoff = (gun.range_yd[0] / 200.).floor() * 100.;
        env.visibility >= 30 && s.p.dist(target.p) / YARD <= cutoff
    }

    pub(crate) fn fire_realtime_volleys(&mut self, volleys: Vec<crate::realtime::Volley>) {
        // The collection phase has already checked every ordered gun against
        // the same second's observations. No shell damage is applied here.
        let threatened: Vec<_> = volleys.iter().map(|volley| volley.contact.ship).collect();
        for volley in volleys {
            let Some(s) = self.ship(volley.ship).filter(|s| s.alive()).cloned() else { continue };
            let Some(t) = self.ship(volley.contact.ship).filter(|t| t.alive()).cloned() else { continue };
            let gun = &self.data.ships[s.def].gun;
            let td = &self.data.ships[t.def];
            let b = volley.band;
            let aid = self.mk4_gun_aid(&s, &volley.contact, volley.radar_only);
            let modifier = aid.as_ref().map_or(0, |aid| {
                let env = self.environment();
                let visibility = if aid.ignore_low_visibility_modifier && env.light == crate::night::Light::Night
                    && self.illumination_modifier(&s, &t).is_none() {
                    crate::night::night_gun_modifier(env, crate::night::Lighting::None)
                } else { 0 };
                aid.fire_control_modifier + aid.land_clutter_modifier - visibility
            });
            let (chance, streak) = self.gun_values(&s, &t, b, volley.battery_barrels, volley.radar_only, &threatened, modifier, false);
            let (roll, deck_roll) = self.realtime_fire_dice(s.id, b >= 2 && chance > 0.);
            let cycle = self.tick / CYCLE;
            self.gun_streak[(s.id - 1) as usize] = (t.id, cycle, streak);
            self.ship_mut(s.id).unwrap().gun_cycle = Some(cycle);
            if !self.fired_this_cycle.contains(&s.id) { self.fired_this_cycle.push(s.id); }
            if !self.incoming_this_cycle.contains(&t.id) { self.incoming_this_cycle.push(t.id); }
            let range = ["近", "中", "远", "极远"][b];
            let sight = if aid.is_some() { "火控雷达 Mk4 · " }
                else if volley.radar_only { "水面搜索雷达 · " } else { "" };
            self.add(1 << s.side, "gun", format!("{} · {}{}射程，{} 门主炮实际发射",
                s.name, sight, range, volley.barrels),
                Some("RTS-GUN-04"), Some(s.p));
            self.last_event_ship(&s);
            if self.curved_movement() { self.last_voice(s.side, Some("fire")); }
            let impact = if roll as f64 <= chance {
                let multiplier = gun_multiplier(&self.data.rules, volley.battery_barrels, b);
                let part = f64::from(volley.barrels) / f64::from(volley.battery_barrels) * f64::from(volley.reload) / f64::from(CYCLE);
                let mut damage = gun.damage[b] * multiplier * part * if self.realtime_point_blank(&s, &t) { 2. } else { 1. };
                let deck = deck_roll.is_some_and(|die| b >= 2 && die > if b == 2 { 40 } else { 30 });
                let armor = if deck { td.armor_deck } else { td.armor_belt };
                let pen = if deck { &gun.pen_deck } else { &gun.pen_belt };
                let mut penetrated = true;
                if let Some(p) = pen.get(b).copied().flatten() {
                    if p <= armor && armor > 0. {
                        damage *= 0.5;
                        penetrated = false;
                    }
                    if gun.armor_piercing && armor <= 2. && p >= armor + 10. {
                        damage *= 0.1;
                    }
                }
                Some(Impact::gun(&t, damage, s.side, penetrated))
            } else { None };
            self.launch_realtime_shell(&s, &t, &volley.contact, volley.barrels, impact);
        }
    }
    fn fire_gun(&mut self, shot: Shot, planned_targets: &[u32]) -> Option<Impact> {
        let s = self.ship(shot.ship)?.clone();
        let t = self.ship(shot.target)?.clone();
        let gun = &self.data.ships[s.def].gun;
        let td = &self.data.ships[t.def];
        let b=shot.band;
        let cycle=self.tick/CYCLE;
        let (chance,streak)=self.gun_values(&s,&t,b,shot.barrels,shot.radar_only,planned_targets,0,false);
        let roll = self.d(100);
        self.gun_streak[(s.id - 1) as usize] = (t.id, cycle, streak);
        let bearing = (t.p - s.p).heading();
        let relative = norm(bearing - s.h);
        let bearings = gun
            .mounts
            .iter()
            .enumerate()
            .map(|(i, m)| {
                (!s.gun_mount_destroyed[i] && !self.mount_lighting(s.id,i) && m_arc(relative, m.arc, m.arc2)).then_some(bearing)
            })
            .collect();
        let until = self.tick + SHELL_FLIGHT;
        let firing = self.ship_mut(s.id).unwrap();
        firing.gun_cycle = Some(cycle);
        firing.gun_mount_bearings = bearings;
        firing.gun_bearing_until = until;
        self.fired_this_cycle.push(s.id);
        self.incoming_this_cycle.push(t.id);
        let range = ["近", "中", "远", "极远"][b];
        self.add(
            1 << s.side,
            "gun",
            if shot.radar_only {
                format!("{} · 使用本舰水面搜索雷达炮击，{} 门", s.name, shot.barrels)
            } else { format!(
                "{} · {}{}射程，{} {} 门 · 命中阈值 {:.0}% / D100 {}",
                s.name,
                if shot.reaction {
                    "反应火力 · "
                } else {
                    ""
                },
                range,
                gun.name,
                shot.barrels,
                chance,
                roll
            ) },
            Some("CAS-6.1.3"),
            Some(s.p),
        );
        if roll as f64 > chance {
            if self.version != LEGACY_VERSION && !shot.radar_only {
                self.launch_shell(&s, &t, shot.barrels, shot.reaction, None);
            }
            return None;
        }
        let multiplier = gun_multiplier(&self.data.rules, shot.barrels, b);
        let mut damage = gun.damage[b] * multiplier * (if shot.reaction { 0.5 } else { 1. });
        let deck = b >= 2 && self.d(100) > (if b == 2 { 40 } else { 30 });
        let armor = if deck { td.armor_deck } else { td.armor_belt };
        let pen = if deck { &gun.pen_deck } else { &gun.pen_belt };
        let mut penetrated = true;
        if let Some(p) = pen.get(b).copied().flatten() {
            if p <= armor && armor > 0. {
                damage *= 0.5;
                penetrated = false;
            }
            if gun.armor_piercing && armor <= 2. && p >= armor + 10. {
                damage = libm::round(damage * 0.1);
            }
        }
        let impact = Impact::gun(&t, damage, s.side, penetrated);
        if self.version == LEGACY_VERSION || shot.radar_only {
            Some(impact)
        } else {
            self.launch_shell(&s, &t, shot.barrels, shot.reaction, Some(impact));
            None
        }
    }
    fn fire_torp(&mut self, l: Launch) {
        let s = self.ship(l.ship).unwrap().clone();
        let d = self.data.ships[s.def].torpedo.as_ref().unwrap();
        let mut torpedo = Torpedo {
            side: l.side,
            ship: l.ship,
            p: s.p,
            h: l.h,
            remaining: d.range_yd * YARD,
            speed: d.speed_knots * KNOT,
            warhead: d.warhead,
            count: l.count,
            traveled: 0.,
            born: self.tick,
            origin: s.p,
            view_ids: crate::world::seat_ids(1 << l.side, &mut self.torp_ids),
            first_visible: None,
            launch_sighted: false,
            impact_sighted: false,
            contact_fuze: d.contact_fuze,
            deep: l.deep,
            single_mode: false,
            tested: vec![],
        };
        let tick = self.tick;
        let per_tube = self.torpedo_depths();
        let v10 = self.v10_family();
        let reload = d.reload_seconds;
        let ship = self.ship_mut(l.ship).unwrap();
        ship.ammo -= l.count;
        ship.torp_cycle = Some(tick / CYCLE);
        if per_tube {
            ship.torp_mount_remaining[l.mount] -= l.count;
        } else {
            ship.torp_mount_remaining[l.mount] = 0;
        }
        // cas-realtime-v10 (CAS 6.3): a mount with a printed reload starts
        // refilling from its reserve after the stated interval.
        if v10
            && reload.is_some()
            && ship.torp_reserve[l.mount] > 0
            && ship.torp_reload_at[l.mount] == 0
        {
            ship.torp_reload_at[l.mount] = tick + reload.unwrap();
        }
        self.add(
            1 << l.side,
            "torpedo",
            format!(
                "{} 发射 {} 枚{}{}直航鱼雷 · 航向 {:.0}°",
                s.name, l.count, d.name, if !per_tube { "" } else if l.deep { "深航" } else { "浅航" }, l.h
            ),
            Some("CAS-6.3.1"),
            Some(s.p),
        );
        self.last_event_ship(&s);
        if self.curved_movement() { self.last_voice(s.side, Some("fire")); }
        self.observe_torpedo_launch(&mut torpedo);
        self.torps.push(torpedo);
    }
    fn hit_rolls(&mut self, table: &str, run: f64, spread: u32, stopped: bool) -> u32 {
        static TABLE_I: std::sync::OnceLock<Value> = std::sync::OnceLock::new();
        let r = if table == "I" {
            TABLE_I.get_or_init(|| serde_json::from_str(include_str!("../data/rules/torpedo-table-i.json")).expect("verified CAS Table I"))
        } else {
            &self.data.rules["torpedo_hit"][table]
        };
        let Some(rows) = r.as_array() else { return 0 };
        let k = (spread - 1) as usize;
        let usable: Vec<_> = rows
            .iter()
            .filter(|row| {
                row[1][k]
                    .as_array()
                    .is_some_and(|a| a.len() == spread as usize)
            })
            .collect();
        let Some((ix, _)) = usable.iter().enumerate().min_by(|(_, a), (_, b)| {
            let x = n(&a[0]);
            let y = n(&b[0]);
            (x - run)
                .abs()
                .total_cmp(&(y - run).abs())
                .then_with(|| y.total_cmp(&x))
        }) else {
            return 0;
        };
        let row = usable[ix.saturating_sub(if stopped { 2 } else { 0 })];
        let chance: Vec<u32> = row[1][k]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_u64().unwrap_or(0) as u32)
            .collect();
        let roll = self.d(100);
        chance
            .iter()
            .enumerate()
            .rev()
            .find(|(_, p)| roll <= **p)
            .map_or(0, |(i, _)| i as u32 + 1)
    }
    /// cas-realtime-v10 (CAS 6.1.5): the secondary battery fires on its own
    /// reload cycle at the main battery's target, or the nearest visible
    /// contact. Hit chance uses the same GS table as the main battery; damage
    /// and penetration use the secondary gun's own row.
    pub(crate) fn resolve_secondaries(&mut self) {
        if !self.v10_family() {
            return;
        }
        let tick = self.tick;
        let ids: Vec<u32> = self
            .ships
            .iter()
            .filter(|s| s.alive() && s.secondary_ready <= tick)
            .map(|s| s.id)
            .collect();
        let mut impacts = Vec::new();
        let mut events = Vec::new();
        for id in ids {
            let Some(s) = self.ship(id).cloned() else { continue };
            let Some(gun) = self.data.ships[s.def].secondary.clone() else { continue };
            let target = s
                .battery
                .order
                .as_ref()
                .and_then(|order| self.contact(s.side, &order.target).ok().map(|c| c.ship))
                .or_else(|| {
                    self.contacts[s.side]
                        .iter()
                        .map(|c| c.ship)
                        .filter(|target| self.ship(*target).is_some_and(Ship::alive))
                        .min_by(|a, b| {
                            let da = self.ship(*a).map_or(f64::INFINITY, |t| s.p.dist(t.p));
                            let db = self.ship(*b).map_or(f64::INFINITY, |t| s.p.dist(t.p));
                            da.total_cmp(&db)
                        })
                });
            let Some(t) = target.and_then(|id| self.ship(id).cloned()).filter(|t| t.alive()) else {
                continue;
            };
            let distance = s.p.dist(t.p) / YARD;
            let Some(band) = gun.range_yd.iter().position(|max| distance <= *max) else {
                continue;
            };
            let relative = norm((t.p - s.p).heading() - s.h);
            let barrels: u32 = gun
                .mounts
                .iter()
                .filter(|mount| m_arc(relative, mount.arc, mount.arc2))
                .map(|mount| mount.barrels)
                .sum();
            if barrels == 0 {
                continue;
            }
            let chance = self.gun_values(&s, &t, band, barrels, false, &[], 0, false).0;
            if (self.d(100) as f64) <= chance {
                let td = &self.data.ships[t.def];
                let deck = band >= 2 && self.d(100) > if band == 2 { 40 } else { 30 };
                let armor = if deck { td.armor_deck } else { td.armor_belt };
                let pen = if deck { &gun.pen_deck } else { &gun.pen_belt };
                let mut damage = gun.damage[band] * gun_multiplier(&self.data.rules, barrels, band);
                if self.realtime_point_blank(&s, &t) {
                    damage *= 2.;
                }
                let mut penetrated = true;
                if let Some(p) = pen.get(band).copied().flatten() {
                    if p <= armor && armor > 0. {
                        damage *= 0.5;
                        penetrated = false;
                    }
                    if gun.armor_piercing && armor <= 2. && p >= armor + 10. {
                        damage *= 0.1;
                    }
                }
                impacts.push(Impact::gun(&t, damage, s.side, penetrated));
                events.push((s.side, s.name.clone(), t.name.clone(), s.p));
            }
            let reload = gun.reload_seconds.unwrap_or(if gun.caliber_mm <= 76. {
                3
            } else if gun.caliber_mm <= 128. {
                4
            } else {
                8
            });
            if let Some(ship) = self.ship_mut(id) {
                ship.secondary_ready = tick + reload;
            }
        }
        for (side, name, target, p) in events {
            self.add(
                1 << side,
                "secondary",
                format!("{name} · 副炮向 {target} 射击"),
                Some("CAS-6.1.5"),
                Some(p),
            );
        }
        self.apply_impacts(impacts);
    }

    /// cas-realtime-v10 (CAS 6.3): refill due torpedo mounts from their
    /// reserve. The interval starts when the mount fires; a destroyed mount
    /// never reloads, and older versions keep the frozen no-reload behaviour.
    pub(crate) fn reload_torpedoes(&mut self) {
        if !self.v10_family() {
            return;
        }
        let tick = self.tick;
        let mut done = Vec::new();
        for index in 0..self.ships.len() {
            let Some(def) = self.data.ships.get(self.ships[index].def).and_then(|d| d.torpedo.as_ref()) else {
                continue;
            };
            if def.reload_seconds.is_none() {
                continue;
            }
            for mount in 0..def.mounts.len() {
                let s = &mut self.ships[index];
                if s.torp_reload_at[mount] == 0 || s.torp_reload_at[mount] > tick {
                    continue;
                }
                s.torp_reload_at[mount] = 0;
                if s.torp_mount_destroyed[mount] {
                    continue;
                }
                let need = def.mounts[mount]
                    .tubes
                    .saturating_sub(s.torp_mount_remaining[mount]);
                let take = need.min(s.torp_reserve[mount]);
                if take == 0 {
                    continue;
                }
                s.torp_mount_remaining[mount] += take;
                s.torp_reserve[mount] -= take;
                s.ammo += take;
                done.push((s.side, s.name.clone(), s.p, mount + 1, take));
            }
        }
        for (side, name, p, mount, take) in done {
            self.add(
                1 << side,
                "torpedo_reload",
                format!("{name} · {mount} 号发射管再装填 {take} 枚"),
                Some("CAS-6.3"),
                Some(p),
            );
        }
    }

    pub fn move_torpedoes(&mut self, before: &[P]) {
        if self.torps.is_empty() {
            return;
        }
        let old = std::mem::take(&mut self.torps);
        let mut impacts = vec![];
        let cas_capital_targets = self.curved_movement();
        for mut torp in old {
            if self.tick <= torp.born {
                self.torps.push(torp);
                continue;
            }
            let dir = P::bearing(torp.h);
            let step = torp.speed.min(torp.remaining);
            let end = (torp.p + dir * step).snap();
            let mut candidates: Vec<_> = self
                .ships
                .iter()
                .filter(|s| s.alive() && s.id != torp.ship && !torp.tested.contains(&s.id))
                .filter(|s| self.torpedo_can_hit(s, torp.deep))
                .filter_map(|s| {
                    let a = before[(s.id - 1) as usize] - torp.p;
                    let b = s.p - end;
                    let along = a.dot(dir);
                    let after = b.dot(dir);
                    // Swept abeam crossing uses both target and torpedo motion, including friends.
                    if along < 0. || after > 0. {
                        return None;
                    }
                    let t = if along - after > 1e-9 {
                        (along / (along - after)).clamp(0., 1.)
                    } else {
                        0.
                    };
                    let at = a + (b - a) * t;
                    (at.cross(dir).abs() <= 500. * YARD).then_some((s.id, step * t))
                })
                .collect();
            candidates.sort_by(|a, b| a.1.total_cmp(&b.1).then_with(|| a.0.cmp(&b.0)));
            for (id, at) in candidates {
                let t = self.ship(id).unwrap().clone();
                let d = &self.data.ships[t.def];
                let incoming = norm(torp.h + 180.);
                let a = aspect(t.h, incoming);
                let table = if cas_capital_targets && d.size == "A" {
                    ["I", "II", "IV"][a]
                } else if d.size == "B" {
                    ["II", "III", "V"][a]
                } else {
                    ["III", "IV", "VI"][a]
                };
                let run = (torp.traveled + at.max(0.)) / YARD;
                let hits = if torp.single_mode {
                    (0..torp.count)
                        .map(|_| self.hit_rolls(table, run, 1, t.speed < 0.05))
                        .sum()
                } else {
                    self.hit_rolls(table, run, torp.count, t.speed < 0.05)
                };
                torp.tested.push(id);
                if hits == 0 {
                    continue;
                }
                torp.count -= hits;
                torp.single_mode = true;
                if t.side != torp.side {
                    torp.impact_sighted = true;
                }
                let mut damage = torp.warhead * hits as f64;
                let mut penetrating_hits = hits;
                if a == 2 {
                    damage *= 0.5;
                } else if torp.deep {
                    let side = usize::from(delta(t.h, incoming) > 0.);
                    (damage, penetrating_hits) = self.absorb_deep_torpedoes(id, side, torp.warhead, hits);
                } else if cas_capital_targets && matches!(d.size.as_str(), "A" | "B") {
                    damage *= match d.armor_belt {
                        belt if belt <= 5. => 1.,
                        belt if belt <= 10. => 0.9,
                        belt if belt <= 20. => 0.75,
                        belt if belt <= 30. => 0.6,
                        belt if belt <= 40. => 0.5,
                        _ => 0.4,
                    };
                } else if d.size == "B" {
                    damage *= if d.armor_belt <= 5. {
                        1.
                    } else if d.armor_belt <= 10. {
                        0.9
                    } else {
                        0.75
                    };
                }

                if t.side == torp.side || self.knows(torp.side, id) {
                    self.add(
                        1 << torp.side,
                        "torpedo_hit",
                        if t.side == torp.side {
                            format!("友舰误中 {} 枚鱼雷", hits)
                        } else {
                            format!("可见接触中雷 · {} 枚", hits)
                        },
                        Some("CAS-6.3.2"),
                        Some(t.p),
                    );
                    if t.side == torp.side {
                        self.last_voice(torp.side, Some("friendly_fire"));
                    }
                }
                if damage > 0. {
                    impacts.push(Impact {
                        victim: id,
                        amount: damage,
                        owner: torp.side,
                        torpedo: true,
                        at: t.p,
                        penetrated: true,
                        flood_hits: if torp.contact_fuze { penetrating_hits } else { 0 },
                    });
                }
                if torp.count == 0 {
                    break;
                }
            }
            torp.p = end;
            torp.traveled += step;
            torp.remaining -= step;
            if torp.count > 0 && torp.remaining > 1e-7 && self.field.contains(end) {
                self.observe_torpedo_wake(&mut torp);
                self.torps.push(torp);
            }
        }
        self.apply_impacts(impacts);
    }

    fn absorb_deep_torpedoes(&mut self, victim: u32, side: usize, warhead: f64, hits: u32) -> (f64, u32) {
        let ship = self.ship(victim).expect("torpedo impact target");
        let cap = self.data.ships[ship.def].torpedo_protection_dp / 3.;
        let mut remaining = ship.torpedo_protection[side];
        if remaining <= 0. {
            return (warhead * hits as f64, hits);
        }
        let mut damage = 0.;
        let mut penetrating = 0;
        let initial = remaining;
        let owner = ship.side;
        let at = ship.p;
        let name = ship.name.clone();
        for _ in 0..hits {
            let absorbed = warhead.min(cap).min(remaining);
            remaining -= absorbed;
            damage += warhead - absorbed;
            penetrating += u32::from(warhead > absorbed);
        }
        self.ship_mut(victim).unwrap().torpedo_protection[side] = remaining;
        self.add(1 << owner, "torpedo_protection", format!("{name} · {}舷水下防护吸收 {:.1} DP，余 {:.1} DP",
            if side == 0 { "左" } else { "右" }, initial - remaining, remaining), Some("CAS-8.1.7.2"), Some(at));
        (damage, penetrating)
    }
    pub(crate) fn apply_impacts(&mut self, v: Vec<Impact>) {
        let mut phase = vec![(0., 0., 0_u32, false); self.ships.len()];
        let progressive = self.progressive_criticals();
        let mut surface_victims = Vec::new();
        for i in v {
            let Some(s) = self.ship(i.victim) else {
                continue;
            };
            if !s.alive() {
                continue;
            }
            let name = s.name.clone();
            let side = s.side;
            let hp = (s.hp - i.amount.max(0.)).max(0.);
            let effective = s.hp - hp;
            if let Some(kula) = &mut self.kula { kula.credit(i.owner, side, effective); }
            self.ship_mut(i.victim).unwrap().hp = hp;
            let rule = if i.torpedo { "CAS-8.1.2" } else if self.realtime() { "RTS-GUN-04" } else { "CAS-6.1.3" };
            self.add(
                1 << side,
                "damage",
                format!(
                    "{name} {}受损 {:.1} DP",
                    if i.torpedo { "中雷" } else { "中弹" },
                    i.amount
                ),
                Some(rule),
                Some(i.at),
            );
            if i.owner != side && self.knows(i.owner, i.victim) {
                self.add(
                    1 << i.owner,
                    "hit",
                    format!(
                        "可见接触受到{}命中",
                        if i.torpedo { "鱼雷" } else { "炮弹" }
                    ),
                    Some(rule),
                    Some(i.at),
                );
                if i.torpedo {
                    // The actual hit already carried the torpedo-hit cue.
                    self.last_voice(i.owner, None);
                }
            }
            if hp <= 0. {
                self.sank(i.victim);
            }
            if self.realtime() && !i.torpedo {
                let a = &mut self.surface_damage[(i.victim - 1) as usize];
                a.total += i.amount;
                if i.penetrated { a.penetrated += i.amount; }
                if progressive { surface_victims.push(i.victim); }
                continue;
            }
            let a = &mut phase[(i.victim - 1) as usize];
            a.0 += i.amount;
            if i.penetrated {
                a.1 += i.amount
            };
            a.2 += i.flood_hits;
            a.3 = i.torpedo;
        }
        for (j, (total, pen, hits, torpedo)) in phase.into_iter().enumerate() {
            let id = j as u32 + 1;
            if total > 0. && self.ship(id).is_some_and(Ship::alive) {
                self.critical_phase_fraction(id, total, torpedo, pen / total);
                if hits > 0 && self.ship(id).is_some_and(Ship::alive) {
                    self.torpedo_automatic_flooding(id, hits, true);
                }
            }
        }
        // All hits in this batch dealt structural damage before any new
        // gunfire criticals can alter either side's ability to shoot.
        surface_victims.sort_unstable();
        surface_victims.dedup();
        for victim in surface_victims {
            self.progress_surface_criticals(victim);
        }
    }
    pub(crate) fn flush_realtime_surface_damage(&mut self) {
        let progressive = self.progressive_criticals();
        for j in 0..self.surface_damage.len() {
            let phase = std::mem::take(&mut self.surface_damage[j]);
            if !progressive && phase.total > 0. {
                self.critical_phase_fraction(j as u32 + 1, phase.total, false, phase.penetrated / phase.total);
            }
        }
    }
    fn project_launch(&self, s: &Ship, c: &Contact) -> (Ship, Contact) {
        let dt = (CYCLE - self.tick % CYCLE) as f64;
        let mut own = s.clone();
        if let Some(t) = &s.track {
            let desired = s
                .fleet
                .and_then(|id| self.fleet(id))
                .map_or(s.speed, |f| f.speed)
                .min(self.max_speed(s));
            let average = if s.speed > 0. {
                s.speed.min(desired)
            } else {
                (dt * self.data.ships[s.def].accel_knots_per_turn / CYCLE as f64 * 0.5).min(desired)
            };
            let (p, h) = t.at((t.pos + dt * average * KNOT).min(t.end));
            own.p = p;
            own.h = h;
        }
        let mut target = c.clone();
        let p = c.p() + P::bearing(c.heading) * (c.speed * KNOT * dt);
        target.x = p.x;
        target.y = p.y;
        (own, target)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cleveland_twelve_barrels_use_printed_eleven_to_twelve_column() {
        let w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
        assert_eq!(gun_multiplier(&w.data.rules, 12, 0), 6.);
        assert_eq!(gun_multiplier(&w.data.rules, 12, 3), 2.);
        assert_eq!(gun_multiplier(&w.data.rules, 5, 0), 3.);
        assert_eq!(gun_multiplier(&w.data.rules, 4, 1), 2.);
    }

    #[test]
    fn split_salvo_spends_only_the_selected_mount_and_revalidates() {
        let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
        w.enable_realtime().unwrap();
        let p = w.ship(1).unwrap().p + P::bearing(165.) * 3_000.;
        w.ship_mut(6).unwrap().p = p;
        w.detect(true);
        let target = w.contacts[0].iter().find(|c| c.ship == 6).unwrap().id.clone();
        let order = json!({"op":"fire","ship":1,"target":target,"weapon":"torpedo","heading":165.,"mount":0,"count":2});
        let aim = w.preview_aim(0, &order).unwrap();
        assert_eq!(aim["valid"], true, "{aim}");
        assert_eq!(aim["torpedoCount"], 2);
        w.queue_fire(0, &order, true).unwrap();
        w.tick = CYCLE;
        w.resolve_fire(true);
        assert_eq!(w.torps.len(), 1);
        assert_eq!(w.torps[0].count, 2);
        assert_eq!(w.ship(1).unwrap().torp_mount_remaining, [3, 5]);
        assert_eq!(w.ship(1).unwrap().ammo, 8);
        let mut oversized = order.clone();
        oversized["count"] = json!(4);
        assert!(w.queue_fire(0, &oversized, true).is_err());
        assert!(w.pending.is_empty());
        let mut deep = order;
        deep["depth"] = json!("deep");
        assert_eq!(w.preview_aim(0, &deep).unwrap()["valid"], false);
    }

    #[test]
    fn held_torpedo_launches_when_tubes_bear_and_never_spends_on_timeout() {
        let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
        w.enable_realtime().unwrap();
        let p = w.ship(1).unwrap().p + P::bearing(90.) * 3_000.;
        w.ship_mut(6).unwrap().p = p;
        w.detect(true);
        let target = w.contacts[0].iter().find(|c| c.ship == 6).unwrap().id.clone();
        // Bow tubes face forward: order a shot dead astern so no tube bears yet.
        let order = json!({"op":"fire","ship":1,"target":target,"weapon":"torpedo","heading":270.});
        assert_eq!(w.preview_aim(0, &order).unwrap()["valid"], false, "{:?}", w.preview_aim(0, &order));
        w.queue_fire(0, &order, true).unwrap();
        assert!(w.torps.is_empty(), "an unbearing salvo must not launch");
        assert_eq!(w.pending.len(), 1, "the held order waits for the arcs");
        assert_eq!(w.ship(1).unwrap().ammo, 10, "holding never expends a torpedo");
        // Turn the ship until the arcs bear; the held order launches by itself.
        for _ in 0..120 {
            w.tick += 1;
            let ship = w.ship_mut(1).unwrap();
            ship.h = norm(ship.h + 2.);
            if w.tick % CYCLE != 0 { w.resolve_fire(false); }
            if !w.torps.is_empty() { break; }
            assert!(w.tick < 90 + 8, "the held order expires at 90 seconds");
        }
        assert_eq!(w.torps.len(), 1, "the held salvo launches once the tubes bear");
        assert!(w.pending.is_empty());
        assert_eq!(w.ship(1).unwrap().ammo, 5);
    }

    #[test]
    fn v10_over_concentration_costs_long_range_fire() {
        let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
        w.enable_realtime().unwrap();
        let p = w.ship(1).unwrap().p + P::bearing(0.) * (12_000. * YARD);
        w.ship_mut(6).unwrap().p = p;
        w.detect(true);
        let contact = w.contacts[0]
            .iter()
            .find(|c| c.ship == 6)
            .expect("the long-range contact must exist")
            .id
            .clone();
        w.order_realtime_gun(0, 1, &contact, true).unwrap();
        let s1 = w.ship(1).unwrap().clone();
        let t = w.ship(6).unwrap().clone();
        let alone = w.gun_values(&s1, &t, 2, 5, false, &[], 0, false).0;
        w.order_realtime_gun(0, 2, &contact, true).unwrap();
        let crowded = w.gun_values(&s1, &t, 2, 5, false, &[], 0, false).0;
        assert!(crowded < alone, "over-concentration {crowded} must trail {alone}");
        let medium = w.gun_values(&s1, &t, 1, 5, false, &[], 0, false).0;
        w.ship_mut(2).unwrap().battery.order = None;
        let medium_alone = w.gun_values(&s1, &t, 1, 5, false, &[], 0, false).0;
        assert_eq!(medium, medium_alone, "the penalty applies only at long and extreme range");
    }

    #[test]
    fn v10_torpedo_mounts_reload_from_their_reserve() {
        let mut w = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
        w.enable_realtime().unwrap();
        let id = w
            .ships
            .iter()
            .find(|s| s.side == 1 && s.torp_reserve.iter().any(|r| *r > 0))
            .map(|s| s.id)
            .expect("the fixture needs a Japanese destroyer with reloads");
        let before = w.ship(id).unwrap();
        let reserve = before.torp_reserve[0];
        let tubes = w.data.ships[before.def].torpedo.as_ref().unwrap().mounts[0].tubes;
        assert!(reserve >= tubes);
        w.fire_torp(Launch { ship: id, side: 1, h: 90., mount: 0, count: tubes, deep: false });
        assert_eq!(w.ship(id).unwrap().torp_mount_remaining[0], 0);
        let due = w.ship(id).unwrap().torp_reload_at[0];
        assert!(due > 0, "a fired mount must schedule its reload");
        w.tick = due;
        w.reload_torpedoes();
        let after = w.ship(id).unwrap();
        assert_eq!(after.torp_mount_remaining[0], tubes);
        assert_eq!(after.torp_reserve[0], reserve - tubes);
    }

    #[test]
    fn deep_torpedo_uses_one_side_and_one_third_per_hit() {
        let mut w = World::new(6106, 0, "coord", crate::prologue::VARIANT, "coord", 0).unwrap();
        let yamato = w.ships.iter().find(|s| s.name == "大和").unwrap().id;
        let hp = w.ship(yamato).unwrap().hp;
        assert!(w.torpedo_can_hit(w.ship(yamato).unwrap(), true));
        assert!(!w.torpedo_can_hit(w.ship(1).unwrap(), true));
        assert_eq!(w.absorb_deep_torpedoes(yamato, 0, 50., 1), (0., 0));
        assert_eq!(w.absorb_deep_torpedoes(yamato, 0, 95., 3), (140., 3));
        assert_eq!(w.absorb_deep_torpedoes(yamato, 0, 50., 1), (50., 1));
        assert_eq!(w.ship(yamato).unwrap().torpedo_protection, [0., 195.]);
        assert_eq!(w.ship(yamato).unwrap().hp, hp);
        assert_eq!(w.visible_events(0, None).iter().filter(|e| e["kind"] == "torpedo_protection").count(), 0);
        assert_eq!(w.visible_events(1, None).iter().filter(|e| e["kind"] == "torpedo_protection").count(), 2);
    }
}
