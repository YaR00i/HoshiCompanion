extends RefCounted
## Pure local state: deterministic when seeded. No LLM, microphone or monitoring.

const Posture = preload("res://scripts/posture_controller.gd")
const FLOOR_REST_GRACE_SECONDS: float = 40.0
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
var notice_weight: float = 0.0
var welcome_weight: float = 0.0
var pet_weight: float = 0.0
var pet_contact_active: bool = false
var cursor_hang_active: bool = false
var release_style: String = ""
var pet_follow: Vector2 = Vector2.ZERO
var wave_weight: float = 0.0
var sleep_weight: float = 0.0
var time: float = 0.0
var blink: float = 0.0
var _notice_left: float = 0.0
var _welcome_left: float = 0.0
var _pet_left: float = 0.0
var _pet_contact_mode: bool = false
var _wave_left: float = 0.0
var _release_left: float = 0.0
var _blink_wait: float = 2.0
var _blink_age: float = -1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _weights: Dictionary = {"neutral": 0.0, "happy": 0.0, "relaxed": 0.0, "surprised": 0.0, "sad": 0.0}

func allows_autonomous_floor_rest() -> bool:
	# A configured place gets first chance to host rest; arrival begins on foot.
	return rest_enabled and motion_enabled and place_mode == "off" and time >= FLOOR_REST_GRACE_SECONDS

func seed_random(value: int) -> void:
	_rng.seed = value
	_blink_wait = _rng.randf_range(1.6, 3.6)

func notice() -> void:
	cancel_welcome()
	cancel_release_reaction()
	cancel_pet_contact()
	dozing = false
	_notice_left = 1.25
	_pet_left = 0.0
	_wave_left = 0.0

func pet() -> void:
	cancel_welcome()
	cancel_release_reaction()
	cancel_pet_contact()
	dozing = false
	_notice_left = 0.0
	_pet_left = 1.6
	_wave_left = 0.0

func begin_pet_contact() -> void:
	cancel_welcome()
	cancel_release_reaction()
	dozing = false
	_notice_left = 0.0
	_pet_left = 0.0
	_wave_left = 0.0
	pet_contact_active = true
	_pet_contact_mode = true

func update_pet_contact(target: Vector2, delta: float) -> void:
	if not pet_contact_active:
		return
	var bounded: Vector2 = Vector2(clampf(target.x, -1.0, 1.0), clampf(target.y, -1.0, 1.0))
	pet_follow = pet_follow.lerp(bounded, 1.0 - exp(-clampf(delta, 0.0, 0.1) * 3.5))

func end_pet_contact() -> void:
	pet_contact_active = false

func cancel_pet_contact() -> void:
	pet_contact_active = false
	_pet_contact_mode = false
	pet_follow = Vector2.ZERO
	pet_weight = 0.0
	_pet_left = 0.0

func begin_cursor_hang() -> void:
	cancel_welcome()
	cancel_release_reaction()
	cancel_pet_contact()
	cursor_hang_active = true
	dozing = false
	_notice_left = 0.0
	_wave_left = 0.0

func end_cursor_hang() -> void:
	cursor_hang_active = false

func wave() -> void:
	cancel_welcome()
	cancel_release_reaction()
	cancel_pet_contact()
	dozing = false
	_notice_left = 0.0
	_pet_left = 0.0
	_wave_left = 3.2

func set_mood(value: String) -> void:
	if MOODS.has(value):
		cancel_welcome()
		cancel_release_reaction()
		cancel_pet_contact()
		mood = value
		dozing = false
		_notice_left = 0.0
		_pet_left = 0.0

func react_to_release(style: String) -> void:
	if style not in ["soft", "rough"]:
		return
	cancel_welcome()
	cancel_pet_contact()
	dozing = false
	_notice_left = 0.0
	_wave_left = 0.0
	release_style = style
	_release_left = 1.15 if style == "rough" else 0.95

