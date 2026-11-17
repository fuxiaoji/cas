extends Control
## Only the authoritative search clock reveals progress and each individual item.
var app
var title:Label
var progress:ProgressBar
var scanning:=false
var known:=0
var last_progress:=0
var revealed:=0
var ruin_id:=-1
func _ready()->void:
	title=$Title;progress=$Progress
	if not is_instance_valid(app):return
	$Cancel.pressed.connect(func():app.issue({"op":"cancel_search"}))
	for icon in $Found.get_children():icon.modulate=Color(.42,.56,.6,.35)
	known=app.core.view.get("salvage",{}).get("cargo_grid",{}).get("items",[]).size()
	visible=false
func _process(_delta:float)->void:
	if not is_instance_valid(app):return
	var salvage:Dictionary=app.core.view.get("salvage",{})
	var search:Variant=salvage.get("search")
	visible=search is Dictionary
	if visible:
		if int(search.ruin)!=ruin_id:ruin_id=int(search.ruin);revealed=0
		progress.max_value=int(search.duration);progress.value=int(search.progress)
		title.text="搜索遗迹  ·  已发现 %d 件"%int(search.revealed)
		last_progress=int(search.progress)
		var found:Array=salvage.get("cargo_grid",{}).get("items",[]).filter(func(item):return int(item.ruin)==int(search.ruin))
		var total:int=int({"calm":4,"standard":5,"hazard":6}.get(str(salvage.get("difficulty","calm")),4))
		for i in range($Found.get_child_count()):
			var icon:TextureRect=$Found.get_child(i)
			icon.visible=i<total
			var item:Dictionary={}
			for value in found:
				if str(value.id).ends_with("-%d"%i):item=value;break
			icon.texture=load(load("res://scripts/cargo_service.gd").art_path(item)) if not item.is_empty() else preload("res://assets/items/scrap.png")
			icon.modulate=Color.WHITE if not item.is_empty() else Color(.2,.3,.4,.12)
		if int(search.revealed)>revealed:
			var index:=mini(int(search.revealed)-1,5);var icon:Control=$Found.get_child(index)
			icon.pivot_offset=icon.size/2.0;icon.scale=Vector2.ONE*.78
			create_tween().tween_property(icon,"scale",Vector2.ONE,.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		revealed=int(search.revealed)
	var count:int=salvage.get("cargo_grid",{}).get("items",[]).size()
	if scanning and not visible and count>known:app.notify({"ok":true,"message":"搜索完成 · 打开货舱选择并装载物资"})
	known=count;scanning=visible
