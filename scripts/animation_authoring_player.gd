@tool
extends AnimationPlayer
## The button saves the same external clip that the desktop companion loads.

const SketchMotion = preload("res://scripts/sketch_motion.gd")
const SeatedMotion = preload("res://scripts/seated_motion.gd")
const PropTracks = preload("res://scripts/prop_track_schema.gd")
const TouchMotion = preload("res://scripts/touch_motion.gd")

@export_tool_button("Проверить и сохранить выбранный клип", "Save") var save_clip = save_animation
@export_tool_button("Показать ключи выбранного клипа", "Animation") var show_keys = show_key_map

func selected_clip_name() -> String:
	var selected: String = assigned_animation
	return selected if selected == "sketch" or SeatedMotion.DURATIONS.has(selected) or TouchMotion.is_touch(selected) else ""

func show_key_map() -> void:
	if not Engine.is_editor_hint():
		return
	var selected: String = selected_clip_name()
	var clip: Animation = get_animation(selected) if not selected.is_empty() else null
	if clip == null:
		_notify("Сначала выбери клип на шкале анимации.", true)
		return
	var popup := Window.new()
	popup.title = "Ключи анимации " + selected
	popup.close_requested.connect(popup.queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	popup.add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	var key_list := TextEdit.new()
	key_list.editable = false
	key_list.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	key_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	key_list.text = key_map_text(clip)
	layout.add_child(key_list)
	var close_button := Button.new()
	close_button.text = "Закрыть"
	close_button.pressed.connect(popup.queue_free)
	layout.add_child(close_button)
	EditorInterface.popup_dialog_centered(popup, Vector2i(800, 520))

func key_map_text(clip: Animation) -> String:
	var lines: Array[String] = [
		"Текущий клип AnimationPlayer · %.2f с" % clip.length,
		"Карта читает открытый клип, включая ещё не сохранённые ключи.",
		"Ромб на шкале = ключ. Линия соединяет ключи; между ними Godot вычисляет движение.",
		"Bones — движение костей. Props — движение предметов. Corrections — твои отдельные поправки.",
		"Спокойная сидячая поза и привязки предметов остаются базой для этих ключей.",
		"Изменение начального или конечного ключа может затронуть весь промежуток.",
		"",
	]
	if clip.resource_name != "sketch":
		lines.insert(2, "Ключи Bones содержат само движение сценки; Corrections содержат дополнительные правки.")
	var grouped: Dictionary = {}
	var group_order: Array[String] = []
	for track in range(clip.get_track_count()):
		var path: String = String(clip.track_get_path(track))
		var group: String = _track_group(path)
		if not grouped.has(group):
			grouped[group] = []
			group_order.append(group)
		var times: Array[String] = []
		var same_value := clip.track_get_key_count(track) > 1
		var first_value: Variant = null
		for key in range(clip.track_get_key_count(track)):
			times.append(String.num(clip.track_get_key_time(track, key), 2))
			var value: Variant = clip.track_get_key_value(track, key)
			if key == 0:
				first_value = value
			elif value != first_value:
				same_value = false
		var row: String = "  %s: %s" % [_track_label(path, clip.track_get_type(track)), ", ".join(times) if not times.is_empty() else "нет ключей"]
		if same_value:
			row += " (значение не меняется)"
		(grouped[group] as Array).append(row)
	for group in group_order:
		lines.append(group)
		for row in grouped[group]:
			lines.append(row)
		lines.append("")
	return "\n".join(lines)

func _track_group(path: String) -> String:
	var bone: String = SketchMotion.bone_semantic(path)
	if not bone.is_empty():
		return "Поза · " + str(SketchMotion.BONE_TARGET_NAMES[bone])
	var descriptor: Dictionary = PropTracks.parse(path, Animation.TYPE_POSITION_3D)
	if descriptor.is_empty():
		descriptor = PropTracks.parse(path, Animation.TYPE_ROTATION_3D)
	if descriptor.is_empty():
		descriptor = PropTracks.parse(path, Animation.TYPE_SCALE_3D)
	if not descriptor.is_empty():
		return str(PropTracks.target_name(str(descriptor["id"])))
	if path == SketchMotion.correction_path("left_hand"):
		return "Поправка левой кисти"
	if path == SketchMotion.correction_path("right_hand"):
		return "Поправка правой кисти"
	match path:
		"Channels:head_pitch": return "Голова"
		"Channels:chest_pitch": return "Корпус"
		"Targets/left_hand": return "Левая ладонь"
		"Targets/right_hand": return "Правая ладонь"
		_: return path

func _track_label(path: String, track_type: Animation.TrackType) -> String:
	if path == "Channels:head_pitch" or path == "Channels:chest_pitch":
		return "Наклон"
	match track_type:
		Animation.TYPE_POSITION_3D: return "Положение"
		Animation.TYPE_ROTATION_3D: return "Поворот"
		Animation.TYPE_SCALE_3D: return "Масштаб"
		_: return "Значение"

func save_animation() -> bool:
	var selected: String = selected_clip_name()
	if selected.is_empty():
		_notify("Сначала выбери клип на шкале анимации.", true)
		return false
	var clip: Animation = get_animation(selected)
	var path: String = SketchMotion.CLIP_PATH if selected == "sketch" else (TouchMotion.path_for(selected) if TouchMotion.is_touch(selected) else SeatedMotion.path_for(selected))
	var problem: String = SketchMotion.validation_error(clip) if selected == "sketch" else (TouchMotion.validation_error(selected, clip) if TouchMotion.is_touch(selected) else SeatedMotion.validation_error(selected, clip))
	if not problem.is_empty():
		_notify("Клип не сохранён: " + problem, true)
		return false
	if clip.resource_path != path:
		_notify("Клип не сохранён: выбранная анимация не связана с " + path, true)
		return false
	var result: Error = ResourceSaver.save(clip, path)
	if result != OK:
		_notify("Не удалось записать " + path + " (код %d)." % result, true)
		return false
	var count: int = 0
	for track in range(clip.get_track_count()):
		count += clip.track_get_key_count(track)
	_notify("Сохранено: %s, %d дорожек, %d ключей." % [selected, clip.get_track_count(), count], false)
	return true

func _notify(message: String, failed: bool) -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_editor_toaster().push_toast(message, EditorToaster.SEVERITY_ERROR if failed else EditorToaster.SEVERITY_INFO)
	else:
		print(message)
