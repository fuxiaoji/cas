"""Read-only final candidate/normal-launch comparison, every public JSON reply.

No source/binary/manifest/account mutation. Both arguments must support v3.
Run after CAS-Godot.cmd --check has produced the actual normal-launch runtime.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--installed', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=root / 'artifacts/island-war-v3/final-installed/equivalence.json')
    parser.add_argument('--part', choices=['all', 'base', 'new-v3'], default='all',
                        help='Split independent frozen legacy/course and new-v3 gates without repeating large traces.')
    args = parser.parse_args()
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    groups = [
        ('new_v3', root / 'artifacts/island-war-v3/parity/new-mode', '*-commands.json'),
        ('new_v2', root / 'artifacts/island-war-v2/parity/new-mode', '*-commands.json'),
        ('old_island_v1', root / 'artifacts/island-war-v1/parity/new-mode', '*-commands.json'),
        ('combined', root / 'artifacts/island-war-v1/parity/combined-legacy', '*-commands.json'),
        ('story_modern', root / 'artifacts/story-modernization-v3', 'c*-commands.json'),
        ('littoral_v1', root / 'artifacts/littoral-core', '*-commands.json'),
        ('littoral_v2', root / 'artifacts/littoral-v2', 'v2-*-commands.json'),
        ('littoral_v3', root / 'artifacts/littoral-v3', 'v3-*-commands.json'),
        ('littoral_v4', root / 'artifacts/littoral-v4', 'v4-*-commands.json'),
        ('multi_v4', root / 'artifacts/littoral-v4/multi', 'v4-*-commands.json'),
    ]
    cases = []
    for category, folder, pattern in groups:
        if args.part == 'base' and category == 'new_v3' or args.part == 'new-v3' and category != 'new_v3':
            continue
        for file in sorted(folder.glob(pattern)):
            cases.append((category, str(file.relative_to(root)), json.loads(file.read_text('utf-8-sig'))))
    for name in ['native-wasm-calls.jsonl', 'carrier-wasm-calls.jsonl', 'multicompany-wasm-calls.jsonl']:
        if args.part == 'new-v3':
            continue
        file = root / 'artifacts/amphibious-expedition' / name
        cases.append(('amphibious', str(file.relative_to(root)), [json.loads(s) for s in file.read_text('utf-8-sig').splitlines() if s.strip()]))
    for file in sorted((root / 'artifacts/godot/story-longform').glob('*-terminal.json')):
        if args.part == 'new-v3':
            continue
        cases.append(('original18', str(file.relative_to(root)), [{'op': 'load', 'serialized': file.read_text('utf-8-sig')}, {'op': 'observe'}, {'op': 'save', 'serialized': True}]))
    # Mid-flight parity fixtures alone do not prove that the installed runtime
    # supports all configured courses and their actual recovery terminals.
    courses = json.loads((root / 'godot/data/tactical-training-v3.json').read_text('utf-8-sig'))['lessons']
    for lesson in courses:
        if args.part == 'new-v3':
            continue
        file = root / f'artifacts/island-war-v3/core/training-{lesson}-terminal.json'
        fixture = json.loads(file.read_text('utf-8-sig'))
        assert fixture['final']['result']['success'], lesson
        assert fixture['final']['littoral']['training']['complete'], lesson
        commands = fixture['commands']
        assert commands[0] == fixture['initial_request'], lesson
        commands = commands + [{'op': 'load', 'serialized': fixture['serialized']},
                               {'op': 'observe'}, {'op': 'save', 'serialized': True}]
        cases.append(('v3_completed_course', str(file.relative_to(root)), commands))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    for category, source, commands in cases:
        processes = [subprocess.Popen([str(p.resolve())], stdin=subprocess.PIPE, stdout=subprocess.PIPE) for p in (args.candidate, args.installed)]
        total = 0
        h = hashlib.sha256()
        try:
            for i, command in enumerate(commands):
                wire = (json.dumps(command, ensure_ascii=False, separators=(',', ':')) + '\n').encode('utf-8')
                replies = []
                for process in processes:
                    process.stdin.write(wire)
                    process.stdin.flush()
                    replies.append(process.stdout.readline())
                if not replies[0] or replies[0] != replies[1]:
                    for label, raw in zip(['candidate', 'installed'], replies):
                        (args.output.parent / ('mismatch-' + label + '.json')).write_bytes(raw)
                    raise AssertionError((category, source, i, command.get('op')))
                total += len(replies[0])
                h.update(replies[0])
        finally:
            for process in processes:
                process.stdin.close()
                process.wait(timeout=30)
        rows.append({'category': category, 'source': source, 'requests': len(commands), 'bytes': total, 'response_sha256': h.hexdigest(), 'raw_identical': True})
    receipt = {'passed': True, 'part': args.part, 'candidate': str(args.candidate), 'candidate_sha256': digest(args.candidate), 'installed': str(args.installed), 'installed_sha256': digest(args.installed), 'cases': rows, 'requests': sum(r['requests'] for r in rows), 'bytes': sum(r['bytes'] for r in rows), 'scope': 'Every response, including rejected commands, finite effects, saves, load, replay and terminals; equality is established for listed fixtures, not proof of binary identity. No account/manifest/runtime mutated.'}
    args.output.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), 'utf-8')
    print(json.dumps({'passed': True, 'cases': len(rows), 'requests': receipt['requests'], 'bytes': receipt['bytes'], 'output': str(args.output)}))


if __name__ == '__main__':
    main()
