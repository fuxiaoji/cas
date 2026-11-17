"""Package source-byte-preserved CG from a generation manifest into an offline album."""
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import sys
import zipfile
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    doc = Path(sys.argv[1]).resolve()
    name = doc.name
    data = json.loads((doc / 'generation-input.json').read_text(encoding='utf-8'))
    out = ROOT / 'output' / name
    assets = ROOT / 'godot/assets/tactical/cg' / name
    (out / 'images').mkdir(parents=True, exist_ok=True)
    assets.mkdir(parents=True, exist_ok=True)
    records = []
    figures = []
    for i, job in enumerate(data['jobs']):
        source = Path(job['source'])
        filename = 'MCP-306-' + job['key'] + '.png'
        with Image.open(source) as image:
            image.load()
            assert image.format == 'PNG'
            dimensions = list(image.size)
        for target in [assets / filename, out / 'images' / filename]:
            shutil.copy2(source, target)
            assert sha(source) == sha(target)
        record = dict(key=job['key'], title=job['title'], source=str(source),
                      file='images/' + filename, asset=str(assets / filename),
                      size=dimensions, sha256=sha(source))
        records.append(record)
        title = html.escape(job['title'])
        figures.append(f'<figure><a href="images/{filename}"><img src="images/{filename}" alt="第6步兵团 · {title}"></a><figcaption><h2>{i+1:02d} · {title}</h2><a href="images/{filename}" download>保存原图</a></figcaption></figure>')
    refs = sorted({p for job in data['jobs'] for step in [job]+job.get('revisions', []) for p in step['references']})
    ledger = dict(tool=data['tool'], source_prompt=data['source_prompt'], scope=data['scope'],
                  runtime_binding=False, source_bytes_preserved=True, images=records,
                  reference_sha256={p:sha(p) for p in refs})
    (doc / 'asset-ledger.json').write_text(json.dumps(ledger, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    for filename in ['asset-ledger.json', 'generation-input.json']:
        shutil.copy2(doc / filename, out / filename)
    markup = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>第6步兵团 · CG追加图册</title>
<style>*{box-sizing:border-box}body{margin:0;background:#e8e5dc;color:#273e44;font:17px/1.65 "Microsoft YaHei",sans-serif}header{background:#273e44;color:#faf6e9;padding:30px 5vw}h1{font-size:clamp(25px,4vw,42px);margin:0}header p{margin-bottom:0}main{max-width:1800px;margin:auto;padding:24px;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}figure{margin:0;padding:16px;background:#fffdf7;border-radius:12px;min-width:0}img{width:100%;display:block;border-radius:5px}figcaption{padding:12px 0 0}h2{font-size:21px;margin:0 0 8px}a{color:#347274}footer{max-width:1800px;margin:auto;padding:24px;font-size:14px}@media(max-width:900px){main{padding:12px;grid-template-columns:1fr}figure{padding:12px}}</style>
<header><h1>第6步兵团 · 芷宁</h1><p>追加CG / 近景败局与俯拍战后</p></header><main>''' + ''.join(figures) + '''</main><footer>护士式头巾 · 白手套 · 白色连裤袜 · 轻甲 · 栓动步枪<br>原创架空美术，画面人数为构图目标，未接游戏事件。<br><a href="generation-input.json">完整生成提示</a> · <a href="asset-ledger.json">素材来源与校验</a></footer></html>'''
    (out / 'index.html').write_text(markup, encoding='utf-8')
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 23)
    sheet = Image.new('RGB', (1440, 940), '#e8e5dc')
    draw = ImageDraw.Draw(sheet)
    for i, record in enumerate(records):
        x, y = (i % 2) * 720, (i // 2) * 470
        with Image.open(record['source']) as source:
            thumb = ImageOps.contain(source.convert('RGB'), (700, 395))
        sheet.paste(thumb, (x+10, y+50))
        draw.text((x+10, y+10), f'{i+1:02d} · {record["title"]}', font=font, fill='#273e44')
    sheet.save(out / 'overview.jpg', quality=93)
    assert all((out / p).is_file() for p in re.findall(r'(?:href|src)="([^"]+)"', markup))
    archive = out.with_suffix('.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(out.rglob('*')):
            if path.is_file():
                z.write(path, path.relative_to(out.parent))
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for record in records:
            assert hashlib.sha256(z.read(name+'/'+record['file'])).hexdigest() == record['sha256']
    verification = dict(image_decode=True, source_copy_hashes=True, html_links=True,
                        zip_crc=True, zip_image_hashes=True, browser_test=False,
                        count=len(records), dimensions=[r['size'] for r in records])
    (doc / 'verification.json').write_text(json.dumps(verification, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(dict(album=str(out / 'index.html'), archive=str(archive), verification=verification), ensure_ascii=False))

if __name__ == '__main__':
    main()
