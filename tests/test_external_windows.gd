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
	app._switch_mode(false)
	await process_frame
	await create_timer(0.12).timeout
	check(app.host.precise_input_available(), "own-HWND precise click-through helper starts on Windows")
	await RenderingServer.frame_post_draw
	check(app.stage.refresh_interaction_alpha(), "desktop mode caches only Hoshi viewport alpha")
	var torso_point: Vector2 = app.stage.camera.unproject_position(app.stage.rig.world_point("hips"))
	check(app.stage.visible_avatar_hit(torso_point) and not app.stage.visible_avatar_hit(Vector2(2.0, 2.0)), "alpha hit separates Hoshi from transparent window space")
	app.host.update_pointer_interaction(false)
	check(app.host.pointer_passthrough_requested(), "transparent Hoshi-window space requests OS click-through")
	app.host.update_pointer_interaction(true)
	check(not app.host.pointer_passthrough_requested(), "visible Hoshi pixel requests native input capture")
	app.host.update_pointer_interaction(false)
	check(not app.host.pointer_passthrough_requested(), "leaving Hoshi keeps capture for one stabilizing frame")
	app.host.update_pointer_interaction(false)
	check(app.host.pointer_passthrough_requested(), "stable transparent hover releases input after hysteresis")
	for index in range(24):
		app.host.update_pointer_interaction(index % 2 == 0)
	check(app.host.precise_input_available(), "rapid own-alpha boundary transitions keep native helper alive")
	var area: Rect2i = app.host.walking_area()
	var own_handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	var python_path: String = FileAccess.get_file_as_string("res://python_path.txt").strip_edges()
	fixture = OS.execute_with_pipe(python_path, PackedStringArray(["-u", ProjectSettings.globalize_path("res://tests/external_window_fixture.py"), str(own_handle), "560"]), false)
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
	var fixture_pid: int = int(fixture.get("pid", -1))
	check(app.playground.auto_choose_window(fixture_pid), "automatic support selection starts without reading window titles")
	check(await until(func(): return app.playground.phase == "attached" and app.state.posture.mode == "seated"), "automatic chooser docks on isolated fixture")
	check(await until(func(): return app.playground.last_support_error < 1.0, 1.0), "automatic choice keeps exact support contact")
	check(app.playground.external_mode, "automatic choice owns only isolated external support")
	app._on_action(41)
	check(await until(func(): return not app.playground.active()), "automatic support can return to floor")
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
	command({"op": "move_by", "dx": 90, "dy": 30, "dw": 100})
	await create_timer(0.45).timeout
	check(app.host.window.position.x > before.x + 80, "follows external window move and resize")
	check(app.playground.last_support_error < 1.0, "contact retained after external resize")
	check(app.playground.saved_floor_position == remembered, "temporary external anchor does not overwrite saved floor position")
	app._on_action(305)
	check(await until(func(): return app.playground.surface.mode == "walk" and app.walker.active(), 6.0), "external support starts local edge walk")
	check(await until(func(): return app.playground.surface.mode == "sit" and app.state.posture.mode == "seated", 12.0), "external edge walk settles back into seated support")
	check(app.playground.phase == "attached" and app.playground.external_mode and app.playground.last_support_error < 1.5, "external edge walk preserves selected support")
	# Planner-driven surface intent: use the same fixture and real controller path.
	app.state.autonomy_enabled = true
	app.state.edge_activity = "auto"
	app.intent_planner.cooldowns.clear()
	app.intent_planner.interrupt("test_reset")
	app._surface_intent_wait = 0.0
	var auto_side: String = app.playground.surface.available_side()
	check(not auto_side.is_empty(), "surface planner preflights at least one real side on fixture")
	if not auto_side.is_empty():
		var surface_context: Dictionary = {"blocked": false, "location": "surface", "can_observe": true, "can_social": true, "can_surface_walk": true, "can_side": true, "preferred_side": auto_side, "can_leave": true}
		var side_plan: Dictionary = app.intent_planner.build_plan("visit_side", surface_context)
		check(app.intent_planner.activate(side_plan), "surface intent planner accepts bounded side visit")
		check(await until(func(): return app.playground.surface.mode == "side_" + auto_side, 8.0), "planner-driven side visit reaches vertical frame")
		check(await until(func(): return app.playground.surface.mode == "sit" and app.state.posture.mode == "seated" and app.intent_planner.active_intent.is_empty(), 16.0), "planner-driven side visit waits then returns to top and completes")
	app.state.autonomy_enabled = false
	app._on_action(306)
	check(await until(func(): return app.playground.surface.mode == "side_left", 8.0), "left side action reaches floor-supported window lean")
	var left_contact: Vector2 = Vector2(app.host.window.position) + app.stage.side_anchor_pixel("left")
	var side_rect: Rect2i = app.playground.support_rect()
	check(absf(left_contact.x - float(side_rect.position.x)) < 1.5 and left_contact.y > side_rect.position.y + 25 and left_contact.y < side_rect.end.y - 25, "left shoulder contact aligns to external vertical frame")
	var side_before: Vector2i = app.host.window.position
	command({"op": "move_by", "dx": 45, "dy": 0, "dw": 0, "dh": 0})
	await create_timer(0.45).timeout
	left_contact = Vector2(app.host.window.position) + app.stage.side_anchor_pixel("left")
	side_rect = app.playground.support_rect()
	check(app.host.window.position.x > side_before.x + 35 and absf(left_contact.x - float(side_rect.position.x)) < 1.5, "side lean follows external window movement")
	app._on_action(308)
	check(await until(func(): return app.playground.surface.mode == "sit" and app.state.posture.mode == "seated", 10.0), "side lean can jump back onto the top edge")
	app._on_action(307)
	check(await until(func(): return app.playground.surface.mode == "side_right", 8.0), "right side action reaches floor-supported window lean")
	var right_contact: Vector2 = Vector2(app.host.window.position) + app.stage.side_anchor_pixel("right")
	side_rect = app.playground.support_rect()
	check(absf(right_contact.x - float(side_rect.end.x)) < 1.5 and right_contact.y > side_rect.position.y + 25 and right_contact.y < side_rect.end.y - 25, "right shoulder contact aligns to external vertical frame")
	app._on_action(308)
	check(await until(func(): return app.playground.surface.mode == "sit" and app.state.posture.mode == "seated", 10.0), "right lean returns to seated top edge")
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
	check(await until(func(): return _read_ack("restore"), 2.0), "isolated fixture confirms native restore")
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

func _read_ack(expected: String) -> bool:
	fixture_buffer += fixture_io.get_buffer(2048).get_string_from_utf8()
	for line in fixture_buffer.split("\n", false):
		var data: Variant = JSON.parse_string(line.strip_edges())
		if data is Dictionary and str(data.get("ack", "")) == expected:
			if expected == "restore":
				return not bool(data.get("iconic", true)) and bool(data.get("visible", false)) and bool(data.get("enabled", false)) and not bool(data.get("zoomed", true)) and not bool(data.get("cloaked", true)) and int(data.get("stable", 0)) >= 3
			return true
	return false

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
