extends Resource

@export var unit_name: String = ""
@export var description: String = ""
@export_group("Stats")
@export var max_health: float = 100.0
@export var armor: float = 0.0
@export var move_speed: float = 5.0
@export var attack_damage: float = 10.0
@export var attack_speed: float = 1.0
@export var attack_range: float = 2.0
@export var vision_radius: float = 15.0
@export_group("Economy")
@export var cost: int = 1
@export var population_value: int = 1
@export_group("Visuals")
@export var model: PackedScene
@export var animation_library: AnimationLibrary
@export_group("Effects")
@export var death_effect: PackedScene
@export var spawn_effect: PackedScene
@export_group("UI")
@export var portrait: Texture2D
@export var icon: Texture2D
