//! Explicit, imported procedural coastal terrain. Only the opt-in coastal
//! ruleset may attach this to a simulation. The accepted centimetre grid is
//! frozen in that ruleset's save; renderers never add a second physical noise.
use crate::model::{E, P};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};

pub(crate) const VERSION: &str = "cas-coastal-geography-v1";
pub(crate) const RULES_VERSION: &str = "cas-island-war-coastal-v1";
const BIOMES: [&str; 8] = ["sea", "sand", "sea_cliff", "swamp", "river", "mountain", "forest", "grassland"];

#[derive(Clone, Debug)]
pub(crate) struct Landing {
    pub id: u32,
    pub shore: P,
    pub sea: P,
    pub land: P,
    pub width_m: f64,
}
#[derive(Clone, Debug)]
pub(crate) struct Sample {
    pub height: f64,
    pub slope: f64,
    pub biome: &'static str,
    pub water_level: f64,
}
#[derive(Clone, Debug)]
pub(crate) struct CoastalGeography {
    pub id: String,
    pub seed: u32,
    pub origin: P,
    pub cell: f64,
    pub columns: usize,
    pub rows: usize,
    heights_cm: Vec<i32>,
    biomes: Vec<u8>,
    water_cm: Vec<i32>,
    pub polygon: Vec<P>,
    pub landings: Vec<Landing>,
    hash: String,
    roads: Vec<Value>,
}
fn finite(v: &Value) -> E<f64> {
    v.as_f64().filter(|n| n.is_finite()).ok_or("连续地理数值必须有限".into())
}
fn list(value:&Value,count:usize)->E<&Vec<Value>>{value.as_array().filter(|a|a.len()==count).ok_or("连续地理各顶点数组长度必须一致".into())}
fn p(v: &Value) -> E<P> {
    let q = P { x: finite(&v["x"])?, y: finite(&v["y"])? };
    if q.x.abs() > 1_000_000. || q.y.abs() > 1_000_000. { return Err("连续地理坐标超出范围".into()); }
    Ok(q)
}
fn signed_area(poly: &[P]) -> f64 {
    poly.iter().zip(poly.iter().cycle().skip(1)).take(poly.len()).map(|(a,b)| a.x*b.y-b.x*a.y).sum::<f64>()*0.5
}
impl CoastalGeography {
    pub(crate) fn from_value(v: &Value) -> E<Self> {
        if v["version"] != VERSION { return Err("须显式指定cas-coastal-geography-v1地理".into()); }
        let id = v["id"].as_str().filter(|s| !s.trim().is_empty() && s.len()<=128).ok_or("连续地理ID无效")?.to_owned();
        let seed = v["seed"].as_u64().filter(|s| *s<=u32::MAX as u64).ok_or("连续地理种子无效")? as u32;
        let h=&v["heightfield"];
        let origin=p(&h["origin"])?;
        let cell=finite(&h["cell_size_m"])?;
        if !(2. ..=20.).contains(&cell) || (cell*100.-(cell*100.).round()).abs()>1e-6 { return Err("连续地理网格须2–20米且精确到厘米".into()); }
        let columns=h["columns"].as_u64().filter(|n|(17..=513).contains(n)).ok_or("连续地理列数无效")? as usize;
        let rows=h["rows"].as_u64().filter(|n|(17..=513).contains(n)).ok_or("连续地理行数无效")? as usize;
        let count=columns*rows;
        if count>200_000 || (columns-1) as f64*cell>2400. || (rows-1) as f64*cell>2400. { return Err("首版连续地理只支持至2400米/200000顶点，不能静默缩放".into()); }
        let heights_cm=list(&h["heights"],count)?.iter().map(|n| {let n=finite(n)?;if !(-200. ..=2000.).contains(&n){return Err("连续高程超出范围".into());}Ok((n*100.).round() as i32)}).collect::<E<Vec<_>>>()?;
        let biomes=list(&v["biomes"],count)?.iter().map(|n|BIOMES.iter().position(|b|n.as_str()==Some(b)).map(|n|n as u8).ok_or("连续地理地貌类型未登记".into())).collect::<E<Vec<_>>>()?;
        let water_cm=list(&v["water_levels"],count)?.iter().map(|n|{let n=finite(n)?;if !(-100. ..=2000.).contains(&n){return Err("连续地理水位超出范围".into());}Ok((n*100.).round() as i32)}).collect::<E<Vec<_>>>()?;
        for y in 0..rows { for x in 0..columns { if (x==0||y==0||x+1==columns||y+1==rows) && heights_cm[y*columns+x]>=0 {return Err("连续海岛网格边界必须为海床，不能截断陆地".into());} } }
        let mut result=Self{id,seed,origin,cell,columns,rows,heights_cm,biomes,water_cm,polygon:vec![],landings:vec![],hash:String::new(),roads:vec![]};
        result.polygon=result.contour()?;
        result.landings=result.derive_landings()?;
        result.roads=result.derive_roads();
        let bytes=serde_json::to_vec(&result.export_grid()).map_err(|e|e.to_string())?;
        let mut hash=0xcbf29ce484222325u64;
        for b in bytes {hash=(hash^b as u64).wrapping_mul(0x100000001b3);}
        result.hash=format!("fnv1a64:{hash:016x}");
        Ok(result)
    }
    fn vertex(&self, x: usize, y: usize) -> P { self.origin+P{x:x as f64*self.cell,y:y as f64*self.cell} }
    fn contour(&self) -> E<Vec<P>> {
        type Key=(i64,i64);
        let key=|q:P| -> Key {(((q.x-self.origin.x)*100.).round() as i64,((q.y-self.origin.y)*100.).round() as i64)};
        let mut graph:BTreeMap<Key,BTreeSet<Key>>=BTreeMap::new();
        for y in 0..self.rows-1 {for x in 0..self.columns-1 {
            let ids=[y*self.columns+x,y*self.columns+x+1,(y+1)*self.columns+x,(y+1)*self.columns+x+1];
            let pts=[self.vertex(x,y),self.vertex(x+1,y),self.vertex(x,y+1),self.vertex(x+1,y+1)];
            for triangle in [[0,1,2],[1,3,2]] {
                let mut hits=vec![];
                for (a,b) in [(triangle[0],triangle[1]),(triangle[1],triangle[2]),(triangle[2],triangle[0])] {
                    let ha=self.heights_cm[ids[a]] as f64;let hb=self.heights_cm[ids[b]] as f64;
                    if (ha>0.)!=(hb>0.) {hits.push(key(pts[a]+(pts[b]-pts[a])*(ha/(ha-hb))));}
                }
                hits.sort();hits.dedup();
                if hits.len()==2 && hits[0]!=hits[1] {graph.entry(hits[0]).or_default().insert(hits[1]);graph.entry(hits[1]).or_default().insert(hits[0]);}
            }
        }}
        if graph.is_empty() || graph.values().any(|n|n.len()!=2){return Err("连续海岸等高线不闭合或分叉；请调整量化网格".into());}
        let mut used=BTreeSet::new();let mut loops=vec![];
        for &start in graph.keys(){if used.contains(&start){continue;}
            let mut loop_keys=vec![];let mut prev=None;let mut current=start;
            loop {if used.contains(&current){if current!=start{return Err("连续海岸发生自交".into());}break;}
                used.insert(current);loop_keys.push(current);
                let next=*graph[&current].iter().find(|n|Some(**n)!=prev).ok_or("连续海岸缺少后继")?;
                prev=Some(current);current=next;
            }
            let poly=loop_keys.into_iter().map(|(x,y)|self.origin+P{x:x as f64/100.,y:y as f64/100.}).collect::<Vec<_>>();
            if poly.len()>=3 {loops.push(poly);}
        }
        let mut poly=loops.into_iter().max_by(|a,b|signed_area(a).abs().total_cmp(&signed_area(b).abs())).ok_or("没有连续陆地外轮廓")?;
        if signed_area(&poly).abs()<10000. {return Err("连续试玩岛陆地面积不足一公顷".into());}
        if signed_area(&poly)<0. {poly.reverse();}
        // Remove collinear contour nodes, preserving real bends and centimetres.
        let mut simplified=vec![];
        for i in 0..poly.len(){let a=poly[(i+poly.len()-1)%poly.len()];let b=poly[i];let c=poly[(i+1)%poly.len()];let ab=b-a;let bc=c-b;
            if (ab.x*bc.y-ab.y*bc.x).abs()>0.005 {simplified.push(b);}
        }
        if simplified.len()>=3 {poly=simplified;}
        Ok(poly)
    }
    pub(crate) fn sample(&self, p:P)->Option<Sample> {
        let gx=(p.x-self.origin.x)/self.cell;let gy=(p.y-self.origin.y)/self.cell;
        if gx<0.||gy<0.||gx>(self.columns-1)as f64||gy>(self.rows-1)as f64{return None;}
        let x=(gx.floor()as usize).min(self.columns-2);let y=(gy.floor()as usize).min(self.rows-2);
        let u=gx-x as f64;let v=gy-y as f64;
        let a=y*self.columns+x;let b=a+1;let c=a+self.columns;let d=c+1;
        let (ids,weights,dx,dy)=if u+v<=1. {([a,b,c],[1.-u-v,u,v],self.heights_cm[b]-self.heights_cm[a],self.heights_cm[c]-self.heights_cm[a])}else{([b,d,c],[1.-v,u+v-1.,1.-u],self.heights_cm[d]-self.heights_cm[c],self.heights_cm[d]-self.heights_cm[b])};
        let height=(0..3).map(|i|weights[i]*self.heights_cm[ids[i]]as f64/100.).sum::<f64>();
        let water_level=(0..3).map(|i|weights[i]*self.water_cm[ids[i]]as f64/100.).sum::<f64>();
        let dominant=(0..3).max_by(|a,b|weights[*a].total_cmp(&weights[*b]).then(b.cmp(a))).unwrap();
        let sx=dx as f64/(100.*self.cell);let sy=dy as f64/(100.*self.cell);
        Some(Sample{height,slope:libm::sqrt(sx*sx+sy*sy),biome:BIOMES[self.biomes[ids[dominant]]as usize],water_level})
    }
    pub(crate) fn movement(&self,p:P,class:&str)->f64 {
        if class=="air"{return 1.;}
        let Some(s)=self.sample(p)else{return 0.;};
        let amphibious=matches!(class,"amphibious"|"river_infantry");
        if s.height<=0. {return if amphibious{0.22}else{0.};}
        let armor=class=="armor";
        let max_slope=if armor{0.62}else if amphibious{0.72}else{0.86};
        if s.slope>max_slope || s.biome=="sea_cliff" {return 0.;}
        match s.biome {
            "river" if s.water_level>s.height+0.20 => if amphibious{0.48}else{0.},
            "swamp" => if armor{0.15}else if amphibious{0.72}else{0.48},
            "forest" => if armor{0.38}else{0.72},
            "mountain" => if armor{0.48}else{0.72},
            "sand" => if armor{0.68}else{0.90},
            _ => 1.,
        }
    }
    pub(crate) fn cover(&self,p:P)->f64 {match self.sample(p).map(|s|s.biome){Some("forest")=>0.70,Some("swamp")=>0.9,_=>1.}}
    pub(crate) fn concealment(&self,p:P)->f64 {match self.sample(p).map(|s|s.biome){Some("forest")=>0.55,Some("swamp")=>0.8,_=>1.}}
    pub(crate) fn line_of_sight(&self,a:P,b:P,eye:f64)->bool {
        let ah=self.sample(a).map_or(0.,|s|s.height.max(0.))+eye;
        let bh=self.sample(b).map_or(0.,|s|s.height.max(0.))+eye;
        let count=(a.dist(b)/(self.cell*0.5)).ceil().max(1.)as u32;
        !(1..count).any(|i|{let t=i as f64/count as f64;self.sample(a+(b-a)*t).is_some_and(|s|s.height>ah+(bh-ah)*t+0.10)})
    }
    fn derive_landings(&self)->E<Vec<Landing>> {
        let mut valid=vec![];
        for i in 0..self.polygon.len(){let a=self.polygon[i];let b=self.polygon[(i+1)%self.polygon.len()];let delta=b-a;let length=a.dist(b);let n=P{x:-delta.y,y:delta.x}.unit();
            let steps=(length/4.).ceil().max(1.)as usize;
            for k in 0..steps {let shore=a+delta*((k as f64+0.5)/steps as f64);let land=shore+n*12.;let sea=shore-n*12.;
                if self.sample(land).is_some_and(|s|s.biome=="sand"&&s.slope<0.38&&s.height>0.) && self.sample(sea).is_some_and(|s|s.height < -0.3) && self.movement(land,"infantry")>0. {valid.push((shore,sea,land,length/steps as f64));}
            }
        }
        // Three insertion slots are an explicit first-playable constraint of
        // the reused combat command vocabulary, not three invented beaches.
        // Each slot has a contiguous, physically sampled shore-width check.
        let mut selected:Vec<Landing>=vec![];
        while selected.len()<3 {
            let best=valid.iter().filter(|(shore,_,_,_)|selected.iter().all(|s|s.shore.dist(*shore)>24.)).map(|row|{
                let width=valid.iter().filter(|q|q.0.dist(row.0)<35.).map(|q|q.3).sum::<f64>();
                let distance=selected.iter().map(|s|s.shore.dist(row.0)).fold(300.,f64::min);
                (row,width,width.min(65.)+distance*0.1)
            }).filter(|(_,width,_)|*width>=16.).max_by(|a,b|a.2.total_cmp(&b.2));
            let Some((row,width,_))=best else{return Err("连续试玩岛至少需要三个相隔24米、宽16米以上的真实沙滩泊位槽".into());};
            selected.push(Landing{id:selected.len()as u32+1,shore:row.0,sea:row.1,land:row.2,width_m:width.min(70.)});
        }
        // Keep the ordinary/default slot 2 on the widest of the real beaches.
        let max=selected.iter().enumerate().max_by(|a,b|a.1.width_m.total_cmp(&b.1.width_m)).unwrap().0;
        selected.swap(1,max);for(i,s)in selected.iter_mut().enumerate(){s.id=i as u32+1;}
        Ok(selected)
    }
    fn derive_roads(&self)->Vec<Value>{
        let center=self.origin+P{x:self.width()*0.5,y:self.height()*0.5};
        let mut routes:Vec<(f64,Vec<(f64,f64)>)>=vec![
            (8.4,vec![(-2.,-43.),(-2.,0.),(-2.,43.),(2.,83.),(21.,115.),(62.,140.)]),
            (6.2,vec![(-62.,18.),(-31.,13.),(-2.,13.),(28.,13.),(66.,25.)]),
            (5.6,vec![(-48.,57.),(-28.,56.),(0.,56.),(31.,57.),(70.,63.)]),
            (3.,vec![(-61.,18.),(-80.,37.),(-101.,71.),(-114.,103.)]),
            (5.5,vec![(66.,25.),(88.,20.)]),(4.,vec![(0.,200.),(0.,230.)])];
        for z in [88.,126.,163.,200.]{routes.push((4.2,vec![(-84.,z),(-40.,z),(0.,z),(40.,z),(80.,z)]));}
        for x in [-84.,80.]{routes.push((4.2,vec![(x,88.),(x,126.),(x,163.),(x,200.)]));}
        for z in [20.,58.,96.]{routes.push((5.5,vec![(88.,z),(126.,z),(170.,z)]));}
        for x in [88.,126.,170.]{routes.push((5.5,vec![(x,20.),(x,58.),(x,96.)]));}
        let mut result=vec![];
        for(width,points)in routes{let mut strip=vec![];
            for pair in points.windows(2){let a=center+P{x:pair[0].0,y:pair[0].1};let b=center+P{x:pair[1].0,y:pair[1].1};let count=(a.dist(b)/2.).ceil().max(1.)as u32;let delta=(b-a).unit();let lateral=P{x:-delta.y,y:delta.x}*(width*0.5);
                for i in 0..count{let q=a+(b-a)*(i as f64/count as f64);let legal=[q,q-lateral,q+lateral].iter().all(|p|self.sample(*p).is_some_and(|s|s.height>0.&&s.slope<0.45&&!matches!(s.biome,"sea"|"sea_cliff"|"river"|"swamp")));
                    if legal{strip.push(q);}else if strip.len()>=2{result.push(json!({"id":format!("coastal-street-{}",result.len()),"points":strip,"width":width,"authority":"surface_only","movement_buff":false,"bridge":false}));strip=vec![];}else{strip.clear();}
                }
            }
            if strip.len()>=2{result.push(json!({"id":format!("coastal-street-{}",result.len()),"points":strip,"width":width,"authority":"surface_only","movement_buff":false,"bridge":false}));}
        }
        result
    }
    pub(crate) fn roads(&self)->Value{json!(self.roads)}
    pub(crate) fn sea_clear(&self,p:P,draft:f64,radius:f64)->bool{
        let clear=|q:P|self.sample(q).map_or(true,|s|s.height < -draft);
        clear(p)&&(0..8).all(|i|clear(p+P::bearing(i as f64*45.)*radius))
    }
    pub(crate) fn sea_route(&self,a:P,b:P,draft:f64,radius:f64)->E<Vec<P>>{
        let clear_line=|a:P,b:P|{let n=(a.dist(b)/(self.cell*0.5)).ceil().max(1.)as usize;(0..=n).all(|i|self.sea_clear(a+(b-a)*(i as f64/n as f64),draft,radius))};
        if !self.sea_clear(b,draft,radius){return Err("登陆艇目标不是安全水域".into());}
        if clear_line(a,b){return Ok(vec![b]);}
        let step=self.cell*2.;let origin=P{x:self.origin.x.min(a.x).min(b.x)-40.,y:self.origin.y.min(a.y).min(b.y)-40.};
        let w=((self.origin.x+self.width()).max(a.x).max(b.x)+40.-origin.x)/step;
        let h=((self.origin.y+self.height()).max(a.y).max(b.y)+40.-origin.y)/step;
        if w*h>250_000.{return Err("登陆艇航路超出首版局部搜索预算".into());}
        let cell=|p:P|(((p.x-origin.x)/step).round()as i32,((p.y-origin.y)/step).round()as i32);
        let point=|(x,y):(i32,i32)|origin+P{x:x as f64*step,y:y as f64*step};
        let start=cell(a);let mut queue=std::collections::VecDeque::from([start]);let mut prev=BTreeMap::from([(start,start)]);let mut found=None;
        while let Some(c)=queue.pop_front(){if point(c).dist(b)<step*1.6&&clear_line(point(c),b){found=Some(c);break;}
            for(dx,dy)in[(1,0),(0,1),(-1,0),(0,-1),(1,1),(-1,1),(1,-1),(-1,-1)]{let n=(c.0+dx,c.1+dy);
                if n.0<0||n.1<0||n.0>w as i32||n.1>h as i32||prev.contains_key(&n){continue;}
                if self.sea_clear(point(n),draft,radius)&&clear_line(point(c),point(n)){prev.insert(n,c);queue.push_back(n);}
            }
        }
        let mut c=found.ok_or("登陆艇无法绕过真实岸线抵达目标水域")?;let mut route=vec![b];while c!=start{route.push(point(c));c=prev[&c];}route.reverse();
        let mut simplified=vec![];let mut at=0;let mut p=a;while at<route.len(){let mut j=at;while j+1<route.len()&&clear_line(p,route[j+1]){j+=1;}p=route[j];simplified.push(p);at=j+1;}
        Ok(simplified)
    }
    pub(crate) fn foundation(&self,p:P,radius:f64)->bool{
        let Some(center)=self.sample(p)else{return false;};
        if center.height<=0.||center.slope>0.18||matches!(center.biome,"river"|"swamp"|"sea_cliff"){return false;}
        let n=(radius/self.cell).ceil()as i32;
        (-n..=n).all(|y|(-n..=n).all(|x|{let delta=P{x:x as f64*self.cell,y:y as f64*self.cell};if delta.dist(P::default())>radius{return true;}let q=p+delta;self.sample(q).is_some_and(|s|s.height>0.&&(s.height-center.height).abs()<1.8&&s.slope<0.22&&!matches!(s.biome,"river"|"swamp"|"sea_cliff"))&&self.movement(q,"armor")>0.}))
    }
    pub(crate) fn query(&self,value:&Value)->E<Value>{
        let q=p(value)?;let Some(s)=self.sample(q)else{return Ok(json!({"point":q,"supported":false,"reason":"outside_frozen_grid"}));};
        let in_slot=self.landings.iter().any(|b|b.land.dist(q)<=12.&&b.width_m>=16.);
        Ok(json!({"point":q,"supported":true,"height":{"supported":true,"height_m":s.height,"sampler":"continuous_triangle_grid_v1"},"slope":{"supported":true,"rise_over_run":s.slope},"biome":{"supported":true,"kind":s.biome,"water_level_m":s.water_level},"movement":{"supported":true,"infantry":self.movement(q,"infantry"),"armor":self.movement(q,"armor"),"amphibious":self.movement(q,"amphibious"),"includes_dynamic_obstacles":false},"landing":{"supported":true,"valid":in_slot&&s.biome=="sand"&&s.slope<0.38,"reason":"finite_registered_shore_slots_only"}}))
    }
    pub(crate) fn landing(&self,id:u32)->E<&Landing>{self.landings.iter().find(|b|b.id==id).ok_or("该连续海岸没有这个真实登陆泊位".into())}
    pub(crate) fn width(&self)->f64 {(self.columns-1)as f64*self.cell}
    pub(crate) fn height(&self)->f64 {(self.rows-1)as f64*self.cell}
    pub(crate) fn header(&self)->Value {json!({"version":VERSION,"id":self.id,"seed":self.seed,"geometry_hash":self.hash,"authority_scope":"validated_frozen_grid","units":"metres","triangulation":"a_b_c__b_d_c","quantization_m":0.01,"bounds_m":{"x":self.origin.x,"y":self.origin.y,"width":self.width(),"height":self.height()}})}
    fn export_grid(&self)->Value {json!({"version":VERSION,"id":self.id,"seed":self.seed,"heightfield":{"origin":self.origin,"cell_size_m":self.cell,"columns":self.columns,"rows":self.rows,"heights":self.heights_cm.iter().map(|n|*n as f64/100.).collect::<Vec<_>>()},"biomes":self.biomes.iter().map(|n|BIOMES[*n as usize]).collect::<Vec<_>>(),"water_levels":self.water_cm.iter().map(|n|*n as f64/100.).collect::<Vec<_>>()})}
    pub(crate) fn snapshot(&self)->Value {let mut value=self.export_grid();value["header"]=self.header();value["geometry_hash"]=self.header()["geometry_hash"].clone();value["polygon"]=json!(self.polygon);value["landing_slots"]=self.landing_view();value}
    pub(crate) fn landing_view(&self)->Value {json!(self.landings.iter().map(|b|json!({"id":b.id,"shore":b.shore,"sea":b.sea,"land":b.land,"width_m":b.width_m,"ordinary":true,"heavy":b.width_m>=30.,"authority":"sampled_sand_slope_depth"})).collect::<Vec<_>>())}
    pub(crate) fn terrain_view(&self)->Value {json!({"version":VERSION,"height_model":"continuous_triangle_grid_v1","height_los":true,"features":[],"roads":self.roads,"elevation_zones":[],"ramps":[],"geography":self.header(),"landing_slots":self.landing_view(),"effect":"连续三角网格统一高程、坡度、地貌、寻路、射界与真实沙滩泊位"})}
}

