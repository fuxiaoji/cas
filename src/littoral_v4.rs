//! Explicit fictional combined-arms wrapper: real naval World and independent
//! 10Hz ground/aviation. Historical scenarios never construct this module.
use super::*;
use crate::model::{Data,ShipDef,GunDef,GunMount,DamageSpeed};
use crate::world::World;
use std::sync::OnceLock;
use std::collections::BTreeMap;
#[path="littoral_autonomy.rs"]
mod autonomy;
#[path="carrier_ops.rs"]
mod carrier_ops;
#[path="carrier_ops_v2.rs"]
mod carrier_ops_v2;
#[path="carrier_ops_v3.rs"]
mod carrier_ops_v3;
#[path="island_war.rs"]
pub(crate) mod island_war;
pub(crate) const VERSION:&str="cas-littoral-v4";
pub(crate) const MAP_WIDTH:f64=30000.;
pub(crate) const MAP_HEIGHT:f64=25000.;
pub(crate) const MULTI:&str="multi-company-v1";
pub(crate) fn unit_id(id:&str)->&str{if id.len()==11&&id.starts_with("MCP-")&&&id[7..9]=="-C"&&id[9..].parse::<u32>().is_ok_and(|n|(1..=5).contains(&n)){&id[..7]}else{id}}
pub(crate) fn company_layout(id:&str)->(u32,u32){match unit_id(id){"MCP-001"|"MCP-076"=>(3,8),"MCP-034"=>(5,9),"MCP-009"|"MCP-018"|"MCP-027"|"MCP-041"|"MCP-128"|"MCP-203"=>(2,6),"MCP-022"|"MCP-087"|"MCP-240"=>(3,6),"MCP-011"|"MCP-103"=>(4,8),"MCP-116"|"MCP-167"=>(4,9),_=>(3,8)}}
pub(crate) fn company_personnel_slots(id:&str,kind:&str,count:u32)->E<u32>{Ok(count*match company_category(unit_id(id),kind)?{"armor"=>4,"airmobile"=>3,_=>1})}
pub(crate) fn carrier_personnel_capacity(id:&str,ammo:u32)->E<u32>{Ok(carrier_capacity(id,ammo)?*6)}
fn company_key(id:&str,index:u32)->&'static str{static KEYS:OnceLock<Vec<String>>=OnceLock::new();KEYS.get_or_init(||PROFILES.iter().flat_map(|p|(1..=5).map(move |n|format!("{}-C{n:02}",p.id))).collect()).iter().find(|s|s.as_str()==format!("{}-C{index:02}",unit_id(id))).unwrap().as_str()}
fn company_label(id:&str,index:u32)->String{format!("{}·{}",profile(unit_id(id)).unwrap().name,["一连","二连","三连","四连","五连"][index as usize-1])}
pub(crate) fn company_body_kinds(id:&str,kind:&str)->Vec<&'static str>{super::company_bodies(company_key(unit_id(id),1),kind)}
fn expand_companies(g:&mut Littoral)->E<()>{
    if g.config.company_layout.as_deref()!=Some(MULTI){return Ok(())}
    let mut groups=vec![];
    for base in &g.groups{let(n,count)=company_layout(base.card.id);for i in 1..=n{let mut c=base.clone();c.card.id=company_key(base.card.id,i);c.card.count=count;c.card.slots=company_personnel_slots(base.card.id,c.transport_kind,count)?;groups.push(c);}}
    if groups.len()>25||groups.iter().map(|g|g.card.count).sum::<u32>()>250{return Err("先遣连队/身体预算超限".into())}
    for s in g.ships.iter_mut().filter(|s|s.ally){s.slots=carrier_personnel_capacity(&s.def.id,s.loaded)?;}
    if g.config.mode!="defense"{
        let mut capacities:Vec<_>=g.ships.iter().filter(|s|s.ally).map(|s|s.slots).collect();
        let eligible:Vec<Vec<usize>>=groups.iter().map(|c|g.ships.iter().take(capacities.len()).enumerate().filter(|(_,s)|carrier_eligibility(unit_id(c.card.id),c.transport_kind,&s.def.id).is_ok()).map(|(i,_)|i).collect()).collect();
        let mut order:Vec<_>=(0..groups.len()).collect();order.sort_by_key(|i|(eligible[*i].len(),std::cmp::Reverse(groups[*i].card.slots),*i));
        fn assign(at:usize,order:&[usize],groups:&[Group],eligible:&[Vec<usize>],cap:&mut[u32],out:&mut[usize],steps:&mut u32)->bool{*steps+=1;if *steps>100000{return false}if at==order.len(){return true}let i=order[at];let mut options=eligible[i].clone();options.sort_by_key(|s|(cap[*s],*s));for s in options{if cap[s]<groups[i].card.slots{continue}cap[s]-=groups[i].card.slots;out[i]=s;if assign(at+1,order,groups,eligible,cap,out,steps){return true}cap[s]+=groups[i].card.slots;}false}
        let mut assigned=vec![0;groups.len()];if !assign(0,&order,&groups,&eligible,&mut capacities,&mut assigned,&mut 0){return Err("身体舱位或合法载舰不足：同一先遣连不能拆载".into())}
        for(i,c)in groups.iter_mut().enumerate(){let s=&g.ships[assigned[i]];c.carrier=s.id;c.p=s.p;c.buff_point=s.p;}
    }
    g.bodies.retain(|b|!b.ally);g.groups=groups;
    if g.config.mode=="defense"{for i in 0..g.groups.len(){let base=g.groups[i].p;let p=base+P{x:(i%5)as f64*110.-220.,y:(i/5)as f64*110.-220.};if g.walkable(p,true){g.groups[i].p=p;}g.spawn_group(i);}}
    Ok(())
}
pub(crate) fn map_position(p:P)->P{P{x:10000.+(10300.-p.y)*0.65,y:13000.+(p.x-13000.)*0.6}}
fn source_position(p:P)->P{P{x:13000.+(p.y-13000.)/0.6,y:10300.-(p.x-10000.)/0.65}}
pub(crate) fn elevation_m(p:P)->f64{let s=source_position(p);let mut h=0f64;for(x,y,r,b,height)in[(10600.,5200.,12300.,6400.,40.),(13700.,4000.,16200.,6400.,80.)]{let edge=((s.x-x)*0.6).min((r-s.x)*0.6).min((s.y-y)*0.65).min((b-s.y)*0.65);h=h.max(height*(edge/120.).clamp(0.,1.));}h}
pub(crate) fn cover_multiplier(p:P)->f64{(1.-elevation_m(p)*0.0025).clamp(0.8,1.)}
pub(crate) fn strict_inside(poly:&[P],p:P)->bool{if !inside(poly,p){return false}for i in 0..poly.len(){let a=poly[i];let b=poly[(i+1)%poly.len()];let d=b-a;let length=d.dist(P::default());if length>0.&&((p.x-a.x)*d.y-(p.y-a.y)*d.x).abs()/length<1e-6&&p.x>=a.x.min(b.x)-1e-6&&p.x<=a.x.max(b.x)+1e-6&&p.y>=a.y.min(b.y)-1e-6&&p.y<=a.y.max(b.y)+1e-6{return false}}true}
pub(crate) fn clear_ground(g:&Littoral,a:P,b:P)->bool{
    if !g.walkable(a,true)||!g.walkable(b,true){return false}
    fn cross(a:P,b:P,c:P)->f64{(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)}
    fn intersects(a:P,b:P,c:P,d:P)->bool{let(a1,a2,b1,b2)=(cross(a,b,c),cross(a,b,d),cross(c,d,a),cross(c,d,b));a1*a2<0.&&b1*b2<0.}
    !std::iter::once(&g.polygon).chain(g.obstacles.iter()).any(|poly|(0..poly.len()).any(|i|intersects(a,b,poly[i],poly[(i+1)%poly.len()])))
}

pub(crate) const ENTERPRISE:&str="CAS-H-USN-ENTERPRISE-1942";
pub(crate) const SHOKAKU:&str="CAS-H-IJN-SHOKAKU-1942";
pub(crate) const LHA:&str="CAS-O-LHA-RETURNLIGHT";
pub(crate) const APV:&str="CAS-O-APV-TIDEBRIDGE";

pub(crate) fn carrier_category(id:&str)->&'static str {
    match id{ENTERPRISE|SHOKAKU=>"CV",LHA=>"LHA",APV=>"APV",_=>"warship"}
}
pub(crate) fn company_category(id:&str,kind:&str)->E<&'static str>{
    let p=profile(id).ok_or("战术人格未登记")?;
    Ok(if kind=="helicopter"||matches!(p.role,"air_assault"|"airborne"|"gunship"){"airmobile"}else if kind=="amphibious_vehicle"||matches!(p.role,"armor"|"transport"){"armor"}else{"infantry"})
}
pub(crate) fn carrier_eligibility(unit:&str,kind:&str,ship:&str)->E<()> {
    let category=carrier_category(ship);
    match company_category(unit,kind)?{
        "airmobile" if !matches!(category,"CV"|"LHA")=>Err("空输与伞兵仅能从航母或两栖攻击舰出发".into()),
        "armor" if !matches!(category,"CV"|"LHA"|"APV")=>Err("装甲连仅能由装甲运输舰、两栖攻击舰或航母搭载".into()),
        _=>Ok(())
    }
}
pub(crate) fn carrier_capacity(id:&str,loaded:u32)->E<u32>{
    let data=extended_data()?;let d=data.ships.iter().find(|s|s.id==id).ok_or("舰只未登记")?;
    let base=match carrier_category(id){"CV"=>24,"LHA"=>28,"APV"=>30,_=>match d.kind.as_str(){"BB"|"BC"|"CB"=>16,"CA"=>12,"CL"=>10,"AV"=>14,_=>8}};
    Ok(base+(100-loaded.min(100))/20)
}
pub(crate) fn company_slots(id:&str,kind:&str)->E<u32>{profile(id).ok_or("战术人格未登记")?;Ok(super::company_slots(id,kind))}
pub(crate) fn ship_points(id:&str)->Option<u32>{match id{ENTERPRISE=>Some(2600),SHOKAKU=>Some(2750),LHA=>Some(1700),APV=>Some(1100),_=>None}}
pub(crate) fn flight_range(id:&str)->f64{match id{"MCP-076"=>10000.,"MCP-027"=>7000.,"MCP-240"=>8000.,_=>6000.}}
fn new_card(base:&ShipDef,id:&str,name:&str,kind:&str,dp:f64,speed:f64,armor:[f64;3],guns:GunDef)->ShipDef{
    let mut d=base.clone();d.id=id.into();d.name=name.into();d.kind=kind.into();d.side="allies".into();d.size="A".into();d.dp=dp;d.max_knots=speed;d.armor_belt=armor[0];d.armor_deck=armor[1];d.torpedo_protection_dp=armor[2];d.gun=guns;d.secondary=None;d.torpedo=None;d.length_m=if kind=="CV"{250.}else{200.};d.turn_advance_yards=400.;d.speed_loss_knots=2.;d.accel_knots_per_turn=8.;d.accel_high_knots_per_turn=4.;d.brake_knots_per_turn=10.;d.engineering_speed_multiplier=None;d.in_service_year=if id==SHOKAKU{1941}else if id==ENTERPRISE{1936}else{0};d.damage_speed=[(0.,speed),(0.25*dp,speed*0.75),(0.5*dp,speed*0.5),(0.75*dp,speed*0.25),(0.9*dp,0.),(dp,0.)].into_iter().map(|(damage,knots)|DamageSpeed{damage,knots}).collect();
    if id==ENTERPRISE{d.damage_speed=[(0.,32.),(157.,24.),(314.,16.),(471.,8.),(565.,0.),(628.,0.)].into_iter().map(|(damage,knots)|DamageSpeed{damage,knots}).collect();}
    if id==SHOKAKU{d.damage_speed=[(0.,34.),(186.,26.),(371.,17.),(557.,8.),(668.,0.),(742.,0.)].into_iter().map(|(damage,knots)|DamageSpeed{damage,knots}).collect();}
    d
}
pub(crate) fn extended_data()->E<&'static Data>{
    static DATA:OnceLock<E<Data>>=OnceLock::new();DATA.get_or_init(||{
        let mut d=crate::salvage_v3::expedition_data()?.clone();let base=d.ships.iter().find(|s|s.id=="IBS-U-USN-FLETCHER").ok_or("缺少基础炮表")?.clone();
        let mut us=base.gun.clone();us.name="Mk24 5in/38 SpCOM".into();us.gs=3;us.barrels=8;us.mounts=[([0.,150.],1),([210.,360.],1),([210.,330.],2),([30.,150.],2),([180.,330.],1),([30.,180.],1)].into_iter().flat_map(|(arc,n)|(0..n).map(move |_|GunMount{barrels:1,arc,arc2:None})).collect();
        let mut jp=us.clone();jp.name="Type 89 12.7cm/40 COM".into();jp.gs=4;jp.barrels=16;jp.range_yd=vec![4800.,9600.,12800.,16000.];jp.damage=vec![16.,13.,12.,10.];jp.pen_belt=vec![Some(4.),Some(2.),Some(2.),Some(1.)];jp.pen_deck=vec![None,None,Some(1.),Some(2.)];jp.armor_piercing=false;jp.mounts=(0..8).map(|i|GunMount{barrels:2,arc:if i<4{[210.,330.]}else{[30.,150.]},arc2:None}).collect();
        let mut lha=us.clone();lha.gs=4;lha.barrels=2;lha.mounts=vec![GunMount{barrels:1,arc:[210.,150.],arc2:None},GunMount{barrels:1,arc:[30.,330.],arc2:None}];lha.name="原创Mk-C 127mm".into();
        let mut apv=lha.clone();apv.barrels=1;apv.mounts.truncate(1);
        d.ships.extend([new_card(&base,ENTERPRISE,"企业", "CV",628.,32.,[8.,3.,135.],us),new_card(&base,SHOKAKU,"翔鹤","CV",742.,34.,[8.,6.,135.],jp),new_card(&base,LHA,"返航灯","LHA",520.,25.,[3.,2.,60.],lha),new_card(&base,APV,"潮桥","APV",360.,21.,[4.,2.,40.],apv)]);
        // Dedicated NPC aliases preserve source cards but permit the opposing
        // exercise seat; they never enter the owned player catalogue.
        for id in ["IBS-U-USN-FLETCHER",SHOKAKU]{let mut card=d.ships.iter().find(|s|s.id==id).unwrap().clone();card.id=format!("CAS-NPC-{id}");card.side="axis".into();d.ships.push(card);}
        Ok(d)
    }).as_ref().map_err(Clone::clone)
}

