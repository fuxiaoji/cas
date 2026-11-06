//! First playable, explicitly restricted adaptation of Rising Sun p. 91.
use super::channel;
use super::{ClosedShip, Disposition, Grade};
use crate::{
    model::*,
    movement::fallback_leader,
    night::{Environment, Light},
    world::World,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{collections::BTreeMap, sync::OnceLock};

pub(crate) const VERSION: &str = "cas-campaign-v9";
pub(crate) const CURVE_VERSION: &str = "cas-campaign-v8";
pub(crate) const IMPACT_VERSION: &str = "cas-campaign-v7";
pub(crate) const CADENCE_VERSION: &str = "cas-campaign-v6";
pub(crate) const LEGACY_VERSION: &str = "cas-campaign-v5";

pub(crate) fn is_campaign_version(version: &str) -> bool {
    matches!(version, VERSION | CURVE_VERSION | IMPACT_VERSION | CADENCE_VERSION | LEGACY_VERSION)
}
pub(crate) const CONTENT: &str = "cas-cape-runtime-v1";
pub(crate) const VARIANT: &str = "cape-st-george-rts";
pub(crate) const LABEL: &str = "圣乔治角 · RTS 改编";
pub(crate) const FIELD: Field = Field {
    width: 64_000.,
    height: 40_000.,
    limit: 5400,
};
pub(crate) const WEST_EXIT: f64 = 1800.;
const ORIGIN: P = P {
    x: 14_000.,
    y: 13_000.,
};
const COLUMN_INTERVAL: f64 = 500. * YARD;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Start {
    pub stage_id: String,
    pub difficulty: String,
    pub content_version: String,
}
impl Start {
    pub(crate) fn new(stage_id: &str, difficulty: &str) -> Self {
        let mut start = Self {
            stage_id: stage_id.into(),
            difficulty: difficulty.into(),
            content_version: String::new(),
        };
        start.content_version = start.expected_content().into();
        start
    }
    pub(crate) fn is_channel(&self) -> bool {
        matches!(self.stage_id.as_str(), "CAMP-ALLIES-01" | "CAMP-AXIS-01")
    }
    pub(crate) fn variant(&self) -> &'static str {
        if self.is_channel() {
            channel::VARIANT
        } else {
            VARIANT
        }
    }
    pub(crate) fn limit(&self) -> u32 {
        if self.is_channel() {
            channel::LIMIT
        } else {
            FIELD.limit
        }
    }
    fn expected_content(&self) -> &'static str {
        if self.is_channel() {
            channel::CONTENT
        } else {
            CONTENT
        }
    }
    pub(crate) fn seat(&self) -> E<usize> {
        match self.stage_id.as_str() {
            "CAMP-ALLIES-03" | "CAMP-ALLIES-01" => Ok(0),
            "CAMP-AXIS-03" | "CAMP-AXIS-01" => Ok(1),
            _ => Err("此战役尚未通过出航核验".into()),
        }
    }
    pub(crate) fn enemy(&self) -> E<&'static str> {
        match self.difficulty.as_str() {
            "story" => Ok("coord"),
            "standard" => Ok("gunnery"),
            "challenge" => Ok("torpedo"),
            _ => Err("请选择有效的战役难度".into()),
        }
    }
}

#[derive(Deserialize)]
struct Layout {
    groups: Vec<Group>,
    environment: Weather,
}
#[derive(Deserialize)]
struct Weather {
    visibility_pct: u8,
    sea_state: u8,
}
#[derive(Deserialize)]
struct Group {
    id: String,
    side: String,
    unit: String,
    leader: String,
    course_deg: f64,
    speed_knots: f64,
    column_spacing_yd: Option<f64>,
    leader_position: Relative,
    members_in_order: Vec<String>,
}
#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Relative {
    ScenarioReference,
    BearingFromShip {
        ship: String,
        bearing_deg: f64,
        distance: f64,
        unit: String,
    },
    AsternOfGroup {
        group: String,
        distance: f64,
        unit: String,
        reference_ship: Option<String>,
    },
}
fn layout() -> &'static Layout {
    static LAYOUT: OnceLock<Layout> = OnceLock::new();
    LAYOUT.get_or_init(|| serde_json::from_str(super::CAPE).expect("verified Cape layout"))
}

