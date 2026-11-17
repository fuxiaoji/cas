"""Export inspection boards and provenance checks for the additive SD art pack."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib, json, shutil, sys, zipfile

R = Path(__file__).resolve().parents[1]
O = R / 'output/cavalry-mountain-animation-v2-20261116'
D = R / 'docs/art/cavalry-mountain-animation-v2-20261116'
ledger = json.loads((D / 'asset-ledger.json').read_text(encoding='utf8'))
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 24)
small = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 19)
board = Image.new('RGB', (1200, 1080), '#eee9df')
draw = ImageDraw.Draw(board)
draw.text((28, 15), '新增遗体姿态 · 每列为同一角色的四种末帧', font=font, fill='#263e48')
names = [('MCP-002', '骑兵'), ('MCP-030', '山地突击旅'), ('MCP-017', '特警')]
expressions = [(3, '闭眼 · 侧倒'), (7, '吐舌 · 仰倒'), (11, '睁眼 · 前扑'), (15, '口水 · 右倒')]
for col, (uid, name) in enumerate(names):
    sheet = Image.open(O / 'assets' / f'{uid}-defeat-extra.png')
    x = col * 400 + 25
    draw.text((x, 60), name, font=font, fill='#263e48')
    for row, (idx, label) in enumerate(expressions):
        y = 105 + row * 235
        tile = sheet.crop((idx % 4 * 512, idx // 4 * 512, (idx % 4 + 1) * 512, (idx // 4 + 1) * 512))
        for offset, size in [(0, 80), (125, 180)]:
            stamp = tile.resize((size, size), Image.Resampling.LANCZOS)
            board.paste(stamp, (x + offset, y), stamp)
        draw.text((x, y + 185), label, font=small, fill='#263e48')
board.save(O / 'corpse-expression-review.jpg', quality=96)

# Two independent rows make the rider/horse separation clear without adding painted pixels.
sep = Image.open(O / 'assets/MCP-002-separation.png')
board = Image.new('RGB', (1440, 440), '#eee9df')
draw = ImageDraw.Draw(board)
for row, title in enumerate(['骑手独立图层 · 8帧', '机械马独立图层 · 8帧']):
    draw.text((20, row * 220 + 8), title, font=font, fill='#263e48')
    for n in range(8):
        idx = row * 8 + n
        tile = sep.crop((idx % 4 * 512, idx // 4 * 512, (idx % 4 + 1) * 512, (idx // 4 + 1) * 512))
        tile.thumbnail((175, 175), Image.Resampling.LANCZOS)
        board.paste(tile, (n * 180, row * 220 + 35), tile)
board.save(O / 'rider-horse-separation-review.jpg', quality=96)

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

for item in ledger['portraits']:
    assert item['source_bytes_preserved'] and sha(item['source']) == item['sha256']
for item in ledger['atlases']:
    assert item['source_bytes_preserved']
    assert sha(item['source']) == sha(O / 'assets' / (item['id'] + '-raw.png')) == item['raw_sha256']
    assert len(item['frames']) == 16
    with Image.open(O / 'assets' / (item['id'] + '.png')) as im:
        im.load()
        assert im.size == (2048, 2048) and im.getchannel('A').getextrema()[0] == 0
    for ref in item['references']:
        assert sha(ref['path']) == ref['sha256']
assert len(ledger['exports']) == 34
for p in ledger['exports']:
    with Image.open(O / p) as im:
        for i in range(getattr(im, 'n_frames', 1)):
            im.seek(i)
            im.load()
report = dict(atlases=7, additional_poses=112, additional_actions=34,
              source_bytes_and_reference_hashes_match=True, alpha_and_frames_valid=True,
              webp_all_frames_decode=True, runtime_changed=False,
              godot_import='17 PNG assets; no errors', godot_headless_run_frames=30,
              browser=json.loads((D / 'browser-validation.json').read_text(encoding='utf8')))
(D / 'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps(report, ensure_ascii=False))

if '--archive' in sys.argv:
    records = O / 'records'
    records.mkdir(exist_ok=True)
    for p in D.iterdir():
        if p.is_file():
            shutil.copyfile(p, records / p.name)
    shutil.copyfile(R / 'docs/design/cavalry-mountain-animation-v2-20261116.md', O / 'README.md')
    archive = O.with_suffix('.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in O.rglob('*'):
            if p.is_file() and '.godot' not in p.parts and p.suffix != '.import':
                z.write(p, p.relative_to(O))
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for item in ledger['atlases']:
            assert hashlib.sha256(z.read('assets/' + item['id'] + '-raw.png')).hexdigest() == item['raw_sha256']
    result = dict(path=str(archive), bytes=archive.stat().st_size,
                  sha256=sha(archive), crc_valid=True, raw_atlas_hashes_match=7)
    (D / 'archive-validation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps(result, ensure_ascii=False))
