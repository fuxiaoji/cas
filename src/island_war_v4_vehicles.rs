//! Original v3 independent equipment and physical passenger transfers.
use super::*;
pub(super) struct Spec {
    pub kind: &'static str,
    pub class: &'static str,
    pub armor_class: &'static str,
    pub hp: f64,
    pub armor: f64,
    pub speed: f64,
    pub radius: f64,
    pub weapon: &'static str,
}
pub(super) fn spec(id: &str) -> Option<Spec> {
    let (kind, class, armor_class, hp, armor, speed, radius, weapon) = match id {
        "MCP-022" => (
            "tank",
            "armor",
            "heavy_armor",
            900.,
            0.32,
            45.,
            3.,
            "tank_gun",
        ),
        "MCP-103" => (
            "amphibious_vehicle",
            "amphibious",
            "light_armor",
            520.,
            0.52,
            72.,
            3.,
            "autocannon",
        ),
        "MCP-304" => ("amphibious_wheeled_ifv","amphibious","light_armor",480.,0.58,105.,3.,"autocannon"),
        "MCP-305" => ("amphibious_tracked_gun","amphibious","light_armor",680.,0.43,76.,3.2,"tank_gun"),
        "MCP-087" => (
            "self_propelled_gun",
            "armor",
            "light_armor",
            460.,
            0.55,
            48.,
            3.,
            "howitzer",
        ),
        "MCP-027" => (
            "attack_helicopter",
            "air",
            "helicopter",
            260.,
            0.95,
            260.,
            6.,
            "helicopter_cannon",
        ),
        "MCP-006" => (
            "attack_helicopter",
            "air",
            "helicopter",
            180.,
            1.2,
            310.,
            6.,
            "helicopter_cannon",
        ),
        _ => return None,
    };
    Some(Spec {
        kind,
        class,
        armor_class,
        hp,
        armor,
        speed,
        radius,
        weapon,
    })
}
pub(super) fn water_speed(id:&str)->f64 {match id{"MCP-304"=>40.,"MCP-305"=>24.,_=>32.}}
fn persistent(id: &str) -> bool {
    matches!(id, "MCP-103" | "MCP-304" | "MCP-305" | "MCP-027" | "MCP-006")
}
fn distance_to_segment(p: P, a: P, b: P) -> f64 {
    let d = b - a;
    let l = d.x * d.x + d.y * d.y;
    let t = if l > 1e-9 {
        ((p - a).x * d.x + (p - a).y * d.y) / l
    } else {
        0.
    };
    p.dist(a + d * t.clamp(0., 1.))
}
impl Battle {
    fn vehicle_in_water(&self, p: P) -> bool {
        if !inside(&self.base.base.core.ground.polygon, p) {
            return true;
        }
        let regions = &self.base.terrain.regions;
        regions.iter().any(|r| r.kind == "river" && inside(&r.polygon, p))
            && !regions.iter().any(|r| matches!(r.kind, "ford" | "road") && inside(&r.polygon, p))
    }
    pub(super) fn precise_route(&self, a: P, b: P, class: &str, sea: bool) -> E<Vec<P>> {
        if !self.base.surface_disc(b, class, sea) {
            return Err("该兵种不能通过目标地形".into());
        }
        if class == "air" || self.base.surface_step(a, b, class, sea) {
            return Ok(vec![b]);
        }
        // Reuse the registered bridge endpoints, then validate every segment
        // with real disc stepping. Narrow bridges need no wider fake ford.
        if let Ok(route)=self.base.surface_path(a,b,class,sea){
            let mut from=a;let valid=route.iter().all(|to|{let ok=self.base.surface_step(from,*to,class,sea);from=*to;ok});
            if valid{return Ok(route)}
        }
        // Weighted deterministic grid search is per company/order, never per body/frame.
        let g = &self.base.base.geometry;
        let step = 80.;
        let o = P {
            x: if sea {
                (g.center.x - g.half_width).min(a.x).min(b.x) - 160.
            } else {
                g.center.x - g.half_width - 80.
            },
            y: if sea {
                (g.center.y - g.half_height).min(a.y).min(b.y) - 160.
            } else {
                g.center.y - g.half_height - 80.
            },
        };
        let width = if sea {
            (((g.center.x + g.half_width).max(a.x).max(b.x) + 160. - o.x) / step).ceil() as i32
        } else {
            ((g.half_width * 2. + 160.) / step).ceil() as i32
        };
        let height = if sea {
            (((g.center.y + g.half_height).max(a.y).max(b.y) + 160. - o.y) / step).ceil() as i32
        } else {
            ((g.half_height * 2. + 160.) / step).ceil() as i32
        };
        let cell = |p: P| {
            (
                ((p.x - o.x) / step).round() as i32,
                ((p.y - o.y) / step).round() as i32,
            )
        };
        let start = cell(a);
        let point = |(x, y): (i32, i32)| {if (x,y)==start{return a;}

            o + P {
                x: x as f64 * step,
                y: y as f64 * step,
            }
        };
        let finish = cell(b);
        let mut queue = std::collections::VecDeque::from([start]);
        let mut prev = BTreeMap::new();
        prev.insert(start, start);
        let mut found = None;
        while let Some(c) = queue.pop_front() {
            if (c == finish || point(c).dist(b)<step*1.5) && self.base.surface_step(point(c),b,class,sea)
            {
                found = Some(c);
                break;
            }
            for (dx, dy) in [
                (1, 0),
                (0, 1),
                (-1, 0),
                (0, -1),
                (1, 1),
                (-1, 1),
                (1, -1),
                (-1, -1),
            ] {
                let n = (c.0 + dx, c.1 + dy);
                if n.0 < 0 || n.1 < 0 || n.0 > width || n.1 > height || prev.contains_key(&n) {
                    continue;
                }
                if self.base.surface_disc(point(n), class, sea)
                    && self.base.surface_step(point(c), point(n), class, sea)
                {
                    prev.insert(n, c);
                    queue.push_back(n);
                }
            }
        }
        let mut c = found.ok_or("没有该兵种可通行的陆路")?;
        let mut route = vec![b];
        while c != start {
            route.push(point(c));
            c = prev[&c];
        }
        route.reverse();
        let mut simple = vec![];
        let mut p = a;
        let mut at = 0;
        while at < route.len() {
            let mut j = at;
            while j + 1 < route.len() && self.base.surface_step(p, route[j + 1], class, sea) {
                j += 1
            }
            simple.push(route[j]);
            p = route[j];
            at = j + 1;
        }
        Ok(simple)
    }

