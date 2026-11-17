"""Original vector object illustrations; no downloaded or generated-image pixels."""
from pathlib import Path
import hashlib, json
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'godot/assets/items/expedition'
OUT.mkdir(parents=True, exist_ok=True)
ART = {
'water_filter':'<path fill="#cbd8c8" d="M42 20h44v88H42z"/><path fill="#438c8b" d="M36 20h56v15H36zM36 93h56v15H36z"/><path d="M49 43h30M49 53h30M49 63h30M49 73h30M49 83h30"/>',
'copper_coil':'<path fill="#4c7476" d="M27 30h74v71H27z"/><path stroke="#d49b61" stroke-width="8" d="M37 34v63m12-63v63m12-63v63m12-63v63m12-63v63m12-63v63"/><path d="M23 23h82M23 106h82"/>',
'cult_processor':'<path fill="#48616b" d="M28 28h72v72H28z"/><path fill="#b599d6" d="m64 40 23 25-23 23-23-23z"/><path d="M37 17v11m18-11v11m18-11v11m18-11v11M37 100v11m18-11v11m18-11v11m18-11v11M17 37h11m-11 18h11m-11 18h11m-11 18h11M100 37h11m-11 18h11m-11 18h11m-11 18h11"/>',
'memory_core':'<path fill="#455c78" d="M37 17h54v94H37z"/><path fill="#8cc9d1" d="M47 29h34v49H47z"/><path fill="#e7c889" d="M47 88h8v14h-8zM61 88h8v14h-8zM75 88h8v14h-8z"/><path d="m55 58 8-16 10 16-10 11z"/>',
'medical_case':'<path fill="#ddd9c4" d="M19 40h90v62H19z"/><path d="M46 40V26h36v14M19 57h90"/><path fill="#ca6d68" stroke="none" d="M56 56h16v12h12v16H72v12H56V84H44V68h12z"/>',
'old_camera':'<path fill="#4d666a" d="M18 41h92v62H18z"/><path fill="#b6bdb2" d="M35 28h30l8 13H27z"/><circle fill="#b0d6d4" cx="66" cy="73" r="24"/><circle fill="#294f62" cx="66" cy="73" r="15"/><path d="M85 49h17M29 58v26"/>',
'porcelain':'<path fill="#e4e4d3" d="M23 76q0 33 81 0zM38 37h43v38q-21 29-43 0z"/><path d="M81 43h15q22 22-15 24"/><path stroke="#578ea5" d="M45 47h29M44 63q16-12 30 0M37 87h50"/>',
'sealed_ledger':'<path fill="#926d5b" d="m28 23 65-8 8 91-65 8z"/><path fill="#d7c49d" d="m36 26 56-5 7 79-56 6z"/><path d="m43 40 40-5m-39 18 40-5m-38 19 37-4"/><circle fill="#c66c5c" cx="71" cy="87" r="14"/><path stroke="#f0cc8b" d="m64 86 7-8 7 8-7 8z"/>',
'fuel_cell':'<path fill="#537e7e" d="M42 24q22-12 44 0v82q-22 13-44 0z"/><path fill="#b4c8b0" d="M52 15h24v14H52z"/><path fill="#c2d49b" stroke="none" d="m68 38-17 31h13l-4 26 21-36H68z"/><path d="M42 34h44M42 97h44"/>',
'turbine_rotor':'<circle fill="#718985" cx="64" cy="64" r="44"/><g fill="#c2cbbb"><path d="m64 29 14 23-14 12-8-13zM99 64 76 78 64 64l13-8zM64 99 50 76 64 64l8 13zM29 64l23-14 12 14-13 8z"/></g><circle fill="#b79665" cx="64" cy="64" r="12"/>',
'navigation_gyro':'<circle fill="#759a9d" cx="64" cy="61" r="39"/><ellipse fill="none" cx="64" cy="61" rx="20" ry="39"/><path d="M25 61h78M64 22v78M44 105h40"/><path fill="#e8c788" d="m64 34 12 30-12-6-12 6z"/>',
'ai_relic':'<path fill="#776c9b" d="m64 13 32 30-6 54-26 18-26-18-6-54z"/><path fill="#c3d3d6" d="m64 13 2 70 30-40z"/><path fill="#9eadd2" d="m64 13-32 30 34 40z"/><path d="m38 97 28-14 24 14M32 43l34 40-2 32"/><circle fill="#eec98b" cx="65" cy="64" r="9"/>',
'thermal_crystal':'<path fill="#c97b70" d="m52 20 30 7 18 62-31 25-37-24z"/><path fill="#e4bc91" d="m52 20 9 59 21-52z"/><path fill="#eecc9e" d="m61 79 39 10-31 25z"/><path d="m32 90 29-11 8 35M61 79l21-52"/>',
'sealed_gear':'<path fill="#8d9c8f" d="m20 32 79-9 11 77-79 9z"/><path d="m20 32 15 16 75-10M35 48l-4 61M35 48l-15-16"/><path fill="#e2c186" d="m62 51 22-2 4 30-22 3z"/><path d="m63 27 9 76M38 30l9 75"/>',
'crew_archive':'<path fill="#7c9792" d="M22 29h84v74H22z"/><path fill="#d2d0b7" d="M28 35h72v62H28z"/><path d="M22 47h84"/><circle fill="#72979e" cx="48" cy="62" r="9"/><path fill="#72979e" d="M34 88V77q14-11 28 0v11z"/><path d="M72 60h18M72 71h18M72 82h18"/>',
'cult_banner':'<path fill="#866a83" d="M37 19h61v86l-30-13-31 13z"/><path fill="#d5b98b" d="m67 37 17 25-17 21-17-21z"/><path d="M27 13v102M27 19h77"/><circle fill="#aec1cb" cx="67" cy="61" r="8"/>',
}
for name,color in [('balanced','#d3c29a'),('ap','#8fa5b3'),('he','#bf7162')]:
    ART['shell_'+name]=f'<path fill="{color}" d="M45 107V48q2-21 19-34 17 13 19 34v59z"/><path fill="#baa476" d="M42 87h44v20H42z"/><path d="M45 48h38M45 76h38"/>'
for name,color in [('standard','#a8bfb7'),('fast','#7ebbc7'),('heavy','#a895bf')]:
    ART['torpedo_'+name]=f'<path fill="{color}" d="M50 99V36q1-17 14-23 13 6 14 23v63z"/><path fill="#6e8182" d="m50 86-12 24 26-10 26 10-12-24z"/><path d="M50 39h28M50 73h28M64 101v13"/>'
entries=[]
for key,body in ART.items():
    size=32 if key.startswith(('shell_','torpedo_')) else 128
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 128 128"><g stroke="#304d58" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">'+body+'</g></svg>\n'
    path=OUT/(key+'.svg');path.write_text(svg,encoding='utf-8')
    entries.append({'id':key,'path':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
ledger={'version':1,'date':'2026-11-12','origin':'Original repository-native SVG object artwork. No external assets or AI raster editing.','license':'Project original artwork','items':entries}
(ROOT/'docs/art/expedition-object-icons-v2.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'{len(entries)} original object/ammunition illustrations saved')
