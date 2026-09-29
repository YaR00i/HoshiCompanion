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
	for activity in ["swing", "lean", "peek", "balance", "sway", "hum", "nod"]:
		app.state.edge_activity = activity
		frames(120)
		check(float(app.stage.edge_life.weights[activity]) > 0.95, activity + " weight reaches target")
		check(app.stage.edge_pose.anchor_world().distance_to(seat) < 0.001, activity + " keeps seat anchor")
		check(app.stage.rig.world_point("hips").distance_to(hip) < 0.001, activity + " keeps pelvis support")
		var finite: bool = true
		var skel: Skeleton3D = app.stage.rig.skeleton
		for bone in range(skel.get_bone_count()):
			var bone_pose: Transform3D = skel.get_bone_global_pose(bone)
			finite = finite and bone_pose.origin.is_finite() and bone_pose.basis.is_finite()
		check(finite, activity + " keeps all bones finite")
		if activity == "lean":
			check(app.stage.rig.world_point("head").z < head.z - 0.025, "lean tilts torso back")
			for side in ["left", "right"]:
				check(app.stage.rig.world_point(side + "Hand").z < hip.z - 0.03, side + " palm moves behind pelvis")
	app.state.edge_activity = "sway"
	frames(100)
	var x_min: float = 1000.0
	var x_max: float = -1000.0
	var sway_foot_min: float = 1000.0
	var sway_foot_max: float = -1000.0
	for i in range(180):
		frames(1)
		var x: float = app.stage.rig.world_point("head").x
		x_min = minf(x_min, x)
		x_max = maxf(x_max, x)
		var sway_foot_z: float = app.stage.rig.world_point("leftFoot").z
		sway_foot_min = minf(sway_foot_min, sway_foot_z)
		sway_foot_max = maxf(sway_foot_max, sway_foot_z)
	check(x_max - x_min > 0.015, "sway produces real side-to-side upper-body travel")
	var sway_foot_range: float = sway_foot_max - sway_foot_min
	print("SWAY_LEG_RANGE meters=", sway_foot_range)
	check(sway_foot_range > 0.065, "sway includes a clearly visible relaxed dangling-leg counter-swing")
	app.state.edge_activity = "swing"
	frames(100)
	var z_min: float = 1000.0
	var z_max: float = -1000.0
	for i in range(100):
		frames(1)
		var z: float = app.stage.rig.world_point("leftFoot").z
		z_min = minf(z_min, z)
		z_max = maxf(z_max, z)
	var full_swing_range: float = z_max - z_min
	print("FULL_SWING_LEG_RANGE meters=", full_swing_range)
	check(full_swing_range > 0.10, "dangling feet visibly swing")
	check(full_swing_range > sway_foot_range * 1.8, "sway leg motion stays restrained below the dedicated swing gesture")
	app.state.edge_activity = "nod"
	frames(100)
	app.state.wave()
	frames(25)
	check(float(app.stage.edge_life.weights["nod"]) < 0.2, "greeting softens rhythmic seated action")
	check(app.stage.edge_pose.anchor_world().distance_to(seat) < 0.001, "greeting preserves seat")
	frames(130)
	app.state.edge_activity = "hum"
	frames(100)
	app.state.pet()
	frames(25)
	check(float(app.stage.edge_life.weights["hum"]) < 0.2, "petting softens rhythmic seated action")
	frames(100)
	app.state.edge_activity = "sway"
	frames(100)
	app.state.dozing = true
	frames(90)
	check(float(app.stage.edge_life.weights["sway"]) < 0.001, "dozing fades rhythmic seated action")
	app.state.dozing = false
	app.state.edge_activity = "auto"
	app.state.autonomy_enabled = true
	app.state.activity = "normal"
	app.stage.edge_life._left = 0.0
	app.stage.edge_life._wait = 0.0
	app.stage.edge_life.seed_random(707)
	var seen: Dictionary = {}
	for i in range(18000):
		frames(1)
		for key in app.stage.edge_life.weights:
			if float(app.stage.edge_life.weights[key]) > 0.8: seen[key] = true
	check(seen.size() == 5 and not seen.has("hum") and not seen.has("nod"), "normal autonomy uses accepted seated activities and keeps hum/nod manual")
	app.state.activity = "quiet"
	app.stage.edge_life._left = 0.0
	app.stage.edge_life._wait = 0.0
	app.stage.edge_life.seed_random(909)
	# A gesture left over from the normal mode may still be fading out; count quiet choices only.
	frames(45)
	var quiet_seen: Dictionary = {}
	var quiet_only_soft: bool = true
	for i in range(12000):
		frames(1)
		for key in app.stage.edge_life.weights:
			if float(app.stage.edge_life.weights[key]) > 0.8:
				quiet_seen[key] = true
				quiet_only_soft = quiet_only_soft and key == "sway"
	check(quiet_only_soft and quiet_seen.size() == 1 and quiet_seen.has("sway"), "quiet autonomy stays alive using only accepted soft sway")
	app.state.activity = "normal"
	app.state.edge_activity = "auto"
	app.state.autonomy_enabled = false
	app.stage.edge_life.autonomous_enabled = false
	for gesture in ["sway", "hum", "nod"]:
		check(app.stage.edge_life.request_gesture(gesture), "planner accepts forced " + gesture + " gesture")
		var forced_seen: bool = false
		for i in range(240):
			frames(1)
			forced_seen = forced_seen or float(app.stage.edge_life.weights[gesture]) > 0.7
		check(forced_seen and not app.stage.edge_life.forced_active(), "forced " + gesture + " plays and releases cleanly")
	app.stage.edge_life.autonomous_enabled = true
	app.state.edge_activity = "auto"
	check(app.stage.edge_life.request_gesture("sketch"), "cozy corner starts one notebook scene")
	for i in range(120): app.stage.edge_life.tick(1.0 / 30.0, app.state, false, true)
	check(float(app.stage.edge_life.weights["sketch"]) > 0.9 and app.stage.edge_life.sketch_progress > 0.35, "cozy scene reaches drawing phase")
	for i in range(100): app.stage.edge_life.tick(1.0 / 30.0, app.state, false, false)
	check(float(app.stage.edge_life.weights["sketch"]) < 0.001 and not app.stage.edge_life.forced_active(), "leaving cozy corner cancels notebook")
	app.state.edge_activity = "sway"
	check(app.stage.edge_life.request_gesture("sketch"), "selected sway lets a notebook scene start")
	for i in range(120): app.stage.edge_life.tick(1.0 / 30.0, app.state, false, true)
	check(float(app.stage.edge_life.weights["sketch"]) > 0.9, "notebook temporarily takes priority over selected sway")
	# Метка «Ждёт»: показала рисунок и ждёт клика — время сценки стоит, пока не ответишь.
	var life = app.stage.edge_life
	var wait_events: Array = []
	life.wait_started.connect(func(g): wait_events.append(["start", g]))
	life.wait_finished.connect(func(g, answered): wait_events.append(["finish", g, answered]))
	var sketch_wait: float = life.wait_time("sketch")
	check(sketch_wait > 6.0 and sketch_wait < 9.5 and life.wait_time("sway") < 0.0, "the notebook clip has a «Ждёт» marker; loops never wait")
	for i in range(300):
		if life.waiting == "sketch": break
		life.tick(1.0 / 30.0, app.state, false, true)
	var held_progress: float = life.sketch_progress
	check(life.prop_scene_active(), "the notebook scene tells clicks not to start touch reactions")
	for i in range(90): life.tick(1.0 / 30.0, app.state, false, true)
	check(life.waiting == "sketch" and absf(held_progress - sketch_wait / 10.0) < 0.01 and absf(life.sketch_progress - held_progress) < 0.0001 and life.forced_active(), "she holds the drawing up and waits instead of finishing")
	check(life.label() != "" and wait_events.size() == 1 and wait_events[0] == ["start", "sketch"], "waiting is announced once")
	check(life.answer_wait() and life.waiting.is_empty() and life.wait_joy > 0.9 and wait_events.back() == ["finish", "sketch", true], "a click answers: she continues and is happy")
	check(not life.answer_wait(), "a second click is not another answer")
	for i in range(240): life.tick(1.0 / 30.0, app.state, false, true)
	check(float(app.stage.edge_life.weights["sway"]) > 0.9 and not app.stage.edge_life.forced_active(), "sway resumes after notebook finishes")
	# Не дождалась: через WAIT_LIMIT сама убирает рисунок.
	check(life.request_gesture("sketch"), "notebook starts again")
	for i in range(300):
		if life.waiting == "sketch": break
		life.tick(1.0 / 30.0, app.state, false, true)
	for i in range(int((life.WAIT_LIMIT + 1.0) * 10.0)): life.tick(0.1, app.state, false, true)
	check(life.waiting.is_empty() and wait_events.back() == ["finish", "sketch", false] and life.sketch_progress > 0.9, "without a click she stops waiting and puts the drawing away")
	for i in range(240): life.tick(1.0 / 30.0, app.state, false, true)
	# Ритм полочки: рисунок/звёздочка — редко, основное — мелочи; музыка и ночь.
	var fresh = load("res://scripts/edge_life.gd").new()
	check(not fresh.big_ready("sketch") and not fresh._choices("quiet", true).has("sketch"), "right after start there is no notebook scene yet")
	fresh._clock = fresh.BIG_COOLDOWN
	check(fresh.big_ready("sketch") and fresh._choices("quiet", true).has("fold"), "after the pause a big scene may come again")
	var calm_list: Array[String] = fresh._choices("quiet", true)
	check(calm_list.has("hair") and calm_list.has("stretch") and not calm_list.has("doze") and not calm_list.has("nod"), "small things (hair, stretch) are the everyday choices")
	fresh.music = true
	check(fresh._choices("", true).count("nod") >= 2 and fresh._choices("", false).has("hum"), "music makes her nod and hum")
	fresh.music = false
	fresh.sleepy = true
	check(fresh._choices("quiet", false).has("doze"), "late at night she may doze off")
	var micros: Array = []
	fresh.micro_requested.connect(func(k): micros.append(k))
	fresh.seed_random(3)
	app.state.edge_activity = "auto"
	var autonomy_before: bool = app.state.autonomy_enabled
	app.state.autonomy_enabled = true
	for i in range(3000): fresh.tick(0.1, app.state, false, true)
	app.state.autonomy_enabled = autonomy_before
	check(micros.size() >= 3, "small overlays are requested while she sits (%d)" % micros.size())
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
