"""Preserve generated CG bytes, package a small offline gallery, and verify it."""
from pathlib import Path
import hashlib
import json
import shutil
import sys
import zipfile
from PIL import Image, ImageOps, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
NAME = 'sixth-infantry-defeat-cg-20261115'
DOC = ROOT / 'docs/art' / NAME
OUT = ROOT / 'output' / NAME
ASSETS = ROOT / 'godot/assets/tactical/cg/sixth-infantry-20261115'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    corrected = Path(sys.argv[1]).resolve()
    generation = json.loads((DOC / 'generation-input.json').read_text(encoding='utf-8'))
    generation['edits'][0]['source'] = corrected.as_posix()
    for item in generation['generations']:
        item['prompt'] = item['prompt'].replace('[IDENTITY]', generation['identity_prompt'])
    generation.pop('prompt_assembly', None)
    for parent in [OUT / 'images', ASSETS]:
        parent.mkdir(parents=True, exist_ok=True)
    sources = {'battle': Path(generation['generations'][0]['source']), 'cleanup': corrected}
    records = []
    for kind, source in sources.items():
        filename = f'MCP-306-{kind}.png'
        with Image.open(source) as im:
            im.load()
            assert im.format == 'PNG'
            width, height = im.size
        targets = [ASSETS / filename, OUT / 'images' / filename]
        for target in targets:
            shutil.copy2(source, target)
            assert sha(source) == sha(target)
        records.append(dict(kind=kind, source=source.as_posix(), sha256=sha(source),
                            width=width, height=height, asset=targets[0].as_posix(),
                            gallery=targets[1].as_posix()))
    ref_paths = sorted({p for item in generation['generations'] + generation['edits'] for p in item['references']})
    references = [dict(path=p, sha256=sha(p)) for p in ref_paths]
    manifest = dict(identity=generation['identity'], tool=generation['tool'], images=records,
                    references=references, scope=generation['scope'],
                    visual_review='护士头巾、棕外套、白色连裤袜、栓动步枪、普通登陆艇；战后色彩纠正保留原构图。数量为美术目标，未作逐人精确伤亡断言。')
    (DOC / 'generation-input.json').write_text(json.dumps(generation, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (DOC / 'artifact-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for name in ['generation-input.json', 'artifact-manifest.json']:
        shutil.copy2(DOC / name, OUT / name)
    html = '''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>第6步兵团 · 芷宁 · 战败CG</title>
<style>*{box-sizing:border-box}body{margin:0;background:#e8e5dc;color:#273e44;font:17px/1.65 "Microsoft YaHei",sans-serif}header{background:#273e44;color:#faf6e9;padding:32px 5vw}h1{font-size:clamp(25px,4vw,42px);margin:0}header p{margin-bottom:0}main{max-width:1800px;margin:auto;padding:24px}.pair{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}figure{margin:0;padding:16px;background:#fffdf7;border-radius:12px;min-width:0}img{width:100%;display:block;border-radius:5px}figcaption{padding:12px 0 0}h2{font-size:21px;margin:0 0 8px}a{color:#347274}footer{max-width:1800px;margin:auto;padding:24px;font-size:14px}@media(max-width:900px){main{padding:12px}.pair{grid-template-columns:1fr}figure{padding:12px}}</style>
<header><h1>第6步兵团 · 芷宁</h1><p>滩头败局 / 战后清理</p></header>
<main class="pair"><figure><a href="images/MCP-306-battle.png"><img src="images/MCP-306-battle.png" alt="第6步兵团芷宁 · 抢滩进攻失败"></a><figcaption><h2>01 · 抢滩败局</h2>岸防火力下的最后抵抗。<br><a download href="images/MCP-306-battle.png">保存原图</a></figcaption></figure>
<figure><a href="images/MCP-306-cleanup.png"><img src="images/MCP-306-cleanup.png" alt="第6步兵团芷宁 · 战后清理"></a><figcaption><h2>02 · 战后清理</h2>战后回收与物资整理。<br><a download href="images/MCP-306-cleanup.png">保存原图</a></figcaption></figure></main>
<footer>护士式头巾 · 格围巾 · 白手套 · 白色连裤袜 · 轻甲 · 栓动步枪<br>原创架空美术，非真实战报；画面人数为构图目标，未接游戏事件。<br><a href="generation-input.json">完整生成提示与参考</a> · <a href="artifact-manifest.json">素材来源与校验记录</a></footer></html>'''
    (OUT / 'index.html').write_text(html, encoding='utf-8')
    # Preview/contact sheet only; all original PNG assets above remain byte-identical.
    sheet = Image.new('RGB', (1440, 470), '#e8e5dc')
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 23)
    for index, record in enumerate(records):
        with Image.open(record['source']) as im:
            thumb = ImageOps.contain(im.convert('RGB'), (700, 395))
        sheet.paste(thumb, (10 + index * 720, 50))
        draw.text((10 + index * 720, 10), ['芷宁 · 抢滩败局', '芷宁 · 战后清理'][index], font=font, fill='#273e44')
    sheet.save(OUT / 'overview.jpg', quality=93)
    archive = OUT.with_suffix('.zip')
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for path in sorted(OUT.rglob('*')):
            if path.is_file():
                z.write(path, path.relative_to(OUT.parent))
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for record in records:
            relative = Path(record['gallery']).relative_to(OUT.parent).as_posix()
            assert hashlib.sha256(z.read(relative)).hexdigest() == record['sha256']
    import re
    links = re.findall(r'(?:src|href)="([^"]+)"', html)
    assert all((OUT / link).is_file() for link in links)
    report = dict(images=records, image_decode=True, copies_match_source=True, html_links=True,
                  zip_crc=True, zip_images_match=True, browser_test=False)
    (DOC / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(gallery=str(OUT / 'index.html'), archive=str(archive), images=records), ensure_ascii=False))

if __name__ == '__main__':
    main()
