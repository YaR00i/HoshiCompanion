extends SceneTree

const UI = preload("res://scripts/companion_ui.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var ui = UI.new()
	root.add_child(ui)
	await process_frame
	ui.show_surface_scan({"ok": true, "window": [640, 420], "visited": 12,
		"visible_count": 1, "candidates": [{"x": 40, "y": 120, "width": 220, "kind": "Button"}]})
	assert(ui.surface_map.candidates.size() == 1)
	ui._on_surface_candidate_selected(0)
	assert(ui.surface_detail.text.contains("кнопка"))
	ui.surface_window.hide()
	ui.queue_free()
	print("HOSHI_WINDOW_SURFACE_UI_RESULT checks=2 failures=0")
	quit()
