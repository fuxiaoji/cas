extends RefCounted
## Exact adapter for the native cas-coastal-geography-v1 triangle grid.
## No procedural height source exists in this display module.
var origin:Vector2
var cell_size:float=1.0
var columns:int=0
var rows:int=0
var heights:PackedFloat32Array=[]
var biomes:Array=[]
var water:PackedFloat32Array=[]
var geometry_hash:String=""
var height_bounds:Vector2=Vector2.ZERO

func bind(source:Dictionary)->bool:
	var field:Dictionary=source.get("heightfield",{})
	columns=int(field.get("columns",0));rows=int(field.get("rows",0))
	cell_size=float(field.get("cell_size_m",0.0))
	var offset:Dictionary=field.get("origin",{});origin=Vector2(float(offset.get("x",0)),float(offset.get("y",0)))
	heights=PackedFloat32Array(field.get("heights",[]));water=PackedFloat32Array(source.get("water_levels",[]));biomes=source.get("biomes",[])
	geometry_hash=str(source.get("geometry_hash",source.get("id","")))
	height_bounds=Vector2.ZERO
	for h:float in heights:height_bounds.x=minf(height_bounds.x,h);height_bounds.y=maxf(height_bounds.y,h)
	return columns>=2 and rows>=2 and cell_size>0 and heights.size()==columns*rows

func _interpolate(values:PackedFloat32Array,point:Vector2)->float:
	if values.size()!=columns*rows:return 0.0
	var local:Vector2=(point-origin)/cell_size
	var x:int=clampi(floori(local.x),0,columns-2);var y:int=clampi(floori(local.y),0,rows-2)
	var u:float=clampf(local.x-x,0,1);var v:float=clampf(local.y-y,0,1)
	var a:int=y*columns+x;var b:int=a+1;var c:int=a+columns;var d:int=c+1
	if u+v<=1.0:return values[a]+(values[b]-values[a])*u+(values[c]-values[a])*v
	return values[d]+(values[c]-values[d])*(1.0-u)+(values[b]-values[d])*(1.0-v)

func contains(point:Vector2)->bool:
	var local:Vector2=(point-origin)/cell_size
	return local.x>=0.0 and local.y>=0.0 and local.x<=columns-1 and local.y<=rows-1
func height_at(point:Vector2)->float:return _interpolate(heights,point) if contains(point) else -32.0
func water_at(point:Vector2)->float:return maxf(0.0,_interpolate(water,point)) if contains(point) else 0.0
func surface_at(point:Vector2)->float:return maxf(height_at(point),water_at(point))

func normal_at(x:int,y:int)->Vector3:
	var dx:float=(heights[y*columns+mini(columns-1,x+1)]-heights[y*columns+maxi(0,x-1)])/(cell_size*2.0)
	var dz:float=(heights[mini(rows-1,y+1)*columns+x]-heights[maxi(0,y-1)*columns+x])/(cell_size*2.0)
	return Vector3(-dx,1.0,-dz).normalized()

func biome_at(x:int,y:int)->String:
	var index:int=y*columns+x
	return str(biomes[index]) if index<biomes.size() else "grass"