pub(crate) fn character_id(ship: &str) -> Option<&'static str> {
    static CHARACTERS: OnceLock<BTreeMap<String, String>> = OnceLock::new();
    let characters = CHARACTERS.get_or_init(|| {
        let source: Value =
            serde_json::from_str(include_str!("../../data/campaign/roster-crosswalk.json"))
                .expect("pinned mobile identity crosswalk");
        source["ships"]
            .as_array()
            .expect("ship crosswalk")
            .iter()
            .filter_map(|row| {
                let instance = &row["cas_source_instance"];
                let id = if instance["scenario_id"] == "cas-rs-cape-st-george" {
                    instance["ship_id"].as_str()?
                } else {
                    // Channel Action's CAS cards are indexed by the original named hull ID.
                    row["ibs_ship_id"].as_str()?
                };
                Some((id.into(), row["ibs_character_id"].as_str()?.into()))
            })
            .collect()
    });
    characters.get(ship).map(String::as_str)
}

#[derive(Deserialize)]
struct Manifest {
    ships: Vec<ShipDef>,
    metadata: ManifestMetadata,
}
#[derive(Deserialize)]
struct ManifestMetadata {
    content_version: String,
    instance_fits: BTreeMap<String, Fit>,
}
#[derive(Deserialize)]
struct Fit {
    radar_confirmed: Vec<String>,
}
struct Runtime {
    data: Data,
    fits: BTreeMap<String, Fit>,
}
fn runtime() -> E<&'static Runtime> {
    static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();
    RUNTIME
        .get_or_init(|| {
            let manifest: Manifest =
                serde_json::from_str(include_str!("../../data/campaign/period/cape-runtime.json"))
                    .map_err(|e| format!("无法读取圣乔治角时期舰卡：{e}"))?;
            if manifest.metadata.content_version != CONTENT {
                return Err("战役内容版本不一致".into());
            }
            Ok(Runtime {
                data: Data {
                    ships: manifest.ships,
                    rules: World::exercise_data()?.rules.clone(),
                },
                fits: manifest.metadata.instance_fits,
            })
        })
        .as_ref()
        .map_err(Clone::clone)
}
fn metres(distance: f64, unit: &str) -> E<f64> {
    match unit {
        "yd" => Ok(distance * YARD),
        "nmi" => Ok(distance * 1852.),
        _ => Err("历史阵位距离单位未知".into()),
    }
}
pub(crate) fn environment() -> Environment {
    let weather = &layout().environment;
    // The original reports scattered squalls but supplies no cells or paths.
    Environment {
        visibility: weather.visibility_pct,
        sea_state: weather.sea_state,
        light: Light::Night,
        precipitation: false,
    }
}
fn objectives(seat: usize) -> &'static str {
    if seat == 0 {
        "截击日方撤离编队。击沉 2 艘驱逐舰获战术胜利；击沉至少 3 艘且所有己方驱逐舰损伤不超过 25%，获决定性胜利。"
    } else {
        "向西撤离，规划航点时确保队尾也能越线。三艘运输舰全部无损撤离获战术胜利；五艘全部撤离且各舰损伤低于 25%，获决定性胜利。"
    }
}

