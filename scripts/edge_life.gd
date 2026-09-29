extends RefCounted
## Small seated activities, not a second locomotion controller.
## Pose weights fade to zero for pickup/stand/doze; pelvis support stays fixed.
const SeatedMotion = preload("res://scripts/seated_motion.gd")
const SketchMotion = preload("res://scripts/sketch_motion.gd")
signal paper_star_completed
## Сценка дошла до метки «Ждёт» на шкале клипа и ждёт клика (answer_wait).
signal wait_started(gesture: String)
## Ожидание кончилось: answered — кликнули; иначе — не дождалась (WAIT_LIMIT).
signal wait_finished(gesture: String, answered: bool)
const WAIT_MARKER: StringName = &"Ждёт"
## Мелочь сидя (поверх спокойной позы): touch_reactions играет её как «вызов».
signal micro_requested(kind: String)
const MICRO := {"stretch": 4.2, "hair": 2.6, "doze": 5.0}
## Большие сценки с предметами — редкое событие, не чаще раза в BIG_COOLDOWN с.
const BIG: Array[String] = ["sketch", "fold"]
const BIG_COOLDOWN: float = 720.0
const WAIT_LIMIT: float = 25.0
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
## Linear blend state behind `weights`; the published weights are eased (smoothstep)
## so every gesture starts and settles softly instead of jumping in at full speed.
var _blend: Dictionary = {}
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
## Какая сценка сейчас ждёт клика ("" — никакая) и сколько уже ждёт.
var waiting: String = ""
var wait_age: float = 0.0
## 1 сразу после ответа, гаснет за ~2 с — радость на лице.
var wait_joy: float = 0.0
var _wait_done: Dictionary = {}
## Что вокруг (ставит companion): играет ли музыка, поздно ли — сонная.
var music: bool = false
var sleepy: bool = false
var _clock: float = 0.0
## Первая большая сценка — не раньше чем через ~6 минут после запуска.
var _big_at: Dictionary = {"sketch": -BIG_COOLDOWN * 0.5, "fold": -BIG_COOLDOWN * 0.5}
## Rhythmic gestures fade out slower when they simply end (no one interrupted),
## so she settles instead of stopping.
const FADE_RATE: float = 2.6
const GENTLE_FADE_RATE: float = 1.1
var _rng := RandomNumberGenerator.new()

func seed_random(value: int) -> void:
	_rng.seed = value

