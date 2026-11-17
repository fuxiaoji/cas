# Island war v3 · original combined arms contract

Explicit `new_island_battle`, `version:cas-island-war-v3`. Published v2, littoral v1–v4, historical scenarios and existing records remain versioned and frozen. New land weapons, movement and vehicles are original accelerated game design, not historical CAS tables. Simulation positions/radii use meters; drawing scale changes no hitbox.

## Authoritative data and persistence

Request modes are `raid`, `defense`, `exercise`, retaining v2 fields. Exercise requires an explicit real `defender` with actual ships, roster, company layout, growth and conditions; it never substitutes NPC forces and has no account costs, rewards or settlement. Optional `lesson` is `landing|weapons|artillery|airborne|roles|combined_arms`. Saves retain exact supplied configuration and validated commands. Load/replay reconstruct finite simulation, including backward seek.

`island_war_catalogue(version=cas-island-war-v3)` exports the sole runtime table: 22 original identities/company counts, 43 concrete weapon models, 18 shared families, per-body primary/secondary compositions and independent vehicle specs. `godot/data/island-war-v3.json` is its export; design briefs are inputs, not another runtime balance table. `godot/data/tactical-training-v3.json` contains six complete borrowed manual-start requests.

Views retain `littoral.version=cas-littoral-v4` for existing controllers and identify the new rules through `island_war.version=cas-island-war-v3`. Actual bodies have stable IDs, x/y, HP, armor, motion, concrete `weapon_id`, `weapon_family_id`, compact `weapon`, finite weapon state, and `in_vehicle:null|u32`. Seated original bodies remain inactive for ground shooting and use `seated`/`render_as_infantry`; no replacement crew is created. Art stays `tactical-art-v2`; equipment is `tactical-vehicles-v3`.

`vehicle_condition:[{id,company,hp_percent}]` applies separately to either side, with one-based company numbers. Unknown, duplicate, out-of-company, zero, nonfinite and >100 entries are rejected. Missing entries read as 100 without writing an account. `littoral.outcome.vehicles` gives each actual platform's IDs, remaining HP and authoritative `recovered_hp_percent`. Only physically returned equipment, defending survivors, or never-deployed equipment aboard a living carrier is safe; destroyed/abandoned equipment returns zero. Bodies and vehicles have separate ledgers. Account consumers settle once and repair equipment separately.

## Fixed transport and separate equipment

All22 identities have `fixed_transport:true` and one transport option; illegal overrides are rejected. 022/103/087 still require armored/APV/LHA/CV carriage; 027/006 and parachute aircraft need LHA/CV. Infantry body classification does not relax equipment eligibility.

|Unit|Original bodies/company|Independent platform/company|Seats|Transport/recovery|
|---|---:|---|---:|---|
|022|6 rifle bodies|1 heavy tank|0|Heavy landing craft carries tank and six accompanying bodies; actual heavy-craft recovery|
|103|8 rifle bodies|1 amphibious vehicle|8|Same physical vehicle travels on water/land; actual enter/leave|
|087|6 pistol bodies|1 self-propelled gun|6|Heavy craft carries people/gun; independent land commands/fire|
|027|6 carbine bodies|1 heavy armed helicopter|6|Same helicopter inserts, fights, loads and returns|
|006|6 carbine bodies|1 light armed helicopter|6|Same helicopter inserts, fights, loads and returns|

All five use `min_crew:0` shared-consciousness remote control, with no additional driver. The tank cannot carry its accompanying infantry. Other platforms board only their own original surviving body IDs. Vehicle HP, armor class, weapon stock, magazine, reload, position and route are independent. The old six-helicopter006/body-as-tank design does not apply to v3.

011 has fixed two-seat kayaks, 180m/s accelerated game speed, no armor, quick unloading, and multiple genuine boats/company. 034 retains ordinary landing craft. Exposed passengers receive shore fire on their actual HP; boat HP is not a substitute. 088 retains five companies×ten bodies, vulnerable and unable to fire while descending, with boats for recovery.

`littoral.land.combat_vehicles` exposes ID/company/side, x/y, heading, actual velocity, active, carried_by, phase, movement_domain, altitude_m, passenger IDs, HP and finite weapon state. Phases: `aboard|inserting|active|loading|unloading|returning|recovered|dead`. Actual unloading clears `carried_by`; returning remains a visible physical trip.

## Commands and previews

`littoral_vehicle_order {vehicle_id,action,x?,y?}` supports `move|attack|embark|disembark`. Valid manual control clears obsolete autonomous withdrawal. Every body must physically reach its own platform; legal unloading preserves original IDs/HP/magazine/reserve. Tank boarding is refused. No company-center threshold teleports stragglers aboard. Equipment/body collision uses real footprints.

`littoral_vehicle_preview` takes identical arguments and returns `{valid,reason,...}` read-only. `littoral_ability_preview {unit_id?,company_id,x,y}` returns `{valid,reason}` from the actual shared ability gates: stage, charges, true originating shooter/platform, real range, magazine, target and terrain. A distant personnel center cannot veto an in-range SPG or allow an out-of-range one to fire. Preview changes no commands, RNG, clock, seats or ammo. V3 `littoral_order action=hold|stop` clears the path and holds every body center while its independent vehicle can move.

## Real firing rhythm and precision

