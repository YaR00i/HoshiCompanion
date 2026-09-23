extends RefCounted
## Procedural, low-amplitude body rig. Rotations are applied relative to each
## authored local REST transform. Never use identity as the resting bone pose.
## Axes below are in the skeleton's rest space (VRM 1.0 avatar faces +Z).

var skeleton: Skeleton3D
var bones: Dictionary = {}
var rest_rotations: Dictionary = {}
var parent_rest_rotations: Dictionary = {}
var _hair: Array = []
var hair_enabled: bool = true
var _hair_angle: Vector2 = Vector2.ZERO
var _hair_velocity: Vector2 = Vector2.ZERO
var _last_gaze: Vector2 = Vector2.ZERO
var _height: float = 1.5

func setup(model: Node3D, source: Dictionary, state: GLTFState) -> Dictionary:
	skeleton = null
	bones.clear()
	rest_rotations.clear()
	parent_rest_rotations.clear()
	_hair.clear()
	var human: Dictionary = source.get("extensions", {}).get("VRMC_vrm", {}).get("humanoid", {}).get("humanBones", {})
	var raw_nodes: Array = source.get("nodes", [])
	var head_node: int = int(human.get("head", {}).get("node", -1))
	if head_node < 0 or head_node >= raw_nodes.size():
		return {"error": "В VRM отсутствует humanoid.head."}
	var head_name: String = str(raw_nodes[head_node].get("name", ""))
	var candidates: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	for candidate in candidates:
		var skel: Skeleton3D = candidate as Skeleton3D
		if skel.find_bone(head_name) >= 0:
			skeleton = skel
			break
	if skeleton == null:
		return {"error": "Не найден скелет с костью головы: " + head_name}
	skeleton.reset_bone_poses()
	for semantic in human:
		var node_index: int = int(human[semantic].get("node", -1))
		if node_index < 0 or node_index >= raw_nodes.size():
			continue
		var node_name: String = str(raw_nodes[node_index].get("name", ""))
		var bone_id: int = skeleton.find_bone(node_name)
		if bone_id < 0 and node_index < state.get_nodes().size():
			bone_id = skeleton.find_bone(state.get_nodes()[node_index].resource_name)
		if bone_id >= 0:
			bones[semantic] = bone_id
			_cache_rest(bone_id)
	for required in ["head", "neck", "hips", "leftUpperArm", "rightUpperArm", "leftLowerArm", "rightLowerArm"]:
		if not bones.has(required):
			return {"error": "Не удалось привязать humanoid-кость: " + required}
	# Only restrained hair motion, no bust/cloth springs or collision simulation.
	var springs: Array = source.get("extensions", {}).get("VRMC_springBone", {}).get("springs", [])
	for chain in springs:
		if not "hair" in str(chain.get("name", "")).to_lower():
			continue
		var depth: int = 0
		for joint in chain.get("joints", []):
			var node_index: int = int(joint.get("node", -1))
			if node_index < 0 or node_index >= raw_nodes.size():
				continue
			var bone_name: String = str(raw_nodes[node_index].get("name", ""))
			if bone_name.ends_with("_end"):
				continue
			var bone_id: int = skeleton.find_bone(bone_name)
			if bone_id >= 0:
				_cache_rest(bone_id)
				_hair.append({"bone": bone_id, "depth": depth, "phase": float(_hair.size()) * 0.73})
			depth += 1
	return {"bones": bones.size(), "hair_bones": _hair.size(), "skeleton_bones": skeleton.get_bone_count()}

func _cache_rest(bone_id: int) -> void:
	if rest_rotations.has(bone_id):
		return
	var local: Transform3D = skeleton.get_bone_rest(bone_id)
	rest_rotations[bone_id] = local.basis.orthonormalized().get_rotation_quaternion()
	var parent: int = skeleton.get_bone_parent(bone_id)
	var parent_q: Quaternion = Quaternion.IDENTITY
	if parent >= 0:
		parent_q = skeleton.get_bone_global_rest(parent).basis.orthonormalized().get_rotation_quaternion()
	parent_rest_rotations[bone_id] = parent_q

func set_offset(bone_id: int, euler_degrees: Vector3) -> void:
	if bone_id < 0 or not rest_rotations.has(bone_id):
		return
	var delta: Quaternion = Quaternion.from_euler(euler_degrees * (PI / 180.0))
	var parent_q: Quaternion = parent_rest_rotations[bone_id]
	var local_q: Quaternion = parent_q.inverse() * delta * parent_q * rest_rotations[bone_id]
	skeleton.set_bone_pose_rotation(bone_id, local_q.normalized())

func pose(semantic: String, euler_degrees: Vector3) -> void:
	if bones.has(semantic):
		set_offset(int(bones[semantic]), euler_degrees)

