//! Point-buy fleets for the basic campaign difficulty.
//!
//! The historical force fixes the number of player hulls and their initial
//! slots. On the basic difficulty the player may replace each hull with any
//! same-side card whose point total fits the historical force's point budget;
//! the slot (position, heading, fleet, leader) stays one-to-one. Standard and
//! challenge always run the printed fleet.
use super::live::{self, GroupPick};
use crate::model::{Ai, Data, Fleet, P, Tactic};
use crate::{ranked_fleets, world::World, E};
use serde_json::{json, Value};
use std::collections::BTreeSet;

/// Append the 202 registered single-ship cards to a scenario card set. The
/// scenario's own printed card wins on an id collision; nothing is rewritten.
/// This is what lets the story picker offer every registered identity without
/// changing `data/ships` or a scenario's printed roster.
pub(crate) fn add_registered_cards(data: &mut Data) -> E<()> {
    let registry = ranked_fleets::data()?;
    for ship in &registry.ships {
        if !data.ships.iter().any(|known| known.id == ship.id) {
            data.ships.push(ship.clone());
        }
    }
    Ok(())
}

/// Resolve one pick to a loaded card and the single-ship identity it stands
/// for. Picks are tried in this order:
/// 1. an exact class/scenario card id (old drafts and historical class picks);
/// 2. the scenario's own period card for an `IBS-U-*` identity (keeps the
///    printed runtime hull and writes the identity onto the ship);
/// 3. the registered single-ship card itself (the 202-card pool);
/// 4. the legacy `class_for` mapping (a registered identity whose class card
///    is the only loaded hull).
fn resolve_pick(w: &World, pick: &str) -> E<(usize, Option<String>)> {
    if !pick.starts_with("IBS-U-") {
        if let Some(def) = w.data.ships.iter().position(|ship| ship.id == pick) {
            return Ok((def, pick_identity(w, def, pick)));
        }
    }
    if pick.starts_with("IBS-U-") {
        if let Some(def) = w
            .data
            .ships
            .iter()
            .position(|ship| !ship.id.starts_with("IBS-U-") && live::character_id(&ship.id) == Some(pick))
        {
            return Ok((def, Some(pick.to_string())));
        }
        if let Some(def) = w.data.ships.iter().position(|ship| ship.id == pick) {
            return Ok((def, Some(pick.to_string())));
        }
    }
    let class = ranked_fleets::class_for(pick);
    if class != pick {
        if let Some(def) = w.data.ships.iter().position(|ship| ship.id == class) {
            return Ok((def, pick_identity(w, def, pick)));
        }
    }
    Err(format!("缺少已核验舰卡 {pick}"))
}

/// The identity written to a hull for a pick. `IBS-U-*` picks are catalogue
/// identities; class picks resolve through the scenario's pinned mapping.
fn pick_identity(w: &World, def: usize, pick: &str) -> Option<String> {
    let card = &w.data.ships[def];
    if pick.starts_with("IBS-U-") {
        Some(pick.to_string())
    } else if card.id.starts_with("IBS-U-") {
        Some(card.id.clone())
    } else {
        live::character_id(&card.id).map(str::to_string)
    }
}

fn name_for(
    w: &World,
    def: usize,
    identity: Option<&str>,
    old_name: Option<&str>,
    old_class: Option<&str>,
    old_character: Option<&str>,
) -> String {
    // Re-picking the hull already in the slot keeps its printed historical
    // name even when the draft stores the identity. A genuinely different
    // single-ship pick takes that identity's own display name.
    if identity.is_some() && identity == old_character {
        if let Some(name) = old_name {
            return name.to_string();
        }
    }
    if let Some(name) = identity.and_then(ranked_fleets::display_name) {
        return name.to_string();
    }
    let card = &w.data.ships[def];
    match old_class {
        Some(class) if class == card.id => old_name.unwrap_or(card.name.as_str()).to_string(),
        _ => card.name.clone(),
    }
}

