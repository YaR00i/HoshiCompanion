@tool
extends RefCounted
## Клипы реакций на касание (стоя): animations/touch_<место>.tres — правятся в
## «Позах и сценках в Godot» (animation_authoring_3d.tscn), как сценки на краю.
##
## Дорожки:
##   Bones/<кость>/<подпись>  Rotation 3D — поворот кости поверх обычной позы стоя
##                           (кисти, пальцы, ноги, таз — все кости из BONE_TARGET_NAMES);
##   Channels:touch_yaw      — поворот всего тела, градусы («отвернулась», «кружится»);
##   Channels:hips_offset    — сдвиг таза (доли роста: x — вбок, y — вверх, z — вперёд);
##   Channels:face_happy, Channels:face_angry — выражение лица (0…1).
## Первые клипы запечены из кодовых реакций (tools/bake_touch_clips.gd); нет клипа —
## Хоши играет реакцию кодом (touch_reactions.gd). Сидя — всегда кодом.

const SketchMotion = preload("res://scripts/sketch_motion.gd")

## Место касания -> длительность клипа, с.
const ZONES := {"leg": 2.6, "arm": 2.9, "belly": 2.4, "chest": 3.4, "hips": 2.4}
const CHANNELS := ["touch_yaw", "hips_offset", "face_happy", "face_angry"]

static var _cache: Dictionary = {}

static func clip_name(zone: String) -> String:
	return "touch_" + zone

static func zone_of(name: String) -> String:
	return name.trim_prefix("touch_") if name.begins_with("touch_") and ZONES.has(name.trim_prefix("touch_")) else ""

static func is_touch(name: String) -> bool:
	return not zone_of(name).is_empty()

static func path_for(name: String) -> String:
	return "res://animations/%s.tres" % name if is_touch(name) else ""

## Клип этого места (или null — нет файла / не проходит проверку).
static func clip_for(zone: String) -> Animation:
	if _cache.has(zone):
		return _cache[zone]
	var path: String = path_for(clip_name(zone))
	var clip: Animation = null
	if not path.is_empty() and ResourceLoader.exists(path):
		clip = load(path) as Animation
		if clip != null and not validation_error(clip_name(zone), clip).is_empty():
			push_warning("Клип касания отклонён: " + validation_error(clip_name(zone), clip))
			clip = null
	_cache[zone] = clip
	return clip

static func forget_cache() -> void:
	_cache.clear()

static func validation_error(name: String, clip: Animation) -> String:
	var zone: String = zone_of(name)
	if zone.is_empty() or clip == null:
		return "Неизвестная реакция на касание."
	if not is_equal_approx(clip.length, float(ZONES[zone])):
		return "Длительность %s должна быть %.2f с." % [name, ZONES[zone]]
	var seen: Dictionary = {}
	for track in range(clip.get_track_count()):
		var path: String = str(clip.track_get_path(track))
		if SketchMotion.ignored_editor_track(path, clip.track_get_type(track)):
			continue
		if not clip.track_is_enabled(track) or clip.track_get_key_count(track) < 2:
			return "На каждой дорожке нужно хотя бы два активных ключа: %s." % path
		if seen.has(path):
			return "Повторная дорожка: %s." % path
		seen[path] = true
		if path.begins_with("Bones/"):
			if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D or SketchMotion.bone_semantic(path).is_empty():
				return "Неизвестная кость или не поворот: %s." % path
		elif path.begins_with("Channels:"):
			if clip.track_get_type(track) != Animation.TYPE_VALUE or not path.trim_prefix("Channels:") in CHANNELS:
				return "Неизвестный канал: %s." % path
		else:
			return "Лишняя дорожка: %s." % path
	return ""

## Кадр клипа: {"bones": {кость: Quaternion}, "yaw": градусы, "hips_offset": Vector3,
## "face": {"happy": f, "angry": f}}.
static func sample(clip: Animation, time: float) -> Dictionary:
	var result: Dictionary = {"bones": {}, "yaw": 0.0, "hips_offset": Vector3.ZERO, "face": {}}
	if clip == null:
		return result
	var t: float = clampf(time, 0.0, clip.length)
	for track in range(clip.get_track_count()):
		if not clip.track_is_enabled(track):
			continue
		var path: String = str(clip.track_get_path(track))
		if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			var semantic: String = SketchMotion.bone_semantic(path)
			if not semantic.is_empty():
				result["bones"][semantic] = clip.rotation_track_interpolate(track, t).normalized()
		elif clip.track_get_type(track) == Animation.TYPE_VALUE:
			var value: Variant = clip.value_track_interpolate(track, t)
			match path.trim_prefix("Channels:"):
				"touch_yaw":
					result["yaw"] = float(value)
				"hips_offset":
					result["hips_offset"] = value if value is Vector3 else Vector3.ZERO
				"face_happy":
					result["face"]["happy"] = clampf(float(value), 0.0, 1.0)
				"face_angry":
					result["face"]["angry"] = clampf(float(value), 0.0, 1.0)
	return result
