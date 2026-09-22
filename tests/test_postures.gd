extends SceneTree
## Exercises the REAL coordinator, model and UI, not a parallel fake state machine.
var app
var checks: int = 0
var failures: int = 0
var metrics: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _frames(count: int, fps: int = 30) -> void:
	for index in range(count):
		app._process(1.0 / float(fps))

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for index in range(10):
		await process_frame
		if app._ready_to_run:
			break
	_check(app._ready_to_run, "coordinator loads real Hoshi")
	if not app._ready_to_run:
		quit(1)
		return
	app.set_process(false)
	app.state.autonomy_enabled = false
	app.ui.bubbles_enabled = false
	_frames(10)
	_check(app.stage.posture_driver.available, "posture capability mapped")
	var skel: Skeleton3D = app.stage.rig.skeleton
	var rests: Array[Transform3D] = []
	for bone in range(skel.get_bone_count()):
		rests.append(skel.get_bone_rest(bone))
	var max_foot_drift: float = 0.0
	var max_joint_step: float = 0.0
	for fps in [30, 60]:
		app._on_action(33)
		_frames(fps * 4, fps)
		var before: Vector3 = app.stage.rig.world_point("hips")
		var feet: Array[Vector3] = [app.stage.rig.world_point("leftFoot"), app.stage.rig.world_point("rightFoot")]
		var previous: Vector3 = before
		app._on_action(32)
		var finite: bool = true
		for index in range(fps * 4):
			_frames(1, fps)
			var hip: Vector3 = app.stage.rig.world_point("hips")
			finite = finite and hip.is_finite()
			max_joint_step = maxf(max_joint_step, hip.distance_to(previous))
			previous = hip
			for side in range(2):
				var foot: Vector3 = app.stage.rig.world_point("leftFoot" if side == 0 else "rightFoot")
				max_foot_drift = maxf(max_foot_drift, foot.distance_to(feet[side]))
		_check(finite and app.state.posture.mode == "seated", "finite completed sit at %d FPS" % fps)
		_check(app.stage.rig.world_point("hips").y < before.y - app.stage.model_height * 0.35, "hips actually lower toward floor")
		_check(not app.walker.active(), "sitting does not start a route")
	_check(max_foot_drift < 0.003, "planted ankles stay within 3 mm during seating")
	_check(max_joint_step < 0.06, "no pelvis teleport during pose transitions")
	_check_seated_arms("rest")
	var seated_hip: Vector3 = app.stage.rig.world_point("hips")
	app._on_action(11)
	_frames(25)
	_check(app.state.posture.mode == "seated", "pet does not stand up seated avatar")
	_check(app.state.pet_weight > 0.8, "pet reaction still active while seated")
	_check(app.stage.rig.world_point("hips").distance_to(seated_hip) < 0.002, "pet keeps seated support")
	_frames(100)
	var hand: Vector3 = app.stage.rig.world_point("rightHand")
	app._on_action(10)
	_frames(28)
	_check(app.state.posture.mode == "seated", "wave keeps seated posture")
	_check(app.stage.rig.world_point("rightHand").y > hand.y + 0.12, "seated wave raises actual wrist")
	_frames(120)
	_check_seated_arms("after wave")
	app._on_action(12)
	_frames(120)
	_check(app.state.dozing and app.state.posture.mode == "seated", "dozes seated, not standing")
	_check(float(app.state.expression_weights()["blink"]) > 0.7, "dozing closes eyes")
	app._on_action(11)
	_frames(20)
	_check(not app.state.dozing and app.state.posture.mode == "seated", "pet wakes without standing")
	app._on_action(30)
	_check(app._pending_action == "walk" and not app.walker.active(), "seated walk waits for standing")
	var overlap: bool = false
	var started: bool = false
	for index in range(360):
		_frames(1)
		started = started or app.walker.active()
		overlap = overlap or (app.walker.active() and app.state.posture.amount > 0.0001)
	_check(started and not overlap, "walking and seated lower-body ownership never overlap")
	_check(not app.walker.active() and app.state.posture.mode == "standing", "walk returns to standing idle")
	app._on_action(32)
	_frames(25)
	var middle: Vector3 = app.stage.rig.world_point("hips")
	app._on_action(33)
	_frames(1)
	_check(middle.distance_to(app.stage.rig.world_point("hips")) < 0.06, "sit-to-stand reversal stays continuous")
	_frames(150)
	_check(app.state.posture.mode == "standing", "reversal finishes standing")
	app._on_action(32)
	_frames(25)
	app._on_action(31)
	_frames(150)
	_check(app.state.posture.mode == "standing" and app._pending_action.is_empty(), "Stop cancels unfinished sit safely")
	app._on_action(32)
	_frames(120)
	app._on_action(30)
	app._hard_stop()
	_frames(180)
	_check(not app.walker.active() and app._pending_action.is_empty(), "pickup cancels queued route, never resumes it")
	app._on_action(33)
	_frames(120)
	app._on_action(141)
	app._on_action(30)
	_frames(35)
	app._on_action(12)
	overlap = false
	for index in range(240):
		_frames(1)
		overlap = overlap or (app.walker.active() and app.state.posture.amount > 0.0001)
	_check(not overlap and app.state.dozing, "walk -> settle -> sit -> doze is ordered")
	_check(app.state.posture.mode == "seated", "sleep request ends seated")
	app._on_action(12)
	_check(not app.state.dozing and app.state.posture.mode == "seated", "wake button preserves seat")
	var unchanged: bool = true
	for bone in range(skel.get_bone_count()):
		unchanged = unchanged and skel.get_bone_rest(bone).is_equal_approx(rests[bone])
	_check(unchanged, "all authored REST matrices unchanged")
	_check(app.ui.menu.get_item_index(32) >= 0 and app.ui.menu.get_item_index(33) >= 0, "sit/stand available in desktop menu")
	_check(app.ui.panel.get_combined_minimum_size().y <= 580.0, "expanded controls still fit the preview")
	_check_timers()
	_check_autonomous_sequence()
	metrics = {"max_foot_drift_m": max_foot_drift, "max_pelvis_frame_motion_m": max_joint_step}
	var report: Dictionary = {"checks": checks, "failures": failures, "metrics": metrics, "engine": Engine.get_version_info()}
	var file: FileAccess = FileAccess.open("user://posture_checks.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("HOSHI_POSTURE_METRICS ", JSON.stringify(metrics))
	print("HOSHI_POSTURE_RESULT checks=", checks, " failures=", failures)
	app.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _check_timers() -> void:
	var controller = load("res://scripts/posture_controller.gd").new()
	controller.request_sit(false)
	for index in range(4000):
		controller.tick(1.0 / 30.0)
	_check(controller.mode == "seated", "manual rest never times out")
	controller.request_sit(true, 10.0)
	for index in range(600):
		controller.tick(1.0 / 30.0, false)
	_check(controller.mode == "seated" and controller.rest_left > 9.9, "blocked automatic rest timer is paused")
	for index in range(450):
		controller.tick(1.0 / 30.0, true)
	_check(controller.mode == "standing", "automatic rest eventually stands up")
	controller.request_sit(true, 10.0)
	for index in range(100):
		controller.tick(1.0 / 30.0)
	controller.keep_rest()
	for index in range(600):
		controller.tick(1.0 / 30.0)
	_check(controller.mode == "seated", "user interaction claims automatic seat")

func _check_autonomous_sequence() -> void:
	app._on_action(33)
	_frames(120)
	app._on_action(141)
	app.state.autonomy_enabled = true
	app.state.rest_enabled = true
	app.director.rest_after_walk = false
	app._start_walk(true)
	_frames(360)
	_check(app.state.posture.mode == "standing", "automatic walk can end standing instead of forcing the old walk-then-sit loop")
	app.director.rest_after_walk = true
	app._start_walk(true)
	_frames(360)
	_check(app.state.posture.mode == "seated" and app.state.posture.automatic, "director can still choose a timed rest after a walk")
	app._on_action(11)
	_check(not app.state.posture.automatic, "pet claims automatic rest in the real coordinator")
	app._on_action(33)
	_frames(120)
	app._on_action(141)
	app.state.rest_enabled = false
	app.director.rest_after_walk = true
	app._start_walk(true)
	_frames(360)
	_check(app.state.posture.mode == "standing", "disabled automatic rest does not queue a seat")
	app.state.autonomy_enabled = false
	var director = load("res://scripts/behavior_director.gd").new()
	director.rest_enabled = false
	director.walk_enabled = false
	director._rest_wait = 0.0
	var no_seat: bool = true
	for index in range(3000):
		no_seat = no_seat and director.tick(1.0 / 30.0, {"can_rest": true}) != "sit"
	_check(no_seat, "director respects the independent rest switch")

func _check_seated_arms(label: String) -> void:
	# Geometric regression for the reported sideways elbows, on the real skeleton.
	var driver = app.stage.posture_driver
	var skel: Skeleton3D = driver.skeleton
	var height: float = app.stage.model_height
	for side in range(2):
		var arm: Dictionary = driver.arms[side]
		var shoulder: Vector3 = skel.get_bone_global_pose(int(arm["upper"])).origin
		var elbow: Vector3 = skel.get_bone_global_pose(int(arm["lower"])).origin
		var wrist: Vector3 = skel.get_bone_global_pose(int(arm["end"])).origin
		var knee: Vector3 = skel.get_bone_global_pose(int(app.stage.gait.legs[side]["lower"])).origin
		var sign_x: float = 1.0 if side == 0 else -1.0
		var lateral: float = (elbow.x - shoulder.x) * sign_x
		var expected: Vector3 = knee + Vector3(sign_x * height * 0.006, height * 0.026, -height * 0.012)
		if app.state.motion_enabled:
			expected.y += sin(app.state.time * 1.65) * height * 0.0008 * app.state.posture.amount
		_check(elbow.is_finite() and elbow.y < wrist.y - height * 0.07,
			"%s arm %d: resting elbow stays below the hand" % [label, side])
		_check(lateral > height * 0.015 and lateral < height * 0.065,
			"%s arm %d: elbow is tucked with a small outward clearance" % [label, side])
		_check(wrist.distance_to(expected) < 0.003,
			"%s arm %d: wrist still rests on its knee target within 3 mm" % [label, side])
