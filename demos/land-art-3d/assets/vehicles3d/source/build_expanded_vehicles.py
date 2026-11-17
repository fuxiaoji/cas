"""Five additional art-only vehicles. Run in a new Blender background process.
Leaves the original three GLB files untouched; exports one palette / rigid assembly.
Blender +Y forward, Z up; exported Godot -Z forward, Y up, metres.
"""
import sys, math, json, hashlib
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector, Matrix
sys.path.insert(0, str(Path(__file__).parent))
from build_vehicles import *
from build_vehicles import hull as original_hull_builder

ORIGINAL_IDS=('cas_landing_craft','cas_amphibious_apc','cas_tank_cc0')
ORIGINAL_HASHES={k:hashlib.sha256((OUT/(k+'.glb')).read_bytes()).hexdigest() for k in ORIGINAL_IDS}

def hull(name, sections, material):
    # Explicit outward normals on each new closed loft. The original three
    # approved binaries stay frozen; these new airframe canopies need culling
    # checked in Godot, where an inward top would disappear.
    obj=original_hull_builder(name,sections,material)
    edit=bmesh.new();edit.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(edit,faces=list(edit.faces))
    edit.to_mesh(obj.data);edit.free();obj.data.update()
    return obj

def attach(obj, pivot):
    bpy.context.view_layer.update()
    obj.parent=pivot
    obj.matrix_parent_inverse=Matrix.Translation(-pivot.location)
    obj['articulated']=True
    return obj

def sphere(name,loc,size,material,segments=16,rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=loc)
    obj=bpy.context.object;obj.name=name;obj.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    assign(obj,material)
    for p in obj.data.polygons:p.use_smooth=True
    return obj

def outline_pipe(name,points,r,material):
    # Rounded, closed polygon collar; deliberately restrained tube count.
    for i in range(len(points)-1):beam(name,points[i],points[i+1],r,material)
    for p in points:sphere(name+' round joint',p,(r,r,r),material,12,6)

def heavy_landing_craft():
    clear()
    hull('Heavy steel hull',[(-11.7,3.32,-1.22,.68,1),(-8.6,3.42,-1.22,.74,1),(8.7,3.38,-1.02,.76,1),(11.7,2.96,-.40,.80,1)],'Dark sage')
    box('Wide vehicle deck',(0,1.3,.80),(5.7,19.8,.24),'Warm deck')
    for side in (-1,1):
        box('Reinforced bulwark',(side*3.15,.7,1.34),(.38,21.1,1.30),'Sage armour')
        box('Steel gunnel',(side*3.15,.7,2.03),(.47,21.2,.14),'Edge steel')
        for y in [-9,-5.8,-2.6,.6,3.8,7.0,10.1]:
            box('Exterior buttress',(side*3.38,y,1.05),(.11,.18,1.7),'Dark sage',.02)
        for y in [-8.8,-2.5,4.0,9.5]:
            torus('Rubber fender',(side*3.45,y,.85),.42,.14,'Dark rubber',(0,math.pi/2,0))
        for y in [-9.9,9.7]:
            cyl('Mooring post',(side*2.8,y,2.26),.13,.42,'Track metal')
            beam('Bollard cross',(side*2.5,y,2.4),(side*3.08,y,2.4),.07,'Track metal')
    box('Aft engine compartment',(0,-9.20,1.60),(5.7,4.15,1.35),'Sage armour')
    box('Bridge',(1.12,-9.18,3.17),(3.1,3.05,2.0),'Sage armour')
    box('Bridge roof',(1.12,-9.18,4.25),(3.4,3.38,.18),'Edge steel')
    box('Bridge forward glazing',(1.12,-7.63,3.42),(2.62,.05,.72),'Window teal',.015)
    for x in [.25,1.12,1.99]:box('Bridge window frame',(x,-7.58,3.42),(.08,.08,.77),'Edge steel',.012)
    for x in [-.46,2.70]:box('Bridge side glazing',(x,-9.12,3.42),(.05,2.25,.72),'Window teal',.015)
    box('Engine vent',(-1.73,-9.25,2.35),(1.25,2.45,.12),'Track metal')
    for y in [-10.1,-9.8,-9.5,-9.2,-8.9,-8.6]:box('Vent louvre',(-1.73,y,2.44),(1.15,.06,.05),'Edge steel',0)
    for x in [-2.15,2.85]:cyl('Engine exhaust',(x,-10.55,3.15),.15,1.4,'Track metal')
    beam('Mast',(1.0,-9.85,4.3),(1.0,-9.85,6.0),.055,'Edge steel')
    beam('Mast yard',(.1,-9.85,5.6),(1.9,-9.85,5.6),.04,'Edge steel')
    box('Radar scanner',(1.0,-9.85,6.08),(1.55,.26,.18),'Cream marking')
    for y in [-6.5,-4.5,-2.5,-.5,1.5,3.5,5.5,7.5,9.5]:
        box('Cargo deck plank seam',(0,y,.932),(5.6,.04,.025),'Interior',0)
    for x in [-1.9,1.9]:box('Vehicle deck guidance strip',(x,1.55,.94),(.09,18.1,.02),'Warning ochre',0)
    ramp=anchor('Ramp',(0,11.40,.84));ramp['articulated']=True
    attach(box('Heavy bow ramp',(0,11.40,1.88),(5.85,.20,2.12),'Sage armour'),ramp)
    for z in [1.03,1.40,1.77,2.14,2.51,2.88]:attach(box('Ramp grip bar',(0,11.25,z),(5.45,.08,.06),'Edge steel',.01),ramp)
    for x in [-2.75,2.75]:attach(box('Ramp brace',(x,11.22,1.89),(.13,.11,2.0),'Dark sage'),ramp)
    anchor('Waterline',(0,0,0));anchor('UnloadPoint',(0,13.1,.92));anchor('VehicleBay',(0,1,.95));anchor('PassengerBay',(2.1,1,1.1))
    return save('cas_heavy_landing_craft',{'source':'CAS original Blender heavy well-deck craft; no suitable free military bow-ramp model found','license':'Project original','articulated_nodes':['Ramp'],'waterline_godot_y':0.0,'capacity_art_interface':{'vehicle_bays':1,'person_seats':12},'role':'Heavy vehicle transport, broad ramp and reinforced cargo well; art interface only','body_roof_height_m':4.34,'length_class_m':23.4})

