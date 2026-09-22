extends RefCounted
## Context-only overlay poses: carry, jump, fall, landing and portal steps.
## Adds rotations on top of the normal rig; never edits REST transforms or skin binds.
var rig
var skeleton: Skeleton3D
var available: bool = false
var pose_mode: String = "idle"
var requested: String = "idle"
var weight: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var progress: float = -1.0
var impact: float = 0.5
var height_m: float = 1.5
var mode_age: float = 0.0
var _carry_lag: Vector2 = Vector2.ZERO

func setup(rig_driver, model_height: float) -> Dictionary:
	rig = rig_driver
	skeleton = rig.skeleton
	height_m = model_height
	available = skeleton != null and rig.bones.has("hips")
	return {"available": available}

func tick(delta: float, value: String, screen_velocity: Vector2 = Vector2.ZERO, normalized_progress: float = -1.0, impact_strength: float = 0.5) -> void:
	if not available:
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	requested = value if value in ["idle", "carry", "jump", "fall", "land", "portal", "side_left", "side_right"] else "idle"
	if requested != "idle" and requested != pose_mode:
		pose_mode = requested
		mode_age = 0.0
		# Landing should read immediately at contact instead of fading in from zero.
		if requested == "land":
			weight = maxf(weight, 0.72)
		else:
			weight = minf(weight, 0.30)
	if requested != "idle":
		mode_age += dt
	var goal: float = 0.0 if requested == "idle" else 1.0
	weight = lerpf(weight, goal, 1.0 - exp(-dt * (11.0 if goal > weight else 7.0)))
	if requested == "idle" and weight < 0.002:
		pose_mode = "idle"
		weight = 0.0
		mode_age = 0.0
	progress = normalized_progress
	impact = clampf(impact_strength, 0.0, 1.4)
	velocity = velocity.lerp(screen_velocity, 1.0 - exp(-dt * 11.0))
	var normalized_velocity := Vector2(
		clampf(screen_velocity.x / 900.0, -1.25, 1.25),
		clampf(screen_velocity.y / 900.0, -1.25, 1.25)
	)
	if requested == "carry":
		# Deliberately slower than the hand/cursor: this residual lag is the
		# little pendulum motion that remains when the user changes direction.
		_carry_lag = _carry_lag.lerp(normalized_velocity, 1.0 - exp(-dt * 4.8))
	else:
		_carry_lag = _carry_lag.lerp(Vector2.ZERO, 1.0 - exp(-dt * 6.0))

func phase_progress() -> float:
	if progress >= 0.0:
		return clampf(progress, 0.0, 1.0)
	match pose_mode:
		"jump":
			return clampf(mode_age / 0.68, 0.0, 1.0)
		"fall":
			return clampf(mode_age / 0.70, 0.0, 1.0)
		"land":
			return clampf(mode_age / 0.34, 0.0, 1.0)
	return 0.0

func phase_label() -> String:
	var u: float = phase_progress()
	match pose_mode:
		"jump":
			if u < 0.18: return "anticipation"
			if u < 0.36: return "takeoff"
			if u < 0.72: return "flight"
			return "prepare_land"
		"fall":
			if u < 0.28: return "react"
			if u < 0.76: return "tuck"
			return "brace"
		"land":
			return "compress" if u < 0.52 else "recover"
	return pose_mode

