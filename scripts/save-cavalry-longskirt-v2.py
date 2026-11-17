from pathlib import Path
from PIL import Image
import json,hashlib,shutil

R=Path(__file__).resolve().parents[1]
D=R/'docs/art/cavalry-longskirt-v2-20261116'
O=R/'output/cavalry-longskirt-v2-20261116'
A=R/'godot/assets/tactical/cavalry-longskirt-v2-20261116'
for p in [O,A]:p.mkdir(parents=True,exist_ok=True)
job=json.loads((D/'generation-input.json').read_text(encoding='utf8'))
source=Path(json.loads((D/'source-map.json').read_text(encoding='utf8'))['source'])
dst=O/'MCP-002-longskirt.png'
shutil.copyfile(source,dst);shutil.copyfile(source,A/dst.name)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
with Image.open(dst) as im:
    im.load();assert im.mode=='RGBA'
    alpha=im.getchannel('A').getextrema();assert alpha[0]==0 and alpha[1]>200
    size=im.size
refs=[]
for i,p in enumerate(job['referenced_image_paths']):
    out=D/f'reference-{i+1}{Path(p).suffix}'
    shutil.copyfile(p,out)
    refs.append(dict(actual_input=p,preserved_copy=str(out),sha256=sha(p),role='edit target' if i==0 else 'visible white breeches, bent leg, riding boot and stirrup structure only'))
assert sha(source)==sha(dst)==sha(A/dst.name)
ledger=dict(generator='built-in image_gen',source=str(source),output=str(dst),project_asset=str(A/dst.name),size=size,mode='RGBA',alpha_range=alpha,sha256=sha(dst),source_bytes_preserved=True,references=refs,runtime_changed=False)
(D/'asset-ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),encoding='utf8')
for p in ['asset-ledger.json','generation-input.json']:shutil.copyfile(D/p,O/p)
print(json.dumps(ledger,ensure_ascii=False))
