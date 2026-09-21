extends RefCounted
## Floor sitting layered over the existing rig. Never edits RESTs or skin binds.
## All IK targets are in SKELETON space; only local pose channels are written.
var rig
var gait
var skeleton: Skeleton3D
var height_m: float = 1.5
var available: bool = false
var arms: Array = []
var hips_rest: Vector3 = Vector3.ZERO
var ground_y: float = 0.0
var max_foot_error: float = 0.0
# Calibrated against the supplied Hoshi model; not a cloth/body collision solver.
var seat_height_ratio: float = 0.055
# Bend the elbows down beside the torso, not sideways at shoulder height.
# A small outward component keeps the upper arms clear of the ribcage.
var seated_elbow_pole: Vector3 = Vector3(0.40, -1.0, -0.12)

func setup(rig_driver, gait_driver, model_height: float) -> Dictionary:
	rig = rig_driver
	gait = gait_driver
	skeleton = rig.skeleton
	height_m = model_height
	arms.clear()
	available = false
	if skeleton == null or not gait.available:
		return {"available": false, "reason": "Для посадки нужны обе ноги и таз."}
	hips_rest = skeleton.get_bone_global_rest(gait.hips_id).origin
	ground_y = skeleton.to_local(Vector3.ZERO).y
	for side in ["left", "right"]:
		if not rig.bones.has(side + "Hand"):
			return {"available": false, "reason": "Нет кости кисти: " + side}
		var upper: int = int(rig.bones[side + "UpperArm"])
		var lower: int = int(rig.bones[side + "LowerArm"])
		var hand: int = int(rig.bones[side + "Hand"])
		var shoulder: Vector3 = skeleton.get_bone_global_rest(upper).origin
		var elbow: Vector3 = skeleton.get_bone_global_rest(lower).origin
		var wrist: Transform3D = skeleton.get_bone_global_rest(hand)
		arms.append({"upper": upper, "lower": lower, "end": hand,
			"a": shoulder.distance_to(elbow), "b": elbow.distance_to(wrist.origin),
			"end_q": wrist.basis.orthonormalized().get_rotation_quaternion()})
	available = true
	return {"available": true, "kind": "floor_knees_up", "foot_support": "planted"}

func apply(amount: float, time: float, wave: float, motion: bool) -> void:
	if not available or amount <= 0.0:
		return
	var p: float = clampf(amount, 0.0, 1.0)
	# Feet remain on their authored ground positions. The pelvis travels backward
	# and down, rather than shrinking the avatar or sliding both shoes forward.
	var hip: Vector3 = hips_rest
	hip.y = lerpf(hips_rest.y, ground_y + height_m * seat_height_ratio, p)
	hip.z -= height_m * 0.30 * p
	_set_position_global(gait.hips_id, hip)
	var transfer: float = pow(sin(PI * p), 2.0)
	_add_rotation("spine", Vector3(5.0 * p + 13.0 * transfer, 0.0, 0.0))
	_add_rotation("chest", Vector3(3.0 * p, 0.0, 0.0))
	for leg in gait.legs:
		var chain: Dictionary = {"upper": leg["upper"], "lower": leg["lower"],
			"end": leg["foot"], "a": leg["a"], "b": leg["b"], "end_q": leg["foot_q"]}
		_solve(chain, leg["rest_ankle"], Vector3(0.0, p, 1.0), leg["foot_q"])
		max_foot_error = maxf(max_foot_error, skeleton.get_bone_global_pose(int(leg["foot"])).origin.distance_to(leg["rest_ankle"]))
	for side in range(2):
		var arm: Dictionary = arms[side]
		var weight: float = smoothstep(0.0, 0.70, p)
		if side == 1:
			weight *= 1.0 - clampf(wave, 0.0, 1.0)
		var knee: Vector3 = skeleton.get_bone_global_pose(int(gait.legs[side]["lower"])).origin
		var sign_x: float = 1.0 if side == 0 else -1.0
		var wrist: Vector3 = knee + Vector3(sign_x * height_m * 0.006, height_m * 0.026, -height_m * 0.012)
		if motion:
			wrist.y += sin(time * 1.65) * height_m * 0.0008 * p
		var rotations: Array[Quaternion] = []
		for key in ["upper", "lower", "end"]:
			rotations.append(skeleton.get_bone_pose_rotation(int(arm[key])))
		var hand_q: Quaternion = Quaternion(Vector3.UP, -sign_x * PI * 0.5) * arm["end_q"]
		_solve(arm, wrist, Vector3(sign_x * seated_elbow_pole.x, seated_elbow_pole.y, seated_elbow_pole.z), hand_q)
		var keys: Array = ["upper", "lower", "end"]
		for index in range(3):
			var bone: int = int(arm[keys[index]])
			var goal: Quaternion = skeleton.get_bone_pose_rotation(bone)
			skeleton.set_bone_pose_rotation(bone, rotations[index].slerp(goal, weight).normalized())

