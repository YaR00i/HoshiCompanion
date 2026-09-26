extends SceneTree
## Integration check for Godot-authored sketch tracks on the local Hoshi rig.

const SketchMotion = preload("res://scripts/sketch_motion.gd")
const AnimatedProp = preload("res://scripts/animated_prop.gd")
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

func _entry_index(workshop: Control, key: String, property: String = "") -> int:
	for index in range(workshop.channel_entries.size()):
		var entry: Dictionary = workshop.channel_entries[index]
		if str(entry["key"]) == key and str(entry.get("property", "")) == property:
			return index
	return -1

func _run() -> void:
	_check(SketchMotion.valid(SketchMotion.clip), "sketch animation has actor and generic prop tracks")
	_check(SketchMotion.reload_clip(), "saved sketch animation reloads for live preview")
	var native_clip: Animation = SketchMotion.clip.duplicate(true) as Animation
	for track in range(native_clip.get_track_count() - 1, -1, -1):
		if str(native_clip.track_get_path(track)) == "Targets/left_hand:rotation_degrees":
			native_clip.remove_track(track)
	var native_rotation: int = native_clip.find_track(NodePath("Targets/left_hand"), Animation.TYPE_ROTATION_3D)
	if native_rotation < 0:
		native_rotation = native_clip.add_track(Animation.TYPE_ROTATION_3D)
		native_clip.track_set_path(native_rotation, NodePath("Targets/left_hand"))
		native_clip.rotation_track_insert_key(native_rotation, 0.0, Quaternion.IDENTITY)
		native_clip.rotation_track_insert_key(native_rotation, 10.0, Quaternion.IDENTITY)
	native_clip.rotation_track_insert_key(native_rotation, 8.2, Quaternion(Vector3.RIGHT, deg_to_rad(20.0)))
	var native_path: String = "res://.workspace/test_native_rotation_key.tres"
	var native_saved: Error = ResourceSaver.save(native_clip, native_path)
	var native_loaded: Animation = ResourceLoader.load(native_path, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation if native_saved == OK else null
	_check(native_saved == OK and SketchMotion.valid(native_loaded), "Godot 3D rotation key survives save and is accepted by runtime")
	if native_saved == OK and SketchMotion.valid(native_loaded):
		var original_clip: Animation = SketchMotion.clip
		SketchMotion.clip = native_loaded
		_check(absf(float((SketchMotion.sample(0.82).get("left_hand_rotation", Vector3.ZERO) as Vector3).x) - 20.0) < 0.1, "runtime samples saved native wrist key")
		_check(absf(float((SketchMotion.sample(0.80).get("left_hand_rotation", Vector3.ZERO) as Vector3).x)) < 0.1, "new wrist key leaves previous key unchanged")
		SketchMotion.clip = original_clip
	DirAccess.remove_absolute(ProjectSettings.globalize_path(native_path))
	var drawing: Dictionary = SketchMotion.sample(0.27)
	var showing: Dictionary = SketchMotion.sample(0.82)
	_check(drawing.has("right_hand") and showing.has("right_hand"), "keyframes interpolate into wrist targets")
	_check((drawing.get("right_hand", Vector3.ZERO) as Vector3).distance_to(showing.get("right_hand", Vector3.ZERO)) > 0.10, "scrubbing changes the authored hand target")
	_check(showing.get("props", {}).get("open_book", {}).has("position") and showing.get("props", {}).get("open_book", {}).has("rotation_degrees"), "notebook position and tilt come from generic prop tracks")
	_check(showing.get("props", {}).get("pencil", {}).has("position") and showing.get("props", {}).get("pencil", {}).has("rotation_degrees"), "pencil position and tilt come from the same prop tracks")
	_check(showing.has("left_hand_rotation") and showing.has("right_hand_rotation"), "wrist rotation can be authored alongside hand position")
	var workshop: Control = load("res://scenes/animation_workshop.tscn").instantiate()
	root.add_child(workshop)
	for i in range(20):
		await process_frame
		if workshop.stage != null and workshop.stage.is_loaded:
			break
	_check(workshop.stage != null and workshop.stage.is_loaded, "workshop loads the real local model")
	_check(not workshop.get_node("EditorGuide").visible, "editor instructions do not cover the live preview")
	var player: AnimationPlayer = workshop.get_node("AnimationPlayer")
	_check(player.has_animation("sketch"), "Godot AnimationPlayer exposes the editable sketch timeline")
	player.play("sketch")
	player.seek(8.2, true)
	_check(float(workshop.get_node("Channels").head_pitch) < 0.0, "native timeline drives the authored channels")
	player.stop()
	if workshop.stage != null and workshop.stage.is_loaded:
		var stage = workshop.stage
		workshop.cursor = 2.7
		workshop._render()
		var seat: Vector3 = stage.edge_pose.anchor_world()
		var first_hand: Vector3 = stage.rig.world_point("rightHand")
		workshop.cursor = 8.2
		workshop._render()
		var second_hand: Vector3 = stage.rig.world_point("rightHand")
		_check(first_hand.distance_to(second_hand) > stage.model_height * 0.05, "scrub moves Hoshi's actual hand")
		_check(stage.edge_pose.anchor_world().distance_to(seat) < 0.001, "scrub keeps the seat contact fixed")
		var finite: bool = true
		var skeleton: Skeleton3D = stage.rig.skeleton
		for bone in range(skeleton.get_bone_count()):
			var pose: Transform3D = skeleton.get_bone_global_pose(bone)
			finite = finite and pose.origin.is_finite() and pose.basis.is_finite()
		_check(finite, "authored pose keeps all bones finite")
		var original_book: Vector3 = SketchMotion.sample(0.82)["props"]["open_book"]["position"]
		var original_center: Vector3 = stage.sketchbook.book.global_position
		workshop.choice.select(_entry_index(workshop, "open_book", "position"))
		workshop._on_field_changed((original_book.y + 0.02) * stage.model_height * 100.0, 1)
		var edited_book: Vector3 = SketchMotion.sample(0.82)["props"]["open_book"]["position"]
		_check(absf(edited_book.y - original_book.y - 0.02) < 0.0001, "workshop adds a book key at the selected time")
		_check(stage.sketchbook.book.global_position.distance_to(original_center) > stage.model_height * 0.015, "book edit immediately moves the visible prop")
		workshop._undo()
		_check((SketchMotion.sample(0.82)["props"]["open_book"]["position"] as Vector3).distance_to(original_book) < 0.0001, "workshop undo restores the original prop track")
		var pencil_index: int = _entry_index(workshop, "pencil", "position")
		_check(pencil_index >= 0, "workshop discovers pencil without a dedicated control")
		var pencil_before: Vector3 = stage.sketchbook.pencil.global_position
		workshop.choice.select(pencil_index)
		workshop._on_field_changed(5.0, 0)
		_check(stage.sketchbook.pencil.global_position.distance_to(pencil_before) > 0.005, "editing pencil position moves the real prop")
		workshop._undo()
		var pencil_rotation_index: int = _entry_index(workshop, "pencil", "rotation_degrees")
		workshop.choice.select(pencil_rotation_index)
		workshop._on_channel_selected(pencil_rotation_index)
		var pencil_angle: float = stage.sketchbook.pencil.rotation_degrees.z
		workshop._on_field_changed(pencil_angle + 12.0, 2)
		_check(absf(stage.sketchbook.pencil.rotation_degrees.z - pencil_angle) > 10.0, "editing pencil rotation turns the real prop")
		workshop._undo()
		var pencil_scale_index: int = _entry_index(workshop, "pencil", "scale")
		workshop.choice.select(pencil_scale_index)
		workshop._on_channel_selected(pencil_scale_index)
		var pencil_scale: float = stage.sketchbook.pencil.scale.x
		workshop._on_field_changed(1.5, 0)
		_check(stage.sketchbook.pencil.scale.x > pencil_scale * 1.4, "editing pencil scale changes the real prop")
		workshop._undo()
		var wrist_bone: int = int(stage.edge_pose.driver.arms[1]["end"])
		var original_wrist: Quaternion = skeleton.get_bone_global_pose(wrist_bone).basis.get_rotation_quaternion()
		var wrist_index: int = _entry_index(workshop, "right_hand_rotation")
		workshop.choice.select(wrist_index)
		workshop._on_channel_selected(wrist_index)
		_check(workshop.field_values[0].suffix == "°", "wrist rotation controls display degrees")
		workshop._on_field_changed(25.0, 0)
		var edited_wrist: Quaternion = skeleton.get_bone_global_pose(wrist_bone).basis.get_rotation_quaternion()
		_check(original_wrist.angle_to(edited_wrist) > 0.05, "authored wrist rotation reaches the existing hand pose controller")
		workshop._undo()
		var extra = AnimatedProp.new()
		extra.prop_id = "test_lantern"
		extra.display_name = "Фонарь"
		extra.anchor_bone = "hips"
		stage.pivot.add_child(extra)
		workshop._collect_channel_entries()
		var extra_index: int = _entry_index(workshop, "test_lantern", "position")
		_check(extra_index >= 0, "new registered prop appears in workshop without editing its UI")
		workshop.choice.select(extra_index)
		workshop._on_channel_selected(extra_index)
		workshop._on_field_changed(3.0, 1)
		_check(SketchMotion.sample(0.82).get("props", {}).has("test_lantern"), "editing new prop creates its Animation track")
		workshop._undo()
		_check(not SketchMotion.sample(0.82).get("props", {}).has("test_lantern"), "undo removes the newly created prop track")
		extra.queue_free()
		var temporary: String = "res://.workspace/test_workshop_clip.tres"
		var save_result: Error = ResourceSaver.save(SketchMotion.clip.duplicate(true), temporary)
		var loaded: Animation = ResourceLoader.load(temporary, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation if save_result == OK else null
		_check(save_result == OK and SketchMotion.valid(loaded), "authored animation serializes and reloads as a Godot resource")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	workshop.queue_free()
	await process_frame
	print("HOSHI_ANIMATION_WORKSHOP_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