pub(crate) fn catalogue()->E<Value>{
    let mut v=super::catalogue_version(VERSION_V3)?;v["version"]=json!(VERSION);v["naval_backend"]=json!(crate::realtime::VERSION);v["aviation_scope"]=json!("fictional-air-v1");
    let data=extended_data()?;
    for d in data.ships.iter().filter(|s|[ENTERPRISE,SHOKAKU,LHA,APV].contains(&s.id.as_str())){v["ships"].as_array_mut().unwrap().push(json!({"id":d.id,"name":d.name,"kind":d.kind,"transport_role":carrier_category(&d.id),"source_kind":if d.id.starts_with("CAS-H-"){"printed_CAS_hull"}else{"original_fictional"},"slots_combat":carrier_capacity(&d.id,100)?,"slots_balanced":carrier_capacity(&d.id,70)?,"slots_transport":carrier_capacity(&d.id,40)?,"dp":d.dp,"max_knots":d.max_knots,"points":ship_points(&d.id)}));}
    for row in v["ships"].as_array_mut().unwrap(){let id=row["id"].as_str().unwrap().to_owned();row["slots_combat"]=json!(carrier_capacity(&id,100)?);row["slots_balanced"]=json!(carrier_capacity(&id,70)?);row["slots_transport"]=json!(carrier_capacity(&id,40)?);row["carrier_category"]=json!(carrier_category(&id));}
    for row in v["cards"].as_array_mut().unwrap(){let id=row["id"].as_str().unwrap().to_owned();for opt in row["transport_options"].as_array_mut().unwrap(){let kind=opt["kind"].as_str().unwrap().to_owned();opt["carrier_requirement"]=json!(company_category(&id,&kind)?);opt["deployment_range"]=json!(if kind=="helicopter"{flight_range(&id)}else{900.});}}
    v["multi_company"]=json!({"version":MULTI,"capacity_multiplier":6,"personnel_weights":{"infantry":1,"armor":4,"airmobile":3},"max_personnel":250,"max_companies":25});
    for s in v["ships"].as_array_mut().unwrap(){for mode in ["combat","balanced","transport"]{s[format!("multi_slots_{mode}")]=json!(s[format!("slots_{mode}")].as_u64().unwrap()*6);}}
    for c in v["cards"].as_array_mut().unwrap(){let id=c["id"].as_str().unwrap().to_owned();let(n,count)=company_layout(&id);c["company_layout"]=json!({"version":MULTI,"company_count":n,"personnel_per_company":count,"total_personnel":n*count,"companies":(1..=n).map(|i|json!({"company_id":company_key(&id,i),"company_name":company_label(&id,i),"personnel_count":count})).collect::<Vec<_>>()});for opt in c["transport_options"].as_array_mut().unwrap(){opt["multi_company_slots"]=json!(company_personnel_slots(&id,opt["kind"].as_str().unwrap(),count)?);}}
    v["aviation"]=json!({"version":"fictional-air-v1","detachment_per_squadron":3,"weapon_stock_per_squadron":18,"aircraft_budget":24,"launch_interval_seconds":2,"recover_interval_seconds":3,"rearm_seconds":20,"models":["F4F","SBD","TBD","A6M2","D3A2","B5N2","support_helicopter"],"limits":"原创近场航空；未实现完整CAS航空表，详见source-note"});
    Ok(v)
}


