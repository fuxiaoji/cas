"""Preserve generated PNGs and package authored atlas frames for review."""
from pathlib import Path
import json, shutil, hashlib, statistics, html
from PIL import Image, ImageDraw, ImageFont

R=Path(__file__).resolve().parents[1]
D=R/'docs/art/cavalry-police-20261116'
O=R/'output/cavalry-police-20261116'
A=R/'godot/assets/tactical/cavalry-police-20261116'
G=O/'native-preview'
for p in [D,O/'assets',O/'animations',A,G/'assets']:
    p.mkdir(parents=True,exist_ok=True)
jobs=json.loads((D/'generation-input.json').read_text('utf8'))
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
base={'待机':([0,1],2,True),'移动':([2,3,4,5],8,True),'瞄准':([6],1,True),'开火':([6,7,6],8,False),'受击':([8,0],5,False),'搜索姿态':([9],1,True),'倒地':([10,11],3,False)}
special={
'cavalry-carbine':{'冲锋':([12,13],8,True),'近战':([14,15],5,False)},
'cavalry-rocket':{'冲锋':([12,13],8,True),'装填':([14,15],4,False)},
'police-smg':{'投闪光':([12,13],4,False),'侧探':([14,15],4,False)},
'police-shield':{'盾前进':([12,13],5,True),'盾警戒':([14,15],3,True)},
'police-shotgun':{'泵动':([12,13],6,False),'装填':([14,15],4,False)}}
labels={'cavalry-carbine':'岚缨 · 骑枪手','cavalry-rocket':'岚缨 · 反坦克手','police-smg':'青巡 · 冲锋枪手','police-shield':'青巡 · 盾手','police-shotgun':'青巡 · 霰弹手'}
receipt={'generator':'built-in image_gen','runtime_units_added':False,'scope':'art_and_design','original_pixels_modified':False,'assets':{},'roles':[]}
for key,src in jobs['final'].items():
    src=Path(src); dst=A/(key+'.png');shutil.copyfile(src,dst)
    for p in [O/'assets'/dst.name,G/'assets'/dst.name]:shutil.copyfile(dst,p)
    im=Image.open(dst)
    assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]==0, (key,'no genuine alpha')
    receipt['assets'][key]={'source':str(src),'sha256':digest(dst),'original_sha256':digest(src),'size':list(im.size),'bytes_preserved':digest(dst)==digest(src),'transparent':True}
    if key.endswith('portrait'):continue
    frames=[];tiles=[]
    for i in range(16):
        x,x1=round(i%4*im.width/4),round((i%4+1)*im.width/4)
        y,y1=round(i//4*im.height/4),round((i//4+1)*im.height/4)
        tile=im.crop((x,y,x1,y1));bounds=tile.getchannel('A').point(lambda a:255 if a>32 else 0).getbbox()
        assert bounds,(key,i,'empty')
        edge=min(bounds[0],bounds[1],tile.width-bounds[2],tile.height-bounds[3])
        assert edge>0,(key,i,'touches cell boundary')
        frames.append({'rect':[x,y,x1-x,y1-y],'bounds':list(bounds),'pivot':[(bounds[0]+bounds[2])/2,bounds[3]],'edge_padding_px':edge})
        tiles.append(tile)
    ref=statistics.median(f['bounds'][3]-f['bounds'][1] for f in frames[:6])
    # Side-lying art pivots around its footprint rather than the last boot pixel.
    frames[11]['pivot']=[(frames[11]['bounds'][0]+frames[11]['bounds'][2])/2,(frames[11]['bounds'][1]+frames[11]['bounds'][3])/2]
    actions={**base,**special[key]}
    for name,(seq,fps,loop) in actions.items():
        ims=[]
        for index in seq:
            tile=tiles[index]; factor=250/ref; canvas=Image.new('RGBA',(440,360))
            tile=tile.resize((round(tile.width*factor),round(tile.height*factor)),Image.Resampling.LANCZOS)
            px,py=frames[index]['pivot'];canvas.alpha_composite(tile,(round(220-px*factor),round(300-py*factor)));ims.append(canvas)
        ims[0].save(O/'animations'/f'{key}-{name}.webp',save_all=True,append_images=ims[1:],duration=round(1000/fps),loop=0 if loop else 1,lossless=True)
    lines=['[gd_resource type="SpriteFrames" load_steps=18 format=3]',f'[ext_resource type="Texture2D" path="res://assets/{key}.png" id="1"]']
    for i,f in enumerate(frames):lines.append(f'[sub_resource type="AtlasTexture" id="F{i}"]\natlas = ExtResource("1")\nregion = Rect2({", ".join(map(str,f["rect"]))})')
    entries=[]
    for name,(seq,fps,loop) in actions.items():
        entries.append('{"frames":['+','.join('{"duration":1.0,"texture":SubResource("F%d")}'%i for i in seq)+'],"loop":'+str(loop).lower()+',"name":&"'+name+'","speed":'+str(float(fps))+'}')
    lines.append('[resource]\nanimations=['+',\n'.join(entries)+']')
    native='\n\n'.join(lines)
    (G/'assets'/f'{key}.tres').write_text(native,'utf8')
    (A/f'{key}.tres').write_text(native.replace('res://assets/', 'res://assets/tactical/cavalry-police-20261116/'),'utf8')
    row={'key':key,'name':labels[key],'frames':frames,'reference_height':ref,'actions':{n:{'frames':s,'fps':f,'loop':l} for n,(s,f,l) in actions.items()}}
    receipt['roles'].append(row)
    # Every locomotion phase must actually differ, not just be an identical shifted tile.
    assert len({hashlib.sha256(t.crop(t.getbbox()).tobytes()).hexdigest() for t in tiles[2:6]})==4
(D/'asset-ledger.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),'utf8')
for dst in [O/'asset-ledger.json',G/'catalogue.json']:shutil.copyfile(D/'asset-ledger.json',dst)
(O/'catalogue.js').write_text('window.CATALOGUE='+json.dumps(receipt,ensure_ascii=False)+';','utf8')
shutil.copyfile(R/'docs/design/cavalry-police-20261116.md',O/'design.md')
board=Image.new('RGB',(1600,1020),'#eee9dd');draw=ImageDraw.Draw(board)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',34);small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',23)
draw.text((45,25),'CAS  /  第2骑兵团 · 第17特种警察团',font=font,fill='#203a3b')
for x,key,label in [(30,'cavalry-portrait','岚缨 · 第2骑兵团  /  3连 × 5骑'),(815,'police-portrait','青巡 · 第17特种警察团  /  3连 × 6身体')]:
    im=Image.open(A/(key+'.png'));im.thumbnail((720,720));board.paste(im,(x+(740-im.width)//2,95),im);draw.text((x+15,820),label,font=small,fill='#203a3b')
for n,row in enumerate(receipt['roles']):
    im=Image.open(A/(row['key']+'.png'));f=row['frames'][0];x,y,w,h=f['rect'];tile=im.crop((x,y,x+w,y+h));tile.thumbnail((160,145));board.paste(tile,(75+n*305,860),tile)
board.save(O/'overview.jpg',quality=94)
print(json.dumps({'assets':len(receipt['assets']),'authored_frames':sum(len(r['frames']) for r in receipt['roles']),'roles':len(receipt['roles']),'sha_preserved':all(r['bytes_preserved'] for r in receipt['assets'].values())}))
