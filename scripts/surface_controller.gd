extends RefCounted
## Treats the current support as a local coordinate system.
## Gait owns leg stepping; this controller only maps its local route onto the support.
var app_ref: WeakRef
var owner_ref: WeakRef
var mode: String = "sit"
var side: String = ""
var _auto_wait: float = 24.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _walk_started: bool = false
var _auto_side_return: float = 0.0
var _last_auto_action: String = ""
var internal_autonomy_enabled: bool = false
var _scoot_from_u: float = 0.0
var _scoot_to_u: float = 0.0
var _scoot_age: float = 0.0
var _scoot_direction: float = 0.0
const SCOOT_DURATION: float = 1.65

func setup(companion, playground) -> void:
	app_ref = weakref(companion)
	owner_ref = weakref(playground)
	_rng.seed = 70421 if OS.get_cmdline_user_args().has("--test-mode") else int(Time.get_ticks_usec())
	reset()

func _owner():
	return owner_ref.get_ref() if owner_ref != null else null

func _app():
	return app_ref.get_ref() if app_ref != null else null

func reset() -> void:
	mode = "sit"
	side = ""
	_walk_started = false
	_auto_side_return = 0.0
	_last_auto_action = ""
	_scoot_age = 0.0
	_scoot_direction = 0.0
	_auto_wait = _rng.randf_range(22.0, 42.0)

func busy() -> bool:
	return mode != "sit"

func walking() -> bool:
	return mode in ["rise", "mount", "walk", "resit"]

func owns_placement() -> bool:
	return mode in ["mount", "walk", "scoot", "side_move", "side_left", "side_right"]

func posture_contact_pixel() -> Vector2:
	# On a surface route, placement follows the feet. A seated pose follows the
	# seat. Blend the two contacts while rising/resitting so switching owners
	# cannot move the native window by a whole torso in one frame.
	var app = _app()
	var foot: Vector2 = app.stage.standing_anchor_pixel()
	var seat: Vector2 = app.stage.camera.unproject_position(app.stage.edge_pose.anchor_world())
	return foot.lerp(seat, clampf(app.state.posture.amount, 0.0, 1.0))

func context_action() -> String:
	if mode == "side_left":
		return "side_left"
	if mode == "side_right":
		return "side_right"
	return "idle"

func label() -> String:
	match mode:
		"rise": return "Встаёт на край"
		"mount": return "Переставляет ножки на край"
		"walk": return "Гуляет по краю окна"
		"resit": return "Снова усаживается"
		"scoot": return "Тихонько передвигается по уголку"
		"side_move": return "Спускается к боковой рамке"
		"side_left", "side_right": return "Опирается на бок окна"
	return ""

func can_walk_route() -> bool:
	return _owner().phase == "attached" and _owner()._shelf_usable() and mode == "sit" and bool(_route_plan().get("ok", false))

func can_scoot_route() -> bool:
	return _owner().phase == "attached" and _owner().cozy_mode and _owner()._shelf_usable() and mode == "sit" and _app().state.posture.mode == "seated" and bool(_scoot_plan().get("ok", false))

func request_scoot() -> bool:
	if not can_scoot_route():
		return false
	var plan: Dictionary = _scoot_plan()
	_scoot_from_u = _fraction_from_local(float(plan["start"]))
	_scoot_to_u = _fraction_from_local(float(plan["target"]))
	_scoot_direction = signf(float(plan["target"]) - float(plan["start"]))
	_scoot_age = 0.0
	mode = "scoot"
	return true

func cancel_scoot() -> void:
	if mode == "scoot":
		mode = "sit"
		_scoot_age = 0.0
		_scoot_direction = 0.0

func scoot_pose() -> Dictionary:
	if mode != "scoot":
		return {}
	var progress: float = clampf(_scoot_age / SCOOT_DURATION, 0.0, 1.0)
	return {"weight": pow(sin(PI * progress), 2.0), "progress": progress, "direction": _scoot_direction}

func available_side() -> String:
	if _owner().phase != "attached" or not _owner().external_mode or not _owner()._shelf_usable() or mode != "sit":
		return ""
	var first: String = "right" if side == "left" else "left"
	var second: String = "left" if first == "right" else "right"
	if bool(_side_placement(first).get("ok", false)):
		return first
	if bool(_side_placement(second).get("ok", false)):
		return second
	return ""

