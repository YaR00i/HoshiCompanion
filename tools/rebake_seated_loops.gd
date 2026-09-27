extends SceneTree
## Rebuilds the rhythmic seated clips (sway, swing, hum, nod, balance) as seamless loops.
##
## Why: the 2026-09-25 key cleanup kept only keys needed for a 1° error with LINEAR
## interpolation. The gestures are only 1–8° large, so smooth waves turned into
## zigzags ("sways, hard stop, sways back"). This tool samples the reference
## procedural motion (edge_pose.gd), whose frequencies fit whole cycles into each
## clip, and keeps a few CUBIC keys: smooth curves that are still easy to edit.
##
## Channels/Corrections tracks (the user's own corrections) are kept; only their key
## times are stretched to the new length. Bones tracks are replaced.
##
## Usage (from the project folder):
##   godot --headless --script res://tools/rebake_seated_loops.gd            -> candidates in .workspace
##   godot --headless --script res://tools/rebake_seated_loops.gd -- --apply -> rewrites res://animations/

const SeatedMotion = preload("res://scripts/seated_motion.gd")
const SketchMotion = preload("res://scripts/sketch_motion.gd")
const SAMPLE_FPS: float = 20.0
const OUTPUT_ROOT: String = "res://.workspace/seated_loop_candidates"
## Allowed deviation from the reference curve: a small share of the bone's own range.
const RELATIVE_TOLERANCE: float = 0.04
const MIN_TOLERANCE_DEG: float = 0.05
const MAX_KEYS_PER_TRACK: int = 32
## Bones that move less than this are dropped (invisible and would only clutter the timeline).
const MIN_VISIBLE_DEG: float = 0.12

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var apply: bool = "--apply" in OS.get_cmdline_user_args()
	var scene: Node3D = load("res://scenes/animation_authoring_3d.tscn").instantiate()
	root.add_child(scene)
	scene._load_preview()
	if not scene.ready_to_preview:
		push_error("Cannot load local avatar for loop bake: " + scene.preview_error)
		quit(1)
		return
	var output_dir: String = "res://animations" if apply else OUTPUT_ROOT + "/" + str(OS.get_process_id())
	if not apply:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var failures: int = 0
	for kind in SeatedMotion.LOOPING:
		var length: float = float(SeatedMotion.DURATIONS[kind])
		var source: Animation = ResourceLoader.load(SeatedMotion.path_for(kind), "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
		var clip: Animation = _rebuild(scene, kind, source, length)
		var problem: String = SeatedMotion.validation_error(kind, clip)
		if not problem.is_empty():
			failures += 1
			push_error("%s: %s" % [kind, problem])
			continue
		if apply:
			clip.take_over_path(SeatedMotion.path_for(kind))
		var path: String = output_dir + "/" + kind + ".tres"
		if ResourceSaver.save(clip, path) != OK:
			failures += 1
			push_error("Cannot save " + path)
			continue
		print("LOOP_CLIP kind=%s length=%.2f keys=%d path=%s" % [kind, length, _bone_key_count(clip), path])
	print("HOSHI_SEATED_LOOP_RESULT clips=%d failures=%d applied=%s" % [SeatedMotion.LOOPING.size(), failures, apply])
	quit(0 if failures == 0 else 1)

func _rebuild(scene: Node3D, kind: String, source: Animation, length: float) -> Animation:
	var clip := Animation.new()
	clip.resource_name = kind
	clip.length = length
	clip.step = 0.05
	clip.loop_mode = Animation.LOOP_LINEAR
	var stretch: float = length / maxf(source.length, 0.001)
	# Keep every non-bone track (channels, corrections, props) with stretched key times.
	for track in range(source.get_track_count()):
		var path: String = str(source.track_get_path(track))
		if path.begins_with("Bones/"):
			continue
		var copy: int = clip.add_track(source.track_get_type(track))
		clip.track_set_path(copy, source.track_get_path(track))
		clip.track_set_interpolation_type(copy, Animation.INTERPOLATION_CUBIC)
		clip.track_set_interpolation_loop_wrap(copy, true)
		for key in range(source.track_get_key_count(track)):
			var time: float = minf(source.track_get_key_time(track, key) * stretch, length)
			clip.track_insert_key(copy, time, source.track_get_key_value(track, key), source.track_get_key_transition(track, key))
	var samples: Array[Dictionary] = _capture(scene, kind, length)
	for semantic in SketchMotion.BONE_TARGET_NAMES:
		var series: Array[Quaternion] = []
		var peak: float = 0.0
		for sample in samples:
			var q: Quaternion = (sample["bones"] as Dictionary).get(semantic, Quaternion.IDENTITY)
			series.append(q)
			peak = maxf(peak, small_angle(q, Quaternion.IDENTITY))
		if rad_to_deg(peak) < MIN_VISIBLE_DEG:
			continue
		var track: int = clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath(SketchMotion.bone_path(semantic)))
		clip.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		clip.track_set_interpolation_loop_wrap(track, true)
		_fit_track(clip, track, samples, series, maxf(deg_to_rad(MIN_TOLERANCE_DEG), peak * RELATIVE_TOLERANCE))
	return clip

