use crate::{model::*, movement::fallback_leader, projectile::Shell, radar::{RadarState, RADAR_DRILL, RADAR_VERSION}};
use serde_json::{json, Value};
use std::collections::BTreeSet;
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
    pub(crate) arena:Option<crate::arena::Start>,
    pub(crate) fuel:Option<crate::fuel::Tank>,
    pub(crate) intel_profile:String,
    pub(crate) expedition:Option<crate::expedition::Run>,
    pub(crate) amphibious_expedition:Option<crate::amphibious_expedition::Run>,
    pub(crate) v4_gun_supply:Option<std::collections::BTreeMap<u32,u32>>,
    pub(crate) ecology:Option<crate::salvage_v3::Ecology>,
    pub(crate) owned_growth:Vec<crate::owned_growth::Stats>,
    pub(crate) owned_practice:Vec<u32>,
    pub(crate) salvage: Option<crate::salvage::Battle>,
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
    pub resupply: Vec<crate::model::ResupplyPoint>,
    pub drum_strings: Vec<u8>,
    pub supply_score: u32,
    /// Savo special rule: the Allied side cannot fire for D6/3 tactical
    /// windows (rounded up) after the Japanese are first detected.
    pub fire_hold: [u32; 2],
    pub fire_hold_rolled: bool,
    pub shells: Vec<Shell>,
    /// Optional, non-authoritative visual records; never serialized into Saved.
    pub(crate) projectile_fx: crate::projectile_presentation::Presentation,
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
    /// Fictional challenge ladder: the stage table names the enemy-loss target
    /// and the stage id. Both are rebuilt from `data/challenge/stages.json` on
    /// load, so only the stage id is persisted.
    pub(crate) challenge_goal: Option<u32>,
    pub(crate) challenge_stage: Option<String>,
    pub(crate) challenge_label: Option<String>,
    /// The exact five single-ship identities chosen for a local exercise.
    /// Saved and replayed so `load`/`replay` rebuild the same fleet.
    pub(crate) local_ships: Option<Vec<String>>,
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

    /// Exercise cards plus the 202 registered single-ship identities. The
    /// printed exercise hulls keep their ids and any collision keeps the
    /// exercise card; the catalogue cards are only targets for an explicit
    /// local fleet pick.
    pub(crate) fn local_data() -> E<&'static Data> {
        static LOCAL: OnceLock<Result<Data, String>> = OnceLock::new();
        LOCAL
            .get_or_init(|| {
                let mut data = Self::exercise_data()?.clone();
                crate::campaign::fleet::add_registered_cards(&mut data)?;
                Ok(data)
            })
            .as_ref()
            .map_err(Clone::clone)
    }

    /// Local exercises with a replaceable five-ship player fleet. Campaigns,
    /// the challenge ladder, the prologue, the historical Empress exercise and
    /// the fixed teaching drills keep their printed rosters.
    pub(crate) fn supports_local_fleet(variant: &str) -> bool {
        matches!(variant, "" | "night")
    }

    pub(crate) fn blank(data: &'static Data, seed: u32, player: usize, enemy: &str, variant: &str, profile: &str, leader_slot: usize) -> Self {
        Self {
            arena:None,
            fuel:None,
            intel_profile:String::new(),
            ecology:None,
            expedition:None,
            amphibious_expedition:None,
            v4_gun_supply:None,
            owned_growth:vec![],
            owned_practice:vec![],
            salvage: None,
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
            resupply: vec![],
            drum_strings: vec![],
            supply_score: 0,
            fire_hold: [0, 0],
            fire_hold_rolled: false,
            shells: vec![],
            projectile_fx: Default::default(),
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
            challenge_goal: None,
            challenge_stage: None,
            challenge_label: None,
            local_ships: None,
        }
    }

    pub fn new(seed: u32, player: usize, enemy: &str, variant: &str, profile: &str, leader_slot: usize) -> E<Self> {
        if !matches!(variant, "" | crate::challenge::VARIANT | "night" | RADAR_DRILL | crate::illumination::TRAINING | crate::illumination::RADAR_TRAINING | crate::prologue::VARIANT | crate::empress::VARIANT) {
            return Err("未知演习想定".into());
        }
        Ai::new(profile, "manual").validate()?;
        if variant == crate::challenge::VARIANT {
            // The staged ladder owns its rosters; `new` keeps the first stage as
            // the backwards-compatible default.
            return Self::new_challenge(seed, player, enemy, profile, leader_slot, "challenge-01");
        }
        if leader_slot >= 5 {
            return Err("领舰未在当前舰队内".into());
        }
        Ai::new(enemy, "auto").validate()?;
        if variant == crate::prologue::VARIANT {
            return crate::prologue::open(seed, player, enemy, profile, leader_slot);
        }
        let data = if variant == crate::empress::VARIANT {
            Self::exercise_data()?
        } else {
            Self::local_data()?
        };
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

    /// Fictional challenge ladder. The stage table supplies both rosters, the
    /// map, the point ceiling and the objective; the enemy AI style comes from
    /// the stage, not from the client's exercise setup.
    pub(crate) fn new_challenge(
        seed: u32,
        player: usize,
        _enemy: &str,
        profile: &str,
        leader_slot: usize,
        stage: &str,
    ) -> E<Self> {
        Ai::new(profile, "manual").validate()?;
        let data = crate::challenge::data()?;
        let mut w = Self::blank(
            data,
            seed,
            player,
            "coord",
            crate::challenge::VARIANT,
            profile,
            leader_slot,
        );
        crate::challenge::open(&mut w, stage, leader_slot)?;
        Ok(w)
    }

    pub(crate) fn spawn(&mut self, def: usize, side: usize, fleet: u32, name: String, p: P, h: f64) -> E<u32> {
        let d = &self.data.ships[def];
        if self.arena.is_none() && !crate::salvage::is_variant(&self.variant) && self.variant!=crate::littoral_v4::VERSION && (!self.host_duel || self.ranked_duel.is_none())
            && ![side_name(side), if side == 0 { "blue" } else { "red" }].contains(&d.side.as_str())
        {
            return Err(format!("{} 的阵营与开局席位不符", d.id));
        }
        if !d.dp.is_finite() || d.dp <= 0.
            || d.gun.range_yd.len() != 4 || d.gun.damage.len() != 4
            || (d.gun.barrels == 0 && !([crate::salvage_v3::VERSION,crate::salvage_v4::VERSION].contains(&self.variant.as_str()) && d.id.starts_with("CAS-FICTION-"))) || d.gun.mounts.iter().map(|m| m.barrels).sum::<u32>() != d.gun.barrels
            || !self.field.contains(p)
        {
            return Err(format!("{} 的阵营、舰卡或出生点无效", d.id));
        }
        let id = (self.ships.len() + 1) as u32;
        // A registered identity is the single-ship key: `IBS-U-*` cards are
        // themselves the catalogue identity, while campaign period/class
        // cards resolve through the pinned runtime table. Unresolved named
        // hulls keep `None` instead of borrowing a same-class character.
        let character = if d.id.starts_with("IBS-U-") {
            Some(d.id.clone())
        } else {
            self.campaign
                .as_ref()
                .and_then(|_| live::character_id(&d.id))
                .map(str::to_string)
        };
        self.ships.push(Ship {
            id, def, side, fleet: Some(fleet), name, character, p, h, speed: 0., escaped: false,
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
        if self.drum_strings.len() < hulls {
            self.drum_strings.resize(hulls, 0);
        }
        Ok(id)
    }

    /// Replace the five player slots with five registered single-ship
    /// identities in one local exercise. Slot positions, headings, speeds and
    /// the formation stay one-to-one. `leader_slot` is an index into `ids`:
    /// that hull takes the leading slot and the remaining picks keep their
    /// scenario order (the same ordering as `World::new(leader_slot)`).
    ///
    /// Everything is validated before a hull is touched. A missing local card
    /// is an explicit error; this never falls back to the printed Fletcher.
    pub(crate) fn replace_player_fleet(&mut self, ids: &[String], leader_slot: usize) -> E<()> {
        if ids.len() != 5 {
            return Err(format!("单舰编队必须正好 5 艘（收到 {} 艘）", ids.len()));
        }
        if leader_slot >= ids.len() {
            return Err("领舰位置无效".into());
        }
        let player_ships: Vec<u32> = self
            .ships
            .iter()
            .filter(|ship| ship.side == self.player)
            .map(|ship| ship.id)
            .collect();
        if player_ships.len() != 5 {
            return Err(format!(
                "当前演习的玩家编队不是 5 艘（有 {} 艘），不能替换单舰",
                player_ships.len()
            ));
        }
        let player_fleets: Vec<u32> = self
            .fleets
            .iter()
            .filter(|fleet| fleet.side == self.player)
            .map(|fleet| fleet.id)
            .collect();
        if player_fleets.len() != 1 {
            return Err("单舰编队需要唯一的玩家编队".into());
        }
        let seat = if self.player == 0 { ["allies", "blue"] } else { ["axis", "red"] };
        let mut seen = BTreeSet::new();
        let mut picked = Vec::with_capacity(ids.len());
        for id in ids {
            if !seen.insert(id.as_str()) {
                return Err(format!("单舰编队不能重复 identity：{id}"));
            }
            let def = self
                .data
                .ships
                .iter()
                .position(|ship| ship.id == *id)
                .ok_or_else(|| format!("本地没有单舰 identity {id} 的已登记舰卡，不能替换"))?;
            let card = &self.data.ships[def];
            if !seat.contains(&card.side.as_str()) {
                return Err(format!("{}（{id}）不属于本席阵营", card.name));
            }
            picked.push(def);
        }
        // The lead pick moves to the front; the other picks keep their
        // scenario slot order.
        let mut order: Vec<usize> = (0..ids.len()).collect();
        let lead = order.remove(leader_slot);
        order.insert(0, lead);
        // Pre-flight the fresh hulls. `spawn` has the same constraints; doing
        // it here keeps a rejected fleet from leaving a half-swapped roster.
        for &def in &picked {
            let card = &self.data.ships[def];
            if !card.dp.is_finite()
                || card.dp <= 0.
                || card.gun.range_yd.len() != 4
                || card.gun.damage.len() != 4
                || card.gun.barrels == 0
                || card.gun.mounts.iter().map(|mount| mount.barrels).sum::<u32>()
                    != card.gun.barrels
            {
                return Err(format!("{} 的舰卡无效，不能替换", card.name));
            }
        }
        let mut plan = Vec::with_capacity(player_ships.len());
        for (position, ship_id) in player_ships.iter().enumerate() {
            let def = picked[order[position]];
            let (p, h, speed, free_speed, fleet) = {
                let old = self.ship(*ship_id).expect("player hull");
                (old.p, old.h, old.speed, old.free_speed, old.fleet.unwrap_or(player_fleets[0]))
            };
            if !self.field.contains(p) {
                return Err(format!("{} 的初始位置不在海图内", self.data.ships[def].name));
            }
            plan.push((*ship_id, def, ids[order[position]].clone(), p, h, speed, free_speed, fleet));
        }
        for (ship_id, def, identity, p, h, speed, free_speed, fleet) in plan {
            let name = self.data.ships[def].name.clone();
            let _fresh_id = self.spawn(def, self.player, fleet, name, p, h)?;
            let mut fresh = self.ships.pop().expect("fresh hull");
            fresh.character = identity.starts_with("IBS-U-").then_some(identity);
            let old = &mut self.ships[(ship_id - 1) as usize];
            *old = crate::model::Ship {
                id: ship_id,
                p,
                h,
                speed,
                free_speed,
                fleet: Some(fleet),
                ..fresh
            };
        }
        self.gun_streak.truncate(self.ships.len());
        self.surface_damage.truncate(self.ships.len());
        let fleet = self.fleet_mut(player_fleets[0]).expect("player fleet");
        fleet.members = player_ships.clone();
        fleet.leader = player_ships[0];
        fleet.points.clear();
        fleet.last_ai_route = 0;
        if self.realtime() {
            let version = self.version;
            self.init_realtime(version)?;
        }
        self.detect(true);
        self.radar_detect();
        self.local_ships = Some(ids.to_vec());
        Ok(())
    }

    pub fn from_save(s: Saved, tick: u32) -> E<Self> {
        if s.arena.is_some() && (s.salvage.is_some()||s.campaign.is_some()||s.ranked.is_some()||s.duel||s.ships.is_some()||s.challenge_stage.is_some()||s.variant!=crate::arena::VARIANT||s.version!=crate::realtime::VERSION||s.side!="allies"||s.enemy!="coord"||s.profile!="coord"||s.leader_slot!=0||s.intel_profile!=crate::intel::VERSION){return Err("竞技存档与内容版本不符".into());}
        if s.variant==crate::arena::VARIANT && s.arena.is_none(){return Err("竞技存档缺少初始编成".into());}
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
        if s.ships.is_some()
            && (s.campaign.is_some() || s.ranked.is_some() || !Self::supports_local_fleet(&s.variant))
        {
            return Err("该存档的想定不支持单舰编队".into());
        }
        // A custom local fleet was built from the un-reordered five slots and
        // then had its leader moved to the front. Rebuild it the same way, not
        // through `new`'s default leader reorder.
        let base_leader_slot = if s.ships.is_some() { 0 } else { s.leader_slot };
        let profile = if s.profile.is_empty() { "coord" } else { &s.profile };
        if s.salvage.is_some() != crate::salvage::is_variant(&s.variant) {
            return Err("打捞内容版本与存档不符".into());
        }
        let mut w = if let Some(start) = s.arena {
            if s.seed!=start.seed{return Err("竞技种子与存档不符".into());} Self::new_arena(start)?
        } else if let Some(start) = s.salvage {
            if start.content!=s.variant {return Err("打捞存档配置与内容版本不符".into());}
            if s.campaign.is_some() || s.ranked.is_some() || s.duel || s.ships.is_some() {
                return Err("打捞存档混入其他模式".into());
            }
            Self::new_salvage(s.seed, start)?
        } else if let Some(ranked) = s.ranked {
            #[cfg(not(target_arch = "wasm32"))]
            { Self::new_ranked_duel(s.seed, ranked)? }
            #[cfg(target_arch = "wasm32")]
            { let _ = ranked; return Err("双席对局由权威主机恢复".into()); }
        } else if let Some(start) = s.campaign {
            if start.seat()? != side(&s.side)? || start.enemy()? != s.enemy || s.leader_slot != 0 {
                return Err("战役存档阵营或编制不符".into());
            }
            Self::new_campaign(s.seed, start, profile)?
        } else if s.variant == crate::challenge::VARIANT {
            Self::new_challenge(
                s.seed,
                side(&s.side)?,
                &s.enemy,
                profile,
                s.leader_slot,
                s.challenge_stage.as_deref().unwrap_or("challenge-01"),
            )?
        } else { Self::new(
            s.seed,
            side(&s.side)?,
            &s.enemy,
            &s.variant,
            profile,
            base_leader_slot,
        )? };
        if let Some(ships) = &s.ships {
            w.leader_slot = s.leader_slot;
            w.replace_player_fleet(ships, s.leader_slot)?;
        }
        if !ranked && realtime && w.campaign.is_none() {
            w.init_realtime(version)?;
        } else {
            w.version = version;
        }
        if s.duel && !ranked {
            w.set_duel_seats();
        }
        w.apply_intel(&s.intel_profile)?;
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
            arena:self.arena.clone(),
            intel_profile:self.intel_profile.clone(),
            salvage: self.salvage.as_ref().map(|b| b.start.clone()),
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
            challenge_stage: self.challenge_stage.clone(),
            ships: self.local_ships.clone(),
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
                "heading":s.h,"speed":s.speed,"hp":s.hp,"maxHp":self.hull_max_hp(s),
                "hullLengthM":d.length_m.max(75.),"hullLengthSource":if d.length_m>=75. {"registered"} else {"engine-clearance-default"},
                "gun":self.can_gun(s),"torpedo":self.can_torp(s),"ammo":s.ammo});
            if let Some(&strings)=self.drum_strings.get((s.id-1) as usize) {
                data["drumStrings"] = json!(strings);
            }
            if let Some(character) = &s.character {
                data["characterId"] = json!(character);
            } else if d.id.starts_with("IBS-U-") {
                // Challenge, prologue and ranked cards carry the catalogue
                // identity as their card id. This also covers seats whose
                // variant is not one of the older special cases.
                data["characterId"] = json!(d.id);
            } else if let Some(character) = self.campaign.as_ref().and_then(|_| live::character_id(&d.id)) {
                data["characterId"] = json!(character);
            }
            if s.searchlight.is_some() {
                if let Some(target) = self.ship(s.searchlight.unwrap()).filter(|t| t.alive()) {
                    let bearing = (target.p - s.p).heading();
                    data["searchlight"] = json!({"target": s.searchlight.unwrap(), "bearing": bearing,
                        "x": target.p.x, "y": target.p.y});
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
            // Detection rings are live against the contacts this seat holds:
            // larger, faster or firing targets are seen farther, and the
            // "being seen" ring uses the known enemy classes as observers.
            let env = self.environment();
            let cycle = self.tick / CYCLE;
            let mut sight = crate::night::surface_base_range_yd(
                env, &d.size, &d.size, 0., false, false,
            );
            let mut seen = 0u32;
            for contact in &self.contacts[s.side] {
                let Some(enemy) = self.ship(contact.ship).filter(|e| e.alive()) else {
                    continue;
                };
                let enemy_def = &self.data.ships[enemy.def];
                sight = sight.max(crate::night::surface_base_range_yd(
                    env,
                    &d.size,
                    &enemy_def.size,
                    enemy.speed,
                    enemy.gun_cycle == Some(cycle),
                    !enemy.fires.is_empty(),
                ));
                seen = seen.max(crate::night::surface_base_range_yd(
                    env,
                    &enemy_def.size,
                    &d.size,
                    s.speed,
                    s.gun_cycle == Some(cycle),
                    !s.fires.is_empty(),
                ));
            }
            data["sightRange"] = json!(sight as f64 * YARD);
            if seen > 0 {
                data["seenRange"] = json!(seen as f64 * YARD);
            }
            if self.realtime() {
                if let Some(order) = &s.battery.order {
                    data["gunTarget"] = json!(order.target);
                    // The live per-volley threshold against the ship's
                    // current target, for the status panel.
                    if let Ok((contact, radar)) = self.gun_contact(s, &order.target) {
                        if let Some(chance) = self.volley_chance(s, contact.as_ref(), radar) {
                            data["targetChance"] = json!(chance);
                        }
                    }
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
                "actual":f.actual,"maxSpeed":self.fleet_max(f),
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
            "scenario":match self.variant.as_str(){"challenge"=>self.challenge_label.as_deref().unwrap_or("越级挑战"),"night"=>"夜航接敌 · 5 对 5 演习",crate::empress::VARIANT=>crate::empress::LABEL,crate::illumination::TRAINING=>"夜战初阵 · 照明实操",crate::illumination::RADAR_TRAINING=>"夜海初航 · 雷达与照明",RADAR_DRILL=>"1943 雷达接敌 · 虚构演习",live::VARIANT=>live::LABEL,crate::campaign::channel::VARIANT=>crate::campaign::channel::LABEL,kula::VARIANT=>kula::LABEL,crate::prologue::VARIANT=>crate::prologue::TITLE,_=>SCENARIO},"variant":self.variant,"ships":ships,"fleets":fleets,"contacts":self.contacts[owner],"torpedoes":torpedoes,"smoke":smoke_view,
            "events":events,"shells":shells,"version":self.version,"environment":self.environment(),"settling":self.result.is_none() && self.action_closed(),"result":self.result_for(owner),"islands":self.islands});
        if let Some(campaign) = self.campaign_view(owner) { view["campaign"] = campaign; }
        if !self.owned_practice.is_empty() && owner==self.player {
            view["ownedGrowth"]=json!({"version":crate::owned_growth::VERSION,"scope":"自有舰战役演练",
                "ships":self.ships.iter().filter(|s|s.side==owner).map(|s|json!({"id":s.character,"practice":(self.owned_practice[s.id as usize-1]/30).min(30)})).collect::<Vec<_>>()});
        }
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
        if !self.resupply.is_empty() {
            view["resupply"] = json!(self.resupply.iter().map(|p| json!({
                "x":p.x,"y":p.y,"radius":p.radius,"capacity":p.capacity
            })).collect::<Vec<_>>());
            view["supplyScore"] = json!(self.supply_score);
        }
        if let Some(ranked) = &self.ranked_duel {
            view["scenario"] = json!(if ranked.budget == 3000 { "三千分护航战" } else { "万分战列舰战" });
        }
        if self.arena.is_some() {view["arena"]=crate::arena::view(self);view["scenario"]=json!(if self.arena.as_ref().unwrap().mode=="team3"{"三对三 · 人机联合演习"}else{"万分排位 · 人机演习"});}
        if self.salvage.is_some() {
            view["scenario"] = json!("失落群岛 · 打捞远征");
            view["salvage"] = self.salvage_view();
            if let Some(weather) = self.dynamic_weather() { view["weather"] = weather.view(self.tick); }
        }
        if self.ecology.is_some() { self.ecology_view(owner,&mut view); }
        if self.story_mission(){self.story_mission_view(&mut view);}
        if self.variant==crate::salvage_v4::VERSION {self.cargo_view(&mut view);}
        self.adventure_view(&mut view);
        self.expedition_view(owner,&mut view);
        self.amphibious_view(&mut view);
        self.fuel_view(&mut view);
        self.intel_view(owner,&mut view);
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
        self.dispatch_external(s,r,true)
    }
    pub(crate) fn dispatch_external(&mut self,s:usize,r:Value,record:bool)->E<()> {
        if let Some(start)=&self.arena {
            let owned=start.groups.iter().map(|g|g.ships.len() as u32).sum::<u32>();
            if r["op"]=="detach"&&self.fleets.iter().filter(|f|f.side==0&&f.members.iter().all(|id|*id<=owned)).count()>=4{return Err("竞技最多同时指挥四个编队".into());}
            if r.get("ship").and_then(Value::as_u64).is_some_and(|id|id>owned as u64)
                || r.get("fleet").and_then(Value::as_u64).and_then(|id|self.fleet(id as u32)).is_some_and(|f|f.members.iter().any(|id|*id>owned)) {
                return Err("AI队友与对手拥有独立指挥权，只能控制自己的编队".into());
            }
        }
        if s==self.player&&self.fuel_empty()&&["route","speed","resume"].contains(&r["op"].as_str().unwrap_or(""))&&!(r["op"]=="speed"&&r["speed"].as_f64()==Some(0.)){return Err("油料耗尽，无法启动推进".into());}
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
            Some("expedition_task"|"expedition_interact"|"extraction_autopilot")=>self.expedition_command(&r)?,
            Some("expedition_land_deploy"|"expedition_land_order"|"expedition_land_task"|"expedition_land_recover"|"expedition_land_autopilot")=>self.amphibious_command(&r)?,
            Some("cargo_place" | "cargo_drop" | "cargo_sort" | "search_salvage" | "cancel_search") => self.cargo_command(&r)?,
            Some("salvage_collect" | "salvage_extract" | "salvage_cancel" | "salvage_drop" | "salvage_abandon") => self.salvage_command(&r)?,
            Some("route") => self.route(s, &r, true)?,
            Some("lead") => self.lead(s, &r)?,
            Some("detach") => self.detach(s, &r)?,
            Some("reform") => self.reform(s, &r)?,
            Some("fire") => self.queue_fire(s, &r, true)?,
            Some("gun_cancel") => self.cancel_realtime_gun(s, &r)?,
            Some("illuminate") => self.queue_illumination(s,&r)?,
            Some("radar_set") => self.radar_power(s, &r)?,
            Some("searchlight") => self.searchlight_cmd(s, &r)?,
            Some("speed") => self.fleet_speed(s, &r)?,
            Some("resume") => self.resume_fleet(s, &r)?,
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
        if record {
        if self.amphibious_expedition.is_some() && matches!(r["op"].as_str(),Some("expedition_land_deploy"|"expedition_land_order"|"expedition_land_task"|"expedition_land_recover")){if let Some(run)=&mut self.expedition{run.autopilot.enabled=false;run.autopilot.reason="指挥官接管陆军操作".into();}}
        if let Some(run)=&mut self.expedition{crate::extraction_ai::manual_override(&mut run.autopilot,&r,self.tick);}
        self.commands.push(Entry {
            tick: self.tick,
            request: r,
            seat: self.host_duel.then(|| side_name(s).into()),
        });
        }
        Ok(())
    }
    fn action_closed(&self) -> bool {
        if self.variant==crate::littoral_v4::VERSION {return self.tick>=self.field.limit;}
        if self.salvage.is_some() { return self.result.is_some() || self.tick >= self.field.limit; }
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
        self.unload_supplies();
        self.apply_savo_fire_hold();
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
        self.weather_events();
        self.advance_owned_practice();
        let before: Vec<_> = self.ships.iter().map(|s| s.p).collect();
        if self.fuel.is_some(){self.advance_fuel();}
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
        if self.ecology.is_some() { self.advance_ecology(); }
        if self.variant==crate::salvage_v4::VERSION {self.advance_cargo_v4();}
        if self.story_mission(){self.advance_story_mission();}
        if self.expedition.is_some(){self.advance_expedition();}
        if self.amphibious_expedition.is_some(){self.advance_amphibious_expedition();}
        if self.salvage.is_some() { self.advance_salvage(); }
        self.check_outcome();
        if self.variant == crate::prologue::VARIANT && self.result.is_none() && !self.action_closed() {
            self.prologue_fire();
        } else if self.result.is_none()
            && (self.version == LEGACY_VERSION || !self.action_closed())
            && (self.tick == 1 || self.tick % 20 == 0 || self.realtime() && self.tick % 4 == 0)
        {
            self.drive_ai();
        }
        if self.open_intel(){self.refresh_open_intel();}
        if self.expedition.is_some(){self.advance_extraction_ai();}
    }
    pub fn sank(&mut self, id: u32) {
        self.expedition_record_defeat(id);
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
    /// Tassafaronga 5.4/objective rule: one drum string per ship per tactical
    /// window, at most three ships per Resupply Point, at 2 knots or less.
    fn unload_supplies(&mut self) {
        if self.resupply.is_empty() || self.tick == 0 || self.tick % CYCLE != 0 {
            return;
        }
        let points = self.resupply.clone();
        let mut used = vec![0u32; points.len()];
        let mut unloads = Vec::new();
        for ship in self.ships.iter().filter(|s| s.side == 1 && s.alive()) {
            let index = (ship.id - 1) as usize;
            if self.drum_strings.get(index).copied().unwrap_or(0) == 0 || ship.speed > 2.05 {
                continue;
            }
            let point = points.iter().enumerate().find(|(index, point)| {
                used[*index] < point.capacity
                    && ship.p.dist(P { x: point.x, y: point.y }) <= point.radius
            }).map(|(index, _)| index);
            let Some(point) = point else { continue };
            used[point] += 1;
            unloads.push((index, point, used[point], ship.p, ship.name.clone()));
        }
        for (index, point, count, at, name) in unloads {
            self.drum_strings[index] -= 1;
            self.supply_score += 20;
            self.add(2, "resupply",
                format!("{name} · 已卸下一串补给桶（本点 {count}/3）"),
                Some("CAS-TASS-RESUPPLY-01"), Some(at));
        }
    }

    /// 5th edition Savo special rule. The first Allied detection of the
    /// Japanese force fixes a D6/3-window fire hold; the D6 is rolled once
    /// and carried in the replay stream.
    pub(crate) fn apply_savo_fire_hold(&mut self) {
        if self.variant != "savo" || self.fire_hold_rolled || self.contacts[0].is_empty() {
            return;
        }
        self.fire_hold_rolled = true;
        let die = self.d(6);
        let windows = (die + 2) / 3;
        self.fire_hold[0] = self.tick + windows * CYCLE;
        self.add(1, "fire_hold",
            format!("日军已被发现：盟军 {windows} 个战术窗口内不能开火（D6={die}）"),
            Some("CAS-RS-SAVO-01"), None);
    }

    fn check_outcome(&mut self) {
        if self.variant==crate::littoral_v4::VERSION {return;}
        if self.arena.is_some(){self.arena_result();return;}
        if self.salvage.is_some() { return; }
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
            let primary = (self.variant == crate::challenge::VARIANT).then(|| {
                lost[1 - self.player] >= self.challenge_goal.unwrap_or(2) && !wiped(self.player)
            });
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
    /// Set the fleet's ordered speed without replanning the route. The
    /// formation still accelerates/decelerates through the normal movement
    /// code; only the target speed changes.
    pub(crate) fn fleet_speed(&mut self, owner: usize, r: &Value) -> E<()> {
        let id = u(r, "fleet")?;
        let speed = r["speed"]
            .as_f64()
            .filter(|v| v.is_finite() && *v >= 0.)
            .ok_or("航速无效")?;
        let max = {
            let fleet = self.fleet_for(owner, id)?;
            let mut max = f64::INFINITY;
            for member in &fleet.members {
                if let Some(ship) = self.ship(*member) {
                    max = max.min(self.max_speed(ship));
                }
            }
            if max.is_finite() { max } else { 0. }
        };
        if speed > max + 1e-6 {
            return Err(format!("航速不得超过编队当前最大航速 {max:.0} 节"));
        }
        let fleet = self.fleet_mut(id).unwrap();
        fleet.speed = speed;
        let name = fleet.name.clone();
        let side = fleet.side;
        self.add(1 << side, "speed", format!("{name} · 编队航速 {speed:.0} 节"), Some("RTS-NAV-03"), None);
        Ok(())
    }

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
