shader_type canvas_item;
render_mode unshaded;

// Original CAS masks. Open-source cover/swap/reveal references are documented in the receipt.
uniform float coverage:hint_range(0.0,1.0)=0.0;
uniform int style:hint_range(0,2)=0;
uniform bool reveal=false;
uniform vec4 cloud_color:source_color=vec4(.894,.953,.945,1.0);
uniform vec4 sea_color:source_color=vec4(.247,.510,.608,1.0);
uniform vec4 accent_color:source_color=vec4(.941,.796,.522,1.0);

float cloud_shape(vec2 uv,vec2 origin,float scale,float aspect){
	vec2 q=(uv-origin)*vec2(aspect,1.0)/scale;
	float a=length(q-vec2(-.58,.09))-.34;
	float b=length(q-vec2(-.18,-.16))-.48;
	float c=length(q-vec2(.30,-.05))-.40;
	float d=length(q-vec2(.64,.13))-.29;
	float base=length(q*vec2(.76,2.5))-.66;
	return 1.0-smoothstep(0.0,.018,min(min(a,b),min(min(c,d),base)));
}

void fragment(){
	vec2 p=UV;
	if(reveal){p.x=1.0-p.x;}
	float alpha=0.0;
	float rim=0.0;
	float aspect=SCREEN_PIXEL_SIZE.y/SCREEN_PIXEL_SIZE.x;
	if(style==0){
		// Rounded, scalloped cloud bank crossing the entire frame, followed by a sea ribbon.
		float lobes=.040*cos(p.y*36.0)+.025*cos(p.y*15.0+.8);
		float edge=-.13+coverage*1.26+lobes;
		alpha=1.0-smoothstep(edge-.008,edge+.008,p.x);
		rim=1.0-smoothstep(.012,.085,abs(p.x-edge));
	}else if(style==1){
		// Circular iris remains circular at every window aspect.
		vec2 centered=(p-vec2(.5))*vec2(aspect,1.0);
		float distance=length(centered)/length(vec2(aspect*.5,.5));
		float radius=1.07-coverage*1.14;
		alpha=smoothstep(radius-.008,radius+.008,distance);
		rim=1.0-smoothstep(.006,.045,abs(distance-radius));
	}else{
		// Broad diagonal paper sails, with a small stagger between strips.
		float strip=floor(p.y*5.0);
		float edge=-.35+coverage*1.75+p.y*.22-mod(strip,2.0)*.06;
		alpha=1.0-smoothstep(edge-.006,edge+.006,p.x);
		rim=1.0-smoothstep(.008,.050,abs(p.x-edge));
	}
	if(coverage<.0001){alpha=0.0;}
	if(coverage>.9999){alpha=1.0;rim=0.0;}
	// Original flat-color nautical card: fluffy cloud silhouettes and a two-layer wave.
	float sea_line=.66+.026*sin(UV.x*13.0)+.012*sin(UV.x*31.0+.4);
	float sea=smoothstep(sea_line-.0015,sea_line+.0015,UV.y);
	vec3 color=mix(cloud_color.rgb,sea_color.rgb,sea*.86);
	float back_line=.70+.018*sin(UV.x*16.0+1.2);
	float back_wave=smoothstep(back_line-.0015,back_line+.0015,UV.y);
	color=mix(color,sea_color.rgb,back_wave*.45);
	float shadow=max(cloud_shape(UV,vec2(.25,.303),.18,aspect),cloud_shape(UV,vec2(.77,.203),.125,aspect));
	float cloud=max(cloud_shape(UV,vec2(.25,.29),.18,aspect),cloud_shape(UV,vec2(.77,.19),.125,aspect));
	color=mix(color,cloud_color.rgb*.93,shadow*.40);
	color=mix(color,vec3(.99,.995,.97),cloud);
	float foam=1.0-smoothstep(.0005,.0025,abs(UV.y-(.78+.010*sin(UV.x*21.0))));
	float broken=step(.48,sin(UV.x*39.0)+.24*sin(UV.x*73.0));
	color=mix(color,mix(cloud_color.rgb,sea_color.rgb,.45),foam*broken*.45);
	color=mix(color,accent_color.rgb,rim*.65);
	// Pale editorial sun, nautical rays and paper flecks give the card an anime
	// intermission composition instead of a plain uniform loading rectangle.
	vec2 sun=(UV-vec2(.66,.29))*vec2(aspect,1.0);
	float sun_disk=1.0-smoothstep(.078,.081,length(sun));
	color=mix(color,accent_color.rgb,sun_disk*.65);
	float ray=pow(max(0.0,cos(atan(sun.y,sun.x)*12.0)),22.0);
	float ray_ring=smoothstep(.105,.11,length(sun))*(1.0-smoothstep(.15,.155,length(sun)));
	color=mix(color,accent_color.rgb,ray*ray_ring*.55);
	for(int i=0;i<8;i++){
		float f=float(i);
		vec2 center=vec2(.12+f*.109,.42+.025*sin(f*2.7));
		vec2 d=abs((UV-center)*vec2(aspect,1.0));
		float diamond=1.0-smoothstep(.003,.005,d.x+d.y);
		color=mix(color,accent_color.rgb,diamond*.6);
	}
	COLOR=vec4(color,alpha);
}
