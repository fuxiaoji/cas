//! Naval-only second revision. Explicit opt-in keeps carrier-ops-v1 replays frozen.
use super::*;
pub(super) const VERSION:&str="cas-carrier-ops-v2";
pub(super) const LANDING_FUEL_RESERVE:f64=3000.;
pub(super) const PATROL_RADIUS:f64=600.;
pub(super) const HOLDING_RADIUS:f64=650.;
pub(super) const PATROL_ENTRY:f64=800.;
const HOLDING_ENTRY:f64=900.;
const ORBIT_TURN_RATE:f64=30.;
#[derive(Default)]
pub(super) struct CommandState {
    pub(super) manual:BTreeSet<String>,
    pub(super) policies:BTreeMap<u32,String>,
    pub decisions:Vec<Value>,
    pub automation:Option<super::carrier_ops_v3::Automation>,
}

#[cfg(test)]
mod tests{
    use super::*;
    fn battle(ai:bool)->Battle{
        let config=Config{mode:"tutorial".into(),company_layout:None,lesson:Some("landing".into()),ships:vec![Hull{id:ENTERPRISE.into(),hp:100.,ammo:100},Hull{id:SHOKAKU.into(),hp:100.,ammo:100}],roster:vec!["MCP-034".into(),"MCP-001".into()],unit_condition:vec![],transport_preset:"combat".into(),defense:vec![],company_transports:vec![]};
        let mut w=Battle::new(42,config).unwrap();w.command(&json!({"op":"carrier_ops","version":VERSION,"ally_ai":ai}),true).unwrap();w
    }
    fn cap(w:&mut Battle)->String{let id=w.squadrons[0].id.clone();let p=w.naval.ship(1).unwrap().p;w.command(&json!({"op":"littoral_air_order","queue":true,"squadron_id":id,"action":"patrol","x":p.x,"y":p.y-1200.}),true).unwrap();for _ in 0..100{w.advance()}id}
    #[test]fn airborne_drag_changes_real_flight_without_new_planes_or_weapons(){
        let mut w=battle(false);let id=cap(&mut w);let p=w.naval.ship(1).unwrap().p;let before=w.aircraft.clone();let stock=w.squadrons[0].stock;
        let q=json!({"op":"carrier_air_order","scope":"flight","squadron_id":id,"action":"patrol","x":p.x+1500.,"y":p.y-1200.});
        w.command(&q,true).unwrap();assert_eq!(before.len(),w.aircraft.len());assert_eq!(stock,w.squadrons[0].stock);
        for(a,b)in before.iter().zip(&w.aircraft){assert_eq!((a.id,a.fuel,a.hp,a.weapons),(b.id,b.fuel,b.hp,b.weapons));assert_eq!(b.target.x,p.x+1500.);}
        assert_eq!(Battle::from_save(w.save(),None).unwrap().view(),w.view());
    }
    #[test]fn invalid_or_fuel_unsafe_redirect_is_atomic_and_return_cannot_be_relaunched(){
        let mut w=battle(false);let id=cap(&mut w);let p=w.naval.ship(1).unwrap().p;
        let q=json!({"op":"carrier_air_order","scope":"flight","squadron_id":id,"action":"patrol","x":p.x+1000.,"y":p.y-1000.});
        w.aircraft[0].fuel=500.;let before=w.view();assert!(w.command(&q,true).is_err());assert_eq!(before,w.view());
        w.command(&json!({"op":"carrier_air_order","scope":"flight","squadron_id":id,"action":"return"}),true).unwrap();let before=w.view();assert!(w.command(&q,true).is_err());assert_eq!(before,w.view());
    }
    #[test]fn whole_wing_recall_cancels_queue_and_ai_cannot_undo_manual_control(){
        let mut w=battle(false);let id=cap(&mut w);let bomber=w.squadrons[1].id.clone();let p=w.naval.ship(1).unwrap().p;
        w.command(&json!({"op":"littoral_air_order","queue":true,"squadron_id":bomber,"action":"strike","target_kind":"land","x":12000.,"y":13000.}),true).unwrap();
        w.command(&json!({"op":"carrier_air_order","scope":"wing","carrier":1,"action":"return"}),true).unwrap();assert!(w.carrier_ops.as_ref().unwrap().queue.is_empty());
        w.command(&json!({"op":"carrier_ops","version":VERSION,"ally_ai":true}),true).unwrap();for _ in 0..600{w.advance()}
        assert!(!w.aircraft.iter().any(|a|a.carrier==1));assert_eq!(w.squadrons[0].available,3);assert_eq!(w.squadrons[0].lost,0);
        assert!(w.carrier_v2_view()["manual_squadrons"].as_array().unwrap().iter().any(|x|x==&id));let _=p;
        assert_eq!(Battle::from_save(w.save(),None).unwrap().view(),w.view());
    }
    #[test]fn stale_target_queue_cancels_with_a_visible_reason(){
        let mut w=battle(false);let id=w.squadrons[1].id.clone();let contact=w.naval.contacts[0][0].clone();
        w.command(&json!({"op":"littoral_air_order","queue":true,"squadron_id":id,"action":"strike","target_kind":"ship","target_id":contact.id,"x":contact.x,"y":contact.y}),true).unwrap();
        w.naval.ship_mut(contact.ship).unwrap().hp=0.;w.ground.frame=10;w.carrier_v2_advance();
        assert!(w.carrier_ops.as_ref().unwrap().queue.is_empty());assert_eq!(w.squadrons[1].available,3);assert!(!w.carrier_ops.as_ref().unwrap().rejected.is_empty());
    }
    #[test]fn three_decks_receive_real_flights_and_landings_keep_priority(){
        let mut w=battle(true);let c=w.naval.ship(1).unwrap().clone();let third=w.naval.spawn(c.def,0,99,"第三测试甲板".into(),c.p+P{x:100.,y:100.},c.h).unwrap();
        for i in 0..3{let mut s=w.squadrons[i].clone();s.carrier=third;s.id=format!("third-{}",s.model);w.squadrons.push(s);}
        for _ in 0..300{w.advance()}
        for c in [1,2,third]{assert!(w.aircraft.iter().any(|a|a.carrier==c),"deck {c} starved");}
        assert!(w.aircraft.iter().filter(|a|w.naval.ship(a.carrier).is_some_and(|c|c.side==0)).count()<=12);
        w.aircraft[0].phase="returning";w.aircraft[0].p=c.p;let mother=w.aircraft[0].carrier;
        let i=w.squadrons.iter().position(|s|s.carrier==mother&&s.available>0).unwrap();assert_eq!(w.carrier_v2_wait(i),Some("优先回收返航机"));
    }
    #[test]fn enemy_carrier_uses_real_planes_but_its_decisions_are_not_exposed(){
        let mut w=battle(true);let c=w.naval.ship(2).unwrap().clone();let enemy=w.naval.spawn(c.def,1,99,"对手测试甲板".into(),c.p+P{x:-4000.,y:0.},c.h).unwrap();
        for i in 3..6{let mut s=w.squadrons[i].clone();s.carrier=enemy;s.id=format!("enemy-{}",s.model);w.squadrons.push(s);}
        w.naval.refresh_open_intel();for _ in 0..150{w.advance()}
        assert!(w.aircraft.iter().any(|a|a.carrier==enemy));assert!(w.squadrons.iter().filter(|s|s.carrier==enemy).any(|s|s.stock<18));
        let v=w.carrier_v2_view();assert!(v["decisions"].as_array().unwrap().iter().all(|d|d["carrier"]!=enemy));
        for side in [0,1]{assert!(w.aircraft.iter().filter(|a|a.hp>0.&&w.naval.ship(a.carrier).is_some_and(|c|c.side==side)).count()<=12);}
    }
    #[test]fn patrol_and_landing_hold_never_stop_and_burn_real_fuel(){
        let mut w=battle(false);let id=cap(&mut w);
        for _ in 0..100{
            let before=w.aircraft.iter().find(|a|a.squadron==0).unwrap().clone();w.advance();let after=w.aircraft.iter().find(|a|a.id==before.id).unwrap();
            assert!((before.p.dist(after.p)-before.speed*DT).abs()<1e-6);assert!(after.fuel<before.fuel);
        }
        w.command(&json!({"op":"carrier_air_order","scope":"flight","squadron_id":id,"action":"return"}),true).unwrap();
        let p=w.naval.ship(1).unwrap().p;w.aircraft[0].p=p+P{x:500.,y:0.};w.deck.insert(1,w.ground.frame+80);
        for _ in 0..30{let before=w.aircraft[0].clone();w.advance();let after=w.aircraft.iter().find(|a|a.id==before.id).unwrap();assert!((before.p.dist(after.p)-before.speed*DT).abs()<1e-6);assert!(after.fuel<before.fuel);assert_eq!(after.phase,"returning");}
        for _ in 0..500{w.advance()}assert!(!w.aircraft.iter().any(|a|a.carrier==1));assert_eq!(w.squadrons[0].available,3);
    }
    #[test]fn cap_splits_interceptors_instead_of_overassigning_one_enemy(){
        let mut w=battle(false);cap(&mut w);let c=w.naval.ship(2).unwrap().clone();let enemy=w.naval.spawn(c.def,1,99,"拦截测试母舰".into(),c.p+P{x:-4000.,y:0.},c.h).unwrap();
        let own=w.aircraft[0].clone();
        for j in 0..3{let mut e=own.clone();e.id=100+j;e.carrier=enemy;e.hp=90.;e.phase="outbound";e.mission="strike";e.target_kind="land".into();e.target_id=Value::Null;e.p=own.p+P{x:100.+100.*j as f64,y:100.};w.aircraft.push(e);}
        w.carrier_v2_intercepts();let own:Vec<_>=w.aircraft.iter().filter(|a|a.carrier==1).collect();
        let targets:BTreeSet<_>=own.iter().filter_map(|a|a.target_id.as_u64()).collect();assert!(targets.len()>=2);
        for id in targets{assert!(own.iter().filter(|a|a.target_id==id).count()<=2);}
    }
}
impl Battle {
    pub(super) fn carrier_v2_intercepts(&mut self){
        for i in 0..self.aircraft.len(){
            let a=&self.aircraft[i];
            if a.hp<=0.||a.role!="fighter"||a.mission!="patrol"||a.phase=="returning"||a.phase=="launching"||a.weapons==0{continue}
            let side=self.naval.ship(a.carrier).map_or(0,|c|c.side);
            let target=self.aircraft.iter().filter(|e|{
                if e.hp<=0.||e.phase=="launching"||!self.naval.ship(e.carrier).is_some_and(|c|c.side!=side)||e.p.dist(a.p)>3000.{return false}
                let assigned=self.aircraft.iter().filter(|f|f.hp>0.&&f.weapons>0&&f.phase!="returning"&&f.target_kind=="aircraft"&&f.target_id==e.id&&self.naval.ship(f.carrier).is_some_and(|c|c.side==side)).count();
                (assigned as f64)*55.<e.hp
            }).min_by(|x,y|{
                let priority=|e:&Aircraft|if e.role=="fighter"{1}else{0};
                priority(x).cmp(&priority(y)).then_with(||x.p.dist(a.p).total_cmp(&y.p.dist(a.p)))
            }).map(|e|(e.p,e.id));
            if let Some((p,id))=target{let a=&mut self.aircraft[i];a.target=p;a.target_id=json!(id);a.target_kind="aircraft".into();a.mission="strike";a.phase="outbound";}
        }
    }
    // Continuous flight at real airspeed. Patrol points are orbit centres.
    pub(super) fn carrier_v2_fly(&self,a:&mut Aircraft,target:P){
        let delta=target-a.p;let distance=delta.len();
        let holding=a.phase=="returning"&&distance<HOLDING_ENTRY&&self.deck.get(&a.carrier).is_some_and(|n|*n>self.ground.frame);
        let patrol=a.mission=="patrol"&&a.phase!="returning"&&(a.phase=="patrolling"||distance<PATROL_ENTRY);
        let mut direction=if holding||patrol{
            let radius=if holding{HOLDING_RADIUS}else{PATROL_RADIUS};
            let radial=if distance>1.{(a.p-target)*(1./distance)}else{P::bearing(a.heading)};
            let tangent=P{x:-radial.y,y:radial.x};
            (tangent+radial*((radius-distance)/radius*2.).clamp(-1.5,1.5)).unit()
        }else if distance>0.01{delta.unit()}else{P::bearing(a.heading)};
        if holding||patrol{let turn=norm(direction.heading()-a.heading+180.)-180.;a.heading=norm(a.heading+turn.clamp(-ORBIT_TURN_RATE*DT,ORBIT_TURN_RATE*DT));direction=P::bearing(a.heading);}
        let travel=a.speed*DT;a.p=a.p+direction*travel;a.heading=direction.heading();a.fuel=(a.fuel-travel*1.1).max(0.);
    }
    pub(super) fn carrier_is_v2(&self)->bool{self.carrier_ops.as_ref().is_some_and(|o|o.modern.is_some())}
    pub(super) fn carrier_v2_configure(&mut self,q:&Value)->E<()> {
        let ai=q["ally_ai"].as_bool().ok_or("请选择航空托管开关")?;
        let ops=self.carrier_ops.get_or_insert_with(carrier_ops::Operations::default);
        ops.ally_ai=ai;ops.modern.get_or_insert_with(CommandState::default);Ok(())
    }
    fn carrier_v2_squad(&self,q:&Value)->E<usize>{
        if !self.carrier_is_v2(){return Err("请先启用新版航空指挥".into())}
        let id=q["squadron_id"].as_str().ok_or("请选择实际中队")?;
        let i=self.squadrons.iter().position(|s|s.id==id).ok_or("中队已失效")?;
        if !self.naval.ship(self.squadrons[i].carrier).is_some_and(|c|c.side==0){return Err("不可指挥敌方中队".into())}Ok(i)
    }
    pub(super) fn carrier_v2_enqueue(&mut self,q:&Value)->E<()> {
        let i=self.carrier_v2_squad(q)?;
        if q["action"]=="return"{self.air_order(q)?;self.carrier_v2_takeover(i);return Ok(())}
        self.air_plan(q)?;
        let s=&self.squadrons[i];
        if s.lost==s.total{return Err("该中队飞机已经全部损失".into())}
        if s.stock==0&&!self.aircraft.iter().any(|a|a.squadron==i&&a.hp>0.&&a.weapons>0){return Err("该中队没有可用航空武器".into())}
        let ops=self.carrier_ops.as_mut().unwrap();
        if !ops.queue.iter().any(|p|p["squadron_id"]==q["squadron_id"])&&ops.queue.len()>=24{return Err("待命中队已达上限".into())}
        ops.queue.retain(|p|p["squadron_id"]!=q["squadron_id"]);ops.rejected.retain(|p|p["squadron_id"]!=q["squadron_id"]);ops.queue.push(q.clone());self.carrier_v2_takeover(i);Ok(())
    }
    fn carrier_v2_takeover(&mut self,i:usize){self.carrier_ops.as_mut().unwrap().modern.as_mut().unwrap().manual.insert(self.squadrons[i].id.clone());}
    pub(super) fn carrier_v2_manual(&mut self,q:&Value)->E<()>{let i=self.carrier_v2_squad(q)?;self.carrier_v2_takeover(i);Ok(())}
    pub(super) fn carrier_v2_policy(&mut self,q:&Value)->E<()> {
        if !self.carrier_is_v2(){return Err("请先启用新版航空指挥".into())}
        let carrier=crate::world::u(q,"carrier")?;
        if !self.naval.ship(carrier).is_some_and(|c|c.side==0&&c.alive())||!self.squadrons.iter().any(|s|s.carrier==carrier){return Err("请选择本方实际航空母舰".into())}
        let policy=q["policy"].as_str().ok_or("请选择航空姿态")?;
        if !["balanced","defend","strike","hold"].contains(&policy){return Err("航空姿态无效".into())}
        let m=self.carrier_ops.as_mut().unwrap().modern.as_mut().unwrap();m.policies.insert(carrier,policy.into());
        if q["release_manual"]==true{for s in self.squadrons.iter().filter(|s|s.carrier==carrier){m.manual.remove(&s.id);}}
        Ok(())
    }
    // Every flight is validated atomically before any aircraft changes course.
    // Remaining fuel covers the new leg, return to the actual mother and a reserve.
    pub(super) fn carrier_v2_plan(&self,q:&Value)->E<Vec<(usize,P,String,Value)>> {
        if !self.carrier_is_v2(){return Err("请先启用新版航空指挥".into())}
        if q["scope"]=="wing"{
            let carrier=crate::world::u(q,"carrier")?;
            if q["action"]!="return"{return Err("联队卡拖回母舰以全联队召回；打击请拖具体中队".into())}
            if !self.naval.ship(carrier).is_some_and(|c|c.side==0)||!self.squadrons.iter().any(|s|s.carrier==carrier){return Err("请选择本方实际母舰".into())}
            return Ok(self.squadrons.iter().enumerate().filter(|(_,s)|s.carrier==carrier).map(|(i,_)|(i,P::default(),String::new(),Value::Null)).collect())
        }
        let i=self.carrier_v2_squad(q)?;
        if q["scope"]=="cancel"{
            if !self.carrier_ops.as_ref().unwrap().queue.iter().any(|p|p["squadron_id"]==q["squadron_id"]){return Err("该中队没有待命任务".into())}return Ok(vec![(i,P::default(),String::new(),Value::Null)])
        }
        if q["scope"]!="flight"{return Err("航空指令范围无效".into())}
        let s=&self.squadrons[i];let flights:Vec<_>=self.aircraft.iter().filter(|a|a.squadron==i&&a.hp>0.).collect();
        if flights.is_empty(){return Err("该中队没有实际在空飞机".into())}
        if q["action"]=="return"{return Ok(vec![(i,P::default(),String::new(),Value::Null)])}
        if flights.iter().any(|a|a.phase=="launching"){return Err("该中队尚未全部离开甲板，请等起飞完成后改令".into())}
        if flights.iter().any(|a|a.phase=="returning"){return Err("返航中不能重新派遣；请等待真实着舰整备".into())}
        let c=self.naval.ship(s.carrier).filter(|c|c.alive()).ok_or("母舰已经损失，不能下达新的出击目标")?;
        let mut validate=q.clone();validate["queue"]=json!(true);
        let (_,_,p,kind,target)=self.air_plan(&validate)?;
        if flights.iter().any(|a|a.weapons==0){return Err("在空飞机武器已用尽，请召回整备".into())}
        if flights.iter().any(|a|a.fuel<(a.p.dist(p)+p.dist(c.p))*1.15+LANDING_FUEL_RESERVE){return Err("改令后燃油不足以安全返舰，请缩短航线或召回".into())}
        Ok(vec![(i,p,kind,target)])
    }
    pub(super) fn carrier_v2_order(&mut self,q:&Value)->E<()> {
        let plan=self.carrier_v2_plan(q)?;
        for(i,p,kind,target)in plan{
            self.carrier_v2_takeover(i);
            if q["scope"]=="cancel"||q["action"]=="return"{self.carrier_ops.as_mut().unwrap().queue.retain(|o|o["squadron_id"]!=self.squadrons[i].id);}
            if q["scope"]=="cancel"{continue}
            for a in self.aircraft.iter_mut().filter(|a|a.squadron==i&&a.hp>0.){
                if q["action"]=="return"{a.phase="returning";}
                else{a.target=p;a.target_kind=kind.clone();a.target_id=target.clone();a.mission=if q["action"]=="patrol"{"patrol"}else{"strike"};a.phase="outbound";}
            }
        }Ok(())
    }
    pub(super) fn carrier_v2_wait(&self,i:usize)->Option<&'static str>{
        let s=&self.squadrons[i];let c=self.naval.ship(s.carrier)?;
        if !c.alive(){return Some("母舰已损失")}
        if self.aircraft.iter().any(|a|a.hp>0.&&a.carrier==s.carrier&&a.phase=="returning"&&a.p.dist(c.p)<1500.){return Some("优先回收返航机")}
        if s.available==0{return Some("等待在空飞机返舰")}
        if s.stock==0{return Some("等待未投武器返舰归库")}
        if s.ready>self.ground.frame{return Some("等待飞机整备")}
        if self.deck.get(&s.carrier).is_some_and(|n|*n>self.ground.frame){return Some("等待本舰甲板")}
        if self.aircraft.iter().filter(|a|a.hp>0.).count()+s.available.min(3).min(s.stock)as usize>24{return Some("等待活动飞机名额")}
        None
    }
    pub(super) fn carrier_v2_advance(&mut self){
        if self.ground.frame%10!=0{return}
        // Automatically assigned CAP follows its real mother; hand-dragged CAP
        // keeps the player's chosen point. Moving the goal never restores fuel.
        for a in &mut self.aircraft{
            let Some(c)=self.naval.ship(a.carrier).filter(|c|c.alive())else{continue};
            let ops=self.carrier_ops.as_ref().unwrap();let m=ops.modern.as_ref().unwrap();
            if a.hp>0.&&a.mission=="patrol"&&a.phase!="returning"&&a.phase!="launching"&&!m.manual.contains(&self.squadrons[a.squadron].id)&&(c.side==1||ops.ally_ai){
                let p=if let Some(v)=&m.automation{v.patrol_goal(a.carrier).unwrap_or(c.p+P{x:0.,y:-1200.})}else{c.p+P{x:0.,y:-1200.}};
                if a.target.dist(p)>if m.automation.is_some(){1.}else{1000.}{a.target=p;a.phase="outbound";}
            }
        }
        // Keep the active version installed during validation and launch.
        let pending=std::mem::take(&mut self.carrier_ops.as_mut().unwrap().queue);
        for mut q in pending{
            let Some(i)=self.squadrons.iter().position(|s|q["squadron_id"]==s.id)else{continue};
            let s=&self.squadrons[i];
            let cancel=if !self.naval.ship(s.carrier).is_some_and(|c|c.alive())||s.lost==s.total{Some("母舰或飞机已损失".into())}
                else if s.stock==0&&!self.aircraft.iter().any(|a|a.squadron==i&&a.weapons>0&&a.hp>0.){Some("航空武器耗尽".into())}
                else{self.air_plan(&q).err()};
            if let Some(reason)=cancel{self.carrier_ops.as_mut().unwrap().rejected.push(json!({"squadron_id":q["squadron_id"],"reason":reason}));continue}
            if self.carrier_v2_wait(i).is_some()||self.squadrons[i].stock==0{self.carrier_ops.as_mut().unwrap().queue.push(q);continue}
            q["queue"]=json!(false);
            if let Err(reason)=self.air_order(&q){self.carrier_ops.as_mut().unwrap().rejected.push(json!({"squadron_id":q["squadron_id"],"reason":reason}));}
        }
        let n=self.squadrons.len();if n==0{return}
        if self.carrier_is_v3(){self.carrier_v3_advance();}
        let cursor=self.carrier_ops.as_ref().unwrap().cursor;
        // Two passes: defend the formation before allocating attack flights.
        for fighter_pass in [true,false]{for offset in 0..n{
            let i=(cursor+offset)%n;let s=&self.squadrons[i];if (s.role=="fighter")!=fighter_pass{continue}
            let Some(c)=self.naval.ship(s.carrier).filter(|c|c.alive())else{continue};let side=c.side;let origin=c.p;let carrier=c.id;
            if side==0&&self.carrier_is_v3(){continue}
            let ops=self.carrier_ops.as_ref().unwrap();let m=ops.modern.as_ref().unwrap();
            let policy=m.policies.get(&carrier).map(String::as_str).unwrap_or("balanced");
            if side==0&&(!ops.ally_ai||m.manual.contains(&s.id))||policy=="hold"||s.stock==0||s.lost==s.total||self.carrier_v2_wait(i).is_some()||ops.queue.iter().any(|q|q["squadron_id"]==s.id){continue}
            let active=self.aircraft.iter().filter(|a|a.hp>0.&&self.naval.ship(a.carrier).is_some_and(|c|c.side==side)).count();
            let count=s.available.min(3).min(s.stock)as usize;
            if active+count>12{continue}
            let carriers:BTreeSet<_>=self.squadrons.iter().filter(|s|s.lost<s.total&&self.naval.ship(s.carrier).is_some_and(|c|c.side==side&&c.alive())).map(|s|s.carrier).collect();
            let cap=if carriers.len()>1{(12/carriers.len()).max(3)}else{12};
            let mine=self.aircraft.iter().filter(|a|a.carrier==carrier&&a.hp>0.).count();if mine+count>cap{continue}
            let enemy=self.aircraft.iter().filter(|a|a.hp>0.&&a.phase!="launching"&&self.naval.ship(a.carrier).is_some_and(|c|c.side!=side)&&a.p.dist(origin)<=s.range)
                .min_by(|a,b|a.p.dist(origin).total_cmp(&b.p.dist(origin))).map(|a|(a.p,a.id));
            let proposal=if fighter_pass{
                if let Some((p,id))=enemy{
                    let assigned=self.aircraft.iter().filter(|a|a.hp>0.&&a.target_kind=="aircraft"&&a.target_id==id&&self.naval.ship(a.carrier).is_some_and(|c|c.side==side)).count();
                    if assigned>=3{None}else{Some(("strike",p,"aircraft",json!(id),"拦截接近编队的敌机"))}
                }else{
                    let covered=self.aircraft.iter().any(|a|a.hp>0.&&a.role=="fighter"&&a.phase!="returning"&&self.naval.ship(a.carrier).is_some_and(|c|c.side==side)&&a.p.dist(origin)<3500.);
                    if covered||policy=="strike"{None}else{Some(("patrol",origin+P{x:0.,y:-1200.},"land",Value::Null,"为相邻航母提供共享警戒"))}
                }
            }else if policy=="defend"{None}else{
                self.naval.contacts[side].iter().filter(|t|origin.dist(t.p())<=s.range&&self.naval.ship(t.ship).is_some_and(|c|c.side!=side&&c.alive()))
                    .min_by(|a,b|{
                        let score=|t:&crate::model::Contact| self.aircraft.iter().filter(|a|a.hp>0.&&a.phase!="returning"&&a.target_kind=="ship"&&a.target_id==t.id&&self.naval.ship(a.carrier).is_some_and(|c|c.side==side)).count();
                        score(a).cmp(&score(b)).then_with(||origin.dist(a.p()).total_cmp(&origin.dist(b.p())))
                    }).map(|t|("strike",t.p(),"ship",json!(t.id),"分配公开敌舰接触，避免重复堆满同一目标"))
            };
            if let Some((action,p,kind,target,reason))=proposal{
                let id=self.squadrons[i].id.clone();
                if self.launch_air(i,action,p,kind.into(),target).is_ok()&&side==0{self.carrier_ops.as_mut().unwrap().modern.as_mut().unwrap().decisions.push(json!({"tick":self.ground.frame as f64/10.,"carrier":carrier,"squadron_id":id,"reason":reason}));}
            }
        }}
        let ops=self.carrier_ops.as_mut().unwrap();ops.cursor=(cursor+1)%n;
        if ops.rejected.len()>12{ops.rejected.drain(..ops.rejected.len()-12);}
        let d=&mut ops.modern.as_mut().unwrap().decisions;if d.len()>24{d.drain(..d.len()-24);}
    }
    pub(super) fn carrier_v2_view(&self)->Value{
        let ops=self.carrier_ops.as_ref().unwrap();let m=ops.modern.as_ref().unwrap();
        let carriers:BTreeSet<_>=self.squadrons.iter().filter(|s|self.naval.ship(s.carrier).is_some_and(|c|c.side==0)).map(|s|s.carrier).collect();
        let decks:Vec<_>=carriers.iter().map(|&id|{let c=self.naval.ship(id).unwrap();let near=self.aircraft.iter().filter(|a|a.hp>0.&&a.carrier==id&&a.phase=="returning"&&a.p.dist(c.p)<1500.).count();json!({"carrier":id,"name":c.name,"alive":c.alive(),"busy_in":self.deck.get(&id).copied().unwrap_or(0).saturating_sub(self.ground.frame)as f64/10.,"recovering":near,"airborne":self.aircraft.iter().filter(|a|a.hp>0.&&a.carrier==id).count(),"policy":m.policies.get(&id).map(String::as_str).unwrap_or("balanced")})}).collect();
        let queue:Vec<_>=ops.queue.iter().map(|q|{let mut q=q.clone();if let Some(i)=self.squadrons.iter().position(|s|q["squadron_id"]==s.id){q["wait_reason"]=json!(self.carrier_v2_wait(i).unwrap_or("下一调度点出击"));}q}).collect();
        let flights:Vec<_>=self.aircraft.iter().filter(|a|a.hp>0.&&self.naval.ship(a.carrier).is_some_and(|c|c.side==0)).map(|a|json!({"id":a.id,"squadron_id":self.squadrons[a.squadron].id,"mission":a.mission,"target":a.target,"phase":a.phase})).collect();
        let mut v=json!({"version":VERSION,"ally_ai":ops.ally_ai,"queue":queue,"rejected":ops.rejected,"decks":decks,"flights":flights,"manual_squadrons":m.manual,"decisions":m.decisions,"landing_priority":true,"ai_side_aircraft_budget":12,"flight_policy":{"continuous_airspeed":true,"patrol_radius_m":PATROL_RADIUS,"holding_radius_m":HOLDING_RADIUS,"orbit_turn_deg_s":ORBIT_TURN_RATE,"landing_fuel_reserve_m":LANDING_FUEL_RESERVE}});
        if self.carrier_is_v3(){v["version"]=json!(super::carrier_ops_v3::VERSION);v["automation"]=self.carrier_v3_view();}v
    }
}
