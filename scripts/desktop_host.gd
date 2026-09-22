extends RefCounted
## Small, native transparent window; never a full-screen input-catching overlay.
## Only monitor geometry and cursor position are read. No window titles/screenshots.

var window: Window
var preview: bool = true
var headless: bool = false
var body_pixels: int = 360
var mask_enabled: bool = true
var saved_position: Vector2i = Vector2i(-99999, -99999)
var _mask: PackedVector2Array = PackedVector2Array()
var _input_process: Dictionary = {}
var _input_io: FileAccess
var _input_passthrough: bool = false
var _input_passthrough_known: bool = false
var _native_passthrough_available: bool = false
var _cinematic_input: bool = false
var _release_candidate_frames: int = 0
const RELEASE_STABLE_FRAMES: int = 2

func setup(root_window: Window) -> void:
	window = root_window
	headless = DisplayServer.get_name() == "headless"
	if not headless:
		DisplayServer.screen_set_keep_on(false)

func switch_mode(wants_preview: bool) -> void:
	_stop_input_helper()
	if not preview and not headless:
		saved_position = window.position
	preview = wants_preview or headless
	if not preview and not DisplayServer.is_window_transparency_available():
		preview = true
		push_warning("Hoshi: transparency unavailable; opening preview instead.")
	if headless:
		return
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	window.mode = Window.MODE_WINDOWED
	window.borderless = not preview
	window.always_on_top = not preview
	window.unfocusable = not preview
	window.transparent = not preview
	window.transparent_bg = not preview
	window.unresizable = true
	window.size = Vector2i(900, 620) if preview else desktop_size()
	window.title = "Hoshi Companion 3D — примерочная" if preview else "Hoshi Companion 3D"
	if preview:
		var rect: Rect2i = usable_area(DisplayServer.get_primary_screen())
		window.position = rect.position + (rect.size - window.size) / 2
	else:
		if saved_position.x > -90000:
			window.position = clamp_position(saved_position)
		else:
			home()
		_start_input_helper()
		apply_mask()

func desktop_size() -> Vector2i:
	return Vector2i(int(round(body_pixels * 0.90 + 28.0)), body_pixels + 66)

func usable_area(screen: int) -> Rect2i:
	if headless:
		return Rect2i(0, 0, 1280, 720)
	var safe_screen: int = clampi(screen, 0, maxi(0, DisplayServer.get_screen_count() - 1))
	var area: Rect2i = DisplayServer.screen_get_usable_rect(safe_screen)
	if area.size.x <= 0 or area.size.y <= 0:
		area = Rect2i(DisplayServer.screen_get_position(safe_screen), DisplayServer.screen_get_size(safe_screen))
	return area

func _screen_for(point: Vector2i) -> int:
	if headless:
		return 0
	for index in range(DisplayServer.get_screen_count()):
		var full: Rect2i = Rect2i(DisplayServer.screen_get_position(index), DisplayServer.screen_get_size(index))
		if full.has_point(point):
			return index
	return DisplayServer.get_primary_screen()

func clamp_position(desired: Vector2i) -> Vector2i:
	var screen: int = _screen_for(desired + window.size / 2)
	var area: Rect2i = usable_area(screen)
	return Vector2i(
		clampi(desired.x, area.position.x, maxi(area.position.x, area.end.x - window.size.x)),
		clampi(desired.y, area.position.y, maxi(area.position.y, area.end.y - window.size.y))
	)

func home() -> void:
	if headless:
		return
	var area: Rect2i = usable_area(_screen_for(DisplayServer.mouse_get_position()))
	window.position = area.end - window.size - Vector2i(32, 0)
	window.position = clamp_position(window.position)
	saved_position = window.position

func resize_body(pixels: int) -> void:
	body_pixels = clampi(pixels, 240, 520)
	if not preview and not headless:
		var feet: Vector2i = window.position + Vector2i(window.size.x / 2, window.size.y)
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		window.size = desktop_size()
		window.position = clamp_position(feet - Vector2i(window.size.x / 2, window.size.y))
		saved_position = window.position
		apply_mask()

