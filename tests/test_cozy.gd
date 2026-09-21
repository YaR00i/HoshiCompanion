extends "res://tests/test_shelf.gd"
## Native app-owned cozy-window acceptance. No external application capture.

func _run() -> void:
	output = "res://.workspace/screenshots/cozy_06"
	if DisplayServer.get_name() != "Windows":
		print("HOSHI_COZY_RESULT checks=0 failures=0 native_windows=false")
		quit(0)
		return
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for i in range(20):
		await process_frame
		if app._ready_to_run: break
	_check(app._ready_to_run, "real avatar loads for cozy corner")
	if not app._ready_to_run:
		quit(1)
		return
	app.set_process(false)
	app.state.autonomy_enabled = false
	app.ui.bubbles_enabled = false
	app.state.edge_activity = "calm"
	var accepted: bool = app.playground.show_demo(true)
	await process_frame
	await process_frame
	_advance(130)
	_check(accepted and app.playground.phase == "attached", "cozy corner docks avatar")
	var cozy = app.playground.shelf
	_check(app.playground.cozy_mode and is_instance_valid(cozy), "cozy support owns a distinct window")
	_check(cozy.borderless and cozy.transparent_bg and cozy.size == Vector2i(460, 170), "cozy window uses compact transparent frame")
	_check(app.playground.last_support_error < 1.1, "cozy seat contact stays within one pixel")
	await _capture("01_calm")
	app._on_action(302)
	_advance(120)
	_check(app.state.edge_activity == "swing" and float(app.stage.edge_life.weights["swing"]) > 0.9, "cozy button selects dangling legs")
	await _capture("02_swing")
	app._on_action(303)
	_advance(120)
	_check(app.state.edge_activity == "lean" and float(app.stage.edge_life.weights["lean"]) > 0.9, "cozy button selects lean-back pose")
	await _capture("03_lean")
	var before: Vector2i = root.position
	cozy.position += Vector2i(60, 10)
	await process_frame
	_advance(3)
	_check((Vector2(root.position - before) - Vector2(60, 10)).length() < 1.5, "avatar follows cozy corner movement")
	app.playground.close_shelf()
	await process_frame
	_advance(190)
	_check(not app.playground.active() and app.host.is_grounded(), "closing cozy corner returns avatar safely")
	app._switch_mode(true)
	app.queue_free()
	await process_frame
	print("HOSHI_COZY_RESULT checks=", checks, " failures=", failures, " native_windows=true")
	quit(0 if failures == 0 else 1)
