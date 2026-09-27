@tool
extends RefCounted
const WalkStyle = preload("res://scripts/walk_style.gd")
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
## Where each sole touches the floor this frame (skeleton space): the ball of the foot
## while the heel is up, the heel while the toes are up. Used to verify no sliding.
var last_contacts: Array[Vector3] = []
var last_pivots: Array[String] = []
var max_reach_error: float = 0.0
## The pelvis goes down at once when the legs need it, but rises back gently: short
## up-down flickers between two dips merge into one soft settle per step.
const RISE_TIME: float = 0.12
## How far a back foot may rise onto its toes to stay on the floor (radians).
const MAX_TOE_PITCH: float = deg_to_rad(70.0)
var _prev_drop: float = 0.0
var _prev_time: float = -1.0

func setup(rig_driver, model_height: float) -> Dictionary:
	rig = rig_driver
	skeleton = rig.skeleton
	height_m = model_height
	legs.clear()
	last_targets.clear()
	last_contacts.clear()
	last_pivots.clear()
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
		# Heel-toe pivots on the floor: the ball of the foot lies under the toe joint,
		# the heel about 40% of that distance behind the ankle (measured on VRoid feet).
		var ground_y: float = skeleton.to_local(Vector3.ZERO).y if skeleton.is_inside_tree() else 0.0
		var toes: int = int(rig.bones.get(side + "Toes", -1))
		var ball_z: float = skeleton.get_bone_global_rest(toes).origin.z if toes >= 0 else ankle.origin.z + b * 0.2
		var heel_z: float = ankle.origin.z - (ball_z - ankle.origin.z) * 0.4
		legs.append({"upper": upper, "lower": lower, "foot": foot, "toes": toes,
			"toes_q": skeleton.get_bone_global_rest(toes).basis.orthonormalized().get_rotation_quaternion() if toes >= 0 else Quaternion.IDENTITY,
			"ball": Vector3(ankle.origin.x, ground_y, ball_z), "heel": Vector3(ankle.origin.x, ground_y, heel_z),
			"rest_hip": hip, "rest_ankle": ankle.origin, "foot_q": ankle.basis.orthonormalized().get_rotation_quaternion(), "a": a, "b": b})
		last_targets.append(ankle.origin)
		last_contacts.append(Vector3(ankle.origin.x, ground_y, ankle.origin.z))
		last_pivots.append("flat")
	available = true
	return {"available": true, "method": "distance-footplants + two-bone IK", "legs": 2}

