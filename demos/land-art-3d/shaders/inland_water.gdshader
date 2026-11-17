shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D grain : repeat_enable, filter_linear_mipmap;
varying vec3 world_pos;
void vertex() { world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    float n=texture(grain,world_pos.xz*.045+vec2(TIME*.002,-TIME*.004)).r;
    float ripple=sin(world_pos.x*.9+world_pos.z*.63+TIME*1.5);
    vec3 tint=mix(vec3(.21,.39,.30),vec3(.40,.55,.35),n);
    tint+=pow(max(0.0,ripple),24.0)*.045;
    ALBEDO=pow(tint,vec3(2.2));
    ROUGHNESS=.36;
    SPECULAR=.08;
    ALPHA=.87;
}