func tick(delta: float, state, suspended: bool = false, cozy: bool = false) -> Dictionary:
	var dt: float = clampf(delta, 0.0, 0.1)
	_clock += dt
	var allowed: bool = state.posture.kind == "edge" and state.posture.mode == "seated" and state.motion_enabled and not state.dozing and not suspended
	var goal: String = "calm"
	var interrupted: bool = not allowed or state.notice_weight > 0.1 or state.welcome_weight > 0.1 or state.pet_weight > 0.1 or state.wave_weight > 0.1
	if (state.notice_weight > 0.1 or state.welcome_weight > 0.1 or state.pet_weight > 0.1 or state.wave_weight > 0.1) and forced_active():
		cancel_forced()
	if allowed and not cozy and _forced_kind in ["sketch", "fold", "admire_star"]:
		cancel_forced()
	var held: bool = not waiting.is_empty() # пока ждёт — время сценки стоит
	if allowed and not _forced_kind.is_empty():
		_forced_left = maxf(0.0, _forced_left - (0.0 if held and waiting == _forced_kind else dt))
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
		if not (held and waiting == kind):
			_left = maxf(0.0, _left - dt)
			_wait -= dt
		if _left <= 0.0 and _wait <= 0.0:
			while choices.has(_last) and choices.size() > 1:
				choices.erase(_last)
			kind = choices[_rng.randi_range(0, choices.size() - 1)]
			_last = kind
			if MICRO.has(kind):
				# Мелочь: поза остаётся спокойной, движение — поверх (avatar_stage).
				_left = float(MICRO[kind])
				micro_requested.emit(kind)
			else:
				_left = _run_length(kind, state.activity, cozy)
			_wait = _left + _pause(state.activity, kind)
		if _left > 0.0 and not MICRO.has(kind):
			goal = kind
	else:
		if not allowed:
			cancel_forced()
		_left = 0.0
		_wait = maxf(_wait, 8.0)
	if state.notice_weight > 0.1 or state.welcome_weight > 0.1 or state.pet_weight > 0.1 or state.wave_weight > 0.1:
		goal = "calm"
	if goal != _previous_goal:
		# A loop that is still visible keeps its phase, so coming back to it never pops.
		if weights.has(goal) and goal != "sketch" and not (SeatedMotion.loops(goal) and float(weights[goal]) > 0.05):
			_gesture_age[goal] = 0.0
		_wait_done.erase(goal)
		if goal in BIG:
			_big_at[goal] = _clock
		_previous_goal = goal
	var goal_dt: float = _wait_step(goal, dt)
	wait_joy = maxf(0.0, wait_joy - dt * 0.5)
	if goal == "sketch":
		_sketch_age = minf(_sketch_age + goal_dt, SketchMotion.clip.length)
		sketch_progress = _sketch_age / SketchMotion.clip.length
	else:
		_sketch_age = 0.0
	if goal == "fold":
		_fold_age = minf(_fold_age + goal_dt, float(SeatedMotion.DURATIONS["fold"]))
		fold_progress = _fold_age / float(SeatedMotion.DURATIONS["fold"])
		if fold_progress >= 0.95 and not _fold_result_emitted:
			_fold_result_emitted = true
			paper_star_completed.emit()
	else:
		_fold_age = 0.0
		fold_progress = 0.0
		_fold_result_emitted = false
	if goal == "admire_star":
		_admire_age = minf(_admire_age + goal_dt, float(SeatedMotion.DURATIONS["admire_star"]))
		admire_progress = _admire_age / float(SeatedMotion.DURATIONS["admire_star"])
	else:
		_admire_age = 0.0
		admire_progress = 0.0
	for gesture in weights:
		if gesture == "sketch":
			continue
		var looping: bool = SeatedMotion.loops(gesture)
		if looping and (gesture == goal or float(weights[gesture]) >= 0.01):
			# Loops keep running while they play AND while they fade out.
			_gesture_age[gesture] = fposmod(float(_gesture_age.get(gesture, 0.0)) + dt, _duration(gesture))
		elif gesture == goal:
			_gesture_age[gesture] = minf(float(_gesture_age.get(gesture, 0.0)) + goal_dt, _duration(gesture))
		elif float(weights[gesture]) < 0.01:
			_gesture_age[gesture] = 0.0
		gesture_progress[gesture] = clampf(float(_gesture_age.get(gesture, 0.0)) / _duration(gesture), 0.0, 1.0)
	for key in weights:
		var rate: float = FADE_RATE
		if key != goal and goal == "calm" and not interrupted and SeatedMotion.loops(str(key)):
			rate = GENTLE_FADE_RATE
		var raw: float = lerpf(float(_blend.get(key, 0.0)), 1.0 if key == goal else 0.0, 1.0 - exp(-dt * rate))
		_blend[key] = raw
		weights[key] = smoothstep(0.0, 1.0, raw)
	return weights.duplicate()

func request_gesture(value: String) -> bool:
	if not weights.has(value):
		return false
	_forced_kind = value
	_wait_done.erase(value)
	if waiting == value:
		waiting = ""
	if not (SeatedMotion.loops(value) and float(weights[value]) > 0.05):
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

## Идёт сценка с предметом (блокнот, бумажная звезда) — клики её не прерывают.
func prop_scene_active() -> bool:
	for gesture in ["sketch", "fold", "admire_star"]:
		if float(weights.get(gesture, 0.0)) > 0.05:
			return true
	return not waiting.is_empty()

## Клик во время ожидания: сценка идёт дальше, Хоши радуется.
func answer_wait() -> bool:
	if waiting.is_empty():
		return false
	var gesture: String = waiting
	waiting = ""
	wait_joy = 1.0
	wait_finished.emit(gesture, true)
	return true

