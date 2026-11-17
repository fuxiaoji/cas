extends RefCounted
## An independent, transactional island ledger. Historical fleets are never rewritten.
const VERSION:String="cas-home-v1"
const BATTLE_VERSION:String="cas-littoral-v4"
const V3_BATTLE_VERSION:String="cas-littoral-v3"
const PREVIOUS_BATTLE_VERSION:String="cas-littoral-v2"
const LEGACY_BATTLE_VERSION:String="cas-littoral-v1"
const BATTLE_VERSIONS:Array[String]=[LEGACY_BATTLE_VERSION,PREVIOUS_BATTLE_VERSION,V3_BATTLE_VERSION,BATTLE_VERSION]
const PROFILES:String="res://data/tactical-profiles-v3.json"
const COMPANY_PROFILES:String="res://data/tactical-profiles-v4.json"
const COMPANY_LAYOUT:String="multi-company-v1"
const TRAINING_SHIPS:Array[String]=["IBS-U-USN-ERMA-IOWA","IBS-U-IJN-NISSHIN"]
const V4_TRAINING_SHIPS:Array[String]=["IBS-U-USN-ERMA-IOWA","CAS-O-LHA-RETURNLIGHT"]
const AVIATION_CATALOG:String="res://data/combined-arms-ships-v4.json"
const Core=preload("res://scripts/core_bridge.gd")
const Development=preload("res://scripts/home_development.gd")
const IslandWar=preload("res://scripts/home_island_war.gd")
const IslandWarV2=preload("res://scripts/home_island_war_v2.gd")
const IslandWarV3=preload("res://scripts/home_island_war_v3.gd")
const IslandWarV4=preload("res://scripts/home_island_war_v4.gd")
const ISLAND_V4_VERSION:String="cas-island-war-v4"
const ISLAND_V4_DATA:String="res://data/island-war-v4-published.json"
const ISLAND_V3_VERSION:String="cas-island-war-v3"
const ISLAND_V3_DATA:String="res://data/island-war-v3.json"
const ISLAND_VERSION:String="cas-island-war-v1"
const ISLAND_V2_VERSION:String="cas-island-war-v2"
const ISLAND_V2_DATA:String="res://data/island-war-v2.json"
const ART_V2_DATA:String="res://data/tactical-art-v2.json"
const CATALOG:String="res://data/tactical-units-v1.json"
const GRID:Vector2i=Vector2i(12,9)
const RESOURCE_CAP:int=20000
const OFFLINE_CAP:int=28800
const DRAW_PRICE:int=160
const LEGACY_RELEASED:Array[String]=["MCP-001","MCP-034","MCP-076","MCP-009","MCP-022"]
const RELEASED:Array[String]=["MCP-001","MCP-034","MCP-076","MCP-009","MCP-022","MCP-011","MCP-018","MCP-027","MCP-041","MCP-052","MCP-063","MCP-087","MCP-103","MCP-116","MCP-128","MCP-145","MCP-167","MCP-184","MCP-203","MCP-240"]
const NPC_ISLANDS:Array=[
	{"name":"碎波哨岛","seed":18031,"description":"均衡哨岛 · 岸炮与仓库","layout":[["hq",.55,.52,1],["turret",.38,.68,1],["aa",.66,.43,1],["depot",.48,.36,1]]},
	{"name":"旧港仓岛","seed":29143,"description":"旧港补给站 · 仓库密集","layout":[["hq",.48,.50,1],["turret",.33,.63,1],["depot",.59,.44,1],["depot",.65,.59,1],["depot",.40,.37,1]]},
	{"name":"长云堡礁","seed":37057,"description":"堡礁驻地 · 防空与岸防","layout":[["hq",.55,.46,2],["turret",.35,.62,2],["turret",.69,.61,1],["aa",.42,.44,2],["aa",.65,.37,2],["depot",.55,.65,1]]}
]
const RESOURCE_NAMES:Dictionary={"scrap":"浮材","alloy":"合金","energy":"能源","protocols":"协议片","credits":"岛屿补给"}
const BUILDINGS:Dictionary={
	"hq":{"name":"联络中枢","icon":"radar","cost":{"scrap":160,"alloy":100},"limit":1,"description":"保存岛权与防守指挥。"},
	"recycler":{"name":"浮材回收站","icon":"cargo","cost":{"scrap":60,"alloy":25},"limit":3,"produces":"scrap","hourly":18,"description":"从洋流回收可用浮材。"},
	"forge":{"name":"合金工坊","icon":"gear","cost":{"scrap":80,"alloy":40},"limit":3,"produces":"alloy","hourly":12,"description":"精炼残骸，为建设提供合金。"},
	"solar":{"name":"潮汐电站","icon":"spark","cost":{"scrap":50,"alloy":25},"limit":3,"produces":"energy","hourly":15,"description":"利用海潮与日照稳定供能。"},
	"medical":{"name":"协议医疗站","icon":"repair","cost":{"scrap":100,"alloy":65,"energy":35},"limit":1,"description":"加快人格编制恢复，核心永不消失。"},
	"turret":{"name":"岸防炮塔","icon":"target","cost":{"scrap":90,"alloy":70,"energy":20},"limit":5,"description":"入侵演练中真实射击，升级增加火力。"},
	"aa":{"name":"防空哨站","icon":"radar","cost":{"scrap":80,"alloy":60,"energy":25},"limit":3,"description":"保护岛屿，压制空中威胁。"},
	"depot":{"name":"补给仓库","icon":"crate","cost":{"scrap":75,"alloy":45},"limit":2,"description":"存放本岛补给，不影响母港仓库。"},
	"dock":{"name":"停泊船坞","icon":"anchor","cost":{"scrap":120,"alloy":85},"limit":2,"description":"让驻防舰娘停泊待命，接敌后起锚。"},
	"machine_gun":{"name":"近防机枪堡","icon":"target","cost":{"scrap":100,"alloy":75,"energy":30},"limit":5,"unlock_level":1,"description":"快速压制登陆轻步兵，近距离连续火力。"},
	"mortar":{"name":"曲射迫击阵地","icon":"target","cost":{"scrap":150,"alloy":120,"energy":50},"limit":3,"unlock_level":2,"description":"曲射范围压制，适合对付密集登陆部队。"},
	"anti_ship":{"name":"海防导弹阵地","icon":"target","cost":{"scrap":220,"alloy":180,"energy":90},"limit":2,"unlock_level":3,"description":"远程海防阵地，压制入侵舰队与近岸投送。"},
	"repair_tower":{"name":"战地整备节点","icon":"repair","cost":{"scrap":180,"alloy":140,"energy":80},"limit":2,"unlock_level":2,"description":"为附近防御设施提供真实有限修复支援。"}
}
var account
var catalogue:Array=[]
var profiles:Dictionary={}
var ship_profiles:Dictionary={}
var aviation_ships:Array=[]
var company_cards:Dictionary={}
var company_rules:Dictionary={}
var v2_data:Dictionary={}
var v2_cards:Dictionary={}
var v2_art:Dictionary={}
var v3_data:Dictionary={}
var v3_cards:Dictionary={}
var v3_weapons:Dictionary={}
var v4_data:Dictionary={}
var v4_cards:Dictionary={}
var v4_weapons:Dictionary={}
var v4_art:Dictionary={}
var geometry_adapter

func _init(owner)->void:
	account=owner
	if FileAccess.file_exists(CATALOG):
		var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if raw is Dictionary:catalogue=raw.get("units",[])
		elif raw is Array:catalogue=raw
	if FileAccess.file_exists(PROFILES):
		var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(PROFILES))
		var rows:Array=data.get("cards",data.get("units",[])) if data is Dictionary else data if data is Array else []
		for row in rows:
			if row is Dictionary:profiles[str(row.get("id",""))]=row
		if data is Dictionary:
			for row in data.get("ships",[]):
				if row is Dictionary:ship_profiles[str(row.get("id",""))]=row
	if FileAccess.file_exists(AVIATION_CATALOG):
		var extra:Variant=JSON.parse_string(FileAccess.get_file_as_string(AVIATION_CATALOG))
		if extra is Dictionary:aviation_ships=extra.get("ships",[])
	if FileAccess.file_exists(COMPANY_PROFILES):
		var expanded:Variant=JSON.parse_string(FileAccess.get_file_as_string(COMPANY_PROFILES))
		if expanded is Dictionary:
			company_rules=expanded.get("multi_company",{})
			for row in expanded.get("cards",[]):company_cards[str(row.get("id",""))]=row
	if FileAccess.file_exists(ISLAND_V2_DATA):
		var latest:Variant=JSON.parse_string(FileAccess.get_file_as_string(ISLAND_V2_DATA))
		if latest is Dictionary:
			v2_data=latest
			for row in latest.get("cards",[]):
				if row is Dictionary:v2_cards[str(row.get("id",""))]=row
	if FileAccess.file_exists(ISLAND_V3_DATA):
		var newest:Variant=JSON.parse_string(FileAccess.get_file_as_string(ISLAND_V3_DATA))
		if newest is Dictionary:
			v3_data=newest
			for row in newest.get("cards",[]):v3_cards[str(row.get("id",""))]=row
			for row in newest.get("weapons",[]):v3_weapons[str(row.get("id",""))]=row
	if FileAccess.file_exists(ART_V2_DATA):
		var artwork:Variant=JSON.parse_string(FileAccess.get_file_as_string(ART_V2_DATA))
		if artwork is Dictionary:
			for row in artwork.get("units",[]):
				if row is Dictionary:v2_art[str(row.get("id",""))]=row
	var v4_path:String="res://data/island-war-v4.json" if OS.get_environment("CAS_SIXTH_INFANTRY_PREVIEW")=="1" else ISLAND_V4_DATA
	if FileAccess.file_exists(v4_path):
		var next:Variant=JSON.parse_string(FileAccess.get_file_as_string(v4_path))
		if next is Dictionary and str(next.get("version",""))==ISLAND_V4_VERSION:
			v4_data=next
			for row in next.get("cards",[]):v4_cards[str(row.get("id",""))]=row
			for row in next.get("weapons",[]):v4_weapons[str(row.get("id",""))]=row
	if FileAccess.file_exists("res://data/tactical-art-v4.json"):
		var extra_art:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-art-v4.json"))
		if extra_art is Dictionary:
			var rows:Variant=extra_art.get("units",[])
			if rows is Dictionary:v4_art=rows
			elif rows is Array:
				for row in rows:v4_art[str(row.get("id",""))]=row
	if FileAccess.file_exists("res://data/home-daily-art-v1.json"):
		var daily:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/home-daily-art-v1.json"))
		if daily is Dictionary and daily.get("units") is Dictionary:
			for id in daily.units:
				var art:Dictionary=daily.units[id]
				if not str(id).begins_with("MCP-") or not bool(art.get("approved",false)):continue
				var visual:Dictionary={}
				for field in ["portrait","sprite_sheet","frames","animations","timing"]:
					if art.has(field):visual[field]=art[field]
				v4_art.get_or_add(str(id),{}).merge(visual,true)
	ensure()

