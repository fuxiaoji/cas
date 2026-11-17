//! Original, opt-in land missions in the existing naval extraction World.
//! Old worlds never construct Run, and all rewards remain real cargo pickups.
use crate::{model::*, salvage::{Start, Ruin}, world::World};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet, BinaryHeap};
use std::cmp::Reverse;

pub const VERSION: &str = "cas-adventure-v3";
pub const LAND_VERSION: &str = "cas-amphibious-expedition-v1";
pub const COMPANY_LAYOUT:&str="multi-company-v1";
const MAX_COMPANIES: usize = 5;
const MAX_LAND_ENEMIES: usize = 36;
const MAX_SEA_REINFORCEMENTS: u32 = 16;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config { pub companies: Vec<CompanyStart>, #[serde(default,skip_serializing_if="String::is_empty")]pub company_layout:String }
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CompanyStart {
    #[serde(default,skip_serializing_if="String::is_empty")]pub company_id:String,
    pub unit_id: String,
    pub carrier_identity: String,
    pub transport_kind: String,
    pub condition_percent: u32,
}
impl CompanyStart {fn key(&self)->&str{if self.company_id.is_empty(){&self.unit_id}else{&self.company_id}}}
#[derive(Clone, Debug)]
pub struct Company {
    pub start: CompanyStart, pub carrier: u32, pub count: u32,
    pub hp_per_body: f64, pub damage: f64, pub range: f64, pub reload: f64,
    pub speed: f64, pub stage: String, pub island: Option<u32>,
    pub p: P, pub target: P, pub order: String, pub task: Option<u32>,
    pub transit_start: P, pub transit_target: P, pub transit_started: u32,
    pub transit_seconds: u32, pub initial_transport_hp: f64, pub transport_hp: f64,
    pub transport_ammo: u32, pub landed: bool, pub entered_at: u32,
    pub body_templates: Vec<Value>,
}
#[derive(Clone, Debug)]
pub struct Body {
    pub id: u32, pub unit: String, pub company:String, pub ally: bool, pub kind: String, pub island: u32,
    pub p: P, pub hp: f64, pub max: f64, pub ammo: u32,
    pub damage: f64, pub range: f64, pub reload: f64, pub ready: f64,
    pub speed: f64, pub h: f64, pub order: String, pub attack_at: Option<f64>,
    pub aim: P, pub death_tick: Option<f64>, pub pose: u32,
}
#[derive(Clone, Debug)]
pub struct LandTask {
    pub id: u32, pub kind: String, pub title: String, pub island: u32,
    pub p: P, pub shore: P, pub beach: P, pub polygon: Vec<P>,
    pub status: String, pub progress: f64, pub duration: f64,
    pub reward_ruin: Option<u32>,
    pub terrain: Value,
}
#[derive(Clone, Debug)]
pub struct Run {
    pub config: Config, pub companies: Vec<Company>, pub tasks: Vec<LandTask>,
    pub bodies: Vec<Body>, pub shots: Vec<Value>, pub impacts: Vec<Value>,
    pub next_body: u32, pub next_shot: u32, pub sea_spawned: u32,
    pub next_sea_wave: u32, pub next_land_wave: u32, pub announced_sea: bool,
    pub announced_land: bool, pub land_spawned: u32, pub land_done: bool,
    pub ai_reason: String, pub ai_commands: u32, pub route_at: BTreeMap<u32,u32>,
    pub failed_tasks:BTreeSet<u32>, pub failures:BTreeMap<u32,u32>,
    pub rng: u64,
}

pub fn is_version(profile: &str) -> bool { profile == VERSION }

pub fn validate(start: &Start) -> E<()> {
    if !is_version(&start.gameplay_profile) {
        return if start.amphibious_expedition.is_some() { Err("旧航次不能带海陆任务配置".into()) } else { Ok(()) };
    }
    crate::expedition::validate(start)?;
    let c = start.amphibious_expedition.as_ref().ok_or("海陆搜打撤缺少部队配置")?;
    let multi=c.company_layout==COMPANY_LAYOUT;
    if !c.company_layout.is_empty()&&!multi{return Err("未登记陆军连队布局版本".into());}
    if c.companies.is_empty() || c.companies.len()>if multi{25}else{MAX_COMPANIES} { return Err("携带陆军数量超过本版本上限".into()); }
    let mut seen=BTreeSet::new(); let mut slots=BTreeMap::<String,u32>::new();
    let mut total=0;
    for company in &c.companies {
        let hull=start.fleet.iter().find(|h|h.id==company.carrier_identity).ok_or("部队搭载舰不在本航次舰队")?;
        if !seen.insert(company.key().to_string()) || !(10..=100).contains(&company.condition_percent) { return Err("战术连队身份重复或整备不足".into()); }
        if multi {let (count,personnel)=crate::littoral_v4::company_layout(&company.unit_id);if !(1..=count).any(|n|company.company_id==format!("{}-C{n:02}",company.unit_id)){return Err("连队编号不属于本人格登记编制".into());}total+=personnel;}else if !company.company_id.is_empty(){return Err("旧单连配置不能携带多连编号".into());}
        crate::littoral_v4::carrier_eligibility(&company.unit_id,&company.transport_kind,&company.carrier_identity)?;
        *slots.entry(company.carrier_identity.clone()).or_default()+=if multi{crate::littoral_v4::company_personnel_slots(&company.unit_id,&company.transport_kind,crate::littoral_v4::company_layout(&company.unit_id).1)?}else{crate::littoral_v4::company_slots(&company.unit_id,&company.transport_kind)?};
        let capacity=if multi{crate::littoral_v4::carrier_personnel_capacity(&hull.id,hull.ammo)?}else{crate::littoral_v4::carrier_capacity(&hull.id,hull.ammo)?};
        if slots[&company.carrier_identity]>capacity { return Err("搭载舰舱位不足，请分配其他舰艇或减少弹药装载".into()); }
    }
    if total>250{return Err("本次真实陆军身体超过250上限".into());}
    Ok(())
}

fn profile(id: &str) -> E<Value> {
    let catalogue=crate::littoral::catalogue_version(crate::littoral::VERSION_V3)?;
    catalogue["cards"].as_array().ok_or("战术编制表缺失")?.iter().find(|p|p["id"]==id).cloned().ok_or("未登记战术编制".into())
}
fn number(p:&Value,key:&str,fallback:f64)->f64 { p[key].as_f64().unwrap_or(fallback) }
fn centroid(poly:&[P])->P { poly.iter().copied().fold(P::default(),|a,b|a+b)*(1./poly.len().max(1) as f64) }
fn inside(poly:&[P],p:P)->bool { crate::salvage::polygon_near(poly,p,0.) }
fn advance_toward(p:P,target:P,distance:f64)->P { let d=target-p;if d.len()<=distance{target}else{p+d.unit()*distance} }
fn family_speed(kind:&str)->f64 { match kind { "helicopter"=>260.,"amphibious_vehicle"=>95.,_=>70. } }
fn family_hp(kind:&str)->f64 { match kind { "helicopter"=>220.,"amphibious_vehicle"=>850.,_=>600. } }
fn family_range(unit:&str,kind:&str)->f64 { if kind=="helicopter" {crate::littoral_v4::flight_range(unit)} else {1800.} }

/// Three genuine large landing islands plus seeded minor islets. The wide
/// southern, northern and inter-island channels are water in World, not art.
/// Called before ruins and ships are spawned; historical/v1/v2 never enter.
pub(crate) fn terrain(w:&mut World,seed:u32,ruins:&mut [Ruin])->E<()> {
    let mut rng=u64::from(seed)^0x7b31_e489_2a71;
    let mut shapes:Vec<Vec<P>>=vec![];
    for (i,anchor) in [P{x:7000.,y:7000.},P{x:13900.,y:7200.},P{x:20500.,y:8100.}].into_iter().enumerate() {
        let c=anchor+P{x:crate::world::roll(&mut rng,401) as f64-200.,y:crate::world::roll(&mut rng,501) as f64-250.};
        let rx=1200.+crate::world::roll(&mut rng,301) as f64;
        let ry=1000.+crate::world::roll(&mut rng,301) as f64;
        // Convex ellipse with seed-dependent outline rotation: every segment
        // between shore, objective and flank remains genuinely walkable.
        let angle=crate::world::roll(&mut rng,100) as f64/1000.-0.05;
        let polygon=(0..16).map(|j|{let a=j as f64*std::f64::consts::TAU/16.+angle; c+P{x:libm::cos(a)*rx,y:libm::sin(a)*ry}}).collect::<Vec<_>>();
        debug_assert!(polygon.iter().all(|p|p.x>4000.&&p.x<23500.&&p.y>4200.&&p.y<11500.),"island {i}");
        shapes.push(polygon);
    }
    // Small natural islets retain theme/seed variety, outside the reserved
    // landing zones and broad approach lanes. No decorative fake collision.
    let theme=w.ecology.as_ref().unwrap().theme.clone();
    for _ in 0..100 {
        if shapes.len()>=12+seed as usize%7 {break;}
        let c=P{x:4200.+crate::world::roll(&mut rng,18200) as f64,y:4800.+crate::world::roll(&mut rng,6100) as f64};
        let rx=140.+crate::world::roll(&mut rng,240) as f64;
        let ry=if theme=="fjord" {280.+crate::world::roll(&mut rng,180) as f64}else{120.+crate::world::roll(&mut rng,200) as f64};
        let p=(0..9).map(|k|{let a=k as f64*std::f64::consts::TAU/9.;let r=0.8+crate::world::roll(&mut rng,21) as f64/100.;c+P{x:libm::cos(a)*rx*r,y:libm::sin(a)*ry*r}}).collect::<Vec<_>>();
        if shapes.iter().any(|other|p.iter().any(|&p|crate::salvage::polygon_near(other,p,1700.))||other.iter().any(|&q|crate::salvage::polygon_near(&p,q,1700.))) {continue;}
        if p.iter().any(|p|p.x<4000.||p.x>23400.||p.y<4300.||p.y>11400.) {continue;}
        shapes.push(p);
    }
    // Loot is deliberately in the connected water corridors. Place against
    // the final polygons rather than moving them after enemy initialization.
    for (i,r) in ruins.iter_mut().enumerate().skip(1) {
        r.p=P{x:5200.+(i%4) as f64*5200.+crate::world::roll(&mut rng,401) as f64,
            y:if i<5 {3000.+crate::world::roll(&mut rng,301) as f64}else{12100.+crate::world::roll(&mut rng,201) as f64}};
    }
    if ruins.iter().any(|r|shapes.iter().any(|p|crate::salvage::polygon_near(p,r.p,500.))){return Err("海陆任务物资点未通过水域校验".into());}
    let offset=w.field.width-24000.;let eco=w.ecology.as_mut().unwrap();eco.landmarks.clear();
    for (i,p) in shapes.iter().enumerate().take(3) {let c=centroid(p);eco.landmarks.push(json!({"id":i+1,"kind":"radio_mast","x":c.x+offset,"y":c.y,"seed":seed.wrapping_add(i as u32),"island_index":i,"height_m":45,"flood":0.2,"charted":true,"collision":"island","footprint":p.iter().map(|q|c+(*q-c)*0.15+P{x:offset,y:0.}).collect::<Vec<_>>()}));}
    eco.layout=format!("{theme}-large-landing-v1");w.islands=shapes;Ok(())
}

fn island_terrain(poly:&[P])->Value {
    let c=centroid(poly);let mut zones=vec![];let mut ramps=vec![];
    for (i,vertex) in [3usize,11usize].into_iter().enumerate() {
        let center=c+(poly[vertex]-c)*0.38;
        let polygon=poly.iter().map(|p|center+(*p-c)*0.25).collect::<Vec<_>>();
        zones.push(json!({"id":i+1,"polygon":polygon,"level":i+1,"height_m":40*(i+1),"blend_width_m":120,"cover_multiplier":if i==0{0.9}else{0.8},"label":if i==0{"低丘掩护"}else{"高地掩护"}}));
        ramps.push(json!({"points":[c,center],"width":360,"from_level":0,"to_level":i+1}));
    }
    json!({"height_model":"inset_edge_blend_v1","elevation_zones":zones,"ramps":ramps,"movement":"walkable_slopes","height_los":false})
}
fn ground_cover(terrain:&Value,p:P)->f64 {
    let height=terrain["elevation_zones"].as_array().into_iter().flatten().filter_map(|z| {
        let polygon:Vec<P>=serde_json::from_value(z["polygon"].clone()).ok()?;
        if !inside(&polygon,p){return None;}
        let inset=polygon.iter().zip(polygon.iter().cycle().skip(1)).take(polygon.len()).map(|(a,b)|crate::adventure::segment_distance(p,*a,*b)).fold(f64::INFINITY,f64::min);
        Some(number(z,"height_m",0.)*(inset/number(z,"blend_width_m",120.).max(1.)).clamp(0.,1.))
    }).fold(0.,f64::max);
    (1.-height*0.0025).max(0.8)
}
fn company_index(run:&Run,q:&Value)->E<usize>{
    if let Some(id)=q["company_id"].as_str(){return run.companies.iter().position(|c|c.start.key()==id).ok_or("连队不在本航次".into());}
    let id=q["unit_id"].as_str().ok_or("请选择战术连队")?;
    let found:Vec<_>=run.companies.iter().enumerate().filter(|(_,c)|c.start.unit_id==id).map(|(i,_)|i).collect();
    if found.len()>1{return Err("该人格有多个连队，请指定company_id".into());}
    found.first().copied().ok_or("部队不在本航次".into())
}
fn group_key(g:&Value)->&str{g["company_id"].as_str().or_else(||g["unit_id"].as_str()).unwrap_or("")}
fn company_request(mut q:Value,g:&Value)->Value{if let Some(id)=g["company_id"].as_str(){q["company_id"]=json!(id);}q}
fn company_name(c:&CompanyStart)->&'static str{let n=c.company_id.rsplit('C').next().and_then(|n|n.parse::<usize>().ok()).unwrap_or(1);["一连","二连","三连","四连","五连"][n.saturating_sub(1).min(4)]}
fn company_fields(mut row:Value,c:&CompanyStart,count:u32)->Value{if !c.company_id.is_empty(){row["company_id"]=json!(c.company_id);row["company_name"]=json!(company_name(c));row["company_index"]=json!(c.company_id.rsplit('C').next().and_then(|n|n.parse::<u32>().ok()).unwrap_or(1));row["company_count"]=json!(crate::littoral_v4::company_layout(&c.unit_id).0);row["personnel_count"]=json!(count);}row}
fn landing_point(task:&LandTask,c:&CompanyStart)->P{if c.company_id.is_empty(){return task.beach;}let index=c.company_id.rsplit('C').next().and_then(|n|n.parse::<u32>().ok()).unwrap_or(1);let axis=(centroid(&task.polygon)-task.beach).unit();let tangent=P{x:-axis.y,y:axis.x};let p=task.beach+tangent*((index as f64-3.)*65.)+axis*(c.unit_id.bytes().map(u32::from).sum::<u32>()%4) as f64*25.;if inside(&task.polygon,p){p}else{task.beach}}

impl World {
    pub(crate) fn init_amphibious_expedition(&mut self) -> E<()> {
        let start=self.salvage.as_ref().unwrap().start.clone();
        if !is_version(&start.gameplay_profile) {return Ok(());}
        let config=start.amphibious_expedition.clone().unwrap();
        let origin=self.ships.iter().find(|s|s.side==0).unwrap().p;
        let mut candidates:Vec<_>=self.islands.iter().enumerate().filter(|(_,poly)| {
            let c=centroid(poly); let area=poly.iter().zip(poly.iter().cycle().skip(1)).take(poly.len()).map(|(a,b)|a.cross(*b)).sum::<f64>().abs()*0.5;
            area>3_000_000. && inside(poly,c)
        }).collect();
        candidates.sort_by(|(_,a),(_,b)|centroid(a).dist(origin).total_cmp(&centroid(b).dist(origin)));
        if candidates.len()<3 {return Err("程序海域没有三处可登陆的完整陆地，未提交出航".into());}
        let mut tasks=vec![];
        for (index,poly) in candidates {
            let i=tasks.len();if i==3{break;}
            let center=centroid(poly);
            let mut edges:Vec<_>=poly.iter().zip(poly.iter().cycle().skip(1)).take(poly.len()).map(|(a,b)|(*a+*b)*0.5).collect();edges.sort_by(|a,b|a.dist(origin).total_cmp(&b.dist(origin)));
            let Some((shore,beach))=edges.into_iter().find_map(|edge|{let outward=(edge-center).unit();let shore=edge+outward*1500.;let beach=edge-outward*65.;(inside(poly,beach)&&self.field.contains(shore)&&!self.islands.iter().any(|other|crate::salvage::polygon_near(other,shore,410.))).then_some((shore,beach))})else{continue;};
            let(kind,title,duration)=match i{0=>("land_relay","重启陆上中继",7.),1=>("land_rescue","救回协议核心",9.),_=>("land_cache","破解地下封存库",11.)};
            let terrain=island_terrain(poly);
            // Distinct inland positions create both direct and flanking
            // approaches. Convex combinations stay inside the real coastline.
            let p=center+(poly[(i*5+3)%poly.len()]-center)*0.36;
            tasks.push(LandTask{id:3001+i as u32,kind:kind.into(),title:title.into(),island:index as u32,p,shore,beach,polygon:poly.clone(),status:"offered".into(),progress:0.,duration,reward_ruin:None,terrain});
        }
        if tasks.len()<3{return Err("陆地任务缺少三处安全接驳水域，未提交出航".into());}
        let mut companies=vec![];
        for c in &config.companies {
            let p=profile(&c.unit_id)?;
            let carrier=self.ships.iter().find(|s|s.side==0&&s.character.as_deref()==Some(c.carrier_identity.as_str())).ok_or("搭载舰未实际生成")?;
            let transport=p["transport_options"].as_array().unwrap().iter().find(|o|o["kind"]==c.transport_kind).ok_or("该编制没有所选载具")?;
            let body_templates=transport["bodies"].as_array().unwrap().clone();let body_templates=if config.company_layout==COMPANY_LAYOUT{crate::littoral_v4::company_body_kinds(&c.unit_id,&c.transport_kind).iter().map(|kind|{let mut row=body_templates.iter().chain(p["bodies"].as_array().into_iter().flatten()).find(|b|b["kind"]==*kind).unwrap_or(&body_templates[0]).clone();row["kind"]=json!(kind);row}).collect::<Vec<_>>()}else{body_templates};let count=body_templates.len() as u32;
            let max=body_templates.iter().map(|b|number(b,"hp",100.)).sum::<f64>()/count as f64; let hp=number(transport,"hp",family_hp(&c.transport_kind))*c.condition_percent as f64/100.;
            companies.push(Company{start:c.clone(),carrier:carrier.id,count,hp_per_body:max,damage:18.,range:500.,reload:1.2,speed:130.,stage:"embarked".into(),island:None,p:carrier.p,target:carrier.p,order:"hold".into(),task:None,transit_start:carrier.p,transit_target:carrier.p,transit_started:0,transit_seconds:0,initial_transport_hp:hp,transport_hp:hp,transport_ammo:if c.unit_id=="MCP-027"{12}else{0},landed:false,entered_at:0,body_templates});
        }
        let mut run=Run{config,companies,tasks,bodies:vec![],shots:vec![],impacts:vec![],next_body:10000,next_shot:1,sea_spawned:0,next_sea_wave:75,next_land_wave:100,announced_sea:false,announced_land:false,land_spawned:0,land_done:false,ai_reason:"携带陆军，可选择岛上专属任务".into(),ai_commands:0,route_at:BTreeMap::new(),failed_tasks:BTreeSet::new(),failures:BTreeMap::new(),rng:u64::from(self.seed)^0x71a4_2c7e_8b35};
        for i in 0..run.tasks.len() { for k in 0..3 { spawn_enemy(&mut run,i,k,self.seed); } }
        self.amphibious_expedition=Some(run);
        self.add(1,"land_tasks_offered","陆上中继、协议救援与封存库已标记；需要战术部队上岸，物资仍须装舱撤离。".into(),Some("CAS-AMPHIBIOUS-01"),None);
        Ok(())
    }

    pub(crate) fn amphibious_preview(&self,q:&Value)->E<Value> {
        let run=self.amphibious_expedition.as_ref().ok_or("本航次未携带陆军")?;
        let c=&run.companies[company_index(run,q)?];let unit=&c.start.unit_id;
        let p=P{x:q["x"].as_f64().ok_or("落点无效")?,y:q["y"].as_f64().ok_or("落点无效")?};
        if !p.x.is_finite()||!p.y.is_finite(){return Err("落点无效".into());}
        let task=run.tasks.iter().find(|t|inside(&t.polygon,p)).ok_or("请拖向标记的可登陆陆地")?;
        let ship=self.ship(c.carrier).filter(|s|s.alive()).ok_or("搭载舰已失能")?;
        let distance=ship.p.dist(task.beach);let range=family_range(&c.start.unit_id,&c.start.transport_kind);
        let valid=["embarked","recovered"].contains(&c.stage.as_str())&&distance<=range&& (c.start.transport_kind=="helicopter"||ship.speed<=8.);
        Ok(company_fields(json!({"accepted":valid,"unit_id":unit,"island":task.island,"task":task.id,"x":p.x,"y":p.y,"carrier":c.carrier,"distance":distance,"range":range,"requires_approach":distance>range,"shore":task.shore,"beach":task.beach,"reason":if !["embarked","recovered"].contains(&c.stage.as_str()){"该部队已在行动，可拖动下达地面指令"}else if distance>range{"载舰需先航向近岸接驳点；旋翼机可在航程内出发"}else if c.start.transport_kind!="helicopter"&&ship.speed>8.{"载舰需降至8节以下再放艇"}else{"可投送"}}),&c.start,c.count))
    }

    pub(crate) fn amphibious_command(&mut self,q:&Value)->E<()> {
        if self.amphibious_expedition.is_none(){return Err("本航次未携带陆军".into());}
        let op=q["op"].as_str().unwrap_or("");
        if op=="expedition_land_autopilot" {let enabled=q["enabled"].as_bool().ok_or("自动指挥状态无效")?;self.amphibious_expedition.as_mut().unwrap().land_done=!enabled;return Ok(());}
        let i=company_index(self.amphibious_expedition.as_ref().unwrap(),q)?;
        let unit=self.amphibious_expedition.as_ref().unwrap().companies[i].start.unit_id.clone();
        let company=self.amphibious_expedition.as_ref().unwrap().companies[i].start.key().to_string();
        if op=="expedition_land_deploy" {
            let preview=self.amphibious_preview(q)?;
            let queue=q.get("queue").and_then(Value::as_bool).unwrap_or(false);
            if !preview["accepted"].as_bool().unwrap_or(false)&&!queue{return Err(preview["reason"].as_str().unwrap_or("暂不能部署").into());}
            let c=&self.amphibious_expedition.as_ref().unwrap().companies[i];
            if !["embarked","recovered"].contains(&c.stage.as_str()){return Err("该部队已出动，不能复制部署".into());}
            let ti=self.amphibious_expedition.as_ref().unwrap().tasks.iter().position(|t|t.id==preview["task"].as_u64().unwrap() as u32).unwrap();
            let task=self.amphibious_expedition.as_ref().unwrap().tasks[ti].clone();
            let run=self.amphibious_expedition.as_ref().unwrap();
            if run.config.company_layout==COMPANY_LAYOUT&&run.companies.iter().any(|other|other.start.key()!=c.start.key()&&other.carrier==c.carrier&&["approach","transit","ground","recovering"].contains(&other.stage.as_str())&&other.island!=Some(task.island)){return Err("同一载舰正在接驳另一座岛；请先撤收该岛连队，再安排下一处投送".into());}
            let ship=self.ship(c.carrier).unwrap();let sid=ship.id;let fleet=ship.fleet.ok_or("搭载舰没有编队")?;
            let ready=preview["accepted"]==true;
            if !ready {
                let points=water_path(self,ship.p,task.shore).ok_or("未找到安全近岸航路，请手动靠近海岸")?;
                self.route(0,&json!({"fleet":fleet,"mode":"follow","speed":24,"points":points}),false)?;
            }
            let c=&mut self.amphibious_expedition.as_mut().unwrap().companies[i];
            c.task=Some(task.id);c.island=Some(task.island);c.target=task.p;c.stage=if ready{"embarked"}else{"approach"}.into();
            if ready {self.start_amphibious_transit(i,false)?;}
            self.add(1,"land_deploy_queued",format!("{}由舰{}投送，已安排近岸航行与真实登陆",unit,sid),Some("CAS-AMPHIBIOUS-01"),Some(task.shore));
            return Ok(());
        }
        if op=="expedition_land_recover" {
            let c=&self.amphibious_expedition.as_ref().unwrap().companies[i];
            if c.stage=="approach" {self.amphibious_expedition.as_mut().unwrap().companies[i].stage="embarked".into();return Ok(());}
            if c.stage!="ground"{return Err("部队当前不在岸上".into());}
            let task=self.amphibious_expedition.as_ref().unwrap().tasks.iter().find(|t|Some(t.island)==c.island).unwrap();
            let beach=task.beach;
            let run=self.amphibious_expedition.as_mut().unwrap();let c=&mut run.companies[i];c.order="retreat".into();c.target=beach;c.task=None;
            for b in &mut run.bodies {if b.ally&&b.company==company&&b.hp>0.{b.order="retreat".into();}}
            return Ok(());
        }
        let c=&self.amphibious_expedition.as_ref().unwrap().companies[i];
        if !["ground","stranded"].contains(&c.stage.as_str()){return Err("请先将部队部署到陆地".into());}
        let action=if op=="expedition_land_task"{"search"}else{q["action"].as_str().unwrap_or("move")};
        if !["move","attack","search","hold"].contains(&action){return Err("地面指令无效".into());}
        let p=if action=="search" {
            let id=q["task"].as_u64().ok_or("请选择陆地任务")? as u32;
            self.amphibious_expedition.as_ref().unwrap().tasks.iter().find(|t|t.id==id&&Some(t.island)==c.island&&t.status!="complete").ok_or("该任务不在本连所在陆地或已经完成")?.p
        }else{P{x:q["x"].as_f64().ok_or("地面落点无效")?,y:q["y"].as_f64().ok_or("地面落点无效")?}};
        let t=self.amphibious_expedition.as_ref().unwrap().tasks.iter().find(|t|Some(t.island)==c.island).unwrap();
        if !p.x.is_finite()||!p.y.is_finite()||!inside(&t.polygon,p){return Err("地面落点必须位于本连所在岛屿内".into());}
        let run=self.amphibious_expedition.as_mut().unwrap();let c=&mut run.companies[i];c.target=p;c.order=action.into();c.task=if action=="search"{q["task"].as_u64().map(|n|n as u32)}else{None};
        for b in &mut run.bodies{if b.ally&&b.company==company&&b.hp>0.{b.order=action.into();}}
        Ok(())
    }

    fn start_amphibious_transit(&mut self,i:usize,returning:bool)->E<()> {
        let run=self.amphibious_expedition.as_ref().unwrap();let c=&run.companies[i];
        let ship=self.ship(c.carrier).filter(|s|s.alive()).ok_or("搭载舰已经失能")?;
        let task=run.tasks.iter().find(|t|Some(t.island)==c.island).ok_or("部队没有目标陆地")?;
        let from=if returning{task.beach}else{ship.p};let to=if returning{ship.p}else{landing_point(task,&c.start)};
        if from.dist(to)>family_range(&c.start.unit_id,&c.start.transport_kind){return Err("载舰超出运输载具回收航程，请驶近本岛接驳点".into());}
        let run=self.amphibious_expedition.as_mut().unwrap();let c=&mut run.companies[i];
        c.stage=if returning{"recovering"}else{"transit"}.into();c.transit_start=from;c.transit_target=to;c.transit_started=self.tick;c.transit_seconds=(from.dist(to)/family_speed(&c.start.transport_kind)).ceil().max(2.) as u32;c.p=from;
        Ok(())
    }

    pub(crate) fn advance_amphibious_expedition(&mut self) {
        if self.result.is_some(){return;}
        let Some(mut run)=self.amphibious_expedition.take() else{return;};
        let mut notices=vec![];
        for i in 0..run.companies.len() {
            let carrier=self.ship(run.companies[i].carrier).filter(|s|s.alive()).map(|s|(s.p,s.speed));
            let c=&mut run.companies[i];
            if carrier.is_none()&&c.stage=="ground"&&run.config.company_layout==COMPANY_LAYOUT {c.stage="stranded".into();notices.push(("land_company_stranded",format!("{} {}载舰失能，岸上身体继续守备；当前航次无法回收",c.start.unit_id,company_name(&c.start)),c.p));}
            if carrier.is_none() && !["lost","ground","stranded"].contains(&c.stage.as_str()) {
                c.stage="lost".into();c.transport_hp=0.;
                notices.push(("land_transport_lost",format!("{}的搭载舰失能，未上岸身体无法回收",c.start.unit_id),c.p));
            }
            if c.stage=="embarked" {if let Some((p,_))=carrier{c.p=p;}}
            if c.stage=="approach" {
                if let Some((p,speed))=carrier {
                    let task=run.tasks.iter().find(|t|Some(t.island)==c.island).unwrap();
                    if p.dist(task.beach)<=family_range(&c.start.unit_id,&c.start.transport_kind) && (c.start.transport_kind=="helicopter"||speed<=8.) {
                        c.stage="transit".into();c.transit_start=p;c.transit_target=landing_point(task,&c.start);c.transit_started=self.tick;c.transit_seconds=(p.dist(c.transit_target)/family_speed(&c.start.transport_kind)).ceil().max(2.) as u32;
                    } else if p.dist(task.beach)<=family_range(&c.start.unit_id,&c.start.transport_kind)*0.92&&speed>0. {
                        if let Some(fleet)=self.ship(c.carrier).and_then(|s|s.fleet) {let _=self.fleet_speed(0,&json!({"fleet":fleet,"speed":0}));}
                    }
                }
            }
            if ["transit","recovering"].contains(&c.stage.as_str()) {
                let progress=(self.tick.saturating_sub(c.transit_started) as f64/c.transit_seconds.max(1) as f64).clamp(0.,1.);c.p=c.transit_start+(c.transit_target-c.transit_start)*progress;
                let threats:Vec<_>=self.ships.iter().filter(|s|s.side==1&&s.alive()&&s.p.dist(c.p)<1700.).map(|s|s.p).collect();
                // Fictional close-in interception is separate from printed naval AA.
                if !threats.is_empty(){let armor=if c.start.transport_kind=="amphibious_vehicle"{0.35}else{1.};c.transport_hp=(c.transport_hp-threats.len() as f64*3.*armor).max(0.);}
                if c.transport_hp<=0. {c.stage="lost".into();notices.push(("land_transport_lost",format!("{}运输载具被摧毁",c.start.unit_id),c.p));continue;}
                if progress>=1. {
                    if c.stage=="recovering" {
                        c.stage="recovered".into();
                        for b in &mut run.bodies{if b.ally&&b.company==c.start.key()&&b.hp>0.{b.order="recovered".into();}}
                        notices.push(("land_company_recovered",format!("{}已真实回舰",c.start.unit_id),c.p));
                    } else {
                        c.stage="ground".into();c.landed=true;c.entered_at=self.tick;c.order="hold".into();c.p=c.transit_target;
                        let reused=run.bodies.iter().any(|b|b.ally&&b.company==c.start.key());
                        if reused {for (k,b) in run.bodies.iter_mut().filter(|b|b.ally&&b.company==c.start.key()&&b.hp>0.).enumerate(){let offset=P{x:(k%4) as f64*18.-27.,y:(k/4) as f64*18.};let task=run.tasks.iter().find(|t|Some(t.island)==c.island).unwrap();b.island=c.island.unwrap();b.p=if inside(&task.polygon,c.p+offset){c.p+offset}else{c.p};b.order="hold".into();}}
                        for k in 0..c.count {
                            if reused {break;}
                            let id=run.next_body;run.next_body+=1;let offset=P{x:(k%4) as f64*22.-33.,y:(k/4) as f64*22.};
                            let task=run.tasks.iter().find(|t|Some(t.island)==c.island).unwrap();let p=if inside(&task.polygon,c.p+offset){c.p+offset}else{c.p};
                            let row=&c.body_templates[k as usize];let max=number(row,"hp",100.);let hp=max*c.start.condition_percent as f64/100.*(c.transport_hp/c.initial_transport_hp.max(1.)).clamp(0.,1.);
                            run.bodies.push(Body{id,unit:c.start.unit_id.clone(),company:c.start.key().to_string(),ally:true,kind:row["kind"].as_str().unwrap_or("marine").into(),island:c.island.unwrap(),p,hp,max,ammo:row["ammo"].as_u64().unwrap_or(90) as u32,damage:number(row,"damage",22.),range:number(row,"range",700.),reload:number(row,"reload_seconds",0.8),ready:0.,speed:number(row,"speed",140.),h:0.,order:"hold".into(),attack_at:None,aim:p,death_tick:None,pose:(id+self.seed)%3});
                        }
                        notices.push(("land_company_landed",format!("{}已登陆，{}个身体进入陆战",c.start.unit_id,c.count),c.p));
                    }
                }
            }
        }
        for sub in 0..10 {advance_ground(&mut run,self.tick as f64-1.+(sub+1) as f64*0.1);}
        for i in 0..run.companies.len() {
            let c=run.companies[i].clone();if c.stage!="ground"{continue;}
            let survivors:Vec<_>=run.bodies.iter().filter(|b|b.ally&&b.company==c.start.key()&&b.hp>0.).collect();
            if survivors.is_empty(){run.companies[i].stage="lost".into();continue;}
            let p=survivors.iter().fold(P::default(),|a,b|a+b.p)*(1./survivors.len() as f64);run.companies[i].p=p;
            if c.order=="retreat" && survivors.iter().all(|b|b.p.dist(c.target)<180.) {
                if let Some((ship_p,_))=self.ship(c.carrier).filter(|s|s.alive()).map(|s|(s.p,s.speed)) {
                    let t=run.tasks.iter().find(|t|Some(t.island)==c.island).unwrap();
                    if ship_p.dist(t.beach)<=family_range(&c.start.unit_id,&c.start.transport_kind) {
                        let c=&mut run.companies[i];c.stage="recovering".into();c.transit_start=t.beach;c.transit_target=ship_p;c.transit_started=self.tick;c.transit_seconds=(t.beach.dist(ship_p)/family_speed(&c.start.transport_kind)).ceil().max(2.) as u32;c.p=t.beach;
                        for b in &mut run.bodies{if b.ally&&b.company==c.start.key()&&b.hp>0.{b.order="aboard".into();}}
                    }
                }
            }
        }
        for task in &mut run.tasks {
            if task.status=="complete"{continue;}
            let working=run.companies.iter().any(|c|["ground","stranded"].contains(&c.stage.as_str())&&c.task==Some(task.id)&&c.order=="search"&&run.bodies.iter().any(|b|b.ally&&b.company==c.start.key()&&b.hp>0.&&b.p.dist(task.p)<180.));
            let guarded=run.bodies.iter().any(|b|!b.ally&&b.hp>0.&&b.island==task.island&&b.p.dist(task.p)<700.);
            if working&&!guarded {task.status="working".into();task.progress+=1.;}
            else if task.status=="working"{task.status="accepted".into();}
            if task.progress>=task.duration {
                task.status="complete".into();task.reward_ruin=Some(task.id);
                let kind=match task.kind.as_str(){"land_relay"=>"command","land_rescue"=>"alloy",_=>"equipment"};
                self.salvage.as_mut().unwrap().ruins.push(Ruin{id:task.id,p:task.shore,kind:kind.into(),amount:5,found:true,collected:false});
                notices.push(("land_task_complete",format!("{}完成，接驳点留下物资箱，仍需搜索、装舱与撤离",task.title),task.shore));
            }
        }
        run.shots.retain(|s|self.tick as f64-s["tick"].as_f64().unwrap_or(0.)<=3.);
        run.impacts.retain(|s|self.tick as f64-s["tick"].as_f64().unwrap_or(0.)<=3.);
        if self.tick+8>=run.next_land_wave&&!run.announced_land&&run.land_spawned<(MAX_LAND_ENEMIES as u32) {
            run.announced_land=true;notices.push(("land_wave_warning","陆地异常信号增强，8秒后守卫将从遗迹边缘出现；可撤收。".into(),run.tasks[0].p));
        }
        if self.tick>=run.next_land_wave&&run.land_spawned<(MAX_LAND_ENEMIES as u32) {
            let targets:Vec<_>=run.tasks.iter().enumerate().filter(|(_,t)|run.companies.iter().any(|c|c.stage=="ground"&&c.island==Some(t.island))).map(|(i,_)|i).collect();
            if !targets.is_empty(){let count=(1+self.tick/150).min(4);for k in 0..count{let index=targets[k as usize%targets.len()];let ordinal=k+run.land_spawned;spawn_enemy(&mut run,index,ordinal,self.seed);}notices.push(("land_wave_arrived",format!("新的陆地守卫已出现，本航次累计{}个",run.land_spawned),run.tasks[targets[0]].p));}
            run.next_land_wave=self.tick+(80u32.saturating_sub(self.tick/10)).max(30);run.announced_land=false;
        }
        if self.tick+10>=run.next_sea_wave&&!run.announced_sea&&run.sea_spawned<MAX_SEA_REINFORCEMENTS {
            run.announced_sea=true;notices.push(("sea_wave_warning","深海回波正在接近，10秒后出现增援；西侧撤离区持续可用。".into(),run.tasks[0].shore));
        }
        if self.tick>=run.next_sea_wave&&run.sea_spawned<MAX_SEA_REINFORCEMENTS {
            let count=(1+self.tick/120).min(3).min(MAX_SEA_REINFORCEMENTS-run.sea_spawned);
            let bases:Vec<_>=self.ships.iter().filter(|s|s.side==0&&s.alive()).map(|s|s.p).collect();
            for k in 0..count {
                let Some(base)=bases.get(k as usize%bases.len().max(1)).copied()else{break;};
                let mut found=None;
                for ring in 0..12 {for a in 0..12 {let p=base+P::bearing((a*30+run.sea_spawned*17) as f64)*(3200.+ring as f64*180.);if self.field.contains(p)&&!self.islands.iter().any(|poly|crate::salvage::polygon_near(poly,p,180.))&&self.ships.iter().filter(|s|s.alive()).all(|s|s.p.dist(p)>600.){found=Some(p);break;}}if found.is_some(){break;}}
                if let Some(p)=found {let kind=if run.sea_spawned%3==0{"rust_crab"}else{"cult_ray"};if let Ok(id)=self.add_expedition_creature(kind,p){run.sea_spawned+=1;self.salvage.as_mut().unwrap().enemy_count+=1;if let Some(fleet)=self.ship(id).and_then(|s|s.fleet){if let Some(task)=self.salvage.as_mut().unwrap().enemies.iter_mut().find(|t|t.fleet==fleet){task.role=2;task.last_contact=Some((base,self.tick));}}}}
            }
            run.next_sea_wave=self.tick+(90u32.saturating_sub(self.tick/8)).max(25);run.announced_sea=false;
            notices.push(("sea_wave_arrived",format!("海上增援已进入，累计{} / {}，可继续任务或撤离",run.sea_spawned,MAX_SEA_REINFORCEMENTS),run.tasks[0].shore));
        }
        self.amphibious_expedition=Some(run);
        for (kind,text,p) in notices{self.add(1,kind,text,Some("CAS-AMPHIBIOUS-01"),Some(p));}
    }

    pub(crate) fn amphibious_extract_blocker(&self)->Option<&'static str> {
        self.amphibious_expedition.as_ref().filter(|r|r.companies.iter().any(|c|["approach","transit","ground","recovering"].contains(&c.stage.as_str()))).map(|_|"陆军尚未全部回舰；请撤收存活部队后再撤离")
    }

    /// Army decisions use the same complete public observation as the naval pilot.
    /// Only normal commands are submitted; position, HP, cargo and outcomes are never assigned.
    pub(crate) fn advance_amphibious_ai(&mut self)->bool {
        if !self.expedition.as_ref().is_some_and(|r|r.autopilot.enabled){return false;}
        let view=self.observation(self.player);let land=&view["salvage"]["amphibious"];
        let Some(groups)=land["groups"].as_array()else{return false;};
        let tasks=land["tasks"].as_array().unwrap();let tick=self.tick;
        let multi=self.amphibious_expedition.as_ref().unwrap().config.company_layout==COMPANY_LAYOUT;
        let task_goal=match self.expedition.as_ref().unwrap().autopilot.policy.as_str(){"cautious"=>1,"bold"=>3,_=>2};
        let completed=tasks.iter().filter(|t|t["status"]=="complete").count();
        let active=groups.iter().any(|g|["approach","transit","ground","recovering"].contains(&g["stage"].as_str().unwrap_or("")));
        let hp_low=view["ships"].as_array().unwrap().iter().any(|s|number(s,"hp",0.)/number(s,"maxHp",1.).max(1.)<0.42);
        let ammo_low=view["salvage"]["ships"].as_array().unwrap().iter().all(|s|number(s,"ammo",0.)<20.);
        let fuel_low=view["fuel"].is_object()&&(view["fuel"]["state"]=="low"||view["fuel"]["state"]=="empty"||number(&view["fuel"],"remaining",1e9)<number(&view["fuel"],"return_required",0.)*1.4);
        let stop=land["land_done"]==true||tick>950||hp_low||ammo_low||fuel_low;
        let skipped=self.amphibious_expedition.as_ref().unwrap().failed_tasks.clone();
        let unfinished=completed<task_goal&&tasks.iter().any(|t|t["status"]!="complete"&&!skipped.contains(&(t["id"].as_u64().unwrap() as u32)));
        let ready=groups.iter().any(|g|["embarked","recovered"].contains(&g["stage"].as_str().unwrap_or(""))&&number(g,"hp_percent",0.)>=35.);
        if (!unfinished||stop||!ready)&&!active {self.amphibious_expedition.as_mut().unwrap().land_done=true;return false;}
        let mut actions=vec![];let mut reason=if stop{"舰队或部队接近安全底线，撤收陆军后恢复海上撤离"}else{"按公开任务依次投送、清理守卫、搜索遗迹并回舰"}.to_string();
        for fleet in view["fleets"].as_array().unwrap(){if fleet["ai"]["move"]!=false||fleet["ai"]["gun"]!=true{actions.push(json!({"op":"ai","fleet":fleet["id"],"profile":"coord","mode":"auto","move":false,"gun":true,"torpedo":true}));}}
        let mut reserved:BTreeSet<u64>=groups.iter().filter(|g|["approach","transit","ground","recovering","stranded"].contains(&g["stage"].as_str().unwrap_or(""))).filter_map(|g|g["island"].as_u64()).collect();
        let mut carriers:BTreeMap<u64,u64>=groups.iter().filter(|g|["approach","transit","ground","recovering"].contains(&g["stage"].as_str().unwrap_or(""))).filter_map(|g|Some((g["carrier"].as_u64()?,g["island"].as_u64()?))).collect();
        for g in groups {
            let unit=g["unit_id"].as_str().unwrap();let stage=g["stage"].as_str().unwrap_or("");
            let weak=number(g,"hp_percent",100.)<35.||(number(g,"ammo",1000.)<20.&&stage=="ground");
            if stage=="approach"&&stop {actions.push(company_request(json!({"op":"expedition_land_recover","unit_id":unit}),g));continue;}
            if ["embarked","recovered"].contains(&stage)&&!stop&&!weak&&unfinished {
                // A balanced sortie commits to two parallel land objectives,
                // then brings the real cargo home. The third remains optional
                // or a deliberate bold-policy risk, never a forced long trip.
                let committed=completed+tasks.iter().filter(|t|t["status"]!="complete"&&reserved.contains(&t["island"].as_u64().unwrap())).count();
                let Some(ship)=view["ships"].as_array().unwrap().iter().find(|s|s["id"]==g["carrier"]&&number(s,"hp",0.)>0.)else{continue;};
                if !multi&&groups.iter().any(|other|group_key(other)!=group_key(g)&&other["carrier"]==g["carrier"]&&["approach","transit","ground","recovering"].contains(&other["stage"].as_str().unwrap_or(""))){continue;}
                let origin=P{x:number(ship,"x",0.),y:number(ship,"y",0.)};
                let carrier=g["carrier"].as_u64().unwrap();let assigned=if multi{carriers.get(&carrier).copied()}else{None};
                if assigned.is_none()&&committed>=task_goal{continue;}
                let task=if let Some(island)=assigned{tasks.iter().find(|t|t["island"]==island&&t["status"]!="complete")}else{tasks.iter().filter(|t|t["status"]!="complete"&&!skipped.contains(&(t["id"].as_u64().unwrap() as u32))&&!reserved.contains(&t["island"].as_u64().unwrap())).min_by(|a,b|P{x:number(a,"x",0.),y:number(a,"y",0.)}.dist(origin).total_cmp(&P{x:number(b,"x",0.),y:number(b,"y",0.)}.dist(origin)))};
                if let Some(task)=task{reserved.insert(task["island"].as_u64().unwrap());carriers.insert(carrier,task["island"].as_u64().unwrap());actions.push(company_request(json!({"op":"expedition_land_deploy","unit_id":unit,"x":task["x"],"y":task["y"],"queue":true}),g));}
            }else if stage=="stranded" {
                let task=tasks.iter().find(|t|t["island"]==g["island"]).unwrap();
                if task["status"]!="complete"&&!stop&&(g["order"]!="search"||g["task"]!=task["id"]){actions.push(company_request(json!({"op":"expedition_land_task","unit_id":unit,"task":task["id"]}),g));}
            }else if stage=="ground" {
                let task=tasks.iter().find(|t|t["island"]==g["island"]).unwrap();
                if stop||weak||task["status"]=="complete" {if g["order"]!="retreat"{actions.push(company_request(json!({"op":"expedition_land_recover","unit_id":unit}),g));}else{reason="部队正在向真实滩头撤收，载舰等候接驳".into();}}
                else if g["order"]!="search"||g["task"]!=task["id"]{actions.push(company_request(json!({"op":"expedition_land_task","unit_id":unit,"task":task["id"]}),g));}
            }
        }
        // Re-route a stalled approach or recover ship from visible geometry, never teleport.
        for g in groups.iter().filter(|g|g["stage"]=="approach"||(g["stage"]=="ground"&&g["order"]=="retreat")){
            let sid=g["carrier"].as_u64().unwrap() as u32;let Some(ship)=self.ship(sid).filter(|s|s.alive())else{continue;};let Some(fleet)=ship.fleet else{continue;};
            let task=tasks.iter().find(|t|t["island"]==g["island"]).unwrap();let beach:P=serde_json::from_value(task["beach"].clone()).unwrap();let shore:P=serde_json::from_value(task["shore"].clone()).unwrap();
            let near=ship.p.dist(beach)<=number(g,"range",900.);let last=self.amphibious_expedition.as_ref().unwrap().route_at.get(&fleet).copied().unwrap_or(0);
            if near&&ship.speed>0.{actions.push(json!({"op":"speed","fleet":fleet,"speed":0}));}
            else if !near&&tick.saturating_sub(last)>=18 {if let Some(points)=water_path(self,ship.p,shore){actions.push(json!({"op":"route","fleet":fleet,"mode":"follow","speed":24,"points":points}));self.amphibious_expedition.as_mut().unwrap().route_at.insert(fleet,tick);}}
        }
        let r=self.amphibious_expedition.as_mut().unwrap();r.ai_reason=reason.clone();r.ai_commands+=actions.len() as u32;
        if let Some(r)=&mut self.expedition{r.autopilot.phase="land_ops".into();r.autopilot.reason=reason;r.autopilot.last_decision_tick=tick;}
        for action in actions{if let Err(e)=self.dispatch_external(self.player,action.clone(),false){let r=self.amphibious_expedition.as_mut().unwrap();r.ai_reason=e;if action["op"]=="expedition_land_deploy"{if let Some(task)=r.tasks.iter().find(|t|number(&action,"x",0.)==t.p.x&&number(&action,"y",0.)==t.p.y){let failed=r.failures.entry(task.id).or_default();*failed+=1;if *failed>=3{r.failed_tasks.insert(task.id);}}}}}
        true
    }

    pub(crate) fn amphibious_view(&self,view:&mut Value) {
        let Some(run)=&self.amphibious_expedition else{return;};
        let tick=self.tick as f64;
        let mut companies:Vec<_>=run.companies.iter().map(|c|{
            let bodies:Vec<_>=run.bodies.iter().filter(|b|b.ally&&b.company==c.start.key()).collect();
            let alive=bodies.iter().filter(|b|b.hp>0.).count();let sum=bodies.iter().map(|b|b.hp.max(0.)).sum::<f64>();
            json!({"id":c.start.unit_id,"unit_id":c.start.unit_id,"carrier":c.carrier,"carrier_identity":c.start.carrier_identity,"transport_kind":c.start.transport_kind,"stage":c.stage,"island":c.island,"x":c.p.x,"y":c.p.y,"order":c.order,"count":c.count,"alive":if c.stage=="lost"{0}else if bodies.is_empty(){c.count as usize}else{alive},"hp_percent":if c.stage=="lost"{0.}else if bodies.is_empty(){c.start.condition_percent as f64}else{sum/(c.hp_per_body*c.count as f64)*100.},"ammo":bodies.iter().filter(|b|b.hp>0.).map(|b|b.ammo).sum::<u32>(),"range":family_range(&c.start.unit_id,&c.start.transport_kind),"task":c.task,"transport_hp":c.transport_hp,"transport_max_hp":c.initial_transport_hp})
        }).collect();
        let mut entities:Vec<_>=run.bodies.iter().filter(|b|b.hp>0.&&!["recovered","aboard"].contains(&b.order.as_str())&&(!b.ally||run.companies.iter().any(|c|c.start.key()==b.company&&["ground","stranded"].contains(&c.stage.as_str())))).map(|b|json!({"id":b.id,"unit_id":b.unit,"side":if b.ally{"allies"}else{"axis"},"kind":b.kind,"island":b.island,"x":b.p.x,"y":b.p.y,"heading":b.h,"hp":b.hp,"max_hp":b.max,"ammo":b.ammo,"order":b.order,"attack_range":b.range,"attack":{"kind":b.kind,"state":if b.attack_at.is_some(){"windup"}else{"recover"},"seconds":b.attack_at.map(|a|(a-tick).max(0.)).unwrap_or((b.ready-tick).max(0.)),"counter":match b.kind.as_str(){"land_rust_crab"=>"绕到侧后，避开近身钳击","land_spore_hound"=>"观察直线扑击，横向移动","land_siege_drone"=>"离开圆形迫击预警",_=>"避开蓄力点射，利用射程差"}}})).collect();
        let mut corpses:Vec<_>=run.bodies.iter().filter(|b|b.hp<=0.).map(|b|json!({"id":b.id,"unit_id":b.unit,"side":if b.ally{"allies"}else{"axis"},"kind":b.kind,"island":b.island,"x":b.p.x,"y":b.p.y,"heading":b.h,"death_tick":b.death_tick,"pose_seed":b.pose,"persistent":true})).collect();
        let tasks:Vec<_>=run.tasks.iter().map(|t|json!({"id":t.id,"kind":t.kind,"title":t.title,"island":t.island,"x":t.p.x,"y":t.p.y,"shore":t.shore,"beach":t.beach,"polygon":t.polygon,"terrain":t.terrain,"status":t.status,"progress":t.progress,"duration":t.duration,"reward_ruin_id":t.reward_ruin,"requires":"army"})).collect();
        let mut transports:Vec<_>=run.companies.iter().enumerate().filter(|(_,c)|["transit","recovering"].contains(&c.stage.as_str())).map(|(i,c)|json!({"id":9000+i,"unit_id":c.start.unit_id,"kind":c.start.transport_kind,"side":"allies","x":c.p.x,"y":c.p.y,"heading":(c.transit_target-c.transit_start).heading(),"hp":c.transport_hp,"max_hp":c.initial_transport_hp,"returning":c.stage=="recovering","stage":c.stage})).collect();
        let mut outcome=self.result.as_ref().map(|_|json!({"version":LAND_VERSION,"completed_tasks":run.tasks.iter().filter(|t|t.status=="complete").map(|t|t.id).collect::<Vec<_>>(),"units":run.companies.iter().map(|c|{
            let hp=run.bodies.iter().filter(|b|b.ally&&b.company==c.start.key()).map(|b|b.hp.max(0.)).sum::<f64>();let bodies_existed=run.bodies.iter().any(|b|b.ally&&b.company==c.start.key());
            let carrier_recovered=self.salvage.as_ref().unwrap().extracted&&self.ship(c.carrier).is_some_and(|s|s.alive());
            let recovered=carrier_recovered&&["embarked","recovered"].contains(&c.stage.as_str());
            let condition=if c.stage=="lost"{0.}else if !bodies_existed{c.start.condition_percent as f64}else{hp/(c.hp_per_body*c.count as f64)*100.};
            json!({"id":c.start.unit_id,"initial_condition":c.start.condition_percent,"condition_percent":(condition*if recovered{1.}else{0.25}).floor().clamp(0.,c.start.condition_percent as f64),"recovered":recovered,"deployed":c.landed,"survivors":run.bodies.iter().filter(|b|b.ally&&b.company==c.start.key()&&b.hp>0.).count(),"carrier":c.start.carrier_identity})
        }).collect::<Vec<_>>() }));
        if run.config.company_layout==COMPANY_LAYOUT {
            for (row,c) in companies.iter_mut().zip(&run.companies){*row=company_fields(row.take(),&c.start,c.count);row["id"]=json!(c.start.key());}
            for row in entities.iter_mut().chain(corpses.iter_mut()) {if let Some(b)=run.bodies.iter().find(|b|row["id"]==b.id&&b.ally){row["company_id"]=json!(b.company);}}
            for row in &mut transports {if let Some(c)=run.companies.get(row["id"].as_u64().unwrap() as usize-9000){*row=company_fields(row.take(),&c.start,c.count);row["island"]=json!(c.island);}}
            if let Some(out)=&mut outcome {
                let mut per_company=out["units"].as_array().unwrap().clone();
                for (row,c) in per_company.iter_mut().zip(&run.companies) {
                    *row=company_fields(row.take(),&c.start,c.count);
                    let max=c.hp_per_body*c.count as f64;
                    let hp=if c.stage=="lost"{0.}else if run.bodies.iter().any(|b|b.ally&&b.company==c.start.key()){run.bodies.iter().filter(|b|b.ally&&b.company==c.start.key()).map(|b|b.hp.max(0.)).sum::<f64>()}else{max*c.start.condition_percent as f64/100.};
                    row["max_hp_total"]=json!(max);row["retained_hp"]=json!(hp*if row["recovered"]==true{1.}else{0.25});
                }
                let ids:BTreeSet<_>=run.companies.iter().map(|c|c.start.unit_id.clone()).collect();
                out["units"]=json!(ids.iter().map(|id|{let rows:Vec<_>=per_company.iter().filter(|r|r["id"]==*id).collect();let max=rows.iter().map(|r|number(r,"max_hp_total",0.)).sum::<f64>();let hp=rows.iter().map(|r|number(r,"retained_hp",0.)).sum::<f64>();json!({"id":id,"initial_condition":rows[0]["initial_condition"],"condition_percent":(hp/max.max(1.)*100.).floor().clamp(0.,100.),"recovered":rows.iter().all(|r|r["recovered"]==true),"deployed":rows.iter().any(|r|r["deployed"]==true),"survivors":rows.iter().map(|r|r["survivors"].as_u64().unwrap_or(0)).sum::<u64>(),"company_count":rows.len(),"personnel_count":rows.iter().map(|r|r["personnel_count"].as_u64().unwrap_or(0)).sum::<u64>()})}).collect::<Vec<_>>());
                out["companies"]=json!(per_company);out["company_layout"]=json!(COMPANY_LAYOUT);
            }
        }
        view["salvage"]["amphibious"]=json!({"version":LAND_VERSION,"tick":tick,"groups":companies,"entities":entities,"corpses":corpses,"transports":transports,"tasks":tasks,"shots":run.shots,"impacts":run.impacts,"land_done":run.land_done,"ai_reason":run.ai_reason,"ai_commands":run.ai_commands,"pressure":{"sea_spawned":run.sea_spawned,"sea_limit":MAX_SEA_REINFORCEMENTS,"land_spawned":run.land_spawned,"land_limit":MAX_LAND_ENEMIES,"next_sea_wave":run.next_sea_wave,"next_land_wave":run.next_land_wave,"sea_announced":run.announced_sea,"land_announced":run.announced_land},"outcome":outcome});
        if run.config.company_layout==COMPANY_LAYOUT{view["salvage"]["amphibious"]["company_layout"]=json!(COMPANY_LAYOUT);}
    }
}

