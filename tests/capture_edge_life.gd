extends "res://tests/test_shelf.gd"
## Real render in the accepted app-owned shelf, no desktop screenshots.

func _run() -> void:
	output = "res://.workspace/screenshots/edge_life"
	if DisplayServer.get_name() != "Windows":
		quit(1)
		return
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for i in range(20):
		await process_frame
		if app._ready_to_run: break
	if not app._ready_to_run:
		quit(1)
		return
	app.set_process(false)
	app.state.autonomy_enabled = false
	app.ui.bubbles_enabled = false
	app.state.edge_activity = "calm"
	_check(await _attach(), "native shelf ready for new activities")
	for activity in ["calm", "swing", "lean", "peek"]:
		app.state.edge_activity = activity
		app.stage.yaw = 0.0
		_advance(120)
		await _capture(activity + "_front")
		app.stage.yaw = 65.0
		_advance(1)
		await _capture(activity + "_side")
	app.stage.yaw = 0.0
	app._on_action(10)
	_advance(28)
	await _capture("wave")
	_advance(120)
	app._on_action(12)
	_advance(120)
	await _capture("doze")
	app._switch_mode(true)
	app.queue_free()
	await process_frame
	print("HOSHI_EDGE_CAPTURE_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
