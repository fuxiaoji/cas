extends RefCounted
## A dismissible companion card. It never blocks clicks elsewhere or forces a transaction.
const Design=preload("res://scripts/ui_design.gd")
const Content=preload("res://scripts/chapter_story_data.gd")

static func render(app)->void:
	if app.screen in ["battle","story","chapter","result"]:return
	var saved:Dictionary=app.progression.chapter_status()
	if not bool(saved.get("guide_active",false)):return
	var guides:Array=Content.data().get("guide",[])
	var index:=int(saved.get("guide_index",0))
	if index<0 or index>=guides.size():return
	var guide:Dictionary=guides[index]
	var layer:=Control.new();layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	app.place(layer,app.page,0,0,1600,900)
	if bool(app.get_meta("chapter_guide_collapsed",false)):
		var expand:Button=app.button(layer,"展开导览 · %d / %d" % [index+1,guides.size()],55,100,300,48,func():_collapse(app,false))
		expand.set_meta("chapter_guide_expand",true)
		return
	app.panel(layer,55,154,540,308,Color(0.97,0.98,0.99,0.98))
	app.icon(layer,"story",78,178,33,33,Design.ACCENT)
	app.label(layer,str(guide.title),123,170,350,45,23,Design.INK)
	var collapse:Button=app.button(layer,"收起",483,175,88,42,func():_collapse(app,true))
	collapse.set_meta("chapter_guide_collapse",true)
	app.label(layer,str(guide.text),80,232,485,113,21,Design.MUTED)
	var route:=str(guide.route)
	var here:=str(app.screen)==route
	var next:Button=app.button(layer,"下一处" if here else "去看看",305,377,260,49,func():_advance(app) if here else app.show_page(route),true)
	next.set_meta("chapter_guide_next",true)
	app.button(layer,"结束导览",78,377,200,49,func():_close(app))
	app.label(layer,"%d / %d  ·  可收起后自由操作" % [index+1,guides.size()],83,435,445,25,17,Design.MUTED)

static func _collapse(app,collapsed:bool)->void:
	app.set_meta("chapter_guide_collapsed",collapsed)
	app.show_page(app.screen)

static func _advance(app)->void:
	var response:Dictionary=app.progression.chapter_move("guide_next")
	if not response.get("ok",false):app.notify(response);return
	var saved:Dictionary=app.progression.chapter_status()
	var guides:Array=Content.data().guide
	app.show_page(str(guides[int(saved.guide_index)].route) if bool(saved.guide_active) else "chapter")

static func _close(app)->void:
	var response:Dictionary=app.progression.chapter_move("guide_end")
	app.show_page(app.screen)
	if not response.get("ok",false):app.notify(response)