def assault_boat():
    clear()
    hull('Rigid shallow vee hull',[(-3.70,1.10,-.48,.25,1),(-2.4,1.22,-.50,.28,1),(1.5,1.12,-.42,.30,1),(3.55,.32,-.08,.50,1)],'Dark sage')
    box('Non slip floor',(0,-.45,.24),(1.75,4.7,.14),'Interior')
    # Inflatable U-shaped collar with a tapered bow, rather than a box silhouette.
    points=[(-1.17,-3.15,.49),(-1.28,-1.8,.49),(-1.25,.5,.53),(-1.02,2.15,.62),(-.40,3.26,.69),(.40,3.26,.69),(1.02,2.15,.62),(1.25,.5,.53),(1.28,-1.8,.49),(1.17,-3.15,.49)]
    outline_pipe('Inflatable collar',points,.25,'Dark rubber')
    for side in (-1,1):
        for y in [-2.5,-.7,1.0]:
            box('Collar tie down',(side*1.29,y,.69),(.12,.30,.08),'Edge steel',.015)
            beam('Grab rope',(side*1.42,y-.40,.64),(side*1.42,y+.40,.64),.025,'Warm deck')
        box('Seat bench',(side*.50,-1.10,.56),(.42,2.25,.18),'Sage armour')
    console=hull('Steering console',[(-.30,.42,.34,1.15,.8),(.62,.37,.34,1.04,.9)],'Sage armour')
    box('Console windscreen',(0,.56,1.25),(.75,.06,.38),'Window teal',.02)
    torus('Steering wheel',(0,.05,1.21),.17,.025,'Dark rubber',(math.pi/3,0,0))
    box('Driver cushion',(0,-.75,.84),(.6,.48,.16),'Dark rubber')
    for x in [-.49,.49]:
        box('Outboard engine hood',(x,-3.58,.59),(.57,.66,.80),'Dark sage',.12)
        box('Engine warning',(x,-3.93,.70),(.38,.025,.10),'Cream marking',0)
        box('Outboard lower unit',(x,-3.63,-.11),(.17,.19,.64),'Track metal')
        cyl('Propeller hub',(x,-3.8,-.28),.09,.27,'Edge steel','Y')
    box('Bow recovery plate',(0,2.4,.62),(1.25,.7,.12),'Sage armour')
    for x in [-.45,.45]:beam('Forward safety handle',(x,2.2,.74),(x,2.65,.74),.03,'Edge steel')
    anchor('Waterline',(0,0,0));anchor('UnloadPoint',(0,3.95,.50));anchor('PassengerBay',(0,-1,.80))
    return save('cas_fast_assault_boat',{'source':'CAS original Blender rigid inflatable assault boat','license':'Project original','articulated_nodes':[],'waterline_godot_y':0.0,'capacity_art_interface':{'vehicle_bays':0,'person_seats':8},'role':'Low protection, twin outboard fast insertion boat; art interface only','length_class_m':7.8})

