shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D grain : repeat_enable, filter_linear_mipmap;
uniform float cloud_cover = 0.3;
varying vec3 world_pos;
varying float rock_slope;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; rock_slope=1.0-abs(NORMAL.y); }
void fragment() {
    float broad = texture(grain, world_pos.xz * 0.019).r;
    float fine = texture(grain, world_pos.xz * 0.52).r;
    float cloud = smoothstep(0.44, 0.72, texture(grain, world_pos.xz * 0.005 + vec2(TIME*0.0007, TIME*0.0003)).r);
    float steep=rock_slope;
    float strata=sin(world_pos.y*1.12+broad*1.4)*.5+.5;
    vec3 tint=COLOR.rgb*mix(.90,1.09,broad)*mix(.94,1.05,fine);
    tint*=mix(1.0,mix(.87,1.09,strata),smoothstep(.1,.65,steep)*.65);
    ALBEDO = pow(tint, vec3(2.2)) * (1.0-cloud*cloud_cover*0.18);
    ROUGHNESS = 0.91;
}
