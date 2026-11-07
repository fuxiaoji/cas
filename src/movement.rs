use crate::{
    model::*,
    world::{u, World},
};
use serde_json::{json, Value};

fn advance_for(turn: f64, step: f64) -> f64 {
    if turn.abs() < 4. {
        0.
    } else {
        (turn.abs() / 45.).ceil() * step
    }
}
fn cumulative(p: &[P]) -> f64 {
    p.windows(2).map(|v| v[0].dist(v[1])).sum()
}
pub(crate) struct Route {
    pub paths: Vec<(u32, Track)>,
    pub speed: f64,
    pub mode: String,
    pub points: Vec<P>,
}

fn route_line(field: Field, ship: &Ship, points: &[P], advance: f64) -> E<Vec<P>> {
    let mut prev = ship.p;
    let mut heading = ship.h;
    let mut line = vec![prev];
    for (i, &p) in points.iter().enumerate() {
        if !field.contains(p) {
            return Err(format!("航点 {} 超出海图", i + 1));
        }
        let v = p - prev;
        if v.len() < 80. {
            return Err(format!("航段 {} 太短", i + 1));
        }
        let new_h = v.heading();
        let turn = delta(heading, new_h);
        if i == 0 && turn.abs() > 4. {
            // First travel on the existing heading. This is deliberately visible in the preview.
            let pre = (1..=4)
                .map(|n| prev + P::bearing(heading) * (advance * n as f64))
                .find(|a| {
                    let angle = delta(heading, (p - *a).heading()).abs();
                    field.contains(*a)
                        && a.dist(p) >= 80.
                        && angle <= 150.
                        && prev.dist(*a) + 1e-6 >= advance_for(angle, advance)
                })
                .ok_or("首段没有足够的转向空间；把第一个航点放远一些或先增加侧向航点")?;
            line.push(pre.snap());
        } else if i > 0 && line[line.len() - 2].dist(prev) + 1e-7 < advance_for(turn, advance) {
            return Err(format!("航点 {} 前的直航距离不足，无法转向", i));
        }
        heading = (p - *line.last().unwrap()).heading();
        line.push(p.snap());
        prev = p;
    }
    Ok(line)
}

// One standard-rudder advance per 45° of arc. CAS specifies advance
// between pivots, so this radius is a continuous-motion adaptation.
fn append_arc(nodes: &mut Vec<P>, center: P, radius: f64, radial: f64, sweep: f64) {
    let segments = (sweep.abs() / 2.).ceil() as u32;
    for i in 1..=segments {
        let angle = radial + sweep * f64::from(i) / f64::from(segments);
        nodes.push((center + P::bearing(angle) * radius).snap());
    }
}

fn curved_route(field: Field, ship: &Ship, points: &[P], advance: f64) -> E<Vec<P>> {
    for (i, &point) in points.iter().enumerate() {
        if !field.contains(point) {
            return Err(format!("航点 {} 超出海图", i + 1));
        }
        let prior = if i == 0 { ship.p } else { points[i - 1] };
        if prior.dist(point) < 80. {
            return Err(format!("航段 {} 太短", i + 1));
        }
    }

    let radius = advance / 45_f64.to_radians();
    let bow = P::bearing(ship.h);
    let first = points[0];
    let first_change = delta(ship.h, (first - ship.p).heading());
    let mut nodes = vec![ship.p];
    if first_change.abs() > 1e-6 {
        let start = if first_change.abs() > 10. {
            ship.p + bow * advance
        } else {
            ship.p
        };
        let sign = first_change.signum();
        let center = start + P::bearing(ship.h + sign * 90.) * radius;
        let to_target = first - center;
        if to_target.len() <= radius {
            return Err("首个航点落在转向圆内，请把航点放远一些".into());
        }
        let radial = ship.h - sign * 90.;
        let tangent = to_target.heading()
            - sign * libm::acos(radius / to_target.len()).to_degrees();
        let sweep = ((tangent - radial) * sign).rem_euclid(360.);
        if sweep >= 180. {
            return Err("首段没有足够的转向空间，请先在侧方放一个航点".into());
        }
        if start != ship.p {
            nodes.push(start.snap());
        }
        append_arc(&mut nodes, center, radius, radial, sweep * sign);
    }

    // Waypoints are intersections of the approach and departure courses.
    // Keep the same radius and cut the corner between the two tangents.
    let mut prior = *nodes.last().unwrap();
    for (i, pair) in points.windows(2).enumerate() {
        let (point, next) = (pair[0], pair[1]);
        let incoming = (point - prior).unit();
        let outgoing = (next - point).unit();
        let turn = delta(incoming.heading(), outgoing.heading());
        if turn.abs() <= 1e-6 {
            nodes.push(point.snap());
            prior = point;
            continue;
        }
        let cut = radius * libm::tan(turn.abs().to_radians() * 0.5);
        if turn.abs() >= 179. || cut + 1e-4 >= prior.dist(point) || cut + 1e-4 >= point.dist(next) {
            return Err(format!("航点 {} 没有足够空间转弯，请拉开航点", i + 1));
        }
        let start = point - incoming * cut;
        let radial = incoming.heading() - turn.signum() * 90.;
        let center = start - P::bearing(radial) * radius;
        nodes.push(start.snap());
        append_arc(&mut nodes, center, radius, radial, turn);
        prior = point + outgoing * cut;
    }
    nodes.push(points.last().unwrap().snap());
    Ok(nodes)
}