func company_layout(id:String)->Dictionary:return company_cards.get(id,{}).get("company_layout",{}).duplicate(true)

func naval_roster()->Array:return account.roster()

func procure_ship(id:String,request_id:String="")->Dictionary:
	if not _idle():return _fail("请先返航，再接收新舰")
	var replay:Dictionary=account._request(request_id,["combined_arms_procure",id])
	if not replay.is_empty():return replay
	var card:Dictionary={}
	for item in aviation_ships:
		if str(item.get("id",""))==id:card=item;break
	if card.is_empty() or not account._cards.has(id):return _fail("该舰尚未进入本版海陆空舰表")
	if account.state.owned.has(id):return _fail("这位舰娘已经到港")
	var price:int=int(card.get("price_origins",0))
	if price<=0 or int(account.state.wallet.get("origins",0))<price:return _fail("元词不足")
	var before:Dictionary=account.state.duplicate(true)
	account.state.wallet.origins=int(account.state.wallet.origins)-price
	account.state.owned[id]=account._new_owned(id)
	return _commit(before,str(card.name)+"已到港 · 海陆空行动专用",{"ship_id":id,"cost":{"origins":price}})

func _now()->int:return int(Time.get_unix_time_from_system())

func ensure()->void:
	if account.state.is_empty():return
	account.state.get_or_add("home_v1",{"version":VERSION,"unlocked":false,"tutorial_complete":false,"seed":1387249,"resources":{"scrap":220,"alloy":160,"energy":80,"protocols":0,"credits":0},"buildings":[{"id":"home-hq","kind":"hq","cell":{"x":6,"y":4},"level":1}],"building_sequence":1,"last_collect":_now(),"carry":{},"garrison":[],"units":{},"tickets":0,"rng":73416391,"pity":0,"draw_sequence":0,"draw_history":[],"last_draw":[],"records":[],"care_at":{}})
	var home:Dictionary=account.state.home_v1
	home.get_or_add("care_at",{});home.get_or_add("carry",{});home.get_or_add("last_draw",[]);home.get_or_add("tactical_garrison",[])
	for key in RESOURCE_NAMES:home.resources.get_or_add(key,0)

func _idle()->bool:return account.state.get("active_run",{}).is_empty()
func _fail(message:String)->Dictionary:return account._fail(message)
func _commit(before:Dictionary,message:String,extra:Dictionary={})->Dictionary:return account._commit(before,message,extra)
func state()->Dictionary:ensure();return account.state.home_v1
func development(read_only:bool=false):return Development.new(self,read_only)
func island_profile()->Dictionary:return development().island_profile()
func storage_profile()->Dictionary:return development().storage_profile()
func buildable(cell:Vector2i)->bool:return development().buildable(cell)
func tactical_profile(id:String)->Dictionary:return development().unit_profile(id)
func replay_record(run_id:String)->Dictionary:return development().replay_record(run_id)
func conflict_records()->Array:return development().records()
func npc_islands()->Array:return IslandWar.new(self).catalogue()
func prepare_island(mode:String,npc_id:String,units:Array=[],ships:Array=[],preset:String="balanced",company_transports:Array=[],seed:int=-1)->Dictionary:return IslandWar.new(self).prepare(mode,npc_id,units,ships,preset,company_transports,seed)
func prepare_island_v2(mode:String,npc_id:String,units:Array=[],ships:Array=[],preset:String="balanced",company_transports:Array=[],seed:int=-1)->Dictionary:return IslandWarV2.new(self).prepare(mode,npc_id,units,ships,preset,company_transports,seed)
func prepare_exercise(units:Array,ships:Array,preset:String="balanced",company_transports:Array=[],seed:int=-1)->Dictionary:return IslandWarV2.new(self).prepare("exercise","",units,ships,preset,company_transports,seed)
func island_v2():return IslandWarV2.new(self)
func island_v3():return IslandWarV3.new(self)
func island_v4():
	return load("res://scripts/home_island_war_coastal_v1.gd").new(self) if preload("res://scripts/coastal_map_settings.gd").enabled() else IslandWarV4.new(self)
func prepare_island_v4(mode:String,npc_id:String,units:Array=[],ships:Array=[],preset:String="balanced",company_transports:Array=[],seed:int=-1)->Dictionary:return IslandWarV4.new(self).prepare(mode,npc_id,units,ships,preset,company_transports,seed)
func prepare_exercise_v4(units:Array,ships:Array,preset:String="balanced",company_transports:Array=[],seed:int=-1)->Dictionary:return IslandWarV4.new(self).prepare("exercise","",units,ships,preset,company_transports,seed)
func latest_version()->String:
	if preload("res://scripts/coastal_map_settings.gd").enabled():return preload("res://scripts/coastal_map_settings.gd").VERSION
	return ISLAND_V4_VERSION if not v4_cards.is_empty() else ISLAND_V3_VERSION
func latest_cards()->Dictionary:return v4_cards if not v4_cards.is_empty() else v3_cards
func latest_weapons()->Dictionary:return v4_weapons if not v4_cards.is_empty() else v3_weapons
func latest_units()->Array:return v4_units() if not v4_cards.is_empty() else v3_units()
func latest_unit(id:String)->Dictionary:return v4_unit(id) if not v4_cards.is_empty() else v3_unit(id)
func latest_profile(id:String)->Dictionary:return v4_profile(id) if not v4_cards.is_empty() else v3_profile(id)
func latest_limit(key:String)->int:return v4_limit(key) if not v4_cards.is_empty() else v3_limit(key)
func latest_transport_option(id:String,kind:String="")->Dictionary:return v4_transport_option(id,kind) if not v4_cards.is_empty() else v3_transport_option(id,kind)
func latest_company_layout(id:String)->Dictionary:return v4_company_layout(id) if not v4_cards.is_empty() else v3_company_layout(id)
func latest_vehicle_profiles(id:String)->Array:return v4_vehicle_profiles(id) if not v4_cards.is_empty() else v3_vehicle_profiles(id)
func latest_vehicle_condition(ids:Array)->Array:return v4_vehicle_condition(ids) if not v4_cards.is_empty() else v3_vehicle_condition(ids)
func latest_transport_label(kind:String)->String:return v4_transport_label(kind)
func latest_combat_label(id:String)->String:return v4_combat_label(id) if not v4_cards.is_empty() else v3_combat_label(id)
func latest_island():return island_v4() if not v4_cards.is_empty() else island_v3()
func geometry_v4()->Dictionary:
	if v4_cards.is_empty():return {}
	if geometry_adapter==null:
		var adapter:String="res://scripts/home_geometry_coastal_v1.gd" if preload("res://scripts/coastal_map_settings.gd").enabled() else "res://scripts/home_geometry_v4.gd"
		geometry_adapter=load(adapter).new(self)
	return geometry_adapter.observe()
func geometry_candidate_v4(kind:String,cell:Vector2i)->Dictionary:
	if geometry_adapter==null:geometry_v4()
	return geometry_adapter.candidate(kind,cell) if geometry_adapter!=null else _fail("岛屿地形准备中")
func set_latest_garrison(ids:Array)->Dictionary:return set_tactical_garrison_v4(ids) if not v4_cards.is_empty() else set_tactical_garrison_v3(ids)
func prepare_latest_island(mode:String,npc_id:String,units:Array=[],ships:Array=[],preset:String="balanced",company_transports:Array=[],seed:int=-1)->Dictionary:return latest_island().prepare(mode,npc_id,units,ships,preset,company_transports,seed)
func prepare_latest_exercise(units:Array,ships:Array,preset:String="balanced",company_transports:Array=[],seed:int=-1)->Dictionary:return latest_island().prepare("exercise","",units,ships,preset,company_transports,seed)
func prepare_island_v3(mode:String,npc_id:String,units:Array=[],ships:Array=[],preset:String="balanced",company_transports:Array=[],seed:int=-1)->Dictionary:return IslandWarV3.new(self).prepare(mode,npc_id,units,ships,preset,company_transports,seed)
func prepare_exercise_v3(units:Array,ships:Array,preset:String="balanced",company_transports:Array=[],seed:int=-1)->Dictionary:return IslandWarV3.new(self).prepare("exercise","",units,ships,preset,company_transports,seed)
func v3_training(lesson:String)->Dictionary:
	var path:String="res://data/tactical-training-v3.json"
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not data is Dictionary:return _fail("联合兵种训练尚未就绪")
	var row:Dictionary=data.get("lessons",{}).get(lesson,{})
	var request:Dictionary=row.get("request",{})
	if str(request.get("version",""))!=ISLAND_V3_VERSION or str(request.get("mode",""))!="exercise" or str(request.get("lesson",""))!=lesson or request.get("defender",{}).is_empty():return _fail("此训练课程正在准备，请先选择其他课程")
	return {"ok":true,"request":request.duplicate(true)}
