extends SceneTree
## Судья опор и опора-линия внутри окна. Без VRM и без Windows.

const Judge = preload("res://scripts/support_judge.gd")
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
	var window := Vector2i(600, 400)
	# Помощник меряет в физических пикселях (например, 150% масштаб), Хоши — в своих.
	var scan := {"ok": true, "source": "structure", "window": [900, 600], "app": "explorer.exe", "candidates": [
		{"x": 3, "y": 90, "width": 894, "kind": "ToolBar"},
		{"x": 30, "y": 300, "width": 240, "kind": "ListItem"},
		{"x": 30, "y": 330, "width": 120, "kind": "Button"},
		{"x": 30, "y": 560, "width": 600, "kind": "Pane"},
	]}
	var found: Array[Dictionary] = Judge.normalize(scan, window)
	_check(found.size() == 4 and found[0]["y"] == 60 and found[0]["width"] == 596 and found[0]["x"] == 2, "helper pixels are scaled into Hoshi's window pixels")
	_check(Judge.level_for(found[0]["confidence"]) == "manual", "a wide structure toolbar is a manual-level seat")
	_check(Judge.judge(found[2], window)["reason"] == "narrow", "a narrow button is not a seat")
	_check(Judge.judge(found[3], window)["reason"] == "too_low", "a line with no window below it is not a seat")
	_check(Judge.judge({"x": 0, "y": 8, "width": 400, "confidence": 0.7}, window)["reason"] == "top_edge", "a line at the very top is just the window top")
	_check(Judge.judge({"x": 0, "y": 100, "width": 400, "confidence": 0.3}, window)["reason"] == "unsure", "an unconfirmed visual edge is only shown, never used")
	_check(Judge.normalize({"ok": false}, window).is_empty(), "failed scans give no candidates")

	var picked: Dictionary = Judge.pick_under_cursor(found, Vector2(300, 80), window)
	_check(picked.get("kind", "") == "ToolBar" and picked.get("level", "") == "manual", "pointing just below a toolbar picks the toolbar top")
	_check(Judge.pick_under_cursor(found, Vector2(300, 390), window).is_empty(), "pointing where no seat fits picks nothing")
	_check(Judge.pick_under_cursor(found, Vector2(300, 250), window).is_empty(), "pointer far below a line does not jump up to it")

	var window_rect := Rect2i(-1500, 300, 600, 400)
	var ledge_rect: Rect2i = Judge.ledge_rect(window_rect, picked)
	_check(ledge_rect == Rect2i(-1498, 360, 596, 340), "an inner ledge becomes a small support whose top is the line")
	var fraction: float = Judge.seat_fraction(picked, 300.0)
	_check(fraction > 0.4 and fraction < 0.6, "Hoshi sits on the ledge under the pointer")
	var placement: Dictionary = Playground.solve_placement(ledge_rect, fraction, Vector2(176, 330), Vector2i(352, 426), Rect2i(-1920, 0, 1920, 1080))
	_check(bool(placement.get("ok", false)) and absf(float(placement["anchor"].y) - float(ledge_rect.position.y + 2)) < 0.1, "existing seat solver works on an inner ledge unchanged")

	var playground = Playground.new()
	playground.external_mode = true
	playground.external.snapshot = {"rect": [window_rect.position.x, window_rect.position.y, window_rect.size.x, window_rect.size.y], "area": [-1920, 0, 1920, 1080]}
	_check(playground.support_rect() == window_rect and playground.side_edges_available(), "without a ledge Hoshi uses the window top and may lean on its sides")
	playground.ledge = picked
	_check(playground.support_rect() == ledge_rect and not playground.side_edges_available(), "on an inner ledge the support is the ledge and window-side leaning is off")
	playground.external.snapshot = {}

	# Приватность: имя программы — только имя файла; заголовки и тексты не читаются.
	var forbidden: Array[String] = ["GetWindowText", "Current.Name", "ValuePattern", "TextPattern"]
	var clean: bool = true
	for path in ["res://tools/window_identity.py", "res://tools/window_geometry.py", "res://tools/window_surfaces.py", "res://tools/window_surfaces.ps1"]:
		var source: String = FileAccess.get_file_as_string(path)
		for word in forbidden:
			if source.contains(word):
				clean = false
				push_error("%s uses %s" % [path, word])
	_check(clean, "window helpers never read titles, names or text")
	_finish()

func _finish() -> void:
	print("HOSHI_SUPPORTS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
