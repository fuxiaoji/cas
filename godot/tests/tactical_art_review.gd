extends SceneTree
## GPU catalogue proof: every original identity loads its own alpha portrait.
const Output:String="res://../artifacts/home-littoral-20261113/art-review/"
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Output))
	var catalogue:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-units-v1.json"))
	check(catalogue.units.size()==20,"twenty tactical identity designs")
	var hashes:Dictionary={};var rows:Array=[]
	var canvas:=SubViewport.new();canvas.size=Vector2i(2000,2560);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var background:=ColorRect.new();background.color=Color("e7eeee");background.size=Vector2(2000,2560);canvas.add_child(background)
	for index in range(catalogue.units.size()):
		var row:Dictionary=catalogue.units[index];var path:String=str(row.portrait)
		check(FileAccess.file_exists(path),str(row.id)+" original PNG saved inside project")
		if not FileAccess.file_exists(path):continue
		var sha:String=FileAccess.get_sha256(path);check(not hashes.has(sha),str(row.id)+" unique illustration file");hashes[sha]=row.id
		var image:Image=Image.load_from_file(ProjectSettings.globalize_path(path))
		check(image!=null and image.get_height()>=1200 and image.get_width()>=800,str(row.id)+" production portrait resolution")
		if image==null:continue
		check(image.detect_alpha()!=Image.ALPHA_NONE,str(row.id)+" genuine alpha channel")
		check(image.get_pixel(0,0).a<.01 and image.get_pixel(image.get_width()-1,image.get_height()-1).a<.01,str(row.id)+" transparent canvas corners")
		var origin:Vector2=Vector2(index%5*400,index/5*640)
		var panel:=ColorRect.new();panel.position=origin+Vector2(8,8);panel.size=Vector2(384,624);panel.color=Color("f7f5ef");canvas.add_child(panel)
		var art:=TextureRect.new();art.position=origin+Vector2(12,15);art.size=Vector2(376,566);art.texture=ImageTexture.create_from_image(image);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;canvas.add_child(art)
		var label:=Label.new();label.position=origin+Vector2(18,579);label.size=Vector2(364,43);label.text=str(row.id)+" · "+str(row.name);label.theme=load("res://scripts/ui_design.gd").theme();label.add_theme_font_size_override("font_size",24);label.add_theme_color_override("font_color",Color("203e48"));canvas.add_child(label)
		rows.append({"id":row.id,"name":row.name,"path":path,"sha256":sha,"width":image.get_width(),"height":image.get_height(),"released":row.released})
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var screenshot:String=Output+"tactical-20-gpu.png"
	check(canvas.get_texture().get_image().save_png(ProjectSettings.globalize_path(screenshot))==OK,"GPU renders complete original cast on pale background")
	var receipt:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"portraits":rows,"contact_sheet":ProjectSettings.globalize_path(screenshot),"renderer":RenderingServer.get_video_adapter_name(),"reference_art_shipped":false}
	FileAccess.open(Output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
	print("TACTICAL_ART "+JSON.stringify({"checks":checks,"failures":failures}));canvas.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
