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
}
#[derive(Clone)]
struct Impact {
    victim: u32,
    amount: f64,
    owner: usize,
    torpedo: bool,
    at: P,
    penetrated: bool,
    flood_hits: u32,
}
#[derive(Clone)]
struct Launch {
    ship: u32,
    side: usize,
    h: f64,
    mount: usize,
    count: u32,
}

impl World {
    pub fn detect(&mut self, initial: bool) {
        let rules = &self.data.rules;
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
                let d = if known.is_some()
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
                            .position(|x| x.as_u64().is_some_and(|k| d as u64 <= k))
                    })
                    .unwrap_or(4);
                for (p, size) in &observers {
                    let d = t.p.dist(*p) / YARD;
                    let base = rules["visual_base_yd"][size][&def.size]
                        .as_u64()
                        .unwrap_or(0);
                    let limit = if known.is_some() {
                        base as f64
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
                });
            }
        }
    }
    pub fn update_tracks(&mut self) {
        // A contact can be tracked continuously once spotted; checks are still only made on CAS intervals.
        for s in 0..2 {
            let mut lost = 0;
            let ships = &self.ships;
            let data = self.data;
            self.contacts[s].retain_mut(|c| {
                let t = &ships[(c.ship - 1) as usize];
                let visible = t.alive()
                    && ships.iter().filter(|o| o.side == s && o.alive()).any(|o| {
                        o.p.dist(t.p)
                            <= YARD
                                * n(&data.rules["visual_base_yd"][&data.ships[o.def].size]
                                    [&data.ships[t.def].size])
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
            .filter(|(i, m)| !s.gun_mount_destroyed[*i] && m_arc(direction, m.arc, m.arc2))
            .map(|(_, m)| m.barrels)
            .sum();
        (barrels > 0).then_some((band, barrels))
    }
    fn is_reaction(&self, c: &Contact) -> bool {
        self.tick >= CYCLE && c.first_cycle == self.tick / CYCLE
    }
    pub fn gun_candidate(&self, s: &Ship, c: &Contact) -> bool {
        self.gun_band(s, c).is_some()
            && (!self.is_reaction(c) || s.gun_cycle != Some(self.tick / CYCLE))
    }
    pub fn can_gun(&self, s: &Ship) -> bool {
        s.alive()
            && !self
                .pending
                .iter()
                .any(|p| p.ship == s.id && p.weapon == "gun")
            && self.contacts[s.side].iter().any(|c| {
                self.gun_band(s, c).is_some()
                    && (!self.is_reaction(c) || s.gun_cycle != Some(self.tick / CYCLE))
            })
    }
    pub fn can_torp(&self, s: &Ship) -> bool {
        s.alive()
            && s.ammo > 0
            && !self
                .pending
                .iter()
                .any(|p| p.ship == s.id && p.weapon == "torpedo")
            && self.contacts[s.side].iter().any(|c| {
                let (a, b) = self.project_launch(s, c);
                !self.is_reaction(c) && self.torp_solution(&a, &b, None).3.is_none()
            })
    }
    fn mount(&self, s: &Ship, h: f64) -> Option<(usize, u32)> {
        let def = self.data.ships[s.def].torpedo.as_ref()?;
        let a = norm(h - s.h);
        def.mounts
            .iter()
            .enumerate()
            .find(|(i, m)| !s.torp_mount_used[*i] && m_arc(a, m.arc, m.arc2))
            .map(|(i, m)| (i, m.tubes.min(s.ammo).min(6)))
    }
    fn friendly_torp(&self, s: &Ship, h: f64, r: f64, v: f64) -> bool {
        let forward = P::bearing(h);
        self.ships
            .iter()
            .filter(|t| t.id != s.id && t.side == s.side && t.alive())
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
    ) -> (f64, f64, bool, Option<String>) {
        let Some(t) = &self.data.ships[s.def].torpedo else {
            return (0., 0., false, Some("这艘舰未装鱼雷".into()));
        };
        let range = t.range_yd * YARD;
        let (suggest, intercept_range) = intercept(s.p, c, t.speed_knots * KNOT);
        let h = norm(angle.unwrap_or(suggest));
        let reason = if s.ammo == 0 {
            Some("鱼雷已耗尽")
        } else if self.is_reaction(c) {
            Some("刚发现的接触不能在此窗口放雷")
        } else if angle.is_none() && intercept_range > range {
            Some("预计交会点超出鱼雷航程")
        } else if self.mount(s, h).is_none() {
            Some("射向不在剩余发射管的可用扇区")
        } else {
            None
        };
        (
            h,
            range,
            self.friendly_torp(s, h, range, t.speed_knots * KNOT),
            reason.map(str::to_owned),
        )
    }
    pub fn preview_aim(&self, owner: usize, r: &Value) -> E<Value> {
        let id = u(r, "ship")?;
        let s = self.ship_for(owner, id)?;
        let target = r["target"].as_str().ok_or("请选择一个敌方接触")?;
        let c = self.contact(owner, target)?;
        if r["weapon"] == "gun" {
            let d = &self.data.ships[s.def];
            let barrels = self.gun_band(s, c).map_or(0, |(_, k)| k);
            let error = if barrels == 0 {
                Some("目标超出射程或没有炮位能对准")
            } else if self
                .pending
                .iter()
                .any(|p| p.ship == s.id && p.weapon == "gun")
            {
                Some("该舰已有待执行的炮击")
            } else if self.is_reaction(c) && s.gun_cycle == Some(self.tick / CYCLE) {
                Some("该舰本窗口已开炮")
            } else {
                None
            };
            return Ok(
                json!({"valid":error.is_none(),"barrels":barrels,"error":error,"heading":(c.p()-s.p).heading(),"arcs":[],"range":d.gun.range_yd[3]*YARD,"friendly":false}),
            );
        }
        let angle = r
            .get("heading")
            .map(|h| h.as_f64().filter(|v| v.is_finite()).ok_or("射向无效"))
            .transpose()?;
        let (future, projected) = self.project_launch(s, c);
        let (h, range, friendly, error) = self.torp_solution(&future, &projected, angle);
        let arcs: Vec<_> = self.data.ships[s.def]
            .torpedo
            .iter()
            .flat_map(|t| t.mounts.iter().enumerate())
            .filter(|(i, _)| !s.torp_mount_used[*i])
            .flat_map(|(_, m)| [Some(m.arc), m.arc2])
            .flatten()
            .map(|a| json!({"from":norm(a[0]+future.h),"to":norm(a[1]+future.h)}))
            .collect();
        Ok(
            json!({"heading":h,"range":range,"arcs":arcs,"friendly":friendly,"valid":error.is_none(),"error":error}),
        )
    }
    pub fn queue_fire(&mut self, owner: usize, r: &Value, manual: bool) -> E<()> {
        let id = u(r, "ship")?;
        let s = self.ship_for(owner, id)?;
        let target = r["target"].as_str().ok_or("请把火力拖向一个接触")?;
        let c = self.contact(owner, target)?;
        let weapon = r["weapon"].as_str().ok_or("武器不可用")?;
        if self
            .pending
            .iter()
            .any(|p| p.ship == id && p.weapon == weapon)
        {
            return Err("该武器已有一条待执行命令".into());
        }
        let mut heading = None;
        match weapon {
            "gun" => {
                self.gun_band(s, c).ok_or("目标超出射程或没有炮位能对准")?;
                if self.is_reaction(c) && s.gun_cycle == Some(self.tick / CYCLE) {
                    return Err("该舰本战术窗口已开炮".into());
                }
            }
            "torpedo" => {
                let angle = r
                    .get("heading")
                    .map(|h| h.as_f64().filter(|v| v.is_finite()).ok_or("射向无效"))
                    .transpose()?;
                let (future, projected) = self.project_launch(s, c);
                let (h, _, friendly, err) = self.torp_solution(&future, &projected, angle);
                if let Some(e) = err {
                    return Err(e);
                }
                if friendly && !manual {
                    return Err("AI 不向已知友舰航迹放雷".into());
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
                if weapon == "gun"
                    && self.contacts[owner]
                        .iter()
                        .find(|x| x.id == target)
                        .is_some_and(|x| self.is_reaction(x))
                {
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
        let c = self.contact(p.side, &p.target)?;
        if !self.ship(c.ship).is_some_and(Ship::alive) {
            return Err("目标已失效".into());
        }
        let reaction = !planned;
        if reaction && !self.is_reaction(c) {
            return Ok(None);
        }
        if s.gun_cycle == Some(self.tick / CYCLE) {
            return Err("本窗口炮位已使用".into());
        }
        let (band, barrels) = self.gun_band(s, c).ok_or("执行时目标已超出射程或射界")?;
        Ok(Some(Shot {
            ship: s.id,
            target: c.ship,
            band,
            barrels,
            reaction,
        }))
    }
    pub fn resolve_fire(&mut self, planned: bool) {
        if self.pending.is_empty() {
            return;
        }
        let mut pending = std::mem::take(&mut self.pending);
        pending.sort_by(|a, b| (a.ship, &a.weapon).cmp(&(b.ship, &b.weapon)));
        let mut shots = vec![];
        let mut launches = vec![];
        for p in pending {
            let run = if planned {
                p.expires <= self.tick
            } else {
                p.weapon == "gun"
                    && self
                        .contact(p.side, &p.target)
                        .is_ok_and(|c| self.is_reaction(c))
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
                    Err(e) => Some(e),
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
    fn validate_launch(&self, p: &Fire) -> E<Launch> {
        let s = self.ship_for(p.side, p.ship)?;
        let c = self.contact(p.side, &p.target)?;
        if !self.ship(c.ship).is_some_and(Ship::alive) {
            return Err("鱼雷的原目标已失效".into());
        }
        if s.jammed_until > self.tick {
            return Err("该舰正在处理转向损伤".into());
        }
        let (h, _, _, e) = self.torp_solution(s, c, p.heading);
        if let Some(e) = e {
            return Err(e);
        }
        let (mount, count) = self.mount(s, h).ok_or("发射管已不可用")?;
        if count == 0 {
            return Err("发射管没有鱼雷".into());
        }
        Ok(Launch {
            ship: s.id,
            side: s.side,
            h,
            mount,
            count,
        })
    }
    fn fire_gun(&mut self, shot: Shot, planned_targets: &[u32]) -> Option<Impact> {
        let s = self.ship(shot.ship)?.clone();
        let t = self.ship(shot.target)?.clone();
        let d = &self.data.ships[s.def];
        let td = &self.data.ships[t.def];
        let gun = &d.gun;
        let b = shot.band;
        let base = n(&self.data.rules["gun_base_hit"][gun.gs.to_string()][b]);
        let mut modifiers = 0_i32;
        modifiers += ((shot.barrels.saturating_sub(1) / 2).min(5)) as i32;
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
        modifiers += if td.size == "B" {
            [1, 0, -1][target_aspect]
        } else {
            [0, -1, -2][target_aspect]
        };
        if s.p.dist(t.p) / YARD <= gun.range_yd[0] / 2. {
            modifiers += 4;
        }
        if s.fire_control_damage {
            modifiers -= 2;
        }
        if !planned_targets.contains(&s.id) && !self.incoming_this_cycle.contains(&s.id) {
            modifiers += 1;
        }
        let cycle = self.tick / CYCLE;
        let old = self.gun_streak[(s.id - 1) as usize];
        let streak = if old.0 == t.id && old.1 + 1 >= cycle {
            old.2 + 1
        } else {
            1
        };
        if streak == 1 && b >= 2 {
            modifiers -= 2
        }
        if streak >= 3 {
            modifiers += 1
        }
        let chance = (base + modifiers as f64 * if b <= 1 { 4. } else { 2. }).clamp(0., 90.);
        let roll = self.d(100);
        self.gun_streak[(s.id - 1) as usize] = (t.id, cycle, streak);
        self.ship_mut(s.id).unwrap().gun_cycle = Some(cycle);
        self.fired_this_cycle.push(s.id);
        self.incoming_this_cycle.push(t.id);
        let range = ["近", "中", "远", "极远"][b];
        self.add(
            1 << s.side,
            "gun",
            format!(
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
            ),
            Some("CAS-6.1.3"),
            Some(s.p),
        );
        if roll as f64 > chance {
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
        Some(Impact {
            victim: t.id,
            amount: damage,
            owner: s.side,
            torpedo: false,
            at: t.p,
            penetrated,
            flood_hits: 0,
        })
    }
    fn fire_torp(&mut self, l: Launch) {
        let s = self.ship(l.ship).unwrap().clone();
        let d = self.data.ships[s.def].torpedo.as_ref().unwrap();
        let id = self.next_torp;
        self.next_torp += 1;
        self.torps.push(Torpedo {
            id,
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
            contact_fuze: d.contact_fuze,
            single_mode: false,
            tested: vec![],
        });
        let tick = self.tick;
        let ship = self.ship_mut(l.ship).unwrap();
        ship.ammo -= l.count;
        ship.torp_cycle = Some(tick / CYCLE);
        ship.torp_mount_used[l.mount] = true;
        self.add(
            1 << l.side,
            "torpedo",
            format!(
                "{} 发射 {} 枚{}直航鱼雷 · 航向 {:.0}°",
                s.name, l.count, d.name, l.h
            ),
            Some("CAS-6.3.1"),
            Some(s.p),
        );
    }
    fn hit_rolls(&mut self, table: &str, run: f64, spread: u32, stopped: bool) -> u32 {
        let r = &self.data.rules["torpedo_hit"][table];
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
    pub fn move_torpedoes(&mut self, before: &[P]) {
        if self.torps.is_empty() {
            return;
        }
        let old = std::mem::take(&mut self.torps);
        let mut impacts = vec![];
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
                let a = aspect(t.h, norm(torp.h + 180.));
                let table = if d.size == "B" {
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
                let mut damage = torp.warhead * hits as f64;
                if a == 2 {
                    damage *= 0.5;
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
                }
                impacts.push(Impact {
                    victim: id,
                    amount: damage,
                    owner: torp.side,
                    torpedo: true,
                    at: t.p,
                    penetrated: true,
                    flood_hits: if torp.contact_fuze { hits } else { 0 },
                });
                if torp.count == 0 {
                    break;
                }
            }
            torp.p = end;
            torp.traveled += step;
            torp.remaining -= step;
            if torp.count > 0 && torp.remaining > 1e-7 && end.on_chart() {
                self.torps.push(torp);
            }
        }
        self.apply_impacts(impacts);
    }
    fn apply_impacts(&mut self, v: Vec<Impact>) {
        let mut phase = vec![(0., 0., 0_u32, false); self.ships.len()];
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
            self.ship_mut(i.victim).unwrap().hp = hp;
            let rule = if i.torpedo { "CAS-8.1.2" } else { "CAS-6.1.3" };
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
            }
            if hp <= 0. {
                self.sank(i.victim);
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
}
