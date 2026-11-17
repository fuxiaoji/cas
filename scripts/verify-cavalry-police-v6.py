"""Verify untouched generated portrait revisions and retain provenance."""
import hashlib
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
docs = root / 'docs/art/cavalry-police-choices-v6-20261116'
out = root / 'output/cavalry-police-choices-v6-20261116'
inputs = json.loads((docs / 'generation-input.json').read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

records = []
for job in inputs['jobs']:
    source = json.loads((docs / (job['id'] + '-source.json')).read_text(encoding='utf-8-sig'))
    target = Path(source['output'])
    assert sha(target) == sha(source['source']), 'Generated source bytes changed'
    with Image.open(target) as im:
        im.load()
        assert im.mode == 'RGBA'
        alpha = im.getchannel('A').getextrema()
        assert alpha[0] == 0 and alpha[1] > 0
        record = dict(source, sha256=sha(target), size=list(im.size), mode=im.mode,
                      alpha=list(alpha), source_bytes_preserved=True)
    record['references'] = [{'path': p, 'sha256': sha(p)} for p in job['refs']]
    records.append(record)
ledger = {'status': 'art_revisions_for_review', 'generator': 'built-in image_gen',
          'assets': records, 'runtime_changed': False}
data = json.dumps(ledger, ensure_ascii=False, indent=2)
(docs / 'asset-ledger.json').write_text(data, encoding='utf-8')
(out / 'asset-ledger.json').write_text(data, encoding='utf-8')
(out / 'generation-input.json').write_bytes((docs / 'generation-input.json').read_bytes())
print(json.dumps({'verified': len(records), 'source_bytes_preserved': True,
                  'alpha': [r['alpha'] for r in records]}, ensure_ascii=False))
