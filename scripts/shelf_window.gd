extends Window
## A window owned by this app. It neither discovers nor reads other applications.
signal sit_requested
signal leave_requested
signal preview_requested
var support_label: Label
var _dragging: bool = false
var _drag_cursor: Vector2i
var _drag_position: Vector2i

func _ready() -> void:
	title = "Hoshi — тестовое окно-полочка"
	min_size = Vector2i(540, 285)
	transparent = false
	transparent_bg = false
	transient = false
	var back := ColorRect.new()
	back.color = Color("f6f0f6")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var stripe := ColorRect.new()
	stripe.color = Color("baa1c3")
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 22.0
	stripe.mouse_default_cursor_shape = Control.CURSOR_MOVE
	stripe.gui_input.connect(_drag_input)
	back.add_child(stripe)
	var drag_hint := _label("Потяни за эту полосу — полочка поедет вместе с Хоши", 11, Color("41364a"))
	drag_hint.position = Vector2(12, 2)
	stripe.add_child(drag_hint)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	margin.add_theme_constant_override("margin_top", 32)
	back.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	box.add_child(_label("ПОЛОЧКА ХОШИ", 22, Color("89678e")))
	box.add_child(_label("Первые шаги в мир окон · 0.4", 13, Color("81768c")))
	box.add_child(_label("Подвигай окно за заголовок\nили измени его ширину.", 15, Color("41364a")))
	support_label = _label("Готовлю место для Хоши…", 12, Color("89678e"))
	box.add_child(support_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_add_button(row, "←", func(): position.x -= 55)
	_add_button(row, "→", func(): position.x += 55)
	_add_button(row, "Посадить", func(): sit_requested.emit())
	_add_button(row, "На пол", func(): leave_requested.emit())
	_add_button(row, "Примерочная", func(): preview_requested.emit())
	box.add_child(_label("Только это тестовое окно. Другие приложения не читаются.", 11, Color("81768c")))

func _label(text: String, font_size: int, color: Color) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func _add_button(row: HBoxContainer, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 32
	button.pressed.connect(action)
	row.add_child(button)

func outer_rect() -> Rect2i:
	if DisplayServer.get_name() == "headless":
		return Rect2i(position, size)
	var id: int = get_window_id()
	return Rect2i(DisplayServer.window_get_position_with_decorations(id), DisplayServer.window_get_size_with_decorations(id))

func _drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_cursor = DisplayServer.mouse_get_position()
			_drag_position = position

func _process(_delta: float) -> void:
	if not _dragging:
		return
	if (DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT) == 0:
		_dragging = false
		return
	position = _drag_position + DisplayServer.mouse_get_position() - _drag_cursor