func apply(frame: Dictionary, time: float, idle_shift: float = 0.0) -> void:
	if not available:
		return
	# Restore these channels before solving; never accumulate rotations each frame.
	for leg in legs:
		for key in ["upper", "lower", "foot", "toes"]:
			var bone: int = int(leg[key])
			if bone >= 0:
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
	var pitches: Array[float] = [float(frame.get("pitch_left", 0.0)), float(frame.get("pitch_right", 0.0))]
	var targets: Array[Vector3] = []
	for side in range(2):
		targets.append(legs[side]["rest_ankle"] + (left if side == 0 else right) + _roll_offset(legs[side], pitches[side]))
	# Choose only as much hip lowering as the actual leg geometry requires. A
	# constant 3%-height crouch looked like squatting rather than relaxed walking.
	var drop: float = height_m * 0.006 * weight
	# Feet on the floor decide how low the pelvis goes; a foot in the air (a long stride
	# or a playful kick) simply straightens its knee instead of pulling the whole body
	# into a crouch. The hand-over between legs is gradual (Locomotion "ground_*"), so
	# the pelvis height never jumps when a foot lands or lifts off.
	var ground: Array[float] = [float(frame.get("ground_left", 1.0)), float(frame.get("ground_right", 1.0))]
	for side in range(2):
		if ground[side] <= 0.0001:
			continue
		var ankle_target: Vector3 = targets[side]
		# The actual hip joint this frame: the walk turns and tilts the pelvis (rig_driver,
		# WalkStyle.hip_turn/hip_tilt), which lifts one hip joint above its rest height.
		var upper_origin: Vector3 = skeleton.get_bone_global_pose(int(legs[side]["upper"])).origin + Vector3(sway, 0.0, 0.0)
		var horizontal_sq: float = pow(ankle_target.x - upper_origin.x, 2.0) + pow(ankle_target.z - upper_origin.z, 2.0)
		var reach: float = float(legs[side]["a"]) + float(legs[side]["b"]) - height_m * 0.0007
		var vertical_reach: float = sqrt(maxf(0.0001, reach * reach - horizontal_sq))
		drop = maxf(drop, (upper_origin.y - ankle_target.y - vertical_reach) * ground[side])
	var land_weight: float = float(frame.get("land_weight", 0.0))
	if land_weight > 0.0001:
		# The front leg at its future touch-down spot (heel down, toes up), measured from
		# the hip joint as it is now: how low the pelvis must be when the heel strikes.
		var land_side: int = int(frame.get("land_side", 0))
		var land_target: Vector3 = legs[land_side]["rest_ankle"] + (frame.get("land_offset", Vector3.ZERO) as Vector3) + _roll_offset(legs[land_side], float(frame.get("land_pitch", 0.0)))
		var land_hip: Vector3 = skeleton.get_bone_global_pose(int(legs[land_side]["upper"])).origin + Vector3(sway, 0.0, 0.0)
		var land_reach: float = float(legs[land_side]["a"]) + float(legs[land_side]["b"]) - height_m * 0.0007
		var land_horizontal: float = pow(land_target.x - land_hip.x, 2.0) + pow(land_target.z - land_hip.z, 2.0)
		drop = maxf(drop, (land_hip.y - land_target.y - sqrt(maxf(0.0001, land_reach * land_reach - land_horizontal))) * land_weight)
	if activity:
		# Soft bounce: lowest when both feet are down, highest as the body passes
		# over the standing foot. Only ever lowers the pelvis, so reach stays safe.
		var u: float = float(frame.get("u", 0.0))
		# WalkStyle.bounce: realistic ~0.0065, cartoon ~0.016.
		var style = WalkStyle.active()
		drop += height_m * style.bounce * weight * _bounce_shape(u, style.drop_snap)
		var dt: float = clampf(time - _prev_time, 0.0, 0.1) if _prev_time >= 0.0 else 0.0
		if dt > 0.0:
			drop = maxf(drop, lerpf(_prev_drop, drop, 1.0 - exp(-dt / RISE_TIME)))
		_prev_drop = drop
		_prev_time = time
	if not activity:
		_prev_time = -1.0
		sway = sin(time * 0.65) * height_m * 0.007 * idle_shift
		drop = height_m * 0.005 * idle_shift
	# A foot that is not fully carrying the body stops where the straight leg ends (same
	# direction, reachable length): in the air, or its toes just leaving the floor.
	for side in range(2):
		if ground[side] >= 0.9999:
			continue
		var hip_now: Vector3 = skeleton.get_bone_global_pose(int(legs[side]["upper"])).origin + Vector3(sway, -drop, 0.0)
		var reach_air: float = float(legs[side]["a"]) + float(legs[side]["b"]) - height_m * 0.0007
		if targets[side].distance_to(hip_now) <= reach_air:
			continue
		# A back foot still on its toes rises further onto them (heel higher) so the toes
		# keep touching the floor while the pelvis stops waiting for it — like a long
		# stride in real life — instead of lifting off early.
		var offset: Vector3 = left if side == 0 else right
		if pitches[side] > 0.0 and offset.y < 0.001:
			var base: Vector3 = legs[side]["rest_ankle"] + offset
			var low: float = pitches[side]
			var high: float = MAX_TOE_PITCH
			if base.distance_to(hip_now - _roll_offset(legs[side], high)) <= reach_air or (base + _roll_offset(legs[side], high)).distance_to(hip_now) <= reach_air:
				for iteration in range(12):
					var mid: float = (low + high) * 0.5
					if (base + _roll_offset(legs[side], mid)).distance_to(hip_now) <= reach_air:
						high = mid
					else:
						low = mid
				pitches[side] = high
				targets[side] = base + _roll_offset(legs[side], high)
				continue
		targets[side] = hip_now + (targets[side] - hip_now).normalized() * reach_air
	# Convert the desired skeleton-space translation into the hip's parent space.
	var parent: int = skeleton.get_bone_parent(hips_id)
	var parent_basis: Basis = Basis.IDENTITY
	if parent >= 0:
		parent_basis = skeleton.get_bone_global_pose(parent).basis
	skeleton.set_bone_pose_position(hips_id, hip_local_rest + parent_basis.inverse() * Vector3(sway, -drop, 0.0))
	for side in range(2):
		last_targets[side] = targets[side]
		_solve_leg(legs[side], targets[side], pitches[side])
		var pivot: String = "ball" if pitches[side] > 0.0005 else ("heel" if pitches[side] < -0.0005 else "flat")
		var local_pivot: Vector3 = (legs[side][pivot if pivot != "flat" else "ball"] as Vector3) - (legs[side]["rest_ankle"] as Vector3)
		var ankle_now: Vector3 = skeleton.get_bone_global_pose(int(legs[side]["foot"])).origin
		last_contacts[side] = ankle_now + Basis(Vector3.RIGHT, pitches[side]) * local_pivot
		last_pivots[side] = pivot

