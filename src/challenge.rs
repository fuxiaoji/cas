//! Parameterised fictional challenge ladder.
//!
//! `data/challenge/stages.json` is the single source of truth for the challenge
//! stage table. Each stage names the exact registered CAS hulls on both sides,
//! its point ceiling, objective, seed and map. The engine opens the stage the
//! client asks for instead of hard-coding one 3-vs-5 roster, so early stages can
//! field destroyers/light cruisers and later stages can field battleships.
//!
//! The content is fictional: it does not reference a historical action's fleet,
//! stations, courses or victory table. Points come from the frozen ranked table;
//! no ship card is modified here.
use crate::{
    model::*,
    ranked_fleets,
    world::World,
};
use serde::Deserialize;
use std::collections::BTreeSet;
use std::sync::OnceLock;

pub(crate) const VARIANT: &str = "challenge";
const CONTENT: &str = include_str!("../data/challenge/stages.json");
const CONTENT_VERSION: &str = "cas-challenge-v2";
const RULES_VERSION: &str = "cas-realtime-v9";

#[derive(Clone, Copy, Deserialize)]
pub(crate) struct FieldSpec {
    pub width: f64,
    pub height: f64,
    pub limit: u32,
}

#[derive(Clone, Deserialize)]
pub(crate) struct FleetSpec {
    pub name: String,
    pub ships: Vec<String>,
    pub kinds: Vec<String>,
    pub points: u32,
    pub leader_slot: usize,
    pub x: f64,
    pub y: f64,
    pub heading: f64,
    pub speed: f64,
}

#[derive(Clone, Deserialize)]
pub(crate) struct SideFleets {
    pub allies: FleetSpec,
    pub axis: FleetSpec,
}

#[derive(Clone, Debug, Deserialize)]
pub(crate) struct EvidenceResult {
    pub allies: u32,
    pub axis: u32,
    pub primary: bool,
}

#[derive(Clone, Deserialize)]
pub(crate) struct Evidence {
    pub seed: u32,
    pub enemy_profile: String,
    pub result: EvidenceResult,
    pub note: String,
}

#[derive(Clone, Deserialize)]
pub(crate) struct Reward {
    pub first_clear: String,
    pub repeat: String,
    pub basis: String,
}

#[derive(Clone, Deserialize)]
pub(crate) struct Stage {
    pub id: String,
    pub order: u32,
    pub name: String,
    pub tier: String,
    pub status: String,
    pub brief: String,
    pub objective: String,
    pub unlock_after: Option<String>,
    pub source: String,
    pub profile: String,
    pub seed: u32,
    pub enemy_profile: String,
    pub budget: u32,
    pub required_enemy_losses: u32,
    pub spacing: f64,
    pub field: FieldSpec,
    pub player: SideFleets,
    pub enemy: SideFleets,
    pub reward: Reward,
    pub evidence: Evidence,
}

#[derive(Deserialize)]
struct File {
    schema_version: u32,
    version: String,
    kind: String,
    source: String,
    engine: EngineSpec,
    rewards: Reward,
    stages: Vec<Stage>,
}

#[derive(Deserialize)]
struct EngineSpec {
    variant: String,
    rules_version: String,
    field: FieldSpec,
    notes: Vec<String>,
}

fn parse() -> E<File> {
    serde_json::from_str(CONTENT).map_err(|error| format!("data/challenge/stages.json 解析失败：{error}"))
}

fn stage_table() -> E<&'static [Stage]> {
    static STAGES: OnceLock<Result<Vec<Stage>, String>> = OnceLock::new();
    STAGES
        .get_or_init(|| {
            let file = parse()?;
            validate(&file)?;
            Ok(file.stages)
        })
        .as_ref()
        .map(Vec::as_slice)
        .map_err(Clone::clone)
}

/// The challenge card set: the stage0 exercise cards plus the 202 registered
/// ranked identities. No card is copied or rewritten; both sets keep their
/// verified ShipDefs.
pub(crate) fn data() -> E<&'static Data> {
    static DATA: OnceLock<Result<Data, String>> = OnceLock::new();
    DATA.get_or_init(|| {
        let mut data = World::exercise_data()?.clone();
        let ranked = ranked_fleets::data()?;
        for ship in &ranked.ships {
            if !data.ships.iter().any(|known| known.id == ship.id) {
                data.ships.push(ship.clone());
            }
        }
        Ok(data)
    })
    .as_ref()
    .map_err(Clone::clone)
}