/// New identities only. These near-field cadences are registered adaptation
/// parameters, never an alternative timing table for old hull identities.
pub(crate) fn gun_timing(id:&str)->Option<crate::realtime::Timings>{
    let id=id.strip_prefix("CAS-NPC-").unwrap_or(id);
    let(reload,train)=match id{ENTERPRISE|LHA|APV=>(4,28.7),SHOKAKU=>(6,16.),"IBS-U-USN-FLETCHER" if id.starts_with("IBS-")=>return None,_=>return None};
    Some(crate::realtime::Timings{reload,train})
}
#[derive(Clone)]
struct Shore {ship:u32,target:P,expires:u32}
#[derive(Clone)]
struct Squadron {id:String,carrier:u32,model:&'static str,role:&'static str,total:u32,available:u32,lost:u32,ready:u32,stock:u32,range:f64,health:Vec<f64>}
#[derive(Clone)]
struct Aircraft {id:u32,squadron:usize,carrier:u32,model:&'static str,role:&'static str,phase:&'static str,mission:&'static str,p:P,heading:f64,hp:f64,max:f64,fuel:f64,weapons:u32,target:P,target_kind:String,target_id:Value,next:u32,speed:f64}
pub(crate) struct Battle {
    naval:World,ground:Littoral,commands:Vec<Command>,shore:Vec<Shore>,
    squadrons:Vec<Squadron>,aircraft:Vec<Aircraft>,deck:BTreeMap<u32,u32>,
    corpses:Vec<Value>,corpse_ids:BTreeSet<u32>,body_poses:BTreeMap<u32,(P,f64)>,next_aircraft:u32,town:Value,
    // Absent until explicitly requested: old v4 observations and saves stay frozen.
    autonomy:Option<autonomy::Commander>,
    carrier_ops:Option<carrier_ops::Operations>,
}
impl Battle {
    fn company_request(&self,q:&Value)->E<Value>{let mut q=q.clone();if self.ground.config.company_layout.as_deref()!=Some(MULTI){return Ok(q)}if !["littoral_deploy","littoral_cancel_deploy","littoral_order","littoral_ability","littoral_support"].contains(&q["op"].as_str().unwrap_or(""))&&q["kind"]!="deploy"{return Ok(q)}if q["op"]=="littoral_support"&&q["kind"]=="naval"{return Ok(q)}let selection=q["company_id"].as_str().or_else(||q["unit_id"].as_str()).ok_or("请选择具体先遣连")?;let selected=if let Some(g)=self.ground.groups.iter().find(|g|g.card.id==selection){g}else{let matches:Vec<_>=self.ground.groups.iter().filter(|g|unit_id(g.card.id)==selection).collect();if matches.len()!=1{return Err("该战术人格有多个先遣连，请选择company_id".into())}matches[0]};if let Some(id)=q["unit_id"].as_str(){if id!=selected.card.id&&id!=unit_id(selected.card.id){return Err("company_id与本人身份不一致".into())}}q["unit_id"]=json!(selected.card.id);Ok(q)}
    pub(crate) fn new(seed:u32,config:Config)->E<Self>{
        let mut ground=Littoral::new_version(seed,config,VERSION)?;
        if ground.config.mode=="raid" {let mut npc=ground.ships.iter().find(|s|!s.ally).unwrap().clone();npc.def=extended_data()?.ships.iter().find(|s|s.id==SHOKAKU).unwrap().clone();npc.id=1000+ground.ships.len()as u32;npc.hp=npc.def.dp;npc.max=npc.def.dp;ground.ships.push(npc);}
        let mut town=json!({"roads":[],"buildings":[]});expand_ground(&mut ground,&mut town);expand_companies(&mut ground)?;town=generate_town(&mut ground);
        if ground.config.mode=="tutorial"{for b in ground.bodies.iter_mut().filter(|b|!b.ally){b.next=450;}for b in ground.buildings.iter_mut().filter(|b|!b.ally){b.next=450;}}
        let data=extended_data()?;
        let mut naval=World::blank(data,seed,0,"coord",VERSION,"coord",0);
        naval.field=crate::model::Field{width:MAP_WIDTH,height:MAP_HEIGHT,limit:1800};
        naval.islands=vec![ground.polygon.clone()];
        let mut gun_supply=BTreeMap::new();
        for i in 0..ground.ships.len(){
            let ally=ground.ships[i].ally;let side=if ally{0}else{1};let fleet=naval.fleets.len() as u32+1;
            let source=ground.ships[i].def.id.clone();
            let def=data.ships.iter().position(|d|d.id==source).ok_or("舰卡未登记")?;
            let sea=ground.beach_for(2)?.0;let p=if ally{P{x:sea.x-300.-(i%2)as f64*100.,y:sea.y-400.+i as f64*170.}}else{P{x:6500.,y:17500.+(i-ground.config.ships.len())as f64*500.}};
            let h=if ally{90.}else{0.};let name=data.ships[def].name.clone();
            let id=naval.spawn(def,side,fleet,name.clone(),p,h)?;
            let initial=if ally{ground.ships[i].initial}else if ground.config.mode=="tutorial"{30.}else{100.};
            naval.ship_mut(id).unwrap().hp=data.ships[def].dp*initial/100.;
            if ally {naval.ship_mut(id).unwrap().character=Some(source.clone());gun_supply.insert(id,ground.ships[i].loaded);
                // Torpedoes remain actual tubes/reserve, scaled only by the
                // explicitly loaded fraction. No free reload stock is added.
                let loaded=ground.ships[i].loaded;let s=naval.ship_mut(id).unwrap();
                for n in &mut s.torp_mount_remaining{*n=*n*loaded/100;}for n in &mut s.torp_reserve{*n=*n*loaded/100;}s.ammo=s.torp_mount_remaining.iter().sum();
            }
            ground.ships[i].id=id;ground.ships[i].p=p;ground.ships[i].h=h;ground.ships[i].max=data.ships[def].dp;ground.ships[i].hp=naval.ship(id).unwrap().hp;ground.ships[i].ai=false;ground.ships[i].anchor=false;
            naval.fleets.push(crate::model::Fleet{id:fleet,side,name,leader:id,members:vec![id],mode:"follow".into(),speed:0.,actual:0.,turn_degrees:0.,points:vec![],ai:crate::model::Ai::new("coord",if ally{"manual"}else{"auto"}),notice:None,last_ai_route:0,tactic:crate::model::Tactic::Search});
        }
        for g in ground.groups.iter_mut().filter(|g|["embarked","recovered"].contains(&g.stage)){g.p=ground.ships.iter().find(|s|s.id==g.carrier).unwrap().p;}
        for id in naval.ships.iter().filter(|s|data.ships[s.def].id=="IBS-U-USN-FLETCHER").map(|s|s.id).collect::<Vec<_>>(){naval.radar.equip_fletcher_1943(id)?;}
        naval.v4_gun_supply=Some(gun_supply);naval.init_realtime(crate::realtime::VERSION)?;
        naval.intel_profile=crate::intel::VERSION.into();naval.refresh_open_intel();
        let mut squadrons=vec![];
        for ship in &naval.ships{
            let identity=&data.ships[ship.def].id;
            let models:&[(&str,&str)]=match identity.as_str(){ENTERPRISE=>&[("F4F","fighter"),("SBD","dive_bomber"),("TBD","torpedo_bomber")],SHOKAKU=>&[("A6M2","fighter"),("D3A2","dive_bomber"),("B5N2","torpedo_bomber")],LHA=>&[("support_helicopter","helicopter")],_=>&[]};
            for &(model,role) in models{let model=match model{"F4F"=>"F4F","SBD"=>"SBD","TBD"=>"TBD","A6M2"=>"A6M2","D3A2"=>"D3A2","B5N2"=>"B5N2",_=>"support_helicopter"};let role=match role{"fighter"=>"fighter","dive_bomber"=>"dive_bomber","torpedo_bomber"=>"torpedo_bomber",_=>"helicopter"};
                squadrons.push(Squadron{id:format!("air-{}-{}",ship.id,model),carrier:ship.id,model,role,total:3,available:3,lost:0,ready:0,stock:18,range:if model=="support_helicopter"{7000.}else{18000.},health:vec![if role=="fighter"{90.}else{120.};3]});}
        }
        Ok(Self{naval,ground,commands:vec![],shore:vec![],squadrons,aircraft:vec![],deck:BTreeMap::new(),corpses:vec![],corpse_ids:BTreeSet::new(),body_poses:BTreeMap::new(),next_aircraft:0,town,autonomy:None,carrier_ops:None})
    }
    fn sync_from_naval(&mut self){
        for gs in &mut self.ground.ships{if let Some(s)=self.naval.ship(gs.id){gs.p=s.p;gs.h=s.h;gs.hp=s.hp.max(0.);gs.speed=s.speed;gs.max=self.naval.data.ships[s.def].dp;gs.ammo=self.naval.salvage_gun_supply(s);gs.anchor=false;}}
    }
    fn sync_to_naval(&mut self){
        for gs in &self.ground.ships{if let Some(s)=self.naval.ship_mut(gs.id){if gs.hp<s.hp{s.hp=gs.hp;}}}
    }
    pub(crate) fn save(&self)->Saved{Saved{version:VERSION.into(),seed:self.ground.seed,config:self.ground.config.clone(),frame:self.ground.frame,tick:self.ground.tick(),commands:self.commands.clone()}}
    pub(crate) fn from_save(s:Saved,target:Option<u32>)->E<Self>{
        if s.version!=VERSION||s.frame>18000||!s.tick.is_finite()||(s.tick-s.frame as f64/10.).abs()>1e-6||s.commands.len()>15000||s.commands.iter().any(|c|c.frame>s.frame)||s.commands.windows(2).any(|p|p[0].frame>p[1].frame){return Err("v4存档版本、时钟或指令日志无效".into())}
        let end=target.unwrap_or(s.frame);if end>s.frame{return Err("不能重演未来时刻".into())}
        let mut w=Self::new(s.seed,s.config)?;let mut commands=s.commands.into_iter().peekable();
        loop{while commands.peek().is_some_and(|c|c.frame==w.ground.frame&&c.frame<=end){w.command(&commands.next().unwrap().request,true)?;}
            if w.ground.frame>=end{break}if w.ground.result.is_some(){return Err("v4重演越过真实终局".into())}w.advance();}
        Ok(w)
    }
    fn sea_route(&mut self,id:u32,points:Vec<P>,speed:f64)->E<()>{let s=self.naval.ship(id).filter(|s|s.side==0&&s.alive()).ok_or("舰艇已损失")?;let fleet=s.fleet.ok_or("舰艇没有编队")?;self.naval.external(json!({"op":"route","fleet":fleet,"mode":"follow","points":points,"speed":speed}))}
    pub(crate) fn command(&mut self,q:&Value,record:bool)->E<Value>{
        if self.ground.result.is_some(){return Err("两栖行动已经结束".into())}if record&&self.commands.len()>=15000{return Err("v4指令上限".into())}
        let original=q.clone();let normalized=self.company_request(q)?;let q=&normalized;
        self.sync_from_naval();let op=q["op"].as_str().ok_or("操作无效")?;
        match op {
            "littoral_autonomy"=>{
                if q["version"]!=autonomy::VERSION{return Err("请选择已登记的海陆空托管规则".into())}
                let enabled=q["enabled"].as_bool().ok_or("托管开关须为真假值")?;
                let posture=q.get("posture").and_then(Value::as_str).unwrap_or("mission");
                if !["mission","withdraw"].contains(&posture){return Err("托管姿态无效".into())}
                self.autonomy.get_or_insert_with(autonomy::Commander::default).configure(enabled,posture,self.ground.frame);
            },
            "carrier_ops"=>self.carrier_configure(q)?,
            "carrier_automation"=>self.carrier_v3_configure(q)?,
            "carrier_mission"=>self.carrier_v3_mission(q)?,
            "carrier_air_order"=>self.carrier_v2_order(q)?,
            "carrier_policy"=>self.carrier_v2_policy(q)?,
            "littoral_air_order" if q["queue"]==true&&self.carrier_ops.is_some()=>self.carrier_enqueue(q)?,
            "littoral_air_order"=>{self.air_order(q)?;if self.carrier_is_v2(){self.carrier_v2_manual(q)?;}},
            "littoral_support" if q["kind"]=="naval"=>{let id=crate::world::u(q,"ship")?;let p=self.ground.position_for(q)?;self.shore_plan(id,p)?;
                if q.get("queue").and_then(Value::as_bool)!=Some(true)&&!self.shore_ready(id,p){return Err("真实炮座尚在转向或装填，请排队待发".into())}
                self.ground.ships.iter_mut().find(|s|s.id==id).unwrap().aim_target=Some(p);let _=self.naval.cancel_realtime_gun(0,&json!({"ship":id}));self.shore.retain(|s|s.ship!=id);self.shore.push(Shore{ship:id,target:p,expires:self.ground.frame+900});},
            "littoral_ship_order"=>{let id=crate::world::u(q,"ship")?;match q["action"].as_str(){
                Some("move")=>{self.cancel_deploy(id);self.sea_route(id,vec![self.ground.position_for(q)?],q.get("speed").and_then(Value::as_f64).unwrap_or(25.))?;},
                Some("hold")|Some("stop")=>{self.cancel_deploy(id);let f=self.naval.ship(id).and_then(|s|s.fleet).ok_or("舰艇无效")?;self.naval.external(json!({"op":"speed","fleet":f,"speed":0}))?;},
                Some("aim_land")=>{let p=self.ground.position_for(q)?;self.shore_plan(id,p)?;let _=self.naval.cancel_realtime_gun(0,&json!({"ship":id}));self.ground.ships.iter_mut().find(|s|s.id==id).unwrap().aim_target=Some(p);},
                Some("cancel_support")=>{self.shore.retain(|s|s.ship!=id);},
                Some("face")=>return Err("v4舰艏转向使用原战役航线操作；炮座会按真实射界训练".into()),
                _=>return Err("舰艇操作无效".into())}},
            "littoral_deploy"=>{if q["queue"]==true{let(gi,si,beach,air,path)=self.ground.deployment_plan(q)?;if !path.is_empty(){let sea=self.ground.beach_for(beach)?.0;let id=self.ground.ships[si].id;self.sea_route(id,vec![sea],18.)?;}self.ground.groups[gi].pending=Some((beach,air));self.ground.event("deploy_queued","载舰按真实海战航线接近滩头",self.ground.ships[si].p);}else{self.ground.command(q,false)?;}},
            "littoral_cancel_deploy"=>{self.ground.command(q,false)?;},
            "littoral_order"|"littoral_ability"|"littoral_extract"|"littoral_abandon"|"littoral_support"=>{if op=="littoral_extract"&&self.aircraft.iter().any(|a|a.hp>0.&&self.naval.ship(a.carrier).is_some_and(|s|s.side==0)){return Err("仍有本方飞机在空，请等待真实返航或下令召回".into())}self.ground.command(q,false)?;self.sync_to_naval();},
            _=>{if !["route","fire","gun_cancel","lead","detach","reform","ai","radar_set","illuminate","searchlight","smoke","speed","resume"].contains(&op){return Err("未知v4操作".into())}if ["route","speed","resume"].contains(&op){if let Some(f)=q["fleet"].as_u64(){let ids=self.naval.fleet(f as u32).map(|f|f.members.clone()).unwrap_or_default();for id in ids{self.cancel_deploy(id);}}}self.naval.external(q.clone())?;if ["fire","gun_cancel"].contains(&op)&&q.get("weapon").is_none_or(|v|v=="gun"){if let Some(id)=q["ship"].as_u64(){self.shore.retain(|p|p.ship!=id as u32);if let Some(s)=self.ground.ships.iter_mut().find(|s|s.id==id as u32){s.aim_target=None;}}}}
        }
        if record{
            // A rejected command never relinquishes control. Successful manual
            // orders take authority immediately; generated orders use record=false.
            if op!="littoral_autonomy"&&!self.carrier_v3_keeps_ground_ai(q){if let Some(ai)=&mut self.autonomy{ai.manual_takeover(self.ground.frame);}}
            self.commands.push(Command{frame:self.ground.frame,request:original});
        }Ok(self.view())
    }
    fn cancel_deploy(&mut self,id:u32){for g in &mut self.ground.groups{if g.carrier==id{g.pending=None;}}}
    fn shore_plan(&self,id:u32,p:P)->E<()>{
        if !inside(&self.ground.polygon,p){return Err("炮援落点须在真实陆岛上".into())}let s=self.naval.ship(id).filter(|s|s.side==0&&s.alive()).ok_or("舰艇已损失")?;let d=&self.naval.data.ships[s.def];
        if self.naval.salvage_gun_supply(s)==0{return Err("真实舰炮弹药已耗尽".into())}if s.p.dist(p)>d.gun.range_yd[3]*YARD{return Err("落点超出真实舰炮射程".into())}
        let relative=norm((p-s.p).heading()-s.h);if !d.gun.mounts.iter().enumerate().any(|(i,m)|!s.gun_mount_destroyed[i]&&(arc(relative,m.arc)||m.arc2.is_some_and(|a|arc(relative,a)))){return Err("落点在舰炮真实射界外，请移动舰艇调整舰艏".into())}Ok(())
    }
    fn shore_ready(&self,id:u32,p:P)->bool{let Some(s)=self.naval.ship(id)else{return false};let d=&self.naval.data.ships[s.def];let bearing=(p-s.p).heading();let relative=norm(bearing-s.h);d.gun.mounts.iter().enumerate().any(|(i,m)|!s.gun_mount_destroyed[i]&&(arc(relative,m.arc)||m.arc2.is_some_and(|a|arc(relative,a)))&&self.naval.turret_loaded(s,i)&&self.naval.illumination_aligned(s,i,bearing))}
    fn advance_shore(&mut self){
        let mut aims:BTreeMap<u32,P>=self.ground.ships.iter().filter(|s|s.ally).filter_map(|s|s.aim_target.map(|p|(s.id,p))).collect();
        for pending in &self.shore{aims.insert(pending.ship,pending.target);}
        for(id,p)in aims{if self.shore_plan(id,p).is_err(){continue}let s=self.naval.ship(id).unwrap().clone();let d=&self.naval.data.ships[s.def];let bearing=(p-s.p).heading();let relative=norm(bearing-s.h);let mounts=d.gun.mounts.iter().enumerate().filter(|(i,m)|!s.gun_mount_destroyed[*i]&&(arc(relative,m.arc)||m.arc2.is_some_and(|a|arc(relative,a)))).map(|(i,_)|i).collect::<Vec<_>>();for i in mounts{self.naval.train_illumination_mount(id,i,bearing);}}
        let orders=self.shore.clone();for o in orders{if self.ground.frame>=o.expires||self.shore_plan(o.ship,o.target).is_err(){self.shore.retain(|p|p.ship!=o.ship);continue;}
            let ship=self.naval.ship(o.ship).unwrap().clone();let d=self.naval.data.ships[ship.def].clone();let bearing=(o.target-ship.p).heading();let relative=norm(bearing-ship.h);
            let mounts:Vec<_>=d.gun.mounts.iter().enumerate().filter(|(i,m)|!ship.gun_mount_destroyed[*i]&&(arc(relative,m.arc)||m.arc2.is_some_and(|a|arc(relative,a)))).map(|(i,m)|(i,m.barrels)).collect();
            let ready:Vec<_>=mounts.into_iter().filter(|(i,_)|{let s=self.naval.ship(o.ship).unwrap();self.naval.turret_loaded(s,*i)&&self.naval.illumination_aligned(s,*i,bearing)}).collect();
            if ready.is_empty(){continue}let count=ready.iter().map(|(_,n)|*n).sum::<u32>();if self.ground.projectiles.len()+count as usize>self.ground.projectile_limit(){continue}
            let range=ship.p.dist(o.target);let band=d.gun.range_yd.iter().position(|r|range<=*r*YARD).unwrap_or(3);let damage=d.gun.damage[band];
            for(i,n)in ready{self.naval.reserve_illumination_mount(o.ship,i);for barrel in 0..n{let offset=P{x:(barrel as f64-(n-1)as f64/2.)*12.,y:0.};self.ground.launch(true,ship.p,o.target+offset,damage,(d.gun.caliber_mm*0.65).clamp(75.,300.),900.,false,"naval",format!("ship:{}",o.ship));}}
            self.naval.add(1,"gun",format!("{}真实炮座实施岸援，发射{}发",ship.name,count),Some(VERSION),None);self.naval.last_event_ship(&ship);
            self.shore.retain(|p|p.ship!=o.ship);self.ground.event("support_fired","真实炮座已向岸上开火，弹药与海战共用",o.target);
        }
    }
    pub(crate) fn advance(&mut self){
        if self.ground.result.is_some(){return}self.sync_from_naval();
        if (self.ground.frame+1)%10==0{self.naval.advance();self.sync_from_naval();self.advance_shore();}
        self.ground.advance();self.sync_to_naval();self.advance_air();self.record_corpses();
        // Close the completed frame before exposing its save. In particular an
        // automated terminal order belongs to this frame, so replay to exactly
        // this timestamp rebuilds the result instead of needing a future step.
        self.advance_autonomy();
    }
    fn record_corpses(&mut self){
        for b in &self.ground.bodies{
            let pose=self.body_poses.entry(b.id).or_insert((b.p,0.));let displacement=b.p-pose.0;
            if displacement.dist(P::default())>0.01{pose.1=displacement.heading();}pose.0=b.p;
            if b.hp<=0.&&self.corpse_ids.insert(b.id){self.corpses.push(json!({"id":b.id,"unit_id":b.group,"side":if b.ally{"allies"}else{"axis"},"kind":b.kind,"x":b.p.x,"y":b.p.y,"heading":pose.1,"pose_seed":self.ground.seed.wrapping_mul(1664525).wrapping_add(b.id.wrapping_mul(1013904223)),"death_tick":self.ground.tick()}));}
        }
        for t in self.ground.transports.iter().filter(|t|t.hp<=0.){if self.corpse_ids.insert(t.id){let g=&self.ground.groups[t.group];self.corpses.push(json!({"id":t.id,"unit_id":g.card.id,"side":"allies","kind":"transport_wreck","vehicle_id":format!("{}-{}",g.card.id,g.transport_kind),"x":t.p.x,"y":t.p.y,"heading":(t.goal-t.p).heading(),"pose_seed":self.ground.seed^t.id,"death_tick":self.ground.tick()}));}}
        for t in std::mem::take(&mut self.ground.v4_transport_losses){if self.corpse_ids.insert(t.id){let g=&self.ground.groups[t.group];self.corpses.push(json!({"id":t.id,"unit_id":g.card.id,"side":"allies","kind":"transport_wreck","vehicle_id":format!("{}-{}",unit_id(g.card.id),g.transport_kind),"x":t.p.x,"y":t.p.y,"heading":(t.goal-t.p).heading(),"pose_seed":self.ground.seed^t.id,"death_tick":self.ground.tick()}));}}
    }
    fn multi_view(&self,v:&mut Value){
        if self.ground.config.company_layout.as_deref()!=Some(MULTI){return}
        v["littoral"]["company_layout"]=json!(MULTI);v["littoral"]["budget"]["friendly_bodies"]=json!(250);v["littoral"]["budget"]["bodies"]=json!(320);v["littoral"]["budget"]["transports"]=json!(25);v["littoral"]["budget"]["projectiles"]=json!(512);
        for(i,g)in self.ground.groups.iter().enumerate(){let id=unit_id(g.card.id);let index=g.card.id[9..].parse::<u32>().unwrap();let row=&mut v["littoral"]["groups"][i];row["unit_id"]=json!(id);row["company_id"]=json!(g.card.id);row["company_name"]=json!(company_label(id,index));row["name"]=row["company_name"].clone();row["company_count"]=json!(company_layout(id).0);row["personnel_slot_cost"]=json!(g.card.slots);row["vehicle_id"]=json!(format!("{}-{}",id,g.transport_kind));}
        for row in v["littoral"]["land"]["entities"].as_array_mut().unwrap(){let key=row["unit_id"].as_str().unwrap_or("").to_owned();if unit_id(&key)!=key{row["company_id"]=json!(key);row["unit_id"]=json!(unit_id(&key));}}
        for row in v["littoral"]["support"]["helicopter"].as_array_mut().unwrap(){let key=row["unit_id"].as_str().unwrap_or("").to_owned();if unit_id(&key)!=key{row["company_id"]=json!(key);row["unit_id"]=json!(unit_id(&key));}}
        for(i,t)in self.ground.transports.iter().enumerate(){let g=&self.ground.groups[t.group];let row=&mut v["littoral"]["transports"][i];row["company_id"]=json!(g.card.id);row["unit_id"]=json!(unit_id(g.card.id));row["vehicle_id"]=json!(format!("{}-{}",unit_id(g.card.id),g.transport_kind));row["visual_id"]=row["vehicle_id"].clone();}
        for row in v["littoral"]["corpses"].as_array_mut().unwrap(){let id=row["unit_id"].as_str().unwrap_or("").to_owned();if unit_id(&id)!=id{row["company_id"]=json!(id);row["unit_id"]=json!(unit_id(&id));if let Some(g)=self.ground.groups.iter().find(|g|g.card.id==id){if row.get("vehicle_id").is_some(){row["vehicle_id"]=json!(format!("{}-{}",unit_id(&id),g.transport_kind));}}}}
        for s in v["ships"].as_array_mut().unwrap(){if let Some(g)=s["id"].as_u64().and_then(|id|self.ground.ships.iter().find(|g|g.id as u64==id)){s["transport_slots"]=json!(g.slots);}}
        if v["result"].is_object(){let mut companies=v["result"]["units"].clone();for row in companies.as_array_mut().unwrap(){let key=row["id"].as_str().unwrap().to_owned();row["company_id"]=json!(key);row["unit_id"]=json!(unit_id(&key));row["company_name"]=json!(company_label(unit_id(&key),key[9..].parse().unwrap()));}let mut units=vec![];for id in &self.ground.config.roster{let rows:Vec<_>=companies.as_array().unwrap().iter().filter(|r|r["unit_id"]==*id).collect();let total=rows.iter().map(|r|r["initial_count"].as_u64().unwrap()).sum::<u64>();let hp=rows.iter().map(|r|r["hp_percent"].as_f64().unwrap()*r["initial_count"].as_u64().unwrap()as f64).sum::<f64>()/total as f64;let recovered=rows.iter().any(|r|r["recovered"]==true&&r["hp_percent"].as_f64().unwrap()>0.);units.push(json!({"id":id,"unit_id":id,"hp_percent":hp,"initial_hp_percent":rows[0]["initial_hp_percent"],"initial_count":total,"surviving_count":rows.iter().map(|r|r["surviving_count"].as_u64().unwrap()).sum::<u64>(),"incapacitated":hp<10.,"recovered":recovered,"missing":!recovered&&rows.iter().any(|r|r["missing"]==true),"companies":rows}));}v["result"]["companies"]=companies;v["result"]["units"]=json!(units);v["result"]["company_layout"]=json!(MULTI);v["littoral"]["outcome"]=v["result"].clone();}
    }
    pub(crate) fn view(&self)->Value{
        let mut v=self.naval.observation(0);let g=self.ground.view();v["version"]=json!(VERSION);v["scenario"]=json!(if self.ground.config.mode=="tutorial"{match self.ground.lesson(){"sea_control"=>"近岸制海训练","combined"=>"海陆空协同训练",_=>"两栖登陆训练"}}else{match self.ground.config.mode.as_str(){"raid"=>"海陆空联合突袭","defense"=>"返航灯岛防卫","salvage"=>"两栖遗迹搜索",_=>"海陆协同行动"}});v["naval_tick"]=json!(self.naval.tick);v["tick"]=json!(self.ground.tick());v["littoral"]=g["littoral"].clone();v["result"]=self.ground.result.clone().unwrap_or(Value::Null);if v["result"].is_object(){v["result"]["aviation"]=self.air_view();}v["littoral"]["outcome"]=v["result"].clone();v["littoral"]["aviation"]=self.air_view();if self.carrier_ops.is_some(){v["littoral"]["carrier_ops"]=self.carrier_view();}v["littoral"]["corpses"]=json!(self.corpses);v["littoral"]["land"]["town"]=self.town.clone();v["littoral"]["land"]["terrain"]=terrain_view(&self.ground.polygon);v["littoral"]["land"]["bounds"]=json!({"x":9600,"y":9900,"width":5600,"height":6400});
        for e in v["littoral"]["land"]["entities"].as_array_mut().unwrap(){let p=P{x:e["x"].as_f64().unwrap(),y:e["y"].as_f64().unwrap()};e["elevation_m"]=json!(elevation_m(p));e["cover_multiplier"]=json!(cover_multiplier(p));}
        for e in v["littoral"]["land"]["buildings"].as_array_mut().unwrap(){e["elevation_m"]=json!(elevation_m(P{x:e["x"].as_f64().unwrap(),y:e["y"].as_f64().unwrap()}));let(w,h)=match e["kind"].as_str().unwrap(){"hq"=>(70.,50.),"turret"=>(12.,12.),"aa"=>(14.,14.),_=>(40.,24.)};e["width_m"]=json!(w);e["length_m"]=json!(h);}
        for e in v["littoral"]["land"]["ruins"].as_array_mut().unwrap(){e["width_m"]=json!(40.);e["length_m"]=json!(30.);}
        for(i,g)in self.ground.groups.iter().enumerate(){v["littoral"]["groups"][i]["elevation_m"]=json!(elevation_m(g.p));v["littoral"]["groups"][i]["carrier_requirement"]=json!(company_category(g.card.id,g.transport_kind).unwrap());v["littoral"]["groups"][i]["deployment_range"]=json!(if g.transport_kind=="helicopter"{flight_range(g.card.id)}else{900.});if v["littoral"]["groups"][i]["pending_deploy"].is_object(){v["littoral"]["groups"][i]["pending_deploy"]["range_limit"]=v["littoral"]["groups"][i]["deployment_range"].clone();}}
        if let Some(ai)=&self.autonomy{v["littoral"]["autonomy"]=ai.view();}
        let support=self.naval.ships.iter().filter(|s|s.side==0).map(|s|{let d=&self.naval.data.ships[s.def];let aim=self.ground.ships.iter().find(|g|g.id==s.id).and_then(|g|g.aim_target);let pending=self.shore.iter().find(|p|p.ship==s.id);let reason=aim.and_then(|p|self.shore_plan(s.id,p).err());let mut mounts=vec![];for(i,m)in d.gun.mounts.iter().enumerate(){let mut x=json!({"index":i,"barrels":m.barrels,"arc":m.arc,"destroyed":s.gun_mount_destroyed[i]});self.naval.realtime_mount_view(s,i,&mut x);mounts.push(x);}
            json!({"ship":s.id,"ammo":self.naval.salvage_gun_supply(s),"range":d.gun.range_yd[3]*YARD,"arcs":d.gun.mounts.iter().map(|m|m.arc).collect::<Vec<_>>(),"alive":s.alive(),"aim_target":aim,"aim_state":if aim.is_none(){"unassigned"}else if reason.is_some(){"blocked"}else if aim.is_some_and(|p|self.shore_ready(s.id,p)){"ready"}else{"training_or_reloading"},"ready_for_target":aim.is_some_and(|p|self.shore_ready(s.id,p))&&reason.is_none(),"reason":reason,"pending_target":pending.map(|p|p.target),"pending_expires_tick":pending.map(|p|p.expires as f64/10.),"mounts":mounts})}).collect::<Vec<_>>();v["littoral"]["support"]["naval"]=json!(support);v["presentation"]=self.naval.projectile_presentation(0);self.multi_view(&mut v);v
    }
    pub(crate) fn execute(&mut self,q:&Value)->E<Value>{match q["op"].as_str().ok_or("缺少操作")?{
        "observe"=>Ok(self.view()),"save"=>Ok(json!(self.save())),"report"=>Ok(json!({"result":self.ground.result,"littoral":self.view()["littoral"]})),"presentation"=>Ok(self.naval.projectile_presentation(0)),
        "step"=>{let n=frames(&q["seconds"])?;for _ in 0..n{if self.ground.result.is_some(){break}self.advance();}Ok(self.view())},
        "suggest"=>{let fleet=crate::world::u(q,"fleet")?;let orders=self.naval.suggestions(0,fleet)?;if q["apply"]==true{for order in &orders{let _=self.command(order,true);}}Ok(json!({"orders":orders,"text":"按真实本方态势和权限生成"}))},
        "carrier_preview"=>Ok(match self.carrier_v2_plan(q){Ok(_)=>json!({"valid":true,"reason":"有效航空任务；实际飞行，不额外生成飞机"}),Err(e)=>json!({"valid":false,"reason":e})}),
        "carrier_mission_preview"=>Ok(match self.carrier_v3_mission_plan(q){Ok(_)=>json!({"valid":true,"reason":"松手指定目标 · 航母自动选机、出击与回收"}),Err(e)=>json!({"valid":false,"reason":e})}),
        "preview_route"=>self.naval.preview(0,q),"preview_reform"=>self.naval.preview_reform(0,q),"aim"=>self.naval.preview_aim(0,q),"illumination_preview"=>self.naval.preview_illumination(0,q),"littoral_preview"=>self.preview(q),
        _=>self.command(q,true)}}
}