func v3_training_lessons()->Array:
	var result:Array=[]
	for row in [{"id":"landing","title":"抢滩登陆","text":"拖动连队上岸，接应撤收。"},{"id":"weapons","title":"武器分工","text":"轻武器与专职火力，各司其职。"},{"id":"artillery","title":"自行火炮","text":"炮车与手枪身体协同。"},{"id":"airborne","title":"空降行动","text":"控制投送风险，接应伞兵。"},{"id":"roles","title":"专业部队","text":"指挥、攻坚、防空、侦察协同。"},{"id":"combined_arms","title":"车步协同","text":"车步独立作战，拖动上下车并撤收。"}]:
		if v3_training(str(row.id)).get("ok",false):result.append(row)
	return result
func v4_training(lesson:String)->Dictionary:
	var path:String="res://data/tactical-training-v4.json"
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not data is Dictionary:return _fail("新版联合兵种训练尚未就绪")
	var row:Dictionary=data.get("lessons",{}).get(lesson,{})
	var request:Dictionary=row.get("request",{})
	if str(request.get("version",""))!=ISLAND_V4_VERSION or str(request.get("mode",""))!="exercise" or str(request.get("lesson",""))!=lesson or request.get("defender",{}).is_empty():return _fail("此训练课程正在准备，请先选择其他课程")
	return {"ok":true,"request":request.duplicate(true)}
func latest_training(lesson:String)->Dictionary:
	var prepared:Dictionary=v4_training(lesson) if not v4_cards.is_empty() else v3_training(lesson)
	if prepared.get("ok",false) and preload("res://scripts/coastal_map_settings.gd").enabled():
		prepared=preload("res://scripts/coastal_battle_plan_v1.gd").adapt(prepared.request)
	return prepared
func latest_training_lessons()->Array:
	if v4_cards.is_empty():return v3_training_lessons()
	var path:String="res://data/tactical-training-v4.json";var result:Array=[]
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not data is Dictionary:return result
	var labels:Dictionary={"landing":"抢滩登陆","weapons":"武器分工","artillery":"自行火炮","airborne":"空降行动","roles":"专业部队","combined_arms":"车步协同","expansion":"秋冬登陆编队"}
	for key in data.get("lessons",{}):
		var row:Dictionary=data.lessons[key]
		if v4_training(str(key)).get("ok",false):result.append({"id":str(key),"title":str(row.get("title",row.get("name",labels.get(key,"战术协同")))),"text":str(row.get("description","借用编队 · 实际操作训练"))})
	return result
func v2_profile(id:String)->Dictionary:return v2_cards.get(id,{}).duplicate(true)
func v2_limit(key:String)->int:return maxi(0,int(v2_data.get("limits",{}).get(key,0)))
func v2_unit(id:String)->Dictionary:
	var result:Dictionary=unit(id)
	if v2_cards.has(id):result.merge(v2_cards[id],true);result["released"]=true
	if v2_art.has(id):result.merge(v2_art[id],true)
	return result
func v2_units()->Array:
	var result:Array=[]
	for id in v2_cards:result.append(v2_unit(str(id)))
	return result
func v2_transport_option(id:String,kind:String="")->Dictionary:
	var data:Dictionary=v2_profile(id);var options:Array=data.get("transport_options",[])
	var desired:String=kind if not kind.is_empty() else str(data.get("default_transport",data.get("transport",{}).get("kind","")))
	for option in options:
		if str(option.get("kind",""))==desired:return option.duplicate(true)
	return options[0].duplicate(true) if kind.is_empty() and not options.is_empty() else {}
func v2_company_layout(id:String)->Dictionary:
	var data:Dictionary=v2_profile(id)
	return {"company_count":int(data.get("company_count",0)),"personnel_per_company":int(data.get("personnel_per_company",0))}
func v2_transport_label(kind:String)->String:
	return str({"landing_craft":"通用登陆艇","fast_boat":"高速突击艇","armored_boat":"装甲登陆艇","heavy_lander":"重型坦克登陆艇","transport_helicopter":"运输直升机","parachute_aircraft":"伞降运输机","amphibious_vehicle":"两栖装甲战车","attack_helicopter":"武装直升机"}.get(kind,kind))
func v2_combat_label(id:String)->String:
	var card:Dictionary=v2_profile(id);var kind:String=str(card.get("combat",{}).get("class","infantry"))
	if kind=="air":return "%d架武装直升机 · 每个身体驾驶一架，不另增步兵"%int(card.get("body_count",0))
	if kind=="amphibious":return "两栖装甲战车 · 水陆为同一作战实体"
	if kind=="armor":return "重装甲单位 · 登陆艇投送，战车上岸后协同作战"
	if str(card.get("default_transport",""))=="parachute_aircraft":return "伞降步兵 · 空中脆弱，撤离使用运输艇"
	return "步兵作战 · 登陆工具仅运输，不提供额外火力"

func v3_profile(id:String)->Dictionary:return v3_cards.get(id,{}).duplicate(true)
func v3_limit(key:String)->int:return maxi(0,int(v3_data.get("limits",{}).get(key,0)))
func v3_unit(id:String)->Dictionary:
	var result:Dictionary=unit(id)
	if v3_cards.has(id):result.merge(v3_cards[id],true);result["released"]=true
	if v2_art.has(id):
		var artwork:Dictionary=v2_art[id].duplicate(true)
		for field in ["id","name","codename","designation"]:artwork.erase(field)
		result.merge(artwork,true)
	if v3_cards.has(id):result["codename"]=str(v3_cards[id].get("name",result.get("codename",id)))
	return result
func v3_units()->Array:
	var result:Array=[]
	for id in v3_cards:result.append(v3_unit(str(id)))
	return result
func v3_transport_option(id:String,kind:String="")->Dictionary:
	var data:Dictionary=v3_profile(id);var options:Array=data.get("transport_options",[])
	var desired:String=str(data.get("default_transport",data.get("transport",{}).get("kind","")))
	if not kind.is_empty() and kind!=desired:return {}
	for option in options:
		if str(option.get("kind",""))==desired:return option.duplicate(true)
	return {}
func v3_company_layout(id:String)->Dictionary:
	var data:Dictionary=v3_profile(id)
	return {"company_count":int(data.get("company_count",0)),"personnel_per_company":int(data.get("personnel_per_company",0))}
func v3_vehicle_profiles(id:String)->Array:
	var card:Dictionary=v3_profile(id);var result:Array=[]
	var saved:Dictionary=state().units.get(id,{}).get("vehicle_condition_v3",{})
	for vehicle in card.get("combat_vehicles",[]):
		for company in range(1,int(card.get("company_count",0))+1):
			var row:Dictionary=vehicle.duplicate(true)
			row["unit_id"]=id;row["company"]=company
			row["hp_percent"]=clampf(float(saved.get(str(company),100.0)),0,100)
			result.append(row)
	return result
func v3_vehicle_condition(ids:Array)->Array:
	var result:Array=[]
	for identity in ids:
		for row in v3_vehicle_profiles(str(identity)):
			result.append({"id":str(identity),"company":int(row.company),"hp_percent":float(row.hp_percent)})
	return result
func v3_transport_label(kind:String)->String:
	return str({"landing_craft":"通用登陆艇","fast_boat":"高速突击艇","armored_boat":"装甲登陆艇","heavy_lander":"重型坦克登陆艇","transport_helicopter":"运输直升机","parachute_aircraft":"伞降运输机","amphibious_vehicle":"两栖装甲战车","attack_helicopter":"武装直升机","kayak":"皮划艇 · 无甲暴露乘员","tank":"坦克","self_propelled_gun":"自行火炮"}.get(kind,kind))
func v3_combat_label(id:String)->String:
	var card:Dictionary=v3_profile(id)
	if not card.get("combat_vehicles",[]).is_empty():
		var parts:Array[String]=[]
		for vehicle in card.combat_vehicles:
			var kind_name:String=str({"tank":"坦克","self_propelled_gun":"自行火炮","amphibious_vehicle":"两栖战车","attack_helicopter":"武装直升机"}.get(str(vehicle.get("kind","")),v3_transport_label(str(vehicle.get("kind","")))))
			parts.append("%d%s%s"%[int(vehicle.get("count_per_company",1)),"架" if str(vehicle.get("kind",""))=="attack_helicopter" else "辆",kind_name])
		var seats:bool=card.combat_vehicles.any(func(vehicle):return int(vehicle.get("passenger_seats",vehicle.get("capacity",0)))>0)
		return "每连"+" / ".join(parts)+" + %d名身体 · "%int(card.get("personnel_per_company",0))+("可上下载具" if seats else "车步独立协同")
	var kind:String=str(card.get("combat",{}).get("class","infantry"))
	if kind=="air":return "空地协同 · 载具与人员数量按本人编制"
	if kind=="amphibious":return "两栖装甲战车 · 水陆为同一作战实体"
	if kind=="armor":return "重装甲单位 · 登陆艇投送，战车上岸后协同作战"
	if str(card.get("default_transport",""))=="parachute_aircraft":return "伞降步兵 · 空中脆弱，撤离使用运输艇"
	return "步兵作战 · 登陆工具仅运输，不提供额外火力"

func v4_profile(id:String)->Dictionary:return v4_cards.get(id,{}).duplicate(true)
func v4_limit(key:String)->int:return maxi(0,int(v4_data.get("limits",{}).get(key,0)))
func v4_unit(id:String)->Dictionary:
	var result:Dictionary=unit(id)
	if v4_cards.has(id):result.merge(v4_cards[id],true);result["released"]=true
	if v4_art.has(id) or v2_art.has(id):
		var artwork:Dictionary=v4_art.get(id,v2_art.get(id,{})).duplicate(true)
		for field in ["id","name","codename","designation"]:artwork.erase(field)
		result.merge(artwork,true)
	if v4_cards.has(id):result["codename"]=str(v4_cards[id].get("name",result.get("codename",id)))
	return result
