@tool
extends RefCounted
const LifeStyle = preload("res://scripts/life_style.gd")
const HairSprings = preload("res://scripts/hair_spring_driver.gd")
const WalkStyle = preload("res://scripts/walk_style.gd")
## Procedural, low-amplitude body rig. Rotations are applied relative to each
## authored local REST transform. Never use identity as the resting bone pose.
## Axes below are in the skeleton's rest space (VRM 1.0 avatar faces +Z).

var skeleton: Skeleton3D
var bones: Dictionary = {}
var rest_rotations: Dictionary = {}
var parent_rest_rotations: Dictionary = {}
var _hair: Array = []
var hair_springs = HairSprings.new()
var hair_enabled: bool = true:
	set(value):
		hair_enabled = value
		hair_springs.set_enabled(value)
var _height: float = 1.5

func setup(model: Node3D, source: Dictionary, state: GLTFState) -> Dictionary:
	hair_springs.clear()
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
	# The native simulator owns hair motion; this list remains useful diagnostics.
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
				_hair.append({"bone": bone_id, "depth": depth})
				depth += 1
	var hair_chains: int = hair_springs.setup(skeleton, source)
	hair_springs.set_enabled(hair_enabled)
	return {"bones": bones.size(), "hair_bones": _hair.size(), "hair_chains": hair_chains, "skeleton_bones": skeleton.get_bone_count()}

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
	# Сила — в animations/life_style.tres (голова, наклон корпуса, покачивание).
	var life = LifeStyle.active()
	var nuzzle: float = sin(time * float(life.pet_sway_speed)) * float(life.pet_sway)
	var pet_spine: Vector3 = Vector3(float(life.pet_body) * 0.35, pet_follow.x * float(life.pet_body) * 0.25, pet_follow.x * float(life.pet_body) * 0.55 + nuzzle * 0.6)
	var pet_chest: Vector3 = Vector3(1.2 + float(life.pet_body) * 0.25, pet_follow.x * float(life.pet_body) * 0.2, pet_follow.x * (0.6 + float(life.pet_body) * 0.3) + nuzzle * 0.5)
	var pet_neck: Vector3 = Vector3(1.5 + pet_follow.y * 1.0, pet_follow.x * 2.0, pet_follow.x * 1.8 - nuzzle * 0.3) * float(life.pet_head)
	var pet_head: Vector3 = Vector3(3.0 + pet_follow.y * 2.0, pet_follow.x * 3.0, pet_follow.x * 3.5 + nuzzle * 0.4) * float(life.pet_head)
	var pet_shoulder: float = 1.5
	var pet_arm: float = 1.5
	# Feet/hips stay anchored. Most life is in shoulders, head and soft hands.
	pose("hips", Vector3.ZERO)
	pose("spine", Vector3(breathe * 0.35, 0.0, sway * 0.35) + pet_spine * pet)
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

