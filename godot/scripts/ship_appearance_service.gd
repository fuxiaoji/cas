extends RefCounted
## Cosmetic forms share an owned ship identity. They never alter CAS or growth.
const VERSION:String="ship-appearance-v1"
const VISUAL_FIELDS:Array[String]=["portrait","chibi","chibi_generated","chibi_poses","chibi_animations","atlas","animation_manifest"]
var account

func _init(owner)->void:
	account=owner

func variants(identity:String)->Array:
	return account._cards.get(identity,{}).get("appearance_variants",[])

func selected(identity:String)->String:
	var saved:String=str(account.state.get("appearance_v1",{}).get("selected",{}).get(identity,"base"))
	for row in options(identity):
		if str(row.id)==saved and bool(row.unlocked):return saved
	return "base"

func options(identity:String)->Array:
	var result:Array=[]
	var owned:bool=account.state.get("owned",{}).has(identity)
	var level:int=int(account.state.get("owned",{}).get(identity,{}).get("level",0))
	for raw in variants(identity):
		var row:Dictionary=raw.duplicate(true)
		row["unlocked"]=owned and level>=int(row.get("unlock_level",0))
		result.append(row)
	return result

func choose(identity:String,variant_id:String)->Dictionary:
	if not account.state.get("owned",{}).has(identity):return account._fail("先与这位舰娘建立归航档案")
	if not account.state.get("active_run",{}).is_empty():return account._fail("请返航后更换形象")
	var found:Dictionary={}
	for row in options(identity):
		if str(row.id)==variant_id:found=row;break
	if found.is_empty():return account._fail("没有这套形象")
	if not bool(found.unlocked):return account._fail("舰娘达到 Lv.%d 后解锁"%int(found.unlock_level))
	if selected(identity)==variant_id:return {"ok":true,"message":"已在使用这套形象"}
	var before:Dictionary=account.state.duplicate(true)
	account.state.get_or_add("appearance_v1",{"version":VERSION,"selected":{}})
	account.state.appearance_v1.selected[identity]=variant_id
	return account._commit(before,"已更换为「%s」"%str(found.get("name",variant_id)))

func visual(identity:String)->Dictionary:
	var source:Dictionary=account._cards.get(identity,{})
	var result:Dictionary=source.duplicate(true)
	var current:String=selected(identity)
	for row in variants(identity):
		if str(row.id)!=current:continue
		for field in VISUAL_FIELDS:
			if row.has(field):result[field]=row[field]
		result["appearance_id"]=current
		break
	return result

static func refresh(app)->void:
	if app.economy==null or app.economy.state.is_empty():return
	var service=load("res://scripts/ship_appearance_service.gd").new(app.economy)
	for identity in app.economy._cards:
		if service.variants(str(identity)).is_empty():continue
		var card:Dictionary=service.visual(str(identity))
		app.cards[str(identity)]=card
