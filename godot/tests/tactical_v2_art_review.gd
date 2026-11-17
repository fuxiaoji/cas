extends SceneTree
## In-engine contact sheet: the actual actor renders each identity and stable casualty.
var checks:int=0
var failures:Array[String]=[]
const Art=preload("res://scripts/tactical_art_v2.gd")
var output:String="res://../artifacts/island-war-v2/presentation/"
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func frames(count:int=3)->void:
	for index in range(count):await process_frame
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.content_scale_size=Vector2i(1760,1120);root.size=Vector2i(1760,1120)
	var canvas:=Control.new();canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(canvas)
	var background:=ColorRect.new();background.color=Color("18323b");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.add_child(background)
	var units:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-art-v2.json")).units
	check(units.size()==22,"all twenty-two original identities registered")
	var row_index:int=0
	for unit in units:
		var identity:String=str(unit.id);var entry:Dictionary=Art.entry(identity)
		check(Art.available(identity),"approved actual own SD "+identity)
		var frames_data:Array=entry.get("frames",[])
		for cell in frames_data:
			var texture:Texture2D=Art.texture(str(cell.get("source","")))
			check(texture!=null,identity+" runtime frame texture loads")
			if texture!=null:
				var rect:Array=cell.get("rect",[])
				check(rect.size()==4 and float(rect[0])>=0 and float(rect[1])>=0 and float(rect[0])+float(rect[2])<=texture.get_width() and float(rect[1])+float(rect[3])<=texture.get_height(),identity+" runtime crop stays inside its own texture")
		for state in ["idle","walk","fire","hurt","search","defeated","deploy"]:
			check(not entry.get("animations",{}).get(state,[]).is_empty(),identity+" has "+state)
		var poses:Array=entry.get("animations",{}).get("defeated",[])
		check(poses.size()>=3,identity+" has at least three drawn casualty poses")
		for pose in poses:
			var data:Dictionary=frames_data[int(pose)];check(ResourceLoader.exists(str(data.get("source",""))),identity+" casualty source is imported")
		var origin:=Vector2(25+(row_index%4)*440,30+(row_index/4)*180)
		var name:=Label.new();name.text=identity+" · "+str(entry.get("name",""));name.position=origin;name.add_theme_font_size_override("font_size",17);canvas.add_child(name)
		for sample in range(4):
			var actor=load("res://scenes/ui/tactical_sprite_v2.tscn").instantiate();canvas.add_child(actor)
			actor.position=origin+Vector2(48+sample*101,145);actor.display_height=78;actor.preview_mode=true;actor.preview_identity=identity;actor.preview_action="idle" if sample==0 else "defeated";actor.preview_frame=maxi(0,sample-1)
			if sample>0:
				var selected:Dictionary=Art.frame(identity,"defeated",0,sample-1)
				check(selected==Art.frame(identity,"defeated",999,sample-1),identity+" corpse does not cycle with time")
		row_index+=1
	await frames(5)
	if DisplayServer.get_name()!="headless":
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+"all-22-own-sd-and-casualties.png"))==OK,"in-engine own SD contact sheet saved")
	var receipt:Dictionary={"checks":checks,"ok":failures.is_empty(),"failures":failures,"identities":units.map(func(unit):return str(unit.id))}
	FileAccess.open(output+"art-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"\t"));print(JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
