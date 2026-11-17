extends RefCounted
## Explicit new-map opt-in. Published accounts and historical battles stay frozen.
const VERSION:String="cas-island-war-coastal-v1"
const COMBAT_TUNING:String="coastal-combat-v2"
const SOURCE:String="res://data/coastal-demo-v1-714.json"
static var _geography:Dictionary={}
static func enabled()->bool:return OS.get_environment("CAS_COASTAL_V1")=="1"
static func geography()->Dictionary:
	if _geography.is_empty():
		var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if parsed is Dictionary:_geography=parsed
	return _geography
