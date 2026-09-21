extends RefCounted
## Analytical two-bone IK. Only LOCAL POSE rotations/hip position are written;
## authored rest transforms and skin binds stay untouched. No SkeletonIK3D plugin.
## Targets and pole are in SKELETON space, not world or parent-bone space.

var rig
var skeleton: Skeleton3D
var height_m: float = 1.5
var available: bool = false
var legs: Array = []
var hips_id: int = -1
var hip_local_rest: Vector3 = Vector3.ZERO
var last_targets: Array[Vector3] = []
var max_reach_error: float = 0.0

func setup(rig_driver, model_height: float) -> Dictionary:
	rig = rig_driver
	skeleton = rig.skeleton
	height_m = model_height
	legs.clear()
	last_targets.clear()
	available = false
	if skeleton == null or not rig.bones.has("hips"):
		return {"available": false, "reason": "Не найден скелет таза."}
	hips_id = int(rig.bones["hips"])
	hip_local_rest = skeleton.get_bone_rest(hips_id).origin
	for side in ["left", "right"]:
		for part in ["UpperLeg", "LowerLeg", "Foot"]:
			if not rig.bones.has(side + part):
				return {"available": false, "reason": "Нет humanoid-кости " + side + part}
		var upper: int = int(rig.bones[side + "UpperLeg"])
		var lower: int = int(rig.bones[side + "LowerLeg"])
		var foot: int = int(rig.bones[side + "Foot"])
		# Extra twist bones between joints are allowed; ordinary direct VRoid joints
		# are the tested asset layout. Global-to-local conversion handles parents.
		var hip: Vector3 = skeleton.get_bone_global_rest(upper).origin
		var knee: Vector3 = skeleton.get_bone_global_rest(lower).origin
		var ankle: Transform3D = skeleton.get_bone_global_rest(foot)
		var a: float = hip.distance_to(knee)
		var b: float = knee.distance_to(ankle.origin)
		if a < 0.02 or b < 0.02:
			return {"available": false, "reason": "Некорректная длина сегментов ноги."}
		legs.append({"upper": upper, "lower": lower, "foot": foot,
			"rest_hip": hip, "rest_ankle": ankle.origin, "foot_q": ankle.basis.orthonormalized().get_rotation_quaternion(), "a": a, "b": b})
		last_targets.append(ankle.origin)
	available = true
	return {"available": true, "method": "distance-footplants + two-bone IK", "legs": 2}

func apply(frame: Dictionary, time: float, idle_shift: float = 0.0) -> void:
	if not available:
		return
	# Restore these channels before solving; never accumulate rotations each frame.
	for leg in legs:
		for key in ["upper", "lower", "foot"]:
			var bone: int = int(leg[key])
			skeleton.set_bone_pose_rotation(bone, rig.rest_rotations[bone])
	skeleton.set_bone_pose_position(hips_id, hip_local_rest)
	var weight: float = float(frame.get("weight", 0.0))
	var left: Vector3 = frame.get("left", Vector3.ZERO)
	var right: Vector3 = frame.get("right", Vector3.ZERO)
	var activity: bool = str(frame.get("mode", "idle")) in ["walk", "settle"]
	# Keep the original calm stance byte-for-byte when no lower-body motion needed.
	if not activity and idle_shift < 0.001:
		return
	var phase: float = float(frame.get("phase", 0.0))
	var sway: float = sin(phase) * height_m * -0.007 * weight
	# Choose only as much hip lowering as the actual leg geometry requires. A
	# constant 3%-height crouch looked like squatting rather than relaxed walking.
	var drop: float = height_m * 0.006 * weight
	for side in range(2):
		var offset: Vector3 = left if side == 0 else right
		var ankle_target: Vector3 = legs[side]["rest_ankle"] + offset
		var upper_origin: Vector3 = legs[side]["rest_hip"] + Vector3(sway, 0.0, 0.0)
		var horizontal_sq: float = pow(ankle_target.x - upper_origin.x, 2.0) + pow(ankle_target.z - upper_origin.z, 2.0)
		var reach: float = float(legs[side]["a"]) + float(legs[side]["b"]) - height_m * 0.0007
		var vertical_reach: float = sqrt(maxf(0.0001, reach * reach - horizontal_sq))
		drop = maxf(drop, upper_origin.y - ankle_target.y - vertical_reach)
	if not activity:
		sway = sin(time * 0.65) * height_m * 0.007 * idle_shift
		drop = height_m * 0.005 * idle_shift
	# Convert the desired skeleton-space translation into the hip's parent space.
	var parent: int = skeleton.get_bone_parent(hips_id)
	var parent_basis: Basis = Basis.IDENTITY
	if parent >= 0:
		parent_basis = skeleton.get_bone_global_pose(parent).basis
	skeleton.set_bone_pose_position(hips_id, hip_local_rest + parent_basis.inverse() * Vector3(sway, -drop, 0.0))
	for side in range(2):
		var delta: Vector3 = left if side == 0 else right
		var target: Vector3 = legs[side]["rest_ankle"] + delta
		last_targets[side] = target
		_solve_leg(legs[side], target)

