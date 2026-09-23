extends RefCounted
## Rare standing micro-gestures. This is not locomotion and never owns foot placement.
## It only adds small upper-body rotations after the ordinary idle rig has been posed.
var rig
var skeleton: Skeleton3D
var available: bool = false
var autonomous_enabled: bool = true
var kind: String = "calm"
var weights: Dictionary = {
	"weight_left": 0.0,
	"weight_right": 0.0,
	"peek_left": 0.0,
	"peek_right": 0.0,
	"hands": 0.0,
	"shoulders": 0.0,
}
var _wait: float = 7.0
var _left: float = 0.0
var _last: String = "shoulders"
var _forced_kind: String = ""
var _forced_left: float = 0.0
var _forced_release: float = 0.0
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
	var forced_requested: bool = not _forced_kind.is_empty() or _forced_release > 0.0
	var allowed: bool = available and not blocked and state.motion_enabled and not state.dozing
	allowed = allowed and (state.autonomy_enabled or forced_requested)
	allowed = allowed and state.posture.mode == "standing" and state.posture.kind == "floor"
	allowed = allowed and state.notice_weight < 0.08 and state.welcome_weight < 0.08 and state.pet_weight < 0.08 and state.wave_weight < 0.08 and not state.release_reaction_active()
	allowed = allowed and walk_weight < 0.05
	var goal: String = "calm"
	if allowed and not _forced_kind.is_empty():
		_forced_left = maxf(0.0, _forced_left - dt)
		if _forced_left > 0.0:
			goal = _forced_kind
		else:
			_forced_kind = ""
			_forced_release = 0.45
	elif allowed and _forced_release > 0.0:
		_forced_release = maxf(0.0, _forced_release - dt)
	elif allowed and autonomous_enabled:
		_left = maxf(0.0, _left - dt)
		_wait -= dt
		if _left <= 0.0 and _wait <= 0.0:
			kind = _choose_kind(state.activity)
			_last = kind
			_left = _duration(kind)
			_wait = _left + _pause(state.activity)
		if _left > 0.0:
			goal = kind
	elif not allowed:
		cancel_forced()
		_left = 0.0
		_wait = maxf(_wait, 4.0)
		kind = "calm"
	for key in weights:
		var target: float = 1.0 if key == goal else 0.0
		weights[key] = lerpf(float(weights[key]), target, 1.0 - exp(-dt * (2.8 if target > 0.0 else 4.4)))
	return weights.duplicate()

func request_gesture(value: String) -> bool:
	if not available or not weights.has(value):
		return false
	_forced_kind = value
	_forced_left = 2.2 if value.begins_with("peek_") else (2.0 if value == "hands" else (2.6 if value == "shoulders" else 2.4))
	_forced_release = 0.0
	_left = 0.0
	kind = value
	_wait = maxf(_wait, _forced_left + 4.0)
	return true

func forced_active() -> bool:
	return not _forced_kind.is_empty() or _forced_release > 0.0

func cancel_forced() -> void:
	_forced_kind = ""
	_forced_left = 0.0
	_forced_release = 0.0

func label() -> String:
	if float(weights["peek_left"]) > 0.55 or float(weights["peek_right"]) > 0.55: return "С любопытством заглядывает"
	if float(weights["hands"]) > 0.55: return "Немного возится с руками"
	if float(weights["shoulders"]) > 0.55: return "Разминает плечи"
	return ""

func _choose_kind(activity: String) -> String:
	var choices: Array = ["weight_left", "weight_right", "hands", "shoulders"]
	if activity != "quiet":
		choices.append("peek_left")
		choices.append("peek_right")
	if activity == "playful" and _rng.randf() < 0.34:
		choices = ["peek_left", "peek_right", "hands", "shoulders"]
	choices.erase(_last)
	return choices[_rng.randi_range(0, choices.size() - 1)]

func _duration(value: String) -> float:
	match value:
		"weight_left", "weight_right":
			return _rng.randf_range(2.8, 4.2)
		"peek_left", "peek_right":
			return _rng.randf_range(1.8, 2.7)
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
	_apply_weight_shift()
	_apply_curiosity_peek()
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

func _apply_weight_shift() -> void:
	var amount: float = float(weights["weight_left"]) - float(weights["weight_right"])
	if absf(amount) <= 0.001:
		return
	var w: float = absf(amount)
	var side: float = signf(amount)
	# Deliberately tiny: this should read as settling onto one leg, not as a pose.
	_add("hips", Vector3(0.0, side * 0.20, side * 0.55) * w)
	_add("spine", Vector3(0.25, -side * 0.35, -side * 0.75) * w)
	_add("chest", Vector3(-0.10, side * 0.20, -side * 0.30) * w)
	_add("neck", Vector3(0.0, -side * 0.45, side * 0.20) * w)
	_add("head", Vector3(0.0, -side * 0.75, side * 0.30) * w)

func _apply_curiosity_peek() -> void:
	var amount: float = float(weights["peek_left"]) - float(weights["peek_right"])
	if absf(amount) <= 0.001:
		return
	var w: float = absf(amount)
	var side: float = signf(amount)
	# A separate readable action: lean forward to inspect something, with only a
	# small side bias. Arms drift behind the torso to counterbalance the lean.
	_add("hips", Vector3(0.7, side * 0.25, -side * 0.35) * w)
	_add("spine", Vector3(7.0, -side * 0.65, -side * 0.90) * w)
	_add("chest", Vector3(4.6, side * 0.50, side * 0.45) * w)
	_add("neck", Vector3(3.2, -side * 1.7, -side * 0.35) * w)
	_add("head", Vector3(8.5, -side * 2.8, -side * 0.70) * w)
	_add("leftShoulder", Vector3(-0.8, 0.0, -0.8) * w)
	_add("rightShoulder", Vector3(-0.8, 0.0, 0.8) * w)
	_add("leftUpperArm", Vector3(5.5, 0.0, 1.0) * w)
	_add("rightUpperArm", Vector3(5.5, 0.0, -1.0) * w)
	_add("leftLowerArm", Vector3(2.5, 0.0, 0.8) * w)
	_add("rightLowerArm", Vector3(2.5, 0.0, -0.8) * w)

func _add(semantic: String, degrees: Vector3) -> void:
	if not rig.bones.has(semantic):
		return
	var bone: int = int(rig.bones[semantic])
	if not rig.parent_rest_rotations.has(bone):
		return
	var parent_q: Quaternion = rig.parent_rest_rotations[bone]
	var extra: Quaternion = parent_q.inverse() * Quaternion.from_euler(degrees * (PI / 180.0)) * parent_q
	skeleton.set_bone_pose_rotation(bone, (extra * skeleton.get_bone_pose_rotation(bone)).normalized())
