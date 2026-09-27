extends Control
const SurfaceMap = preload("res://scripts/window_surface_map.gd")
const QuickMenu = preload("res://scripts/hoshi_quick_menu.gd")
const QRCode = preload("res://scripts/qr_code.gd")
const Commands = preload("res://scripts/hoshi_commands.gd")
const AssistantClouds = preload("res://scripts/assistant_clouds.gd")
const PcActions = preload("res://scripts/pc_actions.gd")
const MonitorMap = preload("res://scripts/monitor_map.gd")

signal action_requested(command: String)
signal light_position_changed(position: Vector3)
signal shading_changed(settings: Dictionary)

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
## Пульт с телефона включён (для галочки в меню).
var remote_enabled: bool = false
var remote_window: Window
var pc_window: Window
var _pc_list: VBoxContainer
var _pc_system_box: HFlowContainer
var _pc_url: LineEdit
var _pc_source
var _pc_changed: Callable
var _pc_dialog: FileDialog
## Выбор приложения из меню «Пуск» для «Моих действий» (список собирается в фоне).
var _start_window: Window
## «Где откроется окно» для одного действия.
var _place_window: Window
var _place_monitor: OptionButton
var _place_mode: OptionButton
var _place_ask: CheckBox
var _place_reuse: CheckBox
var _place_id: String = ""
var _place_map: Control
## «Переставить окно»: открытые окна, схема экранов, положение.
var move_window: Window
var _move_source
var _move_list: ItemList
var _move_map: Control
var _move_version: int = -1
var _move_front: CheckBox
var _start_filter: LineEdit
var _start_list: ItemList
var _start_apps: Array = []   # [{name, id}]
var _start_io: FileAccess
var _start_pid: int = 0
var _start_buffer: String = ""
var sound_window: Window
var _sound_list: VBoxContainer
var _sound_status: Label
var _sound_source
var _sound_changed: Callable
var _remote_text: Label
var _remote_qr: TextureRect
var _remote_addresses: VBoxContainer
var _remote_text_after: Label
## Какой код сейчас показан в окне (remote_bus.code_version).
var remote_code_version: int = -1
var edge_pick: OptionButton
var _walk_available: bool = false
var menu: PopupMenu
var quick_menu: PopupPanel
var _menus_by_action: Dictionary = {}
var light_window: Window
var surface_window: Window
var surface_map: Control
var surface_summary: Label
var surface_detail: Label
var _surface_candidates: Array = []
var _light_sliders: Array[HSlider] = []
var _light_values: Array[Label] = []
var _shadow_slider: HSlider
var _edge_slider: HSlider
var _edge_width_slider: HSlider
var _shadow_color_button: ColorPickerButton
var _edge_color_button: ColorPickerButton
var _outline_slider: HSlider
var _outline_width_slider: HSlider
var _outline_color_button: ColorPickerButton
var _shade_values: Array[Label] = []
var _updating_shading_controls: bool = false
var bubble: PanelContainer
var bubble_label: Label
var _bubble_left: float = 0.0
var bubbles_enabled: bool = true
## Облачка ИИ-помощников над Хоши (assistant_clouds.gd) и что в них показать.
var clouds: Control
var clouds_enabled: bool = true
var cloud_items: Array = []
var _preview: bool = true
var shelf_active: bool = false
var clickthrough_enabled: bool = true

const INK: Color = Color("3b3449")
const MUTED: Color = Color("82798f")
const PLUM: Color = Color("8a688f")
const EDGE_ACTIVITIES: Array[String] = ["auto", "calm", "swing", "lean", "peek", "sway", "hum", "nod"]

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
	_build_quick_menu()
	_build_light_window()
	_build_surface_window()
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

func _button(text: String, action: String) -> Button:
	var item: Button = Button.new()
	item.text = text
	item.custom_minimum_size.y = 32
	item.pressed.connect(_emit_action.bind(action))
	return item

func _emit_action(action: String) -> void:
	action_requested.emit(action)

## Пункты PopupMenu несут внутренний номер; переводим его обратно в имя команды.
func _on_menu_id(id: int) -> void:
	var command: String = Commands.from_menu_id(id)
	if not command.is_empty():
		action_requested.emit(command)

func _on_toggle(_enabled: bool, action: String) -> void:
	action_requested.emit(action)

