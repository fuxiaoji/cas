//! Original v3 role profiles and finite battlefield abilities.
use super::*;
pub(super) fn catalogue_ability(row: &mut Value, u: &Unit) {
    let (name, description, charges, cooldown, duration, radius, range) = match u.ability {
        "self_dressing" => ("战地自救","本连每具存活且在地面的身体立即回复25%最大HP；每连3次、冷却45秒，不能复活、不治疗其他连，满血不消耗次数。",3,45.,0.,0.,1600.),
        "at_missile" => ("专职反甲点射","消耗一次技能与2发实际库存，由存活火箭筒专职射手发射1条150基础伤害、55米范围的真实弹道；仍按甲类、精度和掩护裁决",3,20.,0.,55.,1550.),
        "barrage" => ("自行炮主动覆盖","消耗一次技能与2发炮车库存，由独立存活自行炮发射1条165基础伤害、105米范围的真实弹道；身体手枪不能替代炮车",3,20.,0.,105.,3200.),
        "air_rockets" => ("武直主动压制","消耗一次技能与2发机炮库存，存活同体武直发射1条32基础伤害、28米范围真实机炮弹道；不能凭空生成火箭弹",3,20.,0.,28.,1500.),
        "air_coordination" => ("旋翼火力协同","12秒内700米存活友军武器装填间隔×0.75；有限弹药照常消耗",3,20.,12.,700.,1600.),
        "supply_network" => ("保障协作网","12秒内700米友军弹匣换弹耗时×0.8、承伤×0.9；不生成或转移任何枪弹",3,20.,12.,700.,450.),
        "demolition" => ("战斗工兵爆破","消耗连级有限3枚炸药中的1枚，180米内真实爆破工事；结构强、重甲弱",3,21.,0.,45.,180.),
        "field_repair" => ("战地抢修","400米内共享500点有限抢修量，优先独立存活自行炮，再存活身体；每目标至多35%最大耐久，不能重造",3,20.,0.,400.,1600.),
        "command_network" => (
            "协同指挥网",
            "14秒内700米内存活友军移动×1.2、散布×0.8、真实占点速度×1.25",
            3,
            24.,
            14.,
            700.,
            450.,
        ),
        "grenade" => (
            "攻坚手雷",
            "消耗一次实际手雷；450米投掷，65米范围；人员强、重甲弱",
            3,
            18.,
            0.,
            65.,
            450.,
        ),
        "deploy_aa_turret" => (
            "展开防空炮台",
            "最多2次，实体HP240、16发弹药、1800米射程、45秒寿命，只对空",
            2,
            30.,
            45.,
            1800.,
            450.,
        ),
        "support_designation" => (
            "联合火力标定",
            "2000米内标记350米区域16秒；真实舰炮/航空散布×0.65，仍会脱靶",
            3,
            24.,
            16.,
            350.,
            2000.,
        ),
        _ => (
            ability_name_v2(u.ability),
            ability_description(u.ability),
            3,
            20.,
            if matches!(u.ability, "suppression") {
                3.5
            } else {
                12.
            },
            row["ability"]["radius"].as_f64().unwrap_or(350.),
            1600.,
        ),
    };
    let (description, radius, range) = if matches!(
        u.ability,
        "at_missile" | "barrage" | "air_rockets"
    ) {
        let f = match u.ability {
            "at_missile" => "rocket",
            "barrage" => "howitzer",
            _ => "helicopter_cannon",
        };
        let w = firearms::model(u.id, f);
        (format!("消耗1次技能与1发实际弹匣弹药，发射1条 {} 真实弹道；基础伤害{}、范围{}米、射程{}米。空匣、换弹或射击间隔未完成时不能发动",w.name,w.damage,w.blast_radius_m,w.range_m),w.blast_radius_m,w.range_m)
    } else {
        (description.to_owned(), radius, range)
    };
    let description = if u.ability == "deploy_aa_turret" {
        let w = firearms::model(u.id, "aa_cannon");
        format!("最多2次，实体HP240、{}发有限库存、{}米射程、45秒寿命，只对空；每发{}基础伤害，{}发弹匣和{}秒真实换弹",w.ammo_capacity,w.range_m,w.damage,w.cadence.magazine_capacity,w.cadence.magazine_reload_s)
    } else {
        description
    };
    row["ability"] = json!({"id":u.ability,"name":name,"description":description,"charges":charges,"cooldown":cooldown,"duration_s":duration,"radius":radius,"range":range});
    let ability_family = match u.ability {
        "at_missile" => Some("rocket"),
        "barrage" => Some("howitzer"),
        "air_rockets" => Some("helicopter_cannon"),
        "grenade" => Some("grenade"),
        "demolition" => Some("demolition_charge"),
        "deploy_aa_turret" => Some("aa_cannon"),
        _ => None,
    };
    if let Some(f) = ability_family {
        let w = firearms::model(u.id, f);
        row["ability"]["weapon_id"] = json!(w.id);
        row["ability"]["weapon_family_id"] = json!(w.family_id);
        row["ability"]["ammo_pool"] = json!(if matches!(f, "grenade" | "demolition_charge") {
            "company_throwables"
        } else if f == "aa_cannon" {
            "independent_turret"
        } else {
            "actual_weapon_magazine"
        });
    }
    row["damage_formula"] = json!({"weapons":"actual on-hit damage * weapon.multipliers[target armor_class] * actual body or independent vehicle incoming armor_multiplier * applicable terrain cover * active supply protection; area damage also has actual distance falloff","expected_direct_damage":"weapon.accuracy probability * on-hit damage; one seeded hit roll, no second point-collision probability","area_precision":"accuracy quality changes actual scatter, then real radius/positions decide affected targets; no separate hit roll","armor_multiplier_meaning":"Incoming damage multiplier for the actual body or independent vehicle; vehicles additionally use the typed weapon-vs-armor matrix","personnel_protection":u.armor});
}

