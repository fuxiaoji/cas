"""Review the selected final runtime through production Godot code, in isolation.

All GPU windows are offscreen. The user's running game and account are not opened.
Core parity and catalogue browser checks remain separate, independently linked gates.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument('--native', type=Path, required=True)
    parser.add_argument('--godot', type=Path, default=Path(
        'D:/downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'))
    args = parser.parse_args()
    native = args.native.resolve()
    native_sha = sha(native)
    folder = root / 'artifacts/island-war-v3/presentation'
    folder.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ, CAS_SIM_PATH=str(native))
    rows = []

    def run(name, command, receipt=None, timeout=600):
        log = folder / (name + '-final.log')
        with log.open('w', encoding='utf-8') as stream:
            result = subprocess.run(command, cwd=root, env=environment,
                                    stdout=stream, stderr=subprocess.STDOUT,
                                    timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW)
        content = log.read_text('utf-8', errors='replace')
        assert result.returncode == 0, (name, result.returncode, str(log))
        assert not any(line.startswith(('SCRIPT ERROR:', 'ERROR:'))
                       for line in content.splitlines()), (name, str(log))
        row = {'name': name, 'log': str(log.relative_to(root)), 'log_sha256': sha(log)}
        if receipt:
            file = folder / receipt
            data = json.loads(file.read_text('utf-8-sig'))
            assert data['ok'], (name, data)
            row.update(receipt=str(file.relative_to(root)), receipt_sha256=sha(file),
                       checks=data.get('checks'), inputs=data.get('inputs'), scope=data.get('scope'))
        elif name in ['story-regression', 'first-voyage-regression']:
            prefix = 'CANON_SERVICE ' if name == 'story-regression' else 'FIRST_VOYAGE '
            payloads = [json.loads(line[len(prefix):]) for line in content.splitlines() if line.startswith(prefix)]
            assert len(payloads) == 1 and payloads[0]['passed'], (name, payloads)
            row.update(checks=payloads[0]['checks'], scope=payloads[0].get('scope'))
        rows.append(row)
        print(json.dumps({'review': name, 'ok': True, 'checks': row.get('checks')}, ensure_ascii=False), flush=True)

    run('capture', [sys.executable, str(root / 'scripts/capture-tactical-v3-presentation.py'),
                    '--native', str(native)], 'capture-receipt.json')
    assert json.loads((folder / 'capture-receipt.json').read_text('utf-8'))['native_sha256'] == native_sha
    tests = [
        ('vehicle', 'tactical_v3_vehicle_review', 'vehicle-receipt.json', False),
        ('anchor', 'tactical_v3_anchor_review', 'anchor-receipt.json', False),
        ('story', 'tactical_v3_story_review', 'story-receipt.json', True),
        ('battle', 'tactical_v3_battle_review', 'battle-receipt.json', False),
        ('launch', 'tactical_v3_launch_review', 'launch-receipt.json', False),
        ('roles-input', 'tactical_v3_roles_input_review', 'roles-input-receipt.json', False),
        ('combined-input', 'tactical_v3_combined_input_review', 'combined-input-receipt.json', False),
        ('cover', 'tactical_v3_cover_review', 'cover-receipt.json', False),
        ('story-regression', 'canon_story_service_review', None, True),
        ('first-voyage-regression', 'first_voyage_onboarding_review', None, True),
    ]
    for name, script, receipt, headless in tests:
        command = [str(args.godot.resolve()), '--path', str(root / 'godot'),
                   '--script', f'res://tests/{script}.gd']
        command.extend(['--headless'] if headless else ['--position', '-20000,-20000', '--resolution', '1600x900'])
        run(name, command, receipt)
    assert sha(native) == native_sha, 'Selected immutable runtime changed during review'
    report = {'ok': True, 'native': str(native), 'native_sha256': native_sha,
              'reviews': rows, 'scope': 'Final selected runtime, actual native captures and production Godot IPC/story/input/rendering; independent accounts only. GPU windows offscreen. Old-regression exit leak warnings, if present, retained in logs.'}
    (folder / 'integration-review.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
    print(json.dumps({'ok': True, 'native_sha256': native_sha, 'reviews': len(rows)}), flush=True)


if __name__ == '__main__':
    main()
