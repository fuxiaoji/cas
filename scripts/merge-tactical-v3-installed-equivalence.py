"""Join independently completed raw equality gates for the same immutable binaries."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / 'artifacts/island-war-v3/final-installed'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    files = [FOLDER / name for name in ['base-equivalence.json', 'new-v3-equivalence.json']]
    base, new = [json.loads(path.read_text('utf-8')) for path in files]
    assert base['passed'] and new['passed']
    assert base['part'] == 'base' and new['part'] == 'new-v3'
    for field in ['candidate_sha256', 'installed_sha256']:
        assert base[field] == new[field], field
    for field in ['candidate', 'installed']:
        assert sha(ROOT / base[field]) == base[field + '_sha256'], field
    expected = {str(path.relative_to(ROOT)) for path in
                (ROOT / 'artifacts/island-war-v3/parity/new-mode').glob('*-commands.json')}
    assert expected and expected == {row['source'] for row in new['cases']}
    assert all(row['category'] == 'new_v3' for row in new['cases'])
    assert all(row['category'] != 'new_v3' for row in base['cases'])
    assert len([row for row in base['cases'] if row['category'] == 'v3_completed_course']) == 6
    rows = base['cases'] + new['cases']
    assert all(row['raw_identical'] for row in rows)
    assert len({(row['category'], row['source']) for row in rows}) == len(rows)
    result = {**base, 'part': 'all', 'cases': rows,
              'requests': sum(row['requests'] for row in rows),
              'bytes': sum(row['bytes'] for row in rows),
              'parts': [{'path': str(path.relative_to(ROOT)), 'sha256': sha(path)} for path in files]}
    (FOLDER / 'equivalence.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), 'utf-8')
    print(json.dumps({'passed': True, 'cases': len(rows), 'requests': result['requests'],
                      'bytes': result['bytes'], 'installed_sha256': result['installed_sha256']}))


if __name__ == '__main__':
    main()
