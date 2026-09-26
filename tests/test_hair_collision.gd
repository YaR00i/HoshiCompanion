extends SceneTree
## Exercises the actual VRM hair solver through fall and landing poses.
## Measures strand joints against the avatar's authored body spheres.

const Stage = preload("res://scripts/avatar_stage.gd")
const State = preload("res://scripts/companion_state.gd")

var stage
var skeleton: Skeleton3D
var probes: Array = []
var spheres: Array = []
var phase: String = "idle"
var worst: Dictionary = {}
var worst_by_phase: Dictionary = {}
var samples: int = 0
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	stage = Stage.new()
	stage.size = Vector2(560, 620)
	root.add_child(stage)
	await process_frame
	var loaded: Dictionary = stage.load_model("res://assets/Hoshi_v1.vrm")
	_check(not loaded.has("error"), "load local Hoshi VRM for hair collision check")
	if loaded.has("error"):
		print("HOSHI_HAIR_COLLISION_RESULT checks=", checks, " failures=", failures)
		quit(1)
		return
	skeleton = stage.rig.skeleton
	var simulator: SpringBoneSimulator3D = stage.rig.hair_springs.simulator
	_check(simulator.setting_count == 18 and stage.rig.hair_springs.collider_count == 22,
		"authored hair chains and body spheres are bound")
	_check(simulator.get_collision_count(0) == 22 and simulator.has_node(simulator.get_collision_path(0, 0)),
		"the solver resolves its collision nodes")
	var raw: Dictionary = stage.model_data["source"]
	var nodes: Array = raw.get("nodes", [])
	var extension: Dictionary = raw.get("extensions", {}).get("VRMC_springBone", {})
	for chain in extension.get("springs", []):
		if "hair" not in str(chain.get("name", "")).to_lower():
			continue
		var joints: Array = chain.get("joints", [])
		for index in range(1, joints.size()):
			var bone_name: String = str(nodes[int(joints[index]["node"])].get("name", ""))
			var bone_id: int = skeleton.find_bone(bone_name)
			if bone_id >= 0:
				probes.append({"bone": bone_id, "name": bone_name, "radius": float(joints[index]["hitRadius"])})
	for collider in extension.get("colliders", []):
		var bone_name: String = str(nodes[int(collider["node"])].get("name", ""))
		var bone_id: int = skeleton.find_bone(bone_name)
		if bone_id < 0:
			continue
		var sphere: Dictionary = collider.get("shape", {}).get("sphere", {})
		if sphere.is_empty():
			continue
		var xyz: Array = sphere.get("offset", [0, 0, 0])
		spheres.append({"bone": bone_id, "name": bone_name, "offset": Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2])), "radius": float(sphere.get("radius", 0.0))})
	stage.rig.hair_springs.simulator.modification_processed.connect(_sample)
	var state = State.new()
	state.motion_enabled = true
	for frame in range(140):
		if frame < 20:
			phase = "idle"
			stage.set_context_action("idle")
		elif frame < 90:
			phase = "fall"
			stage.set_context_action("fall", Vector2(180.0, 800.0), float(frame - 20) / 70.0, 1.15)
		else:
			phase = "land"
			stage.set_context_action("land", Vector2(60.0, 0.0), float(frame - 90) / 50.0, 1.15)
		state.tick(1.0 / 30.0)
		stage.animate(1.0 / 30.0, state, Vector2.ZERO)
		await process_frame
	_check(samples > 100, "the native modifier processed the falling avatar")
	_check(worst_by_phase.has("fall") and float(worst_by_phase["fall"]["overlap"]) < 0.01,
		"falling strands stay outside the authored body spheres")
	_check(worst_by_phase.has("land") and float(worst_by_phase["land"]["overlap"]) < 0.025,
		"landing strands avoid deep penetration during compression")
	print("HOSHI_HAIR_COLLISION_RESULT checks=", checks, " failures=", failures,
		" fall_overlap_m=", worst_by_phase.get("fall", {}).get("overlap", "missing"),
		" land_overlap_m=", worst_by_phase.get("land", {}).get("overlap", "missing"))
	quit(1 if failures > 0 else 0)

func _sample() -> void:
	samples += 1
	for hair in probes:
		var point: Vector3 = skeleton.get_bone_global_pose(int(hair["bone"])).origin
		for sphere in spheres:
			var center: Vector3 = skeleton.get_bone_global_pose(int(sphere["bone"])) * sphere["offset"]
			var overlap: float = float(hair["radius"]) + float(sphere["radius"]) - point.distance_to(center)
			if worst.is_empty() or overlap > float(worst["overlap"]):
				worst = {"phase": phase, "hair": hair["name"], "body": sphere["name"], "overlap": snappedf(overlap, 0.0001)}
			if not worst_by_phase.has(phase) or overlap > float(worst_by_phase[phase]["overlap"]):
				worst_by_phase[phase] = {"hair": hair["name"], "body": sphere["name"], "overlap": snappedf(overlap, 0.0001)}