func v4_units()->Array:
	var result:Array=[]
	for id in v4_cards:result.append(v4_unit(str(id)))
	return result
func v4_transport_option(id:String,kind:String="")->Dictionary:
	var data:Dictionary=v4_profile(id);var options:Array=data.get("transport_options",[])
	var desired:String=str(data.get("default_transport",data.get("transport",{}).get("kind","")))
	if not kind.is_empty() and kind!=desired:return {}
	for option in options:
		if str(option.get("kind",""))==desired:return option.duplicate(true)
	return {}
func v4_company_layout(id:String)->Dictionary:
	var data:Dictionary=v4_profile(id)
	return {"company_count":int(data.get("company_count",0)),"personnel_per_company":int(data.get("personnel_per_company",0))}
func v4_vehicle_profiles(id:String)->Array:
	var card:Dictionary=v4_profile(id);var result:Array=[]
	var saved:Dictionary=state().units.get(id,{}).get("vehicle_condition_v3",{})
	for vehicle in card.get("combat_vehicles",[]):
		for company in range(1,int(card.get("company_count",0))+1):
			var row:Dictionary=vehicle.duplicate(true)
			row["unit_id"]=id;row["company"]=company
			row["hp_percent"]=clampf(float(saved.get(str(company),100.0)),0,100)
			result.append(row)
	return result
func v4_vehicle_condition(ids:Array)->Array:
	var result:Array=[]
	for identity in ids:
		for row in v4_vehicle_profiles(str(identity)):
			result.append({"id":str(identity),"company":int(row.company),"hp_percent":float(row.hp_percent)})
	return result
func v4_transport_label(kind:String)->String:
	return str({"landing_craft":"通用登陆艇","fast_boat":"高速突击艇","armored_boat":"装甲登陆艇","heavy_lander":"重型坦克登陆艇","transport_helicopter":"运输直升机","parachute_aircraft":"伞降运输机","amphibious_vehicle":"两栖装甲战车","amphibious_wheeled_ifv":"两栖轮式步战车","amphibious_tracked_gun":"两栖履带突击炮","attack_helicopter":"武装直升机","kayak":"皮划艇 · 无甲暴露乘员","tank":"坦克","self_propelled_gun":"自行火炮"}.get(kind,kind))
func v4_combat_label(id:String)->String:
	var card:Dictionary=v4_profile(id)
	if not card.get("combat_vehicles",[]).is_empty():
		var parts:Array[String]=[]
		for vehicle in card.combat_vehicles:
			var kind_name:String=str({"tank":"坦克","self_propelled_gun":"自行火炮","amphibious_vehicle":"两栖战车","attack_helicopter":"武装直升机"}.get(str(vehicle.get("kind","")),v4_transport_label(str(vehicle.get("kind","")))))
			parts.append("%d%s%s"%[int(vehicle.get("count_per_company",1)),"架" if str(vehicle.get("kind",""))=="attack_helicopter" else "辆",kind_name])
		var seats:bool=card.combat_vehicles.any(func(vehicle):return int(vehicle.get("passenger_seats",vehicle.get("capacity",0)))>0)
		return "每连"+" / ".join(parts)+" + %d名身体 · "%int(card.get("personnel_per_company",0))+("可上下载具" if seats else "车步独立协同")
	var kind:String=str(card.get("combat",{}).get("class","infantry"))
	if kind=="air":return "空地协同 · 载具与人员数量按本人编制"
	if kind=="amphibious":return "两栖装甲战车 · 水陆为同一作战实体"
	if kind=="armor":return "重装甲单位 · 登陆艇投送，战车上岸后协同作战"
	if str(card.get("default_transport",""))=="parachute_aircraft":return "伞降步兵 · 空中脆弱，撤离使用运输艇"
	return "步兵作战 · 登陆工具仅运输，不提供额外火力"

func unit(id:String)->Dictionary:
	for row in catalogue:
		if str(row.get("id",""))==id:return row.duplicate(true)
	return {}

func released(version:String=BATTLE_VERSION)->Array:
	var allowed:Array=LEGACY_RELEASED if version==LEGACY_BATTLE_VERSION else RELEASED
	return catalogue.filter(func(row):return bool(row.get("released",false)) and allowed.has(str(row.get("id",""))))

func profile(id:String)->Dictionary:return profiles.get(id,{}).duplicate(true)

func profile_summary(id:String)->String:
	var stats:Dictionary=profile(id)
	if stats.is_empty():return "编制数据尚未加载"
	var bodies:Array=stats.get("bodies",[]);var hp:float=0;var damage:float=0;var reach:float=0
	for body in bodies:
		hp+=float(body.get("hp",0));damage+=float(body.get("damage",0));reach=maxf(reach,float(body.get("range",0)))
	var ability:Dictionary=stats.get("ability",{})
	return "%s · %d个身体 · %d舱\n总耐久 %.0f · 移速 %.1f\n齐射伤害 %.0f · 射程 %.0f米\n%s · %d次"%[str(stats.get("role_label","先遣部队")),bodies.size(),int(stats.get("transport_slots",0)),hp,float(stats.get("speed",0)),damage,reach,str(ability.get("name","战术专长")),int(ability.get("charges",0))]

func medical_level()->int:
	var level:int=0
	for building in state().buildings:
		if str(building.kind)=="medical":level=maxi(level,int(building.level))
	return level

func condition(id:String,at:int=-1)->float:
	var row:Dictionary=state().units.get(id,{})
	if row.is_empty():return 0.0
	var elapsed:int=maxi(0,(_now() if at<0 else at)-int(row.get("at",_now())))
	return minf(100.0,float(row.get("condition",100.0))+float(elapsed)/1800.0*(1.0+float(medical_level())*.5))

func production()->Dictionary:
	var rates:Dictionary={"scrap":0,"alloy":0,"energy":0}
	for building in state().buildings:
		var definition:Dictionary=BUILDINGS.get(str(building.kind),{})
		var resource:String=str(definition.get("produces",""))
		if not resource.is_empty():rates[resource]=int(rates.get(resource,0))+int(definition.hourly)*int(building.level)
	return rates

func overview(at:int=-1)->Dictionary:
	var home:Dictionary=state().duplicate(true)
	var now:int=_now() if at<0 else at
	var elapsed:int=mini(OFFLINE_CAP,maxi(0,now-int(home.last_collect))) if bool(home.unlocked) else 0
	var rates:Dictionary=production();var pending:Dictionary={}
	for key in rates:pending[key]=maxi(0,mini(RESOURCE_CAP-int(home.resources.get(key,0)),int(float(elapsed)*float(rates[key])/3600.0+float(home.carry.get(key,0)))))
	for id in home.units:home.units[id]["condition"]=condition(str(id),now)
	home["pending"]=pending;home["hourly"]=rates;home["offline_seconds"]=elapsed;home["catalogue"]=catalogue.duplicate(true)
	home["released"]=released().size();home["total"]=catalogue.size();home["resource_names"]=RESOURCE_NAMES.duplicate()
	home["development"]=island_profile()
	if not v4_cards.is_empty():home["geometry_v4"]=geometry_v4()
	return home

func processing():return load("res://scripts/home_economy_v2.gd").new(self)

func _charge(cost:Dictionary)->bool:
	for key in cost:
		if int(state().resources.get(key,0))<int(cost[key]):return false
	for key in cost:state().resources[key]=int(state().resources[key])-int(cost[key])
	return true

func _give(resources:Dictionary)->void:
	for key in resources:
		if RESOURCE_NAMES.has(key):
			var current:int=int(state().resources.get(key,0))
			state().resources[key]=maxi(current,mini(RESOURCE_CAP,current+maxi(0,int(resources[key]))))

func collect(at:int=-1)->Dictionary:
	if not _idle():return _fail("行动期间请先保存返航")
	if not bool(state().unlocked):return _fail("先完成岛屿登陆教学")
	var before:Dictionary=account.state.duplicate(true);var now:int=_now() if at<0 else at
	var resources:Dictionary=_accrue(now)
	_recover_all(now)
	return _commit(before,"生产物资已收取 · 最多累计8小时",{"resources":resources})

func _accrue(now:int)->Dictionary:
	var elapsed:int=mini(OFFLINE_CAP,maxi(0,now-int(state().last_collect)))
	var resources:Dictionary={}
	for key in production():
		var exact:float=float(elapsed)*float(production()[key])/3600.0+float(state().carry.get(key,0))
		resources[key]=int(exact);state().carry[key]=exact-floor(exact)
	_give(resources);state().last_collect=maxi(now,int(state().last_collect))
	return resources

func _recover_all(now:int)->void:
	for id in state().units:
		var recovered:float=condition(str(id),now);state().units[id].condition=recovered;state().units[id].at=maxi(now,int(state().units[id].get("at",now)))

func is_land(cell:Vector2i)->bool:
	if not v4_cards.is_empty():
		geometry_v4()
		return geometry_adapter!=null and geometry_adapter.buildable(cell)
	if cell.x<0 or cell.x>=GRID.x or cell.y<0 or cell.y>=GRID.y:return false
	var center:Vector2=Vector2(5.5,4.0);var relative:Vector2=(Vector2(cell)-center)/Vector2(5.3,3.8)
	var wave:float=sin(float(cell.x*31+cell.y*17+int(state().seed)%137)*1.71)*.12
	return relative.length_squared()<.83+wave

func building_at(cell:Vector2i)->Dictionary:
	for building in state().buildings:
		if int(building.cell.x)==cell.x and int(building.cell.y)==cell.y:return building
	return {}

