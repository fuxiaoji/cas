extends RefCounted
## Original approved AI identities, reused as the faces of related CAS doctrines.
## Avatar family selection is cosmetic; it does not replace the simulation policy.
const BINDINGS:Dictionary={
	"coord":"rc_coordinated", "gunnery":"fleet", "torpedo":"rc_torpedo_wings",
	"evo-screen":"evo-screen", "evo-torpedo":"evo-torpedo", "evo-gunnery":"evo-gunnery",
	"evo-brawler":"evo-brawler", "evo-kiter":"evo-kiter", "evo-denial":"evo-denial"
}
static func lookup(profile:String)->Dictionary:
	var registry:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/ai-art.json"))
	if not registry is Dictionary:return {}
	for row:Dictionary in registry.get("profiles",[]):
		if str(row.id)==str(BINDINGS.get(profile,"")):return row.duplicate(true)
	return {}
