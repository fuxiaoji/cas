//! Read-only adapter for already-published fictional island geometry.
//!
//! This is not a terrain generator, a save migration, or a landing adjudicator.
//! Height queries reproduce the published zone/ramp surface contract; movement
//! features retain their existing native meaning. Unknown draft, berth width,
//! offshore depth and continuous-height physics are explicitly not approved.
use crate::model::{E, P};
use serde_json::{json, Value};

pub(crate) const VERSION: &str = "cas-geography-snapshot-v1";
const MAX_QUERIES: usize = 4096;

fn number(v: &Value, key: &str, default: f64) -> f64 {
    v[key].as_f64().filter(|n| n.is_finite()).unwrap_or(default)
}
fn point(v: &Value) -> E<P> {
    let finite = |k: &str| {
        v[k].as_f64()
            .filter(|n| n.is_finite() && n.abs() <= 1_000_000.)
    };
    Ok(P {
        x: finite("x").ok_or("地理查询横坐标无效")?,
        y: finite("y").ok_or("地理查询纵坐标无效")?,
    })
}
fn polygon(v: &Value) -> E<Vec<P>> {
    let rows = v
        .as_array()
        .filter(|a| (3..=4096).contains(&a.len()))
        .ok_or("原核地理多边形无效")?;
    rows.iter().map(point).collect()
}
fn inside(poly: &[P], p: P) -> bool {
    // Match native polygon_near's zero-clearance ray-cast convention.
    crate::salvage::polygon_near(poly, p, 0.)
}
fn edge_distance(poly: &[P], p: P) -> f64 {
    poly.iter()
        .zip(poly.iter().cycle().skip(1))
        .take(poly.len())
        .map(|(a, b)| crate::adventure::segment_distance(p, *a, *b))
        .fold(f64::INFINITY, f64::min)
}
fn selected(row: &Value, keys: &[&str]) -> Value {
    let mut out = json!({});
    for key in keys {
        if let Some(v) = row.get(*key) {
            out[*key] = v.clone();
        }
    }
    out
}
fn static_rows(source: &Value, key: &str) -> Value {
    json!(source[key]
        .as_array()
        .into_iter()
        .flatten()
        .map(|r| selected(
            r,
            &[
                "id",
                "kind",
                "type",
                "name",
                "cell",
                "x",
                "y",
                "world_position",
                "width_m",
                "length_m",
                "height_m",
                "elevation_m",
                "footprint",
                "polygon",
                "heading",
                "rotation",
                "rotation_deg",
                "level",
                "seed",
                "entrances",
            ]
        ))
        .collect::<Vec<_>>())
}
fn geometry_hash(v: &Value) -> String {
    // Explicit portable, non-cryptographic cache identity; serde_json's default
    // ordered object map gives stable key order in native and WASM builds.
    let mut h = 0xcbf29ce484222325u64;
    for byte in serde_json::to_vec(v).expect("finite JSON value") {
        h = (h ^ u64::from(byte)).wrapping_mul(0x100000001b3);
    }
    format!("fnv1a64:{h:016x}")
}
fn bounds(poly: &[P]) -> Value {
    let x = poly.iter().map(|p| p.x).fold(f64::INFINITY, f64::min);
    let y = poly.iter().map(|p| p.y).fold(f64::INFINITY, f64::min);
    let r = poly.iter().map(|p| p.x).fold(f64::NEG_INFINITY, f64::max);
    let b = poly.iter().map(|p| p.y).fold(f64::NEG_INFINITY, f64::max);
    json!({"x":x,"y":y,"width":r-x,"height":b-y})
}

