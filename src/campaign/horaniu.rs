//! End-state objective counts for Rising Sun, printed p. 88.
//! The encounter stays closed until the small-craft engine and map can produce these facts.
use super::{Grade, Outcome};

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Destroyer {
    Afloat { damage_fraction: f64 },
    Sunk,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransportBarge {
    AtSea,
    LandedAtHoraniu,
    Sunk,
}

/// Only the four Japanese DDs and the thirteen convoy transports enter this
/// projection. Armed Toku escorts are not counted under the current reading.
pub fn assess(
    destroyers: &[Destroyer; 4],
    transport_barges: &[TransportBarge; 13],
) -> Result<Outcome, &'static str> {
    let mut dd_sunk = 0;
    let mut dd_half_damage = 0;
    for dd in destroyers {
        match dd {
            Destroyer::Sunk => {
                dd_sunk += 1;
                dd_half_damage += 1;
            }
            Destroyer::Afloat { damage_fraction } if (0. ..1.).contains(damage_fraction) => {
                dd_half_damage += u8::from(*damage_fraction >= 0.5);
            }
            _ => return Err("霍腊纽结算收到无效的驱逐舰损伤比例"),
        }
    }
    let sunk = transport_barges
        .iter()
        .filter(|b| **b == TransportBarge::Sunk)
        .count();
    let landed = transport_barges
        .iter()
        .filter(|b| **b == TransportBarge::LandedAtHoraniu)
        .count();
    Ok(Outcome {
        allies: if dd_sunk >= 2 && sunk >= 7 {
            Grade::Decisive
        } else if dd_half_damage >= 2 && sunk >= 4 {
            Grade::Tactical
        } else {
            Grade::None
        },
        axis: if dd_sunk > 0 {
            Grade::None
        } else if landed == transport_barges.len() {
            Grade::Decisive
        } else if landed >= transport_barges.len().div_ceil(2) {
            Grade::Tactical
        } else {
            Grade::None
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use TransportBarge::{AtSea, LandedAtHoraniu, Sunk};

    const INTACT: Destroyer = Destroyer::Afloat {
        damage_fraction: 0.,
    };
    const HALF: Destroyer = Destroyer::Afloat {
        damage_fraction: 0.5,
    };

    #[test]
    fn allied_needs_both_ship_damage_and_transport_losses() {
        let dd = [HALF, Destroyer::Sunk, INTACT, INTACT];
        let mut barges = [AtSea; 13];
        barges[..3].fill(Sunk);
        assert_eq!(assess(&dd, &barges).unwrap().allies, Grade::None);
        barges[3] = Sunk;
        assert_eq!(assess(&dd, &barges).unwrap().allies, Grade::Tactical);
        let below_half = Destroyer::Afloat {
            damage_fraction: 0.4999,
        };
        assert_eq!(
            assess(&[below_half, Destroyer::Sunk, INTACT, INTACT], &barges)
                .unwrap()
                .allies,
            Grade::None
        );
        barges[..7].fill(Sunk);
        assert_eq!(
            assess(&[Destroyer::Sunk, Destroyer::Sunk, INTACT, INTACT], &barges)
                .unwrap()
                .allies,
            Grade::Decisive
        );
    }

    #[test]
    fn seven_is_half_and_independent_grades_can_both_be_tactical() {
        let dd = [HALF, HALF, INTACT, INTACT];
        let mut barges = [AtSea; 13];
        barges[..6].fill(LandedAtHoraniu);
        assert_eq!(assess(&dd, &barges).unwrap().axis, Grade::None);
        barges[6] = LandedAtHoraniu;
        barges[7..11].fill(Sunk);
        assert_eq!(
            assess(&dd, &barges).unwrap(),
            Outcome {
                allies: Grade::Tactical,
                axis: Grade::Tactical
            }
        );
        barges.fill(LandedAtHoraniu);
        assert_eq!(assess(&dd, &barges).unwrap().axis, Grade::Decisive);
        assert_eq!(
            assess(&[Destroyer::Sunk, HALF, INTACT, INTACT], &barges)
                .unwrap()
                .axis,
            Grade::None
        );
        let impossible = Destroyer::Afloat {
            damage_fraction: 1.,
        };
        assert!(assess(&[impossible, HALF, INTACT, INTACT], &barges).is_err());
    }
}
