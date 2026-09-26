extends PopupPanel

signal action_requested(command: String)
signal advanced_requested(position: Vector2i)

const Commands = preload("res://scripts/hoshi_commands.gd")
const HEADER = preload("res://assets/ui/hoshi_menu_header.svg")
const SWITCH_ON = preload("res://assets/ui/switch_on.svg")
const SWITCH_OFF = preload("res://assets/ui/switch_off.svg")
const INK: Color = Color("3b3449")
const MUTED: Color = Color("82798f")
const PLUM: Color = Color("665479")
const GOLD: Color = Color("c4a36e")
const WIDTH: int = 390
const HEIGHT: int = 622

var status_label: Label
var voice_button: Button
var walk_button: Button
var stop_button: Button
var activity_pick: OptionButton
var autonomy_check: CheckButton
var rest_check: CheckButton

func _ready() -> void:
	name = "HoshiQuickMenu"
	size = Vector2i(WIDTH, HEIGHT)
	min_size = Vector2i(WIDTH, HEIGHT)
	max_size = Vector2i(WIDTH, HEIGHT)
	var popup_theme := Theme.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("fffaf5")
	frame.border_color = Color("d9c5cb")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(20)
	frame.shadow_color = Color(0.16, 0.11, 0.24, 0.20)
	frame.shadow_size = 12
	popup_theme.set_stylebox("panel", "PopupPanel", frame)
	theme = popup_theme

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	var header := Control.new()
	header.custom_minimum_size.y = 94
	root.add_child(header)
	var art := TextureRect.new()
	art.texture = HEADER
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header.add_child(art)
	var title := _label("✦  Хоши", 24, Color("fffaf5"))
	title.position = Vector2(21, 18)
	header.add_child(title)
	var tagline := _label("Рядом, пока ты работаешь", 12, Color("f3e8f3"))
	tagline.position = Vector2(23, 53)
	header.add_child(tagline)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 17)
	margin.add_theme_constant_override("margin_right", 17)
	margin.add_theme_constant_override("margin_top", 13)
	margin.add_theme_constant_override("margin_bottom", 12)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	voice_button = _button("♪  Поговорить через ChatGPT  ↗", "talk_voice", Color("f5e5ec"), 53)
	voice_button.tooltip_text = "Открыть ChatGPT в браузере. В ChatGPT нажми Voice, затем включи расширение Хоши на этой вкладке."
	column.add_child(voice_button)
	var text_chat := _button("Открыть текстовый чат  ↗", "talk_text", Color("fffdfb"), 36)
	text_chat.tooltip_text = "Открыть ChatGPT в браузере без запуска голосовой связи Хоши."
	column.add_child(text_chat)
	column.add_child(_label("Голос включается на открытой вкладке ChatGPT", 11, MUTED))
	status_label = _label("", 12, PLUM)
	status_label.custom_minimum_size.y = 22
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(status_label)
	column.add_child(_label("МЕСТА И ДВИЖЕНИЕ", 11, MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	column.add_child(grid)
	for item in [["☁  Мой уголок", "cozy_corner"], ["▣  Выбрать окно", "pick_window"], ["✦  Пройтись", "walk"], ["○  Остановиться", "stop"]]:
		var button := _button(str(item[0]), str(item[1]), Color("fffdfb"), 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
		if str(item[1]) == "walk":
			walk_button = button
		elif str(item[1]) == "stop":
			stop_button = button

	var activity_row := HBoxContainer.new()
	activity_row.add_theme_constant_override("separation", 10)
	column.add_child(activity_row)
	activity_row.add_child(_label("Ритм дня", 12, INK))
	activity_pick = OptionButton.new()
	activity_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option in ["Тихая", "Обычная", "Игривая"]:
		activity_pick.add_item(option)
	activity_pick.item_selected.connect(func(index: int): action_requested.emit(Commands.ACTIVITY_CHOICES[index]))
	activity_row.add_child(activity_pick)
	var divider := HSeparator.new()
	divider.modulate = GOLD.lightened(0.35)
	column.add_child(divider)
	autonomy_check = _toggle("Самостоятельность", "toggle_autonomy")
	rest_check = _toggle("Сама выбирает отдых", "toggle_auto_rest")
	column.add_child(autonomy_check)
	column.add_child(rest_check)
	var more := _button("Все действия и настройки  ›", "", Color("eee8f3"), 38)
	more.pressed.connect(_show_advanced)
	column.add_child(more)

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(value: String, action: String, fill: Color, height: int) -> Button:
	var button := Button.new()
	button.text = value
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = height
	for kind in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = fill if kind == "normal" else (fill.darkened(0.045) if kind in ["hover", "pressed"] else fill)
		style.border_color = Color("dfd0d5")
		style.set_border_width_all(1 if kind != "focus" else 0)
		style.set_corner_radius_all(13)
		style.content_margin_left = 13
		style.content_margin_right = 12
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		button.add_theme_stylebox_override(kind, style)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", PLUM)
	button.add_theme_color_override("font_pressed_color", PLUM)
	button.add_theme_color_override("font_disabled_color", MUTED)
	if not action.is_empty():
		button.pressed.connect(func():
			hide()
			action_requested.emit(action))
	return button

func _toggle(value: String, action: String) -> CheckButton:
	var item := CheckButton.new()
	item.text = value
	item.custom_minimum_size.y = 27
	item.add_theme_color_override("font_color", INK)
	item.add_theme_icon_override("checked", SWITCH_ON)
	item.add_theme_icon_override("unchecked", SWITCH_OFF)
	item.add_theme_icon_override("checked_disabled", SWITCH_ON)
	item.add_theme_icon_override("unchecked_disabled", SWITCH_OFF)
	item.toggled.connect(func(_enabled: bool): action_requested.emit(action))
	return item

func set_snapshot(state, label_text: String, can_walk: bool, can_stop: bool) -> void:
	status_label.text = "✦  " + (label_text if not label_text.is_empty() else state.state_label())
	walk_button.disabled = not can_walk
	stop_button.disabled = not can_stop
	activity_pick.select(["quiet", "normal", "playful"].find(state.activity))
	autonomy_check.set_pressed_no_signal(state.autonomy_enabled)
	rest_check.set_pressed_no_signal(state.rest_enabled)

func open_at(point: Vector2i) -> void:
	var screen: int = DisplayServer.get_screen_from_rect(Rect2(point, Vector2.ONE))
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen if screen >= 0 else DisplayServer.SCREEN_PRIMARY)
	var x: int = clampi(point.x, usable.position.x + 8, usable.end.x - WIDTH - 8)
	var y: int = clampi(point.y, usable.position.y + 8, usable.end.y - HEIGHT - 8)
	popup(Rect2i(Vector2i(x, y), Vector2i(WIDTH, HEIGHT)))

func _show_advanced() -> void:
	var at: Vector2i = position + Vector2i(18, 76)
	hide()
	advanced_requested.emit(at)
