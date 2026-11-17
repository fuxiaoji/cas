extends "res://scripts/coastal_architecture.gd"
## Home facility art prototypes. Geometry only: no account, production or combat state.
## All dimensions in metres. Ground is X/Z, Y is height. Front faces -Z.

const CATALOG: Array[Dictionary] = [
	{"id":"command","name":"灯塔指挥所","group":"民生与生产","plot":Vector2(22,24)},
	{"id":"recycler","name":"浮材回收场","group":"民生与生产","plot":Vector2(25,24)},
	{"id":"farm","name":"菜畦与育苗棚","group":"民生与生产","plot":Vector2(29,26)},
	{"id":"workshop","name":"综合工坊","group":"民生与生产","plot":Vector2(26,24)},
	{"id":"warehouse","name":"物资仓库","group":"民生与生产","plot":Vector2(25,24)},
	{"id":"power","name":"能源与储能站","group":"民生与生产","plot":Vector2(22,23)},
	{"id":"barracks","name":"驻防营舍","group":"整备与防御","plot":Vector2(25,25)},
	{"id":"medical","name":"整备医疗站","group":"整备与防御","plot":Vector2(23,24)},
	{"id":"research","name":"遗迹研究所","group":"整备与防御","plot":Vector2(23,24)},
	{"id":"coastal_gun","name":"反装甲岸炮","group":"整备与防御","plot":Vector2(20,21)},
	{"id":"air_defense","name":"防空雷达阵地","group":"整备与防御","plot":Vector2(22,22)},
	{"id":"trench","name":"掩体与战壕","group":"整备与防御","plot":Vector2(25,21)}
]

func build(height_at: Callable) -> void:
	_height_at = height_at
	_palette()
	for i: int in range(CATALOG.size()):
		var column: int = i % 4
		var row: int = i / 4
		spawn_facility(str(CATALOG[i]["id"]), Vector2(-63+column*40,106+row*37))

func spawn_facility(kind: String, ground: Vector2 = Vector2.ZERO) -> Node3D:
	_palette()
	var entry: Dictionary = CATALOG[0]
	for item: Dictionary in CATALOG:
		if str(item["id"]) == kind: entry = item
	var root: Node3D = _root(self, "Home_"+kind, ground, entry["plot"], 0.0)
	root.set_meta("facility_id",kind)
	root.set_meta("display_name",entry["name"])
	var b: Dictionary = {}
	var plot: Vector2 = entry["plot"]
	_box(b,"stone",Vector3(0,-.15,0),Vector3(plot.x,.42,plot.y))
	_box(b,"paving",Vector3(0,.08,0),Vector3(plot.x-.25,.10,plot.y-.25))
	# The landing slab has a low retaining edge and scored paving, not a floating card.
	for x: float in [-plot.x*.5,plot.x*.5]:
		_box(b,"cream",Vector3(x,.14,0),Vector3(.24,.25,plot.y))
	for z: float in [-plot.y*.5,plot.y*.5]:
		_box(b,"cream",Vector3(0,.14,z),Vector3(plot.x,.25,.24))
	match kind:
		"command": _command(b)
		"recycler": _recycler(b)
		"farm": _farm(b)
		"workshop": _workshop(b)
		"warehouse": _warehouse(b)
		"power": _power(b)
		"barracks": _barracks(b)
		"medical": _medical(b)
		"research": _research(b)
		"coastal_gun": _coastal_gun(b)
		"air_defense": _air_defense(b)
		"trench": _trench(b)
	_finish(root,b)
	return root

func _house(b: Dictionary, at: Vector3, size: Vector3, wall: String = "ivory", roof: bool = true) -> void:
	_box(b,wall,at+Vector3(0,size.y*.5+.35,0),size)
	_box(b,"cream",at+Vector3(0,.42,0),Vector3(size.x+.3,.38,size.z+.3))
	_box(b,"cream",at+Vector3(0,size.y+.30,0),Vector3(size.x+.45,.24,size.z+.4))
	if roof: _gable_roof(b,size.x+.8,size.z+.8,size.y+.42,size.x*.23,wall,at)
	for x: float in [-size.x*.32,size.x*.32]:
		_window(b,at+Vector3(x,2.35,-size.z*.5-.08),1.25,1.55,0,true,false)
	_door(b,at+Vector3(0,.38,-size.z*.5-.12),1.4,2.6,false)
	for side: int in [-1,1]:
		_box(b,"copper",at+Vector3(side*(size.x*.5+.38),size.y+.30,0),Vector3(.12,.12,size.z+.7))