func request_walk() -> bool:
	if not can_walk_route():
		return false
	_app().state.dozing = false
	_app().state.posture.kind = "edge"
	_app().state.posture.request_stand()
	_app()._rest_after_walk = false
	mode = "rise"
	_walk_started = false
	return true

func request_side(window_side: String, automatic: bool = false) -> bool:
	if _owner().phase != "attached" or not _owner().external_mode or not _owner()._shelf_usable():
		return false
	if not window_side in ["left", "right"]:
		return false
	# As with walking, reject impossible geometry before Hoshi visibly stands up.
	if not bool(_side_placement(window_side).get("ok", false)):
		return false
	_app().state.dozing = false
	_app()._stop_walk(true)
	_app().state.posture.kind = "edge"
	_app().state.posture.request_stand()
	side = window_side
	mode = "side_move"
	_auto_side_return = _rng.randf_range(5.5, 9.0) if automatic else 0.0
	return true

func request_sit_top() -> bool:
	if not mode in ["side_left", "side_right"]:
		return false
	var placement: Dictionary = _top_placement_for_fraction(_owner().anchor_u)
	if not bool(placement.get("ok", false)):
		return false
	_app().stage.set_context_action("idle")
	_app().air.begin_jump(Vector2(_app().host.window.position), Vector2(placement["position"]), float(_app().host.body_pixels))
	_auto_side_return = 0.0
	mode = "mount"
	_walk_started = true # mount ends by sitting instead of starting a route.
	return true

func before_tick(delta: float) -> void:
	if _owner().phase != "attached":
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	if mode == "sit" and internal_autonomy_enabled:
		_tick_autonomy(dt)
	elif mode == "scoot":
		_scoot_age = minf(SCOOT_DURATION, _scoot_age + dt)
	elif mode == "rise":
		if _app().state.posture.mode == "standing":
			var placement: Dictionary = _top_placement_for_fraction(_owner().anchor_u)
			if not bool(placement.get("ok", false)):
				_resit()
				return
			_app().air.begin_jump(Vector2(_app().host.window.position), Vector2(placement["position"]), float(_app().host.body_pixels))
			mode = "mount"
	elif mode == "mount":
		if not _app().air.active():
			if _walk_started:
				_walk_started = false
				_resit()
			else:
				_start_route()
	elif mode == "walk":
		if not _app().walker.active():
			_resit()
	elif mode == "resit":
		if _app().state.posture.mode == "seated":
			mode = "sit"
			_auto_wait = _rng.randf_range(24.0, 46.0)
	elif mode == "side_move":
		if _app().state.posture.mode == "standing" and not _app().air.active():
			var placement: Dictionary = _side_placement(side)
			if not bool(placement.get("ok", false)):
				_owner().return_home()
				return
			if Vector2(_app().host.window.position).distance_to(Vector2(placement["position"])) > 2.0:
				_app().air.begin_fall(Vector2(_app().host.window.position), Vector2(placement["position"]), float(_app().host.body_pixels))
			else:
				mode = "side_" + side
		elif _app().state.posture.mode == "standing" and _app().air.mode == "idle":
			mode = "side_" + side
	elif mode in ["side_left", "side_right"] and _auto_side_return > 0.0:
		_auto_side_return = maxf(0.0, _auto_side_return - dt)
		if _auto_side_return <= 0.0:
			request_sit_top()

func after_tick() -> void:
	if _owner().phase != "attached" or not owns_placement():
		return
	if mode == "scoot":
		var progress: float = clampf(_scoot_age / SCOOT_DURATION, 0.0, 1.0)
		var move: float = smoothstep(0.18, 0.88, progress)
		var fraction: float = lerpf(_scoot_from_u, _scoot_to_u, move)
		var seat_pixel: Vector2 = _app().stage.camera.unproject_position(_app().stage.edge_pose.anchor_world())
		var placement: Dictionary = _owner().solve_placement(_owner().support_rect(), fraction, seat_pixel, _app().host.window.size, _owner().support_area())
		if not bool(placement.get("ok", false)):
			cancel_scoot()
			return
		_app().host.place_at(Vector2(placement["position"]))
		_owner().anchor_u = fraction
		_owner().last_support_error = (Vector2(_app().host.window.position) + seat_pixel).distance_to(placement["anchor"])
		if progress >= 1.0:
			mode = "sit"
		return
	if mode in ["mount", "walk"]:
		var local_x: float = _current_local_x()
		if mode == "walk":
			local_x = _app().walker.x_px
		var placement: Dictionary = _top_placement(local_x)
		if not bool(placement.get("ok", false)):
			_owner().return_home()
			return
		if mode == "mount" and _app().air.active():
			_app().air.set_target(Vector2(placement["position"]))
		else:
			_app().host.place_at(Vector2(placement["position"]))
		_owner().anchor_u = _fraction_from_local(local_x)
		_owner().last_support_error = (Vector2(_app().host.window.position) + _app().stage.standing_anchor_pixel()).distance_to(placement["anchor"])
	elif mode in ["side_move", "side_left", "side_right"]:
		var placement: Dictionary = _side_placement(side)
		if not bool(placement.get("ok", false)):
			_owner().return_home()
			return
		if mode == "side_move" and _app().air.active():
			_app().air.set_target(Vector2(placement["position"]))
		elif mode != "side_move":
			_app().host.place_at(Vector2(placement["position"]))

