@tool
class_name CasChapterSceneVisual
extends Resource
## Safe visual overrides. Mission id, unlocks, next node and rewards remain in the versioned chapter JSON files.
@export var scene_id: String = ""
@export_file("*.png", "*.webp") var background: String = ""
@export var full_cg: bool = false
@export var actors: Array[String] = []
@export_enum("harbor","formation","salvage","battle") var music_scene: String = "harbor"
@export var location: String = ""
@export var lines: Array[CasChapterLine] = []

func presentation() -> Dictionary:
	var out:Dictionary={"background_asset":background,"cg":full_cg,"actors":Array(actors),"music_scene":music_scene,"location":location}
	if not lines.is_empty():
		var dialogue:Array=[]
		for line in lines:dialogue.append(line.presentation())
		out["lines"]=dialogue
	return out
