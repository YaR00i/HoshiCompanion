extends RefCounted
const WalkStyle = preload("res://scripts/walk_style.gd")
## Screen-space path + distance-driven footsteps. No DisplayServer or scene access.
## Stride, speed, foot lift and heel-toe roll come from WalkStyle (walk workshop).
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
var _settle_pitch: Array[float] = [0.0, 0.0]
const SETTLE_TIME: float = 0.62
## Heel-toe roll (radians), taken from WalkStyle when a walk starts. Positive pitch =
## heel up / toes down (push-off, rolling over the ball of the foot); negative = toes up
## (heel strike, rolling over the heel).
var push_off_pitch: float = deg_to_rad(22.0)
var heel_strike_pitch: float = deg_to_rad(12.0)
var foot_lift: float = 0.038
var leg_kick: float = 0.0
var kick_height: float = 0.025
var back_hold: float = 0.0
var rear_release: float = 0.18

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
	# The heel-toe roll lengthens the leg at both ends of the stride, so steps can be
	# longer (and calmer in cadence) than with flat feet.
	var style = WalkStyle.active()
	push_off_pitch = deg_to_rad(style.push_off)
	heel_strike_pitch = deg_to_rad(style.heel_strike)
	foot_lift = style.foot_lift
	leg_kick = style.leg_kick
	kick_height = style.kick_height
	back_hold = style.back_hold
	rear_release = style.rear_release
	# Even rhythm: a short first step from standing, equal steps, then a short closing
	# step that brings the feet together. distance = (steps - 1) * step_length, and the
	# stride is stretched/shrunk a little so the steps divide the route evenly.
	step_count = maxi(2, int(round(distance_m / (height_m * style.step_length))) + 1)
	step_length = distance_m / float(step_count - 1)
	_speed = height_m * (style.speed + (0.05 if playful else 0.0))
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
		_settle_pitch = [float(frame["pitch_left"]), float(frame["pitch_right"])]
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

## Where the foot that swings in step `index` lands. Every foot moves one full stride
## (two step lengths) except the first step from standing and the closing step (one).
## The final two landings put BOTH feet under the destination.
func _landing(index: int) -> float:
	if index < 0:
		return 0.0
	if index >= step_count - 2:
		return distance_m
	return float(index + 1) * step_length

## Pelvis travel at the start of step `index`. At each heel strike the pelvis is half a
## step behind the landing foot; the first and last steps carry the body half a step.
func _boundary(index: int) -> float:
	if index <= 0:
		return 0.0
	if index >= step_count:
		return distance_m
	return (float(index) - 0.5) * step_length

func sample() -> Dictionary:
	var result: Dictionary = {"left": Vector3.ZERO, "right": Vector3.ZERO,
		"weight": 0.0, "phase": 0.0, "step": 0, "u": 0.0,
		"stance_left": true, "stance_right": true, "distance": travelled_m, "mode": mode,
		"pitch_left": 0.0, "pitch_right": 0.0, "kick": 0.0,
		"ground_left": 1.0, "ground_right": 1.0, "land_weight": 0.0, "land_side": 0,
		"land_offset": Vector3.ZERO, "land_pitch": 0.0}
	if mode == "settle":
		var total: float = clampf(_elapsed / SETTLE_TIME, 0.0, 1.0)
		for side in range(2):
			var is_first: bool = side == _settle_first
			var u: float = clampf(total * 2.0 - (0.0 if is_first else 1.0), 0.0, 1.0)
			var point: Vector3 = _settle_feet[side].lerp(Vector3.ZERO, _ease(u))
			point.y += height_m * 0.018 * pow(sin(PI * u), 2.0)
			result["left" if side == 0 else "right"] = point
			result["pitch_left" if side == 0 else "pitch_right"] = _settle_pitch[side] * (1.0 - _ease(u))
		result["weight"] = _settle_weight * (1.0 - _ease(total))
		result["phase"] = _settle_phase
		result["stance_left"] = false
		result["stance_right"] = false
		return result
	if mode != "walk" or step_count == 0:
		return result
	var index: int = clampi(int(floor(travelled_m / step_length + 0.5)), 0, step_count - 1)
	var u: float = clampf((travelled_m - _boundary(index)) / maxf(_boundary(index + 1) - _boundary(index), 0.0001), 0.0, 1.0)
	# Short double-support periods at either end. With back_hold the back foot stays on
	# its toes longer and then swings through faster. Swing has zero end velocity.
	var swing_start: float = 0.08 + back_hold
	var swing_u: float = clampf((u - swing_start) / (0.92 - swing_start), 0.0, 1.0)
	# The first step (from standing) and the closing step are short and plain.
	var full_stride: bool = index > 0 and index < step_count - 1
	var path: Vector2 = _swing_path(_landing(index - 2), _landing(index), swing_u, full_stride)
	var swing_z: float = path.x
	var lift: float = path.y
	var swinging: Vector3 = Vector3(0.0, lift, swing_z - travelled_m)
	var standing: Vector3 = Vector3(0.0, 0.0, _landing(index - 1) - travelled_m)
	var left_swings: bool = index % 2 == 0
	result["left"] = swinging if left_swings else standing
	result["right"] = standing if left_swings else swinging
	# How much each leg holds the pelvis height (gait_driver). It hands over smoothly:
	# the back leg lets go while its toes leave the floor, the front leg takes the weight
	# while it comes down, so the body lowers WITH the landing foot and never pops.
	var let_go: float = 1.0 - smoothstep(maxf(0.0, swing_start - rear_release), swing_start + 0.08, u)
	result["ground_left"] = let_go if left_swings else 1.0
	result["ground_right"] = 1.0 if left_swings else let_go
	# The landing spot is known in advance: from mid-swing the pelvis eases down to the
	# height the front leg will need at touch-down (relative to where the pelvis will be
	# then), instead of diving after the foot's path through the air.
	result["land_weight"] = smoothstep(0.35, 0.92, u)
	result["land_side"] = 0 if left_swings else 1
	result["land_offset"] = Vector3(0.0, 0.0, _landing(index) - _boundary(index + 1))
	result["stance_left"] = not left_swings or swing_u <= 0.0 or swing_u >= 1.0
	result["stance_right"] = left_swings or swing_u <= 0.0 or swing_u >= 1.0
	result["phase"] = PI * (float(index) + u)
	result["step"] = index
	result["u"] = u
	var weight: float = minf(smoothstep(0.0, _ramp, _elapsed), smoothstep(0.0, _ramp, _duration - _elapsed))
	result["weight"] = weight
	# Heel-toe roll. Swinging foot: still pushing off on its toes, flattens in the air,
	# lifts the toes just before the heel strikes. Standing foot: rolls down from the
	# heel after landing, flat in mid-stance, heel rises for the next push-off.
	# The very first and last steps (start/stop, both feet under the body) stay flatter.
	# Toes come up as the leg reaches forward and stay up until the heel strikes.
	var reach_t: float = _reach_time(full_stride)
	var swing_pitch: float = push_off_pitch * (1.0 - smoothstep(0.0, 0.45, swing_u)) - heel_strike_pitch * smoothstep(reach_t - 0.3, reach_t, swing_u)
	var stance_pitch: float = -heel_strike_pitch * (1.0 - smoothstep(0.0, 0.2, u)) + push_off_pitch * smoothstep(0.6, 1.0, u)
	if index == 0:
		swing_pitch = -heel_strike_pitch * smoothstep(reach_t - 0.3, reach_t, swing_u)
		# Nothing landed on the heel before the first step.
		stance_pitch = push_off_pitch * smoothstep(0.6, 1.0, u)
	if index >= step_count - 1:
		# Final step closes the feet side by side: land flat, no new push-off.
		swing_pitch *= 1.0 - smoothstep(0.5, 1.0, swing_u)
		stance_pitch = -heel_strike_pitch * (1.0 - smoothstep(0.0, 0.2, u)) if index > 0 else 0.0
	# How much the swinging leg is thrown forward right now (0..1, peaks at the reach);
	# the upper body leans into it (WalkStyle.kick_lean).
	result["kick"] = (sin(PI * clampf((swing_u - (reach_t - 0.4)) / 0.55, 0.0, 1.0)) ** 2) * weight if full_stride else 0.0
	result["land_pitch"] = -heel_strike_pitch * weight if index < step_count - 1 else 0.0
	result["pitch_left"] = (swing_pitch if left_swings else stance_pitch) * weight
	result["pitch_right"] = (stance_pitch if left_swings else swing_pitch) * weight
	return result