fn advance_ground(run:&mut Run,now:f64) {
    let before=run.bodies.clone();let mut hits=vec![];
    for b in &mut run.bodies {
        if b.hp<=0.||["recovered","aboard"].contains(&b.order.as_str()){continue;}
        let task=run.tasks.iter().find(|t|t.island==b.island).unwrap();
        let foe=before.iter().filter(|f|f.ally!=b.ally&&f.hp>0.&&f.island==b.island&&!["recovered","aboard"].contains(&f.order.as_str())).min_by(|a,c|a.p.dist(b.p).total_cmp(&c.p.dist(b.p)));
        let mut target=b.p;
        if b.ally {
            let c=run.companies.iter().find(|c|c.start.key()==b.company).unwrap();
            if !["ground","stranded"].contains(&c.stage.as_str()){continue;}
            if c.order!="hold" {let company_offset=if c.start.company_id.is_empty(){0.}else{(c.start.company_id.rsplit('C').next().and_then(|n|n.parse::<u32>().ok()).unwrap_or(3) as f64-3.)*70.};target=c.target+P{x:company_offset+(b.id%4) as f64*20.-30.,y:(b.id/4%3) as f64*20.-20.};if !inside(&task.polygon,target){target=c.target;}}
            if let Some(f)=foe.filter(|f|b.p.dist(f.p)<=b.range&&c.order!="retreat") {
                if b.ammo>0&&now>=b.ready {b.ammo-=1;b.ready=now+b.reload;b.h=(f.p-b.p).heading();hits.push((f.id,b.damage));let id=run.next_shot;run.next_shot+=1;run.shots.push(json!({"id":id,"source":b.id,"target":f.id,"x":b.p.x,"y":b.p.y,"target_x":f.p.x,"target_y":f.p.y,"tick":now,"kind":"land_rifle"}));}
            }
        } else if let Some(f)=foe.filter(|f|b.p.dist(f.p)<1500.) {
            if let Some(at)=b.attack_at {
                if now>=at {
                    b.attack_at=None;b.ready=now+b.reload;b.ammo=b.ammo.saturating_sub(1);
                    let blast=if b.kind=="land_siege_drone"{170.}else if b.kind=="land_spore_hound"{130.}else{90.};
                    if b.kind=="land_spore_hound"{let dash=advance_toward(b.p,b.aim,350.);if inside(&task.polygon,dash){b.p=dash;}}
                    for f in before.iter().filter(|f|f.ally&&f.hp>0.&&!["recovered","aboard"].contains(&f.order.as_str())&&f.island==b.island&&f.p.dist(b.aim)<blast){hits.push((f.id,b.damage));}
                    let id=run.next_shot;run.next_shot+=1;run.shots.push(json!({"id":id,"source":b.id,"x":b.p.x,"y":b.p.y,"target_x":b.aim.x,"target_y":b.aim.y,"tick":now,"kind":b.kind}));run.impacts.push(json!({"id":id,"x":b.aim.x,"y":b.aim.y,"radius":blast,"tick":now}));
                }
            } else if b.p.dist(f.p)<=b.range&&now>=b.ready&&b.ammo>0 {b.aim=f.p;b.h=(f.p-b.p).heading();b.attack_at=Some(now+if b.kind=="land_siege_drone"{1.4}else{0.7});}
            else if b.p.dist(f.p)>b.range*0.8 {target=f.p;}
        }
        if b.attack_at.is_none()&&b.p.dist(target)>10. {let next=advance_toward(b.p,target,b.speed*0.1);if inside(&task.polygon,next){b.h=(next-b.p).heading();b.p=next;}}
    }
    for (id,damage) in hits {if let Some(b)=run.bodies.iter_mut().find(|b|b.id==id&&b.hp>0.){let cover=run.tasks.iter().find(|t|t.island==b.island).map(|t|ground_cover(&t.terrain,b.p)).unwrap_or(1.);b.hp=(b.hp-damage*cover).max(0.);if b.hp<=0.{b.death_tick=Some(now);b.attack_at=None;}}}
}

