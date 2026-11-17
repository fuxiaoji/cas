"""Bind a final candidate to an already verified old-runtime raw oracle.

The oracle is the untouched receipt from the dual-runtime full old-v3 run.
Only the final candidate is replayed; no account or binary is written.
"""
from pathlib import Path
import argparse, hashlib, json, subprocess

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--native',type=Path,required=True)
p.add_argument('--oracle',type=Path,default=ROOT/'artifacts/island-war-v4/parity/old-v3-freeze.json')
p.add_argument('--out',type=Path,default=ROOT/'artifacts/island-war-v4/parity/final-old-v3-freeze.json')
args=p.parse_args()
oracle=json.loads(args.oracle.read_text('utf8'))
assert oracle['passed']
rows=[]
for case in oracle['cases']:
    assert case['raw_identical']
    file=ROOT/case['source']
    commands=json.loads(file.read_text('utf-8-sig'))
    assert len(commands)==case['requests']
    proc=subprocess.Popen([str(args.native.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
    h=hashlib.sha256(); size=0
    try:
        for q in commands:
            proc.stdin.write((json.dumps(q,ensure_ascii=False,separators=(',',':'))+'\n').encode('utf8'))
            proc.stdin.flush()
            raw=proc.stdout.readline()
            assert raw, (file,q['op'])
            h.update(raw);size+=len(raw)
    finally:
        proc.stdin.close();proc.wait(timeout=30)
    assert h.hexdigest()==case['response_sha256'] and size==case['bytes'], (file,h.hexdigest(),case['response_sha256'])
    row={**case,'source_sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'final_raw_identical':True}
    rows.append(row)
    print(json.dumps({'case':len(rows),'source':case['source'],'requests':len(commands),'passed':True}),flush=True)
receipt={'passed':True,'native':str(args.native.resolve()),'native_sha256':hashlib.sha256(args.native.read_bytes()).hexdigest(),
         'baseline':oracle['installed'],'baseline_sha256':oracle['installed_sha256'],'oracle':str(args.oracle.resolve()),
         'oracle_sha256':hashlib.sha256(args.oracle.read_bytes()).hexdigest(),'cases':rows,
         'requests':sum(c['requests'] for c in rows),'bytes':sum(c['bytes'] for c in rows),
         'scope':'All final-candidate raw replies match the per-stream SHA256 and byte length of the already byte-identical dual-runtime old-v3 oracle; no old evidence, account, runtime, or manifest mutated.'}
args.out.parent.mkdir(parents=True,exist_ok=True)
args.out.write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'passed':True,'cases':len(rows),'requests':receipt['requests'],'output':str(args.out)}),flush=True)