func _check(text: String, action: String) -> CheckButton:
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
	outer.add_child(_label("МИНИ-КОМПАНЬОН · 3D / 0.7", 11, MUTED))
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
	for item in [["Пройтись", "walk"], ["Стоп", "stop"], ["Сесть", "sit"], ["Встать", "stand"], ["Погладить", "pet"], ["Помахать", "wave"], ["Улыбка", "mood_happy"], ["Дремать", "doze"]]:
		var button: Button = _button(str(item[0]), str(item[1]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reactions.add_child(button)
		match str(item[1]):
			"doze": sleep_button = button
			"walk": walk_button = button
			"stop": stop_button = button
			"sit": sit_button = button
			"stand": stand_button = button
	box.add_child(_button("Выбрать окно · 4 секунды", "pick_window"))
	box.add_child(_button("Видимые края окна · 1 кадр", "scan_window_visual"))
	box.add_child(_button("Структура окна · без снимка", "scan_window_structure"))
	box.add_child(_button("Полочка — попробовать", "shelf_demo"))
	box.add_child(_button("Мой уютный уголок", "cozy_corner"))
	box.add_child(_button("Пройтись по опоре", "surface_walk"))
	box.add_child(_button("Настроить свет", "light_editor"))
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
	for command in Commands.PLACE_CHOICES:
		place_pick.add_item(Commands.title(command))
	place_pick.item_selected.connect(func(index: int): action_requested.emit(Commands.PLACE_CHOICES[index]))
	place_row.add_child(place_pick)
	box.add_child(place_row)
	var edge_row := HBoxContainer.new()
	edge_row.add_child(_label("На краю", 12, MUTED))
	edge_pick = OptionButton.new()
	edge_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for title_value in ["Сама выбирает", "Спокойно", "Ножками", "Откинуться", "Посмотреть вниз", "Покачиваться", "Напевать", "Кивать в такт"]:
		edge_pick.add_item(title_value)
	edge_pick.item_selected.connect(func(index: int): action_requested.emit(Commands.EDGE_CHOICES[index]))
	edge_row.add_child(edge_pick)
	box.add_child(edge_row)
	autonomy_check = _check("Самостоятельность", "toggle_autonomy")
	rest_check = _check("Самостоятельный отдых", "toggle_auto_rest")
	walk_check = _check("Самостоятельные прогулки", "toggle_auto_walk")
	look_check = _check("Внимание к курсору", "toggle_look")
	motion_check = _check("Мягкие движения", "toggle_motion")
	hair_check = _check("Движение волос", "toggle_hair")
	for item in [autonomy_check, walk_check, rest_check, look_check, motion_check, hair_check]:
		box.add_child(item)
	walk_check.tooltip_text = "Автоматически гуляет только у нижнего края, не в тихом режиме. Кнопка «Пройтись» работает отдельно."
	autonomy_check.tooltip_text = "Выключено: только ручные действия и обычный взгляд за курсором."
	outer.add_child(_button("На рабочий стол", "to_desktop"))
	box.add_child(_button("Вернуть вид спереди", "reset_view"))
	hint = _label("Клик — внимание · зажать и вести по голове — гладить\nУдержать ладошку и поднять мышь — повиснуть\nДвойной клик — взмах · W — пройтись · C — сесть/встать\nКолесо — масштаб · ПКМ — меню", 11, MUTED)
	box.add_child(hint)
	note = _label("Локально, без ИИ и голоса.", 11, MUTED)
	box.add_child(note)
	outer.add_child(_button("Закрыть", "quit"))

func _on_activity_selected(index: int) -> void:
	action_requested.emit(Commands.ACTIVITY_CHOICES[index])

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
	clouds = AssistantClouds.new()
	add_child(clouds)
	clouds.hide()

func say(text: String) -> void:
	if not bubbles_enabled:
		return
	bubble_label.text = text
	bubble.reset_size()
	_bubble_left = 2.8
	bubble.show()

func tick(delta: float, head_point: Vector2, frame_size: Vector2) -> void:
	_poll_start_apps()
	_poll_move_window()
	_bubble_left = maxf(0.0, _bubble_left - delta)
	bubble.visible = _bubble_left > 0.0 and bubbles_enabled
	clouds.items = cloud_items if clouds_enabled else []
	clouds.place(delta, head_point, frame_size)
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
	_set_action_disabled("return_floor", not shelf_active)
	status.text = status_override if not status_override.is_empty() else state.state_label()
	walk_button.disabled = not _walk_available or walking or not state.motion_enabled
	stop_button.disabled = not walking and not state.posture.transitioning() and not state.sleep_requested
	sit_button.disabled = not _posture_available or state.posture.target_seated or not state.motion_enabled
	stand_button.disabled = not _posture_available or state.posture.mode == "standing"
	rest_check.set_pressed_no_signal(state.rest_enabled)
	_set_action_disabled("sit", sit_button.disabled)
	_set_action_disabled("stand", stand_button.disabled)
	autonomy_check.set_pressed_no_signal(state.autonomy_enabled)
	walk_check.set_pressed_no_signal(state.walk_enabled)
	activity_pick.select(["quiet", "normal", "playful"].find(state.activity))
	place_pick.select(Commands.PLACE_MODES.find(state.place_mode))
	edge_pick.select(EDGE_ACTIVITIES.find(state.edge_activity))
	look_check.set_pressed_no_signal(state.look_enabled)
	motion_check.set_pressed_no_signal(state.motion_enabled)
	hair_check.set_pressed_no_signal(state.hair_enabled)
	_set_action_disabled("walk", not _walk_available or walking or not state.motion_enabled)
	_set_action_disabled("stop", stop_button.disabled)
	sleep_button.text = "Разбудить" if state.dozing or state.sleep_requested else "Дремать"
	for pair in [["toggle_auto_rest", state.rest_enabled], ["toggle_auto_walk", state.walk_enabled], ["toggle_autonomy", state.autonomy_enabled], ["toggle_look", state.look_enabled], ["toggle_motion", state.motion_enabled], ["toggle_hair", state.hair_enabled], ["toggle_bubbles", bubbles_enabled], ["toggle_assistant_clouds", clouds_enabled], ["toggle_clickthrough", clickthrough_enabled], ["toggle_remote", remote_enabled]]:
		_set_action_checked(str(pair[0]), bool(pair[1]))
	_set_action_text("doze", "Разбудить" if state.dozing or state.sleep_requested else "Подремать сидя")
	quick_menu.set_snapshot(state, status.text, not walk_button.disabled, not stop_button.disabled, remote_enabled)

func menu_open() -> bool:
	return quick_menu.visible or menu.visible

func open_quick_menu(point: Vector2i) -> void:
	quick_menu.open_at(point)

func _build_quick_menu() -> void:
	quick_menu = QuickMenu.new()
	add_child(quick_menu)
	quick_menu.action_requested.connect(_emit_action)
	quick_menu.advanced_requested.connect(func(at: Vector2i):
		menu.position = at
		menu.popup())

func _submenu(parent: PopupMenu, title_value: String, node_name: String, entries: Array) -> PopupMenu:
	var sub: PopupMenu = PopupMenu.new()
	sub.name = node_name
	_style_popup(sub)
	parent.add_child(sub)
	for pair in entries:
		_add_menu_item(sub, str(pair[0]), str(pair[1]))
	sub.id_pressed.connect(_on_menu_id)
	parent.add_submenu_item(title_value, node_name)
	return sub

func _add_menu_item(parent: PopupMenu, title_value: String, action: String, checked: bool = false) -> void:
	var id: int = Commands.menu_id(action)
	assert(id >= 0, "Unknown Hoshi command in menu: " + action)
	if checked:
		parent.add_check_item(title_value, id)
	else:
		parent.add_item(title_value, id)
	_menus_by_action[action] = parent

func action_menu(action: String) -> PopupMenu:
	return _menus_by_action.get(action) as PopupMenu

func _action_index(action: String) -> int:
	var owner: PopupMenu = action_menu(action)
	return owner.get_item_index(Commands.menu_id(action)) if owner != null else -1

func _set_action_disabled(action: String, disabled: bool) -> void:
	var owner: PopupMenu = action_menu(action)
	if owner != null:
		owner.set_item_disabled(owner.get_item_index(Commands.menu_id(action)), disabled)

func _set_action_checked(action: String, checked: bool) -> void:
	var owner: PopupMenu = action_menu(action)
	if owner != null:
		owner.set_item_checked(owner.get_item_index(Commands.menu_id(action)), checked)

func _set_action_text(action: String, title_value: String) -> void:
	var owner: PopupMenu = action_menu(action)
	if owner != null:
		owner.set_item_text(owner.get_item_index(Commands.menu_id(action)), title_value)

## Окно «Мои действия»: кнопки для вкладки «Компьютер» на пульте.
## pc — pc_actions.gd; on_changed — сообщить пультам, что список изменился.
func show_pc_actions(pc, on_changed: Callable) -> void:
	_pc_source = pc
	_pc_changed = on_changed
	pc.refresh_monitors() # экраны ПК — для кнопки ⚙ «где откроется окно»
	if pc_window == null:
		_build_pc_window()
	_refresh_pc_actions()
	_open_on_top(pc_window)

## Открыть окно «поверх других» по центру (родительского окна или экрана).
## Не popup_centered(): он делает окно «привязанным» (transient), а Windows
## не даёт так окнам поверх других — в журнале сыпались ошибки.
func _open_on_top(target: Window) -> void:
	var area := Rect2i(DisplayServer.screen_get_usable_rect(get_window().current_screen))
	var parent := target.get_parent() as Window
	if parent != null and parent.visible and parent != get_tree().root:
		area = Rect2i(parent.position, parent.size)
	target.position = area.position + (area.size - target.size) / 2
	target.show()
	target.grab_focus()

func _build_pc_window() -> void:
	pc_window = Window.new()
	pc_window.title = "Мои действия для пульта"
	pc_window.size = Vector2i(520, 560)
	pc_window.min_size = Vector2i(460, 420)
	pc_window.always_on_top = true
	pc_window.theme = theme
	add_child(pc_window)
	pc_window.close_requested.connect(pc_window.hide)
	var panel_bg := PanelContainer.new()
	panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fffdfb")
	style.set_content_margin_all(16)
	panel_bg.add_theme_stylebox_override("panel", style)
	pc_window.add_child(panel_bg)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel_bg.add_child(column)
	column.add_child(_label("Эти кнопки будут на пульте во вкладке «Компьютер».", 13, MUTED))
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	column.add_child(add_row)
	var add_file := Button.new()
	add_file.text = "＋ Программа или файл"
	add_file.pressed.connect(_pick_pc_path.bind(false))
	add_row.add_child(add_file)
	var add_folder := Button.new()
	add_folder.text = "＋ Папка"
	add_folder.pressed.connect(_pick_pc_path.bind(true))
	add_row.add_child(add_folder)
	var add_start := Button.new()
	add_start.text = "＋ Из меню «Пуск»"
	add_start.tooltip_text = "Приложения Microsoft Store, Chrome и обычные программы — как в меню «Пуск»"
	add_start.pressed.connect(_show_start_apps)
	add_row.add_child(add_start)
	var url_row := HBoxContainer.new()
	column.add_child(url_row)
	_pc_url = LineEdit.new()
	_pc_url.placeholder_text = "https://… — ссылка"
	_pc_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_line_edit(_pc_url)
	url_row.add_child(_pc_url)
	var add_url := Button.new()
	add_url.text = "＋ Ссылка"
	add_url.pressed.connect(_add_pc_url)
	url_row.add_child(add_url)
	column.add_child(_label("Системные кнопки на пульте", 12, MUTED))
	_pc_system_box = HFlowContainer.new()
	_pc_system_box.add_theme_constant_override("h_separation", 8)
	_pc_system_box.add_theme_constant_override("v_separation", 6)
	column.add_child(_pc_system_box)
	column.add_child(_label("Выключение и перезагрузка — с подтверждением и отсрочкой в минуту.", 11, MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_pc_list = VBoxContainer.new()
	_pc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pc_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_pc_list)
	_pc_dialog = FileDialog.new()
	_pc_dialog.use_native_dialog = true
	_pc_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_pc_dialog.file_selected.connect(_on_pc_path_chosen)
	_pc_dialog.dir_selected.connect(_on_pc_path_chosen)
	pc_window.add_child(_pc_dialog)

## Светлый список в стиле Хоши (стандартный ItemList Godot — тёмный).
func _style_item_list(list: ItemList) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("fffaf6")
	panel.border_color = Color("dfd0d5")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(6)
	list.add_theme_stylebox_override("panel", panel)
	var chosen := StyleBoxFlat.new()
	chosen.bg_color = Color("eadff0")
	chosen.set_corner_radius_all(7)
	for kind in ["selected", "selected_focus", "cursor", "cursor_unfocused"]:
		list.add_theme_stylebox_override(kind, chosen)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color("f4eef6")
	hover.set_corner_radius_all(7)
	list.add_theme_stylebox_override("hovered", hover)
	list.add_theme_color_override("font_color", INK)
	list.add_theme_color_override("font_selected_color", PLUM)
	list.add_theme_color_override("font_hovered_color", PLUM)
	list.add_theme_constant_override("v_separation", 6)

func _style_line_edit(edit: LineEdit) -> void:
	for kind in ["normal", "focus", "read_only"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("fffaf6") if kind != "focus" else Color("ffffff")
		box.border_color = Color("dfd0d5") if kind != "focus" else PLUM
		box.set_border_width_all(1)
		box.set_corner_radius_all(9)
		box.content_margin_left = 9
		box.content_margin_right = 9
		box.content_margin_top = 5
		box.content_margin_bottom = 5
		edit.add_theme_stylebox_override(kind, box)
	edit.add_theme_color_override("font_color", INK)
	edit.add_theme_color_override("font_placeholder_color", MUTED)
	edit.add_theme_color_override("caret_color", PLUM)

## Окно «Переставить окно»: выбрать открытое окно, экран на схеме и положение.
## Окна — только имя программы, экран и развёрнуто ли (заголовки не читаем).
func show_move_window(pc) -> void:
	_move_source = pc
	if move_window == null:
		move_window = Window.new()
		move_window.title = "Переставить окно"
		move_window.size = Vector2i(480, 600)
		move_window.min_size = Vector2i(420, 460)
		move_window.always_on_top = true
		move_window.theme = theme
		add_child(move_window)
		move_window.close_requested.connect(move_window.hide)
		var panel_bg := PanelContainer.new()
		panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("fffdfb")
		style.set_content_margin_all(16)
		panel_bg.add_theme_stylebox_override("panel", style)
		move_window.add_child(panel_bg)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		panel_bg.add_child(column)
		var head := HBoxContainer.new()
		column.add_child(head)
		var hint := _label("1. Какое окно", 12, MUTED)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(hint)
		var refresh := Button.new()
		refresh.text = "↻ Обновить"
		refresh.pressed.connect(func(): _move_source.refresh_windows())
		head.add_child(refresh)
		_move_list = ItemList.new()
		_move_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_style_item_list(_move_list)
		column.add_child(_move_list)
		column.add_child(_label("2. На какой экран — нажми на схеме", 12, MUTED))
		_move_map = MonitorMap.new()
		_move_map.custom_minimum_size = Vector2(0, 130)
		column.add_child(_move_map)
		column.add_child(_label("3. Как поставить", 12, MUTED))
		var modes := GridContainer.new()
		modes.columns = 2
		modes.add_theme_constant_override("h_separation", 6)
		modes.add_theme_constant_override("v_separation", 6)
		column.add_child(modes)
		for mode in PcActions.PLACE_MODES:
			var button := Button.new()
			button.text = PcActions.PLACE_MODES[mode]
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(_move_selected.bind(mode))
			modes.add_child(button)
		var front_row := HBoxContainer.new()
		column.add_child(front_row)
		_move_front = CheckBox.new()
		_move_front.text = "Поверх других окон"
		_move_front.button_pressed = true
		_move_front.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		front_row.add_child(_move_front)
		var show_front := Button.new()
		show_front.text = "Показать поверх, не двигая"
		show_front.pressed.connect(func():
			var picked: PackedInt32Array = _move_list.get_selected_items()
			if not picked.is_empty() and _move_list.get_item_metadata(picked[0]) is Dictionary:
				_move_source.run("pc:front", {"hwnd": _move_list.get_item_metadata(picked[0])["hwnd"]}))
		front_row.add_child(show_front)
	_move_version = -1
	pc.refresh_windows()
	_open_on_top(move_window)

func _move_selected(mode: String) -> void:
	var picked: PackedInt32Array = _move_list.get_selected_items()
	if picked.is_empty() or _move_map.selected <= 0:
		say("Выбери окно и экран")
		return
	var w: Variant = _move_list.get_item_metadata(picked[0])
	if w is Dictionary:
		_move_source.run("pc:move", {"hwnd": w["hwnd"], "monitor": _move_map.selected, "mode": mode, "front": _move_front.button_pressed})

func _poll_move_window() -> void:
	if move_window == null or not move_window.visible or _move_source == null or _move_source.windows_version == _move_version:
		return
	_move_version = _move_source.windows_version
	var keep: String = ""
	var picked: PackedInt32Array = _move_list.get_selected_items()
	if not picked.is_empty() and _move_list.get_item_metadata(picked[0]) is Dictionary:
		keep = str(_move_list.get_item_metadata(picked[0])["hwnd"])
	_move_list.clear()
	var states := {"maximized": " · развёрнуто", "minimized": " · свёрнуто", "normal": ""}
	for w in _move_source.open_windows:
		var index: int = _move_list.add_item("%s  ·  экран %d%s" % [w["name"], int(w["monitor"]), states.get(w["state"], "")])
		_move_list.set_item_metadata(index, w)
		if w["hwnd"] == keep:
			_move_list.select(index)
	if _move_source.open_windows.is_empty():
		_move_list.add_item("Смотрю окна…")
		_move_list.set_item_disabled(0, true)
	_move_map.monitors = _move_source.monitors

## Окно ⚙ «Где откроется окно»: экран, положение и «спрашивать на телефоне».
func _show_place_window(id: String) -> void:
	_place_id = id
	if _place_window == null:
		_place_window = Window.new()
		_place_window.title = "Где откроется окно"
		_place_window.size = Vector2i(460, 410)
		_place_window.unresizable = true
		_place_window.always_on_top = true
		_place_window.theme = theme
		pc_window.add_child(_place_window)
		_place_window.close_requested.connect(_place_window.hide)
		var panel_bg := PanelContainer.new()
		panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("fffdfb")
		style.set_content_margin_all(16)
		panel_bg.add_theme_stylebox_override("panel", style)
		_place_window.add_child(panel_bg)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		panel_bg.add_child(column)
		column.add_child(_label("Экран — как в «Параметры → Дисплей»", 12, MUTED))
		_place_map = MonitorMap.new()
		_place_map.custom_minimum_size = Vector2(0, 110)
		_place_map.picked.connect(func(index: int):
			for i in range(_place_monitor.item_count):
				if int(_place_monitor.get_item_metadata(i)) == index:
					_place_monitor.select(i))
		column.add_child(_place_map)
		_place_monitor = OptionButton.new()
		_place_monitor.item_selected.connect(func(i: int): _place_map.selected = int(_place_monitor.get_item_metadata(i)))
		column.add_child(_place_monitor)
		column.add_child(_label("Положение", 12, MUTED))
		_place_mode = OptionButton.new()
		for mode in PcActions.PLACE_MODES:
			_place_mode.add_item(PcActions.PLACE_MODES[mode])
			_place_mode.set_item_metadata(_place_mode.item_count - 1, mode)
		column.add_child(_place_mode)
		_place_ask = CheckBox.new()
		_place_ask.text = "Спрашивать на телефоне при каждом запуске"
		column.add_child(_place_ask)
		_place_reuse = CheckBox.new()
		_place_reuse.text = "Если уже открыто — показать окно (не запускать ещё раз)"
		column.add_child(_place_reuse)
		var save := Button.new()
		save.text = "Сохранить"
		save.pressed.connect(func():
			var mode: String = str(_place_mode.get_item_metadata(maxi(0, _place_mode.selected)))
			_pc_source.set_place(_place_id, int(_place_monitor.get_item_metadata(maxi(0, _place_monitor.selected))), mode, _place_ask.button_pressed, _place_reuse.button_pressed)
			_place_window.hide()
			_after_pc_change())
		column.add_child(save)
	var place: Dictionary = {}
	for item in _pc_source.actions:
		if item["id"] == id:
			place = item.get("place", {})
	_place_monitor.clear()
	_place_monitor.add_item("Не трогать — где откроется само")
	_place_monitor.set_item_metadata(0, 0)
	for m in _pc_source.monitors:
		_place_monitor.add_item(str(m["label"]))
		_place_monitor.set_item_metadata(_place_monitor.item_count - 1, int(m["index"]))
		if int(m["index"]) == int(place.get("monitor", 0)):
			_place_monitor.select(_place_monitor.item_count - 1)
	if int(place.get("monitor", 0)) == 0:
		_place_monitor.select(0)
	for index in range(_place_mode.item_count):
		if _place_mode.get_item_metadata(index) == str(place.get("mode", "center")):
			_place_mode.select(index)
	_place_ask.button_pressed = bool(place.get("ask", false))
	var action_item: Dictionary = {}
	for item in _pc_source.actions:
		if item["id"] == id:
			action_item = item
	_place_reuse.button_pressed = bool(action_item.get("reuse", true))
	_place_reuse.disabled = PcActions.window_exe(action_item).is_empty() # неизвестно, чьё окно искать
	_place_map.monitors = _pc_source.monitors
	_place_map.selected = int(place.get("monitor", 0))
	_open_on_top(_place_window)

## Окно «Из меню «Пуск»»: список приложений (только названия и AppID, только на ПК).
func _show_start_apps() -> void:
	if _start_window == null:
		_start_window = Window.new()
		_start_window.title = "Приложение из меню «Пуск»"
		_start_window.size = Vector2i(460, 520)
		_start_window.always_on_top = true
		_start_window.theme = theme
		pc_window.add_child(_start_window)
		_start_window.close_requested.connect(_start_window.hide)
		var panel_bg := PanelContainer.new()
		panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("fffdfb")
		style.set_content_margin_all(14)
		panel_bg.add_theme_stylebox_override("panel", style)
		_start_window.add_child(panel_bg)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		panel_bg.add_child(column)
		_start_filter = LineEdit.new()
		_start_filter.placeholder_text = "Поиск: Claude, MPC-BE, YouTube…"
		_style_line_edit(_start_filter)
		_start_filter.text_changed.connect(func(_text: String): _fill_start_list())
		column.add_child(_start_filter)
		_start_list = ItemList.new()
		_start_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_style_item_list(_start_list)
		_start_list.item_activated.connect(_on_start_app_chosen)
		column.add_child(_start_list)
		var add := Button.new()
		add.text = "Добавить на пульт"
		add.pressed.connect(func():
			var selected: PackedInt32Array = _start_list.get_selected_items()
			if not selected.is_empty():
				_on_start_app_chosen(selected[0]))
		column.add_child(add)
	_start_apps = []
	_start_filter.text = ""
	_fill_start_list()
	_open_on_top(_start_window)
	if OS.get_name() == "Windows" and _start_io == null:
		var process: Dictionary = OS.execute_with_pipe("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command",
			"[Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-StartApps | Select-Object Name, AppID | ConvertTo-Json -Compress"], false)
		if not process.is_empty():
			_start_io = process["stdio"]
			_start_pid = int(process["pid"])
			_start_buffer = ""

func _poll_start_apps() -> void:
	if _start_io == null:
		return
	_start_buffer += _start_io.get_buffer(65536).get_string_from_utf8()
	if OS.is_process_running(_start_pid) and _start_buffer.length() < 2000000:
		return
	_start_buffer += _start_io.get_buffer(1000000).get_string_from_utf8()
	_start_io = null
	var parsed: Variant = JSON.parse_string(_start_buffer.strip_edges())
	_start_buffer = ""
	_start_apps = []
	for entry in (parsed if parsed is Array else ([parsed] if parsed is Dictionary else [])):
		if entry is Dictionary and PcActions.is_app_id(str(entry.get("AppID", ""))):
			_start_apps.append({"name": str(entry.get("Name", "")).left(60), "id": str(entry["AppID"])})
	_start_apps.sort_custom(func(a, b): return a["name"].naturalnocasecmp_to(b["name"]) < 0)
	_fill_start_list()

func _fill_start_list() -> void:
	if _start_list == null:
		return
	_start_list.clear()
	var needle: String = _start_filter.text.strip_edges().to_lower()
	for app in _start_apps:
		if needle.is_empty() or str(app["name"]).to_lower().contains(needle):
			var index: int = _start_list.add_item(str(app["name"]))
			_start_list.set_item_metadata(index, app)
	if _start_apps.is_empty():
		_start_list.add_item("Собираю список…" if _start_io != null else "Список пуст")
		_start_list.set_item_disabled(0, true)

func _on_start_app_chosen(index: int) -> void:
	var app: Variant = _start_list.get_item_metadata(index)
	if not app is Dictionary:
		return
	_pc_source.add("startapp", str(app["name"]), str(app["id"]))
	_start_window.hide()
	_after_pc_change()

func _pick_pc_path(folder: bool) -> void:
	_pc_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR if folder else FileDialog.FILE_MODE_OPEN_FILE
	_pc_dialog.title = "Выбери папку" if folder else "Выбери программу или файл"
	_pc_dialog.popup_centered_ratio(0.6)

func _on_pc_path_chosen(chosen: String) -> void:
	var kind: String = "folder" if DirAccess.dir_exists_absolute(chosen) else ("open" if chosen.get_extension().to_lower() in ["exe", "lnk", "bat", "cmd", "url"] else "file")
	_pc_source.add(kind, "", chosen)
	_after_pc_change()

func _add_pc_url() -> void:
	var url: String = _pc_url.text.strip_edges()
	if not url.is_empty() and not url.contains("://"):
		url = "https://" + url
	if _pc_source.add("url", "", url) != "":
		_pc_url.text = ""
	_after_pc_change()

func _after_pc_change() -> void:
	_refresh_pc_actions()
	if _pc_changed.is_valid():
		_pc_changed.call()

func _refresh_pc_actions() -> void:
	for child in _pc_system_box.get_children():
		child.queue_free()
	for id in _pc_source.SYSTEM:
		var check := CheckBox.new()
		check.text = "%s %s" % [_pc_source.SYSTEM[id]["icon"], _pc_source.SYSTEM[id]["title"]]
		check.button_pressed = bool(_pc_source.system_enabled.get(id, false))
		check.toggled.connect(func(on: bool):
			_pc_source.set_system(id, on)
			if _pc_changed.is_valid():
				_pc_changed.call())
		_pc_system_box.add_child(check)
	for child in _pc_list.get_children():
		child.queue_free()
	if _pc_source.actions.is_empty():
		_pc_list.add_child(_label("Пока пусто. Добавь программу, папку или ссылку.", 12, MUTED))
	for item in _pc_source.actions:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_label(str(item["icon"]), 18, INK))
		var name_edit := LineEdit.new()
		name_edit.text = str(item["title"])
		name_edit.tooltip_text = str(item["target"])
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.custom_minimum_size.x = 120
		_style_line_edit(name_edit)
		name_edit.text_submitted.connect(func(value: String):
			_pc_source.rename(item["id"], value)
			_after_pc_change())
		name_edit.focus_exited.connect(func():
			if name_edit.text != str(item["title"]):
				_pc_source.rename(item["id"], name_edit.text)
				_after_pc_change())
		row.add_child(name_edit)
		for pair in [["▲", -1], ["▼", 1]]:
			var move := Button.new()
			move.text = pair[0]
			move.pressed.connect(func():
				_pc_source.move(item["id"], pair[1])
				_after_pc_change())
			row.add_child(move)
		if item["kind"] != "url":
			var place: Dictionary = item.get("place", {})
			var gear := Button.new()
			gear.text = "⚙" if int(place.get("monitor", 0)) == 0 and not bool(place.get("ask", false)) else "🖥"
			gear.tooltip_text = "Где откроется окно: экран и положение"
			gear.pressed.connect(_show_place_window.bind(item["id"]))
			row.add_child(gear)
		var remove := Button.new()
		remove.text = "✕"
		remove.tooltip_text = "Убрать с пульта"
		remove.pressed.connect(func():
			_pc_source.remove(item["id"])
			_after_pc_change())
		row.add_child(remove)
		_pc_list.add_child(row)

## Окно «Звук на пульте»: какие устройства вывода показать на телефоне и как их назвать.
## sound — sound_outputs.gd; on_changed — сообщить пультам, что список изменился.
func show_sound_outputs(sound, on_changed: Callable) -> void:
	_sound_source = sound
	_sound_changed = on_changed
	if sound_window == null:
		_build_sound_window()
	if not sound.devices_changed.is_connected(_refresh_sound_outputs):
		sound.devices_changed.connect(_refresh_sound_outputs)
	sound.request_refresh()
	_refresh_sound_outputs()
	_open_on_top(sound_window)

func _build_sound_window() -> void:
	sound_window = Window.new()
	sound_window.title = "Звук на пульте"
	sound_window.size = Vector2i(500, 460)
	sound_window.min_size = Vector2i(440, 340)
	sound_window.always_on_top = true
	sound_window.theme = theme
	add_child(sound_window)
	sound_window.close_requested.connect(sound_window.hide)
	var panel_bg := PanelContainer.new()
	panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fffdfb")
	style.set_content_margin_all(16)
	panel_bg.add_theme_stylebox_override("panel", style)
	sound_window.add_child(panel_bg)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel_bg.add_child(column)
	column.add_child(_label("Отметь, куда переключать звук с телефона, и дай кнопкам имена.", 13, MUTED))
	var status_row := HBoxContainer.new()
	column.add_child(status_row)
	_sound_status = _label("", 13, INK)
	_sound_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_sound_status)
	var refresh := Button.new()
	refresh.text = "↻ Обновить"
	refresh.pressed.connect(func(): _sound_source.request_refresh())
	status_row.add_child(refresh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_sound_list = VBoxContainer.new()
	_sound_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sound_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_sound_list)
	column.add_child(_label("«Связь» (Discord, звонки) не переключается. Выключенный телевизор на пульте будет серым.", 11, MUTED))

func _after_sound_change() -> void:
	_refresh_sound_outputs()
	if _sound_changed.is_valid():
		_sound_changed.call()

func _refresh_sound_outputs() -> void:
	if sound_window == null or _sound_source == null:
		return
	var sound = _sound_source
	var now: String = sound.current_device()
	var now_name: String = ""
	for entry in sound.devices:
		if entry["device"] == now:
			now_name = str(entry["name"])
	if not sound.known:
		_sound_status.text = "Смотрю устройства…"
	else:
		_sound_status.text = "Сейчас звук: " + (now_name if not now_name.is_empty() else "—")
	# Не перестраивать список, пока в нём печатают имя.
	var focus: Control = sound_window.gui_get_focus_owner()
	if focus != null and _sound_list.is_ancestor_of(focus):
		return
	for child in _sound_list.get_children():
		child.queue_free()
	# Сначала кнопки пульта (в их порядке), потом остальные активные устройства.
	var rows: Array = []
	for item in sound.outputs:
		var dev_name: String = ""
		for entry in sound.devices:
			if entry["device"] == item["device"]:
				dev_name = str(entry["name"])
		rows.append({"device": item["device"], "name": dev_name, "item": item})
	for entry in sound.devices:
		if sound.index_of_device(entry["device"]) < 0:
			rows.append({"device": entry["device"], "name": str(entry["name"]), "item": {}})
	if rows.is_empty():
		_sound_list.add_child(_label("Устройств пока не видно." if sound.known else "", 12, MUTED))
	for row_data in rows:
		var item: Dictionary = row_data["item"]
		var device: String = row_data["device"]
		var dev_name: String = row_data["name"]
		var active: bool = sound.is_active(device)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var check := CheckBox.new()
		check.button_pressed = not item.is_empty()
		check.tooltip_text = "Показывать на пульте"
		check.toggled.connect(func(on: bool):
			sound.set_shown(device, dev_name, on)
			_after_sound_change())
		row.add_child(check)
		if item.is_empty():
			var title := _label(dev_name, 13, INK)
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(title)
		else:
			row.add_child(_label(str(item["icon"]), 18, INK))
			var name_edit := LineEdit.new()
			name_edit.text = str(item["title"])
			name_edit.tooltip_text = dev_name if not dev_name.is_empty() else "Сейчас не подключено"
			name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_edit.custom_minimum_size.x = 120
			_style_line_edit(name_edit)
			name_edit.text_submitted.connect(func(value: String):
				sound.rename(item["id"], value)
				name_edit.release_focus()
				_after_sound_change())
			name_edit.focus_exited.connect(func():
				if name_edit.text != str(item["title"]):
					sound.rename(item["id"], name_edit.text)
					_after_sound_change())
			row.add_child(name_edit)
			if sound.known and not active:
				row.add_child(_label("нет на связи", 11, MUTED))
			elif device == now:
				row.add_child(_label("♪ сейчас", 11, PLUM))
			for pair in [["▲", -1], ["▼", 1]]:
				var move := Button.new()
				move.text = pair[0]
				move.pressed.connect(func():
					sound.move(item["id"], pair[1])
					_after_sound_change())
				row.add_child(move)
		_sound_list.add_child(row)

## Окно «Пульт с телефона»: адрес страницы и код привязки крупно.
## choices — [{url, ip, network, virtual}] из remote_bus.address_choices(); chosen_ip — адрес
## в QR; skipped — сети вне домашней ([{ip, network}]); on_choose(ip) — выбрали адрес для QR.
func show_remote_info(enabled: bool, choices: Array, chosen_ip: String, code: String, phones: int, error: String = "", qr_text: String = "", code_version: int = -1, skipped: Array = [], on_choose: Callable = Callable()) -> void:
	remote_code_version = code_version
	if remote_window == null:
		remote_window = Window.new()
		remote_window.title = "Пульт Хоши с телефона"
		remote_window.size = Vector2i(460, 700)
		remote_window.unresizable = true
		remote_window.always_on_top = true
		remote_window.theme = theme
		add_child(remote_window)
		remote_window.close_requested.connect(remote_window.hide)
		var panel_bg := PanelContainer.new()
		panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("fffdfb")
		style.set_content_margin_all(18)
		panel_bg.add_theme_stylebox_override("panel", style)
		remote_window.add_child(panel_bg)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		panel_bg.add_child(column)
		_remote_qr = TextureRect.new()
		_remote_qr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		_remote_qr.custom_minimum_size = Vector2(0, 300)
		column.add_child(_remote_qr)
		_remote_text = _label("", 14, INK)
		_remote_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(_remote_text)
		_remote_addresses = VBoxContainer.new()
		_remote_addresses.add_theme_constant_override("separation", 2)
		column.add_child(_remote_addresses)
		_remote_text_after = _label("", 14, INK)
		_remote_text_after.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(_remote_text_after)
	var qr: Image = QRCode.to_image(qr_text, 7, 3, INK, Color.WHITE) if enabled and not qr_text.is_empty() else null
	_remote_qr.texture = ImageTexture.create_from_image(qr) if qr != null else null
	_remote_qr.visible = qr != null
	for child in _remote_addresses.get_children():
		child.queue_free()
	var lines: PackedStringArray = []
	var after: PackedStringArray = []
	if qr != null:
		lines.append("Наведи камеру телефона на QR-код и открой ссылку —")
		lines.append("пульт привяжется сам. Или вручную:")
		lines.append("")
	if not enabled:
		lines.append("Пульт выключен." if error.is_empty() else "Не получилось включить пульт: порт занят другой программой.")
		lines.append("Меню → Пульт с телефона → Пульт включён.")
	else:
		lines.append("1. Телефон в той же домашней Wi-Fi сети.")
		lines.append("2. Открой в браузере телефона" + (" (● — адрес в QR, нажми другой, чтобы сменить):" if choices.size() > 1 else ":"))
		var group := ButtonGroup.new()
		for choice in choices:
			var pick := CheckBox.new()
			pick.button_group = group
			pick.button_pressed = choice["ip"] == chosen_ip
			pick.text = "%s  —  %s%s" % [choice["url"], choice["network"], "  · VPN/виртуальная" if choice["virtual"] else ""]
			pick.tooltip_text = "Использовать этот адрес в QR-коде"
			if choice["virtual"]:
				pick.add_theme_color_override("font_color", MUTED)
			var ip: String = choice["ip"]
			pick.pressed.connect(func():
				if on_choose.is_valid() and ip != chosen_ip:
					on_choose.call(ip))
			_remote_addresses.add_child(pick)
		if choices.is_empty():
			_remote_addresses.add_child(_label("      (не нашла адрес в домашней сети — проверь Wi-Fi)", 13, MUTED))
		for item in skipped:
			_remote_addresses.add_child(_label("      не подходит: %s (%s) — не домашняя сеть" % [item["network"], item["ip"]], 11, MUTED))
		after.append("3. Введи код:  " + code.substr(0, 3) + " " + code.substr(3))
		after.append("")
		after.append("Привязано телефонов сейчас на связи: %d" % phones)
		after.append("Если Windows спросит про доступ к сети — разреши для частной сети.")
	_remote_text.text = "\n".join(lines)
	_remote_text_after.text = "\n".join(after)
	_remote_text_after.visible = not after.is_empty()
	if not remote_window.visible:
		_open_on_top(remote_window)

func _build_light_window() -> void:
	light_window = Window.new()
	light_window.title = "Свет, тень и обводка Хоши"
	light_window.size = Vector2i(380, 635)
	light_window.min_size = Vector2i(380, 635)
	light_window.unresizable = true
	light_window.always_on_top = true
	light_window.theme = theme
	add_child(light_window)
	light_window.hide()
	light_window.close_requested.connect(light_window.hide)
	var panel_bg := PanelContainer.new()
	panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fffdfb")
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel_bg.add_theme_stylebox_override("panel", style)
	light_window.add_child(panel_bg)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel_bg.add_child(column)
	column.add_child(_label("Положение света", 20, PLUM))
	column.add_child(_label("Меняй положение — свет на Хоши обновится сразу.", 12, MUTED))
	for item in [["Лево ↔ право", -3.0, 3.0], ["Ниже ↔ выше", 0.2, 3.5], ["Дальше ↔ ближе", 0.4, 4.0]]:
		var row := HBoxContainer.new()
		column.add_child(row)
		var label := _label(str(item[0]), 12)
		label.custom_minimum_size.x = 112.0
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = float(item[1])
		slider.max_value = float(item[2])
		slider.step = 0.05
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_light_slider_changed)
		row.add_child(slider)
		_light_sliders.append(slider)
		var number := _label("", 12, MUTED)
		number.custom_minimum_size.x = 34.0
		row.add_child(number)
		_light_values.append(number)
	column.add_child(HSeparator.new())
	column.add_child(_label("Тень", 18, PLUM))
	_shadow_slider = _shading_slider_row(column, "Сила тени", 0.0, 1.5)
	_shadow_color_button = _shading_color_row(column, "Цвет тени")
	column.add_child(HSeparator.new())
	column.add_child(_label("Верхний блик", 18, PLUM))
	_edge_slider = _shading_slider_row(column, "Сила блика", 0.0, 0.5)
	_edge_width_slider = _shading_slider_row(column, "Ширина", 0.0, 1.0)
	_edge_color_button = _shading_color_row(column, "Цвет блика")
	column.add_child(HSeparator.new())
	column.add_child(_label("Обводка", 18, PLUM))
	_outline_slider = _shading_slider_row(column, "Сила · 0 = выкл.", 0.0, 1.0)
	_outline_width_slider = _shading_slider_row(column, "Толщина", 0.0, 1.0)
	_outline_color_button = _shading_color_row(column, "Цвет обводки")
	var footer := HBoxContainer.new()
	column.add_child(footer)
	var reset := _button("Сбросить настройки", "light_reset")
	footer.add_child(reset)
	var close := Button.new()
	close.text = "Готово"
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(light_window.hide)
	footer.add_child(close)

