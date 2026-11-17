shader_type canvas_item;
void fragment() {
	// About 23px at the 720px reference window, with a steady dark reading area.
	COLOR.a *= smoothstep(0.0, 0.20, UV.y);
}
