//! Point-buy fleets for the basic campaign difficulty.
//!
//! The historical force fixes the number of player hulls and their initial
//! slots. On the basic difficulty the player may replace each hull with any
//! same-side card whose point total fits the historical force's point budget;
//! the slot (position, heading, fleet, leader) stays one-to-one. Standard and
//! challenge always run the printed fleet.
use crate::{ranked_fleets, world::World, E};
use serde_json::{json, Value};

/// The point value of the historical player force. `fleet` entries are the
/// class IDs in spawn order, so the lobby can display the same order.
pub(crate) fn historical(w: &World) -> (u32, Vec<Value>) {
    let mut total = 0;
    let mut rows = Vec::new();
    for ship in w.ships.iter().filter(|ship| ship.side == w.player) {
        let def = &w.data.ships[ship.def];
        let points = ranked_fleets::ship_points(def);
        total += points;
        rows.push(json!({"class":def.id,"name":ship.name,"kind":def.kind,"points":points,
                         "slot":rows.len()}));
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
    json!({"budget":budget,"historical":historical,"options":filtered})
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
        let class = ranked_fleets::class_for(pick);
        let def = w
            .data
            .ships
            .iter()
            .position(|ship| ship.id == class || ship.id == *pick)
            .ok_or_else(|| format!("缺少已核验舰卡 {pick}"))?;
        let seat = if w.player == 0 { ["allies", "blue"] } else { ["axis", "red"] };
        if !seat.contains(&w.data.ships[def].side.as_str()) {
            return Err(format!("{} 不属于本席阵营", w.data.ships[def].name));
        }
        total += ranked_fleets::ship_points(&w.data.ships[def]);
        defs.push(def);
    }
    if total > budget {
        return Err(format!("编队点价 {total} 超过历史兵力 {budget} 分"));
    }
    for (id, def) in ids.iter().zip(defs) {
        let index = (*id - 1) as usize;
        let (p, h, speed, fleet, old_name, old_class) = {
            let old = &w.ships[index];
            (old.p, old.h, old.speed, old.fleet.unwrap_or(0), old.name.clone(),
             w.data.ships[old.def].id.clone())
        };
        let name = if w.data.ships[def].id == old_class { old_name } else {
            w.data.ships[def].name.clone()
        };
        // Build a fresh hull from the chosen card, then copy it over the old
        // slot. This resets mounts, torpedo tubes, damage and fire state while
        // preserving the printed slot, fleet and speed.
        let _fresh_id = w.spawn(def, w.player, fleet, name, p, h)?;
        let fresh = w.ships.pop().expect("fresh hull");
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
    use crate::campaign::live::Start;

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
}
