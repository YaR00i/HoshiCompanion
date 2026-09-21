extends RefCounted
## Bind VRM expressions to LIVE MeshInstance3D nodes after generate_scene().
## Do not use GLTFState.get_scene_node(): importer mesh nodes can be replaced
## during import_post. Their temporary references are not our runtime meshes.
## Material/UV expression binds remain outside this prototype's scope.

const Source = preload("res://scripts/vrm_source.gd")

var bindings: Dictionary = {}
var controlled_meshes: Array[MeshInstance3D] = []
var controlled_indices: Dictionary = {}
var warnings: PackedStringArray = PackedStringArray()
var diagnostic: Dictionary = {}

func setup(model: Node3D, source: Dictionary, state: GLTFState) -> Dictionary:
	bindings.clear()
	controlled_meshes.clear()
	controlled_indices.clear()
	warnings.clear()
	var meshes: Array[MeshInstance3D] = []
	if model is MeshInstance3D:
		meshes.append(model as MeshInstance3D)
	for child in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child as MeshInstance3D)
	var inventory: Array = []
	for mesh in meshes:
		var names: PackedStringArray = PackedStringArray()
		if mesh.mesh != null:
			for index in range(mesh.get_blend_shape_count()):
				names.append(str(mesh.mesh.get_blend_shape_name(index)))
		inventory.append({"path": str(model.get_path_to(mesh)), "node_marker": _marker(mesh, Source.NODE_MARKER),
			"mesh_marker": _marker(mesh.mesh, Source.MESH_MARKER), "shape_count": names.size(), "shapes": names})
	var presets: Dictionary = source.get("extensions", {}).get("VRMC_vrm", {}).get("expressions", {}).get("preset", {})
	var source_nodes: Array = source.get("nodes", [])
	var source_meshes: Array = source.get("meshes", [])
	var resolved: Dictionary = {}
	var mapping_report: Array = []
	for expression in presets:
		var definition: Dictionary = presets[expression]
		var mapped: Array = []
		for bind in definition.get("morphTargetBinds", []):
			var node_index: int = int(bind.get("node", -1))
			var original_index: int = int(bind.get("index", -1))
			if node_index < 0 or node_index >= source_nodes.size():
				_warn("Invalid source node for expression: " + str(expression))
				continue
			if not resolved.has(node_index):
				resolved[node_index] = _resolve_mesh(meshes, source, state, node_index)
				var entry: Dictionary = {"source_node": node_index}
				entry["method"] = resolved[node_index].get("method", "unresolved")
				if resolved[node_index].has("mesh"):
					entry["path"] = str(model.get_path_to(resolved[node_index]["mesh"]))
				else:
					entry["reason"] = resolved[node_index].get("reason", "No matching runtime mesh")
				mapping_report.append(entry)
			var resolution: Dictionary = resolved[node_index]
			var instance: MeshInstance3D = resolution.get("mesh") as MeshInstance3D
			if instance == null or instance.mesh == null:
				_warn("Expression %s: %s" % [str(expression), str(resolution.get("reason", "No mesh"))])
				continue
			var source_mesh_id: int = int(source_nodes[node_index].get("mesh", -1))
			if source_mesh_id < 0 or source_mesh_id >= source_meshes.size():
				_warn("Invalid source mesh for expression: " + str(expression))
				continue
			var names: Array = source_meshes[source_mesh_id].get("extras", {}).get("targetNames", [])
			var expected_name: String = ""
			var shape_index: int = -1
			if original_index >= 0 and original_index < names.size():
				expected_name = str(names[original_index])
				if not expected_name.is_empty():
					shape_index = instance.find_blend_shape_by_name(expected_name)
			# VRM references morphs by index; only use positional mapping if this
			# source has no name for the target and target counts still match.
			if shape_index < 0 and expected_name.is_empty():
				var primitives: Array = source_meshes[source_mesh_id].get("primitives", [])
				var expected_count: int = 0
				if not primitives.is_empty():
					expected_count = primitives[0].get("targets", []).size()
				if expected_count == instance.get_blend_shape_count():
					shape_index = original_index
			if shape_index < 0 or shape_index >= instance.get_blend_shape_count():
				_warn("Expression %s: target %s (index %d) not found on %s; imported shapes=%d" % [str(expression), expected_name, original_index, str(instance.name), instance.get_blend_shape_count()])
				continue
			mapped.append({"mesh": instance, "index": shape_index, "weight": float(bind.get("weight", 1.0))})
			if not controlled_meshes.has(instance):
				controlled_meshes.append(instance)
				controlled_indices[instance.get_instance_id()] = []
			var indices: Array = controlled_indices[instance.get_instance_id()]
			if not indices.has(shape_index):
				indices.append(shape_index)
		if not mapped.is_empty():
			bindings[str(expression)] = {"targets": mapped, "binary": bool(definition.get("isBinary", false))}
		if not definition.get("materialColorBinds", []).is_empty() or not definition.get("textureTransformBinds", []).is_empty():
			_warn("Material/UV binds skipped: " + str(expression))
	# Split blink presets may be present on an otherwise compatible model.
	if not bindings.has("blink") and bindings.has("blinkLeft") and bindings.has("blinkRight"):
		var paired: Array = []
		paired.append_array(bindings["blinkLeft"]["targets"])
		paired.append_array(bindings["blinkRight"]["targets"])
		bindings["blink"] = {"targets": paired, "binary": false}
		_warn("Combined blinkLeft + blinkRight as blink")
	if not bindings.has("blink"):
		_warn("Моргание не подключено. Движения тела доступны; детали — в session.log.")
	diagnostic = {"expressions": bindings.keys(), "blink_available": bindings.has("blink"),
		"warnings": warnings, "mapping": mapping_report, "meshes": inventory}
	return diagnostic

