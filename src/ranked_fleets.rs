use crate::{model::*, realtime, world::World};
use serde_json::{json, Map, Value};
use std::{collections::BTreeSet, sync::OnceLock};

const POINTS_VERSION: &str = "cas-points-surface-v1";
pub(crate) const VARIANT: &str = "personal-duel";

struct Profile {
    id: &'static str,
    source_class: &'static str,
    name: &'static str,
    source: &'static str,
}

const PROFILES: &[Profile] = &[
    Profile {
        id: "IBS-U-USN-FLETCHER",
        source_class: "fletcher",
        name: "弗莱彻",
        source: "序章时期包／弗莱彻舰表与具名 Form 10",
    },
    Profile {
        id: "IBS-U-USN-PERKINS",
        source_class: "IBS-U-USN-PERKINS",
        name: "帕金斯",
        source: "序章时期包／马汉级与帕金斯 Form 10",
    },
    Profile {
        id: "IBS-U-USN-MAURY",
        source_class: "IBS-U-USN-MAURY",
        name: "莫里",
        source: "序章时期包／格里德利级与莫里 Form 10",
    },
    Profile {
        id: "IBS-U-USN-DRAYTON",
        source_class: "IBS-U-USN-DRAYTON",
        name: "德雷顿",
        source: "序章时期包／马汉级与德雷顿 Form 10",
    },
    Profile {
        id: "IBS-U-USN-LAMSON",
        source_class: "IBS-U-USN-LAMSON",
        name: "拉姆森",
        source: "序章时期包／马汉级与拉姆森 Form 10",
    },
    Profile {
        id: "IBS-U-IJN-KAGERO",
        source_class: "kagero",
        name: "阳炎",
        source: "首发时期包／日本舰表 PDF 28、97、108",
    },
    Profile {
        id: "IBS-U-IJN-SENDAI",
        source_class: "sendai",
        name: "川内",
        source: "首发时期包／日本舰表 PDF 21–22、97、108",
    },
    Profile {
        id: "IBS-U-USN-UNNAMED-T01-R03",
        source_class: "north-carolina",
        name: "北卡罗来纳",
        source: "序章时期包／美国舰表 PDF 8、109",
    },
    Profile {
        id: "IBS-U-USN-WASHINGTON",
        source_class: "north-carolina",
        name: "华盛顿",
        source: "序章时期包／美国舰表 PDF 8、109",
    },
    Profile {
        id: "IBS-U-IJN-ERMA-YAMATO",
        source_class: "yamato",
        name: "大和",
        source: "序章时期包／日本舰表 PDF 7、98",
    },
    // Two more Fletchers/Mahans cannot be invented from a class card; these
    // catalog identities reuse the exact same-class prologue card and are
    // labelled here so the 3000-point escort rule can field six destroyers.
    Profile {
        id: "IBS-U-USN-UNNAMED-T01-R51",
        source_class: "IBS-U-USN-PERKINS",
        name: "邓拉普",
        source: "马汉级同型卡／帕金斯 Form 10（1942 年配置）",
    },
    Profile {
        id: "IBS-U-USN-UNNAMED-T01-R52",
        source_class: "IBS-U-USN-MAURY",
        name: "格里德利",
        source: "格里德利级同型卡／莫里 Form 10（1942 年配置）",
    },
    Profile {
        id: "IBS-U-IJN-SHIRATSUYU",
        source_class: "shiratsuyu",
        name: "白露",
        source: "首发时期包／日本舰表 A-25–A-26、C-1、F-1",
    },
    Profile {
        id: "IBS-U-IJN-YUGUMO",
        source_class: "yugumo",
        name: "夕云",
        source: "首发时期包／日本舰表 A-24、C-1、F-1",
    },
    Profile {
        id: "IBS-U-IJN-AKIZUKI",
        source_class: "akizuki",
        name: "秋月",
        source: "首发时期包／日本舰表 A-24、C-1、F-1",
    },
    Profile {
        id: "IBS-U-IJN-FUBUKI",
        source_class: "fubuki_1936_refit",
        name: "吹雪",
        source: "首发时期包／改装吹雪级 A-27、C-1、F-1",
    },
    Profile {
        id: "IBS-U-IJN-HATSUYUKI",
        source_class: "fubuki_1936_refit",
        name: "初雪",
        source: "首发时期包／改装吹雪级 A-27、C-1、F-1",
    },
];

