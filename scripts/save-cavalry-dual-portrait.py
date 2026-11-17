from pathlib import Path
from PIL import Image
import json,shutil,hashlib

R=Path(__file__).resolve().parents[1]
D=R/'docs/art/cavalry-dual-portrait-v4-20261116'
O=R/'output/cavalry-dual-portrait-v4-20261116'
A=R/'godot/assets/tactical/cavalry-dual-portrait-v4-20261116'
for p in [O,A]:p.mkdir(parents=True,exist_ok=True)
jobs=json.loads((D/'generation-input.json').read_text(encoding='utf8'))['jobs']
sources=json.loads((D/'source-map.json').read_text(encoding='utf8'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
ledger=[]
for j in jobs:
    source=Path(sources[j['id']]);dst=O/f'MCP-002-{j["id"]}.png'
    shutil.copyfile(source,dst);shutil.copyfile(source,A/dst.name)
    with Image.open(dst) as im:
        im.load();assert im.mode=='RGBA';size=im.size;alpha=im.getchannel('A').getextrema();assert alpha[0]==0 and alpha[1]>200
    assert sha(source)==sha(dst)==sha(A/dst.name)
    refs=[]
    for i,p in enumerate(j['referenced_image_paths']):
        copy=D/f'{j["id"]}-reference-{i+1}{Path(p).suffix}'
        shutil.copyfile(p,copy)
        refs.append(dict(actual_input=p,preserved_copy=str(copy),sha256=sha(p),role='identity and outfit; mounted edit target' if i==0 else 'standing pose and long-skirt attitude reference'))
    ledger.append(dict(id=j['id'],title=j['title'],generator='built-in image_gen',source=str(source),output=str(dst),project_asset=str(A/dst.name),size=size,alpha_range=alpha,sha256=sha(dst),source_bytes_preserved=True,references=refs,runtime_changed=False))
(D/'asset-ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),encoding='utf8')
for p in ['generation-input.json','asset-ledger.json']:shutil.copyfile(D/p,O/p)
print(json.dumps(ledger,ensure_ascii=False))