pub(crate) fn stages() -> E<&'static [Stage]> {
    stage_table()
}

pub(crate) fn stage(id: &str) -> E<&'static Stage> {
    stage_table()?
        .iter()
        .find(|stage| stage.id == id)
        .ok_or_else(|| format!("未知挑战关卡 {id}"))
}

fn ship_kind<'a>(data: &'a Data, id: &str) -> Option<&'a str> {
    data.ships.iter().find(|ship| ship.id == id).map(|ship| ship.kind.as_str())
}

fn declared_total(fleet: &FleetSpec, data: &Data) -> E<u32> {
    fleet
        .ships
        .iter()
        .map(|id| {
            data.ships
                .iter()
                .find(|ship| ship.id == *id)
                .map(ranked_fleets::ship_points)
                .ok_or_else(|| format!("挑战关卡引用了未登记舰卡 {id}"))
        })
        .collect::<E<Vec<u32>>>()
        .map(|points| points.into_iter().sum())
}

fn check_fleet(stage: &Stage, side: &str, role: &str, fleet: &FleetSpec, data: &Data) -> E<()> {
    let label = format!("{}/{} {side}", stage.id, role);
    if fleet.ships.is_empty() || fleet.ships.len() > 8 {
        return Err(format!("{label}: 编队必须有 1–8 艘舰"));
    }
    if fleet.ships.iter().collect::<BTreeSet<_>>().len() != fleet.ships.len() {
        return Err(format!("{label}: 同一编队不能重复舰卡"));
    }
    if fleet.kinds.len() != fleet.ships.len() {
        return Err(format!("{label}: kinds 与 ships 数量不一致"));
    }
    for (id, kind) in fleet.ships.iter().zip(&fleet.kinds) {
        match ship_kind(data, id) {
            Some(actual) if actual == kind => {}
            Some(actual) => return Err(format!("{label}: {id} 舰种为 {actual}，数据写 {kind}")),
            None => return Err(format!("{label}: 未登记舰卡 {id}")),
        }
    }
    let total = declared_total(fleet, data)?;
    if total != fleet.points {
        return Err(format!("{label}: 点价声明 {} ≠ 实算 {total}", fleet.points));
    }
    if fleet.leader_slot >= fleet.ships.len() {
        return Err(format!("{label}: 领舰槽超出编队"));
    }
    if !(1.0..=40.0).contains(&fleet.speed) {
        return Err(format!("{label}: 航速无效"));
    }
    let direction = P::bearing(fleet.heading);
    for index in 0..fleet.ships.len() {
        let p = P { x: fleet.x, y: fleet.y } - direction * (stage.spacing * index as f64);
        if !(50.0..=stage.field.width - 50.0).contains(&p.x)
            || !(50.0..=stage.field.height - 50.0).contains(&p.y)
        {
            return Err(format!("{label}: 第 {} 舰落在海图外", index + 1));
        }
    }
    Ok(())
}

