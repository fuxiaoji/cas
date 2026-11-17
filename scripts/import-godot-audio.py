"""Prepare authorized local-playtest music/crew voices plus CC0 interface sounds.

Only writes Godot copies. The archive/reference projects and originals stay read-only.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'godot/assets/audio'
FFMPEG = Path(r'D:/desktop/项目/周报分析/tools/ffmpeg/ffmpeg-8.1.2-essentials_build/bin/ffmpeg.exe')
TRACKS = [
    ('26792364469-1-192', 'harbor'), ('26808093623-1-192', 'formation'),
    ('26837123805-1-192', 'recruit'), ('26854230352-1-192', 'salvage'),
    ('42391898601-1-192', 'battle'), ('25793531309-1-192', 'shop'),
    ('26752910749-1-192', 'victory'), ('26778207922-1-192', 'defeat'),
]
KENNEY_URL = 'https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def convert(task):
    source, output = task
    output.parent.mkdir(parents=True, exist_ok=True)
    if not output.exists():
        subprocess.run([str(FFMPEG), '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
                        '-i', str(source), '-vn', '-map', '0:a:0', '-ar', '44100', '-ac', '2',
                        '-af', 'loudnorm=I=-19:LRA=9:TP=-1.5', '-c:a', 'libvorbis', '-q:a', '4',
                        str(output)], check=True, capture_output=True)
    return output


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    tasks = []
    music = []
    for name, scene in TRACKS:
        source = Path('D:/downloads') / (name + '.mp4')
        if not source.is_file():
            raise FileNotFoundError(source)
        output = DEST / 'local_music' / (name + '.ogg')
        tasks.append((source, output))
        music.append({'scene': scene, 'source': str(source), 'source_sha256': sha(source),
                      'path': 'res://assets/audio/local_music/' + output.name,
                      'rights': 'user supplied; local private playtest only; public distribution clearance unrecorded'})
    voice_ledger = json.loads((ROOT/'client/src/audio/archive/ledger.json').read_text(encoding='utf8'))
    voices = []
    for row in voice_ledger['assets']:
        source = Path(row['source_path'])
        if not source.is_file():
            raise FileNotFoundError(source)
        if sha(source) != row['source_sha256']:
            raise ValueError(f'Voice source changed: {source}')
        output = DEST / 'local_voice' / (Path(row['path']).stem + '.ogg')
        tasks.append((source, output))
        voices.append({key: row.get(key) for key in ['event','variant','seat','title_zh','match','note','source_path','source_sha256']})
        voices[-1]['path'] = 'res://assets/audio/local_voice/' + output.name
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(convert, tasks))
    for row in music + voices:
        out = ROOT/'godot'/row['path'][6:]
        row['sha256'] = sha(out)
        row['bytes'] = out.stat().st_size
    # Kenney now rotates signed download links; old media URLs redirect to HTML.
    link_request = urllib.request.Request('https://kenney.nl/download-link/6173736574732f696e746572666163652d736f756e6473',
                                          headers={'Referer':'https://kenney.nl/assets/interface-sounds'})
    with urllib.request.urlopen(link_request, timeout=60) as response:
        download_url = json.load(response)['url']
    request = urllib.request.Request(download_url, headers={'User-Agent':'CAS-development/1.0','Referer':'https://kenney.nl/assets/interface-sounds'})
    with urllib.request.urlopen(request, timeout=60) as response:
        archive = zipfile.ZipFile(io.BytesIO(response.read()))
    ui_dir = DEST / 'ui'
    ui_dir.mkdir(exist_ok=True)
    mapping = {'tap':'click_001.ogg','confirm':'confirmation_001.ogg','select':'select_001.ogg','error':'error_001.ogg'}
    ui = []
    for cue, filename in mapping.items():
        candidates = [name for name in archive.namelist() if Path(name).name == filename]
        if not candidates:
            raise KeyError(f'{filename}; available={archive.namelist()}')
        output = ui_dir / (cue+'.ogg')
        output.write_bytes(archive.read(candidates[0]))
        ui.append({'cue':cue,'path':'res://assets/audio/ui/'+output.name,'source_file':candidates[0],
                   'sha256':sha(output),'bytes':output.stat().st_size,'license':'CC0 1.0'})
    for name in archive.namelist():
        if Path(name).name.lower().startswith('license'):
            (ui_dir/'Kenney-LICENSE.txt').write_bytes(archive.read(name))
            break
    ledger = {
        'version':1, 'date':'2026-11-11', 'scope':'local_private_playtest',
        'processing':'FFmpeg Vorbis quality4, 44.1kHz stereo, EBU loudnorm -19 LUFS / -1.5dBTP. Originals unchanged.',
        'music_assignment':'Scene assignments are development defaults, not inferred song titles or moods.',
        'local_voice_policy':'Only seat-visible live events; no hidden contacts. Direction from seat-visible coordinates only. No clip when a direction is unknown.',
        'release_gate':'Exclude local_music and local_voice for public builds unless clearance is recorded. UI sounds CC0 may ship.',
        'source_voice_ledger':'client/src/audio/archive/ledger.json',
        'uncertainties':voice_ledger['uncertainties'],
        'music':music,'voices':voices,
        'ui_source':'https://kenney.nl/assets/interface-sounds','ui_download':KENNEY_URL,
        'ui_license':'https://creativecommons.org/publicdomain/zero/1.0/', 'ui':ui,
    }
    (ROOT/'godot/data/audio.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'music':len(music),'voices':len(voices),'cc0_ui':len(ui),'bytes':sum(r['bytes'] for r in music+voices+ui)}))


if __name__ == '__main__':
    main()
