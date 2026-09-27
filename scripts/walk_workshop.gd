extends Control
## Walk workshop: Hoshi walks back and forth while sliders change WalkStyle live.
## "Сохранить" writes res://animations/walk_style.tres, which the companion uses.
## Owns no bones itself: it only drives Locomotion + AvatarStage like the app does.

const Stage = preload("res://scripts/avatar_stage.gd")
const State = preload("res://scripts/companion_state.gd")
const Locomotion = preload("res://scripts/locomotion.gd")
const WalkStyle = preload("res://scripts/walk_style.gd")
const MODEL_PATH: String = "res://assets/Hoshi_v1.vrm"
## Sliders in display order: [property, title, what it does].
const GROUPS: Array = [
	["Шаг и стопы", [
		["step_length", "Длина шага", "Доля роста. Дальше шаг — сильнее сгибаются колени."],
		["speed", "Скорость", "Вместе с длиной шага задаёт, как часто она шагает."],
		["foot_lift", "Подъём стопы (сгиб колена)", "Как высоко стопа проходит под телом. Меньше — нога идёт вперёд почти прямой."],
		["push_off", "Отталкивание носком", "Пятка поднимается перед шагом, стопа катится на носок."],
		["heel_strike", "Носок перед касанием", "Нога ставится на пятку с приподнятым носком."],
		["back_hold", "Задержка ноги сзади", "Задняя нога дольше стоит позади на носке, потом быстро выносится."],
		["rear_release", "Плавность отрыва задней ноги", "Больше — таз идёт ровнее, но носок сзади отрывается раньше. Меньше — нога дольше сзади, таз сильнее проседает."],
		["leg_kick", "Выброс ноги вперёд", "Нога выпрямляется и выносится вперёд в воздухе дальше места постановки, потом опускается на пятку."],
		["kick_height", "Высота выноса", "Как высоко стопа в момент выноса вперёд."],
		["bounce", "Пружинка", "Насколько тело опускается и поднимается на каждом шаге."],
		["drop_snap", "Резкость проседания", "0 — ровно, как пружина; 1 — тело быстро проседает вместе с опускающейся ногой и медленно поднимается."],
	]],
	["Таз и корпус", [
		["hip_turn", "Поворот таза", "Таз идёт вперёд за шагающей ногой."],
		["hip_tilt", "Наклон таза вбок", "Таз проседает на стороне шагающей ноги."],
		["torso_lean", "Наклон спины", "Плюс — вперёд, минус — назад, «гордая» прямая походка."],
		["chest_pitch", "Грудь", "Минус — грудь вперёд-вверх, открыто; плюс — сутулясь."],
		["kick_lean", "Наклон при выбросе", "Корпус подаётся вперёд, когда нога выносится вперёд."],
		["footfall_dip", "Проседание на шаге", "Корпус чуть «кивает» вперёд, когда нога встаёт."],
		["side_lean", "Перевал на опорную ногу", "Корпус наклоняется вбок над ногой, на которую опирается."],
		["shoulder_turn", "Поворот плеч", "Плечи поворачиваются навстречу тазу."],
	]],
	["Голова", [
		["head_tilt", "Покачивание головы", "Наклон головы из стороны в сторону в такт шагам."],
		["head_nod", "Кивок на шаге", "Маленький кивок после каждого шага."],
		["head_lag", "Запаздывание головы", "Насколько позже тела движется голова."],
	]],
	["Руки", [
		["arm_forward", "Мах вперёд", "Градусы."],
		["arm_back", "Мах назад", "Градусы."],
		["arm_open", "Руки от тела", "Насколько руки отведены в стороны."],
		["elbow_bend", "Сгиб локтя", "Локоть сильнее сгибается при махе вперёд."],
		["arm_lag", "Запаздывание рук", "Насколько руки отстают от ног."],
		["hand_flop", "Кисти болтаются", "Кисть догоняет руку и «хлёстывает» на концах маха."],
	]],
]

