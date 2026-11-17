@tool
extends Control
## Chapter covers are navigation, never a second source of progression truth.
const Design=preload("res://scripts/ui_design.gd")
const Content=preload("res://scripts/chapter_story_data.gd")
var app
static func render(owner)->void:
	var scene=load("res://scenes/ui/story_catalog.tscn").instantiate()
	owner.page.add_child(scene);owner.page.move_child(scene,2);scene.bind(owner)
func _ready()->void:
	theme=Design.theme()
	$Atmosphere.texture=load("res://assets/story/chapter1/gate.png")
	$FutureA.texture=load("res://assets/story/chapter2/causeway.png")
	$FutureB.texture=load("res://assets/story/chapter3/storm.png")
	$Cover.texture=load("res://assets/story/chapter1/rescue.png")
	$Legacy/Art.texture=load("res://assets/story/chapter1/deck-storm-v1.png")
	for label in find_children("*","Label",true,false):label.add_theme_color_override("font_color",Color("e0e7e7"))
	for label in [$ShelfLabel,$Progress,$FutureCaptionA,$FutureCaptionB]:label.add_theme_color_override("font_color",Color("90a8ad"))
	Design.apply_button($Open,true);Design.apply_button($Legacy/Enter,false,true)
	$Legacy/Enter.add_theme_color_override("font_color",Color("dce5e5"))
	for state in ["normal","hover","pressed","focus"]:$Legacy/Enter.add_theme_color_override("font_"+state+"_color",Color("dce5e5"))
func bind(owner)->void:
	app=owner
	var saved:Dictionary=app.progression.chapter_status()
	var node:Dictionary=Content.scene(str(saved.node))
	$Progress.text="已完成 · "+str(Content.data().title) if str(node.kind)=="complete" else "上次停在 · "+str(node.title)
	$Open.text="查看章节路线"
	$Open.pressed.connect(func():_enter("chapter-01"))
	for pair in [["chapter-02",$Chapter2Open,$FutureA],["chapter-03",$Chapter3Open,$FutureB]]:
		var id:String=pair[0];var button:Button=pair[1];var art:TextureRect=pair[2]
		var unlocked:bool=app.progression.chapter_unlocked(id)
		button.disabled=not unlocked;button.text="查看章节路线" if unlocked else "完成上一章解锁"
		Design.apply_button(button,unlocked)
		art.modulate=Color.WHITE if unlocked else Color(.4,.45,.5,.75)
		button.pressed.connect(func():_enter(id))
	$Legacy/Enter.pressed.connect(func():app.show_page("story"))

func _enter(id:String)->void:
	var response:Dictionary=app.progression.chapter_select(id)
	if not response.get("ok",false):app.notify(response);return
	var saved:Dictionary=app.progression.chapter_status()
	app.set_meta("story_chapter_id",id);app.set_meta("story_route_node",str(saved.node))
	app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line")
	app.show_page("story_route")
