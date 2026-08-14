class_name LightingPresets
extends RefCounted

enum Preset { DAY, SUNSET, NIGHT, RAIN }

const PRESET_ENV := {
	Preset.SUNSET: "res://env/presets/sunset_env.tres",
	Preset.NIGHT: "res://env/presets/night_env.tres",
	Preset.RAIN: "res://env/presets/rain_env.tres",
}

const PRESET_LIGHT := {
	Preset.SUNSET: {
		"direction": Vector3(0.4, 0.12, -0.9),
		"color": Color(1.0, 0.55, 0.25),
		"energy": 1.15,
		"shadow_enabled": true,
		"shadow_bias": 0.12,
		"shadow_blur": 4.0,
		"directional_shadow_max_distance": 200.0,
	},
	Preset.NIGHT: {
		"direction": Vector3(0.15, 0.5, -0.85),
		"color": Color(0.6, 0.7, 1.0),
		"energy": 0.65,
		"shadow_enabled": true,
		"shadow_bias": 0.12,
		"shadow_blur": 8.0,
		"directional_shadow_max_distance": 200.0,
	},
	Preset.RAIN: {
		"direction": Vector3(0.0, 0.75, -0.66),
		"color": Color(0.8, 0.83, 0.88),
		"energy": 0.75,
		"shadow_enabled": false,
		"shadow_bias": 0.12,
		"shadow_blur": 8.0,
		"directional_shadow_max_distance": 200.0,
	},
}

static func apply(world_env: WorldEnvironment, light: DirectionalLight3D, preset: int) -> bool:
	if world_env == null or light == null:
		return false
	if preset == Preset.DAY:
		return false
	var path: String = PRESET_ENV.get(preset, "")
	var env = load(path)
	if not env is Environment:
		push_warning("LightingPresets: missing env resource %s" % path)
		return false
	world_env.environment = env
	var cfg: Dictionary = PRESET_LIGHT.get(preset, {})
	if not cfg.is_empty():
		_apply_light(light, cfg)
	return true

static func _apply_light(light: DirectionalLight3D, cfg: Dictionary) -> void:
	light.global_basis = _basis_from_dir(cfg.get("direction", Vector3(0, -1, 0)))
	light.light_color = cfg.get("color", Color.WHITE)
	light.light_energy = cfg.get("energy", 1.0)
	light.shadow_enabled = cfg.get("shadow_enabled", true)
	light.shadow_bias = cfg.get("shadow_bias", 0.12)
	light.shadow_blur = cfg.get("shadow_blur", 0.0)
	light.directional_shadow_max_distance = cfg.get("directional_shadow_max_distance", 200.0)

static func _basis_from_dir(dir: Vector3) -> Basis:
	var z_axis := -dir.normalized()
	var up_ref := Vector3.UP if absf(z_axis.y) < 0.99 else Vector3.RIGHT
	var x_axis := up_ref.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)