    pub(super) fn apply_vehicle_condition(&mut self) -> E<()> {
        for (side, force) in [(0, Some(&self.config)), (1, self.config.get("defender"))] {
            if let Some(rows) = force.and_then(|f| f.get("vehicle_condition")) {
                let rows = rows.as_array().ok_or("载具整备必须为逐连数组")?;
                let mut seen = BTreeSet::new();
                for r in rows {
                    let id = r["id"].as_str().ok_or("载具人格无效")?;
                    let company = r["company"]
                        .as_u64()
                        .filter(|n| *n > 0 && *n <= 5)
                        .ok_or("载具连序无效")?;
                    let hp = r["hp_percent"]
                        .as_f64()
                        .filter(|n| n.is_finite() && *n > 0. && *n <= 100.)
                        .ok_or("固定战斗载具须先修复，耐久必须在0以上至100")?;
                    if !seen.insert((id, company)) {
                        return Err("载具整备重复".into());
                    }
                    let v = self
                        .vehicles
                        .iter_mut()
                        .find(|v| {
                            let c = &self.base.companies[v.company];
                            c.side == side
                                && c.unit.id == id
                                && c.id.ends_with(&format!("C{company:02}"))
                        })
                        .ok_or("载具整备不属于实际出击编成")?;
                    v.hp = v.max * hp / 100.;
                }
            }
        }
        Ok(())
    }
    pub(super) fn vehicle_safe(&self,v:&CombatVehicle)->bool {
        v.hp>0. && (v.phase=="recovered" || self.base.start.mode=="defense" || v.phase=="aboard" && self.base.base.core.naval.ship(self.base.companies[v.company].carrier).is_some_and(|s|s.alive()))
    }
    pub(super) fn vehicle_outcomes(&self) -> Value {
        json!(self.vehicles.iter().filter(|v|self.base.companies[v.company].side==0).map(|v|{let c=&self.base.companies[v.company];let recovered=self.vehicle_safe(v);json!({"unit_id":c.unit.id,"company_id":c.id,"company":c.id.rsplit('C').next().and_then(|s|s.parse::<u32>().ok()).unwrap_or(1),"vehicle_id":v.id,"kind":v.kind,"hp_percent":v.hp/v.max*100.,"recovered_hp_percent":if recovered{v.hp/v.max*100.}else{0.},"recovered":recovered,"lost":!recovered||v.hp<=0.})}).collect::<Vec<_>>())
    }
    pub(super) fn init_vehicle_mirrors(&mut self) {
        for v in self.vehicles.clone() {
            let c = &self.base.companies[v.company];
            let s = spec(c.unit.id).unwrap();
            self.base.base.core.ground.bodies.push(Body {
                id: v.id,
                group: format!("vehicle:{}", c.id),
                ally: c.side == 0,
                kind: v.kind,
                p: v.p,
                hp: v.hp,
                max: v.max,
                ammo: 0,
                damage: 0.,
                range: 0.,
                reload: 100,
                next: 0,
                armor: s.armor,
                air: v.class == "air",
                active: v.active,
            });
        }
        self.sync_vehicle_mirrors();
    }
    pub(super) fn sync_vehicle_mirrors(&mut self) {
        for v in self.vehicles.clone() {
            if let Some(b) = self.base.body_mut(v.id) {
                b.p = v.p;
                b.hp = v.hp;
                b.max = v.max;
                b.active = v.active;
                b.air = v.class == "air";
            }
        }
    }
    pub(super) fn vehicle_known(&self, id: u32, side: u32) -> bool {
        let Some(v) = self.vehicle_at(id) else {
            return false;
        };
        let c = &self.base.companies[v.company];
        if c.side == side {
            return true;
        }
        self.base
            .actors
            .iter()
            .filter(|a| self.base.companies[a.company].side == side)
            .any(|a| {
                self.base.body(a.id).is_some_and(|b| {
                    b.hp > 0.
                        && b.active
                        && b.p.dist(v.p) < self.base.companies[a.company].unit.vision
                        && (v.class == "air" || self.base.los(b.p, v.p))
                })
            })
            || self.vehicles.iter().any(|o| {
                self.base.companies[o.company].side == side
                    && o.active
                    && o.hp > 0.
                    && o.p.dist(v.p) < 1600.
                    && (o.class == "air" || self.base.los(o.p, v.p))
            })
    }
    pub(super) fn convert_vehicle_transports(&mut self) {
        for vi in 0..self.vehicles.len() {
            let v = self.vehicles[vi].clone();
            if v.phase=="aboard" && self.base.base.core.naval.ship(self.base.companies[v.company].carrier).is_none_or(|s|!s.alive()) {
                self.hurt_vehicle(vi,f64::MAX);continue;
            }
            if v.destroyed || v.phase == "recovered" {
                continue;
            }
            let c = self.base.companies[v.company].clone();
            if v.phase == "aboard" {
                if let Some(t) = self
                    .base
                    .transit
                    .iter()
                    .find(|t| {
                        t.company == v.company
                            && !t.returning
                            && !matches!(t.phase, "lost" | "recovered")
                    })
                    .cloned()
                {
                    if persistent(c.unit.id) {
                        let origin = self.base.body(t.id).map_or(v.p, |b| b.p);
                        let p = (0..512)
                            .map(|n| {
                                origin
                                    + P::bearing((n + vi as u32 * 7) as f64 * 137.507764)
                                        * (14. * (n as f64 + 1.).sqrt())
                            })
                            .find(|p| {
                                self.base.surface_disc(*p, v.class, v.class == "amphibious")
                                    && !self.vehicles.iter().any(|o| {
                                        o.id != v.id
                                            && o.active
                                            && o.hp > 0.
                                            && (o.class == "air") == (v.class == "air")
                                            && o.p.dist(*p) < o.radius + v.radius + 1.
                                    })
                            })
                            .unwrap_or(origin);
                        self.base.transit.retain(|r| r.id != t.id);
                        self.base.base.core.ground.bodies.retain(|b| b.id != t.id);
                        let q = &mut self.vehicles[vi];
                        q.p = p;
                        q.goal = c.goal;
                        q.route = vec![];
                        q.phase = "inserting";
                        q.action = "insert";
                        q.passengers = t.passengers;
                        q.active = true;
                        self.base.companies[v.company].stage = "inserting";
                        for id in self.vehicles[vi].passengers.clone() {
                            if let Some(b) = self.base.body_mut(id) {
                                b.active = false;
                                b.p = p;
                            }
                            if let Some(a) = self.base.actors.iter_mut().find(|a| a.id == id) {
                                a.phase = "in_vehicle";
                                a.altitude = 0.;
                            }
                        }
                    } else {
                        self.vehicles[vi].carried_by = Some(t.id);
                        self.vehicles[vi].phase = "inserting";
                    }
                }
            }
            if !persistent(c.unit.id) && self.vehicles[vi].phase == "inserting" {
                if let Some(tid) = self.vehicles[vi].carried_by {
                    let t = self.base.transit.iter().find(|t| t.id == tid);
                    if t.is_none_or(|t| t.phase == "lost") {
                        self.hurt_vehicle(vi, f64::MAX);
                        continue;
                    }
                    if let Some(b) = self.base.body(tid) {
                        self.vehicles[vi].p = b.p;
                    }
                    if c.stage == "active" {
                        let p = self
                            .base
                            .free_spawn(c.p + P { x: 20., y: 20. }, v.class)
                            .unwrap_or(c.p);
                        let q = &mut self.vehicles[vi];
                        q.p = p;
                        q.goal = p;
                        q.active = true;
                        q.phase = "active";
                        q.action = "follow";
                        q.carried_by = None;
                        self.metrics.insert("vehicle_landed".into());
                    }
                }
            }
        }
        self.sync_vehicle_mirrors();
    }
    pub(super) fn vehicle_preview(&self, q: &Value) -> Value {
        match self.validate_vehicle_order(q, 0) {
            Ok((i, action, p)) => {
                json!({"valid":true,"reason":"","vehicle_id":self.vehicles[i].id,"action":action,"x":p.x,"y":p.y})
            }
            Err(e) => json!({"valid":false,"reason":e}),
        }
    }
    fn validate_vehicle_order(&self, q: &Value, side: u32) -> E<(usize, &'static str, P)> {
        if self.base.result.is_some() {
            return Err("航次已经结束".into());
        }
        let id = q["vehicle_id"].as_u64().ok_or("未指定本连载具")? as u32;
        let i = self
            .vehicles
            .iter()
            .position(|v| v.id == id)
            .ok_or("载具不存在")?;
        let v = &self.vehicles[i];
        let c = &self.base.companies[v.company];
        if c.side != side {
            return Err("不能指挥敌方载具".into());
        }
        if !v.active
            || v.hp <= 0.
            || matches!(v.phase, "aboard" | "inserting" | "recovered" | "dead")
        {
            return Err("载具尚未完成投送或已不能行动".into());
        }
        let action = match q["action"].as_str() {
            Some("move") => "move",
            Some("attack") => "attack",
            Some("face") => "face",
            Some("fire_at") => "fire_at",
            Some("embark") => "embark",
            Some("disembark") => "disembark",
            _ => return Err("未登记的载具动作".into()),
        };
        if action == "embark" && v.capacity == 0 {
            return Err("本连坦克没有步兵乘员座位".into());
        }
        let p = if action == "embark" {
            let points = c
                .bodies
                .iter()
                .filter_map(|id| {
                    self.base
                        .body(*id)
                        .filter(|b| b.active && b.hp > 0.)
                        .map(|b| b.p)
                })
                .collect::<Vec<_>>();
            if points.is_empty() {
                return Err("本连没有待登载身体".into());
            }
            points.iter().copied().fold(P::default(), |a, p| a + p) * (1. / points.len() as f64)
        } else {
            P {
                x: q["x"]
                    .as_f64()
                    .filter(|v| v.is_finite())
                    .ok_or("目标坐标无效")?,
                y: q["y"]
                    .as_f64()
                    .filter(|v| v.is_finite())
                    .ok_or("目标坐标无效")?,
            }
        };
        if action == "disembark" && v.passengers.is_empty() {
            return Err("载具内没有身体".into());
        }
        if action == "disembark" && !self.base.traversable_disc(p, "infantry") {
            return Err("只能在合法陆地卸载身体".into());
        }
        let sea = v.class == "amphibious";
        if action=="face"||action=="fire_at" {
            if p.dist(v.p)<1. {return Err("请拖出有效的火力方向".into())}
            if action=="fire_at" {
                let w=firearms::model(c.unit.id,spec(c.unit.id).unwrap().weapon);
                if !self.firearm_ready(v.id,w,v.ammo,v.next){return Err("载具正在装填或没有弹药".into())}
                let target=self.targets(v.p,c.side,w).iter().any(|t|t.2.dist(p)<65.)||self.base.base.core.ground.buildings.iter().any(|b|b.ally!=(c.side==0)&&b.hp>0.&&b.p.dist(p)<65.&&v.p.dist(b.p)<=w.range_m&&(w.family_id=="howitzer"||self.base.los(v.p,b.p)));
                if !target{return Err("此方向没有射程内可攻击的已知敌目标".into())}
            }
            return Ok((i,action,p))
        }
        self.base.surface_path(v.p, p, v.class, sea)?;
        Ok((i, action, p))
    }
    pub(super) fn vehicle_order(&mut self, q: &Value, side: u32) -> E<()> {
        let (i, action, p) = self.validate_vehicle_order(q, side)?;
        let route = if matches!(action,"face"|"fire_at"){vec![]}else{self.base.surface_path(
            self.vehicles[i].p,
            p,
            self.vehicles[i].class,
            self.vehicles[i].class == "amphibious",
        )?};
        let v = &mut self.vehicles[i];
        v.aim=if matches!(action,"face"|"fire_at"){Some(p)}else{None};
        v.goal = if matches!(action,"face"|"fire_at"){v.p}else{p};
        if matches!(action,"face"|"fire_at"){v.heading=(p-v.p).heading();}
        v.route = route;
        v.manual = true;
        v.action = match action {
            "embark" => "load",
            "disembark" => "unload",
            x => x,
        };
        v.phase = if action == "embark" {
            "loading"
        } else {
            "active"
        };
        let ci = v.company;
        // A valid manual equipment command takes over the real company
        // extraction intent too; the old AI must not immediately undo it.
        if matches!(self.base.companies[ci].stage,"withdrawing"|"returning") {
            self.base.companies[ci].stage="active";
            self.base.companies[ci].order="hold".into();
            self.base.companies[ci].path.clear();
        }
        if action == "embark" {
            self.base.set_goal(ci, p, "board")?;
            self.base.companies[ci].stage = "active";
        }
        Ok(())
    }
    pub(super) fn hurt_vehicle(&mut self, vi: usize, damage: f64) {
        let old = self.vehicles[vi].hp;
        if old <= 0. {
            return;
        }
        self.vehicles[vi].hp = (old - damage).max(0.);
        if self.vehicles[vi].hp <= 0. {
            let v = self.vehicles[vi].clone();
            self.vehicles[vi].destroyed = true;
            self.vehicles[vi].phase = "dead";
            self.vehicles[vi].velocity = P::default();
            for id in v.passengers {
                let hp = self.base.body(id).map_or(0., |b| b.max);
                let loss = if v.class == "air" { 0.65 } else { 0.35 };
                let landing = self.base.free_spawn(v.p, "infantry");
                if let Some(b) = self.base.body_mut(id) {
                    b.hp = if landing.is_some() {
                        (b.hp - hp * loss).max(0.)
                    } else {
                        0.
                    };
                    b.p = landing.unwrap_or(v.p);
                    b.active = true;
                    b.air = false;
                }
                if let Some(a) = self.base.actors.iter_mut().find(|a| a.id == id) {
                    a.phase = if landing.is_some() { "active" } else { "dead" };
                    a.altitude = 0.;
                }
            }
            self.vehicles[vi].passengers.clear();
            let ci = v.company;
            if self.base.companies[ci]
                .bodies
                .iter()
                .any(|id| self.base.body(*id).is_some_and(|b| b.hp > 0. && b.active))
            {
                self.base.companies[ci].stage = "active";
            } else {
                self.base.companies[ci].stage = "lost";
            }
        }
        if let Some(b) = self.base.body_mut(self.vehicles[vi].id) {
            b.hp = (old - damage).max(0.);
        }
    }
    pub(super) fn import_vehicle_damage(&mut self) {
        let hits = self
            .vehicles
            .iter()
            .enumerate()
            .filter_map(|(i, v)| {
                self.base
                    .body(v.id)
                    .and_then(|b| (b.hp < v.hp).then_some((i, v.hp - b.hp)))
            })
            .collect::<Vec<_>>();
        for (i, d) in hits {
            self.hurt_vehicle(i, d);
        }
        self.sync_vehicle_mirrors();
    }

