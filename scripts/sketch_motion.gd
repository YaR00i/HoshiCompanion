@tool
extends RefCounted
## Samples Godot Animation tracks. Pose and prop owners apply the sampled values.

const PropTracks = preload("res://scripts/prop_track_schema.gd")

const CLIP_PATH: String = "res://animations/sketch.tres"
const HAND_ROTATION_LIMIT_DEGREES: float = 35.0
const ACTOR_CHANNELS: PackedStringArray = ["head_pitch", "chest_pitch", "left_hand", "right_hand", "left_hand_rotation", "right_hand_rotation"]
const CORRECTION_TARGET_NAMES := {"left_hand": "Поправка левой кисти", "right_hand": "Поправка правой кисти"}
const BONE_TARGET_NAMES := {
	"chest": "Грудь", "head": "Голова", "neck": "Шея", "spine": "Спина",
	"leftShoulder": "Левая ключица", "leftUpperArm": "Левое плечо", "leftLowerArm": "Левое предплечье", "leftHand": "Левая кисть",
	"rightShoulder": "Правая ключица", "rightUpperArm": "Правое плечо", "rightLowerArm": "Правое предплечье", "rightHand": "Правая кисть",
	"leftLowerLeg": "Левая голень", "leftFoot": "Левая стопа", "rightLowerLeg": "Правая голень", "rightFoot": "Правая стопа",
	# Для реакций на касание (touch_motion.gd): таз, бёдра, пальцы (1 — у ладони).
	"hips": "Таз", "leftUpperLeg": "Левое бедро", "rightUpperLeg": "Правое бедро",
	"leftThumbMetacarpal": "Левый большой 1", "leftThumbProximal": "Левый большой 2", "leftThumbDistal": "Левый большой 3", "leftIndexProximal": "Левый указательный 1", "leftIndexIntermediate": "Левый указательный 2", "leftIndexDistal": "Левый указательный 3", "leftMiddleProximal": "Левый средний 1", "leftMiddleIntermediate": "Левый средний 2", "leftMiddleDistal": "Левый средний 3", "leftRingProximal": "Левый безымянный 1", "leftRingIntermediate": "Левый безымянный 2", "leftRingDistal": "Левый безымянный 3", "leftLittleProximal": "Левый мизинец 1", "leftLittleIntermediate": "Левый мизинец 2", "leftLittleDistal": "Левый мизинец 3",
	"rightThumbMetacarpal": "Правый большой 1", "rightThumbProximal": "Правый большой 2", "rightThumbDistal": "Правый большой 3", "rightIndexProximal": "Правый указательный 1", "rightIndexIntermediate": "Правый указательный 2", "rightIndexDistal": "Правый указательный 3", "rightMiddleProximal": "Правый средний 1", "rightMiddleIntermediate": "Правый средний 2", "rightMiddleDistal": "Правый средний 3", "rightRingProximal": "Правый безымянный 1", "rightRingIntermediate": "Правый безымянный 2", "rightRingDistal": "Правый безымянный 3", "rightLittleProximal": "Правый мизинец 1", "rightLittleIntermediate": "Правый мизинец 2", "rightLittleDistal": "Правый мизинец 3",
}
static var clip: Animation = preload(CLIP_PATH)

static func prop_path(prop_id: String, property: String) -> String:
	return PropTracks.path_for(prop_id, property)

static func actor_path(channel: String) -> String:
	if channel in ["left_hand", "right_hand", "left_hand_rotation", "right_hand_rotation"]:
		return "Targets/%s" % channel.trim_suffix("_rotation")
	return "Channels:" + channel

static func correction_path(channel: String) -> String:
	if channel in ["left_hand", "right_hand", "left_hand_rotation", "right_hand_rotation"]:
		var hand: String = channel.trim_suffix("_rotation")
		return "Corrections/%s/%s" % [hand, CORRECTION_TARGET_NAMES[hand]]
	return actor_path(channel)

static func bone_path(semantic: String) -> String:
	return "Bones/%s/%s" % [semantic, BONE_TARGET_NAMES.get(semantic, "Target")]

static func bone_semantic(path: String) -> String:
	if not path.begins_with("Bones/"):
		return ""
	for semantic in BONE_TARGET_NAMES:
		if path == bone_path(semantic):
			return semantic
	return ""

static func actor_type(channel: String) -> int:
	if channel in ["left_hand", "right_hand"]:
		return Animation.TYPE_POSITION_3D
	if channel in ["left_hand_rotation", "right_hand_rotation"]:
		return Animation.TYPE_ROTATION_3D
	return Animation.TYPE_VALUE

static func actor_channel(path: String, track_type: int) -> String:
	if path.begins_with("Channels:") and track_type == Animation.TYPE_VALUE:
		return path.trim_prefix("Channels:")
	for channel in ["left_hand", "right_hand", "left_hand_rotation", "right_hand_rotation"]:
		if path in [actor_path(channel), correction_path(channel)] and track_type == actor_type(channel):
			return channel
	return ""

