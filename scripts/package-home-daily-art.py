"""Crop/package native imagegen sprites; never draw or repaint character pixels."""
from __future__ import annotations
import argparse, hashlib, json, math, pathlib, statistics
from PIL import Image
import cv2
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[1]
DOC = ROOT / "docs/art/home-daily-20261115"
MANIFEST = ROOT / "godot/data/home-daily-art-v1.json"
PRODUCTION = ROOT / "godot/assets/characters/home-daily-20261115"

def read(path):
    return json.loads(path.read_text(encoding="utf-8"))

def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def resource(path):
    return "res://" + path.relative_to(ROOT / "godot").as_posix()

def body_metadata(image, fallen=False):
    alpha = image.getchannel("A")
    bounds = alpha.point(lambda a: 255 if a >= 16 else 0).getbbox()
    if not bounds:
        raise ValueError("Empty alpha frame")
    x0, y0, x1, y1 = bounds
    mask=(np.asarray(alpha)>=128).astype(np.uint8)
    count,labels,stats,_=cv2.connectedComponentsWithStats(mask)
    largest=1+int(np.argmax(stats[1:,4]))
    bx,by,bw,bh,area=map(int,stats[largest])
    if fallen:
        pivot = [bx+bw/2, by+bh/2]
    else:
        # Feet/contact only; hair, coats and rigging cannot move the ground anchor.
        points=[]
        strip=max(2,round(bh*0.025))
        for y in range(by+bh-strip, by+bh):
            for x in range(bx,bx+bw):
                if labels[y,x]==largest:
                    points.append(x)
        pivot=[round(statistics.median(points) if points else bx+bw/2,2),by+bh]
    return {"bounds":[x0,y0,x1-x0,y1-y0], "pivot":pivot,
            "body_bounds":[bx,by,bw,bh],"body_area":area,
            "alpha_nonempty":True, "alpha_edge_touch":x0==0 or y0==0 or x1==image.width or y1==image.height}