func _shading_slider_row(column: VBoxContainer, caption: String, minimum: float, maximum: float) -> HSlider:
	var row := HBoxContainer.new()
	column.add_child(row)
	var label := _label(caption, 12)
	label.custom_minimum_size.x = 112.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_shading_value_changed)
	row.add_child(slider)
	var number := _label("", 12, MUTED)
	number.custom_minimum_size.x = 34.0
	row.add_child(number)
	_shade_values.append(number)
	return slider

func _shading_color_row(column: VBoxContainer, caption: String) -> ColorPickerButton:
	var row := HBoxContainer.new()
	column.add_child(row)
	var label := _label(caption, 12)
	label.custom_minimum_size.x = 112.0
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size.y = 27.0
	picker.edit_alpha = false
	picker.tooltip_text = "Нажми, чтобы выбрать цвет"
	picker.color_changed.connect(_on_shading_value_changed)
	row.add_child(picker)
	return picker

func show_light_editor(position_value: Vector3, shading: Dictionary) -> void:
	set_light_position(position_value)
	set_shading_settings(shading)
	_open_on_top(light_window)

func set_light_position(position_value: Vector3) -> void:
	var values: Array[float] = [position_value.x, position_value.y, position_value.z]
	for index in range(_light_sliders.size()):
		_light_sliders[index].set_value_no_signal(values[index])
		_light_values[index].text = "%.2f" % values[index]