var stage
var state
var walker
var style
var view_mode: String = "walk"
var view_yaw: float = 0.0
var time_scale: float = 1.0
var dirty: bool = false
var status_label: Label
var sliders: Dictionary = {}
var value_labels: Dictionary = {}
var _direction: int = 1
var _syncing: bool = false

func _ready() -> void:
	get_window().title = "Hoshi — мастерская походки"
	get_window().size = Vector2i(1320, 880)
	style = WalkStyle.active()
	_build_ui()
	state = State.new()
	state.autonomy_enabled = false
	state.look_enabled = false
	state.rest_enabled = false
	walker = Locomotion.new()
	var loaded: Dictionary = stage.load_model(MODEL_PATH)
	if loaded.has("error"):
		status_label.text = str(loaded["error"])
		return
	stage.configure_frame(560.0, 70.0)
	_sync_sliders()
	status_label.text = "Двигай ползунки — Хоши сразу идёт по-новому. Длина шага и скорость меняются со следующего прохода."

func _process(delta: float) -> void:
	if stage == null or not stage.is_loaded:
		return
	var dt: float = clampf(delta, 0.0, 0.1) * time_scale
	if not walker.active():
		_start_leg()
	walker.tick(dt)
	state.tick(dt, false)
	var frame: Dictionary = walker.sample()
	if view_mode == "walk":
		stage.yaw = walker.yaw
		stage.travel_offset_px = walker.x_px
	else:
		# On the spot: the body faces the chosen view, the floor slides under her feet.
		stage.yaw = view_yaw if walker.mode == "walk" or walker.mode == "settle" else lerpf(stage.yaw, view_yaw, 0.2)
		stage.travel_offset_px = 0.0
	stage.animate(dt, state, Vector2.ZERO, frame)

func _start_leg() -> void:
	var half: float = maxf(160.0, stage.size.x * 0.5 - 130.0)
	if view_mode == "walk":
		var from: float = walker.x_px
		var goal: float = half * float(_direction)
		if absf(goal - from) < 50.0:
			_direction = -_direction
			goal = half * float(_direction)
		walker.request(from, goal, Vector2(-half, half), stage.meters_per_pixel(), stage.model_height, stage.yaw)
		_direction = -_direction
	else:
		walker.reset(0.0, view_yaw)
		walker.request(0.0, 4000.0, Vector2(-10.0, 4010.0), stage.meters_per_pixel(), stage.model_height, view_yaw)

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("191825")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var layout := HBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 20.0
	layout.offset_top = 20.0
	layout.offset_right = -20.0
	layout.offset_bottom = -20.0
	layout.add_theme_constant_override("separation", 18)
	add_child(layout)
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(760.0, 800.0)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(preview)
	var preview_area := Control.new()
	preview_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_child(preview_area)
	stage = Stage.new()
	preview_area.add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 470.0
	controls.add_theme_constant_override("separation", 8)
	layout.add_child(controls)
	var title := Label.new()
	title.text = "Мастерская походки"
	title.add_theme_font_size_override("font_size", 24)
	controls.add_child(title)
	var views := HBoxContainer.new()
	controls.add_child(views)
	for entry in [{"name": "Гулять", "mode": "walk", "yaw": 0.0}, {"name": "На месте · спереди", "mode": "spot", "yaw": 0.0},
			{"name": "¾", "mode": "spot", "yaw": 40.0}, {"name": "Сбоку", "mode": "spot", "yaw": 90.0}]:
		var button := Button.new()
		button.text = str(entry["name"])
		button.pressed.connect(_set_view.bind(str(entry["mode"]), float(entry["yaw"])))
		views.add_child(button)
	var speed_row := HBoxContainer.new()
	controls.add_child(speed_row)
	var speed_label := Label.new()
	speed_label.text = "Замедление просмотра"
	speed_label.custom_minimum_size.x = 190.0
	speed_row.add_child(speed_label)
	var speed_slider := HSlider.new()
	speed_slider.min_value = 0.1
	speed_slider.max_value = 1.0
	speed_slider.step = 0.05
	speed_slider.value = 1.0
	speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(speed_slider)
	var speed_value := Label.new()
	speed_value.text = "100%"
	speed_value.custom_minimum_size.x = 52.0
	speed_row.add_child(speed_value)
	speed_slider.value_changed.connect(func(value: float) -> void:
		time_scale = value
		speed_value.text = "%d%%" % int(round(value * 100.0)))
	controls.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	controls.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var ranges: Dictionary = _property_ranges()
	for group in GROUPS:
		var header := Label.new()
		header.text = str(group[0])
		header.add_theme_font_size_override("font_size", 18)
		header.add_theme_color_override("font_color", Color("f3b6d4"))
		list.add_child(header)
		for item in group[1]:
			_add_slider(list, str(item[0]), str(item[1]), str(item[2]), ranges.get(str(item[0]), Vector3(0.0, 1.0, 0.01)))
		list.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	controls.add_child(buttons)
	var save := Button.new()
	save.text = "Сохранить"
	save.pressed.connect(_save)
	buttons.add_child(save)
	var revert := Button.new()
	revert.text = "Вернуть сохранённое"
	revert.pressed.connect(_revert)
	buttons.add_child(revert)
	var defaults := Button.new()
	defaults.text = "Исходные значения"
	defaults.pressed.connect(_defaults)
	buttons.add_child(defaults)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(status_label)

