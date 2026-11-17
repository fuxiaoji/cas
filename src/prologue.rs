//! Fixed fictional fleet action used by the prologue and its opening replay.
use crate::{model::*, world::World};
use serde_json::{json, Value};
use std::sync::OnceLock;

pub(crate) const VARIANT: &str = "prologue";
pub(crate) const TITLE: &str = "未明的海 · 舰队决战";
pub(crate) const HANDOVER_TICK: u32 = 204;
const SQUADRON: [&str; 5] = [
    "IBS-U-USN-FLETCHER",
    "IBS-U-USN-PERKINS",
    "IBS-U-USN-MAURY",
    "IBS-U-USN-DRAYTON",
    "IBS-U-USN-LAMSON",
];

pub(crate) fn data() -> E<&'static Data> {
    static DATA: OnceLock<Result<Data, String>> = OnceLock::new();
    DATA.get_or_init(|| {
        let manifest: Value = serde_json::from_str(include_str!(
            "../data/campaign/period/prologue-runtime.json"
        ))
        .map_err(|e| format!("无法载入序章舰卡：{e}"))?;
        if manifest["content_version"] != "cas-prologue-runtime-v1" {
            return Err("序章舰卡版本不符".into());
        }
        let mut data = World::exercise_data()?.clone();
        let ships: Vec<ShipDef> = serde_json::from_value(manifest["ships"].clone())
            .map_err(|e| format!("序章舰卡格式有误：{e}"))?;
        data.ships.extend(ships);
        Ok(data)
    })
    .as_ref()
    .map_err(Clone::clone)
}

struct Column<'a> {
    name: &'a str,
    side: usize,
    start: P,
    heading: f64,
    speed: f64,
    spacing: f64,
    ships: &'a [(&'a str, &'a str)],
}

fn add_column(world: &mut World, column: Column<'_>) -> E<()> {
    let id = world.fleets.len() as u32 + 1;
    let forward = P::bearing(column.heading);
    let mut members = Vec::new();
    for (i, &(class, name)) in column.ships.iter().enumerate() {
        let index = world
            .data
            .ships
            .iter()
            .position(|ship| ship.id == class)
            .ok_or("缺少序章舰卡")?;
        let p = (column.start - forward * (column.spacing * i as f64)).snap();
        let name = if name.is_empty() {
            world.data.ships[index].name.clone()
        } else {
            name.into()
        };
        let id = world.spawn(index, column.side, id, name, p, column.heading)?;
        members.push(id);
        if column.speed > 0. {
            let distance = 9_000.;
            let end = p + forward * distance;
            let ship = world.ship_mut(id).unwrap();
            ship.speed = column.speed;
            ship.track = Some(Track::new(vec![p, end], 0., distance));
        }
    }
    world.fleets.push(Fleet {
        id,
        side: column.side,
        name: column.name.into(),
        leader: members[0],
        members,
        mode: "follow".into(),
        speed: if column.speed > 0. { column.speed } else { 20. },
        actual: column.speed,
        turn_degrees: 0.,
        points: vec![],
        ai: Ai::new("coord", "manual"),
        notice: None,
        last_ai_route: 0,
        tactic: Tactic::Search,
    });
    Ok(())
}

pub(crate) fn open(
    seed: u32,
    player: usize,
    enemy: &str,
    profile: &str,
    leader_slot: usize,
) -> E<World> {
    if player != 0 {
        return Err("序章由同盟第五驱逐小队指挥".into());
    }
    let mut world = World::blank(data()?, seed, player, enemy, VARIANT, profile, leader_slot);
    world.field = Field {
        width: 28_000.,
        height: 17_000.,
        limit: LIMIT,
    };
    let mut squadron = SQUADRON.map(|class| (class, ""));
    squadron[..=leader_slot].rotate_right(1);
    for column in [
        Column {
            name: "第五驱逐小队",
            side: 0,
            start: P {
                x: 10_300.,
                y: 6_600.,
            },
            heading: 90.,
            speed: 0.,
            spacing: 460.,
            ships: &squadron,
        },
        Column {
            name: "同盟战列线",
            side: 0,
            start: P {
                x: 10_000.,
                y: 8_000.,
            },
            heading: 90.,
            speed: 23.,
            spacing: 1_100.,
            ships: &[
                ("north-carolina", "北卡罗来纳"),
                ("north-carolina", "华盛顿"),
            ],
        },
        Column {
            name: "轴心战列线",
            side: 1,
            start: P {
                x: 15_500.,
                y: 11_300.,
            },
            heading: 270.,
            speed: 21.,
            spacing: 1_150.,
            ships: &[("yamato", "大和"), ("yamato", "武藏")],
        },
        Column {
            name: "轴心水雷队",
            side: 1,
            start: P {
                x: 16_200.,
                y: 14_200.,
            },
            heading: 270.,
            speed: 25.,
            spacing: 530.,
            ships: &[
                ("kagero", "阳炎"),
                ("kagero", "不知火"),
                ("kagero", "黑潮"),
                ("kagero", "亲潮"),
            ],
        },
        Column {
            name: "同盟护航队",
            side: 0,
            start: P {
                x: 9_500.,
                y: 9_600.,
            },
            heading: 90.,
            speed: 20.,
            spacing: 500.,
            ships: &[
                ("fletcher", "护航驱逐舰一号"),
                ("fletcher", "护航驱逐舰二号"),
            ],
        },
    ] {
        add_column(&mut world, column)?;
    }
    world.gun_streak.resize(world.ships.len(), (0, 0, 0));
    world
        .surface_damage
        .resize(world.ships.len(), Default::default());
    world.enable_realtime()?;
    world.add(
        1,
        "start",
        "未明的海 · 虚构舰队决战。第五驱逐小队在战列线南侧待命。".into(),
        Some("RTS-PROLOGUE-01"),
        None,
    );
    world.detect(true);
    Ok(world)
}

