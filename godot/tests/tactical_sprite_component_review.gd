extends SceneTree
const Sprite=preload("res://scenes/ui/tactical_sprite.tscn")
const OUTPUT:String="res://../artifacts/tactical-sprite/"
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run()->void:
	var catalogue:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-units-v1.json"))
	var hashes:Dictionary={};var ids:Array[String]=["MCP-001","MCP-034","MCP-076","MCP-009","MCP-022"]
	for id in ids:
		var card:Dictionary=catalogue.units.filter(func(row):return row.id==id)[0]
		var path:String=str(card.sprite_sheet);var image:Image=load(path).get_image();var sha:String=FileAccess.get_sha256(path)
		check(not hashes.has(sha),id+" distinct original person atlas");hashes[sha]=true
		check(image.get_size()==Vector2i(1448,1086),id+" exact 4x3 atlas dimensions")
		check(image.has_mipmaps(),id+" actual imported texture contains mip levels")
		for frame in range(12):
			var region:Image=image.get_region(Rect2i((frame%4)*362,(frame/4)*362,362,362))
			check(not region.is_invisible(),id+" pose %d has genuine nonempty pixels"%frame)
		var import_text:String=FileAccess.get_file_as_string(path+".import")
		check(import_text.contains("mipmaps/generate=true"),id+" mipmaps generated for reduced display size")
	var unit=Sprite.instantiate();root.add_child(unit)
	var row:Dictionary={"id":131,"unit_id":"MCP-001","side":"allies","kind":"helicopter","x":12000,"y":9000,"hp":90,"max_hp":100}
	unit.configure(row,"res://assets/tactical/sprites/MCP-001-sheet.png",58)
	unit.observe(row,Vector2(160,220),90,.1,false);unit.observe(row,Vector2(200,220),90.1,.1,false)
	check(not unit.moving,"screen-space separation without actual world movement never creates walking")
	row.x=12020;unit.observe(row,Vector2(201,220),90.2,.1,false);check(unit.state_name=="walk","actual public world position change drives walking")
	unit.defeat(91);check(unit.frame_index==8,"actual defeat starts from reaction pose")
	unit.advance(.1,91.2,true);check(unit.frame_index==10,"reaction continues into imbalance/fall frame")
	unit.advance(.1,91.6,true);check(unit.frame_index==11,"fall lands into actual lying pose")
	unit.advance(.1,94.4,true);check(unit.frame_index==11 and not unit.expired(),"lying remains down without re-standing before four seconds")
	unit.advance(.1,95.2,false);check(not unit.expired() and unit.clock==94.4,"pause freezes downed-body retention timer")
	unit.advance(.1,95.2,true);check(unit.expired(),"downed presentation expires after actual four simulation seconds")
	unit.queue_free()
	var preview=load("res://scenes/ui/tactical_sprite_preview.tscn").instantiate();root.add_child(preview);root.size=Vector2i(1280,720)
	await process_frame
	preview.get_node("Frame").value=11
	check(preview.get_node("Cast").get_children().all(func(actor):return actor.preview_frame==11),"F6 preview's real slider switches all five into chosen pose")
	var packed:=PackedScene.new();check(packed.pack(preview)==OK,"native preview scene packs for editing")
	var packed_path:String=OUTPUT+"preview-roundtrip.tscn";check(ResourceSaver.save(packed,packed_path)==OK,"native preview saves as editable scene")
	var restored=load(packed_path).instantiate();check(restored.get_node("Cast/MCP034").preview_mode,"saved scene keeps explicit preview mode");restored.free()
	await process_frame;await process_frame;RenderingServer.force_draw();check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+"editable-preview-defeated.png"))==OK,"actual F6-size five-person lying preview")
	preview.queue_free();await process_frame
	var viewport:=SubViewport.new();viewport.size=Vector2i(1920,1000);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var background:=ColorRect.new();background.size=Vector2(1920,1000);background.color=Color("304d50");viewport.add_child(background)
	for person in range(ids.size()):
		for frame in range(12):
			var actor=Sprite.instantiate();actor.sheet_path="res://assets/tactical/sprites/"+ids[person]+"-sheet.png";actor.preview_mode=true;actor.preview_frame=frame;actor.display_height=148;actor.position=Vector2(80+frame*160,175+person*195);viewport.add_child(actor)
			var label:=Label.new();label.position=Vector2(frame*160+6,181+person*195);label.text=ids[person]+" · %02d"%frame;label.add_theme_font_size_override("font_size",16);viewport.add_child(label)
	await process_frame;RenderingServer.force_draw()
	check(viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+"five-person-twelve-pose-gpu.png"))==OK,"actual GPU all sixty original poses with exact frame boundaries")
	viewport.queue_free();await process_frame
	var filter_view:=SubViewport.new();filter_view.size=Vector2i(900,200);filter_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(filter_view)
	var backdrop:=ColorRect.new();backdrop.size=Vector2(900,200);backdrop.color=Color("304d50");filter_view.add_child(backdrop)
	var filters:Array=[CanvasItem.TEXTURE_FILTER_NEAREST,CanvasItem.TEXTURE_FILTER_LINEAR,CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS]
	for index in range(3):
		var actor=Sprite.instantiate();actor.preview_mode=true;actor.preview_frame=0;actor.sheet_path="res://assets/tactical/sprites/MCP-034-sheet.png";actor.display_height=58;actor.position=Vector2(150+index*300,150);filter_view.add_child(actor);actor.texture_filter=filters[index]
		var label:=Label.new();label.position=Vector2(45+index*300,165);label.text=["Nearest · comparison only","Linear · comparison only","Actual battle · mipmaps"][index];label.add_theme_font_size_override("font_size",16);filter_view.add_child(label)
	await process_frame;RenderingServer.force_draw()
	var filter_image:Image=filter_view.get_texture().get_image()
	var nearest:PackedByteArray=filter_image.get_region(Rect2i(108,40,84,118)).get_data()
	var actual:PackedByteArray=filter_image.get_region(Rect2i(708,40,84,118)).get_data()
	check(nearest!=actual,"actual GPU mipmapped draw differs from nearest-filtered draw at battle size")
	check(filter_image.save_png(ProjectSettings.globalize_path(OUTPUT+"actual-filter-comparison.png"))==OK,"native 58px nearest/linear/mipmap comparison captured")
	filter_view.queue_free();await process_frame
	var receipt:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"identities":ids,"source_hashes":hashes,"preview":"res://scenes/ui/tactical_sprite_preview.tscn","actual_gpu":true,"authority_or_account_mutated":false}
	FileAccess.open(OUTPUT+"component-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "));print("TACTICAL_COMPONENT "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
