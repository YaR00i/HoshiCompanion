extends "res://scripts/shelf_window.gd"
## Compact app-owned resting place. It never reads external application pixels.
signal activity_requested(action: int)

func _ready() -> void:
	title = "Уютный уголок Хоши"
	min_size = Vector2i(460, 170)
	size = min_size
	borderless = true
	unresizable = true
	unfocusable = true
	always_on_top = true
	transparent = true
	transparent_bg = true
	transient = false
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 8
	panel.offset_top = 8
	panel.offset_right = -8
	panel.offset_bottom = -8
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff4e8")
	style.border_color = Color("bea7ca")
	style.set_border_width_all(2)
	style.border_width_top = 5
	style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var decor: Control = load("res://scripts/cozy_decor.gd").new()
	decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(decor)
	panel.mouse_default_cursor_shape = Control.CURSOR_MOVE
	panel.gui_input.connect(_drag_input)
	var caption := _label("HOSHI  /  свой уголок", 11, Color("987da4"))
	caption.position = Vector2(22, 20)
	panel.add_child(caption)
	var heading := _label("Побуду рядом", 19, Color("675477"))
	heading.position = Vector2(22, 40)
	panel.add_child(heading)
	support_label = _label("Устраиваюсь поудобнее", 11, Color("99899f"))
	support_label.position = Vector2(22, 78)
	support_label.size.x = 172
	support_label.clip_text = true
	panel.add_child(support_label)
	var row := HBoxContainer.new()
	row.position = Vector2(18, 112)
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	_add_button(row, "Ножками", func(): activity_requested.emit(302))
	_add_button(row, "Откинуться", func(): activity_requested.emit(303))
	_add_button(row, "На пол", func(): leave_requested.emit())
	var close := Button.new()
	close.text = "×"
	close.position = Vector2(410, 14)
	close.size = Vector2(25, 26)
	close.pressed.connect(func(): close_requested.emit())
	panel.add_child(close)

func outer_rect() -> Rect2i:
	return Rect2i(position + Vector2i(8, 8), size - Vector2i(16, 16))
