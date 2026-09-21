extends SceneTree
## Bounded, app-only renders. Use -- --test-mode to avoid saved-setting changes.
var app
var capture_failed: bool = false
var output: String = "res://.workspace/screenshots/posture_03"

func _initialize() -> void:
	_run.call_deferred()

func _advance(frames: int) -> void:
	for index in range(frames):
		app._process(1.0 / 30.0)

func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = output.path_join(label + ".png")
	var result: Error = image.save_png(path)
	print("POSTURE_CAPTURE ", path, " error=", result)
	if result != OK:
		capture_failed = true
		push_error("Failed to save posture render: " + path)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for index in range(10):
		await process_frame
		if app._ready_to_run:
			break
	if not app._ready_to_run:
		push_error("Avatar did not become ready")
		quit(1)
		return
	app.set_process(false)
	app.state.autonomy_enabled = false
	app.ui.bubbles_enabled = false
	_advance(30)
	await _capture("01_standing")
	app._on_action(32)
	_advance(36)
	await _capture("02_sitting_down")
	_advance(70)
	await _capture("03_seated_front")
	app.stage.yaw = 65.0
	_advance(1)
	await _capture("04_seated_side")
	app.stage.yaw = 0.0
	app._on_action(11)
	_advance(20)
	await _capture("05_seated_pet")
	app._on_action(10)
	_advance(25)
	await _capture("06_seated_wave")
	_advance(130)
	app._on_action(12)
	_advance(100)
	await _capture("07_seated_doze")
	app._on_action(30)
	_advance(34)
	await _capture("08_standing_up")
	_advance(100)
	await _capture("09_walk_after_standing")
	_advance(240)
	await _capture("10_back_to_idle")
	if DisplayServer.get_name() == "Windows":
		app._switch_mode(false)
		app.host.home()
		await process_frame
		await process_frame
		app._on_action(32)
		_advance(120)
		await _capture("11_desktop_seated")
		app.stage.yaw = 65.0
		_advance(1)
		await _capture("12_desktop_side")
		var inside: bool = true
		for semantic in ["head", "hips", "leftHand", "rightHand", "leftFoot", "rightFoot"]:
			var point: Vector2 = app.stage.camera.unproject_position(app.stage.rig.world_point(semantic))
			inside = inside and app.host.mask_contains(point)
		print("POSTURE_NATIVE_MASK_ANCHORS ", inside)
		if not inside:
			capture_failed = true
			push_error("Seated anchors outside native mask")
	print("POSTURE_CAPTURE_DONE")
	app.queue_free()
	await process_frame
	quit(1 if capture_failed else 0)