    pub(super) fn blocking_vehicle(&self,from:P,to:P,target:Option<u32>)->Option<&CombatVehicle>{
        let delta=to-from;let length=delta.x*delta.x+delta.y*delta.y;
        if length<1e-9{return None}
        self.vehicles.iter().filter(|v|v.active&&v.hp>0.&&v.class!="air"&&Some(v.id)!=target).filter_map(|v|{
            let t=((v.p-from).x*delta.x+(v.p-from).y*delta.y)/length;
            (t>0.001&&t<0.999&&distance_to_segment(v.p,from,to)<v.radius).then_some((v,t))
        }).min_by(|(_,a),(_,b)|a.total_cmp(b)).map(|(v,_)|v)
    }
    fn tank_movement_goals(&mut self)->BTreeMap<u32,P>{
        let mut goals=BTreeMap::new();self.tank_tactics.clear();
        for vi in 0..self.vehicles.len(){
            let v=self.vehicles[vi].clone();let c=self.base.companies[v.company].clone();
            if !matches!(c.unit.id,"MCP-022"|"MCP-103"|"MCP-304"|"MCP-305")||!v.active||v.hp<=0.||c.stage!="active"||c.order=="extract"||self.base.land_complete(){continue}
            let target=self.role_target(v.company).map(|t|t.1);
            let Some(target)=target else{continue};let distance=v.p.dist(target);if distance>2200.{continue}
            let forward=(target-v.p).unit();let lateral=P{x:forward.y,y:-forward.x};
            if !v.manual && (c.side!=0||self.base.auto) {
                let stand=480.;
                self.vehicles[vi].goal=if distance>stand{target-forward*stand}else{v.p};
                self.vehicles[vi].route.clear();self.vehicles[vi].action="cooperate";
            }
            for (rank,id) in c.bodies.iter().enumerate(){
                if self.body_manual_until.get(id).is_some_and(|f|*f>self.frame()){continue}
                let Some(body)=self.base.body(*id).filter(|b|b.hp>0.&&b.active)else{continue};
                let pressure=self.body_pressure.get(id).is_some_and(|until|*until>self.frame());
                let phase=(self.frame()+*id*13)%100;
                let flank=rank<2&&(40..60).contains(&phase)&&!pressure&&body.p.dist(target)<self.loadouts[id].weapon.range_m;
                let want=if flank{v.p-forward*1.+lateral*(if rank==0{1.}else{-1.})*(v.radius+7.)}else{v.p-forward*(10.+rank as f64*1.8)+lateral*((rank as f64%2.-0.5)*1.4)};
                // Local legal search changes the actual goal only; movement and
                // shots still arbitrate every physical body and tank footprint.
                let goal=(0..24).map(|n|want+P::bearing(n as f64*137.5)*(n as f64*0.4)).find(|p|self.base.traversable_disc(*p,"infantry")&&p.dist(v.p)>v.radius+0.6).unwrap_or(body.p);
                self.tank_tactics.insert(*id,(v.id,if pressure{"fallback"}else if flank{"flanking"}else{"covered"},goal));goals.insert(*id,goal);
            }
        }
        goals
    }
    fn personal_movement_goals(&mut self)->BTreeMap<u32,P>{
        let mut goals=self.tank_movement_goals();
        let rows=self.base.actors.iter().filter_map(|a|{
            let c=&self.base.companies[a.company];let b=self.base.body(a.id)?;
            if !b.active||b.hp<=0.||a.phase=="parachuting"{return None}
            let loading=self.vehicles.iter().any(|v|v.company==a.company&&v.active&&v.hp>0.&&matches!(v.action,"load"|"extract"));
            (matches!(c.stage,"withdrawing"|"vehicle_loading")||loading).then_some((a.id,b.p,c.goal))
        }).collect::<Vec<_>>();
        for (id,from,goal) in rows {
            let recompute=self.body_routes.get(&id).is_none_or(|(old,_)|old.dist(goal)>8.)||self.frame()%40==id%40;
            if recompute {let path=self.precise_route(from,goal,"infantry",false).unwrap_or_default();self.body_routes.insert(id,(goal,path));}
            if let Some((_,path))=self.body_routes.get_mut(&id){while path.len()>1&&from.dist(path[0])<12.{path.remove(0);}if let Some(p)=path.first(){goals.insert(id,*p);}}
        }
        goals
    }
    pub(super) fn move_people_with_vehicles(&mut self) {

        let mut held = vec![];
        let mut offsets = vec![];
        for v in self.vehicles.clone() {
            if v.hp <= 0. || !v.active {
                continue;
            }
            let ci = v.company;
            let c = self.base.companies[ci].clone();
            if persistent(c.unit.id) && matches!(c.stage, "withdrawing" | "returning") {
                held.push((ci, c.stage));
                self.base.companies[ci].stage = "vehicle_loading";
            }
            if matches!(v.action, "load" | "extract") {
                self.base.companies[ci].goal = v.p;
                self.base.companies[ci].path = vec![v.p];
                for a in self.base.actors.iter_mut().filter(|a| a.company == ci) {
                    offsets.push((a.id, a.offset));
                    a.offset = P::default();
                }
            }
        }
        let equipment=self.vehicles.iter().filter(|v|v.active&&v.hp>0.).map(|v|Disc{id:v.id,p:v.p,radius:v.radius,layer:if v.class=="air"{1}else{0}}).collect::<Vec<_>>();
        let personal=self.personal_movement_goals();
        let mut personal=personal;
        for c in &self.base.companies {if c.unit.role=="artillery"&&c.stage=="active"&&!matches!(c.order.as_str(),"move"|"extract"|"board"|"screen") {
            for id in &c.bodies {if let Some(b)=self.base.body(*id){personal.insert(*id,b.p);}}
        }}
        self.base.move_companies_with_equipment_v3(&equipment,&personal);
        for (ci, stage) in held {
            if self.base.companies[ci].stage == "vehicle_loading" {
                self.base.companies[ci].stage = stage;
            }
        }
        for (id, p) in offsets {
            if let Some(a) = self.base.actors.iter_mut().find(|a| a.id == id) {
                a.offset = p;
            }
        }
    }

