"""Lay out actual Godot previews as contact sheets and a local review booklet."""
from pathlib import Path
import json
import shutil
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'artifacts/home-design-20261116'
OUT = ROOT / 'output/home-design-20261116'
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'assets').mkdir(exist_ok=True)
FONT = 'C:/Windows/Fonts/msyh.ttc'
BOLD = 'C:/Windows/Fonts/msyhbd.ttc'
def font(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)

entries = json.loads((SOURCE / 'building-previews.json').read_text(encoding='utf-8'))
descriptions = [
    '岛权管理 · 灯塔与港务楼', '回收浮材 · 分拣台与吊架', '贸易农产 · 菜畦与育苗棚',
    '定向加工 · 多跨采光顶', '容量与保护 · 装卸台和仓门', '能源生产 · 岸上机房与储能',
    '分连驻防 · 宿舍与训练场', '身体恢复 · 医疗与整备入口', '遗迹加工 · 采光顶与终端',
    '反登陆装甲 · 炮口与射界', '限制空输 · 炮组与雷达', '步兵掩护 · 射孔与侧后弱点'
]
for index, title in enumerate(['安居与生产', '整备与防御']):
    sheet = Image.new('RGB', (1800, 1140), '#f4f0e5')
    draw = ImageDraw.Draw(sheet)
    draw.text((60, 38), '归航 / 家园建筑样板', font=font(24), fill='#52706b')
    draw.text((60, 80), f'0{index+1}  {title}', font=font(43, True), fill='#173f42')
    draw.text((60, 145), '延续已认可的海岸风格 · 真实 Godot 三维模型预览', font=font(23), fill='#62756c')
    for slot in range(6):
        i = index*6+slot
        item = entries[i]
        x = 60 + (slot%3)*570
        y = 207 + (slot//3)*420
        img_path = SOURCE / 'buildings' / item['preview']
        im = Image.open(img_path).convert('RGB')
        # Crop the camera's empty margin, retaining the complete geometric footprint.
        im = im.crop((int(im.width*.13), int(im.height*.16), int(im.width*.93), int(im.height*.90)))
        im.thumbnail((546, 310), Image.Resampling.LANCZOS)
        draw.rounded_rectangle((x, y, x+546, y+389), 13, fill='#e9e8d9')
        sheet.paste(im, (x+(546-im.width)//2, y+(310-im.height)//2))
        draw.text((x+20,y+311),item['name'],font=font(27,True),fill='#204b49')
        draw.text((x+20,y+352),descriptions[i],font=font(18),fill='#586e63')
        shutil.copy2(img_path, OUT/'assets'/item['preview'])
    draw.text((60,1090),'建筑样式与功能关系预览；新经济、占地与防御规则仍需后续接入。',font=font(20),fill='#657369')
    sheet.save(OUT/('production-board.png' if index==0 else 'defense-board.png'))

# Small original planning diagram: lines represent design relationships, not an in-game map.
diagram = Image.new('RGB',(1800,550),'#f4f0e5')
d = ImageDraw.Draw(diagram)
d.text((60,35),'家园与出航：一次完整循环',font=font(39,True),fill='#173f42')
steps=[('稳定生产','回收 / 能源 / 农产'),('整备出航','油弹 / 训练 / 维修'),('远征回收','搜打撤 / 岸上任务'),('加工与贸易','仓储 / 配方 / 银币'),('扩建与布防','平地 / 泊位 / 预备队')]
for i,(label,detail) in enumerate(steps):
    x=60+i*347
    d.rounded_rectangle((x,150,x+290,355),20,fill=['#d9e2c3','#d8e4df','#b8d9d4','#ead9ba','#d9cfb6'][i])
    d.text((x+22,183),f'0{i+1}',font=font(24),fill='#59746a')
    d.text((x+22,224),label,font=font(30,True),fill='#204b49')
    d.text((x+22,287),detail,font=font(20),fill='#52695e')
    if i<4:
        d.line((x+300,250,x+335,250),fill='#51756e',width=4)
        d.polygon([(x+335,250),(x+325,242),(x+325,258)],fill='#51756e')
d.text((60,410),'核心取舍：港口与炮位争岸线，工厂与农田争平地，远征与驻防争同一支连队。',font=font(27,True),fill='#204b49')
d.text((60,470),'生产提供保底，行动提供稀缺；被击败后仍保留恢复与再次出航的路。',font=font(23),fill='#657369')
diagram.save(OUT/'home-loop.png')

for p in (SOURCE/'screenshots').glob('*.png'):
    shutil.copy2(p,OUT/'assets'/p.name)

html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>归航 · 家园设计预览</title><style>
*{box-sizing:border-box}body{margin:0;background:#f4f0e5;color:#204b49;font:17px/1.8 "Microsoft YaHei",sans-serif}main{max-width:1200px;margin:auto;padding:52px 24px}h1{font-size:42px;letter-spacing:.06em;line-height:1.3}h2{font-size:28px;margin-top:50px}p{max-width:900px}img{width:100%;height:auto;border-radius:12px;margin:20px 0}a{color:#a35b43}small,.muted{color:#68786b}.tag{display:inline-block;padding:4px 13px;border:1px solid #b4bca8;border-radius:30px}nav{display:flex;gap:20px;flex-wrap:wrap}ul{padding-left:24px}strong{color:#a35b43}.grid{display:grid;grid-template-columns:1fr 1fr;gap:25px}@media(max-width:700px){h1{font-size:32px}.grid{display:block}}
</style><main><span class="tag">2026.11.16 · 第一版大纲与实际三维样板</span><h1>一个能生活，也能守住的海上据点。</h1><p>沿用已认可的海岸风格：碧青浅海、暖沙、浅墙红瓦、青灰机械。把回收、生产、远征与防线放在同一座程序岛上，让地段、物流和有限驻军产生取舍。</p><nav><a href="#models">建筑风格</a><a href="#economy">经济循环</a><a href="#defense">防御与恢复</a><a href="../../docs/design/home-building-economy-defense-outline-20261116.md">完整大纲</a></nav>
<h2 id="models">先看建筑，再看数字。</h2><p>以下来自实际Godot模型渲染，可继续在编辑器里调整。民用、工业、整备与军事设施通过轮廓和设备辨识用途，生产与防御规则仍为后续实施设计。</p><img src="production-board.png" alt="六类生产建筑实际三维样板"><img src="defense-board.png" alt="六类整备和防御建筑实际三维样板">
<h2>在同一片岛上组合</h2><p>展示区为比较样式而排列；正式经营按真实地形、通路和玩家自由布局，不要求照抄方格。建筑升级增加功能构件，岛级开放后方地区，而非重抽岛形。</p><img src="assets/home-district.png" alt="家园建筑展示区实际运行截图">
<details><summary>查看修正后的树木、登陆艇和装甲车辆实景</summary><img src="assets/vehicle-shore.png" alt="真实三维登陆艇、两栖装甲车和坦克"><img src="assets/nature-detail.png" alt="新阔叶树与地形"><p>只有人物和步兵使用二维动作。树木与坦克采用许可明确的免费模型，军用登陆艇与两栖装甲车补用Blender自建；这三件是美术巡航样车，真实登卸载与战斗仍按后续阶段接入。</p></details>
<h2 id="economy">基础收益保底，出航带回稀缺。</h2><img src="home-loop.png" alt="生产整备远征贸易建设循环"><p>复用浮材、合金、能源与银币；现有岛屿补给保留独立账本。农产、维修件和养成材料按真实物品流转，不增加一排常驻货币。工坊选择产线，支持队列与统一收取；升级、受损或换配方之前先结清旧生产。</p>
<h2 id="defense">防线有方向，也有侧路。</h2><div class="grid"><div><p><strong>海上：</strong>驻舰真实起锚，争夺制海权。</p><p><strong>滩头：</strong>机枪护反甲，重艇需展开，两栖不能爬崖，空输面临防空。</p><p><strong>纵深：</strong>道路、高地、战壕和真实有限预备队形成反击。</p></div><div><p>先做本地人机岛、主动防御战与无损演习。只暴露登记的有限库存，元词、角色、等级和已到账钱包受保护。失败保留恢复底线；演习和观看录像不扣真实资源或重复发奖。</p></div></div>
<h2>操作围绕拖动</h2><p>从图卡拖建筑到岛上，看到占地、入口和道路，旋转并确认；取消不扣费。只有建造时显示网格，只有布防时显示射界。教学从建仓库、收取、生产订单，过渡到放两种互补工事和分连驻防，最后打一次无损演习。</p>
<p class="muted">边界：本次为独立美术样区和设计交付，未替换正式战斗地理、账户或发布核。中端手机仍需真机验收。素材优先免费授权与已有模块，缺项再Blender自建或Tripo，本轮无付费生成。</p></main></html>'''
(OUT/'index.html').write_text(html,encoding='utf-8')
print(json.dumps({'out':str(OUT),'models':len(entries),'boards':3},ensure_ascii=False))