/// The historical anchor of one printed player group. Custom task-force groups
/// are always placed on one of these anchors; no new coordinate is invented.
pub(crate) struct GroupAnchor {
    pub fleet: u32,
    pub name: String,
    pub p: P,
    pub h: f64,
    pub speed: f64,
    pub spacing: f64,
}

/// Per-group point total for the printed player force, used before the custom
/// spawn so the historical budget is available even though the printed hulls
/// are not spawned in the task-force path.
pub(crate) fn historical_budget<'a>(w: &World, classes: impl IntoIterator<Item = &'a str>) -> u32 {
    classes
        .into_iter()
        .filter_map(|class| w.data.ships.iter().find(|ship| ship.id == class))
        .map(ranked_fleets::ship_points)
        .sum()
}

/// The point value of the historical player force. `fleet` entries are the
/// class IDs in spawn order, so the lobby can display the same order.
pub(crate) fn historical(w: &World) -> (u32, Vec<Value>) {
    let mut total = 0;
    let mut rows = Vec::new();
    for ship in w.ships.iter().filter(|ship| ship.side == w.player) {
        let def = &w.data.ships[ship.def];
        let points = ranked_fleets::ship_points(def);
        total += points;
        // One row per printed hull, in spawn order. `identity` is the
        // single-ship pick when one is pinned; unresolved named hulls keep
        // their own name and fall back to the class card instead of merging.
        let identity = ship
            .character
            .clone()
            .or_else(|| live::character_id(&def.id).map(str::to_string));
        rows.push(json!({"class":def.id,"name":ship.name,"kind":def.kind,"points":points,
                         "identity":identity,"slot":rows.len()}));
    }
    (total, rows)
}

pub(crate) fn options(w: &World) -> Value {
    let (budget, historical) = historical(w);
    // Only cards present in this scenario's runtime data are selectable; the
    // historical classes themselves are always offered by the picker.
    let available = |class: &str| w.data.ships.iter().any(|ship| ship.id == class);
    let options = ranked_fleets::options(w.player).unwrap_or_else(|_| json!([]));
    let filtered = options.as_array().map(|rows| {
        rows.iter().filter(|row| row["class"].as_str().is_some_and(available)
            || row["id"].as_str().is_some_and(available)).cloned().collect::<Vec<_>>()
    }).unwrap_or_default();
    json!({
        "budget": budget,
        "historical": historical,
        "options": filtered,
        "positions": positions(w),
        "taskForceSupported": w.campaign.as_ref().is_some_and(|start| start.supports_groups()),
    })
}

/// The player's printed group anchors, in printed order. The UI uses the
/// `position` index, not the fleet id, so the mission cannot invent a slot.
pub(crate) fn positions(w: &World) -> Value {
    let rows: Vec<Value> = w
        .fleets
        .iter()
        .filter(|fleet| fleet.side == w.player)
        .enumerate()
        .map(|(index, fleet)| {
            let leader = w.ship(fleet.leader);
            json!({
                "position": index,
                "fleet": fleet.id,
                "name": fleet.name,
                "leader": leader.map(|ship| ship.name.clone()),
                "course": leader.map(|ship| ship.h),
                "speed": fleet.speed,
                "x": leader.map(|ship| ship.p.x),
                "y": leader.map(|ship| ship.p.y),
                "members": fleet.members.len(),
            })
        })
        .collect();
    json!(rows)
}

