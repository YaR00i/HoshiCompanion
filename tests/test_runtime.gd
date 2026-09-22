extends SceneTree
## Run with TEST_WINDOWS.bat after import. No transparent-window claims here.

const Source = preload("res://scripts/vrm_source.gd")
const State = preload("res://scripts/companion_state.gd")
const Stage = preload("res://scripts/avatar_stage.gd")
const Locomotion = preload("res://scripts/locomotion.gd")
const Director = preload("res://scripts/behavior_director.gd")
const UI = preload("res://scripts/companion_ui.gd")

var failures: int = 0
var checks: int = 0
var walking_metrics: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	_check(Source.parse_container(PackedByteArray()).has("error"), "reject empty input")
	var bad: PackedByteArray = PackedByteArray()
	bad.resize(28)
	_check(Source.parse_container(bad).has("error"), "reject invalid magic")
	var source: Dictionary = Source.read_container("res://assets/Hoshi_v1.vrm")
	_check(not source.has("error"), "read original Hoshi VRM 1.0")
	if source.has("error"):
		_finish()
		return
	var native_glb: PackedByteArray = Source.make_native_glb(source["json"], source["binary"])
	_check(native_glb.decode_u32(8) == native_glb.size(), "converted GLB header length")
	var json_size: int = native_glb.decode_u32(12)
	var raw: Variant = JSON.parse_string(native_glb.slice(20, 20 + json_size).get_string_from_utf8())
	_check(raw is Dictionary, "converted GLB JSON parses")
	_check(not raw.get("extensions", {}).has("VRMC_vrm"), "VRM extensions handled outside native importer")
	_check(int(raw["nodes"][139].get("extras", {}).get(Source.NODE_MARKER, -1)) == 139, "temporary GLB preserves source node identity")
	_check(int(raw["meshes"][0].get("extras", {}).get(Source.MESH_MARKER, -1)) == 0, "temporary GLB preserves source mesh identity")
	_check(raw["meshes"][0]["extras"]["targetNames"] == source["json"]["meshes"][0]["extras"]["targetNames"], "metadata tagging preserves all target names")
	_check(not source["json"]["nodes"][139].get("extras", {}).has(Source.NODE_MARKER), "original source JSON remains untouched")
	_check(native_glb.slice(28 + json_size) == source["binary"], "mesh/texture BIN bytes unchanged")
	var stage = Stage.new()
	stage.size = Vector2(560.0, 620.0)
	root.add_child(stage)
	await process_frame
	var result: Dictionary = stage.load_model("res://assets/Hoshi_v1.vrm")
	_check(not result.has("error"), "Godot runtime imports actual VRM avatar")
	if result.has("error"):
		print(result["error"])
		stage.queue_free()
		await process_frame
		_finish()
		return
	_check(stage.is_loaded, "body animation enabled after setup")
	_check(result.get("status", "") == "ready", "actual Hoshi must be fully ready, not a silent partial fallback")
	_check(bool(result["face"].get("blink_available", false)), "actual Hoshi blink resolved on a live mesh")
	_check(result["face"].get("mapping", []).size() > 0, "mesh mapping diagnostics emitted")
	_check(stage.model_height > 0.5 and stage.model_height < 3.0, "model scale is plausible")
	_check(int(result["mesh_count"]) >= 3, "face, body and hair mesh nodes")
	_check(stage.rig.bones.size() >= 40, "humanoid bones resolved")
	for expression in ["blink", "happy", "sad", "surprised", "relaxed", "aa"]:
		_check(stage.expressions.bindings.has(expression), "morph expression bound: " + expression)
	var state = State.new()
	state.seed_random(42)
	stage.animate(0.0, state, Vector2.ZERO)
	var rest_hand: Vector3 = stage.rig.world_point("rightHand")
	var shoulder: Vector3 = stage.rig.world_point("rightUpperArm")
	_check(rest_hand.y < shoulder.y - 0.15, "arms are lowered from T-pose in idle")
	stage.expressions.apply({"blink": 1.0})
	var actual_blink: bool = false
	if stage.expressions.bindings.has("blink"):
		for target in stage.expressions.bindings["blink"]["targets"]:
			actual_blink = actual_blink or target["mesh"].get_blend_shape_value(int(target["index"])) > 0.9
	_check(actual_blink, "blink writes to the live mesh's actual morph channel")
	stage.expressions.apply({})
	state.wave()
	var max_blink: float = 0.0
	for frame in range(90):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2(0.25, -0.2))
		max_blink = maxf(max_blink, state.blink)
		if frame == 30:
			var wave_hand: Vector3 = stage.rig.world_point("rightHand")
			_check(wave_hand.y > rest_hand.y + 0.15, "wave raises the hand, not just the whole model")
	_check(stage.rig.world_point("head").is_finite(), "finite head pose")
	state.dozing = true
	for frame in range(90):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	_check(state.sleep_weight > 0.95, "smooth dozing transition")
	_check(float(state.expression_weights().get("blink", 0.0)) > 0.7, "eyes close in dozing state")
	state.pet()
	_check(not state.dozing, "pet reaction wakes companion")
	for frame in range(400):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
		max_blink = maxf(max_blink, state.blink)
	_check(max_blink > 0.8, "spontaneous blinking occurs")
	_check(state.pet_weight < 0.001 and state.wave_weight < 0.001, "temporary reactions return to idle")
	state.set_mood("invalid")
	_check(state.mood == "neutral", "unknown moods ignored")
	for mood in State.MOODS:
		state.set_mood(mood)
		for frame in range(30):
			state.tick(1.0 / 30.0)
			stage.animate(1.0 / 30.0, state, Vector2.ZERO)
		var values_ok: bool = true
		for mesh in stage.expressions.controlled_meshes:
			for index in range(mesh.get_blend_shape_count()):
				var weight: float = mesh.get_blend_shape_value(index)
				values_ok = values_ok and is_finite(weight) and weight >= 0.0 and weight <= 1.0
		_check(values_ok, "finite bounded expression weights: " + mood)
	stage.expressions.apply({})
	var all_zero: bool = true
	for mesh in stage.expressions.controlled_meshes:
		for index in stage.expressions.controlled_indices[mesh.get_instance_id()]:
			all_zero = all_zero and absf(mesh.get_blend_shape_value(index)) < 0.00001
	_check(all_zero, "expression channels clear without residual smile")
	_check_walk_runtime(stage)
	_check_behavior()
	stage.rig.reset()
	var finite_rest: bool = true
	for bone in range(stage.rig.skeleton.get_bone_count()):
		finite_rest = finite_rest and stage.rig.skeleton.get_bone_pose_position(bone).is_finite()
	_check(finite_rest, "rest pose reset stays finite")
	var user_interface = UI.new()
	root.add_child(user_interface)
	await process_frame
	await process_frame
	_check(user_interface.menu.get_item_index(199) >= 0, "close command exists")
	_check(user_interface.panel.get_combined_minimum_size().y <= 580.0, "preview controls fit vertically")
	user_interface.model_ready("Test Hoshi", result)
	_check(user_interface.note.text.contains("моргание подключено"), "UI reports actual facial capability")
	user_interface.queue_free()
	# Repeated setup must not duplicate hair entries.
	var hair_before: int = stage.rig._hair.size()
	stage.rig.setup(stage.avatar, stage.model_data["source"], stage.model_data["state"])
	_check(stage.rig._hair.size() == hair_before, "repeated rig setup does not accumulate hair bones")
	await _check_degraded_startup(source)
	stage.queue_free()
	await process_frame
	_finish()

