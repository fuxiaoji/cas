from pathlib import Path
import json, hashlib, shutil, statistics, zipfile
from PIL import Image, ImageDraw, ImageFont

R=Path(__file__).resolve().parents[1]
NAME='cavalry-mountain-animation-v2-20261116'
D=R/'docs/art'/NAME; O=R/'output'/NAME; A=R/'godot/assets/tactical/cavalry-mountain-extra-20261116'
for p in (O/'assets',O/'animations',A):p.mkdir(parents=True,exist_ok=True)
src=json.loads((D/'source-map.json').read_text('utf8'))
jobs=json.loads((D/'generation-input.json').read_text('utf8'))['jobs']
for j in jobs:j['order']=[f'pose_{i}' for i in range(16)]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def act(label,frames,fps=8,loop=True):return dict(label=label,frames=frames,fps=fps,loop=loop)
actions={(j['id'],j['kind']):j['actions'] for j in jobs}
ledger={'generator':'built-in image_gen','runtime_changed':False,'portraits':[],'atlases':[],'exports':[]};catalog=[]
for uid,p in src['portraits'].items():
 dst=A/f'{uid}-portrait.png';shutil.copyfile(p,dst) if Path(p).resolve()!=dst.resolve() else None
 shutil.copyfile(dst,O/'assets'/dst.name)
 with Image.open(dst) as im:im.load();assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]==0
 ledger['portraits'].append(dict(id=uid,source=p,output=str(dst),sha256=sha(dst),source_bytes_preserved=sha(p)==sha(dst)))
