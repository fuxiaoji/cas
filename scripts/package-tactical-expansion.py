"""Package generated originals; author atlas metadata and animation previews."""
from pathlib import Path
import json, shutil, hashlib, html, statistics
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / 'docs/art/tactical-expansion-20261115'
ASSET = ROOT / 'godot/assets/tactical/expansion-20261115'
OUT = ROOT / 'output/tactical-expansion-20261115'
JOBS = json.loads((DOC / 'generation-input.json').read_text(encoding='utf-8'))
for p in (ASSET, OUT / 'assets', OUT / 'animations'):
    p.mkdir(parents=True, exist_ok=True)
BODY_ACTIONS = {
    'idle': {'frames': [0,0,0,0,0,0,0,1], 'fps': 4, 'loop': True},
    'walk': {'frames': [2,3,4,5], 'fps': 8, 'loop': True},
    'aim': {'frames': [6], 'fps': 1, 'loop': True},
    'fire': {'frames': [6,7,6], 'fps': 10, 'loop': False},
    'hurt': {'frames': [8,0], 'fps': 6, 'loop': False},
    'search': {'frames': [9], 'fps': 1, 'loop': True},
    'defeated': {'frames': [10,11,11,11,11,11,11,11], 'fps': 4, 'loop': False},
}
VEHICLE_ACTIONS = {
    'idle': {'frames': [0], 'fps': 1, 'loop': True},
    'drive': {'frames': [1,2,3,2], 'fps': 8, 'loop': True},
    'swim': {'frames': [4,5,6,5], 'fps': 5, 'loop': True},
    'beach': {'frames': [4,5,6,7,0], 'fps': 3, 'loop': False},
    'fire': {'frames': [8,9,8], 'fps': 8, 'loop': False},
    'ramp': {'frames': [10], 'fps': 1, 'loop': True},
    'disabled': {'frames': [11], 'fps': 1, 'loop': False},
}
FONT = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 24)
SMALL = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 18)
TITLE = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 42)
receipt = {'generator': 'built-in image_gen', 'runtime_units_added': False,
           'original_pixels_modified': False, 'units': [], 'checks': []}
board = Image.new('RGB', (1600, 1240), '#eee9dd')
d = ImageDraw.Draw(board)
d.text((42,25), 'CAS  /  新战术部队 · 秋冬登陆编队', fill='#243e42', font=TITLE)
d.text((44,86), '三名步兵主力 + 两名少人数两栖战车人格  /  立绘与动作美术预览', fill='#596b68', font=FONT)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def place(canvas, im, box):
    im = im.copy(); im.thumbnail((box[2], box[3]), Image.Resampling.LANCZOS)
    canvas.paste(im, (int(box[0]+(box[2]-im.width)/2), int(box[1]+(box[3]-im.height)/2)), im)

def make_tres(uid, kind, size, actions, frames):
    texture_path = f'res://assets/tactical/expansion-20261115/{uid}-{kind}.png'
    lines = ['[gd_resource type="SpriteFrames" load_steps=14 format=3]',
             f'[ext_resource type="Texture2D" path="{texture_path}" id="1"]']
    for i, frame in enumerate(frames):
        x,y,w,h = frame['rect']
        lines += [f'[sub_resource type="AtlasTexture" id="Atlas_{i}"]',
                  'atlas = ExtResource("1")', f'region = Rect2({x}, {y}, {w}, {h})']
    entries = []
    for name, a in actions.items():
        seq = ', '.join('{"duration": 1.0, "texture": SubResource("Atlas_%d")}' % i for i in a['frames'])
        entries.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}' % (seq,str(a['loop']).lower(),name,float(a['fps'])))
    lines += ['[resource]', 'animations = [' + ',\n'.join(entries) + ']']
    (ASSET / f'{uid}-{kind}.tres').write_text('\n\n'.join(lines), encoding='utf-8')

