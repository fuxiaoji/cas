extends SceneTree
const Art=preload("res://scripts/character_art.gd")
const Impact=preload("res://scripts/combat_impact.gd")
var checks:int=0
var failures:Array[String]=[]

func check(ok:bool, message:String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
	var cards:Dictionary={}
	for card:Dictionary in source.ships:cards[str(card.id)]=card
	var missouri:Dictionary=cards["IBS-U-USN-ERMA-MISSOURI"]
	check(str(missouri.class_id)=="us_iowa_bb_1943" and int(missouri.points)==3250,"Missouri historical identity and points remain intact")
	var portrait:Texture2D=Art.texture(str(missouri.portrait))
	check(portrait!=null,"new Missouri portrait imports")
	if portrait!=null:
		var pixels:Image=portrait.get_image()
		check(pixels.get_pixel(0,0).a==0.0 and pixels.get_pixel(pixels.get_width()-1,0).a==0.0,"portrait corner alpha is transparent")
	check(Art.projection(missouri).kind=="generated_chibi","default resolves a same-person generated SD")
	check(missouri.get("appearance_variants",[]).size()==2,"limited UR has two exact-person appearances")
	for variant:Dictionary in missouri.get("appearance_variants",[]):
		check(int(variant.unlock_level)==(20 if str(variant.id)=="military" else 0),"appearance unlock data is explicit: "+str(variant.id))
		check(Art.texture(str(variant.portrait))!=null,"appearance portrait imports: "+str(variant.id))
		var appearance:Dictionary=missouri.duplicate(true)
		for field:String in ["chibi","chibi_generated","chibi_poses","chibi_animations"]:appearance[field]=variant[field]
		check(appearance.chibi_poses.size()==12,"appearance includes twelve matching poses: "+str(variant.id))
		for pose:String in appearance.chibi_poses:
			var frame:Texture2D=Art.pose_texture(appearance,pose)
			check(frame is AtlasTexture,"appearance pose imports: "+str(variant.id)+"/"+pose)
			if frame is AtlasTexture:
				var atlas:AtlasTexture=frame
				check(Rect2(Vector2.ZERO,atlas.atlas.get_size()).encloses(atlas.region),"appearance region remains inside source: "+str(variant.id)+"/"+pose)
	for pose:String in missouri.get("chibi_poses",{}):
		var frame:Texture2D=Art.pose_texture(missouri,pose)
		check(frame is AtlasTexture,"pose imports as an editable AtlasTexture: "+pose)
		if frame is AtlasTexture:
			check(frame.get_width()>0 and frame.get_height()>0,"pose has nonempty geometry: "+pose)
			var atlas:AtlasTexture=frame
			check(Rect2(Vector2.ZERO,atlas.atlas.get_size()).encloses(atlas.region),"pose region stays inside atlas: "+pose)
	check(Art.pose_texture(missouri,"walk",0.0)!=Art.pose_texture(missouri,"walk",.3),"walking samples alternate feet")
	var other:Dictionary=cards["IBS-U-USN-FLETCHER"]
	check(Art.pose_texture(other,"walk",.3)==Art.texture(str(Art.projection(other).path)),"characters without pose atlas retain exact existing fallback")
	Art.trigger_pose(other,"fire",.3)
	check(Art.active_pose(other)=="idle","no pose event is invented for other characters")
	var impact:=Impact.new()
	impact.catalog=cards
	var ship:Dictionary={"id":10,"characterId":"IBS-U-USN-ERMA-MISSOURI","classId":"us_iowa_bb_1943","x":0.0,"y":0.0,"heading":0.0}
	impact.fire(ship,{"x":0.0,"y":0.0})
	check(Art.active_pose(missouri)=="fire","actual fire feedback triggers firing pose")
	impact.hurt(ship,.05)
	check(Art.active_pose(missouri)=="hit","actual damage triggers hit pose")
	impact.reset()
	impact.hurt(ship,0.0)
	check(Art.active_pose(missouri)=="idle","zero damage does not trigger a hit pose")
	Art.trigger_pose(missouri,"fire",.01)
	OS.delay_msec(25)
	check(Art.active_pose(missouri)=="idle","expired action returns to idle")
	check(Art.active_pose(missouri,true)=="walk","moving selects walk after action ends")
	var asleep:Dictionary=missouri.duplicate(true)
	asleep["chibi_pose"]="lie-side"
	check(Art.active_pose(asleep)=="lie-side","scripted rest pose is available without changing simulation")
	for asset:String in ["c1-rescue.png","c2-waterline.png","c3-white-tower.png","shinano-hologram.png","shinano-silhouette.png","missouri_home.png","missouri_awakening.png","missouri-limited-banner.png","missouri-uniform-portrait.png"]:
		check(Art.texture("res://assets/story/canon-v2/"+asset)!=null,"story asset imports: "+asset)
	var report:Dictionary={"checks":checks,"failures":failures,"account_services_started":false,"combat_rules_changed":false,"gpu_visual_review_performed":false}
	var output:=FileAccess.open("res://../artifacts/canon-v2-art/resource-review.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	print("CANON_V2_ART %d/%d"%[checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
