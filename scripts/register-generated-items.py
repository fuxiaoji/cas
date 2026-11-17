"""Copy reviewed, original inventory illustrations and retain generation provenance."""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'godot/assets/items'
TARGET.mkdir(parents=True, exist_ok=True)
assets = []
for entry in json.loads((ROOT / 'tools/generated-items-v1.json').read_text(encoding='utf-8')):
    assert entry['id'] in {'scrap', 'alloy', 'equipment', 'command'}
    source = Path(entry['generated_file']).resolve(strict=True)
    target = TARGET / (entry['id'] + '.png')
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() != digest:
        raise ValueError('Refusing to overwrite a different inventory illustration')
    with Image.open(source) as im:
        assert im.mode == 'RGBA' and im.getchannel('A').getextrema() == (0, 255)
        dimensions = list(im.size)
    shutil.copy2(source, target)
    assets.append(dict(entry, path='res://assets/items/' + target.name, sha256=digest, dimensions=dimensions,
        generator='built-in imagegen', appearance_review='agent_visual_checked', original=True, pixels_modified=False))
(TARGET / 'ledger.json').write_text(json.dumps({'version':1, 'purpose':'Single-player salvage inventory and cargo', 'assets':assets}, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(json.dumps({'items':len(assets), 'transparent':True, 'hashes_verified':True}))
