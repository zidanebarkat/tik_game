extends CanvasLayer

var main_scene = null

func setup(ms) -> void:
	main_scene = ms
	$Center/VBox/StartButton.pressed.connect(_on_start_pressed)

func _on_start_pressed() -> void:
	visible = false
	if main_scene and main_scene.has_method("start_game"):
		main_scene.start_game()
