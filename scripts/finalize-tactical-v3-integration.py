"""Link independently verified final runtime, UI, catalogue and preserved accounts."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(name):
    return json.loads((ROOT / name).read_text('utf-8-sig'))


def reference(name):
    path = ROOT / name
    return {'path': str(path.relative_to(ROOT)), 'sha256': digest(path)}


def main():
    core = read('artifacts/island-war-v3/core-verification-index.json')
    assert core['status'] == 'core_frozen'
    for item in core['source_freeze']:
        assert digest(ROOT / item['path']) == item['sha256'], item['path']
    for kind in ['native', 'wasm']:
        assert digest(ROOT / core[kind]['path']) == core[kind]['sha256'], kind
    manifest = read('godot/bin/core-current.json')
    installed = ROOT / 'godot/bin' / manifest['executable']
    assert digest(installed) == manifest['sha256']
    parity = read('artifacts/island-war-v3/final-installed/equivalence.json')
    assert parity['passed']
    assert parity['candidate_sha256'] == core['native']['sha256']
    assert parity['installed_sha256'] == manifest['sha256']
    for part in parity.get('parts', []):
        assert digest(ROOT / part['path']) == part['sha256'], part['path']
    course_count = len(read('godot/data/tactical-training-v3.json')['lessons'])
    assert len([row for row in parity['cases'] if row['category'] == 'v3_completed_course']) == course_count
    review = read('artifacts/island-war-v3/presentation/integration-review.json')
    assert review['ok'] and review['native_sha256'] == manifest['sha256']
    for item in review['reviews']:
        for field in ['log', 'receipt']:
            if field in item:
                assert digest(ROOT / item[field]) == item[field + '_sha256']
    home = read('artifacts/island-war-v3/home/receipt-ui.json')
    legacy = read('artifacts/island-war-v3/home/legacy-224-receipt.json')
    for item in [home, legacy]:
        assert not item['failures']
        assert item['core_sha256'] in [manifest['sha256'], core['native']['sha256']]
    codex = read('artifacts/island-war-v3/codex/receipt.json')
    assert not codex['failures'] and not codex['page_errors'] and not codex['network_requests']
    source_sha = digest(ROOT / 'godot/data/island-war-v3.json')
    catalogue = read('godot/data/island-war-v3.json')
    design = read('docs/design/tactical-v3-weapon-models.json')
    models = {row['id']: row for row in catalogue['weapons']}
    assert len(models) == len(design['models']) and len(models) > 22
    assert len(catalogue['cards']) == 22
    assert {row['id'] for row in catalogue['weapon_families']} == {row['family_id'] for row in design['models']}
    fields = ['name', 'family_id', 'damage', 'range_m', 'ammo_capacity', 'fire_mode',
              'fire_interval_s', 'burst_size', 'burst_interval_s',
              'magazine_capacity', 'magazine_reload_s']
    owners = {}
    for row in design['models']:
        actual = models[row['id']]
        assert all(actual[field] == row[field] for field in fields), row['id']
        owners[row['id']] = row['unit_id']
    for card in catalogue['cards']:
        for body in card['weapon_composition']:
            assert owners[body['weapon_id']] == card['id']
            assert models[body['weapon_id']]['family_id'] == body['weapon_family_id']
            if body.get('secondary_weapon_id'):
                assert owners[body['secondary_weapon_id']] == card['id']
    assert codex['source_sha256'] == source_sha
    assert digest(ROOT / 'output/tactical-codex-v3-20261115/baseline-native.json') == source_sha
    assert codex['accuracy_model']['maxError'] == 0
    assets = read('artifacts/tactical-vehicles-v3-20261115/verification.json')
    assert assets['failed'] == 0
    # The earlier frame/PNG review covered category art. Model bindings are a
    # distinct receipt and must match the final live catalogue, not that review.
    bindings = read('artifacts/tactical-vehicles-v3-20261115/weapon-model-bindings.json')
    assert bindings['pass'] and bindings['core_sha256'] in [manifest['sha256'], core['native']['sha256']]
    assert bindings['native_catalogue_sha256'] == source_sha
    assert bindings['manifest_sha256'] == digest(ROOT / bindings['manifest'])
    assert set(bindings['bindings']) == set(models)
    ledger = read('docs/art/tactical-vehicles-v3-20261115/ledger.json')
    preserved_pngs = []
    for asset in ledger['assets']:
        path = ROOT / 'godot' / asset['production'].removeprefix('res://')
        assert digest(path) == asset['production_sha256'] == asset['source_sha256'], asset['kind']
        preserved_pngs.append(reference(str(path.relative_to(ROOT))))
    vehicle = read('artifacts/island-war-v3/presentation/vehicle-receipt.json')
    assert vehicle['ok'] and not vehicle['failures']
    anchors = read('artifacts/island-war-v3/presentation/anchor-receipt.json')
    assert anchors['ok'] and not anchors['failures'] and anchors['frames'] == 280
    cover = read('artifacts/island-war-v3/presentation/cover-receipt.json')
    assert cover['ok'] and not cover['failures']
    assert any(item['name'] == 'cover' for item in review['reviews'])
    formal = []
    location = Path(os.environ['APPDATA']) / 'Godot/app_userdata/CAS · 归航'
    expected = {'cas_port_v1.json': '3958563182f3b6ebd7a97dd5dda3ea7cfe2a1efc02b4ced761d70d8a74f6c8fa',
                'cas_port_v1.json.bak': 'a46f932f40ec08ba7ce94bb4ddb91311998e57773f3db8dd61d7738ccf5ab1fc'}
    for name, original in expected.items():
        path = location / name
        assert digest(path) == original, name
        data = json.loads(path.read_text('utf-8-sig'))
        assert isinstance(data.get('owned'), dict) and isinstance(data.get('wallet'), dict)
        formal.append({'path': str(path), 'sha256': original, 'valid_json': True,
                       'bytes': path.stat().st_size, 'unchanged': True})
    for name in ['artifacts/island-war-v3/normal-launch-check.log', 'artifacts/godot-launch-import.log']:
        lines = (ROOT / name).read_text('utf-8-sig', errors='replace').splitlines()
        assert not any(line.startswith(('SCRIPT ERROR:', 'ERROR:')) for line in lines), name
    paths = [
        'artifacts/island-war-v3/core-verification-index.json',
        'artifacts/island-war-v3/final-installed/equivalence.json',
        'artifacts/island-war-v3/presentation/integration-review.json',
        'artifacts/island-war-v3/presentation/vehicle-receipt.json',
        'artifacts/island-war-v3/presentation/anchor-receipt.json',
        'artifacts/island-war-v3/presentation/cover-receipt.json',
        'artifacts/island-war-v3/core/actual-tank-rear-cover.json',
        'artifacts/island-war-v3/core/actual-ifv-rear-cover.json',
        'artifacts/tactical-vehicles-v3-20261115/verification.json',
        'artifacts/tactical-vehicles-v3-20261115/weapon-model-bindings.json',
        'artifacts/island-war-v3/home/receipt-ui.json',
        'artifacts/island-war-v3/home/legacy-224-receipt.json',
        'artifacts/island-war-v3/codex/receipt.json',
        'artifacts/island-war-v3/home-codex-final-receipt.json',
        'artifacts/island-war-v3/home/final-metadata-rebind.json',
        'artifacts/island-war-v3/codex/final-source-rebind.json',
        'artifacts/tactical-vehicles-v3-20261115/independent-final-design-review.json',
        'artifacts/tactical-vehicles-v3-20261115/independent-103-actual-cover-final.json',
        'artifacts/island-war-v3/normal-launch-check.log',
        'artifacts/godot-launch-import.log',
    ]
    report = {'version': 'cas-island-war-v3', 'status': 'verified-and-installed',
              'completed_utc': datetime.now(timezone.utc).isoformat(),
              'native': core['native'], 'wasm': core['wasm'],
              'installed': {'path': str(installed.relative_to(ROOT)), 'sha256': manifest['sha256']},
              'catalogue_sha256': source_sha,
              'checks': {'rust': core['tests'], 'installed_cases': len(parity['cases']),
                         'installed_responses': parity['requests'], 'home': home['checks'],
                         'legacy_account': legacy['checks'], 'codex': codex['count'],
                         'accuracy_samples': codex['accuracy_samples'], 'vehicle_metadata': assets['checks'],
                         'unit_profiles': len(catalogue['cards']), 'weapon_models': len(models),
                         'weapon_families': len(catalogue['weapon_families']), 'borrowed_courses': course_count,
                         'vehicle_gpu': vehicle['checks'], 'anchor_gpu': anchors['checks'],
                         'autonomous_cover_gpu': cover['checks'],
                         'active_sprite_frames': anchors['frames'], 'production_godot': review['reviews']},
              'model_art_mapping_checks': bindings['checks'], 'preserved_asset_pngs': preserved_pngs,
              'receipts': [reference(name) for name in paths], 'formal_profiles': formal,
              'production_godot_sources': [reference(str(p.relative_to(ROOT)))
                                           for p in sorted((ROOT / 'godot/scripts').glob('*.gd'))],
              'scope': 'New island raids, defense, own exercises and configured borrowed lessons use v3; historical rules and existing voyages retain their saved versions. Proposals are offline edits, not live account writes.',
              'limits': ['Reuses each original SD; weapon icons/badges and native weapons differ, no claim of newly drawn held-gun pose sheets.',
                         'Authored weapon timings use the actual 0.1-second simulation clock. AI holds position when its main weapons reload; no claim of coordinated cross-company reload rotation.',
                         'Area-fire AI uses a quality-based heuristic, not full geometric expected-damage integration; unloading passenger lead uses nominal craft speed.',
                         'New 022/103 autonomous cover uses real vehicle circles and individual motion. It is not full three-dimensional armor facing, terrain occlusion, or guaranteed safety from area/high-arc fire.',
                         'GPU and mobile-width browser checks are Windows desktop checks, not APK device performance or full three-chapter human playtime.',
                         'Existing first-voyage test exit leak warning is retained in the regression log; production GPU logs must contain no script/render errors.']}
    output = ROOT / 'artifacts/island-war-v3/integration-receipt.json'
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), 'utf-8')
    print(json.dumps({'ok': True, 'installed_sha256': manifest['sha256'], 'checks': report['checks']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
