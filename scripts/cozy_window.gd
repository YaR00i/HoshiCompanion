extends "res://scripts/shelf_window.gd"
## Compact app-owned resting place. It never reads external application pixels.
signal activity_requested(command: String)
var decor: Control
var star_card: Button
var star_count: int = 0

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
	decor = load("res://scripts/cozy_decor.gd").new()
	decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(decor)
	panel.mouse_default_cursor_shape = Control.CURSOR_MOVE
	panel.gui_input.connect(_drag_input)
	var caption := _label("HOSHI  /  свой уголок", 11, Color("987da4"))
	caption.position = Vector2(22, 20)
	panel.add_child(caption)
	var heading := _label("Мой тихий уголок", 19, Color("675477"))
	heading.position = Vector2(22, 40)
	panel.add_child(heading)
	support_label = _label("Устраиваюсь поудобнее", 11, Color("99899f"))
	support_label.position = Vector2(22, 78)
	support_label.size.x = 202
	support_label.clip_text = true
	panel.add_child(support_label)
	var row := HBoxContainer.new()
	row.name = "Actions"
	row.position = Vector2(18, 112)
	row.add_theme_constant_override("separation", 5)
	panel.add_child(row)
	_add_button(row, "Блокнот", func(): activity_requested.emit("edge_sketch"))
	var fold_button := Button.new()
	fold_button.text = "✦"
	fold_button.custom_minimum_size = Vector2(32, 32)
	fold_button.tooltip_text = "Сложить бумажную звёздочку"
	fold_button.pressed.connect(func(): activity_requested.emit("edge_fold"))
	row.add_child(fold_button)
	_add_button(row, "Ножками", func(): activity_requested.emit("edge_mode_swing"))
	_add_button(row, "Откинуться", func(): activity_requested.emit("edge_mode_lean"))
	_add_button(row, "На пол", func(): leave_requested.emit())
	star_card = Button.new()
	star_card.name = "StarCard"
	star_card.flat = true
	star_card.focus_mode = Control.FOCUS_NONE
	star_card.position = Vector2(350, 39)
	star_card.size = Vector2(65, 62)
	star_card.tooltip_text = "Сложить первую звёздочку"
	star_card.pressed.connect(func(): activity_requested.emit("edge_admire_star" if star_count > 0 else "edge_fold"))
	panel.add_child(star_card)
	var close := Button.new()
	close.text = "×"
	close.position = Vector2(410, 14)
	close.size = Vector2(25, 26)
	close.pressed.connect(func(): close_requested.emit())
	panel.add_child(close)

func set_star_count(count: int, revision: int) -> void:
	star_count = clampi(count, 0, 3)
	if is_instance_valid(decor):
		decor.set_stars(star_count, revision)
	if is_instance_valid(star_card):
		star_card.tooltip_text = "Показать сложенную звёздочку" if star_count > 0 else "Сложить первую звёздочку"

func set_star_presenting(active: bool) -> void:
	if is_instance_valid(decor):
		decor.set_presenting(active)

func outer_rect() -> Rect2i:
	return Rect2i(position + Vector2i(8, 8), size - Vector2i(16, 16))
