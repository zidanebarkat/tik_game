extends CanvasLayer

var main_scene = null

func setup(ms) -> void:
	main_scene = ms
	$Center/VBox/StartButton.pressed.connect(_on_start_pressed)

func _on_start_pressed() -> void:
	visible = false
	if has_node("Center/VBox/LastResult"):
		$Center/VBox/LastResult.visible = false
	if main_scene and main_scene.has_method("start_game"):
		main_scene.start_game()

## Shows the outcome of the last finished fight on the menu screen.
func show_result(text: String) -> void:
	if has_node("Center/VBox/LastResult"):
		var label = $Center/VBox/LastResult
		label.text = text
		label.visible = not text.is_empty()