pub(crate) fn class_for(id: &str) -> &str {
    source_class(id).unwrap_or(id)
}

pub(crate) fn ship_points(ship: &ShipDef) -> u32 {
    point_value(ship)
}

pub(crate) fn options(side: usize) -> E<Value> {
    let side_name = if side == 0 { "allies" } else { "axis" };
    let rows = data()?.ships.iter().filter(|ship| ship.side == side_name).map(|ship| {
        json!({"id":ship.id, "class":class_for(&ship.id), "name":ship.name,
               "kind":ship.kind, "points":point_value(ship)})
    }).collect::<Vec<_>>();
    Ok(json!(rows))
}

pub(crate) fn source_class(id: &str) -> Option<&'static str> {
    PROFILES
        .iter()
        .find(|profile| profile.id == id && profile.source_class != id)
        .map(|profile| profile.source_class)
}

fn data() -> E<&'static Data> {
    static DATA: OnceLock<Result<Data, String>> = OnceLock::new();
    DATA.get_or_init(|| {
        let reference = crate::prologue::data()?;
        let ships = PROFILES
            .iter()
            .map(|profile| {
                let mut ship = reference
                    .ships
                    .iter()
                    .find(|ship| ship.id == profile.source_class)
                    .cloned()
                    .ok_or_else(|| format!("{} 的时期舰卡尚未加载", profile.name))?;
                ship.id = profile.id.into();
                ship.name = profile.name.into();
                Ok(ship)
            })
            .collect::<E<_>>()?;
        Ok(Data {
            ships,
            rules: reference.rules.clone(),
        })
    })
    .as_ref()
    .map_err(Clone::clone)
}

// Economy units derived from the fields of the actual frozen surface combat fit.
// These coefficients belong to CAS RTS multiplayer, not to the printed rulebook.
fn point_value(ship: &ShipDef) -> u32 {
    let average_gun_damage = ship.gun.damage.iter().sum::<f64>() / ship.gun.damage.len() as f64;
    let torpedo = ship
        .torpedo
        .as_ref()
        .map_or(0., |t| 0.12 * f64::from(t.tubes) * t.warhead);
    let raw = 1.5 * ship.dp
        + 5. * ship.max_knots
        + 2. * f64::from(ship.gun.barrels) * average_gun_damage
        + torpedo
        + 5. * (ship.armor_belt + ship.armor_deck)
        + 0.8 * ship.torpedo_protection_dp;
    // Balance targets: a 3000-point escort action must fit six destroyers,
    // while a 10000-point action must fit a battleship and escorts.
    let scale = match ship.kind.as_str() {
        "DD" => 0.75,
        "CL" => 0.85,
        "CA" => 1.0,
        "BB" => 1.2,
        _ => 1.0,
    };
    ((raw * scale / 25.).round() as u32) * 25
}

pub(crate) fn catalogue() -> E<Value> {
    let ships: Map<String, Value> = data()?
        .ships
        .iter()
        .zip(PROFILES)
        .map(|(ship, profile)| {
            (
                profile.id.into(),
                json!({"profile_id":format!("cas-prologue-runtime-v1#{}", profile.source_class),
            "points":point_value(ship),"source":profile.source}),
            )
        })
        .collect();
    Ok(
        json!({"schema_version":1,"version":POINTS_VERSION,"rules_version":realtime::VERSION,
        "enabled_budgets":[3000,10000],"ships":ships}),
    )
}

