extends SceneTree
var checks:int=0
var failures:Array=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func run()->void:
	var Content=preload("res://scripts/chapter_story_data.gd")
	for chapter in ["chapter-02","chapter-03"]:
		var content:Dictionary=Content.data(chapter)
		for node in content.scenes:
			var source:Resource=load("res://data/chapter-scenes/%s.tres"%str(node.id))
			check(source!=null and source.scene_id==str(node.id),"native editable authored node "+str(node.id))
			var copy:Resource=source.duplicate(true)
			copy.location="编辑副本"
			var path:="user://tests/%s-visual-copy.tres"%str(node.id)
			check(ResourceSaver.save(copy,path)==OK,"save editable copy "+str(node.id))
			var again:Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
			check(again!=null and again.location=="编辑副本" and again.lines.size()==source.lines.size(),"reload editable copy with dialogue "+str(node.id))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for key in ["fletcher","drayton","sanfrancisco","tideborn"]:
		var faces:SpriteFrames=load("res://assets/story/expressions-v2/%s-faces.tres"%key)
		for face in ["neutral","resolve","concern","talk","blink","hurt"]:
			var atlas:AtlasTexture=faces.get_frame_texture(face,0)
			check(atlas!=null and atlas.region.size==Vector2(512,512),"editable original-pixel expression "+key+" "+face)
	for scene in ["res://scenes/ui/story_catalog.tscn","res://scenes/ui/story_route.tscn","res://scenes/ui/monster_intel.tscn","res://scenes/chapter_stage.tscn"]:
		var node:Node=load(scene).instantiate();root.add_child(node)
		check(node!=null,"native editable scene "+scene)
		var packed:=PackedScene.new();check(packed.pack(node)==OK,"pack UI edit copy "+scene)
		var path:="user://tests/chapter-ui-copy.tscn"
		check(ResourceSaver.save(packed,path)==OK,"save native UI copy "+scene)
		check(ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)!=null,"reload native UI copy "+scene)
		node.free();DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var report:Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures}
	var output:=FileAccess.open("res://../artifacts/godot/chapters-two-three/editable-receipt.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"));output.close();print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
