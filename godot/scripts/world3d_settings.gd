extends RefCounted
## A presentation switch only. It never selects a combat ruleset or a save.
static func enabled() -> bool:
	if Engine.is_editor_hint():
		return false
	if OS.has_environment("CAS_WORLD3D"):
		return OS.get_environment("CAS_WORLD3D") == "1"
	return bool(ProjectSettings.get_setting("cas/presentation/world3d", false))

static func eligible(land: Dictionary) -> bool:
	if not enabled() or land.get("polygon", []).size() < 3:
		return false
	var terrain: Dictionary = land.get("terrain", {})
	if str(land.get("geography",{}).get("version",""))=="cas-coastal-geography-v1":return true
	return str(terrain.get("version", "")) == "tactical-terrain-v4" or str(terrain.get("height_model", "")) == "inset_edge_blend_v1"
