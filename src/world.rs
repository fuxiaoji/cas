use crate::{model::*, movement::fallback_leader, projectile::Shell, radar::{RadarState, RADAR_DRILL, RADAR_VERSION}};
use serde_json::{json, Value};
use std::sync::OnceLock;
use crate::campaign::{kula, live};

pub(crate) fn u(r: &Value, k: &str) -> E<u32> {
    r.get(k)
        .and_then(Value::as_u64)
        .and_then(|n| u32::try_from(n).ok())
        .ok_or_else(|| format!("缺少有效参数：{k}"))
}
static DATA: OnceLock<Result<Data, String>> = OnceLock::new();
pub struct World {
    pub(crate) field: Field,
    pub(crate) campaign: Option<live::Start>,
    pub(crate) campaign_result: Option<crate::campaign::Outcome>,
    pub(crate) host_duel: bool,
    pub(crate) ranked_duel: Option<RankedFleetMatch>,
    pub(crate) kula: Option<kula::Battle>,
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
    pub(crate) surface_damage: Vec<crate::damage::SurfacePhase>,
    pub(crate) surface_critical_rng: u64,
    /// cas-realtime-v10: smoke-screen puffs (5.4.5). Rebuilt deterministically
    /// from the command log, so saves need no extra fields.
    pub smoke: Vec<crate::model::SmokeCloud>,
}
impl World {
    pub(crate) fn exercise_data() -> E<&'static Data> {
        DATA
            .get_or_init(|| {
                serde_json::from_str(include_str!("../data/stage0.json"))
                    .map_err(|e| format!("无法加载昼战资料：{e}"))
            })
            .as_ref()
            .map_err(Clone::clone)
    }

    pub(crate) fn blank(data: &'static Data, seed: u32, player: usize, enemy: &str, variant: &str, profile: &str, leader_slot: usize) -> Self {
        Self {
            field: Field::EXERCISE,
            campaign: None,
            campaign_result: None,
            host_duel: false,
            ranked_duel: None,
            kula: None,
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
            surface_damage: vec![Default::default(); 10],
            surface_critical_rng: (seed as u64) ^ 0x6271_09f5_29a3_084d,
            smoke: vec![],
        }
    }

    pub fn new(seed: u32, player: usize, enemy: &str, variant: &str, profile: &str, leader_slot: usize) -> E<Self> {
        if !matches!(variant, "" | "challenge" | "night" | RADAR_DRILL | crate::illumination::TRAINING | crate::illumination::RADAR_TRAINING | crate::prologue::VARIANT | crate::empress::VARIANT) {
            return Err("未知演习想定".into());
        }
        Ai::new(profile, "manual").validate()?;
        if leader_slot >= if variant == "challenge" { 3 } else { 5 } {
            return Err("领舰未在当前舰队内".into());
        }
        Ai::new(enemy, "auto").validate()?;
        if variant == crate::prologue::VARIANT {
            return crate::prologue::open(seed, player, enemy, profile, leader_slot);
        }
        let data = Self::exercise_data()?;
        let mut w = Self::blank(data, seed, player, enemy, variant, profile, leader_slot);
        if variant == crate::empress::VARIANT {
            crate::empress::fill(&mut w)?;
            return Ok(w);
        }
        for s in 0..2 {
            let (ids, x, y, h, inc, name) = if s == 0 {
                (
                    ["fletcher", "cleveland", "fletcher", "fletcher", "fletcher"],
                    if matches!(variant,"night"|crate::illumination::TRAINING|crate::illumination::RADAR_TRAINING) { 7650. } else { 4200. },
                    6550.,
                    90.,
                    -450.,
                    "第五驱逐编队",
                )
            } else {
                (
                    ["kagero", "sendai", "kagero", "kagero", "kagero"],
                    if matches!(variant,"night"|crate::illumination::TRAINING|crate::illumination::RADAR_TRAINING) { 16_350. } else { 19_800. },
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
                let name = if d.kind.eq_ignore_ascii_case("cl") {
                        d.name.clone()
                    } else {
                        format!("{} {}", d.name, i + 1)
                    };
                let ship = w.spawn(def, s, s as u32 + 1, name, P {x: x + inc * pos as f64, y}, h)?;
                members.push(ship);
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
                turn_degrees: 0.,
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
        if variant == crate::illumination::RADAR_TRAINING {
            if player != 0 || leader_slot != 0 {
                return Err("雷达夜战教学使用同盟弗莱彻领舰".into());
            }
            w.enable_realtime()?;
            w.radar.equip_fletcher_1943(1)?;
            for radar in ["us_sg", "us_sc2"] {
                w.radar_power(0, &json!({"ship":1,"radar":radar,"powered":false}))?;
            }
            for (seat, fleet, x, y) in [(0, 1, 12_400, 6550), (1, 2, 13_450, 7650)] {
                w.fleet_mut(fleet).unwrap().ai = Ai::new("coord", "manual");
                w.route(seat, &json!({"fleet":fleet,"mode":"follow","speed":15,"points":[{"x":x,"y":y}]}), true)?;
            }
        }
        w.add(
            3,
            "start",
            match variant {
                "challenge" => "越级挑战 · 3 对 5。击沉两艘敌舰并让至少一艘己舰存活。",
                "night" => "虚构夜间演习 · 能见度 20%，海况 2。双方各 5 艘；45 分钟按击沉数决胜。",
                crate::illumination::TRAINING => "夜战教学 · 先建立接触，再使用照明弹和舰上火力。",
                crate::illumination::RADAR_TRAINING => "固定教演 · 舰上雷达关闭。编队已按预定航线接近目标。",
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

    pub(crate) fn spawn(&mut self, def: usize, side: usize, fleet: u32, name: String, p: P, h: f64) -> E<u32> {
        let d = &self.data.ships[def];
        if (!self.host_duel || self.ranked_duel.is_none())
            && ![side_name(side), if side == 0 { "blue" } else { "red" }].contains(&d.side.as_str())
        {
            return Err(format!("{} 的阵营与开局席位不符", d.id));
        }
        if !d.dp.is_finite() || d.dp <= 0.
            || d.gun.range_yd.len() != 4 || d.gun.damage.len() != 4
            || d.gun.barrels == 0 || d.gun.mounts.iter().map(|m| m.barrels).sum::<u32>() != d.gun.barrels
            || !self.field.contains(p)
        {
            return Err(format!("{} 的阵营、舰卡或出生点无效", d.id));
        }
        let id = (self.ships.len() + 1) as u32;
        self.ships.push(Ship {
            id, def, side, fleet: Some(fleet), name, p, h, speed: 0., escaped: false,
            hp: d.dp, ammo: d.torpedo.as_ref().map_or(0, |t| t.tubes),
            gun_cycle: None, illumination_cycle: None, torp_cycle: None,
            torp_mount_remaining: d.torpedo.iter().flat_map(|t| t.mounts.iter().map(|m| m.tubes)).collect(),
            torpedo_protection: [d.torpedo_protection_dp; 2],
            track: None, free_speed: 0., fires: vec![], flooding: vec![], fire_control_damage: false,
            gun_mount_destroyed: vec![false; d.gun.mounts.len()],
            gun_mount_bearings: vec![None; d.gun.mounts.len()], gun_bearing_until: 0,
            battery: Default::default(), engineering_speed_levels: 0, jammed_until: 0,
            searchlight: None, searchlight_die: 0, searchlight_since: 0, smoking: false,
            rudder_jam: None, bridge_circle: None,
            torp_mount_destroyed: vec![false; d.torpedo.iter().map(|t| t.mounts.len()).sum()],
            torp_reserve: d.torpedo.iter().flat_map(|t| t.mounts.iter().map(|m| m.reserve)).collect(),
            torp_reload_at: vec![0; d.torpedo.iter().flat_map(|t| t.mounts.iter()).count()],
            secondary_ready: 0, speed_cap: None,
        });
        // Per-ship arrays are indexed by hull id; campaigns can field more
        // than the ten exercise hulls.
        let hulls = self.ships.len();
        if self.gun_streak.len() < hulls {
            self.gun_streak.resize(hulls, (0, 0, 0));
            self.surface_damage.resize(hulls, Default::default());
        }
        Ok(id)
    }
    pub fn from_save(s: Saved, tick: u32) -> E<Self> {
        let version = match s.version.as_str() {
            VERSION => VERSION,
            LEGACY_VERSION => LEGACY_VERSION,
            RADAR_VERSION => RADAR_VERSION,
            crate::illumination::VERSION => crate::illumination::VERSION,
            crate::realtime::VERSION => crate::realtime::VERSION,
            crate::realtime::WINDOW_TORPEDO_VERSION => crate::realtime::WINDOW_TORPEDO_VERSION,
            crate::realtime::CURVE_VERSION => crate::realtime::CURVE_VERSION,
            crate::realtime::IMPACT_VERSION => crate::realtime::IMPACT_VERSION,
            crate::realtime::CADENCE_VERSION => crate::realtime::CADENCE_VERSION,
            crate::realtime::LEGACY_VERSION => crate::realtime::LEGACY_VERSION,
            live::VERSION => live::VERSION,
            live::WINDOW_TORPEDO_VERSION => live::WINDOW_TORPEDO_VERSION,
            live::CURVE_VERSION => live::CURVE_VERSION,
            live::IMPACT_VERSION => live::IMPACT_VERSION,
            live::CADENCE_VERSION => live::CADENCE_VERSION,
            live::LEGACY_VERSION => live::LEGACY_VERSION,
            _ => return Err("此存档使用另一个规则版本".into()),
        };
        let realtime = crate::realtime::is_realtime_version(version);
        let ranked = s.ranked.is_some();
        if (ranked && !s.duel) || (s.duel
            && (cfg!(target_arch = "wasm32")
                || if ranked {
                    !matches!(version, crate::realtime::VERSION | crate::realtime::WINDOW_TORPEDO_VERSION) || s.variant != "personal-duel"
                }
                    else { version != crate::realtime::CURVE_VERSION || !s.variant.is_empty() }
                || s.side != "allies"
                || s.enemy != "coord"
                || s.profile != "coord"
                || s.leader_slot != 0
                || s.campaign.is_some()))
        {
            return Err("双席对局存档与权威想定不符".into());
        }
        if s.commands.iter().any(|entry| match &entry.seat {
            Some(seat) => !s.duel || side(seat).is_err(),
            None => s.duel,
        }) {
            return Err("存档命令的席位无效".into());
        }
        if matches!(s.variant.as_str(), crate::prologue::VARIANT | crate::illumination::RADAR_TRAINING)
            && !matches!(version, crate::realtime::VERSION | crate::realtime::WINDOW_TORPEDO_VERSION | crate::realtime::CURVE_VERSION)
        {
            return Err("该教学存档的规则版本不符".into());
        }
        if s.variant == kula::VARIANT && version != kula::VERSION {
            return Err("库拉湾存档的规则版本不符".into());
        }
        if live::is_campaign_version(version) != s.campaign.is_some()
            || s.campaign.as_ref().is_some_and(|start| s.variant != start.variant()) {
            return Err("战役存档的规则或内容版本不符".into());
        }
        if !realtime && (version == RADAR_VERSION) != (s.variant == RADAR_DRILL) {
            return Err("雷达演习与存档规则版本不符".into());
        }
        if !realtime && (version == crate::illumination::VERSION) != (s.variant == crate::illumination::TRAINING) {return Err("存档的照明规则版本与想定不符".into());}
        let limit = s.campaign.as_ref().map_or(
            if s.variant == crate::empress::VARIANT { crate::empress::LIMIT } else { LIMIT },
            live::Start::limit,
        );
        let last_tick = limit + if realtime {
            crate::realtime::MAX_FLIGHT
        } else if version == LEGACY_VERSION {
            0
        } else {
            SHELL_FLIGHT
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
        let profile = if s.profile.is_empty() { "coord" } else { &s.profile };
        let mut w = if let Some(ranked) = s.ranked {
            #[cfg(not(target_arch = "wasm32"))]
            { Self::new_ranked_duel(s.seed, ranked)? }
            #[cfg(target_arch = "wasm32")]
            { let _ = ranked; return Err("双席对局由权威主机恢复".into()); }
        } else if let Some(start) = s.campaign {
            if start.seat()? != side(&s.side)? || start.enemy()? != s.enemy || s.leader_slot != 0 {
                return Err("战役存档阵营或编制不符".into());
            }
            Self::new_campaign(s.seed, start, profile)?
        } else { Self::new(
            s.seed,
            side(&s.side)?,
            &s.enemy,
            &s.variant,
            profile,
            s.leader_slot,
        )? };
        if !ranked && realtime && w.campaign.is_none() {
            w.init_realtime(version)?;
        } else {
            w.version = version;
        }
        if s.duel && !ranked {
            w.set_duel_seats();
        }
        let mut commands = s.commands.into_iter().peekable();
        loop {
            while commands
                .peek()
                .is_some_and(|e| e.tick == w.tick && e.tick <= tick)
            {
                let entry = commands.next().unwrap();
                let owner = entry.seat.as_deref().map(side).transpose()?.unwrap_or(w.player);
                w.external_for(owner, entry.request)
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
            campaign: self.campaign.clone(),
            tick: self.tick,
            commands: self.commands.clone(),
            duel: self.host_duel,
            ranked: self.ranked_duel.clone(),
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
            own_ship: None,
            rule,
            x,
            y,
            mask,
        });
    }
    pub(crate) fn last_event_ship(&mut self, ship: &Ship) {
        if self.curved_movement() {
            if let Some(event) = self.events.last_mut().filter(|e| e.mask == 1 << ship.side) {
                event.own_ship = Some(ship.id);
            }
        }
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
            let tubes:Vec<_>=d.torpedo.iter().flat_map(|t|t.mounts.iter().enumerate()).map(|(index,m)|{
                let remaining = s.torp_mount_remaining[index];
                let mut view = json!({"index":index,"tubes":m.tubes,"spent":remaining == 0});
                if self.torpedo_depths() {
                    view["remaining"] = json!(remaining);
                    view["reserve"] = json!(s.torp_reserve[index]);
                    if s.torp_reload_at[index] > self.tick {
                        view["reloadingUntil"] = json!(s.torp_reload_at[index]);
                    }
                }
                view
            }).collect();
            let mut data = json!({"gunRange":d.gun.range_yd.last().copied().unwrap_or(0.)*YARD,
                "torpedoRange":d.torpedo.as_ref().map_or(0.,|t|t.range_yd*YARD),
                "systems":{"guns":guns,"tubes":tubes,"directorDamaged":s.fire_control_damage,
                    "engineeringLevels":s.engineering_speed_levels,"fires":s.fires.len(),"floods":s.flooding.len(),"maxSpeed":self.max_speed(s)},
                "id":s.id,"name":s.name,"classId":d.id,"kind":d.kind.to_ascii_lowercase(),"fleet":s.fleet,"x":s.p.x,"y":s.p.y,
                "heading":s.h,"speed":s.speed,"hp":s.hp,"maxHp":d.dp,
                "gun":self.can_gun(s),"torpedo":self.can_torp(s),"ammo":s.ammo});
            if (self.variant == crate::prologue::VARIANT || self.ranked_duel.is_some()) && d.id.starts_with("IBS-U-") {
                data["characterId"] = json!(d.id);
            } else if let Some(character) = self.campaign.as_ref().and_then(|_| live::character_id(&d.id)) {
                data["characterId"] = json!(character);
            }
            if s.searchlight.is_some() {
                if let Some(target) = self.ship(s.searchlight.unwrap()).filter(|t| t.alive()) {
                    let bearing = (target.p - s.p).heading();
                    data["searchlight"] = json!({"target": s.searchlight.unwrap(), "bearing": bearing});
                } else {
                    data["searchlight"] = json!({"target": null});
                }
            }
            if s.smoking {
                data["smoking"] = json!(true);
            }
            if let Some(direction) = s.rudder_jam {
                data["rudderJam"] = json!(if direction < 0. { "port" } else { "starboard" });
            }
            if let Some(direction) = s.bridge_circle {
                if direction != 0. {
                    data["bridgeCircle"] = json!(if direction < 0. { "port" } else { "starboard" });
                }
            }
            if self.radar_enabled() {
                data["systems"]["radars"] = json!(self.radar.own_observation(s.id));
                // Own-seat only: the nominal surface-search reach of whatever is
                // powered, and the visual base range against a same-size hull
                // in the current environment. Detection beyond the visual base
                // stays probabilistic per CAS §5.
                if let Some(range) = self.radar.nominal_surface_range_m(s.id, &d.size) {
                    data["radarRange"] = json!(range);
                }
            }
            data["sightRange"] = json!(crate::night::surface_base_range_yd(
                self.environment(), &d.size, &d.size, 0., false, false,
            ) as f64 * YARD);
            if self.realtime() {
                if let Some(order) = &s.battery.order {
                    data["gunTarget"] = json!(order.target);
                }
            }
            if self.torpedo_depths() && d.torpedo_protection_dp > 0. {
                data["systems"]["torpedoProtection"] = json!({"port":s.torpedo_protection[0],"starboard":s.torpedo_protection[1],"capacity":d.torpedo_protection_dp});
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
                        if self.torpedo_depths() { v["depth"] = json!(if t.deep { "deep" } else { "shallow" }); }
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
        let smoke_view: Vec<_> = self.smoke.iter().filter(|cloud| cloud.expires > self.tick)
            .filter(|cloud| self.ships.iter().any(|s| s.side == owner && s.alive() && s.p.dist(cloud.p) <= 40_000.))
            .map(|cloud| json!({"x": cloud.p.x, "y": cloud.p.y, "expires": cloud.expires})).collect();
        let mut view = json!({"tick":self.tick,"limit":self.field.limit,"width":self.field.width,"height":self.field.height,"side":side_name(owner),
            "scenario":match self.variant.as_str(){"challenge"=>"少舰迎击 · 3 对 5 挑战","night"=>"夜航接敌 · 5 对 5 演习",crate::empress::VARIANT=>crate::empress::LABEL,crate::illumination::TRAINING=>"夜战初阵 · 照明实操",crate::illumination::RADAR_TRAINING=>"夜海初航 · 雷达与照明",RADAR_DRILL=>"1943 雷达接敌 · 虚构演习",live::VARIANT=>live::LABEL,crate::campaign::channel::VARIANT=>crate::campaign::channel::LABEL,kula::VARIANT=>kula::LABEL,crate::prologue::VARIANT=>crate::prologue::TITLE,_=>SCENARIO},"variant":self.variant,"ships":ships,"fleets":fleets,"contacts":self.contacts[owner],"torpedoes":torpedoes,"smoke":smoke_view,
            "events":events,"shells":shells,"version":self.version,"environment":self.environment(),"settling":self.result.is_none() && self.action_closed(),"result":self.result_for(owner),"islands":self.islands});
        if let Some(campaign) = self.campaign_view(owner) { view["campaign"] = campaign; }
        if self.radar_enabled() {
            let mut reports = self.radar.observation(owner, &self.ships);
            if matches!(self.variant.as_str(), live::VARIANT | kula::VARIANT) {
                for report in &mut reports {
                    let target = report["id"].as_str().expect("seat radar contact id");
                    let ships: Vec<_> = self.ships.iter().filter(|s| s.side == owner && s.alive())
                        .filter(|s| self.radar_torp_contact(s, target).is_some())
                        .map(|s| s.id).collect();
                    report["torpedoForShipIds"] = json!(ships);
                }
            }
            view["radarContacts"] = json!(reports);
        }
        if self.has_starshells() { view["illuminations"]=json!(self.visible_illumination(owner)); }
        if self.realtime() { view["realtimeGunnery"] = json!(true); }
        if self.torpedo_depths() { view["torpedoDepths"] = json!(true); }
        if let Some(ranked) = &self.ranked_duel {
            view["scenario"] = json!(if ranked.budget == 3000 { "三千分护航战" } else { "万分战列舰战" });
        }
        view
    }
    pub fn external(&mut self, r: Value) -> E<()> {
        self.external_for(self.player, r)
    }
    pub(crate) fn set_duel_seats(&mut self) {
        self.host_duel = true;
        for fleet in &mut self.fleets {
            fleet.ai = Ai::new("coord", "manual");
        }
    }
    pub(crate) fn external_for(&mut self, s: usize, r: Value) -> E<()> {
        if s > 1 || (!self.host_duel && s != self.player) {
            return Err("当前席位不可下令".into());
        }
        if self.host_duel && self.commands.len() >= 10_000 {
            return Err("双席对局已达到命令记录上限".into());
        }
        if self.result.is_some() || (self.version != LEGACY_VERSION && self.action_closed()) {
            return Err("演习已结束或正在等待末轮弹着".into());
        }
        if self.variant == crate::prologue::VARIANT {
            let commanded_fleet = r.get("fleet").and_then(Value::as_u64);
            let commanded_ship = r.get("ship").and_then(Value::as_u64);
            if commanded_fleet.is_some_and(|fleet| fleet != 1)
                || commanded_ship.is_some_and(|id| self.ship(id as u32).and_then(|ship| ship.fleet) != Some(1))
            {
                return Err("序章由你指挥第五驱逐小队，其他编队按总指挥的命令行动".into());
            }
        }
        match r.get("op").and_then(Value::as_str) {
            Some("route") => self.route(s, &r, true)?,
            Some("lead") => self.lead(s, &r)?,
            Some("detach") => self.detach(s, &r)?,
            Some("reform") => self.reform(s, &r)?,
            Some("fire") => self.queue_fire(s, &r, true)?,
            Some("gun_cancel") => self.cancel_realtime_gun(s, &r)?,
            Some("illuminate") => self.queue_illumination(s,&r)?,
            Some("radar_set") => self.radar_power(s, &r)?,
            Some("searchlight") => self.searchlight_cmd(s, &r)?,
            Some("smoke") => self.smoke_cmd(s, &r)?,
            Some("ai") => {
                let id = u(&r, "fleet")?;
                self.fleet_for(s, id)?;
                let ai: Ai = serde_json::from_value(r.clone()).map_err(|_| "AI 配置不完整")?;
                ai.validate()?;
                if self.host_duel && ai.mode == "auto" {
                    return Err("线上约战的 AI 只提供建议".into());
                }
                if self.ranked_duel.is_some() && self.fleet(id).is_some_and(|fleet| fleet.ai.profile != ai.profile) {
                    return Err("本局的 AI 风格已随舰队预设冻结".into());
                }
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
            seat: self.host_duel.then(|| side_name(s).into()),
        });
        Ok(())
    }
    fn action_closed(&self) -> bool {
        self.tick >= self.field.limit || if self.variant == live::VARIANT {
            !self.ships.iter().any(|s| s.side == 1 && s.alive())
        } else if matches!(self.variant.as_str(), crate::campaign::channel::VARIANT | kula::VARIANT) {
            // The inherited scenario scores at the end of turn four, including ongoing damage.
            false
        } else {
            (0..2).any(|s| !self.ships.iter().any(|i| i.side == s && i.alive()))
        }
    }
    pub fn advance(&mut self) {
        if std::env::var("CAS_RNG_PROBE").is_ok() && self.tick % 60 == 0 {
            eprintln!("RNGPROBE tick={} rng={:016x} optics={:016x} crit={:016x}",
                self.tick, self.rng, self.optics_rng, self.surface_critical_rng);
        }
        let settle_only = self.version != LEGACY_VERSION && self.action_closed();
        self.tick += 1;
        if settle_only {
            self.advance_shells();
            if self.realtime()
                && (self.shells.is_empty() || self.progressive_criticals() && self.tick % CYCLE == 0)
            {
                self.flush_realtime_surface_damage();
            }
            self.check_outcome();
            return;
        }
        let before: Vec<_> = self.ships.iter().map(|s| s.p).collect();
        self.move_ships();
        self.move_torpedoes(&before);
        self.reload_torpedoes();
        self.update_tracks();
        // cas-realtime-v10 (5.4.5): a smoking destroyer drops one puff per
        // minute of trailing; puffs burn for four calm-weather windows.
        self.smoke.retain(|cloud| cloud.expires > self.tick);
        if self.v10_family() && self.tick % 60 == 0 {
            for s in self.ships.iter().filter(|s| s.smoking && s.alive()) {
                self.smoke.push(crate::model::SmokeCloud { p: s.p, born: self.tick, expires: self.tick + 4 * CYCLE });
            }
        }
        self.radar_prune();
        if self.realtime() { self.prepare_illumination_mounts(); }
        if self.tick % CYCLE == 0 {
            self.resolve_fire(true);
            self.fired_this_cycle.clear();
            self.incoming_this_cycle.clear();
            if !self.v10_family() {
                self.detect(false);
                self.radar_detect();
            }
        }
        // cas-realtime-v10: acquisition runs every second; the printed per-phase
        // chance is integrated into a per-second hazard rate so the window-end
        // detection distribution still matches CAS §5.4.
        if self.v10_family() {
            self.detect(false);
            self.radar_detect();
        }
        self.resolve_fire(false);
        if self.realtime() { self.resolve_realtime_guns(); }
        if self.v10_family() { self.resolve_secondaries(); }
        self.resolve_damage_control();
        self.advance_shells();
        if self.variant == live::VARIANT {
            self.campaign_departures();
        } else if self.variant == kula::VARIANT {
            kula::tick(self);
        }
        if self.realtime() && (self.tick % CYCLE == 0 || self.action_closed() && self.shells.is_empty()) {
            self.flush_realtime_surface_damage();
        }
        self.radar_prune();
        self.check_outcome();
        if self.variant == crate::prologue::VARIANT && self.result.is_none() && !self.action_closed() {
            self.prologue_fire();
        } else if self.result.is_none()
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
                    .filter(|s| s.side == side && s.hp <= 0.)
                    .count() as u32
            })
            .collect();
        let wiped = |side: usize| !self.ships.iter().any(|s| s.side == side && s.alive());
        if self.action_closed() && self.shells.is_empty() {
            if self.campaign.is_some() {
                self.close_campaign(lost[0], lost[1]);
                return;
            }
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

impl World {
    /// cas-realtime-v10: searchlight order (5.4.4.1). Night only; the light
    /// tracks one known contact. Turning it on rolls the illumination die.
    pub(crate) fn searchlight_cmd(&mut self, owner: usize, r: &Value) -> E<()> {
        if !self.v10_family() {
            return Err("本局规则版本未开放探照灯".into());
        }
        if self.environment().light != crate::night::Light::Night {
            return Err("探照灯只在夜战可用".into());
        }
        let id = u(r, "ship")?;
        let s = self.ship_for(owner, id)?;
        let on = r.get("on").and_then(Value::as_bool).ok_or("缺少探照灯开关")?;
        let die_roll = self.d(100);
        let now = self.tick;
        if !on {
            let (name, p) = {
                let ship = self.ship_for(owner, id)?;
                (ship.name.clone(), ship.p)
            };
            self.ship_mut(id).unwrap().searchlight = None;
            self.add(1 << owner, "searchlight", format!("{name} · 关闭探照灯"), Some("RTS-LIGHT-02"), Some(p));
            return Ok(());
        }
        let target = r.get("target").and_then(Value::as_str).ok_or("请选择要照亮的接触")?;
        let (name, side, contact, p) = {
            let ship = self.ship_for(owner, id)?;
            let contact = self.contacts[owner].iter().find(|c| c.id == target)
                .ok_or("请选择已发现的水面接触")?.ship;
            (ship.name.clone(), ship.side, contact, ship.p)
        };
        let fixture: u32 = if side == 0 { 8000 } else { 7000 };
        let ship = self.ship_mut(id).unwrap();
        ship.searchlight = Some(contact);
        ship.searchlight_die = die_roll;
        ship.searchlight_since = now;
        let _ = name;
        self.add(1 << owner, "searchlight", format!("探照灯已开启（照距上限 {fixture} 码）"),
            Some("RTS-LIGHT-02"), Some(p));
        let mask = 1 << owner;
        if self.curved_movement() {
            if let Some(event) = self.events.last_mut().filter(|e| e.mask == mask) {
                event.own_ship = Some(id);
            }
        }
        Ok(())
    }

    /// cas-realtime-v10: smoke order (5.4.5). Destroyer generators only; the
    /// screen burns for four calm-weather windows, one puff per minute of
    /// trailing. Wind drift is not modelled (no wind in the environment).
    pub(crate) fn smoke_cmd(&mut self, owner: usize, r: &Value) -> E<()> {
        if !self.v10_family() {
            return Err("本局规则版本未开放烟幕".into());
        }
        let id = u(r, "ship")?;
        let s = self.ship_for(owner, id)?;
        if self.data.ships[s.def].kind != "DD" {
            return Err("烟幕发生器只装在驱逐舰上".into());
        }
        let on = r.get("on").and_then(Value::as_bool).ok_or("缺少烟幕开关")?;
        let (name, p) = (s.name.clone(), s.p);
        let ship = self.ship_mut(id).unwrap();
        ship.smoking = on;
        if on {
            self.smoke.push(crate::model::SmokeCloud { p, born: self.tick, expires: self.tick + 4 * CYCLE });
        }
        let state = if on { "开始施放烟幕" } else { "停止施放烟幕" };
        self.add(1 << owner, "smoke", format!("{name} · {state}"), Some("RTS-SMOKE-01"), Some(p));
        Ok(())
    }

    /// The searchlight of a ship of `side` lighting `target`, with its
    /// illumination range in yards (5.4.4.1, optical-v2 table).
    pub(crate) fn searchlight_lit(&self, side: usize, target: u32) -> Option<(u32, u32)> {
        self.ships.iter().filter(|s| s.side == side && s.alive())
            .find_map(|s| {
                if s.searchlight != Some(target) { return None; }
                let fixture: u32 = if s.side == 0 { 8000 } else { 7000 };
                let maintained = self.tick / CYCLE > s.searchlight_since / CYCLE;
                let env = self.environment();
                let range = crate::night::searchlight_illumination_range_yd(
                    env, fixture, &self.data.ships[self.ship(target)?.def].size,
                    s.searchlight_die, true, false, maintained,
                );
                Some((fixture, range))
            })
    }

    /// Is `target` inside any live smoke puff, and the sighting cap that
    /// follows (1,000 yd day / 500 yd night; 5.4.5)?
    pub(crate) fn smoke_cap_yd(&self, target: &Ship) -> Option<u32> {
        let inside = self.smoke.iter().any(|cloud| {
            cloud.expires > self.tick && cloud.p.dist(target.p) <= crate::night::smoke_radius_yd() as f64 * YARD
        });
        inside.then(|| {
            if self.environment().light == crate::night::Light::Night { 500 } else { 1000 }
        })
    }

    /// Does the sighting ray cross a live smoke puff? (5.4.5 blocks sighting
    /// through the screen for other surface units.)
    pub(crate) fn smoke_blocks_ray(&self, from: P, to: P) -> bool {
        let radius = crate::night::smoke_radius_yd() as f64 * YARD;
        self.smoke.iter().filter(|cloud| cloud.expires > self.tick).any(|cloud| {
            let ab = to - from;
            let length2 = ab.x * ab.x + ab.y * ab.y;
            if length2 < 1. { return cloud.p.dist(from) <= radius; }
            let t = ((cloud.p - from).dot(ab) / length2).clamp(0., 1.);
            cloud.p.dist(from + ab * t) <= radius
        })
    }
}
