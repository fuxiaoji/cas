//! Opt-in naval aviation command queue. No changes to legacy v4 without enable.
use super::*;
pub(super) const VERSION:&str="cas-carrier-ops-v1";
#[derive(Default)]
pub(super) struct Operations {pub ally_ai:bool,pub queue:Vec<Value>,pub rejected:Vec<Value>,pub(super) cursor:usize,pub modern:Option<super::carrier_ops_v2::CommandState>}
impl Battle {
    pub(super) fn carrier_configure(&mut self,q:&Value)->E<()> {
        if q["version"]==super::carrier_ops_v2::VERSION{return self.carrier_v2_configure(q)}
        if q["version"]!=VERSION{return Err("航母操作版本无效".into())}
        let ai=q["ally_ai"].as_bool().ok_or("请选择航空托管开关")?;
        self.carrier_ops.get_or_insert_with(Operations::default).ally_ai=ai;
        Ok(())
    }
    pub(super) fn carrier_enqueue(&mut self,q:&Value)->E<()> {
        if self.carrier_is_v2(){return self.carrier_v2_enqueue(q)}
        self.air_plan(q)?;
        let ops=self.carrier_ops.as_mut().ok_or("请先启用新版航母指挥")?;
        ops.queue.retain(|p|p["squadron_id"]!=q["squadron_id"]);
        if ops.queue.len()>=24{return Err("待命中队数量已达上限".into())}
        ops.queue.push(q.clone());Ok(())
    }
    pub(super) fn carrier_advance(&mut self) {
        if self.carrier_is_v2(){self.carrier_v2_advance();return}
        if self.ground.frame%10!=0{return}
        let Some(mut ops)=self.carrier_ops.take()else{return};
        // Take queue out before issuing: rejected proposals never mutate aircraft.
        let pending=std::mem::take(&mut ops.queue);
        for mut q in pending {
            let id=q["squadron_id"].as_str().unwrap_or("");
            let Some(s)=self.squadrons.iter().find(|s|s.id==id)else{continue};
            let valid=self.naval.ship(s.carrier).is_some_and(|c|c.side==0&&c.alive());
            if !valid||s.lost==s.total||s.stock==0 {ops.rejected.push(json!({"squadron_id":id,"reason":"母舰、可用飞机或武器耗尽，待命取消"}));continue}
            let landing=self.aircraft.iter().any(|a|a.carrier==s.carrier&&a.phase=="returning"&&self.naval.ship(a.carrier).is_some_and(|c|a.p.dist(c.p)<1500.));
            if landing||s.available==0||s.ready>self.ground.frame||self.deck.get(&s.carrier).is_some_and(|n|*n>self.ground.frame)||self.aircraft.len()+s.available.min(3)as usize>24 {ops.queue.push(q);continue}
            q["queue"]=json!(false);
            match self.air_order(&q){Ok(())=>{},Err(e)=>ops.rejected.push(json!({"squadron_id":q["squadron_id"],"reason":e}))}
        }
        // A bounded per-side allocation prevents the first carrier from consuming
        // every aircraft slot. Rotating squadron order gives all decks a turn.
        let n=self.squadrons.len();
        for offset in 0..n {
            let i=(ops.cursor+offset)%n;let s=&self.squadrons[i];
            let Some(c)=self.naval.ship(s.carrier).filter(|c|c.alive())else{continue};
            let side=c.side;
            if side==0&&!ops.ally_ai||s.available==0||s.stock==0||s.ready>self.ground.frame||self.deck.get(&s.carrier).is_some_and(|n|*n>self.ground.frame)||ops.queue.iter().any(|q|q["squadron_id"]==s.id){continue}
            let active=self.aircraft.iter().filter(|a|a.hp>0.&&self.naval.ship(a.carrier).is_some_and(|c|c.side==side)).count();
            if active+s.available.min(3).min(s.stock)as usize>12 {continue}
            if self.aircraft.iter().any(|a|a.carrier==s.carrier&&a.phase=="returning"&&a.p.dist(c.p)<1500.){continue}
            let origin=c.p;let range=s.range;let role=s.role;
            let intercept=if role=="fighter"{self.aircraft.iter().filter(|a|a.hp>0.&&self.naval.ship(a.carrier).is_some_and(|c|c.side!=side)&&a.p.dist(origin)<=range).min_by(|a,b|a.p.dist(origin).total_cmp(&b.p.dist(origin))).map(|a|(a.p,json!(a.id)))}else{None};
            if let Some((p,id))=intercept {let _=self.launch_air(i,"strike",p,"aircraft".into(),id);continue}
            if role=="fighter"{
                // One defensive flight per mother. CAP will intercept in the
                // explicit update below and consumes real fuel even while holding.
                if !self.aircraft.iter().any(|a|a.carrier==s.carrier&&a.role=="fighter"&&a.hp>0.){let _=self.launch_air(i,"patrol",origin+P{x:0.,y:-1200.},"land".into(),Value::Null);}continue
            }
            let target=self.naval.contacts[side].iter().filter(|t|origin.dist(t.p())<=range).min_by_key(|t|self.aircraft.iter().filter(|a|a.hp>0.&&a.target_kind=="ship"&&a.target_id==t.id).count()).map(|t|(t.p(),t.id.clone()));
            if let Some((p,id))=target {let _=self.launch_air(i,"strike",p,"ship".into(),json!(id));}
        }
        if n>0{ops.cursor=(ops.cursor+1)%n;}
        if ops.rejected.len()>12{ops.rejected.drain(..ops.rejected.len()-12);}
        self.carrier_ops=Some(ops);
    }
    pub(super) fn carrier_intercepts(&mut self) {
        if self.carrier_is_v2(){self.carrier_v2_intercepts();return}
        if self.carrier_ops.is_none(){return}
        for i in 0..self.aircraft.len(){
            let a=&self.aircraft[i];
            if a.hp<=0.||a.role!="fighter"||a.mission!="patrol"||a.phase=="returning"||a.phase=="launching"||a.weapons==0{continue}
            let side=self.naval.ship(a.carrier).map_or(0,|c|c.side);
            let target=self.aircraft.iter().filter(|e|e.hp>0.&&self.naval.ship(e.carrier).is_some_and(|c|c.side!=side)&&e.p.dist(a.p)<=3000.).min_by(|x,y|x.p.dist(a.p).total_cmp(&y.p.dist(a.p))).map(|e|(e.p,e.id));
            if let Some((p,id))=target{let a=&mut self.aircraft[i];a.target=p;a.target_id=json!(id);a.target_kind="aircraft".into();a.mission="strike";a.phase="outbound";}
        }
    }
    pub(super) fn carrier_view(&self)->Value {
        if self.carrier_is_v2(){return self.carrier_v2_view()}
        let Some(ops)=&self.carrier_ops else{return Value::Null};
        json!({"version":VERSION,"ally_ai":ops.ally_ai,"queue":ops.queue,"rejected":ops.rejected,"landing_priority":true,"ai_side_aircraft_budget":12})
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn battle()->Battle {
        let config=super::super::Config{mode:"tutorial".into(),company_layout:None,lesson:Some("landing".into()),ships:vec![Hull{id:ENTERPRISE.into(),hp:100.,ammo:100},Hull{id:SHOKAKU.into(),hp:100.,ammo:100}],roster:vec!["MCP-034".into(),"MCP-001".into()],unit_condition:vec![],transport_preset:"combat".into(),defense:vec![],company_transports:vec![]};
        Battle::new(42,config).unwrap()
    }
    fn enable(w:&mut Battle,ai:bool){w.command(&json!({"op":"carrier_ops","version":VERSION,"ally_ai":ai}),true).unwrap();}
    #[test] fn opt_in_and_multi_deck_ai_replay_are_deterministic(){
        let mut w=battle();assert!(w.view()["littoral"].get("carrier_ops").is_none());enable(&mut w,true);
        for _ in 0..120{w.advance();}
        for carrier in [1,2]{assert!(w.aircraft.iter().any(|a|a.carrier==carrier),"both decks must actually fly");}
        assert!(w.aircraft.len()<=24);let save=w.save();assert_eq!(Battle::from_save(save,None).unwrap().view(),w.view());
    }
    #[test] fn queue_waits_for_actual_serial_deck_and_latest_drag_replaces(){
        let mut w=battle();enable(&mut w,false);
        let fighter=w.squadrons[0].id.clone();let bomber=w.squadrons[1].id.clone();let p=w.ground.ruins[0].p;
        w.command(&json!({"op":"littoral_air_order","squadron_id":fighter,"action":"patrol","x":9000.,"y":17000.}),true).unwrap();
        let q=json!({"op":"littoral_air_order","squadron_id":bomber,"action":"strike","target_kind":"land","x":p.x,"y":p.y,"queue":true});
        w.command(&q,true).unwrap();w.command(&q,true).unwrap();assert_eq!(w.carrier_ops.as_ref().unwrap().queue.len(),1);
        for _ in 0..50{w.advance()}assert!(!w.aircraft.iter().any(|a|a.squadron==1));
        for _ in 0..30{w.advance()}assert!(w.aircraft.iter().any(|a|a.squadron==1));assert!(w.carrier_ops.as_ref().unwrap().queue.is_empty());
        assert_eq!(Battle::from_save(w.save(),None).unwrap().view(),w.view());
    }
    #[test] fn patrol_holds_and_can_be_recalled_without_spawning_free_planes(){
        let mut w=battle();enable(&mut w,false);let id=w.squadrons[0].id.clone();let p=w.naval.ship(1).unwrap().p;
        w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"patrol","x":p.x,"y":p.y-200.}),true).unwrap();
        for _ in 0..100{w.advance()}assert!(w.aircraft.iter().any(|a|a.phase=="patrolling"));let stock=w.squadrons[0].stock;
        w.command(&json!({"op":"littoral_air_order","squadron_id":id,"action":"return"}),true).unwrap();for _ in 0..400{w.advance()}
        assert_eq!(w.squadrons[0].available,3);assert!(w.squadrons[0].stock>=stock);assert_eq!(w.squadrons[0].lost,0);
    }
    #[test] fn ai_respects_budget_after_an_uneven_combat_loss(){
        let mut w=battle();enable(&mut w,true);let p=w.naval.ship(1).unwrap().p;
        // Four real flights, followed by one combat loss, leave eleven active.
        // A new three-plane CAP must wait rather than overshoot the side budget.
        for i in [1,2,4,5]{w.deck.clear();w.launch_air(i,"strike",p,"land".into(),Value::Null).unwrap();}
        let loss=w.aircraft.remove(0);w.squadrons[loss.squadron].lost+=1;
        w.deck.clear();w.ground.frame=10;w.carrier_advance();
        assert_eq!(w.aircraft.iter().filter(|a|w.naval.ship(a.carrier).is_some_and(|c|c.side==0)).count(),11);
        for s in &w.squadrons{assert_eq!(s.available+s.lost+w.aircraft.iter().filter(|a|a.squadron==w.squadrons.iter().position(|x|x.id==s.id).unwrap()).count()as u32,s.total);}
    }
}
