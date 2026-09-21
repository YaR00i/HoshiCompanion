extends RefCounted
## Rare autonomous resting-place requests. It never inspects windows itself.
var wait_left: float = 18.0
var pause_left: float = 0.0
var requests: int = 0
var _mode: String = "off"

func manual_pause(seconds: float = 45.0) -> void:
	pause_left = maxf(pause_left, seconds)
	wait_left = maxf(wait_left, 20.0)

func change_mode(mode: String) -> void:
	_mode = mode
	pause_left = 0.0
	wait_left = 12.0 if mode != "off" else 20.0

func tick(delta: float, state, context: Dictionary) -> String:
	var dt: float = clampf(delta, 0.0, 0.1)
	pause_left = maxf(0.0, pause_left - dt)
	if _mode != state.place_mode:
		change_mode(state.place_mode)
	if state.place_mode == "off" or not state.autonomy_enabled or not state.rest_enabled or not state.motion_enabled:
		return ""
	if bool(context.get("blocked", true)) or not bool(context.get("can_place", false)) or pause_left > 0.0 or state.dozing:
		return ""
	if state.posture.mode != "standing":
		return ""
	wait_left = maxf(0.0, wait_left - dt)
	if wait_left > 0.0:
		return ""
	requests += 1
	wait_left = 120.0 if state.activity == "quiet" else 90.0
	return state.place_mode