fn validate(file: &File) -> E<()> {
    if file.schema_version != 2 {
        return Err("challenge schema_version 必须为 2".into());
    }
    if file.version != CONTENT_VERSION {
        return Err(format!("challenge version 必须为 {CONTENT_VERSION}"));
    }
    if file.kind != "fictional" {
        return Err("挑战模式必须是架空内容".into());
    }
    if file.engine.variant != VARIANT || file.engine.rules_version != RULES_VERSION {
        return Err("挑战引擎必须冻结在 v9 时序".into());
    }
    if file.source.trim().is_empty() || file.engine.notes.is_empty() {
        return Err("挑战数据缺少来源说明".into());
    }
    let data = data()?;
    if file.stages.len() != 5 {
        return Err("挑战梯度必须为 5 关".into());
    }
    let mut previous: Option<&str> = None;
    for (index, stage) in file.stages.iter().enumerate() {
        let order = index as u32 + 1;
        if stage.order != order {
            return Err(format!("{}: order 必须为 {order}", stage.id));
        }
        if stage.id != format!("challenge-{order:02}") {
            return Err(format!("{}: 关卡 id 必须按序编号", stage.id));
        }
        if stage.status != "playable" {
            return Err(format!("{}: 本批五关全部接入引擎，不得写 blocked", stage.id));
        }
        if stage.unlock_after.as_deref() != previous {
            return Err(format!("{}: unlock_after 必须为上一关", stage.id));
        }
        for (name, value) in [
            ("name", &stage.name),
            ("tier", &stage.tier),
            ("brief", &stage.brief),
            ("objective", &stage.objective),
            ("source", &stage.source),
        ] {
            if value.trim().is_empty() {
                return Err(format!("{}: 缺少 {name}", stage.id));
            }
        }
        if stage.budget == 0 {
            return Err(format!("{}: 点价上限必须为正", stage.id));
        }
        check_fleet(stage, "allies", "player", &stage.player.allies, data)?;
        check_fleet(stage, "axis", "player", &stage.player.axis, data)?;
        check_fleet(stage, "allies", "enemy", &stage.enemy.allies, data)?;
        check_fleet(stage, "axis", "enemy", &stage.enemy.axis, data)?;
        for (side, fleet) in [("allies", &stage.player.allies), ("axis", &stage.player.axis)] {
            if fleet.points > stage.budget {
                return Err(format!(
                    "{}: {side} 本席 {} 分超过关卡上限 {}",
                    stage.id, fleet.points, stage.budget
                ));
            }
        }
        for (side, fleet) in [("allies", &stage.enemy.allies), ("axis", &stage.enemy.axis)] {
            if stage.required_enemy_losses == 0 || stage.required_enemy_losses as usize > fleet.ships.len() {
                return Err(format!("{}: {side} 敌编成的击沉目标无效", stage.id));
            }
        }
        if stage.spacing <= 0.0 {
            return Err(format!("{}: 列内间距必须为正", stage.id));
        }
        if stage.field.limit < 1800 || stage.field.limit > 5400 {
            return Err(format!("{}: 时限超出 30–90 分钟", stage.id));
        }
        if !["coord", "gunnery", "torpedo"].contains(&stage.profile.as_str()) {
            return Err(format!("{}: 本席 AI 风格无效", stage.id));
        }
        if stage.seed != stage.evidence.seed || stage.enemy_profile != stage.evidence.enemy_profile {
            return Err(format!("{}: evidence 的种子/AI 与关卡不一致", stage.id));
        }
        if !stage.evidence.result.primary {
            return Err(format!("{}: evidence 必须记录主目标达成", stage.id));
        }
        if stage.evidence.result.axis >= stage.player.allies.ships.len() as u32 {
            return Err(format!("{}: evidence 必须记录至少一艘本席舰存活", stage.id));
        }
        let heavy = |fleet: &FleetSpec| fleet.kinds.iter().any(|kind| kind == "BB" || kind == "BC");
        let light = |fleet: &FleetSpec| fleet.kinds.iter().all(|kind| kind == "DD" || kind == "CL");
        if order <= 3 {
            if !light(&stage.player.allies) || !light(&stage.player.axis)
                || !light(&stage.enemy.allies) || !light(&stage.enemy.axis)
            {
                return Err(format!("{}: 前三关只能出驱逐舰/轻巡洋舰", stage.id));
            }
            if stage.field.width > 24_000.0 || stage.field.height > 14_000.0 || stage.field.limit != LIMIT {
                return Err(format!("{}: 前三关必须沿用轻编队海图", stage.id));
            }
        } else {
            for (role, fleet) in [
                ("player.allies", &stage.player.allies),
                ("player.axis", &stage.player.axis),
                ("enemy.allies", &stage.enemy.allies),
                ("enemy.axis", &stage.enemy.axis),
            ] {
                if !heavy(fleet) {
                    return Err(format!("{}: {role} 必须出现战列舰", stage.id));
                }
                let capitals = fleet.kinds.iter().filter(|kind| ["BB", "BC"].contains(&kind.as_str())).count();
                let destroyers = fleet.kinds.iter().filter(|kind| kind.as_str() == "DD").count();
                if !(1..=2).contains(&capitals) || destroyers > 4 {
                    return Err(format!("{}: {role} 的主力/驱逐舰槽位超出分档", stage.id));
                }
            }
            if stage.field.width < 48_000.0 || stage.field.height < 28_000.0 {
                return Err(format!("{}: 主力关海图不足以容纳接敌距离", stage.id));
            }
        }
        previous = Some(&stage.id);
    }
    if let Some((first, _)) = file.stages.split_first() {
        if first.player.allies.points != 1875 {
            return Err("第一关必须保留已验收的 3 舰 1875 分编制".into());
        }
    }
    Ok(())
}

