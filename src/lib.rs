mod ai;
#[cfg(not(target_arch = "wasm32"))]
pub mod ai_evolve;
mod challenge;
mod empress;
pub mod campaign;
mod combat;
mod damage;
mod illumination;
#[cfg(not(target_arch = "wasm32"))]
mod match_host;
mod ranked_fleets;
mod model;
mod movement;
mod night;
mod projectile;
mod prologue;
mod radar;
mod realtime;
mod sighting;
mod world;
use model::*;
use serde_json::{json, Value};
use world::World;

pub struct Engine {
    world: Option<World>,
}
impl Default for Engine {
    fn default() -> Self {
        Self { world: None }
    }
}
impl Engine {
    pub fn handle(&mut self, r: Value) -> Value {
        match self.execute(r) {
            Ok(v) => json!({"ok":true,"data":v}),
            Err(e) => json!({"ok":false,"error":e}),
        }
    }
    fn execute(&mut self, r: Value) -> E<Value> {
        let op = r.get("op").and_then(Value::as_str).ok_or("缺少操作")?;
        match op {
            "info" => Ok(json!({"version":VERSION,"realtimeVersion":realtime::VERSION,"scenario":SCENARIO,"tickSeconds":1})),
            "campaign" => campaign::catalogue(),
            "campaign_detail" => campaign::detail(
                r["id"].as_str().ok_or("请选择战役关卡")?,
            ),
            "new_campaign" => {
                let id = r["id"].as_str().ok_or("请选择战役关卡")?;
                let difficulty = r["difficulty"].as_str().ok_or("请选择战役难度")?;
                let seed = if r.get("seed").is_some() { world::u(&r, "seed")? } else { 6106 };
                let profile = r.get("profile").and_then(Value::as_str).unwrap_or("coord");
                let mut start = campaign::live::Start::new(id, difficulty);
                start.fleet = r.get("fleet").and_then(Value::as_array).map(|picks| {
                    picks.iter().filter_map(Value::as_str).map(str::to_string).collect()
                });
                start.groups = match r.get("groups") {
                    None => None,
                    Some(value) => Some(serde_json::from_value(value.clone())
                        .map_err(|error| format!("特混编成格式无效：{error}"))?),
                };
                let w = World::new_campaign(seed, start, profile)?;
                let view = w.observation(w.player);
                self.world = Some(w);
                Ok(view)
            }
            "campaign_fleet" => {
                let id = r["id"].as_str().ok_or("请选择战役关卡")?;
                let difficulty = r.get("difficulty").and_then(Value::as_str).unwrap_or("story");
                let seed = if r.get("seed").is_some() { world::u(&r, "seed")? } else { 6106 };
                let w = World::new_campaign(seed, campaign::live::Start::new(id, difficulty), "coord")?;
                Ok(campaign::fleet::options(&w))
            }
            "new" => {
                let seed = match r.get("seed") {
                    None => 6106,
                    Some(v) => v
                        .as_u64()
                        .and_then(|n| u32::try_from(n).ok())
                        .ok_or("种子须是 32 位非负整数")?,
                };
                let side = side(r.get("side").and_then(Value::as_str).unwrap_or("allies"))?;
                let enemy = r.get("enemy").and_then(Value::as_str).unwrap_or("coord");
                let variant = r.get("variant").and_then(Value::as_str).unwrap_or("");
                let profile = r.get("profile").and_then(Value::as_str).unwrap_or("coord");
                // Challenge stages may field up to eight hulls; the printed
                // exercises and campaigns keep their five-slot ceiling.
                let leader_limit = if variant == challenge::VARIANT { 8 } else { 5 };
                let leader_slot = r
                    .get("leaderSlot")
                    .map(|v| v.as_u64().filter(|v| *v < leader_limit).ok_or("领舰位置无效"))
                    .transpose()?
                    .unwrap_or(0) as usize;
                let mut w = if variant == challenge::VARIANT {
                    let stage = r.get("stage").and_then(Value::as_str).unwrap_or("challenge-01");
                    World::new_challenge(seed, side, enemy, profile, leader_slot, stage)?
                } else {
                    World::new(seed, side, enemy, variant, profile, leader_slot)?
                };
                if let Some(opt) = r.get("realtime") {
                    if opt.as_bool().ok_or("实时炮击选项无效")? && !w.realtime() {
                        w.enable_realtime()?;
                    }
                }
                let v = w.observation(side);
                self.world = Some(w);
                Ok(v)
            }
            "load" | "replay" => {
                let v = r.get("save").ok_or("没有存档")?;
                let s: Saved =
                    serde_json::from_value(v.clone()).map_err(|_| "无法读取 CAS 存档")?;
                if s.duel {
                    return Err("双席对局由权威主机恢复".into());
                }
                let tick = if op == "replay" {
                    r.get("tick")
                        .and_then(Value::as_u64)
                        .unwrap_or(s.tick as u64)
                        .min(s.tick as u64) as u32
                } else {
                    s.tick
                };
                let w = World::from_save(s, tick)?;
                let v = w.observation(w.player);
                if op == "load" {
                    self.world = Some(w);
                }
                Ok(v)
            }
            _ => {
                let w = self.world.as_mut().ok_or("请先开始演习")?;
                let player = w.player;
                match op {
                    "observe" => Ok(w.observation(player)),
                    "step" => {
                        let n = r
                            .get("seconds")
                            .and_then(Value::as_u64)
                            .ok_or("缺少推进秒数")?;
                        if n > 2700 {
                            return Err("单次推进不得超过 2700 秒".into());
                        }
                        for _ in 0..n {
                            if w.result.is_some() {
                                break;
                            }
                            w.advance();
                        }
                        Ok(w.observation(player))
                    }
                    "save" => Ok(json!(w.save())),
                    "report" => {
                        Ok(json!({"result":w.result_for(player),"events":w.visible_events(player,None)}))
                    }
                    "preview_route" => w.preview(player, &r),
                    "preview_reform" => w.preview_reform(player, &r),
                    "aim" => w.preview_aim(player, &r),
                    "illumination_preview" => w.preview_illumination(player, &r),
                    "suggest" => {
                        let f = world::u(&r, "fleet")?;
                        let orders = w.suggestions(player, f)?;
                        if r.get("apply").and_then(Value::as_bool) == Some(true) {
                            for cmd in &orders {
                                let _ = w.external(cmd.clone());
                            }
                        }
                        let text = if orders.is_empty() {
                            "没有可执行的建议"
                        } else {
                            "建议已按当前本方态势和权限生成"
                        };
                        Ok(json!({"orders":orders,"text":text}))
                    }
                    "route" | "fire" | "gun_cancel" | "lead" | "detach" | "reform" | "ai" | "radar_set" | "illuminate" | "searchlight" | "smoke" | "speed" | "resume" => {
                        w.external(r)?;
                        Ok(w.observation(player))
                    }
                    _ => Err("未知操作".into()),
                }
            }
        }
    }
}

