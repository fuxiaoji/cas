"""Read-only CAS source catalogue; runtime readiness is an explicit separate gate."""
from pathlib import Path
import json, hashlib

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'data/carrier/pacific-source-v1.json'
US='American_Fleets_2012_Standard.pdf'
JP='The_Emperor_s_Fleet.pdf'
def source(book,page,printed):
    p=ROOT/'CAS带翻译/CAS带翻译/船表'/book
    return dict(book=book,pdf_page=page,printed_page=printed,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),verification='page_image_reviewed')
def hull(key,name,cls,book,page,printed,dp,speed,armor,damage,speeds,**kw):
    return dict(id=key,name=name,ship_class=cls,source=source(book,page,printed),dp=dp,max_knots=speed,armor=armor,damage_speed=[dict(damage=d,knots=s) for d,s in zip(damage,speeds)],readiness='source_only',blockers=['完整炮表/炮座/雷达/特例消费者未逐项验收；不开放历史或账户出战'],**kw)
ships=[]
for key,name in [('YORKTOWN','约克城'),('HORNET','大黄蜂')]:
 ships.append(hull(f'CAS-H-USN-{key}-1942',name,'Yorktown',US,12,'A-9',628,32,[8,3,135],[0,157,314,471,565,628],[32,24,16,8,0,0],kind='CV',era='1942 early',gun_standard=3,weapons=['PW/SW/2P/2S/PA/SA(1)8 Mk24 5in/38'],rated_aircraft=90,typical_airgroup={'fighter':18,'dive_bomber':36,'torpedo_bomber':18},special_rules=['工程重击造成的速度降低加倍'],fitting_caveat='雷达与轻防空按具体舰及日期分别核验，不把Enterprise 1943改装套用'))
ships.append(hull('CAS-H-IJN-ZUIKAKU-1942','瑞鹤','Shokaku',JP,11,'A-8',742,34,[8,6,135],[0,186,371,557,668,742],[34,26,17,8,0,0],kind='CV',era='1942-08',gun_standard=4,weapons=['P/S(2)8 Type 89 12.7cm/40'],typical_airgroup={'A6M2':26,'D3A2':27,'B5N2':18},ordnance={'No80_800kg':90,'No25_250kg':306,'No6_60kg':540,'Type95_DC_Mod1':6,'Type91_torpedo':45},fitting_caveat='八月翔鹤装Type21，瑞鹤晚于此；不能为瑞鹤猜定雷达实装日'))
for key,name in [('JUNYO','隼鹰'),('HIYO','飞鹰')]:
 ships.append(hull(f'CAS-H-IJN-{key}-1942',name,'Junyo',JP,11,'A-8',463,25,[0,0,90],[0,116,232,347,417,463],[25,19,13,6,0,0],kind='CV',era='1942-05 class fit',gun_standard=4,weapons=['P/S(2)6 Type 89 12.7cm/40'],airgroup_by_date={'1942-05':{'A6M':12,'D3A':18,'B5N':18},'1942-10':{'A6M':18,'D3A':18,'B5N':9}},special_rules=['商船改装特殊损伤修正 -35%'],fitting_caveat='隼鹰七月、飞鹰八月装Type21；本表五月空群是级卡条目，不声称飞鹰当月已服役'))
for key,name,dp,speed,dam,spd,gun,year,displ in [
 ('LIBERTY','自由轮',130,11,[0,33,65,98,117,130],[11,8,6,3,0,0],'Mk30',1941,{'value':7100,'unit':'grt'}),
 ('VICTORY','胜利轮',125,17,[0,31,63,94,113,125],[17,13,9,4,0,0],'Mk37',1944,{'value':4420,'unit':'ltshp'})]:
 ships.append(hull(f'CAS-H-USN-{key}-{year}',name,key.title()+' Ship',US,44,'A-41',dp,speed,[0],[*dam],[*spd],kind='AK',identity_scope='class_representative',displacement=displ,cargo_holds=5,gun_standard=4,weapons=[f'A(1)1 {gun} 5in/38','F(1)1 Mk22 3in/50'],area_aa=0.6,light_aa=2.0,special_rules=['民船结构特殊损伤修正 -50%','单轴：所有工程重击速度损失加倍'],cargo_capacity_tonnes=None))