func _on_light_slider_changed(_value: float) -> void:
	var position_value := Vector3(_light_sliders[0].value, _light_sliders[1].value, _light_sliders[2].value)
	set_light_position(position_value)
	light_position_changed.emit(position_value)

func set_shading_settings(settings: Dictionary) -> void:
	_updating_shading_controls = true
	_shadow_slider.set_value_no_signal(float(settings["shadow_strength"]))
	_edge_slider.set_value_no_signal(float(settings["edge_strength"]))
	_edge_width_slider.set_value_no_signal(float(settings["edge_width"]))
	_outline_slider.set_value_no_signal(float(settings["outline_strength"]))
	_outline_width_slider.set_value_no_signal(float(settings["outline_width"]))
	_shadow_color_button.color = settings["shadow_color"]
	_edge_color_button.color = settings["edge_color"]
	_outline_color_button.color = settings["outline_color"]
	_refresh_shading_numbers()
	_updating_shading_controls = false

func _refresh_shading_numbers() -> void:
	for index in range(_shade_values.size()):
		_shade_values[index].text = "%.2f" % [_shadow_slider.value, _edge_slider.value, _edge_width_slider.value,
			_outline_slider.value, _outline_width_slider.value][index]

func _on_shading_value_changed(_value: Variant) -> void:
	if _updating_shading_controls:
		return
	_refresh_shading_numbers()
	shading_changed.emit({"shadow_strength": _shadow_slider.value, "shadow_color": _shadow_color_button.color,
		"edge_strength": _edge_slider.value, "edge_color": _edge_color_button.color, "edge_width": _edge_width_slider.value,
		"outline_strength": _outline_slider.value, "outline_color": _outline_color_button.color, "outline_width": _outline_width_slider.value})