    fn unload_vehicle(&mut self, vi: usize) -> bool {
        let v = self.vehicles[vi].clone();
        let mut remaining = vec![];
        for (id_index, id) in v.passengers.iter().enumerate() {
            if self.base.body(*id).is_none_or(|b| b.hp <= 0.) {
                continue;
            }
            let want =
                v.p + P::bearing(id_index as f64 * 137.5) * (v.radius + 12. + id_index as f64 * 2.);
            if let Some(p) = self.base.free_spawn(want, "infantry") {
                self.base.body_mut(*id).unwrap().p = p;
                self.base.body_mut(*id).unwrap().active = true;
                self.base.body_mut(*id).unwrap().air = false;
                if let Some(a) = self.base.actors.iter_mut().find(|a| a.id == *id) {
                    a.phase = "active";
                    a.altitude = 0.;
                    a.velocity = P::default();
                }
                self.metrics.insert("vehicle_disembarked".into());
            } else {
                remaining.push(*id);
            }
        }
        self.vehicles[vi].passengers = remaining;
        self.vehicles[vi].passengers.is_empty()
    }
    fn board_vehicle(&mut self, vi: usize) {
        let v = self.vehicles[vi].clone();
        let c = self.base.companies[v.company].clone();
        for id in c.bodies {
            if self.vehicles[vi].passengers.len() >= v.capacity as usize {
                break;
            }
            if self.base.body(id).is_some_and(|b| {
                b.hp > 0.
                    && b.active
                    && b.p.dist(v.p) <= v.radius + 18.
                    && self.base.straight(b.p, v.p, "infantry")
            }) {
                self.base.body_mut(id).unwrap().active = false;
                self.base.body_mut(id).unwrap().p = v.p;
                if let Some(a) = self.base.actors.iter_mut().find(|a| a.id == id) {
                    a.phase = "in_vehicle";
                    a.velocity = P::default();
                }
                self.vehicles[vi].passengers.push(id);
                self.metrics.insert("vehicle_embarked".into());
            }
        }
    }
    pub(super) fn retain_independent_vehicles(&mut self){
        for v in &self.vehicles {if v.hp>0. && v.active && !matches!(v.phase,"recovered"|"returning"|"dead") {
            let c=&mut self.base.companies[v.company];if matches!(c.stage,"lost"|"recovered") {c.stage="active";c.p=v.p;c.goal=v.p;c.path.clear();if c.order!="extract"{c.order="hold".into();}}
        }}
    }
    pub(super) fn step_vehicles(&mut self) {
        let frame = self.frame();
        let mut vehicle_occupancy=Occupancy::new(self.vehicles.iter().filter(|v|v.active&&v.hp>0.).map(|v|Disc{id:v.id,p:v.p,radius:v.radius,layer:if v.class=="air"{1}else{0}}).collect());
        for vi in 0..self.vehicles.len() {
            let mut v = self.vehicles[vi].clone();
            let c = self.base.companies[v.company].clone();
            if !v.active || v.hp <= 0. {
                continue;
            }
            let extracting = matches!(c.stage, "withdrawing" | "returning") || c.order == "extract";
            if extracting && !matches!(v.phase, "returning" | "recovered") {
                if persistent(c.unit.id) {
                    let first = v.action != "extract";
                    v.action = "extract";
                    v.phase = "loading";
                    let points = c
                        .bodies
                        .iter()
                        .filter_map(|id| {
                            self.base
                                .body(*id)
                                .filter(|b| b.active && b.hp > 0.)
                                .map(|b| b.p)
                        })
                        .collect::<Vec<_>>();
                    if !points.is_empty() && first {
                        let mean = points.iter().copied().fold(P::default(), |a, p| a + p)
                            * (1. / points.len() as f64);
                        v.goal = self.base.free_spawn(mean, "infantry").unwrap_or(points[0]);
                        v.route = vec![];
                    }
                } else {
                    v.action = "recover_vehicle";
                    v.goal = self
                        .base
                        .base
                        .geometry
                        .coast_landing(c.beach)
                        .map_or(c.goal, |b| b.1);
                    if v.p.dist(v.goal) < 100. {
                        if let Some(ship) = self.base.base.core.naval.ship(c.carrier).filter(|s| {
                            s.alive()
                                && s.p.dist(self.base.base.geometry.beach(c.beach).unwrap().0)
                                    < 900.
                        }) {
                            let ship_p = ship.p;
                            let t_id = self.base.base.core.ground.id();
                            let craft = vehicle("heavy_lander").unwrap();
                            self.base.base.core.ground.bodies.push(Body {
                                id: t_id,
                                group: format!("vehicle_recovery:{}", c.id),
                                ally: c.side == 0,
                                kind: "landing_craft",
                                p: self.base.base.geometry.coast_landing(c.beach).unwrap().0,
                                hp: craft.hp,
                                max: craft.hp,
                                ammo: 0,
                                damage: 0.,
                                range: 0.,
                                reload: 100,
                                next: 0,
                                armor: craft.armor,
                                air: false,
                                active: true,
                            });
                            self.base.transit.push(Transit {
                                id: t_id,
                                company: v.company,
                                passengers: vec![],
                                vehicle: craft,
                                phase: "returning",
                                goal: ship_p,
                                heading: 270.,
                                returning: true,
                                drop: false,
                            });
                            v.carried_by = Some(t_id);
                            v.phase = "returning";
                            v.active = false;
                        }
                    }
                }
            }
            if v.action == "follow"
                && !v.manual
                && (c.side != 0 || self.base.auto)
                && c.stage == "active"
                && frame % 20 == 0
            {
                let w = firearms::model(c.unit.id, spec(c.unit.id).unwrap().weapon);
                let target = self
                    .targets(v.p, c.side, w)
                    .first()
                    .map(|t| t.2)
                    .or_else(|| {
                        self.base
                            .base
                            .core
                            .ground
                            .buildings
                            .iter()
                            .filter(|b| b.ally != (c.side == 0) && b.hp > 0.)
                            .min_by(|a, b| a.p.dist(v.p).total_cmp(&b.p.dist(v.p)))
                            .map(|b| b.p)
                    });
                if let Some(p) = target {
                    let d = v.p.dist(p);
                    let stand = if v.kind == "self_propelled_gun" {
                        1100.
                    } else {
                        w.range_m * 0.6
                    };
                    v.goal = if d > stand {
                        p + (v.p - p) * (stand / d)
                    } else {
                        v.p
                    };
                }
            }
            if v.phase == "unloading" && frame >= v.ready_at {
                self.vehicles[vi] = v.clone();
                let complete = self.unload_vehicle(vi);
                v = self.vehicles[vi].clone();
                if complete {
                    v.phase = "active";
                    v.action = "follow";
                    let ci = v.company;
                    self.base.companies[ci].stage = "active";
                    self.base.companies[ci].goal = v.p;
                    self.base.companies[ci].path = vec![];
                    self.metrics.insert("vehicle_landed".into());
                }
            }
            if matches!(v.phase, "loading") {
                self.vehicles[vi] = v.clone();
                self.board_vehicle(vi);
                v = self.vehicles[vi].clone();
                let all = c.bodies.iter().all(|id| {
                    self.base.body(*id).is_none_or(|b| b.hp <= 0.)
                        || v.passengers.contains(id)
                        || self
                            .base
                            .actors
                            .iter()
                            .any(|a| a.id == *id && a.phase == "recovered")
                });
                if all {
                    if extracting {
                        if let Some(ship) = self
                            .base
                            .base
                            .core
                            .naval
                            .ship(c.carrier)
                            .filter(|s| s.alive())
                        {
                            v.phase = "returning";
                            v.goal = ship.p;
                            v.route = vec![];
                            self.base.companies[v.company].stage = "returning";
                        }
                    } else {
                        v.phase = "active";
                        v.action = "hold";
                    }
                }
            }
            if v.phase == "returning" {
                if let Some(ship) = self
                    .base
                    .base
                    .core
                    .naval
                    .ship(c.carrier)
                    .filter(|s| s.alive())
                    .cloned()
                {
                    v.goal = ship.p;
                    if v.p.dist(ship.p) < 120. {
                        for id in v.passengers.clone() {
                            if let Some(b) = self.base.body_mut(id) {
                                b.p = ship.p;
                                b.active = false;
                            }
                            if let Some(a) = self.base.actors.iter_mut().find(|a| a.id == id) {
                                a.phase = "recovered";
                            }
                        }
                        v.phase = "recovered";
                        v.active = false;
                        self.base.companies[v.company].stage = "recovered";
                    }
                }
            }
            let moving =
                !matches!(v.phase, "unloading" | "recovered" | "dead") && v.p.dist(v.goal) > 3.;
            v.velocity = P::default();
            if moving {
                let sea = v.class == "amphibious";
                if v.route.is_empty() || v.route.last().is_some_and(|p| p.dist(v.goal) > 10.) {
                    v.route = self
                        .base
                        .surface_path(v.p, v.goal, v.class, sea)
                        .unwrap_or_default();
                }
                if let Some(target) = v.route.first().copied() {
                    let d = v.p.dist(target);
                    if d < 10. {
                        v.route.remove(0);
                    } else {
                        let terrain_speed = self.base.terrain.speed(v.p, v.class)
                            .max(if v.class == "air" { 1. } else { 0.05 });
                        let speed = if sea && self.vehicle_in_water(v.p) {
                            water_speed(c.unit.id) * terrain_speed
                        } else {
                            v.speed * terrain_speed
                        };
                        let travel = (speed * DT).min(d);
                        let mut next = v.p + (target - v.p) * (travel / d);
                        let occ = self.base.occupancy();
                        let layer = if v.class == "air" { 1 } else { 0 };
                        let legal = |q: P| {
                            self.base.surface_step(v.p, q, v.class, sea)
                                && occ.clear(v.id, v.p, q, v.radius, layer)
                                && vehicle_occupancy.clear(v.id,v.p,q,v.radius,layer)
                        };
                        if !legal(next) {
                            next = v.p;
                            for angle in [45., -45., 90., -90., 135., -135.] {
                                let delta = target - v.p;
                                let a = libm::atan2(delta.x, delta.y).to_degrees() + angle;
                                let q = v.p + P::bearing(a) * travel;
                                if legal(q) {
                                    next = q;
                                    break;
                                }
                            }
                        }
                        if next.dist(v.p) > 0.01 {
                            v.heading = libm::atan2((next - v.p).x, (next - v.p).y).to_degrees();
                            v.velocity = (next - v.p) * (1. / DT);
                            v.p = next;
                        }
                    }
                }
            }
            if matches!(v.action, "insert" | "unload")
                && v.p.dist(v.goal) < 30.
                && !matches!(v.phase, "unloading" | "recovered")
            {
                v.phase = "unloading";
                v.ready_at = frame + 15;
                v.velocity = P::default();
            }
            for id in &v.passengers {
                if let Some(b) = self.base.body_mut(*id) {
                    b.p = v.p;
                    b.active = false;
                }
            }
            vehicle_occupancy.update(v.id,v.p);
            self.vehicles[vi] = v;
        }
        for vi in 0..self.vehicles.len() {
            let v = self.vehicles[vi].clone();
            if v.phase == "returning" && !v.active {
                if let Some(t) = v
                    .carried_by
                    .and_then(|id| self.base.transit.iter().find(|t| t.id == id))
                {
                    if let Some(body) = self.base.body(t.id) {
                        self.vehicles[vi].p = body.p;
                    }
                    if t.phase == "recovered" {
                        self.vehicles[vi].phase = "recovered";
                    } else if t.phase == "lost" {
                        self.hurt_vehicle(vi, f64::MAX);
                    }
                }
            }
        }
        self.sync_vehicle_mirrors();
    }
    pub(super) fn vehicles_view(&self) -> Vec<Value> {
        self.vehicles.iter().map(|v|{let c=&self.base.companies[v.company];let s=spec(c.unit.id).unwrap();let w=firearms::model(c.unit.id,s.weapon);let mut row=json!({"id":v.id,"unit_id":c.unit.id,"company_id":c.id,"side":if c.side==0{"allies"}else{"axis"},"x":v.p.x,"y":v.p.y,"operator_id":Value::Null,"min_crew":0,"shared_consciousness_control":true,"passenger_ids":v.passengers,"capacity":v.capacity,"path":v.route,"goal":v.goal,"vehicle_kind":v.kind,"vehicle_id":format!("{}-{}",c.unit.id,v.kind),"physical_class":v.class,"kind":v.kind,"phase":v.phase,"hp":v.hp,"max_hp":v.max,"armor_multiplier":s.armor,"ammo":v.ammo,"weapon_id":w.id,"weapon_family_id":w.family_id,"weapon":accuracy::compact(w),"range":w.range_m,"damage":w.damage,"armor_class":v.armor_class,"collision_radius_m":v.radius,"heading":v.heading,"velocity":v.velocity,"visible":self.vehicle_known(v.id,0),"known":self.vehicle_known(v.id,0),"art_version":"tactical-art-v2","equipment_version":EQUIPMENT,"air":v.class=="air","altitude_m":if v.class=="air"&& !matches!(v.phase,"loading"|"unloading"|"aboard"|"recovered"){45.}else{0.},"movement_domain":if v.class=="air"{"air"}else if self.vehicle_in_water(v.p){"water"}else{"land"}});row["active"]=json!(v.active);row["carried_by"]=json!(v.carried_by);row["shared_consciousness"]=json!(true);row["separate_vehicle_hp"]=json!(true);row.as_object_mut().unwrap().extend(self.firearm_view(v.id,w,v.ammo,v.next).as_object().unwrap().clone());row}).collect()
    }
}

