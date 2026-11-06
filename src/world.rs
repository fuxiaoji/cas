use crate::{model::*, movement::fallback_leader, projectile::Shell, radar::{RadarState, RADAR_DRILL, RADAR_VERSION}};
use serde_json::{json, Value};
use std::sync::OnceLock;

pub(crate) fn u(r: &Value, k: &str) -> E<u32> {
    r.get(k)
        .and_then(Value::as_u64)
        .and_then(|n| u32::try_from(n).ok())
        .ok_or_else(|| format!("缺少有效参数：{k}"))
}
static DATA: OnceLock<Result<Data, String>> = OnceLock::new();
pub struct World {
    pub data: &'static Data,
    pub ships: Vec<Ship>,
    pub fleets: Vec<Fleet>,
    pub contacts: [Vec<Contact>; 2],
    pub next_contacts: [u32; 2],
    pub torps: Vec<Torpedo>,
    pub illumination: crate::illumination::Illumination,
    pub shells: Vec<Shell>,
    pub version: &'static str,
    pub event_ids: [u32; 2],
    pub shell_ids: [u32; 2],
    pub torp_ids: [u32; 2],
    pub pending: Vec<Fire>,
    pub events: Vec<Event>,
    pub result: Option<Outcome>,
    pub islands: Vec<Vec<P>>,
    pub tick: u32,
    pub player: usize,
    pub rng: u64,
    pub optics_rng: u64,
    pub(crate) radar: RadarState,
    pub seed: u32,
    pub enemy: String,
    pub variant: String,
    pub profile: String,
    pub leader_slot: usize,
    pub commands: Vec<Entry>,
    pub fired_this_cycle: Vec<u32>,
    pub incoming_this_cycle: Vec<u32>,
    pub gun_streak: Vec<(u32, u32, u32)>,
    pub(crate) surface_phase_dp: Vec<(f64, f64)>,
}
impl World {
    pub fn new(
        seed: u32,
        player: usize,
        enemy: &str,
        variant: &str,
        profile: &str,
        leader_slot: usize,
    ) -> E<Self> {
        if !matches!(variant, "" | "challenge" | "night" | RADAR_DRILL | crate::illumination::TRAINING) {
            return Err("未知演习想定".into());
        }
        Ai::new(profile, "manual").validate()?;
        if leader_slot >= if variant == "challenge" { 3 } else { 5 } {
            return Err("领舰未在当前舰队内".into());
        }
        Ai::new(enemy, "auto").validate()?;
        let data = DATA
            .get_or_init(|| {
                serde_json::from_str(include_str!("../data/stage0.json"))
                    .map_err(|e| format!("无法加载昼战资料：{e}"))
            })
            .as_ref()
            .map_err(Clone::clone)?;
        let mut w = Self {
            data,
            ships: vec![],
            fleets: vec![],
            contacts: [vec![], vec![]],
            next_contacts: [1, 1],
            torps: vec![],
            illumination: Default::default(),
            shells: vec![],
            version: match variant { RADAR_DRILL=>RADAR_VERSION,crate::illumination::TRAINING=>crate::illumination::VERSION,_=>VERSION },
            event_ids: [0, 0],
            shell_ids: [0, 0],
            torp_ids: [0, 0],
            pending: vec![],
            events: vec![],
            result: None,
            islands: vec![],
            tick: 0,
            player,
            rng: (seed as u64) ^ 0xa643de5dbcc8e65f,
            optics_rng: (seed as u64) ^ 0x83f232c98e16baf9,
            radar: RadarState::new(seed),
            seed,
            enemy: enemy.into(),
            variant: variant.into(),
            profile: profile.into(),
            leader_slot,
            commands: vec![],
            fired_this_cycle: vec![],
            incoming_this_cycle: vec![],
            gun_streak: vec![(0, 0, 0); 10],
            surface_phase_dp: vec![(0., 0.); 10],
        };
        for s in 0..2 {
            let (ids, x, y, h, inc, name) = if s == 0 {
                (
                    ["fletcher", "cleveland", "fletcher", "fletcher", "fletcher"],
                    if matches!(variant,"night"|crate::illumination::TRAINING) { 7650. } else { 4200. },
                    6550.,
                    90.,
                    -450.,
                    "第五驱逐编队",
                )
            } else {
                (
                    ["kagero", "sendai", "kagero", "kagero", "kagero"],
                    if matches!(variant,"night"|crate::illumination::TRAINING) { 16_350. } else { 19_800. },
                    7650.,
                    270.,
                    450.,
                    "第八水雷编队",
                )
            };
            let mut members = Vec::new();
            let mut slots: Vec<_> = ids
                .into_iter()
                .enumerate()
                .take(if variant == "challenge" && s == player {
                    3
                } else {
                    5
                })
                .collect();
            if s == player {
                let chosen = slots.remove(leader_slot);
                slots.insert(0, chosen);
            }
            for (pos, (i, id)) in slots.into_iter().enumerate() {
                let def = data
                    .ships
                    .iter()
                    .position(|d| d.id.eq_ignore_ascii_case(id))
                    .ok_or_else(|| format!("缺少已核验舰型 {id}"))?;
                let d = &data.ships[def];
                if ![side_name(s), if s == 0 { "blue" } else { "red" }].contains(&d.side.as_str())
                    || !d.dp.is_finite()
                    || d.dp <= 0.
                    || d.gun.range_yd.len() != 4
                    || d.gun.damage.len() != 4
                    || d.gun.barrels == 0
                    || d.gun.mounts.iter().map(|m| m.barrels).sum::<u32>() != d.gun.barrels
                {
                    return Err(format!("{id} 的阵营、损伤或舰炮字段无效"));
                }
                let ship = (w.ships.len() + 1) as u32;
                members.push(ship);
                w.ships.push(Ship {
                    id: ship,
                    def,
                    side: s,
                    fleet: Some(s as u32 + 1),
                    name: if d.kind.eq_ignore_ascii_case("cl") {
                        d.name.clone()
                    } else {
                        format!("{} {}", d.name, i + 1)
                    },
                    p: P {
                        x: x + inc * pos as f64,
                        y,
                    },
                    h,
                    speed: 0.,
                    hp: d.dp,
                    ammo: d.torpedo.as_ref().map_or(0, |t| t.tubes),
                    gun_cycle: None,
                    illumination_cycle: None,
                    torp_cycle: None,
                    torp_mount_used: vec![
                        false;
                        d.torpedo.as_ref().map_or(0, |t| t.mounts.len().max(1))
                    ],
                    track: None,
                    free_speed: 0.,
                    fires: vec![],
                    flooding: vec![],
                    fire_control_damage: false,
                    gun_mount_destroyed: vec![false; d.gun.mounts.len()],
                    gun_mount_bearings: vec![None; d.gun.mounts.len()],
                    gun_bearing_until: 0,
                    battery: Default::default(),
                    engineering_speed_levels: 0,
                    jammed_until: 0,
                });
                if variant == RADAR_DRILL && id == "fletcher" {
                    // Fictional 1943 trial. Annex A A-17 gives the class fit;
                    // the dated 1943 Form 10s corroborate the fitted set types.
                    w.radar.equip_fletcher_1943(ship)?;
                }
            }
            w.fleets.push(Fleet {
                id: s as u32 + 1,
                side: s,
                name: name.into(),
                leader: members[0],
                members,
                mode: "follow".into(),
                speed: 26.,
                actual: 0.,
                points: vec![],
                ai: if s == player {
                    Ai::new(profile, "manual")
                } else {
                    Ai::new(enemy, "auto")
                },
                notice: None,
                last_ai_route: 0,
                tactic: Tactic::Search,
            });
        }
        w.add(
            3,
            "start",
            match variant {
                "challenge" => "越级挑战 · 3 对 5。击沉两艘敌舰并让至少一艘己舰存活。",
                "night" => "虚构夜间演习 · 能见度 20%，海况 2。双方各 5 艘；45 分钟按击沉数决胜。",
                crate::illumination::TRAINING => "夜战教学 · 先建立接触，再使用照明弹和舰上火力。",
                RADAR_DRILL => "虚构 1943 雷达演习 · 同盟驱逐舰试用 SG／SC-2。发现位置下一探测窗口转发。",
                _ => "虚构演习 · 白昼能见度良好。双方各 5 艘；45 分钟按击沉数决胜。",
            }
            .into(),
            None,
            None,
        );
        w.detect(true);
        w.radar_detect();
        Ok(w)
    }
    pub fn from_save(s: Saved, tick: u32) -> E<Self> {
        let version = match s.version.as_str() {
            VERSION => VERSION,
            LEGACY_VERSION => LEGACY_VERSION,
            RADAR_VERSION => RADAR_VERSION,
            crate::illumination::VERSION => crate::illumination::VERSION,
            crate::realtime::VERSION => crate::realtime::VERSION,
            _ => return Err("此存档使用另一个规则版本".into()),
        };
        if version != crate::realtime::VERSION && (version == RADAR_VERSION) != (s.variant == RADAR_DRILL) {
            return Err("雷达演习与存档规则版本不符".into());
        }
        if version != crate::realtime::VERSION && (version == crate::illumination::VERSION) != (s.variant == crate::illumination::TRAINING) {return Err("存档的照明规则版本与想定不符".into());}
        let last_tick = LIMIT + match version {
            crate::realtime::VERSION => crate::realtime::MAX_FLIGHT,
            LEGACY_VERSION => 0,
            _ => SHELL_FLIGHT,
        };
        if version == LEGACY_VERSION && s.variant == "night" {
            return Err("此版本没有夜间演习".into());
        }
        if s.tick > last_tick || tick > s.tick || s.commands.len() > 10_000 {
            return Err("存档超出演习范围".into());
        }
        if s.commands.iter().any(|v| v.tick > s.tick)
            || s.commands.windows(2).any(|a| a[0].tick > a[1].tick)
        {
            return Err("存档命令时序无效".into());
        }
        let mut w = Self::new(
            s.seed,
            side(&s.side)?,
            &s.enemy,
            &s.variant,
            if s.profile.is_empty() {
                "coord"
            } else {
                &s.profile
            },
            s.leader_slot,
        )?;
        if version == crate::realtime::VERSION {
            w.enable_realtime()?;
        } else {
            w.version = version;
        }
        let mut commands = s.commands.into_iter().peekable();
        loop {
            while commands
                .peek()
                .is_some_and(|e| e.tick == w.tick && e.tick <= tick)
            {
                w.external(commands.next().unwrap().request)
                    .map_err(|e| format!("重演命令失败：{e}"))?;
            }
            if w.tick >= tick {
                break;
            }
            if w.result.is_some() {
                return Err("存档时钟越过战局结束".into());
            }
            w.advance();
        }
        Ok(w)
    }
    pub fn save(&self) -> Saved {
        Saved {
            version: self.version.into(),
            seed: self.seed,
            side: side_name(self.player).into(),
            enemy: self.enemy.clone(),
            variant: self.variant.clone(),
            profile: self.profile.clone(),
            leader_slot: self.leader_slot,
            tick: self.tick,
            commands: self.commands.clone(),
        }
    }
    pub fn ship(&self, id: u32) -> Option<&Ship> {
        self.ships.get(id.checked_sub(1)? as usize)
    }
    pub fn ship_mut(&mut self, id: u32) -> Option<&mut Ship> {
        self.ships.get_mut(id.checked_sub(1)? as usize)
    }
    pub fn fleet(&self, id: u32) -> Option<&Fleet> {
        self.fleets.iter().find(|f| f.id == id)
    }
    pub fn fleet_mut(&mut self, id: u32) -> Option<&mut Fleet> {
        self.fleets.iter_mut().find(|f| f.id == id)
    }
    pub fn fleet_for(&self, owner: usize, id: u32) -> E<&Fleet> {
        self.fleet(id)
            .filter(|f| {
                f.side == owner
                    && f.members
                        .iter()
                        .any(|&s| self.ship(s).is_some_and(Ship::alive))
            })
            .ok_or_else(|| "未找到可操作的己方编队".into())
    }
    pub fn ship_for(&self, owner: usize, id: u32) -> E<&Ship> {
        self.ship(id)
            .filter(|s| s.side == owner && s.alive())
            .ok_or_else(|| "未找到可操作的己方舰艇".into())
    }
    pub fn contact(&self, owner: usize, id: &str) -> E<&Contact> {
        self.contacts[owner]
            .iter()
            .find(|c| c.id == id)
            .ok_or_else(|| "目标接触已丢失".into())
    }
    pub fn knows(&self, owner: usize, id: u32) -> bool {
        self.contacts[owner].iter().any(|c| c.ship == id)
    }
    pub fn d(&mut self, sides: u32) -> u32 {
        roll(&mut self.rng, sides)
    }
    pub fn add(
        &mut self,
        mask: u8,
        kind: &'static str,
        text: String,
        rule: Option<&'static str>,
        p: Option<P>,
    ) {
        let (x, y) = p.map_or((None, None), |p| (Some(p.x), Some(p.y)));
        let view_ids = seat_ids(mask, &mut self.event_ids);
        let cue = match kind {
            "start" => Some("battle_start"),
            "contact" => Some("contact"),
            "torpedo_detected" => Some("torpedo_warning"),
            "hit" => Some("hit"),
            "torpedo_hit" => Some("torpedo_hit"),
            "damage" => Some("damage"),
            _ => None,
        };
        self.events.push(Event {
            view_ids,
            voice_cues: view_ids.map(|id| id.and(cue)),
            tick: self.tick,
            kind,
            text,
            rule,
            x,
            y,
            mask,
        });
    }
    pub(crate) fn last_voice(&mut self, seat: usize, cue: Option<&'static str>) {
        if let Some(event) = self
            .events
            .last_mut()
            .filter(|e| e.view_ids[seat].is_some())
        {
            event.voice_cues[seat] = cue;
        }
    }
    pub(crate) fn visible_events(&self, owner: usize, limit: Option<usize>) -> Vec<Value> {
        let mut picked: Vec<_> = self
            .events
            .iter()
            .rev()
            .filter(|e| e.mask & (1 << owner) != 0)
            .take(limit.unwrap_or(usize::MAX))
            .collect();
        picked.reverse();
        picked
            .into_iter()
            .map(|e| {
                let mut v = json!(e);
                v["id"] = json!(e.view_ids[owner]);
                if let Some(cue) = e.voice_cues[owner] {
                    v["voiceCue"] = json!(cue);
                }
                v
            })
            .collect()
    }
    pub fn observation(&self, owner: usize) -> Value {
        let ships:Vec<_>=self.ships.iter().filter(|s|s.side==owner&&s.alive()).map(|s|{
            let d=&self.data.ships[s.def];
            let guns:Vec<_>=d.gun.mounts.iter().enumerate().map(|(index,m)|{
                let bearing=if self.tick<s.gun_bearing_until && !s.gun_mount_destroyed[index] {s.gun_mount_bearings[index]}else{None};
                let mut view = json!({"index":index,"barrels":m.barrels,"destroyed":s.gun_mount_destroyed[index],"arc":m.arc,"arc2":m.arc2,"bearing":bearing});
                if self.realtime() { self.realtime_mount_view(s,index,&mut view); }
                view
            }).collect();
            let tubes:Vec<_>=d.torpedo.iter().flat_map(|t|t.mounts.iter().enumerate()).map(|(index,m)|json!({"index":index,"tubes":m.tubes,"spent":s.torp_mount_used[index]})).collect();
            let mut data = json!({"gunRange":d.gun.range_yd.last().copied().unwrap_or(0.)*YARD,
                "torpedoRange":d.torpedo.as_ref().map_or(0.,|t|t.range_yd*YARD),
                "systems":{"guns":guns,"tubes":tubes,"directorDamaged":s.fire_control_damage,
                    "engineeringLevels":s.engineering_speed_levels,"fires":s.fires.len(),"floods":s.flooding.len(),"maxSpeed":self.max_speed(s)},
                "id":s.id,"name":s.name,"classId":d.id,"kind":d.kind.to_ascii_lowercase(),"fleet":s.fleet,"x":s.p.x,"y":s.p.y,
                "heading":s.h,"speed":s.speed,"hp":s.hp,"maxHp":d.dp,
                "gun":self.can_gun(s),"torpedo":self.can_torp(s),"ammo":s.ammo});
            if self.radar_enabled() {
                data["systems"]["radars"] = json!(self.radar.own_observation(s.id));
            }
            if self.realtime() {
                if let Some(order) = &s.battery.order {
                    data["gunTarget"] = json!(order.target);
                }
            }
            data
        }).collect();
        let fleets:Vec<_>=self.fleets.iter().filter(|f|f.side==owner).filter_map(|f|{
            let members:Vec<_>=f.members.iter().filter(|id|self.ship(**id).is_some_and(Ship::alive)).collect();
            if members.is_empty(){return None}
            let paths:Vec<_>=members.iter().filter_map(|&&id|self.ship(id).and_then(|s|s.track.as_ref()).filter(|t|!t.done())
                .map(|t|json!({"ship":id,"points":t.remaining()}))).collect();
            Some(json!({"id":f.id,"name":f.name,"leader":f.leader,"members":members,"mode":f.mode,"speed":f.speed,
                "points":if paths.is_empty(){&[][..]}else{&f.points[..]},"paths":paths,"ai":f.ai,"notice":f.notice,"aiState":f.tactic.label()}))
        }).collect();
        let torpedoes: Vec<_> = self
            .torps
            .iter()
            .filter_map(|t| {
                t.view_ids[owner].map(|id| {
                    let own = t.side == owner;
                    let mut v = json!({"id":id,"x":t.p.x,"y":t.p.y,"heading":t.h,"own":own});
                    if own {
                        v["from"] = json!(t.origin);
                        v["count"] = json!(t.count);
                    }
                    if self.realtime() {
                        if let Some(start) = if own { Some(t.origin) } else { t.first_visible } {
                            v["trail"] = json!([start,t.p]);
                        }
                    }
                    v
                })
            })
            .collect();
        let events = self.visible_events(owner, Some(90));
        let shells = self.shell_observation(owner);
        let mut view = json!({"tick":self.tick,"limit":LIMIT,"width":WIDTH,"height":HEIGHT,"side":side_name(owner),
            "scenario":match self.variant.as_str(){"challenge"=>"少舰迎击 · 3 对 5 挑战","night"=>"夜航接敌 · 5 对 5 演习",crate::illumination::TRAINING=>"夜战初阵 · 照明实操",RADAR_DRILL=>"1943 雷达接敌 · 虚构演习",_=>SCENARIO},"variant":self.variant,"ships":ships,"fleets":fleets,"contacts":self.contacts[owner],"torpedoes":torpedoes,
            "events":events,"shells":shells,"version":self.version,"environment":self.environment(),"settling":self.result.is_none() && self.action_closed(),"result":self.result,"islands":self.islands});
        if self.radar_enabled() {
            view["radarContacts"] = json!(self.radar.observation(owner, &self.ships));
        }
        if self.has_starshells() { view["illuminations"]=json!(self.visible_illumination(owner)); }
        if self.realtime() { view["realtimeGunnery"] = json!(true); }
        view
    }
    pub fn external(&mut self, r: Value) -> E<()> {
        if self.result.is_some() || (self.version != LEGACY_VERSION && self.action_closed()) {
            return Err("演习已结束或正在等待末轮弹着".into());
        }
        let s = self.player;
        match r.get("op").and_then(Value::as_str) {
            Some("route") => self.route(s, &r, true)?,
            Some("lead") => self.lead(s, &r)?,
            Some("detach") => self.detach(s, &r)?,
            Some("reform") => self.reform(s, &r)?,
            Some("fire") => self.queue_fire(s, &r, true)?,
            Some("gun_cancel") => self.cancel_realtime_gun(s, &r)?,
            Some("illuminate") => self.queue_illumination(s,&r)?,
            Some("radar_set") => self.radar_power(s, &r)?,
            Some("ai") => {
                let id = u(&r, "fleet")?;
                self.fleet_for(s, id)?;
                let ai: Ai = serde_json::from_value(r.clone()).map_err(|_| "AI 配置不完整")?;
                ai.validate()?;
                self.fleet_mut(id).unwrap().ai = ai;
                self.add(
                    1 << s,
                    "ai",
                    "已更新编队指挥权限".into(),
                    Some("RTS-AI-01"),
                    None,
                );
            }
            _ => return Err("存档包含无效命令".into()),
        }
        self.commands.push(Entry {
            tick: self.tick,
            request: r,
        });
        Ok(())
    }
    fn action_closed(&self) -> bool {
        self.tick >= LIMIT || (0..2).any(|s| !self.ships.iter().any(|i| i.side == s && i.alive()))
    }
    pub fn advance(&mut self) {
        let settle_only = self.version != LEGACY_VERSION && self.action_closed();
        self.tick += 1;
        if settle_only {
            self.advance_shells();
            if self.realtime() && self.shells.is_empty() { self.flush_realtime_surface_damage(); }
            self.check_outcome();
            return;
        }
        let before: Vec<_> = self.ships.iter().map(|s| s.p).collect();
        self.move_ships();
        self.move_torpedoes(&before);
        self.update_tracks();
        self.radar_prune();
        if self.realtime() { self.prepare_illumination_mounts(); }
        if self.tick % CYCLE == 0 {
            self.resolve_fire(true);
            self.fired_this_cycle.clear();
            self.incoming_this_cycle.clear();
            self.detect(false);
            self.radar_detect();
        }
        self.resolve_fire(false);
        if self.realtime() { self.resolve_realtime_guns(); }
        self.resolve_damage_control();
        self.advance_shells();
        if self.realtime() && (self.tick % CYCLE == 0 || self.action_closed() && self.shells.is_empty()) {
            self.flush_realtime_surface_damage();
        }
        self.radar_prune();
        self.check_outcome();
        if self.result.is_none()
            && (self.version == LEGACY_VERSION || !self.action_closed())
            && (self.tick == 1 || self.tick % 20 == 0 || self.realtime() && self.tick % 4 == 0)
        {
            self.drive_ai();
        }
    }
    pub fn sank(&mut self, id: u32) {
        let Some(s) = self.ship(id) else { return };
        let (owner, fl, p, name) = (s.side, s.fleet, s.p, s.name.clone());
        self.add(
            1 << owner,
            "sunk",
            format!("{name} 沉没"),
            Some("CAS-8.1"),
            Some(p),
        );
        self.last_voice(owner, Some("own_sunk"));
        if self.knows(1 - owner, id) {
            self.add(
                1 << (1 - owner),
                "sunk",
                "已观测到敌舰沉没".into(),
                Some("CAS-8.1"),
                Some(p),
            );
            self.last_voice(1 - owner, Some("enemy_sunk"));
        }
        for v in &mut self.contacts {
            v.retain(|c| c.ship != id);
        }
        if let Some(f) = fl {
            if self.fleet(f).is_some_and(|f| f.leader == id) {
                if let Some(replacement) = fallback_leader(self, f, id) {
                    let ids = self.fleet(f).unwrap().members.clone();
                    for i in ids {
                        let s = self.ship_mut(i).unwrap();
                        s.track = None;
                        s.speed = 0.;
                    }
                    let fleet = self.fleet_mut(f).unwrap();
                    fleet.leader = replacement;
                    fleet.points.clear();
                    fleet.actual = 0.;
                    fleet.notice =
                        Some("领舰失能，已由下一艘可用舰接替。请为余队重下航路。".into());
                    self.add(
                        1 << owner,
                        "leader",
                        "领舰失能，已交接；编队等待重新下令。".into(),
                        Some("RTS-NAV-02"),
                        None,
                    );
                }
            }
        }
    }
    fn check_outcome(&mut self) {
        let lost: Vec<u32> = (0..2)
            .map(|side| {
                self.ships
                    .iter()
                    .filter(|s| s.side == side && !s.alive())
                    .count() as u32
            })
            .collect();
        let wiped = |side: usize| !self.ships.iter().any(|s| s.side == side && s.alive());
        if self.action_closed() && self.shells.is_empty() {
            let (a, b) = (lost[1], lost[0]);
            let winner = if a > b {
                "allies"
            } else if b > a {
                "axis"
            } else {
                "draw"
            };
            let primary = (self.variant == "challenge")
                .then(|| lost[1 - self.player] >= 2 && !wiped(self.player));
            self.result = Some(Outcome {
                winner: winner.into(),
                allies: a,
                axis: b,
                primary,
            });
            self.add(
                3,
                "end",
                format!(
                    "演习结束：同盟 {a} · 轴心 {b}。{}",
                    if winner == "draw" {
                        "平局"
                    } else if winner == "allies" {
                        "同盟胜出"
                    } else {
                        "轴心胜出"
                    }
                ),
                Some("RTS-EXERCISE-01"),
                None,
            );
            for seat in 0..2 {
                self.last_voice(
                    seat,
                    if winner == "draw" {
                        None
                    } else if winner == side_name(seat) {
                        Some("victory")
                    } else {
                        Some("defeat")
                    },
                );
            }
        }
    }
}

pub(crate) fn seat_ids(mask: u8, seq: &mut [u32; 2]) -> [Option<u32>; 2] {
    std::array::from_fn(|side| {
        (mask & (1 << side) != 0).then(|| {
            seq[side] += 1;
            seq[side]
        })
    })
}

pub(crate) fn roll(state: &mut u64, sides: u32) -> u32 {
    let mut r = *state;
    r ^= r << 13;
    r ^= r >> 7;
    r ^= r << 17;
    *state = r;
    (r % sides as u64) as u32 + 1
}
