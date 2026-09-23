extends SceneTree
## App-only visual acceptance for Hoshi 0.7 context motion.
## Captures only Hoshi's own Godot viewport, never desktop/application pixels.
var app
var checks: int = 0
var failures: int = 0
var output: String = "res://.workspace/screenshots/context_07"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func advance(frames: int) -> void:
	for i in range(frames):
		app._process(1.0 / 30.0)

func advance_pose(frames: int) -> void:
	for i in range(frames):
		app.state.tick(1.0 / 30.0, false)
		app.stage.animate(1.0 / 30.0, app.state, Vector2.ZERO)

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = output.path_join(label + ".png")
	var result: Error = image.save_png(path)
	check(result == OK, "save app-only context frame " + label)
	print("HOSHI_CONTEXT_CAPTURE ", ProjectSettings.globalize_path(path))

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for i in range(20):
		await process_frame
		if app._ready_to_run:
			break
	check(app._ready_to_run, "real Hoshi avatar loads for context captures")
	if not app._ready_to_run:
		quit(1)
		return
	app.set_process(false)
	app.state.autonomy_enabled = false
	app.state.motion_enabled = true
	app.ui.bubbles_enabled = false
	advance(25)
	await capture("01_idle")
	app.state.recognize()
	advance(15)
	await capture("01a_recognition")
	advance(60)
	check(app.stage.refresh_interaction_alpha(), "cache app-owned avatar alpha for precise desktop hit testing")
	var torso_point: Vector2 = app.stage.camera.unproject_position(app.stage.rig.world_point("hips"))
	check(app.stage.visible_avatar_hit(torso_point), "visible torso pixel is interactive")
	check(not app.stage.visible_avatar_hit(Vector2(2.0, 2.0)), "transparent viewport corner is non-interactive")
	# Capture the two distinct standing gestures separately for visual review.
	app.state.autonomy_enabled = true
	app.state.rest_enabled = false
	app.stage.idle_life.kind = "weight_left"
	app.stage.idle_life._left = 8.0
	app.stage.idle_life._wait = 20.0
	for key in app.stage.idle_life.weights:
		app.stage.idle_life.weights[key] = 1.0 if key == "weight_left" else 0.0
	advance(8)
	await capture("01b_weight_shift")
	app.stage.idle_life.kind = "peek_left"
	app.stage.idle_life._left = 8.0
	for key in app.stage.idle_life.weights:
		app.stage.idle_life.weights[key] = 1.0 if key == "peek_left" else 0.0
	advance(8)
	await capture("01c_curiosity_peek")
	app.state.autonomy_enabled = false
	advance(25)
	app.stage.set_context_action("carry", Vector2(420.0, 250.0))
	advance_pose(40)
	await capture("02_carry")
	app.stage.set_context_action("jump", Vector2(160.0, -240.0), 0.08, 0.55)
	advance_pose(10)
	await capture("03a_jump_anticipation")
	app.stage.set_context_action("jump", Vector2(360.0, -300.0), 0.52, 0.55)
	advance_pose(12)
	await capture("03b_jump_flight")
	app.stage.set_context_action("fall", Vector2(80.0, 650.0), 0.22, 1.15)
	advance_pose(10)
	await capture("04a_fall_react")
	app.stage.set_context_action("fall", Vector2(130.0, 820.0), 0.78, 1.15)
	advance_pose(12)
	await capture("04b_fall_brace")
	app.stage.set_context_action("land", Vector2(90.0, 0.0), 0.18, 1.15)
	advance_pose(8)
	await capture("05a_land_compress")
	app.stage.set_context_action("land", Vector2.ZERO, 0.88, 1.15)
	advance_pose(12)
	await capture("05b_land_recover")
	app.stage.set_context_action("idle")
	advance_pose(55)
	app.state.react_to_release("soft")
	app.stage.set_context_action("fall", Vector2(0.0, 320.0), 0.22, 0.51)
	advance_pose(10)
	await capture("05c_soft_release")
	app.stage.set_context_action("idle")
	app.state.cancel_release_reaction()
	advance_pose(55)
	app.state.react_to_release("rough")
	app.stage.set_context_action("fall", Vector2(0.0, 320.0), 0.22, 0.83)
	advance_pose(10)
	await capture("05d_rough_release")
	app.stage.set_context_action("idle")
	app.state.cancel_release_reaction()
	advance_pose(55)
	app.stage.set_context_action("side_left")
	advance_pose(35)
	await capture("05b_side_left")
	app.stage.set_context_action("side_right")
	advance_pose(35)
	await capture("05c_side_right")
	app.stage.set_context_action("idle")
	advance_pose(30)

	app.stage.start_portal_intro()
	advance(10)
	await capture("06_door_appears")
	advance(18)
	await capture("07_door_open")
	advance(20)
	await capture("08_emerging")
	advance(45)
	check(not app.stage.cinematic_active(), "portal intro completes after capture sequence")
	app.stage.start_portal_outro()
	advance(20)
	await capture("09_outro_open")
	advance(22)
	await capture("10_entering_door")
	advance(45)
	check(app.stage.outro_complete(), "portal outro completes after capture sequence")
	app.queue_free()
	await process_frame
	print("HOSHI_CONTEXT_CAPTURE_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