impl Battle {
    fn advance_autonomy(&mut self){
        if self.ground.result.is_some()||!self.autonomy.as_ref().is_some_and(|ai|ai.enabled)||self.ground.frame%20!=0{return}
        // The planner accepts only the same public observation used by Godot.
        // It cannot inspect enemy hidden state, alter HP, or create a result.
        let observation=self.view();let mut ai=self.autonomy.take().unwrap();
        let frame=self.ground.frame;
        for proposal in ai.plan(&observation){
            if self.ground.result.is_some(){break}
            // In v3 the aviation desk is the sole dispatcher. Withdrawal recalls
            // remain valid, so combined-arms AI cannot accidentally relaunch.
            if self.carrier_is_v3()&&proposal.order["op"]=="littoral_air_order"&&proposal.order["action"]!="return"{continue}
            let result=self.command(&proposal.order,false);
            ai.feedback(frame,proposal,result.map(|_|()));
        }
        self.autonomy=Some(ai);
    }
}

impl Battle {
    fn air_plan(&self,q:&Value)->E<(usize,&'static str,P,String,Value)>{
        let id=q["squadron_id"].as_str().ok_or("请选择实际航空中队")?;let i=self.squadrons.iter().position(|s|s.id==id).ok_or("航空中队不存在")?;
        let s=&self.squadrons[i];if !self.naval.ship(s.carrier).is_some_and(|c|c.side==0){return Err("敌方中队拥有独立指挥权".into())}let action=q["action"].as_str().ok_or("请选择航空行动")?;
        if action=="return" {if !self.aircraft.iter().any(|a|a.squadron==i&&a.hp>0.)&&!self.carrier_ops.as_ref().is_some_and(|ops|ops.queue.iter().any(|q|q["squadron_id"]==s.id)){return Err("该中队无在空飞机或待命任务".into())}return Ok((i,"return",P::default(),String::new(),Value::Null))}
        if !["strike","patrol"].contains(&action){return Err("航空行动无效".into())}
        let carrier=self.naval.ship(s.carrier).filter(|s|s.side==0&&s.alive()).ok_or("航空母舰已经损失")?;
        if self.carrier_ops.is_some(){if action=="patrol"&&s.role!="fighter"{return Err("巡逻警戒请使用战斗机中队".into())}if q["target_kind"]=="aircraft"&&s.role!="fighter"{return Err("空中拦截请使用战斗机中队".into())}}
        if self.carrier_is_v2()&&action=="strike"&&s.role=="fighter"&&q["target_kind"]!="aircraft"{return Err("战斗机负责警戒和空中拦截；舰地打击请使用攻击机".into())}
        if !(q["queue"]==true&&self.carrier_ops.is_some())&&(s.available==0||s.stock==0||s.ready>self.ground.frame||self.deck.get(&s.carrier).is_some_and(|n|*n>self.ground.frame)){return Err("飞机在空、甲板忙碌、整备中或武器耗尽".into())}
        if !(q["queue"]==true&&self.carrier_ops.is_some())&&self.aircraft.iter().filter(|a|a.hp>0.).count()+s.available.min(3)as usize>24{return Err("活动飞机预算暂满".into())}
        let mut p=self.ground.position_for(q)?;if !self.naval.field.contains(p)||carrier.p.dist(p)>s.range{return Err("目标超出本中队真实近场航程".into())}
        let kind=q.get("target_kind").and_then(Value::as_str).unwrap_or("land").to_string();let target=q.get("target_id").cloned().unwrap_or(Value::Null);
        if !["ship","land","aircraft"].contains(&kind.as_str()){return Err("航空目标类型无效".into())}
        if kind=="ship" {let id=target.as_str().ok_or("请选择公开敌舰接触")?;if !self.naval.contacts[0].iter().any(|c|c.id==id&&self.naval.ship(c.ship).is_some_and(|s|s.side==1&&s.alive())){return Err("敌舰接触已失效".into())}}
        if kind=="aircraft"&&!self.aircraft.iter().any(|a|Some(a.id as u64)==target.as_u64()&&a.hp>0.&&self.naval.ship(a.carrier).is_some_and(|s|s.side==1)){return Err("空中目标已失效".into())}
        if kind=="ship" {p=self.naval.contacts[0].iter().find(|c|Some(c.id.as_str())==target.as_str()).unwrap().p();}
        if kind=="aircraft" {p=self.aircraft.iter().find(|a|Some(a.id as u64)==target.as_u64()).unwrap().p;}
        if carrier.p.dist(p)>s.range{return Err("真实目标超出中队航程".into())}
        if action=="strike"&&kind=="land"&&!inside(&self.ground.polygon,p){return Err("对地打击落点须在实际岛屿内".into())}
        if action=="strike"&&s.role=="torpedo_bomber"&&kind!="ship"{return Err("鱼雷机只能攻击真实海上敌舰".into())}
        Ok((i,if action=="strike"{"strike"}else{"patrol"},p,kind,target))
    }
    fn air_order(&mut self,q:&Value)->E<()>{
        let(i,action,target,target_kind,target_id)=self.air_plan(q)?;
        if action=="return"{if let Some(ops)=&mut self.carrier_ops{ops.queue.retain(|p|p["squadron_id"]!=q["squadron_id"]);}for a in self.aircraft.iter_mut().filter(|a|a.squadron==i&&a.hp>0.){a.phase="returning";}return Ok(())}
        self.launch_air(i,action,target,target_kind,target_id)
    }
    fn launch_air(&mut self,i:usize,action:&str,target:P,target_kind:String,target_id:Value)->E<()>{
        let active=self.aircraft.iter().filter(|a|a.hp>0.).count()as u32;
        let s=&mut self.squadrons[i];if s.ready>self.ground.frame||self.deck.get(&s.carrier).is_some_and(|n|*n>self.ground.frame){return Err("真实甲板正忙碌或尚未整备".into())}
        let count=s.available.min(3).min(s.stock).min(24u32.saturating_sub(active));if count==0{return Err("没有可出击飞机、武器或活动空间".into())}let carrier=self.naval.ship(s.carrier).filter(|s|s.alive()).ok_or("母舰已经损失")?;
        let speed=match s.model{"F4F"=>145.,"SBD"=>110.,"TBD"=>105.,"A6M2"=>155.,"D3A2"=>120.,"B5N2"=>125.,_=>90.};
        for n in 0..count{self.next_aircraft+=1;self.aircraft.push(Aircraft{id:self.next_aircraft,squadron:i,carrier:s.carrier,model:s.model,role:s.role,phase:"launching",mission:if action=="patrol"{"patrol"}else{"strike"},p:carrier.p,heading:carrier.h,hp:s.health.pop().unwrap(),max:if s.role=="fighter"{90.}else{120.},fuel:s.range*2.+3000.,weapons:1,target,target_kind:target_kind.clone(),target_id:target_id.clone(),next:self.ground.frame+20*(n+1),speed});}
        s.available-=count;s.stock-=count;self.deck.insert(s.carrier,self.ground.frame+20*count);self.ground.event("air_launch","有限中队正在真实甲板逐架起飞",carrier.p);Ok(())
    }
    fn advance_air(&mut self){
        let frame=self.ground.frame;
        self.carrier_advance();self.carrier_intercepts();
        if self.carrier_ops.is_none()&&frame%300==0 {let ready:Vec<_>=self.squadrons.iter().enumerate().filter(|(_,s)|self.naval.ship(s.carrier).is_some_and(|c|c.side==1&&c.alive())&&s.available>0&&s.stock>0&&s.ready<=frame&&!self.deck.get(&s.carrier).is_some_and(|n|*n>frame)).map(|(i,_)|i).collect();
            for i in ready{let carrier=self.naval.ship(self.squadrons[i].carrier).unwrap();if let Some(c)=self.naval.contacts[1].iter().filter(|c|self.naval.ship(c.ship).is_some_and(|s|s.alive())).min_by(|a,b|carrier.p.dist(a.p()).total_cmp(&carrier.p.dist(b.p()))){let p=c.p();let id=c.id.clone();if carrier.p.dist(p)<=self.squadrons[i].range{let _=self.launch_air(i,"strike",p,"ship".into(),json!(id));}}}}
        let mut attacks=vec![];let mut losses=vec![];let mut returns=vec![];
        for i in 0..self.aircraft.len(){
            if self.aircraft[i].hp<=0.{continue}let mut a=self.aircraft[i].clone();let side=self.naval.ship(a.carrier).map_or(0,|s|s.side);
            let mother=self.naval.ship(a.carrier).filter(|s|s.alive()).map(|s|s.p);
            if a.phase=="launching"{if mother.is_none(){a.hp=0.;losses.push(i);}else if frame>=a.next{a.phase="outbound";}else{a.p=mother.unwrap();}self.aircraft[i]=a;continue;}
            if self.carrier_is_v2()&&a.phase!="returning"&&a.mission=="strike"{
                let invalid=if a.target_kind=="aircraft"{!self.aircraft.iter().any(|e|Some(e.id as u64)==a.target_id.as_u64()&&e.hp>0.)}
                    else if a.target_kind=="ship"{!self.naval.contacts[side].iter().any(|c|Some(c.id.as_str())==a.target_id.as_str()&&self.naval.ship(c.ship).is_some_and(|s|s.alive()))}else{false};
                if invalid{a.phase="returning";}
            }
            let target=if a.phase=="returning"{mother.unwrap_or(a.p+P{x:0.,y:100.})}else if a.target_kind=="ship"{a.target_id.as_str().and_then(|id|self.naval.contacts[side].iter().find(|c|c.id==id)).and_then(|c|self.naval.ship(c.ship)).filter(|s|s.alive()).map(|s|s.p).unwrap_or(a.target)}else if a.target_kind=="aircraft"{self.aircraft.iter().find(|p|Some(p.id as u64)==a.target_id.as_u64()&&p.hp>0.).map(|p|p.p).unwrap_or(a.target)}else{a.target};
            let delta=target-a.p;let distance=delta.dist(P::default());
            if self.carrier_is_v2(){self.carrier_v2_fly(&mut a,target);}else{let step=(a.speed*DT).min(distance);if distance>0.01{a.heading=delta.heading();a.p=a.p+delta*(step/distance);}a.fuel=(a.fuel-step-a.speed*DT*0.1).max(0.);}
            if a.fuel<=0.{a.hp=0.;losses.push(i);}else if a.phase=="returning"&&mother.is_some()&&a.p.dist(mother.unwrap())<=120.{
                if !self.deck.get(&a.carrier).is_some_and(|n|*n>frame){returns.push((i,a.hp));self.deck.insert(a.carrier,frame+30);a.phase="recovered";a.hp=0.;}
            }else if self.carrier_ops.is_some()&&a.mission=="patrol"&&a.phase!="returning"&&(distance<=180.||self.carrier_is_v2()&&distance<=carrier_ops_v2::PATROL_ENTRY){
                a.phase="patrolling";if mother.is_some_and(|p|a.fuel<=a.p.dist(p)+if self.carrier_is_v2(){carrier_ops_v2::LANDING_FUEL_RESERVE}else{800.}){a.phase="returning";}
            }else if a.phase!="returning"&&distance<=180.{
                if a.weapons>0&&a.mission=="strike"&&(!self.carrier_is_v3()||a.target_kind!="land"||self.carrier_v3_safe_land(a.p)) {attacks.push((i,a.p,a.target_kind.clone(),a.target_id.clone(),a.role));a.weapons-=1;}
                a.phase="returning";
            }else if a.phase!="returning"&&mother.is_some_and(|p|a.fuel<=a.p.dist(p)+if self.carrier_is_v2(){carrier_ops_v2::LANDING_FUEL_RESERVE}else{800.}){a.phase="returning";}
            // Actual finite ground AA battery fire, shared cooldown and ammo.
            for b in &mut self.ground.buildings{if b.ally==(side==0)||b.hp<=0.||b.kind!="aa"||b.ammo==0||frame<b.next||b.p.dist(a.p)>2100.{continue}b.ammo-=1;b.next=frame+20;a.hp-=32.;if a.hp<=0.{losses.push(i);break;}}
            for b in &mut self.ground.bodies{if b.ally==(side==0)||!b.active||b.hp<=0.||b.kind!="aa_team"||b.ammo==0||frame<b.next||b.p.dist(a.p)>b.range{continue}b.ammo-=1;b.next=frame+b.reload;a.hp-=b.damage;if a.hp<=0.{losses.push(i);break;}}
            self.aircraft[i]=a;
        }
        for(i,p,kind,id,role)in attacks{
            if self.aircraft[i].hp<=0.{continue}let side=self.naval.ship(self.aircraft[i].carrier).map_or(0,|s|s.side);
            if kind=="ship"{let target=id.as_str().and_then(|id|self.naval.contacts[side].iter().find(|c|c.id==id)).map(|c|c.ship);if let Some(id)=target{if let Some(ship)=self.naval.ship_mut(id){if ship.p.dist(p)<450.&&ship.alive(){ship.hp=(ship.hp-match role{"torpedo_bomber"=>90.,"dive_bomber"=>60.,_=>10.}).max(0.);}}}}
            else if kind=="aircraft"{if let Some(enemy)=self.aircraft.iter_mut().find(|a|Some(a.id as u64)==id.as_u64()&&a.hp>0.&&a.p.dist(p)<600.){enemy.hp=(enemy.hp-55.).max(0.);}}
            else {self.ground.blast(p,if role=="dive_bomber"{95.}else{45.},if role=="dive_bomber"{250.}else{160.},side==0,false,"air_strike",format!("aircraft:{}",self.aircraft[i].id).as_str());}
            self.ground.event("air_attack","航空武器已实际投放，有限弹药减少",p);
            bounded(&mut self.ground.shots,json!({"id":format!("air-{}-{}",self.aircraft[i].id,frame),"frame":frame,"tick":frame as f64/10.,"kind":"air_weapon","source":format!("aircraft:{}",self.aircraft[i].id),"side":if side==0{"allies"}else{"axis"},"x":p.x,"y":p.y,"target_x":p.x,"target_y":p.y,"damage":if role=="torpedo_bomber"{90}else if role=="dive_bomber"{60}else{10}}));
        }
        for(i,a)in self.aircraft.iter().enumerate(){if a.hp<=0.&&!["recovered","lost"].contains(&a.phase){losses.push(i);}}
        returns.sort_by_key(|(i,_)|*i);returns.dedup_by_key(|(i,_)|*i);for(i,hp)in returns{let a=&self.aircraft[i];let s=&mut self.squadrons[a.squadron];s.available+=1;s.health.push(hp);s.stock+=a.weapons;s.ready=s.ready.max(frame+200);self.ground.event("air_recovered","飞机已实际返舰，正在整备",a.p);}
        losses.sort_unstable();losses.dedup();for i in losses{let a=&self.aircraft[i];if a.phase=="recovered"{continue}let s=&mut self.squadrons[a.squadron];s.lost+=1;self.aircraft[i].phase="lost";self.ground.event("air_lost","飞机因实际损伤或燃油耗尽而损失",self.aircraft[i].p);}
        // Carrier loss destroys only aircraft still physically on deck. Airborne
        // aircraft remain airborne until their own fuel/AA/recovery outcome.
        for s in &mut self.squadrons{if self.naval.ship(s.carrier).is_none_or(|c|!c.alive())&&s.available>0{s.lost+=s.available;s.available=0;s.health.clear();}}
        // Completed instances have no authoritative future; bounded active
        // history is represented by stable monotonic IDs and squadron totals.
        self.aircraft.retain(|a|a.hp>0.);
        self.sync_to_naval();
    }
    fn air_view(&self)->Value{
        let squadrons=self.squadrons.iter().filter(|s|self.naval.ship(s.carrier).is_some_and(|c|c.side==0)).map(|s|{let carrier=self.naval.ship(s.carrier);let reason=if carrier.is_none_or(|c|!c.alive()){Some("母舰损失")}else if s.available==0{Some("飞机在空或已损失")}else if s.stock==0{Some("航空武器库存耗尽")}else if s.ready>self.ground.frame{Some("飞机整备中")}else if self.deck.get(&s.carrier).is_some_and(|n|*n>self.ground.frame){Some("真实甲板忙碌")}else{None};json!({"id":s.id,"carrier":s.carrier,"carrier_identity":carrier.map(|c|self.naval.data.ships[c.def].id.clone()),"role":s.role,"name":s.model,"visual_type":s.model,"available":s.available,"total":s.total,"airborne":self.aircraft.iter().filter(|a|a.squadron==self.squadrons.iter().position(|t|t.id==s.id).unwrap()&&a.hp>0.).count(),"lost":s.lost,"ready_in":s.ready.saturating_sub(self.ground.frame)as f64/10.,"ammunition":s.stock,"max_range":s.range,"reason":reason})}).collect::<Vec<_>>();
        let aircraft=self.aircraft.iter().filter(|a|a.hp>0.).map(|a|json!({"id":a.id,"squadron_id":self.squadrons[a.squadron].id,"carrier":a.carrier,"kind":a.model,"visual_type":a.model,"side":if self.naval.ship(a.carrier).is_some_and(|s|s.side==0){"allies"}else{"axis"},"phase":a.phase,"x":a.p.x,"y":a.p.y,"heading":a.heading,"hp":a.hp,"max_hp":a.max,"weapon_remaining":a.weapons,"fuel_remaining":a.fuel,"target_kind":a.target_kind,"target_id":a.target_id})).collect::<Vec<_>>();
        json!({"version":"fictional-air-v1","squadrons":squadrons,"aircraft":aircraft,"budget":24,"deck_policy":"serial_launch_and_recovery","source_note":"docs/rules/littoral-v4-source-notes.md"})
    }
    fn preview(&self,q:&Value)->E<Value>{
        let normalized=self.company_request(q)?;let q=&normalized;
        let plan=(||->E<Value>{match q["kind"].as_str(){
            Some("air")=>{let(i,action,p,kind,id)=self.air_plan(q)?;let s=&self.squadrons[i];Ok(json!({"valid":true,"squadron_id":s.id,"action":action,"target":p,"target_kind":kind,"target_id":id,"range":s.range,"reason":"仅验证实际母舰、甲板、飞机、武器与航程；命中须实际飞行裁决"}))},
            Some("deploy")=>{let(gi,si,beach,air,path)=self.ground.deployment_plan(q)?;let(sea,land)=self.ground.beach_for(beach)?;let limit=if air{flight_range(self.ground.groups[gi].card.id)}else{900.};let distance=self.ground.ships[si].p.dist(if air{land}else{sea});if !path.is_empty(){let fleet=self.naval.ship(self.ground.ships[si].id).and_then(|s|s.fleet).ok_or("载舰编队无效")?;let route=self.naval.preview(0,&json!({"fleet":fleet,"mode":"follow","points":[sea],"speed":18}))?;if route["valid"]==false{return Err(route["error"].as_str().unwrap_or("真实航线不可达").into())}}Ok(json!({"valid":true,"unit_id":self.ground.groups[gi].card.id,"carrier":self.ground.ships[si].id,"beach":beach,"sea":sea,"land":land,"range_limit":limit,"distance":distance,"can_launch_now":distance<=limit,"path":path,"reason":"舰位、资格、航程和真实海战航线已核验"}))},
            Some("naval")|Some("aim_land")=>{let id=crate::world::u(q,"ship")?;let p=self.ground.position_for(q)?;self.shore_plan(id,p)?;let s=self.naval.ship(id).unwrap();Ok(json!({"valid":true,"ship":id,"target":p,"ready_for_target":self.shore_ready(id,p),"distance":s.p.dist(p),"reason":"真实炮座射界及余弹合法；按原战役装填和训练"}))},
            Some("ship_move")=>{let id=crate::world::u(q,"ship")?;let fleet=self.naval.ship(id).filter(|s|s.side==0).and_then(|s|s.fleet).ok_or("舰艇无效")?;self.naval.preview(0,&json!({"fleet":fleet,"mode":"follow","points":[self.ground.position_for(q)?],"speed":q.get("speed").cloned().unwrap_or(json!(25))}))},
            _=>Err("预览类型无效".into())}})();Ok(plan.unwrap_or_else(|reason|json!({"valid":false,"reason":reason})))
    }
}