/// Replace the printed player groups with up to N custom groups, each placed on
/// one historical anchor. Empty positions are allowed; the enemy order is not
/// touched. This runs during scenario fill, before radar/realtime initialization.
pub(crate) fn spawn_groups(
    w: &mut World,
    anchors: &[GroupAnchor],
    groups: &[GroupPick],
    budget: u32,
) -> E<()> {
    if groups.is_empty() {
        return Err("特混编成至少要派出一个编队".into());
    }
    let seat = if w.player == 0 { ["allies", "blue"] } else { ["axis", "red"] };
    let mut seen = BTreeSet::new();
    let mut total = 0;
    let mut plan: Vec<(usize, Vec<(usize, Option<String>)>)> = Vec::with_capacity(groups.len());
    for group in groups {
        if group.position >= anchors.len() {
            return Err("初设位置不存在".into());
        }
        if !seen.insert(group.position) {
            return Err("同一初设位置只能放一个编队".into());
        }
        if group.ships.is_empty() {
            return Err("编队不能为空".into());
        }
        let mut defs = Vec::with_capacity(group.ships.len());
        for pick in &group.ships {
            let (def, identity) = resolve_pick(w, pick)?;
            if !seat.contains(&w.data.ships[def].side.as_str()) {
                return Err(format!("{} 不属于本席阵营", w.data.ships[def].name));
            }
            total += ranked_fleets::ship_points(&w.data.ships[def]);
            defs.push((def, identity));
        }
        plan.push((group.position, defs));
    }
    if total > budget {
        return Err(format!("特混编队点价 {total} 超过历史兵力 {budget} 分"));
    }
    let player = w.player;
    let profile = w.profile.clone();
    for (position, defs) in plan {
        let anchor = &anchors[position];
        let mut members = Vec::with_capacity(defs.len());
        for (index, (def, identity)) in defs.into_iter().enumerate() {
            let astern = P::bearing(anchor.h) * (-(anchor.spacing * index as f64));
            let name = name_for(w, def, identity.as_deref(), None, None, None);
            let id = w.spawn(def, player, anchor.fleet, name, anchor.p + astern, anchor.h)?;
            let ship = w.ship_mut(id).expect("fresh custom hull");
            ship.character = identity;
            ship.speed = anchor.speed;
            ship.free_speed = anchor.speed;
            members.push(id);
        }
        w.fleets.push(Fleet {
            id: anchor.fleet,
            side: player,
            name: format!("{} · 特混", anchor.name),
            leader: members[0],
            members,
            mode: "follow".into(),
            speed: anchor.speed,
            actual: anchor.speed,
            turn_degrees: 0.,
            points: vec![],
            ai: Ai::new(profile.as_str(), "manual"),
            notice: None,
            last_ai_route: 0,
            tactic: Tactic::Search,
        });
    }
    Ok(())
}

