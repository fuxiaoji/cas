from pathlib import Path
import json, hashlib, shutil, statistics, zipfile
from PIL import Image, ImageDraw, ImageFont

R=Path(__file__).resolve().parents[1]
NAME='cavalry-mountain-animation-20261116'
D=R/'docs/art'/NAME; O=R/'output'/NAME; A=R/'godot/assets/tactical/cavalry-mountain-20261116'
for p in (O/'assets',O/'animations',A):p.mkdir(parents=True,exist_ok=True)
src=json.loads((D/'source-map.json').read_text('utf8'))
jobs=json.loads((D/'atlas-prompts.json').read_text('utf8'))['jobs']
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def act(label,frames,fps=8,loop=True):return dict(label=label,frames=frames,fps=fps,loop=loop)
base={'idle':act('待机',[0,0,0,0,1],3),'walk':act('行进',[2,3,4,5]),'aim':act('瞄准',[6],1),'fire':act('开火',[6,7,6],10,False),'hurt':act('受击',[8,0],6,False),'search':act('搜索',[9],1),'defeated':act('倒地',[10,11],4,False)}
actions={}
for uid in ['MCP-002','MCP-030','MCP-017']:actions[(uid,'body')]=dict(base)
actions[('MCP-002','body')]['charge']=act('冲锋',[12,13,14,15],10)
actions[('MCP-030','body')]['climb']=act('攀绳',[12,13,14,15],5)
actions[('MCP-017','body')].update(throw=act('闪光投掷',[12,13],6,False),reload=act('换弹',[14,15],4,False))
actions[('MCP-002','roles')]={'at_idle':act('反坦克待机',[0,0,1],3),'at_walk':act('反坦克行进',[2,3,4,5]),'at_fire':act('反坦克开火',[6,7,6],6,False),'at_reload':act('反坦克装填',[8,9],4,False),'at_hurt':act('反坦克受击',[10,0],6,False),'at_defeated':act('反坦克倒地',[11],1,False),'saber':act('马刀挥击',[12,13,14,15],8,False)}
actions[('MCP-030','roles')]={'mg_idle':act('机枪待机',[0],1),'mg_walk':act('机枪行进',[12,13],6),'mg_fire':act('机枪射击',[1,2,1,2],8,False),'mg_reload':act('机枪装填',[3],1),'mortar_walk':act('迫击炮携行',[14,15],6),'mortar_deploy':act('迫击炮架设',[4,5,6,7],4,False),'mortar_fire':act('迫击炮装填发射',[7,8,9,10,11,7],5,False),'mortar_pack':act('迫击炮收拢',[7,6,5,4],4,False)}
actions[('MCP-017','roles')]={'shield_idle':act('盾手待机',[0,0,1],3),'shield_walk':act('盾手推进',[2,3],6),'shield_fire':act('盾后开火',[4,5,4],8,False),'shield_hurt':act('盾手受击',[6,0],6,False),'shield_defeated':act('盾手倒地',[7],1,False),'shotgun_idle':act('霰弹待机',[8,8,9],3),'shotgun_walk':act('霰弹行进',[10,11],6),'shotgun_fire':act('霰弹开火',[12,13,12],8,False),'shotgun_reload':act('霰弹装填',[14],1),'shotgun_hurt':act('霰弹受击',[15,8],6,False)}
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
 lines=['[gd_resource type="SpriteFrames" load_steps=18 format=3]',f'[ext_resource type="Texture2D" path="res://assets/tactical/cavalry-mountain-20261116/{key}.png" id="1"]']
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
for p in ['asset-ledger.json','generation-input.json','atlas-prompts.json','source-map.json']:shutil.copyfile(D/p,O/p)
# Isolated native viewer uses the very same six SpriteFrames resources.
N=O/'native-preview';NA=N/'assets/tactical/cavalry-mountain-20261116';NA.mkdir(parents=True,exist_ok=True)
for p in A.iterdir():
 if p.suffix in ('.png','.tres'):shutil.copyfile(p,NA/p.name)
(N/'project.godot').write_text('[application]\nconfig/name="CAS Cavalry Mountain Animation Art"\nrun/main_scene="res://preview.tscn"\n[display]\nwindow/size/viewport_width=1440\nwindow/size/viewport_height=900\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf8')
scene=['[gd_scene load_steps=7 format=3]']
for i,c in enumerate(catalog):scene.append(f'[ext_resource type="SpriteFrames" path="res://assets/tactical/cavalry-mountain-20261116/{c["id"]}.tres" id="{i+1}"]')
scene.append('[node name="Preview" type="Node2D"]')
for i,c in enumerate(catalog):
 action='walk' if c['kind']=='body' else next(iter(c['actions']))
 scene.append(f'[node name="Sprite{i}" type="AnimatedSprite2D" parent="."]\nposition = Vector2({240+i%3*480}, {250+i//3*420})\nscale = Vector2(0.7, 0.7)\nsprite_frames = ExtResource("{i+1}")\nanimation = &"{action}"\nautoplay = "{action}"')
(N/'preview.tscn').write_text('\n\n'.join(scene),encoding='utf8')
# Contact board for true 80px and 160px readability inspection.
board=Image.new('RGB',(1200,660),'#ece8dd');draw=ImageDraw.Draw(board);font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',22)
for i,c in enumerate(catalog):
 sheet=Image.open(O/c['sheet']);tile=sheet.crop((0,0,512,512));x=20+i%3*400;y=15+i//3*330
 draw.text((x,y),c['id'],font=font,fill='#253e48')
 for n,size in enumerate([80,160]):
  stamp=tile.copy();stamp.thumbnail((size,size));board.paste(stamp,(x+n*150,y+50),stamp)
board.save(O/'small-size-review.jpg',quality=95)
print(json.dumps(dict(atlases=len(catalog),frames=96,animations=len(ledger['exports']),output=str(O)),ensure_ascii=False))
