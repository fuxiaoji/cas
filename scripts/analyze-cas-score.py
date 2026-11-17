"""Measure every original master and create an audition montage; no account access."""
from pathlib import Path
import hashlib,json,subprocess
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
FF=Path(r'D:/desktop/项目/周报分析/tools/ffmpeg/ffmpeg-8.1.2-essentials_build/bin/ffmpeg.exe')
OUT=ROOT/'artifacts/original-music';OUT.mkdir(parents=True,exist_ok=True)
rows=[];fails=[];preview=[]
for path in sorted((ROOT/'godot/assets/audio/original').glob('*.ogg')):
 score=json.loads((ROOT/'music/original-v1'/(path.stem+'.score.json')).read_text(encoding='utf-8'))
 raw=subprocess.run([str(FF),'-v','error','-i',str(path),'-f','f32le','-ar','44100','-ac','2','-'],capture_output=True,check=True).stdout
 data=np.frombuffer(raw,dtype='<f4').reshape(-1,2);peak=float(np.abs(data).max());loop_start=round(score.get('loop_start_bar',0)*4*60/score['bpm']*44100);seam=float(np.abs(data[-1]-data[loop_start]).max())
 meter=subprocess.run([str(FF),'-hide_banner','-i',str(path),'-af','loudnorm=I=-22:TP=-2:LRA=9:print_format=json','-f','null','-'],capture_output=True,text=True,check=True).stderr
 metrics=json.JSONDecoder().raw_decode(meter[meter.rfind('{'):])[0]
 layers=sorted(set(n['instrument'] for n in score['notes']))
 midi=(ROOT/'music/original-v1'/(path.stem+'.mid')).read_bytes()
 checks={'finite_samples':bool(np.isfinite(data).all()),'no_clipping':peak<.9,'moderate_loudness':-24.5<=float(metrics['input_i'])<=-20,'true_peak_headroom':float(metrics['input_tp'])<=-2,'loop_seam':not score['loop'] or seam<.04,'editable_midi':midi[:4]==b'MThd' and len(midi)>500,'layered_arrangement':len(layers)>=4,'authored_notes':len(score['notes'])>=80,'distinct_phrase':score['motif'][0]!=score['motif'][1]}
 for key,ok in checks.items():
  if not ok:fails.append(path.stem+':'+key)
 rows.append(dict(id=path.stem,title=score['title'],seconds=len(data)/44100,layers=layers,note_count=len(score['notes']),peak=peak,loop_sample_delta=seam,loudness_lufs=float(metrics['input_i']),true_peak_dbtp=float(metrics['input_tp']),lra_lu=float(metrics['input_lra']),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),checks=checks))
 # One A phrase and a contrasting B phrase; offsets are recorded for honest audition.
 for section in [0,min(16,score['bars']//2)]:
  at=int(section*4*60/score['bpm']*44100);clip=data[at:at+4*44100].copy()
  if len(clip):
   fade=min(4410,len(clip)//2);clip[:fade]*=np.linspace(0,1,fade)[:,None];clip[-fade:]*=np.linspace(1,0,fade)[:,None];preview.append(clip)
sequence=np.concatenate(preview,axis=0)
subprocess.run([str(FF),'-v','error','-y','-f','f32le','-ar','44100','-ac','2','-i','-','-c:a','libmp3lame','-q:a','3',str(OUT/'original-score-audition.mp3')],input=sequence.astype('<f4').tobytes(),check=True)
report=dict(tracks=rows,checks=sum(len(r['checks']) for r in rows),failures=fails,passed=not fails,external_samples_used=False,preview='original-score-audition.mp3',preview_order=[r['id'] for r in rows],preview_sections='Each track: first four seconds of A, then four seconds from B (or midpoint for short cues). Not a live mix capture.')
(OUT/'analysis.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'checks':report['checks'],'tracks':len(rows),'failures':fails,'loudness_range':[min(r['loudness_lufs'] for r in rows),max(r['loudness_lufs'] for r in rows)]}));raise SystemExit(bool(fails))