#[cfg(test)]
mod tests {
    use super::*;
    pub(crate) fn fixture()->Value {
        let n=81;let cell=4.;let mut heights=vec![];let mut biomes=vec![];let mut waters=vec![];
        for y in 0..n {for x in 0..n {let px=x as f64*cell-160.;let py=y as f64*cell-160.;let d=125.-libm::sqrt(px*px+py*py);heights.push(d*0.12);biomes.push(if d<0.{"sea"}else{"sand"});waters.push(-100.);}}
        json!({"version":VERSION,"id":"test-island","seed":714,"heightfield":{"origin":{"x":14440,"y":12840},"cell_size_m":cell,"columns":n,"rows":n,"heights":heights},"biomes":biomes,"water_levels":waters})
    }
    #[test]fn approved_demo_imports_as_real_metres(){
        let path=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../godot/data/coastal-demo-v1-714.json");
        let value:Value=serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let g=CoastalGeography::from_value(&value).unwrap();
        assert_eq!(g.columns,181);assert_eq!(g.rows,181);assert_eq!(g.width(),720.);assert!(g.polygon.len()>100);assert_eq!(g.landings.len(),3);
        let h=g.sample(P{x:14600.,y:13045.}).unwrap();assert!(h.height>0.&&h.slope<0.18);
        println!("demo imported: {} contour vertices, landings {}, hash {}",g.polygon.len(),g.landing_view(),g.hash);
    }
    #[test]fn deterministic_roundtrip_and_closed_real_coast(){let a=CoastalGeography::from_value(&fixture()).unwrap();let b=CoastalGeography::from_value(&a.snapshot()).unwrap();assert_eq!(a.header(),b.header());assert!(a.polygon.len()>100);assert_eq!(a.landings.len(),3);for s in &a.landings{assert!(a.sample(s.sea).unwrap().height<0.);assert!(a.sample(s.land).unwrap().height>0.);}}
    #[test]fn triangle_interpolation_is_not_bilinear(){let mut a=CoastalGeography::from_value(&fixture()).unwrap();let q=P{x:14600.,y:13000.};let i=40*a.columns+40;a.heights_cm[i]=0;a.heights_cm[i+1]=100;a.heights_cm[i+a.columns]=200;a.heights_cm[i+a.columns+1]=1000;let s=a.sample(q+P{x:1.,y:1.}).unwrap();assert!((s.height-0.75).abs()<1e-9);let s=a.sample(q+P{x:3.,y:3.}).unwrap();assert!((s.height-5.75).abs()<1e-9);}
    #[test]fn validation_rejects_truncated_or_malformed_maps(){let mut f=fixture();f["heightfield"]["heights"][0]=json!(1.);assert!(CoastalGeography::from_value(&f).is_err());let mut f=fixture();f["biomes"][0]=json!("unknown");assert!(CoastalGeography::from_value(&f).is_err());}
    #[test]fn real_slope_blocks_armor_and_hill_blocks_los(){let mut a=CoastalGeography::from_value(&fixture()).unwrap();let i=40*a.columns+40;a.heights_cm[i+1]=10000;a.heights_cm[i+a.columns+1]=10000;let q=P{x:14601.,y:13001.};assert_eq!(a.movement(q,"armor"),0.);assert!(!a.line_of_sight(q+P{x:-12.,y:0.},q+P{x:12.,y:0.},1.7));}
}
