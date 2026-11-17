//! Opt-in extraction pilot. Every decision consumes exactly the player observation.
//! This module has no World/Ship access and cannot inspect an undiscovered entity.
use serde::Serialize;
use serde_json::{json, Value};
use std::cmp::Reverse;
use std::collections::{BTreeMap, BTreeSet, BinaryHeap};

#[derive(Clone, Debug, Serialize)]
pub struct AutoPilot {
    #[serde(skip_serializing_if="String::is_empty")]
    pub version:String,
    pub enabled: bool,
    pub policy: String,
    pub phase: String,
    pub reason: String,
    pub target_ruin: Option<u32>,
    pub target_exit: Option<u32>,
    pub hp_fraction: f64,
    pub ammo_percent: f64,
    pub torpedoes_available: u32,
    pub stowed_value: u32,
    pub stowed_kg: u32,
    pub boss_assessment: String,
    pub last_decision_tick: u32,
    pub commands_issued: u32,
    pub last_error: Option<String>,
    #[serde(skip_serializing_if="Vec::is_empty")]
    pub fleet_targets:Vec<Value>,
    #[serde(skip)]
    retreat: bool,
    #[serde(skip)]
    failures: u32,
    #[serde(skip)]
    skipped: BTreeSet<u32>,
    #[serde(skip)]
    routes: BTreeMap<u32, (Pt, u32)>,
    #[serde(skip)]
    last_evade: u32,
    #[serde(skip)]
    task: Option<String>,
    #[serde(skip)]
    sorted: BTreeSet<String>,
    #[serde(skip)]
    berths: BTreeMap<u32, Pt>,
    #[serde(skip)]
    approach_progress: BTreeMap<String,(f64,u32)>,
    #[serde(skip)]
    skipped_tasks: BTreeSet<String>,
    #[serde(skip)]
    rejected_berths: BTreeMap<u32,BTreeSet<(i32,i32)>>,
    #[serde(skip)]
    compacted: BTreeSet<u32>,
    #[serde(skip)]
    compacting: Option<(u32,u32)>,
    #[serde(skip)]
    compact_failures:BTreeMap<u32,(u32,u32)>,
    #[serde(skip)]
    last_ingress_retry:u32,
    #[serde(skip)]
    fleet_assignments:BTreeMap<u32,u32>,
    #[serde(skip)]
    searched_fleets:BTreeSet<u32>,
    #[serde(skip)]
    fleet_progress:BTreeMap<u32,(u32,f64,u32)>,
    #[serde(skip)]
    fleet_skipped:BTreeSet<(u32,u32)>,
    #[serde(skip)]
    search_attempts:BTreeMap<(u32,u32),u32>,
}
impl Default for AutoPilot {
    fn default() -> Self {
        Self {
            version:String::new(),
            enabled: false,
            policy: "balanced".into(),
            phase: "off".into(),
            reason: "等待指挥官授权".into(),
            target_ruin: None,
            target_exit: None,
            hp_fraction: 1.,
            ammo_percent: 100.,
            torpedoes_available: 0,
            stowed_value: 0,
            stowed_kg: 0,
            boss_assessment: "未发现可评估目标".into(),
            last_decision_tick: 0,
            commands_issued: 0,
            last_error: None,
            fleet_targets:vec![],
            retreat: false,
            failures: 0,
            skipped: BTreeSet::new(),
            routes: BTreeMap::new(),
            last_evade: 0,
            task: None,
            sorted: BTreeSet::new(),
            berths: BTreeMap::new(),
            approach_progress: BTreeMap::new(),
            skipped_tasks: BTreeSet::new(),
            rejected_berths: BTreeMap::new(),
            compacted:BTreeSet::new(),
            compacting:None,
            compact_failures:BTreeMap::new(),
            last_ingress_retry:0,
            fleet_assignments:BTreeMap::new(),searched_fleets:BTreeSet::new(),fleet_progress:BTreeMap::new(),fleet_skipped:BTreeSet::new(),
            search_attempts:BTreeMap::new(),
        }
    }
}
pub fn command(state: &mut AutoPilot, q: &Value) -> Result<(), String> {
    let version=q.get("version").and_then(Value::as_str).unwrap_or("");
    if !["","cas-extraction-pilot-v2","cas-extraction-pilot-v3"].contains(&version){return Err("自动搜打撤版本无效".into());}
    let enabled = q["enabled"].as_bool().ok_or("请选择自动搜打撤开启状态")?;
    let policy = q
        .get("policy")
        .and_then(Value::as_str)
        .unwrap_or(&state.policy);
    if !["cautious", "balanced", "bold"].contains(&policy) {
        return Err("自动搜打撤偏好无效".into());
    }
    let policy = policy.to_owned();
    state.enabled = enabled;
    state.version=version.into();
    state.policy = policy;
    state.phase = if enabled { "assess" } else { "off" }.into();
    state.reason = if enabled {
        "评估已知海域与物资"
    } else {
        "自动已关闭，现有命令保留"
    }
    .into();
    state.retreat = false;
    state.failures = 0;
    state.routes.clear();
    state.skipped.clear();
    state.sorted.clear();
    state.berths.clear();
    state.approach_progress.clear();
    state.skipped_tasks.clear();
    state.rejected_berths.clear();
    state.compacted.clear();state.compacting=None;
    state.compact_failures.clear();
    state.last_ingress_retry=0;state.fleet_targets.clear();state.fleet_assignments.clear();state.searched_fleets.clear();state.fleet_progress.clear();state.fleet_skipped.clear();
    state.search_attempts.clear();
    state.task=None;
    state.target_ruin = None;
    state.target_exit = None;
    state.last_error = None;
    Ok(())
}
pub fn manual_override(state: &mut AutoPilot, q: &Value, tick: u32) {
    // In the current pilot, arranging cargo is cooperation with its logistics,
    // while tactical orders still transfer command to the player. Old logs
    // keep their original takeover semantics.
    if state.version=="cas-extraction-pilot-v3" && matches!(q["op"].as_str(),Some("cargo_place"|"cargo_drop"|"cargo_sort")){return;}
    if state.enabled
        && matches!(
            q["op"].as_str().unwrap_or(""),
            "route"
                | "speed"
                | "resume"
                | "fire"
                | "gun_cancel"
                | "illuminate"
                | "radar_set"
                | "searchlight"
                | "smoke"
                | "lead"
                | "detach"
                | "reform"
                | "ai"
                | "salvage_collect"
                | "search_salvage"
                | "cancel_search"
                | "salvage_cancel"
                | "salvage_extract"
                | "cargo_place"
                | "cargo_drop"
                | "cargo_sort"
                | "salvage_drop"
                | "salvage_abandon"
                | "expedition_task"
                | "expedition_interact"
        )
    {
        state.enabled = false;
        state.phase = "manual".into();
        state.reason = "指挥官已接管".into();
        state.last_decision_tick = tick;
    }
}
pub fn feedback(state: &mut AutoPilot, q: &Value, result: Result<(), String>) {
    match result {
        Ok(()) => {
            if q["op"]=="reform"&&q.get("spacing_m").is_some(){if let Some(id)=q["fleet"].as_u64(){state.compacted.insert(id as u32);}}
            state.commands_issued = state.commands_issued.saturating_add(1);
            state.last_error = None;
            state.failures = 0;
        }
        Err(e) => {
            if q["op"]=="reform"&&q.get("spacing_m").is_some(){if let Some(id)=q["fleet"].as_u64(){let count=state.compact_failures.get(&(id as u32)).map_or(1,|(count,_)|count+1);state.compact_failures.insert(id as u32,(count,state.last_decision_tick));state.compacting=None;}}
            state.last_error = Some(e);
            state.failures += 1;
            if q["op"] == "route" {
                if let Some(id) = q["fleet"].as_u64() {
                    state.routes.remove(&(id as u32));
                    if state.version=="cas-extraction-pilot-v3"&&!state.last_error.as_ref().is_some_and(|e|e.contains("暂时不能转向")){if let Some(p)=state.berths.remove(&(id as u32)){state.rejected_berths.entry(id as u32).or_default().insert((p.x.round()as i32,p.y.round()as i32));}}
                }
            }
            if state.failures >= 4 {
                if let Some(id) = state.target_ruin.take() {
                    state.skipped.insert(id);
                }
                state.retreat = true;
                state.reason = "原命令无法安全完成，准备返航".into();
            }
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Pt {
    x: f64,
    y: f64,
}
impl Pt {
    fn of(v: &Value) -> Self {
        let p = if v["p"].is_object() { &v["p"] } else { v };
        Self {
            x: num(p, "x"),
            y: num(p, "y"),
        }
    }
    fn dist(self, b: Self) -> f64 {
        libm::sqrt((self.x - b.x) * (self.x - b.x) + (self.y - b.y) * (self.y - b.y))
    }
    fn add(self, x: f64, y: f64) -> Self {
        Self {
            x: self.x + x,
            y: self.y + y,
        }
    }
    fn value(self) -> Value {
        json!({"x":self.x,"y":self.y})
    }
}
fn num(v: &Value, k: &str) -> f64 {
    v[k].as_f64().unwrap_or(0.)
}
fn rows(v: &Value) -> &[Value] {
    v.as_array().map(Vec::as_slice).unwrap_or(&[])
}
fn usable_cells(grid: &Value) -> usize {
    grid["usable_cells"]
        .as_u64()
        .unwrap_or((num(grid, "cols") * num(grid, "rows")) as u64) as usize
}
fn alive(v: &Value) -> Vec<&Value> {
    rows(&v["ships"])
        .iter()
        .filter(|s| num(s, "hp") > 0.)
        .collect()
}
fn phase(s: &mut AutoPilot, name: &str, reason: &str) {
    s.phase = name.into();
    s.reason = reason.into();
}
fn task_pilot(s:&AutoPilot)->bool{matches!(s.version.as_str(),"cas-extraction-pilot-v2"|"cas-extraction-pilot-v3")}
fn stalled(s:&mut AutoPilot,key:String,distance:f64,tick:u32)->bool{
    let progress=s.approach_progress.entry(key).or_insert((distance,tick));
    if distance+80.<progress.0{*progress=(distance,tick);return false;}
    tick.saturating_sub(progress.1)>90
}
fn centroid(ships: &[&Value]) -> Pt {
    let n = ships.len().max(1) as f64;
    Pt {
        x: ships.iter().map(|s| num(s, "x")).sum::<f64>() / n,
        y: ships.iter().map(|s| num(s, "y")).sum::<f64>() / n,
    }
}
fn unit(a: Pt, b: Pt) -> (f64, f64) {
    let d = a.dist(b).max(1.);
    ((a.x - b.x) / d, (a.y - b.y) / d)
}
fn segment_distance(p: Pt, a: Pt, b: Pt) -> f64 {
    let dx = b.x - a.x;
    let dy = b.y - a.y;
    let t = if dx * dx + dy * dy > 0. {
        ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)
    } else {
        0.
    };
    p.dist(a.add(dx * t.clamp(0., 1.), dy * t.clamp(0., 1.)))
}
fn inside(poly: &[Pt], p: Pt) -> bool {
    let mut hit = false;
    if poly.len() < 3 {
        return false;
    }
    let mut j = poly.len() - 1;
    for i in 0..poly.len() {
        let a = poly[i];
        let b = poly[j];
        if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
            hit = !hit;
        }
        j = i;
    }
    hit
}
fn polygons(v: &Value) -> Vec<Vec<Pt>> {
    rows(&v["islands"])
        .iter()
        .map(|poly| rows(poly).iter().map(Pt::of).collect())
        .collect()
}
fn clear(polys: &[Vec<Pt>], a: Pt, b: Pt, margin: f64) -> bool {
    !polys.iter().any(|poly| {
        inside(poly, a)
            || inside(poly, b)
            || (0..poly.len()).any(|i| {
                let p = poly[i];
                let q = poly[(i + 1) % poly.len()];
                segment_distance(p, a, b) < margin
                    || segment_distance(q, a, b) < margin
                    || segment_distance(a, p, q) < margin
                    || segment_distance(b, p, q) < margin
                    || {
                        let cross = |r: Pt, s: Pt, t: Pt| {
                            (s.x - r.x) * (t.y - r.y) - (s.y - r.y) * (t.x - r.x)
                        };
                        cross(a, b, p) * cross(a, b, q) < 0. && cross(p, q, a) * cross(p, q, b) < 0.
                    }
            })
    })
}
fn threat(v: &Value, p: Pt) -> f64 {
    rows(&v["contacts"])
        .iter()
        .map(|c| {
            if num(c, "health") == 0. && c.get("health").is_some() {
                return 0.;
            }
            let naval = c["entityKind"] == "naval";
            let reach = num(&c["attack"], "range").max(if c["boss"].as_bool() == Some(true) {
                5000.
            } else {
                2200.
            });
            // Gun range is not a guaranteed-hit area. Conventional vessels are
            // evaluated as a softer standoff threat than an announced monster
            // strike; otherwise one far-away cruiser rejects the entire map.
            let reach = if naval { reach.min(5500.) } else { reach };
            ((reach + 700. - p.dist(Pt::of(c))) / (reach + 700.)).max(0.)
                * (if c["boss"].as_bool() == Some(true) {
                    5.
                } else {
                    if naval {
                        0.45
                    } else {
                        1.
                    }
                })
        })
        .sum()
}
fn site_risk(v:&Value,s:&AutoPilot,p:Pt)->f64{
    if s.version!="cas-extraction-pilot-v3"||s.hp_fraction<0.80||s.ammo_percent<35. {return threat(v,p);}
    // A large healthy player fleet can approach conventional patrols while
    // still respecting creature telegraphs. Scale by public opposing hull
    // strength rather than rejecting the entire map at nominal gun range.
    let strength=alive(v).iter().map(|ship|num(ship,"hp")).sum::<f64>();
    let opposition=rows(&v["contacts"]).iter().filter(|c|c["boss"]!=true&&Pt::of(c).dist(p)<6500.).map(|c|num(c,"health")).sum::<f64>();
    if strength<opposition*1.5{return threat(v,p);}
    let dominant=strength>opposition*2.;
    let mut chart=v.clone();chart["contacts"]=json!(rows(&v["contacts"]).iter().filter(|c|c["boss"]==true||c["entityKind"]!="naval"&&!dominant).collect::<Vec<_>>());
    threat(&chart,p)+(threat(v,p)-threat(&chart,p))*0.2
}
fn safe_edge(v: &Value, a: Pt, b: Pt) -> bool {
    let cap = threat(v, a).max(threat(v, b)).max(0.2) + 0.2;
    let n = (a.dist(b) / 400.).ceil().max(1.) as u32;
    (0..=n).all(|i| {
        threat(
            v,
            a.add(
                (b.x - a.x) * i as f64 / n as f64,
                (b.y - a.y) * i as f64 / n as f64,
            ),
        ) <= cap
    })
}
/// Dijkstra over the public chart, then line-of-sight pruning. All edges keep
/// hull clearance; public hostile reach adds cost, never hidden occupancy.
fn path(v: &Value, start: Pt, goal: Pt) -> Option<Vec<Pt>> {
    let polys = polygons(v);
    if clear(&polys, start, goal, 220.) && safe_edge(v, start, goal) {
        return Some(vec![goal]);
    }
    let step = 600.;
    let w = (num(v, "width") / step).ceil().max(1.) as i32;
    let h = (num(v, "height") / step).ceil().max(1.) as i32;
    if w * h > 30000 {
        return None;
    }
    let point = |n: usize| Pt {
        x: (n as i32 % w) as f64 * step + step / 2.,
        y: (n as i32 / w) as f64 * step + step / 2.,
    };
    let valid = |p: Pt| {
        p.x > 100.
            && p.y > 100.
            && p.x < num(v, "width") - 100.
            && p.y < num(v, "height") - 100.
            && clear(&polys, p, p, 350.)
    };
    let index = |p: Pt| {
        ((p.y / step) as i32).clamp(0, h - 1) as usize * w as usize
            + ((p.x / step) as i32).clamp(0, w - 1) as usize
    };
    let first = index(start);
    let last = index(goal);
    let count = (w * h) as usize;
    let mut costs = vec![u32::MAX; count];
    let mut prev = vec![usize::MAX; count];
    let mut queue = BinaryHeap::new();
    costs[first] = 0;
    queue.push(Reverse((0u32, first)));
    while let Some(Reverse((cost, n))) = queue.pop() {
        if cost != costs[n] {
            continue;
        }
        if n == last {
            break;
        }
        let from = if n == first { start } else { point(n) };
        for (dx, dy) in [
            (1, 0),
            (0, 1),
            (-1, 0),
            (0, -1),
            (1, 1),
            (1, -1),
            (-1, 1),
            (-1, -1),
        ] {
            let x = n as i32 % w + dx;
            let y = n as i32 / w + dy;
            if x < 0 || y < 0 || x >= w || y >= h {
                continue;
            }
            let next = (y * w + x) as usize;
            let p = if next == last { goal } else { point(next) };
            if !valid(p) || !clear(&polys, from, p, 300.) {
                continue;
            }
            let value = cost.saturating_add(from.dist(p) as u32 + ((threat(v, p) * 1800.) as u32));
            if value < costs[next] {
                costs[next] = value;
                prev[next] = n;
                queue.push(Reverse((value, next)));
            }
        }
    }
    if costs[last] == u32::MAX {
        return None;
    }
    let mut raw = vec![goal];
    let mut at = last;
    while at != first {
        at = prev[at];
        if at == usize::MAX {
            return None;
        }
        if at != first {
            raw.push(point(at));
        }
    }
    raw.reverse();
    let mut result = vec![];
    let mut from = start;
    let mut pos = 0;
    while pos < raw.len() {
        let mut chosen = pos;
        for i in pos + 1..raw.len() {
            if clear(&polys, from, raw[i], 350.) && safe_edge(v, from, raw[i]) {
                chosen = i;
            } else {
                break;
            }
        }
        from = raw[chosen];
        result.push(from);
        pos = chosen + 1;
    }
    if result.len() > 10 {
        None
    } else {
        Some(result)
    }
}
fn bearing(degrees: f64) -> Pt {
    let a = degrees.to_radians();
    Pt {
        x: libm::sin(a),
        y: libm::cos(a),
    }
}
fn heading(p: Pt) -> f64 {
    libm::atan2(p.x, p.y).to_degrees().rem_euclid(360.)
}
fn change(a: f64, b: f64) -> f64 {
    (b - a + 180.).rem_euclid(360.) - 180.
}
fn arc(nodes: &mut Vec<Pt>, center: Pt, radius: f64, radial: f64, sweep: f64) {
    let n = (sweep.abs() / 4.).ceil().max(1.) as u32;
    for i in 1..=n {
        let b = bearing(radial + sweep * i as f64 / n as f64);
        nodes.push(center.add(b.x * radius, b.y * radius));
    }
}
/// Predict our own published turning geometry only. The authoritative route
/// command still checks every fleet member, terrain and friendly separation.
fn curve_clear(v: &Value, start: Pt, h: f64, points: &[Pt], advance: f64) -> bool {
    if points.is_empty() || points.len() > 10 {
        return false;
    }
    let radius = advance / 45_f64.to_radians();
    let first = points[0];
    let turn = change(
        h,
        heading(Pt {
            x: first.x - start.x,
            y: first.y - start.y,
        }),
    );
    let mut nodes = vec![start];
    if turn.abs() > 0.000001 {
        let bow = bearing(h);
        let from = if turn.abs() > 10. {
            start.add(bow.x * advance, bow.y * advance)
        } else {
            start
        };
        let b = bearing(h + turn.signum() * 90.);
        let center = from.add(b.x * radius, b.y * radius);
        let delta = Pt {
            x: first.x - center.x,
            y: first.y - center.y,
        };
        let distance = delta.dist(Pt::default());
        if distance <= radius {
            return false;
        }
        let radial = h - turn.signum() * 90.;
        let tangent = heading(delta) - turn.signum() * libm::acos(radius / distance).to_degrees();
        let sweep = ((tangent - radial) * turn.signum()).rem_euclid(360.);
        if sweep >= 180. {
            return false;
        }
        if from != start {
            nodes.push(from);
        }
        arc(&mut nodes, center, radius, radial, sweep * turn.signum());
    }
    let mut prior = *nodes.last().unwrap();
    for pair in points.windows(2) {
        let point = pair[0];
        let next = pair[1];
        let incoming = unit(point, prior);
        let outgoing = unit(next, point);
        let h1 = heading(Pt {
            x: incoming.0,
            y: incoming.1,
        });
        let h2 = heading(Pt {
            x: outgoing.0,
            y: outgoing.1,
        });
        let turn = change(h1, h2);
        if turn.abs() <= 0.000001 {
            nodes.push(point);
            prior = point;
            continue;
        }
        let cut = radius * libm::tan(turn.abs().to_radians() / 2.);
        if turn.abs() >= 179.
            || cut + 0.0001 >= prior.dist(point)
            || cut + 0.0001 >= point.dist(next)
        {
            return false;
        }
        let from = point.add(-incoming.0 * cut, -incoming.1 * cut);
        let radial = h1 - turn.signum() * 90.;
        let b = bearing(radial);
        let center = from.add(-b.x * radius, -b.y * radius);
        nodes.push(from);
        arc(&mut nodes, center, radius, radial, turn);
        prior = point.add(outgoing.0 * cut, outgoing.1 * cut);
    }
    nodes.push(*points.last().unwrap());
    let polys = polygons(v);
    nodes.iter().all(|p| {
        p.x > 100. && p.y > 100. && p.x < num(v, "width") - 100. && p.y < num(v, "height") - 100.
    }) && nodes.windows(2).all(|p| clear(&polys, p[0], p[1], 110.))
}
fn steering_path(v: &Value, leader: &Value, members: &[&Value], goal: Pt) -> Option<Vec<Pt>> {
    let start = Pt::of(leader);
    let h = num(leader, "heading");
    let advance = members
        .iter()
        .map(|ship| num(&ship["navigation"], "turn_advance_m"))
        .fold(0., f64::max)
        .max(250.);
    let direct = path(v, start, goal)?;
    if curve_clear(v, start, h, &direct, advance) {
        return Some(direct);
    }
    let bow = bearing(h);
    let side = bearing(h + 90.);
    let mut best: Option<(f64, Vec<Pt>)> = None;
    for distance in [advance * 3.5, advance * 5., advance * 7.] {
        for sign in [1., -1.] {
            let a = start.add(bow.x * distance, bow.y * distance);
            let b = a.add(side.x * distance * sign, side.y * distance * sign);
            let c = b.add(-bow.x * distance, -bow.y * distance);
            for prefix in [vec![a], vec![a, b], vec![a, b, c], vec![b]] {
                let last = *prefix.last().unwrap();
                if last.x < 100.
                    || last.y < 100.
                    || last.x > num(v, "width") - 100.
                    || last.y > num(v, "height") - 100.
                {
                    continue;
                }
                let Some(rest) = path(v, last, goal) else {
                    continue;
                };
                let mut points = prefix;
                points.extend(rest);
                if !curve_clear(v, start, h, &points, advance) {
                    continue;
                }
                let mut score = 0.;
                let mut from = start;
                for p in &points {
                    score += from.dist(*p) + threat(v, *p) * 1000.;
                    from = *p;
                }
                if best.as_ref().is_none_or(|(old, _)| score < *old) {
                    best = Some((score, points));
                }
            }
        }
    }
    best.map(|(_, p)| p)
}
fn navigate(v: &Value, s: &mut AutoPilot, goal: Pt, knots: f64, force: bool) -> Vec<Value> {
    navigate_selected(v, s, goal, knots, force, None)
}
fn navigate_selected(
    v: &Value,
    s: &mut AutoPilot,
    goal: Pt,
    knots: f64,
    force: bool,
    only: Option<u32>,
) -> Vec<Value> {
    let tick = num(v, "tick") as u32;
    let own = alive(v);
    let mut commands = vec![];
    for fleet in rows(&v["fleets"]) {
        let id = num(fleet, "id") as u32;
        if only.is_some_and(|selected| selected != id) {
            continue;
        }
        let members: Vec<_> = own
            .iter()
            .copied()
            .filter(|ship| num(ship, "fleet") == id as f64)
            .collect();
        if members.is_empty() {
            continue;
        }
        if s.retreat
            && s.target_exit
                .and_then(|id| rows(&v["salvage"]["exits"]).get(id as usize))
                .is_some_and(|exit| members.iter().all(|ship| exit_contains(exit, Pt::of(ship))))
        {
            if num(fleet, "speed") > 0. {
                commands.push(json!({"op":"speed","fleet":id,"speed":0}));
            }
            continue;
        }
        let leader = members
            .iter()
            .find(|ship| ship["id"] == fleet["leader"])
            .copied()
            .unwrap_or(members[0]);
        let origin = Pt::of(leader);
        if origin.dist(goal) < 150. {
            if s.version=="cas-extraction-pilot-v3"&&num(fleet,"speed")>knots+0.5{commands.push(json!({"op":"speed","fleet":id,"speed":knots}));}
            continue;
        }
        // A successfully installed route may be waiting on an authoritative
        // collision hold. Give it a few real ticks before recalculating the
        // entire turning graph; never reset the same curve every second.
        if !force&&s.version=="cas-extraction-pilot-v3"&&s.routes.get(&id).is_some_and(|(p,t)|p.dist(goal)<220.&&tick.saturating_sub(*t)<4){continue;}
        if !force
            && s.routes.get(&id).is_some_and(|(p, t)| {
                p.dist(goal) < 220.
                    && (tick.saturating_sub(*t) < 180 || !rows(&fleet["paths"]).is_empty())
                    && num(fleet, "actual") > 0.05
            })
        {
            if num(fleet, "speed") > knots + 0.5 {
                commands.push(
                    json!({"op":"speed","fleet":id,"speed":knots.min(num(fleet,"maxSpeed"))}),
                );
            }
            continue;
        }
        if let Some(points) = steering_path(v, leader, &members, goal) {
            let max = num(fleet, "maxSpeed");
            if max < 4. {
                continue;
            }
            commands.push(json!({"op":"route","fleet":id,"mode":"follow","speed":knots.min(max).max(4.),"points":points.iter().map(|p|p.value()).collect::<Vec<_>>()}));
            s.routes.insert(id, (goal, tick));
        }
    }
    commands
}
fn exit_contains(exit: &Value, p: Pt) -> bool {
    if exit["shape"] == "rectangle" {
        let b = &exit["bounds"];
        p.x >= num(b, "min_x")
            && p.x <= num(b, "max_x")
            && p.y >= num(b, "min_y")
            && p.y <= num(b, "max_y")
    } else {
        p.dist(Pt::of(exit)) < num(exit, "radius").max(1000.) - 75.
    }
}
fn exit_goal(exit: &Value, from: Pt) -> Pt {
    if exit["shape"] == "rectangle" {
        let b = &exit["bounds"];
        Pt {
            x: from.x.clamp(num(b, "min_x") + 250., num(b, "max_x") - 250.),
            y: from.y.clamp(num(b, "min_y") + 250., num(b, "max_y") - 250.),
        }
    } else {
        Pt::of(exit)
    }
}
fn withdraw(v: &Value, s: &mut AutoPilot, reason: &str) -> Vec<Value> {
    if s.version=="cas-extraction-pilot-v3" {return withdraw_v3(v,s,reason);}
    s.retreat = true;
    phase(s, "extract", reason);
    s.target_ruin = None;
    let own = alive(v);
    if own.is_empty() {
        return vec![];
    }
    let center = centroid(&own);
    let mut choices: Vec<_> = rows(&v["salvage"]["exits"]).iter().enumerate().collect();
    choices.sort_by(|(ai, a), (bi, b)| {
        exit_goal(a, center)
            .dist(center)
            .total_cmp(&exit_goal(b, center).dist(center))
            .then(ai.cmp(bi))
    });
    for (i, exit) in choices {
        let mut goal = exit_goal(exit, center);
        if s.version=="cas-extraction-pilot-v2" && exit["shape"]=="rectangle" {
            // A leader stopping 250 m inside the rectangle can leave the tail
            // of a multi-ship column permanently outside. Aim far enough in
            // for the longest current formation, rather than only its centroid.
            let spread=own.iter().map(|ship|rows(&v["fleets"]).iter().find(|f|f["id"]==ship["fleet"]).and_then(|f|own.iter().find(|s|s["id"]==f["leader"])).map_or(0.,|lead|Pt::of(ship).dist(Pt::of(lead)))).fold(0.,f64::max);
            let b=&exit["bounds"];let width=num(b,"max_x")-num(b,"min_x");let height=num(b,"max_y")-num(b,"min_y");
            if spread>width.max(height)-550. {
                let mut split=vec![];
                for fleet in rows(&v["fleets"]){for ship in rows(&fleet["members"]).iter().skip(1){split.push(json!({"op":"detach","fleet":fleet["id"],"ship":ship}));}}
                if !split.is_empty(){phase(s,"extract","长纵队暂时分舰入港，确保所有舰艇进入接驳区");return split;}
            }
            // The tail needs room behind the direction of entry, not the same
            // full-column margin on both sides of a narrow rectangle.
            let gx=if center.x>(num(b,"min_x")+num(b,"max_x"))*0.5 {(num(b,"max_x")-spread-350.).max(num(b,"min_x")+250.)}else{(num(b,"min_x")+spread+350.).min(num(b,"max_x")-250.)};
            goal=Pt{x:gx,y:center.y.clamp(num(b,"min_y")+250.,num(b,"max_y")-250.)};
        }
        if !own.iter().all(|ship| exit_contains(exit, Pt::of(ship)))
            && path(v, center, goal).is_none()
        {
            continue;
        }
        s.target_exit = Some(i as u32);
        if own.iter().all(|ship| exit_contains(exit, Pt::of(ship))) {
            let stops: Vec<_> = rows(&v["fleets"])
                .iter()
                .filter(|f| num(f, "speed") > 0.)
                .map(|f| json!({"op":"speed","fleet":f["id"],"speed":0}))
                .collect();
            if !stops.is_empty() {
                return stops;
            }
            if !v["salvage"]["extracting"].is_null() {
                phase(s, "extract_wait", "已集结，等待接驳完成");
                return vec![];
            }
            return vec![json!({"op":"salvage_extract","exit":i})];
        }
        return navigate(v, s, goal, 30., false);
    }
    phase(s, "blocked", "未找到已知可达撤离航路，等待接管");
    vec![]
}
/// The exit is a shared area, not one waypoint for every independent fleet.
/// Berth ships in arrival order and move one fleet at a time. This avoids
/// detached tails driving into the first ship parked at the entrance.
fn compact_fleets(v:&Value,s:&mut AutoPilot)->Option<Vec<Value>>{
    if s.version!="cas-extraction-pilot-v3"{return None;}
    if let Some((id,start))=s.compacting{
        if (num(v,"tick")as u32).saturating_sub(start)<90&&rows(&v["fleets"]).iter().any(|f|num(f,"id")as u32==id&&num(f,"actual")>0.05){phase(s,"rally","逐舰真实航行，收紧撤离纵队");return Some(vec![]);}
        s.compacting=None;
    }
    for f in rows(&v["fleets"]){
        let id=num(f,"id")as u32;
        if rows(&f["members"]).len()>1&&!s.compacted.contains(&id)&&s.compact_failures.get(&id).is_none_or(|(count,last)|*count<3&&(num(v,"tick")as u32).saturating_sub(*last)>=10){
            s.compacting=Some((id,num(v,"tick")as u32));
            phase(s,"rally","按舰长安全间距收紧纵队，一同撤离");
            return Some(vec![json!({"op":"reform","fleet":id,"spacing_m":100})]);
        }
    }
    None
}
fn withdraw_v3(v:&Value,s:&mut AutoPilot,reason:&str)->Vec<Value>{
    if s.phase=="blocked"&&(num(v,"tick")as u32).saturating_sub(s.last_ingress_retry)<15{return vec![];}
    s.last_ingress_retry=num(v,"tick")as u32;
    s.retreat=true;phase(s,"extract",reason);s.target_ruin=None;
    let own=alive(v);if own.is_empty(){return vec![];}
    let center=centroid(&own);
    if let Some(actions)=compact_fleets(v,s){return actions;}
    let mut exits:Vec<_>=rows(&v["salvage"]["exits"]).iter().enumerate().collect();
    exits.sort_by(|(ai,a),(bi,b)|(s.target_exit!=Some(*ai as u32)).cmp(&(s.target_exit!=Some(*bi as u32))).then(exit_goal(a,center).dist(center).total_cmp(&exit_goal(b,center).dist(center))).then(ai.cmp(bi)));
    for(index,exit)in exits{
        // Long formations cannot all enter a compact rectangle. Detach only
        // through the normal authority command; positions are never changed.
        let mut split=vec![];
        if exit["shape"]=="rectangle"{
            let b=&exit["bounds"];let room=(num(b,"max_x")-num(b,"min_x")).max(num(b,"max_y")-num(b,"min_y"))-550.;
            for f in rows(&v["fleets"]){
                let members:Vec<_>=own.iter().copied().filter(|ship|ship["fleet"]==f["id"]).collect();
                if let Some(leader)=members.iter().find(|ship|ship["id"]==f["leader"]){
                    if members.iter().any(|ship|Pt::of(ship).dist(Pt::of(leader))>room){
                        for ship in rows(&f["members"]).iter().skip(1){split.push(json!({"op":"detach","fleet":f["id"],"ship":ship}));}
                    }
                }
            }
        }
        if !split.is_empty(){s.berths.clear();s.routes.clear();return split;}
        s.target_exit=Some(index as u32);
        if own.iter().all(|ship|exit_contains(exit,Pt::of(ship))){
            let stops:Vec<_>=rows(&v["fleets"]).iter().filter(|f|num(f,"speed")>0.).map(|f|json!({"op":"speed","fleet":f["id"],"speed":0})).collect();
            if !stops.is_empty(){return stops;}
            if !v["salvage"]["extracting"].is_null(){phase(s,"extract_wait","已集结，等待接驳完成");return vec![];}
            return vec![json!({"op":"salvage_extract","exit":index})];
        }
        let mut fleets:Vec<_>=rows(&v["fleets"]).iter().filter(|f|own.iter().any(|ship|ship["fleet"]==f["id"])).collect();
        fleets.sort_by(|a,b|{
            let distance=|f:&&Value|own.iter().find(|ship|ship["id"]==f["leader"]).map_or(f64::INFINITY,|ship|Pt::of(ship).dist(Pt::of(exit)));
            distance(a).total_cmp(&distance(b)).then(num(a,"id").total_cmp(&num(b,"id")))
        });
        // The movement authority can accept a route, then clear it on the
        // next physical tick when another hull crosses its swept path. That
        // is a failed ingress, not an invitation to alternate stop/route every
        // second. Keep combat active and use the bounded blocked retry delay.
        if let Some(f)=fleets.iter().find(|f|{
            let id=num(f,"id")as u32;
            s.berths.contains_key(&id)&&s.routes.contains_key(&id)&&rows(&f["paths"]).is_empty()
                &&f["notice"].as_str().is_some_and(|notice|notice.contains("航行危险停止"))
        }){
            let id=num(f,"id")as u32;s.routes.remove(&id);
            if let Some(p)=s.berths.remove(&id){s.rejected_berths.entry(id).or_default().insert((p.x.round()as i32,p.y.round()as i32));}
            let enemy=rows(&v["contacts"]).iter().any(|contact|contact["entityKind"]=="naval"&&num(contact,"health")>0.&&own.iter().any(|ship|Pt::of(ship).dist(Pt::of(contact))<500.));
            phase(s,"blocked",if enemy{"敌舰阻挡航道，停航交战并寻找通路"}else{"航路被近处舰艇阻挡，保持火力并等待安全通路"});
            return if num(f,"speed")>0.{vec![json!({"op":"speed","fleet":id,"speed":0})]}else{vec![]};
        }
        // A fleet with a valid active ingress retains exclusive use of the
        // approach. Never restart its curve each second or let another cross.
        if let Some(f)=fleets.iter().find(|f|{
            let id=num(f,"id")as u32;
            s.routes.contains_key(&id)&&!rows(&f["paths"]).is_empty()
                &&(num(f,"actual")>0.05||num(f,"speed")>0.&&s.berths.get(&id).is_some_and(|berth|s.routes.get(&id).is_some_and(|(goal,_)|goal.dist(*berth)<1.)))
        }){
            let id=num(f,"id")as u32;
            let remaining=rows(&f["paths"]).iter().map(|p|rows(&p["points"]).windows(2).map(|p|Pt::of(&p[0]).dist(Pt::of(&p[1]))).sum::<f64>()).fold(0.,f64::max);
            let goal=s.berths.get(&id).copied().or_else(||s.routes.get(&id).map(|(goal,_)|*goal)).unwrap_or_default();
            if stalled(s,format!("ingress:{id}:{}:{}",goal.x.round(),goal.y.round()),remaining,num(v,"tick")as u32){
                s.routes.remove(&id);
                if let Some(p)=s.berths.remove(&id){s.rejected_berths.entry(id).or_default().insert((p.x.round()as i32,p.y.round()as i32));}
                phase(s,"extract","入区航路停止推进，暂停并重新规划");return vec![json!({"op":"speed","fleet":id,"speed":0})];
            }
            let stops:Vec<_>=fleets.iter().filter(|other|num(other,"id")as u32!=id&&num(other,"speed")>0.).map(|other|json!({"op":"speed","fleet":other["id"],"speed":0})).collect();
            if !stops.is_empty(){return stops;}
            return vec![];
        }
        let stops:Vec<_>=fleets.iter().filter(|f|num(f,"speed")>0.).map(|f|json!({"op":"speed","fleet":f["id"],"speed":0})).collect();
        if !stops.is_empty(){return stops;}
        let mut slots=vec![];
        if exit["shape"]=="rectangle"{
            let b=&exit["bounds"];
            for row in 0..3{for col in 0..5{
                let p=Pt{x:num(b,"min_x")+250.+col as f64*(num(b,"max_x")-num(b,"min_x")-500.)/4.,y:num(b,"min_y")+250.+row as f64*(num(b,"max_y")-num(b,"min_y")-500.)/2.};slots.push(p);
            }}
            // Fill the interior beyond the entering column before the edge.
            slots.sort_by(|a,b|b.dist(center).total_cmp(&a.dist(center)).then(a.x.total_cmp(&b.x)).then(a.y.total_cmp(&b.y)));
        }else{
            slots.push(Pt::of(exit));
            for r in [350.,650.]{for a in 0..8{let d=bearing(a as f64*45.);slots.push(Pt::of(exit).add(d.x*r,d.y*r));}}
        }
        for f in fleets{
            let id=num(f,"id")as u32;
            let members:Vec<_>=own.iter().copied().filter(|ship|ship["fleet"]==f["id"]).collect();
            let leader=members.iter().find(|ship|ship["id"]==f["leader"]).copied().unwrap_or(members[0]);
            // Once a ship is inside it may still need to move off the entry
            // line to admit the tail. Give it a distinct, clear berth.
            if let Some(berth)=s.berths.get(&id){if Pt::of(leader).dist(*berth)<150.&&members.iter().all(|ship|exit_contains(exit,Pt::of(ship))){continue;}}
            let mut chart=v.clone();
            let mut obstacles=rows(&v["islands"]).to_vec();
            for ship in &own{if ship["fleet"]!=f["id"]{
                let p=Pt::of(ship);let r=(num(ship,"hullLengthM").max(75.)+num(leader,"hullLengthM").max(75.))*0.5+30.;
                obstacles.push(json!([p.add(-r,-r).value(),p.add(r,-r).value(),p.add(r,r).value(),p.add(-r,r).value()]));
            }}
            chart["islands"]=json!(obstacles);
            let mut candidates=slots.clone();
            if let Some(old)=s.berths.get(&id){candidates.insert(0,*old);}
            for goal in candidates{
                if s.rejected_berths.get(&id).is_some_and(|set|set.contains(&(goal.x.round()as i32,goal.y.round()as i32))){continue;}
                if own.iter().any(|ship|ship["fleet"]!=f["id"]&&Pt::of(ship).dist(goal)<350.)||s.berths.iter().any(|(other,p)|*other!=id&&p.dist(goal)<340.){continue;}
                // This public-map approximation can reject a safe continuation
                // of an existing wake. Let the authority check one slow normal
                // route rather than waiting forever on that approximation.
                let (points,knots)=steering_path(&chart,leader,&members,goal).map_or_else(||(vec![goal],6.),|points|(points,25.));
                s.berths.insert(id,goal);s.routes.insert(id,(goal,num(v,"tick")as u32));
                return vec![json!({"op":"route","fleet":id,"mode":"follow","speed":f64::min(knots,num(f,"maxSpeed")),"points":points.iter().map(|p|p.value()).collect::<Vec<_>>()} )];
            }
        }
        if !s.berths.is_empty(){s.rejected_berths.clear();phase(s,"blocked","接驳航路暂不可行，保留已入区舰艇并等待安全通路");return vec![];}
        s.berths.clear();s.routes.clear();s.rejected_berths.clear();
    }
    phase(s,"blocked","正在寻找可让全部舰艇安全入区的航路");vec![]
}
fn rotated(item: &Value, r: u32) -> Vec<(i32, i32)> {
    let pts: Vec<_> = rows(&item["shape"])
        .iter()
        .map(|p| {
            (
                p[0].as_i64().unwrap_or(0) as i32,
                p[1].as_i64().unwrap_or(0) as i32,
            )
        })
        .collect();
    let x = pts.iter().map(|p| p.0).max().unwrap_or(0);
    let y = pts.iter().map(|p| p.1).max().unwrap_or(0);
    pts.into_iter()
        .map(|(a, b)| match r % 4 {
            1 => (y - b, a),
            2 => (x - a, y - b),
            3 => (b, x - a),
            _ => (a, b),
        })
        .collect()
}
fn first_fit(grid: &Value, item: &Value) -> Option<(u32, u32, u32)> {
    if num(grid, "kg") + num(item, "kg") > num(grid, "max_kg") {
        return None;
    }
    let mut occupied = BTreeSet::new();
    for other in rows(&grid["items"]) {
        if let Some(p) = other["placement"].as_array() {
            if p.len() == 3 {
                for (x, y) in rotated(other, p[2].as_u64().unwrap_or(0) as u32) {
                    occupied.insert((
                        p[0].as_i64().unwrap_or(0) as i32 + x,
                        p[1].as_i64().unwrap_or(0) as i32 + y,
                    ));
                }
            }
        }
    }
    for y in 0..num(grid, "rows") as i32 {
        for x in 0..num(grid, "cols") as i32 {
            for r in 0..4 {
                if rotated(item, r).iter().all(|(a, b)| {
                    *a + x >= 0
                        && *b + y >= 0
                        && *a + x < (num(grid, "cols") as i32)
                        && *b + y < (num(grid, "rows") as i32)
                        && ((*b + y) * num(grid, "cols") as i32 + *a + x)
                            < usable_cells(grid) as i32
                        && !occupied.contains(&(*a + x, *b + y))
                }) {
                    return Some((x as u32, y as u32, r));
                }
            }
        }
    }
    None
}
fn mission_fleets(v:&Value)->Vec<&Value>{
    let ids=rows(&v["salvage"]["expedition"]["mission_fleets"]);
    rows(&v["fleets"]).iter().filter(|f|(ids.is_empty()||ids.contains(&f["id"]))&&rows(&v["ships"]).iter().any(|ship|ship["fleet"]==f["id"]&&num(ship,"hp")>0.)).collect()
}
fn group_site_risk(v:&Value,s:&AutoPilot,p:Pt,members:&[&Value])->f64{
    let center=centroid(members);let mut chart=v.clone();
    chart["ships"]=json!(alive(v).iter().filter(|ship|members.iter().any(|m|m["id"]==ship["id"])||Pt::of(ship).dist(center)<3000.).collect::<Vec<_>>());
    let mut local=s.clone();local.hp_fraction=members.iter().map(|ship|num(ship,"hp")/num(ship,"maxHp").max(1.)).fold(1.,f64::min);
    site_risk(&chart,&local,p)
}
fn escort_group(v:&Value,s:&mut AutoPilot,f:&Value,other:u32)->Vec<Value>{
    let own=alive(v);let Some(lead)=rows(&v["fleets"]).iter().find(|g|num(g,"id")as u32==other).and_then(|g|own.iter().find(|ship|ship["id"]==g["leader"]))else{return vec![];};
    let members:Vec<_>=own.iter().copied().filter(|ship|ship["fleet"]==f["id"]).collect();let center=centroid(&members);let target=Pt::of(lead);
    if center.dist(target)<1700.{if num(f,"speed")>0.{return vec![json!({"op":"speed","fleet":f["id"],"speed":0})];}return vec![];}
    let id=num(f,"id")as u32;if s.routes.get(&id).is_some_and(|(_,last)|(num(v,"tick")as u32).saturating_sub(*last)<10&&num(f,"actual")>0.05){return vec![];}
    let goal=target.add(-450.,if center.y<target.y{-700.}else{700.});
    navigate_selected(v,s,goal,25.,false,Some(id))
}
/// Each original player group receives its own visible site. Approaches run
/// in parallel; the authority's single search action is shared in turn.
fn distributed_search(v:&Value,s:&mut AutoPilot,max_risk:f64)->Option<Vec<Value>>{
    if s.version!="cas-extraction-pilot-v3"{return None;}
    let mut fleets=mission_fleets(v);if fleets.len()<2{return None;}
    let own=alive(v);let completed=rows(&v["salvage"]["cargo_grid"]["completed"]);
    // Give the nearest safe sites to fragile groups first; heavy formations
    // retain their own more distant jobs instead of leaving the last cruiser
    // alone with the last and most dangerous site.
    let strength=|f:&&Value|own.iter().filter(|ship|ship["fleet"]==f["id"]).map(|ship|num(ship,"hp")).sum::<f64>();
    fleets.sort_by(|a,b|strength(a).total_cmp(&strength(b)).then(num(a,"id").total_cmp(&num(b,"id"))));
    s.fleet_assignments.retain(|fleet,ruin|fleets.iter().any(|f|num(f,"id")as u32==*fleet)&&rows(&v["salvage"]["ruins"]).iter().any(|r|num(r,"id")as u32==*ruin));
    for (fleet,ruin)in &s.fleet_assignments{if completed.contains(&json!(ruin)){s.searched_fleets.insert(*fleet);}}
    let everyone_searched=fleets.iter().all(|f|s.searched_fleets.contains(&(num(f,"id")as u32)));
    if everyone_searched{s.fleet_assignments.retain(|_,ruin|!completed.contains(&json!(ruin)));}
    let searching=&v["salvage"]["search"];let mut actions=vec![];s.fleet_targets.clear();
    for f in fleets.iter().copied(){
        let id=num(f,"id")as u32;
        let members:Vec<_>=own.iter().copied().filter(|ship|ship["fleet"]==f["id"]).collect();
        if members.is_empty(){continue;}
        if !everyone_searched&&s.searched_fleets.contains(&id){
            let supported=fleets.iter().map(|g|num(g,"id")as u32).find(|other|s.fleet_assignments.contains_key(other)&&!s.searched_fleets.contains(other));
            if let Some(other)=supported{actions.extend(escort_group(v,s,f,other));}
            s.fleet_targets.push(json!({"fleet":id,"ruin":s.fleet_assignments.get(&id),"phase":"escort"}));continue;
        }
        if !s.fleet_assignments.contains_key(&id){
            let mut candidates:Vec<_>=rows(&v["salvage"]["ruins"]).iter().filter(|r|r["found"]==true&&r["collected"]!=true&&!completed.contains(&r["id"])&&!s.fleet_assignments.values().any(|other|*other==num(r,"id")as u32)&&!s.fleet_skipped.contains(&(id,num(r,"id")as u32))&&group_site_risk(v,s,Pt::of(r),&members)<=max_risk).collect();
            candidates.sort_by(|a,b|Pt::of(a).dist(centroid(&members)).total_cmp(&Pt::of(b).dist(centroid(&members))));
            if let Some(r)=candidates.into_iter().find(|r|path(v,Pt::of(members[0]),Pt::of(r)).is_some()){s.fleet_assignments.insert(id,num(r,"id")as u32);}
        }
        let Some(ruin)=s.fleet_assignments.get(&id).and_then(|id|rows(&v["salvage"]["ruins"]).iter().find(|r|num(r,"id")as u32==*id))else{continue;};
        let rid=num(ruin,"id")as u32;let p=Pt::of(ruin);let distance=members.iter().map(|ship|Pt::of(ship).dist(p)).fold(f64::INFINITY,f64::min);
        let active=fleets.iter().map(|g|num(g,"id")as u32).find(|other|s.fleet_assignments.contains_key(other)&&!s.searched_fleets.contains(other));
        if members.iter().map(|ship|num(ship,"hp")).sum::<f64>()<1200.&&active.is_some_and(|other|other!=id){
            actions.extend(escort_group(v,s,f,active.unwrap()));s.fleet_targets.push(json!({"fleet":id,"ruin":rid,"phase":"escort"}));continue;
        }
        let tick=num(v,"tick")as u32;
        if distance>=730.||searching["ruin"]!=rid{
            let progress=s.fleet_progress.entry(id).or_insert((rid,distance,tick));
            if progress.0!=rid||distance+80.<progress.1{*progress=(rid,distance,tick);}
            if tick.saturating_sub(progress.2)>90{s.fleet_assignments.remove(&id);s.fleet_skipped.insert((id,rid));continue;}
        }
        let close=members.iter().any(|ship|Pt::of(ship).dist(p)<730.&&num(ship,"speed")<=8.);
        if searching["ruin"]==rid{s.fleet_progress.insert(id,(rid,-num(searching,"progress")*100.,tick));}
        let state=if close{if num(f,"speed")>0.{actions.push(json!({"op":"speed","fleet":id,"speed":0}));}
            else if searching.is_null()&&actions.is_empty(){
                let attempts=s.search_attempts.entry((id,rid)).or_default();
                if *attempts>=6{s.fleet_assignments.remove(&id);s.fleet_skipped.insert((id,rid));continue;}
                *attempts+=1;actions.push(json!({"op":"search_salvage","ruin":rid}));
            }
            if searching["ruin"]==rid{"search"}else{"wait_search"}
        }else{
            let collector=members.iter().min_by(|a,b|Pt::of(a).dist(p).total_cmp(&Pt::of(b).dist(p))).unwrap();
            let from=Pt::of(collector);let(dx,dy)=unit(from,p);let goal=p.add(dx*430.,dy*430.);
            actions.extend(navigate_selected(v,s,goal,if distance<1800.{6.}else{25.},false,Some(id)));"approach"
        };
        s.fleet_targets.push(json!({"fleet":id,"ruin":rid,"phase":state}));
    }
    if s.fleet_assignments.is_empty(){None}else{phase(s,if searching.is_null(){"approach"}else{"search"},"各编队分头接近已知残骸，轮流搜索并实际装载");Some(actions)}
}
fn evade(v: &Value, s: &mut AutoPilot) -> Vec<Value> {
    let tick = num(v, "tick") as u32;
    if tick.saturating_sub(s.last_evade) < 3 {
        return vec![];
    }
    let own = alive(v);
    for warning in rows(&v["salvage"]["telegraphs"]) {
        let end = Pt::of(warning);
        let origin = Pt {
            x: num(warning, "origin_x"),
            y: num(warning, "origin_y"),
        };
        let radius = num(warning, "radius") + 100.;
        for ship in &own {
            if warning["exempt_ship_id"].is_u64() && ship["id"] == warning["exempt_ship_id"] {
                continue;
            }
            let p = Pt::of(ship);
            let capsule = warning["shape"] == "capsule";
            let d = if capsule {
                segment_distance(p, origin, end)
            } else {
                p.dist(end)
            };
            if d > radius + 180. {
                continue;
            }
            let (mut dx, mut dy) = if capsule {
                let (x, y) = unit(end, origin);
                (-y, x)
            } else {
                unit(p, end)
            };
            if dx.abs() + dy.abs() < 0.1 {
                let h = num(ship, "heading").to_radians();
                dx = libm::sin(h);
                dy = libm::cos(h);
            }
            for sign in [1., -1.] {
                let goal = p.add(dx * sign * (radius + 950.), dy * sign * (radius + 950.));
                if goal.x < 100.
                    || goal.y < 100.
                    || goal.x > num(v, "width") - 100.
                    || goal.y > num(v, "height") - 100.
                {
                    continue;
                }
                let commands =
                    navigate_selected(v, s, goal, 35., true, Some(num(ship, "fleet") as u32));
                if !commands.is_empty() {
                    s.last_evade = tick;
                    s.target_ruin = None;
                    phase(s, "evade", "离开已公布的攻击范围");
                    return commands;
                }
            }
        }
    }
    vec![]
}

pub fn decide(v: &Value, s: &mut AutoPilot) -> Vec<Value> {
    if !s.enabled {
        return vec![];
    }
    s.last_decision_tick = num(v, "tick") as u32;
    if !v["result"].is_null() {
        s.enabled = false;
        phase(
            s,
            "complete",
            if v["salvage"]["extracted"] == true {
                "已安全撤离"
            } else {
                "本次行动已结束"
            },
        );
        return vec![];
    }
    if v["salvage"]["mission"]["kind"] != "salvage"
        || v["salvage"]["adventure"]["version"] != "cas-adventure-v2"
    {
        s.enabled = false;
        phase(s, "off", "此模式不支持自动搜打撤");
        return vec![];
    }
    let own = alive(v);
    if own.is_empty() {
        return vec![];
    }
    let center = centroid(&own);
    let grid = &v["salvage"]["cargo_grid"];
    s.hp_fraction = own
        .iter()
        .map(|ship| num(ship, "hp") / num(ship, "maxHp").max(1.))
        .fold(1., f64::min);
    // Sunk own hulls disappear from the live tactical list but remain in this
    // seat's expedition receipt. A loss must not look like a fresh healthy fleet.
    if rows(&v["salvage"]["ships"])
        .iter()
        .any(|ship| ship["protected"] == true)
    {
        s.hp_fraction = 0.;
    }
    s.ammo_percent = rows(&v["salvage"]["ships"])
        .iter()
        .filter(|ship| ship["protected"] != true)
        .map(|ship| num(ship, "ammo"))
        .fold(100., f64::min);
    s.torpedoes_available = own
        .iter()
        .map(|ship| {
            num(&ship["expedition_munitions"], "torpedo_loaded") as u32
                + num(&ship["expedition_munitions"], "torpedo_reserve") as u32
        })
        .sum();
    s.stowed_value = rows(&grid["items"])
        .iter()
        .filter(|item| !item["placement"].is_null())
        .map(|i| num(i, "value") as u32)
        .sum();
    s.stowed_kg = num(grid, "kg") as u32;
    let occupied = rows(&grid["items"])
        .iter()
        .filter(|item| !item["placement"].is_null())
        .map(|item| rows(&item["shape"]).len())
        .sum::<usize>() as f64;
    let load = (num(grid, "kg") / num(grid, "max_kg").max(1.))
        .max(occupied / (usable_cells(grid) as f64).max(1.));
    let (hp, ammo, target, full, max_threat) = match s.policy.as_str() {
        "cautious" => (0.70, 28., 1800, 0.45, 0.25),
        "bold" => (0.32, 10., 9000, 0.88, 1.5),
        _ => (0.50, 18., 4200, 0.70, 0.7),
    };
    s.boss_assessment = "未发现可评估目标".into();
    for contact in rows(&v["contacts"]) {
        if contact["boss"] == true {
            s.boss_assessment = if s.policy == "bold"
                && s.hp_fraction > 0.9
                && s.ammo_percent > 75.
                && s.torpedoes_available >= 8
                && own.iter().map(|ship| num(ship, "hp")).sum::<f64>()
                    > num(contact, "max_health") * 1.5
            {
                "兵力有余，可保持远距火力"
            } else {
                "收益不足以承担风险，绕行"
            }
            .into();
        }
    }
    // A committed withdrawal must not oscillate between a warning-avoidance
    // turn and the exit route every second. Low supplies/HP use the same
    // retreat priority in the new pilot. Older logs keep their exact order.
    let exiting=task_pilot(s) && (s.retreat||s.hp_fraction<hp||s.ammo_percent<=ammo);
    let evasion = if exiting {vec![]} else {evade(v, s)};
    if v["fuel"].is_object()&&(v["fuel"]["state"]=="low"||v["fuel"]["state"]=="empty"||num(&v["fuel"],"remaining")<num(&v["fuel"],"return_required")){return withdraw(v,s,"油料接近返航底线，停止搜索并回港");}
    if !evasion.is_empty() {
        return evasion;
    }
    if s.retreat {
        return withdraw(v, s, "带回已装载物资，前往接驳点");
    }
    if s.hp_fraction < hp {
        return withdraw(v, s, "舰体损伤偏高，保留战果返航");
    }
    if s.ammo_percent <= ammo {
        return withdraw(v, s, "弹药余量不足，避免继续接敌");
    }
    if num(v, "limit") - num(v, "tick") < 150. {
        return withdraw(v, s, "海域关闭临近，提前集结撤离");
    }
    let task_pending=task_pilot(s) && s.task.as_deref().is_some_and(|id|rows(&v["salvage"]["expedition"]["tasks"]).iter().any(|t|t["id"].as_str()==Some(id)&&["accepted","working"].contains(&t["status"].as_str().unwrap_or(""))));
    let grouped_ready=mission_fleets(v).len()<2||mission_fleets(v).iter().all(|f|s.searched_fleets.contains(&(num(f,"id")as u32)));
    if s.stowed_value >= target && !task_pending && (s.version!="cas-extraction-pilot-v3"||rows(&grid["completed"]).len()>=2&&grouped_ready) || load >= full {
        return withdraw(v, s, "本次装载目标已达成，收队返航");
    }
    if site_risk(v,s,center) > max_threat && s.stowed_value > 0 {
        return withdraw(v, s, "可见敌对威胁接近，先保住物资");
    }
    // Maintain only explicitly granted combat permissions. Navigation is owned
    // by this pilot, not the pre-existing tactical movement controller.
    let mut combat = vec![];
    for fleet in rows(&v["fleets"]) {
        let ai = &fleet["ai"];
        let autonomous_torpedoes=task_pilot(s) && s.torpedoes_available>0;
        if ai["move"] == true || ai["gun"] != true || autonomous_torpedoes && ai["torpedo"]!=true {
            combat.push(json!({"op":"ai","fleet":fleet["id"],"profile":ai["profile"].as_str().unwrap_or("coord"),"mode":"auto","move":false,"gun":true,"torpedo":autonomous_torpedoes||ai["torpedo"].as_bool().unwrap_or(false)}));
        }
    }
    if !combat.is_empty() {
        return combat;
    }
    if let Some(actions)=compact_fleets(v,s){return actions;}
    let mut waiting: Vec<_> = rows(&grid["items"])
        .iter()
        .filter(|i| i["placement"].is_null())
        .collect();
    waiting.sort_by(|a, b| {
        (num(b, "value") / rows(&b["shape"]).len().max(1) as f64)
            .total_cmp(&(num(a, "value") / rows(&a["shape"]).len().max(1) as f64))
            .then(a["id"].as_str().cmp(&b["id"].as_str()))
    });
    for item in waiting {
        let Some(ruin) = rows(&v["salvage"]["ruins"])
            .iter()
            .find(|r| r["id"] == item["ruin"])
        else {
            continue;
        };
        if !own
            .iter()
            .any(|ship| Pt::of(ship).dist(Pt::of(ruin)) < 740. && num(ship, "speed") <= 8.)
        {
            continue;
        }
        if let Some((x, y, r)) = first_fit(grid, item) {
            phase(s, "stow", "将已发现的物资实际装入货舱");
            return vec![json!({"op":"cargo_place","item":item["id"],"x":x,"y":y,"rotation":r})];
        }
        let layout = rows(&grid["items"])
            .iter()
            .filter(|i| !i["placement"].is_null())
            .map(|i| format!("{}:{}", i["id"], i["placement"]))
            .collect::<Vec<_>>()
            .join(";");
        if !layout.is_empty() && s.sorted.insert(layout) {
            phase(s, "stow", "整理现有物资，检查能否腾出完整格位");
            return vec![json!({"op":"cargo_sort"})];
        }
        if s.stowed_value > 0 {
            return withdraw(v, s, "剩余空间放不下新物资，先带回现有装载");
        }
        if s.version=="cas-extraction-pilot-v3"{
            phase(s,"stow","已确认该物资无法装入，放弃后继续搜索");
            return vec![json!({"op":"cargo_drop","item":item["id"]})];
        }
    }
    if let Some(actions)=distributed_search(v,s,max_threat){return actions;}
    if !v["salvage"]["search"].is_null() {
        phase(s, "search", "低速搜索中，留意可见敌对实体");
        return vec![];
    }
    // New voyages explicitly opt into a task-first pilot. Old command logs
    // without the version key retain their original loot-first decisions.
    if s.version=="cas-extraction-pilot-v3"&&!task_pending{s.task=None;}
    if task_pilot(s) && s.hp_fraction>0.70 && s.ammo_percent>35. && load<0.60 {
        let task_risk=match s.policy.as_str(){"cautious"=>0.20,"bold"=>0.65,_=>0.30};
        let mut tasks:Vec<_>=rows(&v["salvage"]["expedition"]["tasks"]).iter().filter(|t|{
            let status=t["status"].as_str().unwrap_or("");let kind=t["kind"].as_str().unwrap_or("");
            ["relay","survey","rescue","beacon","cache"].contains(&kind) && ["offered","accepted","working"].contains(&status)
            && site_risk(v,s,Pt::of(t))<task_risk
            && !s.skipped_tasks.contains(t["id"].as_str().unwrap_or(""))
            && s.task.as_deref().is_none_or(|id|t["id"].as_str()==Some(id))
        }).collect();
        tasks.sort_by(|a,b|Pt::of(a).dist(center).total_cmp(&Pt::of(b).dist(center)));
        for task in tasks {
            let p=Pt::of(task);if path(v,center,p).is_none(){continue;}
            if s.version=="cas-extraction-pilot-v3"&&stalled(s,format!("task:{}",task["id"]),own.iter().map(|ship|Pt::of(ship).dist(p)).fold(f64::INFINITY,f64::min),num(v,"tick")as u32){
                s.skipped_tasks.insert(task["id"].as_str().unwrap_or("").into());s.task=None;
                if task["status"]!="offered"{return vec![json!({"op":"expedition_task","task":task["id"],"action":"abandon"})];}continue;
            }
            s.task=task["id"].as_str().map(str::to_owned);phase(s,"task","接取可承受任务，完成后搜索并携带物资撤离");
            if task["status"]=="offered" {return vec![json!({"op":"expedition_task","task":task["id"],"action":"accept"})];}
            // A healthy fleet can finish a nearby task before opening its first
            // ruin. Only secure a nearby fallback before a genuinely long trip;
            // otherwise every task is starved by the first loot/combat cycle.
            let nearby_fallback = rows(&v["salvage"]["ruins"]).iter().any(|r|
                r["found"]==true && r["collected"]!=true && Pt::of(r).dist(center)<1800.);
            if s.stowed_value==0 && p.dist(center)>4500. && nearby_fallback {break;}
            if task["status"]=="working"{return vec![];}
            if let Some(ship)=own.iter().find(|ship|Pt::of(ship).dist(p)<600. && num(ship,"speed")<=8.){
                if s.version=="cas-extraction-pilot-v3"{if let Some(f)=rows(&v["fleets"]).iter().find(|f|f["id"]==ship["fleet"]&&num(f,"speed")>0.){return vec![json!({"op":"speed","fleet":f["id"],"speed":0})];}}
                return vec![json!({"op":"expedition_interact","task":task["id"]})];
            }
            return navigate(v,s,p,if p.dist(center)<1800.{6.}else{25.},false);
        }
    }
    let completed = rows(&grid["completed"]);
    let mut candidates: Vec<_> = rows(&v["salvage"]["ruins"])
        .iter()
        .filter(|r| {
            r["found"] == true
                && r["collected"] != true
                && !completed.contains(&r["id"])
                && !s.skipped.contains(&(num(r, "id") as u32))
        })
        .collect();
    candidates.sort_by(|a, b| {
        let score = |r: &Value| Pt::of(r).dist(center) + threat(v, Pt::of(r)) * 5000.;
        score(a)
            .total_cmp(&score(b))
            .then(num(a, "id").total_cmp(&num(b, "id")))
    });
    for ruin in candidates {
        let p = Pt::of(ruin);
        if s.version=="cas-extraction-pilot-v3"&&stalled(s,format!("ruin:{}",ruin["id"]),own.iter().map(|ship|Pt::of(ship).dist(p)).fold(f64::INFINITY,f64::min),num(v,"tick")as u32){s.skipped.insert(num(ruin,"id")as u32);continue;}
        if site_risk(v,s,p) > max_threat {
            continue;
        }
        if path(v, center, p).is_none() {
            continue;
        }
        s.target_ruin = Some(num(ruin, "id") as u32);
        if own
            .iter()
            .any(|ship| Pt::of(ship).dist(p) < 730. && num(ship, "speed") <= 8.)
        {
            phase(s, "search", "已接近残骸，开始实际搜索");
            if s.version=="cas-extraction-pilot-v3"{if let Some(f)=rows(&v["fleets"]).iter().find(|f|num(f,"speed")>0.&&own.iter().any(|ship|ship["fleet"]==f["id"]&&Pt::of(ship).dist(p)<730.&&num(ship,"speed")<=8.)){return vec![json!({"op":"speed","fleet":f["id"],"speed":0})];}}
            return vec![json!({"op":"search_salvage","ruin":ruin["id"]})];
        }
        let collector = own
            .iter()
            .copied()
            .min_by(|a, b| Pt::of(a).dist(p).total_cmp(&Pt::of(b).dist(p)))
            .unwrap();
        let from = Pt::of(collector);
        let (dx, dy) = unit(from, p);
        let goal = p.add(dx * 430., dy * 430.);
        let knots = if p.dist(from) < 1800. { 6. } else { 25. };
        phase(s, "approach", "前往已发现且可达的残骸");
        let commands = navigate_selected(
            v,
            s,
            goal,
            knots,
            false,
            Some(num(collector, "fleet") as u32),
        );
        if !commands.is_empty() {
            return commands;
        }
        return vec![];
    }
    // Optional tasks are only accepted with spare capacity and low public risk.
    if s.policy == "bold" && s.hp_fraction > 0.85 && s.ammo_percent > 65. && load < 0.45 {
        for task in rows(&v["salvage"]["expedition"]["tasks"]) {
            let kind = task["kind"].as_str().unwrap_or("");
            let status = task["status"].as_str().unwrap_or("");
            if !["relay", "survey", "rescue", "beacon", "cache"].contains(&kind)
                || !["offered", "accepted", "working"].contains(&status)
                || threat(v, Pt::of(task)) > 0.15
            {
                continue;
            }
            let p = Pt::of(task);
            if path(v, center, p).is_none() {
                continue;
            }
            s.task = task["id"].as_str().map(str::to_owned);
            phase(s, "task", "余量充足，处理低风险可选任务");
            if status == "offered" {
                return vec![json!({"op":"expedition_task","task":task["id"],"action":"accept"})];
            }
            if status == "working" {
                return vec![];
            }
            if own
                .iter()
                .any(|ship| Pt::of(ship).dist(p) < 600. && num(ship, "speed") <= 8.)
            {
                return vec![json!({"op":"expedition_interact","task":task["id"]})];
            }
            return navigate(
                v,
                s,
                p,
                if p.dist(center) < 1800. { 6. } else { 25. },
                false,
            );
        }
    }
    withdraw(v, s, "已知残骸不值得冒险，返回安全接驳区")
}

#[cfg(test)]
mod tests {
    use super::*;
    fn view() -> Value {
        json!({"tick":1,"limit":1800,"width":24000,"height":14000,"result":null,"islands":[],"contacts":[],"ships":[{"id":1,"fleet":1,"hp":100,"maxHp":100,"x":2200,"y":2200,"speed":0}],"fleets":[{"id":1,"leader":1,"maxSpeed":35,"actual":0,"ai":{"profile":"coord","move":false,"gun":true}}],"salvage":{"mission":{"kind":"salvage"},"adventure":{"version":"cas-adventure-v2"},"ships":[{"hp":100,"ammo":100}],"exits":[{"x":2200,"y":2200,"radius":1000}],"ruins":[{"id":1,"x":2700,"y":2200,"found":true,"collected":false}],"search":null,"extracting":null,"telegraphs":[],"cargo_grid":{"cols":8,"rows":4,"max_kg":1000,"kg":0,"items":[],"completed":[]}}})
    }
    fn enabled() -> AutoPilot {
        let mut s = AutoPilot::default();
        command(&mut s, &json!({"enabled":true,"policy":"balanced"})).unwrap();
        s
    }
    #[test]
    fn authorization_and_manual_takeover() {
        let v = view();
        let mut s = AutoPilot::default();
        assert!(decide(&v, &mut s).is_empty());
        command(&mut s, &json!({"enabled":true})).unwrap();
        manual_override(&mut s, &json!({"op":"route"}), 10);
        assert!(!s.enabled);
        assert!(decide(&v, &mut s).is_empty());
        assert!(command(&mut s, &json!({"enabled":true,"policy":"cheat"})).is_err());
        assert!(!s.enabled);
    }
    #[test]
    fn versioned_balanced_pilot_accepts_tasks_before_loot_without_changing_old_logs(){
        let mut v=view();v["salvage"]["expedition"]=json!({"tasks":[{"id":"task-1","kind":"rescue","status":"offered","x":2400,"y":2200}]});
        assert_eq!(decide(&v,&mut enabled())[0]["op"],"search_salvage");
        let mut next=enabled();command(&mut next,&json!({"enabled":true,"policy":"balanced","version":"cas-extraction-pilot-v2"})).unwrap();
        assert_eq!(decide(&v,&mut next)[0],json!({"op":"expedition_task","task":"task-1","action":"accept"}));
        let before=serde_json::to_value(&next).unwrap();assert!(command(&mut next,&json!({"enabled":true,"version":"unknown"})).is_err());assert_eq!(serde_json::to_value(&next).unwrap(),before);
        v["salvage"]["ruins"]=json!([]);v["salvage"]["expedition"]["tasks"][0]["status"]=json!("accepted");assert_eq!(decide(&v,&mut next)[0]["op"],"expedition_interact");
    }
    #[test]
    fn versioned_near_task_is_not_starved_by_unopened_loot(){
        let mut v=view();
        v["salvage"]["expedition"]=json!({"tasks":[{"id":"task-1","kind":"rescue","status":"accepted","x":2400,"y":2200}]});
        let mut next=enabled();command(&mut next,&json!({"enabled":true,"version":"cas-extraction-pilot-v2"})).unwrap();
        assert_eq!(decide(&v,&mut next)[0]["op"],"expedition_interact");
        v["salvage"]["expedition"]["tasks"][0]["x"]=json!(10000);
        assert_eq!(decide(&v,&mut next)[0]["op"],"search_salvage");
        let mut old=enabled();
        v["salvage"]["expedition"]["tasks"][0]["x"]=json!(2400);
        assert_eq!(decide(&v,&mut old)[0]["op"],"search_salvage");
    }
    #[test]
    fn health_and_ammunition_force_real_exit() {
        for key in ["hp", "ammo"] {
            let mut v = view();
            if key == "hp" {
                v["ships"][0]["hp"] = json!(20);
            } else {
                v["salvage"]["ships"][0]["ammo"] = json!(0);
            }
            let mut s = enabled();
            assert_eq!(decide(&v, &mut s)[0]["op"], "salvage_extract");
        }
    }
    #[test]
    fn discovered_items_pack_without_reward_or_truth_access() {
        let mut v = view();
        let mut s = enabled();
        assert_eq!(decide(&v, &mut s)[0]["op"], "search_salvage");
        v["salvage"]["cargo_grid"]["items"] = json!([{"id":"physical-1","ruin":1,"shape":[[0,0],[1,0]],"kg":50,"value":100,"placement":null}]);
        let q = decide(&v, &mut s);
        assert_eq!(q[0]["op"], "cargo_place");
        assert_eq!(q[0]["item"], "physical-1");
        assert!(v["salvage"]["cargo_grid"]["items"][0]["placement"].is_null());
    }
    #[test]
    fn hidden_contacts_and_unknown_ruins_cannot_be_used() {
        let mut v = view();
        v["salvage"]["ruins"] = json!([]);
        let mut s = enabled();
        assert_eq!(decide(&v, &mut s)[0]["op"], "salvage_extract");
        assert!(s.target_ruin.is_none());
    }
    #[test]
    fn cargo_full_and_visible_boss_do_not_trigger_suicidal_search() {
        let mut v = view();
        v["salvage"]["cargo_grid"]["kg"] = json!(900);
        let mut s = enabled();
        assert_eq!(decide(&v, &mut s)[0]["op"], "salvage_extract");
        let mut v = view();
        v["contacts"] = json!([{"id":"C1","x":2800,"y":2200,"boss":true,"health":1500,"max_health":1500,"attack":{"range":5000}}]);
        let mut s = enabled();
        assert_eq!(decide(&v, &mut s)[0]["op"], "salvage_extract");
        assert!(s.boss_assessment.contains("绕行"));
    }
    #[test]
    fn public_map_path_routes_around_actual_polygons() {
        let mut v = view();
        v["islands"] = json!([[{"x":4000,"y":1500},{"x":5500,"y":1500},{"x":5500,"y":3000},{"x":4000,"y":3000}]]);
        let points = path(&v, Pt { x: 2200., y: 2200. }, Pt { x: 7000., y: 2200. }).unwrap();
        assert!(points.len() > 1);
        let mut from = Pt { x: 2200., y: 2200. };
        for p in points {
            assert!(clear(&polygons(&v), from, p, 200.));
            from = p;
        }
    }
    #[test]
    fn chapter_and_legacy_modes_never_autoplay() {
        for mode in ["chapter", "resources", "ladder"] {
            let mut v = view();
            v["salvage"]["mission"]["kind"] = json!(mode);
            let mut s = enabled();
            assert!(decide(&v, &mut s).is_empty());
            assert!(!s.enabled);
        }
        let mut v = view();
        v["salvage"]["adventure"]["version"] = json!("cas-adventure-v1");
        assert!(decide(&v, &mut enabled()).is_empty());
    }
    #[test]
    fn serialized_ruin_position_and_far_naval_range_are_usable() {
        let mut v = view();
        v["salvage"]["ruins"][0] =
            json!({"id":1,"p":{"x":2700,"y":2200},"found":true,"collected":false});
        v["contacts"] = json!([{"id":"C7","entityKind":"naval","x":6200,"y":2200,"health":160,"attack":{"range":30000}}]);
        assert_eq!(decide(&v, &mut enabled())[0]["op"], "search_salvage");
    }
    #[test]
    fn unpublished_authority_fields_cannot_change_decisions() {
        let v = view();
        let mut poisoned = v.clone();
        poisoned["authority"] = json!({"ships":[{"x":2200,"y":2200,"boss":true}]});
        poisoned["salvage"]["expedition"] = json!({"boss":{"status":"dormant","x":2200,"y":2200,"source_contact":null},"hidden_ruins":[{"id":999,"value":999999}]});
        let mut a = enabled();
        let mut b = enabled();
        assert_eq!(decide(&v, &mut a), decide(&poisoned, &mut b));
        assert_eq!(
            serde_json::to_value(a).unwrap(),
            serde_json::to_value(b).unwrap()
        );
    }
    #[test]
    fn optional_task_uses_accept_and_interact_without_inventing_reward() {
        let mut v = view();
        v["salvage"]["ruins"] = json!([]);
        v["salvage"]["expedition"] =
            json!({"tasks":[{"id":"task-1","kind":"rescue","status":"offered","x":2400,"y":2200}]});
        let mut s = enabled();
        s.policy = "bold".into();
        assert_eq!(
            decide(&v, &mut s)[0],
            json!({"op":"expedition_task","task":"task-1","action":"accept"})
        );
        v["salvage"]["expedition"]["tasks"][0]["status"] = json!("accepted");
        assert_eq!(decide(&v, &mut s)[0]["op"], "expedition_interact");
        v["salvage"]["expedition"]["tasks"][0]["status"] = json!("working");
        assert!(decide(&v, &mut s).is_empty());
        assert!(v["salvage"]["cargo_grid"]["items"]
            .as_array()
            .unwrap()
            .is_empty());
    }
    #[test]
    fn exact_center_warning_has_escape_direction_and_respects_exemption() {
        let mut v = view();
        v["tick"] = json!(10);
        v["ships"][0]["heading"] = json!(90);
        v["salvage"]["telegraphs"] =
            json!([{"x":2200,"y":2200,"radius":300,"shape":"circle","exempt_ship_id":null}]);
        assert_eq!(decide(&v, &mut enabled())[0]["op"], "route");
        v["salvage"]["telegraphs"][0]["exempt_ship_id"] = json!(1);
        assert_eq!(decide(&v, &mut enabled())[0]["op"], "search_salvage");
    }
    #[test]
    fn grid_cell_occupancy_counts_even_when_the_material_is_light() {
        let mut v = view();
        let shape: Vec<_> = (0..4)
            .flat_map(|y| (0..8).map(move |x| json!([x, y])))
            .collect();
        v["salvage"]["cargo_grid"]["items"] =
            json!([{"id":"actual-light-cargo","shape":shape,"placement":[0,0,0],"kg":1,"value":1}]);
        assert_eq!(decide(&v, &mut enabled())[0]["op"], "salvage_extract");
    }
    #[test]
    fn an_about_turn_plans_a_wide_valid_curve_from_public_navigation() {
        let v = view();
        let ship = json!({"x":6000,"y":6000,"heading":90,"navigation":{"turn_advance_m":460}});
        let target = Pt { x: 4800., y: 6000. };
        let planned = steering_path(&v, &ship, &[&ship], target).unwrap();
        assert!(planned.len() > 1);
        assert!(curve_clear(&v, Pt::of(&ship), 90., &planned, 460.));
    }
    #[test]
    fn reserved_and_padding_cells_are_never_free_cargo_space() {
        let shape: Vec<_> = (0..10).map(|i| json!([i % 8, i / 8])).collect();
        let grid = json!({"cols":8,"rows":2,"usable_cells":10,"max_kg":1000,"kg":10,"items":[{"shape":shape,"placement":[0,0,0]}]});
        let actual = json!({"shape":[[0,0]],"kg":1});
        assert!(first_fit(&grid, &actual).is_none());
        let mut legacy = grid.clone();
        legacy.as_object_mut().unwrap().remove("usable_cells");
        assert_eq!(first_fit(&legacy, &actual), Some((2, 1, 0)));
    }
    #[test]
    fn a_lost_own_hull_cannot_be_ignored_when_survivors_are_healthy() {
        let mut v = view();
        v["salvage"]["ships"] =
            json!([{"hp":100,"ammo":100,"protected":false},{"hp":0,"ammo":100,"protected":true}]);
        let mut s = enabled();
        assert_eq!(decide(&v, &mut s)[0]["op"], "salvage_extract");
        assert_eq!(s.hp_fraction, 0.);
    }
    fn current()->AutoPilot{let mut s=enabled();command(&mut s,&json!({"enabled":true,"version":"cas-extraction-pilot-v3"})).unwrap();s}
    #[test]
    fn cargo_cooperation_keeps_v3_authorized_but_tactical_orders_take_control(){
        for op in ["cargo_place","cargo_drop","cargo_sort"]{
            let mut old=enabled();command(&mut old,&json!({"enabled":true,"version":"cas-extraction-pilot-v2"})).unwrap();manual_override(&mut old,&json!({"op":op}),397);assert!(!old.enabled);
            let mut next=current();manual_override(&mut next,&json!({"op":op}),397);assert!(next.enabled);
        }
        for op in ["route","speed","fire","extraction_autopilot"]{
            let mut next=current();manual_override(&mut next,&json!({"op":op}),400);assert_eq!(next.enabled,op=="extraction_autopilot");
        }
    }
    #[test]
    fn impossible_unstowed_cargo_is_abandoned_without_restarting_the_ruin(){
        let mut v=view();v["salvage"]["cargo_grid"]["max_kg"]=json!(20);
        v["salvage"]["cargo_grid"]["items"]=json!([{"id":"heavy","ruin":1,"shape":[[0,0]],"kg":100,"value":2000,"placement":null}]);
        assert_eq!(decide(&v,&mut current()),vec![json!({"op":"cargo_drop","item":"heavy"})]);
        // Historical pilot decisions are frozen, including its old fallback.
        assert_eq!(decide(&v,&mut enabled())[0]["op"],"search_salvage");
    }
    fn ingress_view()->Value{
        let mut v=view();v["ships"]=json!([
            {"id":1,"fleet":1,"hp":100,"maxHp":100,"x":3520,"y":2200,"speed":0,"heading":90,"hullLengthM":75,"navigation":{"turn_advance_m":365.76}},
            {"id":2,"fleet":2,"hp":100,"maxHp":100,"x":2520,"y":2200,"speed":0,"heading":90,"hullLengthM":75,"navigation":{"turn_advance_m":365.76}}
        ]);
        v["fleets"]=json!([
            {"id":1,"leader":1,"members":[1],"speed":0,"actual":0,"maxSpeed":28,"paths":[],"ai":{"move":false,"gun":true}},
            {"id":2,"leader":2,"members":[2],"speed":0,"actual":0,"maxSpeed":33,"paths":[],"ai":{"move":false,"gun":true}}
        ]);
        v["salvage"]["exits"]=json!([{"shape":"rectangle","x":3950,"y":2200,"bounds":{"min_x":2700,"max_x":4600,"min_y":1600,"max_y":2800}}]);v
    }
    #[test]
    fn shared_exit_is_one_actual_ingress_route_at_a_time(){
        let v=ingress_view();let mut s=current();let q=withdraw(&v,&mut s,"return");assert_eq!(q.len(),1);assert_eq!(q[0]["op"],"route");assert_eq!(q[0]["fleet"],1);assert_eq!(q[0]["speed"].as_f64(),Some(25.));
        let goal=Pt::of(q[0]["points"].as_array().unwrap().last().unwrap());assert!(Pt::of(&v["ships"][1]).dist(goal)>350.);
    }
    #[test]
    fn authority_rejected_berth_is_not_retried_forever(){
        let v=ingress_view();let mut s=current();let first=withdraw(&v,&mut s,"return");feedback(&mut s,&first[0],Err("航路过近".into()));
        let second=withdraw(&v,&mut s,"return");assert_eq!(second[0]["op"],"route");assert_ne!(first[0]["points"],second[0]["points"]);
    }
    #[test]
    fn ingress_with_nonempty_paths_still_has_a_progress_deadline(){
        let mut v=ingress_view();let mut s=current();withdraw(&v,&mut s,"return");
        v["fleets"][0]["actual"]=json!(6);v["fleets"][0]["speed"]=json!(6);v["fleets"][0]["paths"]=json!([{"points":[{"x":3520,"y":2200},{"x":4350,"y":1850}]}]);
        assert!(withdraw(&v,&mut s,"return").is_empty());v["tick"]=json!(93);
        assert_eq!(withdraw(&v,&mut s,"return"),vec![json!({"op":"speed","fleet":1,"speed":0})]);
    }
    #[test]
    fn accepted_ingress_collision_hold_does_not_restart_the_curve_every_tick(){
        let mut v=ingress_view();let mut s=current();withdraw(&v,&mut s,"return");
        v["fleets"][0]["actual"]=json!(0);v["fleets"][0]["speed"]=json!(25);v["fleets"][0]["paths"]=json!([{"points":[{"x":3520,"y":2200},{"x":4350,"y":1850}]}]);
        for tick in [1,2,3,4,30,90]{v["tick"]=json!(tick);assert!(withdraw(&v,&mut s,"return").is_empty());}
        v["tick"]=json!(93);assert_eq!(withdraw(&v,&mut s,"return"),vec![json!({"op":"speed","fleet":1,"speed":0})]);
        assert!(!s.berths.contains_key(&1));
    }
    #[test]
    fn authority_cleared_ingress_uses_a_bounded_retry_delay(){
        let mut v=ingress_view();let mut s=current();withdraw(&v,&mut s,"return");
        v["tick"]=json!(1);v["fleets"][0]["speed"]=json!(25);v["fleets"][0]["notice"]=json!("因航行危险停止；请重新下达航路。");
        assert_eq!(withdraw(&v,&mut s,"return"),vec![json!({"op":"speed","fleet":1,"speed":0})]);
        assert_eq!(s.phase,"blocked");v["fleets"][0]["speed"]=json!(0);
        v["tick"]=json!(2);assert!(withdraw(&v,&mut s,"return").is_empty());
        v["tick"]=json!(16);assert_eq!(withdraw(&v,&mut s,"return")[0]["op"],"route");
    }
    #[test]
    fn withdrawing_fleet_finishes_an_accepted_turn_before_berthing(){
        let mut v=ingress_view();let mut s=current();s.routes.insert(1,(Pt{x:6000.,y:6000.},0));
        v["fleets"][0]["actual"]=json!(6);v["fleets"][0]["speed"]=json!(6);v["fleets"][0]["paths"]=json!([{"points":[{"x":3520,"y":2200},{"x":4000,"y":2400}]}]);
        assert!(withdraw(&v,&mut s,"return").is_empty());assert!(!s.berths.contains_key(&1));
        v["tick"]=json!(93);assert_eq!(withdraw(&v,&mut s,"return"),vec![json!({"op":"speed","fleet":1,"speed":0})]);
    }
    #[test]
    fn optional_task_without_approach_progress_is_released(){
        let mut v=view();v["salvage"]["expedition"]=json!({"tasks":[{"id":"task-1","kind":"relay","status":"accepted","x":10000,"y":2200}]});
        let mut s=current();assert_eq!(decide(&v,&mut s)[0]["op"],"search_salvage");v["tick"]=json!(93);
        assert_eq!(decide(&v,&mut s),vec![json!({"op":"expedition_task","task":"task-1","action":"abandon"})]);
    }
}