fn spawn_enemy(run:&mut Run,task_index:usize,k:u32,seed:u32) {
    if run.bodies.iter().filter(|b|!b.ally).count()>=MAX_LAND_ENEMIES{return;}
    let task=&run.tasks[task_index];let kind=["land_rust_crab","land_cult_sentinel","land_spore_hound","land_siege_drone"][(task_index+k as usize+seed as usize)%4];
    let (hp,damage,range,reload,speed)=match kind {"land_rust_crab"=>(200.,16.,100.,2.5,95.),"land_cult_sentinel"=>(130.,14.,650.,2.0,80.),"land_spore_hound"=>(85.,18.,130.,3.0,150.),_=>(160.,22.,900.,4.,60.)};
    let c=task.p;let angle=(k as f64*115.+seed as f64%360.).to_radians();let offset=P{x:libm::sin(angle)*220.,y:libm::cos(angle)*220.};let p=if inside(&task.polygon,c+offset){c+offset}else{c};
    let id=run.next_body;run.next_body+=1;run.land_spawned+=1;
    run.bodies.push(Body{id,unit:String::new(),company:String::new(),ally:false,kind:kind.into(),island:task.island,p,hp,max:hp,ammo:60,damage,range,reload,ready:0.,speed,h:0.,order:"guard".into(),attack_at:None,aim:p,death_tick:None,pose:(id+seed)%3});
}

