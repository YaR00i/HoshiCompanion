extends RefCounted
## Small seated activities, not a second locomotion controller.
## Pose weights fade to zero for pickup/stand/doze; pelvis support stays fixed.
const SeatedMotion = preload("res://scripts/seated_motion.gd")
const SketchMotion = preload("res://scripts/sketch_motion.gd")
signal paper_star_completed
var kind: String = "calm"
var autonomous_enabled: bool = true
var weights: Dictionary = {
	"swing": 0.0,
	"lean": 0.0,
	"peek": 0.0,
	"balance": 0.0,
	"sway": 0.0,
	"hum": 0.0,
	"nod": 0.0,
	"sketch": 0.0,
	"fold": 0.0,
	"admire_star": 0.0,
}
var sketch_progress: float = 0.0
var gesture_progress: Dictionary = {}
var _gesture_age: Dictionary = {}
var _sketch_age: float = 0.0
var fold_progress: float = 0.0
var admire_progress: float = 0.0
var _fold_age: float = 0.0
var _admire_age: float = 0.0
var _fold_result_emitted: bool = false
var _wait: float = 9.0
var _left: float = 0.0
var _last: String = "peek"
var _forced_kind: String = ""
var _forced_left: float = 0.0
var _forced_release: float = 0.0
var _previous_goal: String = "calm"
var _rng := RandomNumberGenerator.new()

func seed_random(value: int) -> void:
	_rng.seed = value

func tick(delta: float, state, suspended: bool = false, cozy: bool = false) -> Dictionary:
	var dt: float = clampf(delta, 0.0, 0.1)
	var allowed: bool = state.posture.kind == "edge" and state.posture.mode == "seated" and state.motion_enabled and not state.dozing and not suspended
	var goal: String = "calm"
	if (state.notice_weight > 0.1 or state.welcome_weight > 0.1 or state.pet_weight > 0.1 or state.wave_weight > 0.1) and forced_active():
		cancel_forced()
	if allowed and not cozy and _forced_kind in ["sketch", "fold", "admire_star"]:
		cancel_forced()
	if allowed and not _forced_kind.is_empty():
		_forced_left = maxf(0.0, _forced_left - dt)
		if _forced_left > 0.0:
			goal = _forced_kind
		else:
			_forced_kind = ""
			_forced_release = 0.45
	elif allowed and _forced_release > 0.0:
		_forced_release = maxf(0.0, _forced_release - dt)
	elif allowed and state.edge_activity != "auto":
		goal = state.edge_activity
	elif allowed and state.autonomy_enabled and autonomous_enabled:
		var choices: Array[String] = _choices(state.activity, cozy)
		if not choices.has(kind):
			_left = 0.0
		_left = maxf(0.0, _left - dt)
		_wait -= dt
		if _left <= 0.0 and _wait <= 0.0:
			while choices.has(_last) and choices.size() > 1:
				choices.erase(_last)
			kind = choices[_rng.randi_range(0, choices.size() - 1)]
			_last = kind
			_left = _duration(kind)
			_wait = _left + _pause(state.activity)
		if _left > 0.0:
			goal = kind
	else:
		if not allowed:
			cancel_forced()
		_left = 0.0
		_wait = maxf(_wait, 8.0)
	if state.notice_weight > 0.1 or state.welcome_weight > 0.1 or state.pet_weight > 0.1 or state.wave_weight > 0.1:
		goal = "calm"
	if goal != _previous_goal:
		if weights.has(goal) and goal != "sketch":
			_gesture_age[goal] = 0.0
		_previous_goal = goal
	if goal == "sketch":
		_sketch_age = minf(_sketch_age + dt, SketchMotion.clip.length)
		sketch_progress = _sketch_age / SketchMotion.clip.length
	else:
		_sketch_age = 0.0
	if goal == "fold":
		_fold_age = minf(_fold_age + dt, float(SeatedMotion.DURATIONS["fold"]))
		fold_progress = _fold_age / float(SeatedMotion.DURATIONS["fold"])
		if fold_progress >= 0.95 and not _fold_result_emitted:
			_fold_result_emitted = true
			paper_star_completed.emit()
	else:
		_fold_age = 0.0
		fold_progress = 0.0
		_fold_result_emitted = false
	if goal == "admire_star":
		_admire_age = minf(_admire_age + dt, float(SeatedMotion.DURATIONS["admire_star"]))
		admire_progress = _admire_age / float(SeatedMotion.DURATIONS["admire_star"])
	else:
		_admire_age = 0.0
		admire_progress = 0.0
	for gesture in weights:
		if gesture == "sketch":
			continue
		if gesture == goal:
			_gesture_age[gesture] = minf(float(_gesture_age.get(gesture, 0.0)) + dt, _duration(gesture))
		elif float(weights[gesture]) < 0.01:
			_gesture_age[gesture] = 0.0
		gesture_progress[gesture] = clampf(float(_gesture_age.get(gesture, 0.0)) / _duration(gesture), 0.0, 1.0)
	for key in weights:
		weights[key] = lerpf(float(weights[key]), 1.0 if key == goal else 0.0, 1.0 - exp(-dt * 2.6))
	return weights.duplicate()