def plane(id,name,book,page,printed,role,dv,maneuver,ceiling,range_nm,fuel,payload,speeds,loadouts,**extra):
 return dict(id=id,name=name,source=source(book,page,printed),role=role,damage_value=dv,maneuver_rating=maneuver,ceiling_m=ceiling,cruise_range_nm=range_nm,internal_fuel_kg=fuel,payload_kg=payload,speed_knots=speeds,loadout_alternatives=loadouts,readiness='source_only',blockers=['高度/载荷/油门/空战/航空武器原版裁决尚未完整消费；近场玩法参数不可当作本表值'],**extra)
planes=[
 plane('CAS-A-USN-F4F4','F4F-4 Wildcat',US,76,'B-20','fighter',14,[2.5,2],10363,798,413,300,{'low':[135,240],'medium':[160,275],'high':[160,250]},['2×100lb bomb','2×42USG or 58USG drop tank'],off_guns='6 M2 .50cal (1.8)',in_service='1941-12..1943'),
 plane('CAS-A-USN-SBD3','SBD-3 Dauntless',US,102,'B-46','dive_bomber',14,[1.5,1],8256,1260,802,726,{'low':[120,210],'medium':[135,220],'high':[None,210]},['2×100lb wing bombs + 1×500lb or 1000lb centerline','1×1600lb bomb','2×325lb depth charge'],off_guns='2 M2 .50cal (0.6)',def_guns='2 Browning .30cal (0.3)',in_service='1941-03'),
 plane('CAS-A-USN-TBD1','TBD-1 Devastator',US,104,'B-48','torpedo_bomber',14,[1.5,1],6000,650,534,961,{'all':[111,180]},['1 Mk7 or Mk13 aerial torpedo','12×100lb bombs','2×500lb or 1000lb bombs or 325lb depth charges'],in_service='1937-10..1942-06',special_rules=['无自封油箱/装甲；中途岛后退出作战服役']),
 plane('CAS-A-USN-TBF1','TBF/TBM-1 Avenger',US,104,'B-48','torpedo_bomber',17,[1.5,1],6828,1090,864,960,{'low':[110,218],'medium':[126,236]},['1 Mk13 or Mk18 torpedo internally','4×500lb or 2×1000lb or 1×1600lb or 1×2000lb bomb internally','275USG internal fuel tank','12×100lb GP bombs','4×350lb Mk54 depth charges','2 Mk24 torpedoes'],in_service='1942-01',special_rules=['1942后期量产机可装ASB雷达，不按所有早期机默认配置']),
 plane('CAS-A-IJN-A6M2-21','A6M2 Model21 Zero',JP,72,'B-1','fighter',10,[3.5,2.5],10300,1010,414,320,{'low':[117,250],'medium':[130,288],'high':[None,251]},['2×30kg or 60kg bombs + centerline 330L drop tank','8×10kg or 2×60kg rockets'],off_guns='2 Type97 7.7mm + 2 Type99 20mm (1.5)',in_service='1941-04',limiting_dive_knots=336),
 plane('CAS-A-IJN-D3A1','D3A1 Val11',JP,77,'B-6','dive_bomber',11,[2,1],9300,795,722,370,{'low':[100,200],'medium':[110,226],'high':[None,244]},['1 centerline 250kg bomb + 1×30kg under each wing'],off_guns='2 Type97 7.7mm (0.4)',def_guns='1 Type92 7.7mm (0.1)',in_service='1940-01'),
 plane('CAS-A-IJN-B5N2','B5N2 Kate',JP,75,'B-4','torpedo_bomber',11,[1.5,.5],8260,1075,787,800,{'low':[100,199],'medium':[100,204],'high':[None,204]},['6×60kg bombs','1×800kg bomb or Type91 torpedo','3×250kg bombs'],def_guns='1 Type92 7.7mm flex (0.1)',in_service='1939-12')]
catalog=dict(version='cas-pacific-source-v1',historical_campaign_available=False,ships=ships,aircraft=planes,units={'speed':'knots','range':'nautical miles','armor':'printed CAS rating'},global_blockers=['原版完整舰载航空未实现；禁止静默启用source_only','载机额定数不等于典型空群，巡航总航程不等于作战半径','原书Sinks用knots=0并以最终dp阈值表示；不赋予沉舰航行能力'])
OUT.parent.mkdir(parents=True,exist_ok=True);OUT.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'{len(ships)} hulls, {len(planes)} aircraft: {OUT}')
