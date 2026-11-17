shader_type canvas_item;
void fragment(){
 float radius=length((UV-vec2(.5))/vec2(.5,.50));
 float ink=(1.0-smoothstep(.15,1.0,radius))*.20;
 COLOR=vec4(vec3(.035,.13,.18),ink*COLOR.a);
}
