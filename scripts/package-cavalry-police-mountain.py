import hashlib
import json
import shutil
import sys
import zipfile
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
NAME = 'cavalry-police-mountain-20261116'
OUT = ROOT / 'output' / NAME
DOC = ROOT / 'docs/art' / NAME
OUT.mkdir(parents=True, exist_ok=True)
DOC.mkdir(parents=True, exist_ok=True)
REFROOT = Path('C:/Users/fwj/Documents/xwechat_files/wxid_2d12gr3fiopq12_9efa/temp/RWTemp/2026-11/9e20f478899dc29eb19741386f9343c8')
refs = [REFROOT / '7df0a13b6a14203a89251c1802dfb296.jpg', REFROOT / '35301afa88d946c30cdde302cf632e31.jpg']
def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()
for n, ref in enumerate(refs, 1):
    shutil.copyfile(ref, DOC / f'user-reference-{n}.jpg')
sources = [Path(sys.argv[1]), ROOT / 'output/cavalry-police-choices-v6-20261116/警察F1.png', Path(sys.argv[2])]
names = ['骑兵G1', '警察F1', '山地A1']
captions = ['第2骑兵团 · 岚缨｜3连×5骑，红发三角帽与自然身形新稿', '第17特种警察团 · 青巡｜3连×6身体，用户已选F1原图', '第30山地突击旅 · 岑翎（暂名）｜2连×8身体，每连6步枪/1机枪/1迫击炮']
ledger = {'status': 'portraits_and_design_review', 'generator': 'built-in image_gen (police reused original F1)', 'runtime_changed': False, 'assets': []}
for i, (src, name) in enumerate(zip(sources, names)):
    dst = OUT / f'{name}.png'
    shutil.copyfile(src, dst)
    assert sha(src) == sha(dst)
    with Image.open(dst) as im:
        im.load()
        assert im.mode == 'RGBA'
        alpha = im.getchannel('A').getextrema()
        assert alpha[0] == 0 and alpha[1] > 0
        size = list(im.size)
    ledger['assets'].append({'id': name, 'source': str(src), 'output': str(dst), 'sha256': sha(dst), 'size': size, 'mode': 'RGBA', 'alpha': alpha, 'source_bytes_preserved': True, 'reference': str(refs[0 if i == 0 else 1]) if i != 1 else 'Original police F1, selected by user', 'visual_review': 'passed; portraits only, not sprite animation'})
ledger['references'] = [{'path': str(p), 'sha256': sha(p), 'role': 'user-provided costume design reference'} for p in refs]
(DOC / 'asset-ledger.json').write_text(json.dumps(ledger, ensure_ascii=False, indent=2), encoding='utf-8')
for p in [DOC / 'asset-ledger.json', DOC / 'generation-input.json']:
    shutil.copyfile(p, OUT / p.name)
shutil.copyfile(ROOT / 'docs/design' / f'{NAME}.md', OUT / '部队设计稿.md')
cards = ''.join(f'<article><h2>{cap}</h2><a href="{n}.png" target="_blank"><img src="{n}.png" alt="{n}" loading="eager"></a><a class="download" href="{n}.png" download>下载原始透明PNG</a></article>' for n, cap in zip(names, captions))
html = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>骑兵·特警·山地｜续接设计</title><style>*{box-sizing:border-box}body{margin:0;background:#ece8e0;color:#203440;font:16px/1.7 system-ui,sans-serif}header,main,footer{max-width:1400px;margin:auto;padding:24px}h1{font-size:clamp(24px,4vw,42px);margin:0}p{max-width:900px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,330px),1fr));gap:20px}article{min-width:0;background:#fffaf1;border:1px solid #c9ccc5;border-radius:16px;overflow:hidden;padding:16px}h2{font-size:18px;min-height:70px}img{display:block;width:100%;height:640px;object-fit:contain;background:repeating-conic-gradient(#d4d9d8 0% 25%,#e9eeec 0% 50%) 0/24px 24px;border-radius:8px}a{color:#21616a;overflow-wrap:anywhere}.download{display:block;padding-top:12px}button{padding:10px 16px;border:0;border-radius:8px;background:#243e4b;color:white;font:inherit;cursor:pointer}.dark img{background:#26323d}@media(max-width:500px){header,main,footer{padding:16px}img{height:540px}h2{min-height:0}}</style><header><h1>骑兵 · 特警 · 山地</h1><p>已续接原聊天最后要求：骑兵重设为自然身形、警察采用F1、新增第30山地突击旅。点击图片可打开原图。</p><p>立绘与数值草案评审；未接正式招募、实战或动画。</p><button onclick="document.body.classList.toggle('dark')">切换图片背景</button> <a href="部队设计稿.md">完整数值与机制设计</a></header><main>''' + cards + '</main><footer>原始生成字节与透明通道保留。人物稿/设计初案不表示运行机制已实现。</footer></html>'
(OUT / 'index.html').write_text(html, encoding='utf-8')
for name in names:
    assert (OUT / f'{name}.png').exists()
assert html.count('<img ') == 3
archive = OUT.with_suffix('.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in OUT.iterdir():
        if p.is_file():
            z.write(p, p.name)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for name in names:
        assert hashlib.sha256(z.read(f'{name}.png')).hexdigest() == sha(OUT / f'{name}.png')
report = {'images': 3, 'decode_alpha_source_sha': 'passed', 'zip_crc_and_image_sha': 'passed', 'html_links': 'passed', 'browser_test': 'not_run', 'native_wasm_or_battle_test': 'not_applicable_design_only'}
(DOC / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'output': str(OUT), 'zip': str(archive), 'verification': report}, ensure_ascii=False))