static func reload_clip() -> bool:
	var loaded: Animation = ResourceLoader.load(CLIP_PATH, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
	if loaded == null or not valid(loaded):
		return false
	clip = loaded
	return true

static func valid(candidate: Animation) -> bool:
	return validation_error(candidate).is_empty()

static func validation_error(candidate: Animation) -> String:
	if candidate == null or not is_equal_approx(candidate.length, 10.0):
		return "Неверная длительность клипа."
	var seen: Dictionary = {}
	for track in range(candidate.get_track_count()):
		if not candidate.track_is_enabled(track):
			return "Выключена дорожка %d." % track
		var path: String = str(candidate.track_get_path(track))
		var track_type: int = candidate.track_get_type(track)
		if ignored_editor_track(path, track_type):
			continue
		if candidate.track_get_key_count(track) < 2:
			return "На дорожке %s нужно минимум два ключа." % path
		var channel: String = actor_channel(path, track_type)
		if not channel.is_empty():
			if not ACTOR_CHANNELS.has(channel) or seen.has(channel):
				return "Повторяется дорожка %s." % path
			seen[channel] = true
		elif path.begins_with("Props/"):
			var descriptor: Dictionary = PropTracks.parse(path, track_type)
			if descriptor.is_empty():
				return "Неизвестный тип дорожки предмета: %s." % path
			var prop_key: String = "%s:%s" % [descriptor["id"], descriptor["property"]]
			if seen.has(prop_key):
				return "Повторяется дорожка предмета: %s." % path
			seen[prop_key] = true
		else:
			return "Неизвестная дорожка: %s (тип %d)." % [path, track_type]
	for channel in ACTOR_CHANNELS:
		if not seen.has(channel):
			return "Отсутствует дорожка: %s." % channel
	return ""

static func sample(progress: float) -> Dictionary:
	if not valid(clip):
		return {}
	return sample_animation(clip, progress)

static func sample_animation(candidate: Animation, progress: float, position_offsets: bool = false) -> Dictionary:
	if candidate == null:
		return {}
	var result: Dictionary = {"props": {}, "bones": {}}
	var time: float = clampf(progress, 0.0, 1.0) * candidate.length
	for track in range(candidate.get_track_count()):
		var path: String = str(candidate.track_get_path(track))
		var track_type: int = candidate.track_get_type(track)
		if ignored_editor_track(path, track_type):
			continue
		if path.begins_with("Bones/") and track_type == Animation.TYPE_ROTATION_3D:
			var semantic: String = bone_semantic(path)
			if semantic.is_empty():
				return {}
			result["bones"][semantic] = candidate.rotation_track_interpolate(track, time)
			continue
		var value: Variant = _interpolate(candidate, track, time)
		var channel: String = actor_channel(path, track_type)
		if not channel.is_empty():
			if channel in ["head_pitch", "chest_pitch"]:
				if not value is float and not value is int or not is_finite(float(value)):
					return {}
				result[channel] = clampf(float(value), -25.0 if channel == "head_pitch" else -15.0, 25.0 if channel == "head_pitch" else 15.0)
			else:
				if track_type == Animation.TYPE_ROTATION_3D:
					value = (value as Quaternion).get_euler() * (180.0 / PI)
				if not value is Vector3 or not (value as Vector3).is_finite():
					return {}
				var v: Vector3 = value
				if channel.ends_with("_rotation"):
					result[channel] = v.clamp(Vector3.ONE * -HAND_ROTATION_LIMIT_DEGREES, Vector3.ONE * HAND_ROTATION_LIMIT_DEGREES)
				else:
					result[channel] = v.clamp(Vector3(-0.20, -0.20, -0.40 if position_offsets else 0.10), Vector3(0.20, 0.25, 0.40))
		else:
			var descriptor: Dictionary = PropTracks.parse(path, track_type)
			if track_type == Animation.TYPE_ROTATION_3D:
				value = (value as Quaternion).get_euler() * (180.0 / PI)
			var prop_value: Variant = PropTracks.clamped_value(str(descriptor["property"]), value)
			if prop_value == null:
				return {}
			var prop_id: String = str(descriptor["id"])
			var property: String = str(descriptor["property"])
			var props: Dictionary = result["props"]
			var prop_sample: Dictionary = props.get(prop_id, {})
			prop_sample[property] = prop_value
			props[prop_id] = prop_sample
			result["props"] = props
	return result

static func ignored_editor_track(path: String, track_type: int) -> bool:
	return track_type == Animation.TYPE_SCALE_3D and path in ["Targets/left_hand", "Targets/right_hand", correction_path("left_hand"), correction_path("right_hand")]

static func _interpolate(animation: Animation, track: int, time: float) -> Variant:
	match animation.track_get_type(track):
		Animation.TYPE_VALUE: return animation.value_track_interpolate(track, time)
		Animation.TYPE_POSITION_3D: return animation.position_track_interpolate(track, time)
		Animation.TYPE_ROTATION_3D: return animation.rotation_track_interpolate(track, time)
		Animation.TYPE_SCALE_3D: return animation.scale_track_interpolate(track, time)
	return null
