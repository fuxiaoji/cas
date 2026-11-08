use crate::{model::*, night::{self, Lighting, StarshellProfile}, world::{u, World}};
use serde_json::{json, Value};

pub(crate) const TRAINING: &str = "night-training";
pub(crate) const RADAR_TRAINING: &str = "night-radar-training";
pub(crate) const VERSION: &str = "cas-illumination-v3";

#[derive(Default)]
pub(crate) struct Illumination {
    marks: Vec<Mark>,
    used: Vec<(u32, usize, u32)>,
    preparing: Vec<(u32, usize)>,
}
struct Mark {
    center: P,
    source: u32,
    target: u32,
    owner: usize,
    expires: u32,
    profile: StarshellProfile,
    silhouette: bool,
    front: bool,
}
pub(crate) struct LightShot {
    pub(crate) mount: usize,
    pub(crate) barrels: u32,
    pub(crate) band: usize,
    profile: StarshellProfile,
    contact: Contact,
}

impl World {
    pub(crate) fn has_starshells(&self) -> bool {
        self.version == VERSION
            || self.variant == crate::empress::VARIANT
            || self.variant == crate::campaign::esperance::VARIANT
            || (self.realtime() && matches!(self.variant.as_str(), TRAINING | RADAR_TRAINING))
    }

    fn light_shot(&self, ship: &Ship, contact: &Contact) -> E<LightShot> {
        if !self.has_starshells() { return Err("此想定没有照明弹指令".into()); }
        let def = &self.data.ships[ship.def];
        let gun = &def.gun;
        if !matches!(def.size.as_str(), "C" | "D" | "E") { return Err("该舰没有已核验可用的照明副炮".into()); }
        let profile = night::starshell_profile(gun.caliber_mm.round() as u16, ship.side == 1, 1942)
            .ok_or("本舰炮口径没有已核验的照明弹")?;
        let distance = ship.p.dist(contact.p()) / YARD;
        if distance < f64::from(profile.min_range_yd) { return Err(format!("照明弹最小射程 {} 码", profile.min_range_yd)); }
        let band = gun.range_yd.iter().take(3).position(|limit| distance <= *limit).ok_or("接触超出照明弹远程射程")?;
        let angle = norm((contact.p()-ship.p).heading()-ship.h);
        let (mount, m) = gun.mounts.iter().enumerate().find(|(i,m)| !ship.gun_mount_destroyed[*i] && self.turret_loaded(ship,*i) &&
            (circle(angle,m.arc)||m.arc2.is_some_and(|arc| circle(angle,arc))))
            .ok_or("照明方向没有可用炮座")?;
        Ok(LightShot{mount,barrels:m.barrels,band,profile,contact:contact.clone()})
    }

    /// cas-realtime-v10 (CAS 5.4.4.5): a starshell may be cued by radar as
    /// well as by a visual contact. Older versions keep the visual-only rule.
    fn illumination_contact(&self, owner: usize, ship: &Ship, target: &str) -> E<Contact> {
        if let Ok(contact) = self.contact(owner, target) {
            return Ok(contact.clone());
        }
        if !self.v10_family() {
            return Err("目标接触已丢失".into());
        }
        let mut candidates = std::iter::once(ship).chain(
            self.ships
                .iter()
                .filter(|s| s.side == owner && s.alive() && s.id != ship.id),
        );
        for observer in &mut candidates {
            if let Some(contact) = self.radar_gun_contact(observer, target) {
                return Ok(contact);
            }
        }
        Err("目标接触已丢失".into())
    }

    pub(crate) fn preview_illumination(&self, owner:usize, r:&Value) -> E<Value> {
        let s=self.ship_for(owner,u(r,"ship")?)?;
        let c=self.illumination_contact(owner,s,r["target"].as_str().ok_or("请选择已发现的水面接触")?)?;
        match self.light_shot(s,&c) {
            Ok(plan) => Ok(json!({"valid":!self.pending.iter().any(|o|o.ship==s.id&&o.weapon=="illumination"),
                "minRange":f64::from(plan.profile.min_range_yd)*YARD,"maxRange":self.data.ships[s.def].gun.range_yd[2]*YARD,
                "mount":plan.mount,"heading":(c.p()-s.p).heading()})),
            Err(e) => Ok(json!({"valid":false,"error":e})),
        }
    }

