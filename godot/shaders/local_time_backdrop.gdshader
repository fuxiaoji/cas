shader_type canvas_item;
render_mode unshaded;

uniform float local_hour:hint_range(0.0,24.0)=12.0;
uniform bool title_composition=false;
uniform float motion_time=0.0;

float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float glow(vec2 uv,vec2 center,float radius){return exp(-dot(uv-center,uv-center)/(radius*radius));}

void fragment(){
	vec4 original=texture(TEXTURE,UV);
	vec3 color=original.rgb;
	float dawn=smoothstep(4.7,5.3,local_hour)*(1.0-smoothstep(7.3,8.3,local_hour));
	float dusk=smoothstep(16.0,16.8,local_hour)*(1.0-smoothstep(18.5,19.3,local_hour));
	float night=max(1.0-smoothstep(4.5,5.5,local_hour),smoothstep(18.5,19.5,local_hour));
	float horizon=title_composition?.66:.48;
	float sky=1.0-smoothstep(horizon-.12,horizon,UV.y);
	float water=smoothstep(horizon,horizon+.04,UV.y);
	float blue=clamp((color.b-color.r)*4.0+.3,0.0,1.0);
	float brightness=dot(color,vec3(.2126,.7152,.0722));
	// The title source is painted at sunset. Daytime opens the blue sky and
	// removes the baked orange cast from clouds/water rather than showing dusk all day.
	if(title_composition){
		float daylight=smoothstep(7.0,8.0,local_hour)*(1.0-smoothstep(16.0,16.8,local_hour));
		vec3 day_color=original.rgb*vec3(1.12,1.26,1.34)+vec3(.025,.035,.045);
		float warm=clamp((original.r-original.b)*4.0,0.0,1.0);
		day_color=mix(day_color,vec3(.96,1.01,1.06)*(brightness+.16),warm*(sky+water*.36));
		day_color=mix(day_color,vec3(.28,.57,.77),sky*blue*.30);
		color=mix(color,day_color,daylight);
	}
	vec3 dawn_grade=mix(vec3(.78,.60,.69),vec3(1.12,.83,.60),1.0-UV.y);
	vec3 dusk_grade=mix(vec3(.52,.46,.81),vec3(1.13,.60,.35),smoothstep(.05,horizon,UV.y));
	color=mix(color,color*dawn_grade+vec3(.12,.045,.04)*sky,dawn*.9);
	color=mix(color,color*dusk_grade+vec3(.10,.035,.075)*sky,dusk*.94);
	// Moonlit blue shadows, warm highlights and lit architecture are separate layers.
	vec3 night_color=original.rgb*vec3(.18,.29,.50)+vec3(.008,.019,.045);
	night_color+=vec3(.035,.045,.09)*pow(max(brightness,0.0),2.0)*sky;
	color=mix(color,night_color,night*.94);
	// Sky chroma changes independently from land, including pale clouds at dawn.
	vec3 sky_dawn=mix(vec3(.61,.56,.84),vec3(1.0,.74,.56),smoothstep(0.0,horizon,UV.y));
	vec3 sky_dusk=mix(vec3(.27,.24,.51),vec3(1.0,.54,.32),smoothstep(0.0,horizon,UV.y));
	color=mix(color,sky_dawn,sky*blue*dawn*.32);
	color=mix(color,sky_dusk,sky*blue*dusk*.42);
	vec2 sun=vec2(title_composition?.64:.70,horizon-.13);
	vec2 moon=vec2(title_composition?.63:.72,.155);
	vec2 metric=vec2(float(textureSize(TEXTURE,0).x)/float(textureSize(TEXTURE,0).y),1.0);
	float sun_disc=1.0-smoothstep(.021,.023,length((UV-sun)*metric));
	float celestial_clear=sky*smoothstep(.05,.24,original.b-original.r+.12);
	color+=vec3(1.0,.55,.27)*glow(UV,sun,.13)*(dawn*.20+dusk*.34)*celestial_clear;
	color=mix(color,vec3(1.0,.90,.67),sun_disc*(dawn+dusk)*celestial_clear*.92);
	float moon_disc=1.0-smoothstep(.020,.022,length((UV-moon)*metric));
	float moon_cut=1.0-smoothstep(.019,.021,length((UV-moon-vec2(.007,-.005))*metric));
	color+=vec3(.24,.34,.55)*glow(UV,moon,.095)*night*celestial_clear*.5;
	color=mix(color,vec3(.88,.93,1.0),max(0.0,moon_disc-moon_cut)*night*celestial_clear);
	vec2 cells=floor(UV*vec2(100.0,65.0));
	vec2 star_center=(cells+vec2(.2+hash(cells)*.6,.2+hash(cells+6.0)*.6))/vec2(100.0,65.0);
	float star=1.0-smoothstep(.0003,.0009,length((UV-star_center)*metric));
	float star_pick=step(.965,hash(cells+13.7));
	color+=vec3(.68,.79,1.0)*star*star_pick*night*celestial_clear*(.6+.25*sin(motion_time*.65+hash(cells)*18.0));
	// A broken reflection path follows the sun or moon across actual blue water.
	float light_x=mix(sun.x,moon.x,night);
	float ripples=pow(max(0.0,sin(UV.y*430.0+sin(UV.x*65.0+motion_time*.3)*2.0+motion_time*.9)),9.0);
	float reflection=exp(-pow((UV.x-light_x)/(max(.014,(UV.y-horizon)*.20)),2.0))*water*blue*ripples;
	color+=mix(vec3(.40,.19,.04),vec3(.14,.23,.36),night)*reflection*(dawn*.7+dusk+night*.7);
	// Registered harbor lights use original building locations, not random land lights.
	float lamps=0.0;
	if(title_composition){
		lamps+=glow(UV,vec2(.918,.164),.009)*1.9;
		lamps+=glow(UV,vec2(.800,.648),.006)*.85;
		lamps+=glow(UV,vec2(.833,.650),.006)*.75;
		lamps+=glow(UV,vec2(.868,.641),.006)*.9;
		lamps+=glow(UV,vec2(.897,.625),.006)*.8;
	}else{
		lamps+=glow(UV,vec2(.969,.326),.008)*1.9;
		lamps+=glow(UV,vec2(.150,.257),.005)*.9;
		lamps+=glow(UV,vec2(.132,.300),.004)*.7;
		lamps+=glow(UV,vec2(.113,.290),.004)*.6;
		lamps+=glow(UV,vec2(.249,.410),.004)*.65;
		lamps+=glow(UV,vec2(.294,.426),.004)*.6;
		lamps+=glow(UV,vec2(.350,.449),.004)*.7;
	}
	color+=vec3(1.0,.58,.18)*lamps*clamp(night+dusk*.5,0.0,1.0);
	COLOR=vec4(color,original.a);
}
