"""CAS coastal art sample. Original craft/APC; CC0 Quaternius tank conversion.
Run only in an independent Blender background process, never in a user's file.
Blender +Y is forward; GLB/Godot -Z is forward. One Blender unit is one metre.
"""
import bpy, math, json, hashlib
from pathlib import Path
from mathutils import Vector, Matrix

OUT=Path(__file__).parent.parent
SOURCE=OUT/'source'
SOURCE.mkdir(exist_ok=True)
MATS={}
def linear(v): return v/12.92 if v<.04045 else ((v+.055)/1.055)**2.4
def mat(name,hexcol,metal=0):
    m=bpy.data.materials.new(name); m.use_nodes=True
    rgb=tuple(int(hexcol[i:i+2],16)/255 for i in (0,2,4))
    col=tuple(linear(v) for v in rgb)+(1,)
    m.diffuse_color=col
    bs=m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=col; bs.inputs['Metallic'].default_value=metal
    bs.inputs['Roughness'].default_value=.72
    MATS[name]=m; return m
def clear():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def assign(o,m):
    o.data.materials.clear(); o.data.materials.append(MATS[m]); return o
def box(name,loc,size,m,bevel=.035):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.name=name
    o.scale=size; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    assign(o,m)
    if bevel:
        b=o.modifiers.new('Soft armour edges','BEVEL'); b.width=bevel; b.segments=2
        o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o
def cyl(name,loc,r,depth,m,axis='Z',vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=depth,location=loc)
    o=bpy.context.object; o.name=name
    if axis=='X': o.rotation_euler.y=math.pi/2
    if axis=='Y': o.rotation_euler.x=math.pi/2
    assign(o,m)
    for p in o.data.polygons: p.use_smooth=len(p.vertices)==4
    return o
def beam(name,a,b,r,m):
    a,b=Vector(a),Vector(b); o=cyl(name,(a+b)*.5,r,(b-a).length,m)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler(); return o
def hull(name,sections,m):
    # Each section: longitudinal Y, half-width, bottom Z, top Z, top-width factor.
    verts=[]
    for y,w,b,t,f in sections: verts += [(-w*.85,y,b),(w*.85,y,b),(w*f,y,t),(-w*f,y,t)]
    faces=[(3,2,1,0)]
    for i in range(len(sections)-1):
        a=i*4; faces += [(a+j,a+(j+1)%4,a+4+(j+1)%4,a+4+j) for j in range(4)]
    a=(len(sections)-1)*4; faces.append(tuple(a+j for j in range(4)))
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    o=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(o); assign(o,m)
    b=o.modifiers.new('Rounded plate seams','BEVEL'); b.width=.06; b.segments=2
    o.modifiers.new('Weighted normals','WEIGHTED_NORMAL'); return o
def torus(name,loc,major,minor,m,rotation=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=16,minor_segments=6,location=loc,major_radius=major,minor_radius=minor,rotation=rotation)
    o=bpy.context.object; o.name=name; assign(o,m); return o
def anchor(name,loc):
    o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o); o.location=loc; return o
def bake_objects():
    dg=bpy.context.evaluated_depsgraph_get()
    for o in list(bpy.context.scene.objects):
        if o.type!='MESH': continue
        e=o.evaluated_get(dg); mesh=bpy.data.meshes.new_from_object(e,depsgraph=dg)
        o.modifiers.clear(); o.data=mesh
    # One mesh for the fixed hull and one per rigid articulated assembly.
    # Shared slots are consolidated; articulated parents survive for animation.
    groups={}
    for o in bpy.context.scene.objects:
        if o.type=='MESH': groups.setdefault(o.parent if o.parent and o.parent.get('articulated',False) else None,[]).append(o)
    for parent,fixed in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in fixed: o.select_set(True)
        bpy.context.view_layer.objects.active=fixed[0]
        bpy.ops.object.join()
        fixed[0].name='Hull' if parent is None else parent.name+'Visual'
        # Consolidate duplicate material slots left by joining repeated primitives.
        obj=fixed[0]; old=list(obj.data.materials); unique=[]
        for m in old:
            if m not in unique: unique.append(m)
        idx=[unique.index(m) for m in old]
        polygon_materials=[idx[p.material_index] for p in obj.data.polygons]
        obj.data.materials.clear()
        for m in unique: obj.data.materials.append(m)
        for p,index in zip(obj.data.polygons,polygon_materials): p.material_index=index
        # A shared vertex-colour palette keeps all original per-part colours
        # while each rigid assembly exports as one surface, without textures.
        for old_colours in list(obj.data.color_attributes): obj.data.color_attributes.remove(old_colours)
        colours=obj.data.color_attributes.new(name='CASPalette',type='FLOAT_COLOR',domain='CORNER')
        obj.data.color_attributes.active_color=colours
        for polygon in obj.data.polygons:
            colour=unique[polygon.material_index].diffuse_color
            for loop_index in polygon.loop_indices: colours.data[loop_index].color=colour
        palette=bpy.data.materials.get('CAS vehicle vertex palette')
        if palette is None:
            palette=bpy.data.materials.new('CAS vehicle vertex palette'); palette.use_nodes=True
            vertex=palette.node_tree.nodes.new('ShaderNodeVertexColor'); vertex.layer_name='CASPalette'
            bs=palette.node_tree.nodes.get('Principled BSDF')
            bs.inputs['Roughness'].default_value=.72
            palette.node_tree.links.new(vertex.outputs['Color'],bs.inputs['Base Color'])
        obj.data.materials.clear(); obj.data.materials.append(palette)
