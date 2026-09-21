extends RefCounted
## Support lifecycle for app-owned and opt-in external resting places.
## Smart discovery is bounded, geometry-only and enabled by an explicit user setting.
const Shelf = preload("res://scripts/shelf_window.gd")
const Cozy = preload("res://scripts/cozy_window.gd")
var cozy_mode: bool = false
const External = preload("res://scripts/external_window.gd")
var external = External.new()
var external_mode: bool = false
var _countdown_number: int = -1
var _start_handle: int = 0
var _start_wait: float = 0.0
var _choice_request: Dictionary = {}
var _auto_choice: bool = false
var app
var shelf
var phase: String = "off"
var anchor_u: float = 0.60
var last_support_error: float = 0.0
var saved_floor_position: Vector2i = Vector2i.ZERO
var _from: Vector2 = Vector2.ZERO
var _return_goal: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _walk_after: bool = false
const TRAVEL_TIME: float = 0.85

func setup(companion) -> void:
	app = companion

func active() -> bool:
	return phase != "off"

func show_demo(use_cozy: bool = false) -> bool:
	if external_mode or (is_instance_valid(shelf) and cozy_mode != use_cozy):
		release_for_mode_change()
	if app.host.headless or not app.stage.is_loaded or not app.stage.edge_pose.available:
		return false
	if app.host.preview:
		app._switch_mode(false)
	if app.host.preview:
		app.ui.say("Для полочки нужен настольный режим")
		return false
	if phase in ["preparing", "boarding", "attached"] and _shelf_usable():
		return true
	cozy_mode = use_cozy
	if not is_instance_valid(shelf):
		_create_shelf()
	shelf.mode = Window.MODE_WINDOWED
	shelf.show()
	app.host.raise_companion()
	if not active():
		saved_floor_position = app.host.floor_position()
	app._clear_intent()
	app._stop_walk()
	app.state.dozing = false
	app.state.posture.request_stand()
	_walk_after = false
	phase = "preparing"
	return true

func _create_shelf() -> void:
	shelf = Cozy.new() if cozy_mode else Shelf.new()
	shelf.name = "HoshiShelf"
	shelf.visible = false
	shelf.size = Vector2i(460, 170) if cozy_mode else Vector2i(600, 285)
	shelf.theme = app.ui.theme
	app.add_child(shelf)
	shelf.close_requested.connect(close_shelf)
	shelf.sit_requested.connect(show_demo.bind(cozy_mode))
	if cozy_mode:
		shelf.activity_requested.connect(app._on_action)
	shelf.leave_requested.connect(return_home)
	shelf.preview_requested.connect(app._switch_mode.bind(true))
	var area: Rect2i = app.host.walking_area()
	shelf.position = area.position + Vector2i((area.size.x - shelf.size.x) / 2, int(area.size.y * 0.54))
	if cozy_mode:
		shelf.position = Vector2i(clampi(app.host.window.position.x - 180, area.position.x + 12, maxi(area.position.x + 12, area.end.x - shelf.size.x - 48)), area.end.y - maxi(250, int(app.host.body_pixels * 0.55 + 76.0)))

func before_tick(delta: float) -> void:
	if phase in ["selection_start", "auto_selection_start"]:
		_start_wait -= delta
		if _start_wait <= 0.0:
			if external.begin(OS.get_process_id(), _start_handle, _choice_request):
				phase = "auto_selecting" if _auto_choice else "selecting"
			elif _auto_choice:
				_fallback_cozy()
			else:
				app.ui.say(external.message())
				return_home()
	if external_mode:
		external.tick(delta)
		if external.status == "error" and phase not in ["returning", "settling", "off"]:
			if _auto_choice:
				_fallback_cozy()
				return
			app.ui.say(external.message())
			return_home()
	if phase == "selecting" and external.status == "selecting":
		var seconds: int = maxi(1, int(ceil(external.seconds_left)))
		if seconds != _countdown_number:
			_countdown_number = seconds
			app.ui.say("Наведи на окно · %d" % seconds)
	if phase in ["selecting", "auto_selecting"] and external.status == "following":
		anchor_u = float(external.snapshot.get("fraction", 0.60))
		_choice_request = {}
		_auto_choice = false
		phase = "preparing"
	if phase == "preparing":
		if not _shelf_usable():
			return_home()
		elif app.state.posture.mode == "standing" and not app.walker.active():
			var planned_seat: Vector2 = app.stage.camera.unproject_position(app.stage.edge_pose.planned_anchor_world())
			var planned: Dictionary = solve_placement(support_rect(), anchor_u, planned_seat, app.host.window.size, support_area())
			if not bool(planned.get("ok", false)):
				return_home()
			else:
				app.state.posture.kind = "edge"
				app.stage.yaw = 0.0
				app.stage.travel_offset_px = 0.0
				_from = Vector2(app.host.window.position)
				_age = 0.0
				app.air.begin_jump(_from, Vector2(planned["position"]), float(app.host.body_pixels))
				phase = "boarding"
	elif phase == "boarding":
		if not _shelf_usable():
			return_home()
		elif not app.air.active():
			if app.state.posture.mode == "standing" and not app.state.posture.target_seated:
				app.state.posture.request_sit(false)
			elif app.state.posture.mode == "seated":
				phase = "attached"
				app.host.raise_companion()
	elif phase == "attached":
		if not _shelf_usable():
			return_home()
	elif phase == "returning":
		if not app.air.active():
			if app.state.posture.mode != "standing":
				app.state.posture.request_stand()
			phase = "settling"
	elif phase == "settling" and app.state.posture.mode == "standing":
		_finish_return()