func _build_menu() -> void:
	menu = PopupMenu.new()
	menu.name = "CompanionMenu"
	_style_popup(menu)
	add_child(menu)
	menu.add_item("✦  ХОШИ · все действия", 999)
	menu.set_item_disabled(0, true)
	menu.add_separator()
	_submenu(menu, "Разговор и приложения  ›", "TalkMenu", [["Поговорить через ChatGPT ↗", "talk_voice"], ["Открыть текстовый чат ↗", "talk_text"]])
	var movement := _submenu(menu, "Места и движение  ›", "MovementMenu", [["Мой уютный уголок", "cozy_corner"], ["Выбрать окно под курсором · 4 с", "pick_window"], ["Полочка — попробовать", "shelf_demo"], ["Пройтись", "walk"], ["Остановиться", "stop"], ["Сесть отдохнуть", "sit"], ["Встать", "stand"], ["Вернуться на пол", "return_floor"]])
	movement.add_separator()
	_submenu(movement, "На поверхности окна  ›", "SurfaceMenu", [["Пройтись по краю", "surface_walk"], ["Подвинуться сидя", "surface_scoot"], ["Опора у левого края", "side_left"], ["Опора у правого края", "side_right"], ["Сесть обратно", "side_return"]])
	var life := _submenu(menu, "Общение и занятия  ›", "LifeMenu", [["Помахать", "wave"], ["Погладить", "pet"], ["Подремать сидя", "doze"]])
	life.add_separator()
	_submenu(life, "Настроение  ›", "MoodMenu", [["Спокойная", "mood_neutral"], ["Радостная", "mood_happy"], ["Расслабленная", "mood_relaxed"], ["Удивлённая", "mood_surprised"], ["Грустная", "mood_sad"]])
	_submenu(life, "Занятие на краю  ›", "EdgeMenu", [["Сама выбирает", "edge_mode_auto"], ["Спокойно", "edge_mode_calm"], ["Болтать ножками", "edge_mode_swing"], ["Откинуться назад", "edge_mode_lean"], ["Посмотреть вниз", "edge_mode_peek"], ["Мягко покачиваться", "edge_mode_sway"], ["Тихонько напевать", "edge_mode_hum"], ["Кивать в такт", "edge_mode_nod"]])
	_submenu(life, "Особые сценки  ›", "SceneMenu", [["Рисовать в блокноте", "edge_sketch"], ["Сложить звёздочку", "edge_fold"], ["Полюбоваться звёздочкой", "edge_admire_star"]])
	var autonomy := _submenu(menu, "Ритм и самостоятельность  ›", "AutonomyMenu", [])
	_add_menu_item(autonomy, "Самостоятельность", "toggle_autonomy", true)
	_add_menu_item(autonomy, "Самостоятельные прогулки", "toggle_auto_walk", true)
	_add_menu_item(autonomy, "Самостоятельный отдых", "toggle_auto_rest", true)
	_add_menu_item(autonomy, "Внимание к курсору", "toggle_look", true)
	_add_menu_item(autonomy, "Короткие реплики", "toggle_bubbles", true)
	_add_menu_item(autonomy, "Облачка помощников", "toggle_assistant_clouds", true)
	autonomy.add_separator()
	_submenu(autonomy, "Активность  ›", "ActivityMenu", [["Тихая · без прогулок", "activity_quiet"], ["Обычная", "activity_normal"], ["Игривая", "activity_playful"]])
	_submenu(autonomy, "Где отдыхать  ›", "PlaceMenu", [["Только вручную", "place_manual"], ["Свой уголок", "place_cozy"], ["Окна → уголок", "place_smart"], ["Моё окно → уголок", "place_focus"]])
	var remote_menu := _submenu(menu, "Пульт с телефона  ›", "RemoteMenu", [])
	_add_menu_item(remote_menu, "Пульт включён", "toggle_remote", true)
	_add_menu_item(remote_menu, "Адрес и код для телефона…", "remote_info")
	_add_menu_item(remote_menu, "Мои действия для пульта…", "pc_actions_editor")
	_add_menu_item(remote_menu, "Звук на пульте…", "sound_outputs_editor")
	_add_menu_item(remote_menu, "Переставить окно…", "move_window_editor")
	_add_menu_item(remote_menu, "Забыть все телефоны", "remote_forget")
	var appearance := _submenu(menu, "Внешний вид  ›", "AppearanceMenu", [])
	_add_menu_item(appearance, "Настроить свет, тени и обводку…", "light_editor")
	_add_menu_item(appearance, "Мягкие движения", "toggle_motion", true)
	_add_menu_item(appearance, "Движение волос", "toggle_hair", true)
	_submenu(appearance, "Размер на рабочем столе  ›", "SizeMenu", [["Небольшая · 280 px", "size_small"], ["Обычная · 360 px", "size_normal"], ["Крупная · 440 px", "size_large"]])
	var tools := _submenu(menu, "Инструменты и окно  ›", "ToolsMenu", [["Открыть примерочную", "open_preview"], ["На рабочий стол", "to_desktop"], ["Вернуть к нижнему краю", "return_bottom"], ["Вернуть вид спереди", "reset_view"]])
	tools.add_separator()
	_add_menu_item(tools, "Клики только по Хоши", "toggle_clickthrough", true)
	_submenu(tools, "Частота кадров  ›", "FPSMenu", [["30 FPS · экономно", "fps_30"], ["60 FPS · плавнее", "fps_60"]])
	_submenu(tools, "Проверка краёв окна  ›", "DiagnosticsMenu", [["Видимые края · 1 кадр · 4 с", "scan_window_visual"], ["Структура · без снимка · 4 с", "scan_window_structure"]])
	menu.add_separator()
	_add_menu_item(menu, "Перезапустить Хоши", "restart")
	_add_menu_item(menu, "Закрыть Хоши", "quit")
	menu.id_pressed.connect(_on_menu_id)

