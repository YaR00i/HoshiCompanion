extends SceneTree
const Air = preload("res://scripts/air_motion.gd")
const Stage = preload("res://scripts/avatar_stage.gd")
const State = preload("res://scripts/companion_state.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func screen_point(stage, semantic: String) -> Vector2:
	return stage.camera.unproject_position(stage.rig.world_point(semantic))

func advance_context(stage, state, mode: String, velocity: Vector2, frames: int) -> void:
	for i in range(frames):
		stage.set_context_action(mode, velocity, 1.0 if mode == "cursor_hang" else -1.0)
		state.tick(1.0 / 30.0, false)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)

func _run() -> void:
	var air := Air.new()
	air.begin_jump(Vector2(100, 500), Vector2(500, 300), 360.0)
	var linear_mid_y: float = 400.0
	var previous_progress: float = air.pose_progress()
	var progress_monotonic: bool = true
	for i in range(10):
		air.tick(0.03)
		progress_monotonic = progress_monotonic and air.pose_progress() >= previous_progress
		previous_progress = air.pose_progress()
	check(air.position.y < linear_mid_y, "jump route rises above the straight line")
	check(progress_monotonic and previous_progress > 0.0 and previous_progress < 1.0, "jump exposes monotonic normalized pose phase")
	check(air.screen_velocity().length() > 1.0, "air motion exposes real screen-space velocity to pose layer")
	for i in range(80):
		air.tick(0.03)
	check(air.mode == "idle" and air.position.distance_to(Vector2(500, 300)) < 0.01, "jump lands exactly at target")
	air.begin_fall(Vector2(300, 120), Vector2(360, 620), 360.0)
	check(air.impact_strength() > 1.0, "long fall exposes stronger landing severity")
	var previous_y: float = air.position.y
	var monotonic: bool = true
	for i in range(100):
		air.tick(0.02)
		monotonic = monotonic and air.position.y >= previous_y - 0.01
		previous_y = air.position.y
	check(monotonic and air.mode == "idle" and air.position.distance_to(Vector2(360, 620)) < 0.01, "fall accelerates downward and lands exactly")
	air.begin_fall(Vector2(300, 400), Vector2(300, 520), 360.0, "soft")
	var soft_impact: float = air.impact_strength()
	air.begin_fall(Vector2(300, 400), Vector2(300, 520), 360.0, "rough")
	check(air.impact_strength() > soft_impact + 0.25 and air.target == Vector2(300, 520), "abrupt release strengthens the same fall without changing its route")
	var stage := Stage.new()
	stage.size = Vector2(560, 620)
	root.add_child(stage)
	await process_frame
	var result: Dictionary = stage.load_model("res://assets/Hoshi_v1.vrm")
	check(not result.has("error") and stage.context_pose.available, "context pose maps actual Hoshi")
	if result.has("error"):
		stage.queue_free()
		_finish()
		return
	var alpha_test := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	alpha_test.fill(Color(0.0, 0.0, 0.0, 0.0))
	alpha_test.fill_rect(Rect2i(14, 6, 12, 28), Color.WHITE)
	check(Stage.alpha_image_hit(alpha_test, Vector2(20, 20), Vector2(40, 40)), "app-owned alpha hit accepts a visible avatar pixel")
	check(not Stage.alpha_image_hit(alpha_test, Vector2(3, 3), Vector2(40, 40)), "app-owned alpha hit rejects transparent window space")
	var state := State.new()
	state.rest_enabled = false
	state.autonomy_enabled = true
	stage.idle_life.seed_random(77)
	stage.idle_life._wait = 0.0
	var idle_seen: bool = false
	for i in range(120):
		state.tick(1.0 / 30.0, false)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
		for idle_weight in stage.idle_life.weights.values():
			idle_seen = idle_seen or float(idle_weight) > 0.55
	check(idle_seen, "standing autonomy produces a restrained micro-gesture")
	state.autonomy_enabled = false
	for i in range(90):
		state.tick(1.0 / 30.0, false)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	var idle_cleared: bool = true
	for idle_weight in stage.idle_life.weights.values():
		idle_cleared = idle_cleared and float(idle_weight) < 0.01
	check(idle_cleared, "standing micro-gesture yields immediately to manual-only mode")
	# Weight shift and curiosity are intentionally different gestures.
	stage.rig.reset()
	state.motion_enabled = true
	stage.rig.tick(0.0, state.time, Vector2.ZERO, 0.0, 0.0, 0.0, true)
	var base_head: Vector3 = stage.rig.world_point("head")
	for key in stage.idle_life.weights:
		stage.idle_life.weights[key] = 0.0
	stage.idle_life.weights["weight_left"] = 1.0
	stage.idle_life.apply(state.time)
	var weight_head: Vector3 = stage.rig.world_point("head")
	check(weight_head.distance_to(base_head) < stage.model_height * 0.025, "weight shift stays a subtle settling gesture")
	stage.rig.reset()
	stage.rig.tick(0.0, state.time, Vector2.ZERO, 0.0, 0.0, 0.0, true)
	var base_left_hand: Vector3 = stage.rig.world_point("leftHand")
	var base_right_hand: Vector3 = stage.rig.world_point("rightHand")
	for key in stage.idle_life.weights:
		stage.idle_life.weights[key] = 0.0
	stage.idle_life.weights["peek_left"] = 1.0
	stage.idle_life.apply(state.time)
	var peek_head: Vector3 = stage.rig.world_point("head")
	var peek_left_hand: Vector3 = stage.rig.world_point("leftHand")
	var peek_right_hand: Vector3 = stage.rig.world_point("rightHand")
	check(peek_head.z > base_head.z + stage.model_height * 0.015, "curiosity peek moves head forward")
	check(absf(peek_head.x - base_head.x) < stage.model_height * 0.055, "curiosity peek keeps side bend restrained")
	check(peek_left_hand.z < base_left_hand.z and peek_right_hand.z < base_right_hand.z, "curiosity peek sends both hands behind for balance")
	for key in stage.idle_life.weights:
		stage.idle_life.weights[key] = 0.0
	state.autonomy_enabled = true
	check(stage.idle_life.request_gesture("peek_right"), "planner can request an explicit standing micro-gesture")
	var forced_seen: bool = false
	for i in range(100):
		state.tick(1.0 / 30.0, false)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
		forced_seen = forced_seen or float(stage.idle_life.weights["peek_right"]) > 0.7
	check(forced_seen and not stage.idle_life.forced_active(), "requested standing micro-gesture plays and releases cleanly")
	state.autonomy_enabled = false
	var rest: Array[Transform3D] = []
	for bone in range(stage.rig.skeleton.get_bone_count()):
		rest.append(stage.rig.skeleton.get_bone_rest(bone))
	for mode in ["carry", "cursor_hang", "jump", "fall", "land"]:
		stage.set_context_action(mode, Vector2(420, 260), 0.55 if mode in ["jump", "fall"] else (0.28 if mode == "land" else (1.0 if mode == "cursor_hang" else -1.0)), 1.0)
		for i in range(50):
			state.tick(1.0 / 30.0)
			stage.animate(1.0 / 30.0, state, Vector2.ZERO)
		var finite: bool = true
		for bone in range(stage.rig.skeleton.get_bone_count()):
			finite = finite and stage.rig.skeleton.get_bone_global_pose(bone).origin.is_finite()
		check(finite, mode + " context pose keeps every bone finite")
	stage.set_context_action("cursor_hang", Vector2(320, -160), 1.0)
	for i in range(24):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	check(stage.rig.world_point("leftHand").y > stage.rig.world_point("head").y and stage.rig.world_point("rightHand").y > stage.rig.world_point("head").y, "cursor hang raises both hands above the head")
	var hang_head: Vector2 = stage.head_pixel()
	var left_elbow: Vector2 = stage.camera.unproject_position(stage.rig.world_point("leftLowerArm"))
	var right_elbow: Vector2 = stage.camera.unproject_position(stage.rig.world_point("rightLowerArm"))
	check(absf(left_elbow.x - hang_head.x) > stage.body_pixels * 0.10 and absf(right_elbow.x - hang_head.x) > stage.body_pixels * 0.10, "cursor grip keeps both elbows outside the head")
	check(left_elbow.y > stage.hand_pixel("left").y and right_elbow.y > stage.hand_pixel("right").y, "cursor grip bends forearms upward toward the hands")
	check(stage.rig.world_point("leftFoot").is_finite() and stage.rig.world_point("rightFoot").is_finite(), "cursor hang keeps dangling legs finite")
	for mode in ["carry", "cursor_hang"]:
		for yaw_angle in [0.0, 80.0, -80.0, 180.0]:
			advance_context(stage, state, "idle", Vector2.ZERO, 70)
			stage.yaw = yaw_angle
			advance_context(stage, state, mode, Vector2.ZERO, 30)
			var neutral_offset: float = screen_point(stage, "head").x - screen_point(stage, "hips").x if mode == "carry" else screen_point(stage, "hips").x - screen_point(stage, "leftHand").x
			advance_context(stage, state, mode, Vector2(-700.0, 0.0), 8)
			var left_offset: float = screen_point(stage, "head").x - screen_point(stage, "hips").x if mode == "carry" else screen_point(stage, "hips").x - screen_point(stage, "leftHand").x
			check(left_offset > neutral_offset + 4.0, mode + " torso lags right when the cursor moves left at yaw " + str(yaw_angle))
			advance_context(stage, state, mode, Vector2.ZERO, 3)
			var coast_offset: float = screen_point(stage, "head").x - screen_point(stage, "hips").x if mode == "carry" else screen_point(stage, "hips").x - screen_point(stage, "leftHand").x
			check(coast_offset > neutral_offset + 2.0, mode + " retains visible momentum just after the cursor stops at yaw " + str(yaw_angle))
			advance_context(stage, state, mode, Vector2(700.0, 0.0), 24)
			var right_offset: float = screen_point(stage, "head").x - screen_point(stage, "hips").x if mode == "carry" else screen_point(stage, "hips").x - screen_point(stage, "leftHand").x
			check(right_offset < neutral_offset - 4.0, mode + " torso lags left when the cursor moves right at yaw " + str(yaw_angle))
		for yaw_angle in [80.0, -80.0]:
			advance_context(stage, state, "idle", Vector2.ZERO, 70)
			stage.yaw = yaw_angle
			advance_context(stage, state, mode, Vector2.ZERO, 30)
			var facing: float = 1.0 if yaw_angle > 0.0 else -1.0
			for side in ["left", "right"]:
				var thigh: Vector2 = screen_point(stage, side + "UpperLeg")
				var knee: Vector2 = screen_point(stage, side + "LowerLeg")
				var ankle: Vector2 = screen_point(stage, side + "Foot")
				check(facing * (knee.x - thigh.x) > 5.0 and facing * (knee.x - ankle.x) > 12.0, mode + " knee bends forward and shin folds back at yaw " + str(yaw_angle) + " " + side)
	# Jump/fall/landing phases must be visually different poses, not one static overlay.
	stage.set_context_action("jump", Vector2(220, -420), 0.08, 0.55)
	for i in range(12):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	var jump_anticipation_head: Vector3 = stage.rig.world_point("head")
	var jump_anticipation_foot: Vector3 = stage.rig.world_point("leftFoot")
	check(stage.context_pose.phase_label() == "anticipation", "jump exposes anticipation phase")
	stage.set_context_action("jump", Vector2(360, -260), 0.52, 0.55)
	for i in range(12):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	var jump_flight_head: Vector3 = stage.rig.world_point("head")
	var jump_flight_foot: Vector3 = stage.rig.world_point("leftFoot")
	check(stage.context_pose.phase_label() == "flight", "jump exposes flight phase")
	check(jump_anticipation_head.distance_to(jump_flight_head) + jump_anticipation_foot.distance_to(jump_flight_foot) > stage.model_height * 0.025, "jump anticipation and flight are geometrically distinct")
	stage.set_context_action("fall", Vector2(120, 760), 0.78, 1.2)
	for i in range(12):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	check(stage.context_pose.phase_label() == "brace" and stage.rig.world_point("leftFoot").is_finite(), "hard fall reaches a finite brace phase")
	stage.set_context_action("land", Vector2(90, 0), 0.18, 1.2)
	for i in range(8):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	var land_compress_head: Vector3 = stage.rig.world_point("head")
	check(stage.context_pose.phase_label() == "compress", "landing begins with compression")
	stage.set_context_action("land", Vector2.ZERO, 0.88, 1.2)
	for i in range(12):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	check(stage.context_pose.phase_label() == "recover" and land_compress_head.distance_to(stage.rig.world_point("head")) > stage.model_height * 0.01, "landing visibly recovers from compression")
	var unchanged: bool = true
	for bone in range(stage.rig.skeleton.get_bone_count()):
		unchanged = unchanged and stage.rig.skeleton.get_bone_rest(bone).is_equal_approx(rest[bone])
	check(unchanged, "context actions never edit authored REST transforms")
	stage.set_context_action("idle")
	for i in range(60):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	check(stage.context_pose.weight < 0.01, "context pose fades back to normal idle")
	stage.start_portal_intro()
	var saw_intro: bool = false
	for i in range(18):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
		saw_intro = saw_intro or stage.cinematic_active()
	check(stage.door.leaf_pivot.rotation.y > 0.25, "arrival door opens toward camera, away from hidden Hoshi")
	check(stage.pivot.position.z < -stage.model_height * 0.40, "arrival keeps Hoshi behind the leaf sweep while opening")
	for i in range(82):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
		saw_intro = saw_intro or stage.cinematic_active()
	check(saw_intro and not stage.cinematic_active(), "magical door intro completes")
	check(not stage.door.frame_root.visible and absf(stage.pivot.position.z) < 0.001, "intro leaves ordinary avatar depth and hides door")
	stage.start_portal_outro()
	for i in range(18):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	check(stage.door.leaf_pivot.rotation.y < -0.25, "departure door opens inward, away from Hoshi in front")
	check(stage.pivot.position.z > stage.model_height * 0.08, "departure keeps Hoshi fully in front while opening")
	for i in range(82):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	check(stage.outro_complete(), "magical door outro reaches completion state")
	stage.queue_free()
	await process_frame
	_finish()

func _finish() -> void:
	print("HOSHI_CONTEXT_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
