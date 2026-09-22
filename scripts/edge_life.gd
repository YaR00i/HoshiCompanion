extends RefCounted
## Small seated activities, not a second locomotion controller.
## Pose weights fade to zero for pickup/stand/doze; pelvis support stays fixed.
var kind: String = "calm"
var autonomous_enabled: bool = true
var weights: Dictionary = {"swing": 0.0, "lean": 0.0, "peek": 0.0, "balance": 0.0}
var _wait: float = 9.0
var _left: float = 0.0
var _last: String = "peek"
var _forced_kind: String = ""
var _forced_left: float = 0.0
var _forced_release: float = 0.0
var _rng := RandomNumberGenerator.new()

func seed_random(value: int) -> void:
	_rng.seed = value

func tick(delta: float, state, suspended: bool = false) -> Dictionary:
	var dt: float = clampf(delta, 0.0, 0.1)
	var allowed: bool = state.posture.kind == "edge" and state.posture.mode == "seated" and state.motion_enabled and not state.dozing and not suspended
	var goal: String = "calm"
	if (state.pet_weight > 0.1 or state.wave_weight > 0.1) and forced_active():
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
		_left = maxf(0.0, _left - dt)
		_wait -= dt
		if _left <= 0.0 and _wait <= 0.0:
			var choices: Array = ["swing", "lean", "peek", "balance"]
			choices.erase(_last)
			kind = choices[_rng.randi_range(0, choices.size() - 1)]
			_last = kind
			_left = 8.0 if kind == "swing" else (14.0 if kind == "lean" else (4.0 if kind == "peek" else 3.5))
			_wait = _left + _rng.randf_range(12.0, 24.0)
		if _left > 0.0:
			goal = kind
	else:
		if not allowed:
			cancel_forced()
		_left = 0.0
		_wait = maxf(_wait, 8.0)
	if state.pet_weight > 0.1 or state.wave_weight > 0.1:
		goal = "calm"
	if state.activity == "quiet" and state.edge_activity == "auto":
		goal = "calm"
	for key in weights:
		weights[key] = lerpf(float(weights[key]), 1.0 if key == goal else 0.0, 1.0 - exp(-dt * 2.6))
	return weights.duplicate()

func request_gesture(value: String) -> bool:
	if not weights.has(value):
		return false
	_forced_kind = value
	_forced_left = 4.0 if value == "swing" else (4.5 if value == "lean" else (3.0 if value == "peek" else 2.8))
	_forced_release = 0.0
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
	if float(weights["swing"]) > 0.55: return "Болтает ножками"
	if float(weights["lean"]) > 0.55: return "Откинулась, опираясь на ладони"
	if float(weights["peek"]) > 0.55: return "С любопытством смотрит вниз"
	return ""
