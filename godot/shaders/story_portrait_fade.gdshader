shader_type canvas_item;
uniform vec4 frame_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform float side_feather = 0.0;
void fragment() {
	vec2 local_uv = (UV - frame_region.xy) / max(frame_region.zw, vec2(0.00001));
	COLOR.a *= 1.0 - smoothstep(0.72, 1.0, local_uv.y);
	if (side_feather > 0.0) {
		float edges = smoothstep(0.0, side_feather, local_uv.x) * (1.0 - smoothstep(1.0 - side_feather, 1.0, local_uv.x));
		// Only long hair/arms near the lower crop can feather. Face and crown stay opaque.
		COLOR.a *= mix(1.0, edges, smoothstep(0.28, 0.45, local_uv.y));
	}
}