impl World {
    pub(crate) fn new_campaign(seed: u32, start: Start, profile: &str) -> E<Self> {
        let player = start.seat()?;
        let enemy = start.enemy()?;
        if start.content_version != start.expected_content() {
            return Err("此存档使用另一个战役内容版本".into());
        }
        Ai::new(profile, "manual").validate()?;
        if start.is_channel() {
            return channel::open(seed, start, player, enemy, profile);
        }
        let runtime = runtime()?;
        let mut w = Self::blank(&runtime.data, seed, player, enemy, VARIANT, profile, 0);
        w.field = FIELD;
        w.campaign = Some(start);
        let mut positions = BTreeMap::<&str, P>::new();
        let mut groups = BTreeMap::<&str, (P, f64)>::new();
        for (index, group) in layout().groups.iter().enumerate() {
            let id = index as u32 + 1;
            let owner = side(&group.side)?;
            let h = group.course_deg;
            let k = group.speed_knots;
            let heading = P::bearing(h);
            let lead = match &group.leader_position {
                Relative::ScenarioReference => ORIGIN,
                Relative::BearingFromShip {
                    ship,
                    bearing_deg,
                    distance,
                    unit,
                } => {
                    *positions.get(ship.as_str()).ok_or("缺少相对阵位基准舰")?
                        + P::bearing(*bearing_deg) * metres(*distance, unit)?
                }
                Relative::AsternOfGroup {
                    group,
                    distance,
                    unit,
                    reference_ship,
                } => {
                    let &(first, bearing) =
                        groups.get(group.as_str()).ok_or("缺少相对阵位基准编队")?;
                    let anchor = match reference_ship {
                        Some(ship) => *positions.get(ship.as_str()).ok_or("缺少运输编队基准舰")?,
                        None => first,
                    };
                    anchor - P::bearing(bearing) * metres(*distance, unit)?
                }
            };
            if group.members_in_order.first() != Some(&group.leader) {
                return Err("历史领舰不在纵队首位".into());
            }
            let spacing = group
                .column_spacing_yd
                .map_or(COLUMN_INTERVAL, |d| d * YARD);
            let mut members = vec![];
            for (order, name) in group.members_in_order.iter().enumerate() {
                let p = (lead - heading * (order as f64 * spacing)).snap();
                let def = w
                    .data
                    .ships
                    .iter()
                    .position(|s| &s.id == name)
                    .ok_or("缺少具名时期舰卡")?;
                let fit = runtime.fits.get(name).ok_or("缺少具名时期配置")?;
                let ship = w.spawn(def, owner, id, w.data.ships[def].name.clone(), p, h)?;
                positions.insert(name, p);
                members.push(ship);
                // Carry only the confirmed US 1943 fit; no Japanese candidate.
                if owner == 0
                    && ["us_sg", "us_sc2", "us_mk4_fd"]
                        .iter()
                        .all(|set| fit.radar_confirmed.iter().any(|f| f == set))
                {
                    w.radar.equip_fletcher_1943(ship)?;
                }
                let distance = if owner == 1 {
                    (400. - p.x) / heading.x
                } else {
                    (FIELD.height - 1000. - p.y) / heading.y
                };
                let end = (p + heading * distance).snap();
                if !FIELD.contains(end) {
                    return Err("初始航路超出战区".into());
                }
                let s = w.ship_mut(ship).unwrap();
                s.speed = k;
                s.track = Some(Track::new(vec![p, end], 0., p.dist(end)));
            }
            groups.insert(&group.id, (lead, h));
            let mut ai = Ai::new(
                if owner == player { profile } else { enemy },
                if owner == player { "manual" } else { "auto" },
            );
            if owner == 1 && owner != player {
                ai.r#move = false;
            }
            let lead_id = members[0];
            let points = w.ship(lead_id).unwrap().track.as_ref().unwrap().remaining();
            w.fleets.push(Fleet {
                id,
                side: owner,
                name: group.unit.clone(),
                leader: lead_id,
                members,
                mode: "follow".into(),
                speed: k,
                actual: k,
                turn_degrees: 0.,
                points,
                ai,
                notice: None,
                last_ai_route: 0,
                tactic: Tactic::Search,
            });
        }
        w.gun_streak.resize(w.ships.len(), (0, 0, 0));
        w.surface_damage.resize(w.ships.len(), Default::default());
        w.enable_realtime()?;
        for seat in 0..2 {
            w.add(
                1 << seat,
                "start",
                format!("{LABEL}｜{}", objectives(seat)),
                Some("RTS-CAPE-01"),
                None,
            );
        }
        w.detect(true);
        w.radar_detect();
        Ok(w)
    }