func _fallback_cozy() -> void:
	if app._test_mode:
		print("AUTO_FALLBACK reason=", external.reason, " status=", external.status)
	external.close()
	external_mode = false
	_choice_request = {}
	_auto_choice = false
	phase = "off"
	app.ui.say("Не нашла свободный край — посижу здесь")
	show_demo(true)

func _finish_return() -> void:
	external.close()
	external_mode = false
	app.state.posture.kind = "floor"
	app.host.window.position = app.host.floor_position()
	app.host.saved_position = app.host.window.position
	saved_floor_position = app.host.window.position
	phase = "off"
	app.director.user_interaction()
	app._save_settings()
	if _walk_after:
		_walk_after = false
		if not app.ui.menu.visible and not app._press_active:
			app._start_walk(false)

func after_tick() -> void:
	if phase in ["boarding", "attached"] and _shelf_usable():
		var anchor_world: Vector3 = app.stage.edge_pose.planned_anchor_world() if phase == "boarding" and not app.state.posture.target_seated else app.stage.edge_pose.anchor_world()
		var anchor: Vector2 = app.stage.camera.unproject_position(anchor_world)
		var area: Rect2i = support_area()
		var placement: Dictionary = solve_placement(support_rect(), anchor_u, anchor, app.host.window.size, area)
		if not bool(placement.get("ok", false)):
			if app._test_mode:
				print("SUPPORT_REJECT rect=", support_rect(), " area=", area, " seat=", anchor, " viewport=", app.host.window.size, " phase=", phase)
			app.ui.say("Здесь тесно — вернусь вниз")
			return_home()
		else:
			var goal: Vector2 = placement["position"]
			if phase == "boarding" and app.air.active():
				app.air.set_target(goal)
			else:
				app.host.place_at(goal)
			last_support_error = (Vector2(app.host.window.position) + anchor).distance_to(placement["anchor"])
	if is_instance_valid(shelf) and shelf.support_label != null:
		shelf.support_label.text = label()

static func solve_placement(rect: Rect2i, fraction: float, seat_pixel: Vector2, viewport_size: Vector2i, area: Rect2i) -> Dictionary:
	if rect.size.x < 180 or rect.size.y < 80 or not seat_pixel.is_finite() or not is_finite(fraction):
		return {"ok": false}
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return {"ok": false}
	var anchor := Vector2(lerpf(float(rect.position.x + 24), float(rect.end.x - 24), clampf(fraction, 0.0, 1.0)), float(rect.position.y + 2))
	var position: Vector2 = (anchor - seat_pixel).round()
	if not Rect2(area).encloses(Rect2(position, Vector2(viewport_size))):
		return {"ok": false}
	return {"ok": true, "position": position, "anchor": anchor}

func _shelf_usable() -> bool:
	if external_mode:
		return external.status == "following"
	return is_instance_valid(shelf) and not shelf.is_queued_for_deletion() and shelf.visible and shelf.mode == Window.MODE_WINDOWED

func return_home(walk_after: bool = false) -> void:
	_choice_request = {}
	_auto_choice = false
	_walk_after = walk_after
	if not active() or phase in ["returning", "settling"]:
		return
	external.close()
	app._clear_intent()
	app._stop_walk()
	app.state.dozing = false
	app.state.posture.request_stand()
	_from = Vector2(app.host.window.position)
	_return_goal = Vector2(app.host.floor_position())
	_age = 0.0
	app.air.begin_fall(_from, _return_goal, float(app.host.body_pixels))
	phase = "returning"
	app.director.user_interaction()

func begin_drag() -> void:
	if phase in ["selection_start", "selecting", "auto_selection_start", "auto_selecting"]:
		release_for_mode_change()
		return
	if active():
		phase = "carried"
	_walk_after = false

func finish_drag() -> bool:
	if _shelf_usable():
		var rect: Rect2i = support_rect()
		var cursor: Vector2 = Vector2(app.host.cursor_global())
		var seat: Vector2 = cursor
		if app.state.posture.kind == "edge":
			seat = Vector2(app.host.window.position) + app.stage.camera.unproject_position(app.stage.edge_pose.anchor_world())
		var point: Vector2 = seat if absf(seat.y - rect.position.y) <= 55.0 else cursor
		if point.x >= rect.position.x and point.x <= rect.end.x and absf(point.y - rect.position.y) <= 55.0:
			anchor_u = clampf((point.x - rect.position.x - 24.0) / maxf(1.0, rect.size.x - 48.0), 0.05, 0.95)
			if phase == "carried" and app.state.posture.kind == "edge":
				app.state.posture.request_sit(false)
				phase = "attached"
				app.host.raise_companion()
			else:
				show_demo()
			return true
	if phase == "carried":
		return_home()
		return true
	return false

