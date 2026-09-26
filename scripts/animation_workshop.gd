extends Control
## Live pose/prop authoring over Godot Animation tracks; no direct bone ownership.

const Stage = preload("res://scripts/avatar_stage.gd")
const State = preload("res://scripts/companion_state.gd")
const SketchMotion = preload("res://scripts/sketch_motion.gd")
const KeyEditor = preload("res://scripts/motion_key_editor.gd")
const Guides = preload("res://scripts/workshop_guides.gd")
const PropTracks = preload("res://scripts/prop_track_schema.gd")
const MODEL_PATH: String = "res://assets/Hoshi_v1.vrm"
const ACTOR_CHANNELS: Array[Dictionary] = [
	{"key": "left_hand", "title": "Левая ладонь · цель", "kind": "position"},
	{"key": "right_hand", "title": "Правая ладонь · цель", "kind": "position"},
	{"key": "left_hand_rotation", "title": "Левая ладонь · поворот", "kind": "rotation"},
	{"key": "right_hand_rotation", "title": "Правая ладонь · поворот", "kind": "rotation"},
	{"key": "head_pitch", "title": "Голова · наклон", "kind": "scalar"},
	{"key": "chest_pitch", "title": "Корпус · наклон", "kind": "scalar"},
]

var stage
var state
var guides
var slider: HSlider
var play_button: Button
var time_label: Label
var status_label: Label
var choice: OptionButton
var channel_entries: Array[Dictionary] = []
var field_rows: Array[HBoxContainer] = []
var field_labels: Array[Label] = []
var field_values: Array[SpinBox] = []
var explanation_label: Label
var save_button: Button
var undo_button: Button
var playing: bool = false
var cursor: float = 0.0
var dirty: bool = false
var _sync_fields: bool = false
var _undo_stack: Array[Animation] = []

func _ready() -> void:
	$EditorGuide.hide()
	SketchMotion.clip = SketchMotion.clip.duplicate(true) as Animation
	get_window().title = "Hoshi — мастерская анимаций"
	get_window().size = Vector2i(1300, 850)
	_build_ui()
	state = State.new()
	state.autonomy_enabled = false
	state.motion_enabled = false
	state.edge_activity = "calm"
	state.posture.kind = "edge"
	state.posture.target_seated = true
	state.posture._progress = 1.0
	state.posture.amount = 1.0
	state.posture.mode = "seated"
	stage.cozy_corner_active = true
	stage.animation_workshop_progress = 0.0
	var loaded: Dictionary = stage.load_model(MODEL_PATH)
	if loaded.has("error"):
		status_label.text = str(loaded["error"])
		return
	stage.configure_frame(590.0, 70.0)
	_collect_channel_entries()
	status_label.text = "Выбери момент, затем предмет или часть позы справа. Мелок тоже доступен."
	_refresh_fields()
	_render()

