import bpy,json
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath='D:/desktop/cas/demos/land-art-3d/assets/vehicles3d/vendor/utility-helicopter-cc0.glb')
for o in bpy.context.scene.objects:
 print('HELI_PART',o.name,o.type,'parent',o.parent.name if o.parent else None,'loc',tuple(round(v,3) for v in o.location),'dim',tuple(round(v,3) for v in o.dimensions),'mats',[m.name for m in o.data.materials] if o.type=='MESH' else [])
