//! Explicit three-level aviation control. All sorties use existing finite
//! aircraft, deck, fuel, weapon and damage authority. v1/v2 remain frozen.
use super::*;
pub(super) const VERSION:&str="cas-carrier-ops-v3";
const AREA_RADIUS:f64=650.;
const FRIENDLY_CLEARANCE:f64=350.;
#[derive(Default)]
pub(super) struct Automation{
    pub level:String,
    missions:BTreeMap<u32,Value>,
    stopped:BTreeSet<u32>,
    status:BTreeMap<u32,String>,
    land_observation:Option<Value>,
    withdrawal:bool,
}

#[cfg(test)]
mod tests{
    use super::*;
    fn battle(level:&str)->Battle{
        let c=Config{mode:"raid".into(),lesson:None,company_layout:None,ships:vec![Hull{id:ENTERPRISE.into(),hp:100.,ammo:100},Hull{id:SHOKAKU.into(),hp:100.,ammo:100}],roster:vec!["MCP-034".into(),"MCP-001".into()],unit_condition:vec![],transport_preset:"combat".into(),defense:vec![],company_transports:vec![]};
        let mut w=Battle::new(42,c).unwrap();set(&mut w,level);w
    }
    fn set(w:&mut Battle,level:&str){w.command(&json!({"op":"carrier_automation","version":VERSION,"level":level}),true).unwrap();}
    fn step(w:&mut Battle,n:u32){for _ in 0..n{w.advance();}}
    #[test]fn medium_waits_for_player_objective_low_never_auto_launches_and_modes_replay(){
        let mut w=battle("low");step(&mut w,100);assert!(!w.aircraft.iter().any(|a|w.naval.ship(a.carrier).is_some_and(|c|c.side==0)));
        set(&mut w,"medium");step(&mut w,160);assert!(w.aircraft.iter().filter(|a|w.naval.ship(a.carrier).is_some_and(|c|c.side==0)).all(|a|a.role=="fighter"));
        let before=w.squadrons.iter().map(|s|(s.stock,s.available,s.lost)).collect::<Vec<_>>();
        set(&mut w,"high");assert_eq!(before,w.squadrons.iter().map(|s|(s.stock,s.available,s.lost)).collect::<Vec<_>>());
        assert_eq!(Battle::from_save(w.save(),None).unwrap().view(),w.view());
    }
    #[test]fn player_ground_objective_uses_real_bombers_and_damage_then_returns(){
        let mut w=battle("medium");let p=SelfTest::target(&w);let hp=SelfTest::enemy_hp(&w);
        w.command(&json!({"op":"carrier_mission","carrier":1,"action":"strike","target_kind":"land","x":p.x,"y":p.y}),true).unwrap();
        step(&mut w,200);assert!(w.aircraft.iter().any(|a|a.carrier==1&&a.role=="dive_bomber"));assert!(w.aircraft.iter().all(|a|a.target_kind!="land"||a.mission=="patrol"||a.role!="torpedo_bomber"));
        step(&mut w,600);assert!(SelfTest::enemy_hp(&w)<hp);assert!(w.squadrons.iter().any(|s|s.stock<18));
        assert_eq!(Battle::from_save(w.save(),None).unwrap().view(),w.view());
    }
    struct SelfTest;
    impl SelfTest{
        fn target(w:&Battle)->P{Battle::carrier_v3_pos(&w.carrier_v3_threats()[0])}
        fn enemy_hp(w:&Battle)->f64{w.carrier_v3_threats().iter().map(|e|e["hp"].as_f64().unwrap()).sum()}
    }
    #[test]fn invalid_target_is_atomic_preview_is_read_only_and_recall_holds(){
        let mut w=battle("high");let before=w.save();let q=json!({"op":"carrier_mission","carrier":1,"action":"strike","target_kind":"land","x":0.,"y":0.});assert!(w.command(&q,true).is_err());assert_eq!(serde_json::to_value(before).unwrap(),serde_json::to_value(w.save()).unwrap());
        let p=SelfTest::target(&w);let mut q=json!({"op":"carrier_mission_preview","carrier":1,"action":"strike","target_kind":"land","x":p.x,"y":p.y});let before=w.view();assert_eq!(w.execute(&q).unwrap()["valid"],true);assert_eq!(w.view(),before);
        q["op"]=json!("carrier_mission");w.command(&q,true).unwrap();step(&mut w,180);
        w.command(&json!({"op":"carrier_mission","carrier":1,"action":"return"}),true).unwrap();step(&mut w,900);
        assert!(!w.aircraft.iter().any(|a|a.carrier==1));assert!(w.carrier_v3_state().stopped.contains(&1));
    }
    #[test]fn high_uses_both_decks_and_land_support_without_exceeding_real_budget(){
        let mut w=battle("high");let mut decks=BTreeSet::new();let mut land=false;
        for _ in 0..500{w.advance();for a in &w.aircraft{decks.insert(a.carrier);land|=a.mission=="strike"&&a.target_kind=="land";}
            assert!(w.aircraft.iter().filter(|a|w.naval.ship(a.carrier).is_some_and(|c|c.side==0)).count()<=12);
            for(i,s)in w.squadrons.iter().enumerate(){assert_eq!(s.available+s.lost+w.aircraft.iter().filter(|a|a.squadron==i&&a.hp>0.).count()as u32,s.total);}
        }assert!(decks.contains(&1)&&decks.contains(&2)&&land);
    }
    #[test]fn air_commands_preserve_ground_autonomy_and_withdrawal_never_relaunches(){
        let mut w=battle("high");step(&mut w,160);
        w.command(&json!({"op":"littoral_autonomy","version":autonomy::VERSION,"enabled":true}),true).unwrap();
        let p=SelfTest::target(&w);w.command(&json!({"op":"carrier_mission","carrier":1,"action":"strike","target_kind":"land","x":p.x,"y":p.y}),true).unwrap();
        assert!(w.autonomy.as_ref().unwrap().enabled);
        set(&mut w,"low");let id=w.squadrons[0].id.clone();let c=w.naval.ship(1).unwrap().p;
        w.command(&json!({"op":"littoral_air_order","squadron_id":id,"queue":true,"action":"patrol","x":c.x,"y":c.y-1500.}),true).unwrap();
        assert!(w.autonomy.as_ref().unwrap().enabled);
        w.command(&json!({"op":"littoral_autonomy","version":autonomy::VERSION,"enabled":true,"posture":"withdraw"}),true).unwrap();step(&mut w,600);
        assert!(!w.aircraft.iter().any(|a|w.naval.ship(a.carrier).is_some_and(|c|c.side==0)));
    }
    #[test]fn actual_public_land_bridge_and_friend_clearance_replace_practice_targets(){
        let mut w=battle("medium");let p=P{x:12500.,y:13000.};
        let v=json!({"littoral":{"land":{"entities":[{"side":"axis","hp":100.,"x":p.x,"y":p.y},{"side":"allies","hp":100.,"x":p.x+100.,"y":p.y}],"buildings":[]}}});
        w.carrier_v3_observe_land(v);assert_eq!(w.carrier_v3_threats().len(),1);assert!(!w.carrier_v3_safe_land(p));
        w.command(&json!({"op":"carrier_mission","carrier":1,"action":"strike","target_kind":"land","x":p.x,"y":p.y}),true).unwrap();step(&mut w,180);
        assert!(!w.aircraft.iter().any(|a|a.carrier==1&&a.role!="fighter"));
    }
}
impl Automation{pub(super) fn patrol_goal(&self,carrier:u32)->Option<P>{self.missions.get(&carrier).filter(|q|q["action"]=="patrol").map(|q|P{x:q["x"].as_f64().unwrap_or(0.),y:q["y"].as_f64().unwrap_or(0.)})}}
impl Battle{
    pub(super) fn carrier_is_v3(&self)->bool{self.carrier_ops.as_ref().and_then(|o|o.modern.as_ref()).is_some_and(|m|m.automation.is_some())}
    fn carrier_v3_state(&self)->&Automation{self.carrier_ops.as_ref().unwrap().modern.as_ref().unwrap().automation.as_ref().unwrap()}
    fn carrier_v3_mut(&mut self)->&mut Automation{self.carrier_ops.as_mut().unwrap().modern.as_mut().unwrap().automation.as_mut().unwrap()}
    pub(super) fn carrier_v3_observe_land(&mut self,v:Value){
        if !self.carrier_is_v3(){return}
        let a=self.carrier_v3_mut();a.land_observation=Some(v["littoral"]["land"].clone());
        a.withdrawal=v["littoral"]["autonomy"]["enabled"]==true&&v["littoral"]["autonomy"]["posture"]=="withdraw";
    }
    pub(super) fn carrier_v3_keeps_ground_ai(&self,q:&Value)->bool{self.carrier_is_v3()&&(q["op"].as_str().unwrap_or("").starts_with("carrier_")||q["op"]=="littoral_air_order")}
    pub(super) fn carrier_v3_configure(&mut self,q:&Value)->E<()>{
        if q["version"]!=VERSION{return Err("请选择三档航母指挥版本".into())}
        let level=q["level"].as_str().ok_or("请选择高、中、低自动化")?;
        if !["high","medium","low"].contains(&level){return Err("自动化只支持high/medium/low".into())}
        self.carrier_v2_configure(&json!({"ally_ai":level!="low"}))?;
        let ops=self.carrier_ops.as_mut().unwrap();let m=ops.modern.as_mut().unwrap();
        let a=m.automation.get_or_insert_with(Automation::default);a.level=level.into();a.status.clear();
        if level!="low"{ops.queue.clear();m.manual.clear();m.policies.clear();a.stopped.clear();}
        if level=="high"{a.missions.clear();}
        Ok(())
    }
    fn carrier_v3_carrier(&self,q:&Value)->E<u32>{
        if !self.carrier_is_v3(){return Err("请先选择三档航母指挥".into())}
        let id=crate::world::u(q,"carrier")?;
        if !self.naval.ship(id).is_some_and(|c|c.side==0&&c.alive())||!self.squadrons.iter().any(|s|s.carrier==id){return Err("请选择本方仍存活的航母".into())}Ok(id)
    }
    fn carrier_v3_land(&self)->Vec<Value>{
        let v=self.ground.view();let land=self.carrier_v3_state().land_observation.as_ref().unwrap_or(&v["littoral"]["land"]);
        land["entities"].as_array().into_iter().flatten().chain(land["buildings"].as_array().into_iter().flatten()).cloned().collect()
    }
    pub(super) fn carrier_v3_safe_land(&self,p:P)->bool{
        !self.carrier_v3_land().iter().any(|e|e["side"]=="allies"&&e["hp"].as_f64().unwrap_or(0.)>0.&&Self::carrier_v3_pos(e).dist(p)<FRIENDLY_CLEARANCE)
    }
    fn carrier_v3_pos(v:&Value)->P{P{x:v["x"].as_f64().unwrap_or(0.),y:v["y"].as_f64().unwrap_or(0.)}}
    fn carrier_v3_threats(&self)->Vec<Value>{self.carrier_v3_land().into_iter().filter(|e|e["side"]=="axis"&&e["hp"].as_f64().unwrap_or(0.)>0.&&e["active"]!=false&&e["airborne"]!=true).collect()}
    pub(super) fn carrier_v3_mission_plan(&self,q:&Value)->E<Value>{
        let carrier=self.carrier_v3_carrier(q)?;
        if q["action"]=="return"{return Ok(json!({"carrier":carrier,"action":"return"}))}
        let mut plan=q.clone();plan["op"]=json!("littoral_air_order");plan["queue"]=json!(true);
        let p=self.ground.position_for(q)?;
        if plan["target_kind"]=="land"&&plan["action"]!="patrol"{
            if !inside(&self.ground.polygon,p){return Err("对陆支援请拖到岛上已发现的敌人附近".into())}
            if !self.carrier_v3_threats().iter().any(|e|Self::carrier_v3_pos(e).dist(p)<=AREA_RADIUS){return Err("此区域没有公开存活的地面敌人；请选择实际敌人或防空海域".into())}
        }
        let mut reason="本舰没有兼容该目标的可用机型".to_string();
        for s in self.squadrons.iter().filter(|s|s.carrier==carrier&&s.lost<s.total){
            if s.stock==0&&!self.aircraft.iter().any(|a|a.carrier==carrier&&a.model==s.model&&a.weapons>0&&a.hp>0.){continue}
            plan["squadron_id"]=json!(s.id);
            match self.air_plan(&plan){Ok(_)=>{plan.as_object_mut().unwrap().remove("squadron_id");plan["carrier"]=json!(carrier);return Ok(plan)},Err(e)=>reason=e}
        }Err(reason)
    }
    pub(super) fn carrier_v3_mission(&mut self,q:&Value)->E<()>{
        let plan=self.carrier_v3_mission_plan(q)?;let id=plan["carrier"].as_u64().unwrap()as u32;
        if q["action"]=="return"{
            self.carrier_v2_order(&json!({"scope":"wing","carrier":id,"action":"return"}))?;
            let a=self.carrier_v3_mut();a.missions.remove(&id);a.stopped.insert(id);a.status.insert(id,"已召回；本舰停止新派遣，选择高档或重新指定目标恢复".into());return Ok(())
        }
        if self.carrier_v3_state().level!="medium"{self.carrier_v3_configure(&json!({"version":VERSION,"level":"medium"}))?;}
        let ids:BTreeSet<_>=self.squadrons.iter().filter(|s|s.carrier==id).map(|s|s.id.clone()).collect();
        self.carrier_ops.as_mut().unwrap().modern.as_mut().unwrap().manual.retain(|s|!ids.contains(s));
        // Changing an objective recalls the old strike instead of continuing to
        // bomb the previous request. Fighters keep protecting actual returners.
        for a in self.aircraft.iter_mut().filter(|a|a.carrier==id&&a.hp>0.&&a.mission=="strike"&&a.target_kind!="aircraft"){a.phase="returning";}
        let a=self.carrier_v3_mut();a.stopped.remove(&id);a.status.insert(id,"目标已接收；自动安排出击，原打击波先返舰".into());a.missions.insert(id,plan);Ok(())
    }
    fn carrier_v3_withdrawing(&self)->bool{
        self.carrier_v3_state().withdrawal||self.autonomy.as_ref().is_some_and(|a|{let v=a.view();v["enabled"]==true&&v["phase"]=="withdrawal"})
    }
    pub(super) fn carrier_v3_advance(&mut self){
        if self.carrier_v3_state().level=="low"{return}
        let withdrawal=self.carrier_v3_withdrawing();
        if withdrawal{for a in self.aircraft.iter_mut().filter(|a|self.naval.ship(a.carrier).is_some_and(|c|c.side==0)){a.phase="returning";}}
        let high=self.carrier_v3_state().level=="high";
        let threats=self.carrier_v3_threats();let own_land=self.carrier_v3_land();
        let carriers:BTreeSet<u32>=self.squadrons.iter().filter(|s|self.naval.ship(s.carrier).is_some_and(|c|c.side==0&&c.alive())).map(|s|s.carrier).collect();
        let cap=if carriers.len()>1{(12/carriers.len()).max(6)}else{12};
        let cursor=self.carrier_ops.as_ref().unwrap().cursor;
        let mut decks:Vec<_>=carriers.iter().copied().collect();if !decks.is_empty(){let n=decks.len();decks.rotate_left(cursor%n);}
        for carrier in decks{
            if withdrawal{self.carrier_v3_mut().status.insert(carrier,"总撤收中；等待所有飞机实际返舰".into());continue}
            if self.carrier_v3_state().stopped.contains(&carrier){continue}
            let origin=self.naval.ship(carrier).unwrap().p;
            let mission=self.carrier_v3_state().missions.get(&carrier).cloned();
            let in_air=self.aircraft.iter().any(|a|a.carrier==carrier&&a.hp>0.&&a.phase!="returning"&&a.mission=="strike"&&a.target_kind!="aircraft");
            let mut status=if high{"搜索公开目标；自动防空与对陆支援"}else if mission.is_some(){"等待本舰兼容机型、甲板或目标条件"}else{"拖本舰航空支援卡到敌舰、陆上敌人或防空海域"}.to_string();
            if in_air{status="打击编队在途；实际投弹后返舰整备".into();}
            for pass in [true,false]{for off in 0..self.squadrons.len(){
                let i=(cursor+off)%self.squadrons.len();let s=&self.squadrons[i];
                if s.carrier!=carrier||(s.role=="fighter")!=pass||s.lost==s.total||s.stock==0{continue}
                if let Some(wait)=self.carrier_v2_wait(i){if !pass&&!in_air{status=wait.into();}continue}
                let count=s.available.min(3).min(s.stock)as usize;
                if self.aircraft.iter().filter(|a|a.hp>0.&&self.naval.ship(a.carrier).is_some_and(|c|c.side==0)).count()+count>12||self.aircraft.iter().filter(|a|a.hp>0.&&a.carrier==carrier).count()+count>cap{continue}
                let mut plan=None;
                if pass{
                    let air=self.aircraft.iter().filter(|e|e.hp>0.&&e.phase!="launching"&&self.naval.ship(e.carrier).is_some_and(|c|c.side==1)&&e.p.dist(origin)<=s.range&&(!mission.as_ref().is_some_and(|q|q["target_kind"]=="aircraft")||mission.as_ref().is_some_and(|q|q["target_id"]==e.id))).find(|e|self.aircraft.iter().filter(|a|a.hp>0.&&a.target_kind=="aircraft"&&a.target_id==e.id).count()<2);
                    if let Some(e)=air{plan=Some(("strike",e.p,"aircraft",json!(e.id),"拦截公开接近敌机"));}
                    else{
                        let goal=mission.as_ref().filter(|q|q["action"]=="patrol").map(|q|Self::carrier_v3_pos(q)).unwrap_or(origin+P{x:0.,y:-1200.});
                        let covered=self.aircraft.iter().any(|a|a.hp>0.&&a.role=="fighter"&&a.phase!="returning"&&self.naval.ship(a.carrier).is_some_and(|c|c.side==0)&&a.target.dist(goal)<2500.);
                        if !covered{plan=Some(("patrol",goal,"land",Value::Null,"自动安排共享盘旋防空"));}
                    }
                }else if !in_air{
                    let requested=mission.as_ref();
                    let land=requested.is_some_and(|q|q["target_kind"]=="land"&&q["action"]!="patrol");
                    if (high||land)&&s.role!="torpedo_bomber"{
                        let candidate=threats.iter().filter(|e|{
                            let p=Self::carrier_v3_pos(e);origin.dist(p)<=s.range&&!own_land.iter().any(|o|o["side"]=="allies"&&o["hp"].as_f64().unwrap_or(0.)>0.&&Self::carrier_v3_pos(o).dist(p)<FRIENDLY_CLEARANCE)&&(!land||requested.is_some_and(|q|Self::carrier_v3_pos(q).dist(p)<=AREA_RADIUS))
                                &&!self.aircraft.iter().any(|a|a.hp>0.&&a.mission=="strike"&&a.phase!="returning"&&a.target_kind=="land"&&a.target.dist(p)<500.)
                        }).min_by(|a,b|{
                            let score=|e:&Value|{let p=Self::carrier_v3_pos(e);let near=own_land.iter().any(|o|o["side"]=="allies"&&o["hp"].as_f64().unwrap_or(0.)>0.&&Self::carrier_v3_pos(o).dist(p)<1800.);let marked=self.carrier_v3_state().land_observation.as_ref().is_some_and(|l|l["effects"].as_array().is_some_and(|es|es.iter().any(|e|e["kind"]=="support_designation"&&e["side"]=="allies"&&e["remaining_s"].as_f64().unwrap_or(0.)>0.&&Self::carrier_v3_pos(e).dist(p)<=e["radius_m"].as_f64().unwrap_or(650.))));(if marked{0}else if near{1}else{2},(origin.dist(p)*10.)as u64)};
                            score(a).cmp(&score(b))
                        });
                        if let Some(e)=candidate{plan=Some(("strike",Self::carrier_v3_pos(e),"land",Value::Null,"为陆上公开敌人安排航空支援"));}
                        else if land{status=if threats.iter().any(|e|requested.is_some_and(|q|Self::carrier_v3_pos(q).dist(Self::carrier_v3_pos(e))<=AREA_RADIUS)){"等待：友军过近、已有支援在途或超出航程"}else{"该区域已清除；拖卡指定新目标"}.into();}
                    }
                    if plan.is_none()&&(high||requested.is_some_and(|q|q["target_kind"]=="ship")){
                        let target=self.naval.contacts[0].iter().filter(|t|origin.dist(t.p())<=s.range&&self.naval.ship(t.ship).is_some_and(|c|c.side==1&&c.alive())&&(high||requested.is_some_and(|q|q["target_id"]==t.id)))
                            .min_by_key(|t|self.aircraft.iter().filter(|a|a.hp>0.&&a.phase!="returning"&&a.target_kind=="ship"&&a.target_id==t.id).count());
                        if let Some(t)=target{plan=Some(("strike",t.p(),"ship",json!(t.id),"按指定或公开海上目标安排打击"));}
                        else if !high{status="目标已失效或超程；拖卡指定新目标".into();}
                    }
                }
                if let Some((action,p,kind,target,why))=plan{
                    if self.launch_air(i,action,p,kind.into(),target).is_ok(){
                        let id=self.squadrons[i].id.clone();self.carrier_ops.as_mut().unwrap().modern.as_mut().unwrap().decisions.push(json!({"tick":self.ground.frame as f64/10.,"carrier":carrier,"squadron_id":id,"reason":why}));status=why.into();
                    }
                }
            }}
            if let Some(wait)=self.squadrons.iter().position(|s|s.carrier==carrier).and_then(|i|self.carrier_v2_wait(i)){if status.starts_with("搜索"){status=wait.into();}}
            self.carrier_v3_mut().status.insert(carrier,status);
        }
    }
    fn carrier_v3_status(&self,id:u32)->String{
        let a=self.carrier_v3_state();
        if !self.naval.ship(id).is_some_and(|c|c.alive()){return "母舰已损失；无法安排新出击".into()}
        if a.level!="low"&&!a.stopped.contains(&id){if let Some(q)=a.missions.get(&id){
            let land=q["target_kind"]=="land"&&q["action"]!="patrol";
            let compatible=|s:&&Squadron|s.carrier==id&&if q["action"]=="patrol"||q["target_kind"]=="aircraft"{s.role=="fighter"}else if land{s.role!="fighter"&&s.role!="torpedo_bomber"}else{s.role!="fighter"};
            let squads:Vec<_>=self.squadrons.iter().filter(compatible).collect();
            if squads.iter().all(|s|s.lost==s.total){return if land{"本舰对陆攻击机已全部损失；请选择其他航母"}else{"本舰兼容飞机已全部损失；请选择其他航母"}.into()}
            if squads.iter().all(|s|s.stock==0)&&!self.aircraft.iter().any(|p|p.carrier==id&&p.hp>0.&&p.weapons>0&&squads.iter().any(|s|s.model==p.model)){return "本舰该任务航空武器已耗尽；请选择其他航母".into()}
        }}
        a.status.get(&id).cloned().unwrap_or_else(||if a.level=="low"{"手动调度；不自动派遣"}else if a.level=="high"{"自动安排中；继续模拟"}else if a.missions.contains_key(&id){"目标已保留；下一调度点安排出击"}else{"拖卡指定目标"}.into())
    }
    pub(super) fn carrier_v3_view(&self)->Value{
        let a=self.carrier_v3_state();let low=a.level=="low";
        let next=match a.level.as_str(){"high"=>"继续模拟即可；需要指定目标时选中档，需要编队细调时选低档","medium"=>"拖航空支援卡到敌舰、陆上敌人或海面；拖回本舰召回",_=>"拖中队卡排下一波；拖在空卡改当前任务；拖联队卡回母舰召回"};
        json!({"level":a.level,"player_responsibility":if low{"具体编队调度"}else if a.level=="medium"{"只指定各舰目标"}else{"选择自动化档位；航母自动安排"},"next_action":next,"land_support":"海图与陆图使用同一航空支援卡、世界坐标与实际飞机；对陆自动选兼容机型，近友军暂缓投弹","area_radius_m":AREA_RADIUS,"friendly_clearance_m":FRIENDLY_CLEARANCE,"missions":a.missions.values().collect::<Vec<_>>(),"stopped_carriers":a.stopped,"carriers":self.squadrons.iter().map(|s|s.carrier).collect::<BTreeSet<_>>().iter().filter(|&&id|self.naval.ship(id).is_some_and(|c|c.side==0)).map(|id|json!({"carrier":id,"status":self.carrier_v3_status(*id)})).collect::<Vec<_>>(),"commands":{"mode":{"op":"carrier_automation","version":VERSION,"level":"high|medium|low"},"target":{"op":"carrier_mission","carrier":"own carrier id","action":"strike|patrol|return","target_kind":"ship|land|aircraft","target_id":"public contact id if applicable","x":"world metres","y":"world metres"}},"automation_owner":"carrier desk; combined autonomy retains ground/naval orders and withdrawal"})
    }
}
