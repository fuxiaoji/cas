"""CAS original score v1. No recordings, external soundfonts or borrowed melodies.

Edit THEMES / SETTINGS, regenerate JSON, type-1 MIDI and deterministic stereo masters.
All timbres are synthesized here. MIDI uses GM programs only as editable suggestions.
"""
from pathlib import Path
import argparse, hashlib, json, math, struct, subprocess, wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'godot/assets/audio/original'
SOURCES=ROOT/'music/original-v1'
FFMPEG=Path(r'D:/desktop/项目/周报分析/tools/ffmpeg/ffmpeg-8.1.2-essentials_build/bin/ffmpeg.exe')
SR=44100
# Each theme is newly authored as two four-bar antecedent/consequent phrases.
# Tuples are diatonic scale degree, duration in beats; -99 is an intentional rest.
THEMES={
 'title':[[0,2,4,5,4,2,1,0],[2,4,6,7,6,4,2,1]],
 'harbor_day':[[4,2,1,0,1,2,4,3],[2,4,5,4,2,1,0,-99]],
 'harbor_night':[[0,4,3,2,1,-99,2,0],[4,6,5,4,2,1,-99,0]],
 'story':[[2,1,4,3,1,0,-99,1],[2,4,6,5,3,2,1,0]],
 'story_tension':[[0,1,4,1,0,3,2,-99],[4,3,6,4,2,1,0,1]],
 'battle':[[0,4,3,2,4,5,6,4],[3,2,1,4,6,5,3,0]],
 'landing':[[0,0,2,4,3,2,5,4],[6,4,3,2,1,3,2,0]],
 'home':[[0,2,1,4,5,4,2,0],[1,3,2,5,4,2,1,0]],
 'tide':[[4,4,6,5,4,2,3,4],[6,5,4,3,1,2,4,0]],
 'victory':[[0,2,4,7,6,4,5,7],[4,5,6,7,6,4,2,0]],
 'defeat':[[4,3,2,1,0,-99,1,0],[2,1,0,-99,-99,1,0,-99]],
}
# name, tempo, tonic MIDI, scale, chord-root progression, lead, bars, percussion
SETTINGS={
 'title':('归航的第一束光',78,67,'major',[0,4,5,3,0,2,3,4],'bell',24,'soft'),
 'harbor_day':('风过晾帆巷',92,62,'major',[0,3,5,4,2,3,4,0],'plucked',32,'brush'),
 'harbor_night':('值班灯与未寄的信',66,69,'minor',[0,5,2,6,3,0,4,0],'piano',24,'none'),
 'story':('潮线以外的回声',72,64,'dorian',[0,3,5,2,0,6,3,4],'piano',24,'soft'),
 'story_tension':('水下的第二次呼吸',96,62,'minor',[0,0,5,4,0,3,6,4],'reed',24,'pulse'),
 'battle':('与浪锋并肩',126,64,'minor',[0,5,3,6,0,2,4,4],'brass',32,'battle'),
 'landing':('踏上尚温的陆地',112,62,'dorian',[0,3,6,0,5,3,4,0],'brass',32,'march'),
 'home':('可以种下明天的岛',88,65,'major',[0,5,3,4,2,3,4,0],'plucked',32,'brush'),
 'tide':('潮环跃迁',138,69,'minor',[0,5,3,6,0,3,2,4],'pulse',32,'tide'),
 'victory':('灯塔回应',108,67,'major',[0,3,4,0],'brass',8,'finale'),
 'defeat':('带上剩下的人',64,64,'minor',[0,5,3,0],'piano',8,'none'),
}
SCALES={'major':[0,2,4,5,7,9,11],'minor':[0,2,3,5,7,8,10],'dorian':[0,2,3,5,7,9,10]}
PROGRAM={'piano':0,'bell':10,'plucked':24,'reed':71,'brass':60,'strings':48,'bass':33,'pulse':80,'pad':89,'drum':0}
def pitch(degree,tonic,scale):return tonic+scale[degree%7]+12*(degree//7)
def make_score(key):
 title,bpm,tonic,mode,progression,lead,bars,drums=SETTINGS[key];scale=SCALES[mode];notes=[]
 def add(inst,start,duration,midi,velocity,pan=0):
  notes.append(dict(instrument=inst,beat=round(start,4),duration=round(duration,4),pitch=int(midi),velocity=round(velocity,4),pan=pan))
 for bar in range(bars):
  section=bar//8;root=progression[bar%len(progression)];base=bar*4
  # Open, close-voiced harmony alternates with an added ninth in the contrasting section.
  chord=[root,root+2,root+4,root+8 if section==2 else root+6]
  for j,d in enumerate(chord):add('strings',base+.025*j,3.9,pitch(d,tonic-12,scale),.095 if drums in ['none','soft'] else .09,(-.45,-.14,.14,.45)[j])
  for beat in ([0,2] if drums in ['none','soft'] else [0,1.5,2,3]):
   add('bass',base+beat,1.7 if drums=='none' else .62,pitch(root if beat<2 else root+4,tonic-24,scale),.18,-.08)
  # Arpeggio inversion and rhythmic displacement make eight-bar sections develop.
  steps=4 if drums in ['none','soft'] else 8
  for j in range(steps):
   d=chord[(j+section)%len(chord)];start=base+j*4/steps
   add('plucked' if lead!='plucked' else 'bell',start,.55 if steps==8 else .95,pitch(d,tonic,scale),.07 if drums=='none' else .095,(-1 if j%2 else 1)*.38)
  phrase=THEMES[key][0 if section in [0,3] else 1]
  # Each two-beat motif cell is a real melodic decision, with a distinct B register.
  cell=(bar%4)*2
  for j in range(2):
   degree=phrase[cell+j]
   if degree==-99:continue
   degree += 7 if section==2 and lead not in ['brass','pulse'] else 0
   onset=base+j*2;duration=1.6 if drums in ['none','soft'] else 1.15
   if section==1 and j==1:degree-=1 if degree%7 not in [0,2,4] else 0
   add(lead,onset+.015,duration,pitch(degree,tonic,scale),.19 if lead in ['brass','pulse'] else .23,.06)
   if drums in ['battle','tide','march'] and (bar%4 in [1,3]):
    add(lead,onset+1.25,.48,pitch(degree-1 if j else degree+1,tonic,scale),.13,.12)
  if section>=1 and bar%2==1:
   add('reed' if lead!='reed' else 'bell',base+1,1.7,pitch(chord[1],tonic-12,scale),.10,-.38)
   add('reed' if lead!='reed' else 'bell',base+3,.8,pitch(chord[2],tonic-12,scale),.09,-.38)
  if drums!='none':
   for beat in range(4):
    if drums not in ['soft','brush'] or beat in [0,2]:add('drum',base+beat,.28,36,.20 if drums in ['battle','march','tide'] else .08,0)
    if beat in [1,3] and drums not in ['soft']:add('drum',base+beat,.20,38,.10,-.12)
   if drums in ['battle','tide','march','pulse']:
    for j in range(8):add('drum',base+j*.5,.07,42,.045 if j%2 else .06,.35)
   if bar%8==7 and drums in ['battle','tide','march','finale']:
    for j in range(4):add('drum',base+3+j*.25,.16,45+j%2*2,.09,-.2+j*.13)
  if bar%8==0:add('bell',base,2.4,pitch(7,tonic,scale),.065,.55)
 loop=key not in ['victory','defeat']
 return {'id':key,'title':title,'composer':'CAS original procedural score, authored 2026-11-13','bpm':bpm,'tonic_midi':tonic,'mode':mode,'bars':bars,'beats_per_bar':4,'sections':[{'name':n,'bar':i*8} for i,n in enumerate(['A','A-prime','B','return'][:math.ceil(bars/8)])],'loop':loop,'loop_start_bar':8 if loop else 0,'motif':THEMES[key],'harmony_degrees':progression,'notes':notes,'sample_rate':SR,'source_samples':'none; all instrument DSP authored in compose-cas-score.py'}
def varlen(n):
 b=[n&127];n>>=7
 while n:b.insert(0,(n&127)|128);n>>=7
 return bytes(b)
def midi(score,path):
 tracks=[];tempo=int(60000000/score['bpm']);events=b'\0\xff\x51\x03'+tempo.to_bytes(3,'big')+b'\0\xff\x58\x04\x04\x02\x18\x08'+b'\0\xff\x2f\0';tracks.append(events)
 for channel,inst in enumerate(dict.fromkeys(n['instrument'] for n in score['notes'])):
  ch=9 if inst=='drum' else channel if channel<9 else channel+1;events=[]
  for n in score['notes']:
   if n['instrument']!=inst:continue
   start=round(n['beat']*480);end=round((n['beat']+n['duration'])*480);vel=max(1,min(110,round(n['velocity']*300)))
   events.extend([(start,bytes([0x90|ch,n['pitch'],vel])),(end,bytes([0x80|ch,n['pitch'],0]))])
  events.sort(key=lambda e:e[0]);raw=b'\0'+bytes([0xc0|ch,PROGRAM[inst]]);previous=0
  for tick,msg in events:raw+=varlen(tick-previous)+msg;previous=tick
  tracks.append(raw+b'\0\xff\x2f\0')
 raw=b'MThd'+struct.pack('>IHHH',6,1,len(tracks),480)
 for track in tracks:raw+=b'MTrk'+struct.pack('>I',len(track))+track
 path.write_bytes(raw)
def voice(inst,midi,seconds,seed):
 t=np.arange(max(1,int((seconds+.30)*SR)),dtype=np.float32)/SR;f=440*2**((midi-69)/12);rng=np.random.default_rng(seed)
 attack={'strings':.18,'pad':.25,'brass':.025,'reed':.04,'bass':.012}.get(inst,.004)
 env=(1-np.exp(-t/attack))*np.minimum(1,np.maximum(0,(seconds+.25-t)/.28))
 if inst=='drum':
  noise=rng.uniform(-1,1,len(t)).astype(np.float32)
  if midi==36:y=np.sin(2*np.pi*(49*t+5*(1-np.exp(-t*30))))*np.exp(-t*19)
  elif midi==38:y=(noise*.65+np.sin(2*np.pi*180*t)*.3)*np.exp(-t*29)
  elif midi==42:y=(noise-np.roll(noise,1))*.25*np.exp(-t*95)
  else:y=np.sin(2*np.pi*(110+(midi-45)*18)*t)*np.exp(-t*15)+noise*.1*np.exp(-t*25)
 elif inst in ['piano','bell','plucked']:
  y=np.zeros(len(t),np.float32)
  for h in range(1,7):
   ratio=h if inst!='bell' else [1,2.003,2.76,4.03,5.42,6.8][h-1]
   decay=(.95 if inst=='piano' else .70 if inst=='plucked' else 1.6)/(1+h*.33)
   y+=np.sin(2*np.pi*f*ratio*t+np.sin(2*np.pi*4*t)*.001)*(h**-1.65)*np.exp(-t/decay)
  y*=.62
 elif inst=='bass':y=(np.sin(2*np.pi*f*t)+.24*np.sin(2*np.pi*f*2*t))*.70*np.exp(-t*.65)
 else:
  y=np.zeros(len(t),np.float32);vibrato=np.sin(2*np.pi*5.1*t)*.003
  for h in range(1,7 if inst in ['brass','pulse'] else 5):
   detune=(1+.0009*(1 if h%2 else -1));amplitude=h**(-1.45 if inst in ['brass','pulse'] else -2)
   y+=np.sin(2*np.pi*f*h*detune*t+vibrato*h)*amplitude
  y*=.46
 return (y*env).astype(np.float32)
def render(score):
 seconds=score['bars']*4*60/score['bpm'];length=round(seconds*SR);mix=np.zeros((length,2),np.float32)
 for index,n in enumerate(score['notes']):
  y=voice(n['instrument'],n['pitch'],n['duration']*60/score['bpm'],index+20261113)*n['velocity'];at=round(n['beat']*60/score['bpm']*SR)
  pan=n['pan'];stereo=np.stack([y*math.sqrt((1-pan)/2),y*math.sqrt((1+pan)/2)],axis=1)
  stop=min(length,at+len(y));mix[at:stop]+=stereo[:stop-at]
  if score['loop'] and at+len(y)>length:mix[:at+len(y)-length]+=stereo[stop-at:]
 # Deterministic stereo room: circular delays preserve the loop tail across the seam.
 dry=mix.copy()
 for delay,gain in [(.071,.11),(.113,.09),(.173,.075),(.257,.055),(.353,.035)]:
  shifted=np.roll(dry,round(delay*SR),axis=0)[:,::-1]
  if not score['loop']:shifted[:round(delay*SR)]=0
  mix+=shifted*gain
 if not score['loop']:
  fade=min(length,round(SR*2.5));mix[-fade:]*=np.linspace(1,0,fade,dtype=np.float32)[:,None]
 mix-=mix.mean(axis=0);peak=float(np.max(np.abs(mix)));mix*=.72/max(peak,.001)
 if score['loop']:
  # The opening A plays once. Loop A-prime/B[/return]; a 50ms local tail morph
  # matches both waveform value and slope into the authored loop start.
  start=round(score['loop_start_bar']*4*60/score['bpm']*SR);count=round(.05*SR)
  blend=np.linspace(0,1,count,dtype=np.float32)[:,None];mix[-count:]=mix[-count:]*(1-blend)+mix[start-count:start]*blend
 raw=SOURCES/(score['id']+'-render.wav')
 with wave.open(str(raw),'wb') as w:w.setnchannels(2);w.setsampwidth(2);w.setframerate(SR);w.writeframes((np.clip(mix,-1,1)*32767).astype('<i2').tobytes())
 output=OUT/(score['id']+'.ogg')
 subprocess.run([str(FFMPEG),'-hide_banner','-loglevel','error','-nostdin','-y','-i',str(raw),'-af','loudnorm=I=-22:TP=-2:LRA=9','-ar','44100','-c:a','libvorbis','-q:a','5',str(output)],check=True)
 meter=subprocess.run([str(FFMPEG),'-hide_banner','-nostdin','-i',str(output),'-af','loudnorm=I=-22:TP=-2:LRA=9:print_format=json','-f','null','-'],capture_output=True,text=True,check=True).stderr
 metrics=json.JSONDecoder().raw_decode(meter[meter.rfind('{'):])[0];raw.unlink()
 return {'id':score['id'],'title':score['title'],'seconds':seconds,'loop_start_seconds':score['loop_start_bar']*4*60/score['bpm'],'notes':len(score['notes']),'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'bytes':output.stat().st_size,'meter':metrics}
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--only');args=parser.parse_args();OUT.mkdir(parents=True,exist_ok=True);SOURCES.mkdir(parents=True,exist_ok=True);rows=[]
 for key in SETTINGS:
  if args.only and key!=args.only:continue
  score=make_score(key);(SOURCES/(key+'.score.json')).write_text(json.dumps(score,ensure_ascii=False,indent=2),encoding='utf-8');midi(score,SOURCES/(key+'.mid'));row=render(score);rows.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
 (SOURCES/('analysis-'+(args.only or 'all')+'.json')).write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':main()
