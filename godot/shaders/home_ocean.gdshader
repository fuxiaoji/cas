shader_type canvas_item;
uniform vec4 sea_color : source_color = vec4(0.16,0.59,0.69,1.0);
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){
	vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment(){
	vec2 p=UV*vec2(8.0,5.0);float t=TIME*.15;
	float broad=noise(p+vec2(t*.11,t*.05))*.65+noise(p*2.3-vec2(t*.08,t*.14))*.35;
	float ripple=sin(p.x*8.0+t*3.0+noise(p*3.0)*5.0)*sin(p.y*7.0-t*2.0);
	float glint=smoothstep(.88,.99,noise(p*19.0+vec2(t*1.8,-t*.7)))*smoothstep(.5,.85,noise(p*4.0));
	vec3 color=sea_color.rgb+vec3(.035,.08,.065)*(broad-.5)+vec3(.005,.012,.01)*ripple;
	color=mix(color,vec3(.80,.96,.88),glint*.12);
	COLOR=vec4(color,1.0);
}