func _command(b: Dictionary) -> void:
	_house(b,Vector3(-2,0,2),Vector3(13,6,9))
	_balcony(b,Vector3(-2,3.4,-3.3),6.4,1.7)
	_cylinder(b,"stone",Vector3(6,3.8,2),2.35,7.4,12)
	_cylinder(b,"cream",Vector3(6,8,2),2.6,.5,12)
	_cylinder(b,"glass",Vector3(6,8.8,2),2,1.25,12)
	_cylinder(b,"teal",Vector3(6,9.6,2),2.5,.45,12)
	for i: int in range(8):
		var a: float = TAU*i/8
		_beam(b,"cream",Vector3(6+2.1*cos(a),8.15,2+2.1*sin(a)),Vector3(6+2.1*cos(a),9.5,2+2.1*sin(a)),.12,.12)
	_cylinder(b,"iron",Vector3(-7,5,-7),.07,10,8)
	_box(b,"blue",Vector3(-5.9,9,-7),Vector3(2.1,1.2,.06))
	_planter(b,Vector3(3,.2,-6),1.6)
	for i: int in range(3): _box(b,"stone",Vector3(-2,.15+float(i)*.12,-6.6+i*.6),Vector3(5,.32,.7))

func _recycler(b: Dictionary) -> void:
	_house(b,Vector3(-7,0,4),Vector3(7,4.0,7),"apricot")
	for x: float in [0,8]: _box(b,"iron",Vector3(x,3,3),Vector3(.38,6,.38))
	_beam(b,"sign",Vector3(-.5,6,3),Vector3(8.5,6,3),.5,.5)
	_cylinder(b,"iron",Vector3(4,4.6,3),.10,2.3,8)
	for i: int in range(5):
		_crate(b,Vector3(1+i*1.6,.1,-5),1.25)
		_box(b,"copper",Vector3(2+i*.95,.5,5),Vector3(.7,.6,2.8),Basis(Vector3.UP,float(i)*.24))
	for z: float in [-8,-6.5]: _box(b,"wood",Vector3(-7,.45,z),Vector3(5,.65,.9))
	_box(b,"teal",Vector3(5,1,-1),Vector3(5.6,1.6,3))
	for x: float in [2.5,7.5]: _box(b,"cream",Vector3(x,1.05,-2.55),Vector3(.15,1.5,.12))

func _farm(b: Dictionary) -> void:
	# Raised beds, stakes and young crop clumps; no decorative currency objects.
	for row: int in range(5):
		for column: int in range(5):
			var at: Vector3 = Vector3(-11+column*2.6,.2,-8+row*3.5)
			_box(b,"dark_wood",at,Vector3(2.35,.35,2.6))
			_box(b,"wood",at+Vector3(0,.2,0),Vector3(2.1,.12,2.35))
			for plant: int in range(3):
				_cylinder(b,"leaf",at+Vector3(-.6+plant*.6,.6,.2),.35,.55,6)
	_house(b,Vector3(8,0,5),Vector3(7,3.8,6),"mint")
	for z: float in [-6,-3,0]:
		_box(b,"sky_glint",Vector3(8,1.8,z),Vector3(6.8,3.1,2.8))
		for x: float in [4.5,11.5]: _box(b,"cream",Vector3(x,1.8,z),Vector3(.12,3.6,3))
		_box(b,"cream",Vector3(8,3.5,z),Vector3(7,.14,3))

func _workshop(b: Dictionary) -> void:
	_house(b,Vector3(-3,0,2),Vector3(15,5,12),"apricot",false)
	# Repeated north-light sawtooth roofs identify the workshop at a glance.
	for row: int in range(3):
		_gable_roof(b,5.1,12.8,5.4,1.6,"apricot",Vector3(-8+row*5,0,2))
		_box(b,"glass",Vector3(-8+row*5,6.05,-4.05),Vector3(2.7,.7,.12))
	_box(b,"teal",Vector3(-3,2.2,-4.13),Vector3(5,3.5,.13))
	for z: float in [-5,0,5]:
		_box(b,"iron",Vector3(7,2.4,z),Vector3(3,4.4,2.4))
		_cylinder(b,"copper",Vector3(7,4.9,z),.8,.6,12)
	_chimney(b,Vector3(-8,7.2,6))
	for i: int in range(3): _crate(b,Vector3(-8+i*2.4,.2,-8),1.65)
	for i: int in range(5):
		_box(b,"cream",Vector3(-9+i*3,2.3,-4.2),Vector3(.14,3.8,.2))
	for i: int in range(5): _box(b,"iron",Vector3(-3,1+i*.6,-4.22),Vector3(5,.06,.08))