def save(name,metadata):
    if name=='cas_amphibious_apc':
        for o in bpy.context.scene.objects:
            if o.parent is None: o.location.z-=.04
    bake_objects()
    bpy.ops.object.select_all(action='DESELECT')
    for o in bpy.context.scene.objects: o.select_set(True)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_animations=False,export_extras=True)
    bpy.context.view_layer.update()
    dg=bpy.context.evaluated_depsgraph_get(); pts=[]; tris=0; mats=set()
    for o in bpy.context.scene.objects:
        if o.type!='MESH': continue
        e=o.evaluated_get(dg); mesh=e.to_mesh(); mesh.calc_loop_triangles()
        tris+=len(mesh.loop_triangles); mats.update(m.name for m in mesh.materials if m)
        pts += [e.matrix_world@v.co for v in mesh.vertices]
        e.to_mesh_clear()
    metadata.update({'id':name,'triangles':tris,'materials':len(mats),'material_names':sorted(mats),'blender_size_m':[round(max(v[i] for v in pts)-min(v[i] for v in pts),3) for i in range(3)],'sha256':hashlib.sha256((OUT/(name+'.glb')).read_bytes()).hexdigest(),'forward_godot':'-Z','up_godot':'+Y','blender_version':bpy.app.version_string})
    print('VEHICLE_BUILT '+json.dumps(metadata))
    return metadata

mat('Sage armour','829180'); mat('Dark sage','52685d'); mat('Warm deck','c5bc9e')
mat('Dark rubber','303c3e'); mat('Edge steel','bbc5ba',.15); mat('Window teal','214d60',.1)
mat('Cream marking','eee5c6'); mat('Warning ochre','d7ac51'); mat('Interior','67736c')
mat('Track metal','46504a',.1); mat('Red lens','c9634d')

