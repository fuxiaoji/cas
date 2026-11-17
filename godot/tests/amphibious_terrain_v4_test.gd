extends SceneTree
const Terrain=preload("res://scripts/procedural_amphibious_terrain.gd")
var failures:Array=[]
func check(value:bool,label:String)->void:
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var polygon:PackedVector2Array=[Vector2(0,0),Vector2(800,50),Vector2(910,510),Vector2(600,790),Vector2(140,680),Vector2(-80,290)]
	var original:PackedVector2Array=polygon.duplicate();var start:int=Time.get_ticks_usec()
	var first:Dictionary=Terrain.terrain_data(polygon,4567)
	var build_ms:float=(Time.get_ticks_usec()-start)/1000.0
	check(not first.is_empty(),"runtime terrain generated")
	check(polygon==original,"visual generation preserves collision polygon")
	check(first.texture.get_width()<=256 and first.texture.get_height()<=256,"bounded distance-field resolution")
	var pixels:PackedByteArray=first.texture.get_image().get_data()
	Terrain.cache.clear();Terrain.order.clear()
	var repeat:Dictionary=Terrain.terrain_data(polygon,4567)
	check(pixels==repeat.texture.get_image().get_data(),"same seed and polygon reproduce exact terrain")
	var different:Dictionary=Terrain.terrain_data(polygon,4568)
	check(pixels!=different.texture.get_image().get_data(),"different seed produces different material relief")
	var generation_count:int=Terrain.generated_count
	for index in range(100):Terrain.terrain_data(polygon,4567)
	check(generation_count==Terrain.generated_count,"100 redraws reuse generated terrain")
	for decoration in first.decor:check(Geometry2D.is_point_in_polygon(decoration.at,polygon),"decoration remains on actual land")
	for seed in range(30):Terrain.terrain_data(polygon,seed)
	check(Terrain.cache.size()<=Terrain.CACHE_LIMIT,"terrain cache remains bounded")
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(pixels)
	var report:Dictionary={"failures":failures,"build_ms":build_ms,"dimensions":str(first.dimensions),"decorations":first.decor.size(),"sha256":digest.finish().hex_encode()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/combined-arms-v4"))
	var file=FileAccess.open("res://../artifacts/combined-arms-v4/terrain-test.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