    pub(crate) fn campaign_view(&self, owner: usize) -> Option<Value> {
        let start = self.campaign.as_ref()?;
        let mut view = if start.is_channel() {
            channel::view(start, owner)
        } else {
            let stage = if owner == 0 {
                "CAMP-ALLIES-03"
            } else {
                "CAMP-AXIS-03"
            };
            json!({"stageId":stage,"difficulty":start.difficulty,"missionLabel":LABEL,
                "objectives":objectives(owner),"withdrawalX":WEST_EXIT})
        };
        if self.result.is_some() {
            // The tactical projection contains only ships still on the chart. The
            // debrief also needs this seat's sunk and withdrawn participants.
            let roster: Vec<_> = self.ships.iter().filter(|ship| ship.side == owner).map(|ship| {
                let class = &self.data.ships[ship.def].id;
                json!({"name":ship.name,"classId":class,"characterId":character_id(class)})
            }).collect();
            view["roster"] = json!(roster);
        }
        Some(view)
    }
    pub(crate) fn result_for(&self, owner: usize) -> Value {
        let mut value = json!(self.result);
        if let Some(outcome) = self.campaign_result {
            let grade = if owner == 0 {
                outcome.allies
            } else {
                outcome.axis
            };
            value["grade"] = json!(grade);
            value["primary"] = json!(grade_text(grade));
        }
        value
    }

    pub(crate) fn campaign_departures(&mut self) {
        let ships: Vec<_> = self
            .ships
            .iter()
            .filter(|s| s.side == 1 && s.alive() && s.p.x <= WEST_EXIT)
            .map(|s| (s.id, s.fleet, s.name.clone(), s.p))
            .collect();
        for (id, fleet, name, p) in ships {
            let s = self.ship_mut(id).unwrap();
            s.escaped = true;
            s.track = None;
            s.speed = 0.;
            self.add(
                2,
                "withdrawal",
                format!("{name} 已越线撤离"),
                Some("RTS-CAPE-01"),
                Some(p),
            );
            if self.knows(0, id) {
                self.add(
                    1,
                    "withdrawal",
                    "观测到一艘敌舰离开交战海域".into(),
                    Some("RTS-CAPE-01"),
                    Some(p),
                );
            }
            for contacts in &mut self.contacts {
                contacts.retain(|c| c.ship != id);
            }
            if let Some(fleet) = fleet {
                if self.fleet(fleet).is_some_and(|f| f.leader == id) {
                    if let Some(replacement) = fallback_leader(self, fleet, id) {
                        self.fleet_mut(fleet).unwrap().leader = replacement;
                    }
                }
            }
        }
    }

    pub(crate) fn close_campaign(&mut self, allied_sunk: u32, axis_sunk: u32) {
        if self.variant == channel::VARIANT {
            let outcome = channel::assess(self, allied_sunk);
            self.finish_campaign(outcome, allied_sunk, axis_sunk, "RTS-CHANNEL-01");
            return;
        }
        let states = self
            .ships
            .iter()
            .map(|s| {
                let def = &self.data.ships[s.def];
                (
                    def.id.clone(),
                    ClosedShip {
                        damage_dp: (def.dp - s.hp).clamp(0., def.dp),
                        disposition: if s.escaped {
                            Disposition::Escaped
                        } else if s.hp <= 0. {
                            Disposition::Sunk
                        } else {
                            Disposition::Present
                        },
                    },
                )
            })
            .collect();
        let outcome = super::assess_cape_st_george(&states)
            .expect("campaign ships and goal schema validated together");
        self.finish_campaign(outcome, allied_sunk, axis_sunk, "CAS-RS-P91");
    }
    fn finish_campaign(
        &mut self,
        outcome: super::Outcome,
        allied_sunk: u32,
        axis_sunk: u32,
        rule: &'static str,
    ) {
        let winner = match outcome.allies.cmp(&outcome.axis) {
            std::cmp::Ordering::Greater => "allies",
            std::cmp::Ordering::Less => "axis",
            std::cmp::Ordering::Equal => "draw",
        };
        self.campaign_result = Some(outcome);
        self.result = Some(Outcome {
            winner: winner.into(),
            allies: axis_sunk,
            axis: allied_sunk,
            primary: None,
        });
        for (owner, grade) in [outcome.allies, outcome.axis].into_iter().enumerate() {
            self.add(
                1 << owner,
                "end",
                format!("战役结束：{}", grade_text(grade)),
                Some(rule),
                None,
            );
            self.last_voice(
                owner,
                Some(if grade == Grade::None {
                    "defeat"
                } else {
                    "victory"
                }),
            );
        }
    }
}

