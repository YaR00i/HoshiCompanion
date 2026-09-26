extends RefCounted
## Жизненный цикл сеанса: Хоши выходит из звёздной двери при запуске и
## уходит в неё при закрытии (сначала возвращается с опоры и встаёт).
## Также держит «кинематографическую» маску окна, пока идёт дверь.

## "" — обычная жизнь; "returning" — идёт домой перед уходом; "outro" — уходит в дверь.
var phase: String = ""
var mask_active: bool = false

var _app_ref: WeakRef

func setup(app) -> void:
	_app_ref = weakref(app)

func _app():
	return _app_ref.get_ref() if _app_ref != null else null

func quitting() -> bool:
	return not phase.is_empty()

func clear_mask() -> void:
	var app = _app()
	if app == null:
		return
	if mask_active:
		app.host.cinematic_mask(false)
		mask_active = false

## Каждый кадр. true — приложение закрывается, дальше этот кадр не обрабатывать.
func tick() -> bool:
	var app = _app()
	if app == null:
		return false
	if mask_active and not app.stage.cinematic_active():
		app.host.cinematic_mask(false)
		mask_active = false
	if phase == "returning" and not app.playground.active() and not app.air.active() and app.state.posture.mode == "standing":
		begin_outro()
	elif phase == "outro" and app.stage.outro_complete():
		finalize_quit()
		return true
	return false

func start_intro() -> void:
	var app = _app()
	if app == null:
		return
	if app.stage == null or app.host.preview:
		return
	app.stage.start_portal_intro()
	app.host.cinematic_mask(true)
	mask_active = true

func request_quit() -> void:
	var app = _app()
	if app == null:
		return
	if not phase.is_empty():
		return
	if app.desk_input.cursor_hanging:
		app.desk_input.end_cursor_hang()
	if app._ready_to_run and not app.host.preview and not app._test_mode and app.stage != null:
		app.places.manual_pause(999.0)
		app._clear_intent()
		app._stop_walk()
		app.state.dozing = false
		if app.playground.active():
			phase = "returning"
			app.playground.return_home()
		elif app.air.active():
			phase = "returning"
			app.air.begin_fall(Vector2(app.host.window.position), Vector2(app.host.floor_position()), float(app.host.body_pixels))
		elif app.state.posture.mode != "standing":
			phase = "returning"
			app.state.posture.request_stand()
		else:
			begin_outro()
		return
	finalize_quit()

func begin_outro() -> void:
	var app = _app()
	if app == null:
		return
	if phase == "outro":
		return
	phase = "outro"
	app.state.dozing = false
	app.state.posture.request_stand()
	app.stage.yaw = 0.0
	app.host.cinematic_mask(true)
	mask_active = true
	app.stage.start_portal_outro()
	app.ui.say("До скорого!")

func finalize_quit() -> void:
	var app = _app()
	if app == null:
		return
	app.playground.release_for_mode_change()
	clear_mask()
	app._save_settings()
	app.get_tree().quit()