    pub(crate) fn queue_illumination(&mut self,owner:usize,r:&Value)->E<()> {
        let ship=u(r,"ship")?;
        let target=r["target"].as_str().ok_or("请选择已发现的水面接触")?;
        let s=self.ship_for(owner,ship)?;
        let contact=self.illumination_contact(owner,s,target)?;
        self.light_shot(s,&contact)?;
        if self.pending.iter().any(|o|o.ship==ship&&o.weapon=="illumination") {return Err("该舰已有照明弹指令".into());}
        let name=s.name.clone();
        self.pending.push(Fire{side:owner,ship,target:target.into(),weapon:"illumination".into(),heading:None,expires:(self.tick/CYCLE+1)*CYCLE,torpedo:TorpedoOrder::default()});
        self.add(1<<owner,"illumination_ordered",format!("{name} · 照明弹已下令"),Some("CAS-5.4.4.5"),None);
        Ok(())
    }

    pub(crate) fn illumination_active(&self) -> bool {
        self.illumination.marks.iter().any(|mark| mark.expires > self.tick)
    }

    pub(crate) fn mount_lighting(&self,ship:u32,mount:usize)->bool {
        self.illumination.used.contains(&(ship,mount,self.tick/CYCLE))
    }

    pub(crate) fn mount_preparing_illumination(&self, ship: u32, mount: usize) -> bool {
        self.illumination.preparing.contains(&(ship, mount))
    }

    pub(crate) fn prepare_illumination_mounts(&mut self) {
        self.clear_turret_training();
        self.illumination.preparing.clear();
        if !self.has_starshells() { return; }
        // The slowest current mount can sweep 180° in 24 seconds. Start
        // turning in advance without spending illumination or gun dice.
        let work: Vec<_> = self.pending.iter()
            .filter(|o| o.weapon == "illumination" && o.expires.saturating_sub(self.tick) <= 26)
            .filter_map(|o| {
                let s = self.ship_for(o.side, o.ship).ok()?;
                let c = self.illumination_contact(o.side, s, &o.target).ok()?;
                let plan = self.light_shot(s, &c).ok()?;
                Some((s.id, plan.mount, (c.p() - s.p).heading()))
            })
            .collect();
        for (id, mount, heading) in work {
            self.illumination.preparing.push((id, mount));
            self.train_illumination_mount(id, mount, heading);
        }
    }

