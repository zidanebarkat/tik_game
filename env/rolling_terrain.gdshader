shader_type spatial;
render_mode unshaded, cull_disabled;

// Apply to a large, high-subdivision PlaneMesh (e.g. 60x60 segments) that
// surrounds your real, flat, collision-enabled arena floor. This mesh is
// purely visual — no collision needed, so the displacement cost is vertex-only
// and cheap even on old GPUs.
//
// The plane sits at base_y (slightly BELOW the real arena floor) and only
// rises into hills once it is past arena_radius, so the playable center stays
// flat while the horizon is faked into a huge rolling battlefield.

uniform sampler2D noise_tex : hint_default_black;
uniform sampler2D ground_tex : source_color;
uniform float base_y : hint_range(-20.0, 0.0) = -0.6;
uniform float hill_height : hint_range(0.0, 60.0) = 14.0;
uniform float noise_scale : hint_range(0.005, 1.0) = 0.02;
uniform float texture_tiling : hint_range(1.0, 64.0) = 10.0;
uniform float arena_radius : hint_range(20.0, 800.0) = 90.0;
uniform float hill_fade : hint_range(10.0, 800.0) = 260.0;

varying float height_out;

void vertex() {
	float h = texture(noise_tex, UV * noise_scale).r;
	// Flat within the arena, rising hills beyond it — no hole needed in the mesh.
	float dist = distance(VERTEX.xz, vec2(0.0));
	float rise = smoothstep(arena_radius, arena_radius + hill_fade, dist);
	VERTEX.y = base_y + h * hill_height * rise;
	height_out = h * rise;
}

void fragment() {
	// Cheap height-based gradient — no per-pixel texture sampling, which is the
	// dominant llvmpipe cost for a full-screen terrain backdrop.
	vec3 base = mix(vec3(0.34, 0.33, 0.28), vec3(0.56, 0.53, 0.46), height_out);
	ALBEDO = base;
	ROUGHNESS = 0.9;
}
