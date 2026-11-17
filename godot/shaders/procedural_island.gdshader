shader_type canvas_item;
render_mode unshaded;
uniform sampler2D shore_field : filter_linear;
uniform vec2 world_origin=vec2(0);
uniform vec2 world_span=vec2(1000);
uniform float island_seed=1.0;
uniform float night_amount=0.0;
uniform float overcast=0.0;
uniform float visual_time=0.0;
uniform int terrain_style=0;
uniform int expedition_style=0;
uniform bool urban_foundation=false;
uniform int ruin_count=0;
uniform vec3 ruin_zones[16];
float ruined(vec2 w){float value=0.0;for(int i=0;i<16;i++){if(i>=ruin_count){break;}value=max(value,1.0-smoothstep(ruin_zones[i].z*.58,ruin_zones[i].z,length(w-ruin_zones[i].xy)));}return value;}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7))+island_seed*3.13)*43758.5453);}
float noise(vec2 p){vec2 a=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(a),hash(a+vec2(1,0)),f.x),mix(hash(a+vec2(0,1)),hash(a+vec2(1)),f.x),f.y);}
float fbm(vec2 p){return noise(p)*.57+noise(p*2.07+3.1)*.28+noise(p*4.33+7.2)*.15;}
// Irregular broken floor slabs, instead of one uniform square tile per island.
vec2 fractured_slab(vec2 p){
 vec2 cell=floor(p),f=fract(p);float first=9.0,second=9.0;vec2 closest=cell;
 for(int x=-1;x<=1;x++){for(int y=-1;y<=1;y++){
  vec2 id=cell+vec2(float(x),float(y));
  vec2 site=vec2(float(x),float(y))+vec2(hash(id+11.0),hash(id+57.0))*.74+.13;
  float distance=length(site-f);
  if(distance<first){second=first;first=distance;closest=id;}else{second=min(second,distance);}
 }}
 return vec2(second-first,hash(closest+93.0));
}
float shore(vec2 uv){return texture(shore_field,clamp(uv,vec2(.001),vec2(.999))).r*max(world_span.x,world_span.y);}
vec2 crown(vec2 w){
 vec2 p=w/145.0, cell=floor(p);float height=0.0, cover=0.0;
 for(int x=-1;x<=1;x++){for(int y=-1;y<=1;y++){
  vec2 id=cell+vec2(float(x),float(y));
  vec2 center=id+vec2(.05)+vec2(hash(id+23.0),hash(id+79.0))*.9;
  float radius=.47+hash(id+51.0)*.25;
  vec2 offset=(p-center)/vec2(radius,radius*.85);
  float dist=length(offset);
  float leaf=noise(w*.045+id)*.23+.07*sin(atan(offset.y,offset.x)*5.0+hash(id)*6.0);
  float canopy=1.0-smoothstep(.62,1.0,dist+leaf);
  float grove=smoothstep(.40,.63,fbm(id*.38))*step(.24,hash(id+9.0));
  cover=max(cover,canopy*grove);
  height=max(height,pow(max(0.0,1.0-dist*dist),.6)*canopy*grove*(42.0+hash(id+67.0)*26.0));
 }}
 float growth=1.0;
 if(terrain_style>0){growth=(terrain_style==4 ? .22 : (terrain_style==1 ? .65 : .85))*(1.0-ruined(w));}
 if(expedition_style==4){growth*=.09;}
 if(expedition_style==3){growth*=.48;}
 if(urban_foundation){growth=0.0;}
 return vec2(height,cover)*growth;
}
float ground(vec2 w,float coast){
 float terrain=fbm(w*.0018);
 float edge=34.0+fbm(w*.005)*70.0;
 float plateau=smoothstep(edge-15.0,edge+9.0,coast);
 float hills=pow(smoothstep(.32,.82,terrain),1.5)*135.0;
 float value=plateau*(88.0+hills)+smoothstep(4.0,45.0,coast)*6.0;
 if(terrain_style>0){value*=terrain_style==1 ? .48 : (terrain_style==3 ? 1.2 : (terrain_style==4 ? .28 : 1.0));value=mix(value,12.0,ruined(w));}
 if(urban_foundation){value=smoothstep(0.0,9.0,coast)*5.0;}
 return value;
}
float height(vec2 w,vec2 uv){float coast=shore(uv);return ground(w,coast)+crown(w).x*smoothstep(95.0,135.0,coast);}
void fragment(){
 vec2 projected_world=world_origin+UV*world_span;
 // Oblique height-field projection: plateau and foliage rise above warm cliff faces.
 // The original Polygon2D still clips the entire result to the exact source shore.
 vec2 w=projected_world;
 vec2 surface_uv=UV;
 float surface_level=0.0;
 for(int step_index=0;step_index<7;step_index++){
  float z=240.0-float(step_index)*40.0;
  vec2 sample_world=projected_world-vec2(0,z*.70);
  vec2 sample_uv=(sample_world-world_origin)/world_span;
  float h=ground(sample_world,shore(sample_uv));
  if(h>=z){
   float low=z, high=z+40.0;
   for(int refine=0;refine<3;refine++){
    float mid=(low+high)*.5;
    vec2 q=projected_world-vec2(0,mid*.70);
    if(ground(q,shore((q-world_origin)/world_span))>=mid){low=mid;}else{high=mid;}
   }
   w=projected_world-vec2(0,low*.70);surface_uv=(w-world_origin)/world_span;surface_level=low;break;
  }
 }
 float coast=shore(surface_uv);
 float e=12.0;
 float hx=height(w+vec2(e,0),surface_uv+vec2(e/world_span.x,0))-height(w-vec2(e,0),surface_uv-vec2(e/world_span.x,0));
 float hy=height(w+vec2(0,e),surface_uv+vec2(0,e/world_span.y))-height(w-vec2(0,e),surface_uv-vec2(0,e/world_span.y));
 vec3 normal=normalize(vec3(-hx,-hy,e*2.0));
 float sunlight=clamp(dot(normal,normalize(vec3(-.55,.75,1.05))),0.0,1.0);
 float elevation=ground(w,coast);
 float cliff=(1.0-normal.z)*smoothstep(10.0,25.0,coast);
 float grain=fbm(w*.018);
 vec3 sand=mix(vec3(.78,.68,.47),vec3(.97,.89,.65),grain);
 vec3 rock=mix(vec3(.43,.40,.34),vec3(.85,.72,.56),grain);
 float grass_mask=smoothstep(87.0,99.0,elevation)*(1.0-smoothstep(.08,.33,cliff));
 vec3 grass=mix(vec3(.28,.43,.16),vec3(.62,.69,.27),fbm(w*.007));
 vec3 land=mix(sand,rock,smoothstep(26.0,43.0,coast));
 land=mix(land,grass,grass_mask);
 vec2 tree=crown(w);
 float forest=tree.y*smoothstep(95.0,135.0,coast);
 vec3 leaves=mix(vec3(.12,.31,.15),vec3(.43,.64,.22),noise(w*.035)*.6+noise(w*.09)*.4);
 land=mix(land,leaves,forest);
 if(terrain_style>0){
  float decay=ruined(w);
  float seams=smoothstep(.95,.995,abs(sin(w.x*.025)))*smoothstep(.5,.85,noise(w*.03));
  vec3 concrete=mix(vec3(.38,.44,.40),vec3(.67,.67,.53),grain);
  concrete=mix(concrete,vec3(.39,.29,.19),smoothstep(.65,.80,fbm(w*.013))*.5);
  concrete*=1.0-seams*.34;
  // Drowned city foundations are worn quays, not tiny tropical beaches under every block.
  if(urban_foundation){
   float wall=1.0-smoothstep(2.0,8.0,shore(UV));
   vec2 slab=fractured_slab(w/64.0);
   concrete=mix(vec3(.29,.37,.34),vec3(.55,.56,.45),grain*.90+slab.y*.10);
   float crack=(1.0-smoothstep(.004,.017,slab.x))*smoothstep(.47,.69,fbm(w*.018+173.0));
   concrete=mix(concrete,vec3(.13,.23,.23),crack*.50);
   float salt=smoothstep(.72,.91,fbm(w*.029));
   concrete=mix(concrete,vec3(.70,.68,.50),salt*.23);
   // Damp lower slabs, rust at exposed reinforcing bars and patches of algae.
   float wet=1.0-smoothstep(8.0,70.0,coast);
   concrete=mix(concrete,concrete*vec3(.59,.85,.80),wet*.58);
   float rust=smoothstep(.64,.88,noise(w*.043))*crack;
   concrete=mix(concrete,vec3(.40,.26,.14),rust*.40);
   concrete=mix(concrete,vec3(.12,.27,.28),wall*.75);
   float weeds=smoothstep(.70,.86,fbm(w*.025));
   concrete=mix(concrete,vec3(.29,.42,.26),weeds*.22);
   land=concrete;
  }else{land=mix(land,concrete,decay);}
 }
 if(expedition_style==4){
  vec3 basalt=mix(vec3(.16,.22,.23),vec3(.39,.40,.34),grain);
  float veins=(1.0-smoothstep(.025,.07,abs(sin(w.x*.015+noise(w*.009)*4.0))))*smoothstep(.58,.75,fbm(w*.012));
  basalt=mix(basalt,vec3(.54,.29,.14),veins*.45);
  land=mix(land,basalt,smoothstep(10.0,40.0,coast)*.92);
 }
 if(expedition_style==2){land=mix(land,land*vec3(.80,.87,1.03),ruined(w)*.55);}
 if(expedition_style==3){land=mix(land,land*vec3(.78,.88,.92),.33);}
 if(expedition_style==5){land=mix(land,land*vec3(1.04,.97,.88),ruined(w)*.48);}
 float cast=crown(w+vec2(-28.0,35.0)).y*(1.0-forest)*smoothstep(100.0,145.0,coast);
 land*=1.0-cast*.24;
 // Warm illuminated strata, cool crevices and irregular vegetation density.
 float fissure=smoothstep(.79,.94,noise(vec2(w.x*.035,w.y*.007)))*cliff;
 land*=1.0-fissure*.24;
 land*=.55+sunlight*.62;
 land=mix(land,land*vec3(.67,.73,.80),overcast*.6);
 land=mix(land,land*vec3(.22,.34,.52),night_amount);
 COLOR=vec4(land,1.0);
}