fn generate_town(ground:&mut Littoral)->Value{
    let mut roads=vec![];
    for x in [12060.,12300.,12540.,12780.]{roads.push(json!({"points":[{"x":x,"y":12300.},{"x":x,"y":13400.}],"width":24}));}
    for y in [12480.,12640.,12800.,12960.,13120.]{roads.push(json!({"points":[{"x":11900.,"y":y},{"x":13000.,"y":y}],"width":24}));}
    let mut buildings=vec![];let mut rng=ground.seed as u64^0x98de_143a;
    // Metres, not oversized symbols: compact seeded street parcels have the
    // identical physical footprint used by ground collision and presentation.
    for y in [12400.,12560.,12720.,12880.,13040.,13200.] {for x in [12000.,12120.,12240.,12360.,12480.,12600.,12720.,12840.] {
        let center=P{x:x+(crate::world::roll(&mut rng,31)as f64-15.),y:y+(crate::world::roll(&mut rng,31)as f64-15.)};
        if ground.buildings.iter().any(|b|b.p.dist(center)<160.)||ground.ruins.iter().any(|r|r.p.dist(center)<160.)||ground.bodies.iter().any(|b|b.p.dist(center)<100.){continue}
        let w=30.+crate::world::roll(&mut rng,50)as f64;let h=30.+crate::world::roll(&mut rng,40)as f64;
        let footprint=vec![P{x:center.x-w/2.,y:center.y-h/2.},P{x:center.x+w/2.,y:center.y-h/2.},P{x:center.x+w/2.,y:center.y+h/2.},P{x:center.x-w/2.,y:center.y+h/2.}];
        if footprint.iter().any(|p|!ground.walkable(*p,true))||footprint.iter().any(|p|(elevation_m(*p)-elevation_m(center)).abs()>5.){continue}
        ground.obstacles.push(footprint.clone());let variant=crate::world::roll(&mut rng,12)-1;let floors=[2,4,1,6,1,2,1,3,3,2,4,2][variant as usize];
        buildings.push(json!({"id":format!("town-{}",buildings.len()+1),"footprint":footprint,"width_m":w,"length_m":h,"elevation_m":elevation_m(center),"floors":floors,"height_m":floors as f64*3.2,"art_variant":variant,"roof_style":(["terrace","gable","workshop"][crate::world::roll(&mut rng,3)as usize-1]),"palette":(["coral","cobalt","ochre","mint"][crate::world::roll(&mut rng,4)as usize-1])}));
    }}
    json!({"version":"town-blocks-v1","units":"metres","roads":roads,"buildings":buildings})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]fn a_real_hit_changes_only_the_selected_company_not_its_sibling(){let mut c=config(&["MCP-034","MCP-009"]);c.company_layout=Some(MULTI.into());let mut w=Battle::new(42,c).unwrap();for id in ["MCP-034-C01","MCP-034-C02"]{w.command(&json!({"op":"littoral_deploy","company_id":id,"beach":2,"queue":true}),true).unwrap();}advance(&mut w,250);let first=w.ground.groups.iter().position(|g|g.card.id=="MCP-034-C01").unwrap();let second=w.ground.groups.iter().position(|g|g.card.id=="MCP-034-C02").unwrap();let p=w.ground.groups[first].p+P{x:320.,y:0.};w.command(&json!({"op":"littoral_order","company_id":"MCP-034-C01","action":"move","x":p.x,"y":p.y}),true).unwrap();advance(&mut w,150);let p=w.ground.bodies.iter().find(|b|b.group=="MCP-034-C01"&&b.hp>0.).unwrap().p;assert!(w.ground.bodies.iter().filter(|b|b.group=="MCP-034-C02").all(|b|b.p.dist(p)>25.1));let before_first=w.ground.group_health(first);let before_second=w.ground.group_health(second);w.ground.blast(p,100.,0.1,false,false,"rifle","test-real-hit");assert!(w.ground.group_health(first)<before_first);assert_eq!(w.ground.group_health(second),before_second);let v=w.view();let rows=v["littoral"]["groups"].as_array().unwrap();assert_ne!(rows.iter().find(|g|g["id"]=="MCP-034-C01").unwrap()["hp_percent"],rows.iter().find(|g|g["id"]=="MCP-034-C02").unwrap()["hp_percent"]);}
    #[test]fn destroyed_transport_leaves_one_actual_wreck_after_parent_removal(){let mut w=battle();w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-001","beach":2,"queue":true}),true).unwrap();advance(&mut w,1);let t=w.ground.transports[0].clone();w.ground.blast(t.p,10000.,1.,false,false,"anti_air","test-real-blast");assert!(w.ground.transports[0].hp<=0.);advance(&mut w,1);assert!(w.ground.transports.is_empty());let wreck=w.corpses.iter().find(|c|c["id"]==t.id).unwrap().clone();assert_eq!(wreck["kind"],"transport_wreck");assert_eq!(wreck["x"],t.p.x);assert_eq!(wreck["y"],t.p.y);advance(&mut w,10);assert_eq!(w.corpses.iter().filter(|c|c["id"]==t.id).count(),1);assert_eq!(w.corpses.iter().find(|c|c["id"]==t.id).unwrap(),&wreck);}
    #[test]fn multiple_companies_are_distinct_real_bodies_and_independent_orders(){let mut c=config(&["MCP-034","MCP-009"]);c.company_layout=Some(MULTI.into());let mut w=Battle::new(42,c).unwrap();assert_eq!(w.ground.groups.len(),7);assert!(w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"queue":true}),true).is_err());for company in ["MCP-034-C01","MCP-034-C02"]{w.command(&json!({"op":"littoral_deploy","company_id":company,"beach":2,"queue":true}),true).unwrap();}advance(&mut w,300);for key in ["MCP-034-C01","MCP-034-C02"]{assert_eq!(w.ground.bodies.iter().filter(|b|b.group==key).count(),9);}let row=w.view()["littoral"]["groups"].as_array().unwrap().iter().find(|r|r["id"]=="MCP-034-C01").unwrap().clone();let p=row["position"].clone();w.command(&json!({"op":"littoral_order","company_id":"MCP-034-C01","action":"move","x":p["x"].as_f64().unwrap()+100.,"y":p["y"]}),true).unwrap();assert_eq!(w.ground.groups.iter().find(|g|g.card.id=="MCP-034-C02").unwrap().order,"hold");let v=w.view();assert_eq!(v["littoral"]["groups"][0]["unit_id"],"MCP-034");assert_eq!(v["littoral"]["land"]["entities"].as_array().unwrap().iter().find(|b|b["company_id"]=="MCP-034-C01").unwrap()["unit_id"],"MCP-034");assert_eq!(v["presentation"],w.naval.projectile_presentation(0));assert_eq!(Battle::from_save(w.save(),None).unwrap().view(),v);}
    #[test]fn multi_company_budget_slots_and_aggregate_loss_do_not_duplicate_rewards(){let mut c=config(&["MCP-034","MCP-116","MCP-167","MCP-011","MCP-103"]);c.company_layout=Some(MULTI.into());c.mode="defense".into();c.lesson=None;let mut w=Battle::new(42,c).unwrap();assert_eq!(w.ground.groups.len(),21);assert_eq!(w.ground.bodies.iter().filter(|b|b.ally).count(),181);assert_eq!(w.view()["littoral"]["budget"]["friendly_bodies"],250);w.command(&json!({"op":"littoral_abandon"}),true).unwrap();let v=w.view();assert_eq!(v["result"]["companies"].as_array().unwrap().len(),21);assert_eq!(v["result"]["units"].as_array().unwrap().len(),5);assert_eq!(v["result"]["resources"],json!({"scrap":0,"alloy":0,"protocols":0,"credits":0}));assert_eq!(carrier_personnel_capacity("IBS-U-USN-FLETCHER",100).unwrap(),48);assert_eq!(company_personnel_slots("MCP-034","landing_craft",9).unwrap(),9);assert_eq!(company_personnel_slots("MCP-001","helicopter",8).unwrap(),24);assert_eq!(company_personnel_slots("MCP-022","amphibious_vehicle",6).unwrap(),24);}
    #[test]fn actual_public_enemy_101_at_rock_edge_is_attackable_without_teleport(){let mut w=battle();let initial=w.ground.bodies.iter().find(|b|b.id==101).unwrap().p;assert_eq!(initial,P{x:12080.,y:12280.});assert!(w.ground.walkable(initial,true));w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"queue":true}),true).unwrap();advance(&mut w,183);let enemy=w.ground.bodies.iter().find(|b|b.id==101).unwrap().clone();assert!(w.ground.walkable(enemy.p,true));w.command(&json!({"op":"littoral_order","unit_id":"MCP-034","action":"attack","target":101,"x":enemy.p.x,"y":enemy.p.y}),true).unwrap();assert_eq!(w.ground.bodies.iter().find(|b|b.id==101).unwrap().p,enemy.p);let poly=&w.ground.obstacles[0];let center=P{x:(poly[0].x+poly[2].x)/2.,y:(poly[0].y+poly[2].y)/2.};assert!(!w.ground.walkable(center,true));assert!(!w.ground.clear(center-P{x:500.,y:0.},center+P{x:500.,y:0.},true));}
    #[test]fn defense_garrison_ignores_outbound_capacity_but_recovery_requires_real_compatible_space(){let mut c=config(&["MCP-034","MCP-001"]);c.mode="defense".into();c.lesson=None;c.company_layout=Some(MULTI.into());c.ships=vec![Hull{id:"IBS-U-USN-FLETCHER".into(),hp:100.,ammo:100}];let mut w=Battle::new(42,c).unwrap();assert_eq!(w.ground.bodies.iter().filter(|b|b.ally).count(),69);assert!(w.ground.groups.iter().all(|g|g.stage=="ground"));let air=w.ground.groups.iter().position(|g|unit_id(g.card.id)=="MCP-001").unwrap();assert!(w.ground.return_carrier(air).is_none());let marine=w.ground.groups.iter().position(|g|g.card.id=="MCP-034-C01").unwrap();assert_eq!(w.ground.return_carrier(marine),Some(1));for g in w.ground.groups.iter_mut().filter(|g|unit_id(g.card.id)=="MCP-034"){g.stage="recovered";}assert_eq!(w.ground.ships[0].slots,48);assert_eq!(w.ground.return_carrier(marine),Some(1));assert!(w.ground.return_carrier(air).is_none());let v=w.view();assert_eq!(Battle::from_save(w.save(),None).unwrap().ground.config.company_layout.as_deref(),Some(MULTI));assert_eq!(v["littoral"]["groups"].as_array().unwrap().len(),8);}
    #[test]fn real_scale_and_continuous_terrain_are_authoritative(){let w=battle();let x0=w.ground.polygon.iter().map(|p|p.x).fold(f64::INFINITY,f64::min);let x1=w.ground.polygon.iter().map(|p|p.x).fold(0.,f64::max);let y0=w.ground.polygon.iter().map(|p|p.y).fold(f64::INFINITY,f64::min);let y1=w.ground.polygon.iter().map(|p|p.y).fold(0.,f64::max);assert!((4000. ..5500.).contains(&(x1-x0)));assert!((5000. ..6500.).contains(&(y1-y0)));for b in w.town["buildings"].as_array().unwrap(){assert!((30. ..=80.).contains(&b["width_m"].as_f64().unwrap()));}let edge=map_position(P{x:10600.,y:5800.});assert!(elevation_m(edge).abs()<1e-9);assert!((elevation_m(edge+P{x:0.,y:1.})-40./120.).abs()<1e-8);let high=map_position(P{x:14500.,y:5200.});assert_eq!(elevation_m(high),80.);assert_eq!(cover_multiplier(high),0.8);let v=w.view();assert_eq!(v["littoral"]["land"]["terrain"]["height_model"],"inset_edge_blend_v1");assert!(v["littoral"]["land"]["buildings"].as_array().unwrap().iter().all(|b|b["width_m"].as_f64().unwrap()<=70.));}
    #[test]fn elevated_cover_reduces_actual_ground_damage_but_not_shore_blast(){fn damage(p:P,kind:&str)->f64{let mut w=battle();w.ground.body("MCP-034".into(),true,"rifle",p,100.);let i=w.ground.bodies.len()-1;let hp=w.ground.bodies[i].hp;w.ground.blast(p,10.,1.,false,false,kind,"terrain-test");hp-w.ground.bodies[i].hp}let low=map_position(P{x:13000.,y:8500.});let high=map_position(P{x:14500.,y:5200.});assert!((damage(high,"rifle")/damage(low,"rifle")-0.8).abs()<1e-8);assert!((damage(high,"naval")/damage(low,"naval")-1.).abs()<1e-8);}
    fn config(roster:&[&str])->Config {Config{mode:"tutorial".into(),company_layout:None,lesson:Some("landing".into()),ships:vec![Hull{id:"IBS-U-USN-ERMA-IOWA".into(),hp:100.,ammo:100},Hull{id:ENTERPRISE.into(),hp:100.,ammo:100}],roster:roster.iter().map(|s|s.to_string()).collect(),unit_condition:vec![],transport_preset:"combat".into(),defense:vec![],company_transports:vec![]}}
    fn battle()->Battle{Battle::new(42,config(&["MCP-034","MCP-001"])).unwrap()}
    fn advance(w:&mut Battle,n:u32){for _ in 0..n{w.advance();}}
    #[test]fn aim_without_firing_trains_real_mounts_without_spending(){let mut w=battle();let id=1;let p=w.ground.ruins[0].p;let before=w.naval.salvage_gun_supply(w.naval.ship(id).unwrap());w.command(&json!({"op":"littoral_ship_order","action":"aim_land","ship":id,"x":p.x,"y":p.y}),true).unwrap();advance(&mut w,100);assert!(w.shore_ready(id,p));assert_eq!(w.naval.salvage_gun_supply(w.naval.ship(id).unwrap()),before);assert!(!w.ground.shots.iter().any(|s|s["kind"]=="naval"));}
    #[test]fn partial_tube_loading_never_spends_phantom_rounding_ammunition(){let mut c=config(&["MCP-034","MCP-001"]);c.transport_preset="balanced".into();c.ships.push(Hull{id:"IBS-U-USN-FLETCHER".into(),hp:100.,ammo:100});let w=Battle::new(42,c).unwrap();let s=w.naval.ship(3).unwrap();assert_eq!(s.ammo,6);assert_eq!(w.naval.salvage_gun_supply(s),70);}
    #[test]fn npc_aircraft_launch_from_actual_enemy_cv_and_are_not_player_commandable(){let mut c=config(&["MCP-034","MCP-001"]);c.mode="raid".into();c.lesson=None;let mut w=Battle::new(42,c).unwrap();advance(&mut w,350);let enemy=w.aircraft.iter().find(|a|w.naval.ship(a.carrier).unwrap().side==1).unwrap();assert_eq!(w.naval.data.ships[w.naval.ship(enemy.carrier).unwrap().def].id,SHOKAKU);let id=w.squadrons[enemy.squadron].id.clone();assert!(w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"return"}),true).is_err());assert!(w.aircraft.len()<=24);let save=w.save();assert_eq!(Battle::from_save(save,None).unwrap().view(),w.view());}
    #[test]fn restored_aircraft_keep_actual_condition_without_automatic_healing(){let mut w=battle();let id=w.squadrons[1].id.clone();w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"strike","x":10650.,"y":11440.}),true).unwrap();w.aircraft[0].hp=37.;advance(&mut w,700);assert!(w.squadrons[1].health.contains(&37.));w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"strike","x":10650.,"y":11440.}),true).unwrap();assert!(w.aircraft.iter().any(|a|a.hp==37.));}
    #[test]fn printed_carriers_use_verified_dp_speed_armor_and_thresholds(){let d=extended_data().unwrap();let us=d.ships.iter().find(|s|s.id==ENTERPRISE).unwrap();assert_eq!((us.dp,us.max_knots,us.armor_belt,us.armor_deck),(628.,32.,8.,3.));assert_eq!(us.damage_speed[1].damage,157.);assert_eq!(us.damage_speed[4].damage,565.);assert_eq!(us.gun.mounts.len(),8);let jp=d.ships.iter().find(|s|s.id==SHOKAKU).unwrap();assert_eq!((jp.dp,jp.max_knots,jp.armor_belt,jp.armor_deck),(742.,34.,8.,6.));assert_eq!(jp.damage_speed[1].damage,186.);assert_eq!(jp.gun.range_yd,vec![4800.,9600.,12800.,16000.]);assert_eq!(jp.gun.mounts.len(),8);assert_eq!(jp.gun.barrels,16);}
    #[test]fn new_cards_never_mutate_old_data_or_points(){let old=crate::salvage_v3::expedition_data().unwrap();let new=extended_data().unwrap();for s in &old.ships{let n=new.ships.iter().find(|n|n.id==s.id).unwrap();assert_eq!(format!("{s:?}"),format!("{n:?}"));}assert!(!old.ships.iter().any(|s|s.id==ENTERPRISE));assert!(ship_points(ENTERPRISE).is_some());assert!(ship_points("IBS-U-USN-FLETCHER").is_none());}
    #[test]fn ordinary_warships_carry_complete_marine_companies_but_never_armor_or_air(){for ship in ["IBS-U-USN-FLETCHER","IBS-U-IJN-NISSHIN","IBS-U-USN-ERMA-IOWA"]{assert!(carrier_eligibility("MCP-034","landing_craft",ship).is_ok());assert!(carrier_eligibility("MCP-022","amphibious_vehicle",ship).is_err());assert!(carrier_eligibility("MCP-001","helicopter",ship).is_err());}for ship in [ENTERPRISE,SHOKAKU,LHA]{assert!(carrier_eligibility("MCP-022","amphibious_vehicle",ship).is_ok());assert!(carrier_eligibility("MCP-001","helicopter",ship).is_ok());}assert!(carrier_eligibility("MCP-022","amphibious_vehicle",APV).is_ok());assert!(carrier_eligibility("MCP-001","helicopter",APV).is_err());assert!(carrier_capacity("IBS-U-USN-FLETCHER",100).unwrap()>=company_slots("MCP-034","landing_craft").unwrap());}
    #[test]fn incompatible_carrier_is_rejected_before_state_exists(){let mut c=config(&["MCP-034","MCP-001"]);c.ships.retain(|s|s.id!=ENTERPRISE);assert!(Battle::new(42,c).is_err());let mut c=config(&["MCP-034","MCP-022"]);c.ships.retain(|s|s.id!=ENTERPRISE);assert!(Battle::new(42,c).is_err());}
    #[test]fn public_naval_view_is_the_actual_world_schema(){let w=battle();let v=w.view();assert_eq!(v["version"],VERSION);assert_eq!(v["ships"][0]["systems"]["guns"].as_array().unwrap().len(),3);assert_eq!(v["fleets"],w.naval.observation(0)["fleets"]);assert_eq!(v["contacts"],w.naval.observation(0)["contacts"]);assert_eq!(w.naval.version,crate::realtime::VERSION);}
    #[test]fn drag_deploy_uses_actual_eligible_carrier_and_transport_motion(){let mut w=battle();let group=w.ground.groups.iter().find(|g|g.card.id=="MCP-001").unwrap();assert_eq!(w.naval.data.ships[w.naval.ship(group.carrier).unwrap().def].id,ENTERPRISE);w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-001","beach":2,"queue":true}),true).unwrap();advance(&mut w,1);assert_eq!(w.ground.transports.len(),1);let origin=w.ground.transports[0].p;assert!(w.ground.bodies.iter().all(|b|b.group!="MCP-001"));advance(&mut w,10);assert!(w.ground.transports[0].p.dist(origin)>0.);advance(&mut w,100);assert_eq!(w.ground.groups.iter().find(|g|g.card.id=="MCP-001").unwrap().stage,"ground");}
    #[test]fn shore_support_trains_and_spends_the_same_actual_mount_and_gun_supply(){let mut w=battle();let ship=1;let p=w.ground.ruins[0].p;let initial=w.naval.salvage_gun_supply(w.naval.ship(ship).unwrap());w.command(&json!({"op":"littoral_support","kind":"naval","ship":ship,"x":p.x,"y":p.y,"queue":true}),true).unwrap();advance(&mut w,100);assert!(w.ground.shots.iter().any(|s|s["kind"]=="naval"));assert_eq!(w.naval.salvage_gun_supply(w.naval.ship(ship).unwrap()),initial-1);assert!((0..3).any(|i|!w.naval.turret_loaded(w.naval.ship(ship).unwrap(),i)));}
    #[test]fn original_torpedo_and_radar_interfaces_remain_real(){let mut c=config(&["MCP-034","MCP-001"]);c.ships.push(Hull{id:"IBS-U-USN-FLETCHER".into(),hp:100.,ammo:100});let mut w=Battle::new(42,c).unwrap();let v=w.view();let ship=&v["ships"][2];assert!(!ship["systems"]["tubes"].as_array().unwrap().is_empty());assert!(!ship["systems"]["radars"].as_array().unwrap().is_empty());let target=w.naval.contacts[0][0].id.clone();let r=w.execute(&json!({"op":"aim","ship":3,"weapon":"torpedo","target":target})).unwrap();assert!(r.is_object());assert_eq!(w.execute(&json!({"op":"presentation"})).unwrap(),w.naval.projectile_presentation(0));}
    #[test]fn aircraft_are_physical_finite_and_recover_before_rearming(){let mut w=battle();let id=w.squadrons.iter().find(|s|s.model=="SBD").unwrap().id.clone();w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"strike","x":10650.,"y":11440.,"target_kind":"land"}),true).unwrap();assert_eq!(w.aircraft.len(),3);assert_eq!(w.squadrons[1].stock,15);let p=w.aircraft[0].p;advance(&mut w,10);assert_eq!(w.aircraft[0].p,p);advance(&mut w,20);assert!(w.aircraft[0].p.dist(p)>0.);assert!(w.ground.events.iter().all(|e|e["kind"]!="air_attack"));advance(&mut w,600);assert!(w.aircraft.is_empty());assert_eq!(w.squadrons[1].available,3);assert_eq!(w.squadrons[1].lost,0);assert_eq!(w.squadrons[1].stock,15);assert!(w.ground.events.iter().any(|e|e["kind"]=="air_attack"));}
    #[test]fn aircraft_weapon_stock_depletes_without_free_replenishment(){let mut w=battle();let id=w.squadrons[1].id.clone();for _ in 0..6{w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"strike","x":10650.,"y":11440.}),true).unwrap();advance(&mut w,700);}assert_eq!(w.squadrons[1].stock,0);assert_eq!(w.squadrons[1].available,3);assert!(w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"strike","x":10650.,"y":11440.}),true).is_err());}
    #[test]fn deck_is_serial_and_torpedo_aircraft_cannot_bomb_land(){let mut w=battle();let id=w.squadrons[1].id.clone();w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"strike","x":10650.,"y":11440.}),true).unwrap();let id=w.squadrons[0].id.clone();assert!(w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"strike","x":10650.,"y":11440.}),true).is_err());let id=w.squadrons[2].id.clone();advance(&mut w,61);assert!(w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"strike","x":10650.,"y":11440.,"target_kind":"land"}),true).is_err());}
    #[test]fn carrier_loss_preserves_airborne_flight_but_destroys_actual_deck_aircraft(){let mut w=battle();let carrier=w.squadrons[1].carrier;let id=w.squadrons[1].id.clone();w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"strike","x":10650.,"y":11440.}),true).unwrap();advance(&mut w,61);w.naval.ship_mut(carrier).unwrap().hp=0.;advance(&mut w,1);assert!(w.aircraft.iter().any(|a|a.hp>0.));assert_eq!(w.squadrons[0].available,0);assert_eq!(w.squadrons[0].lost,3);advance(&mut w,5000);assert!(w.aircraft.is_empty());assert_eq!(w.squadrons[1].lost,3);}
    #[test]fn airborne_planes_cannot_be_silently_deleted_by_extract(){let mut w=battle();let id=w.squadrons[1].id.clone();w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"patrol","x":10650.,"y":11440.}),true).unwrap();let err=w.command(&json!({"op":"littoral_extract"}),true).unwrap_err();assert!(err.contains("飞机"));}
    #[test]fn dead_bodies_persist_at_actual_pose_and_live_recovery_never_becomes_a_corpse(){let mut w=battle();w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"queue":true}),true).unwrap();advance(&mut w,500);let i=w.ground.bodies.iter().position(|b|b.ally).unwrap();let p=w.ground.bodies[i].p;let id=w.ground.bodies[i].id;w.ground.bodies[i].hp=0.;w.record_corpses();let first=w.corpses.clone();assert!(first.iter().any(|c|c["id"]==id&&c["x"]==p.x&&c["y"]==p.y));w.ground.bodies[i].active=false;w.record_corpses();assert_eq!(w.corpses,first);let i=w.ground.bodies.iter().position(|b|b.ally&&b.hp>0.).unwrap();w.ground.bodies[i].active=false;w.record_corpses();assert_eq!(w.corpses,first);}
    #[test]fn full_save_replay_rebuilds_world_ground_air_and_poses(){let mut w=battle();let id=w.squadrons[1].id.clone();w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"strike","x":10650.,"y":11440.}),true).unwrap();w.command(&json!({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"queue":true}),true).unwrap();advance(&mut w,350);let restored=Battle::from_save(w.save(),None).unwrap();assert_eq!(restored.view(),w.view());assert_eq!(restored.naval.projectile_presentation(0),w.naval.projectile_presentation(0));let mut bad=w.save();bad.tick+=0.1;assert!(Battle::from_save(bad,None).is_err());}
    #[test]fn town_footprints_are_real_obstacles_and_every_key_route_is_reachable(){for seed in [1,42,43,44,6106]{let w=Battle::new(seed,config(&["MCP-034","MCP-001"])).unwrap();let buildings=w.town["buildings"].as_array().unwrap();assert!((24..=48).contains(&buildings.len()));for b in buildings{let p:Vec<P>=serde_json::from_value(b["footprint"].clone()).unwrap();let middle=P{x:(p[0].x+p[2].x)/2.,y:(p[0].y+p[2].y)/2.};assert!(!w.ground.walkable(middle,true));}for beach in 1..=3{let start=w.ground.beach_for(beach).unwrap().1;for r in &w.ground.ruins{assert!(w.ground.path(start,r.p,true).is_ok(),"seed {seed} beach{beach} ruin{}",r.id);}for h in &w.ground.buildings{assert!(w.ground.path(start,h.p,true).is_ok());}}}}
    #[test]fn defense_groups_stay_on_their_actual_island_positions(){let mut c=config(&["MCP-034","MCP-001"]);c.mode="defense".into();c.lesson=None;let w=Battle::new(42,c).unwrap();for g in &w.ground.groups{assert!(w.ground.walkable(g.p,true));assert_eq!(g.stage,"ground");}}
}