/// A bounded grid search using the same public island polygons as the player.
/// It only proposes normal World routes; the naval route validator still decides.
fn water_path(w:&World,start:P,goal:P)->Option<Vec<P>> {
    let clear=|p:P|w.field.contains(p)&&!w.islands.iter().any(|poly|crate::salvage::polygon_near(poly,p,400.));
    let segment=|a:P,b:P|{let n=(a.dist(b)/80.).ceil().max(1.) as u32;(0..=n).all(|i|clear(a+(b-a)*(i as f64/n as f64)))};
    if segment(start,goal){return Some(vec![goal]);}
    let step=150.;let cols=(w.field.width/step).ceil() as i32;let rows=(w.field.height/step).ceil() as i32;
    let node=|p:P|((p.x/step).floor() as i32,(p.y/step).floor() as i32);let point=|(x,y):(i32,i32)|P{x:(x as f64+0.5)*step,y:(y as f64+0.5)*step};
    let s=node(start);let target=node(goal);let mut queue=BinaryHeap::from([Reverse((0u32,s))]);let mut costs=BTreeMap::from([(s,0u32)]);let mut prev=BTreeMap::new();let mut end=None;
    while let Some(Reverse((_,u)))=queue.pop(){if costs.len()>20000{break;}let at=if u==s{start}else{point(u)};
        if (u.0-target.0).abs()<=2&&(u.1-target.1).abs()<=2&&segment(at,goal){end=Some(u);break;}
        for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)]{let v=(u.0+dx,u.1+dy);if v.0<0||v.1<0||v.0>=cols||v.1>=rows||!segment(at,point(v)){continue;}let new=costs[&u]+if dx==0||dy==0{10}else{14};if costs.get(&v).is_none_or(|old|new<*old){costs.insert(v,new);prev.insert(v,u);let h=((v.0-target.0).abs()+(v.1-target.1).abs()) as u32*7;queue.push(Reverse((new+h,v)));}}
    }
    let mut u=end?;let mut path=vec![goal];while u!=s{path.push(point(u));u=*prev.get(&u)?;}path.push(start);path.reverse();
    let mut result=vec![];let mut i=0;while i+1<path.len(){let mut next=i+1;for j in (i+1..path.len()).rev(){if segment(path[i],path[j]){next=j;break;}}result.push(path[next]);i=next;}
    (result.len()<=30).then_some(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn start()->Start {serde_json::from_value(json!({"content":"salvage-v4","gameplay_profile":VERSION,"fleet":[{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":100,"level":0}],"mission":{"kind":"salvage","id":"calm","loot_kind":"scrap"},"cargo_v4":{"commander_level":20,"difficulty":"calm","environment":"atoll","weather":"clear","loadouts":{}},"expedition_v2":{"scene":"sunken_metropolis","munitions":{}},"amphibious_expedition":{"companies":[{"unit_id":"MCP-034","carrier_identity":"IBS-U-USN-FLETCHER","transport_kind":"landing_craft","condition_percent":100}]}})).unwrap()}
    fn multi_start()->Start {let mut s=start();let c=s.amphibious_expedition.as_mut().unwrap();c.company_layout=COMPANY_LAYOUT.into();let template=c.companies[0].clone();c.companies=(1..=5).map(|n|{let mut company=template.clone();company.company_id=format!("MCP-034-C{n:02}");company}).collect();s}
    #[test]fn all_twenty_layouts_use_real_people_and_legal_body_capacity(){
        for id in ["001","034","076","009","022","011","018","027","041","052","063","087","103","116","128","145","167","184","203","240"]{
            let unit=format!("MCP-{id}");let (count,people)=crate::littoral_v4::company_layout(&unit);let mut s=start();let hull="CAS-O-LHA-RETURNLIGHT";s.fleet[0].id=hull.into();let kind=if ["001","076","027","041","128","203"].contains(&id){"helicopter"}else if ["022","087","240"].contains(&id){"amphibious_vehicle"}else{"landing_craft"};
            s.amphibious_expedition=Some(Config{company_layout:COMPANY_LAYOUT.into(),companies:(1..=count).map(|n|CompanyStart{company_id:format!("{unit}-C{n:02}"),unit_id:unit.clone(),carrier_identity:hull.into(),transport_kind:kind.into(),condition_percent:100}).collect()});
            // Some protocols have a different registered transport family; use
            // their own first option rather than granting a guessed vehicle.
            let profile=crate::littoral_v4::catalogue().unwrap()["cards"].as_array().unwrap().iter().find(|p|p["id"]==unit).unwrap().clone();
            let kind=profile["transport_options"][0]["kind"].as_str().unwrap();for c in &mut s.amphibious_expedition.as_mut().unwrap().companies{c.transport_kind=kind.into();}
            let w=World::new_salvage(42,s).unwrap_or_else(|e|panic!("{unit}: {e}"));let r=w.amphibious_expedition.as_ref().unwrap();assert_eq!(r.companies.len(),count as usize);assert!(r.companies.iter().all(|c|c.count==people));assert_eq!(r.companies.iter().map(|c|c.count).sum::<u32>(),count*people);
        }
    }
    #[test]fn seven_companies_two_fleets_finish_two_real_tasks_and_extract_without_erasing_stranded_people(){
        let mut s=multi_start();s.weather=Some(crate::salvage_weather::VERSION.into());s.intel_profile=crate::intel::VERSION.into();s.fleet[0].id="IBS-U-USN-ERMA-IOWA".into();s.fleet.push(crate::salvage::Hull{id:"IBS-U-USN-FLETCHER".into(),hp:100,ammo:100,..Default::default()});s.groups=vec![crate::salvage::Group{id:"heavy".into(),name:"一队".into(),ships:vec!["IBS-U-USN-ERMA-IOWA".into()]},crate::salvage::Group{id:"light".into(),name:"二队".into(),ships:vec!["IBS-U-USN-FLETCHER".into()]}];let config=s.amphibious_expedition.as_mut().unwrap();for c in &mut config.companies{c.carrier_identity="IBS-U-USN-ERMA-IOWA".into();}for n in 1..=2{config.companies.push(CompanyStart{company_id:format!("MCP-009-C{n:02}"),unit_id:"MCP-009".into(),carrier_identity:"IBS-U-USN-FLETCHER".into(),transport_kind:"landing_craft".into(),condition_percent:100});}
        let mut w=World::new_salvage(43,s).unwrap();w.external(json!({"op":"extraction_autopilot","enabled":true,"policy":"balanced","version":"cas-extraction-pilot-v3"})).unwrap();for _ in 0..1000{if w.result.is_some(){break;}w.advance();}
        let v=w.observation(0);let a=&v["salvage"]["amphibious"];assert_eq!(v["salvage"]["extracted"],true,"tick={} {}",w.tick,v["result"]);assert_eq!(a["tasks"].as_array().unwrap().iter().filter(|t|t["status"]=="complete").count(),2);assert_eq!(a["outcome"]["companies"].as_array().unwrap().len(),7);assert_eq!(a["outcome"]["units"].as_array().unwrap().len(),2);let r=w.amphibious_expedition.as_ref().unwrap();assert!(r.companies.iter().filter(|c|c.start.unit_id=="MCP-034").all(|c|c.stage=="recovered"));let stranded:Vec<_>=r.bodies.iter().filter(|b|b.ally&&b.unit=="MCP-009"&&b.hp>0.).collect();assert!(!stranded.is_empty());assert!(r.companies.iter().filter(|c|c.start.unit_id=="MCP-009").all(|c|c.stage=="stranded"));let unit=a["outcome"]["units"].as_array().unwrap().iter().find(|u|u["id"]=="MCP-009").unwrap();let hp:f64=stranded.iter().map(|b|b.hp).sum();let max:f64=r.bodies.iter().filter(|b|b.ally&&b.unit=="MCP-009").map(|b|b.max).sum();assert_eq!(unit["condition_percent"].as_f64().unwrap(),(hp/max*25.).floor());assert_eq!(unit["personnel_count"],12);let mut engine=crate::Engine::default();assert_eq!(engine.handle(json!({"op":"load","save":w.save()}))["data"],v);
    }
    #[test]fn multiple_companies_have_real_independent_bodies_orders_and_one_protocol_receipt(){let mut w=World::new_salvage(42,multi_start()).unwrap();assert_eq!(w.amphibious_expedition.as_ref().unwrap().companies.iter().map(|c|c.count).sum::<u32>(),45);let task=w.amphibious_expedition.as_ref().unwrap().tasks[0].clone();assert!(w.amphibious_preview(&json!({"unit_id":"MCP-034","x":task.p.x,"y":task.p.y})).is_err());w.external(json!({"op":"ai","fleet":1,"profile":"coord","mode":"auto","move":false,"gun":true,"torpedo":true})).unwrap();for n in 1..=2{w.external(json!({"op":"expedition_land_deploy","unit_id":"MCP-034","company_id":format!("MCP-034-C{n:02}"),"x":task.p.x,"y":task.p.y,"queue":true})).unwrap();}for _ in 0..120{if w.amphibious_expedition.as_ref().unwrap().companies.iter().take(2).all(|c|c.stage=="ground"){break;}w.advance();}let r=w.amphibious_expedition.as_ref().unwrap();assert!(r.companies.iter().take(2).all(|c|c.stage=="ground"));assert_eq!(r.bodies.iter().filter(|b|b.ally&&b.company=="MCP-034-C01").count(),9);assert_eq!(r.bodies.iter().filter(|b|b.ally&&b.company=="MCP-034-C02").count(),9);assert_eq!(r.companies[2].stage,"embarked");w.external(json!({"op":"expedition_land_task","unit_id":"MCP-034","company_id":"MCP-034-C01","task":task.id})).unwrap();assert_eq!(w.amphibious_expedition.as_ref().unwrap().companies[1].order,"hold");let before=w.observation(0);let mut engine=crate::Engine::default();assert_eq!(engine.handle(json!({"op":"load","save":w.save()}))["data"],before);w.external(json!({"op":"salvage_abandon"})).unwrap();let out=w.observation(0)["salvage"]["amphibious"]["outcome"].clone();assert_eq!(out["units"].as_array().unwrap().len(),1);assert_eq!(out["companies"].as_array().unwrap().len(),5);assert_eq!(out["units"][0]["personnel_count"],45);}
    #[test]fn new_carrier_identities_really_spawn_bind_and_replay(){for (ship,unit,kind) in [("CAS-H-USN-ENTERPRISE-1942","MCP-001","helicopter"),("CAS-H-IJN-SHOKAKU-1942","MCP-076","helicopter"),("CAS-O-LHA-RETURNLIGHT","MCP-027","helicopter"),("CAS-O-APV-TIDEBRIDGE","MCP-022","amphibious_vehicle")]{let mut s=start();s.fleet[0].id=ship.into();let c=&mut s.amphibious_expedition.as_mut().unwrap().companies[0];c.unit_id=unit.into();c.carrier_identity=ship.into();c.transport_kind=kind.into();let w=World::new_salvage(43,s).unwrap();assert_eq!(w.ships[0].character.as_deref(),Some(ship));assert_eq!(w.amphibious_expedition.as_ref().unwrap().companies[0].carrier,w.ships[0].id);assert_eq!(w.fleets[0].members,vec![w.ships[0].id]);let mut e=crate::Engine::default();let loaded=e.handle(json!({"op":"load","save":w.save()}));assert_eq!(loaded["ok"],true,"{loaded}");assert_eq!(loaded["data"],w.observation(0));}}
    #[test] fn seeded_land_is_physical_owned_carriers_and_bounded_enemies(){for seed in 0..12{let w=World::new_salvage(seed,start()).unwrap_or_else(|e|panic!("seed {seed}: {e}"));let r=w.amphibious_expedition.as_ref().unwrap();assert_eq!(r.tasks.len(),3);assert_eq!(r.bodies.len(),9);for t in &r.tasks{assert!(inside(&t.polygon,t.p));assert!(!w.islands.iter().any(|p|crate::salvage::polygon_near(p,t.shore,150.)));let width=t.polygon.iter().map(|p|p.x).fold(f64::NEG_INFINITY,f64::max)-t.polygon.iter().map(|p|p.x).fold(f64::INFINITY,f64::min);let height=t.polygon.iter().map(|p|p.y).fold(f64::NEG_INFINITY,f64::max)-t.polygon.iter().map(|p|p.y).fold(f64::INFINITY,f64::min);assert!(width>2300.&&height>1900.);assert_eq!(t.terrain["elevation_zones"].as_array().unwrap().len(),2);assert!(water_path(&w,w.ships[0].p,t.shore).is_some(),"seed {seed}: shore {}",t.id);for other in &r.tasks {assert!(water_path(&w,t.shore,other.shore).is_some(),"seed {seed}: inter-island {} to {}",t.id,other.id);}}assert!(w.ships.iter().all(|s|!w.islands.iter().any(|p|crate::salvage::polygon_near(p,s.p,150.))));assert!(w.salvage.as_ref().unwrap().ruins.iter().all(|r|!w.islands.iter().any(|p|crate::salvage::polygon_near(p,r.p,400.))));assert!(w.amphibious_extract_blocker().is_none());}}
    #[test]fn highland_cover_changes_actual_ground_damage_without_fake_los(){let mut w=World::new_salvage(42,start()).unwrap();let run=w.amphibious_expedition.take().unwrap();let t=run.tasks[0].clone();let zone:Vec<P>=serde_json::from_value(t.terrain["elevation_zones"][1]["polygon"].clone()).unwrap();let high=centroid(&zone);assert_eq!(ground_cover(&t.terrain,high),0.8);assert_eq!(ground_cover(&t.terrain,t.beach),1.);for (p,expected) in [(high,84.),(t.beach,80.)]{let mut fixture=run.clone();fixture.companies[0].stage="ground".into();fixture.companies[0].order="hold".into();let mut ally=fixture.bodies[0].clone();ally.id=900;ally.ally=true;ally.unit=fixture.companies[0].start.unit_id.clone();ally.company=fixture.companies[0].start.key().to_string();ally.island=t.island;ally.p=p;ally.hp=100.;ally.max=100.;ally.ammo=0;ally.order="hold".into();let mut enemy=ally.clone();enemy.id=901;enemy.ally=false;enemy.kind="land_cult_sentinel".into();enemy.unit=String::new();enemy.p=p+P{x:120.,y:0.};enemy.damage=20.;enemy.attack_at=Some(0.);enemy.aim=p;enemy.ammo=1;fixture.bodies=vec![ally,enemy];advance_ground(&mut fixture,0.);assert!((fixture.bodies[0].hp-expected).abs()<0.001,"actual hp {}",fixture.bodies[0].hp);}assert_eq!(t.terrain["height_los"],false);}
    #[test] fn real_land_damage_corpses_and_reward_require_search_and_recovery(){let mut w=World::new_salvage(42,start()).unwrap();let task=w.amphibious_expedition.as_ref().unwrap().tasks[0].clone();w.ship_mut(1).unwrap().p=task.shore;w.ship_mut(1).unwrap().speed=0.;w.amphibious_command(&json!({"op":"expedition_land_deploy","unit_id":"MCP-034","x":task.p.x,"y":task.p.y})).unwrap();assert!(w.amphibious_extract_blocker().is_some());for _ in 0..26{w.tick+=1;w.advance_amphibious_expedition();}w.amphibious_command(&json!({"op":"expedition_land_task","unit_id":"MCP-034","task":task.id})).unwrap();for _ in 0..55{w.tick+=1;w.advance_amphibious_expedition();}let r=w.amphibious_expedition.as_ref().unwrap();assert_eq!(r.tasks[0].status,"complete");assert!(r.bodies.iter().any(|b|!b.ally&&b.hp<=0.));assert!(w.salvage.as_ref().unwrap().ruins.iter().any(|r|r.id==task.id&&!r.collected));assert!(w.salvage.as_ref().unwrap().cargo.is_empty());w.amphibious_command(&json!({"op":"expedition_land_recover","unit_id":"MCP-034"})).unwrap();for _ in 0..100{if w.amphibious_expedition.as_ref().unwrap().companies[0].stage=="recovered"{break;}w.tick+=1;w.advance_amphibious_expedition();}assert_eq!(w.amphibious_expedition.as_ref().unwrap().companies[0].stage,"recovered");assert!(w.amphibious_extract_blocker().is_none());let next=w.amphibious_expedition.as_ref().unwrap().tasks[1].clone();w.ship_mut(1).unwrap().p=next.shore;w.amphibious_command(&json!({"op":"expedition_land_deploy","unit_id":"MCP-034","x":next.p.x,"y":next.p.y})).unwrap();for _ in 0..26{w.tick+=1;w.advance_amphibious_expedition();}assert_eq!(w.amphibious_expedition.as_ref().unwrap().bodies.iter().filter(|b|b.ally).count(),10);}
    #[test]fn opt_in_keeps_old_raw_start_without_new_nulls(){let mut v=serde_json::to_value(start()).unwrap();v["gameplay_profile"]=json!(crate::expedition::VERSION);v.as_object_mut().unwrap().remove("amphibious_expedition");let old:Start=serde_json::from_value(v).unwrap();let raw=serde_json::to_value(&old).unwrap();assert!(raw.get("amphibious_expedition").is_none());assert!(World::new_salvage(42,old).unwrap().amphibious_expedition.is_none());}
    #[test]fn real_command_log_reconstructs_land_and_corpses(){let mut e=crate::Engine::default();let ask=|e:&mut crate::Engine,q|{let r=e.handle(q);assert_eq!(r["ok"],true,"{r}");r["data"].clone()};ask(&mut e,json!({"op":"new_salvage","seed":42,"start":start()}));ask(&mut e,json!({"op":"extraction_autopilot","enabled":true,"policy":"bold","version":"cas-extraction-pilot-v3"}));let v=ask(&mut e,json!({"op":"step","seconds":32}));assert!(v["salvage"]["amphibious"]["ai_commands"].as_u64().unwrap()>0);let saved=ask(&mut e,json!({"op":"save"}));assert_eq!(ask(&mut e,json!({"op":"load","save":saved.clone()})),v);assert_eq!(ask(&mut e,json!({"op":"replay","save":saved})),v);}
    #[test]fn real_two_fleets_land_search_recover_or_report_true_losses(){let mut s=start();s.weather=Some(crate::salvage_weather::VERSION.into());s.intel_profile=crate::intel::VERSION.into();s.fleet[0].id="IBS-U-USN-ERMA-IOWA".into();s.fleet.push(crate::salvage::Hull{id:"IBS-U-USN-FLETCHER".into(),hp:100,ammo:100,..Default::default()});s.groups=vec![crate::salvage::Group{id:"heavy".into(),name:"登陆护送一队".into(),ships:vec!["IBS-U-USN-ERMA-IOWA".into()]},crate::salvage::Group{id:"light".into(),name:"登陆护送二队".into(),ships:vec!["IBS-U-USN-FLETCHER".into()]}];s.amphibious_expedition.as_mut().unwrap().companies[0].carrier_identity="IBS-U-USN-ERMA-IOWA".into();s.amphibious_expedition.as_mut().unwrap().companies.push(CompanyStart{company_id:String::new(),unit_id:"MCP-009".into(),carrier_identity:"IBS-U-USN-FLETCHER".into(),transport_kind:"landing_craft".into(),condition_percent:100});let mut w=World::new_salvage(43,s).unwrap();w.external(json!({"op":"extraction_autopilot","enabled":true,"policy":"balanced","version":"cas-extraction-pilot-v3"})).unwrap();for _ in 0..1200{if w.result.is_some(){break;}w.advance();}let r=w.amphibious_expedition.as_ref().unwrap();println!("FULL_COMBAT tick={} terminal={} extracted={} completed={} phases={:?} waves={}/{}",w.tick,w.result.is_some(),w.salvage.as_ref().unwrap().extracted,r.tasks.iter().filter(|t|t.status=="complete").count(),r.companies.iter().map(|c|(&c.start.unit_id,&c.stage)).collect::<Vec<_>>(),r.sea_spawned,r.land_spawned);assert!(w.result.is_some(),"multi-fleet pilot did not close");assert!(w.salvage.as_ref().unwrap().extracted);assert!(r.tasks.iter().filter(|t|t.status=="complete").count()>=2);assert!(r.sea_spawned<=MAX_SEA_REINFORCEMENTS);assert!(r.land_spawned<=MAX_LAND_ENEMIES as u32);assert!(r.companies.iter().all(|c|c.carrier>0));}
    #[test]fn controlled_naval_window_allows_repeated_army_tasks_and_true_extraction(){let mut w=World::new_salvage(42,start()).unwrap();for ship in &mut w.ships{if ship.side==1{ship.hp=0.;}}w.amphibious_expedition.as_mut().unwrap().sea_spawned=MAX_SEA_REINFORCEMENTS;w.expedition.as_mut().unwrap().boss_status="defeated".into();w.external(json!({"op":"extraction_autopilot","enabled":true,"policy":"balanced","version":"cas-extraction-pilot-v3"})).unwrap();for _ in 0..1200{if w.result.is_some(){break;}w.advance();}let v=w.observation(0);println!("tick={} groups={} tasks={} pilot={} result={}",w.tick,v["salvage"]["amphibious"]["groups"],v["salvage"]["amphibious"]["tasks"].as_array().unwrap().iter().map(|t|json!([t["id"],t["status"],t["progress"]])).collect::<Vec<_>>().iter().map(|x|x.to_string()).collect::<Vec<_>>().join(","),v["salvage"]["expedition"]["autopilot"],v["result"]);assert!(w.amphibious_expedition.as_ref().unwrap().tasks.iter().filter(|t|t.status=="complete").count()>=2);assert!(w.amphibious_expedition.as_ref().unwrap().land_done);assert!(w.amphibious_expedition.as_ref().unwrap().companies.iter().all(|c|["recovered","lost","embarked"].contains(&c.stage.as_str())));assert!(w.result.is_some());assert!(w.salvage.as_ref().unwrap().extracted);}
}