func _process(delta: float) -> void:
	if not playing or stage == null or not stage.is_loaded:
		return
	cursor = fposmod(cursor + delta, SketchMotion.clip.length)
	slider.set_value_no_signal(cursor)
	_refresh_fields()
	_render()

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
	preview.custom_minimum_size = Vector2(760.0, 770.0)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(preview)
	var preview_area := Control.new()
	preview_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_child(preview_area)
	stage = Stage.new()
	preview_area.add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	guides = Guides.new()
	guides.stage = stage
	preview_area.add_child(guides)
	guides.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 430.0
	controls.add_theme_constant_override("separation", 10)
	layout.add_child(controls)
	var title := Label.new()
	title.text = "Мастерская анимаций"
	title.add_theme_font_size_override("font_size", 24)
	controls.add_child(title)
	var help := Label.new()
	help.text = "Выбери момент, затем предмет или ладонь. Числа меняют позу сразу; «Сохранить» запишет ключи в анимацию."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(help)
	play_button = Button.new()
	play_button.text = "▶ Воспроизвести"
	play_button.pressed.connect(_toggle_play)
	controls.add_child(play_button)
	slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = SketchMotion.clip.length
	slider.step = 0.01
	slider.value_changed.connect(_on_scrub)
	controls.add_child(slider)
	time_label = Label.new()
	controls.add_child(time_label)
	var jumps := HBoxContainer.new()
	controls.add_child(jumps)
	for entry in [{"name": "Рисует · 3 с", "time": 3.0}, {"name": "Показывает · 8.2 с", "time": 8.2}]:
		var button := Button.new()
		button.text = str(entry["name"])
		button.pressed.connect(_jump_to.bind(float(entry["time"])))
		jumps.add_child(button)
	var views := HBoxContainer.new()
	controls.add_child(views)
	for entry in [{"name": "Спереди", "yaw": 0.0}, {"name": "¾", "yaw": 35.0}, {"name": "Сбоку", "yaw": 70.0}]:
		var button := Button.new()
		button.text = str(entry["name"])
		button.pressed.connect(_set_view.bind(float(entry["yaw"])))
		views.add_child(button)
	var guide_button := CheckButton.new()
	guide_button.text = "Показать точки рук и предметов"
	guide_button.button_pressed = true
	guide_button.toggled.connect(_toggle_guides)
	controls.add_child(guide_button)
	var separator := HSeparator.new()
	controls.add_child(separator)
	choice = OptionButton.new()
	choice.item_selected.connect(_on_channel_selected)
	controls.add_child(choice)
	for axis in range(3):
		var row := HBoxContainer.new()
		controls.add_child(row)
		field_rows.append(row)
		var label := Label.new()
		label.custom_minimum_size.x = 165.0
		row.add_child(label)
		field_labels.append(label)
		var field := SpinBox.new()
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.step = 0.1
		field.value_changed.connect(_on_field_changed.bind(axis))
		row.add_child(field)
		field_values.append(field)
	explanation_label = Label.new()
	explanation_label.text = "Оранжевое — край блокнота, голубое — цель ладони, зелёное — кисть."
	explanation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(explanation_label)
	var actions := HBoxContainer.new()
	controls.add_child(actions)
	undo_button = Button.new()
	undo_button.text = "Отменить"
	undo_button.disabled = true
	undo_button.pressed.connect(_undo)
	actions.add_child(undo_button)
	save_button = Button.new()
	save_button.text = "Сохранить анимацию"
	save_button.disabled = true
	save_button.pressed.connect(_save_clip)
	actions.add_child(save_button)
	var reload_button := Button.new()
	reload_button.text = "Перечитать файл с диска"
	reload_button.pressed.connect(_reload_clip)
	controls.add_child(reload_button)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(status_label)

func _collect_channel_entries() -> void:
	channel_entries.clear()
	choice.clear()
	var seen: Dictionary = {}
	for prop in stage.animation_props():
		if not prop.prop_id.is_valid_identifier() or seen.has(prop.prop_id):
			push_warning("Invalid or duplicate animation prop id: " + prop.prop_id)
			continue
		seen[prop.prop_id] = true
		if $Props.get_node_or_null(prop.prop_id) == null:
			var mirror := Node3D.new()
			mirror.name = prop.prop_id
			$Props.add_child(mirror)
			var target := Node3D.new()
			target.name = "Target"
			mirror.add_child(target)
		for property in PropTracks.PROPERTIES:
			var title: String = "положение" if property == "position" else "поворот" if property == "rotation_degrees" else "масштаб"
			channel_entries.append({"key": prop.prop_id, "title": prop.display_name + " · " + title, "kind": "rotation" if property == "rotation_degrees" else property, "property": property, "prop": prop})
	for entry in ACTOR_CHANNELS:
		channel_entries.append(entry)
	for entry in channel_entries:
		choice.add_item(str(entry["title"]))
	if not channel_entries.is_empty():
		choice.select(0)
		guides.selected_prop_id = str(channel_entries[0]["key"]) if channel_entries[0].has("prop") else ""

