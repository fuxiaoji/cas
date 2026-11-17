extends SceneTree
## Freeze the approved procedural coast as new, explicit simulation input.
const Source=preload("res://scripts/coastal_map_source_v1.gd")
const OUTPUT:String="res://data/coastal-demo-v1-714.json"
func _initialize()->void:call_deferred("run")
func run()->void:
	var seed_value:int=714
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):seed_value=int(argument.trim_prefix("--seed="))
	var source=Source.new(seed_value)
	var heights:Array[float]=[];var biomes:Array[String]=[];var water:Array[float]=[]
	for row:int in range(181):
		for column:int in range(181):
			var x:float=-360+column*4;var z:float=-360+row*4
			heights.append(roundf(source.height_at(x,z)*100.0)/100.0)
			biomes.append(source.biome_at(x,z))
			water.append(roundf(source.water_level_at(x,z)*100.0)/100.0)
	var geography:Dictionary={"version":"cas-coastal-geography-v1","id":"demo-coast-%d"%seed_value,"seed":seed_value,"heightfield":{"origin":{"x":14240,"y":12640},"cell_size_m":4,"columns":181,"rows":181,"heights":heights},"biomes":biomes,"water_levels":water}
	var output:String=OUTPUT if seed_value==714 else "res://data/coastal-demo-v1-%d.json"%seed_value
	var file=FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("Cannot freeze procedural geography");quit(1);return
	file.store_string(JSON.stringify(geography));file.close()
	print("COASTAL_GENERATOR ",JSON.stringify({"path":ProjectSettings.globalize_path(output),"seed":seed_value,"vertices":heights.size(),"size_m":720,"cell_size_m":4,"source":"approved_demo_algorithm","sha256":FileAccess.get_sha256(output),"authority":"input_pending_core_validation"}));quit(0)
