extends RefCounted
## A read-only source catalogue; these identities never enter the owned/playable roster.
const Design=preload("res://scripts/ui_design.gd")
const Art=preload("res://scripts/character_art.gd")
const SOURCE:String="res://data/carrier-pacific-source-v1.json"
const ART:String="res://data/carrier-art-v1.json"
static func data()->Dictionary:
	var result:Dictionary={"ships":[],"aircraft":[],"characters":{}}
	if FileAccess.file_exists(SOURCE):
		var source:Variant=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if source is Dictionary:
			result.ships=source.get("ships",[]);result.aircraft=source.get("aircraft",[])
	if FileAccess.file_exists(ART):
		var artwork:Variant=JSON.parse_string(FileAccess.get_file_as_string(ART))
		if artwork is Dictionary:
			for row in artwork.get("characters",[]):result.characters[str(row.get("id",""))]=row
	return result
static func open(app,back:Callable=Callable())->void:
	var content:Dictionary=data();var layer:Control=app.open_modal("航空资料馆 · 原页与本人美术");layer.name="HomeCarrierArchive"
	app.label(layer,"资料收录 · 尚未开放出战",380,205,810,42,24,Design.MUTED)
	var scroll:=ScrollContainer.new();scroll.name="CarrierArchiveScroll";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;app.place(scroll,layer,375,258,850,360)
	var strip:=VBoxContainer.new();strip.size_flags_horizontal=Control.SIZE_EXPAND_FILL;strip.add_theme_constant_override("separation",12);scroll.add_child(strip)
	for ship in content.ships:
		var id:String=str(ship.get("id",""));var art:Dictionary=content.characters.get(id,{})
		var button:=Button.new();button.name="Archive_"+id;button.custom_minimum_size=Vector2(810,94);button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.text=str(ship.get("name",id))+"\n原书资料 · 本人立绘 / 小人";button.icon=Art.texture(str(art.get("chibi","")));button.expand_icon=true;button.add_theme_constant_override("icon_max_width",78);Design.apply_button(button);strip.add_child(button)
		button.pressed.connect(func():character(app,id,back))
	var planes:=Label.new();planes.text="舰载机资料："+"、".join(content.aircraft.map(func(row):return str(row.get("name",""))));planes.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;planes.add_theme_font_size_override("font_size",19);strip.add_child(planes)
	app.button(layer,"返回岛务",380,652,810,64,func():back.call() if back.is_valid() else app.close_modal()).name="CarrierArchiveBack"
static func character(app,id:String,back:Callable=Callable())->void:
	var content:Dictionary=data();var own:Dictionary=content.characters.get(id,{});var ship:Dictionary={}
	for row in content.ships:
		if str(row.get("id",""))==id:ship=row;break
	if own.is_empty() or ship.is_empty():return
	var layer:Control=app.open_modal(str(ship.get("name",id))+" · 航空资料");layer.name="HomeCarrierCharacter";layer.set_meta("source_only",true);layer.set_meta("identity",id)
	var portrait:=TextureRect.new();portrait.name="SourceOnlyPortrait";portrait.texture=Art.texture(str(own.get("portrait","")));portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;app.place(portrait,layer,390,210,425,405)
	var sd:=TextureRect.new();sd.name="SourceOnlySD";sd.texture=Art.texture(str(own.get("chibi","")));sd.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;sd.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;app.place(sd,layer,890,235,225,205)
	var source:Dictionary=ship.get("source",{})
	app.label(layer,"资料收录 · 尚未开放出战\n"+str(own.get("costume","")),830,457,365,95,20,Design.MUTED)
	app.label(layer,"%s · PDF %s页 / 印刷 %s\n原页数值仅供查阅，未计入编成或招募。"%[str(source.get("book","")),str(source.get("pdf_page","")),str(source.get("printed_page",""))],830,560,365,74,18,Design.MUTED)
	app.button(layer,"返回资料馆",390,652,810,64,func():open(app,back)).name="BackCarrierArchive"
