//! Historical archive and Cape St. George outcome authority. A source record is
//! not a battle manifest: no battle starts while runtime inputs are unresolved.
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{collections::BTreeMap, sync::OnceLock};

mod legacy;
pub(crate) mod live;
pub(crate) mod channel;
pub(crate) mod kula;
pub mod horaniu;
pub mod esperance;
pub use legacy::{Deployment as LegacyDeployment, MapGeometry as LegacyMapGeometry};

const CROSSWALK: &str = include_str!("../data/campaign/crosswalk.json");
const CAPE: &str = include_str!("../data/campaign/cape-st-george.json");
const CAPE_PERIOD: &str = include_str!("../data/campaign/period/cape-st-george-1943.json");

fn source_for(id: &str) -> Option<&'static str> {
    Some(match id {
        "cas-rs-cape-esperance" => include_str!("../data/campaign/cape-esperance.json"),
        "cas-rs-cape-st-george" => CAPE,
        "cas-rs-empress-augusta-bay" => include_str!("../data/campaign/empress-augusta-bay.json"),
        "cas-rs-guadalcanal-i" => include_str!("../data/campaign/guadalcanal-i.json"),
        "cas-rs-guadalcanal-ii" => include_str!("../data/campaign/guadalcanal-ii.json"),
        "cas-rs-horaniu" => include_str!("../data/campaign/horaniu.json"),
        "cas-rs-kolombangara" => include_str!("../data/campaign/kolombangara.json"),
        "cas-rs-kula-gulf" => include_str!("../data/campaign/kula-gulf.json"),
        "cas-rs-savo-island" => include_str!("../data/campaign/savo-island.json"),
        "cas-rs-tassafaronga" => include_str!("../data/campaign/tassafaronga.json"),
        "cas-rs-vella-lavella" => include_str!("../data/campaign/vella-lavella.json"),
        _ => return None,
    })
}

fn catalogue_row(id: &str) -> Result<&'static Value, String> {
    static CATALOGUE: OnceLock<Value> = OnceLock::new();
    let catalogue =
        CATALOGUE.get_or_init(|| serde_json::from_str(CROSSWALK).expect("campaign catalogue"));
    catalogue["scenarios"]
        .as_array()
        .expect("campaign rows")
        .iter()
        .find(|row| {
            row["ibs_id"].as_str() == Some(id)
                || row["cas"]["scenario_id"].as_str() == Some(id)
                || row["ibs_id"]
                    .as_str()
                    .is_some_and(|ibs| legacy::alias(ibs, id))
                || row["stage_ids"]
                    .as_array()
                    .is_some_and(|stages| stages.iter().any(|stage| stage.as_str() == Some(id)))
        })
        .ok_or_else(|| "未知战役关卡".to_owned())
}

/// Return immutable geometry and setup evidence. This does not authorize battle start:
/// CAS class, equipment, environment and objective bindings are still required.
pub fn legacy_deployment(id: &str) -> Result<LegacyDeployment, String> {
    let row = catalogue_row(id)?;
    let ibs_id = row["ibs_id"].as_str().ok_or("缺少原战役 ID")?;
    let data = legacy::source(ibs_id).ok_or("该关不使用铁底湾回退部署")?;
    serde_json::from_str(data).map_err(|e| format!("无法读取旧战役部署：{e}"))
}

pub fn detail(id: &str) -> Result<Value, String> {
    let row = catalogue_row(id)?;
    let cas_id = row["cas"]["scenario_id"].as_str();
    let record = cas_id
        .and_then(source_for)
        .map(serde_json::from_str::<Value>)
        .transpose()
        .map_err(|e| format!("无法读取战役原页记录：{e}"))?;
    let legacy = row["ibs_id"]
        .as_str()
        .and_then(legacy::source)
        .map(serde_json::from_str::<Value>)
        .transpose()
        .map_err(|e| format!("无法读取旧战役部署：{e}"))?;
    let readiness = (cas_id == Some("cas-rs-cape-st-george")).then(|| {
        let period: Value = serde_json::from_str(CAPE_PERIOD).expect("Cape St. George period data");
        let unresolved: Vec<_> = period["conflicts"]
            .as_array()
            .expect("conflicts")
            .iter()
            .filter(|row| row["status"] == "unresolved")
            .collect();
        json!({
            "playable": false,
            "periodVersion": period["content_version"],
            "datedShips": cape().period.instances.len(),
            "periodProfiles": cape().period.profiles.len(),
            "unresolvedPeriodData": unresolved
        })
    });
    Ok(json!({"entry":public_row(row.clone()), "record":record, "readiness":readiness, "legacy":legacy}))
}

