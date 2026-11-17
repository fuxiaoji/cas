//! Original v3 role profiles and finite battlefield abilities.
use super::*;
pub(super) fn catalogue_ability(row: &mut Value, u: &Unit) {
    let (name, description, charges, cooldown, duration, radius, range) = match u.ability {
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

#[cfg(test)]
mod tests {
    use super::*;
    fn setup(id: &str) -> (Battle, usize, P) {
        let mut q: Value = serde_json::from_str(include_str!(
            "../artifacts/island-war-v2/core/exercise-terminal.json"
        ))
        .unwrap();
        let mut q = q["initial_request"].take();
        q["roster"] = json!([id]);
        q["defender"]["roster"] = json!(["MCP-006", "MCP-034"]);
        for k in ["op", "version", "seed"] {
            q.as_object_mut().unwrap().remove(k);
        }
        let mut b = Battle::new(714, q).unwrap();
        let ci = b.base.companies.iter().position(|c| c.side == 0).unwrap();
        let point = b.base.free_spawn(b.base.objective(), "infantry").unwrap();
        b.base.companies[ci].p = point;
        b.base.companies[ci].stage = "active";
        let ids = b.base.companies[ci].bodies.clone();
        for (k, id) in ids.iter().enumerate() {
            let body = b.base.body_mut(*id).unwrap();
            body.active = true;
            body.p = point
                + P {
                    x: k as f64 * 9.,
                    y: 0.,
                };
        }
        for a in &mut b.base.actors {
            a.seen = [true, true];
        }
        (b, ci, point)
    }
    #[test]
    fn four_new_profile_compositions_and_personnel_protection_are_real() {
        for (id, weapon, count) in [
            ("MCP-184", "shotgun", 2),
            ("MCP-145", "aa_missile", 2),
            ("MCP-128", "heavy_sniper", 1),
        ] {
            let (b, ci, _) = setup(id);
            let c = &b.base.companies[ci];
            assert_eq!(
                c.bodies
                    .iter()
                    .filter(|id| b.loadouts[id].weapon.family_id == weapon)
                    .count(),
                count
            );
            assert_eq!(armor_class(c.unit), "unarmored");
            assert_eq!(b.base.body(c.bodies[0]).unwrap().armor, profile(id).armor);
        }
        let (b, ci, _) = setup("MCP-203");
        assert_eq!(b.base.companies[ci].unit.speed, 95.);
        assert!(b.base.companies[ci]
            .bodies
            .iter()
            .all(|id| b.loadouts[id].weapon.family_id == "dmr"));
    }
    #[test]
    fn command_network_changes_real_movement_accuracy_and_finite_charges() {
        let (mut b, ci, p) = setup("MCP-203");
        b.base.companies[ci].path = vec![p + P { x: 100., y: 0. }];
        b.role_skill(ci, p).unwrap();
        assert_eq!(b.base.companies[ci].charges, 2);
        b.tick_roles();
        assert_eq!(b.base.companies[ci].speed_scale, 1.2);
        assert_eq!(b.spread_scale(0, p, false), 0.8);
        assert!(b.metrics.contains("command_network"));
        assert!(b.role_skill(ci, p).is_err());
        b.base.base.core.ground.frame = 141;
        b.tick_roles();
        assert_eq!(b.base.companies[ci].speed_scale, 1.);
        assert_eq!(b.spread_scale(0, p, false), 1.);
    }
    #[test]
    fn grenade_is_real_finite_projectile_and_causes_damage() {
        let (mut b, ci, p) = setup("MCP-184");
        let enemy = b
            .base
            .companies
            .iter()
            .find(|c| c.side == 1 && c.unit.class == "infantry")
            .unwrap()
            .bodies[0];
        {
            let t = b.base.body_mut(enemy).unwrap();
            t.p = p + P { x: 100., y: 0. };
            t.hp = 100.;
            t.active = true;
        }
        b.role_skill(ci, p + P { x: 100., y: 0. }).unwrap();
        assert_eq!(b.base.companies[ci].charges, 2);
        assert!(b
            .base
            .base
            .core
            .ground
            .shots
            .iter()
            .any(|s| s["weapon_family_id"] == "grenade"));
        for _ in 0..12 {
            b.projectiles();
        }
        assert!(b.base.body(enemy).unwrap().hp < 100.);
        assert!(b.metrics.contains("hit:grenade"));
    }
    #[test]
    fn turret_has_hp_ammo_real_air_damage_and_expires_without_personnel() {
        let (mut b, ci, p) = setup("MCP-145");
        let before = b.base.actors.len();
        let vi = b
            .vehicles
            .iter()
            .position(|v| b.base.companies[v.company].side == 1 && v.class == "air")
            .unwrap();
        let enemy = b.vehicles[vi].id;
        b.vehicles[vi].active = true;
        b.vehicles[vi].phase = "active";
        b.vehicles[vi].hp = 155.;
        b.vehicles[vi].p = p + P { x: 100., y: 0. };
        b.sync_vehicle_mirrors();
        {
            let t = b.base.body_mut(enemy).unwrap();
            t.p = p + P { x: 100., y: 0. };
            t.hp = 155.;
            t.active = true;
        }
        b.role_skill(ci, p).unwrap();
        assert_eq!(b.base.companies[ci].charges, 1);
        assert_eq!(b.base.actors.len(), before);
        let tid = b.aa_turrets[0].id;
        b.base.base.core.ground.frame = 10;
        b.tick_roles();
        assert_eq!(
            b.base.body(tid).unwrap().ammo,
            firearms::model("MCP-145", "aa_cannon").ammo_capacity - 1
        );
        for _ in 0..4 {
            b.projectiles();
        }
        assert!(b.vehicles[vi].hp < 155.);
        assert!(b.metrics.contains("aa_turret_hit"));
        assert!(b
            .targets(p + P { x: 50., y: 0. }, 1, weapon("rifle"))
            .iter()
            .any(|t| t.1 == tid));
        b.base.base.core.ground.frame = 450;
        b.tick_roles();
        assert_eq!(b.base.body(tid).unwrap().hp, 0.);
        assert_eq!(b.base.actors.len(), before);
    }
    #[test]
    fn support_designation_is_spatial_finite_and_has_no_free_damage() {
        let (mut b, ci, p) = setup("MCP-128");
        let before = b
            .base
            .base
            .core
            .ground
            .bodies
            .iter()
            .map(|b| b.hp)
            .collect::<Vec<_>>();
        b.role_skill(ci, p).unwrap();
        assert_eq!(b.base.companies[ci].charges, 2);
        assert_eq!(b.spread_scale(0, p, true), 0.65);
        assert_eq!(b.spread_scale(0, p, false), 1.);
        assert_eq!(b.spread_scale(0, p + P { x: 400., y: 0. }, true), 1.);
        assert_eq!(
            before,
            b.base
                .base
                .core
                .ground
                .bodies
                .iter()
                .map(|b| b.hp)
                .collect::<Vec<_>>()
        );
        assert!(!b.metrics.contains("support_designation"));
    }
    #[test]
    fn specialists_have_separate_finite_sidearm_and_plain_soldiers_do_not() {
        let (mut b, ci, _) = setup("MCP-145");
        let c = b.base.companies[ci].clone();
        assert_eq!(
            c.bodies
                .iter()
                .filter(|id| b.secondary.contains_key(id))
                .count(),
            2
        );
        let id = c.bodies[0];
        b.base.body_mut(id).unwrap().ammo = 0;
        let sidearm = &mut b.secondary.get_mut(&id).unwrap();
        sidearm.ammo = 0;
        sidearm.next = 0;
        let old = b.base.base.core.ground.shots.len();
        b.shoot();
        assert!(!b
            .base
            .base
            .core
            .ground
            .shots
            .iter()
            .skip(old)
            .any(|s| s["operator_id"] == id));
    }
    #[test]
    fn new_defaults_accept_omitted_defender_in_real_modes_and_unknown_units_reject() {
        let (mut b, _, _) = setup("MCP-034");
        let mut c = b.config.clone();
        c.as_object_mut().unwrap().remove("defender");
        c["mode"] = json!("raid");
        c["island"]["npc_id"] = json!("shoal_watch");
        assert!(Battle::new(714, c.clone()).is_ok());
        c["mode"] = json!("defense");
        assert!(Battle::new(714, c.clone()).is_ok());
        c["roster"] = json!(["no such persona"]);
        assert!(Battle::new(714, c).is_err());
        b.base.auto = false;
    }
    #[test]
    fn area_accuracy_changes_actual_near_far_damage_including_aircraft() {
        for wid in ["tank_gun", "aa_missile"] {
            let (mut b, ci, p) = setup("MCP-145");
            let carrier = b
                .base
                .base
                .core
                .naval
                .ships
                .iter()
                .find(|s| s.side == 1)
                .unwrap()
                .id;
            b.base.base.core.aircraft.push(Aircraft {
                id: 90001,
                squadron: 0,
                carrier,
                model: "test",
                role: "fighter",
                phase: "outbound",
                mission: "land",
                p,
                heading: 0.,
                hp: 10000.,
                max: 10000.,
                fuel: 10000.,
                weapons: 0,
                target: p,
                target_kind: "land".into(),
                target_id: Value::Null,
                next: 0,
                speed: 0.,
            });
            let body = b
                .base
                .companies
                .iter()
                .find(|c| c.side == 1)
                .unwrap()
                .bodies[0];
            b.base.body_mut(body).unwrap().p = p;
            b.base.body_mut(body).unwrap().hp = 10000.;
            b.base.body_mut(body).unwrap().active = true;
            let mut totals = Vec::new();
            for fraction in [0.1, 1.] {
                let mut damage = 0.;
                for _ in 0..100 {
                    b.base.base.core.ground.frame += 1;
                    let before = b.base.base.core.aircraft.last().unwrap().hp;
                    let from = p + P {
                        x: weapon(wid).range_m * fraction,
                        y: 0.,
                    };
                    let id = b.base.companies[ci].bodies[0];
                    b.launch(
                        id,
                        0,
                        from,
                        p,
                        Some(1_000_090_001),
                        "aircraft",
                        weapon(wid),
                        1.,
                        "test".into(),
                    );
                    for _ in 0..60 {
                        b.projectiles();
                    }
                    let after = b.base.base.core.aircraft.last().unwrap().hp;
                    damage += before - after;
                    b.base.base.core.aircraft.last_mut().unwrap().hp = 10000.;
                }
                totals.push(damage);
            }
            assert!(
                totals[0] > totals[1] * 1.05,
                "{} actual near/far aircraft damage {:?}",
                wid,
                totals
            );
        }
    }

    #[test]
    fn role_ai_never_promotes_one_known_body_to_its_hidden_company_members() {
        for side in [0, 1] {
            let (mut b, _, p) = setup("MCP-128");
            let ci = b
                .base
                .companies
                .iter()
                .position(|c| c.side == side)
                .unwrap();
            let enemy = b
                .base
                .companies
                .iter()
                .position(|c| c.side != side)
                .unwrap();
            b.base.companies[ci].p = p;
            let ids = b.base.companies[enemy].bodies.clone();
            for a in &mut b.base.actors {
                a.seen[side as usize] = false;
            }
            for body in &mut b.base.base.core.ground.bodies {
                body.active = false;
            }
            let near = p + P { x: 100., y: 0. };
            let far = p + P { x: 800., y: 0. };
            for (id, point) in [(ids[0], near), (ids[1], far)] {
                let body = b.base.body_mut(id).unwrap();
                body.active = true;
                body.p = point;
            }
            b.base
                .actors
                .iter_mut()
                .find(|a| a.id == ids[1])
                .unwrap()
                .seen[side as usize] = true;
            let target = b
                .role_target(ci)
                .expect("the individually known body is targetable");
            assert_eq!(target.0, enemy);
            assert!(
                target.1.dist(far) < 0.001,
                "hidden nearer body of the same company must not reveal its position"
            );
            b.base
                .actors
                .iter_mut()
                .find(|a| a.id == ids[1])
                .unwrap()
                .seen[side as usize] = false;
            assert!(
                b.role_target(ci).is_none(),
                "no known bodies means no target"
            );
            b.base
                .actors
                .iter_mut()
                .find(|a| a.id == ids[0])
                .unwrap()
                .seen[side as usize] = true;
            assert!(b.role_target(ci).unwrap().1.dist(near) < 0.001);
        }
    }

    #[test]
    fn mixed_company_range_uses_live_finite_weapon_composition() {
        let (mut b, ci, _) = setup("MCP-128");
        assert!(
            b.engagement_range(ci, "unarmored") <= 1250.,
            "five DMRs cannot be silenced by one long-range specialist"
        );
        let (mut aa, ai, _) = setup("MCP-145");
        assert!(aa.engagement_range(ai, "unarmored") < 750.);
        let (mut at, ti, _) = setup("MCP-063");
        for id in at.base.companies[ti].bodies.clone() {
            if at.loadouts[&id].weapon.family_id == "rocket" {
                at.base.body_mut(id).unwrap().ammo = 0;
            }
        }
        assert!(at.engagement_range(ti, "heavy_armor") <= 550.);
        b.base.auto = false;
        aa.base.auto = false;
    }

    #[test]
    fn direct_hit_has_one_probability_gate_and_miss_cannot_hurt_by_proximity() {
        let (mut b, ci, p) = setup("MCP-034");
        let enemy = b
            .base
            .companies
            .iter()
            .find(|c| c.side == 1 && c.unit.class == "infantry")
            .unwrap()
            .bodies[0];
        b.base.body_mut(enemy).unwrap().active = true;
        b.base.body_mut(enemy).unwrap().hp = 100.;
        let id = b.base.companies[ci].bodies[0];
        let info = ShotInfo {
            weapon: weapon("rifle"),
            target: Some(enemy),
            operator: id,
            target_class: "unarmored".into(),
            hit: true,
            probability: 0.5,
            tracking_offset: P::default(),
        };
        b.resolve(
            p + P { x: 10000., y: 0. },
            12.,
            12.,
            0,
            Some(&info),
            "rifle",
            "test",
            false,
            0.,
        );
        assert!(
            b.base.body(enemy).unwrap().hp < 100.,
            "a successful point-target roll has no second geometric hit gate"
        );
        let hp = b.base.body(enemy).unwrap().hp;
        let mut miss = info;
        miss.hit = false;
        b.resolve(
            b.base.body(enemy).unwrap().p,
            12.,
            12.,
            0,
            Some(&miss),
            "rifle",
            "test",
            false,
            0.,
        );
        assert_eq!(
            hp,
            b.base.body(enemy).unwrap().hp,
            "a miss cannot deal damage even if its visual impact is near a body"
        );
    }
    #[test]
    fn guided_aa_keeps_tracking_a_real_fast_crossing_helicopter() {
        let (mut b, ci, p) = setup("MCP-145");
        let vi = b
            .vehicles
            .iter()
            .position(|v| b.base.companies[v.company].side == 1 && v.class == "air")
            .unwrap();
        let enemy = b.vehicles[vi].id;
        b.vehicles[vi].active = true;
        b.vehicles[vi].phase = "active";
        b.vehicles[vi].hp = 155.;
        b.vehicles[vi].p = p + P { x: 100., y: 0. };
        b.sync_vehicle_mirrors();
        {
            let t = b.base.body_mut(enemy).unwrap();
            t.p = p + P { x: 900., y: 0. };
            t.hp = 155.;
            t.active = true;
        }
        let id = b.base.companies[ci].bodies[0];
        b.vehicles[vi].p = p + P { x: 900., y: 0. };
        b.sync_vehicle_mirrors();
        b.launch(
            id,
            0,
            p,
            b.vehicles[vi].p,
            Some(enemy),
            "helicopter",
            weapon("aa_missile"),
            1.,
            b.base.companies[ci].id.clone(),
        );
        for _ in 0..30 {
            b.vehicles[vi].p.y += 31.;
            b.vehicles[vi].velocity = P { x: 0., y: 310. };
            b.sync_vehicle_mirrors();
            b.projectiles();
        }
        assert!(
            b.vehicles[vi].hp < 155.,
            "a real 310m/s transverse helicopter is tracked during flight"
        );
    }

    #[test]
    fn returning_subset_does_not_freeze_a_live_on_land_straggler() {
        let (mut b, ci, p) = setup("MCP-034");
        b.base.companies[ci].stage = "returning";
        b.base.companies[ci].order = "extract".into();
        let id = b.base.companies[ci].bodies[0];
        b.base.body_mut(id).unwrap().p = p;
        b.base.actors.iter_mut().find(|a| a.id == id).unwrap().phase = "active";
        b.resume_stragglers();
        assert_eq!(b.base.companies[ci].stage, "withdrawing");
        assert_eq!(
            b.base.body(id).unwrap().p,
            p,
            "resuming never teleports a body"
        );
        for a in b.base.actors.iter_mut().filter(|a| a.company == ci) {
            a.phase = "returning";
        }
        b.base.companies[ci].stage = "returning";
        b.resume_stragglers();
        assert_eq!(
            b.base.companies[ci].stage, "returning",
            "actually boarded bodies stay aboard"
        );
    }
    #[test]
    fn combat_engineer_demolition_hits_forts_without_repair_or_free_ammunition() {
        let (mut b, ci, p) = setup("MCP-009");
        let fort = b
            .base
            .base
            .core
            .ground
            .buildings
            .iter()
            .position(|f| !f.ally)
            .unwrap();
        b.base.base.core.ground.buildings[fort].p = p + P { x: 100., y: 0. };
        let hp = b.base.base.core.ground.buildings[fort].hp;
        let target = b.base.base.core.ground.buildings[fort].p;
        let ammo = b.base.companies[ci]
            .bodies
            .iter()
            .map(|id| b.base.body(*id).unwrap().ammo)
            .sum::<u32>();
        b.role_skill(ci, target).unwrap();
        assert_eq!(b.base.companies[ci].charges, 2);
        for _ in 0..35 {
            b.projectiles();
        }
        assert!(b.base.base.core.ground.buildings[fort].hp < hp);
        assert_eq!(
            ammo,
            b.base.companies[ci]
                .bodies
                .iter()
                .map(|id| b.base.body(*id).unwrap().ammo)
                .sum::<u32>()
        );
        assert!(b.role_skill(ci, p + P { x: 5000., y: 0. }).is_err());
    }
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