func request_gesture(value: String) -> bool:
	if not weights.has(value):
		return false
	_forced_kind = value
	_gesture_age[value] = 0.0
	_forced_left = _forced_duration(value)
	_forced_release = 0.0
	if value == "sketch":
		_sketch_age = 0.0
		sketch_progress = 0.0
	if value == "fold":
		_fold_age = 0.0
		fold_progress = 0.0
		_fold_result_emitted = false
	if value == "admire_star":
		_admire_age = 0.0
		admire_progress = 0.0
	_left = 0.0
	kind = value
	_wait = maxf(_wait, _forced_left + 6.0)
	return true

func forced_active() -> bool:
	return not _forced_kind.is_empty() or _forced_release > 0.0

func cancel_forced() -> void:
	_forced_kind = ""
	_forced_left = 0.0
	_forced_release = 0.0

func label() -> String:
	if float(weights["fold"]) > 0.55: return "Складывает бумажную звезду"
	if float(weights["admire_star"]) > 0.55: return "Показывает свою звёздочку"
	if float(weights["sketch"]) > 0.55: return "Рисует звёздочку"
	if float(weights["sway"]) > 0.55: return "Мягко покачивается в ритме"
	if float(weights["hum"]) > 0.55: return "Тихонько напевает себе под нос"
	if float(weights["nod"]) > 0.55: return "Кивает в такт"
	if float(weights["swing"]) > 0.55: return "Болтает ножками"
	if float(weights["lean"]) > 0.55: return "Откинулась, опираясь на ладони"
	if float(weights["peek"]) > 0.55: return "С любопытством смотрит вниз"
	return ""

func _choices(activity: String, cozy: bool = false) -> Array[String]:
	if cozy:
		match activity:
			"quiet": return ["sway", "sway", "sketch", "fold"]
			"playful": return ["sway", "swing", "lean", "peek", "balance", "sketch", "fold"]
		return ["sway", "swing", "lean", "peek", "balance", "sketch", "fold"]
	match activity:
		"quiet":
			return ["sway"]
		"playful":
			# Accepted rhythmic sway is more likely; hum/nod remain manual drafts.
			return ["sway", "sway", "swing", "lean", "peek", "balance"]
	return ["sway", "swing", "lean", "peek", "balance"]

func _duration(value: String) -> float:
	if value == "sketch":
		return SketchMotion.clip.length
	if SeatedMotion.DURATIONS.has(value):
		return float(SeatedMotion.DURATIONS[value])
	return 3.0

func _pause(activity: String) -> float:
	match activity:
		"quiet": return _rng.randf_range(18.0, 32.0)
		"playful": return _rng.randf_range(7.0, 15.0)
	return _rng.randf_range(12.0, 24.0)

func _forced_duration(value: String) -> float:
	match value:
		# Preserve the existing planner gesture lengths; ambient actions are longer.
		"swing": return 4.0
		"lean": return 4.5
		"peek": return 3.0
		"balance": return 2.8
		"sway": return 5.5
		"hum": return 4.8
		"nod": return 3.6
		"sketch", "fold", "admire_star": return _duration(value)
	return 3.0