#[derive(Clone)]
pub(super) struct Secondary {
    pub weapon: &'static Weapon,
    pub ammo: u32,
    pub next: u32,
}
#[derive(Clone)]
pub(super) struct Effect {
    pub id: u32,
    pub company: usize,
    pub side: u32,
    pub kind: &'static str,
    pub p: P,
    pub radius: f64,
    pub start: u32,
    pub end: u32,
}
#[derive(Clone)]
pub(super) struct AaTurret {
    pub id: u32,
    pub company: usize,
    pub expiry: u32,
}
impl Battle {
    // Current body health only; casualties never grant another body's bonus.
    pub(super) fn last_stand(&self, id:u32) -> (f64,f64) {
        if !self.loadouts.get(&id).is_some_and(|l|l.weapon.owner==Some("MCP-306")) {return (1.,1.)}
        self.base.body(id).map_or((1.,1.),|b| {
            let pressure=((1.-b.hp/b.max.max(1.))/0.75).clamp(0.,1.);
            (1.+0.35*pressure,1.+0.5*pressure)
        })
    }
    pub(super) fn incoming_scale(&self,side:u32,p:P)->f64 {
        if self.effects.iter().any(|e|e.kind=="supply_network"&&e.side==side&&e.end>self.frame()&&e.p.dist(p)<e.radius){0.9}else{1.}
    }
    // Original v3 protection around unchanged legacy damage consumers. Scale
    // the available HP pool before damage so even lethal hits use the same
    // exact multiplier; undo it before observation or death recording.
    pub(super) fn begin_legacy_protection(&mut self)->(Vec<(u32,f64)>,BTreeSet<String>) {
        let rows=self.base.base.core.ground.bodies.iter().filter(|b|b.hp>0.).filter_map(|b|{
            let scale=self.incoming_scale(if b.ally{0}else{1},b.p);
            (scale<1.).then_some((b.id,scale))
        }).collect::<Vec<_>>();
        for (id,s) in &rows {self.base.body_mut(*id).unwrap().hp/=s;}
        let impacts=self.base.base.core.ground.impacts.iter().map(|v|v["id"].to_string()).collect();
        (rows,impacts)
    }
    pub(super) fn end_legacy_protection(&mut self,(rows,prior):(Vec<(u32,f64)>,BTreeSet<String>)) {
        for (id,s) in &rows {if let Some(b)=self.base.body_mut(*id){b.hp*=s;}}
        for impact in &mut self.base.base.core.ground.impacts {
            if prior.contains(&impact["id"].to_string()){continue}
            if let Some(hits)=impact["affected_bodies"].as_array_mut(){for hit in hits {
                if let Some((_,s))=rows.iter().find(|(id,_)|hit["id"].as_u64()==Some(*id as u64)){
                    if let Some(d)=hit["damage"].as_f64(){hit["damage"]=json!(d*s);}
                    if let Some(h)=hit["hp"].as_f64(){hit["hp"]=json!(h*s);}
                }
            }}
        }
    }
    pub(super) fn advance_air_v3(&mut self) {
        // Each actual land attack receives one seeded aim error. Marking narrows
        // that error before the plane flies there; the weapon stock is unchanged.
        let ids = self
            .base
            .base
            .core
            .aircraft
            .iter()
            .filter(|a| {
                a.hp > 0.
                    && a.phase == "outbound"
                    && !matches!(a.target_kind.as_str(), "ship" | "aircraft")
                    && !self.air_adjusted.contains(&a.id)
            })
            .map(|a| {
                (
                    a.id,
                    a.target,
                    self.base
                        .base
                        .core
                        .naval
                        .ship(a.carrier)
                        .map_or(0, |s| s.side as u32),
                )
            })
            .collect::<Vec<_>>();
        for (id, aim, side) in ids {
            let spread = self.spread_scale(side, aim, true);
            let goal = aim + P::bearing((id.wrapping_mul(113) % 360) as f64) * 80. * spread;
            if let Some(a) = self.base.base.core.aircraft.iter_mut().find(|a| a.id == id) {
                a.target = goal;
            }
            self.air_adjusted.insert(id);
            if spread < 1. {
                self.designated_air.insert(id);
            }
        }
        let before = self
            .base
            .base
            .core
            .aircraft
            .iter()
            .map(|a| (a.id, a.weapons))
            .collect::<BTreeMap<_, _>>();
        let shield=self.begin_legacy_protection();
        self.base.base.core.advance_air();
        self.end_legacy_protection(shield);
        self.import_vehicle_damage();
        for a in &self.base.base.core.aircraft {
            if self.designated_air.contains(&a.id)
                && before.get(&a.id).is_some_and(|n| *n > a.weapons)
            {
                self.metrics.insert("support_designation".into());
            }
        }
    }
    pub(super) fn apply_profiles(&mut self) {
        for ci in 0..self.base.companies.len() {
            let c = self.base.companies[ci].clone();
            let p = profile(c.unit.id);
            self.base.companies[ci].unit = if p.role == "artillery" {
                &ARTILLERY_FOOT
            } else {
                p
            };
            if p.ability == "deploy_aa_turret" {
                self.base.companies[ci].charges = 2;
            }
            for (k, id) in c.bodies.iter().enumerate() {
                let (w, specialist) = loadout(p, k);
                let w = firearms::model(p.id, w);
                let b = self.base.body_mut(*id).unwrap();
                let growth = b.max
                    / if p.role == "artillery" {
                        100.
                    } else {
                        unit(p.id).unwrap().hp
                    };
                let percent = b.hp / b.max;
                b.max = p.hp * growth;
                b.hp = b.max * percent;
                b.armor = p.armor;
                b.damage = w.damage;
                b.range = w.range_m;
                b.reload = (w.reload_s * 10.) as u32;
                b.ammo = w.ammo_capacity;
                if p.class == "infantry" {
                    b.air = false;
                    b.kind = if p.role == "sniper" {
                        "sniper"
                    } else {
                        "marine"
                    };
                }
                self.loadouts.insert(
                    *id,
                    Loadout {
                        weapon: w,
                        specialist,
                        fire_scale: self.loadouts[id].fire_scale,
                    },
                );
                if p.class == "infantry" {
                    if let Some(a) = self.base.actors.iter_mut().find(|a| a.id == *id) {
                        a.offset = spread(self.base.base.core.ground.seed, ci, k, "infantry");
                        a.altitude = 0.;
                    }
                }
                if matches!(w.family_id, "rocket" | "aa_missile") {
                    self.secondary.insert(
                        *id,
                        Secondary {
                            weapon: firearms::model(p.id, "pistol"),
                            ammo: firearms::model(p.id, "pistol").ammo_capacity,
                            next: 0,
                        },
                    );
                }
            }
        }
    }
    pub(super) fn spread_scale(&self, side: u32, p: P, support: bool) -> f64 {
        self.effects
            .iter()
            .filter(|e| e.side == side && e.end > self.frame() && e.p.dist(p) < e.radius)
            .map(|e| match e.kind {
                "support_designation" if support => 0.65,
                "command_network" => 0.8,
                _ => 1.,
            })
            .fold(1., f64::min)
    }
    pub(super) fn validate_role_skill(&self, ci: usize, p: P) -> E<()> {
        if self.base.result.is_some(){return Err("行动已结束".into());}
        let c=&self.base.companies[ci];
        let frame = self.frame();
        if c.stage != "active"
            || c.charges == 0
            || frame < c.next
            || !c
                .bodies
                .iter()
                .any(|id| self.base.body(*id).is_some_and(|b| b.active && b.hp > 0.))
        {
            return Err("行动连技能未就绪".into());
        }
        let kind = c.unit.ability;
        let live = |id:&u32|self.base.body(*id).is_some_and(|b|b.active&&b.hp>0.)&&!self.last_fire.get(id).is_some_and(|f|*f==frame);
        if matches!(kind,"demolition"|"grenade"|"at_missile"|"barrage"|"air_rockets")&&self.base.base.core.ground.projectiles.len()+self.base.base.shots.len()>=512{return Err("实际弹道预算已满".into());}
        match kind {
            "self_dressing"=>{if !c.bodies.iter().any(|id|self.base.body(*id).is_some_and(|b|b.active&&b.hp>0.&&b.hp<b.max)&&!self.seated(*id)){return Err("本连没有可自救的地面伤员".into());}},
            "supply_network"=>{if !self.supply_target(ci){return Err("700米内没有可实际受益的存活友军".into());}},
            "demolition"=>{
                if !self.base.base.core.ground.buildings.iter().any(|b|b.ally!=(c.side==0)&&b.hp>0.&&b.p.dist(p)<65.){return Err("爆破目标必须是实际敌方工事".into());}
                if !c.bodies.iter().any(|id|live(id)&&self.base.body(*id).unwrap().p.dist(p)<=180.){return Err("没有在180米内就绪的真实工兵身体".into());}
            },
            "barrage"|"air_rockets"=>{
                let w=firearms::model(c.unit.id,if kind=="barrage"{"howitzer"}else{"helicopter_cannon"});
                if !self.vehicles.iter().any(|v|v.company==ci&&v.active&&v.hp>0.&&v.p.dist(p)<=w.range_m&&self.firearm_ready(v.id,w,v.ammo,v.next)){return Err("实际载具超出射程、空匣或正在换弹".into());}
            },
            "at_missile"=>{
                let w=firearms::model(c.unit.id,"rocket");
                if !c.bodies.iter().any(|id|live(id)&&self.loadouts[id].weapon.family_id=="rocket"&&self.base.body(*id).is_some_and(|b|b.p.dist(p)<=w.range_m&&self.firearm_ready(*id,w,b.ammo,b.next))){return Err("实际火箭筒射手超出射程、空匣或正在换弹".into());}
            },
            "grenade"=>{
                if c.p.dist(p)>450.||!c.bodies.iter().any(live){return Err("没有450米内就绪的投掷者".into());}
            },
            "command_network"|"deploy_aa_turret"=>{
                if c.p.dist(p)>450.{return Err("技能超出真实射程".into());}
                if kind=="deploy_aa_turret"&&!self.base.traversable_disc(p,"infantry"){return Err("炮台必须部署于合法陆地".into());}
            },
            "support_designation"=>{if c.p.dist(p)>2000.{return Err("标记超出2000米真实射程".into());}},
            _=>{if c.p.dist(p)>1600.{return Err("技能超出真实射程".into());}}
        }
        Ok(())
    }
    pub(super) fn role_skill(&mut self, ci: usize, p: P) -> E<()> {
        self.validate_role_skill(ci,p)?;
        let c=self.base.companies[ci].clone();
        let frame=self.frame();
        let kind=c.unit.ability;
        if kind == "self_dressing" {
            let ids=c.bodies.iter().copied().filter(|id|!self.seated(*id)).collect::<Vec<_>>();
            for id in ids {if let Some(b)=self.base.body_mut(id) {if b.active&&b.hp>0. {b.hp=(b.hp+b.max*0.25).min(b.max);}}}
            self.base.companies[ci].charges-=1;
            self.base.companies[ci].next=frame+450;
            self.base.base.core.ground.event("self_dressing","第6步兵团本连地面存活身体完成有限自救",c.p);
            return Ok(());
        }
        if kind == "supply_network" {
            if !self.supply_target(ci) {
                return Err("700米内没有可实际受益的存活友军".into());
            }
            let id = self.base.base.core.ground.id();
            self.effects.push(Effect {
                id,
                company: ci,
                side: c.side,
                kind: "supply_network",
                p: c.p,
                radius: 700.,
                start: frame,
                end: frame + 120,
            });
            self.base.companies[ci].charges -= 1;
            self.base.companies[ci].next = frame + 200;
            return Ok(());
        }
        if kind == "resupply" {
            if c.p.dist(p) > 1600. {
                return Err("补给目标超距".into());
            }
            let mut pool = c.reserve;
            let before = pool;
            let ids = self
                .base
                .actors
                .iter()
                .filter(|a| self.base.companies[a.company].side == c.side)
                .filter_map(|a| {
                    self.base
                        .body(a.id)
                        .filter(|b| b.active && b.hp > 0. && b.p.dist(p) < 450.)
                        .map(|_| a.id)
                })
                .collect::<Vec<_>>();
            for id in ids {
                let cap = self.loadouts[&id].weapon.ammo_capacity;
                let b = self.base.body_mut(id).unwrap();
                let n = cap.saturating_sub(b.ammo).min(pool);
                b.ammo += n;
                pool -= n;
                if let Some(s) = self.secondary.get_mut(&id) {
                    let n = s.weapon.ammo_capacity.saturating_sub(s.ammo).min(pool);
                    s.ammo += n;
                    pool -= n;
                }
            }
            for v in &mut self.vehicles {
                if v.active
                    && v.hp > 0.
                    && self.base.companies[v.company].side == c.side
                    && v.p.dist(p) < 450.
                {
                    let cap = firearms::model(self.base.companies[v.company].unit.id, "howitzer")
                        .ammo_capacity;
                    let n = cap.saturating_sub(v.ammo).min(pool);
                    v.ammo += n;
                    pool -= n;
                }
            }
            if pool == before {
                return Err("无可补给目标或实际库存不足".into());
            }
            self.base.companies[ci].reserve = pool;
            self.base.companies[ci].charges -= 1;
            self.base.companies[ci].next = frame + 200;
            self.tick_firearms();
            return Ok(());
        }
        if kind == "field_repair" {
            if c.p.dist(p) > 1600. {
                return Err("repair out of range".into());
            }
            let mut pool = 500. * c.support_scale;
            for v in &mut self.vehicles {
                if self.base.companies[v.company].side == c.side
                    && v.active
                    && v.hp > 0.
                    && v.p.dist(p) < 400.
                {
                    let amount = (v.max - v.hp).min(v.max * 0.35).min(pool);
                    v.hp += amount;
                    pool -= amount;
                }
            }
            for b in &mut self.base.base.core.ground.bodies {
                if b.ally == (c.side == 0) && b.active && b.hp > 0. && b.p.dist(p) < 400. {
                    let amount = (b.max - b.hp).min(b.max * 0.35).min(pool);
                    b.hp += amount;
                    pool -= amount;
                }
            }
            self.base.companies[ci].charges -= 1;
            self.base.companies[ci].next = frame + 200;
            return Ok(());
        }
        if kind == "demolition" {
            let w = firearms::model(c.unit.id, "demolition_charge");
            if !self
                .base
                .base
                .core
                .ground
                .buildings
                .iter()
                .any(|b| b.ally != (c.side == 0) && b.hp > 0. && b.p.dist(p) < 65.)
            {
                return Err("爆破目标必须是实际敌方工事".into());
            }
            let id = c
                .bodies
                .iter()
                .copied()
                .find(|id| {
                    self.base
                        .body(*id)
                        .is_some_and(|b| b.active && b.hp > 0. && b.p.dist(p) <= w.range_m)
                        && !self.last_fire.get(id).is_some_and(|f| *f == frame)
                })
                .ok_or("没有在180米内就绪的真实工兵身体")?;
            let from = self.base.body(id).unwrap().p;
            if !self.launch(
                id,
                c.side,
                from,
                p,
                None,
                "light_armor",
                w,
                1.,
                c.id.clone(),
            ) {
                return Err("弹道预算已满".into());
            }
            self.last_fire.insert(id, frame);
            self.base.companies[ci].charges -= 1;
            self.base.companies[ci].next = frame + 210;
            return Ok(());
        }
        if matches!(kind, "at_missile" | "barrage" | "air_rockets") {
            let weapon_id = match kind {
                "at_missile" => "rocket",
                "barrage" => "howitzer",
                _ => "helicopter_cannon",
            };
            let w = firearms::model(c.unit.id, weapon_id);
            if kind=="at_missile"&&!c.bodies.iter().any(|id|self.loadouts[id].weapon.family_id=="rocket"&&self.base.body(*id).is_some_and(|b|b.active&&b.hp>0.&&b.p.dist(p)<=w.range_m)){return Err("超出实际射手射程".into());}
            if matches!(kind, "barrage" | "air_rockets") {
                let index = self
                    .vehicles
                    .iter()
                    .position(|v| {
                        v.company == ci
                            && v.active
                            && v.hp > 0. && v.p.dist(p)<=w.range_m
                            && self.firearm_ready(v.id, w, v.ammo, v.next)
                    })
                    .ok_or("自行炮没有可用炮弹")?;
                let v = self.vehicles[index].clone();
                if !self.launch(v.id, c.side, v.p, p, None, "unarmored", w, 1., c.id.clone()) {
                    return Err("实际弹道预算已满".into());
                }
                self.consume_shot(v.id, w, 1.);
            } else {
                let id = c
                    .bodies
                    .iter()
                    .copied()
                    .find(|id| {
                        self.loadouts[id].weapon.family_id == weapon_id
                            && self.base.body(*id).is_some_and(|b| {
                                b.active && b.hp > 0. && self.firearm_ready(*id, w, b.ammo, b.next)
                            })
                    })
                    .ok_or("专职射手没有实际弹药")?;
                let from = self.base.body(id).unwrap().p;
                if !self.launch(id, c.side, from, p, None, "unarmored", w, 1., c.id.clone()) {
                    return Err("实际弹道预算已满".into());
                }
                self.consume_shot(id, w, 1.);
            }
            self.base.companies[ci].charges -= 1;
            self.base.companies[ci].next = frame + 200;
            return Ok(());
        }
        if !matches!(
            kind,
            "command_network" | "grenade" | "deploy_aa_turret" | "support_designation"
        ) {
            return self.base.ability(ci, p);
        }
        let range = if kind == "support_designation" {
            2000.
        } else {
            450.
        };
        if c.p.dist(p) > range {
            return Err("技能超出真实射程".into());
        }
        match kind {
            "command_network" => {
                let id = self.base.base.core.ground.id();
                self.effects.push(Effect {
                    id,
                    company: ci,
                    side: c.side,
                    kind: "command_network",
                    p: c.p,
                    radius: 700.,
                    start: frame,
                    end: frame + 140,
                });
                self.base.companies[ci].next = frame + 240;
            }
            "support_designation" => {
                let id = self.base.base.core.ground.id();
                self.effects.push(Effect {
                    id,
                    company: ci,
                    side: c.side,
                    kind: "support_designation",
                    p,
                    radius: 350.,
                    start: frame,
                    end: frame + 160,
                });
                self.base.companies[ci].next = frame + 240;
            }
            "grenade" => {
                if !self.launch(
                    *c.bodies
                        .iter()
                        .find(|id| {
                            self.base.body(**id).is_some_and(|b| b.active && b.hp > 0.)
                                && !self.last_fire.get(id).is_some_and(|f| *f == frame)
                        })
                        .ok_or("所有投掷者本帧已射击")?,
                    c.side,
                    c.p,
                    p,
                    None,
                    "unarmored",
                    firearms::model(c.unit.id, "grenade"),
                    1.,
                    c.id.clone(),
                ) {
                    return Err("实际弹道预算已满".into());
                }
                let operator = self.shots.values().last().map(|s| s.operator);
                if let Some(id) = operator {
                    self.last_fire.insert(id, frame);
                }
                self.base.companies[ci].next = frame + 180;
            }
            "deploy_aa_turret" => {
                if !self.base.traversable_disc(p, "infantry") {
                    return Err("炮台必须部署于合法陆地".into());
                }
                let id = self.base.base.core.ground.id();
                self.base.base.core.ground.bodies.push(Body {
                    id,
                    group: format!("aa-turret:{}", c.id),
                    ally: c.side == 0,
                    kind: "aa_turret",
                    p,
                    hp: 240.,
                    max: 240.,
                    ammo: firearms::model(c.unit.id, "aa_cannon").ammo_capacity,
                    damage: firearms::model(c.unit.id, "aa_cannon").damage,
                    range: 1800.,
                    reload: 10,
                    next: frame + 10,
                    armor: 0.7,
                    air: false,
                    active: true,
                });
                self.aa_turrets.push(AaTurret {
                    id,
                    company: ci,
                    expiry: frame + 450,
                });
                self.base.companies[ci].next = frame + 300;
            }
            _ => unreachable!(),
        }
        self.base.companies[ci].charges -= 1;
        self.base
            .base
            .core
            .ground
            .event(kind, "行动连已消耗有限技能次数", p);
        Ok(())
    }
    pub(super) fn role_target(&self, ci: usize) -> Option<(usize, P, bool)> {
        let c = &self.base.companies[ci];
        let mut targets = self
            .base
            .actors
            .iter()
            .filter(|a| self.base.companies[a.company].side != c.side && self.known(a.id, c.side))
            .filter_map(|a| {
                self.base
                    .body(a.id)
                    .filter(|b| b.active && b.hp > 0.)
                    .map(|b| (a.company, b.p, b.air))
            })
            .collect::<Vec<_>>();
        targets.extend(
            self.vehicles
                .iter()
                .filter(|v| {
                    self.base.companies[v.company].side != c.side
                        && v.active
                        && v.hp > 0.
                        && self.vehicle_known(v.id, c.side)
                })
                .map(|v| (v.company, v.p, v.class == "air")),
        );
        targets
            .into_iter()
            .min_by(|a, b| c.p.dist(a.1).total_cmp(&c.p.dist(b.1)))
    }
    pub(super) fn supply_target(&self, ci: usize) -> bool {
        let c = &self.base.companies[ci];
        self.base.actors.iter().any(|a| {
            a.company != ci
                && self.base.companies[a.company].side == c.side
                && self
                    .base
                    .body(a.id)
                    .is_some_and(|b| b.active && b.hp > 0. && b.ammo > 0 && b.p.dist(c.p) < 700.)
        }) || self.vehicles.iter().any(|v| {
            self.base.companies[v.company].side == c.side
                && v.hp > 0.
                && v.active
                && v.ammo > 0
                && v.p.dist(c.p) < 700.
        })
    }
    pub(super) fn roles_ai(&mut self) {
        let frame = self.frame();
        if frame % 40 != 0 {
            return;
        }
        let objective = self.base.objective();
        for ci in 0..self.base.companies.len() {
            let c = self.base.companies[ci].clone();
            if c.side == 0 && !self.base.auto || c.stage != "active" {
                continue;
            }
            let target = self.role_target(ci);
            if c.next <= frame && c.charges > 0 {
                let p = match c.unit.ability {
                    "self_dressing" => c.bodies.iter().any(|id|self.base.body(*id).is_some_and(|b|b.active&&b.hp>0.&&b.hp/b.max<=0.5)&&!self.seated(*id)).then_some(c.p),
                    "field_repair" => self
                        .vehicles
                        .iter()
                        .filter(|v| {
                            v.active
                                && v.hp > 0.
                                && v.hp < v.max
                                && self.base.companies[v.company].side == c.side
                                && v.p.dist(c.p) < 1600.
                        })
                        .min_by(|a, b| a.p.dist(c.p).total_cmp(&b.p.dist(c.p)))
                        .map(|v| v.p)
                        .or_else(|| {
                            self.base
                                .base
                                .core
                                .ground
                                .bodies
                                .iter()
                                .find(|b| {
                                    b.ally == (c.side == 0)
                                        && b.active
                                        && b.hp > 0.
                                        && b.hp < b.max
                                        && b.p.dist(c.p) < 400.
                                })
                                .map(|b| b.p)
                        }),
                    "command_network" => Some(c.p),
                    "supply_network" => self.supply_target(ci).then_some(c.p),
                    "demolition" => self
                        .base
                        .base
                        .core
                        .ground
                        .buildings
                        .iter()
                        .filter(|b| b.ally != (c.side == 0) && b.hp > 0. && b.p.dist(c.p) < 180.)
                        .min_by(|a, b| a.p.dist(c.p).total_cmp(&b.p.dist(c.p)))
                        .map(|b| b.p),
                    "deploy_aa_turret" => target
                        .filter(|(_, p, air)| *air && p.dist(c.p) < 2400.)
                        .map(|_| c.p),
                    "grenade" => target
                        .filter(|(_, p, air)| !*air && p.dist(c.p) < 450.)
                        .map(|(_, p, _)| p)
                        .or_else(|| {
                            self.base
                                .base
                                .core
                                .ground
                                .buildings
                                .iter()
                                .filter(|b| {
                                    b.ally != (c.side == 0) && b.hp > 0. && b.p.dist(c.p) < 450.
                                })
                                .min_by(|a, b| a.p.dist(c.p).total_cmp(&b.p.dist(c.p)))
                                .map(|b| b.p)
                        }),
                    "support_designation" => target
                        .filter(|(_, p, _)| p.dist(c.p) < 2000.)
                        .map(|(_, p, _)| p)
                        .or_else(|| (c.p.dist(objective) < 2000.).then_some(objective)),
                    "at_missile" => target
                        .filter(|(j, p, _)| {
                            matches!(self.base.companies[*j].unit.class, "armor" | "amphibious")
                                && c.p.dist(*p) < 1550.
                        })
                        .map(|(_, p, _)| p),
                    "barrage" => target
                        .filter(|(_, p, air)| !*air && c.p.dist(*p) < 3200.)
                        .map(|(_, p, _)| p),
                    "air_rockets" => target
                        .filter(|(_, p, air)| !*air && c.p.dist(*p) < 1500.)
                        .map(|(_, p, _)| p),
                    _ => None,
                };
                if let Some(p) = p {
                    let _ = self.role_skill(ci, p);
                }
            }
            if self.primary_reloading(ci)
                && target.is_some()
                && c.order != "extract"
                && !self.base.land_complete()
                && self.base.posture != "withdraw"
            {
                let _ = self.base.set_goal(ci, c.p, "reload_hold");
                continue;
            }
            if !matches!(
                c.unit.role,
                "medic" | "engineer" | "logistics" | "rescue" | "command" | "artillery"
            ) && c.order != "extract"
                && !self.base.land_complete()
                && self.base.posture != "withdraw"
            {
                if let Some((j, p, _)) = target {
                    let effective =
                        self.engagement_range(ci, armor_class(self.base.companies[j].unit));
                    let distance = c.p.dist(p);
                    if distance > effective * 1.15 && distance < 3000. {
                        let goal = p + (c.p - p).unit() * effective;
                        let _ = self.base.set_goal(ci, goal, "attack");
                    } else if matches!(c.unit.role, "sniper" | "recon")
                        && distance < effective * 0.5
                    {
                        let goal = p + (c.p - p).unit() * effective;
                        let _ = self.base.set_goal(ci, goal, "screen");
                    } else if distance > effective * 0.8 && distance < effective * 1.15 {
                        let _ = self.base.set_goal(ci, c.p, "hold");
                    }
                }
            }
            if c.unit.ability == "grenade" && c.charges > 0 && c.order != "extract" {
                if let Some((_, p, false)) = target {
                    if c.p.dist(p) > 300. && c.p.dist(p) < 1500. {
                        let goal = p + (c.p - p).unit() * 220.;
                        let _ = self.base.set_goal(ci, goal, "attack");
                    }
                }
            }
            // Role spacing changes real destinations; no render-side fake formation.
            if self.base.land_complete() || self.base.posture == "withdraw" || c.order == "extract"
            {
                continue;
            }
            if c.unit.ability == "demolition" && c.charges > 0 {
                if let Some(p) = self
                    .base
                    .base
                    .core
                    .ground
                    .buildings
                    .iter()
                    .filter(|b| b.ally != (c.side == 0) && b.hp > 0.)
                    .min_by(|a, b| a.p.dist(c.p).total_cmp(&b.p.dist(c.p)))
                    .map(|b| b.p)
                {
                    let goal = p + (c.p - p).unit() * 120.;
                    let _ = self.base.set_goal(ci, goal, "demolition");
                }
                continue;
            }
            if matches!(
                c.unit.role,
                "medic" | "engineer" | "logistics" | "rescue" | "command"
            ) {
                if let Some(front) = self
                    .base
                    .companies
                    .iter()
                    .filter(|f| {
                        f.side == c.side
                            && f.stage == "active"
                            && f.id != c.id
                            && !matches!(f.unit.role, "medic" | "logistics" | "command" | "rescue")
                    })
                    .min_by(|a, b| a.p.dist(c.p).total_cmp(&b.p.dist(c.p)))
                {
                    let goal = front.p + (c.p - front.p).unit() * 140.;
                    if c.p.dist(goal) > 240. {
                        let _ = self.base.set_goal(ci, goal, "support");
                    }
                }
            } else if c.unit.role == "artillery" {
                if let Some((_, p, air)) = target {
                    if !air {
                        let standoff = if c.unit.role == "artillery" {
                            1100.
                        } else {
                            800.
                        };
                        if c.p.dist(p) < standoff * 0.75 {
                            let goal = p + (c.p - p).unit() * standoff;
                            let _ = self.base.set_goal(ci, goal, "screen");
                        }
                    }
                }
            }
        }
        // A loaded boat must meet a real carrier. Keep those carriers on their
        // explicit rendezvous routes instead of inheriting a prior naval AI chase.
        let mut reserved = BTreeSet::new();
        for ci in 0..self.base.companies.len() {
            let c = self.base.companies[ci].clone();
            if (c.side == 0 && !self.base.auto)
                || !matches!(c.stage, "withdrawing" | "returning")
                || !reserved.insert(c.carrier)
            {
                continue;
            }
            let Ok((sea, _)) = self.base.base.geometry.beach(c.beach) else {
                continue;
            };
            if let Some(ship) = self.base.base.core.naval.ship(c.carrier) {
                let distance = ship.p.dist(sea);
                let fleet = ship.fleet;
                if distance > 650. {
                    let needs_route = fleet
                        .and_then(|id| self.base.base.core.naval.fleet(id))
                        .is_none_or(|f| {
                            f.ai.mode != "manual"
                                || f.points.last().is_none_or(|p| p.dist(sea) > 10.)
                        });
                    if needs_route {
                        let _ = self.base.route_carrier(ci, sea);
                    }
                } else if let Some(fleet) = fleet {
                    if let Some(f) = self.base.base.core.naval.fleet_mut(fleet) {
                        f.ai = crate::model::Ai::new("coord", "manual");
                        f.points.clear();
                        f.speed = 0.;
                    }
                }
            }
        }
    }
    pub(super) fn tick_roles(&mut self) {
        let frame = self.frame();
        let alive = self
            .base
            .companies
            .iter()
            .enumerate()
            .filter(|(_, c)| {
                c.bodies
                    .iter()
                    .any(|id| self.base.body(*id).is_some_and(|b| b.active && b.hp > 0.))
            })
            .map(|(i, _)| i)
            .collect::<BTreeSet<_>>();
        self.effects
            .retain(|e| e.end > frame && alive.contains(&e.company));
        for ci in 0..self.base.companies.len() {
            let c = self.base.companies[ci].clone();
            let buff = self.effects.iter().any(|e| {
                e.kind == "command_network"
                    && e.side == c.side
                    && e.end > frame
                    && e.p.dist(c.p) < e.radius
            });
            self.base.companies[ci].speed_scale = if buff { 1.2 } else { 1. };
            if buff && c.path.len() > 0 && c.side == 0 {
                self.metrics.insert("command_network".into());
            }
        }
        let deploy=(0..self.base.companies.len()).filter(|&ci|{let c=&self.base.companies[ci];(c.side!=0||self.base.auto)&&c.stage=="active"&&c.unit.ability=="deploy_aa_turret"&&c.charges>0&&c.next<=frame&&self.vehicles.iter().any(|v|v.active&&v.hp>0.&&v.class=="air"&&self.base.companies[v.company].side!=c.side&&self.vehicle_known(v.id,c.side)&&v.p.dist(c.p)<1800.)}).collect::<Vec<_>>();for ci in deploy{let p=self.base.companies[ci].p;let _=self.role_skill(ci,p);}
        let mut fires = vec![];
        for turret in &self.aa_turrets {
            let Some(b) = self.base.body(turret.id) else {
                continue;
            };
            let c = &self.base.companies[turret.company];
            if frame >= turret.expiry || b.hp <= 0. || b.ammo == 0 || b.next > frame {
                continue;
            }
            let w = firearms::model(c.unit.id, "aa_cannon");
            if !self.firearm_ready(turret.id, w, b.ammo, b.next) {
                continue;
            }
            if let Some((_, id, p, class)) = self
                .targets(b.p, c.side, w)
                .into_iter()
                .filter(|(_, _, _, kind)| {
                    matches!(*kind, "aircraft" | "helicopter" | "parachuting")
                })
                .next()
            {
                fires.push((turret.id, c.side, b.p, p, id, class, c.id.clone()));
            }
        }
        for (id, side, p, goal, target, class, source) in fires {
            if self.launch(
                id,
                side,
                p,
                goal,
                Some(target),
                class,
                firearms::model(
                    self.base.companies
                        [self.aa_turrets.iter().find(|t| t.id == id).unwrap().company]
                        .unit
                        .id,
                    "aa_cannon",
                ),
                1.,
                source,
            ) {
                let ci = self.aa_turrets.iter().find(|t| t.id == id).unwrap().company;
                self.consume_shot(
                    id,
                    firearms::model(self.base.companies[ci].unit.id, "aa_cannon"),
                    1.,
                );
            }
        }
        for turret in &self.aa_turrets {
            if frame >= turret.expiry {
                if let Some(b) = self.base.body_mut(turret.id) {
                    b.active = false;
                    b.hp = 0.;
                }
            }
        }
    }
    pub(super) fn roles_view(&self, v: &mut Value) {
        let frame = self.frame();
        let effects=self.effects.iter().filter(|e|e.end>frame).map(|e|json!({"id":e.id,"kind":e.kind,"source_company":self.base.companies[e.company].id,"side":if e.side==0{"allies"}else{"axis"},"x":e.p.x,"y":e.p.y,"radius_m":e.radius,"start_tick":e.start as f64/10.,"duration_s":(e.end-e.start)as f64/10.,"remaining_s":e.end.saturating_sub(frame)as f64/10.,"move_multiplier":if e.kind=="command_network"{1.2}else{1.},"accuracy_spread_multiplier":if e.kind=="command_network"{0.8}else if e.kind=="support_designation"{0.65}else{1.},"task_rate_multiplier":if e.kind=="command_network"{1.25}else{1.},"magazine_reload_multiplier":if e.kind=="supply_network"{0.8}else{1.},"incoming_damage_multiplier":if e.kind=="supply_network"{0.9}else{1.}})).collect::<Vec<_>>();
        v["littoral"]["land"]["effects"] = json!(effects);
        for t in &self.aa_turrets {
            if let Some(b) = self.base.body(t.id) {
                let c = &self.base.companies[t.company];
                let w = firearms::model(c.unit.id, "aa_cannon");
                let mut row = json!({"id":t.id,"kind":"aa_turret","source_company":c.id,"side":if c.side==0{"allies"}else{"axis"},"x":b.p.x,"y":b.p.y,"hp":b.hp,"max_hp":b.max,"ammo":b.ammo,"range_m":1800.,"weapon_id":"aa_cannon","expiry":t.expiry as f64/10.,"remaining_seconds":t.expiry.saturating_sub(frame)as f64/10.,"active":b.active&&b.hp>0.&&frame<t.expiry});
                row["weapon_id"] = json!(w.id);
                row["weapon_family_id"] = json!(w.family_id);
                row["weapon"] = accuracy::compact(w);
                row.as_object_mut().unwrap().extend(
                    self.firearm_view(t.id, w, b.ammo, b.next)
                        .as_object()
                        .unwrap()
                        .clone(),
                );
                v["littoral"]["land"]["deployables"]
                    .as_array_mut()
                    .unwrap()
                    .push(row.clone());
                v["island_war"]["deployables"]
                    .as_array_mut()
                    .unwrap()
                    .push(row);
            }
        }
        for row in v["littoral"]["land"]["entities"].as_array_mut().unwrap() {
            if let Some(id) = row["id"].as_u64() {
                if let Some(s) = self.secondary.get(&(id as u32)) {
                    row["secondary"] = json!({"weapon_id":s.weapon.id,"weapon_family_id":s.weapon.family_id,"weapon":accuracy::compact(s.weapon),"ammo":s.ammo});
                    row["secondary"].as_object_mut().unwrap().extend(
                        self.firearm_view(id as u32, s.weapon, s.ammo, s.next)
                            .as_object()
                            .unwrap()
                            .clone(),
                    );
                }
            }
        }
    }
}
