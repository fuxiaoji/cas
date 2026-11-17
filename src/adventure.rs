//! Opt-in fictional action-travel rules. The absent profile is the frozen
//! historical/legacy path; never infer a profile while loading a snapshot.
use crate::{model::*,salvage::{Start,Ruin},world::{World,roll}};
use serde_json::{json,Value};
pub const VERSION:&str="cas-adventure-v1";

pub(crate) fn validate(s:&Start)->E<()> {
    if s.gameplay_profile.is_empty(){return if s.expedition_v2.is_some(){Err("旧航次不能带新远征配置".into())}else{Ok(())};}
    if s.gameplay_profile==crate::expedition::VERSION{return crate::expedition::validate(s);}
    if s.gameplay_profile==crate::amphibious_expedition::VERSION{return crate::amphibious_expedition::validate(s);}
    if s.expedition_v2.is_some(){return Err("旧冒险不能带新远征配置".into());}
    if s.gameplay_profile!=VERSION || !s.mission.as_ref().is_some_and(|m|
        (m.kind=="chapter" && (s.content==crate::salvage_v3::VERSION || crate::story_missions::active(s)))
        || (m.kind=="salvage" && s.content==crate::salvage_v4::VERSION)) {
        return Err("冒险规则仅支持明确登记的新剧情或新版搜打撤，不能用于历史/天梯/旧航次".into());
    }Ok(())
}
pub(crate) fn segment_distance(p:P,a:P,b:P)->f64 {
    let d=b-a;let t=if d.len()>0.{((p-a).dot(d)/(d.len()*d.len())).clamp(0.,1.)}else{0.};p.dist(a+d*t)
}
fn intersects_lane(poly:&[P],a:P,b:P,clearance:f64)->bool {
    let steps=(a.dist(b)/80.).ceil().max(1.) as u32;
    (0..=steps).any(|i|crate::salvage::polygon_near(poly,a+(b-a)*(i as f64/steps as f64),clearance))
}
/// A connected shipping tree is reserved *before* island placement. All shape
/// candidates are rejected against its swept clearance, so every loot site and
/// exit has a continuous, ship-width water route, even as topology changes.
pub(crate) fn terrain(w:&mut World,seed:u32,start:&Start,ruins:&mut [Ruin])->E<()> {
    // This new fictional profile reserves its large landing islands before
    // any ruin, enemy or shipping route is placed. Frozen v1/v2 use the exact
    // generator below, including its RNG sequence.
    if crate::amphibious_expedition::is_version(&start.gameplay_profile) {
        return crate::amphibious_expedition::terrain(w,seed,ruins);
    }
    let theme=w.ecology.as_ref().unwrap().theme.clone();
    let mut rng=u64::from(seed)^0x42c9_d127_f395 ^ crate::story_missions::terrain_salt(start);
    for (i,ruin) in ruins.iter_mut().enumerate().skip(1) {
        ruin.p=P{x:4600.+(i%4) as f64*4500.+roll(&mut rng,1800) as f64,
            y:3200.+(i/4) as f64*3500.+roll(&mut rng,2100) as f64};
    }
    let spawn=P{x:2200.,y:2200.};
    let mut points=vec![spawn,P{x:22000.,y:2200.},P{x:2200.,y:12000.}];
    points.extend(ruins.iter().map(|r|r.p));
    // The authored story objectives are physical positions, not only icons.
    points.extend([P{x:6200.,y:2200.},P{x:5500.,y:2200.},P{x:6500.,y:2200.}]);
    let mut lanes=vec![(spawn,P{x:22000.,y:2200.}),(spawn,P{x:2200.,y:w.field.height-600.})];
    lanes.extend(crate::story_missions::shipping_lanes(start));
    for i in 1..points.len() {
        let nearest=points[..i].iter().copied().min_by(|a,b|a.dist(points[i]).total_cmp(&b.dist(points[i]))).unwrap();
        lanes.push((nearest,points[i]));
    }
    let rock=|rng:&mut u64,c:P,rx:f64,ry:f64,angle:f64|->Vec<P>{(0..12).map(|j|{
        let a=j as f64*std::f64::consts::TAU/12.;let r=0.72+roll(rng,29) as f64/100.;
        let x=libm::cos(a)*rx*r;let y=libm::sin(a)*ry*r;
        c+P{x:x*libm::cos(angle)-y*libm::sin(angle),y:x*libm::sin(angle)+y*libm::cos(angle)}
    }).collect()};
    let mut shapes:Vec<Vec<P>>=vec![];
    let story=start.mission.as_ref().is_some_and(|m|m.kind=="chapter");
    let layout=roll(&mut rng,3)-1;
    let target=match theme.as_str(){"atoll"=>28+roll(&mut rng,20),"drowned_city"=>30+roll(&mut rng,26),"fjord"=>12+roll(&mut rng,16),_=>20+roll(&mut rng,20)} as usize;
    for i in 0..110 {
        let c=P{x:4000.+roll(&mut rng,18300) as f64,y:if story{3400.+roll(&mut rng,9400) as f64}else{1400.+roll(&mut rng,11400) as f64}};
        let mut candidates=vec![];
        match theme.as_str() {
            "atoll"=>{
                let radius=if i<8{1300.+roll(&mut rng,700) as f64}else{650.+roll(&mut rng,600) as f64};
                let count=3+roll(&mut rng,3);
                for j in 0..count {
                    let a=(j as f64+layout as f64*0.3)*std::f64::consts::TAU/count as f64;
                    let mut ring=vec![];let half=if i<8{0.42}else{0.31};let width=if i<8{300.}else{160.};
                    for k in 0..6{let angle=a-half+2.*half*k as f64/5.;ring.push(c+P::bearing(angle.to_degrees())*(radius-width));}
                    for k in (0..6).rev(){let angle=a-half+2.*half*k as f64/5.;ring.push(c+P::bearing(angle.to_degrees())*(radius+width));}
                    candidates.push(ring);
                }
            },
            "fjord"=>{
                let angle=(layout as f64-1.)*0.35;
                let rx=if i<8{1600.+roll(&mut rng,1200) as f64}else{800.+roll(&mut rng,800) as f64};let ry=if i<8{700.+roll(&mut rng,800) as f64}else{280.+roll(&mut rng,400) as f64};
                candidates.push(rock(&mut rng,c,rx,ry,angle));
            },
            "drowned_city"=>{
                let rx=110.+roll(&mut rng,250) as f64;let ry=110.+roll(&mut rng,220) as f64;
                let skew=roll(&mut rng,140) as f64;
                candidates.push(vec![c+P{x:-rx,y:-ry},c+P{x:rx,y:-ry+skew},c+P{x:rx,y:ry},c+P{x:-rx,y:ry-skew}]);
                if i%4==0{candidates.push(rock(&mut rng,c+P{x:700.,y:450.},600.,400.,0.));}
            },
            _=>{
                let rx=if i<8{1300.+roll(&mut rng,1100) as f64}else{250.+roll(&mut rng,750) as f64};let ry=if i<8{700.+roll(&mut rng,800) as f64}else{230.+roll(&mut rng,650) as f64};
                candidates.push(rock(&mut rng,c,rx,ry,layout as f64*0.6));
            }
        }
        for polygon in candidates {
            if polygon.iter().any(|p|p.x<3600.||p.x>23400.||p.y<if story{2900.}else{800.}||p.y>13400.)
                || lanes.iter().any(|&(a,b)|intersects_lane(&polygon,a,b,420.))
                || shapes.iter().any(|other|polygon.iter().any(|&p|crate::salvage::polygon_near(other,p,200.))
                    ||other.iter().any(|&p|crate::salvage::polygon_near(&polygon,p,200.))) {continue;}
            shapes.push(polygon);
            if shapes.len()>=target{break;}
        }
        if shapes.len()>=target{break;}
    }
    if shapes.len()<4{return Err("冒险海域未生成足够地貌，出航未提交".into());}
    for &(a,b) in &lanes {if shapes.iter().any(|poly|intersects_lane(poly,a,b,350.)){return Err("冒险航路未通过连续水域校验".into());}}
    let offset=w.field.width-24000.;
    let eco=w.ecology.as_mut().unwrap();eco.landmarks.clear();
    for (i,poly) in shapes.iter().enumerate() {
        if theme!="drowned_city" && i%3!=0 {continue;}
        let c=poly.iter().copied().fold(P::default(),|a,b|a+b)*(1./poly.len() as f64);
        let kind=["drowned_tower","industrial_ruin","flooded_dock","radio_mast","cult_pylon"][(i+seed as usize)%5];
        eco.landmarks.push(json!({"id":i+1,"kind":kind,"x":c.x+offset,"y":c.y,"seed":roll(&mut rng,u32::MAX),"island_index":i,
            "height_m":30+roll(&mut rng,140),"flood":0.25+roll(&mut rng,50) as f64/100.,"charted":true,"collision":"island",
            "footprint":poly.iter().map(|p|c+(*p-c)*0.45+P{x:offset,y:0.}).collect::<Vec<_>>()}));
    }
    eco.layout=format!("{}-{}",theme,["branching","scattered","braided"][layout as usize]);
    w.islands=shapes;Ok(())
}
impl World {
    pub(crate) fn adventure(&self)->bool {self.salvage.as_ref().is_some_and(|b|[VERSION,crate::expedition::VERSION,crate::amphibious_expedition::VERSION].contains(&b.start.gameplay_profile.as_str()))}
    /// Placement repair only applies to new fictional content; it cannot move a
    /// historical ship. Bounded lattice search finds clear water near each den.
    pub(crate) fn init_adventure(&mut self)->E<()> {
        let mut occupied:Vec<P>=self.ships.iter().filter(|s|s.side==0).map(|s|s.p).collect();
        for i in 0..self.ships.len() {
            if self.ships[i].side!=1{continue;}
            let origin=self.ships[i].p;
            let seed_shift=P{x:((self.seed.wrapping_mul(173)+(i as u32)*293)%900) as f64-450.,y:((self.seed.wrapping_mul(97)+(i as u32)*389)%1200) as f64-600.};
            let base=origin+seed_shift;
            let p=(0..25).flat_map(|r|(0..16).map(move|a|base+P::bearing(a as f64*22.5)*(r as f64*180.)))
                .find(|p|self.field.contains(*p)&&occupied.iter().all(|q|q.dist(*p)>400.)&&!self.islands.iter().any(|poly|crate::salvage::polygon_near(poly,*p,220.)))
                .ok_or("冒险怪物巢位未找到安全水域")?;
            self.ships[i].p=p;occupied.push(p);
        }Ok(())
    }
    pub(crate) fn adventure_view(&self,view:&mut Value){
        if !self.adventure(){return;}
        let eco=self.ecology.as_ref().unwrap();
        view["salvage"]["generatorVersion"]=json!("archipelago-adventure-1");
        view["salvage"]["adventure"]=json!({"version":self.salvage.as_ref().unwrap().start.gameplay_profile,"movement_multiplier":10,"acceleration_multiplier":6,"acceleration_min_knots_per_second":4,"braking_min_knots_per_second":6,"terrain_layout":eco.layout});
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::{BTreeSet,VecDeque};
    fn chapter(id:&str)->Start{let mut s=crate::salvage_v3::chapter_start(id).unwrap();s.gameplay_profile=VERSION.into();s}
    #[test]
    fn explicit_profile_never_changes_legacy_serialization_and_rejects_other_modes(){
        let old=crate::salvage_v3::chapter_start("c1-boss").unwrap();assert!(serde_json::to_value(&old).unwrap().get("gameplay_profile").is_none());
        let mut s=chapter("c1-boss");s.gameplay_profile="future".into();assert!(World::new_salvage(9,s).is_err());
        let mut s=chapter("c1-boss");s.chapter_version.clear();s.mission.as_mut().unwrap().kind="resources".into();assert!(World::new_salvage(9,s).is_err());
        let mut s=chapter("c1-boss");s.chapter_version.clear();s.content="salvage-v2".into();s.mission.as_mut().unwrap().kind="salvage".into();assert!(World::new_salvage(9,s).is_err());
    }
    #[test]
    fn tenfold_travel_sixfold_response_without_advancing_the_clock(){
        let mut old=World::new_salvage(9,crate::salvage_v3::chapter_start("c1-breakout").unwrap()).unwrap();
        let mut new=World::new_salvage(9,chapter("c1-breakout")).unwrap();
        for w in [&mut old,&mut new] {w.external(json!({"op":"route","fleet":1,"mode":"follow","speed":6,"points":[{"x":7400,"y":2200}]})).unwrap();w.fleets[0].actual=6.;}
        let p=old.ships[0].p;
        old.move_ships();new.move_ships();
        assert!((new.ships[0].p.dist(p)/old.ships[0].p.dist(p)-10.).abs()<0.002);
        assert_eq!(old.tick,new.tick);
        assert_eq!(old.dynamic_weather().unwrap().view(1),new.dynamic_weather().unwrap().view(1));
        old.fleets[0].actual=0.;new.fleets[0].actual=0.;old.move_ships();new.move_ships();
        assert!(new.fleets[0].actual>=old.fleets[0].actual*6.);assert_eq!(new.fleets[0].actual,4.);
        new.fleets[0].actual=30.;new.fleets[0].speed=0.;new.move_ships();assert!(new.fleets[0].actual<=24.);
    }
    fn reachability(w:&World)->bool {
        let step=300.;let cols=(w.field.width/step) as i32;let rows=(w.field.height/step) as i32;
        let clear=|x:i32,y:i32|{let p=P{x:x as f64*step+150.,y:y as f64*step+150.};w.field.contains(p)&&!w.islands.iter().any(|poly|crate::salvage::polygon_near(poly,p,90.))};
        let start=((w.ships[0].p.x/step) as i32,(w.ships[0].p.y/step) as i32);
        let mut queue=VecDeque::from([start]);let mut seen=BTreeSet::from([start]);
        while let Some((x,y))=queue.pop_front(){for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)]{let q=(x+dx,y+dy);if q.0>=0&&q.1>=0&&q.0<cols&&q.1<rows&&!seen.contains(&q)&&clear(q.0,q.1){seen.insert(q);queue.push_back(q);}}}
        w.salvage.as_ref().unwrap().ruins.iter().map(|r|r.p).chain(w.salvage.as_ref().unwrap().exits.iter().copied()).all(|p|seen.contains(&((p.x/step) as i32,(p.y/step) as i32)))
    }
    #[test]
    fn generated_maps_change_topology_and_all_sites_are_connected(){
        for theme in ["atoll","fractured","fjord","drowned_city"] {
            let mut shapes=BTreeSet::new();let mut counts=BTreeSet::new();
            for seed in 0..20 {
                let s:Start=serde_json::from_value(json!({"content":"salvage-v4","gameplay_profile":VERSION,"fleet":[{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":100,"level":0}],"mission":{"kind":"salvage","id":"calm","loot_kind":"scrap"},"cargo_v4":{"commander_level":1,"difficulty":"calm","environment":theme,"weather":"clear","loadouts":{}}})).unwrap();
                let w=World::new_salvage(seed,s.clone()).unwrap();
                assert_eq!(serde_json::to_string(&w.islands).unwrap(),serde_json::to_string(&World::new_salvage(seed,s).unwrap().islands).unwrap());
                shapes.insert(serde_json::to_string(&w.islands).unwrap());counts.insert(w.islands.len());
                assert!(w.ships.iter().all(|s|!w.islands.iter().any(|poly|crate::salvage::polygon_near(poly,s.p,70.))));
                if seed<2 {assert!(reachability(&w),"{theme} seed{seed}");}
            }
            assert_eq!(shapes.len(),20);assert!(counts.len()>1,"topology must change count, not only jitter {theme}");
        }
        for id in ["c1-breakout","c1-salvage","c1-boss"]{assert!(reachability(&World::new_salvage(6109,chapter(id)).unwrap()));}
    }
    #[test]
    fn public_monster_readouts_and_warnings_disappear_with_contacts(){
        let mut w=World::new_salvage(6109,chapter("c1-breakout")).unwrap();
        let v=w.observation(0);assert_eq!(v["salvage"]["adventure"]["version"],VERSION);
        assert!(v["contacts"].as_array().unwrap().iter().any(|c|c["health"].is_number()&&c["attack"]["counter"].is_string()));
        for _ in 0..8{w.advance();}
        let v=w.observation(0);assert!(v["salvage"]["telegraphs"].as_array().unwrap().iter().any(|t|t["shape"]=="capsule"));
        w.contacts[0].clear();let v=w.observation(0);assert_eq!(v["contacts"],json!([]));assert_eq!(v["salvage"]["telegraphs"],json!([]));
    }
    #[test]
    fn high_speed_swept_collision_cannot_tunnel_through_a_thin_island(){
        let mut w=World::new_salvage(6109,chapter("c1-breakout")).unwrap();
        let p=w.ships[0].p;
        w.islands=vec![vec![P{x:p.x+75.,y:p.y-200.},P{x:p.x+85.,y:p.y-200.},P{x:p.x+85.,y:p.y+200.},P{x:p.x+75.,y:p.y+200.}]];
        w.ships[0].track=Some(Track::new(vec![p,p+P{x:1000.,y:0.}],0.,1000.));w.fleets[0].speed=30.;w.fleets[0].actual=30.;
        w.move_ships();assert_eq!(w.ships[0].p,p);assert!(w.ships[0].track.is_none());
    }
}
