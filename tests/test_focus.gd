extends SceneTree
## Режим «Моё окно → уголок»: трекер активного окна и правила переходов. Без VRM и Windows.

const FocusTracker = preload("res://scripts/focus_tracker.gd")
const Place = preload("res://scripts/place_director.gd")
const Commands = preload("res://scripts/hoshi_commands.gd")
const Playground = preload("res://scripts/shelf_playground.gd")

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

func _run() -> void:
	var focus = FocusTracker.new()
	focus.accept({"hwnd": "101", "app": "chrome.exe", "state": "normal"})
	focus.advance(200.0)
	_check(focus.dwell_seconds() >= 199.0 and focus.focus["app"] == "chrome.exe", "time in the same window adds up")
	focus.accept({"own": true})
	focus.advance(10.0)
	_check(focus.focus["hwnd"] == "101" and focus.dwell_seconds() >= 209.0, "clicking Hoshi herself does not count as leaving the window")
	focus.accept({"hwnd": "101", "app": "chrome.exe", "state": "normal"})
	_check(focus.dwell_seconds() >= 209.0, "heartbeat of the same window keeps the timer")
	focus.accept({"hwnd": "202", "app": "discord.exe", "state": "normal"})
	focus.advance(30.0)
	_check(focus.dwell_seconds() < 31.0 and focus.seconds_since_active("101") >= 29.0, "switching windows restarts the timer and remembers when the old one was active")
	_check(focus.seconds_since_active("202") == 0.0 and focus.seconds_since_active("999") == INF, "current and unknown windows report sensible away time")

	var normal := {"hwnd": "101", "app": "chrome.exe", "state": "normal"}
	_check(not Place.focus_ready(normal, 60.0, "normal"), "a short visit keeps Hoshi at home")
	_check(Place.focus_ready(normal, 200.0, "normal") and Place.focus_destination(normal, 200.0, "normal") == "window", "a long session in a normal window invites Hoshi")
	_check(not Place.focus_ready(normal, 200.0, "quiet") and Place.focus_ready(normal, 130.0, "playful"), "quiet waits longer, playful comes sooner")
	for state_name in ["maximized", "fullscreen", "minimized", "system", "none"]:
		_check(Place.focus_destination({"hwnd": "101", "state": state_name}, 999.0, "normal") == "cozy", "%s window sends Hoshi home" % state_name)
	_check(Place.focus_destination({}, 999.0, "normal") == "cozy", "unknown focus sends Hoshi home")

	var place = Place.new()
	place.change_mode("focus")
	_check(not place.focus_should_leave("cozy", normal, 60.0, 0.0, "normal"), "Hoshi stays in her corner while the visit is short")
	_check(place.focus_should_leave("cozy", normal, 200.0, 0.0, "normal"), "Hoshi leaves the corner to join a long session")
	place.note_focus_move()
	_check(not place.focus_should_leave("cozy", normal, 999.0, 0.0, "normal") and place.wait_left <= 3.0, "after a move she does not run back and forth, but picks the next place soon")
	place.move_cooldown = 0.0
	_check(not place.focus_should_leave("focus_window", normal, 10.0, 30.0, "normal"), "a brief switch away does not chase her off the window")
	_check(place.focus_should_leave("focus_window", normal, 10.0, 120.0, "normal"), "a long absence sends her back home")
	_check(not place.focus_should_leave("other", normal, 999.0, 999.0, "normal"), "a place the user chose by hand is left alone")
	place.change_mode("cozy")
	_check(not place.focus_should_leave("cozy", normal, 999.0, 0.0, "normal"), "other rest modes never move her by focus")

	# Развёрнутое окно: сесть сверху некуда — уголок подлетает поближе.
	var maximized := {"hwnd": "303", "app": "blender.exe", "state": "maximized"}
	_check(Place.focus_destination(maximized, 999.0, "normal") == "cozy" and Place.focus_near_ready(maximized, 200.0, "normal"), "a long session in a maximized window: go home first, then fly closer")
	_check(not Place.focus_near_ready(maximized, 60.0, "normal") and not Place.focus_near_ready({"hwnd": "404", "state": "fullscreen"}, 999.0, "normal"), "short visits and fullscreen video never pull the corner")
	place.move_cooldown = 0.0
	place.change_mode("focus")
	_check(place.focus_should_approach("cozy", maximized, 200.0, "normal", false), "the corner flies to a user who works long in a maximized window")
	_check(not place.focus_should_approach("cozy", maximized, 200.0, "normal", true), "once near that window it does not fly again")
	_check(not place.focus_should_approach("focus_window", maximized, 200.0, "normal", false), "only the corner flies, not a borrowed window")
	var area := Rect2i(0, 0, 1920, 1040)
	var size := Vector2i(460, 170)
	var cursor := Vector2i(900, 900)
	var spot: Vector2i = Playground.cozy_near_position(area, size, cursor, 360)
	var zone := Rect2i(spot.x, spot.y - 360, size.x, size.y + 360)
	_check(spot.x >= 0 and Rect2i(area).encloses(Rect2i(spot, size)), "the corner lands inside the screen")
	_check(not zone.has_point(cursor) and absf(spot.x + size.x * 0.5 - cursor.x) < 800.0, "Hoshi lands beside the pointer, not on top of it")
	var edge_spot: Vector2i = Playground.cozy_near_position(area, size, Vector2i(1900, 1000), 360)
	_check(edge_spot.x >= 0 and edge_spot.x + size.x < 1900, "near the screen edge the corner picks the free side")
	_check(Commands.has("place_focus") and Commands.PLACE_CHOICES.size() == Commands.PLACE_MODES.size() and Commands.PLACE_MODES[Commands.PLACE_CHOICES.find("place_focus")] == "focus", "the rest-mode menu knows «Моё окно → уголок»")
	var helper: String = FileAccess.get_file_as_string("res://tools/window_focus.py")
	_check(not helper.contains("GetWindowText") and not helper.contains("SetWindowsHook"), "focus helper reads no titles and installs no hooks")
	print("HOSHI_FOCUS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
