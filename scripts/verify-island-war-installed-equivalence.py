"""Read-only byte comparison of normal-launch native and previously frozen candidate."""
from pathlib import Path
import json,hashlib,subprocess,struct
root=Path(__file__).resolve().parents[1]
out=root/'artifacts/island-war-v1/final-installed';out.mkdir(parents=True,exist_ok=True)
baseline=root/'target/island-war-build/release/cas-sim.exe'
installed=root/'godot/bin/runtime/565ffb4ce525c3cc/cas-sim.exe'
def digest(b):return hashlib.sha256(b).hexdigest()
def run_case(path):
    raw=path.read_text('utf-8-sig')
    calls=[json.loads(line) for line in raw.splitlines() if line.strip()] if path.suffix=='.jsonl' else json.loads(raw)
    procs=[subprocess.Popen([str(p)],stdin=subprocess.PIPE,stdout=subprocess.PIPE) for p in (baseline,installed)]
    h=hashlib.sha256();size=0
    try:
        for i,q in enumerate(calls):
            wire=(json.dumps(q,ensure_ascii=False,separators=(',',':'))+'\n').encode('utf-8')
            replies=[]
            for p in procs:
                p.stdin.write(wire);p.stdin.flush();replies.append(p.stdout.readline())
            assert replies[0] and replies[1],(path,i,'core terminated')
            if replies[0]!=replies[1]:
                (out/'mismatch-baseline.json').write_bytes(replies[0]);(out/'mismatch-installed.json').write_bytes(replies[1])
                raise AssertionError((path,i,q.get('op')))
            result=replies[0].rstrip(b'\r\n');h.update(result);h.update(b'\n');size+=len(result)
        return {'path':str(path.relative_to(root)),'requests':len(calls),'raw_identical_bytes':size,'response_sha256':h.hexdigest(),'command_file_sha256':digest(path.read_bytes()),'raw_identical':True}
    finally:
        for p in procs:p.stdin.close();p.wait(timeout=20)
def pe(path):
    b=path.read_bytes();p=struct.unpack_from('<I',b,0x3c)[0];assert b[p:p+4]==b'PE\0\0'
    count=struct.unpack_from('<H',b,p+6)[0];opt=struct.unpack_from('<H',b,p+20)[0]
    sections=[]
    for i in range(count):
        at=p+24+opt+40*i;name=b[at:at+8].rstrip(b'\0').decode('ascii');size,offset=struct.unpack_from('<II',b,at+16)
        sections.append({'name':name,'bytes':size,'sha256':digest(b[offset:offset+size])})
    return {'path':str(path.relative_to(root)),'sha256':digest(b),'bytes':len(b),'coff_timestamp':struct.unpack_from('<I',b,p+8)[0],'sections':sections}
new=sorted((root/'artifacts/island-war-v1/parity/new-mode').glob('*-commands.json'));assert len(new)==16
legacy=[]
for folder,prefix in [('littoral-core',''),('littoral-v2','v2-'),('littoral-v3','v3-'),('littoral-v4','v4-'),('littoral-v4/multi','v4-')]:
    legacy+=sorted(p for p in (root/'artifacts'/folder).glob('*-commands.json') if p.name.startswith(prefix))
legacy += [root/'artifacts/amphibious-expedition'/f for f in ['native-wasm-calls.jsonl','carrier-wasm-calls.jsonl','multicompany-wasm-calls.jsonl']]
assert len(legacy)==40
rows=[]
for category,files in [('new16',new),('legacy40',legacy)]:
    for file in files:
        row=run_case(file);row['category']=category;rows.append(row)
    print(json.dumps({'category':category,'passed':True,'files':len(files),'requests':sum(r['requests'] for r in rows if r['category']==category)}),flush=True)
a,b=pe(baseline),pe(installed)
receipt={'passed':True,'baseline':a,'installed':b,'cases':rows,'requests':sum(r['requests'] for r in rows),'raw_identical_bytes':sum(r['raw_identical_bytes'] for r in rows),'scope':'Every response from 16 new island scenarios and 40 existing littoral/amphibious fixtures compared byte-for-byte between normal-launch release and frozen candidate, including saves, replay and rejected commands. No source, binaries, manifests or accounts modified.','binary_difference_evidence':{'section_comparison':[{ 'name':x['name'],'baseline_sha256':x['sha256'],'installed_sha256':next((s['sha256'] for s in b['sections'] if s['name']==x['name']),None),'same':any(s['name']==x['name'] and s['sha256']==x['sha256'] for s in b['sections'])} for x in a['sections']],'interpretation':'Different executable SHA is established. Section and COFF comparison records what differs; public-protocol equality is established only for listed fixtures, not universal binary equivalence or a proven unique build-cause.'}}
(out/'native-equivalence.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'passed':True,'requests':receipt['requests'],'bytes':receipt['raw_identical_bytes'],'receipt':str(out/'native-equivalence.json')}),flush=True)
