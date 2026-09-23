extends RefCounted
## Local-only pointer gesture recognition and short session novelty memory.
## It never moves the native window or writes to the avatar rig.

const BODY_DRAG_THRESHOLD_PX: float = 6.0
const HEAD_DRAG_SCALE: float = 0.135
const STROKE_PATH_SCALE: float = 0.022
const MIN_STROKE_SECONDS: float = 0.08
const PET_EXIT_GRACE_SECONDS: float = 0.12
const MAX_HISTORY: int = 12
const RETURN_AFTER_SECONDS: float = 45.0
const ATTENTION_COOLDOWN_SECONDS: float = 2.4
const WAVE_COOLDOWN_SECONDS: float = 3.5
const BUBBLE_COOLDOWN_SECONDS: float = 8.0

var active: bool = false
var started_on_head: bool = false
var on_head_now: bool = false
var pet_started: bool = false
var off_head_age: float = 0.0
var age: float = 0.0
var path_length: float = 0.0
var displacement: float = 0.0
var history: Array[Dictionary] = []
var _idle_seconds: float = 0.0
var _idle_before_press: float = 0.0
var _known_user: bool = false
var _known_before_press: bool = false
var _attention_cooldown: float = 0.0
var _wave_cooldown: float = 0.0
var _button_pet_cooldown: float = 0.0
var _bubble_cooldown: float = 0.0

var _body_pixels: float = 480.0
var _start: Vector2 = Vector2.ZERO
var _last: Vector2 = Vector2.ZERO

func tick(delta: float, user_holding: bool = false) -> void:
	var dt: float = clampf(delta, 0.0, 3600.0)
	_idle_seconds = 0.0 if user_holding else _idle_seconds + dt
	_attention_cooldown = maxf(0.0, _attention_cooldown - dt)
	_wave_cooldown = maxf(0.0, _wave_cooldown - dt)
	_button_pet_cooldown = maxf(0.0, _button_pet_cooldown - dt)
	_bubble_cooldown = maxf(0.0, _bubble_cooldown - dt)

func manual_activity() -> void:
	_known_user = true
	_idle_seconds = 0.0

func accept_wave() -> bool:
	manual_activity()
	if _wave_cooldown > 0.0:
		return false
	_wave_cooldown = WAVE_COOLDOWN_SECONDS
	_record("wave")
	return true

func accept_button_pet() -> bool:
	manual_activity()
	if _button_pet_cooldown > 0.0:
		return false
	_button_pet_cooldown = 2.4
	_record("pet_button")
	return true

func accept_palm_attention() -> bool:
	manual_activity()
	if _attention_cooldown > 0.0:
		return false
	_attention_cooldown = ATTENTION_COOLDOWN_SECONDS
	_record("attention")
	return true

func allow_bubble() -> bool:
	if _bubble_cooldown > 0.0:
		return false
	_bubble_cooldown = BUBBLE_COOLDOWN_SECONDS
	return true

func begin(global_point: Vector2, on_head: bool, body_size_px: float) -> void:
	_idle_before_press = _idle_seconds
	_known_before_press = _known_user
	_idle_seconds = 0.0
	active = true
	started_on_head = on_head
	on_head_now = on_head
	pet_started = false
	off_head_age = 0.0
	age = 0.0
	path_length = 0.0
	displacement = 0.0
	_body_pixels = maxf(1.0, body_size_px)
	_start = global_point
	_last = global_point

func update(global_point: Vector2, delta: float, on_head: bool) -> void:
	if not active:
		return
	age += clampf(delta, 0.0, 0.1)
	path_length += global_point.distance_to(_last)
	displacement = global_point.distance_to(_start)
	_last = global_point
	on_head_now = on_head
	off_head_age = 0.0 if on_head_now else off_head_age + clampf(delta, 0.0, 0.1)
	if started_on_head and on_head_now and age >= MIN_STROKE_SECONDS and path_length >= stroke_path_threshold() and not should_begin_drag():
		pet_started = true

func petting_now() -> bool:
	return active and pet_started and on_head_now and not should_begin_drag()

func should_begin_drag() -> bool:
	if not active:
		return false
	# Sweeping over the head is petting, even when the cursor travels farther
	# than the pickup threshold. A deliberate pull must leave the head zone.
	if started_on_head:
		return not on_head_now and displacement > head_drag_threshold() and (not pet_started or off_head_age >= PET_EXIT_GRACE_SECONDS)
	return displacement > BODY_DRAG_THRESHOLD_PX

func finish(was_dragged: bool, was_double_click: bool, was_dozing: bool = false) -> String:
	if not active:
		return "none"
	var result: String = "attention"
	if was_dragged or was_double_click:
		result = "none"
	elif pet_started:
		result = "pet"
	elif was_dozing:
		result = "wake"
	elif _known_before_press and _idle_before_press >= RETURN_AFTER_SECONDS:
		result = "return"
	elif _attention_cooldown > 0.0:
		result = "quiet"
	if result in ["attention", "wake", "return"]:
		_attention_cooldown = ATTENTION_COOLDOWN_SECONDS
	elif result == "pet":
		_attention_cooldown = maxf(_attention_cooldown, 1.2)
	manual_activity()
	_record(result)
	cancel()
	return result

func cancel() -> void:
	active = false
	started_on_head = false
	on_head_now = false
	pet_started = false
	off_head_age = 0.0
	age = 0.0
	path_length = 0.0
	displacement = 0.0

func head_drag_threshold() -> float:
	return maxf(48.0, _body_pixels * HEAD_DRAG_SCALE)

func stroke_path_threshold() -> float:
	return maxf(10.0, _body_pixels * STROKE_PATH_SCALE)

func recent_events() -> Array[Dictionary]:
	return history.duplicate(true)

func release_style(screen_velocity: Vector2, drop_pixels: float) -> String:
	# A quick flick or a high drop reads as abrupt. Stopping before release
	# lets the same carry end gently, regardless of earlier movement.
	var speed: float = screen_velocity.length()
	var downward_speed: float = maxf(0.0, screen_velocity.y)
	var drop_ratio: float = maxf(0.0, drop_pixels) / _body_pixels
	return "rough" if speed >= 950.0 or downward_speed >= 650.0 or drop_ratio >= 0.75 else "soft"

func record_release(style: String) -> void:
	if style in ["soft", "rough"]:
		_record("release_" + style)

func _record(kind: String) -> void:
	if kind == "none":
		return
	history.append({"kind": kind})
	while history.size() > MAX_HISTORY:
		history.pop_front()
