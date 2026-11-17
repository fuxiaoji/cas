extends SceneTree
const Art=preload("res://scripts/tactical_art_v2.gd")
const Sprite=preload("res://scripts/tactical_sprite.gd")
var failures:Array[String]=[]
var checks:int=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	OS.set_environment("CAS_SIXTH_INFANTRY_PREVIEW","1")
	var card:Dictionary=Art.entry("MCP-306")
	var account=load("res://scripts/economy.gd").new("res://../artifacts/sixth-infantry/isolated-account.json")
	check(account.new_profile().ok,"isolated profile only")
	var home=load("res://scripts/home_service.gd").new(account)
	check(not home.state().units.has("MCP-306"),"new identity is not silently gifted")
	var unit:Dictionary=home.latest_unit("MCP-306")
	check(unit.get("company_count",0)==2 and unit.get("personnel_per_company",0)==10,"actual home catalogue has two companies of ten")
	check(ResourceLoader.exists(str(unit.get("portrait",""))),"recruitment uses own white tights portrait")
	check(home.latest_weapons().has("mcp306_bolt_action"),"home and core use same rifle")
	check(Art.available("MCP-306"),"own identity registered")
	check(card.frames.size()>=16,"sixteen authored poses")
	check(card.animations.defeated.size()>=3,"several distinct fallen poses")
	for state in ["idle","walk","fire","bolt","heal","hurt","search","fall","defeated"]:
		check(not Art.frame("MCP-306",state,.3).is_empty(),"state reachable "+state)
	var sprite:Node2D=Sprite.new();root.add_child(sprite)
	sprite.art_v2=true
	var row:Dictionary={"unit_id":"MCP-306","id":306,"hp":144,"max_hp":360,"x":0,"y":0,"side":"allies","equipment_version":"tactical-vehicles-v4"}
	sprite.configure(row,"",80);sprite.observe(row,Vector2(300,300),1,.1,false)
	sprite.fire(1,Vector2(500,300),{"tick":1,"weapon_family_id":"dmr"});sprite.clock=1.4;sprite._refresh()
	check(sprite.state_name=="bolt","actual fire selects bolt")
	row=row.duplicate();row.hp=234;sprite.observe(row,Vector2(300,300),1.5,.1,false)
	check(sprite.state_name=="heal","actual health increase selects bandage")
	root.size=Vector2i(1600,900);root.content_scale_size=Vector2i(1600,900)
	sprite.visible=false
	var board:Node2D=Node2D.new();root.add_child(board)
	board.draw.connect(func():
		board.draw_rect(Rect2(0,0,1600,900),Color("eee9df"))
		var states:Array[String]=["idle","walk","fire","bolt","heal","hurt","search","defeated"]
		for i in range(states.size()):
			var p:=Vector2(160+(i%4)*400,300+floori(i/4.0)*420)
			Art.paint(board,"MCP-306",states[i],.3,i,150,p,false)
			Art.paint(board,"MCP-306",states[i],.3,i,80,p+Vector2(130,0),true)
	)
	board.queue_redraw()
	for i in range(5):await process_frame
	if DisplayServer.get_name()!="headless":
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/sixth-infantry/native-poses.png"))==OK,"GPU snapshot saved")
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"own identity, semantic pose lookup, actual shot and health-increase presentation, mirrored GPU poses; no user account loaded"}
	FileAccess.open("res://../artifacts/sixth-infantry/native-art.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