pub fn catalogue() -> Result<Value, String> {
    let mut catalog: Value = serde_json::from_str(CROSSWALK)
        .map_err(|e| format!("无法读取战役档案：{e}"))?;
    for row in catalog["scenarios"].as_array_mut().expect("campaign rows") {
        *row = public_row(row.take());
    }
    Ok(catalog)
}

fn public_row(mut row: Value) -> Value {
    if row["cas"]["scenario_id"] == "cas-rs-cape-st-george" {
        row["playable"] = json!(true);
        row["runtime"] = json!({"historicalReady":false,"label":live::LABEL,"contentVersion":live::CONTENT});
    } else if row["cas"]["scenario_id"] == "cas-rs-kula-gulf" {
        row["playable"] = json!(true);
        row["runtime"] = json!({"historicalReady":false,"label":kula::LABEL,"contentVersion":kula::CONTENT,"localOnly":true});
    } else if row["ibs_id"] == "IBS-S-03" {
        row["playable"] = json!(true);
        row["runtime"] = json!({"historicalReady":false,"label":channel::LABEL,"contentVersion":channel::CONTENT,"localOnly":true});
    } else if row["cas"]["scenario_id"] == "cas-rs-empress-augusta-bay" {
        row["playable"] = json!(true);
        row["runtime"] = json!({"historicalReady":false,"label":crate::empress::LABEL,"contentVersion":crate::empress::CONTENT,"localOnly":true});
    } else if row["cas"]["scenario_id"] == "cas-rs-cape-esperance" {
        row["playable"] = json!(true);
        row["runtime"] = json!({"historicalReady":false,"label":esperance::LABEL,"contentVersion":esperance::CONTENT,"localOnly":true});
    }
    row
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum Disposition {
    Present,
    Escaped,
    Sunk,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ClosedShip {
    pub damage_dp: f64,
    pub disposition: Disposition,
}

#[derive(Debug, Clone, Copy, Serialize, Eq, PartialEq, Ord, PartialOrd)]
#[serde(rename_all = "snake_case")]
pub enum Grade {
    None,
    Tactical,
    Decisive,
}

#[derive(Debug, Clone, Copy, Serialize, Eq, PartialEq)]
pub struct Outcome {
    pub allies: Grade,
    pub axis: Grade,
}

#[derive(Deserialize)]
struct Scenario {
    ships: Vec<Ship>,
    groups: Vec<Group>,
    objectives: Objectives,
}
#[derive(Deserialize)]
struct Ship {
    id: String,
    kind: String,
}
#[derive(Deserialize)]
struct Group {
    id: String,
    side: String,
    members_in_order: Vec<String>,
}
#[derive(Deserialize)]
struct Objectives {
    allies: Goals,
    axis: Goals,
}
#[derive(Deserialize)]
struct Goals {
    decisive: Conditions,
    tactical: Conditions,
}
#[derive(Deserialize)]
struct Conditions {
    all_of: Vec<Condition>,
}
#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Condition {
    OpposingShipsSunkAtLeast { kind: String, count: usize },
    AllOwnShipsDamageAtMostPct { kind: String, pct: u32 },
    AllOwnShipsEscape,
    AllOwnShipsDamageStrictlyBelowPct { pct: u32 },
    GroupEscapes { group: String },
    GroupUndamaged { group: String },
}
#[derive(Deserialize)]
struct Period {
    instances: BTreeMap<String, Instance>,
    profiles: BTreeMap<String, Profile>,
}
#[derive(Deserialize)]
struct Instance {
    profile: String,
}
#[derive(Deserialize)]
struct Profile {
    damage_speed_rows_dp_knots: Vec<(u16, Option<u16>)>,
}
struct Cape {
    scenario: Scenario,
    period: Period,
}
fn cape() -> &'static Cape {
    static CAPE_DATA: OnceLock<Cape> = OnceLock::new();
    CAPE_DATA.get_or_init(|| Cape {
        scenario: serde_json::from_str(CAPE).expect("Cape St. George objectives"),
        period: serde_json::from_str(CAPE_PERIOD).expect("Cape St. George period data"),
    })
}

