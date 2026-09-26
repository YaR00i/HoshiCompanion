@tool
extends RefCounted
## Maps authored VRM hair chains onto Godot's native spring-bone modifier.
## The imported avatar and its REST/bind data are never changed.

var simulator: SpringBoneSimulator3D
var chain_count: int = 0
var collider_count: int = 0

func setup(skeleton: Skeleton3D, source: Dictionary) -> int:
	clear()
	var raw_nodes: Array = source.get("nodes", [])
	var spring_data: Dictionary = source.get("extensions", {}).get("VRMC_springBone", {})
	var springs: Array = spring_data.get("springs", [])
	var usable: Array = []
	for chain in springs:
		if not "hair" in str(chain.get("name", "")).to_lower():
			continue
		var mapped: Array = []
		for joint in chain.get("joints", []):
			var node_index: int = int(joint.get("node", -1))
			if node_index < 0 or node_index >= raw_nodes.size():
				continue
			var bone_name: String = str(raw_nodes[node_index].get("name", ""))
			var bone_id: int = skeleton.find_bone(bone_name)
			if bone_id >= 0:
				mapped.append({"bone": bone_id, "source": joint})
		if mapped.size() < 2:
			continue
		var contiguous: bool = true
		for i in range(1, mapped.size()):
			if skeleton.get_bone_parent(int(mapped[i]["bone"])) != int(mapped[i - 1]["bone"]):
				contiguous = false
				break
		if contiguous:
			var tail_length: float = 0.0
			var authored_joints: Array = chain.get("joints", [])
			if not authored_joints.is_empty():
				var tail_node: int = int(authored_joints[-1].get("node", -1))
				if tail_node >= 0 and tail_node < raw_nodes.size() and skeleton.find_bone(str(raw_nodes[tail_node].get("name", ""))) < 0:
					var translation: Array = raw_nodes[tail_node].get("translation", [])
					if translation.size() == 3:
						tail_length = Vector3(float(translation[0]), float(translation[1]), float(translation[2])).length()
			usable.append({"joints": mapped, "center": int(chain.get("center", -1)), "tail_length": tail_length,
				"collider_groups": chain.get("colliderGroups", [])})
	if usable.is_empty():
		return 0
	simulator = SpringBoneSimulator3D.new()
	simulator.name = "HoshiHairSprings"
	simulator.active = false
	skeleton.add_child(simulator)
	simulator.setting_count = usable.size()
	var collider_nodes: Dictionary = _create_colliders(skeleton, raw_nodes, spring_data, usable)
	var collider_groups: Array = spring_data.get("colliderGroups", [])
	for index in range(usable.size()):
		var mapped: Array = usable[index]["joints"]
		simulator.set_root_bone(index, int(mapped[0]["bone"]))
		simulator.set_end_bone(index, int(mapped[-1]["bone"]))
		if float(usable[index]["tail_length"]) > 0.001:
			simulator.set_extend_end_bone(index, true)
			simulator.set_end_bone_length(index, float(usable[index]["tail_length"]))
		# VRM center follows the avatar. Large desktop-window jumps must not
		# throw strands through the head or flip them over the face.
		var center_node: int = int(usable[index]["center"])
		var center_bone: int = -1
		if center_node >= 0 and center_node < raw_nodes.size():
			center_bone = skeleton.find_bone(str(raw_nodes[center_node].get("name", "")))
		if center_bone >= 0:
			simulator.set_center_from(index, SpringBoneSimulator3D.CENTER_FROM_BONE)
			simulator.set_center_bone(index, center_bone)
		else:
			simulator.set_center_from(index, SpringBoneSimulator3D.CENTER_FROM_NODE)
			simulator.set_center_node(index, NodePath(".."))
		simulator.set_individual_config(index, true)
		for joint_index in range(mapped.size()):
			var authored: Dictionary = mapped[joint_index]["source"]
			simulator.set_joint_stiffness(index, joint_index, maxf(0.05, float(authored.get("stiffness", 0.7))))
			simulator.set_joint_drag(index, joint_index, clampf(float(authored.get("dragForce", 0.4)), 0.0, 1.0))
			simulator.set_joint_gravity(index, joint_index, maxf(0.0, float(authored.get("gravityPower", 0.0))))
			var gravity_dir: Array = authored.get("gravityDir", [])
			if gravity_dir.size() == 3:
				simulator.set_joint_gravity_direction(index, joint_index, Vector3(float(gravity_dir[0]), float(gravity_dir[1]), float(gravity_dir[2])))
			simulator.set_joint_radius(index, joint_index, maxf(0.0, float(authored.get("hitRadius", 0.0))))
		var chain_colliders: Array[SpringBoneCollisionSphere3D] = []
		for group_index_value in usable[index]["collider_groups"]:
			var group_index: int = int(group_index_value)
			if group_index < 0 or group_index >= collider_groups.size():
				continue
			for collider_index_value in collider_groups[group_index].get("colliders", []):
				var collider_index: int = int(collider_index_value)
				if collider_nodes.has(collider_index) and not chain_colliders.has(collider_nodes[collider_index]):
					chain_colliders.append(collider_nodes[collider_index])
		simulator.set_enable_all_child_collisions(index, false)
		simulator.set_collision_count(index, chain_colliders.size())
		for collision_index in range(chain_colliders.size()):
			simulator.set_collision_path(index, collision_index, simulator.get_path_to(chain_colliders[collision_index]))
	chain_count = usable.size()
	simulator.reset()
	simulator.active = true
	return chain_count

func _create_colliders(skeleton: Skeleton3D, raw_nodes: Array, spring_data: Dictionary, usable: Array) -> Dictionary:
	var referenced: Dictionary = {}
	var groups: Array = spring_data.get("colliderGroups", [])
	for chain in usable:
		for group_index_value in chain["collider_groups"]:
			var group_index: int = int(group_index_value)
			if group_index < 0 or group_index >= groups.size():
				continue
			for collider_index_value in groups[group_index].get("colliders", []):
				referenced[int(collider_index_value)] = true
	var result: Dictionary = {}
	var colliders: Array = spring_data.get("colliders", [])
	for collider_index in referenced:
		if collider_index < 0 or collider_index >= colliders.size():
			continue
		var authored: Dictionary = colliders[collider_index]
		var node_index: int = int(authored.get("node", -1))
		if node_index < 0 or node_index >= raw_nodes.size():
			continue
		var bone_id: int = skeleton.find_bone(str(raw_nodes[node_index].get("name", "")))
		var sphere_data: Dictionary = authored.get("shape", {}).get("sphere", {})
		var offset: Array = sphere_data.get("offset", [])
		var radius: float = float(sphere_data.get("radius", 0.0))
		if bone_id < 0 or offset.size() != 3 or radius <= 0.0:
			continue
		var sphere := SpringBoneCollisionSphere3D.new()
		sphere.name = "HairCollider_%d" % collider_index
		sphere.bone = bone_id
		sphere.position_offset = Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
		sphere.radius = radius
		simulator.add_child(sphere)
		result[collider_index] = sphere
	collider_count = result.size()
	return result

func set_enabled(enabled: bool) -> void:
	if not is_instance_valid(simulator):
		return
	if simulator.active == enabled:
		return
	simulator.active = enabled
	if enabled:
		simulator.reset()

func reset() -> void:
	if is_instance_valid(simulator):
		simulator.reset()

func clear() -> void:
	if is_instance_valid(simulator):
		if simulator.get_parent() != null:
			simulator.get_parent().remove_child(simulator)
		simulator.free()
	simulator = null
	chain_count = 0
	collider_count = 0