func cursor_local() -> Vector2:
	if headless:
		return Vector2(450.0, 200.0)
	return Vector2(DisplayServer.mouse_get_position() - window.position)

func cursor_global() -> Vector2i:
	return Vector2i.ZERO if headless else DisplayServer.mouse_get_position()

func drag_to(position: Vector2i) -> void:
	if not headless and not preview:
		window.position = position

func finish_drag() -> void:
	if not headless and not preview:
		window.position = clamp_position(window.position)
		saved_position = window.position

func _fallback_mask(expanded: bool = false) -> PackedVector2Array:
	var normalized: Array[Vector2]
	if expanded:
		normalized = [
			Vector2(0.07, 0.015), Vector2(0.93, 0.015),
			Vector2(0.98, 0.16), Vector2(0.99, 1.0),
			Vector2(0.01, 1.0), Vector2(0.02, 0.16)
		]
	else:
		normalized = [
			Vector2(0.24, 0.035), Vector2(0.76, 0.035),
			Vector2(0.94, 0.25), Vector2(0.96, 0.63),
			Vector2(0.94, 0.82), Vector2(0.94, 1.0),
			Vector2(0.06, 1.0), Vector2(0.06, 0.82),
			Vector2(0.04, 0.63), Vector2(0.06, 0.25)
		]
	var polygon := PackedVector2Array()
	for point in normalized:
		polygon.append(point * Vector2(window.size))
	return polygon

func apply_mask(expanded: bool = false) -> void:
	if headless or preview:
		return
	_cinematic_input = expanded
	_mask = _fallback_mask(expanded)
	if _native_passthrough_available:
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		_set_native_passthrough(mask_enabled, true)
		return
	if not mask_enabled:
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		return
	DisplayServer.window_set_mouse_passthrough(_mask)

func update_pointer_interaction(avatar_hit: bool, force_capture: bool = false) -> void:
	if headless or preview or not _native_passthrough_available:
		return
	if _cinematic_input:
		_release_candidate_frames = 0
		_set_native_passthrough(true)
		return
	if not mask_enabled:
		_release_candidate_frames = 0
		_set_native_passthrough(false)
		return
	if avatar_hit or force_capture:
		# Capture immediately so a click that follows pointer entry is never lost.
		_release_candidate_frames = 0
		_set_native_passthrough(false)
		return
	# Releasing input back through the transparent window is intentionally a
	# little sticky. Alpha edges (hair, skirt, antialiasing) can otherwise flip
	# the native HWND style on adjacent frames while the cursor crosses Hoshi.
	if _input_passthrough_known and not _input_passthrough:
		_release_candidate_frames += 1
		if _release_candidate_frames < RELEASE_STABLE_FRAMES:
			return
	_release_candidate_frames = 0
	_set_native_passthrough(true)

func menu_focus(active: bool) -> void:
	if headless or preview:
		return
	window.unfocusable = not active
	if active:
		window.grab_focus()
		if _native_passthrough_available:
			_set_native_passthrough(false, true)
	elif _native_passthrough_available:
		_input_passthrough_known = false

func cinematic_mask(active: bool) -> void:
	if headless or preview:
		return
	_cinematic_input = active
	_mask = _fallback_mask(active)
	if _native_passthrough_available:
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		if active:
			_set_native_passthrough(true, true)
		else:
			_input_passthrough_known = false
	else:
		apply_mask(active)

func precise_input_available() -> bool:
	if not _native_passthrough_available:
		return false
	if not _input_helper_alive():
		_native_passthrough_available = false
		return false
	return true

func pointer_passthrough_requested() -> bool:
	return _input_passthrough_known and _input_passthrough

