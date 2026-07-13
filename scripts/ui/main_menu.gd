class_name MainMenu
extends Control

## Simple main menu. Entry point of the game and the destination the player
## returns to on death. Builds its UI in code so it needs no hand-authored layout.

const MAP_SCENE := "res://scenes/map/map.tscn"


func _ready() -> void:
	# Full-screen dark backdrop.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.06, 0.09, 1.0)
	add_child(bg)

	# Centered column of title + buttons.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	# Death notice (only when the player arrived here by dying).
	if GameState.player_died:
		var died := Label.new()
		died.text = "You Died"
		died.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		died.add_theme_font_size_override("font_size", 56)
		died.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15))
		vbox.add_child(died)

		var sub := Label.new()
		sub.text = "Your journey ends here."
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", 20)
		sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		vbox.add_child(sub)

		# Spacer between the notice and the buttons.
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 24)
		vbox.add_child(spacer)
	else:
		var title := Label.new()
		title.text = "CardGame"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 64)
		vbox.add_child(title)

		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 24)
		vbox.add_child(spacer)

	var start_label := "Try Again" if GameState.player_died else "New Run"
	var start_btn := Button.new()
	start_btn.text = start_label
	start_btn.custom_minimum_size = Vector2(240, 52)
	start_btn.pressed.connect(_on_new_run)
	vbox.add_child(start_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(240, 52)
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)


func _on_new_run() -> void:
	GameState.reset()
	get_tree().change_scene_to_file(MAP_SCENE)


func _on_quit() -> void:
	get_tree().quit()