## Samples one full cycle [0, length). Calm pose is static (motion off) so the delta is purely periodic.
func _capture(scene: Node3D, kind: String, length: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count: int = roundi(length * SAMPLE_FPS)
	var rig = scene.rig
	for index in range(count):
		var time: float = float(index) / SAMPLE_FPS
		rig.tick(0.0, 0.0, Vector2.ZERO, 0.0, 0.0, 0.0, false)
		scene.edge_pose.apply(1.0, time, 0.0, false)
		var calm: Dictionary = {}
		for semantic in rig.bones:
			calm[semantic] = rig.skeleton.get_bone_pose_rotation(int(rig.bones[semantic]))
		rig.tick(0.0, 0.0, Vector2.ZERO, 0.0, 0.0, 0.0, false)
		scene.edge_pose.apply(1.0, time, 0.0, false, {kind: 1.0})
		var deltas: Dictionary = {}
		for semantic in rig.bones:
			var current: Quaternion = rig.skeleton.get_bone_pose_rotation(int(rig.bones[semantic]))
			deltas[semantic] = ((calm[semantic] as Quaternion).inverse() * current).normalized()
		result.append({"time": time, "bones": deltas})
	return result

## Evenly spaced keys (a tidy grid on the timeline): use the smallest count whose
## cubic loop stays within tolerance of the reference everywhere.
func _fit_track(clip: Animation, track: int, samples: Array[Dictionary], series: Array[Quaternion], tolerance: float) -> void:
	var n: int = series.size()
	var best_count: int = MAX_KEYS_PER_TRACK
	for count in range(4, MAX_KEYS_PER_TRACK + 1):
		var chosen: Dictionary = {}
		for part in range(count):
			chosen[int(round(float(part) * float(n) / float(count))) % n] = true
		_write_keys(clip, track, samples, series, chosen)
		var worst: float = 0.0
		for index in range(n):
			worst = maxf(worst, small_angle(clip.rotation_track_interpolate(track, float(samples[index]["time"])), series[index]))
		if worst <= tolerance:
			if OS.get_environment("HOSHI_BAKE_DEBUG") != "":
				print("FIT %s keys=%d worst=%.3f tol=%.3f" % [clip.track_get_path(track), count, rad_to_deg(worst), rad_to_deg(tolerance)])
			return
		best_count = count
	if OS.get_environment("HOSHI_BAKE_DEBUG") != "":
		print("FIT %s keys=%d (cap) tol=%.3f" % [clip.track_get_path(track), best_count, rad_to_deg(tolerance)])

## Angle between two nearly equal rotations. Quaternion.angle_to() uses acos and loses
## ~0.2° to float rounding at these tiny gesture sizes; asin of the vector part does not.
static func small_angle(a: Quaternion, b: Quaternion) -> float:
	var d: Quaternion = a.normalized().inverse() * b.normalized()
	return 2.0 * asin(minf(1.0, Vector3(d.x, d.y, d.z).length()))

func _write_keys(clip: Animation, track: int, samples: Array[Dictionary], series: Array[Quaternion], chosen: Dictionary) -> void:
	while clip.track_get_key_count(track) > 0:
		clip.track_remove_key(track, 0)
	var indices: Array = chosen.keys()
	indices.sort()
	for index in indices:
		# Keys land on the 0.05 s editor grid so they are easy to select and move by hand.
		var time: float = snappedf(float(samples[index]["time"]), 0.05)
		clip.rotation_track_insert_key(track, time, series[index])

func _bone_key_count(clip: Animation) -> int:
	var count: int = 0
	for track in range(clip.get_track_count()):
		if str(clip.track_get_path(track)).begins_with("Bones/"):
			count += clip.track_get_key_count(track)
	return count
