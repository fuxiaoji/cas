//! Original IBS relative positions and goals, adjudicated with CAS hull data.
use super::{legacy_deployment, live::Start, Grade, Outcome};
use crate::{
    model::*,
    night::{Environment, Light},
    world::World,
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::sync::OnceLock;

pub(crate) const VARIANT: &str = "channel-action-rts";
pub(crate) const CONTENT: &str = "cas-channel-runtime-v1";
pub(crate) const LABEL: &str = "通道行动 · 原布置 RTS 改编";
pub(crate) const LIMIT: u32 = 4 * CYCLE;
pub(crate) const ENVIRONMENT: Environment = Environment {
    // The old case has four hexes of visibility. CAS 5% night, with
    // fast size-C destroyers, approximates this after CAS optical modifiers.
    visibility: 5,
    sea_state: 2,
    light: Light::Night,
    precipitation: false,
};
const DAMAGED_SPEED: f64 = 1200. * YARD / (CYCLE as f64 * KNOT);

#[derive(Deserialize)]
struct Manifest {
    ships: Vec<ShipDef>,
    metadata: Value,
}
fn data() -> E<&'static Data> {
    static DATA: OnceLock<Result<Data, String>> = OnceLock::new();
    DATA.get_or_init(|| {
        let manifest: Manifest = serde_json::from_str(include_str!(
            "../../data/campaign/period/channel-runtime.json"
        ))
        .map_err(|e| format!("无法读取通道行动时期舰卡：{e}"))?;
        if manifest.metadata["content_version"] != CONTENT || manifest.ships.len() != 8 {
            return Err("通道行动内容版本或舰卡数量不一致".into());
        }
        Ok(Data {
            ships: manifest.ships,
            rules: World::exercise_data()?.rules.clone(),
        })
    })
    .as_ref()
    .map_err(Clone::clone)
}

pub(crate) fn view(start: &Start, owner: usize) -> Value {
    let objectives = if owner == 0 {
        "追击三艘德舰。击沉一艘，或令其受损后的最高航速不高于 11.85 节，即获战术胜利；达成两艘即获战略胜利。"
    } else {
        "保持三艘德舰存活，且各舰受损后的最高航速高于 11.85 节，即获战术胜利；另击沉至少两艘英舰即获小战略胜利。"
    };
    json!({"stageId":if owner == 0 { "CAMP-ALLIES-01" } else { "CAMP-AXIS-01" },"difficulty":start.difficulty,
        "objectives":objectives,"missionLabel":LABEL})
}