def self_propelled_artillery():
    clear()
    hull('Sloped tracked hull',[(-3.85,1.65,.54,1.35,.98),(-2.6,1.76,.45,1.44,1),(2.65,1.76,.45,1.44,1),(3.85,1.45,.66,1.27,.90)],'Sage armour')
    for side in (-1,1):
        box('Track belt',(side*1.69,-.15,.55),(.53,7.20,1.10),'Dark rubber',.24)
        for y in [-2.85,-1.73,-.61,.51,1.63,2.75]:
            cyl('Road wheel',(side*1.985,y,.55),.45,.12,'Dark sage','X',14)
            cyl('Wheel hub',(side*2.06,y,.55),.19,.10,'Edge steel','X',10)
        for y in [-3.23,-2.73,-2.23,-1.73,-1.23,-.73,-.23,.27,.77,1.27,1.77,2.27,2.77,3.27]:
            box('Track top shoe',(side*1.72,y,1.12),(.53,.12,.08),'Track metal',.01)
        box('Track side armour',(side*1.82,-.15,1.25),(.22,6.50,.52),'Sage armour')
    turret=anchor('Turret',(0,-.85,1.43));turret['articulated']=True
    attach(hull('High artillery gunhouse',[(-2.85,1.37,1.45,2.83,.90),(-.7,1.50,1.45,2.83,.95),(1.35,1.20,1.45,2.60,.90)],'Sage armour'),turret)
    attach(box('Gunhouse roof',(0,-.80,2.85),(2.65,3.75,.14),'Dark sage'),turret)
    attach(box('Rear ammunition service door',(0,-2.92,2.12),(1.7,.07,1.2),'Dark sage'),turret)
    for x in [-.9,.9]:attach(box('Door hinge',(x,-2.98,2.10),(.09,.10,.84),'Edge steel'),turret)
    attach(cyl('Gun mantlet',(0,1.20,2.28),.41,1.0,'Dark sage','X'),turret)
    attach(cyl('155 mm barrel',(0,3.68,2.31),.105,5.18,'Edge steel','Y',12),turret)
    attach(cyl('Barrel thermal sleeve',(0,2.2,2.31),.17,2.1,'Sage armour','Y',12),turret)
    attach(box('Muzzle brake',(0,6.32,2.31),(.34,.50,.30),'Track metal'),turret)
    for y in [6.20,6.33,6.46]:attach(box('Muzzle brake port',(0,y,2.32),(.36,.055,.12),'Dark rubber',0),turret)
    attach(cyl('Commander hatch',(.65,-1.4,2.97),.42,.10,'Edge steel'),turret)
    for x in [-1.10,1.10]:attach(box('Stowage locker',(x,-2.15,2.97),(.45,.9,.22),'Warm deck'),turret)
    attach(cyl('Antenna',(-.9,-2.1,3.54),.018,1.25,'Dark rubber',vertices=6),turret)
    for x in [-.7,.7]:box('Forward lamp',(x,3.64,1.29),(.23,.12,.16),'Cream marking')
    anchor('GroundContact',(0,0,0));anchor('PassengerBay',(0,-1,1.6));anchor('Muzzle',(0,6.59,2.31))
    return save('cas_self_propelled_artillery',{'source':'CAS original Blender tracked 155mm artillery silhouette','license':'Project original','articulated_nodes':['Turret'],'capacity_art_interface':{'person_seats':6},'body_roof_height_m':1.44,'turret_roof_height_m':2.92,'role':'Independent tracked artillery vehicle, long barrel, enclosed gunhouse; art interface only','length_class_m':10.4})

