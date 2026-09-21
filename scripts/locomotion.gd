extends RefCounted
## Screen-space path + distance-driven footsteps. No DisplayServer or scene access.
## Positive model Z is forward (VRM 1.0). A +/-90 degree turn maps it to screen X.
## During stance each foot keeps a CONSTANT world-Z; translation is subtracted
## from its local target. This is not a timer-only walk cycle sliding over a path.

var mode: String = "idle"
var x_px: float = 0.0
var yaw: float = 0.0
var direction: int = 1
var distance_m: float = 0.0
var travelled_m: float = 0.0
var step_count: int = 0
var step_length: float = 0.0
var height_m: float = 1.5
var meters_per_pixel: float = 0.004
var _origin_px: float = 0.0
var _target_px: float = 0.0
var _elapsed: float = 0.0
var _duration: float = 1.0
var _ramp: float = 0.32
var _speed: float = 0.3
var _turn_from: float = 0.0
var _turn_to: float = 0.0
var _turn_duration: float = 0.50
var _return_yaw: float = 0.0
var _settle_feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _settle_first: int = 0
var _settle_weight: float = 0.0
var _settle_phase: float = 0.0
const SETTLE_TIME: float = 0.62

func active() -> bool:
	return mode != "idle"

func request(start_x: float, target_x: float, lane: Vector2, mpp: float, avatar_height: float, start_yaw: float, playful: bool = false) -> bool:
	if active() or not is_finite(start_x) or not is_finite(target_x):
		return false
	if lane.y <= lane.x or mpp <= 0.0 or avatar_height <= 0.1:
		return false
	var goal: float = clampf(target_x, lane.x, lane.y)
	var span: float = absf(goal - start_x)
	if span * mpp < avatar_height * 0.12:
		return false
	_origin_px = start_x
	_target_px = goal
	x_px = start_x
	direction = 1 if goal > start_x else -1
	height_m = avatar_height
	meters_per_pixel = mpp
	distance_m = span * mpp
	travelled_m = 0.0
	# Short steps limit the IK reach and suit this small companion's proportions.
	step_count = maxi(2, int(ceil(distance_m / (height_m * 0.11))))
	step_length = distance_m / float(step_count)
	_speed = height_m * (0.26 if playful else 0.21)
	_ramp = minf(0.38, distance_m / _speed * 0.30)
	_duration = distance_m / _speed + _ramp
	_return_yaw = 0.0
	yaw = start_yaw
	_begin_turn("turn_out", float(direction) * 90.0)
	return true

func reset(current_x: float = 0.0, current_yaw: float = 0.0) -> void:
	mode = "idle"
	x_px = current_x
	yaw = current_yaw
	travelled_m = 0.0
	distance_m = 0.0
	step_count = 0
	_elapsed = 0.0

func stop(keep_facing: bool = false) -> void:
	if not active():
		return
	if mode == "settle" or mode == "turn_in":
		if keep_facing:
			_return_yaw = yaw
		return
	_return_yaw = yaw if keep_facing else 0.0
	if mode == "walk":
		var frame: Dictionary = sample()
		_settle_feet = [frame["left"], frame["right"]]
		_settle_first = int(frame["step"]) % 2
		_settle_weight = float(frame["weight"])
		_settle_phase = float(frame["phase"])
		mode = "settle"
		_elapsed = 0.0
	else:
		_begin_turn("turn_in", _return_yaw)

func _begin_turn(next_mode: String, target_degrees: float) -> void:
	mode = next_mode
	_elapsed = 0.0
	_turn_from = deg_to_rad(yaw)
	_turn_to = deg_to_rad(target_degrees)
	_turn_duration = maxf(0.28, absf(wrapf(_turn_to - _turn_from, -PI, PI)) / PI * 0.95)

