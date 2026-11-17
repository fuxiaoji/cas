@tool
class_name CasChapterLine
extends Resource
## Presentation only. Progress and battle outcomes are not authored here.
@export var speaker: String = ""
@export var speaker_name: String = ""
@export_multiline var text: String = ""
@export_enum("calm","concern","resolve","alert","bright","soft","cold","hurt","dry") var tone: String = "calm"
@export_enum("wide","near") var shot: String = "wide"
@export_enum("none","wake","step","pulse") var motion: String = "none"
@export_enum("none","tremble","echo") var text_effect: String = "none"
@export_range(15.0,70.0,1.0) var characters_per_second: float = 34.0
@export var caption: String = ""
@export var actors: Array[String] = []
@export var actor_tones: Dictionary = {}

func presentation() -> Dictionary:
	var line: Dictionary={"speaker":speaker,"text":text,"tone":tone,"shot":shot,"motion":motion,"text_effect":text_effect,"characters_per_second":characters_per_second,"caption":caption}
	if not speaker_name.is_empty():line["name"]=speaker_name
	if not actors.is_empty():line["actors"]=Array(actors)
	if not actor_tones.is_empty():line["actor_tones"]=actor_tones.duplicate()
	return line
