@tool
extends Marker3D
## Records this target's local rotation on the selected clip's rotation track.

const SketchMotion = preload("res://scripts/sketch_motion.gd")

@export_tool_button("Записать поворот в выбранный клип", "Key") var key_rotation = record_rotation_key

func record_rotation_key() -> bool:
	var scene_root: Node = self
	while scene_root != null and not scene_root.has_node("AnimationPlayer"):
		scene_root = scene_root.get_parent()
	if scene_root == null:
		_notify("Не найден AnimationPlayer сцены авторинга.", true)
		return false
	var player: AnimationPlayer = scene_root.get_node("AnimationPlayer") as AnimationPlayer
	var selected: String = player.selected_clip_name() if player != null else ""
	if selected.is_empty():
		_notify("Сначала выбери клип на шкале анимации.", true)
		return false
	var clip: Animation = player.get_animation(selected)
	if clip == null:
		_notify("Выбранный клип не найден.", true)
		return false
	var path: NodePath = scene_root.get_path_to(self)
	var track: int = clip.find_track(path, Animation.TYPE_ROTATION_3D)
	if track < 0:
		_notify("Нет дорожки Rotation 3D для %s." % path, true)
		return false
	var time: float = player.current_animation_position
	if not is_finite(time) or time < 0.0 or time > clip.length:
		_notify("Указатель времени вне клипа %s." % selected, true)
		return false
	var rotation_value: Quaternion = quaternion.normalized()
	var existing_key: int = -1
	for key in range(clip.track_get_key_count(track)):
		if absf(clip.track_get_key_time(track, key) - time) <= 0.005:
			existing_key = key
			time = clip.track_get_key_time(track, key)
			break
	if Engine.is_editor_hint():
		var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Ключ поворота %s · %.2f с" % [path, time])
		if existing_key >= 0:
			var previous_value: Quaternion = clip.track_get_key_value(track, existing_key)
			undo_redo.add_do_method(clip, "track_set_key_value", track, existing_key, rotation_value)
			undo_redo.add_undo_method(clip, "track_set_key_value", track, existing_key, previous_value)
		else:
			undo_redo.add_do_method(clip, "rotation_track_insert_key", track, time, rotation_value)
			undo_redo.add_undo_method(clip, "track_remove_key_at_time", track, time)
		undo_redo.commit_action()
	elif existing_key >= 0:
		clip.track_set_key_value(track, existing_key, rotation_value)
	else:
		clip.rotation_track_insert_key(track, time, rotation_value)
	var written_key: int = clip.track_find_key(track, time, Animation.FIND_MODE_EXACT)
	if written_key < 0 or (clip.track_get_key_value(track, written_key) as Quaternion).angle_to(rotation_value) > 0.001:
		_notify("Поворот не попал в ключ %s на %.2f с." % [path, time], true)
		return false
	var message: String = "Записан Rotation 3D: %s · %.2f с. Сохрани %s через AnimationPlayer." % [path, time, selected]
	if String(path).begins_with("Targets/"):
		var degrees: Vector3 = rotation_degrees
		if maxf(absf(degrees.x), maxf(absf(degrees.y), absf(degrees.z))) > SketchMotion.HAND_ROTATION_LIMIT_DEGREES:
			message += " Видимый поворот кисти ограничен ±%.0f° на ось." % SketchMotion.HAND_ROTATION_LIMIT_DEGREES
	_notify(message, false)
	return true

func _notify(message: String, failed: bool) -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_editor_toaster().push_toast(message, EditorToaster.SEVERITY_ERROR if failed else EditorToaster.SEVERITY_INFO)
	else:
		print(message)