fn roster(data: &Data, config: &RankedFleet, budget: u32) -> E<Vec<usize>> {
    let ship_ids = &config.ship_ids;
    let count = ship_ids.len();
    let max = if budget == 3000 { 6 } else { 8 };
    if !(3..=max).contains(&count) || ship_ids.iter().collect::<BTreeSet<_>>().len() != count {
        return Err("编队数量不符或有重复舰船".into());
    }
    let leader = ship_ids
        .iter()
        .position(|id| id == &config.leader_id)
        .ok_or("领舰不属于当前编队")?;
    let mut ships = ship_ids
        .iter()
        .map(|id| {
            data.ships
                .iter()
                .position(|ship| ship.id == *id)
                .ok_or_else(|| format!("尚未核准舰船 {id} 的 CAS 出战舰卡"))
        })
        .collect::<E<Vec<_>>>()?;
    let defs: Vec<_> = ships.iter().map(|index| &data.ships[*index]).collect();
    if defs.iter().any(|ship| ship.side != defs[0].side) {
        return Err("同一编队的舰船必须属于同一舰籍阵营".into());
    }
    let (mut dd, mut cruisers, mut bb) = (0, 0, 0);
    for ship in &defs {
        match ship.kind.as_str() {
            "DD" => dd += 1,
            "CL" | "CA" => cruisers += 1,
            "BB" => bb += 1,
            _ => return Err("该舰种不允许编入此对局".into()),
        }
    }
    let valid = if budget == 3000 {
        bb == 0 && dd >= 2 && cruisers <= 2
    } else {
        (1..=2).contains(&bb) && dd <= 4 && dd + cruisers >= 2
    };
    if !valid {
        return Err("编成不符合所选分档".into());
    }
    if defs.iter().map(|ship| point_value(ship)).sum::<u32>() > budget {
        return Err("编队超过所选分档的点数上限".into());
    }
    let index = ships.remove(leader);
    ships.insert(0, index);
    Ok(ships)
}

fn doctrine(id: &str) -> E<&'static str> {
    match id {
        "adaptive" | "rc_coordinated" | "coord" => Ok("coord"),
        "gunnery" => Ok("gunnery"),
        "torpedo" => Ok("torpedo"),
        _ => Err("该账号指挥官尚无对应 CAS 策略".into()),
    }
}

