"""Compile authored CAS dialogue into editable Godot JSON and Resource files.

No external generation, runtime authority writes or source art changes.
"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'godot/data'
SPEAKERS = {'旁白': '', '你': '', '医生': '', '女人': '', '男孩': '', '老人': '', '修理师': '', '看守': '', '老妇人': '', '潮痕': 'tideborn'}

def assign_cast(node, cast):
    """Keep a three-person stage stable until another actual cast member speaks.

    Names without a cast/portrait remain named NPC voices, never borrowed ship art.
    A slot only changes when its speaker is needed; keep the other actors in place.
    """
    rows = node.get('lines', [])
    speakers = [row.get('speaker', '') for row in rows]
    stage = []
    for key in speakers:
        if key in cast and key not in stage:
            stage.append(key)
            if len(stage) == 3: break
    if not stage: stage = [key for key in node.get('actors', []) if key in cast][:3]
    node['actors'] = stage.copy()
    for i, row in enumerate(rows):
        speaker = row.get('speaker', '')
        if speaker in cast and speaker not in stage:
            def next_use(key):
                return next((j for j in range(i+1, len(rows)) if speakers[j] == key), len(rows)+1)
            if len(stage) < 3: stage.append(speaker)
            else: stage[max(range(len(stage)), key=lambda j: next_use(stage[j]))] = speaker
        row['actors'] = stage.copy()

def authored(chapter):
    scenes = {}
    for path in sorted((DATA / 'story-longform').glob(f'{chapter}*.txt')):
        key = ''
        for line in path.read_text('utf-8').splitlines():
            if line.startswith('# '):
                key = line[2:].strip(); scenes[key] = []
            elif '|' in line and key:
                speaker, text = line.split('|', 1)
                row = {'speaker': SPEAKERS.get(speaker, speaker), 'text': text, 'tone': 'calm', 'characters_per_second': 34.0, 'shot': 'wide'}
                if speaker in SPEAKERS and speaker not in ['旁白', '潮痕']: row['name'] = speaker
                scenes[key].append(row)
    return scenes

INSERTIONS = {
    'chapter-01': [('rescue','c1-medic'),('breakout','c1-rear-watch','c1-rear-escort'),('return','c1-supp-morning'),('hearing','c1-port-ledger','c1-quay-check','c1-water-dispute','c1-supp-game'),('supplies','c1-survey-brief','c1-survey','c1-crate-audit','c1-unclaimed-goods'),('archive','c1-witness','c1-before-report','c1-supp-dispute'),('message','c1-after-radio','c1-evacuation','c1-evacuate'),('promise','c1-night-kitchen','c1-supp-rooftop')],
    'chapter-02': [('c2-arrival','c2-harbor-work'),('c2-convoy-node','c2-rain-catch','c2-late-boat','c2-late-escort'),('c2-radio','c2-repair-bench','c2-signal-test','c2-market','c2-practice'),('c2-relay-node','c2-record-crosscheck','c2-second-cache','c2-two-copies','c2-response-seal','c2-response-plug','c2-guest','c2-clock','c2-soundings'),('c2-mine','c2-water-vote','c2-break-time','c2-nurse'),('c2-after','c2-water-trial','c2-maintenance-escort','c2-paper-lights'),('c2-secret','c2-workshop-night','c2-unposted-letter','c2-night-shift','c2-departure-log')],
    'chapter-03': [('c3-arrival','c3-weather-watch'),('c3-crossing-node','c3-empty-room','c3-rescue-signal'),('c3-lighthouse','c3-counter-sign'),('c3-core-node','c3-record-room','c3-copy-run'),('c3-choice','c3-tideborn-account'),('c3-after','c3-final-watch','c3-return-escort'),('c3-return','c3-kitchen-return','c3-public-hearing')],
}
ALIASES = {
 'c1-rear-escort': ('c1-breakout','拖缆后的船','抵达接应信标，集结仍可航行的本方舰撤离。'),
 'c1-survey': ('c1-salvage','外侧定位记录','实际搜索并带回外侧记录，确认主打捞点的坐标。'),
 'c1-evacuate': ('c1-breakout','外堤疏散','穿过受袭航路，集结仍可航行的本方舰抵达安全区。'),
 'c2-late-escort': ('c2-convoy','末班维修艇','回接落后的维修艇，保持全队生还抵达信标。'),
 'c2-second-cache': ('c2-relay','封存件的副本','第二次实际回收：带回独立副本以交叉核对原记录。'),
 'c2-maintenance-escort': ('c2-convoy','给明天留条路','为维护班重新通过外环航道，保障后续补给路线。'),
 'c3-rescue-signal': ('c3-crossing','回声之外','抵达接应信标，集结仍可航行的本方舰撤离。'),
 'c3-copy-run': ('c3-core','第二份原件','实际搜索并回收分开保存的档案副本。'),
 'c3-return-escort': ('c3-crossing','带记录的人','抵达返航信标，集结仍可航行的本方舰撤离。'),
}
TITLES={
 'c1-medic':'医务室的木片','c1-rear-watch':'落在后面的船','c1-port-ledger':'配给牌下面','c1-quay-check':'断锁与红线','c1-water-dispute':'不是同一桶水','c1-survey-brief':'出航前的干布','c1-crate-audit':'箱子有多重','c1-unclaimed-goods':'失物抽屉','c1-witness':'没有写齐的笔录','c1-before-report':'留白的那一栏','c1-after-radio':'安静的频道','c1-evacuation':'不能落下的东西','c1-night-kitchen':'熄灯之前','c1-supp-morning':'新来的早晨','c1-supp-game':'一局不算的牌','c1-supp-dispute':'还没有答应的话','c1-supp-rooftop':'毯子晾在屋顶',
 'c2-harbor-work':'多出来的一箱','c2-rain-catch':'接一场雨','c2-late-boat':'末班船的回话','c2-repair-bench':'修理台上','c2-signal-test':'不是同一条线','c2-market':'鱼篮里有十一条','c2-practice':'桌上的杯子','c2-record-crosscheck':'把原件排好','c2-two-copies':'两份不同的副本','c2-guest':'还没到的人','c2-clock':'三只不同的钟','c2-soundings':'命令里的这边','c2-water-vote':'水停下以后','c2-break-time':'读第三遍的时候','c2-nurse':'医棚来的客人','c2-water-trial':'最远的取水点','c2-paper-lights':'灯罩上的线','c2-workshop-night':'雨里的船灯','c2-unposted-letter':'没有寄出的信','c2-night-shift':'值班到天亮','c2-departure-log':'留下的人接班',
 'c2-response-seal':'封存以后谁接班','c2-response-plug':'还不够的条件',
 'c3-weather-watch':'天气纸上的墨迹','c3-empty-room':'值班室仍有回声','c3-counter-sign':'两种交接暗记','c3-record-room':'餐食单的时间','c3-tideborn-account':'潮痕的那份申请','c3-final-watch':'最后一班巡查','c3-kitchen-return':'不一样的辣酱','c3-public-hearing':'听证之后'
}
PORTRAIT_CG_BACKDROPS = {
    'res://assets/story/chapter1/rescue.png': 'res://assets/story/chapter1/deck-storm-v1.png',
    'res://assets/story/chapter1/hearing.png': 'res://assets/story/chapter1/archive-room-v1.png',
    'res://assets/story/chapter3/choice-cg.png': 'res://assets/story/chapter3/altar.png',
}
SCENE_BACKDROPS = {
    'c1-quay-check': 'res://assets/backgrounds/harbor-day-v2.png',
    'c1-water-dispute': 'res://assets/backgrounds/harbor-day-v2.png',
    'c2-workshop-night': 'res://assets/story/chapter1/drydock-v1.png',
}
SCENE_LOCATIONS = {
    'c1-medic': '第五队甲板 · 临时诊疗处',
    'c1-supp-morning': '第五队驻所 · 储物间与厨房',
    'c1-port-ledger': '战帮事务处 · 配给登记台',
    'c1-quay-check': '母港外码头 · 断锁旁',
    'c1-water-dispute': '母港外码头 · 取水处',
    'c1-supp-game': '第五队驻所 · 休息室',
    'c1-supp-dispute': '第五队驻所 · 仓库走廊',
    'c1-night-kitchen': '第五队驻所 · 夜间厨房',
    'c1-supp-rooftop': '第五队驻所 · 屋顶晾台',
    'c2-market': '沉钟交换站 · 鱼摊',
    'c2-practice': '沉钟交换站 · 临时桌边',
    'c2-workshop-night': '沉钟交换站 · 维修棚',
    'c2-night-shift': '沉钟交换站 · 夜间值班室',
    'c3-empty-room': '风暴灯塔 · 底层值班室',
    'c3-lighthouse': '风暴灯塔 · 上层交接间',
    'c3-record-room': '旧设施外侧 · 临时抄录点',
    'c3-kitchen-return': '母港 · 厨房',
    'c3-public-hearing': '母港 · 听证与档案保管处',
}

def visual_from_resource(node):
    path = DATA/'chapter-scenes'/f'{node["id"]}.tres'
    if not path.exists(): return
    src = path.read_text('utf-8-sig')
    for prop, key in [('background','background_asset'),('location','location'),('music_scene','music_scene')]:
        found = re.search(rf'^{prop}=(".*")$', src, re.M)
        if found: node[key] = json.loads(found[1])
    found = re.search(r'^actors=Array\[String\]\((\[.*\])\)',src,re.M)
    if found: node['actors'] = json.loads(found[1])
    found = re.search(r'^full_cg=(true|false)',src,re.M)
    if found: node['cg'] = found[1] == 'true'

def direction(node, directives):
    moods = {}
    matches = {}
    for item in directives:
        if item['scene_id'] != node['id']: continue
        found = [i for i, row in enumerate(node.get('lines', [])) if item['text_contains'] in row['text']]
        if len(found) != 1: raise ValueError(f'Non-unique director cue: {item}')
        matches[found[0]] = item
    for i, row in enumerate(node.get('lines', [])):
        if i in matches:
            cue = matches[i]
            moods[row['speaker']] = cue['tone']
            if cue.get('motion'): row['motion'] = cue['motion']
        row['actor_tones'] = moods.copy()
        row['tone'] = moods.get(row.get('speaker', ''), 'calm')

def save_resource(node):
    rows = node.get('lines',[])
    q = lambda x: json.dumps(x, ensure_ascii=False)
    out = [f'[gd_resource type="Resource" script_class="CasChapterSceneVisual" load_steps={len(rows)+3} format=3]',
      '[ext_resource type="Script" path="res://scripts/chapter_scene_resource.gd" id="1_scene"]',
      '[ext_resource type="Script" path="res://scripts/chapter_line_resource.gd" id="2_line"]']
    for i,row in enumerate(rows):
        out += [f'[sub_resource type="Resource" id="Line_{i}"]','script=ExtResource("2_line")',f'speaker={q(row.get("speaker",""))}',f'speaker_name={q(row.get("name",""))}',f'text={q(row["text"])}',f'tone={q(row.get("tone","calm"))}',f'shot={q(row.get("shot","wide"))}',f'motion={q(row.get("motion","none"))}',f'text_effect={q(row.get("text_effect","none"))}',f'characters_per_second={float(row.get("characters_per_second",34))}',f'caption={q(row.get("caption",""))}',f'actors=Array[String]({q(row.get("actors",[]))})',f'actor_tones={q(row.get("actor_tones",{}))}']
    out += ['[resource]','script=ExtResource("1_scene")',f'scene_id={q(node["id"])}',f'background={q(node.get("background_asset","res://assets/story/chapter1/deck-storm-v1.png"))}',f'full_cg={str(node.get("cg",False)).lower()}',f'actors=Array[String]({q(node.get("actors",[]))})',f'music_scene={q(node.get("music_scene","harbor"))}',f'location={q(node.get("location",""))}', 'lines=Array[ExtResource("2_line")](['+', '.join(f'SubResource("Line_{i}")' for i in range(len(rows)))+'])']
    (DATA/'chapter-scenes'/f'{node["id"]}.tres').write_text('\n\n'.join(out)+'\n',encoding='utf-8')

def compile_chapter(chapter, filename):
    path=DATA/f'{filename}.json'; data=json.loads(path.read_text('utf-8-sig'))
    # Re-running compiles idempotently: retain existing authored nodes and reset links below.
    byid={n['id']:n for n in data['scenes']}
    original=[n for n in data['scenes'] if not n.get('longform_extra',False)]
    for n in original: visual_from_resource(n)
    text=authored(chapter)
    for node in original:
        if node['id'] in text: node['lines']=text[node['id']]
        if node['kind']=='battle' and 'goal_type' not in node:
            node['goal_type']={'c1-breakout':'reach','c1-salvage':'archive','c1-boss':'boss'}.get(node.get('stage'),'reach')
    for anchor, *chain in INSERTIONS[chapter]:
        old=byid[anchor]
        following=old.get('longform_original_next',old.get('next',''))
        old['longform_original_next']=following
        present=[]
        for id in chain:
            if id in ALIASES:
                native,title,objective=ALIASES[id]
                base=next((n for n in original if n.get('stage')==native),None)
                if base is None: continue
                node={k:v for k,v in base.items() if k not in ['id','next','stage','lines','longform_original_next']}
                node.update(id=id,stage=id,native_stage=native,seed=71000+list(ALIASES).index(id)*137,title=title,objective=objective,rewards={})
            elif id in text:
                node={'id':id,'title':TITLES.get(id,id),'kind':'dialogue','background_asset':old.get('background_asset','res://assets/story/chapter1/deck-storm-v1.png'),'cg':False,'actors':old.get('actors',['fletcher','drayton','perkins'])[:3],'music_scene':old.get('music_scene','harbor'),'location':old.get('location','第五驱逐小队 · 航海日志'),'lines':text[id]}
            else: continue
            node['longform_extra']=True; byid[id]=node; present.append(node)
        if present:
            old['next']=present[0]['id']
            for i,node in enumerate(present): node['next']=present[i+1]['id'] if i+1<len(present) else following
            place=original.index(old)+1
            original[place:place]=present
    # Additional authored investigation passages follow their declared existing anchor.
    for id, lines in text.items():
        if id not in byid: raise ValueError(f'Unconnected authored scene: {id}')
    data['scenes']=original
    if chapter=='chapter-02':
        byid['c2-two-copies']['choices']=[{'id':'seal','text':'先封存有疑点的板，交接后再核。'},{'id':'test','text':'能否先用小电源测试一致的端口？'}]
        byid['c2-two-copies']['choice_next']={'seal':'c2-response-seal','test':'c2-response-plug'}
        byid['c2-response-seal']['next']='c2-guest'
        byid['c2-response-plug']['next']='c2-guest'
    data['narrative_revision']='cas-longform-dialogue-2026-11-12'
    directives_path=DATA/'story-longform/direction-overrides.json'
    directives=json.loads(directives_path.read_text('utf-8-sig'))['chapters'].get(chapter,[]) if directives_path.exists() else []
    for n in original:
        if n['kind']=='dialogue':
            if n['id'] in SCENE_LOCATIONS:n['location']=SCENE_LOCATIONS[n['id']]
            if not n.get('cg',False):
                n['background_asset']=SCENE_BACKDROPS.get(n['id'],PORTRAIT_CG_BACKDROPS.get(n.get('background_asset'),n.get('background_asset')))
            assign_cast(n, data.get('cast', {}))
            direction(n, directives)
            # Short paragraphs retain visual-novel readability; no forced dwell or slow reveal.
            for line in n.get('lines',[]): line['characters_per_second']=34.0
        save_resource(n)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    chars=sum(len(re.findall(r'[\u4e00-\u9fff]',l['text'])) for n in original for l in n.get('lines',[]))
    return {'chapter':chapter,'han_characters':chars,'lines':sum(len(n.get('lines',[])) for n in original),'nodes':len(original),'battles':len([n for n in original if n['kind']=='battle'])}

if __name__=='__main__':
    for chapter, filename in [('chapter-01','chapter-one'),('chapter-02','chapter-two'),('chapter-03','chapter-three')]:
        print(json.dumps(compile_chapter(chapter,filename),ensure_ascii=False))