func place(kind:String,cell:Vector2i)->Dictionary:
	if not _idle():return _fail("行动期间不能改建岛屿")
	if not bool(state().unlocked):return _fail("先完成岛屿登陆教学")
	if not BUILDINGS.has(kind) or not is_land(cell) or not building_at(cell).is_empty():return _fail("请选择岛内空地")
	if not buildable(cell):return _fail("此区域尚未开放，请升级联络中枢扩建岛屿")
	if int(BUILDINGS[kind].get("unlock_level",1))>int(development().level()):return _fail("升级联络中枢后解锁此设施")
	if not v4_cards.is_empty():
		var validity:Dictionary=geometry_candidate_v4(kind,cell)
		if not validity.get("ok",false):return validity
	var count:int=0
	for building in state().buildings:
		if str(building.kind)==kind:count+=1
	if count>=int(BUILDINGS[kind].limit) or state().buildings.size()>=int(island_profile().building_limit):return _fail("此类建筑已达到岛屿容纳上限")
	var before:Dictionary=account.state.duplicate(true)
	_accrue(_now());_recover_all(_now())
	if not _charge(BUILDINGS[kind].cost):account.state=before;return _fail("建设资源不足")
	state().building_sequence=int(state().building_sequence)+1
	var building:Dictionary={"id":"home-%d"%int(state().building_sequence),"kind":kind,"cell":{"x":cell.x,"y":cell.y},"level":1}
	state().buildings.append(building)
	return _commit(before,str(BUILDINGS[kind].name)+"已落成",{"building":building})

func upgrade_cost(id:String)->Dictionary:
	for building in state().buildings:
		if str(building.id)==id:
			var cost:Dictionary=BUILDINGS.get(str(building.kind),{}).get("cost",{}).duplicate()
			for key in cost:cost[key]=int(cost[key])*(int(building.level)+1)
			cost["credits"]=30*int(building.level)
			if int(building.level)>=2:cost["protocols"]=5*maxi(1,int(building.level)-1)
			return cost
	return {}

func upgrade(id:String)->Dictionary:
	if not _idle():return _fail("行动期间不能升级岛屿")
	if not bool(state().unlocked):return _fail("先完成岛屿登陆教学")
	for building in state().buildings:
		if str(building.id)!=id:continue
		var headquarters:bool=str(building.kind)=="hq"
		if int(building.level)>=(5 if headquarters else 3):return _fail("已达到当前建设上限")
		if headquarters and int(account.player_profile().level)<int([1,3,6,10,15][mini(4,int(building.level))]):return _fail("指挥官等级不足，暂不能扩建岛屿")
		var before:Dictionary=account.state.duplicate(true)
		_accrue(_now());_recover_all(_now())
		if not _charge(upgrade_cost(id)):account.state=before;return _fail("升级资源不足")
		building.level=int(building.level)+1
		return _commit(before,"建筑已升级",{"building":building.duplicate(true)})
	return _fail("建筑不存在")

func set_garrison(ids:Array)->Dictionary:
	if not _idle():return _fail("行动期间不能调整驻舰")
	if ids.size()>6:return _fail("驻防最多六艘舰娘")
	var unique:Array=[]
	for id in ids:
		if not id is String or unique.has(id) or not account.state.owned.has(id) or not bool(account._cards.get(id,{}).get("playable",false)):return _fail("驻舰须已拥有、可出航且不重复")
		unique.append(id)
	var before:Dictionary=account.state.duplicate(true);state().garrison=unique
	return _commit(before,"驻防舰娘已停泊待命")

func set_tactical_garrison(ids:Array)->Dictionary:
	if not _idle():return _fail("行动期间不能调整战术驻防")
	if not bool(state().unlocked):return _fail("先完成岛屿登陆教学")
	if not ids.is_empty() and (ids.size()<2 or ids.size()>5):return _fail("战术驻防请选择2至5连，或清空驻防")
	var unique:Array=[]
	for id in ids:
		if not id is String or unique.has(id) or not state().units.has(id) or not RELEASED.has(id) or not bool(unit(id).get("released",false)):return _fail("驻防部队须已拥有、已开放且不重复")
		if condition(id)<10:return _fail("驻防部队整备不足10%，请先恢复")
		unique.append(id)
	var before:Dictionary=account.state.duplicate(true);state().tactical_garrison=unique
	return _commit(before,"战术驻防已保存 · 防御演练按此部署")

func set_tactical_garrison_v2(ids:Array)->Dictionary:
	if not _idle():return _fail("行动期间不能调整战术驻防")
	var cap:int=v2_limit("roster_per_side")
	if cap<=0:return _fail("新版驻防目录尚未就绪")
	if not bool(state().unlocked) or ids.size()>cap:return _fail("请先完成入驻引导；驻防最多%d个战术人格"%cap)
	var unique:Array=[];var bodies:int=0;var companies:int=0
	for identity in ids:
		var id:String=str(identity);var card:Dictionary=v2_profile(id)
		if not identity is String or unique.has(id) or not state().units.has(id) or card.is_empty():return _fail("驻防部队须已拥有、已开放且不重复")
		if condition(id)<10:return _fail("驻防部队整备不足10%，请先恢复")
		unique.append(id);companies+=int(card.get("company_count",0));bodies+=int(card.get("company_count",0))*int(card.get("personnel_per_company",0))
	if bodies>v2_limit("bodies_per_side") or companies>v2_limit("companies_per_side"):return _fail("驻防先遣编制超过本场容纳上限，请减少所选部队")
	var before:Dictionary=account.state.duplicate(true);state().tactical_garrison=unique
	return _commit(before,"新版战术驻防已保存 · 无损演习以此作为守方")

func set_tactical_garrison_v3(ids:Array)->Dictionary:
	if not _idle():return _fail("行动期间不能调整战术驻防")
	var cap:int=v3_limit("roster_per_side")
	if cap<=0:return _fail("新版驻防目录尚未就绪")
	if not bool(state().unlocked) or ids.size()>cap:return _fail("请先完成入驻引导；驻防最多%d个战术人格"%cap)
	var unique:Array=[];var bodies:int=0;var companies:int=0
	for identity in ids:
		var id:String=str(identity);var card:Dictionary=v3_profile(id)
		if not identity is String or unique.has(id) or not state().units.has(id) or card.is_empty():return _fail("驻防部队须已拥有、已开放且不重复")
		if condition(id)<10:return _fail("驻防部队整备不足10%，请先恢复")
		unique.append(id);companies+=int(card.get("company_count",0));bodies+=int(card.get("company_count",0))*int(card.get("personnel_per_company",0))
	if bodies>v3_limit("bodies_per_side") or companies>v3_limit("companies_per_side"):return _fail("驻防先遣编制超过本场容纳上限，请减少所选部队")
	var before:Dictionary=account.state.duplicate(true);state().tactical_garrison=unique
	return _commit(before,"新版战术驻防已保存 · 无损演习以此作为守方")

func set_tactical_garrison_v4(ids:Array)->Dictionary:
	if not _idle():return _fail("行动期间不能调整战术驻防")
	var cap:int=v4_limit("roster_per_side")
	if cap<=0:return _fail("新版驻防目录尚未就绪")
	if not bool(state().unlocked) or ids.size()>cap:return _fail("请先完成入驻引导；驻防最多%d个战术人格"%cap)
	var unique:Array=[];var bodies:int=0;var companies:int=0
	for identity in ids:
		var id:String=str(identity);var card:Dictionary=v4_profile(id)
		if not identity is String or unique.has(id) or not state().units.has(id) or card.is_empty():return _fail("驻防部队须已拥有、已开放且不重复")
		if condition(id)<10:return _fail("驻防部队整备不足10%，请先恢复")
		unique.append(id);companies+=int(card.get("company_count",0));bodies+=int(card.get("company_count",0))*int(card.get("personnel_per_company",0))
	if bodies>v4_limit("bodies_per_side") or companies>v4_limit("companies_per_side"):return _fail("驻防先遣编制超过本场容纳上限，请减少所选部队")
	var before:Dictionary=account.state.duplicate(true);state().tactical_garrison=unique
	return _commit(before,"新版战术驻防已保存 · 无损演习以此作为守方")

func transport_option(id:String,kind:String="")->Dictionary:
	var row:Dictionary=profile(id);var desired:String=str(row.get("default_transport","landing_craft")) if kind.is_empty() else kind
	for option in row.get("transport_options",[]):
		if str(option.get("kind",""))==desired:return option.duplicate(true)
	return {}

