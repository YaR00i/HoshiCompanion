extends SceneTree
## Numerical acceptance on the real VRM; no external window discovery.
var app
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func frames(count: int) -> void:
	for i in range(count):
		app._process(1.0 / 30.0)

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for i in range(20):
		await process_frame
		if app._ready_to_run: break
	check(app._ready_to_run, "real avatar loads for edge activities")
	if not app._ready_to_run:
		quit(1)
		return
	app.set_process(false)
	app.state.autonomy_enabled = false
	app.state.edge_activity = "calm"
	app.state.posture.kind = "edge"
	app.state.posture.request_sit(false)
	frames(120)
	var seat: Vector3 = app.stage.edge_pose.anchor_world()
	var hip: Vector3 = app.stage.rig.world_point("hips")
	var head: Vector3 = app.stage.rig.world_point("head")
	for activity in ["swing", "lean", "peek"]:
		app.state.edge_activity = activity
		frames(120)
		check(float(app.stage.edge_life.weights[activity]) > 0.95, activity + " weight reaches target")
		check(app.stage.edge_pose.anchor_world().distance_to(seat) < 0.001, activity + " keeps seat anchor")
		check(app.stage.rig.world_point("hips").distance_to(hip) < 0.001, activity + " keeps pelvis support")
		var finite: bool = true
		var skel: Skeleton3D = app.stage.rig.skeleton
		for bone in range(skel.get_bone_count()):
			finite = finite and skel.get_bone_global_pose(bone).origin.is_finite()
		check(finite, activity + " keeps all bones finite")
		if activity == "lean":
			check(app.stage.rig.world_point("head").z < head.z - 0.025, "lean tilts torso back")
			for side in ["left", "right"]:
				check(app.stage.rig.world_point(side + "Hand").z < hip.z - 0.03, side + " palm moves behind pelvis")
	app.state.edge_activity = "swing"
	frames(100)
	var z_min: float = 1000.0
	var z_max: float = -1000.0
	for i in range(100):
		frames(1)
		var z: float = app.stage.rig.world_point("leftFoot").z
		z_min = minf(z_min, z)
		z_max = maxf(z_max, z)
	check(z_max - z_min > 0.10, "dangling feet visibly swing")
	app.state.wave()
	frames(25)
	check(float(app.stage.edge_life.weights["swing"]) < 0.2, "greeting softens extra seated action")
	check(app.stage.edge_pose.anchor_world().distance_to(seat) < 0.001, "greeting preserves seat")
	frames(130)
	app.state.dozing = true
	frames(90)
	check(float(app.stage.edge_life.weights["swing"]) < 0.001, "dozing fades extra action")
	app.state.dozing = false
	app.state.edge_activity = "auto"
	app.state.autonomy_enabled = true
	app.state.activity = "normal"
	var seen: Dictionary = {}
	for i in range(12000):
		frames(1)
		for key in app.stage.edge_life.weights:
			if float(app.stage.edge_life.weights[key]) > 0.8: seen[key] = true
	check(seen.size() == 3, "autonomy uses all three activities")
	app.state.activity = "quiet"
	frames(120)
	var quiet: bool = true
	for weight in app.stage.edge_life.weights.values():
		quiet = quiet and float(weight) < 0.001
	check(quiet, "quiet mode calms autonomous actions")
	app.state.activity = "normal"
	app.state.edge_activity = "lean"
	frames(100)
	app.stage.edge_suspended = true
	var frame: Dictionary = app.stage.edge_life.tick(0.1, app.state, true)
	var before: float = float(frame["lean"])
	for i in range(40): frame = app.stage.edge_life.tick(0.1, app.state, true)
	check(float(frame["lean"]) < before * 0.01, "pickup/menu suspension fades posture extras")
	app.stage.edge_suspended = false
	app.state.autonomy_enabled = false
	app.state.posture.request_stand()
	frames(180)
	var off: bool = true
	for weight in app.stage.edge_life.weights.values():
		off = off and float(weight) < 0.001
	check(off, "standing has no residual edge activity")
	app.queue_free()
	await process_frame
	print("HOSHI_EDGE_LIFE_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
