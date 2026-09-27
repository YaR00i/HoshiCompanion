@tool
extends RefCounted
## Editable seated gesture keys and optional corrections. EdgePose remains the bone owner.

const SketchMotion = preload("res://scripts/sketch_motion.gd")
const PropTracks = preload("res://scripts/prop_track_schema.gd")

const DURATIONS := {
	"swing": 7.25,
	"lean": 14.0,
	"peek": 4.0,
	"balance": 3.6,
	"sway": 8.0,
	"hum": 5.35,
	"nod": 5.25,
	"fold": 8.5,
	"admire_star": 3.6,
}

## Rhythmic clips are seamless loops: they repeat while the gesture lasts and keep
## moving while they fade out, so there is never a frozen last frame.
## tools/rebake_seated_loops.gd rebuilds them from the reference motion in edge_pose.gd.
const LOOPING: Array[String] = ["sway", "swing", "hum", "nod", "balance"]

const CLIPS := {
	"swing": preload("res://animations/swing.tres"),
	"lean": preload("res://animations/lean.tres"),
	"peek": preload("res://animations/peek.tres"),
	"balance": preload("res://animations/balance.tres"),
	"sway": preload("res://animations/sway.tres"),
	"hum": preload("res://animations/hum.tres"),
	"nod": preload("res://animations/nod.tres"),
	"fold": preload("res://animations/fold.tres"),
	"admire_star": preload("res://animations/admire_star.tres"),
}

static func kinds() -> Array[String]:
	var result: Array[String] = []
	for kind in DURATIONS:
		result.append(kind)
	return result

static func loops(kind: String) -> bool:
	return kind in LOOPING

static func path_for(kind: String) -> String:
	return "res://animations/%s.tres" % kind if DURATIONS.has(kind) else ""

static func clip_for(kind: String) -> Animation:
	return CLIPS.get(kind) as Animation

static func validation_error(kind: String, clip: Animation) -> String:
	if not DURATIONS.has(kind) or clip == null:
		return "Неизвестная сидячая сценка."
	if not is_equal_approx(clip.length, float(DURATIONS[kind])):
		return "Длительность %s должна быть %.2f с." % [kind, DURATIONS[kind]]
	var seen: Dictionary = {}
	for track in range(clip.get_track_count()):
		if SketchMotion.ignored_editor_track(str(clip.track_get_path(track)), clip.track_get_type(track)):
			continue
		if not clip.track_is_enabled(track) or clip.track_get_key_count(track) < 2:
			return "На каждой дорожке нужно хотя бы два активных ключа."
		var channel: String = SketchMotion.actor_channel(str(clip.track_get_path(track)), clip.track_get_type(track))
		if not channel.is_empty():
			if seen.has(channel):
				return "Повторная дорожка: %s." % clip.track_get_path(track)
			seen[channel] = true
		elif str(clip.track_get_path(track)).begins_with("Bones/") and clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			var bone_path: String = str(clip.track_get_path(track))
			if SketchMotion.bone_semantic(bone_path).is_empty() or seen.has(bone_path):
				return "Неизвестная или повторная кость: %s." % clip.track_get_path(track)
			seen[bone_path] = true
		else:
			var descriptor: Dictionary = PropTracks.parse(str(clip.track_get_path(track)), clip.track_get_type(track))
			if descriptor.is_empty():
				return "Неизвестная дорожка: %s." % clip.track_get_path(track)
			var prop_key: String = "%s:%s" % [descriptor["id"], descriptor["property"]]
			if seen.has(prop_key):
				return "Повторная дорожка предмета: %s." % clip.track_get_path(track)
			seen[prop_key] = true
	for channel in SketchMotion.ACTOR_CHANNELS:
		if not seen.has(channel):
			return "Нет дорожки %s." % channel
	return ""

static func sample(kind: String, progress: float) -> Dictionary:
	var clip: Animation = clip_for(kind)
	if not validation_error(kind, clip).is_empty():
		return {}
	return SketchMotion.sample_animation(clip, progress, true)