impl World {
    pub(crate) fn prologue_fire(&mut self) {
        if self.tick % 4 != 1 {
            return;
        }
        let mut orders = Vec::new();
        for ship in self
            .ships
            .iter()
            .filter(|s| s.fleet != Some(1) && s.alive())
        {
            let mut targets: Vec<_> = self.contacts[ship.side]
                .iter()
                .filter(|contact| contact.kind.as_deref() == Some("bb"))
                .collect();
            targets.sort_by(|a, b| ship.p.dist(a.p()).total_cmp(&ship.p.dist(b.p())));
            if let Some(target) = targets.iter().find(|target| {
                self.can_gun(ship)
                    && self
                        .realtime_aim(ship, &target.id)
                        .is_ok_and(|aim| aim["valid"] == true)
            }) {
                orders.push((
                    ship.side,
                    json!({"op":"fire","ship":ship.id,"weapon":"gun","target":target.id}),
                ));
            }
            if self.tick < CYCLE && self.can_torp(ship) {
                for target in targets {
                    let order =
                        json!({"op":"fire","ship":ship.id,"weapon":"torpedo","target":target.id});
                    if self
                        .preview_aim(ship.side, &order)
                        .is_ok_and(|aim| aim["valid"] == true && aim["friendly"] == false)
                    {
                        orders.push((ship.side, order));
                        break;
                    }
                }
            }
        }
        for (side, order) in orders {
            if let Err(error) = self.queue_fire(side, &order, false) {
                if std::env::var("CAS_PROLOGUE_PROBE").is_ok() {
                    eprintln!("PROLOGUEFIRE tick={} ship={} err={}", self.tick, order["ship"], error);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prologue_squadron_reports_catalogue_identities() {
        let world = World::new(6106, 0, "gunnery", VARIANT, "coord", 0).unwrap();
        let view = world.observation(0);
        let ships = view["ships"].as_array().unwrap();
        let squadron: Vec<_> = ships.iter().filter(|ship| ship["fleet"] == 1).collect();
        assert_eq!(squadron.len(), 5);
        assert!(squadron.iter().all(|ship| ship["characterId"]
            .as_str().is_some_and(|id| id.starts_with("IBS-U-USN-"))));
        assert_eq!(squadron[0]["characterId"], "IBS-U-USN-FLETCHER");
    }

    #[test]
    fn handover_uses_real_battleship_fire_and_inflight_torpedoes() {
        let mut world = World::new(6106, 0, "gunnery", VARIANT, "coord", 0).unwrap();
        for _ in 0..HANDOVER_TICK {
            world.advance();
        }
        let observation = world.observation(0);
        let shells = observation["shells"].as_array().unwrap();
        assert!(shells.iter().any(|shell| shell["own"] == true));
        // The sustained v10 volleys land on their own reload clocks, so scan a
        // short window instead of pinning the enemy shell to one tick.
        let enemy_shell = (0..40)
            .find_map(|_| {
                world.advance();
                world.observation(0)["shells"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .find(|shell| shell["own"] == false)
                    .cloned()
            })
            .is_some();
        assert!(enemy_shell, "enemy fire must be in flight around the handover");
        assert!(observation["torpedoes"]
            .as_array()
            .unwrap()
            .iter()
            .any(|torp| torp["trail"].is_array()));
        let capital_fire = |side| {
            world.events.iter().any(|event| {
                event.kind == "gun"
                    && event
                        .own_ship
                        .and_then(|id| world.ship(id))
                        .is_some_and(|ship| {
                            ship.side == side && world.data.ships[ship.def].kind == "BB"
                        })
            })
        };
        assert!(capital_fire(0) && capital_fire(1));
        assert!(world.ship(6).unwrap().p.x > 11_000.);
        assert!(world.ship(8).unwrap().p.x < 14_000.);
        // The mid-battle leader switch requires a queue-end hull: hand the
        // column over to its tail ship (the story's own handover uses the
        // deployment-phase swap for mid-line choices).
        world
            .external(json!({"op":"lead","fleet":1,"ship":5}))
            .unwrap();
        assert_eq!(world.fleet(1).unwrap().leader, 5);
        assert!(world
            .external(
                json!({"op":"route","fleet":2,"mode":"follow","points":[{"x":13500,"y":8000}]})
            )
            .is_err());
        let save = world.save();
        let resumed = World::from_save(save.clone(), save.tick).unwrap();
        assert_eq!(resumed.observation(0), world.observation(0));
    }
}
