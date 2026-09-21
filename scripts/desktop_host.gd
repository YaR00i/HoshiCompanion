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

func setup(root_window: Window) -> void:
	window = root_window
	headless = DisplayServer.get_name() == "headless"
	if not headless:
		DisplayServer.screen_set_keep_on(false)

func switch_mode(wants_preview: bool) -> void:
	if not preview and not headless:
		saved_position = window.position
	preview = wants_preview or headless
	if not preview and not DisplayServer.is_window_transparency_available():
		preview = true
		push_warning("Hoshi: transparency unavailable; opening preview instead.")
	if headless:
		return
	# Clear native region before resizing or switching modes.
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
		# Allow crossing monitors while dragging; clamp only when released.
		window.position = position

func finish_drag() -> void:
	if not headless and not preview:
		window.position = clamp_position(window.position)
		saved_position = window.position

func apply_mask() -> void:
	if headless or preview:
		return
	if not mask_enabled:
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		return
	# Conservative, STABLE envelope for all included gestures, not pixel hit-testing.
	# Windows clips rendering outside this polygon, so it includes the hair and hand.
	# Do not update it per frame (SetWindowRgn can flicker on some Windows drivers).
	var normalized: Array[Vector2] = [
		Vector2(0.24, 0.035), Vector2(0.76, 0.035),
		Vector2(0.94, 0.25), Vector2(0.96, 0.63),
		Vector2(0.94, 0.82), Vector2(0.94, 1.0),
		Vector2(0.06, 1.0), Vector2(0.06, 0.82),
		Vector2(0.04, 0.63), Vector2(0.06, 0.25)
	]
	_mask = PackedVector2Array()
	for point in normalized:
		_mask.append(point * Vector2(window.size))
	DisplayServer.window_set_mouse_passthrough(_mask)

func menu_focus(active: bool) -> void:
	if headless or preview:
		return
	window.unfocusable = not active
	if active:
		window.grab_focus()

func mask_contains(point: Vector2) -> bool:
	if preview or not mask_enabled or _mask.is_empty():
		return true
	return Geometry2D.is_point_in_polygon(point, _mask)


func walking_lane() -> Vector2:
	# Keep the whole native window on its CURRENT monitor. No autonomous crossing.
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
	# Fractional pixels are returned for a compensating subpixel model offset.
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
	# Return under the avatar on its current monitor, not on the cursor's monitor.
	var area: Rect2i = walking_area()
	return Vector2i(clampi(window.position.x, area.position.x, maxi(area.position.x, area.end.x - window.size.x)), area.end.y - window.size.y)

func place_at(point: Vector2) -> void:
	# Moves only this companion window. The support is an app-owned demo Window.
	if preview or headless or not point.is_finite():
		return
	var rounded := Vector2i(point.round())
	if window.position != rounded:
		window.position = rounded