func _tick_autonomy(delta: float) -> void:
	if _app().state.edge_activity != "auto" or not _app().state.autonomy_enabled or not _app().state.motion_enabled or _app().state.dozing:
		return
	if _app()._press_active or _app().ui.menu.visible or _app().state.notice_weight > 0.1 or _app().state.wave_weight > 0.1 or _app().state.pet_weight > 0.1:
		return
	_auto_wait = maxf(0.0, _auto_wait - delta)
	if _auto_wait > 0.0:
		return
	var activity: String = _app().state.activity
	var side_chance: float = 0.0 if not _owner().external_mode else (0.28 if activity == "playful" else (0.16 if activity == "normal" else 0.05))
	var leave_chance: float = 0.15 if activity == "playful" else (0.07 if activity == "normal" else 0.02)
	var roll: float = _rng.randf()
	if _owner().external_mode and roll < side_chance:
		var first_side: String = "left" if _rng.randf() < 0.5 else "right"
		var other_side: String = "right" if first_side == "left" else "left"
		if request_side(first_side, true) or request_side(other_side, true):
			_last_auto_action = "side"
			return
	if roll < side_chance + leave_chance:
		_last_auto_action = "leave"
		_owner().return_home()
		return
	if request_walk():
		_last_auto_action = "walk"
		return
	# No valid route: remain seated instead of doing a visible stand->sit no-op.
	_last_auto_action = "stay"
	_auto_wait = _rng.randf_range(16.0, 28.0)

func _route_plan() -> Dictionary:
	return plan_route(_owner().support_rect(), _current_local_x(), _app().stage.standing_anchor_pixel(), _app().host.window.size, _owner().support_area(), float(_app().host.body_pixels), _app().stage.meters_per_pixel(), _app().stage.model_height, _app().state.activity == "playful")

func _scoot_plan() -> Dictionary:
	var rect: Rect2i = _owner().support_rect()
	var start: float = lerpf(24.0, float(rect.size.x - 24), _owner().anchor_u)
	var seat_pixel: Vector2 = _app().stage.camera.unproject_position(_app().stage.edge_pose.anchor_world())
	var lane: Vector2 = top_lane(rect, seat_pixel, _app().host.window.size, _owner().support_area())
	if lane.y <= lane.x + 20.0 or start < lane.x or start > lane.y:
		return {"ok": false}
	var left_room: float = start - lane.x
	var right_room: float = lane.y - start
	var direction: float = 1.0 if right_room >= left_room else -1.0
	var span: float = minf(float(_app().host.body_pixels) * 0.22, maxf(left_room, right_room))
	if span < 20.0:
		return {"ok": false}
	var target: float = start + direction * span
	if not bool(_owner().solve_placement(rect, _fraction_from_local(target), seat_pixel, _app().host.window.size, _owner().support_area()).get("ok", false)):
		return {"ok": false}
	return {"ok": true, "start": start, "target": target}

func _start_route() -> void:
	var plan: Dictionary = _route_plan()
	if not bool(plan.get("ok", false)):
		_resit()
		return
	if not _app().walker.request(float(plan["start"]), float(plan["target"]), Vector2(plan["lane"]), _app().stage.meters_per_pixel(), _app().stage.model_height, _app().stage.yaw, _app().state.activity == "playful"):
		_resit()
		return
	_app()._walk_area = _app().host.walking_area()
	_app()._rest_after_walk = false
	mode = "walk"

func _resit() -> void:
	_app()._stop_walk()
	_app().state.posture.kind = "edge"
	_app().state.posture.request_sit(false)
	_app().stage.yaw = 0.0
	mode = "resit"