func cancel_release_reaction() -> void:
	release_style = ""
	_release_left = 0.0

func release_reaction_active() -> bool:
	return _release_left > 0.0

func recognize() -> void:
	cancel_pet_contact()
	cancel_release_reaction()
	dozing = false
	_notice_left = 0.0
	_wave_left = 0.0
	_welcome_left = 1.65

func cancel_welcome() -> void:
	_welcome_left = 0.0
	welcome_weight = 0.0

func welcome_active() -> bool:
	return _welcome_left > 0.0

func tick(delta: float, allow_rest: bool = true) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	time += dt
	posture.tick(dt, allow_rest and autonomy_enabled and rest_enabled and motion_enabled and not dozing)
	_notice_left = maxf(0.0, _notice_left - dt)
	_welcome_left = maxf(0.0, _welcome_left - dt)
	_pet_left = maxf(0.0, _pet_left - dt)
	_wave_left = maxf(0.0, _wave_left - dt)
	_release_left = maxf(0.0, _release_left - dt)
	if _release_left <= 0.0:
		release_style = ""
	var smoothing: float = 1.0 - exp(-dt * 7.0)
	notice_weight = lerpf(notice_weight, 1.0 if _notice_left > 0.22 else 0.0, smoothing)
	welcome_weight = lerpf(welcome_weight, 1.0 if _welcome_left > 0.28 else 0.0, smoothing)
	pet_weight = lerpf(pet_weight, 1.0 if pet_contact_active or _pet_left > 0.35 else 0.0, smoothing)
	if not pet_contact_active:
		pet_follow = pet_follow.lerp(Vector2.ZERO, 1.0 - exp(-dt * 4.0))
		if pet_weight < 0.01:
			_pet_contact_mode = false
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
	if _pet_left > 0.0 or _wave_left > 0.0 or _pet_contact_mode or cursor_hang_active:
		active = "happy"
	elif _release_left > 0.0:
		active = ("surprised" if _release_left > 0.55 else "relaxed") if release_style == "rough" else "happy"
	elif _welcome_left > 0.0:
		active = "happy"
	elif _notice_left > 0.0:
		active = "surprised"
	if dozing:
		active = "relaxed"
	for key in _weights:
		# Limit authored full-face presets, so expressions do not overdrive eyelids.
		var target: float = (0.30 if active == "surprised" and _notice_left > 0.0 else 0.68) if key == active and key != "neutral" else 0.0
		if _pet_contact_mode:
			target = 0.52 * pet_weight if key == "happy" else (0.26 * pet_weight if key == "relaxed" else 0.0)
		elif cursor_hang_active and key == "happy":
			target = 0.36
		if dozing and key == "relaxed":
			target = 0.25
		if _release_left > 0.0 and key == active:
			target = 0.36 if release_style == "rough" else 0.45
		if _welcome_left > 0.0 and key == "happy":
			target = 0.48
		_weights[key] = lerpf(float(_weights[key]), target, smoothing)

func expression_weights() -> Dictionary:
	var weights: Dictionary = _weights.duplicate()
	# The happy / relaxed full-face presets already partially close the eyes.
	var closure: float = maxf(maxf(blink, sleep_weight * 0.96), pet_weight * 0.5 if _pet_contact_mode else 0.0)
	var suppression: float = clampf(1.0 - float(weights["happy"]) * 0.8 - float(weights["relaxed"]) * 0.45, 0.2, 1.0)
	weights["blink"] = closure * suppression
	return weights

func state_label() -> String:
	if _release_left > 0.0:
		return "Вздрогнула и успокаивается" if release_style == "rough" else "Бережно опускается"
	if _welcome_left > 0.0:
		return "Рада снова тебя видеть"
	if _wave_left > 0.0:
		return "Машет тебе"
	if pet_contact_active or _pet_left > 0.0 or _pet_contact_mode:
		return "Радуется вниманию"
	if _notice_left > 0.0:
		return "Заметила тебя"
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
