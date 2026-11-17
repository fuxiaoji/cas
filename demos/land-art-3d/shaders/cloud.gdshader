shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform float coverage=0.3;
void fragment() {
    vec2 q=UV-.5;
    float edge=1.0-smoothstep(.18,.52,length(q*vec2(.85,1.25)));
    float n=texture(grain,UV*1.6+vec2(TIME*.002,.0)).r;
    float billow=smoothstep(.28,.59,n+edge*.24);
    ALBEDO=mix(vec3(.81,.88,.90),vec3(.99,.99,.93),n);
    ALPHA=edge*billow*coverage;
}
