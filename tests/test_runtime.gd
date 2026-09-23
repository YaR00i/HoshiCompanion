extends SceneTree
## Run with TEST_WINDOWS.bat after import. No transparent-window claims here.

const Source = preload("res://scripts/vrm_source.gd")
const State = preload("res://scripts/companion_state.gd")
const Stage = preload("res://scripts/avatar_stage.gd")
const Locomotion = preload("res://scripts/locomotion.gd")
const Director = preload("res://scripts/behavior_director.gd")
const IntentPlanner = preload("res://scripts/intent_planner.gd")
const InteractionSession = preload("res://scripts/interaction_session.gd")
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
	_check(stage.head_contact_hit(stage.head_pixel()), "projected head center belongs to the petting contact zone")
	_check(not stage.head_contact_hit(stage.standing_anchor_pixel()), "feet stay outside the head petting contact zone")
	_check(stage.hand_contact_side(stage.hand_pixel("left")) == "left", "left palm can start a cursor hold")
	_check(stage.hand_contact_side(stage.hand_pixel("right")) == "right", "right palm can start a cursor hold")
	_check(stage.hand_contact_side(stage.head_pixel()) == "", "head contact cannot trigger a cursor hold")
	var hair_edge: Vector2 = stage.head_pixel() + Vector2(stage.body_pixels * 0.20, 0.0)
	_check(not stage.head_contact_hit(hair_edge) and stage.head_stroke_zone_hit(hair_edge), "an ongoing head stroke tolerates the outer hair zone")
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
	state.notice()
	for frame in range(18):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2(0.2, -0.1))
	_check(not state.dozing and state.notice_weight > 0.8, "brief contact wakes Hoshi into a visible attention reaction")
	_check(float(state.expression_weights().get("surprised", 0.0)) > 0.1, "attention adds a restrained surprised expression")
	state.dozing = true
	state.recognize()
	for frame in range(18):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	_check(not state.dozing and state.welcome_weight > 0.8 and float(state.expression_weights().get("happy", 0.0)) > 0.35, "recognition wakes Hoshi with a calm smile and distinct head pose")
	state.begin_pet_contact()
	for frame in range(18):
		state.update_pet_contact(Vector2(-1.0, 0.0), 1.0 / 30.0)
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	var head_left: Quaternion = stage.rig.skeleton.get_bone_pose_rotation(int(stage.rig.bones["head"]))
	_check(not state.dozing and state.pet_weight > 0.8, "held head contact wakes Hoshi and sustains a response")
	_check(float(state.expression_weights().get("happy", 0.0)) > 0.35 and float(state.expression_weights().get("blink", 0.0)) > 0.1, "held petting softens the live facial expression and eyes")
	for frame in range(2):
		state.update_pet_contact(Vector2(1.0, 0.0), 1.0 / 30.0)
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	var head_early: Quaternion = stage.rig.skeleton.get_bone_pose_rotation(int(stage.rig.bones["head"]))
	_check(head_left.angle_to(head_early) < deg_to_rad(3.0), "reversing the mouse does not snap the head immediately")
	for frame in range(18):
		state.update_pet_contact(Vector2(1.0, 0.0), 1.0 / 30.0)
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	var head_right: Quaternion = stage.rig.skeleton.get_bone_pose_rotation(int(stage.rig.bones["head"]))
	_check(head_left.angle_to(head_right) > deg_to_rad(3.0) and head_left.angle_to(head_right) < deg_to_rad(12.0), "the head follows the cursor gently across the stroke")
	state.end_pet_contact()
	state.begin_cursor_hang()
	for frame in range(18):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	_check(state.cursor_hang_active and float(state.expression_weights().get("happy", 0.0)) > 0.25, "holding the cursor gives Hoshi a temporary pleased expression")
	state.end_cursor_hang()
	state.react_to_release("rough")
	for frame in range(8):
		state.tick(1.0 / 30.0)
	_check(state.release_reaction_active() and float(state.expression_weights().get("surprised", 0.0)) > 0.2, "abrupt release briefly startles Hoshi")
	state.react_to_release("soft")
	for frame in range(8):
		state.tick(1.0 / 30.0)
	_check(float(state.expression_weights().get("happy", 0.0)) > 0.25 and state.state_label() == "Бережно опускается", "gentle release changes to a soft recovery")
	state.notice()
	_check(not state.release_reaction_active(), "new manual contact interrupts a release reaction")
	for frame in range(400):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
		max_blink = maxf(max_blink, state.blink)
	_check(max_blink > 0.8, "spontaneous blinking occurs")
	_check(state.notice_weight < 0.001 and state.pet_weight < 0.001 and state.wave_weight < 0.001, "temporary reactions return to idle")
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
	_check_intent_planner()
	_check_interaction_session()
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
	var arrival = State.new()
	arrival.place_mode = "smart"
	arrival.activity = "quiet"
	arrival.time = 120.0
	_check(not arrival.allows_autonomous_floor_rest(), "smart place keeps automatic floor rest out of the place search")
	arrival.place_mode = "cozy"
	_check(not arrival.allows_autonomous_floor_rest(), "cozy place keeps automatic floor rest in the corner")
	arrival.place_mode = "off"
	arrival.time = State.FLOOR_REST_GRACE_SECONDS - 0.1
	_check(not arrival.allows_autonomous_floor_rest(), "arrival has a standing grace period")
	arrival.time = State.FLOOR_REST_GRACE_SECONDS
	_check(arrival.allows_autonomous_floor_rest(), "floor rest becomes possible after arrival when no place is selected")
	arrival.rest_enabled = false
	_check(not arrival.allows_autonomous_floor_rest(), "disabled automatic rest stays disabled in the planner")
	arrival.posture.request_sit(false)
	_check(arrival.posture.target_seated and not arrival.posture.automatic, "manual floor sit remains available")
	arrival.rest_enabled = true
	arrival.motion_enabled = false
	_check(not arrival.allows_autonomous_floor_rest(), "disabled motion cannot select an impossible sit")
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
	_check(quiet_rest.automatic_rest_duration() <= 32.0, "quiet automatic floor rest ends within a short scene")
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