func _current_local_x() -> float:
	var rect: Rect2i = _owner().support_rect()
	var anchor_x: float = float(_app().host.window.position.x) + _app().stage.standing_anchor_pixel().x
	return anchor_x - float(rect.position.x)

func _fraction_from_local(local_x: float) -> float:
	var width: float = maxf(1.0, float(_owner().support_rect().size.x - 48))
	return clampf((local_x - 24.0) / width, 0.05, 0.95)

func _top_placement_for_fraction(fraction: float) -> Dictionary:
	var rect: Rect2i = _owner().support_rect()
	var local_x: float = lerpf(24.0, float(rect.size.x - 24), clampf(fraction, 0.05, 0.95))
	return _top_placement(local_x)

func _top_placement(local_x: float) -> Dictionary:
	return solve_top(_owner().support_rect(), local_x, _app().stage.standing_anchor_pixel(), _app().host.window.size, _owner().support_area())

func _side_placement(window_side: String) -> Dictionary:
	return solve_side(_owner().support_rect(), window_side, _app().stage.side_anchor_pixel(window_side), _app().host.window.size, _owner().support_area())

static func plan_route(rect: Rect2i, current_local_x: float, foot_pixel: Vector2, viewport: Vector2i, area: Rect2i, body_pixels: float, mpp: float, model_height: float, playful: bool = false) -> Dictionary:
	var lane: Vector2 = top_lane(rect, foot_pixel, viewport, area)
	if lane.y <= lane.x + 8.0 or mpp <= 0.0 or model_height <= 0.1:
		return {"ok": false}
	var start: float = clampf(current_local_x, lane.x, lane.y)
	if not bool(solve_top(rect, start, foot_pixel, viewport, area).get("ok", false)):
		return {"ok": false}
	var right_room: float = lane.y - start
	var left_room: float = start - lane.x
	var direction: int = 1 if right_room >= left_room else -1
	var room: float = maxf(right_room, left_room)
	var span: float = minf(body_pixels * (0.72 if playful else 0.56), room)
	if span * mpp < model_height * 0.12:
		return {"ok": false}
	var target: float = start + float(direction) * span
	if not bool(solve_top(rect, target, foot_pixel, viewport, area).get("ok", false)):
		return {"ok": false}
	return {"ok": true, "start": start, "target": target, "lane": lane}

static func solve_top(rect: Rect2i, local_x: float, foot_pixel: Vector2, viewport: Vector2i, area: Rect2i) -> Dictionary:
	if rect.size.x < 180 or rect.size.y < 80 or not foot_pixel.is_finite() or not is_finite(local_x):
		return {"ok": false}
	var screen_anchor := Vector2(float(rect.position.x) + local_x, float(rect.position.y + 2))
	var position: Vector2 = (screen_anchor - foot_pixel).round()
	if not Rect2(area).encloses(Rect2(position, Vector2(viewport))):
		return {"ok": false}
	return {"ok": true, "position": position, "anchor": screen_anchor}

static func top_lane(rect: Rect2i, foot_pixel: Vector2, viewport: Vector2i, area: Rect2i) -> Vector2:
	if not foot_pixel.is_finite() or viewport.x <= 0:
		return Vector2.ZERO
	var minimum_screen: float = maxf(float(rect.position.x + 24), float(area.position.x) + foot_pixel.x)
	var maximum_screen: float = minf(float(rect.end.x - 24), float(area.end.x - viewport.x) + foot_pixel.x)
	return Vector2(minimum_screen - float(rect.position.x), maximum_screen - float(rect.position.x))

static func solve_side(rect: Rect2i, window_side: String, contact_pixel: Vector2, viewport: Vector2i, area: Rect2i) -> Dictionary:
	if not window_side in ["left", "right"] or not contact_pixel.is_finite() or viewport.x <= 0 or viewport.y <= 0:
		return {"ok": false}
	var edge_x: float = float(rect.position.x if window_side == "left" else rect.end.x)
	var position := Vector2(edge_x - contact_pixel.x, float(area.end.y - viewport.y)).round()
	var avatar_rect := Rect2(position, Vector2(viewport))
	if not Rect2(area).encloses(avatar_rect):
		return {"ok": false}
	var contact_y: float = position.y + contact_pixel.y
	if contact_y < float(rect.position.y + 30) or contact_y > float(rect.end.y - 30):
		return {"ok": false}
	return {"ok": true, "position": position, "anchor": Vector2(edge_x, contact_y)}