#[cfg(target_arch = "wasm32")]
mod wasm {
    use super::*;
    use std::cell::RefCell;
    thread_local! {
        static ENGINE:RefCell<Engine>=RefCell::new(Engine::default());
        static OUTPUT:RefCell<Vec<u8>>=const {RefCell::new(Vec::new())};
    }
    #[no_mangle]
    pub extern "C" fn cas_alloc(len: u32) -> u32 {
        Box::into_raw(vec![0_u8; len as usize].into_boxed_slice()) as *mut u8 as u32
    }
    #[no_mangle]
    pub extern "C" fn cas_request(ptr: u32, len: u32) -> u32 {
        let raw = std::ptr::slice_from_raw_parts_mut(ptr as *mut u8, len as usize);
        // The worker allocated this exact slice via cas_alloc and transfers ownership once.
        let input = unsafe { Box::from_raw(raw) };
        let v = match serde_json::from_slice(&input) {
            Ok(r) => ENGINE.with(|engine| engine.borrow_mut().handle(r)),
            Err(_) => json!({"ok":false,"error":"无法识别命令数据"}),
        };
        OUTPUT.with(|s| {
            let mut s = s.borrow_mut();
            *s = serde_json::to_vec(&v).unwrap();
            s.as_ptr() as u32
        })
    }
    #[no_mangle]
    pub extern "C" fn cas_response_len() -> u32 {
        OUTPUT.with(|s| s.borrow().len() as u32)
    }
}

#[cfg(test)]
mod tests;
