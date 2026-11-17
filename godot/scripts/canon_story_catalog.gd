extends RefCounted
const Data=preload("res://scripts/canon_story_data.gd")
const Service=preload("res://scripts/canon_story_service.gd")
static func render(app)->void:
	var service=Service.new(app.economy)
	app.panel(app.page,0,0,1600,900,Color("101e2a"))
	app.button(app.page,"‹ 返回",34,24,130,51,app.go_back)
	app.button(app.page,"母港",176,24,105,51,app.go_home)
	app.label(app.page,"第五小队 · 航海日志",65,114,1200,64,38,Color("edf2ee"))
	app.label(app.page,"翻开一章，再沿着她们走过的航线前进。",68,185,1350,44,21,Color("a8c3c8"))
	var titles:Array[String]=["借来的灯，自己的岸","不许熄灭的码头","把名字留在海上"]
	var covers:Array[String]=["res://assets/story/canon-v2/c1-rescue.png","res://assets/story/canon-v2/c2-waterline.png","res://assets/story/canon-v2/c3-white-tower.png"]
	for i in Data.IDS.size():
		var id:String=Data.IDS[i];var data:Dictionary=Data.chapter(id);var x:float=72+i*495
		var available:bool=i==0 or service.enabled() and bool(service.state().chapters.get(Data.IDS[i-1],{}).get("complete",false))
		app.panel(app.page,x,267,455,415,Color("1c3544"))
		if ResourceLoader.exists(covers[i]):app.picture(app.page,covers[i],x,267,455,305,true)
		app.label(app.page,"0%d"%(i+1),x+22,583,75,56,32,Color("e3c38b"))
		app.label(app.page,str(data.get("title",titles[i])),x+103,582,333,57,25,Color("eef3ef"))
		var button:Button=app.button(app.page,"继续航海日志" if available else "完成上一章后解锁",x,700,455,62,func():
			var response:Dictionary=service.select(id)
			if response.get("ok",false):app.show_page("canon_story")
			else:app.notify(response),available)
		button.disabled=not available or data.is_empty();button.name="CanonChapter_"+id
	app.button(app.page,"旧版章节与已有进度",73,812,430,50,func():app.show_page("story_catalog"))
	app.toast_label=app.label(app.page,"",535,817,1000,40,19,Color("eef4f3"))
