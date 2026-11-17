"""Inspect every real route, asset anchor and unique protocol transition in v2."""
import hashlib
import json
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
DOC=Path(__file__).resolve().parent
DATA=ROOT/'godot/data/story-canon-v2'
ALLOWED={'native_battle','harbor_tour','arena_ranked','arena_3v3','growth',
         'salvage_tutorial','littoral_sea','littoral_landing','littoral_combined',
         'home_build','home_garrison','fixed_recruit','island_defense'}
CHAPTERS={p.stem:json.loads(p.read_text(encoding='utf-8')) for p in sorted(DATA.glob('chapter-*.json'))}
assert set(CHAPTERS)=={'chapter-01','chapter-02','chapter-03'}
assert len({d['version'] for d in CHAPTERS.values()})==3

def successors(n):
    if n['kind']=='complete':return []
    if n.get('choices'):return list(n['choice_next'].values())
    if n.get('success_next'):return [n['success_next'],n['failure_next']]
    return [n['next']]

def routes(d):
    by={n['id']:n for n in d['scenes']}
    def walk(ident,chain,decisions):
        assert ident not in chain,('cycle',ident)
        n=by[ident];chain=chain+[ident]
        if n['kind']=='complete':
            yield chain,decisions
            return
        for nxt in successors(n):
            chosen=dict(decisions)
            if n.get('choices'):
                value=next(k for k,v in n['choice_next'].items() if v==nxt)
                chosen[ident]=value
            yield from walk(nxt,chain,chosen)
    return list(walk(d['entry'],[],{}))

report={'scope':'Only static narrative/data integrity; no claim of real-play duration or engine completion.',
        'chapters':[],'asset_anchors':[],'protocol_paths':[],'warnings':[]}
for chapter_id,d in CHAPTERS.items():
    assert d['content_version']=='story-canon-v2'
    assert not d['cast']['shadow'].get('ship_id')
    assert d['cast']['shadow']['hidden_identity']
    by={n['id']:n for n in d['scenes']}
    assert len(by)==len(d['scenes'])
    assert d['entry'] in by
    for n in d['scenes']:
        for nxt in successors(n):assert nxt in by,(n['id'],nxt)
        if n.get('choices'):
            choice_ids=[c['id'] for c in n['choices']]
            assert len(choice_ids)==len(set(choice_ids))
            assert set(choice_ids)==set(n['choice_next'])
        if n['kind']=='action':
            assert n['action_type'] in ALLOWED,(n['id'],n['action_type'])
            assert n.get('objective') and n['objectives']
            assert n['action']['requires_real_completion']
            if n['action_type'] in ['native_battle','salvage_tutorial']:
                assert n.get('mission_profile')=='canon-missions-v3'
                assert n.get('teaching_contract')=='native-tutorialSteps-v1'
            assert not re.search('原核|v4|未实现|模板|不冒称|协议保管事件',n['objective']),n['id']
        for actor in n.get('actors',[]):assert actor in d['cast'],(n['id'],actor)
        anchors=[n.get('background_asset',''),n.get('cg_asset','')]
        for line in n.get('lines',[]):
            assert not line['speaker'] or line['speaker'] in d['cast']
            assert line['text'].strip()
            for actor in line.get('actors',[]):assert actor in d['cast']
            anchors.append(line.get('cg_asset',''))
            if line.get('if_choice'):
                c=line['if_choice'];source=CHAPTERS[c['chapter']]
                source_node=next(x for x in source['scenes'] if x['id']==c['node'])
                assert c['value'] in source_node['choice_next']
        for path in filter(None,anchors):
            assert path.startswith('res://')
            assert (ROOT/'godot'/path[6:]).is_file(),(n['id'],path)
            report['asset_anchors'].append({'chapter':chapter_id,'node':n['id'],'asset':path})
    paths=routes(d)
    seen=set(x for p,_ in paths for x in p)
    assert seen==set(by),('unreachable',set(by)-seen)
    counts=[]
    for path,_ in paths:
        counts.append(sum(len(re.findall(r'[\u4e00-\u9fff]',l['text'])) for ident in path for l in by[ident].get('lines',[])))
    report['chapters'].append({'id':chapter_id,'nodes':len(by),'routes':len(paths),
        'all_nodes_reachable':True,'all_routes_complete':True,
        'route_chinese_characters':[min(counts),max(counts)],
        'authored_chinese_characters':d['authored_chinese_characters'],
        'actions':sum(n['kind']=='action' for n in by.values()),
        'optional_actions':[n['id'] for n in by.values() if n.get('optional')],
        'sha256':hashlib.sha256((DATA/(chapter_id+'.json')).read_bytes()).hexdigest()})

