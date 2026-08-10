shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 flash_color : source_color = vec4(1.0, 0.7, 0.35, 1.0);

void vertex() {
	// Always face the camera (billboard) so the burst reads from any angle.
	mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
	vec3 scale = vec3(
		length(mv[0].xyz),
		length(mv[1].xyz),
		length(mv[2].xyz)
	);
	mv[0].xyz = vec3(scale.x, 0.0, 0.0);
	mv[1].xyz = vec3(0.0, scale.y, 0.0);
	mv[2].xyz = vec3(0.0, 0.0, scale.z);
	MODELVIEW_MATRIX = mv;
}

void fragment() {
	float d = length(UV - vec2(0.5));
	float glow = smoothstep(0.5, 0.0, d);
	ALBEDO = flash_color.rgb;
	ALPHA = flash_color.a * glow;
}