func _entry_value(entry: Dictionary, sampled: Dictionary) -> Variant:
	if entry.has("prop"):
		var prop = entry["prop"]
		var prop_sample: Dictionary = sampled.get("props", {}).get(prop.prop_id, {})
		return prop_sample.get(entry["property"], prop.default_value(entry["property"]))
	return sampled.get(entry["key"])

func _render() -> void:
	if stage == null or not stage.is_loaded:
		return
	stage.animation_workshop_progress = cursor / SketchMotion.clip.length
	state.time = cursor
	stage.animate(0.0, state, Vector2.ZERO)
	time_label.text = "%.2f / %.2f сек" % [cursor, SketchMotion.clip.length]
	guides.queue_redraw()

func _refresh_fields() -> void:
	if stage == null or not stage.is_loaded or choice == null or choice.selected < 0:
		return
	var entry: Dictionary = channel_entries[choice.selected]
	var kind: String = str(entry["kind"])
	var anchor_text: String = "таза"
	if entry.has("prop"):
		match str(entry["prop"].anchor_bone):
			"rightHand": anchor_text = "правой кисти"
			"leftHand": anchor_text = "левой кисти"
	explanation_label.text = ("X — вбок, Y — вверх, Z — вперёд; сантиметры относительно %s. " % anchor_text if kind == "position" else "X/Y/Z — поворот выбранной части в градусах. " if kind == "rotation" else "Наклон в градусах. ") + "Оранжевое — предмет, голубое — цель ладони, зелёное — кисть."
	var sampled: Dictionary = SketchMotion.sample(cursor / SketchMotion.clip.length)
	var value: Variant = _entry_value(entry, sampled)
	if value == null:
		return
	_sync_fields = true
	if kind == "scale":
		explanation_label.text = "Масштаб предмета: 1 — исходный размер. Оранжевое — предмет, голубое — цель ладони, зелёное — кисть."
	for axis in range(3):
		field_rows[axis].visible = kind != "scalar" or axis == 0
		if not field_rows[axis].visible:
			continue
		field_labels[axis].text = "Наклон" if kind == "scalar" else (["X · вбок", "Y · вверх", "Z · вперёд"][axis] if kind == "position" else ["X · размер", "Y · размер", "Z · размер"][axis] if kind == "scale" else ["X · наклон", "Y · поворот", "Z · крен"][axis])
		var bounds: Vector2 = _bounds(entry, axis)
		field_values[axis].min_value = floorf(bounds.x)
		field_values[axis].max_value = ceilf(bounds.y)
		field_values[axis].suffix = " см" if kind == "position" else "×" if kind == "scale" else "°"
		var component: float = float(value) if kind == "scalar" else _component(value as Vector3, axis)
		field_values[axis].set_value_no_signal(component * stage.model_height * 100.0 if kind == "position" else component)
	_sync_fields = false

func _bounds(entry: Dictionary, axis: int) -> Vector2:
	var key: String = str(entry["key"])
	if entry.has("prop"):
		match str(entry["property"]):
			"rotation_degrees": return Vector2(-180.0, 180.0)
			"scale": return Vector2(0.0, 4.0)
			"position": return Vector2(-100.0, 100.0) * stage.model_height
	if key == "head_pitch":
		return Vector2(-25.0, 25.0)
	if key == "chest_pitch":
		return Vector2(-15.0, 15.0)
	if key in ["left_hand_rotation", "right_hand_rotation"]:
		return Vector2(-35.0, 35.0)
	var scale: float = stage.model_height * 100.0
	if axis == 2:
		return Vector2(0.10 * scale, 0.40 * scale)
	return Vector2(-0.20 * scale, (0.25 if axis == 1 else 0.20) * scale)

func _component(value: Vector3, axis: int) -> float:
	match axis:
		0: return value.x
		1: return value.y
	return value.z

