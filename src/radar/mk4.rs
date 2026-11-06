//! Mk4 (FD) cued fire-control evaluation. No world, dice, or sighting side
//! effects; the live v4 caller supplies its independently held optical cue.
//! This cannot discover a target or activate any weapon.
//!
//! Source: Fifth Edition §§2.2.2, 5.2.3, 5.2.5, 6.1.1–3 and American
//! Fleets 2012 Annex J1 PDF 123 (J-1). Device-specific limits are data-driven.
use super::{ray_blocked, rules, sector_contains_polygon, NMI};
use crate::model::{delta, P};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Cue {
    Visual,
    // Source-evaluated, but the live path lacks a separate flash contact.
    #[allow(dead_code)]
    MuzzleFlash,
    // Retained as a negative case; callers handle ordinary search-only fire.
    #[allow(dead_code)]
    SurfaceSearchOnly,
}

pub(crate) struct CuedShot<'a> {
    pub observer: P,
    pub observer_heading: f64,
    pub observer_size: &'a str,
    pub target: P,
    pub target_size: &'a str,
    pub cue: Cue,
    /// True only for a powered, undamaged radar and working main director
    /// assigned to this salvo. Locally aimed gun mounts cannot receive GFC.
    pub director_usable: bool,
    pub land: &'a [Vec<P>],
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct Aid {
    pub fire_control_modifier: i32,
    pub land_clutter_modifier: i32,
    pub ignore_low_visibility_modifier: bool,
}

/// Returns the Mk4's assistance for an already acquired contact only. A
/// negative or absent solution says nothing about the target's actual identity.
/// The 90° search mode and its cumulative failure timer are deliberately absent.
pub(crate) fn evaluate(shot: CuedShot<'_>) -> Option<Aid> {
    if !shot.director_usable || !matches!(shot.observer_size, "C" | "D" | "E") {
        return None;
    }
    let offset = shot.target - shot.observer;
    let bearing = offset.heading();
    // Minor combatants have one F arc director (PDF 61); diagram PDF 14
    // defines F as all but 30° either side of dead astern.
    if delta(bearing, shot.observer_heading).abs() > 150. + 1e-9 {
        return None;
    }
    let r = rules();
    let mk4 = &r.sets["us_mk4_fd"];
    let obs = r.acquisition.surface_class_column.get(shot.observer_size)?;
    let target = r.acquisition.surface_class_column.get(shot.target_size)?;
    let range_col = r
        .acquisition
        .target_columns
        .iter()
        .position(|c| c == target)?;
    let horizon_col = r
        .surface_los
        .target_columns
        .iter()
        .position(|c| c == target)?;
    let nominal = mk4.surface_range_nmi[range_col] * NMI;
    let horizon = r.surface_los.observer_rows_nmi[obs][horizon_col] * NMI;
    if offset.len() > nominal.min(horizon)
        || shot
            .land
            .iter()
            .any(|island| ray_blocked(shot.observer, shot.target, island))
    {
        return None;
    }
    let fire_control_modifier = match shot.cue {
        Cue::Visual => mk4.fire_control_modifier_with_visual?,
        Cue::MuzzleFlash if mk4.blindfire_capable == Some(false) => {
            r.surface_gunnery.modifier_non_blindfire_gfc_at_muzzle_flash
        }
        // A search position alone is not a blindfire solution for an FD set.
        Cue::SurfaceSearchOnly | Cue::MuzzleFlash => return None,
    };
    let land_clutter_modifier = if shot.land.iter().any(|island| {
        sector_contains_polygon(
            shot.observer,
            bearing,
            r.surface_gunnery.gfc_land_clutter_half_sector_deg,
            nominal,
            island,
        )
    }) {
        r.surface_gunnery.modifier_land_clutter_gfc
    } else {
        0
    };
    Some(Aid {
        fire_control_modifier,
        land_clutter_modifier,
        ignore_low_visibility_modifier: r.surface_gunnery.gfc_ignores_low_visibility_modifier,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shot<'a>(cue: Cue, distance: f64, bearing: f64, land: &'a [Vec<P>]) -> CuedShot<'a> {
        CuedShot {
            observer: P::default(),
            observer_heading: 0.,
            observer_size: "C",
            target: P::bearing(bearing) * (NMI * distance),
            target_size: "C",
            cue,
            director_usable: true,
            land,
        }
    }

    #[test]
    fn mk4_requires_cue_range_forward_arc_and_working_director() {
        assert_eq!(
            evaluate(shot(Cue::Visual, 8., 0., &[])),
            Some(Aid {
                fire_control_modifier: 2,
                land_clutter_modifier: 0,
                ignore_low_visibility_modifier: true
            })
        );
        assert_eq!(evaluate(shot(Cue::Visual, 8.01, 0., &[])), None);
        assert!(evaluate(shot(Cue::Visual, 7., 150., &[])).is_some());
        assert!(evaluate(shot(Cue::Visual, 7., 210., &[])).is_some());
        assert_eq!(evaluate(shot(Cue::Visual, 7., 150.1, &[])), None);
        assert_eq!(evaluate(shot(Cue::SurfaceSearchOnly, 7., 0., &[])), None);
        let mut disabled = shot(Cue::Visual, 7., 0., &[]);
        disabled.director_usable = false;
        assert_eq!(evaluate(disabled), None);
    }

    #[test]
    fn muzzle_flash_modifier_includes_radar_bonus_and_obstruction_prevents_tracking() {
        let square = |x, y| {
            vec![
                P { x, y },
                P { x: x + 20., y },
                P {
                    x: x + 20.,
                    y: y + 20.,
                },
                P { x, y: y + 20. },
            ]
        };
        let adjacent = [square(240., 6000.)]; // ≈2.3° off, no obstruction.
        let s = shot(Cue::MuzzleFlash, 7., 0., &adjacent);
        assert_eq!(
            evaluate(s),
            Some(Aid {
                fire_control_modifier: -3,
                land_clutter_modifier: -2,
                ignore_low_visibility_modifier: true
            })
        );
        let distant_bearing = [square(800., 6000.)]; // >5° off.
        assert_eq!(
            evaluate(shot(Cue::MuzzleFlash, 7., 0., &distant_bearing))
                .unwrap()
                .land_clutter_modifier,
            0
        );
        let beyond_range = [square(240., 9. * NMI)];
        assert_eq!(
            evaluate(shot(Cue::Visual, 7., 0., &beyond_range))
                .unwrap()
                .land_clutter_modifier,
            0
        );
        let blocking = [square(-10., 6000.)];
        assert_eq!(evaluate(shot(Cue::Visual, 7., 0., &blocking)), None);
    }
}
