"""Register unmodified built-in image outputs, atlas geometry and original identities."""
from pathlib import Path
import hashlib,json
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'godot/assets/tactical/transport'
DOC=ROOT/'docs/art/transport-v3-20261114'
SETS={
 'alpha':('001','034','076','009','022'),
 'bravo':('011','018','027','041','052'),
 'charlie':('063','087','103','116','128'),
 'delta':('145','167','184','203','240'),
}
SOURCES={
 'alpha':('exec-7403971f-d266-4140-8e69-aadcee3f8ac5.png','exec-6e6f34af-1009-4210-b667-71bc83368e6b.png'),
 'bravo':('exec-0741b45e-9dd2-49c3-9127-ca86b123bff8.png','exec-d007ba48-ffe4-44e5-9f67-ac97ba8bdfe6.png'),
 'charlie':('exec-4d07651a-8c4e-41f2-b4f2-097aa10e7870.png','exec-cb54ad14-1dfd-4bbd-8233-e8f6fda8c9d7.png'),
 'delta':('exec-3a8e0cb3-30d4-49e9-92f2-01b4af42c935.png','exec-8bd8140f-29c7-4a8c-bd08-ca8c4ee8b849.png'),
}
DESIGNS={
 'alpha':['compact light assault helicopter with side doors, skids, four-bladed rotor and winch','heavy landing craft with twin bow ramps, troop seating and side pontoons','grey blue twin wingtip tiltrotor insertion aircraft','engineering landing craft with yellow folding crane and tool lockers','heavy tracked amphibious IFV with angular bow, turret and rear hatch'],
 'bravo':['narrow fast assault landing boat with twin engines and benches','recon hovercraft with rubber skirt and rear ducted fans','tandem canopy attack helicopter with chin cannon, rocket pods and stub wings','electronic warfare landing craft with radome and folding antennas','white medical evacuation boat with teal star of life, patient cabin and rescue floats'],
 'charlie':['anti armor missile landing craft with paired launchers','rocket support landing boat with six-tube rack and outriggers','wheeled 8x8 amphibious personnel carrier','armored logistics barge with crane and visible cargo','low noise stealth sniper skiff with camouflage troop cover and twin hulls'],
 'delta':['anti air landing craft with twin cannon and surveillance radar','shallow water riverine patrol boat with side propulsor guards','breaching landing craft with folded mine plow and blade','command landing craft with mast, antennas and satellite dish','white teal rescue helicopter with hoist and flotation pods'],
}
PREFIX='Original production quality top-down military vehicle game sprite atlas, genuine TRANSPARENT background, wide landscape. Exactly FIVE equal columns and TWO equal rows. All vehicles face UP in strict direct overhead orthographic plan view. No perspective, no water, no terrain, no people. Each vehicle centered, fully contained with transparent margins. Row1 intact cruising, row2 same model, orientation, size and anchor deploying with open ramp/hatch or rotor. Rich precise mechanical military anime cel shading, distinctive silhouette, ivory/desaturated navy teal with mustard safety accents, clean highlights, thin dark contour. Readable at100px. No typography, labels, logos, existing game symbols or drawn grid.'
CLEANUP='Preserve exact five identities, mechanical designs and top-down 5x2 layout. Remove all white background, fog, smoke, white wash, ground shadows and colored halos between sprites to genuine zero alpha. Preserve actual rotor blur only. Shrink each individual sprite to72% and center precisely in its own equal cell. At least12% transparent border on all four sides including rotor/ramp. Same centered body anchor/scale in both rows. No matte, terrain, labels or drawn grid.'
profiles=json.loads((ROOT/'godot/data/tactical-profiles-v3.json').read_text(encoding='utf-8'))
cards={c['id']:c for c in profiles['cards']}
manifest={'version':'cas-transport-art-v3','source':'built-in image_gen','historical_rules_affected':False,'columns':5,'rows':2,'units':{},'fallback':{'atlas':'res://assets/tactical/transport/transport-atlas-v3.png','columns':3,'rows':3,'kinds':['landing_craft','amphibious_vehicle','helicopter']}}
ledger={'source':'built-in image_gen','prompt_text':'normalized production specifications; full wording remains in generation tool calls','pixel_edits_after_generation':False,'sets':[]}
fallback=ART/'transport-atlas-v3.png';fallback_image=Image.open(fallback)
ledger['fallback']={'file':str(fallback.relative_to(ROOT)).replace('\\','/'),'source':'exec-1e733fc3-9b52-4722-83d9-9609c30eaded.png','sha256':hashlib.sha256(fallback.read_bytes()).hexdigest(),'size':list(fallback_image.size),'alpha_range':list(fallback_image.getextrema()[3]),'columns':3,'rows':3,'prompt':'Original detailed military anime true top-down vehicle atlas, north/up, transparent. Columns landing craft, amphibious tracked IFV, light transport helicopter. Rows intact cruising, deployed open ramp/hatch or rotor, damaged recoverable with smoke/soot. Keep same model scale and center across states, ivory/teal steel and yellow safety details, readable90px. No water, ground, people, labels, grid or logo.'}
for key,ids in SETS.items():
 path=ART/f'variants-{key}-v3.png';im=Image.open(path)
 assert im.mode=='RGBA' and im.getextrema()[3]==(0,255)
 w,h=im.size
 record={'set':key,'file':str(path.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'size':[w,h],'alpha_range':[0,255],'source_candidates':list(SOURCES[key]),'generation_prompt':PREFIX+' Columns: '+'; '.join(DESIGNS[key]),'edit_prompt':CLEANUP,'identities':[]}
 for col,suffix in enumerate(ids):
  identity='MCP-'+suffix;card=cards[identity]
  frames=[]
  for row in range(2):
   left=round(col*w/5);right=round((col+1)*w/5);top=round(row*h/2);bottom=round((row+1)*h/2)
   # Read-only atlas QA; crop is never saved or used to change generated pixels.
   alpha=im.getchannel('A').crop((left,top,right,bottom));bbox=alpha.point(lambda a:255 if a>128 else 0).getbbox()
   assert bbox is not None
   frame={'region':[left,top,right-left,bottom-top],'anchor':[(right-left)/2,(bottom-top)/2],'alpha_bbox_128':list(bbox)}
   frames.append(frame)
  reference=frames[0]['alpha_bbox_128'];shared_scale=max(reference[2]-reference[0],reference[3]-reference[1])
  for frame in frames:frame['scale_reference']=shared_scale
  item={'id':identity,'vehicle_id':card['vehicle_id'],'name':card['vehicle_name'],'default_kind':card['default_transport'],'art_variant':card['art_variant'],'atlas':'res://'+str(path.relative_to(ROOT/'godot')).replace('\\','/'),'frames':{'intact':frames[0],'deploying':frames[1]},'forward':'north','display_length':88 if card['default_transport']=='helicopter' else 76,'rotor_procedural':card['default_transport']=='helicopter','deployment_rotor_uses_intact_body':card['default_transport']=='helicopter','alternate_family_policy':'generic family atlas with this identity type token and label, never another unit exclusive vehicle'}
  manifest['units'][identity]=item;record['identities'].append(identity)
 ledger['sets'].append(record)
DOC.mkdir(parents=True,exist_ok=True)
(ROOT/'godot/data/transport-variants-v3.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(DOC/'generation-ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert len(manifest['units'])==20
print(json.dumps({'registered':20,'atlases':len(SETS),'transparent':True,'pixel_edits':False},ensure_ascii=False))