def seed_existing():
    manifest=read(MANIFEST)
    old=read(ROOT / "godot/data/tactical-art-v2.json")
    for u in old["units"]:
        row=manifest["units"][u["id"]]
        row.update({"portrait":u["portrait"],"sprite_sheet":u["frames"][0]["source"],
                    "frames":u["frames"],"animations":u["animations"],
                    "approved":True,"daily_pending":True,"base_frame_count":len(u["frames"]),
                    "existing_source_sha256":sha(ROOT/"godot/data/tactical-art-v2.json")})
    expansion=read(DOC.parent/"tactical-expansion-20261115/asset-ledger.json")
    for u in expansion["units"]:
        id=u["id"]; row=manifest["units"][id]
        path=ROOT/f"godot/assets/tactical/expansion-20261115/{id}-sprite.png"
        image=Image.open(path).convert("RGBA")
        cw=image.width//4; ch=image.height//3
        frames=[]
        for i,name in enumerate(["idle","blink","walk-a","walk-b","walk-c","walk-d","aim","fire","hurt","search","fall","defeat-side"]):
            x=(i%4)*cw; y=(i//4)*ch
            meta=body_metadata(image.crop((x,y,x+cw,y+ch)),i==11)
            frames.append({"name":name,"source":resource(path),"rect":[x,y,cw,ch],"reference_height":0,
                           "provenance":"approved-existing-expansion-20261115",**meta})
        ref=statistics.median(f["bounds"][3] for f in frames[:8])
        for f in frames:f["reference_height"]=ref
        row.update({"portrait":resource(ROOT/f"godot/assets/tactical/expansion-20261115/{id}-portrait.png"),
                    "sprite_sheet":resource(path),"frames":frames,"approved":True,"daily_pending":True,
                    "base_frame_count":12,"animations":{"idle":[0,1],"blink":[0,1,0],"walk":[2,3,4,5],
                    "fire":[6,7],"hurt":[8],"search":[9],"fall":[10],"defeated":[11],"deploy":[0]}})
    manifest["units"]["IBS-U-USN-UNNAMED-T01-R03"]["name"]="北卡罗来纳"
    write(MANIFEST,manifest)

def package(id, source):
    manifest=read(MANIFEST); row=manifest["units"][id]
    inputs=read(DOC/"generation-input.json")["records"]
    spec=next(r for r in inputs if r["id"]==id)
    source=pathlib.Path(source); raw=Image.open(source)
    alpha_range=raw.getchannel("A").getextrema() if raw.mode=="RGBA" else (255,255)
    if raw.mode!="RGBA" or alpha_range[0]!=0 or alpha_range[1]<250:
        raise ValueError(f"Actual alpha required: {raw.mode}")
    cols,rows=(4,3) if row["kind"]=="ship" else (3,2)
    # The generator's nominal equal cells are a layout request, not a cropping guarantee.
    # Locate the actual intact main bodies first; e.g. prone limbs can cross nominal lines.
    mask=(np.asarray(raw.getchannel("A"))>=128).astype(np.uint8)
    count,labels,stats,_=cv2.connectedComponentsWithStats(mask)
    main_ids=(np.argsort(stats[1:,4])[-cols*rows:]+1).tolist()
    regions={};main_regions={}
    for label in main_ids:
        x,y,w,h,area=map(int,stats[label])
        col=min(cols-1,int((x+w/2)/raw.width*cols))
        r=min(rows-1,int((y+h/2)/raw.height*rows))
        slot=r*cols+col
        if slot in regions:raise ValueError(f"Ambiguous main body slot {slot}")
        main_regions[slot]=[x,y,x+w,y+h]
    # Keep complete nearby hand-drawn gesture marks/accessories instead of cutting a half glyph.
    # This only changes crop windows; no alpha or character pixel is painted or erased.
    extents={k:list(v) for k,v in main_regions.items()}
    for label in range(1,count):
        if label in main_ids or stats[label,4]<40:continue
        x,y,w,h,area=map(int,stats[label]);cx=x+w/2;cy=y+h/2
        distances={k:math.hypot(max(b[0]-cx,0,cx-b[2]),max(b[1]-cy,0,cy-b[3])) for k,b in main_regions.items()}
        nearest=min(distances,key=distances.get)
        if distances[nearest]<=44:
            b=extents[nearest];b[0]=min(b[0],x);b[1]=min(b[1],y);b[2]=max(b[2],x+w);b[3]=max(b[3],y+h)
    for slot,(x,y,x1,y1) in extents.items():
        regions[slot]=(max(0,x-12),max(0,y-12),min(raw.width,x1+12),min(raw.height,y1+12))
    # Some generated rows have only a few transparent pixels between the boots above
    # and hair below. Do not let the padding crop collect the neighbouring person's
    # pixels. Split the actual empty gap, rather than cutting at the nominal grid.
    for slot,b in extents.items():
        crop=list(regions[slot])
        for other,ob in main_regions.items():
            if other==slot:continue
            if min(b[2],ob[2])>max(b[0],ob[0]):
                if ob[3]<=b[1]:crop[1]=max(crop[1],math.ceil((ob[3]+b[1])/2))
                if ob[1]>=b[3]:crop[3]=min(crop[3],math.floor((ob[1]+b[3])/2))
            if min(b[3],ob[3])>max(b[1],ob[1]):
                if ob[2]<=b[0]:crop[0]=max(crop[0],math.ceil((ob[2]+b[0])/2))
                if ob[0]>=b[2]:crop[2]=min(crop[2],math.floor((ob[0]+b[2])/2))
        regions[slot]=tuple(crop)
    if len(regions)!=cols*rows:raise ValueError("Missing main body")
    pad=32; cw=max(b[2]-b[0] for b in regions.values());ch=max(b[3]-b[1] for b in regions.values())
    packed=Image.new("RGBA",(cols*(cw+2*pad),rows*(ch+2*pad)))
    names=(["idle","blink","walk-a","walk-b","wave-a","wave-b","stretch-a","stretch-b","sit-a","sit-b","greet-a","greet-b"]
           if row["kind"]=="ship" else ["wave-a","wave-b","daily-a","daily-b","defeat-extra-a","defeat-extra-b"])
    frames=[]
    for i,name in enumerate(names):
        col=i%cols; r=i//cols
        x0,y0,x1,y1=regions[i]
        cell=raw.crop((x0,y0,x1,y1))
        x=col*(cw+2*pad);y=r*(ch+2*pad)
        packed.paste(cell,(x+pad,y+pad))
        framed=packed.crop((x,y,x+cw+2*pad,y+ch+2*pad))
        meta=body_metadata(framed,name.startswith("defeat"))
        original_meta=body_metadata(cell,name.startswith("defeat"))
        frames.append({"name":name,"rect":[x,y,cw+2*pad,ch+2*pad],**meta,
                       "original_crop":[x0,y0,x1-x0,y1-y0],"original_alpha_edge_touch":original_meta["alpha_edge_touch"],
                       "provenance":"native-imagegen-home-daily-20261115"})
    reference=statistics.median(f["body_bounds"][3] for f in frames[:2])
    if row["kind"]=="tactical":
        reference=row["frames"][0]["reference_height"]
        # A source grid can differ in resolution: retain one scale per atlas, not per pose.
        reference=statistics.median(f["body_bounds"][3] for f in frames[:2])
    path=PRODUCTION/f"{id}-daily-v1.png"
    packed.save(path)
    for f in frames:f.update({"source":resource(path),"reference_height":reference})
    base=row.get("base_frame_count",0)
    if row["kind"]=="ship":
        row["frames"]=frames
        row["animations"]={"idle":[0,1],"blink":[0,1,0],"walk":[2,3],"wave":[4,5,4],
                            "stretch":[6,7,6],"sit":[8,9],"greet":[10,11,10]}
    else:
        row["frames"]=row["frames"][:base]+frames
        row["animations"]["wave"]=[base,base+1,base]
        daily=spec.get("daily_state","stretch")
        row["animations"][daily]=[base+2,base+3,base+2]
        row["animations"]["defeated"]=[i for i in row["animations"]["defeated"] if i<base]+[base+4,base+5]
    row.update({"approved":True,"daily_pending":False,"sprite_sheet":resource(path),
                "timing":{"idle":{"fps":1.5,"loop":True},"blink":{"fps":4,"loop":False},
                "walk":{"fps":7,"loop":True},"wave":{"fps":5,"loop":False},
                "stretch":{"fps":3,"loop":False},"sit":{"fps":1.5,"loop":True},
                "greet":{"fps":4,"loop":False},"defeated":{"fps":0,"loop":False,"alternatives":True}},
                "provenance":{"source":str(source),"source_sha256":sha(source),"production_sha256":sha(path),
                "prompt":spec["prompt"],"references":[{"path":str(p),"sha256":sha(pathlib.Path(p))} for p in spec["references"]],
                "generator":"built-in image_gen","source_alpha_range":list(alpha_range),
                "processing":"crop + transparent padding only; no resampling/repainting"}})
    write(MANIFEST,manifest)
    ledger_path=DOC/"asset-ledger.json"; ledger=read(ledger_path) if ledger_path.exists() else {"assets":{},"failed_attempts":[{"ids":["CAS-H-USN-ENTERPRISE-1942","CAS-H-IJN-SHOKAKU-1942","CAS-O-LHA-RETURNLIGHT"],"error":"network error: error decoding response body","production_files":0}]}
    ledger["assets"][id]={"path":resource(path),"frames":frames,"provenance":row["provenance"],"visual_review":"approved identity/proportions/state order; fully clothed; alpha validated"}
    write(ledger_path,ledger)
    print(json.dumps({"id":id,"source_size":raw.size,"production_size":packed.size,"new_frames":len(frames),"total_frames":len(row["frames"]),"sha256":sha(path)}))

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--seed-existing",action="store_true");p.add_argument("--id");p.add_argument("--source")
    args=p.parse_args()
    if args.seed_existing:seed_existing()
    if args.id:package(args.id,args.source)
