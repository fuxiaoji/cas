"""Check the actual branch graph, source text and runtime presentation contracts."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/godot/story-longform'
OUT.mkdir(parents=True, exist_ok=True)
failures = []
counts = []
native = {'c1-breakout', 'c1-salvage', 'c1-boss', 'c2-convoy', 'c2-relay', 'c2-warden', 'c3-crossing', 'c3-core', 'c3-breaker'}
for filename in ['chapter-one', 'chapter-two', 'chapter-three']:
    data = json.loads((ROOT / f'godot/data/{filename}.json').read_text('utf-8-sig'))
    nodes = data['scenes']
    by_id = {n['id']: n for n in nodes}
    if len(by_id) != len(nodes): failures.append(f'{filename}: duplicate node')
    for n in nodes:
        if n['kind'] == 'battle' and n.get('native_stage', n['stage']) not in native:
            failures.append(f'{n["id"]}: unknown real native stage')
        targets = list(n.get('choice_next', {}).values()) or ([n['next']] if n.get('next') else [])
        for target in targets:
            if target not in by_id: failures.append(f'{n["id"]}: dangling next {target}')
        for i, row in enumerate(n.get('lines', [])):
            actors = row.get('actors', n.get('actors', []))
            if len(actors) > 3 or any(key not in data['cast'] for key in actors):
                failures.append(f'{n["id"]}:{i}: invalid actor slots')
            if not n.get('cg') and row['speaker'] in data['cast'] and row['speaker'] not in actors:
                failures.append(f'{n["id"]}:{i}: speaker never appears')
            if not row['text'].strip(): failures.append(f'{n["id"]}:{i}: blank text')
        if not (ROOT / f'godot/data/chapter-scenes/{n["id"]}.tres').exists():
            failures.append(f'{n["id"]}: no editable native Resource')
    reached = set()
    def walk(node_id, trail=()):
        if node_id in trail: raise ValueError(f'cycle {trail}: {node_id}')
        reached.add(node_id)
        n = by_id[node_id]
        own = len(re.findall(r'[\u4e00-\u9fff]', ''.join(l['text'] for l in n.get('lines', []))))
        targets = list(n.get('choice_next', {}).values()) or ([n['next']] if n.get('next') else [])
        if not targets or n['kind'] == 'complete': return own, own
        branches = [walk(t, trail+(node_id,)) for t in targets]
        return own + min(v[0] for v in branches), own + max(v[1] for v in branches)
    low, high = walk(data['entry'])
    if set(by_id) != reached: failures.append(f'{filename}: unreachable {set(by_id)-reached}')
    counts.append({'chapter': data['id'], 'nodes': len(nodes), 'pages': sum(len(n.get('lines', [])) for n in nodes),
                   'minimum_route_han': low, 'maximum_route_han': high,
                   'reading_minutes_at_400_han_per_minute': round(low / 400, 2),
                   'total_han_all_branches': sum(len(re.findall(r'[\u4e00-\u9fff]', l['text'])) for n in nodes for l in n.get('lines', [])),
                   'native_missions': len([n for n in nodes if n['kind'] == 'battle']),
                   'expressions': sorted({l['tone'] for n in nodes for l in n.get('lines', [])})})
report = {'failures': failures, 'chapters': counts, 'scope': 'Chinese body text only; mutually exclusive branches excluded from the minimum reading budget'}
(OUT / 'content-audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', 'utf-8')
print(json.dumps(report, ensure_ascii=False))
raise SystemExit(bool(failures))