fn fleet_for_player(stage: &Stage, side: usize) -> &FleetSpec {
    if side == 0 { &stage.player.allies } else { &stage.player.axis }
}

/// The enemy roster is indexed by the *enemy's* side: when the player is
/// allied the enemy is the axis fleet and vice versa.
fn fleet_for_enemy(stage: &Stage, side: usize) -> &FleetSpec {
    if side == 0 { &stage.enemy.allies } else { &stage.enemy.axis }
}

/// Open the requested stage on an already-blanked world. The world's data must
/// be `data()`; the caller (World::new_challenge) guarantees that.
pub(crate) fn open(w: &mut World, stage_id: &str, leader_slot: usize) -> E<()> {
    let stage = stage(stage_id)?;
    let player_fleet = fleet_for_player(stage, w.player);
    if leader_slot >= player_fleet.ships.len() {
        return Err("领舰未在当前舰队内".into());
    }
    if player_fleet.points > stage.budget {
        return Err(format!(
            "本席编队 {} 分超过 {} 分关卡上限",
            player_fleet.points, stage.budget
        ));
    }
    w.field = Field {
        width: stage.field.width,
        height: stage.field.height,
        limit: stage.field.limit,
    };
    w.challenge_goal = Some(stage.required_enemy_losses);
    w.challenge_stage = Some(stage.id.clone());
    w.challenge_label = Some(format!(
        "{} · {} 对 {} 挑战 · 上限 {} 分",
        stage.name,
        player_fleet.ships.len(),
        fleet_for_enemy(stage, 1 - w.player).ships.len(),
        stage.budget
    ));
    w.enemy = stage.enemy_profile.clone();
    for side in 0..2 {
        let fleet = if side == w.player {
            fleet_for_player(stage, side)
        } else {
            fleet_for_enemy(stage, side)
        };
        let mut definitions = fleet
            .ships
            .iter()
            .map(|id| {
                w.data
                    .ships
                    .iter()
                    .position(|ship| ship.id == *id)
                    .ok_or_else(|| format!("缺少已登记舰卡 {id}"))
            })
            .collect::<E<Vec<usize>>>()?;
        if side == w.player {
            let chosen = definitions.remove(leader_slot);
            definitions.insert(0, chosen);
        }
        let direction = P::bearing(fleet.heading);
        let start = P { x: fleet.x, y: fleet.y };
        let mut members = Vec::new();
        for (position, def) in definitions.into_iter().enumerate() {
            let kind = w.data.ships[def].kind.clone();
            let base = ranked_fleets::display_name(&w.data.ships[def].id)
                .unwrap_or(&w.data.ships[def].name)
                .to_string();
            let name = if kind == "DD" {
                format!("{} {}", base, position + 1)
            } else {
                base
            };
            let p = (start - direction * (stage.spacing * position as f64)).snap();
            let id = w.spawn(def, side, side as u32 + 1, name, p, fleet.heading)?;
            members.push(id);
        }
        w.fleets.push(Fleet {
            id: side as u32 + 1,
            side,
            name: fleet.name.clone(),
            leader: members[0],
            members,
            mode: "follow".into(),
            speed: fleet.speed,
            actual: 0.,
            turn_degrees: 0.,
            points: vec![],
            ai: if side == w.player {
                // Honour the launch profile (the client sends the stage
                // default); the stage field is the documented default.
                Ai::new(&w.profile, "manual")
            } else {
                Ai::new(&stage.enemy_profile, "auto")
            },
            notice: None,
            last_ai_route: 0,
            tactic: Tactic::Search,
        });
    }
    let player_count = w.fleets.iter().find(|fleet| fleet.side == w.player).map_or(0, |fleet| fleet.members.len());
    let enemy_count = w.fleets.iter().find(|fleet| fleet.side != w.player).map_or(0, |fleet| fleet.members.len());
    w.add(
        3,
        "start",
        format!(
            "{} · 上限 {} 分 · 本席 {} 艘对敌 {} 艘：{}",
            stage.name, stage.budget, player_count, enemy_count, stage.objective
        ),
        None,
        None,
    );
    w.detect(true);
    w.radar_detect();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn stage_table_is_lawful_and_progresses_from_light_to_capital_ships() {
        let stages = stages().unwrap();
        assert_eq!(stages.len(), 5);
        assert_eq!(stages[0].required_enemy_losses, 2);
        for stage in stages {
            assert_eq!(stage.status, "playable");
            assert!(stage.player.allies.points <= stage.budget);
            assert!(stage.player.axis.points <= stage.budget);
            assert!(stage.evidence.result.primary);
        }
        let light: Vec<_> = stages.iter().take(3).collect();
        assert!(light.iter().all(|stage| stage.tier.contains("DD/CL")));
        assert!(stages[3..].iter().all(|stage| stage.tier.contains("BB")));
        assert!(stages[3].player.allies.kinds.contains(&"BB".to_string()));
    }

    #[test]
    fn stage_one_keeps_the_accepted_three_ship_geometry() {
        let stage = stage("challenge-01").unwrap();
        assert_eq!(stage.player.allies.ships.len(), 3);
        assert_eq!(stage.enemy.axis.ships.len(), 5);
        assert_eq!(stage.player.allies.leader_slot, 1);
        assert_eq!(stage.player.allies.points, 1875);
        assert_eq!(stage.field.width, 24_000.0);
        assert_eq!(stage.field.height, 14_000.0);
        let world = World::new_challenge(6106, 0, "gunnery", "coord", 1, "challenge-01").unwrap();
        assert_eq!(world.ships.len(), 8);
        assert_eq!(world.field.width, 24_000.0);
        assert_eq!(world.challenge_goal, Some(2));
        let own: Vec<_> = world.ships.iter().filter(|ship| ship.side == 0).collect();
        assert_eq!(own.len(), 3);
        assert_eq!(own[0].name, "克利夫兰");
        assert_eq!(own[0].p, P { x: 4200.0, y: 6550.0 });
        assert_eq!(own[1].p, P { x: 3750.0, y: 6550.0 });
    }

    #[test]
    fn every_evidence_seed_clears_its_stage_with_the_auto_ai() {
        for stage in stages().unwrap() {
            let mut recorded = None;
            let mut axis_primary = None;
            for side in [0, 1] {
                let leader = if side == 0 {
                    stage.player.allies.leader_slot
                } else {
                    stage.player.axis.leader_slot
                };
                let mut world = World::new_challenge(
                    stage.seed,
                    side,
                    &stage.enemy_profile,
                    &stage.profile,
                    leader,
                    &stage.id,
                )
                .unwrap();
                world.enable_realtime().unwrap();
                world
                    .external(json!({"op":"ai","fleet":side as u32 + 1,"profile":stage.profile,"mode":"auto","move":true,"gun":true,"torpedo":true}))
                    .unwrap();
                while world.result.is_none() && world.tick < world.field.limit + 200 {
                    world.advance();
                }
                let result = world.result.clone().expect("challenge stage resolves");
                println!("evidence {} seat {side} -> {result:?}", stage.id);
                if side == 0 {
                    recorded = Some(result);
                } else {
                    axis_primary = result.primary;
                }
            }
            // The published evidence covers the allied seat, which is the
            // default client side. The axis seat is exercised above so a
            // roster that cannot even resolve is caught, but its balance is a
            // separate audit.
            let result = recorded.expect("allied seat resolves");
            assert_eq!(result.primary, Some(true), "{} {result:?}", stage.id);
            assert_eq!(
                result.allies, stage.evidence.result.allies,
                "{} enemy losses",
                stage.id
            );
            assert_eq!(
                result.axis, stage.evidence.result.axis,
                "{} own losses",
                stage.id
            );
            assert_eq!(result.winner, "allies", "{} winner", stage.id);
            assert_eq!(axis_primary, Some(true), "{} axis seat objective", stage.id);
        }
    }
}