// Explicit v3 fork of our frozen movement consumer. Equipment occupancy and
// per-body retreat waypoints are supplied before arbitration, never rolled back
// after another body has occupied a vacated position.
impl super::super::Battle {
    fn move_companies_with_equipment_v3(&mut self, equipment:&[Disc], personal:&BTreeMap<u32,P>) {
        let frame = self.frame();
        let mut discs=self.occupancy().discs;discs.extend_from_slice(equipment);let mut occupancy=Occupancy::new(discs);
        for i in 0..self.actors.len() {
            if self.actors[i].phase == "recovered" {
                let a = self.actors[i].clone();
                let ship = self
                    .base
                    .core
                    .naval
                    .ship(self.companies[a.company].carrier)
                    .filter(|s| s.alive())
                    .map(|s| s.p);
                if let Some(b) = self.body_mut(a.id) {
                    if let Some(p) = ship {
                        b.p = p;
                    } else {
                        b.hp = 0.;
                        b.active = true;
                    }
                }
                if ship.is_none() {
                    self.actors[i].phase = "dead";
                }
            }
        }
        for ci in 0..self.companies.len() {
            self.launch_pending(ci);
            let c = self.companies[ci].clone();
            if ["lost", "recovered", "embarked"].contains(&c.stage) {
                if matches!(c.stage, "embarked" | "recovered") {
                    if let Some(p) = self.base.core.naval.ship(c.carrier).map(|s| s.p) {
                        for id in &c.bodies {
                            if let Some(b) = self.body_mut(*id) {
                                b.p = p;
                            }
                        }
                    }
                }
                if self
                    .base
                    .core
                    .naval
                    .ship(c.carrier)
                    .is_none_or(|s| !s.alive())
                    && matches!(c.stage, "embarked" | "recovered")
                {
                    for id in &c.bodies {
                        if let Some(b) = self.body_mut(*id) {
                            b.hp = 0.;
                            b.active = true;
                        }
                    }
                    self.companies[ci].stage = "lost";
                }
                continue;
            }
            let positions = c
                .bodies
                .iter()
                .filter_map(|id| {
                    self.body(*id)
                        .filter(|b| b.hp > 0. && b.active)
                        .map(|b| b.p)
                })
                .collect::<Vec<_>>();
            if c.stage == "returning"
                && c.unit.class != "air"
                && c.unit.class != "amphibious"
                && c.bodies.iter().all(|id| {
                    self.body(*id).is_none_or(|b| b.hp <= 0.)
                        || self
                            .actors
                            .iter()
                            .any(|a| a.id == *id && a.phase == "recovered")
                })
            {
                self.companies[ci].stage = "recovered";
                continue;
            }
            if positions.is_empty() {
                if c.bodies
                    .iter()
                    .all(|id| self.body(*id).is_none_or(|b| b.hp <= 0.))
                {
                    self.companies[ci].stage = "lost";
                }
                continue;
            }
            let center =
                positions.iter().fold(P::default(), |p, q| p + *q) * (1. / positions.len() as f64);
            self.companies[ci].p = center;
            if c.stage == "withdrawing" && positions.iter().any(|p| p.dist(c.goal) < 90.) {
                let s = self
                    .base
                    .core
                    .naval
                    .ship(c.carrier)
                    .filter(|s| s.alive())
                    .map(|s| s.p);
                if s.is_some_and(|p| p.dist(self.base.geometry.beach(c.beach).unwrap().0) <= 900.)
                    && !self.transit.iter().any(|t| {
                        t.company == ci
                            && t.returning
                            && !t.passengers.is_empty()
                            && t.phase != "recovered"
                    })
                {
                    let v = vehicle(if c.transport.kind == "parachute_aircraft" {
                        "landing_craft"
                    } else {
                        c.transport.kind
                    })
                    .unwrap();
                    for batch in c.bodies.chunks(v.capacity as usize) {
                        let passengers = batch
                            .iter()
                            .filter(|id| {
                                self.body(**id).is_some_and(|b| {
                                    b.hp > 0. && b.active && b.p.dist(c.goal) < 90.
                                })
                            })
                            .copied()
                            .collect::<Vec<_>>();
                        if passengers.is_empty() {
                            continue;
                        }
                        let boarding = passengers
                            .iter()
                            .filter_map(|id| self.body(*id))
                            .fold(P::default(), |p, b| p + b.p)
                            * (1. / passengers.len() as f64);
                        let id = self.base.core.ground.id();
                        self.base.core.ground.bodies.push(Body {
                            id,
                            group: format!("recovery:{}", c.id),
                            ally: c.side == 0,
                            kind: if v.air { "helicopter" } else { "landing_craft" },
                            p: if v.air{boarding}else{self.base.geometry.coast_landing(c.beach).unwrap().0},
                            hp: v.hp,
                            max: v.hp,
                            ammo: 0,
                            damage: 0.,
                            range: 0.,
                            reload: 100,
                            next: 0,
                            armor: v.armor,
                            air: v.air,
                            active: true,
                        });
                        for bid in &passengers {
                            if let Some(b) = self.body_mut(*bid) {
                                b.active = false;
                            }
                            if let Some(a) = self.actors.iter_mut().find(|a| a.id == *bid) {
                                a.phase = "returning";
                            }
                        }
                        self.transit.push(Transit {
                            id,
                            company: ci,
                            passengers,
                            vehicle: v,
                            phase: "returning",
                            goal: s.unwrap(),
                            heading: 270.,
                            returning: true,
                            drop: false,
                        });
                    }
                    if c.bodies.iter().all(|id| {
                        self.body(*id).is_none_or(|b| b.hp <= 0.)
                            || self.actors.iter().any(|a| {
                                a.id == *id && matches!(a.phase, "returning" | "recovered")
                            })
                    }) {
                        self.companies[ci].stage = "returning";
                    }
                }
            }
            if c.stage == "returning" && c.unit.class != "air" && c.unit.class != "amphibious" {
                if c.bodies.iter().all(|id| {
                    self.body(*id).is_none_or(|b| b.hp <= 0.)
                        || self
                            .actors
                            .iter()
                            .any(|a| a.id == *id && a.phase == "recovered")
                }) {
                    self.companies[ci].stage = "recovered";
                    self.companies[ci].next = frame + 200;
                }
                continue;
            }
            if c.stage == "returning" && matches!(c.unit.class, "air" | "amphibious") {
                if let Some(p) = self
                    .base
                    .core
                    .naval
                    .ship(c.carrier)
                    .filter(|s| s.alive())
                    .map(|s| s.p)
                {
                    self.companies[ci].goal = p;
                    if c.unit.class == "air" || self.companies[ci].path.is_empty() {
                        self.companies[ci].path = vec![p];
                    } else if let Some(last) = self.companies[ci].path.last_mut() {
                        *last = p;
                    }
                    for id in &c.bodies {
                        if !self
                            .body(*id)
                            .is_some_and(|b| b.hp > 0. && b.active && b.p.dist(p) < 120.)
                        {
                            continue;
                        }
                        if let Some(b) = self.body_mut(*id) {
                            b.active = false;
                        }
                        if let Some(a) = self.actors.iter_mut().find(|a| a.id == *id) {
                            a.phase = "recovered";
                        }
                    }
                    if c.bodies.iter().all(|id| {
                        self.body(*id).is_none_or(|b| b.hp <= 0.)
                            || self
                                .actors
                                .iter()
                                .any(|a| a.id == *id && a.phase == "recovered")
                    }) {
                        self.companies[ci].stage = "recovered";
                        self.companies[ci].next = frame + 200;
                        continue;
                    }
                }
            }
            let target = c.path.first().copied().unwrap_or(c.goal);
            if !c.path.is_empty()
                && c.bodies
                    .iter()
                    .filter(|id| self.body(**id).is_some_and(|b| b.active && b.hp > 0.))
                    .all(|id| {
                        self.actors.iter().any(|a| {
                            a.id == *id && a.last_waypoint.is_some_and(|p| p.dist(target) < 0.1)
                        })
                    })
            {
                self.companies[ci].path.remove(0);
            }
            if c.stage == "inserting"
                && matches!(c.unit.class, "air" | "amphibious")
                && center.dist(c.goal) < 90.
            {
                self.companies[ci].stage = "active";
                for a in self.actors.iter_mut().filter(|a| a.company == ci) {
                    a.phase = "active";
                }
            }
            for id in &c.bodies {
                let Some(old) = self.body(*id).cloned() else {
                    continue;
                };
                if old.hp <= 0. || !old.active {
                    continue;
                }
                let ai = self.actors.iter().position(|a| a.id == *id).unwrap();
                let mut a = self.actors[ai].clone();
                if a.phase == "parachuting" {
                    a.altitude = (3. * (a.air_until.saturating_sub(frame)) as f64).max(0.);
                    if frame >= a.air_until {
                        a.phase = "active";
                        if let Some(b) = self.body_mut(*id) {
                            b.air = false;
                        }
                    }
                    self.actors[ai] = a;
                    continue;
                }
                let mut goal = if c.path.len() > 1 {
                    if old.p.dist(target) < 35. + body_radius(c.unit.class) * 3. {
                        a.last_waypoint = Some(target);
                    }
                    if a.last_waypoint.is_some_and(|p| p.dist(target) < 0.1) {
                        c.path[1]
                    } else {
                        target
                    }
                } else {
                    if matches!(c.stage, "returning" | "withdrawing") {
                        target
                    } else {
                        target + a.offset
                    }
                };
                if let Some(p)=personal.get(id){goal=*p;}
                if !self.traversable_disc(goal, c.unit.class)
                    || !self.straight(old.p, goal, c.unit.class)
                {
                    // Collapse through constrained terrain before fanning out again.
                    if !personal.contains_key(id){goal = target;}
                }
                if c.path.is_empty() && c.order == "hold" && !personal.contains_key(id) {
                    goal = old.p;
                }
                let delta = goal - old.p;
                let mut speed = c.unit.speed * c.speed_scale;
                if c.unit.class == "amphibious" && !inside(&self.base.core.ground.polygon, old.p) {
                    speed = vehicle("amphibious_vehicle").unwrap().speed;
                } else {
                    speed *= self.terrain.speed(old.p, c.unit.class);
                }
                if c.buff_until > frame && matches!(c.unit.ability, "rapid_march" | "coordination")
                {
                    speed *= 1.3;
                }
                let radius = body_radius(c.unit.class);
                let layer = if c.unit.class == "air" { 1 } else { 0 };
                let length = delta.dist(P::default());
                let step = (speed * DT).min(length);
                let sea =
                    matches!(c.stage, "inserting" | "returning") && c.unit.class == "amphibious";
                let mut next = old.p;
                if a.knock_until <= frame && length > 0.2 {
                    // Consistent right-hand yielding breaks two-company head-on symmetry.
                    // Short alternatives fit into queues; segment checks prevent tunnelling.
                    'steer: for fraction in [1., 0.5, 0.2] {
                        for angle in [0., 30., -30., 60., -60., 90., -90., 120., -120.] {
                            let candidate =
                                old.p + P::bearing(delta.heading() + angle) * (step * fraction);
                            let terrain_ok = self.surface_disc(candidate, c.unit.class, sea)
                                && self.surface_step(old.p, candidate, c.unit.class, sea);
                            if terrain_ok && occupancy.clear(*id, old.p, candidate, radius, layer) {
                                next = candidate;
                                break 'steer;
                            }
                        }
                    }
                    if next.dist(old.p) < 0.001 {
                        a.blocked_frames += 1;
                    } else {
                        a.blocked_frames = 0;
                    }
                }
                a.velocity = (next - old.p) * (1. / DT);
                if next.dist(old.p) > 0.01 {
                    a.heading = (next - old.p).heading();
                }
                if c.unit.class == "air" {
                    a.fuel = (a.fuel - next.dist(old.p) - 3.).max(0.);
                    if a.fuel <= 0. {
                        if let Some(b) = self.body_mut(*id) {
                            b.hp = 0.;
                        }
                    }
                }
                if let Some(b) = self.body_mut(*id) {
                    b.p = next;
                }
                occupancy.update(*id, next);
                self.actors[ai] = a;
            }
        }
    }
}
impl Terrain {
}