/// Assess each side independently after an authoritative battle close. A result
/// does not imply a match winner: the source supplies no tie precedence or
/// escape geometry, and a client cannot submit these state facts as commands.
pub fn assess_cape_st_george(states: &BTreeMap<String, ClosedShip>) -> Result<Outcome, String> {
    let cape = cape();
    let scenario = &cape.scenario;
    if states.len() != scenario.ships.len() {
        return Err("圣乔治角结算须包括所有十艘舰艇".into());
    }
    let mut facts = Vec::with_capacity(scenario.ships.len());
    for ship in &scenario.ships {
        let state = states
            .get(&ship.id)
            .ok_or_else(|| format!("缺少舰艇状态：{}", ship.id))?;
        let group = scenario
            .groups
            .iter()
            .find(|group| group.members_in_order.contains(&ship.id))
            .ok_or_else(|| format!("舰艇未编入历史纵队：{}", ship.id))?;
        let profile = &cape.period.profiles[&cape.period.instances[&ship.id].profile];
        let max_dp = profile
            .damage_speed_rows_dp_knots
            .last()
            .expect("DP breakdown")
            .0;
        let max_dp = f64::from(max_dp);
        if !state.damage_dp.is_finite() || state.damage_dp < 0. || state.damage_dp > max_dp
            || (state.damage_dp == max_dp && state.disposition != Disposition::Sunk)
        {
            return Err(format!("舰艇损伤与状态不一致：{}", ship.id));
        }
        let damage_dp = if state.disposition == Disposition::Sunk {
            max_dp
        } else {
            state.damage_dp
        };
        facts.push((
            ship,
            group,
            *state,
            damage_dp * 100.,
            max_dp,
        ));
    }
    let evaluate = |side: &str, goals: &Goals| {
        let satisfied = |conditions: &Conditions| {
            conditions.all_of.iter().all(|test| match test {
                Condition::OpposingShipsSunkAtLeast { kind, count } => {
                    facts
                        .iter()
                        .filter(|(ship, group, state, _, _)| {
                            group.side != side
                                && &ship.kind == kind
                                && state.disposition == Disposition::Sunk
                        })
                        .count()
                        >= *count
                }
                Condition::AllOwnShipsDamageAtMostPct { kind, pct } => facts
                    .iter()
                    .filter(|(ship, group, ..)| group.side == side && &ship.kind == kind)
                    .all(|(_, _, _, damage, max)| *damage <= f64::from(*pct) * *max),
                Condition::AllOwnShipsDamageStrictlyBelowPct { pct } => facts
                    .iter()
                    .filter(|(_, group, ..)| group.side == side)
                    .all(|(_, _, _, damage, max)| *damage < f64::from(*pct) * *max),
                Condition::AllOwnShipsEscape => facts
                    .iter()
                    .filter(|(_, group, ..)| group.side == side)
                    .all(|(_, _, state, ..)| state.disposition == Disposition::Escaped),
                Condition::GroupEscapes { group } => facts
                    .iter()
                    .filter(|(_, g, ..)| g.side == side && &g.id == group)
                    .all(|(_, _, state, ..)| state.disposition == Disposition::Escaped),
                Condition::GroupUndamaged { group } => facts
                    .iter()
                    .filter(|(_, g, ..)| g.side == side && &g.id == group)
                    .all(|(_, _, _, damage, _)| *damage == 0.),
            })
        };
        if satisfied(&goals.decisive) {
            Grade::Decisive
        } else if satisfied(&goals.tactical) {
            Grade::Tactical
        } else {
            Grade::None
        }
    };
    Ok(Outcome {
        allies: evaluate("allies", &scenario.objectives.allies),
        axis: evaluate("axis", &scenario.objectives.axis),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh() -> BTreeMap<String, ClosedShip> {
        cape()
            .scenario
            .ships
            .iter()
            .map(|ship| {
                (
                    ship.id.clone(),
                    ClosedShip {
                        damage_dp: 0.,
                        disposition: Disposition::Present,
                    },
                )
            })
            .collect()
    }

    #[test]
    fn all_32_stage_aliases_return_their_own_archive_and_only_one_kind_of_record() {
        let mut sources = 0;
        let mut fallback_count = 0;
        let mut fallback_ships = 0;
        for n in 1..=16 {
            let allies = detail(&format!("CAMP-ALLIES-{n:02}")).unwrap();
            let axis = detail(&format!("CAMP-AXIS-{n:02}")).unwrap();
            assert_eq!(allies, axis);
            assert_eq!(allies["entry"]["playable"], matches!(n, 1 | 2 | 3 | 4 | 11));
            if !allies["record"].is_null() {
                sources += 1;
                assert_eq!(allies["record"]["ibs_id"], allies["entry"]["ibs_id"]);
                assert_eq!(allies["record"]["playable"], false);
                assert!(allies["legacy"].is_null());
            } else {
                fallback_count += 1;
                let stage_id = format!("CAMP-ALLIES-{n:02}");
                let deployment = legacy_deployment(&stage_id).unwrap();
                let alias = detail(&deployment.scenario_id).unwrap();
                assert_eq!(allies, alias);
                assert_eq!(allies["legacy"]["ibs_id"], allies["entry"]["ibs_id"]);
                assert_eq!(deployment.schema, "cas-legacy-deployment-v1");
                assert!(!deployment.playable);
                assert!(deployment.ships.iter().all(|s| {
                    s.cas_profile_id.is_none()
                        && s.placement.x_m > 0.0
                        && s.placement.x_m < deployment.map.width_m
                        && s.placement.y_m > 0.0
                        && s.placement.y_m < deployment.map.height_m
                }));
                fallback_ships += deployment.ships.len();
            }
        }
        assert_eq!(sources, 11);
        assert_eq!(fallback_count, 5);
        assert_eq!(fallback_ships, 159);
        assert!(legacy_deployment("CAMP-ALLIES-02").is_err());
        assert!(detail("../cape-st-george").is_err());
    }

    #[test]
    fn exactly_25_percent_is_eligible_for_allied_decisive_but_not_axis_decisive() {
        let mut states = fresh();
        for id in ["onami", "makinami", "amagiri"] {
            states.get_mut(id).unwrap().disposition = Disposition::Sunk;
        }
        states.get_mut("ausburne").unwrap().damage_dp = 36.;
        assert_eq!(
            assess_cape_st_george(&states).unwrap().allies,
            Grade::Decisive
        );
        states.get_mut("ausburne").unwrap().damage_dp = 37.;
        assert_eq!(
            assess_cape_st_george(&states).unwrap().allies,
            Grade::Tactical
        );
        let mut states = fresh();
        for id in ["onami", "makinami", "amagiri", "yugiri", "uzuki"] {
            states.get_mut(id).unwrap().disposition = Disposition::Escaped;
        }
        states.get_mut("onami").unwrap().damage_dp = 34.;
        assert_eq!(
            assess_cape_st_george(&states).unwrap().axis,
            Grade::Decisive
        );
        states.get_mut("onami").unwrap().damage_dp = 35.;
        assert_eq!(
            assess_cape_st_george(&states).unwrap().axis,
            Grade::Tactical
        );
    }

    #[test]
    fn concurrent_tactical_success_preserves_both_grades_and_rejects_incomplete_snapshot() {
        let mut states = fresh();
        for id in ["onami", "makinami"] {
            states.get_mut(id).unwrap().disposition = Disposition::Sunk;
        }
        for id in ["amagiri", "yugiri", "uzuki"] {
            states.get_mut(id).unwrap().disposition = Disposition::Escaped;
        }
        assert_eq!(
            assess_cape_st_george(&states).unwrap(),
            Outcome {
                allies: Grade::Tactical,
                axis: Grade::Tactical
            }
        );
        states.get_mut("uzuki").unwrap().damage_dp = 1.;
        assert_eq!(assess_cape_st_george(&states).unwrap().axis, Grade::None);
        states.remove("spence");
        assert!(assess_cape_st_george(&states).is_err());
    }
}
