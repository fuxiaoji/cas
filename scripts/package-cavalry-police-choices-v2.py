"""Register ten independent portrait options without altering generated images."""
from pathlib import Path
import hashlib,json,zipfile
from PIL import Image

root=Path(__file__).resolve().parents[1]
out=root/'output/cavalry-police-choices-v2-20261116'
doc=root/'docs/art/cavalry-police-choices-v2-20261116'
jobs=json.loads((doc/'generation-input.json').read_text('utf8'))
rows=[]
for job in jobs['jobs']:
    path=out/(job['id']+'.png')
    source=Path((out/(job['id']+'-source.txt')).read_text('utf-8-sig').strip())
    im=Image.open(path);im.verify();im=Image.open(path)
    assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]==0 and im.getchannel('A').getextrema()[1]>=250,job['id']
    sha=hashlib.sha256(path.read_bytes()).hexdigest()
    assert sha==hashlib.sha256(source.read_bytes()).hexdigest(),job['id']
    rows.append({'id':job['id'],'label':job['label'],'path':str(path),'source':str(source),'sha256':sha,'size':list(im.size),'mode':im.mode,'genuine_alpha':True,'source_bytes_preserved':True,'selected':False})
assert len(rows)==10 and len({r['sha256'] for r in rows})==10
receipt={'status':'awaiting_user_selection','generator':'built-in image_gen','count':10,'runtime_or_account_modified':False,'assets':rows,'visual_review':'Each cavalry option inspected for four horse legs and four hooves, white horse, golden updo, saber, feather hat and half-body-front-covering cape; police uniforms compared visually; no loose trousers. No selection inferred.'}
(doc/'asset-ledger.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),'utf8')
(out/'asset-ledger.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),'utf8')
(out/'generation-input.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2),'utf8')
with zipfile.ZipFile(out.with_suffix('.zip'),'w',zipfile.ZIP_DEFLATED) as z:
    for path in out.iterdir():
        if path.is_file() and not path.name.endswith('-source.txt'):z.write(path,path.name)
print(json.dumps({'count':10,'unique':10,'transparent':10,'original_bytes_preserved':10,'zip':str(out.with_suffix('.zip'))},ensure_ascii=False))

