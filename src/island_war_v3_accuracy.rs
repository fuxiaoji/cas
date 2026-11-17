//! Original v3 weapon-specific distance accuracy, shared by adjudication, AI and catalogue.
use super::*;
#[derive(Clone, Copy)]
struct Accuracy {
    base: f64,
    knots: [f64; 5],
    moving: f64,
    close: f64,
    close_m: f64,
    effective: f64,
}
fn profile(w: &Weapon) -> Accuracy {
    let (base, knots, moving, close, close_m, effective) = match w.family_id {
        "smg" => (0.94, [1., 0.85, 0.45, 0.18, 0.07], 0.85, 1., 0., 0.45),
        "rifle" => (0.91, [1., 0.98, 0.84, 0.60, 0.35], 0.78, 1., 0., 0.65),
        "carbine" => (0.90, [1., 0.95, 0.76, 0.48, 0.25], 0.80, 1., 0., 0.60),
        "pistol" => (0.85, [1., 0.83, 0.55, 0.25, 0.12], 0.85, 1., 0., 0.45),
        "dmr" => (0.92, [1., 0.99, 0.95, 0.88, 0.78], 0.55, 0.85, 100., 0.85),
        "sniper" | "heavy_sniper" => (0.95, [1., 1., 0.98, 0.94, 0.88], 0.25, 0.35, 350., 0.90),
        "lmg" => (0.88, [1., 0.94, 0.78, 0.52, 0.32], 0.45, 1., 0., 0.60),
        "shotgun" => (0.96, [1., 0.80, 0.50, 0.18, 0.05], 0.80, 1., 0., 0.35),
        "rocket" => (0.88, [1., 0.98, 0.88, 0.72, 0.55], 0.50, 1., 0., 0.75),
        "tank_gun" => (0.90, [1., 0.99, 0.92, 0.80, 0.65], 0.60, 1., 0., 0.75),
        "autocannon" | "helicopter_cannon" => {
            (0.88, [1., 0.97, 0.86, 0.68, 0.45], 0.75, 1., 0., 0.70)
        }
        "aa_missile" | "aa_cannon" => (0.94, [1., 1., 0.96, 0.88, 0.75], 0.75, 1., 0., 0.80),
        "howitzer" => (0.85, [1., 0.99, 0.92, 0.80, 0.65], 0.65, 1., 0., 0.75),
        "grenade" => (0.90, [1., 0.98, 0.90, 0.78, 0.60], 0.85, 1., 0., 0.65),
        _ => (0.90, [1., 0.95, 0.80, 0.60, 0.40], 0.75, 1., 0., 0.65),
    };
    Accuracy {
        base: base * w.accuracy_scale,
        knots,
        moving,
        close,
        close_m,
        effective,
    }
}
pub(super) fn indirect(w: &Weapon) -> bool {
    w.blast_radius_m > 0.
}
pub(super) fn probability(w: &Weapon, distance: f64, moving: bool, spread_multiplier: f64) -> f64 {
    if !distance.is_finite() || distance < 0. || distance > w.range_m {
        return 0.;
    }
    let a = profile(w);
    let fraction = (distance / w.range_m).clamp(0., 1.);
    let scaled = fraction * 4.;
    let lo = (scaled.floor() as usize).min(3);
    let t = scaled - lo as f64;
    let curve = a.knots[lo] + (a.knots[lo + 1] - a.knots[lo]) * t;
    let close = if a.close_m > 0. {
        a.close + (1. - a.close) * (distance / a.close_m).clamp(0., 1.)
    } else {
        1.
    };
    (a.base * curve * if moving { a.moving } else { 1. } * close / spread_multiplier.max(0.1))
        .clamp(0., 0.99)
}
pub(super) fn effective(w: &Weapon) -> f64 {
    w.range_m * profile(w).effective
}
pub(super) fn roll(seed: u32, shot: u32) -> f64 {
    let mut x = seed ^ shot.wrapping_mul(0x9e3779b9) ^ 0xa341316c;
    x ^= x >> 16;
    x = x.wrapping_mul(0x7feb352d);
    x ^= x >> 15;
    x = x.wrapping_mul(0x846ca68b);
    x ^= x >> 16;
    x as f64 / 4294967296.
}
pub(super) fn compact(w: &Weapon) -> Value {
    let a = profile(w);
    let mut row = json!(w);
    row["mean_fire_interval_s"] = json!(w.reload_s);
    row["accuracy"] = json!({"model":"piecewise-linear-v1","application":if indirect(w){"indirect_spread"}else{"direct_probability"},"base_hit":a.base,"curve":(0..5).map(|i|json!({"range_fraction":i as f64/4.,"multiplier":a.knots[i]})).collect::<Vec<_>>(),"moving_multiplier":a.moving,"moving_threshold_mps":2.,"close_multiplier":a.close,"close_range_m":a.close_m,"effective_range_m":effective(w),"clamp_min":0.,"clamp_max":0.99});
    row
}
pub(super) fn scatter(w: &Weapon, quality: f64, seed: u32, shot_key: u32) -> P {
    let angle = roll(seed, shot_key.wrapping_mul(7)) * 360.;
    let radial = roll(seed ^ 0x57b1a399, shot_key).sqrt();
    P::bearing(angle) * (w.blast_radius_m * 0.85 / quality.max(0.05) * radial)
}
pub(super) fn view(w: &Weapon) -> Value {
    let a = profile(w);
    let mut row = json!(w);
    row["mean_fire_interval_s"] = json!(w.reload_s);
    row["accuracy"] = json!({"model":"piecewise-linear-v1","application":if indirect(w){"indirect_spread"}else{"direct_probability"},"base_hit":a.base,"curve":(0..5).map(|i|json!({"range_fraction":i as f64/4.,"multiplier":a.knots[i]})).collect::<Vec<_>>(),"moving_multiplier":a.moving,"moving_threshold_mps":2.,"close_multiplier":a.close,"close_range_m":a.close_m,"close_interpolation":"linear from close_multiplier at zero to 1 at close_range_m","effective_range_m":effective(w),"clamp_min":0.,"clamp_max":0.99,"baseline":"stationary shooter; point-target probability (direct) or real geometric aim spread (area); no command buff; terrain/protection affect damage separately","formula":"clamp(base_hit * linear(curve,distance/range_m) * (moving?moving_multiplier:1) * lerp(close_multiplier,1,clamp(distance/close_range_m,0,1)) / command_spread_multiplier,0,0.99)","direct_motion_model":"one probability roll; successful direct fire resolves on current living target; no second geometry hit roll","indirect_motion_model":"unguided area rounds lead current target velocity; AA missile tracks with fixed seeded error; targets may evade area rounds","indirect_formula":"uniform seeded disk: maximum radius meters = blast_radius_m * 0.85 / max(quality,0.05); radial=sqrt(uniform); no separate probability hit roll","samples":(0..=10).map(|i|{let d=w.range_m*i as f64/10.;json!({"distance_m":d,"range_fraction":i as f64/10.,"stationary":probability(w,d,false,1.),"moving":probability(w,d,true,1.)})}).collect::<Vec<_>>()});
    row
}
impl Battle {
    pub(super) fn engagement_range(&self, ci: usize, class: &str) -> f64 {
        let c = &self.base.companies[ci];
        let mut available = vec![];
        for id in &c.bodies {
            if self.base.body(*id).is_some_and(|b| b.hp > 0.) {
                let b = self.base.body(*id).unwrap();
                let w = self.loadouts[id].weapon;
                if b.ammo > 0
                    && !(w.family_id == "rocket" && !matches!(class, "light_armor" | "heavy_armor"))
                {
                    available.push(w);
                }
                if let Some(s) = self.secondary.get(id) {
                    if s.ammo > 0 {
                        available.push(s.weapon);
                    }
                }
            }
        }
        let options = [
            75., 100., 150., 220., 300., 400., 500., 650., 800., 1000., 1200., 1500., 1800., 2100.,
            2400.,
        ];
        let scores = options.map(|d| {
            (
                d,
                available
                    .iter()
                    .map(|w| {
                        w.damage * factor(w, class) * probability(w, d, false, 1.) / w.reload_s
                    })
                    .sum::<f64>(),
            )
        });
        let best = scores.iter().map(|(_, v)| *v).fold(0., f64::max);
        scores
            .into_iter()
            .filter(|(_, v)| best > 0. && *v >= best * 0.85)
            .last()
            .map_or(150., |(d, _)| d)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn smg_falls_steeply_and_dmr_stays_useful_at_distance() {
        let s = weapon("smg");
        let d = weapon("dmr");
        assert!(probability(s, s.range_m * 0.9, false, 1.) < 0.15);
        assert!(probability(d, d.range_m * 0.9, false, 1.) > 0.7);
        assert!(probability(s, 50., false, 1.) > probability(s, 400., false, 1.) * 4.);
        assert!(effective(s) < 250.);
        assert!(effective(d) > 1000.);
    }
    #[test]
    fn sniper_close_and_moving_are_real_penalties_and_buff_is_bounded() {
        let w = weapon("heavy_sniper");
        assert!(probability(w, 50., false, 1.) < probability(w, 800., false, 1.) * 0.5);
        assert!(probability(w, 800., true, 1.) < probability(w, 800., false, 1.) * 0.3);
        assert!(
            probability(weapon("rifle"), 500., false, 0.8)
                > probability(weapon("rifle"), 500., false, 1.)
        );
        assert!(probability(w, 1000., false, 0.1) <= 0.99);
        assert_eq!(probability(w, w.range_m + 1., false, 1.), 0.);
    }
    #[test]
    fn deterministic_roll_frequency_matches_probability_without_shared_rng() {
        let count = (0..20000).filter(|id| roll(714, *id) < 0.25).count();
        assert!((count as i32 - 5000).abs() < 250);
        assert_eq!(roll(714, 99), roll(714, 99));
        assert_ne!(roll(714, 99), roll(715, 99));
    }
    #[test]
    fn every_weapon_exports_the_exact_runtime_samples() {
        for w in &WEAPONS {
            let row = view(w);
            for sample in row["accuracy"]["samples"].as_array().unwrap() {
                let d = sample["distance_m"].as_f64().unwrap();
                assert_eq!(sample["stationary"], json!(probability(w, d, false, 1.)));
                assert_eq!(sample["moving"], json!(probability(w, d, true, 1.)));
            }
        }
    }
}