func transport_summary(roster:Array,ships:Array,preset:String,transports:Array=[],version:String=BATTLE_VERSION,layout:String=COMPANY_LAYOUT)->Dictionary:
	var chosen:Dictionary={}
	for row in transports:
		if row is Dictionary:chosen[str(row.get("id",""))]=str(row.get("kind",""))
	var multi:bool=version==BATTLE_VERSION and layout==COMPANY_LAYOUT
	var used:int=0;var available:int=0;var people:int=0;var company_count:int=0
	for id in roster:
		var option:Dictionary=transport_option(str(id),str(chosen.get(str(id),"")))
		if not multi:used+=int(option.get("transport_slots",0));people+=int(option.get("entity_count",0));company_count+=1
	if version!=BATTLE_VERSION:
		for id in ships:available+=int(ship_profiles.get(str(id),{}).get("slots_"+preset,0))
		return {"used":used,"available":available,"people":people,"fits":used<=available,"reason":""}
	var capacities:Array=[];var requirements:Array=[]
	for id in ships:
		var kind:String=_carrier_category(str(id));var base:int=int({"CV":24,"LHA":28,"APV":30}.get(kind,0))
		if base==0:base=int({"BB":16,"BC":16,"CB":16,"CA":12,"CL":10,"AV":14}.get(str(account._cards.get(id,{}).get("type",ship_profiles.get(id,{}).get("kind","DD"))),8))
		var loaded:int=mini(int(account.state.owned.get(id,{}).get("ammo",100)),int({"combat":100,"balanced":70,"transport":40}.get(preset,70)))
		var slots:int=base+int((100-loaded)/20)
		if multi:slots*=int(company_rules.get("capacity_multiplier",6))
		available+=slots;capacities.append({"id":str(id),"kind":kind,"free":slots})
	for id in roster:
		var option:Dictionary=transport_option(str(id),str(chosen.get(str(id),"")))
		var role:String=str(profile(str(id)).get("role","marine"));var family:String=str(option.get("kind","landing_craft"))
		var category:String="airmobile" if family=="helicopter" or role in ["air_assault","airborne","gunship"] else "armor" if family=="amphibious_vehicle" or role in ["armor","transport"] else "infantry"
		if multi:
			var formation:Dictionary=company_layout(str(id))
			if str(formation.get("version",""))!=COMPANY_LAYOUT:return {"used":0,"available":available,"people":0,"companies":0,"fits":false,"reason":"多连编制目录尚未就绪"}
			var bodies:int=int(formation.get("personnel_per_company",0));var count:int=int(formation.get("company_count",0))
			var weight:int=int(company_rules.get("personnel_weights",{}).get(category,1));var body_slots:int=bodies*weight
			for company in formation.get("companies",[]):requirements.append({"id":str(company.get("company_id","")),"category":category,"slots":body_slots})
			used+=body_slots*count;people+=bodies*count;company_count+=count
		else:requirements.append({"id":id,"category":category,"slots":int(option.get("transport_slots",999))})
	requirements.sort_custom(func(a,b):return int(a.category=="airmobile")*100+int(a.category=="armor")*50+int(a.slots)>int(b.category=="airmobile")*100+int(b.category=="armor")*50+int(b.slots))
	var fits:bool=used<=available and _fit_companies(requirements,capacities,0,{})
	return {"used":used,"available":available,"people":people,"companies":company_count,"fits":fits,"reason":"" if fits else "普通陆战可乘任意舰；装甲需APV/两栖攻击舰/航母；空输需两栖攻击舰/航母，且整连舱位必须充足"}

func _carrier_category(id:String)->String:
	if id in ["CAS-H-USN-ENTERPRISE-1942","CAS-H-IJN-SHOKAKU-1942"]:return "CV"
	if id=="CAS-O-LHA-RETURNLIGHT":return "LHA"
	if id=="CAS-O-APV-TIDEBRIDGE":return "APV"
	return "warship"

func _fit_companies(requirements:Array,ships:Array,index:int,memo:Dictionary)->bool:
	if index>=requirements.size():return true
	var state_key:String=str(index)
	for ship in ships:state_key+="|"+str(ship.kind)+":"+str(ship.free)
	if memo.has(state_key):return false
	var unit:Dictionary=requirements[index]
	var tried:Dictionary={}
	for ship in ships:
		if int(ship.free)<int(unit.slots):continue
		if unit.category=="airmobile" and str(ship.kind) not in ["LHA","CV"]:continue
		if unit.category=="armor" and str(ship.kind) not in ["APV","LHA","CV"]:continue
		var equivalent:String=str(ship.kind)+":"+str(ship.free)
		if tried.has(equivalent):continue
		tried[equivalent]=true
		ship.free=int(ship.free)-int(unit.slots)
		var fits:bool=_fit_companies(requirements,ships,index+1,memo)
		ship.free=int(ship.free)+int(unit.slots)
		if fits:return true
	memo[state_key]=true
	return false

func care(id:String)->Dictionary:
	if not _idle():return _fail("行动期间不能安排护理")
	if not state().units.has(id) or medical_level()==0:return _fail("请先建设协议医疗站")
	var now:int=_now()
	if now-int(state().care_at.get(id,0))<1800:return _fail("本次护理尚未结束 · 30分钟冷却")
	if condition(id)>=100:return _fail("编制已经整备完毕")
	var before:Dictionary=account.state.duplicate(true)
	if not _charge({"energy":25,"alloy":10}):return _fail("护理需要25能源和10合金")
	state().units[id].condition=minf(100.0,condition(id)+5.0);state().units[id].at=now;state().care_at[id]=now
	return _commit(before,"已补充医疗物资 · 恢复5%整备率")

func _own_unit(id:String)->void:
	if not state().units.has(id):state().units[id]={"condition":100.0,"at":_now(),"obtained_at":_now(),"losses":0}

func unlock_test_units()->Dictionary:
	if not _idle():return _fail("请先结束当前行动")
	if str(account.state.get("test_account",""))!="cas-local-qa-2026-11-12":return _fail("仅当前明确登记的测试档可使用")
	var before:Dictionary=account.state.duplicate(true)
	for row in released():_own_unit(str(row.id))
	_give({"scrap":1800,"alloy":1400,"energy":1000});state().tickets=maxi(int(state().tickets),20)
	return _commit(before,"测试编制已就绪 · 不解锁未实装单位")

func unlock_test_units_v2()->Dictionary:
	if not _idle() or str(account.state.get("test_account",""))!="cas-local-qa-2026-11-12":return _fail("仅已登记且已返航的隔离测试档可使用")
	if v2_cards.size()!=22:return _fail("新版22人格目录未完成导出")
	var before:Dictionary=account.state.duplicate(true)
	for id in v2_cards:_own_unit(str(id))
	return _commit(before,"22个战术人格已同步至测试档")
func unlock_test_units_latest()->Dictionary:
	if not _idle() or str(account.state.get("test_account",""))!="cas-local-qa-2026-11-12":return _fail("仅已登记且已返航的隔离测试档可使用")
	if latest_cards().is_empty():return _fail("当前战术人格目录尚未就绪")
	var before:Dictionary=account.state.duplicate(true)
	for id in latest_cards():_own_unit(str(id))
	return _commit(before,"%d个战术人格已同步至测试档"%latest_cards().size())

func _random()->int:
	state().rng=(int(state().rng)*48271)%2147483647
	return int(state().rng)

func draw_units(count:int=1,request_id:String="")->Dictionary:
	if not _idle():return _fail("先继续或结束当前行动")
	if not bool(state().unlocked):return _fail("先完成岛屿登陆教学")
	if count not in [1,10]:return _fail("请选择单次或十次协议招募")
	var replay:Dictionary=account._request(request_id,["home_draw",count])
	if not replay.is_empty():return replay
	var pool:Array=latest_units() if not latest_cards().is_empty() else v2_units() if v2_cards.size()==22 else released()
	if pool.is_empty() or pool.size()!=latest_cards().size() and pool.size()!=RELEASED.size():return _fail("战术人格目录尚未就绪")
	var tickets:int=mini(count,int(state().tickets));var origins:int=(count-tickets)*DRAW_PRICE
	if int(account.state.wallet.get("origins",0))<origins:return _fail("协议券或元词不足")
	var before:Dictionary=account.state.duplicate(true)
	state().tickets=int(state().tickets)-tickets;account.state.wallet.origins=int(account.state.wallet.origins)-origins
	var obtained:Array=[]
	for index in range(count):
		var candidates:Array=pool
		var unseen:Array=pool.filter(func(row):return not state().units.has(str(row.id)))
		var pity:bool=int(state().pity)>=19 and not unseen.is_empty()
		if pity:candidates=unseen
		var row:Dictionary=candidates[_random()%candidates.size()]
		var id:String=str(row.id);var duplicate:bool=state().units.has(id)
		if duplicate:_give({"protocols":10});state().pity=int(state().pity)+1
		else:_own_unit(id);state().pity=0
		state().draw_sequence=int(state().draw_sequence)+1
		var result:Dictionary={"sequence":int(state().draw_sequence),"id":id,"name":str(row.name),"portrait":str(row.get("portrait","")),"rarity":str(row.get("rarity","SR")),"duplicate":duplicate,"protocols":10 if duplicate else 0,"pity":pity}
		obtained.append(result);state().draw_history.append(result.duplicate(true))
	while state().draw_history.size()>100:state().draw_history.pop_front()
	state().last_draw=obtained.duplicate(true)
	return _commit(before,"协议同步完成",{"results":obtained,"cost":{"tickets":tickets,"origins":origins},"pity":int(state().pity)})

func _ships(ids:Array,preset:String)->Dictionary:
	if ids.is_empty() or ids.size()>6:return _fail("请选择1至6艘已拥有舰娘")
	var unique:Array=[];var ships:Array=[];var loaded:int=0
	var cap:int=int({"combat":100,"balanced":70,"transport":40}.get(preset,0))
	if cap==0:return _fail("运输计划无效")
	for id in ids:
		if not id is String or unique.has(id) or not account.state.owned.has(id) or not bool(account._cards.get(id,{}).get("playable",false)):return _fail("舰娘身份未拥有、重复或不能出航")
		var row:Dictionary=account.state.owned[id];var hp:int=clampi(int(row.get("hp",100)),0,100);var ammo:int=clampi(int(row.get("ammo",100)),0,100)
		if hp<=0:return _fail("请先修复受损舰娘")
		unique.append(id);ships.append({"id":id,"hp":hp,"ammo":ammo});loaded+=mini(ammo,cap)
	if int(account.state.wallet.get("ammo_stock",0))<loaded:return _fail("母港弹药库存不足，请先补充")
	return {"ok":true,"ships":ships,"loaded_ammo":loaded}

func repair_building(id:String)->Dictionary:
	if not _idle():return _fail("行动期间不能修复岛屿")
	for building in state().buildings:
		if str(building.id)!=id:continue
		var missing:int=100-int(building.get("hp",100))
		if missing<=0:return _fail("建筑完好")
		var before:Dictionary=account.state.duplicate(true)
		if not _charge({"scrap":maxi(1,int(ceil(missing*.6))),"alloy":maxi(1,int(ceil(missing*.4)))}):return _fail("修复资源不足")
		building.hp=100
		return _commit(before,"建筑已经修复 · 原建筑与等级保留")
	return _fail("建筑不存在")

