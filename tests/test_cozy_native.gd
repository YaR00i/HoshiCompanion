extends Node
## Real-scene Windows check: a repeated cozy menu action must not hide its own HWND.

var checks: int = 0
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() != "Windows":
		print("HOSHI_COZY_NATIVE_RESULT checks=0 failures=0 native_windows=false")
		get_tree().quit()
		return
	var app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	var deadline: int = Time.get_ticks_msec() + 10000
	while not app._ready_to_run and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(app._ready_to_run, "real scene loads Hoshi")
	if not app._ready_to_run:
		_finish()
		return
	app.state.autonomy_enabled = false
	_check(app.playground.show_demo(true), "cozy corner opens")
	deadline = Time.get_ticks_msec() + 10000
	while app.playground.phase != "attached" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(app.playground.phase == "attached" and app.state.posture.mode == "seated", "Hoshi sits on the cozy corner")
	if app.playground.phase != "attached":
		_finish()
		return
	var cozy: Window = app.playground.shelf
	var id: int = cozy.get_window_id()
	_check(_native_visible(cozy), "native cozy window is visible before menu action")
	for i in range(3):
		app._open_menu()
		app._on_action(43)
		app.ui.menu.hide()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(cozy == app.playground.shelf and cozy.get_window_id() == id and app.playground.phase == "attached" and app.state.posture.mode == "seated" and cozy.visible and _native_visible(cozy), "reselect %d keeps the seated Hoshi and native corner visible" % (i + 1))
	cozy.mode = Window.MODE_MINIMIZED
	await get_tree().process_frame
	app._on_action(43)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(cozy.mode == Window.MODE_WINDOWED and cozy.visible and _native_visible(cozy), "reselect restores a minimized native corner")
	deadline = Time.get_ticks_msec() + 10000
	while app.playground.phase != "attached" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(app.playground.phase == "attached" and app.state.posture.mode == "seated", "Hoshi seats again after restored corner")
	_finish()

func _native_visible(window: Window) -> bool:
	var python_path: String = FileAccess.get_file_as_string("res://python_path.txt").strip_edges()
	var helper: String = ProjectSettings.globalize_path("res://tests/native_window_state.py")
	var hwnd: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window.get_window_id())
	var lines: Array = []
	var code: int = OS.execute(python_path, PackedStringArray([helper, str(hwnd), str(OS.get_process_id())]), lines, true)
	var state: Variant = JSON.parse_string("".join(lines))
	return code == 0 and state is Dictionary and bool(state.get("visible", false))

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", label)
	else:
		print("PASS: ", label)

func _finish() -> void:
	print("HOSHI_COZY_NATIVE_RESULT checks=", checks, " failures=", failures, " native_windows=true")
	get_tree().quit(0 if failures == 0 else 1)
