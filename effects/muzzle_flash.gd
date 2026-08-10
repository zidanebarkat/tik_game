extends Node3D

const FLASH_TIME := 0.09

var _timer: float = 0.0
var _light: OmniLight3D
var _quad: MeshInstance3D
var _mat: ShaderMaterial

func _ready() -> void:
	_light = $OmniLight3D
	_quad = $Flash
	_mat = _quad.material_override as ShaderMaterial
	_quad.visible = false
	_light.light_energy = 0.0

func flash() -> void:
	_timer = FLASH_TIME
	_quad.visible = true
	_quad.rotation.y = randf() * TAU
	_update_fade(1.0)

func _process(delta: float) -> void:
	if _timer <= 0.0:
		return
	_timer -= delta
	var k: float = clamp(_timer / FLASH_TIME, 0.0, 1.0)
	_update_fade(k)
	if _timer <= 0.0:
		_quad.visible = false
		_light.light_energy = 0.0

func _update_fade(k: float) -> void:
	if _mat:
		_mat.set_shader_parameter("flash_color", Color(1.0, 0.7, 0.35, k))
	if _light:
		_light.light_energy = 3.0 * k
	_quad.scale = Vector3.ONE * (0.7 + 0.3 * k)
