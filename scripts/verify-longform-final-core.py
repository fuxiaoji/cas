"""Freeze the 18 real chapter terminals across the final pilot-only update."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'godot/bin/core-current.json').read_text('utf-8-sig'))
current = root / 'godot/bin' / manifest['executable']
previous = root / 'godot/bin/runtime/be12309e0b9d2fd2/cas-sim.exe'
folder = root / 'artifacts/godot/story-longform'
rows = []
for path in sorted(folder.glob('*-terminal.json')):
    commands = [
        {'op': 'load', 'serialized': path.read_text('utf-8-sig')},
        {'op': 'observe'},
        {'op': 'save', 'serialized': True},
    ]
    request = ('\n'.join(json.dumps(q, ensure_ascii=False) for q in commands) + '\n').encode()
    replies = []
    for binary in [previous, current]:
        process = subprocess.run([str(binary)], input=request, capture_output=True, check=True, timeout=60)
        for line in process.stdout.splitlines():
            assert json.loads(line)['ok'], (path.name, line[:200])
        replies.append(process.stdout)
    assert replies[0] == replies[1], path.name
    rows.append({'stage': path.stem.removesuffix('-terminal'), 'requests': 3,
                 'bytes': len(replies[0]), 'sha256': hashlib.sha256(replies[0]).hexdigest(),
                 'exact': True})
assert len(rows) == 18, len(rows)
report = {'passed': 18, 'requests': 54, 'previous': str(previous), 'current': str(current),
          'current_sha256': manifest['sha256'], 'rows': rows,
          'scope': 'Real GPU playthrough terminal snapshots; load/observe/save bytes equal across final extraction-pilot-only change'}
(folder / 'final-core-freeze.json').write_text(json.dumps(report, indent=2), 'utf-8')
print(json.dumps({'passed': 18, 'requests': 54, 'bytes': sum(row['bytes'] for row in rows)}))
