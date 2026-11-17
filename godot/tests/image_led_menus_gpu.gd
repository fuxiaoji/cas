extends "res://tests/image_led_menus_review.gd"
## Render only this isolated process's viewport. No desktop capture or OS input.
var captures:Array=[]
var pointer_events:int=0
func _initialize()->void:
	directory="res://../artifacts/story-canon-v2/menus-gpu-%d/"%OS.get_process_id()
	review_scope="isolated off-screen GPU viewport screenshots, local Godot pointer navigation, actual committed draw economy; story CG previews are explicit fixtures, not earned progress or mobile-device acceptance"
	root.position=Vector2i(-10000,-10000)
	super._initialize()
func go(route:String)->bool:
	var ready:bool=await super.go(route)
	if ready:await shot(route+("-"+str(app.get_meta("activity_tab","overview")) if route=="activity" else ""))
	return ready
func shot(title:String)->void:
	await frames(6);await RenderingServer.frame_post_draw
	var file:String=directory+title+".png"
	var rendered:Image=root.get_texture().get_image()
	if check(rendered!=null and rendered.get_width()>0,"GPU viewport image "+title):
		check(rendered.save_png(ProjectSettings.globalize_path(file))==OK,"save own viewport "+title)
		captures.append(file)
func click(control:Control)->void:
	var point:Vector2=root.get_screen_transform()*(control.get_global_transform_with_canvas()*(control.size*.5))
	var down:=InputEventMouseButton.new();down.position=point;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;Input.parse_input_event(down)
	await process_frame
	var up:=InputEventMouseButton.new();up.position=point;up.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(up)
	pointer_events+=2;await frames(4)
func finish(before:Dictionary)->void:
	if is_instance_valid(app) and failures.is_empty():
		app.set_meta("activity_tab","overview")
		if await go("recruit"):
			await click(app.page.get_node("RecruitBanner/Pool_Standard"));await app.wait_for_page("recruit")
			check(str(app.get_meta("recruit_pool",""))=="standard","pointer selects standard pool")
			await shot("recruit-standard")
			await click(app.page.get_node("RecruitBanner/Pool_Tactical"));await app.wait_for_page("home_recruit")
			check(app.screen=="home_recruit","pointer selects tactical pool")
			var scene:Control=app.page.get_node("TacticalRecruit")
			await click(scene.get_node("Layout/FeaturedScroll/Featured").get_child(1))
			check(str(scene.focus_id)=="MCP-034","pointer changes tactical personality")
			await shot("tactical-second-personality")
		if await go("activity"):
			await click(app.page.get_node("ActivityHub/Tabs/Updates"));await app.wait_for_page("activity")
			check(str(app.get_meta("activity_tab",""))=="updates","pointer opens update category")
			await click(app.page.get_node("ActivityHub/Tabs/Overview"));await app.wait_for_page("activity")
			await click(app.page.get_node("ActivityHub/Editorial/Editorial_canon_catalog/Action"));await app.wait_for_page("canon_catalog")
			check(app.screen=="canon_catalog","pointer follows editorial story image")
			await shot("canon-catalog")
			# Keep this test's window off screen. The production story still enters
			# full screen; this flag only suppresses its OS switch in this process.
			app.fullscreen_story=true
			await click(app.page.get_node("CanonChapter_chapter-01"));await app.wait_for_page("canon_story")
			check(app.screen=="canon_story","pointer enters isolated new-canon chapter")
			var entered:Control=app.page.get_node("CanonStory")
			var service=load("res://scripts/canon_story_service.gd").new(app.economy)
			check(entered.reader.get_parent()==entered and not entered.reader.plain_text.is_empty(),"live dialogue reader attaches and starts authored text")
			entered.reader.elapsed=1000.0;entered.reader.text_label.visible_characters=-1
			var prior_line:int=int(service.chapter().line)
			await click(entered.get_node("StoryControls/ContinueStory"))
			check(int(service.chapter().line)==prior_line+1,"actual pointer continues authored dialogue once")
			check(entered.reader.get_parent()==entered,"replacement reader remains attached to same persistent stage")
			entered.reader.elapsed=1000.0;entered.reader.text_label.visible_characters=-1
			await shot("canon-entry")
			for fixture in [["chapter-01","v2c1-rent",3,"ship-form"],["chapter-01","v2c1-rent",5,"one-mind-crew"],["chapter-03","v2c3-many-hands",0,"one-mind-tactical"]]:
				service.state().selected=str(fixture[0]);service.chapter().node=str(fixture[1]);service.chapter().line=int(fixture[2])
				if not await super.go("canon_story"):break
				var story:Control=app.page.get_node("CanonStory")
				check(str(story.get_node("Backdrop").get_meta("asset","")).ends_with(str(fixture[3])+".png"),"new multi-body CG fixture resolves "+str(fixture[3]))
				check(story.reader.get_parent()==story,"dialogue reader belongs to its own current stage")
				# A render fixture reveals text without invoking the next-line action.
				story.reader.elapsed=1000.0;story.reader.text_label.visible_characters=-1
				await shot("cg-preview-"+str(fixture[3]))
		FileAccess.open(directory+"gpu-capture-index.json",FileAccess.WRITE).store_string(JSON.stringify({"renderer":RenderingServer.get_video_adapter_name(),"captures":captures,"pointer_events":pointer_events,"scope":"Own off-screen GPU viewport and injected local Godot pointer events; no desktop/user-window control"},"\t"))
	await super.finish(before)