fn grade_text(grade: Grade) -> &'static str {
    match grade {
        Grade::None => "未达成本方战役胜利条件",
        Grade::Tactical => "本方达成战术胜利",
        Grade::Decisive => "本方达成决定性胜利",
    }
}

#[cfg(test)]
mod tests {
    use crate::Engine;
    use serde_json::{json, Value};

    fn request(engine: &mut Engine, message: Value) -> Value {
        let reply = engine.handle(message.clone());
        assert_eq!(reply["ok"], true, "{message}: {reply}");
        reply["data"].clone()
    }
    fn opening(engine: &mut Engine, id: &str) -> Value {
        request(
            engine,
            json!({"op":"new_campaign","id":id,"difficulty":"story","seed":6106}),
        )
    }

    #[test]
    fn direct_radar_requires_two_windows_and_a_live_own_solution_at_launch() {
        let mut e = Engine::default();
        let start = opening(&mut e, "CAMP-ALLIES-03");
        assert!(start["radarContacts"]
            .as_array()
            .unwrap()
            .iter()
            .all(|r| r["torpedoForShipIds"] == json!([])));
        let aim = json!({"op":"aim","weapon":"torpedo","ship":1,"target":"R01"});
        assert_eq!(e.handle(aim.clone())["ok"], false);
        for fleet in [1, 2] {
            request(
                &mut e,
                json!({"op":"ai","fleet":fleet,"profile":"torpedo","mode":"auto","move":true,"gun":false,"torpedo":false}),
            );
        }
        let current = request(&mut e, json!({"op":"step","seconds":540}));
        let plan = request(&mut e, aim);
        assert_eq!(plan["valid"], true);
        request(
            &mut e,
            json!({"op":"fire","weapon":"torpedo","ship":1,"target":"R01","heading":plan["heading"]}),
        );
        let accepted = request(&mut e, json!({"op":"save"}));
        for radar in ["us_sg", "us_sc2", "us_mk4_fd"] {
            request(
                &mut e,
                json!({"op":"radar_set","ship":1,"radar":radar,"powered":false}),
            );
        }
        let denied = request(&mut e, json!({"op":"step","seconds":180}));
        let own_ammo = |v: &Value| {
            v["ships"]
                .as_array()
                .unwrap()
                .iter()
                .find(|s| s["id"] == 1)
                .unwrap()["ammo"]
                .as_u64()
        };
        assert_eq!(own_ammo(&current), own_ammo(&denied));
        assert!(denied["events"]
            .as_array()
            .unwrap()
            .iter()
            .any(|r| r["kind"] == "rejected"));
        request(&mut e, json!({"op":"load","save":accepted}));
        let executed = request(&mut e, json!({"op":"step","seconds":180}));
        assert!(own_ammo(&executed).unwrap() < own_ammo(&current).unwrap());
        assert!(executed["torpedoes"]
            .as_array()
            .unwrap()
            .iter()
            .any(|t| t["own"] == true && t["trail"].is_array()));
    }

