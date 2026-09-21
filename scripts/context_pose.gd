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
var height_m: float = 1.5

func setup(rig_driver, model_height: float) -> Dictionary:
	rig = rig_driver
	skeleton = rig.skeleton
	height_m = model_height
	available = skeleton != null and rig.bones.has("hips")
	return {"available": available}

func tick(delta: float, value: String, screen_velocity: Vector2 = Vector2.ZERO) -> void:
	if not available:
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	requested = value if value in ["idle", "carry", "jump", "fall", "land", "portal", "side_left", "side_right"] else "idle"
	if requested != "idle" and requested != pose_mode:
		pose_mode = requested
		weight = minf(weight, 0.30)
	var goal: float = 0.0 if requested == "idle" else 1.0
	weight = lerpf(weight, goal, 1.0 - exp(-dt * (9.0 if goal > weight else 7.0)))
	if requested == "idle" and weight < 0.002:
		pose_mode = "idle"
		weight = 0.0
	velocity = velocity.lerp(screen_velocity, 1.0 - exp(-dt * 9.0))

func apply(time: float) -> void:
	if not available or pose_mode == "idle" or weight <= 0.001:
		return
	var w: float = weight
	var sx: float = clampf(velocity.x / 900.0, -1.0, 1.0)
	var sy: float = clampf(velocity.y / 900.0, -1.0, 1.0)
	match pose_mode:
		"carry":
			var pendulum: float = sin(time * 3.0) * 3.0 + sx * 7.0
			_add("hips", Vector3(6.0 + sy * 3.0, 0.0, pendulum * 0.45) * w)
			_add("spine", Vector3(-8.0 - sy * 3.0, 0.0, pendulum) * w)
			_add("chest", Vector3(-5.0, 0.0, -pendulum * 0.55) * w)
			_add("neck", Vector3(5.0 + sy * 2.0, -sx * 2.0, -pendulum * 0.35) * w)
			_add("head", Vector3(7.0 + sy * 3.0, -sx * 3.0, -pendulum * 0.60) * w)
			_add("leftUpperArm", Vector3(7.0 + sx * 3.0, 0.0, -5.0 - pendulum * 0.30) * w)
			_add("rightUpperArm", Vector3(7.0 + sx * 3.0, 0.0, 5.0 - pendulum * 0.30) * w)
			_add("leftLowerArm", Vector3(-7.0, 0.0, -8.0) * w)
			_add("rightLowerArm", Vector3(-7.0, 0.0, 8.0) * w)
			_dangle_legs(time, w, 1.0)
		"jump":
			var jump_sway: float = sin(time * 8.0) * 2.0
			_add("spine", Vector3(-8.0, 0.0, jump_sway) * w)
			_add("chest", Vector3(-5.0, 0.0, -jump_sway) * w)
			_add("leftUpperArm", Vector3(-12.0, 0.0, -10.0) * w)
			_add("rightUpperArm", Vector3(-12.0, 0.0, 10.0) * w)
			_add("leftUpperLeg", Vector3(25.0, 0.0, -2.0) * w)
			_add("rightUpperLeg", Vector3(25.0, 0.0, 2.0) * w)
			_add("leftLowerLeg", Vector3(-42.0, 0.0, 0.0) * w)
			_add("rightLowerLeg", Vector3(-42.0, 0.0, 0.0) * w)
		"fall":
			_add("spine", Vector3(4.0, 0.0, sx * 5.0) * w)
			_add("chest", Vector3(3.0, 0.0, -sx * 3.0) * w)
			_add("leftUpperArm", Vector3(-5.0, 0.0, -15.0) * w)
			_add("rightUpperArm", Vector3(-5.0, 0.0, 15.0) * w)
			_dangle_legs(time, w, 0.72)
		"land":
			_add("spine", Vector3(12.0, 0.0, 0.0) * w)
			_add("chest", Vector3(7.0, 0.0, 0.0) * w)
			_add("leftUpperArm", Vector3(4.0, 0.0, -12.0) * w)
			_add("rightUpperArm", Vector3(4.0, 0.0, 12.0) * w)
			_add("leftUpperLeg", Vector3(22.0, 0.0, 0.0) * w)
			_add("rightUpperLeg", Vector3(22.0, 0.0, 0.0) * w)
			_add("leftLowerLeg", Vector3(-34.0, 0.0, 0.0) * w)
			_add("rightLowerLeg", Vector3(-34.0, 0.0, 0.0) * w)
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
