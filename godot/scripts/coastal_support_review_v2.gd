extends SceneTree
const Profile=preload("res://scripts/naval_support_visual_profile.gd")
const FX=preload("res://scripts/littoral_support_fx.gd")
var failures:Array[String]=[]
var checks:int=0
class MapStub extends Control:
	var playing:bool=true
	var miniature:bool=false
	var playback_rate:float=1.0
	func project(point:Vector2)->Vector2:return point*3.0+Vector2(80,80)
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func salvo(caliber:float,radius:float,coastal:bool=true)->Dictionary:
	var shots:Array=[]
	for index:int in range(8):
		var shot:Dictionary={"id":str(index),"kind":"naval","tick":0,"x":0,"y":0,"target_x":40+index*2,"target_y":30,"flight_seconds":1,"caliber_mm":caliber,"blast_radius_m":radius}
		if coastal:shot["tuning_profile"]="coastal-combat-v2"
		shots.append(shot)
	return {"tick":1.0,"art_version":"tactical-art-v2","shots":shots}
func run()->void:
	var light:Dictionary=Profile.for_caliber(127)
	var capital:Dictionary=Profile.for_caliber(406)
	check(str(light.tier)=="light" and str(capital.tier)=="capital","127 and 406 have distinct presentations")
	check(float(capital.shell_px)>float(light.shell_px)*2,"capital shell visibly heavier")
	check(float(capital.life_s)>float(light.life_s)*2,"light burst clears quickly")
	check(pow(float(light.shake),2)*9<.5,"light impact has less than half-pixel kick")
	var canvas:=MapStub.new();root.add_child(canvas)
	var effect=FX.new();effect.source_map=canvas;canvas.add_child(effect);effect.set_process(false)
	effect.observe(salvo(127,5.08),true);effect._process(.001)
	check(effect.records.size()==8,"each of eight actual launch records retained")
	check(float(effect.trauma)<=.2,"eight small impacts do not accumulate capital shake")
	for row:Dictionary in effect.records.values():
		var outline:PackedVector2Array=effect.blast_outline(row,1.0)
		var precise:bool=outline.size()==49
		for point:Vector2 in outline:precise=precise and absf(point.distance_to(canvas.project(row.end))-5.08*3)<.001
		check(precise,"outline uses true 5.08 metre radius")
	effect.observe(salvo(406,16.24),true);effect._process(.001)
	check(float(effect.trauma)>.9,"406 impact retains strong feedback")
	effect.observe({"tick":0.0,"shots":[]})
	check(effect.records.is_empty() and is_zero_approx(float(effect.trauma)),"rewind clears bursts and camera kick")
	effect.observe(salvo(127,69.85,false),true);effect._process(.001)
	check(float(effect.trauma)>.9,"legacy visual behavior preserved")
	canvas.playing=false;effect.trauma=0;effect.impacts_seen.clear();effect._process(.01)
	check(is_zero_approx(float(effect.trauma)),"paused frame does not trigger impact")
	canvas.free()
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"scope":"synthetic presentation contracts; actual combat tested separately"}
	var path:String="res://../artifacts/coastal-rebuild-20261116/support-v2-review.json"
	var out:=FileAccess.open(path,FileAccess.WRITE);out.store_string(JSON.stringify(report,"  "));out.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