for job in jobs:
 uid,kind=job['id'],job['kind']; key=uid+'-'+kind;p=Path(src['atlases'][key]);raw=A/f'{key}-raw.png';shutil.copyfile(p,raw)
 im=Image.open(raw).convert('RGBA');assert im.getchannel('A').getextrema()[0]==0
 tiles=[];frames=[];cw=im.width/4;ch=im.height/4;assert abs(cw-ch)<2
 sheet=Image.new('RGBA',(2048,2048));scale=min(512/cw,512/ch)*.86
 for i in range(16):
  x0,y0=round(i%4*cw),round(i//4*ch);x1,y1=round((i%4+1)*cw),round((i//4+1)*ch)
  tile=im.crop((x0,y0,x1,y1));b=tile.getchannel('A').point(lambda x:255 if x>32 else 0).getbbox();assert b,(key,i)
  # Crop and translate only. Preserve generated source bytes separately; no painted edits.
  clipped=tile.crop(b);clipped=clipped.resize((max(1,round(clipped.width*scale)),max(1,round(clipped.height*scale))),Image.Resampling.LANCZOS)
  dx=round(256-clipped.width/2);dy=round(452-clipped.height)
  assert dx>=0 and dy>=0,(key,i,b)
  frame=Image.new('RGBA',(512,512));frame.alpha_composite(clipped,(dx,dy));tiles.append(frame);sheet.alpha_composite(frame,(i%4*512,i//4*512))
  frames.append(dict(index=i,label=job['order'][i],source_rect=[x0,y0,x1-x0,y1-y0],source_bounds=b,pivot=[256,452],normalized_rect=[i%4*512,i//4*512,512,512]))
 normalized=A/f'{key}.png';sheet.save(normalized);shutil.copyfile(normalized,O/'assets'/normalized.name);shutil.copyfile(raw,O/'assets'/raw.name)
 aa=actions[(uid,kind)]
 for name,a in aa.items():
  seq=[tiles[i] for i in a['frames']];out=O/'animations'/f'{key}-{name}.webp'
  seq[0].save(out,save_all=True,append_images=seq[1:],duration=round(1000/a['fps']),loop=0 if a['loop'] else 1,lossless=True)
  with Image.open(out) as ck:
   for n in range(getattr(ck,'n_frames',1)):ck.seek(n);ck.load()
  ledger['exports'].append(str(out.relative_to(O)))
 lines=['[gd_resource type="SpriteFrames" load_steps=18 format=3]',f'[ext_resource type="Texture2D" path="res://assets/tactical/cavalry-mountain-extra-20261116/{key}.png" id="1"]']
 for i in range(16):lines += [f'[sub_resource type="AtlasTexture" id="F{i}"]','atlas = ExtResource("1")',f'region = Rect2({i%4*512}, {i//4*512}, 512, 512)']
 entries=[]
 for name,a in aa.items():
  fs=', '.join('{"duration": 1.0, "texture": SubResource("F%d")}'%i for i in a['frames'])
  entries.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}'%(fs,str(a['loop']).lower(),name,float(a['fps'])))
 lines+=['[resource]','animations = ['+',\n'.join(entries)+']'];(A/f'{key}.tres').write_text('\n\n'.join(lines),encoding='utf8')
 refs=[str(A/f'{uid}-portrait.png'),str(R/'godot/assets/tactical/sprites/MCP-034-sheet.png'),str(R/'godot/assets/tactical/art-v2/sprites/MCP-088-sheet-padded.png')]
 ledger['atlases'].append(dict(id=key,source=str(p),raw_sha256=sha(raw),source_bytes_preserved=sha(raw)==sha(p),size=im.size,frames=frames,actions=aa,references=[dict(path=q,sha256=sha(q)) for q in refs]))
 catalog.append(dict(id=key,unit_id=uid,kind=kind,sheet='assets/'+normalized.name,actions=aa))
(O/'catalogue.js').write_text('window.CATALOGUE='+json.dumps(catalog,ensure_ascii=False)+';',encoding='utf8')
(D/'asset-ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),encoding='utf8')
for p in ['asset-ledger.json','generation-input.json','source-map.json']:shutil.copyfile(D/p,O/p)
# Isolated native viewer uses the very same six SpriteFrames resources.
N=O/'native-preview';NA=N/'assets/tactical/cavalry-mountain-extra-20261116';NA.mkdir(parents=True,exist_ok=True)
for p in A.iterdir():
 if p.suffix in ('.png','.tres'):shutil.copyfile(p,NA/p.name)
(N/'project.godot').write_text('[application]\nconfig/name="CAS Cavalry Mountain Animation Art"\nrun/main_scene="res://preview.tscn"\n[display]\nwindow/size/viewport_width=1440\nwindow/size/viewport_height=1250\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf8')
scene=['[gd_scene load_steps=8 format=3]']
for i,c in enumerate(catalog):scene.append(f'[ext_resource type="SpriteFrames" path="res://assets/tactical/cavalry-mountain-extra-20261116/{c["id"]}.tres" id="{i+1}"]')
scene.append('[node name="Preview" type="Node2D"]')
for i,c in enumerate(catalog):
 action='walk' if c['kind']=='body' else next(iter(c['actions']))
 scene.append(f'[node name="Sprite{i}" type="AnimatedSprite2D" parent="."]\nposition = Vector2({240+i%3*480}, {220+i//3*400})\nscale = Vector2(0.7, 0.7)\nsprite_frames = ExtResource("{i+1}")\nanimation = &"{action}"\nautoplay = "{action}"')
(N/'preview.tscn').write_text('\n\n'.join(scene),encoding='utf8')
# Contact board for true 80px and 160px readability inspection.
board=Image.new('RGB',(1200,990),'#ece8dd');draw=ImageDraw.Draw(board);font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',22)
for i,c in enumerate(catalog):
 sheet=Image.open(O/c['sheet']);tile=sheet.crop((0,0,512,512));x=20+i%3*400;y=15+i//3*330
 draw.text((x,y),c['id'],font=font,fill='#253e48')
 for n,size in enumerate([80,160]):
  stamp=tile.copy();stamp.thumbnail((size,size));board.paste(stamp,(x+n*150,y+50),stamp)
board.save(O/'small-size-review.jpg',quality=95)
print(json.dumps(dict(atlases=len(catalog),frames=112,animations=len(ledger['exports']),output=str(O)),ensure_ascii=False))