/// Replace the player's hulls in place. Picks are catalog identities or
/// historical class IDs; `class_for` maps the former to the loaded card.
pub(crate) fn apply(w: &mut World, picks: &[String]) -> E<()> {
    let ids: Vec<u32> = w
        .ships
        .iter()
        .filter(|ship| ship.side == w.player)
        .map(|ship| ship.id)
        .collect();
    if picks.len() != ids.len() {
        return Err(format!(
            "基础难度编队需要与历史兵力同为 {} 艘（收到 {} 艘）",
            ids.len(),
            picks.len()
        ));
    }
    let (budget, _) = historical(w);
    let mut defs = Vec::with_capacity(picks.len());
    let mut total = 0;
    for pick in picks {
        let (def, identity) = resolve_pick(w, pick)?;
        let seat = if w.player == 0 { ["allies", "blue"] } else { ["axis", "red"] };
        if !seat.contains(&w.data.ships[def].side.as_str()) {
            return Err(format!("{} 不属于本席阵营", w.data.ships[def].name));
        }
        total += ranked_fleets::ship_points(&w.data.ships[def]);
        defs.push((def, identity));
    }
    if total > budget {
        return Err(format!("编队点价 {total} 超过历史兵力 {budget} 分"));
    }
    for (id, (def, identity)) in ids.iter().zip(defs) {
        let index = (*id - 1) as usize;
        let (p, h, speed, fleet, old_name, old_class, old_character) = {
            let old = &w.ships[index];
            (old.p, old.h, old.speed, old.fleet.unwrap_or(0), old.name.clone(),
             w.data.ships[old.def].id.clone(), old.character.clone())
        };
        // The identity is a single-ship key: the name follows that hull even
        // when the loaded card is the same class, and the battle view reads
        // `Ship.character` before the class fallback.
        let name = name_for(w, def, identity.as_deref(), Some(&old_name), Some(&old_class), old_character.as_deref());
        // Build a fresh hull from the chosen card, then copy it over the old
        // slot. This resets mounts, torpedo tubes, damage and fire state while
        // preserving the printed slot, fleet and speed.
        let _fresh_id = w.spawn(def, w.player, fleet, name, p, h)?;
        let mut fresh = w.ships.pop().expect("fresh hull");
        fresh.character = identity;
        let old = &mut w.ships[index];
        *old = crate::model::Ship { id: *id, p, h, speed, free_speed: speed, fleet: Some(fleet), ..fresh };
        w.gun_streak.truncate(w.ships.len());
        w.surface_damage.truncate(w.ships.len());
    }
    // The historical fleet records still point at the same ship IDs; refresh
    // the leader's speed and drop any completion track that belonged to a
    // replaced hull.
    // The replacement hulls need their gun-mount turret states rebuilt for the
    // campaign real-time timings; this runs at tick 0, before any order.
    w.enable_realtime()?;
    for fleet in w.fleets.iter_mut().filter(|fleet| fleet.side == w.player) {
        if let Some(leader) = w.ships.iter().find(|ship| ship.id == fleet.leader) {
            fleet.speed = leader.speed;
        }
        fleet.points.clear();
        fleet.last_ai_route = 0;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::campaign::live::{GroupPick, Start};

    #[test]
    fn basic_difficulty_replaces_each_printed_slot_in_order() {
        let mut start = Start::new("CAMP-ALLIES-02", "story");
        start.fleet = Some(vec!["IBS-U-USN-FLETCHER".into(); 9]);
        let world = World::new_campaign(6106, start, "coord").unwrap();
        assert_eq!(world.ships.iter().filter(|ship| ship.side == 0).count(), 9);
        assert!(world.ships.iter().filter(|ship| ship.side == 0)
            .all(|ship| ["fletcher", "IBS-U-USN-FLETCHER"].contains(&world.data.ships[ship.def].id.as_str())));
        assert_eq!(world.ships.iter().filter(|ship| ship.side == 1).count(), 5);
        assert_eq!(world.fleets.iter().filter(|fleet| fleet.side == 0).count(), 1);
    }

    #[test]
    fn basic_difficulty_rejects_a_wrong_count_or_over_budget_fleet() {
        let mut start = Start::new("CAMP-ALLIES-02", "story");
        start.fleet = Some(vec!["IBS-U-USN-FLETCHER".into(); 8]);
        assert!(World::new_campaign(6106, start, "coord").is_err());
        let mut start = Start::new("CAMP-ALLIES-02", "story");
        start.fleet = Some(vec!["IBS-U-USN-UNNAMED-T01-R03".into(); 9]);
        assert!(World::new_campaign(6106, start, "coord").is_err());
    }

    #[test]
    fn task_force_places_one_group_on_the_printed_anchor() {
        let historical = World::new_campaign(6106, Start::new("CAMP-ALLIES-02", "standard"), "coord").unwrap();
        let anchor = historical.ships.iter().find(|ship| ship.side == 0).unwrap().p;
        let mut start = Start::new("CAMP-ALLIES-02", "standard");
        start.groups = Some(vec![GroupPick { position: 0, ships: vec!["fletcher".into()] }]);
        let world = World::new_campaign(6106, start, "coord").unwrap();
        let own: Vec<_> = world.ships.iter().filter(|ship| ship.side == 0).collect();
        assert_eq!(own.len(), 1);
        assert!((own[0].p.x - anchor.x).abs() < 1e-3);
        assert!((own[0].p.y - anchor.y).abs() < 1e-3);
        let fleets: Vec<_> = world.fleets.iter().filter(|fleet| fleet.side == 0).collect();
        assert_eq!(fleets.len(), 1);
        assert_eq!(fleets[0].members.len(), 1);
    }

    #[test]
    fn task_force_accepts_a_single_battleship_and_rejects_an_over_budget_group() {
        let mut start = Start::new("CAMP-ALLIES-02", "standard");
        start.groups = Some(vec![GroupPick {
            position: 0,
            ships: vec!["IBS-U-USN-UNNAMED-T01-R03".into()],
        }]);
        let world = World::new_campaign(6106, start, "coord").unwrap();
        assert_eq!(world.ships.iter().filter(|ship| ship.side == 0).count(), 1);
        assert_eq!(
            world.ships.iter().find(|ship| ship.side == 0).unwrap().name,
            "北卡罗来纳"
        );

        let mut over = Start::new("CAMP-ALLIES-02", "standard");
        over.groups = Some(vec![GroupPick { position: 0, ships: vec!["fletcher".into(); 15] }]);
        assert!(World::new_campaign(6106, over, "coord").is_err());
    }

    #[test]
    fn task_force_allows_empty_positions_and_rejects_duplicates() {
        let mut start = Start::new("CAMP-ALLIES-11", "standard");
        start.groups = Some(vec![
            GroupPick { position: 0, ships: vec!["fletcher".into()] },
            GroupPick { position: 2, ships: vec!["fletcher".into()] },
        ]);
        let world = World::new_campaign(6106, start, "coord").unwrap();
        assert_eq!(world.fleets.iter().filter(|fleet| fleet.side == 0).count(), 2);
        assert_eq!(world.ships.iter().filter(|ship| ship.side == 0).count(), 2);

        let mut duplicate = Start::new("CAMP-ALLIES-11", "standard");
        duplicate.groups = Some(vec![
            GroupPick { position: 0, ships: vec!["fletcher".into()] },
            GroupPick { position: 0, ships: vec!["fletcher".into()] },
        ]);
        assert!(World::new_campaign(6106, duplicate, "coord").is_err());
    }

    #[test]
    fn task_force_is_rejected_outside_the_wired_stages() {
        let mut start = Start::new("CAMP-ALLIES-03", "standard");
        start.groups = Some(vec![GroupPick { position: 0, ships: vec!["fletcher".into()] }]);
        assert!(World::new_campaign(6106, start, "coord").is_err());
    }

    #[test]
    fn fleet_options_expose_printed_positions_and_support_flag() {
        let world = World::new_campaign(6106, Start::new("CAMP-ALLIES-11", "standard"), "coord").unwrap();
        let rows = options(&world);
        assert_eq!(rows["positions"].as_array().unwrap().len(), 3);
        assert_eq!(rows["taskForceSupported"], true);
        let esperance = World::new_campaign(6106, Start::new("CAMP-ALLIES-02", "standard"), "coord").unwrap();
        assert_eq!(options(&esperance)["positions"].as_array().unwrap().len(), 1);
        let st_george = World::new_campaign(6106, Start::new("CAMP-ALLIES-03", "standard"), "coord").unwrap();
        assert_eq!(options(&st_george)["taskForceSupported"], false);
    }

    #[test]
    fn printed_player_forces_keep_their_historical_point_budgets() {
        // These totals are the printed-force anchor used by the story budget.
        // They are not balance targets: do not tune them to make a swap fit.
        for (stage, expected, hulls) in [
            ("CAMP-ALLIES-02", 6850, 9),
            ("CAMP-ALLIES-05", 9300, 11),
            ("CAMP-ALLIES-11", 7500, 12),
        ] {
            let world = World::new_campaign(6106, Start::new(stage, "standard"), "coord").unwrap();
            let (total, rows) = historical(&world);
            assert_eq!(total, expected, "{stage} printed force total");
            assert_eq!(rows.len(), hulls, "{stage} printed hull count");
        }
    }

    #[test]
    fn historical_rows_keep_each_printed_hull_and_identity_separate() {
        let world = World::new_campaign(6106, Start::new("CAMP-ALLIES-02", "standard"), "coord").unwrap();
        let (_, rows) = historical(&world);
        assert_eq!(rows.len(), 9);
        let fletchers: Vec<_> = rows.iter().filter(|row| row["class"] == "fletcher").collect();
        assert_eq!(fletchers.len(), 5, "the five printed Fletchers stay five rows");
        assert_eq!(
            fletchers.iter().map(|row| row["name"].as_str().unwrap()).collect::<Vec<_>>(),
            ["法伦霍尔特", "邓肯", "拉菲", "布坎南", "麦卡拉"]
        );
        assert!(fletchers.iter().all(|row| row["identity"].is_null()),
            "class-only Esperance hulls stay unresolved instead of borrowing an identity");
        let slots: Vec<_> = rows.iter().map(|row| row["slot"].as_u64().unwrap()).collect();
        assert_eq!(slots, (0..9).collect::<Vec<_>>(), "slot ids are stable one-to-one");

        // Cape St George prints period ids that resolve exactly to identities.
        let cape = World::new_campaign(6106, Start::new("CAMP-ALLIES-03", "standard"), "coord").unwrap();
        let (_, rows) = historical(&cape);
        assert_eq!(rows.len(), 5);
        assert!(rows.iter().all(|row| row["identity"].as_str().is_some_and(|id| id.starts_with("IBS-U-"))));

        // Savo's resolved/unresolved split is preserved hull by hull.
        let savo = World::new_campaign(6106, Start::new("CAMP-ALLIES-10", "standard"), "coord").unwrap();
        let (_, rows) = historical(&savo);
        assert_eq!(rows.len(), 49);
        assert_eq!(rows.iter().filter(|row| row["identity"].is_string()).count(), 16);
        assert!(rows.iter().any(|row| row["class"] == "savo_hobart"
            && row["identity"].is_null()
            && row["name"] == "霍巴特"));
    }

    #[test]
    fn apply_resolves_single_ship_identities_and_old_class_drafts() {
        let world = World::new_campaign(6106, Start::new("CAMP-ALLIES-02", "standard"), "coord").unwrap();
        let (_, rows) = historical(&world);
        let mut picks: Vec<String> = rows.iter().map(|row| row["identity"]
            .as_str().map(str::to_string)
            .unwrap_or_else(|| row["class"].as_str().unwrap().to_string())).collect();
        picks[0] = "IBS-U-USN-FLETCHER".into();
        let mut start = Start::new("CAMP-ALLIES-02", "story");
        start.fleet = Some(picks);
        let world = World::new_campaign(6106, start, "coord").unwrap();
        let first = world.ships.iter().find(|ship| ship.side == 0).unwrap();
        assert_eq!(first.name, "弗莱彻");
        assert_eq!(first.character.as_deref(), Some("IBS-U-USN-FLETCHER"));
        assert_eq!(world.data.ships[first.def].id, "IBS-U-USN-FLETCHER");
        // Same-class printed hulls keep their own names around the swap.
        for name in ["邓肯", "拉菲", "布坎南", "麦卡拉"] {
            assert!(world.ships.iter().any(|ship| ship.side == 0 && ship.name == name), "{name} stays separate");
        }

        // An old draft stores class picks. They still resolve, and the exact
        // identity is written onto the ship so the portrait follows the hull.
        let cape = World::new_campaign(6106, Start::new("CAMP-ALLIES-03", "standard"), "coord").unwrap();
        let (_, rows) = historical(&cape);
        let mut start = Start::new("CAMP-ALLIES-03", "story");
        start.fleet = Some(rows.iter().map(|row| row["class"].as_str().unwrap().to_string()).collect());
        let world = World::new_campaign(6106, start, "coord").unwrap();
        let first = world.ships.iter().find(|ship| ship.side == 0).unwrap();
        assert_eq!(first.name, "Charles F. Ausburne");
        assert_eq!(first.character.as_deref(), Some("IBS-U-USN-CF-AUSBURNE"));
        assert_eq!(world.data.ships[first.def].id, "ausburne");
    }

    #[test]
    fn task_force_picks_carry_the_single_ship_identity() {
        let mut start = Start::new("CAMP-ALLIES-02", "standard");
        start.groups = Some(vec![GroupPick {
            position: 0,
            ships: vec!["IBS-U-USN-FLETCHER".into()],
        }]);
        let world = World::new_campaign(6106, start, "coord").unwrap();
        let own: Vec<_> = world.ships.iter().filter(|ship| ship.side == 0).collect();
        assert_eq!(own.len(), 1);
        assert_eq!(own[0].name, "弗莱彻");
        assert_eq!(own[0].character.as_deref(), Some("IBS-U-USN-FLETCHER"));
    }

    #[test]
    fn default_identity_picks_fit_every_seat_and_initialize_realtime() {
        for stage in [
            "CAMP-ALLIES-02", "CAMP-AXIS-02",
            "CAMP-ALLIES-03", "CAMP-AXIS-03",
            "CAMP-ALLIES-04", "CAMP-AXIS-04",
            "CAMP-ALLIES-05", "CAMP-AXIS-05",
            "CAMP-ALLIES-10", "CAMP-AXIS-10",
            "CAMP-ALLIES-11", "CAMP-AXIS-11",
        ] {
            // The client's default draft is identity, falling back to the
            // printed class card. The kernel must accept that draft on the
            // printed budget and initialize its realtime mounts.
            let printed = World::new_campaign(6106, Start::new(stage, "standard"), "coord").unwrap();
            let (total, rows) = historical(&printed);
            let picks: Vec<String> = rows.iter().map(|row| row["identity"]
                .as_str().map(str::to_string)
                .unwrap_or_else(|| row["class"].as_str().unwrap().to_string())).collect();
            assert_eq!(picks.len(), rows.len(), "{stage} one pick per printed hull");
            let mut start = Start::new(stage, "story");
            start.fleet = Some(picks);
            let world = World::new_campaign(6106, start, "coord")
                .unwrap_or_else(|error| panic!("{stage} default story fleet: {error}"));
            assert_eq!(world.ships.iter().filter(|ship| ship.side == world.player).count(), rows.len(),
                "{stage} printed slot count");
            let spent: u32 = rows.iter().map(|row| row["points"].as_u64().unwrap() as u32).sum();
            assert_eq!(spent, total, "{stage} default picks stay on the printed point total");
        }
    }

    #[test]
    fn fleet_options_offer_the_registered_single_ship_pool_without_class_dedupe() {
        let allies = World::new_campaign(6106, Start::new("CAMP-ALLIES-02", "standard"), "coord").unwrap();
        let picker = options(&allies);
        let rows = picker["options"].as_array().unwrap();
        assert_eq!(rows.len(), 107, "every allied registered single-ship card is offered");
        assert!(rows.iter().all(|row| row["id"].as_str().is_some_and(|id| id.starts_with("IBS-U-"))));
        let classes: BTreeSet<_> = rows.iter().map(|row| row["class"].as_str().unwrap()).collect();
        assert!(classes.len() < rows.len(), "same-class identities stay separate options");

        let axis = World::new_campaign(6106, Start::new("CAMP-AXIS-02", "standard"), "coord").unwrap();
        assert_eq!(options(&axis)["options"].as_array().unwrap().len(), 95);
    }

    #[test]
    fn registered_identity_task_force_picks_initialize_campaign_realtime() {
        // These still ship period/merged cards rather than a scenario class id.
        // Picking one in a campaign task force must find its gun cadence, not
        // fail with "实时炮座配置尚未核准".
        for (stage, identity) in [
            ("CAMP-ALLIES-02", "IBS-U-USN-BOISE"),
            ("CAMP-ALLIES-02", "IBS-U-USN-FARENHOLT"),
            ("CAMP-ALLIES-02", "IBS-U-RAN-CANBERRA"),
            ("CAMP-AXIS-02", "IBS-U-IJN-CHOKAI"),
            ("CAMP-AXIS-02", "IBS-U-IJN-ATAGO"),
            ("CAMP-AXIS-02", "IBS-U-IJN-ERMA-AZUMA"),
        ] {
            let mut start = Start::new(stage, "standard");
            start.groups = Some(vec![GroupPick {
                position: 0,
                ships: vec![identity.into()],
            }]);
            let world = World::new_campaign(6106, start, "coord")
                .unwrap_or_else(|error| panic!("{identity} in {stage}: {error}"));
            let own = world.ships.iter().find(|ship| ship.side == world.player).unwrap();
            assert_eq!(own.character.as_deref(), Some(identity));
        }
    }
}