def transport_helicopter():
    clear()
    bpy.ops.import_scene.gltf(filepath=str(OUT/'vendor'/'utility-helicopter-cc0.glb'))
    bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
    convert=Matrix.Rotation(math.pi,4,'Z')@Matrix.Scale(1.55,4)
    baked=[];pivots={}
    palette={'teal':'Sage armour','glass':'Window teal','cream':'Cream marking','orange':'Dark sage','alloy':'Edge steel','rubber':'Dark rubber'}
    for o in list(bpy.context.scene.objects):
        if o.type!='MESH':continue
        e=o.evaluated_get(dg);mesh=bpy.data.meshes.new_from_object(e,depsgraph=dg);mesh.transform(convert@e.matrix_world)
        obj=bpy.data.objects.new(o.name,mesh)
        for i,m in enumerate(mesh.materials):mesh.materials[i]=MATS[palette.get(m.name.split('.')[0],'Sage armour')]
        group='MainRotor' if o.name.startswith('main-rotor') else 'TailRotor' if o.name.startswith('tail-rotor') else None
        if group and group not in pivots:pivots[group]=convert@o.matrix_world.translation
        baked.append((obj,group))
    clear()
    anchors={name:anchor(name,tuple(loc)) for name,loc in pivots.items()}
    for a in anchors.values():a['articulated']=True
    for o,group in baked:
        bpy.context.collection.objects.link(o)
        if group:attach(o,anchors[group])
    # Military field additions preserve the downloaded airframe and pivots.
    for side in (-1,1):
        box('Sliding cabin door seam',(side*1.21,.10,2.14),(.035,1.38,1.05),'Dark sage',.015)
        box('Cabin door window',(side*1.24,.20,2.50),(.035,.94,.48),'Window teal',.025)
        box('Door handle',(side*1.27,-.40,2.10),(.035,.24,.05),'Edge steel',.01)
        sphere('Auxiliary fuel tank',(side*1.42,-.75,1.43),(.31,1.14,.33),'Dark sage')
        beam('External step',(side*1.38,-.5,.82),(side*1.38,.9,.82),.05,'Edge steel')
    box('Engine filter housing',(0,-.70,3.49),(1.14,1.1,.28),'Dark sage',.1)
    for x in [-.30,0,.30]:box('Intake grille',(x,-.12,3.48),(.12,.025,.17),'Dark rubber',0)
    anchor('GroundContact',(0,0,0));anchor('PassengerBay',(0,.15,1.75));anchor('UnloadPoint',(1.6,.2,.7))
    return save('cas_transport_helicopter',{'source':'3DAssets.dev Utility helicopter / Air Land Sea Vehicles, plus CAS military equipment conversion','source_url':'https://3dassets.dev/assets/air-land-sea-vehicles-utility-helicopter-7dbc148e','download_url':'https://cdn.3dassets.dev/assets/20028/v1/model.glb','source_sha256':'5b01f318035776d9cc632d76dc25ac9a0447b94e37180f46850bdb154b8faff5','license':'CC0-1.0 + original additions','modifications':'1.55 metre uniform scale, +Z nose normalized to Godot -Z; military recolour, cabin door and fuel equipment, independent main/tail rotor assemblies, one shared vertex palette','articulated_nodes':['MainRotor','TailRotor'],'capacity_art_interface':{'person_seats':10},'role':'Transport helicopter, rotor and disembark anchors; art interface only','length_class_m':13.1})