for n, job in enumerate(JOBS['profiles']):
    row = {k: v for k,v in job.items() if k != 'assets'}
    row['status'] = 'art_ready_design_proposal_not_recruitable'
    row['assets'] = {}
    for kind, meta in job['assets'].items():
        source = Path(meta['source']); target = ASSET / f'{job["id"]}-{kind}.png'
        shutil.copyfile(source, target)
        shutil.copyfile(source, OUT / 'assets' / target.name)
        im = Image.open(target).convert('RGBA'); alpha = im.getchannel('A')
        assert alpha.getextrema()[0] == 0 and alpha.getextrema()[1] > 200
        record = dict(meta, path='res://assets/tactical/expansion-20261115/'+target.name,
                      sha256=digest(target), size=list(im.size), alpha_extrema=list(alpha.getextrema()),
                      alpha_zero_pixels=alpha.histogram()[0], source_bytes_preserved=digest(source)==digest(target))
        if kind != 'portrait':
            cw,ch = im.width//4,im.height//3
            assert im.width % 4 == 0 and im.height % 3 == 0
            frames=[]; tiles=[]; boxes=[]
            for i in range(12):
                x,y=(i%4)*cw,(i//4)*ch
                tile=im.crop((x,y,x+cw,y+ch))
                bounds=tile.getchannel('A').point(lambda a: 255 if a>32 else 0).getbbox()
                assert bounds, (job['id'],kind,i)
                boxes.append(bounds); tiles.append(tile)
                frames.append({'rect':[x,y,cw,ch], 'pivot':[cw/2,ch*.94], 'bounds':list(bounds)})
            baseline=statistics.median(b[3] for b in boxes[:6])
            for i,f in enumerate(frames):
                f['pivot']=[cw/2,baseline] if kind=='sprite' else [cw/2,ch*.8]
            actions = BODY_ACTIONS if kind=='sprite' else VEHICLE_ACTIONS
            record.update(frames=frames,animations=actions,grid=[4,3],single_angle=True,
                          reference_height=statistics.median(b[3]-b[1] for b in boxes[:6]),
                          visual_only=True)
            make_tres(job['id'],kind,im.size,actions,frames)
            sequences = {key:spec['frames'] for key,spec in actions.items()}
            sequences['showcase'] = ([0]*8+[1]+[2,3,4,5]*3+[6,7,6]*2+[9]*5+[8]+[10]+[11]*12) if kind=='sprite' else [0]*4+[1,2,3,2]*2+[4,5,6,5]*3+[7]*4+[8,9,8]*2+[10]*5+[11]*6
            for action, seq in sequences.items():
                clip=[]
                for i in seq:
                    # Animation assembly only: source atlas artwork is untouched.
                    canvas=Image.new('RGBA',(cw,ch),(0,0,0,0))
                    dx=round(cw/2-frames[i]['pivot'][0])
                    dy=round(ch*.94-frames[i]['pivot'][1]) if kind=='sprite' else 0
                    canvas.alpha_composite(tiles[i],(dx,dy));clip.append(canvas)
                duration=round(1000/actions.get(action,{'fps':8})['fps'])
                output=OUT/'animations'/f'{job["id"]}-{kind}-{action}.webp'
                save_args={'save_all':True,'append_images':clip[1:],'duration':duration,'lossless':True}
                if action=='showcase' or actions[action]['loop']:save_args['loop']=0
                else:save_args['loop']=1
                clip[0].save(output,**save_args)
                check=Image.open(output)
                receipt['checks'].append({'animation':output.name,'decoded_frames':getattr(check,'n_frames',1),'expected_input_frames':len(seq)})
            record['cell_alpha_bounds']=boxes
        row['assets'][kind]=record
    receipt['units'].append(row)
    left=20+n*316
    d.rounded_rectangle((left,140,left+300,1205),radius=16,fill='#fffdf7')
    d.text((left+18,160),job['name'],fill='#263e42',font=TITLE)
    d.text((left+18,218),job['role'],fill='#5b716b',font=SMALL)
    portrait=Image.open(ASSET/f'{job["id"]}-portrait.png').convert('RGBA')
    place(board,portrait,(left+10,255,280,590))
    sheet=Image.open(ASSET/f'{job["id"]}-sprite.png').convert('RGBA')
    tile=sheet.crop((0,0,sheet.width//4,sheet.height//3))
    place(board,tile,(left+60,870,180,180))
    d.text((left+18,1080),f'{job["companies"]}连 × {job["bodies"]}身体',fill='#354f50',font=FONT)
    d.text((left+18,1120),job['id'],fill='#8a7252',font=SMALL)
    if 'vehicle' in job['assets']:
        d.text((left+18,1156),'每连1辆海陆同体战车',fill='#5b716b',font=SMALL)

board.save(OUT/'overview.jpg',quality=94)
(DOC/'asset-ledger.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
webrows=[]
for row in receipt['units']:
    r={k:row[k] for k in ('id','name','role','companies','bodies','tactic','weakness')}
    r['assets']={k:{'file':'assets/'+Path(v['path']).name,**({key:v[key] for key in ('frames','animations','reference_height')} if k!='portrait' else {})} for k,v in row['assets'].items()}
    webrows.append(r)
(OUT/'catalogue.js').write_text('window.CATALOGUE='+json.dumps(webrows,ensure_ascii=False)+';',encoding='utf-8')
shutil.copyfile(DOC/'asset-ledger.json',OUT/'asset-ledger.json')
(OUT/'verification.json').write_text(json.dumps({'units':5,'portraits':5,'body_atlases':5,'vehicle_atlases':2,'original_pixels_modified':False,'checks':receipt['checks']},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'units':len(webrows),'atlases':7,'animation_exports':len(receipt['checks']),'album':str(OUT/'index.html')},ensure_ascii=False))

# A minimal, isolated native animation viewer never opens the user's account.
native = OUT / 'native-preview'
native_assets = native / 'assets/tactical/expansion-20261115'
native_assets.mkdir(parents=True,exist_ok=True)
for f in ASSET.iterdir():
    if f.suffix in ('.png','.tres'): shutil.copyfile(f,native_assets/f.name)
(native/'project.godot').write_text('[application]\nconfig/name="CAS Tactical Art Preview"\nrun/main_scene="res://preview.tscn"\n[display]\nwindow/size/viewport_width=1440\nwindow/size/viewport_height=900\n[rendering]\nrenderer/rendering_method="gl_compatibility"\nenvironment/defaults/default_clear_color=Color(0.92,0.93,0.88,1)\n',encoding='utf-8')
scene=['[gd_scene load_steps=8 format=3]']
sprites=[]
for row in webrows:
    sprites.append((row['id'],'sprite',row['name'],row['role']))
for row in webrows:
    if 'vehicle' in row['assets']:sprites.append((row['id'],'vehicle',row['name'],'Amphibious vehicle'))
for i,(uid,kind,name,role) in enumerate(sprites):
    scene.append(f'[ext_resource type="SpriteFrames" path="res://assets/tactical/expansion-20261115/{uid}-{kind}.tres" id="{i+1}"]')
scene.append('[node name="TacticalArtPreview" type="Node2D"]')
for i,(uid,kind,name,role) in enumerate(sprites):
    x=150+i*280 if i<5 else 480+(i-5)*480
    y=300 if i<5 else 700
    action='walk' if kind=='sprite' else 'swim'
    scene.append(f'[node name="Sprite{i}" type="AnimatedSprite2D" parent="."]\nposition = Vector2({x}, {y})\nscale = Vector2(0.7, 0.7)\nsprite_frames = ExtResource("{i+1}")\nanimation = &"{action}"\nautoplay = "{action}"')
    scene.append(f'[node name="Label{i}" type="Label" parent="."]\noffset_left = {x-120}.0\noffset_top = {y-180}.0\noffset_right = {x+120}.0\noffset_bottom = {y-140}.0\ntheme_override_colors/font_color = Color(0.12,0.24,0.26,1)\ntheme_override_font_sizes/font_size = 23\ntext = "{uid} {name}"\nhorizontal_alignment = 1')
(native/'preview.tscn').write_text('\n\n'.join(scene),encoding='utf-8')
