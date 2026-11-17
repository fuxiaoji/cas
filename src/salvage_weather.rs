//! Authored regional weather for new fictional salvage voyages only.
//! The timeline has its own seed; neither reading it nor constructing it rolls
//! combat/optics dice. Saves freeze its version and rebuild from seed + tick.
use crate::{night::{Environment, Light}, world::{roll, World}};
use serde::Deserialize;
use serde_json::{json, Value};
use std::sync::OnceLock;

pub(crate) const VERSION: &str = "salvage-weather-v1";

#[derive(Clone, Deserialize)]
struct Preset {
    kind: String,
    label: String,
    visibility: u8,
    precipitation: bool,
    cloud_cover: f64,
    rain_intensity: f64,
    fog_density: f64,
}

#[derive(Deserialize)]
struct Pack {
    version: String,
    phase_seconds: u32,
    transition_seconds: u32,
    sea_state: u8,
    presets: Vec<Preset>,
    successors: Vec<Vec<usize>>,
    visual_wind_speed: u32,
}

fn pack() -> &'static Pack {
    static PACK: OnceLock<Pack> = OnceLock::new();
    PACK.get_or_init(|| serde_json::from_str(include_str!("../data/salvage/weather-v1.json"))
        .expect("versioned fictional weather pack"))
}

#[derive(Clone, Debug)]
pub(crate) struct Timeline {
    fronts: Vec<usize>,
    wind_heading: u32,
}

impl Timeline {
    pub(crate) fn new(seed: u32) -> Self {
        let p = pack();
        let mut rng = u64::from(seed) ^ 0xa197_725b_46d3_80e1;
        let wind_heading = roll(&mut rng, 360) - 1;
        let mut fronts = vec![0];
        // Include one forecast beyond the voyage's maximum active duration.
        for _ in 0..=crate::salvage::LIMIT / p.phase_seconds {
            let candidates = &p.successors[*fronts.last().unwrap()];
            fronts.push(candidates[(roll(&mut rng, candidates.len() as u32) - 1) as usize]);
        }
        Self { fronts, wind_heading }
    }

    pub(crate) fn authored(seed:u32,kind:&str)->Self {
        let mut out=Self::new(seed);
        if let Some(index)=pack().presets.iter().position(|p|p.kind==kind){out.fronts[0]=index;}
        out
    }
    fn phase(&self, tick: u32) -> usize {
        (tick / pack().phase_seconds).min(self.fronts.len() as u32 - 2) as usize
    }

    pub(crate) fn environment(&self, tick: u32) -> Environment {
        let p = pack();
        let current = &p.presets[self.fronts[self.phase(tick)]];
        Environment { light: Light::Day, visibility: current.visibility,
            sea_state: p.sea_state, precipitation: current.precipitation }
    }

    pub(crate) fn view(&self, tick: u32) -> Value {
        let p = pack();
        let phase = self.phase(tick);
        let current = &p.presets[self.fronts[phase]];
        let next = &p.presets[self.fronts[phase + 1]];
        let started = phase as u32 * p.phase_seconds;
        let ends = started + p.phase_seconds;
        let elapsed = tick.saturating_sub(ends - p.transition_seconds).min(p.transition_seconds);
        let progress = f64::from(elapsed) / f64::from(p.transition_seconds);
        let mix = |a: f64, b: f64| a + (b - a) * progress;
        json!({"version":p.version, "kind":current.kind, "next":next.kind,
            "phase_started_tick":started, "phase_ends_tick":ends, "rules_change_tick":ends,
            "transition_seconds":p.transition_seconds, "transition_progress":progress,
            "cloud_cover":mix(current.cloud_cover,next.cloud_cover),
            "rain_intensity":mix(current.rain_intensity,next.rain_intensity),
            "fog_density":mix(current.fog_density,next.fog_density),
            "visual_wind_heading_deg":self.wind_heading, "visual_wind_speed":p.visual_wind_speed,
            "visibility":current.visibility, "next_visibility":next.visibility})
    }
}

impl World {
    pub(crate) fn dynamic_weather(&self) -> Option<&Timeline> {
        self.salvage.as_ref().and_then(|battle| battle.weather.as_ref())
    }