## 1 = lowest, 0 = highest. Even spring: a cosine, lowest at the heel strike (u = 0).
## Snappy ("опа"): while the swinging foot comes down (last 20% of the step) the body
## drops fast with it, stays low a moment after the heel strike, then rises slowly
## while passing over the standing leg and stays up until the next foot comes down.
static func _bounce_shape(u: float, snap: float) -> float:
	var even: float = 0.5 + 0.5 * cos(TAU * u)
	var v: float = fposmod(u + 0.2, 1.0)
	var snappy: float = 0.0
	if v < 0.2:
		snappy = smoothstep(0.0, 0.2, v)
	elif v < 0.3:
		snappy = 1.0
	elif v < 0.75:
		snappy = 1.0 - smoothstep(0.3, 0.75, v)
	return lerpf(even, snappy, clampf(snap, 0.0, 1.0))

## Ankle displacement for a foot pitched by `pitch` around its floor pivot: the ball of
## the foot for heel-up (positive), the heel for toes-up (negative). Translation-invariant,
## so the same offset applies on the ground and in the air.
func _roll_offset(leg: Dictionary, pitch: float) -> Vector3:
	if absf(pitch) < 0.0005:
		return Vector3.ZERO
	var ankle: Vector3 = leg["rest_ankle"]
	var pivot: Vector3 = leg["ball"] if pitch > 0.0 else leg["heel"]
	return pivot + Basis(Vector3.RIGHT, pitch) * (ankle - pivot) - ankle

func _set_global_rotation(bone: int, rotation: Quaternion) -> void:
	var parent: int = skeleton.get_bone_parent(bone)
	var parent_q: Quaternion = Quaternion.IDENTITY
	if parent >= 0:
		parent_q = skeleton.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, (parent_q.inverse() * rotation).normalized())

func _solve_leg(leg: Dictionary, desired_ankle: Vector3, pitch: float = 0.0) -> void:
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
	# The shoe pitches around its floor pivot (see _roll_offset), so the sole never dips
	# below the taskbar. While the heel is up the toes stay flat on the floor.
	_set_global_rotation(foot, (Quaternion(Vector3.RIGHT, pitch) * (leg["foot_q"] as Quaternion)).normalized())
	var toes: int = int(leg["toes"])
	if toes >= 0 and pitch > 0.0:
		_set_global_rotation(toes, leg["toes_q"])
	max_reach_error = maxf(max_reach_error, desired_ankle.distance_to(skeleton.get_bone_global_pose(foot).origin))

func reset() -> void:
	if skeleton == null:
		return
	if hips_id >= 0:
		skeleton.set_bone_pose_position(hips_id, hip_local_rest)
	for leg in legs:
		for key in ["upper", "lower", "foot", "toes"]:
			var bone: int = int(leg[key])
			if bone >= 0:
				skeleton.set_bone_pose_rotation(bone, rig.rest_rotations[bone])
	max_reach_error = 0.0