func _apply_walk_upper(frame: Dictionary, wave: float) -> void:
	var weight: float = float(frame.get("weight", 0.0))
	if weight <= 0.001:
		return
	# phase = PI * (step + u); the LEFT foot swings on even steps. On this rig +X on an
	# upper arm swings it back, +Y on the hips turns the left hip back, +Z lifts the left hip.
	var phase: float = float(frame.get("phase", 0.0))
	var s: float = sin(phase)
	var c: float = cos(phase)
	var w: float = weight
	# Every amount below is a WalkStyle slider (walk workshop), in degrees.
	var st = WalkStyle.active()
	# One bounce per step: `step_bob` is 1 when a foot lands, -1 while passing over it.
	var step_bob: float = cos(phase * 2.0)
	# Pelvis follows the swinging leg forward and dips on the swing side; the chest turns
	# the other way so shoulders and hips counter-rotate like a real walk.
	add_pose("hips", Vector3(0.0, c * st.hip_turn, -s * st.hip_tilt) * w)
	# Torso leans over the standing leg and gives a little on each footfall.
	var kick: float = float(frame.get("kick", 0.0))
	add_pose("spine", Vector3(st.torso_lean + step_bob * st.footfall_dip + kick * st.kick_lean, -c * st.shoulder_turn * 0.5, s * st.side_lean) * w)
	pose("chest", Vector3(st.chest_pitch + step_bob * st.footfall_dip * 0.67, -c * st.shoulder_turn, s * st.side_lean * 0.6) * w)
	# Head keeps looking ahead, tilts side to side with the steps and nods a moment after
	# each footfall (lagging like a heavier head on a springy neck).
	add_pose("neck", Vector3(0.0, -c * 0.3, -s * st.head_tilt * 0.35) * w)
	add_pose("head", Vector3(cos(phase * 2.0 - st.head_lag) * st.head_nod, 0.0, -sin(phase - st.head_lag * 0.57) * st.head_tilt) * w)
	# Arms swing opposite to the legs, a little behind them (a loose pendulum driven by the
	# shoulders), with separate forward/back reach; the elbow bends more on the forward
	# swing. +X on an upper arm swings it back.
	var swing: float = -cos(phase - st.arm_lag)
	var left_arm: float = swing * (st.arm_forward if swing < 0.0 else st.arm_back) * w
	var right_arm: float = -swing * (st.arm_forward if swing > 0.0 else st.arm_back) * w
	var left_forward: float = clampf(-swing, 0.0, 1.0)
	var right_forward: float = clampf(swing, 0.0, 1.0)
	# Arms held away from the body; loose hands trail the swing and flick at its ends.
	var open_arms: float = st.arm_open * w
	var flop: float = -cos(phase - st.arm_lag - 0.9) * st.hand_flop * w
	pose("leftUpperArm", Vector3(left_arm, -2.0, -73.0 + open_arms))
	pose("leftLowerArm", Vector3(-3.0, -6.0 - st.elbow_bend * left_forward * w, 8.0))
	add_pose("leftHand", Vector3(flop, 0.0, 0.0))
	# An explicit greeting can still take priority during the short stop transition.
	if wave < 0.1:
		pose("rightUpperArm", Vector3(right_arm, 2.0, 73.0 - open_arms))
		pose("rightLowerArm", Vector3(-3.0, 6.0 + st.elbow_bend * right_forward * w, -8.0))
		add_pose("rightHand", Vector3(-flop, 0.0, 0.0))

## Adds a rotation on top of the pose already set this frame (same frame as pose()).
func add_pose(semantic: String, euler_degrees: Vector3) -> void:
	if not bones.has(semantic):
		return
	var bone_id: int = int(bones[semantic])
	if not parent_rest_rotations.has(bone_id):
		return
	var parent_q: Quaternion = parent_rest_rotations[bone_id]
	var extra: Quaternion = parent_q.inverse() * Quaternion.from_euler(euler_degrees * (PI / 180.0)) * parent_q
	skeleton.set_bone_pose_rotation(bone_id, (extra * skeleton.get_bone_pose_rotation(bone_id)).normalized())

func _tick_fingers(wave: float) -> void:
	for side in ["left", "right"]:
		var sign_value: float = -1.0 if side == "left" else 1.0
		var curl: float = 1.0 - wave * 0.85 if side == "right" else 1.0
		for finger in ["Index", "Middle", "Ring", "Little"]:
			pose(side + finger + "Proximal", Vector3(0.0, sign_value * 9.0 * curl, 0.0))
			pose(side + finger + "Intermediate", Vector3(0.0, sign_value * 13.0 * curl, 0.0))
			pose(side + finger + "Distal", Vector3(0.0, sign_value * 5.0 * curl, 0.0))

func world_point(semantic: String) -> Vector3:
	if skeleton == null or not bones.has(semantic):
		return Vector3.ZERO
	return skeleton.global_transform * skeleton.get_bone_global_pose(int(bones[semantic])).origin

func reset() -> void:
	if skeleton != null:
		skeleton.reset_bone_poses()
	hair_springs.reset()