func _check_intent_planner() -> void:
	var context: Dictionary = {"blocked": false, "location": "floor", "can_observe": true, "can_walk": true, "can_rest": true, "can_social": true}
	var first_choice = IntentPlanner.new()
	var quiet_first: Dictionary = first_choice.candidate_report(context, "quiet")
	_check(float(quiet_first["rest"]["weight"]) < float(quiet_first["observe"]["weight"]) * 0.2, "quiet floor rest is rarer than observation")
	var a = IntentPlanner.new()
	var b = IntentPlanner.new()
	a.seed_random(991)
	b.seed_random(991)
	var seq_a: Array[String] = []
	var seq_b: Array[String] = []
	for i in range(18):
		var pa: Dictionary = a.choose(context, "normal")
		var pb: Dictionary = b.choose(context, "normal")
		seq_a.append(str(pa.get("name", "")))
		seq_b.append(str(pb.get("name", "")))
		if not pa.is_empty(): a.activate(pa)
		if not pb.is_empty(): b.activate(pb)
	_check(seq_a == seq_b, "intent planner is deterministic for identical seed and context")
	var impossible: Dictionary = a.build_plan("explore_floor", {"blocked": false, "location": "floor", "can_walk": false})
	_check(impossible.is_empty(), "intent planner rejects impossible actions before execution")
	var surface: Dictionary = {"blocked": false, "location": "surface", "can_surface_walk": true, "can_side": true, "can_leave": true, "can_observe": true}
	var side_plan: Dictionary = a.build_plan("visit_side", surface)
	_check(not side_plan.is_empty() and (side_plan.get("steps", []) as Array).size() <= IntentPlanner.MAX_STEPS, "intent planner creates bounded short plans")
	var no_triplicate: bool = true
	var c = IntentPlanner.new()
	c.seed_random(881)
	var previous: String = ""
	var run_length: int = 0
	for i in range(80):
		var plan: Dictionary = c.choose(context, "playful")
		if plan.is_empty(): continue
		var name: String = str(plan["name"])
		run_length = run_length + 1 if name == previous else 1
		previous = name
		no_triplicate = no_triplicate and run_length < 3
		c.activate(plan)
	_check(no_triplicate, "novelty memory prevents three identical intentions in a row")
	var active: Dictionary = a.build_plan("explore_floor", context)
	_check(a.activate(active) and not a.active_intent.is_empty(), "intent planner can hold one active plan")
	a.interrupt("manual_test")
	_check(a.active_intent.is_empty() and a.last_interrupt_reason == "manual_test", "manual input cancels active intention immediately")
	var shadow = IntentPlanner.new()
	shadow.seed_random(12)
	var observed: Dictionary = shadow.observe_legacy_action("walk", context)
	_check(observed.get("name", "") == "explore_floor" and shadow.current_step() == "walk", "shadow mode maps legacy action without executing it")
	_check(shadow.cooldown_left("explore_floor") > 17.9 and not shadow.intent_available("explore_floor", context), "activation arms per-intent cooldown")
	var report: Dictionary = shadow.candidate_report(context, "normal")
	_check(report["explore_floor"]["reason"] == "cooldown" and float(report["explore_floor"]["weight"]) == 0.0, "candidate report explains cooldown rejection")
	for i in range(181): shadow.tick(0.1, context)
	_check(shadow.cooldown_left("explore_floor") <= 0.001 and shadow.intent_available("explore_floor", context), "cooldown expires only through planner time")
	var invalid_report: Dictionary = shadow.candidate_report({"blocked": false, "location": "floor", "can_walk": false, "can_rest": false, "can_observe": false, "can_social": false}, "normal")
	_check(invalid_report["explore_floor"]["reason"] == "cannot_walk" and invalid_report["rest"]["reason"] == "cannot_rest", "candidate report preserves concrete precondition reasons")
	var novelty = IntentPlanner.new()
	novelty.seed_random(3)
	var observe_plan: Dictionary = novelty.build_plan("observe", context)
	novelty.activate(observe_plan)
	var first_novelty: float = float(novelty.candidate_report(context, "normal")["observe"]["novelty"])
	_check(first_novelty < 0.2, "most recent intention receives a strong novelty penalty")
	var keep = IntentPlanner.new()
	var keep_plan: Dictionary = {"name": "explore_floor", "variant": "blocked_test", "steps": ["walk", "look"], "index": 0}
	keep.activate(keep_plan)
	keep.tick(0.1, {"blocked": true, "location": "floor", "can_walk": false})
	_check(keep.current_step() == "walk", "controller-blocked frame does not erase an in-flight intent")
	var chain = IntentPlanner.new()
	var chain_plan: Dictionary = {"name": "explore_floor", "variant": "test_walk_look", "steps": ["walk", "look"], "index": 0}
	_check(chain.activate(chain_plan) and chain.current_step() == "walk", "floor exploration begins with locomotion")
	_check(chain.complete_step() == "look" and chain.current_step() == "look", "floor exploration advances to observation only after walk completion")
	_check(chain.complete_step() == "explore_floor" and chain.active_intent.is_empty(), "short floor intent completes after its final real step")
	var attention = Director.new()
	attention.seed_random(5)
	attention.decisions_enabled = false
	attention.request_observe(Vector2(0.3, 0.1), true)
	var emitted: bool = false
	for i in range(120):
		emitted = emitted or not attention.tick(1.0 / 30.0, {"cursor_near": true, "cursor_gaze": Vector2(0.3, 0.1), "can_walk": true, "can_rest": true}).is_empty()
	_check(not emitted and not attention.look_active(), "attention-only director finishes gaze without emitting legacy actions")
	var scenes = IntentPlanner.new()
	scenes.seed_random(404)
	var scene_ids: Array[String] = []
	for i in range(12):
		var scene: Dictionary = scenes.build_plan("explore_floor", context, "playful")
		_check((scene.get("steps", []) as Array).size() >= 2 and (scene.get("steps", []) as Array).size() <= IntentPlanner.MAX_STEPS, "floor scene stays within bounded step count")
		scene_ids.append(str(scene.get("variant", "")))
		scenes.activate(scene)
		scenes.interrupt("scene_test")
	var repeated_variant: bool = false
	for i in range(1, scene_ids.size()):
		repeated_variant = repeated_variant or scene_ids[i] == scene_ids[i - 1]
	var unique_scene_ids: Dictionary = {}
	for scene_id in scene_ids:
		unique_scene_ids[scene_id] = true
	_check(not repeated_variant and unique_scene_ids.size() >= 3, "scene memory rotates among multiple floor variants without immediate repeats")
	var quiet_report: Dictionary = scenes.candidate_report(context, "quiet")
	_check(float(quiet_report["social_react"]["weight"]) == 0.0, "quiet activity suppresses autonomous social wave intents")
	var surface_scenes = IntentPlanner.new()
	surface_scenes.seed_random(818)
	var surface_context: Dictionary = {"blocked": false, "location": "surface", "can_observe": true, "can_surface_walk": true, "can_side": true, "can_leave": true, "preferred_side": "left"}
	var quiet_vibes: Dictionary = {}
	var quiet_bounded: bool = true
	var quiet_no_repeat: bool = true
	var previous_quiet_variant: String = ""
	for i in range(8):
		var quiet_scene: Dictionary = surface_scenes.build_plan("observe", surface_context, "quiet")
		var quiet_steps: Array = quiet_scene.get("steps", [])
		var quiet_variant: String = str(quiet_scene.get("variant", ""))
		quiet_bounded = quiet_bounded and quiet_steps.size() > 0 and quiet_steps.size() <= IntentPlanner.MAX_STEPS
		quiet_no_repeat = quiet_no_repeat and quiet_variant != previous_quiet_variant
		previous_quiet_variant = quiet_variant
		for step in quiet_steps:
			quiet_vibes[str(step)] = true
		surface_scenes.activate(quiet_scene)
		surface_scenes.interrupt("quiet_surface_scene_test")
	_check(quiet_bounded and quiet_vibes.size() == 1 and quiet_vibes.has("edge_sway"), "quiet surface scenes use only accepted bounded sway")
	var cozy_scenes = IntentPlanner.new()
	cozy_scenes.seed_random(819)
	var cozy_context: Dictionary = surface_context.duplicate()
	cozy_context["cozy"] = true
	cozy_context["can_leave"] = false
	var cozy_steps: Dictionary = {}
	for i in range(12):
		var cozy_scene: Dictionary = cozy_scenes.build_plan("observe", cozy_context, "quiet")
		for step in cozy_scene.get("steps", []):
			cozy_steps[str(step)] = true
		cozy_scenes.activate(cozy_scene)
		cozy_scenes.interrupt("cozy_scene_test")
	_check(cozy_steps.has("edge_sway") and cozy_steps.has("edge_sketch") and cozy_steps.has("look"), "cozy quiet scenes alternate sway, notebook and looking around")
	_check(cozy_scenes.rejection_reason("leave_support", cozy_context) == "cannot_leave", "cozy corner remains the autonomous home")
	var normal_vibes: Dictionary = {}
	var normal_bounded: bool = true
	var normal_no_repeat: bool = true
	var previous_normal_variant: String = ""
	for i in range(36):
		var normal_scene: Dictionary = surface_scenes.build_plan("explore_surface", surface_context, "normal")
		var normal_steps: Array = normal_scene.get("steps", [])
		var normal_variant: String = str(normal_scene.get("variant", ""))
		normal_bounded = normal_bounded and normal_steps.size() > 0 and normal_steps.size() <= IntentPlanner.MAX_STEPS
		normal_no_repeat = normal_no_repeat and normal_variant != previous_normal_variant
		previous_normal_variant = normal_variant
		for step in normal_steps:
			if str(step) == "edge_sway":
				normal_vibes[str(step)] = true
		surface_scenes.activate(normal_scene)
		surface_scenes.interrupt("normal_surface_scene_test")
	_check(normal_bounded and normal_no_repeat and normal_vibes.size() == 1, "normal surface exploration reaches accepted sway without immediate variant repeats")
	var side_endings: Dictionary = {}
	var side_bounded: bool = true
	for i in range(6):
		var side_scene: Dictionary = surface_scenes.build_plan("visit_side", surface_context, "playful")
		var side_steps: Array = side_scene.get("steps", [])
		side_bounded = side_bounded and side_steps.size() == IntentPlanner.MAX_STEPS
		if not side_steps.is_empty():
			side_endings[str(side_steps.back())] = true
		surface_scenes.activate(side_scene)
		surface_scenes.interrupt("side_surface_scene_test")
	_check(side_bounded and side_endings.size() == 1 and side_endings.has("edge_peek"), "side visits keep the accepted bounded peek ending while hum remains manual")

