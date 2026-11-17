extends SceneTree
const Art=preload("res://scripts/character_art.gd")
var failures:Array=[]
var checks:=0
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var rows:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
	if rows is Dictionary:rows=rows.get("ships",[])
	var cards:Dictionary={}
	for card in rows:cards[str(card.id)]=card
	var sources:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/v3/campaign-identity-audit.json"))
	var mappings:Dictionary={};var audit:Array=[]
	for row in sources.rows:
		var ship:Dictionary={"name":row.ship,"characterId":row.characterId,"classId":row.classId}
		var found:Dictionary=Art.resolve(cards,ship,false)
		var key:String=found.mapping;mappings[key]=int(mappings.get(key,0))+1
		check(not bool(found.representative),"no class representative projected as a named historical ship")
		if row.characterId!=null:check(found.identity==str(row.characterId),"explicit campaign identity retained")
		if not str(found.identity).is_empty():check(ResourceLoader.exists(str(found.card.portrait)),"resolved portrait exists")
		audit.append({"stage":row.stage,"ship":row.ship,"identity":found.identity,"mapping":key,"projection":Art.projection(found.card).kind})
	for name in Art.NAME_ALIASES:
		check(Art.resolve(cards,{"name":name},false).identity==Art.NAME_ALIASES[name],"source-backed alias "+name)
	var unknown:Dictionary=Art.resolve(cards,{"name":"未登记测试舰","classId":"fletcher"},false)
	check(unknown.identity=="" and unknown.mapping=="unmapped","unknown identity never inherits Fletcher's portrait")
	var counts:Dictionary={}
	for card in cards.values():
		var kind:String=Art.projection(card).kind;counts[kind]=int(counts.get(kind,0))+1
		check(kind!="none","every registered character has a usable own projection")
	var output:="res://../artifacts/v3/character-art-display-audit.json"
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"mappings":mappings,"projectionCounts":counts,"rows":audit},"  "));file.close()
	print("CHARACTER_ART: %d/%d %s %s"%[checks-failures.size(),checks,JSON.stringify(mappings),JSON.stringify(counts)])
	quit(0 if failures.is_empty() else 1)
