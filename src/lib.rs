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
mod arena;
mod model;
mod movement;
mod night;
mod projectile;
mod projectile_presentation;
mod prologue;
mod radar;
mod realtime;
mod sighting;
mod world;
mod salvage;
mod salvage_v3;
mod salvage_v4;
mod story_missions;
mod adventure;
mod expedition;
mod extraction_ai;
mod fuel;
mod intel;
mod tide;
mod tide_v2;
mod amphibious_expedition;
mod littoral;
pub(crate) use littoral::v4 as littoral_v4;
use littoral_v4::island_war;
use island_war::v4_base::v4 as island4;
mod cargo_transfer;
mod salvage_weather;
mod owned_growth;
mod geography_snapshot;
use model::*;
use serde_json::{json, Value};
use world::World;

pub struct Engine {
    world: Option<World>,
    tide:Option<TideMode>,
    littoral:Option<littoral::Littoral>,
    littoral_v4:Option<littoral_v4::Battle>,
    island_war:Option<island_war::Battle>,
    island_replay:Option<island_war::Replay>,
    island_war_v2:Option<island_war::v2::Battle>,
    island_replay_v2:Option<island_war::v2::Replay>,
    island_war_v4:Option<island4::Battle>,
    island_replay_v4:Option<island4::Replay>,
    island_war_v3:Option<island_war::v2::v3::Battle>,
    island_replay_v3:Option<island_war::v2::v3::Replay>,
}
enum TideMode { V1(tide::Tide), V2(tide_v2::Tide) }
impl TideMode {
    fn view(&self)->Value {match self {Self::V1(w)=>w.view(),Self::V2(w)=>w.view()}}
    fn save(&self)->Value {match self {Self::V1(w)=>json!(w.save()),Self::V2(w)=>json!(w.save())}}
    fn tick(&self)->Value {match self {Self::V1(w)=>json!(w.tick),Self::V2(w)=>json!(w.tick())}}
    fn result(&self)->&Option<Value> {match self {Self::V1(w)=>&w.result,Self::V2(w)=>&w.result}}
    fn command(&mut self,q:&Value)->E<Value> {match self {Self::V1(w)=>w.command(q,true),Self::V2(w)=>w.command(q,true)}}
    fn preview(&self,q:&Value)->Value {match self {Self::V1(w)=>w.preview(q),Self::V2(w)=>w.preview(q)}}
    fn step(&mut self,seconds:&Value)->E<Value> {
        match self {
            Self::V1(w)=>{let n=seconds.as_u64().filter(|n|*n<=2700).ok_or("活动推进秒数无效")?;for _ in 0..n {if w.paused()||w.result.is_some(){break;}w.advance();}Ok(w.view())},
            Self::V2(w)=>{let n=tide_v2::frames(seconds)?;for _ in 0..n {if w.paused()||w.result.is_some(){break;}w.advance();}Ok(w.view())},
        }
    }
}
impl Default for Engine {
    fn default() -> Self {
        Self { world: None,tide:None,littoral:None,littoral_v4:None,island_war:None,island_replay:None,island_war_v2:None,island_replay_v2:None,island_war_v3:None,island_replay_v3:None,island_war_v4:None,island_replay_v4:None }
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
        if op == "geography_snapshot" {
            if r.get("home").and_then(Value::as_bool).unwrap_or(false) {
                return geography_snapshot::home_snapshot(&r);
            }
            let observation = self.execute(json!({"op":"observe"}))?;
            return geography_snapshot::snapshot(&observation, &r);
        }
        if op=="island_home_preview"&&r["version"]==island4::VERSION{return island_war::v4_base::home_preview(&r)}
        if op=="island_war_catalogue"&&r["version"]==island4::VERSION{return Ok(island4::catalogue())}
        if op=="new_island_battle"&&r["version"]==island4::VERSION{let(seed,start)=island4::Battle::decode(r.clone())?;let w=island4::Battle::new(seed,start)?;let v=w.view();self.world=None;self.tide=None;self.littoral=None;self.littoral_v4=None;self.island_war=None;self.island_war_v2=None;self.island_war_v3=None;self.island_war_v4=Some(w);return Ok(v)}
        if ["load","replay"].contains(&op)&&r["save"]["version"]==island4::VERSION{let s:island4::Saved=serde_json::from_value(r["save"].clone()).map_err(|e|format!("新版海岛录像格式无效：{e}"))?;let end=if op=="replay"{r.get("tick").map(littoral::frames).transpose()?.unwrap_or(s.frame)}else{s.frame};if op=="replay"{if self.island_replay_v4.as_ref().is_some_and(|p|p.matches(&s)){return self.island_replay_v4.as_mut().unwrap().seek(end)}let mut p=island4::Replay::open(s,end)?;let v=p.seek(end)?;self.island_replay_v4=Some(p);return Ok(v)}let w=island4::Battle::from_save(s,Some(end))?;let v=w.view();self.world=None;self.tide=None;self.littoral=None;self.littoral_v4=None;self.island_war=None;self.island_war_v2=None;self.island_war_v3=None;self.island_war_v4=Some(w);return Ok(v)}
        if self.island_war_v4.is_some(){if !["new_island_battle","new_littoral","new_tide","new_arena","new_chapter","new_salvage","new_campaign","new","load","replay","campaign","campaign_detail","info","arena_catalogue","fuel_preview","campaign_fleet","littoral_catalogue","island_war_catalogue"].contains(&op){return self.island_war_v4.as_mut().unwrap().execute(&r)}if ["new_island_battle","new_littoral","new_tide","new_arena","new_chapter","new_salvage","new_campaign","new","load"].contains(&op){self.island_war_v4=None;}}
        if op=="island_war_catalogue"&&r["version"]==island_war::v2::v3::VERSION{return Ok(island_war::v2::v3::catalogue())}
        if op=="new_island_battle"&&r["version"]==island_war::v2::v3::VERSION{let(seed,start)=island_war::v2::v3::Battle::decode(r.clone())?;let w=island_war::v2::v3::Battle::new(seed,start)?;let v=w.view();self.world=None;self.tide=None;self.littoral=None;self.littoral_v4=None;self.island_war=None;self.island_war_v2=None;self.island_war_v3=Some(w);return Ok(v)}
        if ["load","replay"].contains(&op)&&r["save"]["version"]==island_war::v2::v3::VERSION{let s:island_war::v2::v3::Saved=serde_json::from_value(r["save"].clone()).map_err(|e|format!("新版海岛录像格式无效：{e}"))?;let end=if op=="replay"{r.get("tick").map(littoral::frames).transpose()?.unwrap_or(s.frame)}else{s.frame};if op=="replay"{if self.island_replay_v3.as_ref().is_some_and(|p|p.matches(&s)){return self.island_replay_v3.as_mut().unwrap().seek(end)}let mut p=island_war::v2::v3::Replay::open(s,end)?;let v=p.seek(end)?;self.island_replay_v3=Some(p);return Ok(v)}let w=island_war::v2::v3::Battle::from_save(s,Some(end))?;let v=w.view();self.world=None;self.tide=None;self.littoral=None;self.littoral_v4=None;self.island_war=None;self.island_war_v2=None;self.island_war_v3=Some(w);return Ok(v)}
        if self.island_war_v3.is_some(){if !["new_island_battle","new_littoral","new_tide","new_arena","new_chapter","new_salvage","new_campaign","new","load","replay","campaign","campaign_detail","info","arena_catalogue","fuel_preview","campaign_fleet","littoral_catalogue","island_war_catalogue"].contains(&op){return self.island_war_v3.as_mut().unwrap().execute(&r)}if ["new_island_battle","new_littoral","new_tide","new_arena","new_chapter","new_salvage","new_campaign","new","load"].contains(&op){self.island_war_v3=None;}}
        if op=="island_war_catalogue"&&r["version"]==island_war::v2::VERSION{return Ok(island_war::v2::catalogue())}
        if op=="new_island_battle"&&r["version"]==island_war::v2::VERSION{let(seed,start)=island_war::v2::Battle::decode(r.clone())?;let w=island_war::v2::Battle::new(seed,start)?;let v=w.view();self.world=None;self.tide=None;self.littoral=None;self.littoral_v4=None;self.island_war=None;self.island_war_v2=Some(w);return Ok(v)}
        if ["load","replay"].contains(&op)&&r["save"]["version"]==island_war::v2::VERSION{let s:island_war::v2::Saved=serde_json::from_value(r["save"].clone()).map_err(|e|format!("新版海岛录像格式无效：{e}"))?;let end=if op=="replay"{r.get("tick").map(littoral::frames).transpose()?.unwrap_or(s.frame)}else{s.frame};if op=="replay"{if self.island_replay_v2.as_ref().is_some_and(|p|p.matches(&s)){return self.island_replay_v2.as_mut().unwrap().seek(end)}let mut p=island_war::v2::Replay::open(s,end)?;let v=p.seek(end)?;self.island_replay_v2=Some(p);return Ok(v)}let w=island_war::v2::Battle::from_save(s,Some(end))?;let v=w.view();self.world=None;self.tide=None;self.littoral=None;self.littoral_v4=None;self.island_war=None;self.island_war_v2=Some(w);return Ok(v)}
        if self.island_war_v2.is_some(){if !["new_island_battle","new_littoral","new_tide","new_arena","new_chapter","new_salvage","new_campaign","new","load","replay","campaign","campaign_detail","info","arena_catalogue","fuel_preview","campaign_fleet","littoral_catalogue","island_war_catalogue"].contains(&op){return self.island_war_v2.as_mut().unwrap().execute(&r)}if ["new_island_battle","new_littoral","new_tide","new_arena","new_chapter","new_salvage","new_campaign","new","load"].contains(&op){self.island_war_v2=None;}}
        if op=="island_war_catalogue"{return Ok(island_war::catalogue())}
        if op=="new_island_battle"{let(seed,start)=island_war::Battle::decode(r.clone())?;let w=island_war::Battle::new(seed,start)?;let v=w.view();self.world=None;self.tide=None;self.littoral=None;self.littoral_v4=None;self.island_war=Some(w);return Ok(v)}
        if ["load","replay"].contains(&op)&&r["save"]["version"]==island_war::VERSION{let saved:island_war::Saved=serde_json::from_value(r["save"].clone()).map_err(|e|format!("海岛录像格式无效：{e}"))?;let end=if op=="replay"{r.get("tick").map(littoral::frames).transpose()?.unwrap_or(saved.frame)}else{saved.frame};if op=="replay"{if self.island_replay.as_ref().is_some_and(|p|p.matches(&saved)){return self.island_replay.as_mut().unwrap().seek(end)}let mut p=island_war::Replay::open(saved,end)?;let v=p.seek(end)?;self.island_replay=Some(p);return Ok(v)}let w=island_war::Battle::from_save(saved,Some(end))?;let v=w.view();self.world=None;self.tide=None;self.littoral=None;self.littoral_v4=None;self.island_war=Some(w);return Ok(v)}
        if self.island_war.is_some(){if !["new_littoral","new_tide","new_arena","new_chapter","new_salvage","new_campaign","new","load","replay","campaign","campaign_detail","info","arena_catalogue","fuel_preview","campaign_fleet","littoral_catalogue"].contains(&op){return self.island_war.as_mut().unwrap().execute(&r)}if ["new_littoral","new_tide","new_arena","new_chapter","new_salvage","new_campaign","new","load"].contains(&op){self.island_war=None;}}
        if op=="littoral_catalogue"&&r["version"]==littoral_v4::VERSION{return littoral_v4::catalogue();}
        if op=="littoral_catalogue" {return littoral::catalogue_version(r.get("version").and_then(Value::as_str).unwrap_or(littoral::VERSION));}
        if op=="new_littoral"&&r["version"]==littoral_v4::VERSION{let seed=world::u(&r,"seed")?;let mut config=r.clone();for k in ["op","version","seed"]{config.as_object_mut().ok_or("两栖配置无效")?.remove(k);}let config=littoral::decode_config(config,littoral_v4::VERSION).map_err(|e|format!("两栖配置无效：{e}"))?;let w=littoral_v4::Battle::new(seed,config)?;let v=w.view();self.world=None;self.tide=None;self.littoral=None;self.littoral_v4=None;self.littoral_v4=Some(w);return Ok(v);}
        if ["load","replay"].contains(&op)&&r["save"]["version"]==littoral_v4::VERSION{littoral::decode_config(r["save"]["config"].clone(),littoral_v4::VERSION).map_err(|_|"v4配置无效")?;let saved:littoral::Saved=serde_json::from_value(r["save"].clone()).map_err(|_|"v4存档格式无效")?;let target=if op=="replay"{r.get("tick").map(littoral::frames).transpose()?}else{None};let w=littoral_v4::Battle::from_save(saved,target)?;let v=w.view();if op=="load"{self.world=None;self.tide=None;self.littoral=None;self.littoral_v4=None;self.littoral_v4=Some(w);}return Ok(v);}
        if self.littoral_v4.is_some()&&!["new_littoral","new_tide","new_arena","new_chapter","new_salvage","new_campaign","new","load","replay","campaign","campaign_detail","info","arena_catalogue","fuel_preview","campaign_fleet"].contains(&op){return self.littoral_v4.as_mut().unwrap().execute(&r);}
        if op=="new_littoral" {
            let version=r["version"].as_str().ok_or("两栖规则版本无效")?;
            if ![littoral::VERSION,littoral::VERSION_V2,littoral::VERSION_V3].contains(&version){return Err("两栖规则版本无效".into());}
            let seed=world::u(&r,"seed")?;
            let mut config=r.clone();for key in ["op","version","seed"]{config.as_object_mut().ok_or("两栖配置无效")?.remove(key);}
            let config=littoral::decode_config(config,version).map_err(|e|format!("两栖配置无效：{e}"))?;
            let w=littoral::Littoral::new_version(seed,config,version)?;let v=w.view();self.world=None;self.tide=None;self.littoral=Some(w);self.littoral_v4=None;return Ok(v);
        }
        if ["load","replay"].contains(&op)&&[littoral::VERSION,littoral::VERSION_V2,littoral::VERSION_V3].contains(&r["save"]["version"].as_str().unwrap_or("")) {
            littoral::decode_config(r["save"]["config"].clone(),r["save"]["version"].as_str().unwrap()).map_err(|_|"两栖存档格式无效")?;
            let s:littoral::Saved=serde_json::from_value(r["save"].clone()).map_err(|_|"两栖存档格式无效")?;
            let frame=if op=="replay"{r.get("tick").map(littoral::frames).transpose()?}else{None};let w=littoral::Littoral::from_save(s,frame)?;let v=w.view();if op=="load"{self.world=None;self.tide=None;self.littoral=Some(w);self.littoral_v4=None;}return Ok(v);
        }
        if let Some(w)=&mut self.littoral {match op {
            "observe"=>return Ok(w.view()),"save"=>return Ok(json!(w.save())),"report"=>return Ok(json!({"result":w.result,"littoral":w.view()["littoral"]})),
            "presentation"=>return Ok(json!({"version":projectile_presentation::VERSION,"tick":w.tick(),"shots":[]})),
            "step"=>{let n=littoral::frames(&r["seconds"])?;for _ in 0..n{if w.result.is_some(){break;}w.advance();}return Ok(w.view());},
            "littoral_preview"=>return w.preview_littoral(&r),
            "preview_route"=>return Ok(w.preview(&r)),"route"|"speed"|"littoral_deploy"|"littoral_cancel_deploy"|"littoral_ability"|"littoral_order"|"littoral_support"|"littoral_ship_order"|"littoral_extract"|"littoral_abandon"=>return w.command(&r,true),_=>{}
        }}
        if op=="new_tide"{
            let character_id=r["character_id"].as_str().ok_or("请选择活动舰娘")?.to_string();
            let difficulty=match r.get("difficulty"){None=>"normal",Some(v)=>v.as_str().ok_or("活动难度须为字符串")?}.to_string();
            let intel_profile=match r.get("intel_profile"){None=>intel::VERSION,Some(v)=>v.as_str().ok_or("敌情版本须为字符串")?}.to_string();
            let w=match r.get("version") {
                None=>TideMode::V1(tide::Tide::new(world::u(&r,"seed")?,tide::Config{character_id,difficulty,intel_profile})?),
                Some(v) if v==tide::VERSION=>TideMode::V1(tide::Tide::new(world::u(&r,"seed")?,tide::Config{character_id,difficulty,intel_profile})?),
                Some(v) if v==tide_v2::VERSION=>{let roster=match r.get("roster"){None=>vec![],Some(v)=>serde_json::from_value::<Vec<String>>(v.clone()).map_err(|_|"活动后备须为身份字符串列表")?};TideMode::V2(tide_v2::Tide::new(world::u(&r,"seed")?,tide_v2::Config{character_id,roster,difficulty,intel_profile})?)},
                _=>return Err("活动规则版本无效".into()),
            };let view=w.view();self.tide=Some(w);self.world=None;self.littoral=None;self.littoral_v4=None;return Ok(view);
        }
        if ["load","replay"].contains(&op)&&(r["save"]["version"]==tide::VERSION||r["save"]["version"]==tide_v2::VERSION){
            let w=if r["save"]["version"]==tide::VERSION {
                let s:tide::Saved=serde_json::from_value(r["save"].clone()).map_err(|_|"活动存档格式无效")?;let tick=if op=="replay"{r["tick"].as_u64().map(|n|n.min(u32::MAX as u64) as u32)}else{None};TideMode::V1(tide::Tide::from_save(s,tick)?)
            }else{let s:tide_v2::Saved=serde_json::from_value(r["save"].clone()).map_err(|_|"新版活动存档格式无效")?;let frame=if op=="replay"{r.get("tick").map(tide_v2::frames).transpose()?}else{None};TideMode::V2(tide_v2::Tide::from_save(s,frame)?)};
            let view=w.view();if op=="load"{self.tide=Some(w);self.world=None;self.littoral=None;self.littoral_v4=None;}return Ok(view);
        }
        if let Some(w)=&mut self.tide{match op{
            "presentation"=>return Ok(json!({"version":projectile_presentation::VERSION,"tick":w.tick(),"shots":[]})),
            "observe"=>return Ok(w.view()),"save"=>return Ok(w.save()),"report"=>return Ok(json!({"result":w.result(),"tide":w.view()["tide"],"events":w.view()["events"]})),
            "step"=>return w.step(&r["seconds"]),
            "preview_route"=>return Ok(w.preview(&r)),"route"|"speed"|"tide_choose"|"tide_abandon"=>return w.command(&r),_=>{}
        }}
        match op {
            "arena_catalogue" => arena::catalogue(),
            "new_arena" => {
                let start:arena::Start=serde_json::from_value(r.clone()).map_err(|e|format!("竞技编成无效：{e}"))?;
                let w=World::new_arena(start)?;let v=w.observation(0);self.tide=None;self.littoral=None;self.littoral_v4=None;self.world=Some(w);Ok(v)
            }
            "fuel_preview"=>{let start:salvage::Start=serde_json::from_value(r["start"].clone()).map_err(|_|"油料预览编队格式无效")?;crate::fuel::preview(&start)},
            "new_chapter" => {
                let id=r["id"].as_str().ok_or("请选择章节实战")?;
                let seed=world::u(&r,"seed")?;
                let mut start=match r.get("chapter_profile") {
                    None=>salvage_v3::chapter_start(id)?,
                    Some(profile) if profile.as_str()==Some(story_missions::VERSION)=>story_missions::start(id)?,
                    Some(_)=>return Err("剧情关卡规则版本未登记".into()),
                };
                if let Some(profile)=r.get("gameplay_profile") {start.gameplay_profile=profile.as_str().ok_or("冒险规则版本必须是字符串")?.into();}
                if let Some(profile)=r.get("intel_profile"){start.intel_profile=profile.as_str().ok_or("敌情规则须为字符串")?.into();}
                let w=World::new_salvage(seed,start)?;
                let view=w.observation(w.player);self.tide=None;self.littoral=None;self.littoral_v4=None;self.world=Some(w);Ok(view)
            }
            "new_salvage" => {
                let seed = world::u(&r, "seed")?;
                let mut start: salvage::Start = serde_json::from_value(r["start"].clone()).map_err(|e| format!("打捞配置无效：{e}"))?;
                // Only new voyages opt in. Loading an old save passes its absent
                // weather version straight through World::new_salvage unchanged.
                if start.weather.is_none() { start.weather = Some(salvage_weather::VERSION.into()); }
                let w = World::new_salvage(seed, start)?;
                let view = w.observation(w.player);
                self.tide=None;self.littoral=None;self.littoral_v4=None;self.world = Some(w);
                Ok(view)
            }
            "info" => Ok(json!({"version":VERSION,"realtimeVersion":realtime::VERSION,"scenario":SCENARIO,"tickSeconds":1})),
            "campaign" => campaign::catalogue(),
            "campaign_detail" => campaign::detail(
                r["id"].as_str().ok_or("请选择战役关卡")?,
            ),
            "new_campaign" => {
                if r.get("intel_profile").is_some()||r.get("fuel_v1").is_some(){return Err("历史战役不能启用架空敌情或燃油规则".into());}
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
                start.owned_growth=r.get("ownedGrowth").map(|value|serde_json::from_value(value.clone())
                    .map_err(|error|format!("自有舰成长快照无效：{error}"))).transpose()?;
                let w = World::new_campaign(seed, start, profile)?;
                let view = w.observation(w.player);
                self.tide=None;self.littoral=None;self.littoral_v4=None;self.world = Some(w);
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
                // Optional five single-ship identities for a local exercise.
                // Campaigns use `new_campaign`; the challenge ladder and the
                // fixed teaching/prologue/historical variants keep their own
                // printed rosters.
                let ships = match r.get("ships") {
                    None | Some(Value::Null) => None,
                    Some(value) => {
                        let rows = value
                            .as_array()
                            .ok_or("ships 必须是 5 个单舰 identity 的数组")?;
                        Some(
                            rows.iter()
                                .map(|row| {
                                    row.as_str()
                                        .map(str::to_string)
                                        .ok_or_else(|| "ships 只能包含字符串 identity".to_string())
                                })
                                .collect::<E<Vec<_>>>()?,
                        )
                    }
                };
                if let Some(ships) = &ships {
                    if !World::supports_local_fleet(variant) {
                        return Err("该演习使用固定编队，不能替换单舰".into());
                    }
                    if ships.len() != 5 {
                        return Err(format!("单舰编队必须正好 5 艘（收到 {} 艘）", ships.len()));
                    }
                }
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
                    // With a custom fleet, build the untouched five default
                    // slots first; `replace_player_fleet` owns the leader
                    // reorder, so passing `leader_slot` here would apply it
                    // twice.
                    let base_leader_slot = if ships.is_some() { 0 } else { leader_slot };
                    World::new(seed, side, enemy, variant, profile, base_leader_slot)?
                };
                if let Some(ships) = &ships {
                    w.leader_slot = leader_slot;
                    w.replace_player_fleet(ships, leader_slot)?;
                }
                if let Some(opt) = r.get("realtime") {
                    if opt.as_bool().ok_or("实时炮击选项无效")? && !w.realtime() {
                        w.enable_realtime()?;
                    }
                }
                if let Some(profile)=r.get("intel_profile"){w.apply_intel(profile.as_str().ok_or("敌情规则须为字符串")?)?;}
                let v = w.observation(side);
                self.tide=None;self.littoral=None;self.littoral_v4=None;self.world = Some(w);
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
                    self.tide=None;self.littoral=None;self.littoral_v4=None;self.world = Some(w);
                }
                Ok(v)
            }
            _ => {
                let w = self.world.as_mut().ok_or("请先开始演习")?;
                let player = w.player;
                match op {
                    "observe" => Ok(w.observation(player)),
                    "presentation" => Ok(w.projectile_presentation(player)),
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
                    "expedition_land_preview" => w.amphibious_preview(&r),
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
                    "route" | "fire" | "gun_cancel" | "lead" | "detach" | "reform" | "ai" | "radar_set" | "illuminate" | "searchlight" | "smoke" | "speed" | "resume" | "salvage_collect" | "salvage_extract" | "salvage_cancel" | "salvage_drop" | "salvage_abandon" | "cargo_place" | "cargo_drop" | "cargo_sort" | "search_salvage" | "cancel_search" | "expedition_task" | "expedition_interact" | "extraction_autopilot" | "expedition_land_deploy" | "expedition_land_order" | "expedition_land_task" | "expedition_land_recover" | "expedition_land_autopilot" => {
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


