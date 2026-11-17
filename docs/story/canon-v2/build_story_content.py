"""Authoring source for the requested separate canon-v2 campaign. No v1 edits."""
import json, re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
DATA=ROOT/'godot/data/story-canon-v2'
DOC=ROOT/'docs/story/canon-v2'
CAST={
 'jintsu':{'name':'神通','ship_id':'IBS-U-IJN-JINTSU-I'},
 'fletcher':{'name':'弗莱彻','ship_id':'IBS-U-USN-FLETCHER'},
 'perkins':{'name':'帕金斯','ship_id':'IBS-U-USN-PERKINS'},
 'maury':{'name':'莫里','ship_id':'IBS-U-USN-MAURY'},
 'drayton':{'name':'德雷顿','ship_id':'IBS-U-USN-DRAYTON'},
 'lamson':{'name':'拉姆森','ship_id':'IBS-U-USN-LAMSON'},
 'missouri':{'name':'密苏里','ship_id':'IBS-U-USN-ERMA-MISSOURI','portrait':'res://assets/story/canon-v2/missouri-portrait.png','canon_role':'白毛龙娘、懒散傲娇成年御姐、隐居守家者'},
 'shinano':{'name':'信浓','ship_id':'IBS-U-IJN-ERMA-SHINANO','canon_role':'架空战列舰、守护者联盟高位担保人'},
 'shadow':{'name':'未知战列舰','portrait':'res://assets/story/canon-v2/shinano-hologram.png','silhouette':True,'hidden_identity':True,'canon_identity':'shinano'},
 'hologram':{'name':'远端通讯','portrait':'res://assets/story/canon-v2/shinano-hologram.png','silhouette':True,'hidden_identity':True,'canon_identity':'shinano'},
 'player':{'name':'你','portrait':''},
 'fsm_ai':{'name':'状态机AI','portrait':''},
 'warning_voice':{'name':'……','portrait':'','identity_status':'未核实的第一人称幻听，不与状态机AI合并'},
 'ahe':{'name':'阿禾','portrait':'','role':'受庇护人类、修理学徒'},
 'judge':{'name':'审查官','portrait':''},
 'liaison':{'name':'联盟联络官','portrait':''},
 'archive':{'name':'档案管理员','portrait':''},
 'mcp034':{'name':'礁刃','unit_id':'MCP-034','role':'第34海军派遣团，单一女性人格'},
 'mcp001':{'name':'云隼','unit_id':'MCP-001','role':'第1空中特勤旅，单一女性人格'},
 'mcp011':{'name':'灯鲨','unit_id':'MCP-011','role':'第11夜航突击队，单一女性人格'},
 'cultist':{'name':'白塔播音','portrait':''},
 'engineer':{'name':'桥守','portrait':''},
 'elder':{'name':'守航老舰娘','portrait':''},
}
CODE={'S':'jintsu','F':'fletcher','K':'perkins','M':'maury','D':'drayton','L':'lamson','P':'player','A':'fsm_ai','W':'warning_voice','H':'ahe','J':'judge','E':'liaison','R':'archive','X':'shadow','V':'hologram','B':'missouri','Q':'mcp034','U':'mcp001','T':'mcp011','C':'cultist','G':'engineer','O':'elder','Z':'shinano'}
CHAPTERS=[]
def chapter(number,title,theme,minutes):
    d={'id':f'chapter-{number:02d}','version':f'chapter-{number:02d}-canon-v2','content_version':'story-canon-v2','title':title,'fictional':True,'entry':'','cast':CAST,'theme':theme,'design_minutes':minutes,'timing_claim':'设计预算，未冒称整章一小时实测；不含加载和强制慢字','scenes':[],'guide':[]}
    CHAPTERS.append(d);return d
def lines(text,actors=None):
    out=[]
    for row in text.strip().splitlines():
        if not row.strip():continue
        who,body=row.split('|',1);tone='calm'
        if ':' in who:who,tone=who.split(':',1)
        if who not in CODE and who!='N':raise ValueError('Unknown speaker code: '+who)
        speaker=CODE.get(who,'')
        item={'speaker':speaker,'text':body.strip(),'tone':tone,'characters_per_second':34.0,'shot':'wide','actors':actors or [],'actor_tones':{speaker:tone} if speaker else {}}
        if speaker=='player':item['name']='你'
        out.append(item)
    return out
