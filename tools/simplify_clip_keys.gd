extends SceneTree
## Убрать лишние ключи из клипов: ключ удаляется, если без него движение между
## соседями отличается меньше допуска (поворот — градусы, каналы — свои единицы).
## Первый и последний ключ дорожки остаются всегда.
##   godot --headless --path . --script res://tools/simplify_clip_keys.gd -- res://animations/touch_arm.tres [...]
##   без путей — все animations/touch_*.tres

const ROTATION_DEGREES: float = 0.6
const VALUE_TOLERANCE := {"touch_yaw": 0.8, "hips_offset": 0.0015, "face_happy": 0.03, "face_angry": 0.03}
const SAMPLE_STEP: float = 1.0 / 60.0

func _init() -> void:
	var paths: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("res://"):
			paths.append(arg)
	if paths.is_empty():
		for file in DirAccess.get_files_at("res://animations"):
			if file.begins_with("touch_") and file.ends_with(".tres"):
				paths.append("res://animations/" + file)
	var failed: bool = false
	for path in paths:
		var clip: Animation = ResourceLoader.load(path, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
		if clip == null:
			print("SIMPLIFY_ERROR not an animation: ", path)
			failed = true
			continue
		var before: int = _key_count(clip)
		var reference: Animation = clip.duplicate(true)
		for track in range(clip.get_track_count()):
			_simplify(clip, reference, track)
		var error: float = _max_error(clip, reference)
		if ResourceSaver.save(clip, path) != OK:
			print("SIMPLIFY_ERROR save failed: ", path)
			failed = true
			continue
		print("SIMPLIFY %s keys %d -> %d, max error %.3f" % [path, before, _key_count(clip), error])
	quit(1 if failed else 0)

func _key_count(clip: Animation) -> int:
	var count: int = 0
	for track in range(clip.get_track_count()):
		count += clip.track_get_key_count(track)
	return count

func _tolerance(clip: Animation, track: int) -> float:
	if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
		return ROTATION_DEGREES
	var path: String = str(clip.track_get_path(track))
	return float(VALUE_TOLERANCE.get(path.trim_prefix("Channels:"), 0.001))

func _error_at(clip: Animation, reference: Animation, track: int, time: float) -> float:
	if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
		return rad_to_deg(clip.rotation_track_interpolate(track, time).angle_to(reference.rotation_track_interpolate(track, time)))
	var a: Variant = clip.value_track_interpolate(track, time)
	var b: Variant = reference.value_track_interpolate(track, time)
	if a is float or a is int:
		return absf(float(a) - float(b))
	return 0.0 if a == b else INF

func _track_error(clip: Animation, reference: Animation, track: int, from: float, to: float) -> float:
	var worst: float = 0.0
	var t: float = from
	while t <= to + 0.0001:
		worst = maxf(worst, _error_at(clip, reference, track, minf(t, to)))
		t += SAMPLE_STEP
	return worst

## Жадно: пробуем снять каждый внутренний ключ; если ошибка на всём отрезке
## между соседями в допуске — оставляем снятым, иначе возвращаем.
func _simplify(clip: Animation, reference: Animation, track: int) -> void:
	var tolerance: float = _tolerance(clip, track)
	var changed: bool = true
	while changed:
		changed = false
		var key: int = 1
		while key < clip.track_get_key_count(track) - 1:
			var time: float = clip.track_get_key_time(track, key)
			var value: Variant = clip.track_get_key_value(track, key)
			var transition: float = clip.track_get_key_transition(track, key)
			var from: float = clip.track_get_key_time(track, maxi(0, key - 2))
			var to: float = clip.track_get_key_time(track, mini(clip.track_get_key_count(track) - 1, key + 2))
			clip.track_remove_key(track, key)
			if _track_error(clip, reference, track, from, to) <= tolerance:
				changed = true
			else:
				clip.track_insert_key(track, time, value, transition)
				key += 1

func _max_error(clip: Animation, reference: Animation) -> float:
	var worst: float = 0.0
	for track in range(clip.get_track_count()):
		var tolerance: float = _tolerance(clip, track)
		worst = maxf(worst, _track_error(clip, reference, track, 0.0, clip.length) / tolerance)
	return worst # в долях допуска: ≤1 — в пределах