## Время метки «Ждёт» в клипе сценки, или -1 (сценка не ждёт).
func wait_time(gesture: String) -> float:
	var clip: Animation = SketchMotion.clip if gesture == "sketch" else (SeatedMotion.clip_for(gesture) if SeatedMotion.DURATIONS.has(gesture) else null)
	if clip == null or SeatedMotion.loops(gesture) or not clip.has_marker(WAIT_MARKER):
		return -1.0
	return clip.get_marker_time(WAIT_MARKER)

func _age(gesture: String) -> float:
	match gesture:
		"sketch": return _sketch_age
		"fold": return _fold_age
		"admire_star": return _admire_age
	return float(_gesture_age.get(gesture, 0.0))

## Сколько времени сценке пройти в этом кадре: 0, пока она ждёт клика.
func _wait_step(goal: String, dt: float) -> float:
	if not waiting.is_empty() and waiting != goal:
		waiting = "" # сценку прервали (подняли, погладили, уснула) — ждать нечего
	if waiting == goal and not waiting.is_empty():
		wait_age += dt
		if wait_age >= WAIT_LIMIT:
			waiting = ""
			wait_finished.emit(goal, false)
		return 0.0
	var at: float = wait_time(goal)
	if at < 0.0 or _wait_done.has(goal):
		return dt
	var age: float = _age(goal)
	if age + dt < at:
		return dt
	_wait_done[goal] = true
	waiting = goal
	wait_age = 0.0
	wait_started.emit(goal)
	return maxf(0.0, at - age)

func label() -> String:
	if not waiting.is_empty(): return "Ждёт, когда ты посмотришь"
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

## Большую сценку можно снова (прошло BIG_COOLDOWN с с прошлой).
func big_ready(value: String) -> bool:
	return _clock - float(_big_at.get(value, -BIG_COOLDOWN)) >= BIG_COOLDOWN

## Из чего выбирать сидя. Основное — спокойные мелочи; рисунок и звёздочка —
## редко (big_ready); музыка — кивает и напевает; поздно — зевает и клюёт носом.
func _choices(activity: String, cozy: bool = false) -> Array[String]:
	var result: Array[String] = []
	if cozy:
		match activity:
			"quiet": result = ["sway", "sway", "hair", "stretch"]
			"playful": result = ["sway", "swing", "swing", "lean", "peek", "balance", "hair", "stretch"]
			_: result = ["sway", "swing", "lean", "peek", "balance", "hair", "stretch"]
		for big in BIG:
			if big_ready(big) or (kind == big and _left > 0.0):
				result.append(big)
	else:
		match activity:
			"quiet": result = ["sway", "hair"]
			"playful": result = ["sway", "sway", "swing", "lean", "peek", "balance", "hair"]
			_: result = ["sway", "swing", "lean", "peek", "balance", "hair"]
	if music:
		result.append_array(["nod", "hum", "nod"])
	elif sleepy:
		result.append_array(["doze", "stretch", "doze"])
	return result

func _duration(value: String) -> float:
	if value == "sketch":
		return SketchMotion.clip.length
	if SeatedMotion.DURATIONS.has(value):
		return float(SeatedMotion.DURATIONS[value])
	return 3.0

## How long one autonomous run lasts. Loops repeat a few times instead of playing once;
## in the quiet corner the sway goes on for a long, calm while.
func _run_length(value: String, activity: String, cozy: bool = false) -> float:
	var length: float = _duration(value)
	if not SeatedMotion.loops(value):
		return length
	var cycles: int = 1
	if value == "sway":
		match activity:
			"quiet": cycles = _rng.randi_range(5, 8) if cozy else _rng.randi_range(4, 7)
			"playful": cycles = _rng.randi_range(1, 2)
			_: cycles = _rng.randi_range(2, 4)
	else:
		cycles = _rng.randi_range(1, 2)
	return length * float(cycles)

func _pause(activity: String, value: String = "") -> float:
	match activity:
		"quiet":
			# After a long sway she just sits and breathes a little before the next thing.
			return _rng.randf_range(6.0, 12.0) if value == "sway" else _rng.randf_range(18.0, 32.0)
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