## Swing phases, like an animator's keys:
##   lift-off -> pass (knee bent, highest, t=0.38) -> reach (leg straight, foot forward
##   in the air past the landing spot) -> plant (heel comes down and back onto the spot).
## Returns (z along the route, height above the floor). A bigger leg_kick reaches
## further, earlier and (with kick_height) higher.
func _swing_path(from_z: float, to_z: float, t: float, full_stride: bool) -> Vector2:
	var kick_n: float = clampf(leg_kick / 0.06, 0.0, 1.0) if full_stride else 0.0
	var t_pass: float = 0.38
	var t_reach: float = _reach_time(full_stride)
	# A real foot always overshoots a little and pulls back onto the heel.
	var over: float = height_m * ((0.008 + leg_kick) if full_stride else 0.004)
	var y_pass: float = height_m * foot_lift * (1.0 if full_stride else 0.75)
	var y_reach: float = height_m * lerpf(0.006, kick_height, kick_n)
	var z: float
	if t <= t_reach:
		z = lerpf(from_z, to_z + over, _ease(t / t_reach))
	else:
		z = lerpf(to_z + over, to_z, smoothstep(0.0, 1.0, (t - t_reach) / (1.0 - t_reach)))
	var down: float = -y_reach / maxf(1.0 - t_reach, 0.05)
	var y: float
	if t <= t_pass:
		y = _hermite(t, 0.0, t_pass, 0.0, y_pass, 0.0, 0.0)
	elif t <= t_reach:
		y = _hermite(t, t_pass, t_reach, y_pass, y_reach, 0.0, down * 0.6)
	else:
		y = _hermite(t, t_reach, 1.0, y_reach, 0.0, down * 0.6, down * 0.5)
	return Vector2(z, maxf(0.0, y))

func _reach_time(full_stride: bool) -> float:
	return lerpf(0.86, 0.68, clampf(leg_kick / 0.06, 0.0, 1.0)) if full_stride else 0.86

static func _hermite(t: float, t0: float, t1: float, p0: float, p1: float, m0: float, m1: float) -> float:
	var span: float = maxf(t1 - t0, 0.0001)
	var s: float = clampf((t - t0) / span, 0.0, 1.0)
	var s2: float = s * s
	var s3: float = s2 * s
	return (2.0 * s3 - 3.0 * s2 + 1.0) * p0 + (s3 - 2.0 * s2 + s) * span * m0 + (-2.0 * s3 + 3.0 * s2) * p1 + (s3 - s2) * span * m1

func label() -> String:
	match mode:
		"turn_out": return "Собирается пройтись"
		"walk": return "Гуляет по нижнему краю"
		"settle": return "Заканчивает шаг"
		"turn_in": return "Останавливается рядом"
	return ""