#[cfg(test)]
mod tests {
 use super::*;
    fn battle()->Battle {
        let d:Value=serde_json::from_str(include_str!("../godot/data/tactical-training-v4.json")).unwrap();
        let mut q=d["lessons"]["combined_arms"]["request"].clone();
        q["roster"]=json!(["MCP-022","MCP-103","MCP-087","MCP-027","MCP-006","MCP-304","MCP-305"]);q["ships"]=json!([{"id":"CAS-O-APV-TIDEBRIDGE","hp":100,"ammo":100},{"id":"CAS-H-USN-ENTERPRISE-1942","hp":100,"ammo":100},{"id":"CAS-O-LHA-RETURNLIGHT","hp":100,"ammo":100}]);
        let seed=q["seed"].as_u64().unwrap() as u32;
        let o=q.as_object_mut().unwrap();for key in ["op","version","seed"]{o.remove(key);}
        Battle::new(seed,q).unwrap()
    }
    fn landed(b:&mut Battle,id:&str)->usize {
        let ci=b.base.companies.iter().position(|c|c.side==0&&c.unit.id==id).unwrap();
        let p=b.base.base.geometry.beach(2).unwrap().1+P{x:150.,y:0.};
        b.base.companies[ci].stage="active";b.base.companies[ci].p=p;b.base.companies[ci].goal=p;b.base.companies[ci].path.clear();b.base.companies[ci].order="hold".into();
        for (k,id) in b.base.companies[ci].bodies.clone().iter().enumerate(){
            let p=b.base.free_spawn(p+P::bearing(k as f64*137.5)*(15.+k as f64*5.),"infantry").unwrap();
            let body=b.base.body_mut(*id).unwrap();body.active=true;body.p=p;
            let a=b.base.actors.iter_mut().find(|a|a.id==*id).unwrap();a.phase="active";a.velocity=P::default();
        }
        let vi=b.vehicles.iter().position(|v|v.company==ci).unwrap();let s=spec(id).unwrap();let point=b.base.free_spawn(p+P{x:75.,y:0.},s.class).unwrap();
        let v=&mut b.vehicles[vi];v.active=true;v.phase="active";v.p=point;v.goal=point;v.action="hold";v.passengers.clear();b.sync_vehicle_mirrors();ci
    }
    #[test]
    fn actual_tank_hull_blocks_direct_fire_for_both_sides_without_free_cover_buff(){
        let mut b=battle();let ci=landed(&mut b,"MCP-022");let vi=b.vehicles.iter().position(|v|v.company==ci).unwrap();let p=b.vehicles[vi].p;
        let body=b.base.companies[ci].bodies[0];b.base.body_mut(body).unwrap().p=p+P{x:-20.,y:0.};
        let enemy=b.base.companies.iter().find(|c|c.side==1).unwrap().bodies[0];b.base.body_mut(enemy).unwrap().p=p+P{x:150.,y:0.};b.base.body_mut(enemy).unwrap().active=true;
        let w=firearms::model("MCP-022","rifle");let ammo=b.base.body(body).unwrap().ammo;
        assert!(!b.launch(body,0,b.base.body(body).unwrap().p,b.base.body(enemy).unwrap().p,Some(enemy),"unarmored",w,1.,"body".into()));
        assert_eq!(b.base.body(body).unwrap().ammo,ammo,"blocked fire does not consume a round");
        let ew=b.loadouts[&enemy].weapon;
        assert!(b.launch(enemy,1,b.base.body(enemy).unwrap().p,b.base.body(body).unwrap().p,Some(body),"unarmored",ew,1.,"enemy".into()));
        assert_eq!(b.shots.values().last().unwrap().target,Some(b.vehicles[vi].id),"enemy direct round first meets actual tank");
        let from=p+P{x:-20.,y:15.};assert!(b.blocking_vehicle(from,p+P{x:150.,y:15.},Some(enemy)).is_none(),"a real flank clears the same hull");
        let before=b.base.body(body).unwrap().hp;let mut info=b.shots.values().last().unwrap().clone();info.weapon=firearms::model("MCP-087","howitzer");info.hit=true;info.target=Some(body);
        b.resolve(b.base.body(body).unwrap().p,20.,100.,1,Some(&info),"howitzer","arc",false,0.);assert!(b.base.body(body).unwrap().hp<before,"high-angle area fire can hurt people behind the vehicle");
    }
    #[test]
    fn tank_cooperation_uses_known_threat_physical_rear_and_at_most_two_flanks(){
        let mut b=battle();let ci=landed(&mut b,"MCP-022");b.base.auto=false;let vi=b.vehicles.iter().position(|v|v.company==ci).unwrap();let p=b.vehicles[vi].p;
        let enemy=b.base.companies.iter().find(|c|c.side==1).unwrap().bodies[0];let e=b.base.body_mut(enemy).unwrap();e.active=true;e.p=p+P{x:150.,y:0.};b.base.actors.iter_mut().find(|a|a.id==enemy).unwrap().seen[0]=true;
        let positions=b.base.companies[ci].bodies.iter().map(|id|(*id,b.base.body(*id).unwrap().p)).collect::<Vec<_>>();
        for frame in 0..100 {b.base.base.core.ground.frame=frame;let goals=b.tank_movement_goals();assert_eq!(goals.len(),6);assert!(b.tank_tactics.values().filter(|(_,s,_)|*s=="flanking").count()<=2);for (id,(_,state,goal)) in &b.tank_tactics{assert!(goal.dist(p)>b.vehicles[vi].radius);if *state!="flanking"{assert!(goal.x<p.x,"rear must follow real threat direction");}assert_eq!(b.base.body(*id).unwrap().p,positions.iter().find(|(k,_)|k==id).unwrap().1,"planning never teleports bodies");}}
    }
    #[test]
    fn tank_infantry_physically_take_rear_cover_and_retreat_after_real_damage(){
        for unit in ["MCP-022","MCP-103","MCP-304","MCP-305"] {
        let mut b=battle();let ci=landed(&mut b,unit);b.base.auto=false;
        let vi=b.vehicles.iter().position(|v|v.company==ci).unwrap();
        let origin=b.vehicles[vi].p;
        let p=(0..200).map(|n|origin+P::bearing(n as f64*137.5)*(n as f64*3.)).find(|p|{
            (0..24).all(|n|b.base.traversable_disc(*p+P::bearing(n as f64*15.)*55.,"infantry"))
                &&b.base.traversable_disc(*p,"armor")
        }).expect("legal open tactical space");
        b.vehicles[vi].p=p;b.vehicles[vi].goal=p;b.vehicles[vi].manual=true;
        let enemy=b.base.companies.iter().find(|c|c.side==1).unwrap().bodies[0];
        b.base.body_mut(enemy).unwrap().active=true;b.base.body_mut(enemy).unwrap().p=p+P{x:150.,y:0.};
        b.base.actors.iter_mut().find(|a|a.id==enemy).unwrap().seen[0]=true;
        let ids=b.base.companies[ci].bodies.clone();
        for (n,id) in ids.iter().enumerate(){b.base.body_mut(*id).unwrap().p=p+P{x:-40.,y:(n as f64-2.5)*5.};}
        b.base.companies[ci].order="hold".into();b.base.companies[ci].path.clear();
        b.base.companies[ci].goal=p;
        let before=b.base.body(ids[5]).unwrap().p;
        for frame in 0..35 {b.base.base.core.ground.frame=frame;b.move_people_with_vehicles();}
        let after=b.base.body(ids[5]).unwrap().p;
        assert!(after.dist(before)>5.,"rear cover is reached by actual movement");
        assert!(after.x<p.x-8.&&after.dist(p)<before.dist(p));
        let body=ids[0];let flank=p+P{x:-1.,y:-10.};b.base.body_mut(body).unwrap().p=flank;
        let hp=b.base.body(body).unwrap().hp;
        let hit=ShotInfo{weapon:firearms::model("MCP-087","howitzer"),target:Some(body),operator:enemy,target_class:"unarmored".into(),hit:true,probability:1.,tracking_offset:P::default()};
        b.resolve(flank,1.,1.,1,Some(&hit),"howitzer","pressure",false,0.);
        assert!(b.base.body(body).unwrap().hp<hp);assert!(b.body_pressure[&body]>b.frame());
        for _ in 0..15 {b.base.base.core.ground.frame+=1;b.move_people_with_vehicles();}
        assert_eq!(b.tank_tactics[&body].1,"fallback");
        assert!(b.base.body(body).unwrap().p.x<flank.x-4.,"real hit sends the actual body back behind armor");
        for a in &ids {for z in &ids{if a!=z{assert!(b.base.body(*a).unwrap().p.dist(b.base.body(*z).unwrap().p)>=0.9);}}}
        }
    }
    #[test]
    fn hold_preserves_every_actual_body_center_while_own_vehicle_moves(){
        for id in ["MCP-022","MCP-103","MCP-087","MCP-027","MCP-006"] {
            let mut b=battle();let ci=landed(&mut b,id);let ids=b.base.companies[ci].bodies.clone();
            let positions=ids.iter().map(|id|(*id,b.base.body(*id).unwrap().p)).collect::<Vec<_>>();
            b.base.companies[ci].p=P{x:-123.,y:-456.}; // an invalid arithmetic center must not reject stop
            b.execute(&json!({"op":"littoral_order","company_id":b.base.companies[ci].id,"action":"hold"})).unwrap();
            let vi=b.vehicles.iter().position(|v|v.company==ci).unwrap();let old=b.vehicles[vi].p;let goal=b.base.free_spawn(old+P{x:130.,y:0.},b.vehicles[vi].class).unwrap();
            b.execute(&json!({"op":"littoral_vehicle_order","vehicle_id":b.vehicles[vi].id,"action":"move","x":goal.x,"y":goal.y})).unwrap();
            for _ in 0..30 {b.base.base.core.ground.frame+=1;b.move_people_with_vehicles();b.step_vehicles();}
            assert!(b.vehicles[vi].p.dist(old)>1.,"{id} vehicle actually moves");
            for (id,p) in positions{assert_eq!(b.base.body(id).unwrap().p,p,"{id} actual hold is independent from equipment");}
        }
    }
}
