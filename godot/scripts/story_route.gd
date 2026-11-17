@tool
extends Control
const Design=preload("res://scripts/ui_design.gd")
const Content=preload("res://scripts/chapter_story_data.gd")
const Chapter=preload("res://scripts/chapter_presentation.gd")
var app
var selected:="rescue"
static func render(owner)->void:
	var scene=load("res://scenes/ui/story_route.tscn").instantiate()
	owner.page.add_child(scene);owner.page.move_child(scene,2);scene.bind(owner)
func _ready()->void:
	theme=Design.theme();$Hero.texture=load("res://assets/story/chapter1/gate.png")
	for label in find_children("*","Label",true,false):label.add_theme_color_override("font_color",Color("e0e8e8"))
	for label in [$ChapterHint,$Detail/Description,$Detail/Status]:label.add_theme_color_override("font_color",Color("a2b5bc"))
	$Detail/Type.add_theme_color_override("font_color",Color("e6c484"))
	$ChapterTitle.add_theme_color_override("font_color",Color.WHITE)
	$ChapterHint.add_theme_color_override("font_color",Color("d4e5e8"))
	Design.apply_button($Detail/Open,true);Design.apply_button($Detail/Continue,false,true)
	$Detail/Continue.add_theme_color_override("font_color",Color("dce5e5"))
	for state in ["normal","hover","pressed","focus"]:$Detail/Continue.add_theme_color_override("font_"+state+"_color",Color("dce5e5"))
	if Engine.is_editor_hint():
		var sample:Dictionary={"node":"rescue","seen":[],"cleared":{}}
		$Graph.bind(Content.data().scenes,sample,"rescue")
func bind(owner)->void:
	app=owner
	var saved:Dictionary=app.progression.chapter_status()
	var content:Dictionary=Content.data()
	$ChapterTitle.text={"chapter-01":"第一章","chapter-02":"第二章","chapter-03":"第三章"}.get(str(content.id),"")+"  /  "+str(content.title)
	$ChapterHint.text=str(content.get("hint","沿着返航灯，回到故事发生的海域"))
	$Hero.texture=load(str(content.get("cover","res://assets/story/chapter1/gate.png")))
	selected=str(app.get_meta("story_route_node",str(saved.node)))
	# New progress takes priority over the launch-node selection restored by page history.
	if str(app.get_meta("story_route_progress",str(saved.node)))!=str(saved.node):selected=str(saved.node)
	app.set_meta("story_route_progress",str(saved.node))
	var picked:Dictionary=Content.scene(selected)
	if picked.is_empty() or not _available(picked,saved):selected=str(saved.node)
	$Graph.node_selected.connect(_select)
	$Detail/Open.pressed.connect(_open)
	$Detail/Continue.pressed.connect(func():selected=str(app.progression.chapter_status().node);app.set_meta("story_route_node",selected);_open())
	_select(selected)
func _available(node:Dictionary,saved:Dictionary)->bool:
	return str(Content.scene(str(saved.node)).get("kind",""))=="complete" or str(node.id)==str(saved.node) or saved.seen.has(str(node.id)) or saved.cleared.has(str(node.get("stage","")))
func _select(id:String)->void:
	selected=id;app.set_meta("story_route_node",id)
	var node:Dictionary=Content.scene(id);var saved:Dictionary=app.progression.chapter_status()
	$Graph.bind(Content.data().scenes,saved,id)
	$Detail/Art.texture=load(Content.background_path(node))
	$Detail/Title.text=str(node.title)
	$Detail/Type.text={"dialogue":"故事片段","battle":"海上行动","guide":"母港导览","complete":"章节终章"}.get(str(node.kind),"故事")
	$Detail/Description.text=str(node.get("objective","第五驱逐小队的航海日志。")) if str(node.kind)=="battle" else "沿着返航灯，读懂沉没世界的线索。"
	var current:bool=id==str(saved.node)
	$Detail/Open.text="进入作战简报" if str(node.kind)=="battle" else "继续故事" if current else "回看片段"
	$Detail/Open.disabled=not _available(node,saved) or (str(node.kind) in ["guide","complete"] and not current)
	$Detail/Status.text="正在这里" if current else "已完成 · 可重访" if _available(node,saved) else "尚未抵达"
	$Detail/Continue.visible=not current
func _open()->void:
	var node:Dictionary=Content.scene(selected);var saved:Dictionary=app.progression.chapter_status()
	if node.is_empty() or not _available(node,saved):return
	Chapter._open_node(app,selected)