func _check_degraded_startup(source: Dictionary) -> void:
	# A face-less test variant is written only into this app's user data directory.
	# Never modify the supplied avatar. The variant is removed at the end.
	var altered: Dictionary = source["json"].duplicate(true)
	altered["extensions"]["VRMC_vrm"]["expressions"]["preset"] = {}
	var path: String = "user://hoshi_runtime_no_face_test.vrm"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "create isolated missing-expression fixture")
	if file == null:
		return
	file.store_buffer(Source.pack_container(altered, source["binary"]))
	file.close()
	var partial = Stage.new()
	partial.size = Vector2(560.0, 620.0)
	root.add_child(partial)
	await process_frame
	var result: Dictionary = partial.load_model(path)
	_check(not result.has("error") and partial.is_loaded, "missing blink cannot abort body initialization")
	_check(result.get("status", "") == "partial", "missing blink is reported, never hidden as full success")
	_check(not result.get("face", {}).get("blink_available", true), "missing blink capability is false")
	if partial.is_loaded:
		var state = State.new()
		partial.animate(0.0, state, Vector2.ZERO)
		_check(partial.rig.world_point("rightHand").y < partial.rig.world_point("rightUpperArm").y - 0.15, "no-face avatar still leaves the T-pose")
	partial.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check_walk_runtime(stage) -> void:
	_check(stage.gait.available, "walk IK maps both complete legs on the actual Hoshi")
	if not stage.gait.available:
		return
	var state = State.new()
	state.seed_random(50)
	state.autonomy_enabled = false
	var max_error: float = 0.0
	var max_slide: float = 0.0
	var max_lift: float = 0.0
	for fps in [30, 60]:
		for direction in [-1, 1]:
			var walker = Locomotion.new()
			var goal: float = float(direction) * 240.0
			_check(walker.request(0.0, goal, Vector2(-400.0, 400.0), stage.meters_per_pixel(), stage.model_height, 0.0), "accept a walk at %d FPS / direction %d" % [fps, direction])
			var previous_frame: Dictionary = {}
			var previous_feet: Array[Vector3] = []
			var all_finite: bool = true
			var in_bounds: bool = true
			for index in range(1800):
				var dt: float = 1.0 / float(fps)
				walker.tick(dt)
				state.tick(dt)
				var frame: Dictionary = walker.sample()
				stage.yaw = walker.yaw
				stage.travel_offset_px = walker.x_px
				stage.animate(dt, state, Vector2.ZERO, frame)
				var feet: Array[Vector3] = [stage.rig.world_point("leftFoot"), stage.rig.world_point("rightFoot")]
				in_bounds = in_bounds and walker.x_px >= minf(0.0, goal) - 0.001 and walker.x_px <= maxf(0.0, goal) + 0.001
				for side in range(2):
					all_finite = all_finite and feet[side].is_finite()
					if walker.mode == "walk":
						var expected: Vector3 = stage.rig.skeleton.global_transform * stage.gait.last_targets[side]
						max_error = maxf(max_error, feet[side].distance_to(expected))
						var offset: Vector3 = frame["left" if side == 0 else "right"]
						max_lift = maxf(max_lift, offset.y)
				if frame["mode"] == "walk" and previous_frame.get("mode", "") == "walk" and frame["step"] == previous_frame["step"]:
					var support: int = 1 if int(frame["step"]) % 2 == 0 else 0
					max_slide = maxf(max_slide, feet[support].distance_to(previous_feet[support]))
				previous_frame = frame
				previous_feet = feet
				if not walker.active():
					break
			_check(not walker.active() and absf(walker.x_px - goal) < 0.001, "walk finishes exactly at target, %d FPS / %d" % [fps, direction])
			_check(all_finite and in_bounds, "walk stays finite and inside the lane")
			_check(absf(walker.yaw) < 0.001, "walk returns to front-facing idle")
	_check(max_error < 0.003, "actual Skeleton3D ankle IK error below 3 mm")
	_check(max_slide < 0.003, "actual world-space support foot slides less than 3 mm per frame")
	_check(max_lift > stage.model_height * 0.02, "swinging foot lifts clear of the ground")
	walking_metrics = {"max_ankle_target_error_m": max_error, "max_stance_frame_drift_m": max_slide, "max_foot_lift_m": max_lift}
	var stopped = Locomotion.new()
	stopped.request(0.0, 240.0, Vector2(-400.0, 400.0), stage.meters_per_pixel(), stage.model_height, 0.0)
	for index in range(300):
		stopped.tick(1.0 / 60.0)
		if stopped.mode == "walk" and stopped.travelled_m > stopped.distance_m * 0.36:
			break
	var before: Dictionary = stopped.sample()
	stopped.stop()
	var after: Dictionary = stopped.sample()
	_check(before["left"].is_equal_approx(after["left"]) and before["right"].is_equal_approx(after["right"]), "stop starts from the current feet, without a pose jump")
	var stop_x: float = stopped.x_px
	for index in range(180):
		stopped.tick(1.0 / 60.0)
	_check(not stopped.active() and is_equal_approx(stopped.x_px, stop_x), "stop settles the feet without continuing the path")
	var invalid = Locomotion.new()
	_check(not invalid.request(0.0, 1.0, Vector2(-100.0, 100.0), 0.004, 1.5, 0.0), "too-short routes are rejected")
	stage.travel_offset_px = 0.0
	stage.yaw = 0.0
	stage.gait.reset()