struct Source {
    land: Value,
    source_version: String,
    source_kind: &'static str,
    default_island_id: String,
    beaches: Value,
}
fn source(observation: &Value, request: &Value) -> E<Source> {
    if observation["littoral"]["land"].is_object() {
        let version = observation["island_war"]["version"]
            .as_str()
            .or_else(|| observation["littoral"]["version"].as_str())
            .unwrap_or("");
        if !["cas-island-war-v4", "cas-littoral-v4"].contains(&version) {
            return Err("共享地理只读适配暂不接管旧版或历史战役".into());
        }
        let npc = observation["island_war"]["npc_id"]
            .as_str()
            .filter(|s| !s.trim().is_empty())
            .unwrap_or("home");
        return Ok(Source {
            land: observation["littoral"]["land"].clone(),
            source_version: version.into(),
            source_kind: "published_fictional_island",
            default_island_id: npc.into(),
            beaches: observation["littoral"]["beaches"]
                .as_array()
                .map_or(json!([]), |v| json!(v)),
        });
    }
    let tasks = observation["salvage"]["amphibious"]["tasks"]
        .as_array()
        .ok_or("当前观察没有可导出的原创岛屿地理")?;
    let candidates: Vec<_> = tasks
        .iter()
        .filter(|t| {
            request
                .get("task_id")
                .is_none_or(|id| t.get("id") == Some(id))
                && request
                    .get("island_index")
                    .is_none_or(|id| t.get("island") == Some(id))
        })
        .collect();
    if candidates.len() != 1 {
        return Err("多岛航次请指定唯一的island_index或task_id，不能默认套用第一座岛".into());
    }
    let task = candidates[0];
    let poly = polygon(&task["polygon"])?;
    let land = json!({"bounds":bounds(&poly),"polygon":task["polygon"],"terrain":task["terrain"],"buildings":[],"ruins":[]});
    Ok(Source {
        land,
        source_version: crate::amphibious_expedition::LAND_VERSION.into(),
        source_kind: "published_fictional_expedition",
        default_island_id: format!("expedition-island-{}", task["island"]),
        beaches: json!([{"id":format!("task-{}",task["id"]),"sea":task["shore"],"land":task["beach"],"task_id":task["id"]}]),
    })
}

/// Sample exactly the existing zone/ramp display contract, without adding noise,
/// inferring new coast elevations, or changing native feature collision.
fn height(terrain: &Value, p: P) -> E<f64> {
    let model = terrain["height_model"].as_str().unwrap_or("");
    if !["inset_edge_blend_v1", "island-ramp-v1"].contains(&model) {
        return Err("未支持的公开高程合同".into());
    }
    let mut h = 0f64;
    let mut level = i64::MIN;
    let mut levels = std::collections::BTreeMap::from([(0, 0.)]);
    for zone in terrain["elevation_zones"].as_array().into_iter().flatten() {
        let zlevel = zone["level"].as_i64().unwrap_or(0);
        let zh = number(zone, "height_m", 0.);
        levels.insert(zlevel, zh);
        let poly = polygon(&zone["polygon"])?;
        if !inside(&poly, p) {
            continue;
        }
        if model == "inset_edge_blend_v1" {
            h = h.max(
                zh * (edge_distance(&poly, p) / number(zone, "blend_width_m", 120.).max(0.001))
                    .clamp(0., 1.),
            );
        } else if zlevel >= level {
            h = zh;
            level = zlevel;
        }
    }
    if model == "inset_edge_blend_v1" {
        return Ok(h);
    }
    for ramp in terrain["ramps"].as_array().into_iter().flatten() {
        // v4 polygon-only ramp features remain polygon features, not invented
        // line ramps. Both existing Godot consumers skip ramps without points.
        let Some(rows) = ramp["points"].as_array().filter(|a| a.len() >= 2) else {
            continue;
        };
        let path: Vec<P> = rows.iter().map(point).collect::<E<_>>()?;
        let total: f64 = path.windows(2).map(|s| s[0].dist(s[1])).sum();
        let mut along = 0.;
        for pair in path.windows(2) {
            let (a, b) = (pair[0], pair[1]);
            let delta = b - a;
            let l2 = delta.x * delta.x + delta.y * delta.y;
            let f = ((p.x - a.x) * delta.x + (p.y - a.y) * delta.y) / l2.max(0.001);
            if (0. ..=1.).contains(&f) && p.dist(a + delta * f) <= number(ramp, "width", 0.) * 0.5 {
                let lo = levels
                    .get(&ramp["from_level"].as_i64().unwrap_or(0))
                    .copied()
                    .unwrap_or(0.);
                let hi = levels
                    .get(&ramp["to_level"].as_i64().unwrap_or(0))
                    .copied()
                    .unwrap_or(0.);
                return Ok(lo + (hi - lo) * (along + a.dist(b) * f) / total.max(0.001));
            }
            along += a.dist(b);
        }
    }
    Ok(h)
}
fn query(land: &Value, p: P) -> E<Value> {
    let poly = polygon(&land["polygon"])?;
    let on_land = inside(&poly, p);
    let terrain = &land["terrain"];
    let sampled = height(terrain, p)?;
    let mut kinds = vec![];
    let mut movement = json!({"infantry":1.,"armor":1.,"amphibious":1.,"air":1.});
    let matching: Vec<_> = terrain["features"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|r| polygon(&r["polygon"]).is_ok_and(|poly| inside(&poly, p)))
        .collect();
    let ford = matching
        .iter()
        .any(|r| matches!(r["kind"].as_str(), Some("ford" | "road")));
    for r in matching {
        if let Some(kind) = r["kind"].as_str() {
            kinds.push(kind);
        }
        if ford && r["kind"] == "river" {
            continue;
        }
        for class in ["infantry", "armor", "amphibious", "air"] {
            let old = movement[class].as_f64().unwrap();
            movement[class] = json!(old.min(number(&r["movement"], class, 1.)));
        }
    }
    let biome = if !on_land {
        "sea"
    } else {
        [
            "cliff",
            "road",
            "ford",
            "river",
            "swamp",
            "beach",
            "landing_zone",
            "forest",
            "bush",
            "highland",
            "ramp",
            "lowland",
        ]
        .into_iter()
        .find(|k| kinds.contains(k))
        .unwrap_or("plain")
    };
    let continuous = terrain["height_model"] == "inset_edge_blend_v1";
    let slope = if continuous {
        let dx = (height(terrain, p + P { x: 1., y: 0. })?
            - height(terrain, p + P { x: -1., y: 0. })?)
            * 0.5;
        let dy = (height(terrain, p + P { x: 0., y: 1. })?
            - height(terrain, p + P { x: 0., y: -1. })?)
            * 0.5;
        json!({"supported":true,"rise_per_m":libm::sqrt(dx*dx+dy*dy),"sampling":"central_difference_1m","purpose":"published_surface_only"})
    } else {
        json!({"supported":false,"rise_per_m":null,"reason":"原版分区/坡道合同并非连续高程物理，不能据差分判定坡度通行"})
    };
    Ok(
        json!({"point":p,"on_land":on_land,"height":{"supported":true,"metres":sampled,"purpose":"published_surface_only"},"slope":slope,"biome":{"supported":!terrain["features"].is_null(),"kind":biome,"features":kinds},"movement":{"supported":on_land&&terrain["features"].is_array(),"multipliers":if on_land&&terrain["features"].is_array(){movement}else{Value::Null},"includes_dynamic_obstacles":false},"water_depth_m":null,"landing":{"supported":false,"valid":null,"reason":"请使用原版本littoral_preview；连续岸宽/吃水/水路/卸载空间与拥堵尚无统一新合同"}}),
    )
}