func defense_layout()->Array:
	var layout:Array=[]
	for building in state().buildings:
		if str(building.kind) not in ["hq","turret","aa","depot"]:continue
		layout.append({"id":str(building.id),"kind":str(building.kind),"x":clampf(float(building.cell.x)/11.0,.1,.9),"y":clampf(float(building.cell.y)/8.0,.1,.9),"level":int(building.level),"hp":int(building.get("hp",100))})
	return layout

func npc_layout(seed:int)->Array:
	for island in NPC_ISLANDS:
		if int(island.seed)!=seed:continue
		var layout:Array=[]
		for index in range(island.layout.size()):
			var row:Array=island.layout[index]
			layout.append({"id":"npc-%d-%d"%[seed,index],"kind":str(row[0]),"x":float(row[1]),"y":float(row[2]),"level":int(row[3]),"hp":100})
		return layout
	return []

func prepare_littoral(mode:String,seed:int,units:Array=[],ships:Array=[],preset:String="balanced",ruleset:String=BATTLE_VERSION,lesson:String="landing",company_transports:Array=[],company_layout_mode:String="auto")->Dictionary:
	if not _idle():return _fail("请先继续或结束当前行动")
	if ruleset not in BATTLE_VERSIONS:return _fail("海陆行动版本无效")
	if mode not in ["tutorial","raid","defense","salvage"]:return _fail("海陆行动模式无效")
	if mode!="tutorial" and not bool(state().unlocked):return _fail("先完成岛屿登陆教学")
	var modern:bool=ruleset in [V3_BATTLE_VERSION,BATTLE_VERSION]
	var training:bool=modern and mode=="tutorial"
	var chosen_layout:String=COMPANY_LAYOUT if company_layout_mode=="auto" and ruleset==BATTLE_VERSION and not training else "" if company_layout_mode=="auto" else company_layout_mode
	if chosen_layout not in ["",COMPANY_LAYOUT] or (not chosen_layout.is_empty() and (ruleset!=BATTLE_VERSION or training)):return _fail("本次行动不支持该连队编制")
	if training and lesson not in ["sea_control","landing","combined"]:return _fail("训练课程无效")
	if not training and lesson!="landing":return _fail("普通行动不能携带训练课程")
	if not modern and not company_transports.is_empty():return _fail("旧版行动保留原运输规则")
	var identities:Array=ships.duplicate()
	if training:identities=(V4_TRAINING_SHIPS if ruleset==BATTLE_VERSION else TRAINING_SHIPS).duplicate()
	elif identities.is_empty():
		identities=state().garrison.duplicate()
		if identities.is_empty() and not account.formation.is_empty():identities=[str(account.formation[0])]
	var naval:Dictionary={"ok":true,"ships":[],"loaded_ammo":0} if training else _ships(identities,preset)
	if training:
		if preset not in ["combat","balanced","transport"]:return _fail("运输计划无效")
		for id in identities:naval.ships.append({"id":id,"hp":100,"ammo":100})
	if not naval.get("ok",false):return naval
	var roster:Array=units.duplicate()
	var allowed:Array=LEGACY_RELEASED if ruleset==LEGACY_BATTLE_VERSION else RELEASED
	var limit:int=5 if modern or ruleset==LEGACY_BATTLE_VERSION else 6
	var loan_units:Array=["MCP-034","MCP-001","MCP-022"] if training and lesson=="combined" else ["MCP-034","MCP-001"] if training else []
	if training:
		if roster.is_empty():roster=loan_units.duplicate()
		if not _same(roster,loan_units):return _fail("请使用本课借用编队，玩家编制不参与训练战损")
	elif modern and mode=="defense" and roster.is_empty():roster=state().tactical_garrison.duplicate()
	if roster.is_empty():
		if modern and mode=="defense":return _fail("请先安排2至5连战术驻防")
		elif mode=="tutorial" and not bool(state().tutorial_complete):roster=["MCP-034"]
		else:
			for id in state().units:
				if allowed.has(str(id)) and condition(str(id))>=10 and roster.size()<limit:roster.append(str(id))
	if roster.size()<(2 if modern else 1) or roster.size()>limit:return _fail("请选择%d至%d支部队，实际投送还受载舰舱位限制"%[2 if modern else 1,limit])
	if modern and mode=="defense" and not _same(roster,state().tactical_garrison):return _fail("防御演练使用已保存的战术驻防，请先确认驻防安排")
	var unique:Array=[];var conditions:Array=[]
	for id in roster:
		var borrowed:bool=loan_units.has(id) or (mode=="tutorial" and id=="MCP-034" and (ruleset==PREVIOUS_BATTLE_VERSION or not bool(state().tutorial_complete)))
		if not id is String or unique.has(id) or not allowed.has(id) or not bool(unit(id).get("released",false)) or (not state().units.has(id) and not borrowed):return _fail("部队未拥有、重复或仍在整编")
		var ready:float=100.0 if borrowed else condition(id)
		if ready<10:return _fail("部队整备不足10%，请先安排恢复")
		unique.append(id);conditions.append({"id":id,"hp":floor(ready*100.0)/100.0})
	var layout:Array=defense_layout() if mode=="defense" else npc_layout(seed) if mode=="raid" else []
	var request:Dictionary={"op":"new_littoral","version":ruleset,"seed":seed,"mode":mode,"ships":naval.ships,"roster":roster,"unit_condition":conditions,"transport_preset":preset,"defense":layout}
	if not chosen_layout.is_empty():request["company_layout"]=chosen_layout
	if modern:
		var choices:Dictionary={}
		for item in company_transports:
			if not item is Dictionary or not roster.has(item.get("id")) or choices.has(item.get("id")):return _fail("运输方案身份须与部队完整对应且不重复")
			choices[str(item.id)]=str(item.get("kind",""))
		if not company_transports.is_empty() and choices.size()!=roster.size():return _fail("请为每一连选择运输方式")
		request["company_transports"]=[]
		for id in roster:
			var option:Dictionary=transport_option(str(id),str(choices.get(id,"")))
			if option.is_empty():return _fail("本队运输型号尚未加载或选择无效")
			request.company_transports.append({"id":id,"kind":str(option.kind)})
		if training:request["lesson"]=lesson
		if mode!="defense":
			var capacity:Dictionary=transport_summary(roster,identities,preset,request.company_transports,ruleset,chosen_layout)
			if not capacity.fits:return _fail(str(capacity.get("reason","")) if not str(capacity.get("reason","")).is_empty() else "需要%d舱，所选舰娘仅有%d舱，请减少携行或换运输计划"%[int(capacity.used),int(capacity.available)])
	if ruleset==BATTLE_VERSION:
		# The actual core validates all carrier assignments before account mutation.
		var verifier=Core.new();var checked:Dictionary=verifier.request(request);verifier.close()
		if not checked.get("ok",false):return _fail(str(checked.get("error","海陆空配置检查失败")))
	return {"ok":true,"request":request,"loaded_ammo":int(naval.loaded_ammo),"borrowed_tutorial":training or (mode=="tutorial" and (ruleset==PREVIOUS_BATTLE_VERSION or not bool(state().tutorial_complete))),"loan_units":loan_units,"loan_ships":identities.duplicate() if training else []}

func _canonical(value:Variant)->Variant:
	if value is Dictionary:
		var keys:Array=value.keys();keys.sort();var result:Array=[]
		for key in keys:result.append([str(key),_canonical(value[key])])
		return result
	if value is Array:
		var result:Array=[]
		for item in value:result.append(_canonical(item))
		return result
	if value is int or value is float:return float(value)
	return value
func _same(a:Variant,b:Variant)->bool:return JSON.stringify(_canonical(a))==JSON.stringify(_canonical(b))

func _native(serialized:String)->Dictionary:
	var verifier=Core.new();var response:Dictionary=verifier.request({"op":"load","serialized":serialized});verifier.close()
	if not response.get("ok",false):return _fail("海陆战报无法重演，已保留当前行动")
	var view:Dictionary=response.get("data",{})
	if str(view.get("littoral",{}).get("version","")) not in BATTLE_VERSIONS:return _fail("快照不是海陆协同行动")
	return {"ok":true,"view":view}

func _configuration_matches(saved:Dictionary,request:Dictionary)->bool:
	var expected_version:String=str(request.get("version",LEGACY_BATTLE_VERSION))
	if expected_version not in BATTLE_VERSIONS or str(saved.get("version",""))!=expected_version or int(saved.get("seed",-1))!=int(request.get("seed",-2)):return false
	var expected:Dictionary=request.duplicate(true)
	for key in ["op","version","seed"]:expected.erase(key)
	return _same(saved.get("config",{}),expected)

