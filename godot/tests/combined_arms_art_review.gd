extends SceneTree
## Real imported textures and editable scene; no combat outcome or account claims.
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run()->void:
	var directory:String="res://../artifacts/littoral-v4-ui/art/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var preview:Control=load("res://scenes/ui/combined_arms_art_preview.tscn").instantiate()
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1600,900);root.add_child(preview)
	for i in range(4):await process_frame
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/combined-arms-art-v4.json"))
	var sources:Dictionary={}
	for entry in raw.casualties.values():sources[str(entry.atlas)]=true
	for entry in raw.aircraft.values():sources[str(entry.atlas)]=true
	for entry in raw.land_enemies.values():sources[str(entry.atlas)]=true
	var assets:Array=[]
	for path in sources:
		var texture:Texture2D=load(str(path));check(texture!=null,"actual texture imported "+str(path))
		var image:Image=texture.get_image();check(image.has_mipmaps(),"mipmap pyramid generated for small battle projection "+str(path))
		var source:Image=Image.load_from_file(str(path));check(source.detect_alpha()!=Image.ALPHA_NONE,"actual source has transparent background "+str(path))
		assets.append({"path":path,"source_sha256":FileAccess.get_sha256(str(path)),"width":source.get_width(),"height":source.get_height(),"has_mipmaps":image.has_mipmaps()})
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(directory+"editable-gallery.png"))==OK,"editable full gallery captured from actual GPU")
	FileAccess.open(directory+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures,"assets":assets,"scope":"art texture and editable preview only"},"  "))
	preview.queue_free();await process_frame;print("COMBINED_ARMS_ART ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)
