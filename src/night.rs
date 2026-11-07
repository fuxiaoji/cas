//! Optical detection and illumination from the English CAS fifth-edition rules.
//! Callers supply the authority clock and dice; this module never samples hidden state.
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, sync::OnceLock};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Light {
    Day,
    Twilight,
    Night,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub(crate) struct Environment {
    pub visibility: u8,
    pub sea_state: u8,
    pub light: Light,
    pub precipitation: bool,
}

impl Environment {
    pub const DAY: Self = Self {
        visibility: 100,
        sea_state: 2,
        light: Light::Day,
        precipitation: false,
    };
    pub const NIGHT: Self = Self {
        visibility: 20,
        sea_state: 2,
        light: Light::Night,
        precipitation: false,
    };
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum WakePropulsion {
    Steam,
    Electric,
    /// The local ship data do not specify a propulsion bonus; use only base chance.
    Unspecified,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Lighting {
    None,
    Illuminated,
    Silhouetted,
    UsingSearchlight,
}

#[derive(Deserialize)]
struct OpticalData {
    visibility_ladder_pct: Vec<u8>,
    surface_to_surface_yd: BTreeMap<u8, [[u32; 7]; 7]>,
    d100_columns_upper: [i32; 5],
    visual_detection_yd: BTreeMap<u32, [u32; 5]>,
    automatic_below_yd: u32,
    normal_periscope_pct_by_sea_state: [i32; 7],
    launch_range_multiplier: f64,
    launch_gunfire_penalty: i32,
    launch_salvo_threshold: u32,
    launch_salvo_bonus: i32,
    wake_range_multiplier: f64,
    wake_max_sea_state: u8,
    wake_steam_bonus_pct: BTreeMap<String, i32>,
    wake_launch_bonus_pct: i32,
    wake_flaming_datum_bonus_pct: i32,
    searchlight_yd: BTreeMap<u32, [u32; 5]>,
    starshell_gun_caliber_mm_min_max_minrange_radius_yd: Vec<[u32; 4]>,
    starshell_target_size_illum_silhouette_yd: BTreeMap<String, [u32; 2]>,
    starshell_scatter_upper_d100_right_forward_yd_gray: BTreeMap<u32, (i32, i32, bool)>,
    starshell_japan_parachute_year: u16,
}

fn data() -> &'static OpticalData {
    static OPTICAL: OnceLock<OpticalData> = OnceLock::new();
    OPTICAL.get_or_init(|| {
        serde_json::from_str(include_str!("../data/rules/optical-v2.json"))
            .expect("checked optical rules pack")
    })
}

fn size_index(size: &str) -> Option<usize> {
    Some(match size {
        "A" => 0,
        "B" => 1,
        "C" => 2,
        "D" => 3,
        "E" => 4,
        "F" | "G" | "F/G" => 5,
        "Per" => 6,
        _ => return None,
    })
}

fn visibility_step(visibility: u8, steps: i32) -> u8 {
    let ladder = &data().visibility_ladder_pct;
    let current = ladder
        .partition_point(|&v| v <= visibility)
        .saturating_sub(1);
    ladder[(current as i32 + steps).clamp(0, (ladder.len() - 1) as i32) as usize]
}

fn surface_table(visibility: u8, observer: &str, target: &str) -> u32 {
    let Some((observer, target)) = size_index(observer).zip(size_index(target)) else {
        return 0;
    };
    data().surface_to_surface_yd[&visibility_step(visibility, 0)][target][observer]
}

pub(crate) fn surface_base_range_yd(
    env: Environment,
    observer_size: &str,
    target_size: &str,
    target_knots: f64,
    target_fired_large_gun: bool,
    target_on_fire: bool,
) -> u32 {
    let mut visibility = env.visibility;
    if env.light == Light::Night && visibility < 70 {
        let signs = i32::from(target_fired_large_gun) + i32::from(target_on_fire);
        visibility = visibility_step(visibility, 3 * signs).min(70);
    }
    // Stage v2 uses ordinary 20-kt wake thresholds; German S-boats are not in the pack.
    let speed_steps = if target_knots <= 10. {
        -1
    } else if target_knots >= 20. {
        1
    } else {
        0
    };
    surface_table(
        visibility_step(visibility, speed_steps),
        observer_size,
        target_size,
    )
}

fn d100_column(roll: i32) -> usize {
    data()
        .d100_columns_upper
        .iter()
        .position(|&upper| roll <= upper)
        .unwrap_or(4)
}

/// The per-window acquisition probability for one formation, computed exactly
/// from the printed detection table: the fraction of D100 outcomes whose
/// detection range reaches any observer at the current distances. `bases_yd`
/// and `distances_yd` are aligned per observer.
/// cas-realtime-v10: the modelled radius of one smoke puff laid by a
/// destroyer. The printed rule gives the downwind blocked zone (4,000 yards);
/// with no wind modelled the puffs approximate the screen around their spawner.
pub(crate) fn smoke_radius_yd() -> u32 { 1000 }

/// One observing hull's view of one formation member: its own base range, the
/// distance, and its own D100 modifier (cue, firing state).
pub(crate) type DetectionView = (u32, u32, i32);

pub(crate) fn formation_detection_chance(views: &[DetectionView]) -> f64 {
    let automatic = automatic_visual_yd();
    if views.is_empty() {
        return 0.;
    }
    // Inside the automatic band every phase detects without a roll.
    if views.iter().any(|(_, dist, _)| *dist < automatic) {
        return 1.;
    }
    let mut hits = 0u32;
    for die in 1..=100i32 {
        if views
            .iter()
            .any(|(base, dist, modifier)| {
                *dist <= surface_detection_range_yd(*base, die + modifier) as u32
            })
        {
            hits += 1;
        }
    }
    hits as f64 / 100.
}

/// cas-realtime-v10: spread a per-window CAS chance across per-second
/// independent trials so the window-end detection distribution is unchanged
/// while acquisition may happen at any second inside the window.
pub(crate) fn per_second_chance(window_chance: f64, dt_seconds: f64) -> f64 {
    if window_chance >= 1. {
        return 1.;
    }
    if window_chance <= 0. || dt_seconds <= 0. {
        return 0.;
    }
    1. - (1. - window_chance).powf(dt_seconds / 180.)
}

pub(crate) fn surface_detection_range_yd(base_yd: u32, modified_d100: i32) -> u32 {
    data()
        .visual_detection_yd
        .range(..=base_yd)
        .next_back()
        .map_or(0, |(_, row)| row[d100_column(modified_d100)])
}

pub(crate) fn automatic_visual_yd() -> u32 {
    data().automatic_below_yd
}

pub(crate) fn visual_d100_modifier(
    env: Environment,
    cued: bool,
    japanese_night_equipment: bool,
    observer_fired: bool,
) -> i32 {
    let mut modifier = if cued { -20 } else { 0 };
    if env.light == Light::Night && japanese_night_equipment {
        modifier -= 20;
    }
    if observer_fired {
        modifier += match env.visibility {
            0..=5 => 30,
            6..=20 => 20,
            _ => 0,
        };
    }
    modifier
}

pub(crate) fn launch_sighting_chance(
    env: Environment,
    observer_size: &str,
    distance_yd: f64,
    surface: bool,
    firing_guns: bool,
    salvo_count: u32,
) -> u32 {
    let d = data();
    let limit = surface_table(env.visibility, observer_size, "Per") as f64;
    if !surface || limit == 0. || distance_yd > limit * d.launch_range_multiplier {
        return 0;
    }
    let Some(base) = d
        .normal_periscope_pct_by_sea_state
        .get(env.sea_state as usize)
    else {
        return 0;
    };
    let chance =
        base - if firing_guns {
            d.launch_gunfire_penalty
        } else {
            0
        } + if salvo_count >= d.launch_salvo_threshold {
            d.launch_salvo_bonus
        } else {
            0
        };
    chance.clamp(0, 100) as u32
}

pub(crate) fn wake_sighting_chance(
    env: Environment,
    observer_size: &str,
    distance_yd: f64,
    propulsion: WakePropulsion,
    launch_sighted: bool,
    flaming_datum: bool,
) -> u32 {
    let d = data();
    if propulsion == WakePropulsion::Electric || env.sea_state > d.wake_max_sea_state {
        return 0;
    }
    let limit = surface_table(env.visibility, observer_size, "Per") as f64;
    if limit == 0. || distance_yd > limit * d.wake_range_multiplier {
        return 0;
    }
    let steam = if propulsion == WakePropulsion::Steam {
        d.wake_steam_bonus_pct[match env.light {
            Light::Day => "day",
            Light::Twilight => "twilight",
            Light::Night => "night",
        }]
    } else {
        0
    };
    (d.normal_periscope_pct_by_sea_state[env.sea_state as usize]
        + steam
        + if launch_sighted {
            d.wake_launch_bonus_pct
        } else {
            0
        }
        + if flaming_datum {
            d.wake_flaming_datum_bonus_pct
        } else {
            0
        })
    .clamp(0, 100) as u32
}

pub(crate) fn night_gun_modifier(env: Environment, lighting: Lighting) -> i32 {
    match lighting {
        Lighting::Illuminated => -1,
        Lighting::Silhouetted => -2,
        Lighting::UsingSearchlight => 1,
        Lighting::None if env.visibility <= 20 => -4,
        Lighting::None if env.visibility <= 40 => -2,
        Lighting::None => 0,
    }
}

pub(crate) fn identification_level(
    env: Environment,
    d10: u32,
    range_yd: f64,
    visibility_range_yd: u32,
    illuminated: bool,
    target_firing_main: bool,
) -> u8 {
    let mut result = d10 as i32;
    if !illuminated {
        // The printed 20% example applies the applicable tier, not both thresholds.
        result += night_gun_modifier(env, Lighting::None).max(-3);
    }
    if target_firing_main {
        result += if env.light == Light::Night { 4 } else { 2 };
    }
    if range_yd > 0.5 * visibility_range_yd as f64 {
        result -= 2;
    }
    if range_yd < 0.2 * visibility_range_yd as f64 {
        result += 3;
    }
    if result >= 8 {
        3
    } else if result >= 4 {
        2
    } else if result >= 1 {
        1
    } else {
        0
    }
}

pub(crate) fn searchlight_illumination_range_yd(
    env: Environment,
    max_range_yd: u32,
    target_size: &str,
    d100: u32,
    cued: bool,
    multiple_ships: bool,
    maintained_from_last_turn: bool,
) -> u32 {
    let modifier = (if cued { 0 } else { 20 })
        + match size_index(target_size) {
            Some(0 | 1) => -10,
            Some(4) => 10,
            Some(5) => 20,
            _ => 0,
        }
        - if multiple_ships { 20 } else { 0 }
        - if maintained_from_last_turn { 20 } else { 0 };
    let base = data()
        .searchlight_yd
        .range(..=max_range_yd)
        .next_back()
        .map_or(0, |(_, row)| row[d100_column(d100 as i32 + modifier)]);
    if env.visibility <= 2 {
        base / 4
    } else if env.visibility <= 5 || (env.precipitation && env.visibility <= 10) {
        base / 2
    } else {
        base
    }
}

pub(crate) fn searchlight_source_range_yd(
    env: Environment,
    max_range_yd: u32,
    observer_size: &str,
    emitter_size: &str,
) -> u32 {
    if env.light != Light::Night {
        return 0;
    }
    if !env.precipitation {
        return max_range_yd.saturating_mul(5);
    }
    surface_table(
        visibility_step(env.visibility, 3),
        observer_size,
        emitter_size,
    )
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct StarshellProfile {
    pub min_range_yd: u32,
    pub radius_yd: u32,
    pub hit_modifier: i32,
    pub japan_pre1943: bool,
}

pub(crate) fn starshell_profile(
    caliber_mm: u16,
    axis_japan: bool,
    year: u16,
) -> Option<StarshellProfile> {
    let d = data();
    let &[_, _, min_range_yd, radius_yd] = d
        .starshell_gun_caliber_mm_min_max_minrange_radius_yd
        .iter()
        .find(|row| (row[0]..=row[1]).contains(&(caliber_mm as u32)))?;
    let japan_pre1943 = axis_japan && year < d.starshell_japan_parachute_year;
    Some(StarshellProfile {
        min_range_yd,
        radius_yd,
        hit_modifier: if japan_pre1943 { -2 } else { 0 },
        japan_pre1943,
    })
}

pub(crate) fn starshell_visibility_yd(
    env: Environment,
    target_size: &str,
    silhouette: bool,
    profile: StarshellProfile,
) -> u32 {
    let base = data()
        .starshell_target_size_illum_silhouette_yd
        .get(target_size)
        .map_or(0, |pair| pair[usize::from(silhouette)]);
    if env.visibility <= 2 {
        return 0;
    }
    let weather_divisor = if env.visibility <= 5 || (env.precipitation && env.visibility <= 10) {
        2
    } else {
        1
    };
    let parachute_divisor = if profile.japan_pre1943 && !silhouette {
        2
    } else {
        1
    };
    base / (weather_divisor * parachute_divisor)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Scatter {
    /// Marker offsets measured along the firing line, relative to the aimpoint.
    pub right_yd: i32,
    pub forward_yd: i32,
    /// Printed gray cells qualify for silhouette, still subject to visibility.
    pub silhouette: bool,
}

pub(crate) fn starshell_scatter(d100: u32) -> Option<Scatter> {
    if !(1..=95).contains(&d100) {
        return None;
    }
    let (_, &(right_yd, forward_yd, silhouette)) = data()
        .starshell_scatter_upper_d100_right_forward_yd_gray
        .range(d100..)
        .next()?;
    Some(Scatter {
        right_yd,
        forward_yd,
        silhouette,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn original_visual_example_and_ranges() {
        let env = Environment {
            visibility: 60,
            ..Environment::DAY
        };
        assert_eq!(
            surface_base_range_yd(env, "A", "B", 15., false, false),
            23_000
        );
        assert_eq!(surface_detection_range_yd(23_000, 58), 16_500);
        assert_eq!(surface_detection_range_yd(29_000, 100), 17_500);
        assert_eq!(surface_detection_range_yd(28_000, 100), 17_000);
        assert_eq!(
            surface_base_range_yd(Environment::NIGHT, "B", "C", 15., false, false),
            6_500
        );
        assert_eq!(
            surface_base_range_yd(Environment::NIGHT, "C", "C", 15., true, false),
            16_000
        );
        assert_eq!(
            surface_base_range_yd(Environment::NIGHT, "C", "C", 10., false, false),
            3_000
        );
        assert_eq!(automatic_visual_yd(), 300);
    }

    #[test]
    fn launch_and_wake_limits_follow_the_main_book() {
        let d = Environment::DAY;
        assert_eq!(launch_sighting_chance(d, "C", 7500., true, false, 3), 50);
        assert_eq!(launch_sighting_chance(d, "C", 7500.1, true, false, 3), 0);
        assert_eq!(launch_sighting_chance(d, "C", 5000., true, true, 3), 25);
        assert_eq!(launch_sighting_chance(d, "C", 10., false, false, 6), 0);
        let n = Environment::NIGHT;
        assert_eq!(
            wake_sighting_chance(n, "C", 3000., WakePropulsion::Steam, true, false),
            85
        );
        assert_eq!(
            wake_sighting_chance(n, "C", 3000.1, WakePropulsion::Steam, true, true),
            0
        );
        assert_eq!(
            wake_sighting_chance(n, "C", 500., WakePropulsion::Electric, true, true),
            0
        );
        assert_eq!(
            wake_sighting_chance(
                Environment { sea_state: 5, ..n },
                "C",
                500.,
                WakePropulsion::Steam,
                true,
                true
            ),
            0
        );
    }

    #[test]
    fn searchlight_and_starshell_golden_cases() {
        let n = Environment::NIGHT;
        assert_eq!(
            searchlight_illumination_range_yd(n, 8000, "C", 50, true, false, false),
            6000
        );
        assert_eq!(
            searchlight_illumination_range_yd(n, 8000, "C", 51, true, false, false),
            5000
        );
        assert_eq!(searchlight_source_range_yd(n, 8000, "C", "C"), 40_000);
        assert_eq!(night_gun_modifier(n, Lighting::None), -4);
        assert_eq!(night_gun_modifier(n, Lighting::UsingSearchlight), 1);
        assert_eq!(identification_level(n, 5, 4000., 6000, false, false), 0);
        assert_eq!(identification_level(n, 5, 2100., 6000, false, true), 2);
        let shell = starshell_profile(127, true, 1942).unwrap();
        assert_eq!(
            (shell.min_range_yd, shell.radius_yd, shell.hit_modifier),
            (4000, 400, -2)
        );
        assert_eq!(starshell_visibility_yd(n, "C", false, shell), 6000);
        assert_eq!(starshell_visibility_yd(n, "C", true, shell), 7000);
        assert_eq!(
            starshell_scatter(10),
            Some(Scatter {
                right_yd: 0,
                forward_yd: 2000,
                silhouette: true
            })
        );
        assert_eq!(
            starshell_scatter(81),
            Some(Scatter {
                right_yd: 0,
                forward_yd: -2000,
                silhouette: false
            })
        );
        assert_eq!(starshell_scatter(96), None);
    }
}

#[cfg(test)]
mod hazard_tests {
    use super::*;

    #[test]
    fn automatic_band_and_empty_views_are_deterministic() {
        assert_eq!(formation_detection_chance(&[]), 0.);
        let close = automatic_visual_yd() - 10;
        assert_eq!(formation_detection_chance(&[(10_000, close, 0)]), 1.);
    }

    #[test]
    fn per_second_hazard_integrates_to_the_window_chance() {
        for window in [0.05f64, 0.2, 0.5, 0.75, 0.99] {
            let per_second = per_second_chance(window, 1.);
            // Exactly 180 seconds of independent trials.
            let no_detect = (1. - per_second).powi(180);
            assert!((no_detect - (1. - window)).abs() < 1e-9, "window {window}: {no_detect}");
        }
        assert_eq!(per_second_chance(1., 1.), 1.);
        assert_eq!(per_second_chance(0., 1.), 0.);
    }

    #[test]
    fn monte_carlo_seconds_match_the_window_roll() {
        // 180 Bernoulli draws at the per-second hazard reproduce the window
        // roll frequency; 20k replications keep the 3-sigma band tight.
        let window = 0.4f64;
        let per_second = per_second_chance(window, 1.);
        let mut state = 0x5eed_c0de_u64;
        let mut detected = 0u32;
        let reps = 20_000;
        for _ in 0..reps {
            let mut hit = false;
            for _ in 0..180 {
                if crate::world::roll(&mut state, 10_000) as f64 / 10_000. < per_second {
                    hit = true;
                    break;
                }
            }
            detected += u32::from(hit);
        }
        let frequency = f64::from(detected) / f64::from(reps);
        // 3 sigma of a binomial(p=0.4, n=20000) is ~0.0033.
        assert!((frequency - window).abs() < 0.01, "frequency {frequency}");
    }
}
