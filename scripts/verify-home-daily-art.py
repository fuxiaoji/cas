"""Verify actual packaged art, source pixel preservation, crops and identity bindings."""
from pathlib import Path
import hashlib
import json
import math
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
DOC=ROOT/'docs/art/home-daily-20261115'
MANIFEST=ROOT/'godot/data/home-daily-art-v1.json'

def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def file(p):return ROOT/'godot'/p.removeprefix('res://')
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
FONT=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',16)
SMALL=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',12)

def main():
    m=read(MANIFEST);ledger=read(DOC/'asset-ledger.json');checks=[];images={}
    def check(value,label):checks.append({'passed':bool(value),'check':label})
    def load(p):
        if p not in images:images[p]=Image.open(file(p)).convert('RGBA')
        return images[p]
    check(len(m['units'])==33,'33 exact identities')
    ships=[u for u in m['units'].values() if u['kind']=='ship'];tactical=[u for u in m['units'].values() if u['kind']=='tactical']
    check(len(ships)==6 and len(tactical)==27,'6 garrison ships and 27 tactical identities')
    check(m['units']['IBS-U-USN-UNNAMED-T01-R03']['name']=='北卡罗来纳','R03 is North Carolina, never Missouri')
    check(m['units']['CAS-O-LHA-RETURNLIGHT']['name']=='返航灯','Returnlight uses current actual catalogue name')
    new_frames=0;down=0
    for id,u in m['units'].items():
        check(u['id']==id and u['approved'] is True,id+' exact-ID approved')
        check(file(u['portrait']).is_file(),id+' identity portrait exists')
        for i,f in enumerate(u['frames']):
            label=f'{id}/{i}:{f["name"]}'
            image=load(f['source']);x,y,w,h=f['rect'];px,py=f['pivot']
            check(0<=x and 0<=y and w>0 and h>0 and x+w<=image.width and y+h<=image.height,label+' actual bounds')
            check(all(math.isfinite(v) for v in [px,py,f['reference_height']]) and 0<=px<=w and 0<=py<=h and f['reference_height']>0,label+' finite local anchor and scale')
            frame=image.crop((x,y,x+w,y+h));a=frame.getchannel('A')
            check(a.getextrema()[0]==0 and a.getextrema()[1]>=250,label+' real alpha and visible subject')
            if f.get('provenance')=='native-imagegen-home-daily-20261115':
                new_frames+=1;prov=u['provenance'];raw=Image.open(prov['source']).convert('RGBA');cx,cy,cw,ch=f['original_crop']
                check(frame.crop((32,32,32+cw,32+ch)).tobytes()==raw.crop((cx,cy,cx+cw,cy+ch)).tobytes(),label+' exact source pixels preserved')
                box=a.point(lambda v:255 if v>=16 else 0).getbbox()
                check(box and box[0]>0 and box[1]>0 and box[2]<w and box[3]<h,label+' full subject inside transparent padding')
                check(not f['original_alpha_edge_touch'],label+' source crop not cutting visible alpha')
        for state,indices in u['animations'].items():
            check(bool(indices) and all(isinstance(i,int) and 0<=i<len(u['frames']) for i in indices),id+'/'+state+' valid frame indices')
        if u['kind']=='tactical':
            poses=u['animations']['defeated'];down+=len(poses)
            check(len(set(poses))>=3,id+' at least three distinct final down frames')
        if id in ledger['assets']:
            l=ledger['assets'][id];p=u['provenance']
            check(sha(Path(p['source']))==p['source_sha256'],id+' native source SHA')
            check(sha(file(u['sprite_sheet']))==p['production_sha256']==l['provenance']['production_sha256'],id+' final production SHA')
            check(l['frames']==[f for f in u['frames'] if f.get('provenance')=='native-imagegen-home-daily-20261115'],id+' ledger exact final frames')
            for r in p['references']:check(sha(Path(r['path']))==r['sha256'],id+' unchanged original identity/style reference')
    check(new_frames==102,'102 new individually drawn frames')
    check(len(ledger['assets'])==11,'11 new identity PNGs')
    def contact(rows,states,path,cell_w=160,cell_h=195,columns=12):
        qa=Image.new('RGB',(columns*cell_w, len(rows)*cell_h),'#e7edef');draw=ImageDraw.Draw(qa)
        for row,u in enumerate(rows):
            indices=states(u)
            for col,i in enumerate(indices):
                f=u['frames'][i];x,y,w,h=f['rect'];crop=load(f['source']).crop((x,y,x+w,y+h));scale=115/f['reference_height']
                if crop.width*scale>cell_w-8:scale=(cell_w-8)/crop.width
                crop=crop.resize((max(1,round(crop.width*scale)),max(1,round(crop.height*scale))),Image.Resampling.LANCZOS)
                fallen=i in u['animations'].get('defeated',[])
                anchor_y=row*cell_h+(110 if fallen else 158);anchor_x=col*cell_w+cell_w/2
                px=round(anchor_x-f['pivot'][0]*scale);py=round(anchor_y-f['pivot'][1]*scale)
                qa.paste(crop,(px,py),crop)
                draw.line((anchor_x-4,anchor_y,anchor_x+4,anchor_y),fill='#d73a3a',width=1)
                draw.line((anchor_x,anchor_y-4,anchor_x,anchor_y+4),fill='#d73a3a',width=1)
                draw.text((col*cell_w+4,row*cell_h+3),u['id'],font=SMALL,fill='#143244')
                draw.text((col*cell_w+4,row*cell_h+174),f'{i} {f["name"]}',font=SMALL,fill='#143244')
        qa.save(path,quality=95)
    contact(ships,lambda u:list(range(12)),DOC/'six-ships-qa.jpg')
    five=[u for u in tactical if u['id'] in [f'MCP-{i}' for i in range(301,306)]]
    contact(five,lambda u:list(range(12,18)),DOC/'new-five-qa.jpg',cell_w=225,cell_h=205,columns=6)
    for page in range(3):contact(tactical[page*9:(page+1)*9],lambda u:u['animations']['defeated'],DOC/f'all-down-poses-{page+1}.jpg',cell_w=205,cell_h=190,columns=5)
    # Independently validate the two byte-preserved vehicle sheets and actual direction crops.
    vm=read(ROOT/'godot/data/tactical-vehicles-v4.json');vl=read(DOC/'vehicle-ledger.json');vehicle_checks_start=len(checks)
    for kind,v in vm['vehicles'].items():
        l=vl['assets'][kind];im=Image.open(file(v['atlas']))
        check(sha(Path(l['source_path']))==sha(file(v['atlas']))==l['production_sha256'],kind+' exact byte copy')
        check(im.mode=='RGBA' and im.getchannel('A').getextrema()==(0,255),kind+' genuine transparent alpha')
        check(set(v['frames'])==set('NESW'),kind+' four actual direction drawings')
        for i,(direction,f) in enumerate(v['frames'].items()):
            x,y,w,h=f['region'];px,py=f['anchor'];check(0<=x and 0<=y and x+w<=im.width and y+h<=im.height,kind+'/'+direction+' actual region')
            check(0<px<w and 0<py<h and f['scale_reference']>0 and f['forward_deg']=='NESW'.index(direction)*90,kind+'/'+direction+' hull anchor, scale and heading')
            a=im.crop((x,y,x+w,y+h)).getchannel('A');b=a.point(lambda v:255 if v>=128 else 0).getbbox()
            check(b and b[0]>0 and b[1]>0 and b[2]<w and b[3]<h,kind+'/'+direction+' full silhouette transparent margin')
        for r in l['references']:check(sha(Path(r['path']))==r['sha256'],kind+' unchanged original equipment reference')
    failures=[c['check'] for c in checks if not c['passed']]
    result={'scope':'Art metadata, actual alpha/crops/source/reference SHA and manual visual review; not runtime GPU acceptance',
            'identities':33,'tactical':27,'current_garrison_ships':6,'new_character_pngs':11,'new_character_frames':new_frames,
            'all_character_frames':sum(len(u['frames']) for u in m['units'].values()),'tactical_down_pose_records':down,
            'new_vehicle_pngs':2,'new_vehicle_direction_frames':8,'checks':len(checks),'passed':len(checks)-len(failures),'failures':failures,
            'vehicle_checks':len(checks)-vehicle_checks_start,'manifest_sha256':sha(MANIFEST),
            'vehicle_manifest_sha256':sha(ROOT/'godot/data/tactical-vehicles-v4.json'),'checks_detail':checks}
    write(DOC/'verification.json',result)
    print(json.dumps({k:v for k,v in result.items() if k!='checks_detail'}))
    if failures:raise SystemExit(1)

if __name__=='__main__':main()