func _set_global_rotation(bone: int, rotation: Quaternion) -> void:
	var parent: int = skeleton.get_bone_parent(bone)
	var parent_q: Quaternion = Quaternion.IDENTITY
	if parent >= 0:
		parent_q = skeleton.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, (parent_q.inverse() * rotation).normalized())

func _solve_leg(leg: Dictionary, desired_ankle: Vector3) -> void:
	var upper: int = int(leg["upper"])
	var lower: int = int(leg["lower"])
	var foot: int = int(leg["foot"])
	var hip: Vector3 = skeleton.get_bone_global_pose(upper).origin
	var to_target: Vector3 = desired_ankle - hip
	var a: float = float(leg["a"])
	var b: float = float(leg["b"])
	var length: float = clampf(to_target.length(), absf(a - b) + 0.00001, a + b - 0.00001)
	var direction: Vector3 = to_target.normalized()
	var along: float = (a * a + length * length - b * b) / (2.0 * length)
	var out: float = sqrt(maxf(0.0, a * a - along * along))
	# Avatar faces +Z, therefore knees bend toward +Z. Stable projection prevents
	# the backward-knee solution and keeps mirrored legs in separate sagittal planes.
	var pole: Vector3 = Vector3(0.0, 0.0, 1.0)
	pole = (pole - direction * pole.dot(direction)).normalized()
	if pole.length_squared() < 0.1:
		pole = Vector3.RIGHT
	var desired_knee: Vector3 = hip + direction * along + pole * out
	var upper_pose: Transform3D = skeleton.get_bone_global_pose(upper)
	var knee: Vector3 = skeleton.get_bone_global_pose(lower).origin
	var swing: Quaternion = Quaternion((knee - hip).normalized(), (desired_knee - hip).normalized())
	_set_global_rotation(upper, (swing * upper_pose.basis.orthonormalized().get_rotation_quaternion()).normalized())
	var lower_pose: Transform3D = skeleton.get_bone_global_pose(lower)
	var ankle: Vector3 = skeleton.get_bone_global_pose(foot).origin
	var actual_target: Vector3 = hip + direction * length
	var bend: Quaternion = Quaternion((ankle - lower_pose.origin).normalized(), (actual_target - lower_pose.origin).normalized())
	_set_global_rotation(lower, (bend * lower_pose.basis.orthonormalized().get_rotation_quaternion()).normalized())
	# Flat authored shoes during support. No pitch noise that pushes the sole below
	# the taskbar; heel/toe rolling can be added with an explicit sole contact model.
	_set_global_rotation(foot, leg["foot_q"])
	max_reach_error = maxf(max_reach_error, desired_ankle.distance_to(skeleton.get_bone_global_pose(foot).origin))

func reset() -> void:
	if skeleton == null:
		return
	if hips_id >= 0:
		skeleton.set_bone_pose_position(hips_id, hip_local_rest)
	for leg in legs:
		for key in ["upper", "lower", "foot"]:
			var bone: int = int(leg[key])
			skeleton.set_bone_pose_rotation(bone, rig.rest_rotations[bone])
	max_reach_error = 0.0
