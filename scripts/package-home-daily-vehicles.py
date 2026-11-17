"""Package native imagegen vehicle pixels and explicit directional crops; no drawing."""
from pathlib import Path
import hashlib
import json
import shutil
import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / 'docs/art/home-daily-20261115'
PROD = ROOT / 'godot/assets/tactical/vehicles-v4'
SOURCE = Path('C:/Users/fwj/.codex/generated_images/01a1d9a4-b160-7ab3-be19-9d8ee4179b7c')
INPUTS = json.loads((DOC/'generation-input.json').read_text(encoding='utf-8'))
SPECS = [
    # Hull boxes exclude the cannon/antenna overhang, established by visual review.
    ('amphibious_wheeled_ifv', 'exec-e46b1a7c-148d-4293-9a14-2039ca95062d.png', 6.9,
     {'N':[175,64,240,457], 'E':[611,175,478,253], 'S':[178,711,247,472], 'W':[613,797,483,256]}),
    ('amphibious_tracked_gun', 'exec-b7363e15-f395-4753-be8f-d2eeb5f9c525.png', 7.4,
     {'N':[175,143,274,412], 'E':[693,211,429,246], 'S':[175,701,275,433], 'W':[675,791,439,254]}),
]

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v): p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def main():
    PROD.mkdir(parents=True,exist_ok=True)
    manifest={'version':'tactical-vehicles-v4','orientation':'N=up/E=right/S=down/W=left; heading north zero clockwise; TL/TR/BL/BR',
              'scope':'Two original equipment-only directional art overrides; no gameplay statistics override.', 'vehicles':{}}
    ledger={'generator':'built-in image_gen','pixel_processing':'Byte-for-byte copy; actual connected-object crop metadata only, no resizing, recolouring or pixel repainting.', 'assets':{}}
    qa=Image.new('RGB',(1400,750),'#e3e8eb');draw=ImageDraw.Draw(qa)
    for row,(kind,filename,length,hulls) in enumerate(SPECS):
        spec=next(r for r in INPUTS['records'] if r['id']==kind)
        src=SOURCE/filename;dst=PROD/(kind+'.png');shutil.copyfile(src,dst)
        im=Image.open(dst)
        assert im.mode=='RGBA' and im.getchannel('A').getextrema()==(0,255)
        n,labels,stats,_=cv2.connectedComponentsWithStats((np.asarray(im.getchannel('A'))>=128).astype('uint8'))
        ids=(np.argsort(stats[1:,4])[-4:]+1).tolist();objects={}
        for label in ids:
            x,y,w,h,area=map(int,stats[label]);slot=int((y+h/2)/im.height*2)*2+int((x+w/2)/im.width*2)
            direction='NESW'[slot];objects[direction]=(x,y,w,h)
        assert set(objects)==set('NESW')
        frames={}
        for col,direction in enumerate('NESW'):
            x,y,w,h=objects[direction];pad=12
            region=[max(0,x-pad),max(0,y-pad),min(im.width,x+w+pad)-max(0,x-pad),min(im.height,y+h+pad)-max(0,y-pad)]
            hx,hy,hw,hh=hulls[direction]
            anchor=[hx+hw/2-region[0],hy+hh/2-region[1]]
            frames[direction]={'region':region,'anchor':anchor,'scale_reference':hh if direction in 'NS' else hw,
                               'alpha_bbox_128':[x-region[0],y-region[1],w,h],
                               'hull_bbox':[hx-region[0],hy-region[1],hw,hh], 'forward_deg':col*90}
            crop=im.crop((region[0],region[1],region[0]+region[2],region[1]+region[3]))
            crop.thumbnail((280,280),Image.Resampling.LANCZOS)
            px=col*350+(350-crop.width)//2;py=row*375+55+(280-crop.height)//2
            qa.paste(crop,(px,py),crop);draw.text((col*350+12,row*375+15),kind+' '+direction,fill='#152e38')
            ax=px+anchor[0]/region[2]*crop.width;ay=py+anchor[1]/region[3]*crop.height
            draw.ellipse((ax-3,ay-3,ax+3,ay+3),outline='#d73528',width=2)
        entry={'atlas':'res://'+dst.relative_to(ROOT/'godot').as_posix(),'frames':frames,'length_m':length,
               'source_record':(DOC/(kind+'.json')).relative_to(ROOT).as_posix(),'status':'approved','render_role':'equipment_only',
               'source_sha256':sha(src),'dimension_basis':'Nominal original fictional hull length in metres, excluding cannon and antenna overhang. Not a historical transcription or gameplay collision override.',
               'anchor_basis':'Manually reviewed hull centre, excluding gun/antenna overhang; all four original orientations are separate drawings.'}
        manifest['vehicles'][kind]=entry
        record={'id':kind,'unit_id':spec['unit_id'],'generator':'built-in image_gen','prompt':spec['prompt'],
                'references':[{'path':p,'sha256':sha(Path(p))} for p in spec['references']],
                'source_path':str(src),'source_sha256':sha(src),'production_path':entry['atlas'],'production_sha256':sha(dst),
                'size':list(im.size),'alpha_extrema':list(im.getchannel('A').getextrema()),'frames':frames,
                'visual_review':'Approved orthographic overhead; actual N/E/S/W front and weapon orientation; no people, no water/ground, complete separate equipment silhouettes.',
                'length_m':length,'dimension_basis':entry['dimension_basis']}
        write(DOC/(kind+'.json'),record);ledger['assets'][kind]=record
        spec['generation_state']='generated_approved_packaged';spec['source_path']=str(src)
    write(ROOT/'godot/data/tactical-vehicles-v4.json',manifest)
    write(DOC/'vehicle-ledger.json',ledger);write(DOC/'generation-input.json',INPUTS)
    qa.save(DOC/'vehicles-v4-qa.jpg',quality=94)
    print(json.dumps({'vehicles':len(manifest['vehicles']),'manifest_sha256':sha(ROOT/'godot/data/tactical-vehicles-v4.json')}))

if __name__=='__main__':main()