func _marker(object: Object, key: String) -> int:
	if object == null or not is_instance_valid(object):
		return -1
	var extras: Variant = object.get_meta("extras", {})
	if extras is Dictionary and extras.has(key):
		return int(extras[key])
	return -1

func _resolve_mesh(meshes: Array[MeshInstance3D], source: Dictionary, state: GLTFState, node_index: int) -> Dictionary:
	var source_node: Dictionary = source["nodes"][node_index]
	var mesh_index: int = int(source_node.get("mesh", -1))
	if mesh_index < 0:
		return {"reason": "Source node has no mesh"}
	var node_matches: Array[MeshInstance3D] = []
	var mesh_matches: Array[MeshInstance3D] = []
	for instance in meshes:
		if instance.mesh == null:
			continue
		if _marker(instance, Source.NODE_MARKER) == node_index:
			node_matches.append(instance)
		if _marker(instance.mesh, Source.MESH_MARKER) == mesh_index:
			mesh_matches.append(instance)
	if not node_matches.is_empty():
		return _select_unique(node_matches, str(source_node.get("name", "")), "node_metadata")
	if not mesh_matches.is_empty():
		return _select_unique(mesh_matches, str(source_node.get("name", "")), "mesh_metadata")
	# Older import paths can drop node extras. Resource identity is also stable:
	# the converter uses ImporterMesh.get_mesh() for the live ArrayMesh.
	if state != null:
		var imported_meshes: Array = state.get_meshes()
		if mesh_index < imported_meshes.size():
			var importer_mesh: ImporterMesh = imported_meshes[mesh_index].mesh
			if importer_mesh != null:
				var runtime_mesh: ArrayMesh = importer_mesh.get_mesh()
				for instance in meshes:
					if instance.mesh == runtime_mesh:
						mesh_matches.append(instance)
		if not mesh_matches.is_empty():
			return _select_unique(mesh_matches, str(source_node.get("name", "")), "mesh_resource")
	# A last, conservative path for legacy scenes without any metadata.
	# Do not bind to an arbitrary mesh merely because it has a blend shape.
	var source_name: String = str(source_node.get("name", ""))
	if not source_name.is_empty():
		for instance in meshes:
			if instance.mesh != null and str(instance.name) == source_name:
				node_matches.append(instance)
	if not node_matches.is_empty():
		return _select_unique(node_matches, source_name, "exact_node_name")
	return {"reason": "No live mesh for source node %d (mesh %d, name %s)" % [node_index, mesh_index, source_name]}

func _select_unique(candidates: Array[MeshInstance3D], source_name: String, method: String) -> Dictionary:
	if candidates.size() == 1:
		return {"mesh": candidates[0], "method": method}
	var named: Array[MeshInstance3D] = []
	if not source_name.is_empty():
		for instance in candidates:
			if str(instance.name) == source_name:
				named.append(instance)
	if named.size() == 1:
		return {"mesh": named[0], "method": method + "+name"}
	return {"reason": "Ambiguous runtime meshes (%d) for source node %s; binding skipped" % [candidates.size(), source_name]}

func _warn(message: String) -> void:
	if not warnings.has(message):
		warnings.append(message)

func apply(weights: Dictionary) -> void:
	# Clear each managed channel; no residual smile after changing mood.
	for instance in controlled_meshes:
		if not is_instance_valid(instance):
			continue
		for shape_index in controlled_indices[instance.get_instance_id()]:
			instance.set_blend_shape_value(int(shape_index), 0.0)
	for expression in weights:
		if not bindings.has(expression):
			continue
		var definition: Dictionary = bindings[expression]
		var amount: float = clampf(float(weights[expression]), 0.0, 1.0)
		if bool(definition["binary"]):
			amount = 1.0 if amount >= 0.5 else 0.0
		if amount <= 0.0001:
			continue
		for bind in definition["targets"]:
			var mesh: MeshInstance3D = bind["mesh"]
			if not is_instance_valid(mesh):
				continue
			var index: int = int(bind["index"])
			var value: float = mesh.get_blend_shape_value(index) + float(bind["weight"]) * amount
			mesh.set_blend_shape_value(index, clampf(value, 0.0, 1.0))
