extends RefCounted
const LifeStyle = preload("res://scripts/life_style.gd")
## Context-only overlay poses: carry, cursor grip, jump, fall, landing and portal steps.
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
var facing_yaw: float = 0.0
var _thigh_m: float = 0.0
## When the overlay changes (jump -> land, fall -> land, carry -> fall...) the old pose
## fades out while the new one fades in, so there is never a one-frame snap.
const SWITCH_TIME: float = 0.14
## Landing: absorb the impact into a squat (on the haunches), a short hold, then a careful rise.
const LAND_TIME: float = 0.85
var _prev_mode: String = ""
var _prev_u: float = 1.0
var _switch_age: float = 1.0
var _shin_m: float = 0.0

func setup(rig_driver, model_height: float) -> Dictionary:
	rig = rig_driver
	skeleton = rig.skeleton
	height_m = model_height
	available = skeleton != null and rig.bones.has("hips")
	if available and rig.bones.has("leftUpperLeg") and rig.bones.has("leftLowerLeg") and rig.bones.has("leftFoot"):
		var hip: Vector3 = skeleton.get_bone_global_rest(int(rig.bones["leftUpperLeg"])).origin
		var knee: Vector3 = skeleton.get_bone_global_rest(int(rig.bones["leftLowerLeg"])).origin
		var ankle: Vector3 = skeleton.get_bone_global_rest(int(rig.bones["leftFoot"])).origin
		_thigh_m = hip.distance_to(knee)
		_shin_m = knee.distance_to(ankle)
	return {"available": available}

func tick(delta: float, value: String, screen_velocity: Vector2 = Vector2.ZERO, normalized_progress: float = -1.0, impact_strength: float = 0.5, yaw_degrees: float = 0.0) -> void:
	if not available:
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	facing_yaw = yaw_degrees
	requested = value if value in ["idle", "carry", "cursor_hang", "jump", "fall", "land", "portal", "side_left", "side_right"] else "idle"
	if requested != "idle" and requested != pose_mode:
		if pose_mode != "idle" and weight > 0.01 and requested != "cursor_hang":
			_prev_mode = pose_mode
			_prev_u = phase_progress()
			_switch_age = 0.0
		else:
			_prev_mode = ""
		pose_mode = requested
		mode_age = 0.0
		# Landing should read immediately at contact instead of fading in from zero.
		if requested == "land":
			weight = maxf(weight, 0.72)
		elif requested == "cursor_hang":
			weight = 0.0
		elif _prev_mode.is_empty():
			weight = minf(weight, 0.30)
	_switch_age += dt
	if requested != "idle":
		mode_age += dt
	var goal: float = clampf(normalized_progress, 0.0, 1.0) if requested == "cursor_hang" else (0.0 if requested == "idle" else 1.0)
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
	if requested in ["carry", "cursor_hang"]:
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
			return clampf(mode_age / LAND_TIME, 0.0, 1.0)
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
			return "compress" if u < 0.50 else "recover"
	return pose_mode

func apply(time: float) -> void:
	if not available or pose_mode == "idle" or weight <= 0.001:
		return
	var w: float = weight
	var sx: float = clampf(velocity.x / 900.0, -1.2, 1.2)
	var sy: float = clampf(velocity.y / 900.0, -1.2, 1.2)
	var u: float = phase_progress()
	var blend: float = smoothstep(0.0, SWITCH_TIME, _switch_age) if not _prev_mode.is_empty() else 1.0
	# Feet on the ground: remember where they stand before the overlay bends the legs.
	# Touch-down is instant: while a fall/jump overlay fades into the landing, the feet
	# are already on the floor, so the landing's grounding applies in full.
	var planted: float = _planted(pose_mode, u)
	if blend < 1.0:
		planted = maxf(planted, _planted(_prev_mode, _prev_u) * (1.0 - blend))
	var feet_before: Vector3 = _feet_point() if planted > 0.001 else Vector3.ZERO
	if blend < 1.0:
		_apply_mode(_prev_mode, _prev_u, w * (1.0 - blend), time, sx, sy)
	_apply_mode(pose_mode, u, w * blend, time, sx, sy)
	if planted > 0.001:
		# Measure, don't guess: move the pelvis by exactly how far the feet moved, so the
		# hips go down into the squat while the shoes stay on the floor. This also covers
		# leftovers of other overlays (fall, carry) still fading out underneath.
		var shift: Vector3 = feet_before - _feet_point()
		_move_hips(Vector3(0.0, shift.y, shift.z) * planted)

