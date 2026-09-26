extends SceneTree
## Verifies that native 3D target edits drive the real seated pose and props.

const SketchMotion = preload("res://scripts/sketch_motion.gd")
const SeatedMotion = preload("res://scripts/seated_motion.gd")

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var scene: Node3D = load("res://scenes/animation_authoring_3d.tscn").instantiate()
	root.add_child(scene)
	scene._load_preview()
	_check(scene.ready_to_preview, "local VRM preview loads")
	if scene.ready_to_preview:
		var player: AnimationPlayer = scene.get_node("AnimationPlayer")
		var original_library: AnimationLibrary = player.get_animation_library("")
		_check(player.get_animation("sketch").resource_path == "res://animations/sketch.tres", "editor timeline points at the runtime clip file")
		var clip: Animation = player.get_animation("sketch")
		var key_map: String = player.key_map_text(clip)
		_check(key_map.contains("Мелок\n  Положение:") and key_map.contains("Правая ладонь\n  Положение:"), "key map lists editable prop and hand tracks")
		var edited_clip: Animation = clip.duplicate(true)
		var pencil_track: int = edited_clip.find_track(NodePath("Props/pencil/Мелок"), Animation.TYPE_POSITION_3D)
		edited_clip.position_track_insert_key(pencil_track, 5.371, Vector3(0.01, 0.04, 0.02))
		_check(player.key_map_text(edited_clip) != key_map and player.key_map_text(edited_clip).contains("5.37"), "key map includes a new unsaved key")
		player.assigned_animation = "sketch"
		player.seek(8.2, true)
		scene._update_preview()
		_check(is_equal_approx(player.current_animation_position, 8.2), "paused timeline seeks to 8.2 seconds")
		_check(player.current_animation.is_empty(), "preview works without playing animation")
		var left_track: int = clip.find_track(NodePath("Targets/left_hand"), Animation.TYPE_POSITION_3D)
		var book_track_at_preview: int = clip.find_track(NodePath("Props/open_book/Блокнот"), Animation.TYPE_POSITION_3D)
		_check(scene.get_node("Targets/left_hand").position.distance_to(clip.position_track_interpolate(left_track, 8.2)) < 0.001 and scene.get_node("Props/open_book/Блокнот").position.distance_to(clip.position_track_interpolate(book_track_at_preview, 8.2)) < 0.001, "native 3D tracks drive hand and book at 8.2 seconds")
		var hand_before: Vector3 = scene.rig.world_point("leftHand")
		var left_target: Marker3D = scene.get_node("Targets/left_hand")
		left_target.position.x += 0.03
		scene._update_preview()
		_check(scene.rig.world_point("leftHand").distance_to(hand_before) > 0.01, "3D left-hand target moves posed hand")
		var book_before: Vector3 = scene.sketchbook.book.global_position
		var book_target: Marker3D = scene.get_node("Props/open_book/Блокнот")
		book_target.position.y += 0.03
		scene._update_preview()
		_check(scene.sketchbook.book.global_position.distance_to(book_before) > 0.01, "3D prop target moves visible book")
		var pencil_before: Vector3 = scene.sketchbook.pencil.global_position
		var pencil_target: Marker3D = scene.get_node("Props/pencil/Мелок")
		pencil_target.position.x += 0.03
		scene._update_preview()
		_check(scene.sketchbook.pencil.global_position.distance_to(pencil_before) > 0.01, "same prop path drives pencil")
		var wrist_bone: int = int(scene.posture.arms[0]["end"])
		var wrist_before: Quaternion = scene.posture.skeleton.get_bone_global_pose(wrist_bone).basis.get_rotation_quaternion()
		left_target.rotation_degrees.x += 20.0
		scene._update_preview()
		var wrist_after: Quaternion = scene.posture.skeleton.get_bone_global_pose(wrist_bone).basis.get_rotation_quaternion()
		var wrist_delta: Quaternion = (wrist_after * wrist_before.inverse()).normalized()
		_check(absf(wrist_delta.get_axis().dot(Vector3.RIGHT)) > 0.90, "X gizmo rotates the visible wrist around X")
		var paste_clip: Animation = clip.duplicate(true)
		var paste_library := AnimationLibrary.new()
		paste_library.add_animation("sketch", paste_clip)
		player.remove_animation_library("")
		player.add_animation_library("", paste_library)
		player.assigned_animation = "sketch"
		player.seek(8.0, true)
		scene._update_preview()
		var board_before_paste: Vector3 = scene.sketchbook.book.global_position
		var board_track: int = paste_clip.find_track(NodePath("Props/open_book/Блокнот"), Animation.TYPE_POSITION_3D)
		var copied_board_position: Vector3 = paste_clip.track_get_key_value(board_track, 0)
		var existing_at_eight: int = paste_clip.track_find_key(board_track, 8.0, Animation.FIND_MODE_EXACT)
		if existing_at_eight >= 0:
			paste_clip.track_remove_key(board_track, existing_at_eight)
		paste_clip.position_track_insert_key(board_track, 8.0, copied_board_position + Vector3(0.0, 0.14, -0.07))
		player.seek(8.0, true)
		scene._update_preview()
		board_before_paste = scene.sketchbook.book.global_position
		paste_clip.track_remove_key(board_track, paste_clip.track_find_key(board_track, 8.0, Animation.FIND_MODE_EXACT))
		paste_clip.position_track_insert_key(board_track, 8.0, copied_board_position)
		scene._update_preview()
		_check(book_target.position.distance_to(copied_board_position) < 0.001 and scene.sketchbook.book.global_position.distance_to(board_before_paste) > 0.05, "pasted book position updates the paused 3D preview")
		var pencil_rotation_track: int = paste_clip.find_track(NodePath("Props/pencil/Мелок"), Animation.TYPE_ROTATION_3D)
		var authored_pencil_rotation := Quaternion.from_euler(Vector3(0.55, 0.25, -0.30))
		paste_clip.rotation_track_insert_key(pencil_rotation_track, 8.0, authored_pencil_rotation)
		scene._update_preview()
		var preview_rotation: Quaternion = scene.sketchbook.pencil.quaternion
		_check(preview_rotation.angle_to(authored_pencil_rotation) < 0.01, "pencil rotation key turns the visible prop in the paused preview")
		var previous_runtime_clip: Animation = SketchMotion.clip
		SketchMotion.clip = paste_clip
		var runtime_sample: Dictionary = SketchMotion.sample(0.8)
		SketchMotion.clip = previous_runtime_clip
		var sampled_rotation: Vector3 = runtime_sample["props"]["pencil"]["rotation_degrees"]
		_check(Quaternion.from_euler(sampled_rotation * (PI / 180.0)).angle_to(authored_pencil_rotation) < 0.01, "pencil rotation key reaches the runtime prop sample")
		pencil_target.rotation_degrees = Vector3(20.0, 10.0, -30.0)
		var replaced_rotation: Quaternion = pencil_target.quaternion
		var rotation_key_count: int = paste_clip.track_get_key_count(pencil_rotation_track)
		_check(pencil_target.record_rotation_key(), "target button records the selected pencil rotation")
		var key_at_eight: int = paste_clip.track_find_key(pencil_rotation_track, 8.0, Animation.FIND_MODE_EXACT)
		_check(paste_clip.track_get_key_count(pencil_rotation_track) == rotation_key_count and (paste_clip.track_get_key_value(pencil_rotation_track, key_at_eight) as Quaternion).angle_to(replaced_rotation) < 0.001, "rotation button replaces the key at the same time")
		var new_time: float = 5.137
		while paste_clip.track_find_key(pencil_rotation_track, new_time, Animation.FIND_MODE_EXACT) >= 0:
			new_time += 0.011
		player.seek(new_time, true)
		pencil_target.rotation_degrees = Vector3(-25.0, 15.0, 30.0)
		var inserted_rotation: Quaternion = pencil_target.quaternion
		_check(pencil_target.record_rotation_key(), "target button inserts a new rotation key")
		var inserted_key: int = paste_clip.track_find_key(pencil_rotation_track, new_time, Animation.FIND_MODE_EXACT)
		_check(paste_clip.track_get_key_count(pencil_rotation_track) == rotation_key_count + 1 and inserted_key >= 0 and (paste_clip.track_get_key_value(pencil_rotation_track, inserted_key) as Quaternion).angle_to(inserted_rotation) < 0.001, "new pencil rotation is stored on Rotation 3D")
		var temp_path: String = "res://.workspace/checks/rotation_key_%d.tres" % OS.get_process_id()
		var saved: Error = ResourceSaver.save(paste_clip, temp_path)
		var reloaded: Animation = ResourceLoader.load(temp_path, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation if saved == OK else null
		var saved_key: int = reloaded.find_track(NodePath("Props/pencil/Мелок"), Animation.TYPE_ROTATION_3D) if reloaded != null else -1
		var saved_index: int = -1
		if saved_key >= 0:
			for key in range(reloaded.track_get_key_count(saved_key)):
				if absf(reloaded.track_get_key_time(saved_key, key) - new_time) < 0.005:
					saved_index = key
					break
		_check(saved_index >= 0 and (reloaded.track_get_key_value(saved_key, saved_index) as Quaternion).angle_to(inserted_rotation) < 0.001, "rotation key survives resource save and reload")
		if saved == OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		player.seek(8.0, true)
		var hand_rotation_track: int = paste_clip.find_track(NodePath("Targets/left_hand"), Animation.TYPE_ROTATION_3D)
		left_target.rotation_degrees = Vector3(20.0, 0.0, 0.0)
		_check(left_target.record_rotation_key(), "same target button records hand rotation")
		var saved_hand_key: int = paste_clip.track_find_key(hand_rotation_track, 8.0, Animation.FIND_MODE_EXACT)
		_check(saved_hand_key >= 0 and (paste_clip.track_get_key_value(hand_rotation_track, saved_hand_key) as Quaternion).angle_to(Quaternion.from_euler(Vector3(deg_to_rad(20.0), 0.0, 0.0))) < 0.001, "hand Rotation 3D key stores the intended wrist angle")
		scene._update_preview()
		left_target.rotation_degrees = Vector3(35.0, 0.0, 0.0)
		scene._update_preview()
		var wrist_at_limit: Quaternion = scene.posture.skeleton.get_bone_global_pose(wrist_bone).basis.get_rotation_quaternion()
		left_target.rotation_degrees = Vector3(60.0, 0.0, 0.0)
		scene._update_preview()
		var wrist_beyond_limit: Quaternion = scene.posture.skeleton.get_bone_global_pose(wrist_bone).basis.get_rotation_quaternion()
		_check(wrist_at_limit.angle_to(wrist_beyond_limit) < 0.001, "editor hand preview uses the runtime wrist limit")
		paste_clip.track_set_key_value(hand_rotation_track, saved_hand_key, Quaternion.from_euler(Vector3(deg_to_rad(60.0), 0.0, 0.0)))
		SketchMotion.clip = paste_clip
		var capped_runtime: Dictionary = SketchMotion.sample(0.8)
		SketchMotion.clip = previous_runtime_clip
		_check(is_equal_approx(float(capped_runtime["left_hand_rotation"].x), 35.0), "runtime sample uses the same wrist limit")
		player.remove_animation_library("")
		player.add_animation_library("", original_library)
		for kind in SeatedMotion.kinds():
			var seated_clip: Animation = player.get_animation(kind)
			_check(seated_clip != null and seated_clip.resource_path == SeatedMotion.path_for(kind) and SeatedMotion.validation_error(kind, seated_clip).is_empty(), "native timeline has a valid editable %s clip" % kind)
			var bone_tracks: int = 0
			for track in range(seated_clip.get_track_count()):
				if str(seated_clip.track_get_path(track)).begins_with("Bones/"):
					bone_tracks += 1
			_check(bone_tracks > 0, "%s stores its visible bone motion as editable keys" % kind)
		player.assigned_animation = "fold"
		player.seek(4.0, true)
		scene._update_preview()
		_check(scene.paper_star.visible and scene.paper_star.paper.visible and not scene.sketchbook.visible, "fold timeline previews the existing paper scene")
		var fold_clip: Animation = player.get_animation("fold")
		_check(fold_clip.get_marker_names().has(&"Складывает") and fold_clip.get_marker_names().has(&"Звезда") and fold_clip.get_marker_names().has(&"Показывает"), "fold timeline labels its main phases")
		var fold_keys: int = 0
		var generic_targets: int = 0
		for track in range(fold_clip.get_track_count()):
			fold_keys += fold_clip.track_get_key_count(track)
			if str(fold_clip.track_get_path(track)).ends_with("/Target"):
				generic_targets += 1
		_check(fold_keys < 250 and generic_targets == 0, "fold timeline has concise keys and descriptive track names")
		var shape_track: int = fold_clip.find_track(NodePath("Props/paper_shape/Сложенная звезда"), Animation.TYPE_SCALE_3D)
		var folded_shape: Vector3 = fold_clip.scale_track_interpolate(shape_track, 4.0) if shape_track >= 0 else Vector3.ZERO
		var fold_sample: Dictionary = SeatedMotion.sample("fold", 4.0 / fold_clip.length)
		_check(shape_track >= 0 and fold_clip.track_get_key_count(shape_track) > 2 and (fold_sample.get("props", {}) as Dictionary).has("paper_shape") and (fold_sample["props"]["paper_shape"]["scale"] as Vector3).distance_to(folded_shape) < 0.001, "star creation has real sampled scale keys")
		_check((fold_sample.get("bones", {}) as Dictionary).has("rightUpperArm") and (fold_sample["bones"]["rightUpperArm"] as Quaternion).angle_to(Quaternion.IDENTITY) > 0.01, "fold arm motion reaches the runtime bone sample")
		var upper_arm_target: Marker3D = scene.get_node("Bones/rightUpperArm/Правое плечо")
		var upper_arm_id: int = int(scene.rig.bones["rightUpperArm"])
		var upper_arm_before: Quaternion = scene.rig.skeleton.get_bone_pose_rotation(upper_arm_id)
		var authored_arm: Quaternion = upper_arm_target.quaternion
		upper_arm_target.quaternion = (authored_arm * Quaternion(Vector3.RIGHT, deg_to_rad(20.0))).normalized()
		scene._update_preview()
		_check(scene.rig.skeleton.get_bone_pose_rotation(upper_arm_id).angle_to(upper_arm_before) > deg_to_rad(5.0), "turning a bone target changes the visible seated pose")
		upper_arm_target.quaternion = authored_arm
		var root_target: Marker3D = scene.get_node("Props/paper_star/Бумажная сценка")
		var paper_before: Vector3 = scene.paper_star.global_position
		root_target.position.x += 0.04
		scene._update_preview()
		_check(scene.paper_star.global_position.distance_to(paper_before) > scene.model_height * 0.03, "paper target moves the visible paper prop")
		root_target.position.x -= 0.04
		player.assigned_animation = "sway"
		player.seek(3.0, true)
		scene._update_preview()
		_check(not scene.paper_star.visible and not scene.sketchbook.visible, "sway timeline hides props from other clips")
		var sway_target: Marker3D = scene.get_node("Corrections/left_hand/Поправка левой кисти")
		var sway_hand_before: Vector3 = scene.rig.world_point("leftHand")
		_check(sway_target.global_position.distance_to(sway_hand_before) < 0.02, "correction gizmo appears at the unmodified hand")
		sway_target.position.x += 0.03
		scene._update_preview()
		_check(scene.rig.world_point("leftHand").distance_to(sway_hand_before) > 0.01, "moving correction gizmo changes the seated hand")
		sway_target.position = Vector3.ZERO
		var sway_clip: Animation = player.get_animation("sway").duplicate(true)
		var sway_head: int = sway_clip.find_track(NodePath("Channels:head_pitch"), Animation.TYPE_VALUE)
		sway_clip.track_insert_key(sway_head, 3.0, 8.0)
		var sway_sample: Dictionary = SketchMotion.sample_animation(sway_clip, 3.0 / sway_clip.length, true)
		_check(is_equal_approx(float(sway_sample.get("head_pitch", 0.0)), 8.0), "seated correction samples a new head key independently of sketch")
		var sway_path: String = "res://.workspace/checks/sway_key_%d.tres" % OS.get_process_id()
		var sway_saved: Error = ResourceSaver.save(sway_clip, sway_path)
		var sway_reloaded: Animation = ResourceLoader.load(sway_path, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation if sway_saved == OK else null
		_check(sway_reloaded != null and SeatedMotion.validation_error("sway", sway_reloaded).is_empty() and is_equal_approx(float(SketchMotion.sample_animation(sway_reloaded, 3.0 / sway_reloaded.length, true).get("head_pitch", 0.0)), 8.0), "new seated key survives file save and runtime sampling")
		if sway_saved == OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(sway_path))
		var extra_scale_clip: Animation = player.get_animation("sketch").duplicate(true)
		if extra_scale_clip.find_track(NodePath("Targets/right_hand"), Animation.TYPE_SCALE_3D) < 0:
			var scale_track: int = extra_scale_clip.add_track(Animation.TYPE_SCALE_3D)
			extra_scale_clip.track_set_path(scale_track, NodePath("Targets/right_hand"))
			extra_scale_clip.scale_track_insert_key(scale_track, 0.0, Vector3.ONE)
		_check(SketchMotion.valid(extra_scale_clip) and not SketchMotion.sample_animation(extra_scale_clip, 0.5).is_empty(), "an incidental hand scale key does not disable the sketch clip")
	await process_frame
	print("HOSHI_ANIMATION_AUTHORING_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
