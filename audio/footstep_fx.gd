extends Node
## FootstepFX: a single shared node that turns unit footstep events into cheap
## surface-aware feedback. One pooled set of AudioStreamPlayer3D nodes serves
## every unit (no per-unit audio nodes), plus one reused CPUParticles3D dust
## burst. All sounds are generated procedurally (ProceduralFootsteps).
##
## Static accessor works in normal runs and in `-s` test runs, mirroring the
## RegistryAccess pattern.

class_name FootstepFX

const SURFACES := ["stone", "dirt", "grass"]
const HEAR_RADIUS := 55.0
const PLAYER_COUNT := 12
const STEP_VOLUME := -6.0
const PARTICLE_AMOUNT := 8

static var _instance: FootstepFX = null

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer3D] = []
var _rr := 0
var _particles: CPUParticles3D = null

# Introspection for tests / debugging.
var play_count := 0
var last_surface := ""

static func get_instance() -> FootstepFX:
	if _instance and is_instance_valid(_instance) and _instance.is_inside_tree():
		return _instance
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		var existing: Node = tree.root.get_node_or_null("FootstepFX")
		if existing:
			_instance = existing as FootstepFX
			return _instance
		var fx := FootstepFX.new()
		fx.name = "FootstepFX"
		tree.root.add_child(fx)
		_instance = fx
		return _instance
	return null

func _ready() -> void:
	for s in SURFACES:
		_streams[s] = ProceduralFootsteps.make_wav(s)
	for i in PLAYER_COUNT:
		var p := AudioStreamPlayer3D.new()
		p.max_polyphony = 2
		p.max_distance = HEAR_RADIUS * 2.5
		p.unit_size = 8.0
		add_child(p)
		_players.append(p)
	_build_particles()

func _build_particles() -> void:
	_particles = CPUParticles3D.new()
	_particles.one_shot = true
	_particles.emitting = false
	_particles.amount = PARTICLE_AMOUNT
	_particles.lifetime = 0.4
	_particles.explosiveness = 0.9
	_particles.local_coords = false
	_particles.direction = Vector3(0, 1, 0)
	_particles.spread = 45.0
	_particles.initial_velocity_min = 0.6
	_particles.initial_velocity_max = 1.5
	_particles.gravity = Vector3(0, -3.0, 0)
	_particles.scale_amount_min = 0.12
	_particles.scale_amount_max = 0.3
	_particles.damping_min = 1.0
	_particles.damping_max = 3.0
	add_child(_particles)

## Emits one step at `pos`. Surface lookup is cheap; audio/particles only fire
## when a camera is nearby, so 80+ unit armies cost almost nothing when the
## camera is far away.
func play_step(pos: Vector3, surface: String) -> void:
	var key := surface if _streams.has(surface) else "stone"
	last_surface = key
	play_count += 1

	var near := true
	var viewport := get_viewport()
	if viewport:
		var cam := viewport.get_camera_3d()
		if cam and cam.global_position.distance_to(pos) > HEAR_RADIUS:
			near = false
	if not near:
		return

	var player := _players[_rr]
	_rr = (_rr + 1) % _players.size()
	player.global_position = pos
	player.stream = _streams[key]
	player.pitch_scale = randf_range(0.92, 1.12)
	player.volume_db = STEP_VOLUME + randf_range(-3.0, 1.0)
	player.play()

	if _particles:
		_particles.global_position = pos + Vector3(0, 0.05, 0)
		_particles.color = _surface_color(key)
		_particles.restart()

func _surface_color(kind: String) -> Color:
	match kind:
		"dirt":
			return Color(0.45, 0.32, 0.22, 0.6)
		"grass":
			return Color(0.42, 0.5, 0.28, 0.5)
		_:
			return Color(0.5, 0.48, 0.45, 0.55)
