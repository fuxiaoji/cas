class_name CasEnemyAnimation
extends RefCounted
## Animation memory contains only already observed HP/state, never a retained enemy position.
const POSES := ["idle", "swim", "windup", "strike", "hurt", "down"]
var observed: Dictionary = {}
var last_tick := -1
var world_signature := 0

func update(view: Dictionary, clock: float) -> void:
	var tick := int(view.get("tick", 0))
	var signature := hash([view.get("scenario",""),view.get("islands",[]),view.get("salvage",{}).get("generatorVersion","")])
	if tick < last_tick or signature != world_signature:
		observed.clear()
	world_signature=signature
	var present: Array[String] = []
	for contact in view.get("contacts", []):
		var id := str(contact.get("id", ""))
		present.append(id)
		var hp := float(contact.get("health", contact.get("health_fraction", 1)))
		var attack := str(contact.get("attack", {}).get("state", ""))
		var previous: Dictionary = observed.get(id, {})
		if not previous.is_empty():
			if hp < float(previous.get("hp",hp)): previous["hurt_until"] = clock + .48
			if attack == "recover" and str(previous.get("attack","")) == "windup": previous["strike_until"] = clock + .65
		previous["hp"] = hp
		previous["attack"] = attack
		observed[id] = previous
	for id in observed.keys():
		if not present.has(str(id)): observed.erase(id)
	last_tick = tick

func pose(contact: Dictionary, clock: float) -> String:
	var previous: Dictionary = observed.get(str(contact.get("id", "")), {})
	if float(previous.get("hurt_until", -1)) > clock: return "hurt"
	if str(contact.get("attack", {}).get("state", "")) == "windup": return "windup"
	if float(previous.get("strike_until", -1)) > clock: return "strike"
	return "swim" if float(contact.get("speed", 0)) > .5 else "idle"

func transition(contact:Dictionary,clock:float)->Dictionary:
	var id:=str(contact.get("id",""))
	var current:=pose(contact,clock)
	var memory:Dictionary=observed.get(id,{})
	if str(memory.get("display_pose",current))!=current:
		memory["from_pose"]=str(memory.display_pose);memory["pose_at"]=clock
	memory["display_pose"]=current;observed[id]=memory
	return {"from":str(memory.get("from_pose",current)),"mix":clampf((clock-float(memory.get("pose_at",clock-1.0)))/.16,0,1)}

static func frames_for(species: String, textures: Dictionary) -> SpriteFrames:
	var asset := "res://assets/enemies/topdown-v2/" + species + "-frames.tres"
	if not ResourceLoader.exists(asset): return null
	if not textures.has(asset): textures[asset] = load(asset)
	return textures[asset] as SpriteFrames