## How much of this pose stands on the ground (1) versus hangs in the air (0).
func _planted(mode: String, u: float) -> float:
	match mode:
		"land":
			return 1.0
		"jump":
			# AirMotion keeps her on the spot for the crouch (first 20% of progress).
			return 1.0 - smoothstep(0.17, 0.24, u)
	return 0.0

func _feet_point() -> Vector3:
	var sum := Vector3.ZERO
	var count: int = 0
	for side in ["left", "right"]:
		if rig.bones.has(side + "Foot"):
			sum += skeleton.get_bone_global_pose(int(rig.bones[side + "Foot"])).origin
			count += 1
	return sum / float(maxi(count, 1))

func _move_hips(offset: Vector3) -> void:
	var hips: int = int(rig.bones["hips"])
	var parent: int = skeleton.get_bone_parent(hips)
	var parent_basis: Basis = skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + parent_basis.inverse() * offset)

func _apply_mode(mode: String, u: float, w: float, time: float, sx: float, sy: float) -> void:
	if w <= 0.0005:
		return
	match mode:
		"cursor_hang":
			var lag_x: float = clampf(_carry_lag.x, -1.2, 1.2)
			var change_x: float = clampf((sx - lag_x) * 1.8, -1.2, 1.2)
			# The hand stays under the pointer. Lean the hanging body opposite the
			# cursor so the torso lags behind the grip instead of leading it.
			var swing: float = -(sin(time * 3.0) * 1.0 + lag_x * 9.0 + change_x * 1.0)
			var kick: float = sin(time * 5.3) * 3.0
			_add("hips", Vector3(5.0 + sy * 2.0, 0.0, 0.0) * w)
			_screen_roll("hips", swing * 0.75 * w)
			_add("spine", Vector3(-5.0, 0.0, 0.0) * w)
			_screen_roll("spine", swing * w)
			_add("chest", Vector3(-4.0, 0.0, 0.0) * w)
			_screen_roll("chest", -swing * 0.35 * w)
			_add("neck", Vector3(2.0, -sx * 2.0, 0.0) * w)
			_screen_roll("neck", -swing * 0.25 * w)
			_add("head", Vector3(-3.0, -sx * 3.0, 0.0) * w)
			_screen_roll("head", -swing * 0.35 * w)
			# The elbows stay beside the head; forearms fold inward to meet the cursor.
			_add("leftUpperArm", Vector3(20.0, 0.0, 135.0) * w)
			_add("rightUpperArm", Vector3(20.0, 0.0, -135.0) * w)
			_screen_roll("leftUpperArm", -swing * 0.12 * w)
			_screen_roll("rightUpperArm", -swing * 0.12 * w)
			_add("leftLowerArm", Vector3(-5.0, 0.0, 60.0) * w)
			_add("rightLowerArm", Vector3(-5.0, 0.0, -60.0) * w)
			_add("leftHand", Vector3(0.0, 0.0, -10.0) * w)
			_add("rightHand", Vector3(0.0, 0.0, 10.0) * w)
			for side in ["left", "right"]:
				var curl_sign: float = -1.0 if side == "left" else 1.0
				for finger in ["Index", "Middle", "Ring", "Little"]:
					_add(side + finger + "Proximal", Vector3(0.0, curl_sign * 28.0, 0.0) * w)
					_add(side + finger + "Intermediate", Vector3(0.0, curl_sign * 30.0, 0.0) * w)
			_dangle_legs(time, w, 1.0)
			_add("leftUpperLeg", Vector3(-3.0 + kick, 0.0, 0.0) * w)
			_add("rightUpperLeg", Vector3(-5.0 - kick, 0.0, 0.0) * w)
			_add("leftLowerLeg", Vector3(5.0, 0.0, 0.0) * w)
			_add("rightLowerLeg", Vector3(7.0, 0.0, 0.0) * w)
		"carry":
			var lag_x: float = clampf(_carry_lag.x, -1.2, 1.2)
			var lag_y: float = clampf(_carry_lag.y, -1.2, 1.2)
			var direction_change: float = clampf((sx - lag_x) * 2.1, -1.2, 1.2)
			var speed: float = clampf(Vector2(sx, sy).length(), 0.0, 1.25)
			var pendulum: float = sin(time * 2.8) * (1.2 + speed * 0.8) + lag_x * 9.0 + direction_change * 5.0
			_add("hips", Vector3(5.0 + lag_y * 3.0, 0.0, 0.0) * w)
			_screen_roll("hips", pendulum * 0.42 * w)
			_add("spine", Vector3(-7.0 - lag_y * 3.5, 0.0, 0.0) * w)
			_screen_roll("spine", pendulum * w)
			_add("chest", Vector3(-4.0 - speed * 1.5, 0.0, 0.0) * w)
			_screen_roll("chest", -pendulum * 0.55 * w)
			_add("neck", Vector3(4.0 + sy * 2.0, -sx * 2.5, 0.0) * w)
			_screen_roll("neck", -pendulum * 0.32 * w)
			_add("head", Vector3(6.0 + sy * 3.0, -sx * 3.5, 0.0) * w)
			_screen_roll("head", -pendulum * 0.55 * w)
			_add("leftUpperArm", Vector3(6.0 + speed * 4.0, 0.0, -5.0 - speed * 4.0) * w)
			_add("rightUpperArm", Vector3(6.0 + speed * 4.0, 0.0, 5.0 + speed * 4.0) * w)
			_screen_roll("leftUpperArm", -pendulum * 0.22 * w)
			_screen_roll("rightUpperArm", -pendulum * 0.22 * w)
			_add("leftLowerArm", Vector3(-6.0, 0.0, -7.0 - speed * 2.0) * w)
			_add("rightLowerArm", Vector3(-6.0, 0.0, 7.0 + speed * 2.0) * w)
			_dangle_legs(time, w, 0.85 + speed * 0.35)
		"jump":
			# On this rig: +X on a thigh swings the knee BACK, +X on a shin folds the foot
			# back, +X on an upper arm swings it back, +Z opens the LEFT arm (-Z the right).
			# Timeline (air_motion keeps her on the ground for the first 20%):
			# crouch on the spot -> push off -> tuck in flight -> reach for the landing.
			var crouch: float = smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.17, 0.27, u))
			var push: float = smoothstep(0.14, 0.22, u) * (1.0 - smoothstep(0.26, 0.42, u))
			var flight: float = smoothstep(0.24, 0.40, u) * (1.0 - smoothstep(0.70, 0.90, u))
			var prepare: float = smoothstep(0.68, 0.96, u)
			var drift: float = sin(time * 6.0) * 0.8 * flight + sx * 2.0
			_add("hips", Vector3(0.0, 0.0, drift * 0.3) * w)
			_add("spine", Vector3(13.0 * crouch - 6.0 * push - 3.0 * flight + 4.0 * prepare, 0.0, drift) * w)
			_add("chest", Vector3(5.0 * crouch - 3.0 * push - 2.0 * flight + 2.0 * prepare, 0.0, -drift * 0.6) * w)
			# The head keeps looking where she is going while the body folds and opens.
			_add("neck", Vector3(-3.0 * crouch + 1.0 * push, -sx * 1.5, 0.0) * w)
			_add("head", Vector3(-5.0 * crouch + 2.0 * push + 1.0 * flight + 2.0 * prepare, -sx * 2.0, -drift * 0.3) * w)
			var arm_x: float = 26.0 * crouch - 48.0 * push - 22.0 * flight - 10.0 * prepare
			var arm_open: float = 4.0 * crouch + 8.0 * push + 12.0 * flight + 18.0 * prepare
			_add("leftUpperArm", Vector3(arm_x, 0.0, arm_open) * w)
			_add("rightUpperArm", Vector3(arm_x, 0.0, -arm_open) * w)
			_add("leftLowerArm", Vector3(0.0, -10.0 * flight - 6.0 * prepare, 0.0) * w)
			_add("rightLowerArm", Vector3(0.0, 10.0 * flight + 6.0 * prepare, 0.0) * w)
			_legs(36.0 * crouch * w, 22.0 * crouch * w, true)
			# In the air the knees come up (not planted); before touch-down they straighten and
			# reach for the ground, so the feet are on it when the planted landing squat starts.
			var tuck: float = 30.0 * flight + 12.0 * prepare * (1.0 - smoothstep(0.86, 1.0, u))
			_legs(tuck * w, tuck * 0.75 * w, false)
			_add("leftFoot", Vector3(-6.0 * push + 8.0 * flight, 0.0, 0.0) * w)
			_add("rightFoot", Vector3(-6.0 * push + 8.0 * flight, 0.0, 0.0) * w)
		"fall":
			var severity: float = clampf(impact, 0.45, 1.25)
			var alarm: float = clampf((severity - 0.50) / 0.35, 0.0, 1.0)
			var react: float = 1.0 - smoothstep(0.16, 0.48, u)
			var tuck: float = smoothstep(0.18, 0.76, u)
			var brace: float = smoothstep(0.68, 0.98, u)
			_add("hips", Vector3((2.0 + severity * 2.0) * tuck, 0.0, sx * 2.0) * w)
			_add("spine", Vector3((-3.0 - 7.0 * alarm) * react + (5.0 + severity * 5.0) * tuck, 0.0, sx * 5.0) * w)
			_add("chest", Vector3((-2.0 - 4.0 * alarm) * react + (3.0 + severity * 3.0) * tuck, 0.0, -sx * 3.0) * w)
			_add("neck", Vector3(2.0 * tuck + 3.0 * brace, -sx * 2.0, 0.0) * w)
			_add("head", Vector3(-8.0 * alarm * react + 3.0 * tuck + 4.0 * brace, -sx * 2.8, 0.0) * w)
			var spread: float = (9.0 + 23.0 * alarm) * react + 8.0 * brace
			_add("leftUpperArm", Vector3(-7.0 * react + 5.0 * brace, 0.0, spread) * w)
			_add("rightUpperArm", Vector3(-7.0 * react + 5.0 * brace, 0.0, -spread) * w)
			# Knees come up in front of the body (thigh -X, shin +X), then the legs reach down so
			# the feet meet the ground at contact. The landing squat (planted) absorbs the impact;
			# legs still tucked at contact would hang in the air above the floor.
			var reach_down: float = 1.0 - 0.85 * brace
			var thigh: float = (11.0 + severity * 17.0) * tuck * reach_down
			var shin: float = (21.0 + severity * 24.0) * tuck * reach_down
			_add("leftUpperLeg", Vector3(-thigh, 0.0, -2.0) * w)
			_add("rightUpperLeg", Vector3(-thigh * 0.9, 0.0, 2.0) * w)
			_add("leftLowerLeg", Vector3(shin, 0.0, 0.0) * w)
			_add("rightLowerLeg", Vector3(shin * 1.05, 0.0, 0.0) * w)
		"land":
			var severity: float = clampf(impact, 0.35, 1.25)
			var hard: float = clampf((severity - 0.35) / 0.6, 0.0, 1.0)
			# 0-26%: sink into a squat on the haunches, arms thrown forward for balance;
			# 26-46%: stay down a moment; 46-100%: rise slowly and smoothly back to standing.
			var sink: float = _ease_out(clampf(u / 0.26, 0.0, 1.0))
			var rise: float = _smoother(clampf((u - 0.46) / 0.54, 0.0, 1.0))
			var down: float = lerpf(0.18, 1.0, sink) * (1.0 - rise)
			var arms: float = _ease_out(clampf(u / 0.18, 0.0, 1.0)) * (1.0 - _smoother(clampf((u - 0.40) / 0.55, 0.0, 1.0)))
			var thigh: float = (58.0 + 14.0 * hard) * down
			# Hips go back as the knees go forward, so the chest leans in to stay over the feet.
			_legs(thigh * w, thigh * 0.55 * w, true)
			_add("spine", Vector3(20.0 * down, 0.0, sx * 3.0 * down) * w)
			_add("chest", Vector3(9.0 * down, 0.0, -sx * 2.0 * down) * w)
			# Eyes stay forward while the body folds.
			_add("neck", Vector3(-6.0 * down, 0.0, 0.0) * w)
			_add("head", Vector3(-9.0 * down, 0.0, 0.0) * w)
			var reach: float = 40.0 * arms + 6.0 * down
			var open: float = 12.0 * arms * (1.0 - 0.5 * down) + 4.0 * down
			_add("leftUpperArm", Vector3(-reach, 0.0, open) * w)
			_add("rightUpperArm", Vector3(-reach, 0.0, -open) * w)
			_add("leftLowerArm", Vector3(0.0, -14.0 * arms, 0.0) * w)
			_add("rightLowerArm", Vector3(0.0, 14.0 * arms, 0.0) * w)
			_add("leftHand", Vector3(-8.0 * arms, 0.0, 0.0) * w)
			_add("rightHand", Vector3(-8.0 * arms, 0.0, 0.0) * w)
		"portal":
			var step: float = sin(time * 5.0) * 4.0
			_add("spine", Vector3(-3.0, 0.0, step * 0.3) * w)
			_add("leftUpperArm", Vector3(step, 0.0, -3.0) * w)
			_add("rightUpperArm", Vector3(-step, 0.0, 3.0) * w)
			_add("leftUpperLeg", Vector3(maxf(0.0, step) * 0.5, 0.0, 0.0) * w)
			_add("rightUpperLeg", Vector3(maxf(0.0, -step) * 0.5, 0.0, 0.0) * w)
		"side_left":
			var breathe_left: float = sin(time * 1.4) * 0.8
			var lean_left: float = float(LifeStyle.active().lean_body)
			_add("hips", Vector3(0.0, 0.0, 3.0) * w)
			# Ноги не наклоняются вместе с тазом — ступни остаются на опоре.
			_add("leftUpperLeg", Vector3(0.0, 0.0, -3.0) * w)
			_add("rightUpperLeg", Vector3(0.0, 0.0, -3.0) * w)
			_add("spine", Vector3(-2.0, 2.0, lean_left + breathe_left) * w)
			_add("chest", Vector3(-1.0, 3.0, 5.0) * w)
			_add("neck", Vector3(1.0, -4.0, -3.0) * w)
			_add("head", Vector3(2.0, -6.0, -4.0) * w)
			_add("leftUpperArm", Vector3(-7.0, 0.0, 35.0) * w)
			_add("leftLowerArm", Vector3(-8.0, 0.0, -28.0) * w)
			_add("leftHand", Vector3(0.0, 0.0, -12.0) * w)
		"side_right":
			var breathe_right: float = sin(time * 1.4) * 0.8
			var lean_right: float = float(LifeStyle.active().lean_body)
			_add("hips", Vector3(0.0, 0.0, -3.0) * w)
			_add("leftUpperLeg", Vector3(0.0, 0.0, 3.0) * w)
			_add("rightUpperLeg", Vector3(0.0, 0.0, 3.0) * w)
			_add("spine", Vector3(-2.0, -2.0, -lean_right - breathe_right) * w)
			_add("chest", Vector3(-1.0, -3.0, -5.0) * w)
			_add("neck", Vector3(1.0, 4.0, 3.0) * w)
			_add("head", Vector3(2.0, 6.0, 4.0) * w)
			_add("rightUpperArm", Vector3(-7.0, 0.0, -35.0) * w)
			_add("rightLowerArm", Vector3(-8.0, 0.0, 28.0) * w)
			_add("rightHand", Vector3(0.0, 0.0, 12.0) * w)

