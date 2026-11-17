from pathlib import Path
from PIL import Image
from html import escape
from html.parser import HTMLParser
import hashlib
import json
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NAME = 'cavalry-selected-rifle-cg-v7-20261116'
DOC = ROOT / 'docs/art' / NAME
OUT = ROOT / 'output' / NAME
ASSET = ROOT / 'godot/assets/tactical' / NAME
for folder in (OUT / 'images', ASSET / 'portraits', ASSET / 'cg', DOC / 'references'):
    folder.mkdir(parents=True, exist_ok=True)
data = json.loads((DOC / 'final-generation-input.json').read_text(encoding='utf8'))

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def copy_original(src, dst):
    src, dst = Path(src), Path(dst)
    if dst.exists():
        assert sha(src) == sha(dst), f'Existing different asset: {dst}'
    else:
        shutil.copyfile(src, dst)
    assert sha(src) == sha(dst)

ledger = []
for job in data['jobs']:
    prefix = 'MCP-002-' if job['kind'] == 'portrait' else 'CG-'
    filename = prefix + job['id'] + '.png'
    dst = OUT / 'images' / filename
    asset = ASSET / ('portraits' if job['kind'] == 'portrait' else 'cg') / filename
    copy_original(job['source'], dst)
    copy_original(job['source'], asset)
    with Image.open(dst) as im:
        im.load()
        assert im.format == 'PNG'
        size, mode = im.size, im.mode
        alpha = im.getchannel('A').getextrema() if mode == 'RGBA' else None
        if job['kind'] == 'portrait':
            assert mode == 'RGBA' and alpha[0] < 5 and alpha[1] > 200
    refs = []
    for i, path in enumerate(job['referenced_image_paths']):
        ref = Path(path)
        saved = DOC / 'references' / (job['id'] + '-' + str(i + 1) + ref.suffix)
        copy_original(ref, saved)
        refs.append({'actual_input': str(ref), 'preserved_copy': str(saved), 'sha256': sha(ref)})
    ledger.append({'id': job['id'], 'title': job['title'], 'kind': job['kind'],
                   'source': job['source'], 'output': str(dst), 'project_asset': str(asset),
                   'file': 'images/' + filename, 'size': size, 'mode': mode,
                   'alpha_range': alpha, 'sha256': sha(dst), 'source_bytes_preserved': True,
                   'references': refs, 'runtime_changed': False})

for run in data['source_runs']:
    run['sha256'] = sha(run['source'])
    if not run['selected']:
        candidate = DOC / 'candidates' / (run['key'] + '.png')
        candidate.parent.mkdir(parents=True, exist_ok=True)
        copy_original(run['source'], candidate)
        run['preserved_candidate'] = str(candidate)
(DOC / 'source-runs.json').write_text(json.dumps(data['source_runs'], ensure_ascii=False, indent=2), encoding='utf8')
(DOC / 'asset-ledger.json').write_text(json.dumps(ledger, ensure_ascii=False, indent=2), encoding='utf8')
for file in DOC.glob('*.json'):
    shutil.copyfile(file, OUT / file.name)

readme = '''骑兵背步枪立绘与战败CG · 2026-11-16

共8张原始PNG：
1. 骑马、站立背步枪立绘各一张，以用户本轮选图为准保留开口裙和原裙长。
2. 滩头、阵地、城市三张近距俯视冲锋惨败CG，按后续反馈拉近人物、增强面部可读性。
3. 全灭后敌方护士清场CG，分类回收外套、披风和空靴，人员仍完整穿着不透明内层衣物。
4. 追加战壕内与小镇伏击两张低角度特写；小镇画面可见两侧敌军开火。

index.html可直接浏览，点击图片打开原图，每图另有下载链接。
均由内置image_gen生成/编辑，原始PNG字节与生成透明通道不重绘。
完整实际提示见final-generation-input.json及各阶段input/revision文件；来源与哈希见asset-ledger.json。
远景、低位步枪初稿及镜头修订来源仅作为生成链登记，不混入最终8图。
镜头角度、人数和表情是绘画目标而非精确相机标定或逐人统计。
画面有浅伤、衣装破损和少量血迹，无肢解或深创。
仅本轮独立美术资源；未绑定游戏战败触发、实际伤亡统计或战利品库存，未覆盖旧立绘/SD/CG或运行目录。
'''
(OUT / 'README.txt').write_text(readme, encoding='utf8')
(DOC / 'README.txt').write_text(readme, encoding='utf8')