func _with_component(value: Vector3, axis: int, component: float) -> Vector3:
	match axis:
		0: value.x = component
		1: value.y = component
		2: value.z = component
	return value

func _on_field_changed(value: float, axis: int) -> void:
	if _sync_fields or stage == null or not stage.is_loaded:
		return
	playing = false
	play_button.text = "▶ Воспроизвести"
	var entry: Dictionary = channel_entries[choice.selected]
	var key: String = str(entry["key"])
	var kind: String = str(entry["kind"])
	var sampled: Dictionary = SketchMotion.sample(cursor / SketchMotion.clip.length)
	var previous: Variant = _entry_value(entry, sampled)
	if previous == null:
		return
	var authored: Variant = value if kind == "scalar" else _with_component(previous as Vector3, axis, value / (stage.model_height * 100.0) if kind == "position" else value)
	if authored == previous:
		return
	_undo_stack.append(SketchMotion.clip.duplicate(true) as Animation)
	if _undo_stack.size() > 20:
		_undo_stack.pop_front()
	var changed: bool = KeyEditor.put_prop_value(SketchMotion.clip, key, str(entry["property"]), cursor, authored as Vector3, entry["prop"].default_value(entry["property"])) if entry.has("prop") else KeyEditor.put_value(SketchMotion.clip, key, cursor, authored)
	if not changed:
		_undo_stack.pop_back()
		status_label.text = "Не удалось изменить ключ кадра."
		return
	dirty = true
	_update_actions()
	status_label.text = "Изменение видно сразу. Нажми «Сохранить анимацию», когда результат устроит."
	_render()

func _update_actions() -> void:
	undo_button.disabled = _undo_stack.is_empty()
	save_button.disabled = not dirty

func _on_channel_selected(_index: int) -> void:
	_refresh_fields()
	var entry: Dictionary = channel_entries[choice.selected]
	guides.selected_prop_id = str(entry["key"]) if entry.has("prop") else ""
	guides.queue_redraw()

func _toggle_play() -> void:
	playing = not playing
	play_button.text = "Ⅱ Пауза" if playing else "▶ Воспроизвести"

func _on_scrub(value: float) -> void:
	cursor = value
	playing = false
	play_button.text = "▶ Воспроизвести"
	_refresh_fields()
	_render()

func _jump_to(value: float) -> void:
	slider.value = value

func _set_view(value: float) -> void:
	stage.yaw = value
	_render()

func _toggle_guides(enabled: bool) -> void:
	guides.enabled = enabled
	guides.queue_redraw()

func _undo() -> void:
	if _undo_stack.is_empty():
		return
	SketchMotion.clip = _undo_stack.pop_back()
	dirty = true
	_update_actions()
	_refresh_fields()
	_render()
	status_label.text = "Последняя правка отменена. Для записи изменений нажми «Сохранить анимацию»."

func _save_clip() -> void:
	if not SketchMotion.valid(SketchMotion.clip):
		status_label.text = "Анимация повреждена: обязательные дорожки позы и десятисекундный клип должны сохраниться."
		return
	var result: Error = ResourceSaver.save(SketchMotion.clip, SketchMotion.CLIP_PATH)
	if result != OK:
		status_label.text = "Не удалось сохранить файл анимации (код %d)." % result
		return
	dirty = false
	_update_actions()
	status_label.text = "Сохранено. Обычная Хоши использует новые кадры при следующем запуске."

func _reload_clip() -> void:
	if dirty:
		status_label.text = "Есть несохранённые правки. Сохрани их или отмени перед перечитыванием файла."
		return
	if SketchMotion.reload_clip():
		SketchMotion.clip = SketchMotion.clip.duplicate(true) as Animation
		_undo_stack.clear()
		_update_actions()
		slider.max_value = SketchMotion.clip.length
		_refresh_fields()
		_render()
		status_label.text = "Сохранённая анимация загружена."
	else:
		status_label.text = "Не удалось загрузить анимацию: проверь дорожки позы и длину клипа."