`weapon.id` is a concrete model; `family_id` is shared mechanics/art. `fire_mode=single|burst`; authored timing is whole0.1-second frames. `fire_interval_s` separates burst shots; `burst_interval_s` runs from the previous burst's last shot to the next first. Single models use size1/matching intervals. `magazine_reload_s` is separate empty-magazine reload. `mean_fire_interval_s` and compatibility `reload_s` mean sustained average shot spacing, not reload duration.

`ammo_capacity` includes the loaded magazine. Always `magazine_ammo+reserve_ammo==ammo`, including reload. `reloading_in` is true magazine waiting; `ready_in` includes cadence gates. Every actual projectile/miss consumes one round. Primary/secondary states are separate but a body fires at most once/frame. An active weapon skill uses one real projectile round and one charge. Vehicle weapons do not debit people. Hand grenades/engineering explosives use declared company pools; a deployed AA turret owns its finite stock.

Precision model `piecewise-linear-v1` exports five normalized-distance knots, base accuracy, actual moving threshold2m/s, moving multiplier and smooth close-range penalty. Full catalogue includes baseline samples; live rows retain compact parameters. Formula: `clamp(base_hit*linear(curve,distance/range)*moving_factor*lerp(close_multiplier,1,clamp(distance/close_range_m,0,1))/command_spread_multiplier,0,.99)`. Vehicles use actual vehicle velocity.

Point weapons (`blast_radius_m=0`) use one seeded hit roll, resolve success on the current living target, and apply no second35m geometry lottery. Misses cannot hurt a nearby body. This is an explicit RTS point-target abstraction. Area weapons use `application=indirect_spread`: seeded uniform-disk error radius=`blast_radius_m*.85/max(quality,.05)`; actual geometry/radius/falloff decides damage, without another hit coin. Unguided shots lead actual target velocity; AA missiles track with fixed seeded error. Later turns can evade area fire. Public per-shot probability/quality is an estimate, not a guarantee.

Damage uses weapon target-class matrix×actual body/vehicle incoming armor multiplier×applicable terrain×protection×area falloff. Personnel armor never turns a person into vehicle armor class. Classes: unarmored/light_armor/heavy_armor/aircraft/helicopter/parachuting. Light weapons are weak against aircraft/armed helicopters but keep personnel effectiveness against descending paratroopers.

## Skills and actual armored cooperation

203 command_network modifies actual friendly motion/precision/task work.184 uses real finite damaging grenades.145 deploys an independent damageable finite AA turret.128 narrows real finite naval/air support scatter.009 demolition_charge needs an actual enemy fort within180m and uses three company explosives.116 supply_network has three charges,12s,700m, empty-magazine reload×.8 and incoming damage×.9; it creates/transfers no ammo. Protection also wraps existing native incoming paths before lethal damage. A gun-empty116 stays only with charges and a real living support recipient, otherwise withdraws.

AA turrets appear in `island_war.deployables`/`littoral.land.deployables` as `kind:aa_turret`, with side/position/HP/ammo/expiry and no extra people. Real-duration effects/marks appear in `littoral.land.effects`.027/006 skills use the existing independent platform; old support cannot create free extra helicopters.

AI uses same-side actually known bodies, never unseen members of a partly spotted company. Desired range uses living finite primary/secondary stocks and true cadence, choosing the furthest sampled distance retaining85% of peak estimated company DPS. This is a typed heuristic, not a geometric Monte Carlo calculation. Roles/reload hold remain explicit; an empty SPG withdraws despite escort pistol ammo. Extraction overrides combat spacing. V3 movement includes swept collision against actual platforms and independent straggler routes; frozen v2 movement stays unchanged.

022 and103 use actual known threat direction. Their tank/IFV leads, people seek legal positions10–19m behind it, and at most two bodies peek at the sides for2s per10s cycle. Real damage forces2s fallback. These are actual movement goals subject to individual collision/pathing, including autonomous combat hold; manual hold stays put. An active ground platform's real circular hull blocks direct firing segments on both sides. Friendly obstruction prevents a shot without consuming ammo; enemy hull intercepts it. Flanks and high-angle area fire can still hurt people behind a tank. No unconditional cover buff, instant formation placement, screen displacement or complete3D ballistics is claimed.

## Six borrowed lessons

`littoral.training={lesson,checks:[{id,label,instruction,unit_id,done}],complete,evidence,preparation_remaining_s}`. Every check uses real simulation events; both winning terminal and all checks are required. Configured training preparation only postpones actual defender fire (visible,≤120s), never grants progress; normal modes have none.

|Lesson|Actual checks|
|---|---|
|landing|Kayak landing, real shore fort destruction, survivor recovery|
|weapons|Light-weapon damage and typed anti-armor hit|
|artillery|Independent SPG hit, original pistol escort participation, real recovery|
|airborne|Actual parachute landing and reduced light-weapon hit against aircraft/helicopter|
|roles|demolition_charge/supply_network/command_network/grenade/deploy_aa_turret/support_designation, each from useful real effect/damage|
|combined_arms|vehicle_infantry/disembark/embark/independent_fire/recover; original people and equipment really deploy, separate, load, fire and return|

Borrowed assets do not become permanent units. Dialogue completion, clicking, empty-ground explosives and timers cannot pass these checks. An unresolved1200-second battle fails instead of producing a fictitious victory or endless account run.
