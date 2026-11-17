shader_type spatial;
render_mode cull_disabled, diffuse_burley;
varying vec3 world_pos;
void vertex() {
    world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    VERTEX.x+=sin(TIME*1.7+world_pos.x*.21+world_pos.z*.13)*VERTEX.y*.16;
}
void fragment() { ALBEDO=pow(COLOR.rgb,vec3(2.2)); ROUGHNESS=.95; }
