"""Preserve generated originals; crop/anchor authored frames and assemble previews."""
from pathlib import Path
import json,shutil,hashlib,statistics,zipfile
from PIL import Image
R=Path(__file__).resolve().parents[1];D=R/'docs/art/sixth-infantry-20261115';A=R/'godot/assets/tactical/sixth-infantry-20261115';O=R/'output/sixth-infantry-20261115'
d=json.loads((D/'generation-input.json').read_text('utf8'))
actions={'idle':([0,1],3),'walk':([2,3,4,5],8),'fire':([6,7,12,13,6],6),'bolt':([12,13],5),'heal':([14,15],3),'hurt':([8,0],5),'search':([9],1),'defeated':([10,11,11,11],3)}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assets={}
for kind in ['portrait','sprite','casualty']:
 src=Path(d['final'][kind]);dst=A/f'MCP-306-{kind}.png';shutil.copyfile(src,dst);shutil.copyfile(dst,O/'assets'/dst.name)
 im=Image.open(dst).convert('RGBA');assert im.getchannel('A').getextrema()[0]==0
 assets[kind]={'source':str(src),'path':'res://assets/tactical/sixth-infantry-20261115/'+dst.name,'sha256':sha(dst),'size':list(im.size),'source_bytes_preserved':sha(src)==sha(dst)}
sheet=Image.open(A/'MCP-306-sprite.png').convert('RGBA');frames=[];tiles=[]
for i in range(16):
 x,y=round(i%4*sheet.width/4),round(i//4*sheet.height/4);x1,y1=round((i%4+1)*sheet.width/4),round((i//4+1)*sheet.height/4)
 tile=sheet.crop((x,y,x1,y1));bounds=tile.getchannel('A').point(lambda a:255 if a>32 else 0).getbbox();assert bounds
 tiles.append(tile);frames.append({'rect':[x,y,x1-x,y1-y],'bounds':list(bounds),'pivot':[(bounds[0]+bounds[2])/2,bounds[3]],'source':assets['sprite']['path']})
height=statistics.median(f['bounds'][3]-f['bounds'][1] for f in frames[:6])
casualty=Image.open(A/'MCP-306-casualty.png').convert('RGBA')
for i in range(4):
 x,x1=round(i*casualty.width/4),round((i+1)*casualty.width/4)
 tile=casualty.crop((x,0,x1,casualty.height));bounds=tile.getchannel('A').point(lambda a:255 if a>32 else 0).getbbox();assert bounds
 tiles.append(tile);frames.append({'rect':[x,0,x1-x,casualty.height],'bounds':list(bounds),'pivot':[(bounds[0]+bounds[2])/2,(bounds[1]+bounds[3])/2],'source':assets['casualty']['path']})
for i,f in enumerate(frames):
 f['reference_height']=height
 if i==11 or i>=16:f['pivot']=[(f['bounds'][0]+f['bounds'][2])/2,(f['bounds'][1]+f['bounds'][3])/2]
row={'id':'MCP-306','portrait':assets['portrait']['path'],'sprite_sheet':assets['sprite']['path'],'art_status':'approved_original_identity_handoff','frames':frames,'animations':{k:v[0] for k,v in actions.items()},'source_ledger':'docs/art/sixth-infantry-20261115/asset-ledger.json'}
row['animations'].update(fall=[10],deploy=[0],parachuting=[0])
row['animations']['defeated']=[11,16,17,18,19]
p=R/'godot/data/tactical-expansion-art-v4.json';reg=json.loads(p.read_text('utf8'));reg['units']['MCP-306']=row;p.write_text(json.dumps(reg,ensure_ascii=False,indent=2)+'\n','utf8')
p=R/'godot/data/tactical-art-v4.json';reg=json.loads(p.read_text('utf8')) if p.exists() else {'version':'tactical-art-v4','units':{}};reg['units']['MCP-306']=row;p.write_text(json.dumps(reg,ensure_ascii=False,indent=2)+'\n','utf8')
seqs=dict(actions);seqs['showcase']=([0]*6+[1]+[2,3,4,5]*3+[6,7,12,13]*2+[14,15]*3+[8,10]+[11]*8,7)
seqs['fallen_variants']=([16]*5+[17]*5+[18]*5+[19]*5,4)
for name,(seq,fps) in seqs.items():
 images=[]
 for i in seq:
  canvas=Image.new('RGBA',(420,420));tile=tiles[i];factor=300/height
  tile=tile.resize((round(tile.width*factor),round(tile.height*factor)),Image.Resampling.LANCZOS)
  px,py=frames[i]['pivot'];canvas.alpha_composite(tile,(round(210-px*factor),round(360-py*factor)));images.append(canvas)
 images[0].save(O/'animations'/f'{name}.webp',save_all=True,append_images=images[1:],duration=round(1000/fps),loop=0,lossless=True)
preview=Image.new('RGBA',(320,340));preview.alpha_composite(tiles[0],(0,0));preview.save(O/'assets/chibi.png')
ledger={'generator':'built-in image_gen','identity':'MCP-306','assets':assets,'frames':frames,'animations':actions,'wardrobe':'opaque white pantyhose','single_angle_mirrored':True}
(D/'asset-ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),'utf8');shutil.copyfile(D/'asset-ledger.json',O/'asset-ledger.json');shutil.copyfile(R/'docs/design/sixth-infantry-20261115.md',O/'design.md')
# Godot SpriteFrames: exact nonuniform source regions, source PNG unmodified.
lines=['[gd_resource type="SpriteFrames" load_steps=23 format=3]',f'[ext_resource type="Texture2D" path="{assets["sprite"]["path"]}" id="1"]',f'[ext_resource type="Texture2D" path="{assets["casualty"]["path"]}" id="2"]']
for i,f in enumerate(frames):lines.append(f'[sub_resource type="AtlasTexture" id="F{i}"]\natlas = ExtResource("{1 if i<16 else 2}")\nregion = Rect2({", ".join(map(str,f["rect"]))})')
entries=[]
for name,(seq,fps) in actions.items():entries.append('{"frames":['+','.join('{"duration":1.0,"texture":SubResource("F%d")}'%i for i in seq)+'],"loop":true,"name":&"'+name+'","speed":'+str(float(fps))+'}')
lines.append('[resource]\nanimations = ['+',\n'.join(entries)+']');(A/'MCP-306-sprite.tres').write_text('\n\n'.join(lines),'utf8');shutil.copyfile(A/'MCP-306-sprite.tres',O/'assets/MCP-306-sprite.tres')
(O/'catalogue.js').write_text('window.UNIT='+json.dumps({'frames':frames,'actions':actions},ensure_ascii=False)+';','utf8')
print(json.dumps({'frames':len(frames),'animations':len(seqs),'original_pixels_modified':False,'assets':assets},ensure_ascii=False))
