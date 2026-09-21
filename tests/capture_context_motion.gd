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
	app.stage.set_context_action("carry", Vector2(420.0, 250.0))
	advance(40)
	await capture("02_carry")
	app.stage.set_context_action("jump", Vector2(250.0, -320.0))
	advance(30)
	await capture("03_jump")
	app.stage.set_context_action("fall", Vector2(80.0, 600.0))
	advance(30)
	await capture("04_fall")
	app.stage.set_context_action("land")
	advance(22)
	await capture("05_land")
	app.stage.set_context_action("idle")
	advance(55)

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