func _style_popup(target: PopupMenu) -> void:
	var popup_theme := Theme.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("fffaf5")
	frame.border_color = Color("d9c5cb")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(14)
	frame.set_content_margin_all(8)
	frame.shadow_color = Color(0.16, 0.11, 0.24, 0.18)
	frame.shadow_size = 9
	popup_theme.set_stylebox("panel", "PopupMenu", frame)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color("efe7f3")
	hover.set_corner_radius_all(8)
	popup_theme.set_stylebox("hover", "PopupMenu", hover)
	popup_theme.set_color("font_color", "PopupMenu", INK)
	popup_theme.set_color("font_hover_color", "PopupMenu", PLUM)
	popup_theme.set_color("font_disabled_color", "PopupMenu", MUTED)
	popup_theme.set_color("font_separator_color", "PopupMenu", PLUM)
	popup_theme.set_constant("v_separation", "PopupMenu", 5)
	popup_theme.set_constant("h_separation", "PopupMenu", 10)
	popup_theme.set_constant("item_start_padding", "PopupMenu", 12)
	popup_theme.set_constant("item_end_padding", "PopupMenu", 12)
	target.theme = popup_theme

func _build_surface_window() -> void:
	surface_window = Window.new()
	surface_window.title = "Хоши · линии внутри окна"
	surface_window.size = Vector2i(620, 510)
	surface_window.min_size = Vector2i(500, 420)
	surface_window.always_on_top = true
	surface_window.theme = theme
	add_child(surface_window)
	surface_window.hide()
	surface_window.close_requested.connect(surface_window.hide)
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fffdfb")
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	background.add_theme_stylebox_override("panel", style)
	surface_window.add_child(background)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	background.add_child(column)
	column.add_child(_label("Где Хоши видит края", 20, PLUM))
	column.add_child(_label("Фиолетовые — края, бирюзовые — строки. Кадр обрабатывается локально.", 12, MUTED))
	surface_summary = _label("", 13, INK)
	column.add_child(surface_summary)
	surface_map = SurfaceMap.new()
	surface_map.custom_minimum_size = Vector2(460, 300)
	surface_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	surface_map.candidate_selected.connect(_on_surface_candidate_selected)
	column.add_child(surface_map)
	surface_detail = _label("", 12, MUTED)
	column.add_child(surface_detail)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	buttons.add_child(_button("Другое окно · кадр", "scan_window_visual"))
	buttons.add_child(_button("Другое окно · структура", "scan_window_structure"))
	var close_button := Button.new()
	close_button.text = "Готово"
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(surface_window.hide)
	buttons.add_child(close_button)