    pub(crate) fn resolve_illumination(&mut self,planned:bool){
        if !self.has_starshells(){return;}
        self.illumination.marks.retain(|m| m.expires > self.tick);
        self.illumination.used.retain(|(_,_,cycle)| *cycle>=self.tick/CYCLE);
        // cas-realtime-v10: the starshell leaves the moment its mount is
        // trained and loaded, planned or reaction, so mid-window contacts can
        // be lit inside the same window. The one-mount-per-window CAS budget
        // and the one-window burn time are unchanged. Earlier versions only
        // resolve orders at the planned window boundary.
        let realtime = self.v10_family() && !planned;
        if !planned && !realtime {return;}
        let old=std::mem::take(&mut self.pending);
        let (mut ready,wait):(Vec<_>,Vec<_>)=old.into_iter().partition(|p| p.weapon=="illumination"&&
            (p.expires<=self.tick || realtime));
        self.pending=wait;
        ready.sort_by_key(|p|p.ship);
        for order in ready {
            let s=self.ship_for(order.side,order.ship).cloned();
            let plan=s.as_ref().map_err(Clone::clone).and_then(|s| {
                let c=self.illumination_contact(order.side,s,&order.target)?;
                self.light_shot(s,&c)
            });
            let Ok(plan)=plan else {
                self.add(1<<order.side,"rejected",format!("照明弹未发射：{}",plan.err().unwrap()),Some("CAS-5.4.4.5"),None); continue;
            };
            let s=s.unwrap();
            let bearing=(plan.contact.p()-s.p).heading();
            if !self.illumination_aligned(&s,plan.mount,bearing) {
                if realtime && order.expires > self.tick {
                    // The mount is still training; hold and retry next second.
                    self.pending.push(order);
                    continue;
                }
                self.add(1<<s.side,"rejected","照明弹未发射：炮座尚未转入射向".into(),Some("RTS-GUN-04"),None);
                continue;
            }
            let Some(t)=self.ship(plan.contact.ship).filter(|v|v.alive()).cloned() else {continue};
            let mut threatened:Vec<_>=self.pending.iter().filter(|v|v.weapon=="gun"&&v.expires<=self.tick)
                .filter_map(|v|self.contact(v.side,&v.target).ok().map(|v|v.ship)).collect();
            if let Some(c)=self.contacts[1-s.side].iter().find(|c|c.ship==s.id) {
                if self.pending.iter().any(|v|v.side!=s.side&&v.weapon=="gun"&&v.target==c.id) {threatened.push(s.id);}
            }
            let (chance,_)=self.gun_values(&s,&t,plan.band,plan.barrels,false,&threatened,plan.profile.hit_modifier,true);
            let hit=self.d(100) as f64<=chance;
            self.illumination.used.push((s.id,plan.mount,self.tick/CYCLE));
            self.reserve_illumination_mount(s.id,plan.mount);
            let cycle=self.tick/CYCLE;
            // Same primary battery creates the visible night flash.
            self.ship_mut(s.id).unwrap().illumination_cycle=Some(cycle);
            let offset=if hit {Some((0,0,false))} else {night::starshell_scatter(self.d(100)).map(|m|(m.right_yd,m.forward_yd,m.silhouette))};
            let Some((right,forward,silhouette))=offset else {
                self.add(1<<s.side,"illumination_failed","照明弹发射，未起亮。".into(),Some("CAS-5.4.4.5"),None); continue;
            };
            let center=(plan.contact.p()+P::bearing(bearing+90.)*(f64::from(right)*YARD)+P::bearing(bearing)*(f64::from(forward)*YARD)).snap();
            if s.p.dist(center)<f64::from(plan.profile.min_range_yd)*YARD || self.environment().visibility<=2 {
                self.add(1<<s.side,"illumination_failed","照明弹过近或环境无法形成有效照明。".into(),Some("CAS-5.4.4.5"),None); continue;
            }
            self.illumination.marks.push(Mark{center,source:s.id,target:t.id,owner:s.side,expires:self.tick+CYCLE,profile:plan.profile,
                silhouette,front:forward<0&&right==0});
            self.add(1<<s.side,"illumination",format!("{} · 照明弹已起亮，炮座 {} 本窗口用于照明",s.name,plan.mount+1),Some("CAS-5.4.4.5"),Some(center));
            self.last_event_ship(&s);
        }
    }

    pub(crate) fn illumination_modifier(&self,s:&Ship,t:&Ship)->Option<i32>{
        let size=&self.data.ships[t.def].size;
        let env=self.environment();
        let mut best=None;
        let mut blocked=false;
        for m in self.illumination.marks.iter().filter(|m|m.expires>self.tick){
            let max=|silhouette| f64::from(night::starshell_visibility_yd(env,size,silhouette,m.profile))*YARD;
            if s.p.dist(t.p)<=max(false)&&m.center.dist(t.p)<=f64::from(m.profile.radius_yd)*YARD {
                best=Some(night::night_gun_modifier(env,Lighting::Illuminated));
            } else if m.target==t.id&&m.source==s.id {
                if m.silhouette&&s.p.dist(t.p)<=max(true)&&best.is_none(){best=Some(night::night_gun_modifier(env,Lighting::Silhouetted));}
                if m.front{blocked=true;}
            }
        }
        // Seat tracks remain shared; obstructed firing ship uses dead reckoning.
        if blocked&&best.is_none(){Some(-4)}else{best}
    }

    pub(crate) fn visible_illumination(&self,owner:usize)->Vec<Value>{
        self.illumination.marks.iter().filter(|m|m.expires>self.tick && (m.owner==owner || self.ships.iter().any(|s|s.side==owner&&s.alive()&&s.p.dist(m.center)<=30.*1852.))).map(|m|{
            let mut view=json!({"x":m.center.x,"y":m.center.y,"radius":f64::from(m.profile.radius_yd)*YARD,
                "expires":m.expires,"own":m.owner==owner});
            // The firing seat knows the aimed contact; show the target point so
            // the chart can mark the ship, not only the burst centre.
            if m.owner==owner {
                if let Some(target)=self.ship(m.target) {
                    view["targetX"]=json!(target.p.x); view["targetY"]=json!(target.p.y);
                }
            }
            view
        }).collect()
    }
}
