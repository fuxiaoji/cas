//! Observation-only commander for the explicitly opted-in fictional v4 mode.
//! All proposals go through the existing human command validator. No terrain,
//! casualty, ammunition, aircraft or outcome authority is implemented here.
use super::{json,Value,P};
use std::collections::{BTreeMap,BTreeSet};

pub(super) const VERSION:&str="combined-autonomy-v1";
#[derive(Clone)]
pub(super) struct Proposal{pub order:Value,pub reason:String,key:String,cooldown:u32}
#[derive(Default)]
pub(super) struct Commander{
    pub enabled:bool,
    withdrawing:bool,
    status:String,
    last:BTreeMap<String,(Value,u32)>,
    decisions:Vec<Value>,
    assignments:BTreeMap<String,u64>,
    started:u32,
}

#[cfg(test)]
mod tests{
    use super::*;
    use super::super::{Battle,Config,Hull,ENTERPRISE,APV,MULTI};
    fn battle(mode:&str,multi:bool)->Battle{
        Battle::new(42,Config{mode:mode.into(),ships:vec![Hull{id:"IBS-U-USN-ERMA-IOWA".into(),hp:100.,ammo:100},Hull{id:ENTERPRISE.into(),hp:100.,ammo:100},Hull{id:APV.into(),hp:100.,ammo:100}],roster:vec!["MCP-034".into(),"MCP-001".into(),"MCP-009".into()],unit_condition:vec![],transport_preset:"combat".into(),defense:vec![],company_transports:vec![],lesson:(mode=="tutorial").then(||"landing".into()),company_layout:multi.then(||MULTI.into())}).unwrap()
    }
    fn enable(w:&mut Battle){w.command(&json!({"op":"littoral_autonomy","version":VERSION,"enabled":true}),true).unwrap();}
    fn advance(w:&mut Battle,count:u32){for _ in 0..count{w.advance();if w.ground.result.is_some(){break}}}
    #[test]fn explicit_opt_in_does_not_add_fields_to_legacy_v4(){
        let mut w=battle("tutorial",false);assert!(w.view()["littoral"].get("autonomy").is_none());let before=w.view();
        assert!(w.command(&json!({"op":"littoral_autonomy","version":"invented","enabled":true}),true).is_err());
        assert_eq!(w.view(),before);advance(&mut w,50);assert!(w.save().commands.is_empty());assert!(w.view()["littoral"].get("autonomy").is_none());
        assert_eq!(Battle::from_save(w.save(),None).unwrap().view(),w.view());
    }
    #[test]fn successful_manual_order_takes_over_but_failed_order_does_not(){
        let mut w=battle("tutorial",true);enable(&mut w);advance(&mut w,21);
        assert!(w.command(&json!({"op":"littoral_order","company_id":"not-owned","action":"retreat"}),true).is_err());assert!(w.autonomy.as_ref().unwrap().enabled);
        w.command(&json!({"op":"littoral_ship_order","ship":1,"action":"hold"}),true).unwrap();assert!(!w.autonomy.as_ref().unwrap().enabled);
        let before=w.autonomy.as_ref().unwrap().decisions.len();advance(&mut w,40);assert_eq!(w.autonomy.as_ref().unwrap().decisions.len(),before);
        assert_eq!(Battle::from_save(w.save(),None).unwrap().view(),w.view());
    }
    #[test]fn multi_company_commander_searches_several_sites_and_recovers_real_survivors(){
        let mut w=battle("tutorial",true);enable(&mut w);advance(&mut w,9000);
        let searched=w.ground.ruins.iter().filter(|r|r.searched).count();
        eprintln!("autonomy result frame={} searched={} success={}",w.ground.frame,searched,w.ground.result.as_ref().map_or(false,|r|r["success"]==true));
        assert!(searched>=2,"must not stall after the first public ruin");
        assert!(w.ground.landed_companies.len()>=5,"multiple companies must actually land");
        assert!(w.ground.result.as_ref().is_some_and(|r|r["success"]==true));
        assert!(w.ground.groups.iter().all(|g|matches!(g.stage,"recovered"|"embarked"|"lost")));
        assert!(w.ground.events.iter().any(|e|e["kind"]=="support_fired"));
        assert!(w.ground.events.iter().any(|e|e["kind"]=="air_launch"));
        assert_eq!(Battle::from_save(w.save(),None).unwrap().view(),w.view(),"the terminal frame itself must replay without a future step");
    }
    #[test]fn automation_rebuilds_decisions_and_flights_from_saved_toggle(){
        let mut w=battle("tutorial",true);enable(&mut w);advance(&mut w,600);
        let mut restored=Battle::from_save(w.save(),None).unwrap();assert_eq!(restored.view(),w.view());
        assert!(w.save().commands.iter().all(|c|c.request["op"]=="littoral_autonomy"));
        advance(&mut w,200);advance(&mut restored,200);assert_eq!(restored.view(),w.view());
    }
    #[test]fn low_ammo_and_damaged_company_withdraw_without_fabricated_repair(){
        let mut w=battle("tutorial",false);enable(&mut w);advance(&mut w,300);
        for b in w.ground.bodies.iter_mut().filter(|b|b.ally){b.ammo=0;b.hp*=0.2;}
        let hp=w.ground.bodies.iter().filter(|b|b.ally).map(|b|b.hp).sum::<f64>();
        advance(&mut w,21);assert!(w.autonomy.as_ref().unwrap().withdrawing);
        assert!(w.ground.groups.iter().filter(|g|g.stage=="ground").all(|g|g.order=="retreat"));
        assert!(w.ground.bodies.iter().filter(|b|b.ally).map(|b|b.hp).sum::<f64>()<=hp);
    }
    #[test]fn destroyed_carrier_and_incompatible_recovery_stay_real(){
        let mut w=battle("tutorial",true);enable(&mut w);advance(&mut w,300);
        let carrier=w.ground.groups.iter().find(|g|g.card.id.starts_with("MCP-001")).unwrap().carrier;
        w.naval.ship_mut(carrier).unwrap().hp=0.;w.command(&json!({"op":"littoral_autonomy","version":VERSION,"enabled":true,"posture":"withdraw"}),true).unwrap();
        advance(&mut w,3000);
        assert!(w.naval.ship(carrier).unwrap().hp<=0.);
        assert!(w.ground.groups.iter().filter(|g|g.card.id.starts_with("MCP-001")&&g.stage!="lost").all(|g|g.stage!="recovered"));
        assert!(w.autonomy.as_ref().unwrap().status.contains("撤收受阻")||w.ground.result.is_some());
        assert!(w.ground.result.as_ref().is_none_or(|r|r["success"]!=true));
    }
    #[test]fn early_withdrawal_recovers_and_finishes_as_loss_at_actual_exit(){
        let mut w=battle("salvage",true);w.command(&json!({"op":"littoral_autonomy","version":VERSION,"enabled":true,"posture":"withdraw"}),true).unwrap();advance(&mut w,1000);
        let r=w.ground.result.as_ref().expect("embarked survivors can reach exit");assert_eq!(r["success"],false);assert_eq!(r["abandoned"],true);
        assert!(w.ground.ships.iter().filter(|s|s.ally&&s.hp>0.).all(|s|s.p.dist(w.ground.exit_point())<=1600.));
    }
    #[test]fn carrier_only_sea_control_uses_actual_flights_and_spends_finite_weapons(){
        let mut c=battle("tutorial",false).ground.config;c.roster=vec!["MCP-001".into(),"MCP-034".into()];c.lesson=Some("sea_control".into());
        c.ships=vec![Hull{id:ENTERPRISE.into(),hp:100.,ammo:0}];let mut w=Battle::new(44,c).unwrap();enable(&mut w);advance(&mut w,6000);
        eprintln!("carrier-only frame={} success={} stock={:?} status={}",w.ground.frame,w.ground.result.as_ref().map_or(false,|r|r["success"]==true),w.squadrons.iter().map(|s|(s.model,s.stock,s.available,s.lost)).collect::<Vec<_>>(),w.autonomy.as_ref().unwrap().status);
        assert!(w.squadrons.iter().any(|s|s.stock<18));assert!(w.ground.events.iter().any(|e|e["kind"]=="air_attack"));
        assert!(w.ground.landed_companies.is_empty(),"sea-control lesson must not disembark troops");
        assert!(w.ground.result.as_ref().is_some_and(|r|r["success"]==true));
        assert!(w.aircraft.is_empty(),"airborne aircraft must physically recover before success");
    }
    #[test]fn mission_types_do_not_stall_on_search_orders_after_completion(){
        for mode in ["raid","defense","salvage"]{
            let mut w=battle(mode,true);enable(&mut w);advance(&mut w,9000);
            eprintln!("mode={mode} frame={} success={} status={}",w.ground.frame,w.ground.result.as_ref().map_or(false,|r|r["success"]==true),w.autonomy.as_ref().unwrap().status);
            let result=w.ground.result.as_ref().expect("mission must reach success or a real safety withdrawal");
            assert_eq!(result["success"],result["objective_complete"],"{mode} must never invent success");
            if mode=="defense"{assert_eq!(result["success"],true);}
        }
    }
}
fn rows(v:&Value)->&[Value]{v.as_array().map_or(&[],Vec::as_slice)}
fn n(v:&Value)->f64{v.as_f64().unwrap_or(0.)}
fn pos(v:&Value)->P{P{x:n(&v["x"]),y:n(&v["y"])}}
fn id(v:&Value)->String{v.as_str().map(str::to_owned).unwrap_or_else(||v.to_string())}
fn alive(v:&Value)->bool{n(&v["hp"])>0.}
fn group_key(g:&Value)->String{g["company_id"].as_str().or_else(||g["id"].as_str()).unwrap_or("").into()}
fn body_group(b:&Value)->String{b["company_id"].as_str().or_else(||b["unit_id"].as_str()).unwrap_or("").into()}
impl Commander{
    pub fn configure(&mut self,enabled:bool,posture:&str,frame:u32){
        self.enabled=enabled;self.withdrawing=posture=="withdraw";self.started=frame;
        self.status=if !enabled{"已接管"}else if self.withdrawing{"撤收部队与航空中队"}else{"评估舰队、连队与当前任务"}.into();
        self.last.clear();self.assignments.clear();
        self.decisions.push(json!({"frame":frame,"kind":"control","enabled":enabled,"posture":posture}));self.trim();
    }
    pub fn manual_takeover(&mut self,frame:u32){if self.enabled{self.enabled=false;self.status="已接管 · 原指令继续执行，可随时重新托管".into();self.decisions.push(json!({"frame":frame,"kind":"manual_takeover"}));self.trim();}}
    pub fn view(&self)->Value{json!({"version":VERSION,"enabled":self.enabled,"phase":if self.withdrawing{"withdrawal"}else{"mission"},"status":self.status,"assignments":self.assignments,"decisions":self.decisions,"authority":"own_observation_and_validated_commands","decision_interval_seconds":2})}
    fn trim(&mut self){if self.decisions.len()>48{self.decisions.drain(..self.decisions.len()-48);}}
    fn offer(&self,out:&mut Vec<Proposal>,frame:u32,key:String,mut order:Value,reason:&str,cooldown:u32){
        // Single-company v4 still addresses unit_id; the multi-company wrapper
        // accepts the exact company identity in both fields. Never issue an
        // order that works only after a player has enabled company expansion.
        if order.get("company_id").is_some()&&order.get("unit_id").is_none(){order["unit_id"]=order["company_id"].clone();}
        if self.last.get(&key).is_some_and(|(previous,until)|previous==&order&&frame<*until){return}
        out.push(Proposal{order,reason:reason.into(),key,cooldown});
    }
    pub fn feedback(&mut self,frame:u32,proposal:Proposal,result:Result<(),String>){
        let accepted=result.is_ok();let error=result.err();
        // Invalid routes/targets have a short bounded retry and remain visible;
        // they never get treated as a completed search, hit or evacuation.
        let until=frame.saturating_add(if accepted{proposal.cooldown}else{60});
        self.last.insert(proposal.key,(proposal.order.clone(),until));
        self.decisions.push(json!({"frame":frame,"order":proposal.order,"reason":proposal.reason,"accepted":accepted,"error":error}));self.trim();
    }
    pub fn plan(&mut self,v:&Value)->Vec<Proposal>{
        let l=&v["littoral"];let frame=l["frame"].as_u64().unwrap_or(0)as u32;
        let ships=rows(&v["ships"]);let groups=rows(&l["groups"]);let bodies=rows(&l["land"]["entities"]);
        let enemies:Vec<_>=bodies.iter().filter(|b|b["side"]=="axis"&&alive(b)).chain(rows(&l["land"]["buildings"]).iter().filter(|b|b["side"]=="axis"&&alive(b))).collect();
        let ruins:Vec<_>=rows(&l["land"]["ruins"]).iter().filter(|r|r["searched"]!=true).collect();
        let complete=rows(&l["objectives"]).iter().all(|o|o["complete"]==true);
        let defense=l["mode"]=="defense";let sea_control=l["training"]["lesson"]=="sea_control";
        let live:Vec<_>=ships.iter().filter(|s|alive(s)).collect();let mut out=vec![];
        if live.is_empty(){self.status="载舰全部损失，按真实损失结束行动".into();self.offer(&mut out,frame,"finish".into(),json!({"op":"littoral_abandon"}),"没有存活载舰；不补造运输与战果",20);return out}
        let fleet_health=live.iter().map(|s|n(&s["hp"])).sum::<f64>()/live.iter().map(|s|n(&s["maxHp"])).sum::<f64>().max(1.);
        let ground_alive=groups.iter().any(|g|n(&g["hp_percent"])>0.&&g["stage"]!="lost");
        let land_armed=bodies.iter().filter(|b|b["side"]=="allies"&&n(&b["ammo"])>0.).count();
        let any_landed=groups.iter().any(|g|g["stage"]=="ground");
        let reserve=groups.iter().any(|g|n(&g["ability"]["reserve_ammo"])>0.&&n(&g["ability"]["charges"])>0.);
        // Objectives are optional only in the safety withdrawal. A failed
        // mission is settled as a loss after physically recovering survivors.
        let landing_force_spent=groups.iter().any(|g|g["stage"]=="recovered")&&groups.iter().all(|g|matches!(g["stage"].as_str(),Some("recovered"|"lost")));
        if fleet_health<0.25||!ground_alive||landing_force_spent||any_landed&&land_armed==0&&!reserve||frame.saturating_sub(self.started)>13500{
            self.withdrawing=true;
        }
        let optional_search_done=ruins.is_empty()||sea_control||defense||l["mode"]=="raid";
        if complete&&optional_search_done{self.withdrawing=true;}
        if defense&&complete{self.status="守备目标已真实完成".into();self.offer(&mut out,frame,"finish".into(),json!({"op":"littoral_extract"}),"守备计时与存活指挥部均已达标",20);return out}
        let beach=rows(&l["beaches"]).iter().find(|b|b["id"]==2).or_else(||rows(&l["beaches"]).first());
        let Some(beach)=beach else{self.status="缺少公开接驳点，等待接管".into();return out};
        let shore=pos(&beach["sea"]);let land=pos(&beach["land"]);
        if self.withdrawing{return self.withdraw(v,frame,&live,groups,shore,out)}
        self.status=if defense{"守备连坚守指挥部，海空支援拦截进攻"}else if sea_control{"建立制海权，载舰保持安全距离"}else if !any_landed{"载舰接近滩头，分别投送先遣连"}else if !ruins.is_empty(){"分配遗迹搜索，火力组掩护与支援"}else{"各连协同完成主要目标"}.into();
        // Enable the original naval combat controller without granting movement
        // authority: approach/landing/withdrawal routes remain with this planner.
        for s in &live{
            if let Some(fleet)=s["fleet"].as_u64(){self.offer(&mut out,frame,format!("naval-ai-{fleet}"),json!({"op":"ai","fleet":fleet,"profile":"coord","mode":"auto","move":false,"gun":true,"torpedo":true}),"原海战AI负责真实接敌与炮雷裁决；不覆盖接驳航线",u32::MAX/2);}
        }
        let naval_targets=rows(&v["contacts"]);
        if sea_control{
            if let Some(target)=naval_targets.first(){for s in &live{
                if matches!(s["kind"].as_str(),Some("cv"|"lha")){continue}
                let from=pos(s);let toward=pos(target);let distance=from.dist(toward);
                if distance>3200.{let goal=toward+(from-toward)*(2800./distance);self.offer(&mut out,frame,format!("ship-route-{}",s["id"]),json!({"op":"littoral_ship_order","ship":s["id"],"action":"move","x":goal.x,"y":goal.y,"speed":25}),"向公开敌舰接近到炮战距离",300);}
            }}
        }else{
            for g in groups{
                let key=group_key(g);if n(&g["hp_percent"])<=0.{continue}
                if g["stage"]=="embarked"&&g["pending_deploy"].is_null(){
                    let carrier=ships.iter().find(|s|s["id"]==g["carrier"]&&alive(s));
                    if carrier.is_some_and(|s|n(&s["hp"])/n(&s["maxHp"]).max(1.)>=0.3){
                        self.offer(&mut out,frame,format!("deploy-{key}"),json!({"op":"littoral_deploy","company_id":key,"unit_id":g["unit_id"].as_str().unwrap_or(&key),"beach":beach["id"],"insertion":if g["transport_kind"]=="helicopter"{"air"}else{"landing"},"queue":true}),"核验本连载舰、类别、身体舱位与近岸距离后投送",300);
                    }
                }
            }
            self.assignments.retain(|group,target|groups.iter().any(|g|group_key(g)==*group&&g["stage"]=="ground"&&n(&g["hp_percent"])>30.)&&ruins.iter().any(|r|r["id"].as_u64()==Some(*target)));
            let mut claimed:BTreeSet<u64>=self.assignments.values().copied().collect();
            for g in groups.iter().filter(|g|g["stage"]=="ground"&&n(&g["hp_percent"])>0.){
                let key=group_key(g);let p=pos(&g["position"]);let ours:Vec<_>=bodies.iter().filter(|b|b["side"]=="allies"&&body_group(b)==key).collect();
                let ammo=ours.iter().map(|b|n(&b["ammo"])).sum::<f64>();
                let wounded=n(&g["hp_percent"])<32.;
                if !defense&&(wounded||!ours.is_empty()&&ammo==0.&&!reserve){
                    self.assignments.remove(&key);self.offer(&mut out,frame,format!("group-{key}"),json!({"op":"littoral_order","company_id":key,"action":"retreat"}),"本连伤重或缺弹，独立撤收而非继续冲锋",300);continue
                }
                if g["ability"]["available"]==true{
                    let ability=g["ability"]["id"].as_str().unwrap_or("");
                    let repair_needed=ability=="field_repair"&&rows(&l["land"]["buildings"]).iter().any(|b|b["side"]=="allies"&&alive(b)&&n(&b["hp"])<n(&b["max_hp"])*0.85&&p.dist(pos(b))<=n(&g["ability"]["radius"]));
                    if matches!(ability,"resupply"|"triage"|"rescue"|"field_repair")&&(ammo<(ours.len()*18)as f64||n(&g["hp_percent"])<75.||repair_needed){
                        self.offer(&mut out,frame,format!("ability-{key}"),json!({"op":"littoral_ability","company_id":key}),"消耗本连真实储备进行补弹或急救",100);
                    }
                }
                if defense{
                    let primary=rows(&l["objectives"]).first().map(pos).unwrap_or(land);
                    self.offer(&mut out,frame,format!("group-{key}"),json!({"op":"littoral_order","company_id":key,"action":"defend","x":primary.x,"y":primary.y}),"守备连坚守真实指挥部，不因追击外围目标放空防线",300);continue
                }
                // Contact positions and health are public in this fictional
                // mode. A dead target immediately releases its attack order.
                let near=enemies.iter().filter(|e|p.dist(pos(e))<1550.).min_by(|a,b|p.dist(pos(a)).total_cmp(&p.dist(pos(b))));
                if let Some(e)=near{
                    let target=pos(e);self.offer(&mut out,frame,format!("group-{key}"),json!({"op":"littoral_order","company_id":key,"action":"attack","x":target.x,"y":target.y}),"先压制本连附近公开威胁，实际命中后再继续任务",200);continue
                }
                let target_id=self.assignments.get(&key).copied().or_else(||{
                    ruins.iter().filter(|r|!claimed.contains(&r["id"].as_u64().unwrap())).min_by(|a,b|p.dist(pos(a)).total_cmp(&p.dist(pos(b)))).and_then(|r|r["id"].as_u64())
                });
                if !defense&&l["mode"]!="raid"{if let Some(target)=target_id{
                    claimed.insert(target);self.assignments.insert(key.clone(),target);
                    if g["order"]!="search"||g["target"].as_u64()!=Some(target){self.offer(&mut out,frame,format!("group-{key}"),json!({"op":"littoral_order","company_id":key,"action":"search","target":target}),"每个遗迹由不同连队认领；搜索真实完成后自动转下一个",300);}continue
                }}
                let primary=rows(&l["objectives"]).first().map(pos).unwrap_or(land);
                let target=if let Some(e)=enemies.iter().min_by(|a,b|primary.dist(pos(a)).total_cmp(&primary.dist(pos(b)))){pos(e)}else{primary};
                let action=if defense{"defend"}else{"attack"};
                self.offer(&mut out,frame,format!("group-{key}"),json!({"op":"littoral_order","company_id":key,"action":action,"x":target.x,"y":target.y}),"空闲火力组向主要目标推进，掩护搜索与占领",300);
            }
        }
        self.support(v,frame,&enemies,naval_targets,&mut out);
        out
    }
    fn support(&self,v:&Value,frame:u32,enemies:&[&Value],naval_targets:&[Value],out:&mut Vec<Proposal>){
        let l=&v["littoral"];let ships=rows(&v["ships"]);
        // One queued salvo per ship, only while loaded and no friendly body is
        // in its conservative blast radius. Existing mounts validate real arcs.
        for gun in rows(&l["support"]["naval"]){
            if gun["alive"]!=true||n(&gun["ammo"])<=8.||!gun["pending_target"].is_null(){continue}
            let Some(s)=ships.iter().find(|s|s["id"]==gun["ship"])else{continue};
            if let Some(e)=enemies.iter().filter(|e|pos(s).dist(pos(e))<n(&gun["range"])).filter(|e|!rows(&l["land"]["entities"]).iter().any(|b|b["side"]=="allies"&&pos(b).dist(pos(e))<450.)).min_by(|a,b|pos(s).dist(pos(a)).total_cmp(&pos(s).dist(pos(b)))){
                let p=pos(e);self.offer(out,frame,format!("shore-{}",gun["ship"]),json!({"op":"littoral_support","kind":"naval","ship":gun["ship"],"x":p.x,"y":p.y,"queue":true}),"有限舰炮压制公开陆上威胁，避开友军与已排队炮座",100);
            }
        }
        let mut used_decks=BTreeSet::new();
        for squad in rows(&l["aviation"]["squadrons"]){
            if !squad["reason"].is_null()||n(&squad["ammunition"])==0.||n(&squad["airborne"])>0.{continue}
            if used_decks.contains(&id(&squad["carrier"])){continue}
            let Some(carrier)=ships.iter().find(|s|s["id"]==squad["carrier"]&&alive(s))else{continue};
            let range=n(&squad["max_range"]);let from=pos(carrier);let role=squad["role"].as_str().unwrap_or("");
            let air=rows(&l["aviation"]["aircraft"]).iter().find(|a|a["side"]=="axis"&&from.dist(pos(a))<=range&&n(&a["x"])>=0.&&n(&a["y"])>=0.&&n(&a["x"])<=n(&v["width"])&&n(&a["y"])<=n(&v["height"]));
            let close_support=enemies.iter().filter(|e|from.dist(pos(e))<=range).find(|e|rows(&l["land"]["entities"]).iter().chain(rows(&l["land"]["buildings"]).iter()).any(|ours|ours["side"]=="allies"&&alive(ours)&&pos(ours).dist(pos(e))<1800.));
            let target=if role=="fighter"&&air.is_some(){let a=air.unwrap();Some(("aircraft",a["id"].clone(),pos(a)))}else if matches!(role,"dive_bomber"|"helicopter")&&close_support.is_some(){Some(("land",Value::Null,pos(close_support.unwrap())))}else if let Some(t)=naval_targets.iter().find(|t|from.dist(pos(t))<=range){Some(("ship",t["id"].clone(),pos(t)))}else if role!="torpedo_bomber"{enemies.iter().find(|e|from.dist(pos(e))<=range).map(|e|("land",Value::Null,pos(e)))}else{None};
            if let Some((kind,target_id,p))=target{used_decks.insert(id(&squad["carrier"]));self.offer(out,frame,format!("air-{}",id(&squad["id"])),json!({"op":"littoral_air_order","squadron_id":squad["id"],"action":"strike","target_kind":kind,"target_id":target_id,"x":p.x,"y":p.y}),"按公开接触派出有限中队，真实飞行、返舰、整备后才能再次出击",100);}
        }
    }
    fn withdraw(&mut self,v:&Value,frame:u32,live:&[&Value],groups:&[Value],shore:P,mut out:Vec<Proposal>)->Vec<Proposal>{
        let l=&v["littoral"];self.status="先撤收连队和飞机，再驶入返航区".into();
        for g in groups.iter().filter(|g|g["stage"]=="ground"&&n(&g["hp_percent"])>0.){
            let key=group_key(g);self.offer(&mut out,frame,format!("group-{key}"),json!({"op":"littoral_order","company_id":key,"action":"retreat"}),"存活连队沿真实路径返回滩头，保留伤亡与弹药",300);
        }
        for squad in rows(&l["aviation"]["squadrons"]).iter().filter(|s|n(&s["airborne"])>0.){
            let still_out=rows(&l["aviation"]["aircraft"]).iter().any(|a|a["squadron_id"]==squad["id"]&&a["phase"]!="returning");
            if still_out{self.offer(&mut out,frame,format!("recall-{}",id(&squad["id"])),json!({"op":"littoral_air_order","squadron_id":squad["id"],"action":"return"}),"召回实际在空飞机，不能从结算中静默删除",100);}
        }
        let troops_waiting=groups.iter().any(|g|n(&g["hp_percent"])>0.&&!matches!(g["stage"].as_str(),Some("embarked"|"recovered"|"lost")));
        let planes_waiting=rows(&l["aviation"]["aircraft"]).iter().any(|a|a["side"]=="allies"&&live.iter().any(|s|s["id"]==a["carrier"]));
        // Every surviving ship stays near the common beach until recovery. The
        // authoritative allocator chooses only compatible carriers with slots.
        let exit=pos(&l["exit"]);let radius=n(&l["exit"]["radius"]);
        for s in live{
            let target=if troops_waiting{shore}else{exit};
            let distance=pos(s).dist(target);
            if distance>if troops_waiting{650.}else{radius*0.7}{self.offer(&mut out,frame,format!("ship-route-{}",s["id"]),json!({"op":"littoral_ship_order","ship":s["id"],"action":"move","x":target.x,"y":target.y,"speed":25}),if troops_waiting{"载舰驶近实际滩头等待接驳，不能先行甩下部队"}else{"存活舰艇驶入真实返航圈"},300);}
            else if troops_waiting{self.offer(&mut out,frame,format!("ship-hold-{}",s["id"]),json!({"op":"littoral_ship_order","ship":s["id"],"action":"hold"}),"接驳范围内停车，避免回收载具追逐移动载舰",600);}
        }
        if troops_waiting&&groups.iter().any(|g|g["status_reason"].as_str().is_some_and(|s|s.contains("没有兼容"))){self.status="撤收受阻：兼容载舰或舱位不足；保留现场并等待接管".into();}
        if !troops_waiting&&!planes_waiting&&live.iter().all(|s|pos(s).dist(exit)<=radius){
            let success=rows(&l["objectives"]).iter().all(|o|o["complete"]==true);
            self.offer(&mut out,frame,"finish".into(),json!({"op":if success{"littoral_extract"}else{"littoral_abandon"}}),if success{"任务、实际撤收、飞机返舰与撤离区全部达标"}else{"已真实保存存活部队，任务未完成按失败结算"},20);
        }
        out
    }
}