func cancel_queued_walk() -> void:
	_walk_after = false

func release_for_mode_change() -> void:
	_choice_request = {}
	_auto_choice = false
	external.close()
	external_mode = false
	if active():
		app.host.place_at(Vector2(app.host.clamp_position(saved_floor_position)))
		app.host.saved_position = app.host.window.position
		app.state.posture.reset_standing()
	phase = "off"
	_walk_after = false
	if is_instance_valid(shelf):
		shelf.hide()
		shelf.queue_free()
		shelf = null

func close_shelf() -> void:
	app.places.manual_pause(180.0)
	return_home()
	if is_instance_valid(shelf):
		shelf.hide()
		shelf.queue_free()
		shelf = null

func handle_action(action: int) -> bool:
	if action == 43:
		show_demo(true)
		return true
	if action == 42:
		select_window()
		return true
	if action == 40:
		show_demo()
		return true
	if action == 41:
		return_home()
		return true
	if not active():
		return false
	if action in [30, 33, 140]:
		return_home(action == 30)
		return true
	if action in [32, 101]:
		return true
	if action == 12:
		if phase == "attached":
			app.state.dozing = not app.state.dozing
		return true
	if action == 31:
		_walk_after = false
		if phase in ["selection_start", "selecting", "auto_selection_start", "auto_selecting", "preparing", "boarding"]:
			return_home()
		return true
	if action == 121:
		app.state.motion_enabled = not app.state.motion_enabled
		app._save_settings()
		return true
	cancel_queued_walk()
	return false

func label() -> String:
	if phase == "attached" and not app.state.dozing:
		var activity: String = app.stage.edge_life.label()
		if not activity.is_empty():
			return activity
	if phase in ["selection_start", "selecting"]:
		return "Наведи на окно: %d с · ПКМ → На пол — отмена" % maxi(0, int(ceil(external.seconds_left)))
	if phase in ["auto_selection_start", "auto_selecting"]:
		return "Ищет себе уютный край"
	if external_mode and phase == "attached":
		return "Дремлет на выбранном окне" if app.state.dozing else "Сидит на выбранном окне"
	match phase:
		"preparing", "boarding": return "Устраивается на полочке"
		"attached": return "Дремлет на полочке" if app.state.dozing else "Сидит на краю — можно двигать окно"
		"carried": return "В руках — отпусти у края полочки"
		"returning": return "Возвращается к нижнему краю"
		"settling": return "Снова встаёт на пол"
	return "Полочка свободна — нажми «Посадить»"

func select_window(explicit_handle: int = 0) -> bool:
	# explicit_handle is for isolated test fixtures; UI always uses the cursor.
	if app.host.headless or not app.stage.edge_pose.available:
		return false
	release_for_mode_change()
	if app.host.preview:
		app._switch_mode(false)
	if app.host.preview:
		return false
	saved_floor_position = app.host.floor_position()
	app._clear_intent()
	app._stop_walk()
	app.state.dozing = false
	app.state.posture.request_stand()
	_walk_after = false
	_choice_request = {}
	_auto_choice = false
	external_mode = true
	_countdown_number = -1
	_start_handle = explicit_handle
	_start_wait = 0.20
	phase = "selection_start"
	app.ui.say("Наведи на нужное окно · 4")
	app.ui._bubble_left = 5.0
	return true

func auto_choose_window(fixture_pid: int = 0) -> bool:
	if app.host.headless or not app.stage.edge_pose.available:
		return false
	release_for_mode_change()
	if app.host.preview:
		app._switch_mode(false)
	if app.host.preview:
		return false
	saved_floor_position = app.host.floor_position()
	app._clear_intent()
	app._stop_walk()
	app.state.dozing = false
	app.state.posture.request_stand()
	_walk_after = false
	external_mode = true
	_auto_choice = true
	_start_handle = 0
	_start_wait = 0.05
	var seat: Vector2 = app.stage.camera.unproject_position(app.stage.edge_pose.planned_anchor_world())
	var area: Rect2i = app.host.walking_area()
	_choice_request = {
		"seat": [seat.x, seat.y],
		"size": [app.host.window.size.x, app.host.window.size.y],
		"area": [area.position.x, area.position.y, area.size.x, area.size.y],
		"origin": [app.host.window.position.x, app.host.window.position.y]
	}
	if fixture_pid > 0:
		_choice_request["fixture_pid"] = fixture_pid
	phase = "auto_selection_start"
	app.ui.say("Ищу уютный край…")
	return true

func support_rect() -> Rect2i:
	return external.current_rect() if external_mode else shelf.outer_rect()

func support_area() -> Rect2i:
	return external.current_area() if external_mode else app.host.usable_area(shelf.current_screen)
