extends RefCounted
## Rare autonomous resting-place requests. It never inspects windows itself.
##
## Режим "focus" («Моё окно → уголок»): дом Хоши — её уютный уголок. Если
## человек долго работает в одном обычном окне, Хоши приходит сидеть на это
## окно; если он надолго ушёл в другое — возвращается в уголок. Все пороги и
## решения здесь, а смотреть на окна и двигаться будут другие (FocusTracker,
## shelf_playground). Развёрнутые на весь экран и полноэкранные окна пока не
## подходят: сверху у них нет места — к развёрнутому окну Хоши подлетает на
## своём уголке; к полноэкранному (видео, игра) не лезет (см. docs/SUPPORTS_RU.md).

## Сколько секунд подряд нужно пробыть в окне, чтобы Хоши пришла туда.
const FOCUS_DWELL := {"quiet": 300.0, "normal": 180.0, "playful": 120.0}
## Сколько секунд окна Хоши не было активным, чтобы она ушла обратно домой.
const FOCUS_AWAY: float = 90.0
## Не бегать туда-сюда чаще, чем раз в столько секунд.
const FOCUS_MOVE_COOLDOWN: float = 240.0
var wait_left: float = 18.0
var pause_left: float = 0.0
var requests: int = 0
var _mode: String = "off"
var move_cooldown: float = 0.0

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
	move_cooldown = maxf(0.0, move_cooldown - dt)
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

## Годится ли активное окно, чтобы прийти туда отдыхать.
static func focus_ready(focus: Dictionary, dwell: float, activity: String) -> bool:
	if focus.is_empty() or str(focus.get("state", "")) != "normal" or str(focus.get("hwnd", "0")) in ["", "0"]:
		return false
	return dwell >= float(FOCUS_DWELL.get(activity, FOCUS_DWELL["normal"]))

## Человек долго работает в РАЗВЁРНУТОМ окне: сесть на него некуда, поэтому
## Хоши подлетает к нему на своём уголке («хочу к тебе поближе»).
static func focus_near_ready(focus: Dictionary, dwell: float, activity: String) -> bool:
	if focus.is_empty() or str(focus.get("state", "")) != "maximized" or str(focus.get("hwnd", "0")) in ["", "0"]:
		return false
	return dwell >= float(FOCUS_DWELL.get(activity, FOCUS_DWELL["normal"]))

## Куда идти, когда пора отдыхать: "window" — на активное окно; иначе "cozy"
## (если окно развёрнуто — уголок потом подлетит ближе, см. focus_should_approach).
static func focus_destination(focus: Dictionary, dwell: float, activity: String) -> String:
	return "window" if focus_ready(focus, dwell, activity) else "cozy"

## Пора ли уголку подлететь к человеку. already_near — уже прилетели к этому окну.
func focus_should_approach(where: String, focus: Dictionary, dwell: float, activity: String, already_near: bool) -> bool:
	if _mode != "focus" or move_cooldown > 0.0 or pause_left > 0.0 or where != "cozy" or already_near:
		return false
	return focus_near_ready(focus, dwell, activity)

## Пора ли уйти с текущего места. where: "cozy" / "focus_window" / "other".
## away — сколько секунд окно, на котором сидит Хоши, не активно.
func focus_should_leave(where: String, focus: Dictionary, dwell: float, away: float, activity: String) -> bool:
	if _mode != "focus" or move_cooldown > 0.0 or pause_left > 0.0:
		return false
	if where == "focus_window":
		return away >= FOCUS_AWAY
	if where == "cozy":
		return focus_ready(focus, dwell, activity)
	return false

## Хоши ушла с места: следующий выбор — почти сразу, но не чаще cooldown.
func note_focus_move() -> void:
	move_cooldown = FOCUS_MOVE_COOLDOWN
	wait_left = minf(wait_left, 3.0)