def attack_helicopter():
    clear()
    # Full sectioned mesh fuselage: compact two-seat gunship with small assault cabin.
    sections=[(-6.2,.10,1.82,2.10,1),(-3.3,.32,1.25,2.45,1),(-1.4,.80,.84,2.80,1),(.9,.80,.70,2.50,1),(2.8,.64,.62,2.17,1),(4.0,.25,.80,1.47,1)]
    hull('Tandem attack helicopter fuselage',sections,'Sage armour')
    # Canopies use faceted translucent-looking blue paint, no expensive transparency.
    hull('Rear pilot canopy',[(-.65,.59,2.65,3.22,.70),(.55,.59,2.48,3.05,.70),(1.20,.49,2.36,2.84,.80)],'Window teal')
    hull('Forward pilot canopy',[(1.05,.49,2.35,2.83,.80),(2.25,.47,2.10,2.62,.80),(3.15,.31,1.90,2.23,.80)],'Window teal')
    for x in [-.72,.72]:
        beam('Canopy protective frame',(x,-.6,2.55),(x,.6,2.35),.04,'Edge steel')
        box('Assault cabin side door',(x,-.35,1.67),(.04,1.30,.76),'Dark sage',.025)
        box('Cabin window',(x*1.04,-.4,2.14),(.035,.65,.28),'Window teal',.02)
    for side in (-1,1):
        wing=box('Weapon stub wing',(side*1.60,-.1,1.58),(1.85,1.05,.17),'Dark sage',.04)
        wing.rotation_euler.y=side*-.08
        cyl('Rocket pod',(side*2.06,.02,1.11),.30,1.75,'Track metal','Y',14)
        for a in range(6):
            angle=a*math.tau/6
            cyl('Rocket launch tube',(side*2.06+math.cos(angle)*.18,.91,1.11+math.sin(angle)*.18),.065,.05,'Dark rubber','Y',8)
        sphere('Engine nacelle',(side*.64,-1.49,2.70),(.40,1.26,.36),'Dark sage')
        cyl('Engine exhaust',(side*.64,-2.77,2.71),.25,.34,'Track metal','Y',12)
        beam('Landing gear strut',(side*.65,-.75,.92),(side*.94,-.75,.30),.075,'Edge steel')
        cyl('Main landing wheel',(side*.99,-.75,.30),.30,.20,'Dark rubber','X',16)
        cyl('Main wheel hub',(side*1.11,-.75,.30),.13,.04,'Edge steel','X',10)
    beam('Nose undercarriage',(0,2.75,.85),(0,2.9,.20),.055,'Edge steel')
    cyl('Nose wheel',(0,2.9,.22),.22,.19,'Dark rubber','X',14)
    sphere('Chin sensor ball',(0,3.16,.72),(.27,.28,.27),'Track metal')
    box('Sensor lens',(0,3.43,.75),(.24,.04,.15),'Window teal',.015)
    gun=anchor('ChinGun',(0,2.42,.55));gun['articulated']=True
    attach(cyl('Chin autocannon',(0,3.09,.50),.055,1.35,'Track metal','Y',10),gun)
    box('Tail horizontal stabilizer',(0,-5.30,2.12),(3.10,.55,.12),'Dark sage')
    fin=hull('Tall tail fin',[(-6.30,.09,1.85,3.25,1),(-5.75,.09,1.85,3.10,1)],'Sage armour')
    cyl('Rotor mast',(0,-.68,3.08),.105,.69,'Edge steel')
    main=anchor('MainRotor',(0,-.68,3.43));main['articulated']=True
    attach(cyl('Rotor hub',(0,-.68,3.43),.29,.20,'Track metal'),main)
    for i in range(4):
        a=i*math.pi/2
        blade=box('Composite main blade',(math.cos(a)*3.06,-.68+math.sin(a)*3.06,3.44),(5.55,.27,.055),'Dark rubber',.015)
        blade.rotation_euler.z=a;attach(blade,main)
        tip=box('Rotor tip marking',(math.cos(a)*5.67,-.68+math.sin(a)*5.67,3.45),(.32,.28,.055),'Warning ochre',.008)
        tip.rotation_euler.z=a;attach(tip,main)
    tail=anchor('TailRotor',(.16,-5.96,2.64));tail['articulated']=True
    attach(cyl('Tail rotor hub',(.16,-5.96,2.64),.12,.18,'Edge steel','X'),tail)
    for a in [0,math.pi/2]:
        blade=box('Tail rotor blade',(.26,-5.96,2.64),(.055,1.70,.15),'Dark rubber',.012)
        blade.rotation_euler.x=a;attach(blade,tail)
    anchor('GroundContact',(0,0,0));anchor('PassengerBay',(0,-.55,1.45));anchor('UnloadPoint',(1.25,-.2,.6));anchor('Muzzle',(0,3.80,.50))
    return save('cas_attack_helicopter',{'source':'CAS original Blender tandem-seat assault gunship, after checking CC0 utility helicopter limitations','license':'Project original','articulated_nodes':['MainRotor','TailRotor','ChinGun'],'capacity_art_interface':{'person_seats':6},'role':'Armed assault helicopter: autocannon, twin rocket pods, small troop cabin; art interface only','length_class_m':11.7})

if __name__=='__main__':
    manifest=json.loads((OUT/'vehicle-manifest.json').read_text(encoding='utf-8'))
    originals=[row for row in manifest['models'] if row['id'] in ORIGINAL_IDS]
    models=[heavy_landing_craft(),assault_boat(),self_propelled_artillery(),transport_helicopter(),attack_helicopter()]
    for name,digest in ORIGINAL_HASHES.items():assert hashlib.sha256((OUT/(name+'.glb')).read_bytes()).hexdigest()==digest, 'Original changed: '+name
    manifest.update({'date':'2026-11-16','models':originals+models,'original_three_preserved_sha256':ORIGINAL_HASHES,'scope':'Isolated art showcase, no battle/economy/account modification'})
    (OUT/'vehicle-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print('EXPANDED_FLEET_COMPLETE 8 models; original GLB SHA preserved')
