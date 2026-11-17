extends RefCounted
## One full-resolution picture is held at a time. Portrait identity stays explicit.
var app
var units:Array=[]
var index:int=0
var return_action:Callable
static func open(owner,identity:String="",back:Callable=Callable())->void:
	var gallery=load("res://scripts/home_cg_gallery.gd").new();gallery.app=owner;gallery.return_action=back
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-units-v1.json"))
	for unit in raw.get("units",[]):
		if ResourceLoader.exists("res://assets/tactical/defeat-cg-v1/"+str(unit.id)+".png"):gallery.units.append(unit)
	for i in range(gallery.units.size()):
		if str(gallery.units[i].id)==identity:gallery.index=i
	gallery._show()
func _leave()->void:
	app.close_modal()
	if return_action.is_valid():return_action.call()
func _show()->void:
	var layer:Control=app.open_modal("战术行动图鉴",_leave);layer.name="TacticalCGGallery";layer.set_meta("gallery_owner",self)
	# A cinematic frame covers the generic dialog, leaving global navigation clear.
	app.panel(layer,50,112,1500,768,Color("10232c"))
	app.label(layer,"战术行动图鉴",90,117,1400,36,25,Color("e4edf1"))
	if units.is_empty():app.label(layer,"作战图鉴素材准备中",400,300,800,80,28);return
	var unit:Dictionary=units[index]
	var artwork:=TextureRect.new();artwork.name="TacticalDefeatCG";artwork.texture=load("res://assets/tactical/defeat-cg-v1/"+str(unit.id)+".png");artwork.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;artwork.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;app.place(artwork,layer,90,154,1420,570)
	app.label(layer,str(unit.get("name",unit.id))+" · "+str(unit.get("designation","")),190,728,1210,38,26,Color("e4edf1"))
	app.label(layer,"抢滩失利 · 同一人格的多个女性机器人身体  %d / %d"%[index+1,units.size()],190,766,1210,25,18,Color("a6bdc8"))
	app.button(layer,"上一支",90,795,300,58,func():index=(index-1+units.size())%units.size();_show()).name="PreviousTacticalCG"
	app.button(layer,"返回",410,795,780,58,_leave,true).name="CloseTacticalCG"
	app.button(layer,"下一支",1210,795,300,58,func():index=(index+1)%units.size();_show()).name="NextTacticalCG"
