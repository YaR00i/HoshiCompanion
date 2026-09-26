extends SceneTree
## Render Hoshi's own popup viewport, without capturing the desktop.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for index in range(30):
		await process_frame
		if app._ready_to_run:
			break
	if not app._ready_to_run:
		push_error("Quick menu capture: avatar did not load")
		quit(1)
		return
	app.state.autonomy_enabled = false
	app.ui.bubbles_enabled = false
	app.ui.refresh(app.state, "Тихо рисует в уголке")
	app.ui.open_quick_menu(Vector2i(60, 45))
	for index in range(5):
		await process_frame
	var image: Image = app.ui.quick_menu.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Quick menu capture: empty popup viewport")
		quit(1)
		return
	var path: String = ProjectSettings.globalize_path("res://.workspace/screenshots/quick_menu.png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var result: Error = image.save_png(path)
	print("HOSHI_QUICK_MENU_CAPTURE path=", path, " size=", image.get_size(), " error=", result)
	app.queue_free()
	quit(0 if result == OK else 1)
