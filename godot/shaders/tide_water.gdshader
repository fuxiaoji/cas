shader_type canvas_item;
render_mode unshaded;
uniform vec2 world_origin=vec2(0.0);
uniform vec2 world_span=vec2(24000.0,14000.0);
uniform float visual_time=0.0;
uniform float seed=42.0;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
 vec2 w=world_origin+UV*world_span;float t=visual_time;
 float depth=noise(w*.00026+seed*.013),ripples=noise(w*.0015+vec2(t*.026,-t*.018));
 vec3 water=mix(vec3(.035,.35,.48),vec3(.10,.64,.64),depth)+vec3(.04,.13,.10)*smoothstep(.53,.78,ripples);
 float phase=w.x*.0037+w.y*.0011-t*.72+sin(w.y*.0023+t*.13)*.8;
 water=mix(water,vec3(.62,.91,.83),smoothstep(.987,.999,sin(phase))*smoothstep(.48,.72,ripples)*.21);
 vec2 grid=w*.003+vec2(t*.035,0),cell=floor(grid),d=fract(grid)-.5;
 float glint=exp(-dot(d*vec2(10.,20.),d*vec2(10.,20.)))*pow(max(0.,sin(t*1.4+hash(cell)*6.28)),5.)*step(.79,hash(cell));water+=vec3(.5,.7,.6)*glint*.45;
 // Drifting anime cloud banks; no volume ray marching or map photograph.
 vec2 c=w*.00017+vec2(t*.006,-t*.003)+seed*.001,q=fract(c)-.5;
 float bank=exp(-dot(q*vec2(3.8,6.0),q*vec2(3.8,6.0)));
 q=fract(c+vec2(.16,.04))-.5;bank+=exp(-dot(q*vec2(5.5,6.8),q*vec2(5.5,6.8)))*.7;
 q=fract(c+vec2(-.15,.04))-.5;bank+=exp(-dot(q*vec2(5.4,7.4),q*vec2(5.4,7.4)))*.65;
 COLOR=vec4(mix(water,vec3(.79,.89,.87),smoothstep(.5,1.22,bank+noise(c*9.)*.09)*.26),1.0);
}