c1=CHAPTERS['chapter-01'];by={n['id']:n for n in c1['scenes']}
for path,decisions in routes(c1):
    custody='undiscovered';events=[]
    for ident in path:
        n=by[ident]
        if n.get('action_type')=='salvage_tutorial':
            assert custody=='undiscovered';custody='recovered';events.append('recovered')
        if n.get('protocol_event')=='confiscate':
            assert custody=='recovered';custody='alliance';events.append('alliance')
        if n.get('protocol_event')=='return':
            assert custody=='alliance';custody='returned';events.append('returned')
        if n.get('action_type')=='fixed_recruit':
            assert custody=='returned';custody='bound';events.append('bound')
    assert events==['recovered','alliance','returned','bound']
    assert path.index('v2c1-island-deed')<path.index('v2c1-fixed-recruit')
    report['protocol_paths'].append({'choices':decisions,'events':events,'bound_once':True})
for id in ['chapter-02','chapter-03']:
    assert not any(n.get('protocol_event') or n.get('action_type')=='fixed_recruit' for n in CHAPTERS[id]['scenes'])

# The new form/crew illustrations depict Missouri herself, so their first
# display must follow her name reveal rather than spoil the early harbor tour.
illustrations={'res://assets/story/canon-v2/ship-form.png','res://assets/story/canon-v2/one-mind-crew.png'}
rent=by['v2c1-rent']
reveal_index=next(i for i,l in enumerate(rent['lines']) if l['speaker']=='missouri' and l['text'].startswith('密苏里。'))
for n in c1['scenes']:
    for i,line in enumerate(n.get('lines',[])):
        if line.get('cg_asset') in illustrations:
            assert n['id']=='v2c1-rent' and i>reveal_index
assert illustrations.issubset({l.get('cg_asset') for l in rent['lines']})
tactical=next(n for n in CHAPTERS['chapter-03']['scenes'] if n['id']=='v2c3-many-hands')
assert tactical['background_asset']=='res://assets/story/canon-v2/one-mind-tactical.png'
report['new_illustration_bindings']={'missouri_form_and_crew':'v2c1-rent (after personal name reveal)',
    'tactical_identity':'MCP-011 / v2c3-many-hands','early_harbor_spoiler':False,
    'actions_or_rewards_added':False}

opening=CHAPTERS['chapter-01']['scenes'][0]
assert opening['id']==CHAPTERS['chapter-01']['entry']=='v2c1-drifting'
assert opening['perspective']=='first_person'
warning=[l for l in opening['lines'] if l['speaker']=='warning_voice']
assert len(warning)>=3 and all(l.get('text_effect')=='echo' for l in warning)
assert sum('不要打开星门' in l['text'] for l in warning)>=2
assert any(l['speaker']=='jintsu' and '抓住' in l['text'] for l in opening['lines'])
assert CHAPTERS['chapter-01']['cast']['warning_voice']['name']=='……'
for chapter_id,node_id in [('chapter-01','v2c1-old-sky'),('chapter-02','v2c2-different-tides'),('chapter-03','v2c3-closed-channel')]:
    scene=next(n for n in CHAPTERS[chapter_id]['scenes'] if n['id']==node_id)
    assert scene.get('lore_status')
    assert '星门' in ''.join(l['text'] for l in scene['lines'])
report['opening_and_lore']={'first_person_entry':opening['id'],'jintsu_rescue':True,'warning_voice_distinct_from_fsm':True,
    'chapters_have_separate_lore_clues':True,'claims_endgame_explanation_confirmed':False,
    'new_mission_profile':'canon-missions-v3','actual_cargo_place_required':True}
report['warnings']=[
 'Four-CA reinforcement, CA-class monster and Missouri fire are cutscene scope, not a newly implemented native battle.',
 'New launches explicitly request canon-missions-v3; native task tests, escort behavior and current-mechanic completion are audited separately by the engine integration owner. Existing saved older missions keep their snapshot/version.',
 'Reader word counts include all alternate branches; route ranges count a single path and include conditional callback lines before filtering.',
 'No real elapsed one-hour claim. Runtime and native receipt tests are tracked separately by the integration owner.'
]
(DOC/'narrative-integrity-receipt.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'ok':True,'chapters':report['chapters'],'protocol_paths':len(report['protocol_paths'])},ensure_ascii=True))