func _warehouse(b: Dictionary) -> void:
	_house(b,Vector3(-2,0,2),Vector3(15,5,12),"mint")
	for x: float in [-5,1]: _box(b,"teal",Vector3(x,2.4,-4.1),Vector3(4.5,3.8,.15))
	for i: int in range(4):
		_crate(b,Vector3(-8+i*3,.5,-7),2)
		_box(b,"wood",Vector3(-8+i*3,.25,-7),Vector3(2.3,.25,2.3))
	for x: float in [7,9]:
		_cylinder(b,"copper",Vector3(x,1.5,5),.85,2.6,12)
	for i: int in range(4): _box(b,"paving_light",Vector3(-3,.12+float(i)*.07,-5.5-i*.7),Vector3(12,.14,.75))

func _power(b: Dictionary) -> void:
	_house(b,Vector3(-5,0,3),Vector3(8,4.3,8),"ivory")
	for x: float in [3,8]:
		for z: float in [-5,1,7]:
			_box(b,"iron",Vector3(x,.8,z),Vector3(.25,1.4,.25))
			_box(b,"blue",Vector3(x,1.7,z),Vector3(3.8,.18,4.4),Basis(Vector3.RIGHT,-.24))
			for dx: float in [-1.8,-.6,.6,1.8]: _box(b,"sky_glint",Vector3(x+dx,1.85,z),Vector3(.04,.04,4.3),Basis(Vector3.RIGHT,-.24))
	for x: float in [-8,-5,-2]:
		_box(b,"teal",Vector3(x,1.25,-7),Vector3(2.2,2.2,2.1))
		_box(b,"cream",Vector3(x,2.4,-7),Vector3(2.3,.18,2.2))

func _barracks(b: Dictionary) -> void:
	_house(b,Vector3(-6,0,4),Vector3(8,4.2,11),"ivory")
	_house(b,Vector3(6,0,4),Vector3(8,4.2,11),"mint")
	_box(b,"paving_light",Vector3(0,.2,-6),Vector3(18,.1,6))
	for z: float in [-7,-4.5]: _beam(b,"wood",Vector3(-7,.6,z),Vector3(-1,.6,z),.22,.22)
	for x: float in [2,4,6,8]:
		_box(b,"dark_wood",Vector3(x,.7,-5.5),Vector3(.18,1.3,.18))
		_box(b,"sign",Vector3(x,1.7,-5.5),Vector3(.9,1,.16))
	_cylinder(b,"iron",Vector3(0,4.8,3),.06,9.4,8)
	_box(b,"blue",Vector3(1,8.9,3),Vector3(2,1.2,.06))

func _medical(b: Dictionary) -> void:
	_house(b,Vector3(0,0,2),Vector3(16,4.6,10),"ivory")
	_box(b,"cream",Vector3(0,5.3,-3.6),Vector3(4,2.4,.23))
	_box(b,"flower",Vector3(0,5.35,-3.75),Vector3(.46,1.6,.1))
	_box(b,"flower",Vector3(0,5.35,-3.75),Vector3(1.6,.46,.1))
	_box(b,"teal",Vector3(0,3.4,-5.3),Vector3(8,.18,4.2))
	for x: float in [-3.8,3.8]: _box(b,"cream",Vector3(x,1.8,-7),Vector3(.15,3.3,.15))
	for x: float in [-7,7]: _planter(b,Vector3(x,.25,-7),1.7)
	for i: int in range(2): _box(b,"cream",Vector3(-4+float(i)*8,.65,-7),Vector3(3.6,.25,1.1))

func _research(b: Dictionary) -> void:
	_house(b,Vector3(0,0,2),Vector3(15,5.5,11),"mint",false)
	_cylinder(b,"teal",Vector3(0,6.1,2),4.7,.7,16)
	_cylinder(b,"glass",Vector3(0,7,2),3.8,1.5,16)
	_cylinder(b,"cream",Vector3(0,7.9,2),4.1,.3,16)
	_cylinder(b,"teal",Vector3(0,8.2,2),2.2,.6,16)
	for x: float in [-5,5]:
		_box(b,"copper",Vector3(x,1.4,-7),Vector3(2.2,2.5,2.2))
		_box(b,"sky_glint",Vector3(x,2.9,-7),Vector3(1.8,.4,1.8))
	_box(b,"sky_glint",Vector3(0,3,-3.63),Vector3(1.3,1.8,.12))
	for x: float in [-9,9]: _planter(b,Vector3(x,.25,4),1.4)