func begin(request:Dictionary,serialized:String)->Dictionary:
	if str(request.get("version",""))==preload("res://scripts/coastal_map_settings.gd").VERSION:return load("res://scripts/home_island_war_coastal_v1.gd").new(self).begin(request,serialized)
	if str(request.get("version",""))==ISLAND_V4_VERSION:return IslandWarV4.new(self).begin(request,serialized)
	if str(request.get("version",""))==ISLAND_V3_VERSION:return IslandWarV3.new(self).begin(request,serialized)
	if str(request.get("version",""))==ISLAND_V2_VERSION:return IslandWarV2.new(self).begin(request,serialized)
	if str(request.get("version",""))==ISLAND_VERSION:return IslandWar.new(self).begin(request,serialized)
	var ids:Array=[]
	for row in request.get("ships",[]):ids.append(str(row.get("id","")))
	var plan:Dictionary=prepare_littoral(str(request.get("mode","")),int(request.get("seed",0)),request.get("roster",[]),ids,str(request.get("transport_preset","")),str(request.get("version",LEGACY_BATTLE_VERSION)),str(request.get("lesson","landing")),request.get("company_transports",[]),str(request.get("company_layout","")))
	if not plan.get("ok",false):return plan
	# Natural recovery can advance after preview. An earlier, lower readiness is
	# still a legitimate frozen loadout; a caller can never add unearned health.
	var supplied:Variant=request.get("unit_condition",[])
	if not supplied is Array or supplied.size()!=plan.request.unit_condition.size():return _fail("部队整备配置不完整")
	for index in range(supplied.size()):
		var condition_row:Variant=supplied[index]
		if not condition_row is Dictionary or str(condition_row.get("id",""))!=str(plan.request.unit_condition[index].id):return _fail("部队整备身份不一致")
		var health:Variant=condition_row.get("hp",-1)
		if not (health is int or health is float) or not is_finite(float(health)) or float(health)<10 or float(health)>float(plan.request.unit_condition[index].hp)+.000001:return _fail("部队整备率高于真实恢复状态")
	plan.request.unit_condition=supplied.duplicate(true)
	if not _same(request,plan.request):return _fail("海陆出航计划与当前账户不一致")
	var evidence:Dictionary=_native(serialized)
	if not evidence.get("ok",false):return evidence
	var observed:Dictionary=evidence.view
	if float(observed.get("tick",-1))!=0 or observed.get("result")!=null:return _fail("只能绑定新的海陆行动")
	var saved:Variant=JSON.parse_string(serialized)
	if not saved is Dictionary or str(saved.get("version",""))!=str(request.get("version",LEGACY_BATTLE_VERSION)):return _fail("海陆保存版本不符")
	if not _configuration_matches(saved,request):return _fail("原核快照配置与账户出航计划不一致")
	var before:Dictionary=account.state.duplicate(true)
	account.state.run_sequence=int(account.state.get("run_sequence",0))+1
	var run_id:String="littoral-%d-%d"%[int(account.state.run_sequence),int(request.seed)]
	var active:Dictionary={"run_id":run_id,"mode":"littoral","ruleset":str(request.version),"stage_id":str(request.mode),"title":"海陆协同 · "+str({"tutorial":"新岛登陆","raid":"近海突袭","defense":"驻防演练","salvage":"遗迹搜索"}.get(str(request.mode),"行动")),"request":request.duplicate(true),"snapshot":serialized,"fleet":ids.duplicate(),"home_frozen":{"units":state().units.duplicate(true),"ships":request.ships.duplicate(true),"resources":state().resources.duplicate(true),"loaded_ammo":int(plan.loaded_ammo),"borrowed_tutorial":bool(plan.borrowed_tutorial)}}
	active.home_frozen["loan_units"]=plan.get("loan_units",[]).duplicate();active.home_frozen["loan_ships"]=plan.get("loan_ships",[]).duplicate()
	account.state.wallet.ammo_stock=int(account.state.wallet.ammo_stock)-int(plan.loaded_ammo)
	for row in request.ships:
		if not active.home_frozen.loan_ships.has(str(row.id)):account.state.owned[str(row.id)].ammo=0
	account.state.active_run=active.duplicate(true)
	return _commit(before,"海陆编队出航 · 装载与运输取舍已冻结",active)

func settle(view:Dictionary,serialized:String,abandon:bool=false)->Dictionary:
	var active:Dictionary=account.state.get("active_run",{})
	var coastal_version:String=preload("res://scripts/coastal_map_settings.gd").VERSION
	if str(active.get("ruleset",""))==coastal_version or (active.is_empty() and str(account.latest_receipt().get("ruleset",""))==coastal_version):return load("res://scripts/home_island_war_coastal_v1.gd").new(self).settle(view,serialized,abandon)
	if str(active.get("ruleset",""))==ISLAND_V4_VERSION or (active.is_empty() and str(account.latest_receipt().get("ruleset",""))==ISLAND_V4_VERSION):return IslandWarV4.new(self).settle(view,serialized,abandon)
	if str(active.get("ruleset",""))==ISLAND_V3_VERSION or (active.is_empty() and str(account.latest_receipt().get("ruleset",""))==ISLAND_V3_VERSION):return IslandWarV3.new(self).settle(view,serialized,abandon)
	if str(active.get("ruleset",""))==ISLAND_V2_VERSION or (active.is_empty() and str(account.latest_receipt().get("ruleset",""))==ISLAND_V2_VERSION):return IslandWarV2.new(self).settle(view,serialized,abandon)
	if str(active.get("ruleset",""))==ISLAND_VERSION or (active.is_empty() and str(account.latest_receipt().get("ruleset",""))==ISLAND_VERSION):return IslandWar.new(self).settle(view,serialized,abandon)
	if active.is_empty():
		var last:Dictionary=account.latest_receipt()
		return {"ok":true,"duplicate":true,"receipt":last} if str(last.get("mode",""))=="littoral" else _fail("没有海陆行动")
	if str(active.get("mode",""))!="littoral" or str(active.get("ruleset","")) not in BATTLE_VERSIONS:return _fail("当前不是海陆协同行动")
	var proof:Dictionary=_native(serialized)
	if not proof.get("ok",false):return proof
	var actual:Dictionary=proof.view
	for key in ["littoral","ships","result","tick"]:
		if not _same(actual.get(key),view.get(key)):return _fail("海陆结算与真实战况不一致")
	var saved:Dictionary=JSON.parse_string(serialized)
	if not _configuration_matches(saved,active.request):return _fail("海陆战报属于其他行动")
	var littoral:Dictionary=actual.get("littoral",{});var outcome_value:Variant=littoral.get("outcome")
	if actual.get("result")==null or not outcome_value is Dictionary or outcome_value.is_empty():return _fail("请完成撤离或明确结束当前行动")
	var outcome:Dictionary=outcome_value
	if abandon and not bool(outcome.get("abandoned",false)):return _fail("请先执行原核撤退命令")
	var before:Dictionary=account.state.duplicate(true)
	var success:bool=bool(outcome.get("success",false)) and not bool(outcome.get("abandoned",false))
	var rewards:Dictionary=outcome.get("resources",{}).duplicate(true) if success else {}
	if str(active.ruleset) in [V3_BATTLE_VERSION,BATTLE_VERSION] and str(active.request.mode)=="tutorial" and bool(state().tutorial_complete):rewards={}
	for key in rewards:
		if not RESOURCE_NAMES.has(key) or int(rewards[key])<0 or int(rewards[key])>5000:return _fail("岛屿奖励超出有效范围")
	var now:int=_now();var seen:Array=[]
	for row in outcome.get("units",[]):
		var id:String=str(row.get("id",""))
		if not active.request.roster.has(id) or seen.has(id):account.state=before;return _fail("部队战损身份不一致")
		seen.append(id)
		if active.home_frozen.get("loan_units",[]).has(id):continue
		if id=="MCP-034" and str(active.get("ruleset",""))==PREVIOUS_BATTLE_VERSION and bool(active.home_frozen.get("borrowed_tutorial",false)):continue
		if not state().units.has(id):continue
		var health:float=clampf(float(row.get("hp_percent",0)),0,100)
		if bool(row.get("missing",false)) or bool(row.get("incapacitated",false)):health=0
		state().units[id].condition=health;state().units[id].at=now
		if health<=0:state().units[id].losses=int(state().units[id].get("losses",0))+1
	if seen.size()!=active.request.roster.size():account.state=before;return _fail("部队战损记录不完整")
	var returned_ammo:int=0;seen.clear()
	for row in outcome.get("ships",[]):
		var id:String=str(row.get("id",""))
		if not active.fleet.has(id) or seen.has(id):account.state=before;return _fail("舰娘战损身份不一致")
		seen.append(id)
		if active.home_frozen.get("loan_ships",[]).has(id):continue
		var hp:int=clampi(int(floor(float(row.get("hp_percent",0)))),0,100)
		account.state.owned[id].hp=hp;account.state.owned[id].ammo=0
		if not bool(row.get("sunk",false)) and bool(row.get("recovered",false)):returned_ammo+=clampi(int(floor(float(row.get("ammo_percent",0)))),0,100)
	if seen.size()!=active.fleet.size():account.state=before;return _fail("舰娘返航记录不完整")
	account.state.wallet.ammo_stock=int(account.state.wallet.ammo_stock)+returned_ammo
	if str(active.request.mode)=="defense":
		for row in outcome.get("buildings",[]):
			for building in state().buildings:
				if str(building.id)==str(row.get("id","")):building.hp=clampi(int(floor(float(row.get("hp_percent",0)))),0,100)
	var losses:Dictionary={}
	if str(active.request.mode)=="defense" and not success:
		for key in ["scrap","alloy","credits"]:
			var loss:int=mini(80,int(float(state().resources.get(key,0))*.1))
			losses[key]=loss;state().resources[key]=int(state().resources.get(key,0))-loss
	_give(rewards)
	if success and str(active.request.mode)=="tutorial" and not bool(state().tutorial_complete):
		state().tutorial_complete=true;state().unlocked=true;state().last_collect=now;_own_unit("MCP-034");state().tickets=int(state().tickets)+10
		_give({"scrap":180,"alloy":120,"energy":60})
	var receipt:Dictionary={"run_id":str(active.run_id),"mode":"littoral","ruleset":str(active.ruleset),"success":success,"borrowed":false,"home_tutorial_loan":bool(active.home_frozen.get("borrowed_tutorial",false)),"title":"新岛已接入归航网络" if success and str(active.request.mode)=="tutorial" else "海陆行动结束","return_route":"home","rewards":rewards,"home_losses":losses,"units":outcome.units.duplicate(true),"ships":outcome.ships.duplicate(true),"ammo_loaded":int(active.home_frozen.loaded_ammo),"ammo_returned":returned_ammo,"snapshot":serialized,"request":active.request.duplicate(true)}
	state().records.append({"run_id":str(active.run_id),"mode":str(active.request.mode),"success":success,"at":now})
	while state().records.size()>50:state().records.pop_front()
	account.state.settled[str(active.run_id)]=receipt.duplicate(true);account.state.last_receipt_id=str(active.run_id);account.state.active_run={}
	return _commit(before,"岛屿战报与真实损耗已保存",{"receipt":receipt})