def landing_craft():
    clear()
    hull('Flat-bottom displacement hull',[(-6.7,2.2,-.8,.45,1),(-4.7,2.42,-.8,.50,1),(4.8,2.38,-.65,.50,1),(6.7,2.10,-.30,.55,1)],'Dark sage')
    box('Open cargo deck',(0,1.05,.5),(3.65,10.9,.20),'Warm deck')
    for s in (-1,1):
        box('Protective side wall',(s*2.16,.45,1.05),(.35,11.75,1.20),'Sage armour')
        box('Gunnel steel cap',(s*2.16,.4,1.72),(.43,11.85,.12),'Edge steel')
        box('Internal bench',(s*1.63,.7,.83),(.4,9.3,.20),'Interior')
        for y in [-4.5,-1.5,1.5,4.5]:
            torus('Hanging tyre fender',(s*2.40,y,.62),.35,.12,'Dark rubber',(0,math.pi/2,0))
            box('Hull external rib',(s*2.36,y,.9),(.10,.12,1.4),'Dark sage',.015)
        for y in [-5.8,4.8]:
            cyl('Mooring bollard',(s*1.94,y,1.90),.10,.33,'Track metal')
            beam('Bollard crossbar',(s*1.94-.21,y,2.0),(s*1.94+.21,y,2.0),.055,'Track metal')
    box('Rear machinery roof',(0,-5.28,.98),(3.65,2.9,.85),'Sage armour')
    box('Offset wheelhouse',(.72,-5.15,2.20),(2.08,2.0,2.0),'Sage armour')
    box('Cabin roof',(.72,-5.15,3.25),(2.30,2.2,.14),'Edge steel')
    box('Forward glazing',(.72,-4.12,2.51),(1.64,.045,.69),'Window teal',.015)
    box('Front glazing divider',(.72,-4.08,2.51),(.085,.05,.72),'Edge steel',.01)
    box('Side glazing',(1.785,-5.10,2.51),(.045,1.3,.69),'Window teal',.015)
    box('Wheelhouse door',(-.35,-5.14,2.1),(.04,.8,1.6),'Dark sage',.01)
    beam('Cabin rail',(-1.6,-4.8,1.7),(-1.6,-6.25,1.7),.045,'Edge steel')
    for y in [-4.8,-5.5,-6.25]: beam('Rail stanchion',(-1.6,y,1.25),(-1.6,y,1.7),.04,'Edge steel')
    cyl('Exhaust stack',(-.98,-5.8,2.15),.16,1.3,'Track metal')
    cyl('Antenna',(.35,-5.55,4.05),.025,1.5,'Dark rubber',vertices=6)
    cyl('Navigation beacon',(1.35,-5.55,3.48),.10,.25,'Red lens')
    hinge=anchor('Ramp',(0,6.42,.62)); hinge['articulated']=True
    ramp=box('Bow ramp plate',(0,6.42,1.35),(3.85,.16,1.52),'Sage armour'); ramp['articulated']=True
    ramp.parent=hinge; ramp.matrix_parent_inverse=hinge.matrix_world.inverted()
    for z in [.8,1.1,1.4,1.7,2.0]:
        rib=box('Ramp traction rib',(0,6.31,z),(3.6,.08,.05),'Edge steel',.01)
        rib['articulated']=True; rib.parent=hinge; rib.matrix_parent_inverse=hinge.matrix_world.inverted()
    for y in [-3.7,-2.5,-1.3,-.1,1.1,2.3,3.5,4.7]:
        box('Deck seam',(0,y,.612),(3.52,.035,.016),'Interior',0)
    anchor('Waterline',(0,0,0)); anchor('UnloadPoint',(0,7.7,.50)); anchor('DeckPassengerAnchor',(0,1,.72))
    return save('cas_landing_craft',{'source':'CAS original Blender construction after free military landing-craft search found only unsuitable civilian/sailing craft','license':'Project original','length_class_m':14,'waterline_y':0.0,'articulated_nodes':['Ramp'],'ramp_open_rotation_x_rad':-1.4})

def amphibious_carrier():
    clear()
    hull('Boat-shaped armoured chassis',[(-3.85,1.56,.62,1.85,1),(-2.7,1.65,.52,2.10,1),(1.8,1.65,.58,2.05,.90),(3.85,1.32,1.10,1.80,.93)],'Sage armour')
    box('Engine deck',(-.75,-2.6,2.15),(1.3,1.45,.13),'Dark sage')
    for y in [-3.1,-2.85,-2.6,-2.35,-2.1]: box('Engine cooling slat',(-.75,y,2.24),(1.2,.09,.09),'Track metal',.01)
    for s in (-1,1):
        box('Armour skirt',(s*1.63,0,1.18),(.15,6.85,.55),'Dark sage')
        for y in [-2.65,-.9,.9,2.65]:
            cyl('Run-flat tyre',(s*1.63,y,.73),.69,.45,'Dark rubber','X',16)
            cyl('Wheel hub',(s*1.88,y,.73),.34,.055,'Sage armour','X',12)
            cyl('Wheel hub centre',(s*1.92,y,.73),.11,.07,'Edge steel','X',10)
        box('Side equipment bin',(s*1.58,-1.65,1.94),(.30,1.25,.5),'Interior')
        beam('Deck handrail',(s*1.37,-2.0,2.34),(s*1.37,.3,2.34),.045,'Edge steel')
        for y in [-1.9,-.8,.25]: beam('Handrail peg',(s*1.37,y,2.05),(s*1.37,y,2.34),.04,'Edge steel')
        box('Front viewing port',(s*.65,2.58,1.98),(.7,.16,.22),'Window teal')
        cyl('Headlamp',(s*1.10,3.34,1.58),.14,.07,'Cream marking','Y')
        cyl('Rear jet outlet',(s*.96,-3.91,.96),.28,.2,'Track metal','Y')
        cyl('Rear jet dark opening',(s*.96,-4.025,.96),.19,.03,'Dark rubber','Y')
    hull('Bow trim vane',[(2.70,1.35,1.63,1.70,1),(3.65,1.24,1.60,1.66,1)],'Dark sage')
    turret=anchor('Turret',(0,.55,2.08)); turret['articulated']=True
    parts=[]
    parts.append(cyl('Turret race',(0,.55,2.18),.88,.22,'Track metal'))
    parts.append(box('Weapon station',(0,.55,2.58),(1.43,1.35,.68),'Dark sage',.14))
    parts.append(cyl('Autocannon',(0,2.12,2.66),.09,2.05,'Track metal','Y'))
    parts.append(cyl('Muzzle',(0,3.11,2.66),.13,.25,'Track metal','Y'))
    parts.append(box('Optic',(.65,.84,2.83),(.20,.35,.25),'Window teal'))
    for part in parts:
        part['articulated']=True; part.parent=turret; part.matrix_parent_inverse=turret.matrix_world.inverted()
    cyl('Crew hatch',(.85,-.85,2.17),.41,.12,'Edge steel')
    cyl('Radio mast',(-1.15,-1.05,3.05),.025,1.9,'Dark rubber',vertices=6)
    box('Rear dismount ramp',(0,-3.86,1.35),(1.55,.09,1.20),'Dark sage')
    box('Side recognition stripe',(1.728,.0,1.6),(.025,1.10,.20),'Cream marking',0)
    anchor('GroundContact',(0,0,0)); anchor('Waterline',(0,0,.85)); anchor('UnloadPoint',(0,-4.6,.15)); anchor('Muzzle',(0,3.26,2.66))
    return save('cas_amphibious_apc',{'source':'CAS original Blender construction; amphibious carrier with deck details and separate weapon station','license':'Project original','waterline_godot_y':.85,'articulated_nodes':['Turret'],'length_class_m':8.5})

