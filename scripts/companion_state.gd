extends RefCounted
## Pure local state: deterministic when seeded. No LLM, microphone or monitoring.

const Posture = preload("res://scripts/posture_controller.gd")
var posture = Posture.new()
var rest_enabled: bool = true
var place_mode: String = "off"
var edge_activity: String = "auto"
var sleep_requested: bool = false

const MOODS: PackedStringArray = ["neutral", "happy", "relaxed", "surprised", "sad"]
var mood: String = "neutral"
var activity: String = "normal"
var autonomy_enabled: bool = true
var walk_enabled: bool = true
var curiosity: float = 0.0
var dozing: bool = false
var look_enabled: bool = true
var motion_enabled: bool = true
var hair_enabled: bool = true
var pet_weight: float = 0.0
var wave_weight: float = 0.0
var sleep_weight: float = 0.0
var time: float = 0.0
var blink: float = 0.0
var _pet_left: float = 0.0
var _wave_left: float = 0.0
var _blink_wait: float = 2.0
var _blink_age: float = -1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _weights: Dictionary = {"neutral": 0.0, "happy": 0.0, "relaxed": 0.0, "surprised": 0.0, "sad": 0.0}

func seed_random(value: int) -> void:
	_rng.seed = value
	_blink_wait = _rng.randf_range(1.6, 3.6)

func pet() -> void:
	dozing = false
	_pet_left = 2.4

func wave() -> void:
	dozing = false
	_wave_left = 3.2

func set_mood(value: String) -> void:
	if MOODS.has(value):
		mood = value
		dozing = false
		_pet_left = 0.0

func tick(delta: float, allow_rest: bool = true) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	time += dt
	posture.tick(dt, allow_rest and autonomy_enabled and rest_enabled and motion_enabled and not dozing)
	_pet_left = maxf(0.0, _pet_left - dt)
	_wave_left = maxf(0.0, _wave_left - dt)
	var smoothing: float = 1.0 - exp(-dt * 7.0)
	pet_weight = lerpf(pet_weight, 1.0 if _pet_left > 0.35 else 0.0, smoothing)
	wave_weight = lerpf(wave_weight, 1.0 if _wave_left > 0.55 else 0.0, smoothing)
	sleep_weight = lerpf(sleep_weight, 1.0 if dozing else 0.0, 1.0 - exp(-dt * 2.8))
	if _blink_age >= 0.0:
		_blink_age += dt
		if _blink_age < 0.075:
			blink = smoothstep(0.0, 0.075, _blink_age)
		elif _blink_age < 0.13:
			blink = 1.0
		elif _blink_age < 0.27:
			blink = 1.0 - smoothstep(0.13, 0.27, _blink_age)
		else:
			_blink_age = -1.0
			blink = 0.0
			_blink_wait = _rng.randf_range(2.3, 5.4)
	else:
		_blink_wait -= dt
		if _blink_wait <= 0.0:
			_blink_age = 0.0
	var active: String = mood
	if _pet_left > 0.0 or _wave_left > 0.0:
		active = "happy"
	if dozing:
		active = "relaxed"
	for key in _weights:
		# Limit authored full-face presets, so expressions do not overdrive eyelids.
		var target: float = 0.68 if key == active and key != "neutral" else 0.0
		if dozing and key == "relaxed":
			target = 0.25
		_weights[key] = lerpf(float(_weights[key]), target, smoothing)

func expression_weights() -> Dictionary:
	var weights: Dictionary = _weights.duplicate()
	# The happy / relaxed full-face presets already partially close the eyes.
	var closure: float = maxf(blink, sleep_weight * 0.96)
	var suppression: float = clampf(1.0 - float(weights["happy"]) * 0.8 - float(weights["relaxed"]) * 0.45, 0.2, 1.0)
	weights["blink"] = closure * suppression
	return weights

func state_label() -> String:
	if _wave_left > 0.0:
		return "Машет тебе"
	if _pet_left > 0.0:
		return "Радуется вниманию"
	if dozing:
		return "Дремлет сидя" if posture.mode == "seated" else "Дремлет"
	if posture.mode != "standing":
		return posture.label()
	match mood:
		"happy": return "В хорошем настроении"
		"relaxed": return "Расслаблена"
		"surprised": return "Удивлена"
		"sad": return "Немного грустит"
	return "Спокойно стоит рядом"
