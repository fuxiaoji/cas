shader_type canvas_item;
render_mode unshaded;
uniform vec2 world_origin = vec2(0.0);
uniform vec2 world_span = vec2(24000.0, 14000.0);
uniform bool affine_world = false;
uniform vec2 world_axis_x = vec2(24000.0, 0.0);
uniform vec2 world_axis_y = vec2(0.0, 14000.0);
uniform float island_style : hint_range(0.0, 1.0) = 0.0;
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
uniform float motion : hint_range(0.0, 1.0) = 1.0;
uniform float visual_time = 0.0;
uniform vec2 wind_direction = vec2(.8,.6);
uniform float wind_speed = 8.0;
uniform float overcast = 0.0;
uniform float rain_amount = 0.0;
uniform float fog_amount = 0.0;
uniform float roughness = 0.35;
uniform vec3 shoals[32];
uniform int shoal_count = 0;
uniform int adventure_theme = 0;
uniform int expedition_scene = 0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void fragment() {
 vec2 w=world_origin+UV*world_span;
 if(affine_world){w=world_origin+UV.x*world_axis_x+UV.y*world_axis_y;}
 float t=visual_time*motion;
 vec2 flow_direction=normalize(wind_direction+vec2(.001));
 vec2 lateral=vec2(-flow_direction.y,flow_direction.x);
 vec2 drift=vec2(sin(w.y*.00019+t*.045),cos(w.x*.00021-t*.035))*250.0;
 float sw=noise((w+drift)*0.00018+vec2(t*.009,0.0));
 float sw2=noise((w-drift*.6)*0.00043+vec2(-t*.004,t*.003));
 float wash=smoothstep(.18,.85,sw*.65+sw2*.35);
 vec3 water=mix(vec3(.045,.37,.60),vec3(.065,.61,.69),wash);
 water=mix(water,vec3(.18,.36,.43)+vec3(.025,.08,.07)*wash,overcast*.72);
 float shallow=0.0;
 for(int i=0;i<32;i++) {
  if(i>=shoal_count) {break;}
  float dist=length(w-shoals[i].xy);
  float shape=noise(w*.0012)*.22+.89;
  shallow=max(shallow,1.0-smoothstep(shoals[i].z*.85,shoals[i].z*2.7,dist*shape));
 }
 vec3 lagoon=mix(vec3(.09,.67,.65),vec3(.29,.86,.71),wash);
 // Procedural colour fields give each adventure coast an identity without a map photograph.
 if(adventure_theme==1){water=mix(vec3(.025,.40,.62),vec3(.06,.67,.72),wash);lagoon=mix(vec3(.10,.76,.68),vec3(.42,.91,.74),wash);}
 if(adventure_theme==2){water=mix(vec3(.055,.30,.51),vec3(.07,.53,.66),wash);lagoon=mix(vec3(.10,.61,.63),vec3(.31,.78,.71),wash);}
 if(adventure_theme==3){water=mix(vec3(.055,.23,.38),vec3(.11,.43,.55),wash);lagoon=mix(vec3(.13,.47,.53),vec3(.37,.66,.65),wash);}
 if(adventure_theme==4){water=mix(vec3(.08,.29,.36),vec3(.12,.47,.48),wash);lagoon=mix(vec3(.18,.56,.53),vec3(.42,.71,.60),wash);}
 if(adventure_theme>0){water=mix(water,vec3(.18,.36,.43)+vec3(.025,.08,.07)*wash,overcast*.72);}
 if(expedition_scene==1){water=mix(water,vec3(.10,.36,.42),.20);lagoon=mix(lagoon,vec3(.28,.58,.57),.15);}
 if(expedition_scene==2){water=mix(water,vec3(.15,.24,.40),.25);lagoon=mix(lagoon,vec3(.36,.45,.61),.16);}
 if(expedition_scene==3){water=mix(water,vec3(.10,.30,.40),.25);lagoon=mix(lagoon,vec3(.35,.58,.60),.12);}
 if(expedition_scene==4){water=mix(water,vec3(.08,.36,.39),.20);lagoon=mix(lagoon,vec3(.37,.63,.48),.15);}
 if(expedition_scene==5){water=mix(water,vec3(.06,.44,.51),.12);lagoon=mix(lagoon,vec3(.42,.75,.64),.15);}
 water=mix(water,mix(lagoon,lagoon*.76,overcast),shallow*.96);
 water+=vec3(.06,.13,.12)*smoothstep(.53,.81,noise((w+drift)*.00072+vec2(t*.007,-t*.006)))*(.35+shallow*.25);
 vec2 flow=w*.0015+vec2(t*.025,-t*.04);
 float a=noise(flow+vec2(noise(flow*.3),0));
 float b=noise(flow*1.87+vec2(t*.018,2));
 float ripple=smoothstep(.48,.65,a)*.025+smoothstep(.65,.84,b)*.035;
 water+=vec3(.15,.58,.50)*ripple*.22;
 float caustic=pow(1.0-abs(sin(w.x*.008+a*7.0+t*.13)*sin(w.y*.009+b*5.0-t*.2)),16.0);
 water+=vec3(.22,.34,.18)*caustic*shallow*.12;
 // Advancing wave fronts curve, break and rejoin; direction follows authoritative wind.
 float along=dot(w,flow_direction);
 float across=dot(w,lateral);
 float phase=along*.0042-t*(.9+wind_speed*.035)+sin(across*.0027+t*.12)*.48+sw2*2.0;
 float swell=sin(phase);
 float crest=smoothstep(.99,.9999,swell);
 float broken=smoothstep(.60,.78,noise(vec2(across*.004,along*.0012-t*.035)));
 float foam=crest*broken*(.065+roughness*.10);
 float trough=smoothstep(.35,.93,-swell);
 water*=1.0-trough*(.025+roughness*.025);
 water=mix(water,vec3(.57,.88,.88),foam);
 vec2 glitter=w*.0042+flow_direction*t*.12;
 vec2 cell=floor(glitter);
 vec2 offset=fract(glitter)-(vec2(.30)+vec2(hash(cell),hash(cell+37.0))*.40);
 float spot=exp(-dot(offset*vec2(9.0,15.0),offset*vec2(9.0,15.0)));
 float flicker=pow(max(0.0,sin(t*1.6+hash(cell)*6.283)),3.0);
 float cluster=smoothstep(.54,.78,noise(w*.00065+vec2(t*.025,0)));
 float glint=spot*flicker*cluster*(1.0-overcast*.87);
 water=mix(water,vec3(.82,.98,.94),glint*.60);
 // Rain circles are local wavelets, not persistent map markings.
 vec2 drops=w*.0036;
 vec2 dc=floor(drops);
 float age=fract(t*1.3+hash(dc)*7.0);
 vec2 drop_center=vec2(.2)+vec2(hash(dc+41.0),hash(dc+23.0))*.6;
 float radius=length(fract(drops)-drop_center);
 float ring=(1.0-smoothstep(.012,.038,abs(radius-age*.47)))*(1.0-age);
 water+=vec3(.13,.22,.23)*ring*rain_amount*.22*step(.91,hash(dc+8.0));
 vec3 moon=mix(vec3(.022,.10,.22),vec3(.06,.25,.35),wash);
 moon+=vec3(.12,.20,.24)*(glint*.3+foam*.40);
 water=mix(water,moon,night_amount);
 // Clear anime water uses broad colour masses, sparse moving highlights and
 // a soft world-anchored cloud shadow. Existing modes keep their own material.
 vec3 clean=mix(vec3(.035,.43,.64),vec3(.10,.68,.73),wash);
 clean=mix(clean,mix(vec3(.12,.75,.73),vec3(.37,.86,.76),wash),shallow*.85);
 clean=mix(clean,vec3(.22,.43,.52),overcast*.52);
 clean=mix(clean,vec3(.78,.98,.93),foam*.65+glint*.52);
 clean+=vec3(.09,.15,.08)*caustic*shallow*.15;
 // Small waves remain visible when the camera is near a company. Derivative
 // fade removes sub-pixel crests in the kilometre overview instead of aliasing.
 float close_detail=1.0-smoothstep(3.0,18.0,length(fwidth(w)));
 float fine_phase=along*.19-t*(1.6+wind_speed*.04)+noise(w*.027+flow_direction*t*.05)*2.2;
 float fine_swell=sin(fine_phase);
 float fine_break=smoothstep(.55,.8,noise(vec2(across*.055,along*.014-t*.10)));
 clean+=vec3(.035,.062,.050)*fine_swell*close_detail;
 clean=mix(clean,vec3(.74,.96,.90),smoothstep(.94,.999,fine_swell)*fine_break*close_detail*.20);
 float cloud=smoothstep(.56,.79,noise((w-flow_direction*t*11.0)*.00043));
 clean*=1.0-cloud*(.06+overcast*.08);
 clean=mix(clean,moon,night_amount);
 water=mix(water,clean,island_style);
 COLOR=vec4(water,1.0);
}