impl World {
    pub(crate) fn new_ranked_duel(seed: u32, config: RankedFleetMatch) -> E<Self> {
        let budget = config.budget;
        if !matches!(budget, 3000 | 10000) || config.points_version != POINTS_VERSION {
            return Err("个人舰队分档或点表版本无效".into());
        }
        let data = data()?;
        let allies = roster(data, &config.fleets.allies, budget)?;
        let axis = roster(data, &config.fleets.axis, budget)?;
        let profiles = [
            doctrine(&config.fleets.allies.ai_profile)?,
            doctrine(&config.fleets.axis.ai_profile)?,
        ];
        let mut world = Self::blank(data, seed, 0, "coord", VARIANT, "coord", 0);
        if budget == 10000 {
            world.field = Field {
                width: 60_000.,
                height: 36_000.,
                limit: LIMIT,
            };
        }
        world.host_duel = true;
        // The two seats are tactical sides, independent from national fleet identity.
        world.ranked_duel = Some(config);
        for (owner, definitions) in [allies, axis].into_iter().enumerate() {
            let id = owner as u32 + 1;
            let (x, heading, y) = if budget == 3000 {
                if owner == 0 {
                    (4200., 90., 6550.)
                } else {
                    (19_800., 270., 7650.)
                }
            } else if owner == 0 {
                (12_000., 90., 15_500.)
            } else {
                (48_000., 270., 20_500.)
            };
            let gap = if budget == 3000 { 450. } else { 950. };
            let direction = P::bearing(heading);
            let start = P { x, y };
            let mut members = Vec::new();
            for (slot, def) in definitions.into_iter().enumerate() {
                let name = data.ships[def].name.clone();
                members.push(world.spawn(
                    def,
                    owner,
                    id,
                    name,
                    (start - direction * (gap * slot as f64)).snap(),
                    heading,
                )?);
            }
            world.fleets.push(Fleet {
                id,
                side: owner,
                name: if owner == 0 {
                    "同盟席编队".into()
                } else {
                    "轴心席编队".into()
                },
                leader: members[0],
                members,
                mode: "follow".into(),
                speed: 26.,
                actual: 0.,
                turn_degrees: 0.,
                points: vec![],
                ai: Ai::new(profiles[owner], "suggest"),
                notice: None,
                last_ai_route: 0,
                tactic: Tactic::Search,
            });
        }
        world.gun_streak.resize(world.ships.len(), (0, 0, 0));
        world
            .surface_damage
            .resize(world.ships.len(), Default::default());
        world.init_realtime(realtime::VERSION)?;
        world.add(
            3,
            "start",
            "个人舰队演习 · 双方预设已冻结，四十五分钟按击沉数决胜。".into(),
            Some("RTS-PVP-01"),
            None,
        );
        world.detect(true);
        Ok(world)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn preset(ids: &[&str]) -> RankedFleet {
        RankedFleet {
            ship_ids: ids.iter().map(|id| (*id).into()).collect(),
            leader_id: ids[1].into(),
            ai_profile: "rc_coordinated".into(),
        }
    }

    fn duel(budget: u32, allies: RankedFleet, axis: RankedFleet) -> RankedFleetMatch {
        RankedFleetMatch {
            budget,
            points_version: POINTS_VERSION.into(),
            fleets: RankedFleets { allies, axis },
        }
    }

    #[test]
    fn free_fleet_mirrors_keep_their_named_profiles_and_replay() {
        let ids = ["IBS-U-USN-FLETCHER", "IBS-U-USN-PERKINS", "IBS-U-USN-MAURY"];
        let mut world =
            World::new_ranked_duel(6106, duel(3000, preset(&ids), preset(&ids))).unwrap();
        for (seat, (fleet, x, y)) in [(1, 15_000, 6550), (2, 9000, 7650)].into_iter().enumerate() {
            let view = world.observation(seat);
            assert_eq!(view["ships"].as_array().unwrap().len(), 3);
            assert_eq!(view["ships"][0]["characterId"], ids[1]);
            assert_eq!(view["ships"][1]["classId"], ids[0]);
            assert_eq!(view["fleets"][0]["leader"], view["ships"][0]["id"]);
            assert_eq!(view["fleets"][0]["ai"]["mode"], "suggest");
            world.external_for(seat, json!({"op":"route","fleet":fleet,"mode":"follow","speed":25,"points":[{"x":x,"y":y}]})).unwrap();
        }
        for _ in 0..540 {
            world.advance();
        }
        for seat in [0, 1] {
            let gun = world
                .suggestions(seat, seat as u32 + 1)
                .unwrap()
                .into_iter()
                .find(|order| order["op"] == "fire" && order["weapon"] == "gun")
                .unwrap();
            world.external_for(seat, gun).unwrap();
        }
        for _ in 0..120 {
            world.advance();
        }
        assert!([0, 1].into_iter().all(|seat| world
            .visible_events(seat, None)
            .iter()
            .any(|event| event["kind"] == "gun" && event.get("own_ship").is_some())));
        let save = world.save();
        let restored = World::from_save(save.clone(), save.tick).unwrap();
        for seat in [0, 1] {
            assert_eq!(restored.observation(seat), world.observation(seat));
        }
        assert_eq!(json!(restored.save()), json!(save));
        assert!(World::new_ranked_duel(6106, duel(10000, preset(&ids), preset(&ids))).is_err());
    }

    #[test]
    fn capital_ships_inherit_source_batteries_and_armor() {
        let allies = preset(&[
            "IBS-U-USN-UNNAMED-T01-R03",
            "IBS-U-USN-FLETCHER",
            "IBS-U-USN-MAURY",
        ]);
        let axis = preset(&[
            "IBS-U-IJN-ERMA-YAMATO",
            "IBS-U-IJN-SENDAI",
            "IBS-U-IJN-KAGERO",
        ]);
        let world = World::new_ranked_duel(42, duel(10000, allies, axis)).unwrap();
        assert_eq!(
            world.observation(0)["ships"][1]["systems"]["torpedoProtection"]["capacity"].as_f64(),
            Some(165.)
        );
        assert_eq!(
            world.observation(1)["ships"][1]["systems"]["torpedoProtection"]["capacity"].as_f64(),
            Some(195.)
        );
        let table = catalogue().unwrap();
        assert_eq!(table["enabled_budgets"], json!([3000, 10000]));
        assert_eq!(table["ships"]["IBS-U-USN-FLETCHER"]["points"], 475);
    }
}
