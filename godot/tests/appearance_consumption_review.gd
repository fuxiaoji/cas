extends SceneTree
const Art=preload("res://scripts/character_art.gd")
const Appearance=preload("res://scripts/ship_appearance_service.gd")
const Port=preload("res://scripts/port_presentation.gd")
const Preparation=preload("res://scripts/page_preparation.gd")
const ID:String="IBS-U-USN-ERMA-MISSOURI"
const MILITARY:String="res://assets/story/canon-v2/missouri-uniform-portrait.png"
const BASE:String="res://assets/story/canon-v2/missouri-portrait.png"
var checks:int=0
var failures:Array[String]=[]
var account_path:String
var user_hash:String
var app
var app_b

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func origin(texture:Texture2D)->String:
	if texture==null:return ""
	if texture is AtlasTexture:return origin(texture.atlas)
	return texture.resource_path

func card_has_portrait(node:Node,path:String)->bool:
	for child in node.find_children("*","TextureRect",true,false):
		if origin(child.texture)==path:return true
	return false

func _initialize()->void:call_deferred("run")

func run()->void:
	check(DisplayServer.get_name()=="headless","review runs without opening a game window")
	user_hash=FileAccess.get_sha256("user://cas_port_v1.json") if FileAccess.file_exists("user://cas_port_v1.json") else ""
	account_path="user://tests/appearance-consumption-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	var account=load("res://scripts/economy.gd").new(account_path)
	check(account.new_profile().ok,"create isolated account")
	account.state.owned={ID:account._new_owned(ID)}
	account.state.owned[ID].level=20
	account.formation.clear();account.formation.append(ID)
	account.state.formation=[ID]
	account.state["fleet_book"]=[{"id":"qa-fleet","name":"外观验证舰队","ships":[ID]}]
	account.state["active_fleet_id"]="qa-fleet";account.state["sortie_fleet_ids"]=["qa-fleet"]
	account.state["harbor"]={"secretary":ID,"scale":1.0,"x":0.0,"y":0.0}
	check(account.save_state().ok,"save only isolated account")
	app=load("res://scenes/main.tscn").instantiate()
	app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.economy=account
	root.add_child(app);await process_frame
	app.page_motion=false;app.page_transition.cancel()
	var service=Appearance.new(account)
	var raw:Dictionary=account._cards[ID].duplicate(true)
	var numerical:Dictionary=account.state.owned[ID].duplicate(true)
	check(service.choose(ID,"military").ok,"select unlocked military appearance on isolated account")
	app.show_page("harbor");await process_frame
	check(str(app.cards[ID].portrait)==MILITARY,"main page refresh publishes selected portrait")
	check(str(Port._featured(app).portrait)==MILITARY,"secretary selection consumes selected appearance")
	var secretary:TextureRect=app.page.find_child("SecretaryPortrait",true,false)
	check(secretary!=null and origin(secretary.texture)==MILITARY,"actual harbor secretary node displays military portrait")
	check(str(account.roster()[0].portrait)==BASE,"economy roster remains original data")
	check(str(Port.visual_roster(app)[0].portrait)==MILITARY,"port visual roster substitutes only appearance")
	app.show_page("formation");await process_frame
	var fleet_card:Node=app.page.find_child("FleetSlot0",true,false)
	check(fleet_card!=null and card_has_portrait(fleet_card,MILITARY),"actual fleet card contains selected military portrait")
	app.show_page("roster");await process_frame
	var roster_card:Node=app.page.find_child("RosterShip_"+ID,true,false)
	check(roster_card!=null and card_has_portrait(roster_card,MILITARY),"actual roster card contains selected military portrait")
	var prepared:Array[String]=Preparation.paths_for("formation",app)
	check(prepared.has(MILITARY) and not prepared.has(BASE),"page preparation loads selected portrait")
	app.page_transition.use_registered_cast=false;app.page_transition.max_transition_characters=1
	app.page_transition._pick_characters(app)
	check(app.page_transition.actor_states.size()==1,"transition fixture has exactly the owned Missouri")
	if not app.page_transition.actor_states.is_empty():
		var state:Dictionary=app.page_transition.actor_states[0]
		check(str(state.path)=="res://assets/story/canon-v2/missouri-uniform-sd.tres","actual transition uses selected military SD")
		check(origin(state.sprite.texture).ends_with("missouri-uniform-sd-atlas.png"),"transition texture contains real military atlas")
	var resolved:Dictionary=Art.resolve(app.cards,{"characterId":ID},false)
	check(str(resolved.card.portrait)==MILITARY and not resolved.representative,"battle HUD resolves selected exact-person portrait from original catalog")
	check(str(Art.resolve({ID:raw},{"characterId":ID},false).card.portrait)==BASE,"raw registry resolves its own original appearance without another account")
	check(str(Art.visual_card(raw).portrait)==BASE,"context-free preview is never overridden")
	for pose:String in ["idle","walk","fire","hit","awake","lie-side"]:
		check(origin(Art.pose_texture(app.cards[ID],pose,.3)).ends_with("missouri-uniform-sd-atlas.png"),"battle SD samples selected military pose: "+pose)
	var tide=load("res://scripts/tide_sea.gd").new();tide.cards=app.cards
	var ship:Dictionary={"id":1,"characterId":ID,"x":1000.0,"y":1000.0,"heading":0.0,"speed":10.0}
	check(origin(tide._texture(ship,"ship")).ends_with("missouri-uniform-sd-atlas.png"),"roguelike renderer consumes selected SD")
	var littoral=load("res://scripts/littoral_sea.gd").new();littoral.cards=app.cards;littoral.size=Vector2(800,500);root.add_child(littoral)
	var observation:Dictionary={"tick":0.0,"width":24000,"height":16000,"ships":[ship],"littoral":{"transports":[]}}
	littoral.observe(observation)
	check(origin(littoral.textures[ID]).ends_with("missouri-uniform-sd-atlas.png"),"littoral renderer consumes selected SD")
	var stage=load("res://scenes/ui/canon_story.tscn").instantiate();root.add_child(stage);stage.app=app
	var chapter:Dictionary=load("res://scripts/canon_story_data.gd").chapter("chapter-01")
	stage._render_cast(chapter,{"actors":["missouri"],"cg":false},{"speaker":"missouri"})
	var story_actor:TextureRect=stage.get_node("Cast/Actor_missouri")
	check(origin(story_actor.texture)==BASE,"authored canon cast keeps default story outfit despite selected military form")
	stage._render_cast(chapter,{"actors":["missouri"],"cg":true,"background_asset":"res://assets/story/canon-v2/missouri_home.png"},{"speaker":"missouri"})
	check(not story_actor.visible,"fixed story CG does not overlay a player-selected costume")
	var b_path:String="user://tests/appearance-account-b-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	var b=load("res://scripts/economy.gd").new(b_path);check(b.new_profile().ok,"create isolated second account")
	b.state.owned[ID]=b._new_owned(ID);b.state.owned[ID].level=19
	b.state["appearance_v1"]={"version":"ship-appearance-v1","selected":{ID:"military"}}
	b.state["harbor"]={"secretary":ID,"scale":1.0,"x":0.0,"y":0.0}
	check(b.save_state().ok,"save isolated level19 account with locked selection")
	app_b=load("res://scenes/main.tscn").instantiate();app_b.boot_to_title=false;app_b.deferred_startup=false;app_b.staged_navigation=false;app_b.economy=b
	root.add_child(app_b);await process_frame;app_b.page_motion=false;app_b.page_transition.cancel()
	# This fixture checks isolated appearance registries. New-profile story
	# routing is exercised separately; explicitly open the secretary surface.
	app_b.show_page("harbor");await app_b.wait_for_page("harbor");await process_frame
	var b_service=Appearance.new(b)
	check(b_service.selected(ID)=="base" and str(app_b.cards[ID].portrait)==BASE,"account B level19 falls back to own base")
	check(not b_service.choose(ID,"military").ok,"account B cannot select locked military appearance")
	var b_secretary:TextureRect=app_b.page.find_child("SecretaryPortrait",true,false)
	check(b_secretary!=null and origin(b_secretary.texture)==BASE,"account B actual secretary stays base while A is military")
	check(str(app.cards[ID].portrait)==MILITARY,"B startup does not override A registry")
	app.show_page("harbor");await process_frame
	secretary=app.page.find_child("SecretaryPortrait",true,false)
	check(secretary!=null and origin(secretary.texture)==MILITARY,"A rerender remains military after B refresh")
	check(str(Art.visual_card(raw,app.cards).portrait)==MILITARY and str(Art.visual_card(raw,app_b.cards).portrait)==BASE,"explicit registry selects each account appearance")
	b.state.owned.erase(ID);Appearance.refresh(app_b)
	check(str(app_b.cards[ID].portrait)==BASE and str(app.cards[ID].portrait)==MILITARY,"B unowned identity never borrows A military appearance")
	b.state.owned[ID]=b._new_owned(ID);b.state.owned[ID].level=19;Appearance.refresh(app_b)
	var impact_a=load("res://scripts/combat_impact.gd").new();impact_a.catalog=app.cards
	var impact_b=load("res://scripts/combat_impact.gd").new();impact_b.catalog=app_b.cards
	impact_a.fire(ship,{"x":0.0,"y":0.0})
	check(Art.active_pose(app.cards[ID])=="fire" and Art.active_pose(app_b.cards[ID])=="idle","A firing pose does not leak to B same identity")
	impact_b.hurt(ship,.05)
	check(Art.active_pose(app_b.cards[ID])=="hit" and Art.active_pose(app.cards[ID])=="fire","B positive-damage pose does not replace A firing pose")
	impact_b.reset();impact_b.hurt(ship,0.0)
	check(Art.active_pose(app_b.cards[ID])=="idle" and Art.active_pose(app.cards[ID])=="fire","B reset and zero damage leave A event intact")
	Art.trigger_pose(app.cards[ID],"fire",.01);OS.delay_msec(25)
	check(Art.active_pose(app.cards[ID])=="idle" and Art.active_pose(app_b.cards[ID])=="idle","each account event expires back to idle")
	check(Art.active_pose(raw)=="idle","raw preview never receives a battle pose from either account")
	check(service.choose(ID,"base").ok,"switch back to base on isolated account")
	Appearance.refresh(app)
	check(origin(tide._texture(ship,"ship")).ends_with("missouri-sd-atlas.png"),"roguelike cache follows appearance change")
	littoral.observe(observation)
	check(origin(littoral.textures[ID]).ends_with("missouri-sd-atlas.png"),"littoral cache follows appearance change")
	check(account._cards[ID]==raw,"catalogue card was never mutated")
	check(account.state.owned[ID]==numerical,"owned ship numerical growth data never changes")
	var final_user_hash:String=FileAccess.get_sha256("user://cas_port_v1.json") if FileAccess.file_exists("user://cas_port_v1.json") else ""
	check(final_user_hash==user_hash,"real user save file stays byte-identical")
	stage.free();tide.free();littoral.free();app.core.close();app_b.core.close();app.free();app_b.free()
	var report:Dictionary={"checks":checks,"failures":failures,"isolated_profile":account_path,"second_isolated_profile":b_path,"real_user_save_unchanged":final_user_hash==user_hash,"game_window_opened":false,"gpu_visual_qa":false}
	FileAccess.open("res://../artifacts/canon-v2-art/appearance-consumption-review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("APPEARANCE_CONSUMPTION %d/%d"%[checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