def scene(d,id,title,text,bg='harbor',actors=None,**extra):
    ident=f'v2c{int(d["id"][-2:])}-{id}'
    n={'id':ident,'kind':'dialogue','title':title,'background':bg,'lines':lines(text,actors),'actors':actors or [],'next':''}
    n.update(extra)
    if not d['entry']:d['entry']=ident
    if d['scenes'] and not d['scenes'][-1].get('next'):d['scenes'][-1]['next']=ident
    d['scenes'].append(n);return n
def action(d,id,title,kind,objectives,minutes=3,optional=False,native_stage='',**extra):
    n=scene(d,id,title,'N|'+objectives[0] if objectives else 'N|准备行动。',objectives=objectives,design_minutes=minutes)
    n.update(kind='action',action_type=kind,objective='；'.join(objectives),optional=optional,action={'type':kind,'objectives':objectives,'native_stage':native_stage,'requires_real_completion':True})
    if kind in ['native_battle','salvage_tutorial']:
        n.update(mission_profile='canon-missions-v3',teaching_contract='native-tutorialSteps-v1')
    if native_stage:n['native_stage']=native_stage
    n.update(extra);return n
def end(d,text):
    scene(d,'complete','本章终',text,kind='complete')
def insert_dialogue(d,after,id,title,text,bg='harbor',actors=None,**extra):
    """Place a fully authored scene without changing any other scene's identity."""
    tail=d['scenes'][-1];tail_next=tail.get('next','')
    n=scene(d,id,title,text,bg,actors,**extra)
    d['scenes'].pop();tail['next']=tail_next
    index=next(i for i,row in enumerate(d['scenes']) if row['id']==after)
    n['next']=d['scenes'][index]['next'];d['scenes'][index]['next']=n['id']
    d['scenes'].insert(index+1,n)
    return n
def finish():
    for d in CHAPTERS:
        nodes=d['scenes'];by={n['id']:n for n in nodes};ids=set(by)
        assert len(ids)==len(nodes)
        for n in nodes:
            assert not n.get('next') or n['next'] in ids,(n['id'],n.get('next'))
            for p in n.get('choice_next',{}).values():assert p in ids
        chars=sum(len(re.findall(r'[\u4e00-\u9fff]',l['text'])) for n in nodes for l in n.get('lines',[]))
        d['authored_chinese_characters']=chars
        (DATA/(d['id']+'.json')).write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
        md=[f'# {d["id"]}《{d["title"]}》',f'正史版本：{d["version"]}。主题：{d["theme"]}。',f'正文汉字 {chars}；{d["timing_claim"]}。','']
        for n in nodes:
            md.extend([f'## {n["id"]}｜{n["title"]}',f'类型：{n["kind"]}；场景：{n.get("background","")}；同框：'+ '、'.join(CAST.get(a,{}).get('name',a) for a in n.get('actors',[])), ''])
            if n.get('background_asset'):md.extend(['场景图：'+n['background_asset'],''])
            if n['kind']=='action':md.extend(['实际玩法：'+n['action_type'],'验收：'+'；'.join(n.get('objectives',[])),''])
            current_cg=n.get('background_asset','')
            for l in n.get('lines',[]):
                next_cg=l.get('cg_asset',n.get('background_asset',''))
                if next_cg!=current_cg:
                    md.append('〔画面切换：'+next_cg+'〕')
                    current_cg=next_cg
                md.append(('旁白' if not l['speaker'] else CAST[l['speaker']]['name'])+'：'+l['text'])
            if n.get('choices'):
                md.append('')
                for c in n['choices']:md.append('选择 '+c['id']+'：'+c['text']+' → '+n.get('choice_next',{}).get(c['id'],'未绑定'))
            if n.get('protocol_event'):md.append('整段读完后的协议事件：'+n['protocol_event'])
            if n.get('success_next'):md.append('真实胜利 → '+n['success_next']+'；真实失败 → '+n.get('failure_next',''))
            if n.get('implementation_boundary'):md.append('实现边界：'+n['implementation_boundary'])
            md.extend(['',f'下一节点：{n.get("next","")}',''])
        (DOC/(d['id']+'-剧本.md')).write_text('\n'.join(md),encoding='utf-8')
    summary=[{'id':d['id'],'title':d['title'],'nodes':len(d['scenes']),'lines':sum(len(n.get('lines',[])) for n in d['scenes']),'chinese_characters':d['authored_chinese_characters'],'design_minutes':d['design_minutes']} for d in CHAPTERS]
    (DOC/'authoring-audit.json').write_text(json.dumps({'chapters':summary,'original_v1_files_written':False,'playtime_measured':False},ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(summary,ensure_ascii=False))