def card(item):
    title, file = escape(item['title']), escape(item['file'])
    width, height = item['size']
    return f'<article><a class="art" href="{file}" target="_blank" rel="noopener"><img src="{file}" alt="{title}" width="{width}" height="{height}" loading="lazy"></a><div class="caption"><h3>{title}</h3><a class="download" href="{file}" download>下载原图 ↓</a></div></article>'

sections = [('low-cg', 'low', '低角度特写'), ('close-cg', 'close', '近距俯视'), ('portrait', 'portraits', '背步枪立绘')]
content = ''.join(f'<section id="{anchor}"><h2>{title}</h2><div class="grid {kind}">' + ''.join(card(x) for x in ledger if x['kind'] == kind) + '</div></section>' for kind, anchor, title in sections)
page = '''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>骑兵 · 战地镜头</title><style>
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f1eee6;color:#243b39;font:16px/1.6 "Microsoft YaHei",sans-serif}header,main,footer{max-width:1560px;margin:auto;padding:28px 24px}header{border-bottom:1px solid #cfcbc0}header p{color:#63706a;margin:8px 0}h1{font-size:clamp(28px,4vw,46px);font-weight:600;letter-spacing:.05em;margin:0}nav{display:flex;flex-wrap:wrap;gap:12px;margin-top:18px}nav a,.download{color:#196b66;text-decoration:none;border-bottom:1px solid #87aaa0}nav a{padding:5px 0}section{scroll-margin-top:20px;margin-bottom:48px}h2{font-size:22px;font-weight:500;border-left:4px solid #b79752;padding-left:12px;margin:8px 0 20px}.grid{display:grid;gap:24px}.portrait{grid-template-columns:1fr 1fr}article{background:#fffdf7;border:1px solid #dad5c9;border-radius:9px;overflow:hidden}.art{display:block;background:#263431}img{display:block;width:100%;height:auto}.portrait img{max-height:860px;object-fit:contain}.caption{padding:12px 18px;display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}h3{font-size:17px;font-weight:500;margin:0}.download{font-size:14px;white-space:nowrap}footer{font-size:13px;color:#68746e;padding-top:0}a:focus-visible{outline:3px solid #bd9950;outline-offset:4px}@media(max-width:650px){header,main,footer{padding-left:14px;padding-right:14px}.portrait{grid-template-columns:1fr}.caption{padding:10px 12px}.grid{gap:18px}}
</style></head><body><header><h1>骑兵 · 战地镜头</h1><p>两版背枪立绘 · 六幅战地CG</p><nav><a href="#low">低角度特写</a><a href="#close">近距俯视</a><a href="#portraits">背步枪立绘</a></nav></header><main>''' + content + '</main><footer>点击画面查看完整原图。</footer></body></html>'
(OUT / 'index.html').write_text(page, encoding='utf8')

class Links(HTMLParser):
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ('href', 'src') and value and not value.startswith('#'):
                assert (OUT / value).is_file(), value
Links().feed(page)
assert len(ledger) == 8
archive = ROOT / 'output' / (NAME + '.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for file in sorted(OUT.rglob('*')):
        if file.is_file():
            z.write(file, file.relative_to(OUT))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for item in ledger:
        assert hashlib.sha256(z.read(item['file'])).hexdigest() == item['sha256']
report = {'final_images': len(ledger), 'original_bytes_and_project_copies': 'pass',
          'png_decode_and_portrait_alpha': 'pass', 'static_gallery_links': 'pass',
          'zip_crc_and_png_sha256': 'pass', 'browser_review': 'not_performed_static_gallery',
          'archive_bytes': archive.stat().st_size, 'generator': 'built-in image_gen',
          'gallery': str(OUT / 'index.html'), 'zip': str(archive),
          'images': [{'id': x['id'], 'size': x['size'], 'alpha': x['alpha_range']} for x in ledger]}
(DOC / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps(report, ensure_ascii=True))