func tick(delta: float) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	_elapsed += dt
	match mode:
		"turn_out", "turn_in":
			var fraction: float = clampf(_elapsed / _turn_duration, 0.0, 1.0)
			yaw = rad_to_deg(lerp_angle(_turn_from, _turn_to, smoothstep(0.0, 1.0, fraction)))
			if fraction >= 1.0:
				if mode == "turn_out":
					mode = "walk"
					_elapsed = 0.0
				else:
					mode = "idle"
					yaw = rad_to_deg(_turn_to)
		"walk":
			travelled_m = _distance_at(_elapsed)
			x_px = _origin_px + float(direction) * travelled_m / meters_per_pixel
			if _elapsed >= _duration:
				travelled_m = distance_m
				x_px = _target_px
				_begin_turn("turn_in", _return_yaw)
		"settle":
			if _elapsed >= SETTLE_TIME:
				_begin_turn("turn_in", _return_yaw)

func _distance_at(t: float) -> float:
	# Raised-cosine acceleration / deceleration, constant cruise in the middle.
	if t <= 0.0:
		return 0.0
	if t >= _duration:
		return distance_m
	if t < _ramp:
		return _speed * 0.5 * (t - _ramp / PI * sin(PI * t / _ramp))
	if t > _duration - _ramp:
		var left: float = _duration - t
		return distance_m - _speed * 0.5 * (left - _ramp / PI * sin(PI * left / _ramp))
	return _speed * (t - _ramp * 0.5)

static func _ease(value: float) -> float:
	var u: float = clampf(value, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)

func _landing(index: int) -> float:
	if index < 0:
		return 0.0
	# Final two landings put BOTH feet under the destination, not mid-stride.
	if index >= step_count - 2:
		return distance_m
	return (float(index) + 1.5) * step_length

func sample() -> Dictionary:
	var result: Dictionary = {"left": Vector3.ZERO, "right": Vector3.ZERO,
		"weight": 0.0, "phase": 0.0, "step": 0, "u": 0.0,
		"stance_left": true, "stance_right": true, "distance": travelled_m, "mode": mode}
	if mode == "settle":
		var total: float = clampf(_elapsed / SETTLE_TIME, 0.0, 1.0)
		for side in range(2):
			var is_first: bool = side == _settle_first
			var u: float = clampf(total * 2.0 - (0.0 if is_first else 1.0), 0.0, 1.0)
			var point: Vector3 = _settle_feet[side].lerp(Vector3.ZERO, _ease(u))
			point.y += height_m * 0.018 * pow(sin(PI * u), 2.0)
			result["left" if side == 0 else "right"] = point
		result["weight"] = _settle_weight * (1.0 - _ease(total))
		result["phase"] = _settle_phase
		result["stance_left"] = false
		result["stance_right"] = false
		return result
	if mode != "walk" or step_count == 0:
		return result
	var index: int = mini(step_count - 1, int(floor(travelled_m / step_length)))
	var u: float = clampf((travelled_m - float(index) * step_length) / step_length, 0.0, 1.0)
	# Short double-support periods at either end. Swing has zero end velocity.
	var swing_u: float = clampf((u - 0.08) / 0.84, 0.0, 1.0)
	var swing_z: float = lerpf(_landing(index - 2), _landing(index), _ease(swing_u))
	var lift: float = height_m * 0.033 * pow(sin(PI * swing_u), 2.0)
	var swinging: Vector3 = Vector3(0.0, lift, swing_z - travelled_m)
	var standing: Vector3 = Vector3(0.0, 0.0, _landing(index - 1) - travelled_m)
	var left_swings: bool = index % 2 == 0
	result["left"] = swinging if left_swings else standing
	result["right"] = standing if left_swings else swinging
	result["stance_left"] = not left_swings or swing_u <= 0.0 or swing_u >= 1.0
	result["stance_right"] = left_swings or swing_u <= 0.0 or swing_u >= 1.0
	result["phase"] = PI * (float(index) + u)
	result["step"] = index
	result["u"] = u
	result["weight"] = minf(smoothstep(0.0, _ramp, _elapsed), smoothstep(0.0, _ramp, _duration - _elapsed))
	return result

func label() -> String:
	match mode:
		"turn_out": return "Собирается пройтись"
		"walk": return "Гуляет по нижнему краю"
		"settle": return "Заканчивает шаг"
		"turn_in": return "Останавливается рядом"
	return ""
