extends RefCounted
## Rare standing micro-gestures. This is not locomotion and never owns foot placement.
## It only adds small upper-body rotations after the ordinary idle rig has been posed.
var rig
var skeleton: Skeleton3D
var available: bool = false
var kind: String = "calm"
var weights: Dictionary = {
	"shift_left": 0.0,
	"shift_right": 0.0,
	"hands": 0.0,
	"shoulders": 0.0,
}
var _wait: float = 7.0
var _left: float = 0.0
var _last: String = "shoulders"
var _rng := RandomNumberGenerator.new()

func setup(rig_driver) -> Dictionary:
	rig = rig_driver
	skeleton = rig.skeleton
	available = skeleton != null and rig.bones.has("hips") and rig.bones.has("head")
	return {"available": available}

func seed_random(value: int) -> void:
	_rng.seed = value
	_wait = _rng.randf_range(5.0, 9.0)
	_left = 0.0
	_last = "shoulders"

func tick(delta: float, state, blocked: bool = false, walk_weight: float = 0.0) -> Dictionary:
	var dt: float = clampf(delta, 0.0, 0.1)
	var allowed: bool = available and not blocked
	allowed = allowed and state.autonomy_enabled and state.motion_enabled and not state.dozing
	allowed = allowed and state.posture.mode == "standing" and state.posture.kind == "floor"
	allowed = allowed and state.pet_weight < 0.08 and state.wave_weight < 0.08
	allowed = allowed and walk_weight < 0.05
	var goal: String = "calm"
	if allowed:
		_left = maxf(0.0, _left - dt)
		_wait -= dt
		if _left <= 0.0 and _wait <= 0.0:
			var choices: Array = ["shift_left", "shift_right", "hands", "shoulders"]
			choices.erase(_last)
			if state.activity == "quiet":
				choices.erase("shoulders")
			kind = choices[_rng.randi_range(0, choices.size() - 1)]
			_last = kind
			_left = _duration(kind)
			_wait = _left + _pause(state.activity)
		if _left > 0.0:
			goal = kind
	else:
		_left = 0.0
		_wait = maxf(_wait, 4.0)
		kind = "calm"
	for key in weights:
		var target: float = 1.0 if key == goal else 0.0
		weights[key] = lerpf(float(weights[key]), target, 1.0 - exp(-dt * (2.8 if target > 0.0 else 4.4)))
	return weights.duplicate()

func _duration(value: String) -> float:
	match value:
		"shift_left", "shift_right":
			return _rng.randf_range(2.6, 3.6)
		"hands":
			return _rng.randf_range(2.0, 2.8)
		"shoulders":
			return _rng.randf_range(2.8, 3.8)
	return 2.5

func _pause(activity: String) -> float:
	match activity:
		"quiet":
			return _rng.randf_range(18.0, 32.0)
		"playful":
			return _rng.randf_range(6.0, 12.0)
	return _rng.randf_range(10.0, 20.0)

func apply(time: float) -> void:
	if not available:
		return
	var left: float = float(weights["shift_left"])
	var right: float = float(weights["shift_right"])
	var shift: float = left - right
	if absf(shift) > 0.001:
		# A curious standing peek: mostly forward, only a little sideways. The old
		# version bent the whole torso sideways and read like a waist kink.
		var w: float = absf(shift)
		var side: float = signf(shift)
		_add("hips", Vector3(1.2, side * 0.6, -side * 0.9) * w)
		_add("spine", Vector3(8.5, -side * 1.2, -side * 2.2) * w)
		_add("chest", Vector3(6.0, side * 1.0, side * 1.1) * w)
		_add("neck", Vector3(4.0, -side * 2.8, -side * 0.8) * w)
		_add("head", Vector3(10.5, -side * 4.5, -side * 1.6) * w)
		# Both arms drift behind the torso for balance instead of one hand appearing
		# to hook awkwardly against the waist.
		_add("leftShoulder", Vector3(-1.5, 0.0, -1.5) * w)
		_add("rightShoulder", Vector3(-1.5, 0.0, 1.5) * w)
		_add("leftUpperArm", Vector3(8.0, 0.0, 2.0) * w)
		_add("rightUpperArm", Vector3(8.0, 0.0, -2.0) * w)
		_add("leftLowerArm", Vector3(4.0, 0.0, 1.5) * w)
		_add("rightLowerArm", Vector3(4.0, 0.0, -1.5) * w)
	var hands: float = float(weights["hands"])
	if hands > 0.001:
		var small: float = sin(time * 3.8) * 1.5
		_add("leftLowerArm", Vector3(-1.5, 0.0, (-3.0 + small) * hands))
		_add("rightLowerArm", Vector3(-1.5, 0.0, (3.0 - small) * hands))
		_add("leftHand", Vector3(small * 0.8, 0.0, -3.0) * hands)
		_add("rightHand", Vector3(-small * 0.8, 0.0, 3.0) * hands)
	var shoulders: float = float(weights["shoulders"])
	if shoulders > 0.001:
		var settle: float = 0.75 + sin(time * 1.9) * 0.25
		_add("spine", Vector3(-1.2 * settle, 0.0, 0.0) * shoulders)
		_add("chest", Vector3(-2.2 * settle, 0.0, 0.0) * shoulders)
		_add("leftShoulder", Vector3(-2.0, 0.0, -2.2) * shoulders)
		_add("rightShoulder", Vector3(-2.0, 0.0, 2.2) * shoulders)
		_add("neck", Vector3(1.2, 0.0, 0.0) * shoulders)
		_add("head", Vector3(1.8, 0.0, 0.0) * shoulders)

func _add(semantic: String, degrees: Vector3) -> void:
	if not rig.bones.has(semantic):
		return
	var bone: int = int(rig.bones[semantic])
	if not rig.parent_rest_rotations.has(bone):
		return
	var parent_q: Quaternion = rig.parent_rest_rotations[bone]
	var extra: Quaternion = parent_q.inverse() * Quaternion.from_euler(degrees * (PI / 180.0)) * parent_q
	skeleton.set_bone_pose_rotation(bone, (extra * skeleton.get_bone_pose_rotation(bone)).normalized())