func _sandbags(b: Dictionary, at: Vector3, length: int, yaw: float = 0.0) -> void:
	for level: int in range(3):
		for i: int in range(length):
			var local: Vector3 = Vector3((i-(length-1)*.5)*1.0+float(level%2)*.35,level*.33+.25,0)
			_box(b,"sign",at+Basis(Vector3.UP,yaw)*local,Vector3(.95,.30,.62),Basis(Vector3.UP,yaw))

func _coastal_gun(b: Dictionary) -> void:
	_cylinder(b,"stone",Vector3(0,.35,0),7,.5,24)
	_cylinder(b,"iron",Vector3(0,1.0,0),2.25,1.1,16)
	_box(b,"iron",Vector3(0,1.5,0),Vector3(3.4,.6,4.2))
	for side: int in [-1,1]:
		_box(b,"teal",Vector3(side*1.3,2.1,-.5),Vector3(.35,1.5,2.6))
		_cylinder(b,"iron",Vector3(side*1.5,2.6,-.6),.6,.32,12,Basis(Vector3.FORWARD,PI*.5))
	_box(b,"teal",Vector3(0,2.8,-1.6),Vector3(4.6,2.4,.35),Basis(Vector3.RIGHT,-.18))
	_box(b,"iron",Vector3(0,2.7,.3),Vector3(1.1,1.0,2.5))
	_cylinder(b,"iron",Vector3(0,2.8,-4.6),.23,6.5,14,Basis(Vector3.RIGHT,PI*.5-.04))
	_cylinder(b,"copper",Vector3(0,2.75,-2.6),.35,1.8,14,Basis(Vector3.RIGHT,PI*.5-.04))
	_cylinder(b,"iron",Vector3(0,2.97,-7.9),.30,.7,14,Basis(Vector3.RIGHT,PI*.5-.04))
	_box(b,"glass",Vector3(0,2.98,-8.27),Vector3(.26,.22,.04))
	for i: int in range(8): _box(b,"paving_light",Vector3(-5.9+i*1.7,.62,5.4),Vector3(.8,.1,.17))
	_box(b,"cream",Vector3(-2.5,1.2,2),Vector3(1.5,1.8,1.6))
	_sandbags(b,Vector3(0,.15,5.5),11)
	_sandbags(b,Vector3(-6,.15,1),8,PI*.5)
	_sandbags(b,Vector3(6,.15,1),8,PI*.5)
	for x: float in [-4,4]: _crate(b,Vector3(x,.2,-3),1.3)

func _air_defense(b: Dictionary) -> void:
	_cylinder(b,"stone",Vector3(-3,.3,-2),4.2,.5,16)
	_box(b,"teal",Vector3(-3,1,-2),Vector3(3.6,1.5,3.4))
	for x: float in [-3.65,-2.35]:
		_beam(b,"iron",Vector3(x,1.5,-2),Vector3(x,5.5,-5),.27,.27)
	_box(b,"cream",Vector3(5,1.7,4),Vector3(5,3,5))
	_cylinder(b,"iron",Vector3(5,5.7,4),.15,5,8)
	_box(b,"teal",Vector3(5,8,4),Vector3(4.8,2.2,.2),Basis(Vector3.UP,.4))
	for i: int in range(7): _box(b,"sky_glint",Vector3(3.3+i*.55,8,3.9),Vector3(.08,1.8,.10))
	_sandbags(b,Vector3(-3,.15,4),9)
	for x: float in [-6,-3,0]: _crate(b,Vector3(x,.2,7),1.1)

func _trench(b: Dictionary) -> void:
	_box(b,"wood",Vector3(-2,.4,0),Vector3(17,.6,3.4))
	for x: float in [-10,-7,-4,-1,2,5]:
		_box(b,"dark_wood",Vector3(x,.75,0),Vector3(.18,.9,3))
	_sandbags(b,Vector3(-2,.1,-2.2),18)
	_sandbags(b,Vector3(-2,.1,2.2),18)
	_box(b,"stone",Vector3(7,1.25,1),Vector3(6,2.2,6))
	_box(b,"leaf",Vector3(7,2.6,1),Vector3(6.8,.55,6.8))
	_box(b,"glass",Vector3(7,1.6,-2.07),Vector3(4.6,.5,.1))
	_box(b,"iron",Vector3(7,1.7,-3.3),Vector3(.16,.16,2.5))
	for i: int in range(3): _crate(b,Vector3(-8+i*2,.2,6),1.2)
