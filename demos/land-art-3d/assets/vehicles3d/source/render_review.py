import bpy, math, json
from pathlib import Path
from mathutils import Vector
P=Path(__file__).parent.parent
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for i,name in enumerate(['cas_landing_craft','cas_amphibious_apc','cas_tank_cc0']):
    old=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(P/(name+'.glb')))
    new=set(bpy.data.objects)-old
    for o in new:
        if o.parent is None: o.location.x+=(i-1)*12
    dg=bpy.context.evaluated_depsgraph_get(); report=[]
    for o in new:
        if o.type=='MESH':
            e=o.evaluated_get(dg); pts=[e.matrix_world@Vector(v) for v in e.bound_box]
            report.append((o.name,[[round(min(p[k] for p in pts),3),round(max(p[k] for p in pts),3)] for k in range(3)]))
    print(name,report)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,0)); ground=bpy.context.object
m=bpy.data.materials.new('Review pale sand'); m.diffuse_color=(.72,.70,.60,1); ground.data.materials.append(m)
bpy.ops.object.light_add(type='AREA',location=(-15,-15,26)); l=bpy.context.object; l.data.energy=2200; l.data.shape='DISK'; l.data.size=20
l.rotation_euler=(Vector((0,0,0))-l.location).to_track_quat('-Z','Y').to_euler()
bpy.context.scene.world.color=(.7,.8,.85)
bpy.ops.object.light_add(type='SUN',rotation=(.45,-.5,-.8)); bpy.context.object.data.energy=2.0; bpy.context.object.data.angle=.35
bpy.ops.object.camera_add(location=(30,40,30)); c=bpy.context.object; c.rotation_euler=(Vector((0,0,1))-c.location).to_track_quat('-Z','Y').to_euler(); c.data.type='ORTHO'; c.data.ortho_scale=48
s=bpy.context.scene; s.camera=c; s.render.engine='CYCLES'; s.cycles.samples=24
s.render.resolution_x=1600; s.render.resolution_y=900; s.render.resolution_percentage=100
s.view_settings.view_transform='Standard'; s.view_settings.look='Medium High Contrast' if 'Medium High Contrast' in [] else 'None'
s.render.filepath=str(P/'vehicle-review.png'); bpy.ops.render.render(write_still=True)
