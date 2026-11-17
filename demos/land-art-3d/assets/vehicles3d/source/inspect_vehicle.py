import bpy, json
from mathutils import Vector
from pathlib import Path
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
p=Path(__file__).parent.parent
bpy.ops.import_scene.gltf(filepath=str(p/'vendor/Tank.glb'))
dg=bpy.context.evaluated_depsgraph_get()
report=[]
for o in bpy.context.scene.objects:
    if o.type=='MESH':
        e=o.evaluated_get(dg)
        pts=[e.matrix_world@Vector(v) for v in e.bound_box]
        report.append({'name':o.name,'min':[min(v[i] for v in pts) for i in range(3)],'max':[max(v[i] for v in pts) for i in range(3)],'mats':[m.name for m in o.data.materials]})
(p/'tank-inspection.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
