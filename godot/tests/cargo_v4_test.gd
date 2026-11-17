extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Service=preload("res://scripts/cargo_service.gd")
const Presentation=preload("res://scripts/cargo_presentation.gd")
const CargoGrid=preload("res://scripts/cargo_grid.gd")
var errors:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:
	call_deferred("run")
func run()->void:
	var account=Economy.new();account.save_path="user://cargo-v4-test.json";account.load_state()
	account.new_profile()
	account.state.active_run={}
	var service=Service.new(account)
	check(service.set_options({"difficulty":"calm","environment":"atoll","weather":"clear"}).ok,"valid options")
	check(not service.set_options({"difficulty":"impossible"}).ok,"invalid options rejected")
	check(not service.set_options({"unknown":true}).ok,"unknown options rejected")
	var shape:Dictionary={"id":"one","kind":"equipment","name":"封存舰装","shape":[[0,0],[0,1],[1,1]],"kg":90,"value":360,"ruin":1,"placement":[0,0,0]}
	check(service.can_fit([shape],shape,[0,0,1],3,3),"rotation fits")
	var second:Dictionary=shape.duplicate(true);second.id="two"
	check(not service.can_fit([shape],second,[0,0,0],3,3),"overlap blocked")
	check(not service.can_fit([],shape,[2,2,0],3,3),"bounds blocked")
	check(Service.validate_receipt([shape],{"equipment":1},true),"valid physical receipt")
	check(not Service.validate_receipt([shape],{"equipment":2},true),"counts mismatch blocked")
	account.state.cargo_stash={"version":"cargo-stash-v1","items":[]}
	service.receive([shape],{"run_id":"cargo-test","cargo_v4":{"difficulty":"standard"}})
	check(service.stash().items.size()==1,"physical stash receive")
	service.receive([shape],{"run_id":"cargo-test","cargo_v4":{"difficulty":"standard"}})
	check(service.stash().items.size()==1,"receive idempotent")
	check(service.place_stash("cargo-test:one",[8,3,1]).ok,"stash legal move")
	check(not service.place_stash("cargo-test:one",[99,99,0]).ok,"stash invalid move")
	var count:int=account.state.item_instances.size()
	check(service.consume("cargo-test:one").ok,"unpack once")
	check(account.state.item_instances.size()==count+1,"gear physically created on unpack")
	check(not service.consume("cargo-test:one").ok,"double unpack blocked")
	var big:Dictionary=shape.duplicate(true);big.id="full";big.shape=[]
	for yy in range(int(service.stash().rows)):
		for xx in range(10):big.shape.append([xx,yy])
	account.state.cargo_stash.items=[big]
	service.receive([shape],{"run_id":"overflow-test","cargo_v4":{"difficulty":"hazard"}})
	check(service.stash().items.size()==2 and service.stash().items[1].placement==null,"full port stash preserves overflow")
	check(service.consume("overflow-test:one").ok,"overflow can be unpacked without deletion")
	var last:Dictionary=account.state.item_instances.values()[-1]
	check(int(last.quality)>=3,"hazard gear quality floor applied when unpacked")
	check(account.save_state().ok,"stash commits to account save")
	var restored=Economy.new(account.save_path);check(restored.load_state().ok,"stash account reload")
	check(restored.state.cargo_stash.items.size()==1 and Service.item_cells(restored.state.cargo_stash.items[0],restored.state.cargo_stash.items[0].placement)==Service.item_cells(big,big.placement),"stash exact coordinates restored")
	account.state.active_run={"run_id":"locked"}
	check(not service.set_options({"weather":"fog"}).ok,"active options locked")
	check(not service.consume("cargo-test:one").ok,"active stash locked")
	var app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false
	root.add_child(app);await process_frame
	Presentation.open_stash(app);await process_frame;check(is_instance_valid(app.modal),"stash scene opens")
	app.close_modal();Presentation.open_loadout(app);await process_frame;check(is_instance_valid(app.modal),"loadout scene opens")
	app.close_modal();app.queue_free();await process_frame
	var report:Dictionary={"cargo_v4_test":errors.is_empty(),"checks":checks,"passed":checks-errors.size(),"errors":errors,"unit_fixtures":true}
	var folder:=ProjectSettings.globalize_path("res://../artifacts/godot/cargo-v4");DirAccess.make_dir_recursive_absolute(folder)
	var file:=FileAccess.open(folder.path_join("data.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
