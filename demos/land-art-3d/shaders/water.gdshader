shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform float map_extent = 360.0;
uniform float cloud_cover = 0.3;
uniform float sea_state = 1.0;
uniform float sample_time = -1.0;
varying vec3 world_pos;
float clock_time() { return sample_time < 0.0 ? TIME : sample_time; }
float waves(vec2 p, float t) {
    return (sin(dot(p,vec2(.14,.21))-t*1.35)*.33
          +sin(dot(p,vec2(-.29,.19))-t*1.85)*.17
          +sin(dot(p,vec2(.59,.43))+t*2.2)*.055)*sea_state;
}
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float floor_y = texture(height_map, world_pos.xz/(map_extent*2.0)+vec2(.5)).r*100.0-32.0;
    VERTEX.y += waves(world_pos.xz,clock_time())*smoothstep(.0,2.0,-floor_y);
}
void fragment() {
    vec2 p=world_pos.xz;
    float t=clock_time();
    float floor_y = texture(height_map, p/(map_extent*2.0)+vec2(0.5)).r*100.0-32.0;
    float depth=max(0.0,-floor_y);
    vec3 shallow=vec3(0.19,0.74,0.70);
    vec3 deep=vec3(0.035,0.33,0.49);
    vec3 tint=mix(shallow,deep,smoothstep(0.0,12.0,depth));
    float n=texture(grain,p*0.028+vec2(t*0.006,-t*0.004)).r;
    tint*=mix(0.92,1.09,n);
    float caustic=pow(1.0-abs(sin(p.x*0.63+sin(p.y*0.71+t)*0.8+t*.65)),16.0);
    caustic*=pow(1.0-abs(sin(p.y*0.61+sin(p.x*.44-t*.7))),8.0);
    tint+=caustic*0.18*(1.0-smoothstep(0.0,6.0,depth));
    float ripple=waves(p,t);
    float foam=(1.0-smoothstep(0.10,0.60,abs(depth-.22-ripple*.32)))*step(.005,depth);
    // Depth contours advance shoreward; changing crest strength makes the wave
    // break and recede instead of painting a stationary white shore outline.
    float surf_phase=depth*1.65+t*1.42+n*.70;
    float breaker=pow(max(0.0,sin(surf_phase)),14.0)*smoothstep(.2,.8,depth)*(1.0-smoothstep(4.0,8.0,depth));
    breaker*=smoothstep(.24,.65,n)*(.65+sea_state*.18);
    float wake=pow(max(0.0,sin(dot(p,vec2(.14,.21))-t*1.35+n*.6)),24.0);
    wake*=smoothstep(.42,.67,n)*smoothstep(4.0,10.0,depth)*.20*sea_state;
    float glitter=pow(max(0.0,sin(p.x*2.8+t*1.9)*sin(p.y*3.2-t*2.1)),80.0);
    tint=mix(tint,vec3(.92,.99,.96),clamp(foam*.76+breaker*.91+wake,0.0,.92));
    tint+=glitter*.07;
    float cloud=smoothstep(.44,.72,texture(grain,p*.005+vec2(TIME*.0007,TIME*.0003)).r);
    ALBEDO=pow(tint,vec3(2.2))*(1.0-cloud*cloud_cover*.14);
    vec2 derivative=vec2(waves(p+vec2(.15,0),t)-waves(p-vec2(.15,0),t),waves(p+vec2(0,.15),t)-waves(p-vec2(0,.15),t))/.30;
    NORMAL=normalize((VIEW_MATRIX*vec4(-derivative.x,1.0,-derivative.y,0.0)).xyz);
    ROUGHNESS=.30;
    METALLIC=.05;
    SPECULAR=.025;
    ALPHA=mix(.52,.98,smoothstep(0.0,5.0,depth));
}