def converted_tank():
    clear(); bpy.ops.import_scene.gltf(filepath=str(OUT/'vendor/Tank.glb'))
    dg=bpy.context.evaluated_depsgraph_get(); baked=[]
    rot=Matrix.Rotation(-math.pi/2,4,'Z'); scale=Matrix.Scale(.52,4)
    silhouette=Matrix.Diagonal((.75,1.0,.8,1.0))
    ground_offset=Matrix.Translation((0,0,.009915))
    for o in list(bpy.context.scene.objects):
        if o.type!='MESH' or o.name=='Icosphere': continue
        e=o.evaluated_get(dg); mesh=bpy.data.meshes.new_from_object(e,depsgraph=dg)
        mesh.transform(ground_offset@silhouette@scale@rot@e.matrix_world)
        n=bpy.data.objects.new('TurretVisual' if o.name in ('Tank_Turret','Tank_Gun') else 'Tank_'+o.name,mesh)
        baked.append(n)
        for i,m in enumerate(mesh.materials):
            name=m.name.lower()
            mesh.materials[i]=MATS['Dark rubber' if 'wheel' in name else 'Track metal' if 'details' in name else 'Dark sage' if 'dark' in name else 'Edge steel' if 'light' in name else 'Sage armour']
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    for n in baked: bpy.context.collection.objects.link(n)
    # Quaternius front is -X in Blender; turn it to +Y, GLB forward -Z.
    turret=anchor('Turret',(0,-.55,1.65*.8+.009915)); turret['articulated']=True
    for n in baked:
        if n.name.startswith('TurretVisual'):
            n['articulated']=True; n.parent=turret; n.matrix_parent_inverse=Matrix.Translation(-turret.location)
    anchor('GroundContact',(0,0,0)); anchor('Muzzle',(0,5.12,2.03*.8+.009915))
    return save('cas_tank_cc0',{'source':'Quaternius Animated Tanks Pack / Tank.glb via trebeljahr converted mirror','source_url':'https://quaternius.com/packs/animatedtanks.html','download_url':'https://raw.githubusercontent.com/trebeljahr/quaternius-showcase/main/public/glb/tank_pack/Tank.glb','license':'CC0-1.0','modifications':'Bake rest geometry, remove stray Icosphere, normalize original -X forward to GLB -Z, metre scale, recolour shared palette, independent turret pivot. Original source rig/track animation kept separately in vendor/Tank.glb.','articulated_nodes':['Turret'],'length_class_m':8.9})

if __name__ == '__main__':
    results=[landing_craft(),amphibious_carrier(),converted_tank()]
    (OUT/'vehicle-manifest.json').write_text(json.dumps({'date':'2026-11-16','models':results},ensure_ascii=False,indent=2),encoding='utf-8')
