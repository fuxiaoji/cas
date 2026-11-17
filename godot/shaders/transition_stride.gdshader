shader_type canvas_item;
// Small lower-body step deformation of the existing registered image; no source pixels edited.
uniform float stride_phase=0.0;
uniform float airborne=0.0;
uniform float stride_strength=1.0;
varying vec4 actor_tint;
void vertex(){actor_tint=COLOR;}
void fragment(){
 vec2 uv=UV;
 float lower=smoothstep(.68,.95,uv.y);
 float side=smoothstep(.45,.55,uv.x)*2.0-1.0;
 uv.x+=sin(stride_phase+side*.9)*lower*.012*(1.0-airborne*.55)*stride_strength;
 uv.y+=cos(stride_phase)*side*lower*.006*stride_strength;
 vec4 ink=texture(TEXTURE,uv);
 if(any(lessThan(uv,vec2(0.0)))||any(greaterThan(uv,vec2(1.0))))ink=vec4(0.0);
 COLOR=ink*actor_tint;
}