func _set_position_global(bone: int, point: Vector3) -> void:
	var parent: int = skeleton.get_bone_parent(bone)
	var local: Vector3 = point if parent < 0 else skeleton.get_bone_global_pose(parent).affine_inverse() * point
	skeleton.set_bone_pose_position(bone, local)

func _set_rotation_global(bone: int, rotation: Quaternion) -> void:
	var parent: int = skeleton.get_bone_parent(bone)
	var parent_q: Quaternion = Quaternion.IDENTITY
	if parent >= 0:
		parent_q = skeleton.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, (parent_q.inverse() * rotation).normalized())

func _add_rotation(semantic: String, degrees: Vector3) -> void:
	if not rig.bones.has(semantic):
		return
	var bone: int = int(rig.bones[semantic])
	var parent_q: Quaternion = rig.parent_rest_rotations[bone]
	var extra: Quaternion = parent_q.inverse() * Quaternion.from_euler(degrees * (PI / 180.0)) * parent_q
	skeleton.set_bone_pose_rotation(bone, (extra * skeleton.get_bone_pose_rotation(bone)).normalized())

func _solve(chain: Dictionary, goal: Vector3, pole: Vector3, end_q: Quaternion) -> void:
	var upper: int = int(chain["upper"])
	var lower: int = int(chain["lower"])
	var end: int = int(chain["end"])
	var start: Vector3 = skeleton.get_bone_global_pose(upper).origin
	var to_goal: Vector3 = goal - start
	if to_goal.length_squared() < 0.0000001:
		return
	var a: float = float(chain["a"])
	var b: float = float(chain["b"])
	var reach: float = clampf(to_goal.length(), absf(a - b) + 0.00001, a + b - 0.00001)
	var direction: Vector3 = to_goal.normalized()
	var along: float = (a * a + reach * reach - b * b) / (2.0 * reach)
	var bend: float = sqrt(maxf(0.0, a * a - along * along))
	var outward: Vector3 = pole - direction * pole.dot(direction)
	if outward.length_squared() < 0.000001:
		outward = Vector3.RIGHT - direction * direction.x
	outward = outward.normalized()
	var joint: Vector3 = start + direction * along + outward * bend
	var pose: Transform3D = skeleton.get_bone_global_pose(upper)
	var current: Vector3 = skeleton.get_bone_global_pose(lower).origin - start
	var swing: Quaternion = Quaternion(current.normalized(), (joint - start).normalized())
	_set_rotation_global(upper, swing * pose.basis.orthonormalized().get_rotation_quaternion())
	pose = skeleton.get_bone_global_pose(lower)
	current = skeleton.get_bone_global_pose(end).origin - pose.origin
	var target: Vector3 = start + direction * reach
	swing = Quaternion(current.normalized(), (target - pose.origin).normalized())
	_set_rotation_global(lower, swing * pose.basis.orthonormalized().get_rotation_quaternion())
	_set_rotation_global(end, end_q)