## Bends the knees: thighs forward by `thigh_deg`, shins lean back by `shin_deg`, feet
## stay level. Keeping the shoes on the floor is done once per frame in apply()
## (measured pelvis shift for grounded poses), so `_planted` here is only descriptive.
func _legs(thigh_deg: float, shin_deg: float, _planted_hint: bool) -> void:
	if thigh_deg <= 0.01 and shin_deg <= 0.01:
		return
	for side in ["left", "right"]:
		_add(side + "UpperLeg", Vector3(-thigh_deg, 0.0, 0.0))
		_add(side + "LowerLeg", Vector3(thigh_deg + shin_deg, 0.0, 0.0))
		_add(side + "Foot", Vector3(-shin_deg, 0.0, 0.0))

static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

static func _smoother(x: float) -> float:
	var v: float = clampf(x, 0.0, 1.0)
	return v * v * v * (v * (v * 6.0 - 15.0) + 10.0)

func _dangle_legs(time: float, w: float, amount: float) -> void:
	var swing: float = sin(time * 2.7) * 5.0 * amount
	# On this rig, negative thigh X sends the knee forward while positive shin X
	# folds the foot back. The old signs made the knee point behind the body.
	_add("leftUpperLeg", Vector3(-16.0 + swing, 0.0, -2.0) * w)
	_add("rightUpperLeg", Vector3(-16.0 - swing, 0.0, 2.0) * w)
	_add("leftLowerLeg", Vector3(30.0 - swing * 0.5, 0.0, 0.0) * w)
	_add("rightLowerLeg", Vector3(30.0 + swing * 0.5, 0.0, 0.0) * w)
	_add("leftFoot", Vector3(5.0 + swing * 0.15, 0.0, 0.0) * w)
	_add("rightFoot", Vector3(5.0 - swing * 0.15, 0.0, 0.0) * w)

func _screen_roll(semantic: String, degrees: float) -> void:
	if not rig.bones.has(semantic):
		return
	var bone: int = int(rig.bones[semantic])
	if not rig.parent_rest_rotations.has(bone):
		return
	var yaw_rad: float = deg_to_rad(facing_yaw)
	var axis := Vector3(-sin(yaw_rad), 0.0, cos(yaw_rad))
	var parent_q: Quaternion = rig.parent_rest_rotations[bone]
	var extra: Quaternion = parent_q.inverse() * Quaternion(axis, deg_to_rad(degrees)) * parent_q
	skeleton.set_bone_pose_rotation(bone, (extra * skeleton.get_bone_pose_rotation(bone)).normalized())

func _add(semantic: String, degrees: Vector3) -> void:
	if not rig.bones.has(semantic):
		return
	var bone: int = int(rig.bones[semantic])
	if not rig.parent_rest_rotations.has(bone):
		return
	var parent_q: Quaternion = rig.parent_rest_rotations[bone]
	var extra: Quaternion = parent_q.inverse() * Quaternion.from_euler(degrees * (PI / 180.0)) * parent_q
	skeleton.set_bone_pose_rotation(bone, (extra * skeleton.get_bone_pose_rotation(bone)).normalized())
