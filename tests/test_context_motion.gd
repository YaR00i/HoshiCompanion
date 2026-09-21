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
	var state := State.new()
	state.autonomy_enabled = false
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
	for i in range(100):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
		saw_intro = saw_intro or stage.cinematic_active()
	check(saw_intro and not stage.cinematic_active(), "magical door intro completes")
	check(not stage.door.frame_root.visible and absf(stage.pivot.position.z) < 0.001, "intro leaves ordinary avatar depth and hides door")
	stage.start_portal_outro()
	for i in range(100):
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
	check(stage.outro_complete(), "magical door outro reaches completion state")
	stage.queue_free()
	await process_frame
	_finish()

func _finish() -> void:
	print("HOSHI_CONTEXT_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
