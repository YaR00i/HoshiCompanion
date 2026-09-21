extends Control

signal action_requested(action: int)

var panel: PanelContainer
var backdrop: ColorRect
var subtitle: Label
var status: Label
var hint: Label
var note: Label
var loading: Label
var look_check: CheckButton
var motion_check: CheckButton
var hair_check: CheckButton
var sleep_button: Button
var walk_button: Button
var stop_button: Button
var sit_button: Button
var stand_button: Button
var rest_check: CheckButton
var _posture_available: bool = false
var autonomy_check: CheckButton
var walk_check: CheckButton
var activity_pick: OptionButton
var place_pick: OptionButton
var edge_pick: OptionButton
var _walk_available: bool = false
var menu: PopupMenu
var bubble: PanelContainer
var bubble_label: Label
var _bubble_left: float = 0.0
var bubbles_enabled: bool = true
var _preview: bool = true
var shelf_active: bool = false

const INK: Color = Color("3b3449")
const MUTED: Color = Color("82798f")
const PLUM: Color = Color("8a688f")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme: Theme = Theme.new()
	ui_theme.default_font_size = 14
	ui_theme.set_color("font_color", "Label", INK)
	ui_theme.set_color("font_color", "Button", INK)
	ui_theme.set_color("font_hover_color", "Button", INK)
	ui_theme.set_color("font_pressed_color", "Button", INK)
	for kind in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color("f6f0f7") if kind == "normal" else Color("ecdfef")
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_left = 10
		style.corner_radius_bottom_right = 10
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		ui_theme.set_stylebox(kind, "Button", style)
	theme = ui_theme
	_build_panel()
	_build_bubble()
	_build_menu()
	loading = _label("Загружаю твою модель…", 17)
	loading.position = Vector2(35, 28)
	loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(loading)

func _label(text: String, font_size: int = 14, color: Color = INK) -> Label:
	var item: Label = Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func _button(text: String, action: int) -> Button:
	var item: Button = Button.new()
	item.text = text
	item.custom_minimum_size.y = 32
	item.pressed.connect(_emit_action.bind(action))
	return item

func _emit_action(action: int) -> void:
	action_requested.emit(action)

func _on_toggle(_enabled: bool, action: int) -> void:
	action_requested.emit(action)

