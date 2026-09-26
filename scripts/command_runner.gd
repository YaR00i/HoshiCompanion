extends RefCounted
## Исполнитель команд — КАК и КОГДА Хоши выполняет действие из hoshi_commands.gd.
##
## Раньше одно и то же действие («помахать», «пройтись по краю», «покачаться»)
## было написано в нескольких местах: отдельно для кнопки меню, отдельно для
## самостоятельной Хоши на полу и отдельно на окне. Теперь у каждого действия
## одна функция запуска и одна проверка «закончилось ли».
##
## source:
##   "user" — человек (меню, клавиши; позже телефон и голос). Может получить
##            короткую реплику, если действие сейчас невозможно;
##   "auto" — сама Хоши по плану IntentPlanner. Невозможное действие молча
##            прерывает план с понятной причиной.
##
## Исполнитель НЕ двигает кости и окно сам: он только просит владельцев
## (походку, позу, edge_life/idle_life, SurfaceController) — они остаются
## единственными хозяевами тела, как требует AGENTS.md.

const Commands = preload("res://scripts/hoshi_commands.gd")
const MotionLibrary = preload("res://scripts/motion_library.gd")

## Особый ответ start(): действие уже выполнено, ждать нечего.
const ALREADY_DONE: String = "already_done"

## Какие шаги плана понимает автономия на полу и на опоре.
const FLOOR_STEPS: Array[String] = ["walk", "look", "sit", "wave",
	"floor_peek_left", "floor_peek_right", "floor_weight_left", "floor_weight_right", "floor_hands", "floor_shoulders"]
const SURFACE_STEPS: Array[String] = ["surface_scoot", "surface_walk", "surface_settle", "side_left", "side_right",
	"side_wait", "side_return", "return_floor", "look", "wave",
	"edge_peek", "edge_balance", "edge_swing", "edge_lean", "edge_sway", "edge_hum", "edge_nod", "edge_sketch", "edge_fold",
	"floor_peek_left", "floor_peek_right", "floor_weight_left", "floor_weight_right", "floor_hands", "floor_shoulders"]
## Ручные команды опоры: исполняются здесь, до общей логики меню.
const USER_SUPPORT_COMMANDS: Array[String] = ["return_floor", "surface_walk", "surface_scoot", "side_left", "side_right", "side_return"]

var _app_ref: WeakRef
var _pause_left: float = 0.0

func setup(app) -> void:
	_app_ref = weakref(app)

func _app():
	return _app_ref.get_ref() if _app_ref != null else null

func reset_pause() -> void:
	_pause_left = 0.0

## Действие завершается в тот же момент, когда запущено.
func is_instant(command: String) -> bool:
	return command == "wave"

## Запустить команду. Пустая строка — запущена; иначе причина отказа
## (или ALREADY_DONE). context для "auto": where ("floor"/"surface"),
## context (behavior_context из companion.gd), cursor_gaze, cursor_near.
func start(command: String, source: String, context: Dictionary = {}) -> String:
	var app = _app()
	if app == null:
		return "no_app"
	if source == "auto":
		return _start_auto(app, command, context)
	return _start_user(app, command)

## Закончилось ли ранее запущенное действие (для шагов плана).
func is_done(command: String, delta: float) -> bool:
	var app = _app()
	if app == null:
		return true
	var playground = app.playground
	var seated: bool = app.state.posture.mode == "seated"
	match command:
		"walk":
			return not app.walker.active()
		"look":
			return not app.director.look_active()
		"sit":
			return seated
		"surface_walk", "surface_scoot", "side_return":
			return playground.active() and playground.surface.mode == "sit" and seated
		"surface_settle", "side_wait":
			_pause_left = maxf(0.0, _pause_left - delta)
			return _pause_left <= 0.0
		"side_left", "side_right":
			return playground.active() and playground.surface.mode == command
		"return_floor":
			return not playground.active() and app.state.posture.mode == "standing"
	if command.begins_with("edge_"):
		return not app.stage.edge_life.forced_active()
	if command.begins_with("floor_"):
		return not app.stage.idle_life.forced_active()
	return true