pub(crate) fn open(seed: u32, start: Start, player: usize, enemy: &str, profile: &str) -> E<World> {
    let layout = legacy_deployment(&start.stage_id)?;
    let mut w = World::blank(data()?, seed, player, enemy, VARIANT, profile, 0);
    w.field = Field {
        width: layout.map.width_m,
        height: layout.map.height_m,
        limit: LIMIT,
    };
    w.campaign = Some(start);
    if layout.start.duration_candidate_seconds != LIMIT
        || !layout.formations.is_empty()
        || layout.ships.len() != 8
    {
        return Err("通道行动开局布局超出当前核验范围".into());
    }
    for (i, entry) in layout.ships.iter().enumerate() {
        let raw = &entry.placement;
        let id = i as u32 + 1;
        let owner = side(&entry.side)?;
        let def = w
            .data
            .ships
            .iter()
            .position(|d| d.id == raw.ibs_ship_id)
            .ok_or("通道行动缺少具名舰卡")?;
        if raw.speed_knots > w.data.ships[def].max_knots {
            return Err("原阵位初速超过 CAS 舰卡上限".into());
        }
        let p = P {
            x: raw.x_m,
            y: raw.y_m,
        };
        let heading = f64::from(raw.heading_deg);
        let direction = P::bearing(heading);
        let safe_end = |p: f64, heading: f64, chart: f64| {
            if heading < -1e-9 {
                (150. - p) / heading
            } else if heading > 1e-9 {
                (chart - 150. - p) / heading
            } else {
                f64::INFINITY
            }
        };
        let advance = safe_end(p.x, direction.x, w.field.width).min(safe_end(
            p.y,
            direction.y,
            w.field.height,
        ));
        let end = (p + direction * advance).snap();
        let s = w.spawn(def, owner, id, entry.name.clone(), p, heading)?;
        let ship = w.ship_mut(s).unwrap();
        ship.speed = raw.speed_knots;
        ship.track = Some(Track::new(vec![p, end], 0., p.dist(end)));
        w.fleets.push(Fleet {
            id,
            side: owner,
            name: entry.name.clone(),
            leader: s,
            members: vec![s],
            mode: "follow".into(),
            speed: raw.speed_knots,
            actual: raw.speed_knots,
            points: vec![end],
            notice: None,
            ai: Ai::new(
                if owner == player { profile } else { enemy },
                if owner == player { "manual" } else { "auto" },
            ),
            last_ai_route: 0,
            tactic: Tactic::Search,
        });
    }
    w.gun_streak.resize(w.ships.len(), (0, 0, 0));
    w.surface_damage.resize(w.ships.len(), Default::default());
    w.enable_realtime()?;
    for owner in 0..2 {
        let objectives = view(w.campaign.as_ref().unwrap(), owner);
        let text = objectives["objectives"].as_str().unwrap();
        w.add(
            1 << owner,
            "start",
            format!("{LABEL}｜{text}"),
            Some("RTS-CHANNEL-01"),
            None,
        );
    }
    w.detect(true);
    Ok(w)
}

pub(crate) fn assess(world: &World, allied_sunk: u32) -> Outcome {
    let disabled = world
        .ships
        .iter()
        .filter(|s| s.side == 1 && (!s.alive() || world.max_speed(s) <= DAMAGED_SPEED))
        .count();
    Outcome {
        allies: match disabled {
            0 => Grade::None,
            1 => Grade::Tactical,
            _ => Grade::Decisive,
        },
        axis: if disabled > 0 {
            Grade::None
        } else if allied_sunk >= 2 {
            Grade::Decisive
        } else {
            Grade::Tactical
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_original_opening_and_scores_cas_damage_speed_not_throttle() {
        let start = Start::new("CAMP-ALLIES-01", "story");
        let original = legacy_deployment(&start.stage_id).unwrap();
        let mut w = World::new_campaign(53, start, "coord").unwrap();
        assert_eq!(w.field.limit, 720);
        assert_eq!(w.ships.iter().filter(|s| s.side == 1).count(), 3);
        assert_eq!(w.ships.len(), 8);
        for (ship, entry) in w.ships.iter().zip(&original.ships) {
            let placed = &entry.placement;
            assert_eq!(w.data.ships[ship.def].id, placed.ibs_ship_id);
            assert_eq!(ship.side, side(&entry.side).unwrap());
            assert!(
                ship.p.dist(P {
                    x: placed.x_m,
                    y: placed.y_m
                }) < 0.002
            );
            assert_eq!(ship.h, f64::from(placed.heading_deg));
            assert_eq!(ship.speed, placed.speed_knots);
        }
        w.ships[0].speed = 0.;
        assert_eq!(assess(&w, 0).axis, Grade::Tactical);
        assert_eq!(assess(&w, 2).axis, Grade::Decisive);
        let damage_for_10_knots = |ship: &Ship| {
            let def = &w.data.ships[ship.def];
            def.dp
                - def
                    .damage_speed
                    .iter()
                    .find(|r| r.knots == 10.)
                    .unwrap()
                    .damage
        };
        let crippled = [
            damage_for_10_knots(&w.ships[0]),
            damage_for_10_knots(&w.ships[1]),
        ];
        w.ships[0].hp = crippled[0];
        assert_eq!(assess(&w, 2).axis, Grade::None);
        assert_eq!(assess(&w, 0).allies, Grade::Tactical);
        w.ships[1].hp = crippled[1];
        assert_eq!(assess(&w, 0).allies, Grade::Decisive);
    }
}
