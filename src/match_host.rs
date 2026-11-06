use crate::{
    model::*,
    world::{u, World},
    Engine,
};
use serde_json::{json, Value};

// Hosts pin this version until both clients and the match service are upgraded.
pub(crate) const DUEL_VERSION: &str = crate::realtime::CURVE_VERSION;

impl Engine {
    pub fn handle_host(&mut self, request: Value) -> Value {
        let op = request["op"].as_str().unwrap_or("");
        if !op.starts_with("match_") && !self.world.as_ref().is_some_and(|w| w.host_duel) {
            return self.handle(request);
        }
        match self.execute_match(op, &request) {
            Ok(data) => json!({"ok":true,"data":data}),
            Err(error) => json!({"ok":false,"error":error}),
        }
    }

    fn execute_match(&mut self, op: &str, request: &Value) -> E<Value> {
        match op {
            "match_pool" => crate::ranked_fleets::catalogue(),
            "match_new_ranked" => {
                let config = serde_json::from_value(json!({"budget":request["budget"],
                    "points_version":request["points_version"], "fleets":request["fleets"]}))
                    .map_err(|_| "个人舰队对局编制无效")?;
                let world = World::new_ranked_duel(u(request, "seed")?, config)?;
                let status = match_status(&world);
                self.world = Some(world);
                Ok(status)
            }
            "match_new" => {
                let mut world = World::new(u(request, "seed")?, 0, "coord", "", "coord", 0)?;
                world.init_realtime(DUEL_VERSION)?;
                world.set_duel_seats();
                let status = match_status(&world);
                self.world = Some(world);
                Ok(status)
            }
            "match_load" => {
                let save: Saved = serde_json::from_value(request["save"].clone())
                    .map_err(|_| "无法读取权威双席存档")?;
                if !save.duel {
                    return Err("请选择权威双席存档".into());
                }
                let tick = save.tick;
                let world = World::from_save(save, tick)?;
                let status = match_status(&world);
                self.world = Some(world);
                Ok(status)
            }
            _ => {
                let world = self
                    .world
                    .as_mut()
                    .filter(|w| w.host_duel)
                    .ok_or("双席对局尚未开局")?;
                match op {
                    "match_save" => Ok(json!(world.save())),
                    "match_step" => {
                        let seconds = u(request, "seconds")?;
                        if seconds > 2700 {
                            return Err("单次推进不得超过 2700 秒".into());
                        }
                        for _ in 0..seconds {
                            if world.result.is_some() {
                                break;
                            }
                            world.advance();
                        }
                        Ok(match_status(world))
                    }
                    "match_observe" | "match_report" | "match_act" | "match_inspect" => {
                        let owner = side(request["seat"].as_str().ok_or("请选择当前席位")?)?;
                        let command = &request["command"];
                        match op {
                            "match_observe" => Ok(world.observation(owner)),
                            "match_report" => Ok(
                                json!({"result":world.result_for(owner),"events":world.visible_events(owner,None)}),
                            ),
                            "match_act" => {
                                world.external_for(owner, command.clone())?;
                                Ok(world.observation(owner))
                            }
                            _ => inspect(world, owner, command),
                        }
                    }
                    _ => Err("此权威对局只接受双席协议".into()),
                }
            }
        }
    }
}

fn match_status(world: &World) -> Value {
    json!({"tick":world.tick,"version":world.version,"result":world.result_for(0)})
}

fn inspect(world: &World, owner: usize, command: &Value) -> E<Value> {
    match command["op"].as_str() {
        Some("preview_route") => world.preview(owner, command),
        Some("preview_reform") => world.preview_reform(owner, command),
        Some("aim") => world.preview_aim(owner, command),
        Some("illumination_preview") => world.preview_illumination(owner, command),
        Some("suggest") if command.get("apply").is_none_or(|v| v == false) => {
            let orders = world.suggestions(owner, u(command, "fleet")?)?;
            let text = if orders.is_empty() {
                "没有可执行的建议"
            } else {
                "建议已按当前本方态势和权限生成"
            };
            Ok(json!({"orders":orders,"text":text}))
        }
        _ => Err("双席预览只接受查询操作".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ask(engine: &mut Engine, request: Value) -> Value {
        let reply = engine.handle_host(request);
        assert_eq!(reply["ok"], true, "{reply}");
        reply["data"].clone()
    }

    fn route(fleet: u32, x: u32, y: u32) -> Value {
        json!({"op":"route","fleet":fleet,"mode":"follow","speed":24,"points":[{"x":x,"y":y}]})
    }

    #[test]
    fn two_seats_share_clock_and_replay_without_sharing_orders() {
        let mut engine = Engine::default();
        assert_eq!(
            ask(&mut engine, json!({"op":"match_new","seed":6106}))["version"],
            DUEL_VERSION
        );
        for (seat, fleet, x, y) in [("allies", 1, 14_500, 6550), ("axis", 2, 9500, 7650)] {
            let view = ask(&mut engine, json!({"op":"match_observe","seat":seat}));
            assert_eq!(view["side"], seat);
            assert_eq!(view["ships"].as_array().unwrap().len(), 5);
            assert!(view["contacts"]
                .as_array()
                .unwrap()
                .iter()
                .all(|contact| contact.get("ship").is_none()));
            assert_eq!(view["fleets"].as_array().unwrap().len(), 1);
            assert_eq!(view["fleets"][0]["id"], fleet);
            assert_eq!(view["fleets"][0]["ai"]["mode"], "manual");
            let order = route(fleet, x, y);
            let other = if seat == "allies" { "axis" } else { "allies" };
            assert_eq!(
                engine.handle_host(json!({"op":"match_act","seat":other,"command":order}))["ok"],
                false
            );
            let mut preview = order.clone();
            preview["op"] = json!("preview_route");
            assert_eq!(
                engine.handle_host(json!({"op":"match_inspect","seat":other,"command":preview}))
                    ["ok"],
                false
            );
            ask(
                &mut engine,
                json!({"op":"match_act","seat":seat,"command":order}),
            );
            assert_eq!(engine.handle_host(json!({"op":"match_act","seat":seat,"command":{"op":"ai","fleet":fleet,"profile":"coord","mode":"auto","move":true,"gun":true,"torpedo":true}}))["ok"], false);
            assert_eq!(engine.handle_host(json!({"op":"match_inspect","seat":seat,"command":{"op":"suggest","fleet":fleet,"apply":true}}))["ok"], false);
        }
        ask(&mut engine, json!({"op":"match_step","seconds":540}));
        let save = ask(&mut engine, json!({"op":"match_save"}));
        assert_eq!(save["duel"], true);
        assert_eq!(save["commands"].as_array().unwrap().len(), 2);
        assert_eq!(save["commands"][0]["seat"], "allies");
        assert_eq!(save["commands"][1]["seat"], "axis");
        let mut restored = Engine::default();
        assert_eq!(
            restored.handle(json!({"op":"load","save":save}))["ok"],
            false
        );
        assert_eq!(engine.handle_host(json!({"op":"save"}))["ok"], false);
        ask(&mut restored, json!({"op":"match_load","save":save}));
        for seat in ["allies", "axis"] {
            for op in ["match_observe", "match_report"] {
                let request = json!({"op":op,"seat":seat});
                assert_eq!(
                    ask(&mut engine, request.clone()),
                    ask(&mut restored, request)
                );
            }
        }
        assert_eq!(ask(&mut restored, json!({"op":"match_save"})), save);
        assert!(engine
            .world
            .unwrap()
            .events
            .iter()
            .all(|event| !matches!(event.kind, "gun_fire" | "torp_launch")));
    }
}
