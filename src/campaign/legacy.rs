//! Import boundary for the five IBS campaigns with no matching CAS scenario.
use serde::Deserialize;
use serde_json::Value;

const CASES: [(&str, &str, &str); 5] = [
    (
        "IBS-S-03",
        "cas-ibs-channel-action",
        include_str!("../../data/campaign/legacy/channel-action.json"),
    ),
    (
        "IBS-S-07",
        "cas-ibs-solomons-1928",
        include_str!("../../data/campaign/legacy/solomons-1928.json"),
    ),
    (
        "IBS-S-12",
        "cas-ibs-bougainville-1928",
        include_str!("../../data/campaign/legacy/bougainville-1928.json"),
    ),
    (
        "IBS-S-EM-01",
        "cas-ibs-philippine-sea-surface",
        include_str!("../../data/campaign/legacy/philippine-sea-surface.json"),
    ),
    (
        "IBS-S-FM-01",
        "cas-ibs-midnight-fleet",
        include_str!("../../data/campaign/legacy/midnight-fleet.json"),
    ),
];

pub(super) fn source(ibs_id: &str) -> Option<&'static str> {
    CASES.iter().find(|row| row.0 == ibs_id).map(|row| row.2)
}

pub(super) fn alias(ibs_id: &str, id: &str) -> bool {
    CASES.iter().any(|row| row.0 == ibs_id && row.1 == id)
}

#[derive(Debug, Deserialize)]
pub struct Deployment {
    pub schema: String,
    pub scenario_id: String,
    pub ibs_id: String,
    pub stage_ids: Vec<String>,
    pub playable: bool,
    pub map: MapGeometry,
    pub start: Start,
    pub ships: Vec<Ship>,
    pub formations: Vec<Formation>,
    pub post_default_formation_setup: Option<ResolvedSetup>,
    pub objectives: Objectives,
    pub conflicts: Vec<Value>,
    pub gates: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct MapGeometry {
    pub width_m: f64,
    pub height_m: f64,
    pub land_polygons_m: Vec<Vec<[f64; 2]>>,
    pub coast_polygons_m: Vec<Vec<[f64; 2]>>,
}

#[derive(Debug, Deserialize)]
pub struct Start {
    pub light_hint: Option<String>,
    pub legacy_turn_limit: u32,
    pub duration_candidate_seconds: u32,
    pub deploy_mode: String,
    pub setup_zones: Vec<DeploymentZone>,
}

#[derive(Debug, Deserialize)]
pub struct DeploymentZone {
    pub side: String,
    pub from_m: [f64; 2],
    pub to_m: [f64; 2],
    pub half_plane: String,
    pub include_boundary: bool,
}

#[derive(Debug, Deserialize)]
pub struct Ship {
    pub name: String,
    pub side: String,
    pub flagship: bool,
    pub formation_id: Option<String>,
    pub cas_profile_id: Option<String>,
    #[serde(flatten)]
    pub placement: Placement,
}

#[derive(Debug, Deserialize)]
pub struct Placement {
    pub ibs_ship_id: String,
    pub initial_hex: String,
    pub x_m: f64,
    pub y_m: f64,
    pub heading_deg: u16,
    pub speed_knots: f64,
}

#[derive(Debug, Deserialize)]
pub struct Formation {
    pub id: String,
    pub side: String,
    pub ship_ids: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct ResolvedSetup {
    pub phase: String,
    pub formations: Vec<Formation>,
    pub ships: Vec<Placement>,
    pub conflicts: Vec<Value>,
}

#[derive(Debug, Deserialize)]
pub struct Objectives {
    pub status: String,
    pub intent: Vec<String>,
}
