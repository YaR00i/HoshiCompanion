extends SceneTree
## Produces readable, reduced copies of authored clips in .workspace for review.
## Never overwrites the originals or their saved user corrections.

const SketchMotion = preload("res://scripts/sketch_motion.gd")
const PropTracks = preload("res://scripts/prop_track_schema.gd")
const KINDS := ["sketch", "swing", "lean", "peek", "balance", "sway", "hum", "nod", "fold", "admire_star"]
const OUTPUT_ROOT := "res://.workspace/animation_track_candidates"

func _initialize() -> void:
	var output_dir: String = OUTPUT_ROOT + "/" + str(OS.get_process_id())
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)) != OK:
		push_error("Cannot create candidate directory: " + output_dir)
		quit(1)
		return
	var failures: int = 0
	for kind in KINDS:
		var source: Animation = ResourceLoader.load("res://animations/%s.tres" % kind, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
		if source == null:
			failures += 1
			continue
		var candidate: Animation = source.duplicate(true)
		var removed: int = 0
		var renamed: int = 0
		for track in range(candidate.get_track_count()):
			var old_path: String = str(candidate.track_get_path(track))
			var new_path: String = _readable_path(old_path)
			if new_path != old_path:
				candidate.track_set_path(track, NodePath(new_path))
				renamed += 1
			if not old_path.begins_with("Bones/") and not old_path.begins_with("Props/paper_"):
				continue
			var tolerance: float = _tolerance(candidate.track_get_type(track), old_path)
			var keep: Array[int] = _keep_keys(source, track, tolerance)
			var keep_lookup: Dictionary = {}
			for index in keep:
				keep_lookup[index] = true
			for index in range(candidate.track_get_key_count(track) - 1, -1, -1):
				if not keep_lookup.has(index):
					candidate.track_remove_key(track, index)
					removed += 1
			var error: float = _max_error(source, candidate, track)
			if error > tolerance + 0.0001:
				failures += 1
				push_error("Reduction exceeded tolerance in %s %s: %f > %f" % [kind, old_path, error, tolerance])
		var output_path: String = output_dir + "/" + kind + ".tres"
		if ResourceSaver.save(candidate, output_path) != OK:
			failures += 1
		else:
			print("CLEAN_CLIP kind=%s renamed=%d removed=%d remaining=%d" % [kind, renamed, removed, _key_count(candidate)])
	print("HOSHI_ANIMATION_TRACK_CLEAN_RESULT clips=%d failures=%d output=%s" % [KINDS.size(), failures, output_dir])
	quit(0 if failures == 0 else 1)

func _readable_path(path: String) -> String:
	if path.begins_with("Bones/") and path.ends_with("/Target"):
		return SketchMotion.bone_path(path.trim_prefix("Bones/").trim_suffix("/Target"))
	if path.begins_with("Corrections/") and path.ends_with("/Target"):
		return SketchMotion.correction_path(path.trim_prefix("Corrections/").trim_suffix("/Target"))
	if path.begins_with("Props/") and path.ends_with("/Target"):
		return PropTracks.path_for(path.trim_prefix("Props/").trim_suffix("/Target"), "position")
	return path

func _tolerance(track_type: int, path: String) -> float:
	if track_type == Animation.TYPE_ROTATION_3D:
		return deg_to_rad(1.0)
	if track_type == Animation.TYPE_SCALE_3D:
		return 0.003
	return 0.005 if path.begins_with("Props/") else 0.0

func _keep_keys(clip: Animation, track: int, tolerance: float) -> Array[int]:
	var count: int = clip.track_get_key_count(track)
	if count <= 2:
		var all: Array[int] = []
		for index in range(count):
			all.append(index)
		return all
	var kept: Dictionary = {0: true, count - 1: true}
	var pending: Array[Vector2i] = [Vector2i(0, count - 1)]
	while not pending.is_empty():
		var segment: Vector2i = pending.pop_back()
		var first: int = segment.x
		var last: int = segment.y
		if last - first < 2:
			continue
		var first_time: float = clip.track_get_key_time(track, first)
		var last_time: float = clip.track_get_key_time(track, last)
		var first_value: Variant = clip.track_get_key_value(track, first)
		var last_value: Variant = clip.track_get_key_value(track, last)
		var worst_error: float = tolerance
		var worst_index: int = -1
		for index in range(first + 1, last):
			var alpha: float = (clip.track_get_key_time(track, index) - first_time) / (last_time - first_time)
			var error: float = _distance(clip.track_get_type(track), clip.track_get_key_value(track, index), _blend(clip.track_get_type(track), first_value, last_value, alpha))
			if error > worst_error:
				worst_error = error
				worst_index = index
		if worst_index >= 0:
			kept[worst_index] = true
			pending.append(Vector2i(first, worst_index))
			pending.append(Vector2i(worst_index, last))
	var result: Array[int] = []
	for index in kept:
		result.append(index)
	result.sort()
	return result

func _max_error(original: Animation, reduced: Animation, track: int) -> float:
	var maximum: float = 0.0
	for index in range(original.track_get_key_count(track)):
		var time: float = original.track_get_key_time(track, index)
		maximum = maxf(maximum, _distance(original.track_get_type(track), original.track_get_key_value(track, index), _interpolate(reduced, track, time)))
	return maximum

func _interpolate(clip: Animation, track: int, time: float) -> Variant:
	match clip.track_get_type(track):
		Animation.TYPE_POSITION_3D: return clip.position_track_interpolate(track, time)
		Animation.TYPE_ROTATION_3D: return clip.rotation_track_interpolate(track, time)
		Animation.TYPE_SCALE_3D: return clip.scale_track_interpolate(track, time)
	return null

func _blend(track_type: int, first: Variant, last: Variant, alpha: float) -> Variant:
	return (first as Quaternion).slerp(last, alpha) if track_type == Animation.TYPE_ROTATION_3D else (first as Vector3).lerp(last, alpha)

func _distance(track_type: int, first: Variant, last: Variant) -> float:
	return (first as Quaternion).angle_to(last) if track_type == Animation.TYPE_ROTATION_3D else (first as Vector3).distance_to(last)

func _key_count(clip: Animation) -> int:
	var count: int = 0
	for track in range(clip.get_track_count()):
		count += clip.track_get_key_count(track)
	return count
