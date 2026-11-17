shader_type canvas_item;
render_mode unshaded;
uniform float visual_time = 0.0;
uniform float rain_amount = 0.0;
uniform float fog_amount = 0.0;
uniform float night_amount = 0.0;
uniform vec2 viewport_size = vec2(1280,720);
uniform vec2 wind = vec2(.6,-.8);
float hash(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p) {
 vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void fragment() {
 vec2 pixel=UV*viewport_size;
 float t=visual_time;
 vec2 mist_uv=UV*vec2(3.4,2.0)+wind*t*.022;
 float mist=noise(mist_uv)*.65+noise(mist_uv*2.3+7.0)*.35;
 float fog=smoothstep(.2,.85,mist)*fog_amount*.60;
 // Diagonal rain has several depths, and travels continuously through the frame.
 vec2 slant=vec2(pixel.x-pixel.y*(.28+wind.x*.25),pixel.y);
 vec2 streak=slant/vec2(47,135)+vec2(0,-t*5.0);
 vec2 cell=floor(streak);
 vec2 f=fract(streak);
 float x=.2+hash(vec2(cell.x,0.0))*.6;
 float drop=(1.0-smoothstep(0.0,.035,abs(f.x-x)))*smoothstep(.1,.22,f.y)*(1.0-smoothstep(.47,.55,f.y));
 drop*=step(.45,hash(cell));
 vec3 mist_color=mix(vec3(.76,.86,.85),vec3(.18,.27,.38),night_amount);
 vec3 rain_color=mix(vec3(.74,.89,.94),vec3(.40,.55,.65),night_amount);
 float rain=drop*rain_amount*.35;
 float opacity=clamp(fog+rain,0.0,.56);
 COLOR=vec4(mix(mist_color,rain_color,rain/max(opacity,.001)),opacity);
}
