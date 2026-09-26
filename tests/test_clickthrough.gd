extends SceneTree
## Own-HWND regression: transparent Hoshi window space must release OS mouse input.
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _style(underlay_handle: int) -> Dictionary:
	var python_path: String = FileAccess.get_file_as_string("res://python_path.txt").strip_edges()
	var helper: String = ProjectSettings.globalize_path("res://tests/own_window_input_style.py")
	var hwnd: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	var lines: Array = []
	var code: int = OS.execute(python_path, PackedStringArray([helper, str(hwnd), str(OS.get_process_id()), str(underlay_handle)]), lines, true)
	var result: Variant = JSON.parse_string("".join(lines))
	return result if code == 0 and result is Dictionary else {}

func _run() -> void:
	if DisplayServer.get_name() != "Windows":
		print("HOSHI_CLICKTHROUGH_RESULT checks=0 failures=0 native_windows=false")
		quit(0)
		return
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for i in range(30):
		await process_frame
		if app._ready_to_run:
			break
	_check(app._ready_to_run, "Hoshi starts in native mode")
	if not app._ready_to_run:
		quit(1)
		return
	app.state.autonomy_enabled = false
	app.state.place_mode = "off"
	for i in range(300):
		await process_frame
		if not app.stage.cinematic_active():
			break
	var area: Rect2i = app.host.usable_area(DisplayServer.get_primary_screen())
	var cursor: Vector2i = DisplayServer.mouse_get_position()
	var left: Vector2i = area.position + Vector2i(20, 20)
	var right: Vector2i = area.end - app.host.window.size - Vector2i(20, 20)
	app.host.drag_to(left if Vector2(cursor - left).length() > Vector2(cursor - right).length() else right)
	for i in range(8):
		await process_frame
	var underlay := Window.new()
	underlay.title = "Hoshi input fixture"
	underlay.borderless = true
	underlay.always_on_top = true
	underlay.size = Vector2i(110, 72)
	underlay.position = app.host.window.position + Vector2i(4, app.host.window.size.y - 64)
	underlay.transient = false
	root.add_child(underlay)
	underlay.show()
	app.host.raise_companion()
	app.host.update_pointer_interaction(false)
	app.host.update_pointer_interaction(false)
	for i in range(3):
		await process_frame
	var underlay_handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, underlay.get_window_id())
	var style: Dictionary = _style(underlay_handle)
	_check(not style.is_empty(), "query only Hoshi's own HWND")
	var native_point: Array = style.get("point", [])
	var native_rect: Array = style.get("overlay_rect", [])
	var local_point: Vector2 = Vector2.ZERO
	if native_point.size() == 2 and native_rect.size() == 4:
		local_point = Vector2((float(native_point[0]) - float(native_rect[0])) * float(app.host.window.size.x) / maxf(1.0, float(native_rect[2]) - float(native_rect[0])), (float(native_point[1]) - float(native_rect[1])) * float(app.host.window.size.y) / maxf(1.0, float(native_rect[3]) - float(native_rect[1])))
	_check(native_point.size() == 2 and not app.stage.visible_avatar_hit(local_point), "overlap point is transparent Hoshi space")
	_check(app.host.pointer_passthrough_requested(), "empty space requests pointer pass-through")
	_check(bool(style.get("passthrough", false)), "Windows HWND carries the pass-through style")
	_check(style.get("target", "") == "underlay", "Windows targets an app-owned button below transparent Hoshi space")
	app._open_menu()
	for i in range(3):
		await process_frame
	_check(app.ui.quick_menu.visible and app.ui.menu_open(), "themed menu opens as a native popup")
	app.ui.quick_menu.hide()
	for i in range(3):
		await process_frame
	_check(not app.ui.menu_open(), "themed menu closes without leaving the companion blocked")
	underlay.queue_free()
	app.queue_free()
	await process_frame
	print("HOSHI_CLICKTHROUGH_RESULT checks=", checks, " failures=", failures, " native_windows=true")
	quit(0 if failures == 0 else 1)
