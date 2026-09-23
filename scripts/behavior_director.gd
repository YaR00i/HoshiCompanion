extends RefCounted
## Bounded initiative, local-only. No screenshots, title scanning, timers outside
## the process, microphone or chat. Identical seed + input -> identical behavior.

var activity: String = "normal"
var enabled: bool = true
var decisions_enabled: bool = true
var walk_enabled: bool = true
var rest_enabled: bool = true
var rest_after_walk: bool = false
var _rest_wait: float = 50.0
var gaze: Vector2 = Vector2.ZERO
var curiosity: float = 0.0
var attention_label: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _wait: float = 8.0
var _walk_wait: float = 20.0
var _gesture_wait: float = 60.0
var _look_left: float = 0.0
var _look_duration: float = 0.0
var _look_mode: String = "away"
var _away: Vector2 = Vector2.ZERO
var _cooldown: float = 0.0
var _last_kind: String = ""

func seed_random(value: int) -> void:
	_rng.seed = value
	_wait = _rng.randf_range(8.0, 14.0)
	_walk_wait = _rng.randf_range(18.0, 28.0)
	_gesture_wait = _rng.randf_range(35.0, 60.0)

func set_activity(value: String) -> void:
	if not value in ["quiet", "normal", "playful"]:
		return
	activity = value
	_look_left = 0.0
	curiosity = 0.0
	gaze = Vector2.ZERO
	_wait = 4.0
	_walk_wait = maxf(_walk_wait, 8.0)
	rest_after_walk = false

func user_interaction() -> void:
	_cooldown = 8.0
	_look_left = 2.2
	_look_duration = 2.2
	_look_mode = "cursor"
	curiosity = 0.0
	_walk_wait = maxf(_walk_wait, 10.0)
	rest_after_walk = false

func tick(delta: float, context: Dictionary) -> String:
	var dt: float = clampf(delta, 0.0, 0.1)
	var blocked: bool = bool(context.get("blocked", false))
	_cooldown = maxf(0.0, _cooldown - dt)
	_walk_wait = maxf(0.0, _walk_wait - dt)
	_gesture_wait = maxf(0.0, _gesture_wait - dt)
	_rest_wait = maxf(0.0, _rest_wait - dt)
	rest_after_walk = false
	if blocked:
		gaze = Vector2.ZERO
		curiosity = move_toward(curiosity, 0.0, dt * 3.0)
		attention_label = ""
		return ""
	var cursor: Vector2 = context.get("cursor_gaze", Vector2.ZERO)
	var near: bool = bool(context.get("cursor_near", false))
	if not enabled:
		gaze = cursor if near else Vector2.ZERO
		curiosity = 0.0
		attention_label = ""
		return ""
	_wait -= dt
	_look_left = maxf(0.0, _look_left - dt)
	if _look_left > 0.0:
		var blend: float = minf(smoothstep(0.0, 0.5, _look_left), smoothstep(0.0, 0.4, _look_duration - _look_left))
		gaze = (cursor if _look_mode == "cursor" and near else _away) * blend
		curiosity = blend * (0.65 if _look_mode == "cursor" else 0.15)
		attention_label = "Следит за курсором" if _look_mode == "cursor" and near else "Оглядывается"
	else:
		gaze = Vector2.ZERO
		curiosity = 0.0
		attention_label = ""
	if not decisions_enabled or _wait > 0.0 or _cooldown > 0.0:
		return ""
	_wait = _next_decision_wait()
	var can_rest: bool = rest_enabled and bool(context.get("can_rest", false)) and _rest_wait <= 0.0
	var can_walk: bool = activity != "quiet" and walk_enabled and bool(context.get("can_walk", false)) and _walk_wait <= 0.0 and _last_kind != "walk"
	var can_wave: bool = activity == "playful" and _gesture_wait <= 0.0 and _last_kind != "wave"
	var roll: float = _rng.randf()
	if activity == "quiet":
		if can_rest and roll < 0.24:
			_begin_rest()
			return "sit"
	elif activity == "normal":
		if can_rest and roll < 0.18:
			_begin_rest()
			return "sit"
		if can_walk and roll < 0.50:
			_begin_walk(0.30)
			return "walk"
	elif activity == "playful":
		if can_rest and roll < 0.07:
			_begin_rest()
			return "sit"
		if can_walk and roll < 0.56:
			_begin_walk(0.10)
			return "walk"
		if can_wave and roll < 0.74:
			_gesture_wait = _rng.randf_range(35.0, 70.0)
			_last_kind = "wave"
			return "wave"
	_begin_look(cursor, near)
	return ""

func _next_decision_wait() -> float:
	match activity:
		"quiet":
			return _rng.randf_range(18.0, 32.0)
		"playful":
			return _rng.randf_range(4.5, 9.0)
	return _rng.randf_range(8.0, 15.0)

func _begin_rest() -> void:
	rest_started()
	_last_kind = "sit"

func _begin_walk(rest_probability: float) -> void:
	_walk_wait = _rng.randf_range(32.0, 58.0) if activity == "normal" else _rng.randf_range(16.0, 30.0)
	rest_after_walk = rest_enabled and _rng.randf() < rest_probability
	_last_kind = "walk"

func request_observe(cursor: Vector2, near: bool) -> float:
	_begin_look(cursor, near)
	return _look_duration

func look_active() -> bool:
	return _look_left > 0.0

func _begin_look(cursor: Vector2, near: bool) -> void:
	_look_mode = "cursor" if near and _last_kind != "cursor" else "away"
	_away = Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.23, 0.15))
	_look_duration = _rng.randf_range(1.8, 3.8)
	_look_left = _look_duration
	_last_kind = _look_mode

func automatic_rest_duration() -> float:
	match activity:
		"quiet":
			return 32.0
		"playful":
			return 14.0
	return 24.0

func rest_started() -> void:
	_rest_wait = _rng.randf_range(110.0, 150.0)
	_walk_wait = maxf(_walk_wait, 18.0)
