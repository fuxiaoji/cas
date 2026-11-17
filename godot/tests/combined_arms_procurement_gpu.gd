extends "res://tests/littoral_drag_v2_review.gd"
func run()->void:
	output_dir="res://../artifacts/combined-arms-v4/procurement/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile);account.load_state()
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var before:Dictionary=account.state.duplicate(true);app.home.state().unlocked=true;app.home.state().tutorial_complete=true;account.state.wallet.origins=3000
	app.home._own_unit("MCP-034");app.home._own_unit("MCP-011");account._commit(before,"isolated progressed procurement UI fixture")
	app.show_page("home");await frames()
	await click(app.page.get_node("HomeIsland/Layout/Bottom/Sortie"))
	var open:Button=app.modal.find_child("OpenAviationProcurement",true,false)
	if not check(open!=null,"aviation procurement visible from actual sortie"):return finish()
	await click(open)
	var wallet:int=int(account.state.wallet.origins)
	for row in app.home.aviation_ships:check(ResourceLoader.exists(str(row.portrait)),"original portrait imported "+str(row.id))
	await shot("four-new-ships")
	var acquire:Button=app.modal.find_child("Procure_CAS-O-LHA-RETURNLIGHT",true,false)
	if not check(acquire!=null and not acquire.disabled,"actual qualified transport procurement button enabled"):return finish()
	await click(acquire)
	check(account.state.owned.has("CAS-O-LHA-RETURNLIGHT") and int(account.state.wallet.origins)==wallet-900,"pointer receives real LHA with exact debit")
	check(app.modal.find_child("Procure_CAS-O-LHA-RETURNLIGHT",true,false).disabled,"owned receive action disabled after commit")
	await click(app.modal.get_node("ModalNavigateBack"))
	check(app.modal.find_child("Sortie_CAS-O-LHA-RETURNLIGHT",true,false)!=null,"one-level back returns to sortie with owned LHA")
	await shot("owned-qualified-carrier")
	await click(app.modal.get_node("ModalNavigateHome"))
	check(app.screen=="harbor" and not is_instance_valid(app.modal),"direct harbor exit remains reachable")
	finish()