fn expand_ground(g:&mut Littoral,town:&mut Value){
    for p in &mut g.polygon{*p=map_position(*p);}for poly in &mut g.obstacles{for p in poly{*p=map_position(*p);}}
    for b in &mut g.bodies{b.p=map_position(b.p);}for b in &mut g.buildings{b.p=map_position(b.p);}for r in &mut g.ruins{r.p=map_position(r.p);}for m in &mut g.mines{m.p=map_position(m.p);}
    for group in &mut g.groups{if group.stage=="ground"{group.p=map_position(group.p);}}
    for road in town["roads"].as_array_mut().unwrap(){let points:Vec<P>=serde_json::from_value(road["points"].clone()).unwrap();road["points"]=json!(points.into_iter().map(map_position).collect::<Vec<_>>());road["width"]=json!(900);}
    for building in town["buildings"].as_array_mut().unwrap(){let poly:Vec<P>=serde_json::from_value(building["footprint"].clone()).unwrap();let poly:Vec<_>=poly.into_iter().map(map_position).collect();let center=P{x:(poly[0].x+poly[2].x)/2.,y:(poly[0].y+poly[2].y)/2.};building["footprint"]=json!(poly);building["elevation_m"]=json!(elevation_m(center));}
}
fn terrain_view(polygon:&[P])->Value{
    let zones=vec![json!({"id":"coastal_plain","polygon":polygon,"level":0,"height_m":0,"cover_multiplier":1.,"label":"西岸平原"}),
        json!({"id":"western_terrace","polygon":rect_source(10600.,5200.,12300.,6400.),"level":1,"height_m":40,"blend_width_m":120,"cover_multiplier":0.9,"label":"钟楼缓坡"}),
        json!({"id":"eastern_ridge","polygon":rect_source(13700.,4000.,16200.,6400.),"level":2,"height_m":80,"blend_width_m":120,"cover_multiplier":0.8,"label":"东部高地"})];
    json!({"height_model":"inset_edge_blend_v1","elevation_zones":zones,"ramps":[{"points":[map_position(P{x:11000.,y:6900.}),map_position(P{x:11000.,y:6100.})],"width":360,"from_level":0,"to_level":1},{"points":[map_position(P{x:14500.,y:6900.}),map_position(P{x:14500.,y:5900.})],"width":360,"from_level":0,"to_level":2}],"height_los":false,"effect":"地面轻重火力伤害随坡度乘0.9/0.8；舰炮、空袭和地雷不享此掩护"})
}
fn rect_source(x:f64,y:f64,r:f64,b:f64)->Vec<P>{[P{x,y},P{x:r,y},P{x:r,y:b},P{x,y:b}].into_iter().map(map_position).collect()}