    pub(crate) fn weather_events(&mut self) {
        let Some(timeline) = self.dynamic_weather() else { return };
        let p = pack();
        let phase = timeline.phase(self.tick);
        let within = self.tick % p.phase_seconds;
        let message = if within == p.phase_seconds - p.transition_seconds {
            let next = &p.presets[timeline.fronts[phase + 1]];
            Some(("weather_forecast", format!("海况预报：{} 秒后转为{}，能见度 {}%", p.transition_seconds, next.label, next.visibility)))
        } else if within == 0 {
            let current = &p.presets[timeline.fronts[phase]];
            Some(("weather", format!("天气转为{}，能见度 {}%", current.label, current.visibility)))
        } else { None };
        if let Some((kind, text)) = message {
            self.add(3, kind, text, Some("CAS-SALVAGE-WEATHER-01"), None);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{model::{Contact, P, YARD}, salvage::{Hull, Start}};

    fn start(dynamic: bool) -> Start {
        Start { content: crate::salvage::VARIANT.into(),
            weather: dynamic.then(|| VERSION.into()),
            fleet: vec![Hull {id:"IBS-U-USN-FLETCHER".into(),hp:100,ammo:100,
                level:1,equipment:false,command:false,..Default::default()}],..Default::default() }
    }

    #[test]
    fn independent_timeline_leaves_initial_combat_streams_and_terrain_unchanged() {
        for seed in [0, 42, 6106, u32::MAX] {
            let old = World::new_salvage(seed, start(false)).unwrap();
            let new = World::new_salvage(seed, start(true)).unwrap();
            assert_eq!((old.rng,old.optics_rng,old.surface_critical_rng),
                (new.rng,new.optics_rng,new.surface_critical_rng));
            let mut view = new.observation(0);
            view.as_object_mut().unwrap().remove("weather");
            assert_eq!(view,old.observation(0));
            let before = new.save();
            for tick in 0..=crate::salvage::LIMIT {
                let weather = new.dynamic_weather().unwrap();
                assert_eq!(weather.view(tick),Timeline::new(seed).view(tick));
                assert_eq!(weather.environment(tick).sea_state,2);
            }
            assert_eq!(json!(before),json!(new.save()));
        }
        let all = (0..20).flat_map(|seed| Timeline::new(seed).fronts).collect::<std::collections::BTreeSet<_>>();
        assert_eq!(all.len(),5,"all authored weather types reachable across seeds");
    }

    #[test]
    fn forecast_precedes_exact_rule_boundary_and_view_is_readonly() {
        let mut w = World::new_salvage(6106,start(true)).unwrap();
        for _ in 0..195 { w.advance(); }
        assert_eq!(w.observation(0)["weather"]["kind"],"clear");
        assert!(w.events.iter().any(|e| e.kind=="weather_forecast"));
        let before = w.observation(0);
        let rng = (w.rng,w.optics_rng,w.surface_critical_rng);
        for _ in 0..10 { assert_eq!(w.observation(0),before); }
        assert_eq!((w.rng,w.optics_rng,w.surface_critical_rng),rng);
        for _ in 195..239 { w.advance(); }
        let last = w.observation(0);
        assert_eq!(last["weather"]["kind"],"clear");
        assert_eq!(last["weather"]["rules_change_tick"],240);
        assert!(last["weather"]["transition_progress"].as_f64().unwrap()>0.97);
        w.advance();
        assert_eq!(w.observation(0)["weather"]["kind"],"cloudy");
        assert_eq!(w.observation(0)["weather"]["transition_progress"],0.0);
        assert_eq!(w.events.iter().filter(|e|e.kind=="weather").count(),1);
    }

    #[test]
    fn new_and_legacy_voyages_restore_the_same_world_and_future() {
        for dynamic in [false,true] {
            let mut w = World::new_salvage(42,start(dynamic)).unwrap();
            for _ in 0..478 { w.advance(); }
            let save = w.save();
            assert_eq!(json!(save)["salvage"].get("weather").is_some(),dynamic);
            let mut restored = World::from_save(save, w.tick).unwrap();
            assert_eq!(restored.observation(0),w.observation(0));
            for _ in 0..35 {
                w.advance();restored.advance();
                assert_eq!(restored.observation(0),w.observation(0));
            }
            assert_eq!((restored.rng,restored.optics_rng,restored.surface_critical_rng),
                (w.rng,w.optics_rng,w.surface_critical_rng));
            if !dynamic { assert_eq!(w.environment(),Environment::DAY); }
        }
        let mut invalid = start(true); invalid.weather=Some("future-version".into());
        assert!(World::new_salvage(1,invalid).is_err());
    }

    #[test]
    fn historical_and_training_environments_never_gain_weather() {
        for variant in ["","night","prologue","night-training","night-radar-training","empress"] {
            let mut w = World::new(6106,0,"gunnery",variant,"coord",0).unwrap();
            w.enable_realtime().unwrap();
            let initial = w.environment();
            for _ in 0..241 { w.advance(); }
            assert_eq!(w.environment(),initial,"{variant}");
            assert!(w.dynamic_weather().is_none());
            assert!(w.observation(0).get("weather").is_none());
        }
    }

    fn firing_fixture(preset: usize) -> World {
        let mut w = World::new_salvage(42,start(true)).unwrap();
        w.salvage.as_mut().unwrap().weather.as_mut().unwrap().fronts.fill(preset);
        w.islands.clear();
        for ship in &mut w.ships { ship.p=P{x:20000.,y:12000.}; }
        w.ships[0].p=P{x:2200.,y:2200.};w.ships[0].h=0.;
        w.ships[1].p=P{x:7200.,y:2200.};w.ships[1].h=0.;w.ships[1].speed=15.;
        w.contacts[0]=vec![Contact {id:"C01".into(),ship:2,x:7200.,y:2200.,heading:0.,speed:15.,
            kind:None,name:None,first_cycle:0,acquisition_base_yd:0,acquisition_range_yd:0}];
        w.contacts[1].clear();
        w
    }

    #[test]
    fn rain_and_fog_use_printed_ranges_and_actual_aimed_fire_threshold() {
        let sunny = firing_fixture(0);
        let base = sunny.preview_aim(0,&json!({"ship":1,"weapon":"gun","target":"C01"})).unwrap()["chance"].as_f64().unwrap();
        for (preset,modifier) in [(0,0),(3,-2),(4,-4)] {
            for hit in [true,false] {
                let mut w = firing_fixture(preset);
                let aim = w.preview_aim(0,&json!({"ship":1,"weapon":"gun","target":"C01"})).unwrap();
                assert_eq!(aim["valid"],true,"{aim}");
                let chance = aim["chance"].as_f64().unwrap();
                let ship = w.ship(1).unwrap();
                let def = &w.data.ships[ship.def];
                let distance = ship.p.dist(w.ship(2).unwrap().p)/YARD;
                let band = def.gun.range_yd.iter().position(|&max| distance<=max).unwrap();
                assert_eq!(chance,base+f64::from(modifier)*if band<=1 {4.}else{2.});
                let barrels=aim["barrels"].as_u64().unwrap() as u32;
                assert!(chance>0. && chance<90.);
                w.ship_mut(1).unwrap().battery.hit_roll=Some(chance.floor() as u32+u32::from(!hit));
                let contact = w.contacts[0][0].clone();
                w.fire_realtime_volleys(vec![crate::realtime::Volley {ship:1,contact,band,
                    barrels,battery_barrels:barrels,radar_only:false,reload:4}]);
                assert_eq!(w.shells.len(),1,"actual volley must launch");
                w.tick+=crate::realtime::MAX_FLIGHT;
                w.advance_shells();
                assert_eq!(w.surface_damage[1].total>0.,hit,"visible aim threshold and actual impact must agree");
            }
        }
        let mut fog=firing_fixture(4);
        // A previously acquired target beyond the printed 20% D/D range is
        // removed, not merely dimmed by the client.
        fog.ships[1].p.x=15000.;fog.contacts[0][0].x=15000.;
        fog.update_tracks();
        assert!(fog.contacts[0].is_empty());
        assert!(fog.events.iter().any(|e|e.kind=="lost"));
    }
}
