extends SceneTree
func _initialize()->void:
 var bridge=load("res://scripts/core_bridge.gd").new()
 var r=bridge.request({"op":"island_home_preview","version":"cas-island-war-v4","seed":1387249,"hq_level":5,"buildings":[]});bridge.close()
 var d:Dictionary=r.data;var p=load("res://scripts/home_projection_v4.gd").new();p.bind({"land":d.littoral.land,"construction_grid":d.construction_grid});p.screen=Rect2(0,0,2000,1600)
 var w:Vector2=p.world(Vector2(15,22));var s:Vector2=p.project(w);var u:Vector2=p.unproject(s)
 print("INVERSE ",w," elevation ",p.height(w)," screen ",s," => ",u," elevation ",p.height(u)," residual ",p.project(u).distance_to(s)," cell ",p.cell_at(s))
 quit()