    #[test]
    fn named_cape_sortie_hits_with_torpedoes_and_replays_without_exposing_other_seat() {
        let mut e = Engine::default();
        let start = request(
            &mut e,
            json!({"op":"new_campaign","id":"CAMP-ALLIES-03","difficulty":"story","seed":6177}),
        );
        assert_eq!(start["ships"].as_array().unwrap().len(), 5);
        assert_eq!(start["ships"][0]["classId"], "ausburne");
        assert_eq!(start["ships"][0]["characterId"], "IBS-U-USN-CF-AUSBURNE");
        assert_eq!(start["environment"]["visibility"], 10);
        assert_eq!(start["environment"]["sea_state"], 1);
        assert_eq!(start["contacts"], json!([]));
        for fleet in [1, 2] {
            request(
                &mut e,
                json!({"op":"ai","fleet":fleet,"profile":"torpedo","mode":"auto","move":true,"gun":true,"torpedo":true}),
            );
        }
        let mut end = request(&mut e, json!({"op":"step","seconds":2700}));
        if end["result"].is_null() {
            end = request(&mut e, json!({"op":"step","seconds":2700}));
        }
        assert_eq!(end["result"]["grade"], "decisive");
        let report = request(&mut e, json!({"op":"report"}));
        assert!(report["events"]
            .as_array()
            .unwrap()
            .iter()
            .any(|r| r["kind"] == "torpedo_hit"));
        let mut save = request(&mut e, json!({"op":"save"}));
        assert_eq!(request(&mut e, json!({"op":"replay","save":save})), end);
        save["campaign"]["contentVersion"] = json!("unknown");
        assert_eq!(e.handle(json!({"op":"load","save":save}))["ok"], false);
        assert_eq!(request(&mut e, json!({"op":"observe"})), end);
        let axis = opening(&mut e, "CAMP-AXIS-03");
        assert_eq!(axis["radarContacts"], json!([]));
        assert_eq!(axis["ships"][0]["classId"], "onami");
        assert!(axis["ships"]
            .as_array()
            .unwrap()
            .iter()
            .skip(2)
            .all(|s| s["ammo"] == 0));
    }

    #[test]
    fn both_axis_columns_must_cross_the_line_to_earn_decisive_victory() {
        let mut e = Engine::default();
        let start = opening(&mut e, "CAMP-AXIS-03");
        assert!(start["campaign"].get("roster").is_none());
        for (fleet, x, y, speed) in [(3, 30_000, 35_000, 35), (4, 33_000, 3_000, 33)] {
            request(
                &mut e,
                json!({"op":"route","fleet":fleet,"mode":"follow","speed":speed,
                "points":[{"x":x,"y":y},{"x":400,"y":y}]}),
            );
            request(
                &mut e,
                json!({"op":"ai","fleet":fleet,"profile":"torpedo","mode":"auto","move":false,"gun":true,"torpedo":true}),
            );
        }
        let interim = request(&mut e, json!({"op":"step","seconds":2700}));
        assert!(interim["result"].is_null());
        let end = request(&mut e, json!({"op":"step","seconds":2700}));
        assert_eq!(end["result"]["grade"], "decisive");
        assert_eq!(end["result"]["allies"], 0);
        assert!(end["ships"].as_array().unwrap().is_empty());
        let roster = end["campaign"]["roster"].as_array().unwrap();
        assert_eq!(roster.len(), 5);
        assert!(roster.iter().all(|ship| ship["characterId"]
            .as_str().is_some_and(|id| id.starts_with("IBS-U-IJN-"))));
        assert!(roster.iter().any(|ship| ship["characterId"] == "IBS-U-IJN-UZUKI"));
        let report = request(&mut e, json!({"op":"report"}));
        let withdrawals: Vec<_> = report["events"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|r| r["kind"] == "withdrawal")
            .collect();
        assert_eq!(withdrawals.len(), 5);
        assert!(withdrawals
            .iter()
            .all(|r| r["x"].as_f64().unwrap() <= super::WEST_EXIT));
        let save = request(&mut e, json!({"op":"save"}));
        assert_eq!(request(&mut e, json!({"op":"replay","save":save})), end);
    }
}
