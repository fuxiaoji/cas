@tool
extends Control
## Original game symbols inspired by the frame/function grammar of military maps.
## Deliberately simplified for small game tokens; not an APP-6 compliance renderer.

@export var role: String = "marine":
	set(value):
		role = value
		queue_redraw()
@export_enum("friendly", "hostile", "neutral") var affiliation: String = "friendly":
	set(value):
		affiliation = value
		queue_redraw()
@export var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()
@export var echelon:String="":
	set(value):echelon=value;queue_redraw()
const FormationMark=preload("res://scripts/tactical_formation_mark.gd")
var nato_type: String:
	get:
		return canonical_role(role)
	set(value):
		set_role(value)

const ROLES: Array[String] = ["air_assault", "marine", "airborne", "engineer", "armor", "recon", "gunship", "electronic", "medic", "antiarmor", "artillery", "transport", "logistics", "sniper", "airdefense", "riverine", "breacher", "command", "rescue", "infantry"]
const ROLE_NAMES: Dictionary = {"air_assault":"空中突击", "marine":"海军陆战", "airborne":"空降", "engineer":"工兵", "armor":"装甲", "recon":"侦察", "gunship":"武装旋翼", "electronic":"电子战", "medic":"医疗", "antiarmor":"反装甲", "artillery":"炮兵", "transport":"运输", "logistics":"后勤", "sniper":"精确射手", "airdefense":"防空", "riverine":"河岸作战", "breacher":"破障", "command":"指挥", "rescue":"救援", "infantry":"步兵", "unknown":"未识别类型"}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = custom_minimum_size.max(Vector2(42, 34))
	resized.connect(queue_redraw)
	tooltip_text = role_name(role)

func configure(new_role: String, new_affiliation: String = "friendly", is_selected: bool = false, formation_echelon:String="") -> void:
	role = new_role
	affiliation = new_affiliation
	selected = is_selected
	echelon = formation_echelon
	tooltip_text = role_name(role)

func set_role(value: String) -> void:
	role = value
	tooltip_text = role_name(role)

static func canonical_role(value: String) -> String:
	var key: String = value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	key = str({"airassault":"air_assault", "airmobile_infantry":"air_assault", "marines":"marine", "mechanized_infantry":"marine", "naval_infantry":"marine", "airborne_infantry":"airborne", "assault_infantry":"breacher", "armour":"armor", "reconnaissance":"recon", "helicopter":"gunship", "aviation":"gunship", "electronic_warfare":"electronic", "medical":"medic", "anti_tank":"antiarmor", "anti_air":"airdefense", "air_defense":"airdefense", "supply":"logistics"}.get(key, key))
	return key if ROLES.has(key) else "unknown"

static func role_name(value: String) -> String:
	return str(ROLE_NAMES[canonical_role(value)])

func _draw() -> void:
	paint(self, Rect2(Vector2.ZERO, size), role, affiliation, selected, echelon)

static func _line(canvas: CanvasItem, points: Array, area: Rect2, color: Color, width: float) -> void:
	var path := PackedVector2Array()
	for point: Vector2 in points:
		path.append(area.position + point * area.size)
	canvas.draw_polyline(path, color, width, true)

