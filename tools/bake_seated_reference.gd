extends SceneTree
## Captures the current procedural seated gestures into candidate Godot clips.
## Output is deliberately confined to .workspace; it never rewrites edited clips.

const SeatedMotion = preload("res://scripts/seated_motion.gd")
const SketchMotion = preload("res://scripts/sketch_motion.gd")
const PropTracks = preload("res://scripts/prop_track_schema.gd")
const STEP: float = 0.15
const OUTPUT_ROOT: String = "res://.workspace/seated_bake_candidates"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = load("res://scenes/animation_authoring_3d.tscn").instantiate()
	root.add_child(scene)
	scene._load_preview()
	if not scene.ready_to_preview:
		push_error("Cannot load local avatar for reference bake: " + scene.preview_error)
		quit(1)
		return
	var output_dir: String = OUTPUT_ROOT + "/" + str(OS.get_process_id())
	var mkdir_result: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if mkdir_result != OK:
		push_error("Cannot create candidate directory: " + output_dir)
		quit(1)
		return
	var failures: int = 0
	for kind in SeatedMotion.kinds():
		var source: Animation = SeatedMotion.clip_for(kind)
		var candidate: Animation = source.duplicate(true) as Animation
		var samples: Array[Dictionary] = _capture(scene, kind, source.length)
		var bone_count: int = _add_bone_tracks(candidate, samples)
		var prop_count: int = _add_paper_tracks(candidate, samples) if kind in ["fold", "admire_star"] else 0
		var output_path: String = output_dir + "/" + kind + ".tres"
		var saved: Error = ResourceSaver.save(candidate, output_path)
		if saved != OK:
			failures += 1
			push_error("Cannot save candidate %s: %d" % [kind, saved])
		else:
			print("BAKE_CANDIDATE kind=%s bones=%d paper_tracks=%d keys=%d path=%s" % [kind, bone_count, prop_count, _key_count(candidate), output_path])
	print("HOSHI_SEATED_BAKE_RESULT clips=%d failures=%d output=%s" % [SeatedMotion.kinds().size(), failures, output_dir])
	quit(0 if failures == 0 else 1)

func _capture(scene: Node3D, kind: String, length: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count: int = ceili(length / STEP)
	for index in range(count + 1):
		var time: float = minf(float(index) * STEP, length)
		var progress: float = time / length
		var rig = scene.rig
		rig.tick(0.0, time, Vector2.ZERO, 0.0, 0.0, 0.0, true)
		scene.edge_pose.apply(1.0, time, 0.0, true)
		var calm: Dictionary = {}
		for semantic in rig.bones:
			calm[semantic] = rig.skeleton.get_bone_pose_rotation(int(rig.bones[semantic]))
		rig.tick(0.0, time, Vector2.ZERO, 0.0, 0.0, 0.0, true)
		var life: Dictionary = {kind: 1.0, "fold_progress": progress if kind == "fold" else 0.0, "admire_progress": progress if kind == "admire_star" else 0.0}
		scene.edge_pose.apply(1.0, time, 0.0, true, life)
		var bone_deltas: Dictionary = {}
		for semantic in rig.bones:
			var current: Quaternion = rig.skeleton.get_bone_pose_rotation(int(rig.bones[semantic]))
			bone_deltas[semantic] = ((calm[semantic] as Quaternion).inverse() * current).normalized()
		var paper_props: Dictionary = {}
		if kind in ["fold", "admire_star"]:
			scene.paper_star.update_pose(scene.get_node("PreviewRoot"), rig, 1.0 if kind == "fold" else 0.0, progress, 1.0 if kind == "admire_star" else 0.0, progress)
			var paper = scene.paper_star
			var hip: Vector3 = scene.get_node("PreviewRoot").to_local(rig.world_point("hips"))
			paper_props["paper_star"] = {"position": (paper.position - hip) / scene.model_height, "rotation": Quaternion.from_euler(paper.rotation), "scale": paper.scale}
			paper_props["paper_sheet"] = {"position": paper.paper.position / scene.model_height, "rotation": Quaternion.from_euler(paper.paper.rotation), "scale": paper.paper.scale if paper.paper.visible else Vector3.ZERO}
			paper_props["paper_shape"] = {"position": paper.star.position / scene.model_height, "rotation": Quaternion.from_euler(paper.star.rotation), "scale": paper.star.scale if paper.star.visible else Vector3.ZERO}
		result.append({"time": time, "bones": bone_deltas, "props": paper_props})
	return result

func _add_bone_tracks(clip: Animation, samples: Array[Dictionary]) -> int:
	var count: int = 0
	var first_bones: Dictionary = samples[0]["bones"]
	for semantic in first_bones:
		var maximum: float = 0.0
		var first: Quaternion = first_bones[semantic]
		var variation: float = 0.0
		for sample in samples:
			var q: Quaternion = sample["bones"][semantic]
			maximum = maxf(maximum, q.angle_to(Quaternion.IDENTITY))
			variation = maxf(variation, q.angle_to(first))
		if maximum < deg_to_rad(0.08):
			continue
		var path: NodePath = NodePath(SketchMotion.bone_path(semantic))
		var track: int = clip.find_track(path, Animation.TYPE_ROTATION_3D)
		if track < 0:
			track = clip.add_track(Animation.TYPE_ROTATION_3D)
			clip.track_set_path(track, path)
		clip.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		var indices: Array[int] = []
		if variation < deg_to_rad(0.08):
			indices = [0, samples.size() - 1]
		else:
			for index in range(samples.size()):
				indices.append(index)
		for index in indices:
			var sample: Dictionary = samples[index]
			clip.rotation_track_insert_key(track, float(sample["time"]), sample["bones"][semantic])
		count += 1
	return count

func _add_paper_tracks(clip: Animation, samples: Array[Dictionary]) -> int:
	var count: int = 0
	for prop_id in ["paper_star", "paper_sheet", "paper_shape"]:
		for property in ["position", "rotation", "scale"]:
			var track_type: int = Animation.TYPE_POSITION_3D if property == "position" else (Animation.TYPE_ROTATION_3D if property == "rotation" else Animation.TYPE_SCALE_3D)
			var path: NodePath = NodePath(PropTracks.path_for(prop_id, property))
			var track: int = clip.find_track(path, track_type)
			if track < 0:
				track = clip.add_track(track_type)
				clip.track_set_path(track, path)
			clip.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
			for sample in samples:
				var value: Variant = sample["props"][prop_id][property]
				match track_type:
					Animation.TYPE_POSITION_3D: clip.position_track_insert_key(track, float(sample["time"]), value)
					Animation.TYPE_ROTATION_3D: clip.rotation_track_insert_key(track, float(sample["time"]), value)
					Animation.TYPE_SCALE_3D: clip.scale_track_insert_key(track, float(sample["time"]), value)
			count += 1
	return count

func _key_count(clip: Animation) -> int:
	var count: int = 0
	for track in range(clip.get_track_count()):
		count += clip.track_get_key_count(track)
	return count