func _check(text: String, action: int) -> CheckButton:
	var item: CheckButton = CheckButton.new()
	item.text = text
	item.custom_minimum_size.y = 30
	item.add_theme_color_override("font_color", INK)
	item.toggled.connect(_on_toggle.bind(action))
	return item

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(580.0, 20.0)
	panel.size = Vector2(300.0, 580.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("fffdfb")
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	panel.add_child(outer)
	outer.add_child(_label("HOSHI", 28, PLUM))
	outer.add_child(_label("МИНИ-КОМПАНЬОН · 3D / 0.5.1", 11, MUTED))
	subtitle = _label("VRoid → VRM 1.0 → Godot", 12)
	outer.add_child(subtitle)
	status = _label("Загрузка…", 13, PLUM)
	outer.add_child(status)
	# More features must not push Close or the walking controls off the window.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 5)
	scroll.add_child(box)
	var reactions: GridContainer = GridContainer.new()
	reactions.columns = 2
	reactions.add_theme_constant_override("h_separation", 6)
	reactions.add_theme_constant_override("v_separation", 6)
	box.add_child(reactions)
	for item in [["Пройтись", 30], ["Стоп", 31], ["Сесть", 32], ["Встать", 33], ["Погладить", 11], ["Помахать", 10], ["Улыбка", 21], ["Дремать", 12]]:
		var button: Button = _button(str(item[0]), int(item[1]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reactions.add_child(button)
		match int(item[1]):
			12: sleep_button = button
			30: walk_button = button
			31: stop_button = button
			32: sit_button = button
			33: stand_button = button
	box.add_child(_button("Выбрать окно · 4 секунды", 42))
	box.add_child(_button("Полочка — попробовать", 40))
	box.add_child(_button("Мой уютный уголок", 43))
	var activity_row: HBoxContainer = HBoxContainer.new()
	activity_row.add_child(_label("Активность", 12, MUTED))
	activity_pick = OptionButton.new()
	activity_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for text_value in ["Тихая", "Обычная", "Игривая"]:
		activity_pick.add_item(text_value)
	activity_pick.item_selected.connect(_on_activity_selected)
	activity_row.add_child(activity_pick)
	box.add_child(activity_row)
	var place_row := HBoxContainer.new()
	place_row.add_child(_label("Где отдыхать", 12, MUTED))
	place_pick = OptionButton.new()
	place_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for title_value in ["Только вручную", "Свой уголок", "Окна → уголок"]:
		place_pick.add_item(title_value)
	place_pick.item_selected.connect(func(index: int): action_requested.emit(210 + index))
	place_row.add_child(place_pick)
	box.add_child(place_row)
	var edge_row := HBoxContainer.new()
	edge_row.add_child(_label("На краю", 12, MUTED))
	edge_pick = OptionButton.new()
	edge_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for title_value in ["Сама выбирает", "Спокойно", "Ножками", "Откинуться", "Посмотреть вниз"]:
		edge_pick.add_item(title_value)
	edge_pick.item_selected.connect(func(index: int): action_requested.emit(300 + index))
	edge_row.add_child(edge_pick)
	box.add_child(edge_row)
	autonomy_check = _check("Самостоятельность", 126)
	rest_check = _check("Самостоятельный отдых", 127)
	walk_check = _check("Самостоятельные прогулки", 125)
	look_check = _check("Внимание к курсору", 120)
	motion_check = _check("Мягкие движения", 121)
	hair_check = _check("Движение волос", 122)
	for item in [autonomy_check, walk_check, rest_check, look_check, motion_check, hair_check]:
		box.add_child(item)
	walk_check.tooltip_text = "Автоматически гуляет только у нижнего края, не в тихом режиме. Кнопка «Пройтись» работает отдельно."
	autonomy_check.tooltip_text = "Выключено: только ручные действия и обычный взгляд за курсором."
	outer.add_child(_button("На рабочий стол", 101))
	box.add_child(_button("Вернуть вид спереди", 141))
	hint = _label("Клик — погладить · двойной — взмах\nW — пройтись · C — сесть/встать\nКолесо — масштаб · ПКМ — меню", 11, MUTED)
	box.add_child(hint)
	note = _label("Локально, без ИИ и голоса.", 11, MUTED)
	box.add_child(note)
	outer.add_child(_button("Закрыть", 199))

func _on_activity_selected(index: int) -> void:
	action_requested.emit(200 + index)

func _build_bubble() -> void:
	bubble = PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.98, 0.95, 0.96)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	bubble.add_theme_stylebox_override("panel", style)
	bubble_label = _label("Привет!", 13, INK)
	bubble.add_child(bubble_label)
	add_child(bubble)
	bubble.hide()

func say(text: String) -> void:
	if not bubbles_enabled:
		return
	bubble_label.text = text
	bubble.reset_size()
	_bubble_left = 2.8
	bubble.show()

func tick(delta: float, head_point: Vector2, frame_size: Vector2) -> void:
	_bubble_left = maxf(0.0, _bubble_left - delta)
	bubble.visible = _bubble_left > 0.0 and bubbles_enabled
	if bubble.visible:
		# Keep desktop text inside the stable native window region.
		bubble.position = Vector2(
			clampf(head_point.x - bubble.size.x * 0.5, frame_size.x * 0.25, maxf(frame_size.x * 0.25, frame_size.x * 0.75 - bubble.size.x)),
			maxf(frame_size.y * 0.04, head_point.y - 65.0)
		)

func set_preview(value: bool) -> void:
	_preview = value
	panel.visible = value

func model_ready(name_value: String, report: Dictionary = {}) -> void:
	subtitle.text = name_value + " · VRM 1.0"
	loading.hide()
	_posture_available = bool(report.get("posture", {}).get("available", false))
	_walk_available = bool(report.get("locomotion", {}).get("available", false))
	walk_button.disabled = not _walk_available
	var face: Dictionary = report.get("face", {})
	var expression_count: int = face.get("expressions", []).size()
	if bool(face.get("blink_available", false)):
		note.text = "Мимика: %d · моргание подключено.\nЛокально, без ИИ и голоса." % expression_count
	else:
		note.text = "Движения работают, но моргание\nне подключено. Детали: session.log."
	if _walk_available:
		note.text += "\nХодьба: ноги и постановка стоп подключены."
	else:
		note.text += "\nХодьба недоступна: проверь скелет."
	var details: PackedStringArray = PackedStringArray(face.get("warnings", []))
	note.tooltip_text = "\n".join(details)
	if not details.is_empty():
		note.mouse_filter = Control.MOUSE_FILTER_PASS

func show_error(message: String) -> void:
	loading.text = "Не удалось подготовить аватар"
	loading.show()
	subtitle.text = "Проверь session.log"
	status.text = "Ошибка загрузки"
	note.text = message
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 255

func refresh(state, status_override: String = "", walking: bool = false) -> void:
	menu.set_item_disabled(menu.get_item_index(41), not shelf_active)
	status.text = status_override if not status_override.is_empty() else state.state_label()
	walk_button.disabled = not _walk_available or walking or not state.motion_enabled
	stop_button.disabled = not walking and not state.posture.transitioning() and not state.sleep_requested
	sit_button.disabled = not _posture_available or state.posture.target_seated or not state.motion_enabled
	stand_button.disabled = not _posture_available or state.posture.mode == "standing"
	rest_check.set_pressed_no_signal(state.rest_enabled)
	menu.set_item_disabled(menu.get_item_index(32), sit_button.disabled)
	menu.set_item_disabled(menu.get_item_index(33), stand_button.disabled)
	autonomy_check.set_pressed_no_signal(state.autonomy_enabled)
	walk_check.set_pressed_no_signal(state.walk_enabled)
	activity_pick.select(["quiet", "normal", "playful"].find(state.activity))
	place_pick.select(["off", "cozy", "smart"].find(state.place_mode))
	edge_pick.select(["auto", "calm", "swing", "lean", "peek"].find(state.edge_activity))
	look_check.set_pressed_no_signal(state.look_enabled)
	motion_check.set_pressed_no_signal(state.motion_enabled)
	hair_check.set_pressed_no_signal(state.hair_enabled)
	var walk_index: int = menu.get_item_index(30)
	menu.set_item_disabled(walk_index, not _walk_available or walking or not state.motion_enabled)
	menu.set_item_disabled(menu.get_item_index(31), stop_button.disabled)
	sleep_button.text = "Разбудить" if state.dozing or state.sleep_requested else "Дремать"
	for pair in [[127, state.rest_enabled], [125, state.walk_enabled], [126, state.autonomy_enabled], [120, state.look_enabled], [121, state.motion_enabled], [122, state.hair_enabled], [123, bubbles_enabled]]:
		var index: int = menu.get_item_index(int(pair[0]))
		if index >= 0:
			menu.set_item_checked(index, bool(pair[1]))
	var sleep_index: int = menu.get_item_index(12)
	menu.set_item_text(sleep_index, "Разбудить" if state.dozing or state.sleep_requested else "Подремать сидя")

func _submenu(title_value: String, node_name: String, entries: Array) -> void:
	var sub: PopupMenu = PopupMenu.new()
	sub.name = node_name
	menu.add_child(sub)
	for pair in entries:
		sub.add_item(str(pair[0]), int(pair[1]))
	sub.id_pressed.connect(_emit_action)
	menu.add_submenu_item(title_value, node_name)

func _build_menu() -> void:
	menu = PopupMenu.new()
	menu.name = "CompanionMenu"
	add_child(menu)
	menu.add_item("HOSHI · локальный 3D-прототип", 999)
	menu.set_item_disabled(0, true)
	menu.add_separator()
	menu.add_item("Пройтись", 30)
	menu.add_item("Остановиться", 31)
	menu.add_item("Выбрать окно под курсором · 4 с", 42)
	menu.add_item("Полочка — попробовать", 40)
	menu.add_item("Мой уютный уголок", 43)
	menu.add_item("Вернуться на пол", 41)
	menu.add_item("Сесть отдохнуть", 32)
	menu.add_item("Встать", 33)
	menu.add_item("Помахать", 10)
	menu.add_item("Погладить", 11)
	menu.add_item("Подремать сидя", 12)
	_submenu("Настроение", "MoodMenu", [["Спокойная", 20], ["Радостная", 21], ["Расслабленная", 22], ["Удивлённая", 23], ["Грустная", 24]])
	menu.add_separator()
	_submenu("Активность", "ActivityMenu", [["Тихая · без прогулок", 200], ["Обычная", 201], ["Игривая", 202]])
	_submenu("Где отдыхать", "PlaceMenu", [["Только вручную", 210], ["Свой уголок", 211], ["Окна → уголок", 212]])
	_submenu("Занятие на краю", "EdgeMenu", [["Сама выбирает", 300], ["Спокойно", 301], ["Болтать ножками", 302], ["Откинуться назад", 303], ["Посмотреть вниз", 304]])
	menu.add_check_item("Самостоятельность", 126)
	menu.add_check_item("Самостоятельные прогулки", 125)
	menu.add_check_item("Самостоятельный отдых", 127)
	menu.add_check_item("Внимание к курсору", 120)
	menu.add_check_item("Мягкие движения", 121)
	menu.add_check_item("Движение волос", 122)
	menu.add_check_item("Короткие реплики", 123)
	_submenu("Размер на рабочем столе", "SizeMenu", [["Небольшая · 280 px", 110], ["Обычная · 360 px", 111], ["Крупная · 440 px", 112]])
	_submenu("Частота кадров", "FPSMenu", [["30 FPS · экономно", 131], ["60 FPS · плавнее", 130]])
	menu.add_item("Отключить / включить маску клика", 124)
	menu.add_separator()
	menu.add_item("Открыть примерочную", 100)
	menu.add_item("На рабочий стол", 101)
	menu.add_item("Вернуть к нижнему краю", 140)
	menu.add_item("Вернуть вид спереди", 141)
	menu.add_separator()
	menu.add_item("Закрыть Hoshi", 199)
	menu.id_pressed.connect(_emit_action)
