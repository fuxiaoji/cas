extends SceneTree
const OUTPUT:String="res://../artifacts/littoral-drag/"
var app
func _initialize()->void:call_deferred("run")
func shot(name:String)->void:
	await process_frame;await process_frame;RenderingServer.force_draw()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+name+".png"))
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var profile:String=OUTPUT+"isolated-layout-%d.json"%OS.get_process_id()
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://../artifacts/home-review/isolated-npc-64232.json"),ProjectSettings.globalize_path(profile))
	var economy=load("res://scripts/economy.gd").new(profile);economy.load_state()
	app=load("res://scenes/main.tscn").instantiate();app.economy=economy;app.boot_to_title=false;app.fullscreen_battle=false;root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app)
	await process_frame;app.set_process(false);app.page_motion=false
	var raw:String=FileAccess.get_file_as_string("res://../artifacts/home-review/npc-raid-save.json")
	app.core.request({"op":"replay","serialized":raw,"tick":90});app.show_page("battle");app.running=false;app.update_battle()
	await shot("sea-primary-layout")
	app.battle_controller.set_primary_map("land");await shot("land-primary-layout")
	app.core.close();app.queue_free();await process_frame;print("LITTORAL_LAYOUT captured real90s");quit()