/// Only static source fields participate in the geometry hash. Damage, clock,
/// searched flags and actors are intentionally excluded from render-cache keys.
pub(crate) fn snapshot(observation: &Value, request: &Value) -> E<Value> {
    let src = source(observation, request)?;
    let poly = polygon(&src.land["polygon"])?;
    let mut land = selected(&src.land, &["bounds", "polygon", "terrain", "obstacles"]);
    if land["bounds"].is_null() {
        land["bounds"] = bounds(&poly);
    }
    for key in ["buildings", "ruins", "mines"] {
        land[key] = static_rows(&src.land, key);
    }
    // Coordinates and source declarations, not account IDs, are the stable
    // geometric cache identity. Same home/exercise geometry hashes identically.
    let hash = geometry_hash(&land);
    let island_id = request["island_id"]
        .as_str()
        .filter(|s| !s.is_empty() && s.len() <= 128)
        .unwrap_or(&src.default_island_id);
    let map_id = request["map_id"]
        .as_str()
        .filter(|s| !s.is_empty() && s.len() <= 128)
        .map(str::to_owned)
        .unwrap_or_else(|| format!("{island_id}:{hash}"));
    let rows = match request.get("points") {
        None => &[][..],
        Some(v) => v
            .as_array()
            .filter(|v| v.len() <= MAX_QUERIES)
            .map(Vec::as_slice)
            .ok_or("地理查询点上限4096")?,
    };
    let queries = rows
        .iter()
        .map(|p| query(&land, point(p)?))
        .collect::<E<Vec<_>>>()?;
    let buildings: Vec<_> = land["buildings"]
        .as_array()
        .unwrap()
        .iter()
        .map(|b| {
            let mut row = b.clone();
            row["island_id"] = json!(island_id);
            row
        })
        .collect();
    let shore: Vec<_> = poly.iter().zip(poly.iter().cycle().skip(1)).take(poly.len()).enumerate().map(|(i, (a, b))| json!({"id":format!("{island_id}:shore:{i}"),"a":a,"b":b,"kind":"unclassified","landing_valid":null,"authority":"outline_only"})).collect();
    let model = land["terrain"]["height_model"].as_str().unwrap_or("");
    let supported_height = ["island-ramp-v1", "inset_edge_blend_v1"].contains(&model);
    Ok(json!({
        "version":VERSION,
        "header":{"geometry_hash":hash,"hash_algorithm":"fnv1a64_canonical_json","map_id":map_id,"island_id":island_id,"geometry_version":land["terrain"].get("version").cloned().unwrap_or_else(||json!(model)),"source_version":src.source_version,"source_kind":src.source_kind,"authority_scope":"readonly_published_geometry","units":"metres","axis_convention":"core_x_east_y_north_to_godot_x_height_y","origin_m":{"x":0.,"y":0.},"bounds_m":land["bounds"],"sea_level_m":0.},
        "land":land,"buildings":buildings,"shore_segments":shore,"registered_beaches":src.beaches,
        "height_surface":{"supported":supported_height,"sampler":model,"purpose":"published_surface_contract","collision":"source_native_features_unchanged","adds_noise":false,"continuous_height_physics":false},
        "queries":queries,
        "blockers":["统一连续高程物理未发布；现有移动/LOS与旧高程合同保持原样","岸段分类/连续有效滩宽/吃水/近岸水路/下船空间/拥堵不得由本快照批准","历史战役、旧版航次与账户地理不迁移；模型LOD只改变表现"]
    }))
}