func _add_slider(parent: Control, key: String, title: String, hint: String, range_info: Vector3) -> void:
	var row := HBoxContainer.new()
	row.tooltip_text = hint
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.tooltip_text = hint
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.custom_minimum_size.x = 210.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = range_info.x
	slider.max_value = range_info.y
	slider.step = range_info.z
	slider.tooltip_text = hint
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_slider.bind(key))
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 58.0
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	sliders[key] = slider
	value_labels[key] = value

## Slider limits straight from WalkStyle's @export_range hints: {name: (min, max, step)}.
func _property_ranges() -> Dictionary:
	var result: Dictionary = {}
	for info in style.get_property_list():
		if int(info["hint"]) != PROPERTY_HINT_RANGE:
			continue
		var parts: PackedStringArray = str(info["hint_string"]).split(",")
		if parts.size() >= 3:
			result[str(info["name"])] = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return result

func _on_slider(value: float, key: String) -> void:
	_show_value(key, value)
	if _syncing:
		return
	style.set(key, value)
	if not dirty:
		dirty = true
		status_label.text = "Есть несохранённые изменения."

func _show_value(key: String, value: float) -> void:
	var step: float = (sliders[key] as HSlider).step
	(value_labels[key] as Label).text = ("%.3f" if step < 0.01 else ("%.2f" if step < 0.1 else "%.1f")) % value

func _sync_sliders() -> void:
	_syncing = true
	for key in sliders:
		(sliders[key] as HSlider).value = float(style.get(key))
		_show_value(key, float(style.get(key)))
	_syncing = false

func _set_view(mode: String, yaw: float) -> void:
	view_mode = mode
	view_yaw = yaw
	walker.reset(0.0, stage.yaw)
	stage.travel_offset_px = 0.0

func _save() -> void:
	var error: Error = style.save_to_project()
	if error == OK:
		dirty = false
		status_label.text = "Сохранено в animations/walk_style.tres. Перезапусти Хоши — она будет ходить так же."
	else:
		status_label.text = "Не удалось сохранить: " + error_string(error)

func _revert() -> void:
	if ResourceLoader.exists(WalkStyle.PATH):
		var saved: Resource = ResourceLoader.load(WalkStyle.PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		for key in sliders:
			style.set(key, saved.get(key))
	dirty = false
	_sync_sliders()
	status_label.text = "Вернула сохранённую походку."

func _defaults() -> void:
	var fresh: Resource = WalkStyle.defaults()
	for key in sliders:
		style.set(key, fresh.get(key))
	dirty = true
	_sync_sliders()
	status_label.text = "Исходные значения (ещё не сохранены)."
