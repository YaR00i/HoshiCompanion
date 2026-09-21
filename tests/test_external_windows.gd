extends SceneTree
## Exercises the bridge against our OWN isolated window in another process.
## Never selects, moves, reads contents or captures any pre-existing app.
var app
var fixture: Dictionary = {}
var fixture_io: FileAccess
var fixture_buffer: String = ""
var handle: int = 0
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

func until(predicate: Callable, limit: float = 6.0) -> bool:
	var end: int = Time.get_ticks_msec() + int(limit * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < end:
		await create_timer(0.05).timeout
	return bool(predicate.call())

func command(message: Dictionary) -> void:
	fixture_io.store_line(JSON.stringify(message))

func _run() -> void:
	if DisplayServer.get_name() != "Windows":
		print("HOSHI_EXTERNAL_SKIPPED native Windows required")
		quit(0)
		return
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	if not await until(func(): return app._ready_to_run):
		check(false, "app startup")
		await finish()
		return
	app.state.autonomy_enabled = false
	app.ui.bubbles_enabled = false
	check(app.playground.external.process_id == -1, "no geometry process on normal startup")
	check(app.ui.menu.get_item_index(42) >= 0, "manual window selection is exposed")
	await check_selection_controls()
	var area: Rect2i = app.host.usable_area(DisplayServer.get_primary_screen())
	var x: int = area.position.x + int(area.size.x * 0.25)
	var y: int = area.position.y + int(area.size.y * 0.48)
	var python_path: String = FileAccess.get_file_as_string("res://python_path.txt").strip_edges()
	fixture = OS.execute_with_pipe(python_path, PackedStringArray(["-u", ProjectSettings.globalize_path("res://tests/external_window_fixture.py"), str(x), str(y), str(area.position.x), str(area.position.y)]), false)
	check(not fixture.is_empty(), "create separate-process test fixture")
	if fixture.is_empty():
		await finish()
		return
	fixture_io = fixture["stdio"]
	var ready: bool = await until(_read_handle)
	check(ready, "receive fixture HWND without enumerating applications")
	if not ready:
		await finish()
		return
	check(app.playground.select_window(handle), "explicit test-window selection starts")
	var docked: bool = await until(func(): return app.playground.phase == "attached" and app.state.posture.mode == "seated")
	check(docked, "native external window docks and seats")
	if not docked:
		print("BRIDGE_STATE ", app.playground.external.status, " reason=", app.playground.external.reason)
		await finish()
		return
	check(app.playground.external_mode and not is_instance_valid(app.playground.shelf), "external support does not create own shelf")
	check(app.playground.last_support_error < 1.0, "external DWM seat contact within one pixel")
	print("COORD_CHECK native=", app.playground.support_area(), " godot=", area)
	check(app.playground.support_area() == area, "host-DPI virtual-desktop coordinates agree with Godot on this monitor")
	var remembered: Vector2i = app.playground.saved_floor_position
	var before: Vector2i = app.host.window.position
	command({"op": "move", "x": x + 90, "y": y + 30, "w": 740})
	await create_timer(0.45).timeout
	check(app.host.window.position.x > before.x + 80, "follows external window move and resize")
	check(app.playground.last_support_error < 1.0, "contact retained after external resize")
	check(app.playground.saved_floor_position == remembered, "temporary external anchor does not overwrite saved floor position")
	app._on_action(11)
	await create_timer(0.25).timeout
	check(app.playground.phase == "attached", "pet preserves external support")
	app._on_action(10)
	await create_timer(0.25).timeout
	check(app.playground.phase == "attached", "wave preserves external support")
	await capture()
	app._on_action(12)
	check(app.state.dozing and app.playground.phase == "attached", "dozing stays on selected window")
	var helper_pid: int = app.playground.external.process_id
	command({"op": "minimize"})
	check(await until(func(): return not app.playground.active()), "minimize returns companion to floor")
	check(app.host.is_grounded() and app.state.posture.kind == "floor", "external loss restores floor pose")
	check(await until(func(): return not OS.is_process_running(helper_pid), 2.0), "helper exits after detach")
	command({"op": "restore"})
	await create_timer(0.25).timeout
	app.playground.select_window(handle)
	check(await until(func(): return app.playground.phase == "attached"), "restored window can be manually reselected")
	app._on_action(30)
	check(await until(func(): return app.walker.active()), "walk waits for external return then starts")
	app._on_action(31)
	await until(func(): return not app.walker.active())
	app.playground.select_window(handle)
	await until(func(): return app.playground.phase == "attached")
	command({"op": "maximize"})
	check(await until(func(): return not app.playground.active()), "maximize releases unsupported support")
	command({"op": "restore"})
	await create_timer(0.3).timeout
	app.playground.select_window(handle)
	await until(func(): return app.playground.phase == "attached")
	helper_pid = app.playground.external.process_id
	command({"op": "close"})
	check(await until(func(): return not app.playground.active()), "closing external window releases support")
	check(await until(func(): return not OS.is_process_running(helper_pid), 2.0), "closed-window helper leaves no running process")
	app._switch_mode(true)
	check(app.host.preview and not app.playground.external_mode, "preview has no external ownership")
	await finish()

func _read_handle() -> bool:
	fixture_buffer += fixture_io.get_buffer(2048).get_string_from_utf8()
	if not fixture_buffer.contains("\n"):
		return false
	var line: String = fixture_buffer.get_slice("\n", 0)
	var data: Variant = JSON.parse_string(line)
	if data is Dictionary:
		handle = int(data.get("hwnd", "0"))
	return handle > 0

func capture() -> void:
	await RenderingServer.frame_post_draw
	var avatar: Image = root.get_texture().get_image()
	var support: Rect2i = app.playground.support_rect()
	var own: Rect2i = Rect2i(app.host.window.position, avatar.get_size())
	var union: Rect2i = support.merge(own).grow(12)
	var image: Image = Image.create(union.size.x, union.size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color("eee8f1"))
	image.fill_rect(Rect2i(support.position - union.position, support.size), Color("d2bedb"))
	image.fill_rect(Rect2i(support.position - union.position, Vector2i(support.size.x, 3)), Color("89678e"))
	avatar.convert(Image.FORMAT_RGBA8)
	image.blend_rect(avatar, Rect2i(Vector2i.ZERO, avatar.get_size()), own.position - union.position)
	var path: String = "res://.workspace/screenshots/external_05_schematic.png"
	check(image.save_png(path) == OK, "save avatar render with schematic support bounds, no external pixels")
	print("HOSHI_EXTERNAL_CAPTURE ", ProjectSettings.globalize_path(path))

func finish() -> void:
	if is_instance_valid(app):
		app.playground.release_for_mode_change()
		app.queue_free()
	if fixture_io != null:
		if OS.is_process_running(int(fixture.get("pid", -1))):
			command({"op": "close"})
		fixture_io.close()
	if fixture.has("stderr"):
		fixture["stderr"].close()
	await create_timer(0.2).timeout
	print("HOSHI_EXTERNAL_RESULT checks=", checks, " failures=", failures, " fixture_only=true")
	quit(0 if failures == 0 else 1)

func check_selection_controls() -> void:
	app._on_action(42)
	check(await until(func(): return app.playground.external.status == "selecting", 1.5), "UI selection starts bounded countdown before reading target")
	check(app.playground.external.snapshot.is_empty(), "no window selected before countdown expires")
	var pid: int = app.playground.external.process_id
	app._on_action(41)
	check(await until(func(): return not app.playground.active()), "cancel selection returns without acquiring a target")
	check(await until(func(): return not OS.is_process_running(pid), 2.0), "canceled picker leaves no helper")
	var own_handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	app.playground.select_window(own_handle)
	check(await until(func(): return not app.playground.active()), "own Hoshi window is rejected as external support")
	check(app.playground.external.reason == "own", "own-window rejection is explicit")
	app._switch_mode(true)