func _start_auto(app, command: String, context: Dictionary) -> String:
	var surface: bool = str(context.get("where", "floor")) == "surface"
	var allowed_steps: Array[String] = SURFACE_STEPS if surface else FLOOR_STEPS
	if not Commands.allows(command, "auto") or not command in allowed_steps:
		return "unsupported_surface_step" if surface else "unsupported_floor_step"
	var behavior: Dictionary = context.get("context", {})
	var playground = app.playground
	var state = app.state
	match command:
		"walk":
			if not bool(behavior.get("can_walk", false)):
				return "walk_unavailable"
			app._start_walk(true, true)
			return "" if app.walker.active() else "walk_failed"
		"look":
			if not bool(behavior.get("can_observe", surface)):
				return "surface_observe_unavailable" if surface else "observe_unavailable"
			app.director.request_observe(context.get("cursor_gaze", Vector2.ZERO), bool(context.get("cursor_near", false)))
			return ""
		"sit":
			if not bool(behavior.get("can_rest", false)):
				return "rest_unavailable"
			app._request_sit(true)
			return ""
		"wave":
			if not surface and not bool(behavior.get("can_social", false)):
				return "social_unavailable"
			state.wave()
			return ""
		"surface_scoot":
			return "" if playground.active() and playground.surface.request_scoot() else "surface_scoot_unavailable"
		"surface_walk":
			return "" if playground.active() and playground.surface.request_walk() else "surface_walk_unavailable"
		"surface_settle":
			_pause_left = 1.4 if state.activity == "playful" else (3.2 if state.activity == "quiet" else 2.2)
			return ""
		"side_left", "side_right":
			return "" if playground.active() and playground.surface.request_side(command.trim_prefix("side_"), false) else "side_unavailable"
		"side_wait":
			_pause_left = 4.0 if state.activity == "playful" else 5.5
			return ""
		"side_return":
			return "" if playground.active() and playground.surface.request_sit_top() else "side_return_failed"
		"return_floor":
			if not playground.active():
				return ALREADY_DONE
			playground.return_home()
			return ""
	if command.begins_with("edge_"):
		var edge_gesture: String = _gesture_for(command, "edge_life")
		if not playground.active() or state.posture.mode != "seated" or (edge_gesture in ["sketch", "fold"] and not playground.cozy_mode) or not app.stage.edge_life.request_gesture(edge_gesture):
			return "edge_gesture_unavailable"
		return ""
	if command.begins_with("floor_"):
		var floor_gesture: String = _gesture_for(command, "idle_life")
		if surface and (playground.active() or state.posture.mode != "standing"):
			return "return_gesture_unavailable"
		if not app.stage.idle_life.request_gesture(floor_gesture):
			return "return_gesture_unavailable" if surface else "floor_gesture_unavailable"
		return ""
	return "unsupported_surface_step" if surface else "unsupported_floor_step"

func _start_user(app, command: String) -> String:
	var playground = app.playground
	var state = app.state
	match command:
		"wave":
			if not app.interaction.accept_wave():
				return "wave_cooldown"
			state.wave()
			if app.interaction.allow_bubble():
				app.ui.say("Я тут!")
			return ""
		"walk":
			app._start_walk(false)
			return ""
		"sit":
			app._request_sit()
			return ""
		"return_floor":
			playground.return_home()
			return ""
		"surface_walk":
			return _support_result(app, playground.surface.request_walk(), "Здесь маловато места для прогулки", "surface_walk_unavailable")
		"surface_scoot":
			return _support_result(app, playground.surface.request_scoot(), "Здесь сейчас не подвинуться сидя", "surface_scoot_unavailable")
		"side_left", "side_right":
			return _support_result(app, playground.surface.request_side(command.trim_prefix("side_")), "К этому боку сейчас не прислониться", "side_unavailable")
		"side_return":
			return _support_result(app, playground.surface.request_sit_top(), "Я уже на краю", "side_return_failed")
		"edge_sketch", "edge_fold", "edge_admire_star":
			if not (playground.active() and playground.cozy_mode and playground.phase == "attached" and state.posture.mode == "seated" and state.motion_enabled and not state.dozing):
				return "cozy_scene_unavailable"
			if command == "edge_admire_star" and playground.cozy_stars_made <= 0:
				return "no_star_yet"
			app.stage.edge_life.request_gesture(_gesture_for(command, "edge_life"))
			return ""
	return "not_a_runner_command"

func _support_result(app, ok: bool, message: String, reason: String) -> String:
	if ok:
		return ""
	if app.playground.active():
		app.ui.say(message)
	return reason

## Имя жеста у проигрывателя берётся из библиотеки движений, а не пишется вручную.
func _gesture_for(command: String, expected_player: String) -> String:
	var motion: String = Commands.animation(command)
	if MotionLibrary.player(motion) != expected_player:
		push_warning("Command %s is not linked to a %s motion" % [command, expected_player])
		return ""
	return MotionLibrary.gesture(motion)
