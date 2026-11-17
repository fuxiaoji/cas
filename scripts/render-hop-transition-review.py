"""Build review artifacts from actual production Godot GPU frame captures."""
import json
from pathlib import Path
import shutil
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/hop-transition'
receipt=json.loads((OUT/'receipt.json').read_text(encoding='utf-8'))
frames=receipt['actual_route_frames']
ffmpeg=shutil.which('ffmpeg') or 'D:/desktop/项目/周报分析/tools/ffmpeg/ffmpeg-8.1.2-essentials_build/bin/ffmpeg.exe'
concat=['ffconcat version 1.0']
for i, frame in enumerate(frames):
    duration=(frames[i+1]['elapsed_ms']-frame['elapsed_ms'])/1000 if i+1<len(frames) and frames[i+1]['route']==frame['route'] else 1/60
    duration=max(.008,min(.25,duration))
    concat.extend(["file '"+frame['path'].replace('\\','/')+"'",f'duration {duration:.6f}'])
(OUT/'actual-routes.ffconcat').write_text('\n'.join(concat)+'\n',encoding='utf-8')
subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-safe','0','-f','concat','-i',str(OUT/'actual-routes.ffconcat'),'-vf','fps=60','-c:v','libx264','-crf','18','-preset','medium','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/'actual-three-hop-routes.mp4')],check=True)
font=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',20)
small=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',16)
for route in ['formation','modes','home']:
    rows=[row for row in frames if row['route']==route]
    sheet=Image.new('RGB',(1920,1050),'#111e2c');draw=ImageDraw.Draw(sheet)
    draw.text((18,10),f'ACTUAL GPU: {route} / 1.18 s / 3 short hops / planted feet between jumps',fill='white',font=font)
    chosen=[]
    for index, phase in enumerate([.08,.16,.24,.32,.40,.48,.56,.64,.72,.80,.88,.96]):
        row=min(rows,key=lambda r:abs(r['phase']-phase));chosen.append(row)
        picture=Image.open(row['path']).convert('RGB')
        w,h=picture.size
        # Enlarge the three SD actors and the baseline rather than reducing the
        # whole menu to an unreadable contact-sheet thumbnail.
        picture=picture.crop((int(w*.06),int(h*.48),int(w*.94),int(h*.89)))
        picture.thumbnail((468,280))
        x=(index%4)*480+6;y=(index//4)*332+46
        sheet.paste(picture,(x,y+34))
        draw.text((x+4,y),f"{row['elapsed_ms']/1000:.3f}s  /  phase {row['phase']:.2f}",fill='#f2d497',font=small)
    sheet.save(OUT/f'{route}-hop-storyboard.png')
    (OUT/f'{route}-storyboard-samples.json').write_text(json.dumps(chosen,ensure_ascii=False,indent=2),encoding='utf-8')
receipt['video']=(OUT/'actual-three-hop-routes.mp4').as_posix()
receipt['storyboards']=[(OUT/f'{route}-hop-storyboard.png').as_posix() for route in ['formation','modes','home']]
receipt['video_origin']='Actual production Main navigation captured from Godot GPU. Repeated frames resampled to 60fps; no synthetic motion interpolation.'
(OUT/'receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'frames':len(frames),'video':receipt['video'],'routes':receipt['routes']},ensure_ascii=False))