/// Read-only home input uses the same native v4 preview as home construction.
pub(crate) fn home_snapshot(request: &Value) -> E<Value> {
    let observation = crate::island_war::v4_base::home_preview(request)?;
    snapshot(&observation, request)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn home(level: u32, seed: u32) -> Value {
        crate::island_war::v4_base::home_preview(&json!({"hq_level":level,"seed":seed,"buildings":[{"id":"hq","kind":"hq","cell":{"x":6,"y":4},"hp":100,"max_hp":100}]})).unwrap()
    }
    #[test]
    fn original_home_contract_is_retained_at_all_levels_and_seeds() {
        for level in 1..=5 {
            for seed in [1, 714, 18031] {
                let observation = home(level, seed);
                let before = observation.clone();
                let export = snapshot(&observation, &json!({})).unwrap();
                assert_eq!(observation, before);
                assert_eq!(
                    export["land"]["polygon"],
                    observation["littoral"]["land"]["polygon"]
                );
                assert_eq!(
                    export["land"]["terrain"],
                    observation["littoral"]["land"]["terrain"]
                );
                assert_eq!(
                    export["land"]["bounds"]["width"].as_f64().unwrap(),
                    (3600 + 1200 * (level - 1)) as f64
                );
                assert_eq!(
                    export["land"]["bounds"]["height"].as_f64().unwrap(),
                    (4800 + 1400 * (level - 1)) as f64
                );
                assert_eq!(export["height_surface"]["adds_noise"], false);
            }
        }
    }
    #[test]
    fn damage_and_clock_do_not_dirty_static_cache_but_placement_does() {
        let mut v = home(5, 714);
        v["island_war"]["npc_id"] = json!("");
        let a = snapshot(&v, &json!({})).unwrap();
        assert_eq!(a["header"]["island_id"], "home");
        assert!(a["shore_segments"][0]["id"]
            .as_str()
            .unwrap()
            .starts_with("home:shore:"));
        v["tick"] = json!(200);
        v["littoral"]["land"]["buildings"][0]["hp"] = json!(1);
        v["littoral"]["land"]["entities"] = json!([{"id":1,"x":123,"hp":2}]);
        let b = snapshot(&v, &json!({})).unwrap();
        assert_eq!(a["header"]["geometry_hash"], b["header"]["geometry_hash"]);
        v["littoral"]["land"]["buildings"][0]["x"] = json!(15001);
        let c = snapshot(&v, &json!({})).unwrap();
        assert_ne!(a["header"]["geometry_hash"], c["header"]["geometry_hash"]);
        assert!(b["land"]["buildings"][0].get("hp").is_none());
    }
    #[test]
    fn exact_inset_sampling_and_unsupported_landing_are_explicit() {
        let v = json!({"littoral":{"version":"cas-littoral-v4","land":{"polygon":[{"x":0,"y":0},{"x":1000,"y":0},{"x":1000,"y":1000},{"x":0,"y":1000}],"terrain":{"height_model":"inset_edge_blend_v1","elevation_zones":[{"polygon":[{"x":0,"y":0},{"x":1000,"y":0},{"x":1000,"y":1000},{"x":0,"y":1000}],"height_m":80,"level":2,"blend_width_m":100}],"features":[]}}}});
        let export = snapshot(&v, &json!({"points":[{"x":50,"y":500},{"x":500,"y":500}]})).unwrap();
        assert_eq!(export["queries"][0]["height"]["metres"], 40.);
        assert_eq!(export["queries"][1]["height"]["metres"], 80.);
        assert!(
            (export["queries"][0]["slope"]["rise_per_m"]
                .as_f64()
                .unwrap()
                - 0.8)
                .abs()
                < 1e-12
        );
        assert_eq!(export["queries"][0]["landing"]["valid"], Value::Null);
        assert_eq!(export["queries"][0]["landing"]["supported"], false);
    }
    #[test]
    fn expedition_requires_explicit_island_instead_of_reusing_first_terrain() {
        let task = |id| json!({"id":id,"island":id,"polygon":[{"x":0,"y":0},{"x":10,"y":0},{"x":0,"y":10}],"terrain":{"height_model":"inset_edge_blend_v1","elevation_zones":[]}});
        let v = json!({"salvage":{"amphibious":{"tasks":[task(1),task(2)]}}});
        assert!(snapshot(&v, &json!({})).is_err());
        let a = snapshot(&v, &json!({"island_index":2})).unwrap();
        assert_eq!(a["registered_beaches"][0]["task_id"], 2);
        assert_eq!(a["header"]["island_id"], "expedition-island-2");
    }
    #[test]
    fn old_and_historical_views_are_not_claimed_or_migrated() {
        assert!(snapshot(
            &json!({"littoral":{"version":"cas-littoral-v3","land":{}}}),
            &json!({})
        )
        .is_err());
        assert!(snapshot(&json!({"version":"cas-battle-v2","islands":[]}), &json!({})).is_err());
        assert!(snapshot(&home(1, 1), &json!({"points":[{"x":"nan","y":1}]})).is_err());
    }
    #[test]
    fn registered_line_ramps_have_no_raised_end_caps() {
        let terrain = json!({"height_model":"island-ramp-v1","elevation_zones":[{"polygon":[{"x":500,"y":500},{"x":600,"y":500},{"x":600,"y":600},{"x":500,"y":600}],"height_m":100,"level":1}],"ramps":[{"points":[{"x":0,"y":0},{"x":100,"y":0}],"width":20,"from_level":0,"to_level":1}]});
        assert_eq!(height(&terrain, P { x: 50., y: 0. }).unwrap(), 50.);
        assert_eq!(height(&terrain, P { x: -1., y: 0. }).unwrap(), 0.);
        assert_eq!(height(&terrain, P { x: 101., y: 0. }).unwrap(), 0.);
        assert_eq!(height(&terrain, P { x: 50., y: 11. }).unwrap(), 0.);
    }
    #[test]
    fn original_river_crossing_feature_overrides_water_blocking_without_changing_surface() {
        let v = home(5, 714);
        let export = snapshot(
            &v,
            &json!({"points":[{"x":15100,"y":13000},{"x":15100,"y":13100}]}),
        )
        .unwrap();
        let crossing = &export["queries"][0];
        let water = &export["queries"][1];
        assert!(crossing["biome"]["features"]
            .as_array()
            .unwrap()
            .contains(&json!("river")));
        assert!(
            crossing["movement"]["multipliers"]["armor"]
                .as_f64()
                .unwrap()
                > 0.
        );
        assert_eq!(water["movement"]["multipliers"]["armor"], 0.);
        assert_eq!(crossing["slope"]["supported"], false);
    }
    #[test]
    fn new_read_only_operation_does_not_replace_live_world_or_modify_save() {
        // World construction already needs more than the Windows libtest
        // worker's small debug stack. Keep this test self-contained instead of
        // changing the runtime or relying on a global RUST_MIN_STACK setting.
        std::thread::Builder::new().stack_size(16 * 1024 * 1024).spawn(|| {
        let mut e = crate::Engine::default();
        assert_eq!(
            e.handle(json!({"op":"new","seed":6106,"side":"allies","enemy":"coord"}))["ok"],
            true
        );
        let before = e.handle(json!({"op":"save"}));
        let home = e.handle(json!({"op":"geography_snapshot","home":true,"hq_level":5,"seed":714,"buildings":[],"points":[{"x":14600,"y":13000}]}));
        assert_eq!(home["ok"], true, "{home}");
        assert_eq!(home["data"]["version"], VERSION);
        assert_eq!(e.handle(json!({"op":"save"})), before);
        assert_eq!(e.handle(json!({"op":"geography_snapshot"}))["ok"], false);
        assert_eq!(e.handle(json!({"op":"save"})), before);
        }).unwrap().join().unwrap();
    }
}
