extends RefCounted
## Screen-space jump/fall/landing route. Owns no OS APIs and touches no rig bones.
var mode: String = "idle"
var position: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var _start: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _duration: float = 0.6
var _arc_px: float = 48.0
var _landing_time: float = 0.0

func active() -> bool:
	return mode != "idle"

func moving() -> bool:
	return mode in ["jump", "fall"]

func pose_mode() -> String:
	return mode

func cancel(at: Vector2 = position) -> void:
	mode = "idle"
	position = at
	target = at
	_start = at
	_age = 0.0
	_landing_time = 0.0

func begin_jump(from: Vector2, to: Vector2, body_pixels: float) -> void:
	_start = from
	position = from
	target = to
	_age = 0.0
	_duration = clampf(0.52 + from.distance_to(to) / maxf(body_pixels, 1.0) * 0.18, 0.52, 0.82)
	_arc_px = clampf(maxf(34.0, from.distance_to(to) * 0.18), 34.0, body_pixels * 0.22)
	mode = "jump"

func begin_fall(from: Vector2, to: Vector2, body_pixels: float) -> void:
	_start = from
	position = from
	target = to
	_age = 0.0
	var vertical: float = absf(to.y - from.y)
	_duration = clampf(0.36 + sqrt(vertical / maxf(body_pixels, 1.0)) * 0.34, 0.38, 0.92)
	_arc_px = 0.0
	mode = "fall"

func set_target(value: Vector2) -> void:
	if value.is_finite():
		target = value

func tick(delta: float) -> Vector2:
	var dt: float = clampf(delta, 0.0, 0.1)
	match mode:
		"jump":
			_age += dt
			var u: float = clampf(_age / _duration, 0.0, 1.0)
			var eased: float = smoothstep(0.0, 1.0, u)
			position = _start.lerp(target, eased)
			position.y -= sin(PI * u) * _arc_px
			if u >= 1.0:
				position = target
				mode = "land"
				_landing_time = 0.0
		"fall":
			_age += dt
			var u: float = clampf(_age / _duration, 0.0, 1.0)
			var x_u: float = smoothstep(0.0, 1.0, u)
			var y_u: float = u * u
			position.x = lerpf(_start.x, target.x, x_u)
			position.y = lerpf(_start.y, target.y, y_u)
			if u >= 1.0:
				position = target
				mode = "land"
				_landing_time = 0.0
		"land":
			_landing_time += dt
			position = target
			if _landing_time >= 0.34:
				mode = "idle"
	return position
