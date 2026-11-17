shader_type canvas_item;
render_mode unshaded;
uniform float night_amount=0.0;
uniform bool shadow=false;
uniform float variant=0.0;
uniform float cloud_opacity=1.0;
uniform float overcast=0.0;
uniform float visual_time=0.0;
uniform vec2 quad_size=vec2(200.0,100.0);
uniform vec3 clear_zones[32];
uniform int clear_count=0;
float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7))+variant*17.13)*43758.5453);}
float noise(vec3 p){
 vec3 a=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
 float x0=mix(hash(a),hash(a+vec3(1,0,0)),f.x);
 float x1=mix(hash(a+vec3(0,1,0)),hash(a+vec3(1,1,0)),f.x);
 float x2=mix(hash(a+vec3(0,0,1)),hash(a+vec3(1,0,1)),f.x);
 float x3=mix(hash(a+vec3(0,1,1)),hash(a+vec3(1,1,1)),f.x);
 return mix(mix(x0,x1,f.y),mix(x2,x3,f.y),f.z);
}
float density(vec3 p){
 float mass=0.0;
 for(int i=0;i<7;i++){
  float fi=float(i);
  vec3 center=vec3((fi-3.0)*.19,(hash(vec3(fi,3.7,1))-.5)*.48,(hash(vec3(fi,5.1,2))-.5)*.25);
  vec3 radius=vec3(.26+hash(vec3(fi,5.2,3))*.13,.30+hash(vec3(fi,7.4,4))*.15,.28+hash(vec3(fi,9.4,5))*.13);
  vec3 v=(p-center)/radius;
  mass+=exp(-dot(v,v)*1.7)*.72;
 }
 vec3 q=p*7.0+vec3(visual_time*.015,0,-visual_time*.01);
 float billow=noise(q)*.64+noise(q*2.07+5.1)*.36;
 return max(0.0,mass-.16-billow*.23);
}
void fragment(){
 vec2 p=(UV-.5)*vec2(2.25,1.40);
 float opacity=0.0;
 vec3 radiance=vec3(0.0);
 vec3 sun=normalize(vec3(-.7,-.8,.75));
 for(int i=0;i<14;i++){
  float z=.8-float(i)*.115;
  vec3 sample_point=vec3(p+vec2(0,z*.12),z);
  float d=density(sample_point);
  float a=1.0-exp(-d*3.4);
  if(a>.001){
   if(!shadow){
   float light_density=density(sample_point+sun*.19);
   float light=exp(-light_density*3.7);
   float sky=clamp(z*.35+.66,0.0,1.0);
   vec3 cloud_color=mix(vec3(.48,.63,.75),vec3(1.0,.995,.96),clamp(light*.63+sky*.38,0.0,1.0));
   radiance+=(1.0-opacity)*a*cloud_color;
   }
   opacity+=(1.0-opacity)*a;
  }
 }
 vec3 base=radiance/max(opacity,.001);
 float alpha=opacity*cloud_opacity;
 if(shadow){COLOR=vec4(.025,.16,.25,alpha*.16);}
 else{
  for(int i=0;i<32;i++){if(i>=clear_count){break;}float distance=length(UV*quad_size-clear_zones[i].xy);alpha*=smoothstep(clear_zones[i].z*.40,clear_zones[i].z*1.65,distance);}
  base=mix(base,base*vec3(.67,.73,.80),overcast*.65);
  base=mix(base,base*vec3(.23,.35,.52),night_amount*.83);
  COLOR=vec4(base,alpha);
 }
}