func show_surface_scan(data: Dictionary) -> void:
	_surface_candidates = data.get("candidates", [])
	var visual_mode: bool = str(data.get("source", "structure")) == "visual"
	surface_window.title = "Хоши · видимые края окна" if visual_mode else "Хоши · структура окна"
	if bool(data.get("ok", false)):
		var count_value: int = _surface_candidates.size()
		var total: int = int(data.get("visible_count", count_value))
		if visual_mode:
			surface_summary.text = "Кадр: краёв %d · строк %d · показаны %d из %d" % [int(data.get("edge_count", 0)), int(data.get("row_count", 0)), count_value, total]
		else:
			surface_summary.text = "Структура: линий %d · показаны %d · просмотрено %d элементов" % [total, count_value, int(data.get("visited", 0))]
		if bool(data.get("limited", false)):
			surface_detail.text = "Предел структуры. Для содержимого выбери «Другое окно · кадр»."
		elif count_value == 0:
			surface_detail.text = "Структура пуста. Попробуй «Другое окно · кадр»." if not visual_mode else "На кадре не нашлось подходящих краёв."
		else:
			surface_detail.text = "Это ориентиры, пока не готовые маршруты для прыжка."
		var app_name: String = str(data.get("app", ""))
		if not app_name.is_empty():
			surface_summary.text = "%s · %s" % [app_name, surface_summary.text]
		surface_map.show_result(data)
	else:
		var reason: String = str(data.get("reason", "unavailable"))
		match reason:
			"own_or_hidden": surface_summary.text = "Выбрано окно Хоши или скрытое окно"
			"minimized": surface_summary.text = "Окно свёрнуто"
			"uia_unavailable": surface_summary.text = "Приложение не отдало геометрию интерфейса"
			"visual_dependency": surface_summary.text = "Для видимых краёв нужен локальный модуль захвата"
			"blank_capture": surface_summary.text = "Захват окна вернул пустой кадр"
			"capture_unavailable": surface_summary.text = "Не удалось захватить выбранное окно"
			"timeout": surface_summary.text = "Приложение слишком долго отвечает"
			_: surface_summary.text = "Не удалось проверить окно (%s)" % reason
		surface_detail.text = "Можно навести курсор на другое окно и повторить."
		surface_map.show_result({"window": [1, 1], "candidates": []})
	_open_on_top(surface_window)

func _on_surface_candidate_selected(index: int) -> void:
	if index < 0 or index >= _surface_candidates.size():
		return
	var item: Dictionary = _surface_candidates[index]
	var kinds: Dictionary = {"Visual": "видимый край", "VisualItem": "строка интерфейса, пока не опора", "ToolBar": "панель", "Tab": "вкладки", "TabItem": "вкладка", "Header": "заголовок списка",
		"HeaderItem": "ячейка заголовка", "ListItem": "строка списка", "Button": "кнопка", "Group": "группа",
		"Pane": "область", "Custom": "нестандартный элемент"}
	var kind: String = str(item.get("kind", ""))
	surface_detail.text = "%s · ширина %d px · высота %d px в окне" % [str(kinds.get(kind, kind)), int(item.get("width", 0)), int(item.get("y", 0))]
