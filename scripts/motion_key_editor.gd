extends RefCounted
## Small reusable bridge between workshop controls and Godot Animation tracks.

const PropTracks = preload("res://scripts/prop_track_schema.gd")
const SketchMotion = preload("res://scripts/sketch_motion.gd")

static func put_value(clip: Animation, channel: String, time: float, value: Variant) -> bool:
	if clip == null or not is_finite(time) or time < 0.0 or time > clip.length:
		return false
	return _put_path(clip, SketchMotion.actor_path(channel), SketchMotion.actor_type(channel), time, value)

static func put_prop_value(clip: Animation, prop_id: String, property: String, time: float, value: Vector3, default_value: Vector3) -> bool:
	if clip == null or not is_finite(time) or time < 0.0 or time > clip.length or not prop_id.is_valid_identifier() or not PropTracks.PROPERTIES.has(property):
		return false
	var path: String = PropTracks.path_for(prop_id, property)
	var track_type: int = PropTracks.type_for(property)
	if clip.find_track(NodePath(path), track_type) < 0:
		var track: int = clip.add_track(track_type)
		clip.track_set_path(track, NodePath(path))
		clip.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		clip.track_insert_key(track, 0.0, _stored_value(track_type, default_value))
		clip.track_insert_key(track, clip.length, _stored_value(track_type, default_value))
	return _put_path(clip, path, track_type, time, value)

static func _put_path(clip: Animation, path: String, track_type: int, time: float, value: Variant) -> bool:
	if not is_finite(time) or time < 0.0 or time > clip.length:
		return false
	var track: int = clip.find_track(NodePath(path), track_type)
	if track < 0:
		return false
	var stored: Variant = _stored_value(track_type, value)
	for key in range(clip.track_get_key_count(track)):
		if absf(clip.track_get_key_time(track, key) - time) <= 0.005:
			clip.track_set_key_value(track, key, stored)
			return true
	return clip.track_insert_key(track, time, stored) >= 0

static func _stored_value(track_type: int, value: Variant) -> Variant:
	if track_type == Animation.TYPE_ROTATION_3D:
		return Quaternion.from_euler((value as Vector3) * (PI / 180.0))
	return value
