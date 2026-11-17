extends SceneTree
## Focused regression for the caption defect found in actual legacy compatibility play.
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run()->void:
	var app=load("res://scenes/main.tscn").instantiate()
	app.boot_to_title=false
	app.economy=load("res://scripts/economy.gd").new("user://tests/campaign-caption-%d.json"%OS.get_process_id())
	root.add_child(app);await process_frame;app.set_process(false)
	app.start_local_mode({"op":"new_campaign","id":"CAMP-ALLIES-02","difficulty":"standard","seed":6106,"profile":"coord"},{"mode":"campaign","id":"CAMP-ALLIES-02","difficulty":"standard","title":"埃斯佩兰斯角","side":"allies"})
	await process_frame;await process_frame
	await load("res://tests/transition_settle.gd").wait_for_route(self,app)
	check(app.screen=="battle" and str(app.core.view.campaign.stageId)=="CAMP-ALLIES-02","real selected historical campaign is active")
	check(app.core.view.ships.size()==9 and str(app.core.view.environment.light)=="night","nine borrowed allied hulls and night environment retained")
	var caption:Label=app.page.find_child("BattleSceneTitle",true,false)
	check(caption!=null and caption.is_visible_in_tree(),"campaign title is visibly present")
	var expected:String=str(app.core.view.campaign.missionLabel)
	check(caption.text==expected and expected.contains("埃斯佩兰斯角") and expected.contains("夜战"),"caption follows actual observed mission label")
	check(not caption.text.contains("5 对 5"),"historical campaign no longer claims an exercise")
	var output:=ProjectSettings.globalize_path("res://../artifacts/godot/legacy-v3-integration/")
	DirAccess.make_dir_recursive_absolute(output)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output+"10-campaign-title-corrected.png")==OK,"captured actual corrected title")
	var file:=FileAccess.open(output+"campaign-title-receipt.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"stage":app.core.view.campaign.stageId,"title":caption.text,"source_label":expected,"synthetic_battle_receipts":false},"  "));file.close()
	app.core.close();app.queue_free();await process_frame;await process_frame
	print("CAMPAIGN_CAPTION: %d/%d"%[checks-failures.size(),checks]);quit(0 if failures.is_empty() else 1)