func tick(delta: float, time: float, gaze: Vector2, wave: float, pet: float, sleepy: float, moving: bool, curiosity: float = 0.0, notice: float = 0.0, pet_follow: Vector2 = Vector2.ZERO, gait: Dictionary = {}, welcome: float = 0.0) -> void:
	if skeleton == null:
		return
	var motion: float = 1.0 if moving else 0.0
	var breathe: float = sin(time * 1.65) * motion
	var sway: float = sin(time * 0.62) * motion
	# Petting is a single soft nuzzle. The small, smoothed cursor offset follows
	# the hand instead of choosing a new head pose after release.
	var pet_chest: Vector3 = Vector3(1.2, 0.0, pet_follow.x * 0.6)
	var pet_neck: Vector3 = Vector3(1.5 + pet_follow.y * 1.0, pet_follow.x * 2.0, pet_follow.x * 1.8)
	var pet_head: Vector3 = Vector3(3.0 + pet_follow.y * 2.0, pet_follow.x * 3.0, pet_follow.x * 3.5)
	var pet_shoulder: float = 1.5
	var pet_arm: float = 1.5
	# Feet/hips stay anchored. Most life is in shoulders, head and soft hands.
	pose("hips", Vector3.ZERO)
	pose("spine", Vector3(breathe * 0.35, 0.0, sway * 0.35))
	pose("chest", Vector3(breathe * 0.45 + sleepy * 1.0, 0.0, sway * -0.22) + pet_chest * pet + Vector3(-0.8, 0.0, 1.4) * welcome)
	pose("upperChest", Vector3(breathe * 0.2, 0.0, 0.0))
	pose("neck", Vector3(gaze.y * 3.0 + sleepy * 3.0, gaze.x * 4.0, 0.0) + pet_neck * pet + Vector3(-1.4, 0.0, 1.0) * notice + Vector3(1.0, 0.0, -1.2) * welcome)
	pose("head", Vector3(gaze.y * 6.0 + sleepy * 8.0, gaze.x * 10.0, sway * 0.7 + curiosity * 4.0) + pet_head * pet + Vector3(-3.4, 0.0, 2.4) * notice + Vector3(2.2, 0.0, -4.2) * welcome)
	pose("leftEye", Vector3(gaze.y * 4.0, gaze.x * 5.0, 0.0))
	pose("rightEye", Vector3(gaze.y * 4.0, gaze.x * 5.0, 0.0))
	pose("leftShoulder", Vector3(-notice * 1.2, 0.0, -pet * pet_shoulder))
	pose("rightShoulder", Vector3(-notice * 1.2, 0.0, pet * pet_shoulder))
	pose("leftUpperArm", Vector3(0.0, -2.0, -72.0 + sway * 1.1 - pet * pet_arm))
	pose("leftLowerArm", Vector3(-3.0, -6.0, 6.0 + pet * 3.0))
	pose("leftHand", Vector3(0.0, 0.0, -2.0))
	pose("rightUpperArm", Vector3(0.0, 2.0, lerpf(72.0 - sway + pet * pet_arm, 22.0, wave)))
	pose("rightLowerArm", Vector3(-3.0, 6.0, lerpf(-6.0, -125.0, wave)))
	pose("rightHand", Vector3(wave * -30.0, 0.0, 2.0 + wave * sin(time * 9.5) * 13.0))
	_apply_walk_upper(gait, wave)
	_tick_fingers(wave)
	_tick_hair(minf(delta, 0.05), time, gaze, motion)

func _apply_walk_upper(frame: Dictionary, wave: float) -> void:
	var weight: float = float(frame.get("weight", 0.0))
	if weight <= 0.001:
		return
	var phase: float = float(frame.get("phase", 0.0))
	var arm: float = -cos(phase) * 9.0 * weight
	pose("chest", Vector3(weight * 2.5, sin(phase) * weight * 1.0, 0.0))
	pose("leftUpperArm", Vector3(arm, -2.0, -73.0))
	pose("leftLowerArm", Vector3(-3.0, -6.0, 8.0))
	# An explicit greeting can still take priority during the short stop transition.
	if wave < 0.1:
		pose("rightUpperArm", Vector3(-arm, 2.0, 73.0))
		pose("rightLowerArm", Vector3(-3.0, 6.0, -8.0))

func _tick_fingers(wave: float) -> void:
	for side in ["left", "right"]:
		var sign_value: float = -1.0 if side == "left" else 1.0
		var curl: float = 1.0 - wave * 0.85 if side == "right" else 1.0
		for finger in ["Index", "Middle", "Ring", "Little"]:
			pose(side + finger + "Proximal", Vector3(0.0, sign_value * 9.0 * curl, 0.0))
			pose(side + finger + "Intermediate", Vector3(0.0, sign_value * 13.0 * curl, 0.0))
			pose(side + finger + "Distal", Vector3(0.0, sign_value * 5.0 * curl, 0.0))

func _tick_hair(delta: float, time: float, gaze: Vector2, motion: float) -> void:
	var goal: Vector2 = (gaze - _last_gaze) * -0.13
	_last_gaze = gaze
	# Analytic critically damped response: remains stable after a long frame.
	var omega: float = 10.0
	var offset: Vector2 = _hair_angle - goal
	var impulse: Vector2 = (_hair_velocity + offset * omega) * delta
	var decay: float = exp(-omega * delta)
	_hair_angle = goal + (offset + impulse) * decay
	_hair_velocity = (_hair_velocity - impulse * omega) * decay
	_hair_angle = _hair_angle.limit_length(0.025)
	for entry in _hair:
		var depth: float = float(entry["depth"])
		var phase: float = float(entry["phase"])
		var enabled_weight: float = motion if hair_enabled else 0.0
		var angle: float = (sin(time * 1.1 + phase - depth * 0.38) * 0.28 + _hair_angle.x * 30.0) * enabled_weight
		set_offset(int(entry["bone"]), Vector3(sin(time * 0.9 + phase) * 0.17 * enabled_weight, 0.0, angle))

func world_point(semantic: String) -> Vector3:
	if skeleton == null or not bones.has(semantic):
		return Vector3.ZERO
	return skeleton.global_transform * skeleton.get_bone_global_pose(int(bones[semantic])).origin

func reset() -> void:
	if skeleton != null:
		skeleton.reset_bone_poses()
	_hair_angle = Vector2.ZERO
	_hair_velocity = Vector2.ZERO
	_last_gaze = Vector2.ZERO