func _start_input_helper() -> void:
	if headless or preview or DisplayServer.get_name() != "Windows":
		return
	var python_path: String = FileAccess.get_file_as_string("res://python_path.txt").strip_edges()
	if python_path.is_empty() or not FileAccess.file_exists(python_path):
		push_warning("Hoshi: precise Windows click-through unavailable; using polygon fallback.")
		return
	var helper_path: String = ProjectSettings.globalize_path("res://tools/window_input_passthrough.py")
	var hwnd: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	if hwnd <= 0:
		push_warning("Hoshi: native HWND unavailable; using polygon click mask.")
		return
	var pipe: Dictionary = OS.execute_with_pipe(python_path, PackedStringArray(["-u", helper_path, str(hwnd)]), false)
	if pipe.is_empty():
		push_warning("Hoshi: input passthrough helper did not start; using polygon fallback.")
		return
	_input_process = pipe
	_input_io = pipe.get("stdio") as FileAccess
	_native_passthrough_available = _input_io != null
	_input_passthrough_known = false
	_release_candidate_frames = 0

func _input_helper_alive() -> bool:
	if _input_process.is_empty():
		return false
	var pid: int = int(_input_process.get("pid", -1))
	return pid > 0 and OS.is_process_running(pid)

func _set_native_passthrough(active: bool, force: bool = false) -> void:
	if not _native_passthrough_available or _input_io == null:
		return
	if not _input_helper_alive():
		_native_passthrough_available = false
		return
	if not force and _input_passthrough_known and _input_passthrough == active:
		return
	_input_io.store_line(JSON.stringify({"op": "passthrough", "active": active}))
	_input_io.flush()
	_input_passthrough = active
	_input_passthrough_known = true

func _stop_input_helper() -> void:
	if _input_io != null:
		if _input_helper_alive():
			_input_io.store_line(JSON.stringify({"op": "stop"}))
			_input_io.flush()
		_input_io.close()
	var stderr_file: FileAccess = _input_process.get("stderr") as FileAccess
	if stderr_file != null:
		stderr_file.close()
	_input_io = null
	_input_process.clear()
	_native_passthrough_available = false
	_input_passthrough = false
	_input_passthrough_known = false
	_release_candidate_frames = 0
	_cinematic_input = false

func shutdown() -> void:
	_stop_input_helper()

func raise_companion() -> void:
	if headless or preview:
		return
	window.always_on_top = true
	DisplayServer.window_move_to_foreground(window.get_window_id())

func mask_contains(point: Vector2) -> bool:
	if preview or not mask_enabled or _mask.is_empty():
		return true
	return Geometry2D.is_point_in_polygon(point, _mask)

func walking_lane() -> Vector2:
	var area: Rect2i = walking_area()
	return Vector2(float(area.position.x + 6), float(maxi(area.position.x + 6, area.end.x - window.size.x - 6)))

func walking_area() -> Rect2i:
	return usable_area(_screen_for(window.position + window.size / 2))

func is_grounded() -> bool:
	if preview or headless:
		return false
	var area: Rect2i = walking_area()
	return absi(window.position.y + window.size.y - area.end.y) <= 8

func walk_to(x_value: float) -> float:
	if preview or headless:
		return 0.0
	var lane: Vector2 = walking_lane()
	var safe_x: float = clampf(x_value, lane.x, lane.y)
	var area: Rect2i = walking_area()
	var wanted: Vector2i = Vector2i(int(round(safe_x)), area.end.y - window.size.y)
	if window.position != wanted:
		window.position = wanted
	saved_position = window.position
	return safe_x - float(window.position.x)

func floor_position() -> Vector2i:
	var area: Rect2i = walking_area()
	return Vector2i(clampi(window.position.x, area.position.x, maxi(area.position.x, area.end.x - window.size.x)), area.end.y - window.size.y)

func place_at(point: Vector2) -> void:
	if preview or headless or not point.is_finite():
		return
	var rounded := Vector2i(point.round())
	if window.position != rounded:
		window.position = rounded