func _check_interaction_session() -> void:
	var session = InteractionSession.new()
	session.begin(Vector2.ZERO, false, 480.0)
	session.update(Vector2(2.0, 1.0), 0.06, false)
	_check(not session.should_begin_drag() and session.finish(false, false) == "attention", "short body click is classified as attention")
	session.begin(Vector2.ZERO, true, 480.0)
	session.update(Vector2(7.0, 0.0), 0.08, true)
	session.update(Vector2(-5.0, 0.0), 0.08, true)
	_check(session.petting_now() and not session.should_begin_drag() and session.finish(false, false) == "pet", "soft head movement starts a response while the button is held")
	session.begin(Vector2.ZERO, true, 360.0)
	session.update(Vector2(38.0, 0.0), 0.09, true)
	_check(not session.should_begin_drag() and session.finish(false, false) == "pet", "one gentle head stroke at desktop scale remains a pet, not a pickup")
	session.begin(Vector2.ZERO, true, 360.0)
	session.update(Vector2(80.0, 0.0), 0.10, true)
	_check(session.petting_now() and not session.should_begin_drag() and session.finish(false, false) == "pet", "a wide stroke remains petting while the pointer stays on the head")
	session.begin(Vector2.ZERO, false, 480.0)
	session.update(Vector2(7.0, 0.0), 0.03, false)
	_check(session.should_begin_drag(), "body drag keeps the original six-pixel pickup threshold")
	session.finish(true, false)
	session.begin(Vector2.ZERO, true, 360.0)
	session.update(Vector2(24.0, 0.0), 0.08, true)
	session.update(Vector2(35.0, 0.0), 0.08, false)
	var hair_gap_safe: bool = not session.should_begin_drag()
	session.update(Vector2(54.0, 0.0), 0.08, false)
	_check(hair_gap_safe and session.should_begin_drag(), "a head stroke never falls back to body pickup after a hair gap, but a deliberate pull still works")
	session.finish(true, false)
	session.begin(Vector2.ZERO, true, 360.0)
	session.update(Vector2(20.0, 0.0), 0.10, true)
	session.update(Vector2(70.0, 0.0), 0.05, false)
	var exit_grace: bool = not session.should_begin_drag()
	session.update(Vector2(76.0, 0.0), 0.08, false)
	_check(exit_grace and session.should_begin_drag(), "an active pet tolerates a brief zone exit before deliberate head pickup")
	session.finish(true, false)
	session.begin(Vector2.ZERO, true, 360.0)
	for index in range(90):
		session.update(Vector2(12.0 if index % 2 == 0 else -12.0, 0.0), 0.05, true)
	_check(session.petting_now() and not session.should_begin_drag() and session.finish(false, false) == "pet", "a long held back-and-forth stroke remains active until release")
	session.begin(Vector2.ZERO, true, 360.0)
	session.update(Vector2(14.0, 0.0), 0.1, true)
	session.update(Vector2(18.0, 0.0), 0.05, false)
	var temporarily_outside: bool = not session.petting_now() and not session.should_begin_drag()
	session.update(Vector2(12.0, 0.0), 0.05, true)
	_check(temporarily_outside and session.petting_now(), "a brief exit from the head zone pauses and resumes the same stroke")
	session.finish(false, false)
	for index in range(20):
		session.begin(Vector2.ZERO, false, 360.0)
		session.finish(false, false)
	_check(session.recent_events().size() <= InteractionSession.MAX_HISTORY, "interaction session history stays bounded")
	session.begin(Vector2.ZERO, false, 360.0)
	_check(session.release_style(Vector2(120.0, 60.0), 90.0) == "soft", "slow low release is gentle")
	_check(session.release_style(Vector2(1150.0, 0.0), 90.0) == "rough", "fast sideways flick is abrupt")
	_check(session.release_style(Vector2(0.0, 760.0), 90.0) == "rough", "fast downward drop is abrupt")
	_check(session.release_style(Vector2.ZERO, 300.0) == "rough", "high release remains a significant drop")
	session.record_release("soft")
	_check(session.recent_events().size() == InteractionSession.MAX_HISTORY and str(session.recent_events().back().get("kind", "")) == "release_soft", "release joins bounded local history")
	var social = InteractionSession.new()
	social.tick(50.0)
	social.begin(Vector2.ZERO, false, 360.0)
	_check(social.finish(false, false) == "attention", "first contact is ordinary attention even after startup idle")
	social.begin(Vector2.ZERO, false, 360.0)
	_check(social.finish(false, false) == "quiet", "rapid repeated click does not restart the full reaction")
	social.tick(3.0)
	social.begin(Vector2.ZERO, false, 360.0)
	_check(social.finish(false, false) == "attention", "attention can respond again after its short cooldown")
	social.tick(46.0)
	social.begin(Vector2.ZERO, false, 360.0)
	_check(social.finish(false, false) == "return", "contact after a real pause recognizes the returning user")
	social.begin(Vector2.ZERO, false, 360.0)
	_check(social.finish(false, false, true) == "wake", "sleeping contact wins over click cooldown")
	_check(social.accept_wave() and not social.accept_wave(), "rapid repeated wave starts once")
	_check(social.accept_button_pet() and not social.accept_button_pet(), "rapid pet button presses start one short response")
	_check(social.allow_bubble() and not social.allow_bubble(), "rapid actions share a quiet bubble cooldown")
	social.tick(8.1)
	_check(social.accept_wave() and social.accept_button_pet() and social.allow_bubble(), "manual reactions and bubble recover after cooldown")
	_check(social.accept_palm_attention() and not social.accept_palm_attention(), "repeated palm taps stay quiet between full attention reactions")

func _finish() -> void:
	var report: Dictionary = {"engine": Engine.get_version_info(), "checks": checks, "failures": failures,
		"headless": DisplayServer.get_name() == "headless", "windows_transparency_tested": false, "walking": walking_metrics}
	var file: FileAccess = FileAccess.open("user://runtime_checks.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("HOSHI_TEST_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