fn closest(a: P, b: P) -> f64 {
    let v = b - a;
    let d = v.dot(v);
    let t = if d > 0. {
        (-a.dot(v) / d).clamp(0., 1.)
    } else {
        0.
    };
    (a + v * t).len()
}
pub fn swept_separation(a: P, b: P, c: P, d: P) -> f64 {
    closest(a - c, b - d)
}

impl World {
    pub(crate) fn curved_movement(&self) -> bool {
        matches!(self.version, crate::realtime::VERSION | crate::realtime::WINDOW_TORPEDO_VERSION | crate::realtime::CURVE_VERSION
            | crate::campaign::live::VERSION | crate::campaign::live::WINDOW_TORPEDO_VERSION | crate::campaign::live::CURVE_VERSION)
    }

    pub(crate) fn max_speed(&self, ship: &Ship) -> f64 {
        let def = &self.data.ships[ship.def];
        let damage = def.dp - ship.hp;
        if def.damage_speed.is_empty() {
            return def
                .max_knots
                .min(ship.speed_cap.unwrap_or(f64::INFINITY))
                .min(self.flooding_speed_limit(ship));
        }
        let i = def
            .damage_speed
            .iter()
            .rposition(|r| damage + 1e-7 >= r.damage)
            .unwrap_or(0);
        def.damage_speed[(i + ship.engineering_speed_levels).min(def.damage_speed.len() - 1)]
            .knots
            .min(ship.speed_cap.unwrap_or(f64::INFINITY))
            .min(self.flooding_speed_limit(ship))
    }
    fn fleet_max(&self, f: &Fleet) -> f64 {
        f.members
            .iter()
            .filter_map(|&id| self.ship(id))
            .filter(|s| s.alive())
            .map(|s| self.max_speed(s))
            .fold(f64::INFINITY, f64::min)
    }
    fn blocked(&self, p: P) -> bool {
        if !self.field.contains(p) {
            return true;
        }
        for poly in &self.islands {
            let mut odd = false;
            for i in 0..poly.len() {
                let a = poly[i];
                let b = poly[(i + 1) % poly.len()];
                if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                {
                    odd = !odd
                }
                if closest(a - p, b - p) < 55. {
                    return true;
                }
            }
            if odd {
                return true;
            }
        }
        false
    }
    fn block_segment(&self, a: P, b: P) -> bool {
        self.blocked(a)
            || self.blocked(b)
            || (!self.islands.is_empty() && {
                let n = (a.dist(b) / 35.).ceil() as u32;
                (1..n).any(|i| self.blocked(a + (b - a) * (i as f64 / n as f64)))
            })
    }
    pub(crate) fn plan_route(
        &self,
        owner: usize,
        fleet: u32,
        mode: &str,
        points: &[P],
        speed: Option<f64>,
    ) -> E<Route> {
        let f = self.fleet_for(owner, fleet)?;
        if !matches!(mode, "follow" | "sync") {
            return Err("请选择一种编队机动".into());
        }
        if !(1..=10).contains(&points.len()) {
            return Err("请放置 1 至 10 个航点".into());
        }
        let lead = self.ship(f.leader).ok_or("没有可用领舰")?;
        if !lead.alive() {
            return Err("领舰已失能".into());
        }
        let members: Vec<_> = f
            .members
            .iter()
            .filter_map(|id| self.ship(*id))
            .filter(|s| s.alive())
            .collect();
        let max = self.fleet_max(f);
        let k = speed.unwrap_or(f.speed.min(max));
        if !k.is_finite() || k < 4. || k > max + 1e-6 {
            return Err(format!("共同可用航速：4–{max:.0} 节；请降速或让受损舰脱队"));
        }
        if let Some(s) = members.iter().find(|s| s.jammed_until > self.tick) {
            return Err(format!("{} 暂时不能转向", s.name));
        }
        let advance = members
            .iter()
            .map(|s| self.data.ships[s.def].turn_advance_yards * YARD)
            .fold(0., f64::max);
        let heading = P::bearing(lead.h);
        let raw = if self.curved_movement() {
            curved_route(self.field, lead, points, advance)?
        } else {
            route_line(self.field, lead, points, advance)?
        };
        let mut paths = Vec::new();
        if mode == "sync" {
            let axis = members
                .iter()
                .find(|s| s.id != lead.id)
                .map(|s| (s.p - lead.p).unit())
                .unwrap_or(heading);
            for s in members {
                if delta(s.h, lead.h).abs() > 6. || (s.p - lead.p).cross(axis).abs() > 75. {
                    return Err(
                        "同步机动需要各舰航向一致、处在一条队列上；等后舰完成转向再试".into(),
                    );
                }
                let nodes: Vec<P> = raw.iter().map(|&p| (p + s.p - lead.p).snap()).collect();
                let end = cumulative(&nodes);
                paths.push((s.id, Track::new(nodes, 0., end)));
            }
        } else {
            let prior = lead.track.as_ref();
            let on_wake = f.mode == "follow"
                && prior.is_some()
                && members.iter().all(|s| {
                    s.track
                        .as_ref()
                        .zip(prior)
                        .is_some_and(|(a, b)| a.nodes == b.nodes && a.pos <= b.pos + 0.01)
                });
            let mut past: Vec<(u32, f64)> = Vec::new();
            let mut spine;
            if on_wake {
                let t = prior.unwrap();
                let min = members
                    .iter()
                    .map(|s| s.track.as_ref().unwrap().pos)
                    .fold(t.pos, f64::min);
                spine = vec![t.at(min).0];
                for (i, d) in t.len.iter().enumerate() {
                    if *d > min + 1e-6 && *d < t.pos - 1e-6 {
                        spine.push(t.nodes[i]);
                    }
                }
                if t.pos - min > 1e-6 {
                    spine.push(lead.p);
                }
                for s in members {
                    past.push((s.id, s.track.as_ref().unwrap().pos - min));
                }
            } else {
                let mut row: Vec<_> = members
                    .iter()
                    .map(|s| {
                        let offset = s.p - lead.p;
                        (*s, offset.dot(heading), offset.cross(heading))
                    })
                    .collect();
                if row
                    .iter()
                    .any(|(s, a, b)| *a > 30. || b.abs() > 50. || delta(s.h, lead.h).abs() > 6.)
                {
                    return Err("领舰尾随需要纵队；先点「重整纵队」，等各舰对齐".into());
                }
                row.sort_by(|a, b| a.1.total_cmp(&b.1));
                spine = row.iter().map(|(s, _, _)| s.p).collect();
                if spine.last().is_some_and(|p| p.dist(lead.p) > 1e-5) {
                    return Err("所选领舰不在队首，先重整纵队".into());
                }
                let mut d = 0.;
                for (i, (s, _, _)) in row.into_iter().enumerate() {
                    if i > 0 {
                        d += spine[i - 1].dist(spine[i]);
                    }
                    past.push((s.id, d));
                }
            }
            let len = cumulative(&raw);
            spine.extend_from_slice(&raw[1..]);
            for (id, p) in past {
                paths.push((id, Track::new(spine.clone(), p, p + len)));
            }
        }
        let r = Route {
            paths,
            speed: k,
            mode: mode.into(),
            points: points.to_vec(),
        };
        self.check_route(owner, &r)?;
        Ok(r)
    }
    fn check_route(&self, owner: usize, route: &Route) -> E<()> {
        for (id, t) in &route.paths {
            for (i, w) in t.remaining().windows(2).enumerate() {
                if self.block_segment(w[0], w[1]) {
                    return Err(format!(
                        "{} 第 {} 段触及陆地或海图边缘",
                        self.ship(*id).unwrap().name,
                        i + 1
                    ));
                }
            }
        }
        let ids: Vec<_> = route.paths.iter().map(|(id, _)| *id).collect();
        let others: Vec<_> = self
            .ships
            .iter()
            .filter(|s| s.side == owner && s.alive() && !ids.contains(&s.id))
            .collect();
        let mut watch: Vec<(u32, &Track, f64)> = route
            .paths
            .iter()
            .map(|(id, t)| (*id, t, route.speed))
            .collect();
        for s in &others {
            if let Some(t) = &s.track {
                let k = s
                    .fleet
                    .and_then(|f| self.fleet(f))
                    .map_or(s.free_speed, |f| f.speed);
                watch.push((s.id, t, k));
            }
        }
        let stationary: Vec<_> = others.iter().filter(|s| s.track.is_none()).collect();
        let maxt = route
            .paths
            .iter()
            .map(|(_, t)| ((t.end - t.pos) / (route.speed * KNOT)).ceil() as u32)
            .max()
            .unwrap_or(0)
            .min(self.field.limit.saturating_sub(self.tick));
        // Sample continuous swept intervals. Live motion validates every second again.
        for sec in (0..maxt).step_by(4) {
            let span = 4_u32.min(maxt - sec);
            for (i, (id, a, k)) in watch.iter().enumerate().take(route.paths.len()) {
                let a0 = a.to(a.pos + *k * KNOT * sec as f64);
                let a1 = a.to(a.pos + *k * KNOT * (sec + span) as f64);
                for (jd, b, q) in watch.iter().skip(i + 1) {
                    let b0 = b.to(b.pos + *q * KNOT * sec as f64);
                    let b1 = b.to(b.pos + *q * KNOT * (sec + span) as f64);
                    if swept_separation(a0, a1, b0, b1) < self.clearance(*id, *jd) {
                        return Err(format!(
                            "约 {} 秒后，{} 与 {} 航路过近",
                            sec,
                            self.ship(*id).unwrap().name,
                            self.ship(*jd).unwrap().name
                        ));
                    }
                }
                for s in &stationary {
                    if swept_separation(a0, a1, s.p, s.p) < self.clearance(*id, s.id) {
                        return Err(format!(
                            "约 {} 秒后，{} 航路经过友舰 {}",
                            sec,
                            self.ship(*id).unwrap().name,
                            s.name
                        ));
                    }
                }
            }
        }
        Ok(())
    }
    fn clearance(&self, a: u32, b: u32) -> f64 {
        let k = |id| {
            self.ship(id)
                .map_or(75., |s| self.data.ships[s.def].length_m.max(75.))
        };
        (k(a) + k(b)) * 0.5
    }
    fn inputs(r: &Value) -> E<(u32, &str, Vec<P>, Option<f64>)> {
        let id = u(r, "fleet")?;
        let mode = r
            .get("mode")
            .and_then(Value::as_str)
            .ok_or("未选择机动方式")?;
        let points: Vec<P> = serde_json::from_value(r.get("points").ok_or("请添加航点")?.clone())
            .map_err(|_| "航点格式无效")?;
        let speed = r
            .get("speed")
            .filter(|v| !v.is_null())
            .map(|x| x.as_f64().ok_or("无效航速"))
            .transpose()?;
        Ok((id, mode, points, speed))
    }
    pub fn preview(&self, owner: usize, r: &Value) -> E<Value> {
        let (id, mode, points, speed) = Self::inputs(r)?;
        let f = self.fleet_for(owner, id)?;
        match self.plan_route(owner, id, mode, &points, speed) {
            Ok(a) => Ok(json!({"valid":true,"speed":a.speed,"paths":paths_json(&a.paths)})),
            Err(error) => Ok(json!({"valid":false,"error":error,"speed":f.speed,"paths":[]})),
        }
    }
    pub fn route(&mut self, owner: usize, r: &Value, manual: bool) -> E<()> {
        let (id, mode, points, speed) = Self::inputs(r)?;
        let a = self.plan_route(owner, id, mode, &points, speed)?;
        self.install_route(id, a, manual);
        Ok(())
    }
    fn install_route(&mut self, id: u32, a: Route, manual: bool) {
        for (ship, t) in a.paths {
            self.ship_mut(ship).unwrap().track = Some(t);
        }
        let tick = self.tick;
        let f = self.fleet_mut(id).unwrap();
        f.mode = a.mode;
        f.points = a.points;
        f.speed = a.speed;
        f.notice = None;
        if manual {
            f.ai.r#move = false;
        } else {
            f.last_ai_route = tick;
        }
        let text = format!(
            "{}已确认{}，{} 个航点 · {:.0} 节",
            f.name,
            if f.mode == "follow" {
                "领舰移动"
            } else {
                "同步移动"
            },
            f.points.len(),
            f.speed
        );
        let s = f.side;
        self.add(1 << s, "route", text, Some("RTS-NAV-01"), None);
    }
    pub fn lead(&mut self, owner: usize, r: &Value) -> E<()> {
        let id = u(r, "fleet")?;
        let s = u(r, "ship")?;
        let f = self.fleet_for(owner, id)?;
        if !f.members.contains(&s) || !self.ship(s).is_some_and(Ship::alive) {
            return Err("请选择本队存活舰艇".into());
        }
        if f.leader == s {
            return Ok(());
        }
        if f.members
            .iter()
            .any(|x| self.ship(*x).is_some_and(|s| s.speed > 0.5))
        {
            return Err("先等编队完成当前机动，再更换领舰".into());
        }
        let ids = f.members.clone();
        let old_id = f.leader;
        let deployment = self.tick == 0
            || self.variant == crate::prologue::VARIANT && id == 1
                && self.tick == crate::prologue::HANDOVER_TICK && f.points.is_empty();
        if deployment {
            // Before the clock starts this is a deployment edit, never an in-battle jump.
            let old = self.ship(old_id).unwrap().p;
            let new = self.ship(s).unwrap().p;
            self.ship_mut(old_id).unwrap().p = new;
            self.ship_mut(s).unwrap().p = old;
        } else {
            let p = self.ship(s).unwrap().p;
            let axis = ids
                .iter()
                .filter_map(|i| self.ship(*i))
                .filter(|i| i.alive() && i.id != s)
                .max_by(|a, b| a.p.dist(p).total_cmp(&b.p.dist(p)))
                .map(|other| (other.p - p).unit());
            if let Some(axis) = axis {
                if ids
                    .iter()
                    .filter_map(|i| self.ship(*i))
                    .filter(|i| i.alive())
                    .any(|i| (i.p - p).dot(axis) < -40. || (i.p - p).cross(axis).abs() > 75.)
                {
                    return Err("战斗中请从队列一端选择领舰".into());
                }
            }
        }
        for &m in &ids {
            self.ship_mut(m).unwrap().track = None;
        }
        let f = self.fleet_mut(id).unwrap();
        f.leader = s;
        if deployment {
            let a = ids.iter().position(|&i| i == old_id).unwrap();
            let b = ids.iter().position(|&i| i == s).unwrap();
            f.members.swap(a, b);
        } else {
            f.members.retain(|&i| i != s);
            f.members.insert(0, s);
        }
        f.points.clear();
        f.ai.r#move = false;
        f.notice = if deployment {
            None
        } else {
            Some("已选领舰；如果领舰不在队首，先重整纵队。".into())
        };
        self.add(
            1 << owner,
            "leader",
            "领舰已更换".into(),
            Some("RTS-NAV-02"),
            None,
        );
        Ok(())
    }
    fn reform_plan(&self, owner: usize, r: &Value) -> E<Route> {
        let id = u(r, "fleet")?;
        let f = self.fleet_for(owner, id)?;
        let lead = self.ship(f.leader).ok_or("没有可用领舰")?;
        let axis = f
            .members
            .iter()
            .filter_map(|s| self.ship(*s))
            .filter(|s| s.alive() && s.id != lead.id)
            .max_by(|a, b| a.p.dist(lead.p).total_cmp(&b.p.dist(lead.p)))
            .map(|s| (lead.p - s.p).unit());
        let Some(axis) = axis else {
            return Err("编队只有一艘舰，直接使用领舰移动".into());
        };
        if f.members
            .iter()
            .filter_map(|s| self.ship(*s))
            .filter(|s| s.alive())
            .any(|s| (s.p - lead.p).dot(axis) > 40.)
        {
            return Err("所选领舰不在队列一端；请选择一端的舰艇作为领舰".into());
        }
        let mid = lead.p + P::bearing(lead.h) * 1400.;
        let end = mid + axis * 1550.;
        self.plan_route(owner, id, "sync", &[mid, end], None)
    }
    pub fn preview_reform(&self, owner: usize, r: &Value) -> E<Value> {
        let f = self.fleet_for(owner, u(r, "fleet")?)?;
        Ok(match self.reform_plan(owner, r) {
            Ok(a) => json!({"valid":true,"speed":a.speed,"paths":paths_json(&a.paths)}),
            Err(error) => json!({"valid":false,"error":error,"speed":f.speed,"paths":[]}),
        })
    }
    pub fn reform(&mut self, owner: usize, r: &Value) -> E<()> {
        let id = u(r, "fleet")?;
        let a = self.reform_plan(owner, r)?;
        self.install_route(id, a, true);
        self.fleet_mut(id).unwrap().notice =
            Some("正在重整，完成转向并排成纵队后可用领舰移动。".into());
        Ok(())
    }
    pub fn detach(&mut self, owner: usize, r: &Value) -> E<()> {
        let id = u(r, "fleet")?;
        let ship = u(r, "ship")?;
        let f = self.fleet_for(owner, id)?;
        if !f.members.contains(&ship) || f.members.len() < 2 {
            return Err("该舰不能从此编队脱离".into());
        }
        let actual = f.actual;
        let new_id = self.fleets.iter().map(|f| f.id).max().unwrap_or(0) + 1;
        let s = self.ship_mut(ship).unwrap();
        s.fleet = Some(new_id);
        let name = format!("{} · 独立", s.name);
        let max = self.max_speed(self.ship(ship).unwrap());
        self.fleets.push(Fleet {
            id: new_id,
            side: owner,
            name,
            leader: ship,
            members: vec![ship],
            mode: "follow".into(),
            speed: actual.min(max),
            actual: actual.min(max),
            turn_degrees: 0.,
            points: vec![],
            ai: Ai::new("coord", "manual"),
            notice: None,
            last_ai_route: 0,
            tactic: Tactic::Search,
        });
        let replacement = fallback_leader(self, id, ship);
        let f = self.fleet_mut(id).unwrap();
        f.members.retain(|&x| x != ship);
        f.ai.r#move = false;
        if f.leader == ship {
            if let Some(l) = replacement {
                f.leader = l;
            }
        }
        self.add(
            1 << owner,
            "detach",
            "受损舰已成为独立分队".into(),
            Some("RTS-NAV-02"),
            None,
        );
        Ok(())
    }
    pub fn move_ships(&mut self) {
        let mut proposal: Vec<(P, f64, f64, Option<f64>)> =
            self.ships.iter().map(|s| (s.p, s.h, 0., None)).collect();
        let curved = self.curved_movement();
        for n in 0..self.fleets.len() {
            if curved && self.tick.saturating_sub(1) % CYCLE == 0 {
                self.fleets[n].turn_degrees = 0.;
            }
            let f = &self.fleets[n];
            let active: Vec<_> = f
                .members
                .iter()
                .filter_map(|id| self.ship(*id))
                .filter(|s| s.alive() && s.track.as_ref().is_some_and(|t| !t.done()))
                .collect();
            if active.is_empty() {
                self.fleets[n].actual = 0.;
                continue;
            }
            let target = f.speed.min(self.fleet_max(f));
            let jammed = active.iter().any(|s| s.jammed_until > self.tick);
            let accel = active
                .iter()
                .map(|s| {
                    let d = &self.data.ships[s.def];
                    if f.actual <= 0.75 * d.max_knots {
                        d.accel_knots_per_turn
                    } else {
                        d.accel_high_knots_per_turn
                    }
                })
                .fold(100., f64::min);
            let brake = active
                .iter()
                .map(|s| self.data.ships[s.def].brake_knots_per_turn)
                .fold(100., f64::min);
            let max = self.fleet_max(f);
            let accel = if curved && f.turn_degrees >= 45. { accel * 0.5 } else { accel };
            let k = if f.actual > target {
                (f.actual - brake / CYCLE as f64).max(target).min(max)
            } else {
                (f.actual + accel / CYCLE as f64).min(target)
            };
            let mut next_k = k;
            let mut turn_degrees = f.turn_degrees;
            if curved && !jammed {
                let heading_change = active
                    .iter()
                    .map(|s| {
                        let t = s.track.as_ref().unwrap();
                        delta(s.h, t.at((t.pos + k * KNOT).min(t.end)).1).abs()
                    })
                    .fold(0., f64::max);
                let loss = active
                    .iter()
                    .map(|s| self.data.ships[s.def].speed_loss_knots)
                    .fold(0., f64::max);
                turn_degrees = (turn_degrees + heading_change).min(180.);
                next_k = (k - (turn_degrees - f.turn_degrees) / 45. * loss).max(0.);
            } else if let Some(l) = self.ship(f.leader) {
                if let Some(t) = &l.track {
                    let next = t.at(t.pos + k * KNOT).1;
                    let turn = delta(l.h, next).abs();
                    if turn > 5. && !jammed {
                        let loss = active
                            .iter()
                            .map(|s| self.data.ships[s.def].speed_loss_knots)
                            .fold(0., f64::max);
                        next_k = (k - (turn / 45.).ceil() * loss).max(1.).min(target);
                    }
                }
            }
            for &s in &active {
                if jammed {
                    // A jammed rudder cannot execute the ordered turn. Keep a safe held track.
                    continue;
                }
                let t = s.track.as_ref().unwrap();
                let at = (t.pos + k * KNOT).min(t.end);
                let (p, h) = t.at(at);
                proposal[(s.id - 1) as usize] = (p, h, k, Some(at));
            }
            let slowed = target + 0.1 < f.speed
                && f.notice.as_deref()
                    != Some("有舰因损伤掉速，已限制共同航速。可降速重下航路或将受损舰脱队。");
            let ff = &mut self.fleets[n];
            ff.actual = if jammed { 0. } else { next_k };
            ff.turn_degrees = turn_degrees;
            if slowed {
                ff.notice =
                    Some("有舰因损伤掉速，已限制共同航速。可降速重下航路或将受损舰脱队。".into());
            }
        }
        // cas-realtime-v10 (CAS 8.3): a jammed rudder or a bridge circle
        // overrides the ordered track. The ship is no longer in the fleet's
        // active list because the critical cleared its track; it turns at a
        // slow rate and runs on at its current speed.
        for (i, s) in self.ships.iter().enumerate() {
            if !s.alive() {
                continue;
            }
            let direction = match (s.rudder_jam, s.bridge_circle) {
                (Some(d), _) => d,
                (None, Some(d)) => d,
                _ => continue,
            };
            if direction == 0. {
                continue;
            }
            let rate = if self.data.ships[s.def].size == "C" { 4. } else { 2. };
            let h = norm(s.h + direction * rate);
            let p = s.p + P::bearing(h) * (s.speed * KNOT);
            proposal[i] = (p, h, s.speed, None);
        }
        let mut halt: Vec<u32> = Vec::new();
        for (i, s) in self.ships.iter().enumerate().filter(|(_, s)| s.alive()) {
            if s.p.dist(proposal[i].0) < 1e-8 {
                continue;
            }
            if self.block_segment(s.p, proposal[i].0) {
                if let Some(f) = s.fleet {
                    halt.push(f);
                }
            }
            for (j, t) in self
                .ships
                .iter()
                .enumerate()
                .filter(|(j, s)| *j != i && s.alive())
            {
                let current = s.p.dist(t.p);
                if current > self.clearance(s.id, t.id)
                    && swept_separation(s.p, proposal[i].0, t.p, proposal[j].0)
                        < self.clearance(s.id, t.id)
                {
                    if let Some(f) = s.fleet {
                        halt.push(f);
                    }
                    if let Some(f) = t.fleet {
                        halt.push(f);
                    }
                }
            }
        }
        halt.sort_unstable();
        halt.dedup();
        for id in &halt {
            let f = self.fleet_mut(*id).unwrap();
            f.actual = 0.;
            f.points.clear();
            f.notice = Some("因航行危险停止；请重新下达航路。".into());
            let side = f.side;
            self.add(
                1 << side,
                "navigation_hold",
                "编队在安全距离外停止，请重新规划".into(),
                Some("RTS-SAFE-01"),
                None,
            );
        }
        for (s, (p, h, k, at)) in self.ships.iter_mut().zip(proposal) {
            if s.fleet.is_some_and(|f| halt.contains(&f)) {
                s.track = None;
                s.speed = 0.;
                continue;
            }
            s.p = p;
            s.h = h;
            if let Some(at) = at {
                if let Some(track) = s.track.as_mut() {
                    track.pos = at;
                }
            }
            s.speed = k;
        }
    }
}
pub(crate) fn fallback_leader(w: &World, id: u32, except: u32) -> Option<u32> {
    w.fleet(id)?
        .members
        .iter()
        .copied()
        .find(|&s| s != except && w.ship(s).is_some_and(Ship::alive))
}
pub(crate) fn paths_json(paths: &[(u32, Track)]) -> Vec<Value> {
    paths
        .iter()
        .map(|(id, t)| json!({"ship":id,"points":t.remaining()}))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_waypoint_keeps_the_same_track_in_preview_and_execution() {
        let points = [P { x: 6_200., y: 6_550. }, P { x: 6_200., y: 9_800. }];
        for mode in ["follow", "sync"] {
            let mut world = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
            world.enable_realtime().unwrap();
            for fleet in &mut world.fleets { fleet.ai = Ai::new("coord", "manual"); }
            let order = json!({"fleet":1,"mode":mode,"speed":20,"points":points});
            let preview = world.preview(0, &order).unwrap();
            assert_eq!(preview["valid"], true, "{preview}");
            world.route(0, &order, true).unwrap();
            let lead = world.ship(1).unwrap();
            let track = lead.track.as_ref().unwrap().clone();
            let corners: Vec<_> = track.nodes.windows(3).map(|nodes|
                delta((nodes[1] - nodes[0]).heading(), (nodes[2] - nodes[1]).heading()).abs()).collect();
            assert!(corners.iter().filter(|&&change| change > 1.).count() > 30);
            assert!(corners.iter().all(|&change| change < 2.1));
            assert!(track.nodes.iter().all(|p| p.dist(points[0]) > 100.));
            let mut prev = lead.h;
            for _ in 0..420 {
                world.advance();
                let lead = world.ship(1).unwrap();
                assert!(delta(prev, lead.h).abs() < 4.);
                assert_eq!(track.at(lead.track.as_ref().unwrap().pos).0, lead.p);
                prev = lead.h;
            }
            assert!(world.ship(1).unwrap().h < 1.);
            if mode == "sync" {
                assert!(delta(world.ship(1).unwrap().h, world.ship(5).unwrap().h).abs() < 1e-4);
            }
        }
    }

    #[test]
    fn a_short_reversal_is_rejected_instead_of_cutting_the_radius() {
        let mut world = World::new(6106, 0, "coord", "", "coord", 0).unwrap();
        world.enable_realtime().unwrap();
        let preview = world.preview(0, &json!({"fleet":1,"mode":"follow","points":[
            {"x":6800,"y":6550},{"x":6200,"y":6650}
        ]})).unwrap();
        assert_eq!(preview["valid"], false);
        assert!(preview["error"].as_str().unwrap().contains("没有足够空间转弯"));
    }
}