func _check_behavior() -> void:
	for activity in ["quiet", "normal", "playful"]:
		var director = Director.new()
		director.seed_random(12)
		director.set_activity(activity)
		var walks: int = 0
		var waves: int = 0
		for index in range(18000):
			var action: String = director.tick(1.0 / 30.0, {"can_walk": true, "cursor_near": true, "cursor_gaze": Vector2(0.2, 0.1)})
			if action == "walk": walks += 1
			if action == "wave": waves += 1
		if activity == "quiet":
			_check(walks == 0 and waves == 0, "quiet mode never starts an autonomous walk or wave")
		else:
			_check(walks > 0 and walks < 30, "bounded autonomous initiative: " + activity)
	var playful_rest = Director.new()
	playful_rest.set_activity("playful")
	var normal_rest = Director.new()
	normal_rest.set_activity("normal")
	var quiet_rest = Director.new()
	quiet_rest.set_activity("quiet")
	_check(playful_rest.automatic_rest_duration() < normal_rest.automatic_rest_duration() and normal_rest.automatic_rest_duration() < quiet_rest.automatic_rest_duration(), "activity changes autonomous rest duration, not just timer frequency")
	var blocked = Director.new()
	blocked.seed_random(2)
	var no_action: bool = true
	for index in range(3600):
		no_action = no_action and blocked.tick(1.0 / 30.0, {"can_walk": true, "blocked": true}).is_empty()
	_check(no_action, "menus, dragging and sleep suppress autonomous actions")
	blocked.enabled = false
	no_action = true
	for index in range(3600):
		no_action = no_action and blocked.tick(1.0 / 30.0, {"can_walk": true}).is_empty()
	_check(no_action, "disabled autonomy never emits actions")

func _finish() -> void:
	var report: Dictionary = {"engine": Engine.get_version_info(), "checks": checks, "failures": failures,
		"headless": DisplayServer.get_name() == "headless", "windows_transparency_tested": false, "walking": walking_metrics}
	var file: FileAccess = FileAccess.open("user://runtime_checks.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("HOSHI_TEST_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
