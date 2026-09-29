@tool
extends Marker3D
## Records this target's local rotation on the selected clip's rotation track.

const SketchMotion = preload("res://scripts/sketch_motion.gd")

@export_tool_button("Записать поворот в выбранный клип", "Key") var key_rotation = record_rotation_key

# Кольцо-контроллер кости (рисует addons/hoshi_authoring). Заполняет сцена авторинга
# при загрузке модели; в файл сцены не сохраняется.
var ring_axis: Vector3 = Vector3.UP   # вдоль кости, в её локальных осях
var ring_length: float = 0.1          # длина кости, м
var ring_radius: float = 0.03         # радиус кольца, м
var ring_side: int = 0                # 1 — левая сторона, -1 — правая, 0 — центр
var ring_small: bool = false          # пальцы, глаза: тонкое кольцо без «палочки»
var tracked: bool = false:            # у кости есть дорожка в выбранном клипе
	set(value):
		if tracked != value:
			tracked = value
			update_gizmos()

func set_ring(axis: Vector3, length: float, radius: float, side: int, small: bool) -> void:
	ring_axis = axis.normalized() if axis.length() > 0.0001 else Vector3.UP
	ring_length = length
	ring_radius = radius
	ring_side = side
	ring_small = small
	update_gizmos()

## Автоключ (addons/hoshi_authoring): кольцо повёрнуто не так, как говорит клип
## на текущем времени (или вообще повёрнуто, если у кости ещё нет дорожки).
func needs_key() -> bool:
	var scene_root: Node = _scene_root()
	var player: AnimationPlayer = scene_root.get_node("AnimationPlayer") as AnimationPlayer if scene_root != null else null
	var selected: String = player.selected_clip_name() if player != null else ""
	if selected.is_empty() or selected == "sketch":
		return false
	var clip: Animation = player.get_animation(selected)
	if clip == null:
		return false
	var track: int = clip.find_track(scene_root.get_path_to(self), Animation.TYPE_ROTATION_3D)
	var expected: Quaternion = clip.rotation_track_interpolate(track, player.current_animation_position) if track >= 0 else Quaternion.IDENTITY
	return rad_to_deg(expected.angle_to(quaternion.normalized())) > 0.05

func _scene_root() -> Node:
	var scene_root: Node = self
	while scene_root != null and not scene_root.has_node("AnimationPlayer"):
		scene_root = scene_root.get_parent()
	return scene_root

func record_rotation_key(quiet: bool = false) -> bool:
	var scene_root: Node = _scene_root()
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
	if track < 0 and not String(path).begins_with("Bones/"):
		_notify("Нет дорожки Rotation 3D для %s." % path, true)
		return false
	var time: float = player.current_animation_position
	if not is_finite(time) or time < 0.0 or time > clip.length:
		_notify("Указатель времени вне клипа %s." % selected, true)
		return false
	var rotation_value: Quaternion = quaternion.normalized()
	if track < 0:
		# Кость без дорожки: создать её — покой в начале и в конце клипа, поворот сейчас.
		if Engine.is_editor_hint():
			var undo_new: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
			undo_new.create_action("Новая дорожка %s · %.2f с" % [path, time])
			undo_new.add_do_method(self, "_add_bone_track", clip, path, time, rotation_value)
			undo_new.add_undo_method(self, "_remove_track", clip, path)
			undo_new.commit_action()
		else:
			_add_bone_track(clip, path, time, rotation_value)
		track = clip.find_track(path, Animation.TYPE_ROTATION_3D)
		if track < 0:
			_notify("Не удалось создать дорожку %s." % path, true)
			return false
		_notify("Новая дорожка: %s (покой в начале и в конце, поворот на %.2f с). Сохрани %s через AnimationPlayer." % [path, time, selected], false)
		return true
	var existing_key: int = -1
	for key in range(clip.track_get_key_count(track)):
		if absf(clip.track_get_key_time(track, key) - time) <= 0.005:
			existing_key = key
			time = clip.track_get_key_time(track, key)
			break
	if Engine.is_editor_hint():
		var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Ключ поворота %s · %.2f с" % [path, time])
		# Первым объектом идёт сам узел: ключ попадает в историю сцены, рядом с
		# поворотом кольца, — Ctrl+Z сначала снимает ключ, потом поворот.
		if existing_key >= 0:
			var previous_value: Quaternion = clip.track_get_key_value(track, existing_key)
			undo_redo.add_do_method(self, "_set_key", clip, track, existing_key, rotation_value)
			undo_redo.add_undo_method(self, "_set_key", clip, track, existing_key, previous_value)
		else:
			undo_redo.add_do_method(self, "_insert_key", clip, track, time, rotation_value)
			undo_redo.add_undo_method(self, "_remove_key", clip, track, time)
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
	if not quiet:
		_notify(message, false)
	return true

func _set_key(clip: Animation, track: int, key: int, value: Quaternion) -> void:
	clip.track_set_key_value(track, key, value)

func _insert_key(clip: Animation, track: int, time: float, value: Quaternion) -> void:
	clip.rotation_track_insert_key(track, time, value)

func _remove_key(clip: Animation, track: int, time: float) -> void:
	clip.track_remove_key_at_time(track, time)

func _add_bone_track(clip: Animation, path: NodePath, time: float, value: Quaternion) -> void:
	var interpolation: int = Animation.INTERPOLATION_CUBIC
	for other in range(clip.get_track_count()):
		if str(clip.track_get_path(other)).begins_with("Bones/"):
			interpolation = clip.track_get_interpolation_type(other)
			break
	var track: int = clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(track, path)
	clip.track_set_interpolation_type(track, interpolation)
	clip.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
	clip.rotation_track_insert_key(track, clip.length, Quaternion.IDENTITY)
	clip.rotation_track_insert_key(track, time, value) # на 0 или в конце заменит покой
	tracked = true

func _remove_track(clip: Animation, path: NodePath) -> void:
	var track: int = clip.find_track(path, Animation.TYPE_ROTATION_3D)
	if track >= 0:
		clip.remove_track(track)
	tracked = false

func _notify(message: String, failed: bool) -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_editor_toaster().push_toast(message, EditorToaster.SEVERITY_ERROR if failed else EditorToaster.SEVERITY_INFO)
	else:
		print(message)
