"""Copy original built-in generated assets and register provenance without editing pixels."""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GODOT = ROOT / 'godot'
jobs = json.loads((ROOT / 'tools/nov12-arena-art-prompts.json').read_text(encoding='utf-8'))

def read(path): return json.loads(path.read_text(encoding='utf-8'))
def write(path, data): path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def copy(source, target):
    source = Path(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and sha(target) != sha(source): raise ValueError(f'Refusing different existing candidate: {target}')
    if not target.exists(): shutil.copy2(source, target)
    with Image.open(target) as image:
        assert image.mode == 'RGBA' and image.getchannel('A').getextrema()[0] == 0
        size = list(image.size)
    return {'sha256': sha(target), 'size': size, 'pixels_unchanged': True}

helena = jobs['helena']
target = GODOT / 'assets/characters/chibis-generated-2026-11-12-v4/ibs-u-usn-helena.png'
info = copy(helena['generated_file'], target)
portrait = GODOT / 'assets/characters/portraits/ibs-u-usn-helena.webp'
record = {**helena, **info, 'path': 'res://'+target.relative_to(GODOT).as_posix(), 'status': 'generated_v4_identity_corrected', 'generator': jobs['generator'], 'source_portrait': helena['references'][0], 'source_portrait_sha256': sha(portrait), 'appearance_review':'agent_visual_checked_against_own_portrait_and_accepted_sd_style', 'user_acceptance':'not_claimed', 'supersedes':'res://assets/characters/chibis/ibs-u-usn-helena.png', 'scope':'local_developer_and_test_builds'}
write(target.with_suffix('.json'), record)
ships_path = GODOT / 'data/ships.json'
ships = read(ships_path)
for row in ships['ships']:
    if row['id'] == helena['identity']:
        row.update({'chibi':record['path'], 'chibi_generated':record['path'], 'chibi_reference':'', 'projection_status':'generated_chibi_identity_corrected', 'chibi_appearance_verified_against_cas_portrait':True, 'chibi_user_style_accepted':False})
write(ships_path, ships)
ledger_path = GODOT / 'assets/characters/ledger.json'
ledger = read(ledger_path)
ledger['chibis'] = [r for r in ledger['chibis'] if r.get('identity') != helena['identity']] + [record]
ledger['generated_chibis'] = [r for r in ledger.get('generated_chibis',[]) if r.get('identity') != helena['identity']] + [record]
ledger['pending_chibis'] = [r for r in ledger.get('pending_chibis',[]) if r.get('identity') != helena['identity']]
for row in ledger.get('reference_spine_chibis',[]):
    if row.get('identity') == helena['identity']:
        row['runtime_active'] = False
        row['superseded_by'] = record['path']
generated = sum(bool(r.get('chibi_generated')) for r in ships['ships'])
ledger['summary']['runtime_generated_chibis'] = generated
ledger['summary']['runtime_reference_chibis'] = len(ships['ships'])-generated
ledger['summary']['produced_generated_images'] = generated
ledger['summary']['identity_corrected_v4_chibis'] = 1
write(ledger_path, ledger)

ai_path = GODOT / 'data/ai-art.json'
ai = read(ai_path)
records = []
for row in jobs['ai']:
    target = GODOT / ('assets/ai/original-v3/'+row['id']+'.png')
    info = copy(row['generated_file'], target)
    item = {**row, **info, 'portrait':'res://'+target.relative_to(GODOT).as_posix(), 'generator':jobs['generator'], 'style_reference':'res://assets/ai/rc_coordinated.png', 'identity':'original_unique_tactical_automaton', 'scope':'local_developer_and_test_builds', 'appearance_review':'agent_visual_checked', 'user_acceptance':'not_claimed'}
    records.append(item)
    write(target.with_suffix('.json'), item)
    ai['profiles'] = [r for r in ai['profiles'] if r['id'] != row['id']] + [item]
write(ai_path, ai)
write(ROOT / 'docs/art/generated-arena-ai-helena-v1.json', {'date':jobs['date'],'generator':jobs['generator'],'helena':record,'ai':records,'runtime_generated':generated,'runtime_reference':len(ships['ships'])-generated})
print(json.dumps({'helena':record['path'],'ai_count':len(records),'generated':generated,'reference':len(ships['ships'])-generated}, ensure_ascii=False))
