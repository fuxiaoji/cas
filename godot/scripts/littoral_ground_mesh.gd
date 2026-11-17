@tool
extends RefCounted
## Triangulate in native world space before height projection can fold an edge.
static var cache:Dictionary={}
static func paint(canvas:CanvasItem,world:PackedVector2Array,projector:Callable,tint:Color,texture:Texture2D=null,coordinates:PackedVector2Array=PackedVector2Array(),flat_projector:Callable=Callable(),max_step_m:float=0,edge_m:float=128)->void:
	if world.size()<3:return
	var key:int=hash([world,coordinates,edge_m])
	if not cache.has(key):
		# A large island has more than a thousand 256m material cells. A small
		# FIFO would evict every visible mesh each frame at the overview zoom.
		while cache.size()>=4096:cache.erase(cache.keys()[0])
		var indices:PackedInt32Array=Geometry2D.triangulate_polygon(world);var pending:Array=[];var triangles:Array=[]
		for index in range(0,indices.size(),3):
			var points:PackedVector2Array=[];var uv:PackedVector2Array=[]
			for corner in range(3):
				var source:int=indices[index+corner];points.append(world[source])
				if coordinates.size()==world.size():uv.append(coordinates[source])
			pending.append({"points":points,"uv":uv,"depth":0})
		# Projecting only the corners makes a long road or river cut straight
		# through a hill. Cache a world-space mesh before applying the same height
		# function as bodies and buildings. This changes no terrain or collision.
		while not pending.is_empty():
			var triangle:Dictionary=pending.pop_back();var points:PackedVector2Array=triangle.points
			var edge:int=0;var longest:float=0
			for i in range(3):
				var length:float=points[i].distance_squared_to(points[(i+1)%3])
				if length>longest:longest=length;edge=i
			if longest<=edge_m*edge_m or int(triangle.depth)>=14:triangles.append(triangle);continue
			var a:int=edge;var b:int=(edge+1)%3;var c:int=(edge+2)%3;var middle:Vector2=(points[a]+points[b])*.5
			for half in [0,1]:
				var next_points:PackedVector2Array=[points[a] if half==0 else middle,middle if half==0 else points[b],points[c]];var next_uv:PackedVector2Array=[]
				if not triangle.uv.is_empty():
					var uv_middle:Vector2=(triangle.uv[a]+triangle.uv[b])*.5
					next_uv=PackedVector2Array([triangle.uv[a] if half==0 else uv_middle,uv_middle if half==0 else triangle.uv[b],triangle.uv[c]])
				pending.append({"points":next_points,"uv":next_uv,"depth":int(triangle.depth)+1})
		cache[key]=triangles
	for triangle in cache[key]:
		var vertices:PackedVector2Array=[];var uv:PackedVector2Array=[]
		var low:float=INF;var high:float=-INF
		for corner in range(3):
			vertices.append(projector.call(triangle.points[corner]))
			if flat_projector.is_valid() and max_step_m>0:
				var height:float=(flat_projector.call(triangle.points[corner]) as Vector2).y-vertices[corner].y
				low=minf(low,height);high=maxf(high,height)
			if not triangle.uv.is_empty():uv.append(triangle.uv[corner])
		if flat_projector.is_valid() and max_step_m>0:
			var scale:float=(flat_projector.call(triangle.points[0]+Vector2.RIGHT) as Vector2).distance_to(flat_projector.call(triangle.points[0]))
			# A paved surface stops at a vertical step. Only the terrain wall
			# renderer draws that face; roads must not become upright ribbons.
			if high-low>max_step_m*scale:continue
		if absf((vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]))<.001:continue
		if canvas is Control:
			var bounds:Rect2=Rect2(vertices[0],Vector2.ZERO)
			for point in vertices:bounds=bounds.expand(point)
			if not bounds.intersects(Rect2(Vector2.ZERO,canvas.size).grow(2),true):continue
		# These are already triangulated. Sending tiny overview triangles back to
		# the polygon triangulator can fail after screen-space float rounding.
		canvas.draw_primitive(vertices,PackedColorArray([tint]),uv,texture)
