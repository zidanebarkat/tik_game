shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// A flipbook spritesheet of a marching/fighting soldier, e.g. 4x4 grid of frames.
uniform sampler2D soldier_tex : source_color;
uniform int frame_columns : hint_range(1, 16) = 4;
uniform int frame_rows : hint_range(1, 16) = 4;
uniform float frames_per_second : hint_range(1.0, 30.0) = 8.0;

varying float anim_phase;

void vertex() {
	// Y-axis billboard: rotate to face the camera around the vertical axis only,
	// so troops stay upright on the ground instead of tilting like a sprite.
	mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
	vec3 scale = vec3(
		length(mv[0].xyz),
		length(mv[1].xyz),
		length(mv[2].xyz)
	);
	mv[0].xyz = vec3(scale.x, 0.0, 0.0);
	mv[2].xyz = vec3(0.0, 0.0, scale.z);
	MODELVIEW_MATRIX = mv;
	// Per-instance frame offset so every soldier isn't animating in lockstep —
	// INSTANCE_ID gives a cheap pseudo-random offset with no CPU work.
	anim_phase = float(INSTANCE_ID) * 1.7;
}

void fragment() {
	float total_frames = float(frame_columns * frame_rows);
	float t = TIME * frames_per_second + anim_phase;
	float frame = mod(floor(t), total_frames);

	float col = mod(frame, float(frame_columns));
	float row = floor(frame / float(frame_columns));

	vec2 frame_uv = (UV + vec2(col, row)) / vec2(float(frame_columns), float(frame_rows));

	vec4 tex = texture(soldier_tex, frame_uv);
	if (tex.a < 0.5) {
		discard;
	}
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}