static func paint(canvas: CanvasItem, rect: Rect2, type: String, side: String = "friendly", is_selected: bool = false, formation_echelon:String="") -> void:
	if rect.size.x < 8 or rect.size.y < 8:
		return
	var kind: String = canonical_role(type)
	var ink := Color("d7f1e9")
	var fill := Color("183f48")
	if side in ["hostile", "axis", "enemy"]:
		ink = Color("ffd3b4")
		fill = Color("663e38")
	elif side == "neutral":
		ink = Color("eee3bc")
		fill = Color("484b43")
	var stroke: float = maxf(1.5, minf(rect.size.x, rect.size.y) * 0.055)
	var frame: Rect2 = rect.grow(-stroke * 1.4)
	var mark:String=FormationMark.symbol(formation_echelon)
	if not mark.is_empty():
		var mark_size:int=maxi(10,roundi(rect.size.y*.29))
		var font:Font=ThemeDB.fallback_font
		var width:float=font.get_string_size(mark,HORIZONTAL_ALIGNMENT_LEFT,-1,mark_size).x
		canvas.draw_string(font,Vector2(rect.get_center().x-width*.5,rect.position.y+mark_size*.76),mark,HORIZONTAL_ALIGNMENT_LEFT,-1,mark_size,ink)
		frame.position.y+=rect.size.y*.25;frame.size.y-=rect.size.y*.25
	if side in ["hostile", "axis", "enemy"]:
		var diamond := PackedVector2Array([Vector2(frame.get_center().x, frame.position.y), Vector2(frame.end.x, frame.get_center().y), Vector2(frame.get_center().x, frame.end.y), Vector2(frame.position.x, frame.get_center().y)])
		canvas.draw_colored_polygon(diamond, fill)
		diamond.append(diamond[0])
		canvas.draw_polyline(diamond, ink, stroke, true)
	else:
		canvas.draw_rect(frame, fill)
		canvas.draw_rect(frame, ink, false, stroke)
	if is_selected:
		canvas.draw_rect(rect.grow(-stroke * .5), Color("ffe1a1"), false, stroke)
	var area := Rect2(frame.position + frame.size * Vector2(.22, .22), frame.size * Vector2(.56, .56))
	match kind:
		"infantry", "marine", "airborne", "riverine":
			_line(canvas, [Vector2(.05,.1),Vector2(.95,.9)], area, ink, stroke)
			_line(canvas, [Vector2(.05,.9),Vector2(.95,.1)], area, ink, stroke)
			if kind == "marine":
				_line(canvas,[Vector2(0,1),Vector2(.25,.88),Vector2(.5,1),Vector2(.75,.88),Vector2(1,1)],area,ink,stroke)
			if kind == "riverine":
				_line(canvas,[Vector2(-.1,.7),Vector2(.1,1.1),Vector2(.9,1.1),Vector2(1.1,.7)],area,ink,stroke)
			if kind == "airborne":
				_line(canvas,[Vector2(0,.18),Vector2(.2,-.1),Vector2(.5,-.22),Vector2(.8,-.1),Vector2(1,.18)],area,ink,stroke)
		"armor":
			canvas.draw_arc(area.get_center(), area.size.y*.4, 0, TAU, 32, ink, stroke, true)
			_line(canvas,[Vector2(.35,.5),Vector2(1,.5)],area,ink,stroke)
		"air_assault", "gunship":
			_line(canvas,[Vector2(0,.18),Vector2(1,.18)],area,ink,stroke)
			_line(canvas,[Vector2(.5,.05),Vector2(.5,.72),Vector2(.22,.94)],area,ink,stroke)
			_line(canvas,[Vector2(.5,.72),Vector2(.78,.94)],area,ink,stroke)
			if kind == "gunship":
				_line(canvas,[Vector2(.16,.62),Vector2(.84,.62)],area,ink,stroke)
		"recon", "sniper":
			_line(canvas,[Vector2(.1,.9),Vector2(.9,.1)],area,ink,stroke)
			if kind == "sniper":
				canvas.draw_arc(area.get_center(),minf(area.size.x,area.size.y)*.34,0,TAU,24,ink,stroke,true)
			else:
				canvas.draw_circle(area.position+area.size*Vector2(.72,.7),stroke*1.3,ink)
		"engineer", "breacher":
			_line(canvas,[Vector2(.1,.95),Vector2(.1,.2),Vector2(.9,.2),Vector2(.9,.95)],area,ink,stroke)
			_line(canvas,[Vector2(.1,.55),Vector2(.9,.55)],area,ink,stroke)
			if kind == "breacher":
				_line(canvas,[Vector2(.5,.2),Vector2(.38,.5),Vector2(.63,.5),Vector2(.42,.85)],area,ink,stroke)
		"medic", "rescue":
			_line(canvas,[Vector2(.5,.1),Vector2(.5,.9)],area,ink,stroke*1.65)
			_line(canvas,[Vector2(.1,.5),Vector2(.9,.5)],area,ink,stroke*1.65)
			if kind == "rescue":
				canvas.draw_arc(area.get_center(),minf(area.size.x,area.size.y)*.58,0,TAU,28,ink,stroke,true)
		"artillery", "antiarmor", "airdefense":
			if kind == "artillery":
				canvas.draw_circle(area.get_center(),stroke*1.8,ink)
			elif kind == "antiarmor":
				_line(canvas,[Vector2(.05,.9),Vector2(.5,.08),Vector2(.95,.9),Vector2(.05,.9)],area,ink,stroke)
			else:
				canvas.draw_arc(area.position+area.size*Vector2(.5,.9),area.size.y*.75,PI,TAU,24,ink,stroke,true)
				_line(canvas,[Vector2(.5,.9),Vector2(.5,.05)],area,ink,stroke)
		"electronic":
			_line(canvas,[Vector2(.1,.55),Vector2(.3,.55),Vector2(.44,.1),Vector2(.6,.9),Vector2(.74,.4),Vector2(.92,.4)],area,ink,stroke)
		"transport", "logistics":
			canvas.draw_rect(Rect2(area.position+area.size*Vector2(.05,.2),area.size*Vector2(.9,.58)),ink,false,stroke)
			if kind == "transport":
				canvas.draw_circle(area.position+area.size*Vector2(.25,.95),stroke*1.2,ink)
				canvas.draw_circle(area.position+area.size*Vector2(.75,.95),stroke*1.2,ink)
			else:
				_line(canvas,[Vector2(.5,.2),Vector2(.5,.78)],area,ink,stroke)
		"command":
			_line(canvas,[Vector2(.2,1),Vector2(.2,0),Vector2(.9,.15),Vector2(.2,.5)],area,ink,stroke)
		_:
			_line(canvas,[Vector2(.2,.2),Vector2(.5,0),Vector2(.8,.2),Vector2(.5,.55),Vector2(.5,.68)],area,ink,stroke)
			canvas.draw_circle(area.position+area.size*Vector2(.5,.94),stroke,ink)