func apply(time: float) -> void:
	if not available or pose_mode == "idle" or weight <= 0.001:
		return
	var w: float = weight
	var sx: float = clampf(velocity.x / 900.0, -1.2, 1.2)
	var sy: float = clampf(velocity.y / 900.0, -1.2, 1.2)
	var u: float = phase_progress()
	match pose_mode:
		"carry":
			var lag_x: float = clampf(_carry_lag.x, -1.2, 1.2)
			var lag_y: float = clampf(_carry_lag.y, -1.2, 1.2)
			var direction_change: float = clampf((sx - lag_x) * 2.1, -1.2, 1.2)
			var speed: float = clampf(Vector2(sx, sy).length(), 0.0, 1.25)
			var pendulum: float = sin(time * 2.8) * (2.0 + speed * 2.0) + lag_x * 6.0 + direction_change * 5.0
			_add("hips", Vector3(5.0 + lag_y * 3.0, 0.0, pendulum * 0.42) * w)
			_add("spine", Vector3(-7.0 - lag_y * 3.5, 0.0, pendulum) * w)
			_add("chest", Vector3(-4.0 - speed * 1.5, 0.0, -pendulum * 0.55) * w)
			_add("neck", Vector3(4.0 + sy * 2.0, -sx * 2.5, -pendulum * 0.32) * w)
			_add("head", Vector3(6.0 + sy * 3.0, -sx * 3.5, -pendulum * 0.55) * w)
			_add("leftUpperArm", Vector3(6.0 + speed * 4.0, 0.0, -5.0 - speed * 4.0 - pendulum * 0.22) * w)
			_add("rightUpperArm", Vector3(6.0 + speed * 4.0, 0.0, 5.0 + speed * 4.0 - pendulum * 0.22) * w)
			_add("leftLowerArm", Vector3(-6.0, 0.0, -7.0 - speed * 2.0) * w)
			_add("rightLowerArm", Vector3(-6.0, 0.0, 7.0 + speed * 2.0) * w)
			_dangle_legs(time, w, 0.85 + speed * 0.35)
		"jump":
			var anticipation: float = 1.0 - smoothstep(0.04, 0.19, u)
			var takeoff: float = smoothstep(0.08, 0.24, u) * (1.0 - smoothstep(0.34, 0.50, u))
			var flight: float = smoothstep(0.20, 0.38, u) * (1.0 - smoothstep(0.70, 0.92, u))
			var prepare: float = smoothstep(0.68, 0.98, u)
			var sway: float = sin(time * 7.0) * 1.2 * flight + sx * 2.0
			_add("hips", Vector3(4.5 * anticipation - 2.0 * takeoff + 2.0 * prepare, 0.0, sway * 0.35) * w)
			_add("spine", Vector3(9.0 * anticipation - 8.0 * flight + 5.0 * prepare, 0.0, sway) * w)
			_add("chest", Vector3(5.5 * anticipation - 4.5 * flight + 3.0 * prepare, 0.0, -sway * 0.7) * w)
			_add("neck", Vector3(2.0 * anticipation + 2.5 * prepare, -sx * 1.5, 0.0) * w)
			_add("head", Vector3(4.0 * anticipation - 1.5 * flight + 4.0 * prepare, -sx * 2.0, -sway * 0.3) * w)
			var arm_back: float = 8.0 * anticipation + 13.0 * takeoff + 9.0 * flight
			var arm_open: float = 5.0 * anticipation + 12.0 * flight + 10.0 * prepare
			_add("leftUpperArm", Vector3(arm_back, 0.0, -arm_open) * w)
			_add("rightUpperArm", Vector3(arm_back, 0.0, arm_open) * w)
			var leg_tuck: float = 18.0 * anticipation + 29.0 * takeoff + 27.0 * flight + 18.0 * prepare
			var knee: float = -27.0 * anticipation - 45.0 * takeoff - 43.0 * flight - 30.0 * prepare
			_add("leftUpperLeg", Vector3(leg_tuck, 0.0, -2.0) * w)
			_add("rightUpperLeg", Vector3(leg_tuck, 0.0, 2.0) * w)
			_add("leftLowerLeg", Vector3(knee, 0.0, 0.0) * w)
			_add("rightLowerLeg", Vector3(knee, 0.0, 0.0) * w)
		"fall":
			var severity: float = clampf(impact, 0.45, 1.25)
			var react: float = 1.0 - smoothstep(0.16, 0.48, u)
			var tuck: float = smoothstep(0.18, 0.76, u)
			var brace: float = smoothstep(0.68, 0.98, u)
			_add("hips", Vector3((2.0 + severity * 2.0) * tuck, 0.0, sx * 2.0) * w)
			_add("spine", Vector3(-3.0 * react + (5.0 + severity * 5.0) * tuck, 0.0, sx * 5.0) * w)
			_add("chest", Vector3(-2.0 * react + (3.0 + severity * 3.0) * tuck, 0.0, -sx * 3.0) * w)
			_add("neck", Vector3(2.0 * tuck + 3.0 * brace, -sx * 2.0, 0.0) * w)
			_add("head", Vector3(3.0 * tuck + 4.0 * brace, -sx * 2.8, 0.0) * w)
			var spread: float = 17.0 * react + 8.0 * brace
			_add("leftUpperArm", Vector3(-7.0 * react + 5.0 * brace, 0.0, -spread) * w)
			_add("rightUpperArm", Vector3(-7.0 * react + 5.0 * brace, 0.0, spread) * w)
			var thigh: float = (11.0 + severity * 17.0) * tuck + 9.0 * brace
			var shin: float = -(21.0 + severity * 24.0) * tuck - 18.0 * brace
			_add("leftUpperLeg", Vector3(thigh, 0.0, -2.0) * w)
			_add("rightUpperLeg", Vector3(thigh, 0.0, 2.0) * w)
			_add("leftLowerLeg", Vector3(shin, 0.0, 0.0) * w)
			_add("rightLowerLeg", Vector3(shin, 0.0, 0.0) * w)
		"land":
			var severity: float = clampf(impact, 0.35, 1.25)
			var compress: float = 1.0 - smoothstep(0.16, 0.72, u)
			var rebound: float = smoothstep(0.46, 0.66, u) * (1.0 - smoothstep(0.72, 1.0, u))
			_add("hips", Vector3((5.0 + severity * 5.0) * compress - 1.5 * rebound, 0.0, sx * 1.5) * w)
			_add("spine", Vector3((13.0 + severity * 8.0) * compress - 3.5 * rebound, 0.0, sx * 3.0) * w)
			_add("chest", Vector3((8.0 + severity * 5.0) * compress - 2.0 * rebound, 0.0, -sx * 2.0) * w)
			_add("neck", Vector3(4.0 * compress - 1.0 * rebound, 0.0, 0.0) * w)
			_add("head", Vector3(5.0 * compress - 1.5 * rebound, 0.0, 0.0) * w)
			var arm_open: float = (10.0 + severity * 5.0) * compress
			_add("leftUpperArm", Vector3(4.0 * compress, 0.0, -arm_open) * w)
			_add("rightUpperArm", Vector3(4.0 * compress, 0.0, arm_open) * w)
			var thigh: float = (23.0 + severity * 14.0) * compress
			var shin: float = -(35.0 + severity * 16.0) * compress
			_add("leftUpperLeg", Vector3(thigh, 0.0, 0.0) * w)
			_add("rightUpperLeg", Vector3(thigh, 0.0, 0.0) * w)
			_add("leftLowerLeg", Vector3(shin, 0.0, 0.0) * w)
			_add("rightLowerLeg", Vector3(shin, 0.0, 0.0) * w)
		"portal":
			var step: float = sin(time * 5.0) * 4.0
			_add("spine", Vector3(-3.0, 0.0, step * 0.3) * w)
			_add("leftUpperArm", Vector3(step, 0.0, -3.0) * w)
			_add("rightUpperArm", Vector3(-step, 0.0, 3.0) * w)
			_add("leftUpperLeg", Vector3(maxf(0.0, step) * 0.5, 0.0, 0.0) * w)
			_add("rightUpperLeg", Vector3(maxf(0.0, -step) * 0.5, 0.0, 0.0) * w)
		"side_left":
			var breathe_left: float = sin(time * 1.4) * 0.8
			_add("hips", Vector3(0.0, 0.0, 3.0) * w)
			_add("spine", Vector3(-2.0, 2.0, 6.0 + breathe_left) * w)
			_add("chest", Vector3(-1.0, 3.0, 5.0) * w)
			_add("neck", Vector3(1.0, -4.0, -3.0) * w)
			_add("head", Vector3(2.0, -6.0, -4.0) * w)
			_add("leftUpperArm", Vector3(-7.0, 0.0, 35.0) * w)
			_add("leftLowerArm", Vector3(-8.0, 0.0, -28.0) * w)
			_add("leftHand", Vector3(0.0, 0.0, -12.0) * w)
		"side_right":
			var breathe_right: float = sin(time * 1.4) * 0.8
			_add("hips", Vector3(0.0, 0.0, -3.0) * w)
			_add("spine", Vector3(-2.0, -2.0, -6.0 - breathe_right) * w)
			_add("chest", Vector3(-1.0, -3.0, -5.0) * w)
			_add("neck", Vector3(1.0, 4.0, 3.0) * w)
			_add("head", Vector3(2.0, 6.0, 4.0) * w)
			_add("rightUpperArm", Vector3(-7.0, 0.0, -35.0) * w)
			_add("rightLowerArm", Vector3(-8.0, 0.0, 28.0) * w)
			_add("rightHand", Vector3(0.0, 0.0, 12.0) * w)

