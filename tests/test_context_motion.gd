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

func _run() -> void:
	var air := Air.new()
	air.begin_jump(Vector2(100, 500), Vector2(500, 300), 360.0)
	var linear_mid_y: float = 400.0
	for i in range(10):
		air.tick(0.03)
	check(air.position.y < linear_mid_y, "jump route rises above the straight line")
	for i in range(80):
		air.tick(0.03)
	check(air.mode == "idle" and air.position.distance_to(Vector2(500, 300)) < 0.01, "jump lands exactly at target")
	air.begin_fall(Vector2(300, 120), Vector2(360, 620), 360.0)
	var previous_y: float = air.position.y
	var monotonic: bool = true
	for i in range(100):
		air.tick(0.02)
		monotonic = monotonic and air.position.y >= previous_y - 0.01
		previous_y = air.position.y
	check(monotonic and air.mode == "idle" and air.position.distance_to(Vector2(360, 620)) < 0.01, "fall accelerates downward and lands exactly")
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
	var rest: Array[Transform3D] = []
	for bone in range(stage.rig.skeleton.get_bone_count()):
		rest.append(stage.rig.skeleton.get_bone_rest(bone))
	for mode in ["carry", "jump", "fall", "land"]:
		stage.set_context_action(mode, Vector2(420, 260))
		for i in range(50):
			state.tick(1.0 / 30.0)
			stage.animate(1.0 / 30.0, state, Vector2.ZERO)
		var finite: bool = true
		for bone in range(stage.rig.skeleton.get_bone_count()):
			finite = finite and stage.rig.skeleton.get_bone_global_pose(bone).origin.is_finite()
		check(finite, mode + " context pose keeps every bone finite")
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
