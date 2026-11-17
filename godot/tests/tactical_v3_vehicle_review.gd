extends SceneTree
## Authored directional equipment, checked independently of account and combat.
const Art=preload("res://scripts/tactical_transport_art.gd")
const OUTPUT:String="res://../artifacts/island-war-v3/presentation/"
var checks:int=0
var failures:Array[String]=[]
class Board extends Control:
	var kinds:Array=[]
	func _draw()->void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("173d47"))
		draw_string(ThemeDB.fallback_font,Vector2(26,36),"V3 independent equipment / N E S W / actual movement heading",HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("f2e8c8"))
		for i in range(kinds.size()):
			var y:float=110+i*140
			draw_string(ThemeDB.fallback_font,Vector2(24,y),str(kinds[i]),HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("e8dbbb"))
			for direction in range(4):
				var at:=Vector2(480+direction*270,y+20)
				var heading:float=direction*PI*.5
				var row:Dictionary={"equipment_version":"tactical-vehicles-v3","vehicle_kind":kinds[i],"hp":100,"max_hp":100}
				Art.paint(self,row,at,108,heading,1.2,true,false,"infantry",str(kinds[i])=="self_propelled_gun")
				draw_string(ThemeDB.fallback_font,at+Vector2(-7,72),["N","E","S","W"][direction],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("c3e9e6"))
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func frames()->void:
	for i in range(4):await process_frame
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for name in ["main","canon_story_data","canon_story_actions","canon_story_service","canon_tactical_v3","tactical_weapons_tutorial_v3","tactical_weapon_fx_v3","tactical_weapon_badge_v3","tactical_transport_art","tactical_vehicle_controls_v3","littoral_battle","littoral_land","tactical_sprite","progression"]:
		var script:Script=load("res://scripts/%s.gd"%name)
		check(script!=null and script.reload()==OK and script.can_instantiate(),"load "+name)
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-vehicles-v3.json"))
	var kinds:Array=raw.vehicles.keys();kinds.sort()
	var expected:Array=["kayak","self_propelled_gun","landing_craft","armored_boat","fast_boat","heavy_lander","amphibious_vehicle","attack_helicopter","transport_helicopter","transport_aircraft","tank","aa_turret"]
	for kind in expected:check(kinds.has(kind),"independent equipment "+kind)
	for kind in kinds:
		var item:Dictionary=raw.vehicles[kind]
		var image:Image=Image.load_from_file(ProjectSettings.globalize_path(item.atlas))
		check(image!=null and not image.is_empty(),"decode "+kind)
		if image==null or image.is_empty():continue
		check(image.get_format()==Image.FORMAT_RGBA8,"true alpha "+kind)
		for direction in range(4):
			var key:String=["N","E","S","W"][direction]
			var frame:Dictionary=item.frames[key];var r:Array=frame.region
			check(float(r[0])>=0 and float(r[1])>=0 and float(r[0])+float(r[2])<=image.get_width() and float(r[1])+float(r[3])<=image.get_height(),"actual frame in texture "+kind+key)
			var spec:Dictionary=Art.specification({"equipment_version":"tactical-vehicles-v3","vehicle_kind":kind},direction*PI*.5+.13)
			check(str(spec.get("direction",""))==key and absf(float(spec.get("rotation",9))-.13)<.001,"frame plus residual heading "+kind+key)
			check(spec.get("path","")==item.atlas and spec.frame.region==frame.region,"metadata consumed "+kind+key)
			var pivot:Array=frame.anchor
			check(float(pivot[0])>=0 and float(pivot[1])>=0 and float(pivot[0])<float(r[2]) and float(pivot[1])<float(r[3]),"body centre anchor "+kind+key)
	# Explicit v3 selection must never silently replace a saved v2 vehicle.
	var old:Dictionary=Art.specification({"unit_id":"MCP-034","kind":"landing_craft","art_version":"tactical-art-v2","hp":100,"max_hp":100},PI*.5)
	check(not old.has("equipment_kind") and not str(old.get("path","")).contains("vehicles-v3"),"published v2 art remains separate")
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1600,900);root.content_scale_size=Vector2i(1600,900)
		var board:=Board.new();board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(board)
		for page in range(ceili(kinds.size()/5.0)):
			board.kinds=kinds.slice(page*5,mini(kinds.size(),page*5+5));board.queue_redraw();await frames();RenderingServer.force_draw(false)
			check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+"vehicle-directions-%d.png"%page))==OK,"GPU equipment page %d"%page)
		board.queue_free();await frames()
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"kinds":kinds,"scope":"Independent asset frame/anchor/heading consumption; GPU direction contact sheets; does not claim a battle or new account progress"}
	FileAccess.open(OUTPUT+"vehicle-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