func _dangle_legs(time: float, w: float, amount: float) -> void:
	var swing: float = sin(time * 2.7) * 5.0 * amount
	_add("leftUpperLeg", Vector3(13.0 + swing, 0.0, -2.0) * w)
	_add("rightUpperLeg", Vector3(13.0 - swing, 0.0, 2.0) * w)
	_add("leftLowerLeg", Vector3(-28.0 - swing * 0.5, 0.0, 0.0) * w)
	_add("rightLowerLeg", Vector3(-28.0 + swing * 0.5, 0.0, 0.0) * w)
	_add("leftFoot", Vector3(9.0 + swing * 0.15, 0.0, 0.0) * w)
	_add("rightFoot", Vector3(9.0 - swing * 0.15, 0.0, 0.0) * w)

func _add(semantic: String, degrees: Vector3) -> void:
	if not rig.bones.has(semantic):
		return
	var bone: int = int(rig.bones[semantic])
	if not rig.parent_rest_rotations.has(bone):
		return
	var parent_q: Quaternion = rig.parent_rest_rotations[bone]
	var extra: Quaternion = parent_q.inverse() * Quaternion.from_euler(degrees * (PI / 180.0)) * parent_q
	skeleton.set_bone_pose_rotation(bone, (extra * skeleton.get_bone_pose_rotation(bone)).normalized())
