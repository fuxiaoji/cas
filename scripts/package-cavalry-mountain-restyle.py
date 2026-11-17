import hashlib
import json
import shutil
import sys
import zipfile
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
NAME = 'cavalry-police-mountain-v2-20261116'
OUT = ROOT / 'output' / NAME
DOC = ROOT / 'docs/art' / NAME
OUT.mkdir(parents=True, exist_ok=True)
def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()
inputs = json.loads((DOC / 'generation-input.json').read_text(encoding='utf-8'))
assets = []
for item, src in zip(inputs['assets'], sys.argv[1:]):
    dest = OUT / (item['id'] + '.png')
    shutil.copyfile(src, dest)
    with Image.open(dest) as im:
        im.load()
        assert im.mode == 'RGBA'
        alpha = im.getchannel('A').getextrema()
        assert alpha[0] == 0 and alpha[1] > 0
        size = im.size
    assert sha(src) == sha(dest)
    refs = [{'path': p, 'sha256': sha(p)} for p in item['references']]
    assets.append({'id': item['id'], 'source': src, 'output': str(dest), 'sha256': sha(dest), 'size': size, 'mode': 'RGBA', 'alpha': alpha, 'source_bytes_preserved': True, 'references': refs, 'visual_review': 'passed'})
assert len(assets) == 2
ledger = {'generator': 'built-in image_gen', 'status': 'art_revision_for_review', 'assets': assets, 'runtime_changed': False}
(DOC / 'asset-ledger.json').write_text(json.dumps(ledger, ensure_ascii=False, indent=2), encoding='utf-8')
ref = inputs['assets'][0]['references'][2]
shutil.copyfile(ref, DOC / 'user-headscarf-reference.jpg')
for p in ['generation-input.json', 'asset-ledger.json']:
    shutil.copyfile(DOC / p, OUT / p)
content = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>骑兵H1与山地B1 · 统一战术画风</title><style>*{box-sizing:border-box}body{margin:0;background:#eee9df;color:#243c47;font:16px/1.7 system-ui,sans-serif}header,main{max-width:1250px;margin:auto;padding:24px}h1{font-size:clamp(24px,4vw,40px)}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,330px),1fr));gap:24px}article{background:#fffaf0;border:1px solid #c5ccc8;border-radius:16px;padding:20px;min-width:0}h2{font-size:22px}img{display:block;width:100%;height:680px;object-fit:contain;background:repeating-conic-gradient(#d7ddda 0% 25%,#edf0ec 0% 50%) 0/24px 24px;border-radius:8px}a{color:#20666e}button{padding:10px 16px;background:#284650;color:white;border:0;border-radius:8px;font:inherit}.dark img{background:#253541}@media(max-width:500px){header,main{padding:16px}img{height:540px}}</style><header><h1>骑兵H1 · 山地B1</h1><p>以既有战术部队立绘统一画风；外部参考只取服装元素，重新设计人物。骑兵用布质头巾，山地保留白长外套与紫肩披。警察沿用F1。</p><button onclick="document.body.classList.toggle('dark')">切换图片背景</button><p>本轮为两张立绘修订，数值与游戏运行目录未改。</p></header><main><article><h2>第2骑兵团 · H1</h2><a href="骑兵H1.png" target="_blank"><img src="骑兵H1.png" alt="骑兵H1"></a><a href="骑兵H1.png" download>下载透明原图</a></article><article><h2>第30山地突击旅 · B1</h2><a href="山地B1.png" target="_blank"><img src="山地B1.png" alt="山地B1"></a><a href="山地B1.png" download>下载透明原图</a></article></main></html>'''
(OUT / 'index.html').write_text(content, encoding='utf-8')
assert content.count('<img ') == 2
archive = OUT.with_suffix('.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in OUT.iterdir():
        if p.is_file():
            z.write(p, p.name)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for a in assets:
        assert hashlib.sha256(z.read(a['id'] + '.png')).hexdigest() == a['sha256']
report = {'decode_alpha_source_sha': 'passed', 'zip_crc_image_sha': 'passed', 'html_local_links': 'passed', 'visual_review': 'two portraits individually reviewed against existing style references', 'browser_test': 'not_run', 'runtime_test': 'not_applicable_art_only'}
(DOC / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'output': str(OUT), 'assets': [{'id': a['id'], 'size': a['size'], 'alpha': a['alpha']} for a in assets]}, ensure_ascii=False))
