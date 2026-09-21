extends RefCounted
## Pure pose transition state. User-chosen rest never expires by itself.
## Reversals keep position and brake velocity instead of snapping between poses.
var mode: String = "standing"
var kind: String = "floor"
var amount: float = 0.0
var target_seated: bool = false
var automatic: bool = false
var rest_left: float = 0.0
var _progress: float = 0.0
var _speed: float = 0.0

func request_sit(auto_rest: bool = false, duration: float = 50.0) -> void:
	target_seated = true
	automatic = auto_rest
	rest_left = maxf(10.0, duration)
	_update_mode()

func request_stand() -> void:
	target_seated = false
	automatic = false
	_update_mode()

func keep_rest() -> void:
	# Direct interaction while sitting gives control back to the user.
	automatic = false

func transitioning() -> bool:
	return mode in ["sitting_down", "standing_up"]

func tick(delta: float, allow_auto_stand: bool = true) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	if mode == "seated" and automatic and allow_auto_stand:
		rest_left = maxf(0.0, rest_left - dt)
		if rest_left <= 0.0:
			request_stand()
	var goal: float = 1.0 if target_seated else 0.0
	if not is_equal_approx(_progress, goal):
		var desired_speed: float = 0.43 if target_seated else -0.47
		_speed = move_toward(_speed, desired_speed, dt * 2.2)
		_progress = clampf(_progress + _speed * dt, 0.0, 1.0)
		if (target_seated and _progress >= 1.0) or (not target_seated and _progress <= 0.0):
			_speed = 0.0
	else:
		_progress = goal
		_speed = 0.0
	amount = _progress * _progress * _progress * (10.0 + _progress * (-15.0 + 6.0 * _progress))
	_update_mode()

func _update_mode() -> void:
	if target_seated:
		mode = "seated" if _progress >= 1.0 else "sitting_down"
	else:
		mode = "standing" if _progress <= 0.0 else "standing_up"

func label() -> String:
	match mode:
		"sitting_down": return "Устраивается поудобнее"
		"seated": return "Отдыхает сидя"
		"standing_up": return "Поднимается на ноги"
	return "Спокойно стоит рядом"

func cancel_automatic() -> void:
	automatic = false
	rest_left = 0.0

func reset_standing() -> void:
	# Used only when leaving the separate ledge demo or changing window mode.
	kind = "floor"
	mode = "standing"
	amount = 0.0
	target_seated = false
	automatic = false
	rest_left = 0.0
	_progress = 0.0
	_speed = 0.0
