//! Account-owned items physically brought into a new extraction voyage.
use crate::{model::E,salvage::Start,salvage_v4::Item};use serde::{Deserialize,Serialize};
pub const VERSION:&str="fleet-cargo-v1";
#[derive(Clone,Debug,Serialize,Deserialize)]#[serde(deny_unknown_fields)]
pub struct Config{pub version:String,pub pickup_namespace:String,pub items:Vec<Item>}
pub fn validate(start:&Start)->E<()>{let Some(c)=&start.cargo_transfer_v1 else{return Ok(());};if c.version!=VERSION||![crate::expedition::VERSION,crate::amphibious_expedition::VERSION].contains(&start.gameplay_profile.as_str())||start.content!=crate::salvage_v4::VERSION||c.pickup_namespace.is_empty()||c.pickup_namespace.len()>128||c.items.len()>96{return Err("编队货物版本、命名域或数量无效".into());}let mut ids=std::collections::BTreeSet::new();for item in &c.items{
 if item.id.is_empty()||!ids.insert(&item.id)||item.placement.is_none(){return Err("带入货物身份重复或未安排格位".into());}
 if let Some(row)=crate::expedition::loot().iter().find(|r|r.id==item.loot_id){if item.kind!=row.kind||item.name!=row.name||item.shape!=row.shape||item.kg!=row.kg||![10,14,19].iter().any(|f|item.value==row.value*f/10){return Err("带入货物与登记目录不符".into());}}
 else{return Err("带入货物目录身份未登记".into());}
 }Ok(())}
#[cfg(test)]mod tests{use super::*;use crate::world::World;use serde_json::json;
 fn start()->Start{let item=crate::expedition::loot_item(42,1,0,"calm");let mut v=serde_json::to_value(item).unwrap();v["id"]=json!("existing-loot-1");v["placement"]=json!([0,0,0]);serde_json::from_value(json!({"content":"salvage-v4","gameplay_profile":"cas-adventure-v2","fleet":[{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":100,"level":0}],"mission":{"kind":"salvage","id":"calm","loot_kind":"scrap"},"cargo_v4":{"commander_level":1,"difficulty":"calm","environment":"atoll","weather":"clear","loadouts":{}},"expedition_v2":{"scene":"sunken_metropolis","munitions":{}},"cargo_transfer_v1":{"version":VERSION,"pickup_namespace":"voyage-2","items":[v]}})).unwrap()}
 #[test]fn carried_items_really_occupy_space_weight_and_preserve_identity(){let w=World::new_salvage(42,start()).unwrap();let g=w.salvage.as_ref().unwrap().grid.as_ref().unwrap();assert_eq!(g.items.len(),1);assert_eq!(g.items[0].id,"existing-loot-1");assert_eq!(w.salvage.as_ref().unwrap().cargo.len(),1);assert!(w.observation(0)["salvage"]["cargo_grid"]["kg"].as_u64().unwrap()>0);}
 #[test]fn imported_overlap_padding_or_unknown_catalog_is_rejected(){let mut s=start();let mut item=s.cargo_transfer_v1.as_ref().unwrap().items[0].clone();item.id="another".into();s.cargo_transfer_v1.as_mut().unwrap().items.push(item);assert!(World::new_salvage(42,s).is_err());let mut s=start();s.cargo_transfer_v1.as_mut().unwrap().items[0].loot_id="invented".into();assert!(World::new_salvage(42,s).is_err());}
}
