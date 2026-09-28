extends RefCounted
## Что опора (своя полочка, уютный уголок, чужое окно) может попросить у Хоши.
##
## Раньше shelf_playground.gd и surface_controller.gd сами лезли во
## внутренние функции companion.gd, в меню и в планировщик. Теперь у них есть
## только этот короткий список просьб. Если опоре понадобится что-то новое —
## сначала добавь просьбу сюда, чтобы было видно, чем опоры управляют.
##
## Общие службы тела остаются общими и читаются напрямую: host (окно на
## экране), state (состояние и поза), stage (3D-сцена), air (прыжки/падения),
## walker (маршрут). У каждой из них один хозяин, см. AGENTS.md.
## tests/test_commands.gd проверяет, что опоры не обходят этот список.

var _app_ref: WeakRef

func setup(app) -> void:
	_app_ref = weakref(app)

func _app():
	return _app_ref.get_ref() if _app_ref != null else null

## Короткая реплика над головой. hold > 0 — показать дольше обычного.
func say(text: String, hold: float = -1.0) -> void:
	var app = _app()
	if app == null:
		return
	app.ui.say(text)
	if hold > 0.0:
		app.ui._bubble_left = hold

## Прервать текущий самостоятельный план Хоши (опора начинает свою сценку).
func interrupt_autonomy(reason: String) -> void:
	var app = _app()
	if app != null:
		app._abort_autonomous_intent(reason)

## Отменить отложенные намерения (сесть/уснуть после прогулки) и остановить прогулку.
func cancel_plans_and_walk() -> void:
	var app = _app()
	if app == null:
		return
	app._clear_intent()
	app._stop_walk()

func stop_walking(keep_facing: bool = false) -> void:
	var app = _app()
	if app != null:
		app._stop_walk(keep_facing)

## Начать обычную прогулку по полу (после возвращения с опоры).
func start_floor_walk() -> void:
	var app = _app()
	if app != null:
		app._start_walk(false)

## Прогулка по краю опоры началась: запомнить область и не садиться после неё.
func mark_support_walk() -> void:
	var app = _app()
	if app == null:
		return
	app._walk_zone = app.host.walking_zone()
	app._rest_after_walk = false

## Не садиться автоматически после текущей прогулки.
func cancel_rest_after_walk() -> void:
	var app = _app()
	if app != null:
		app._rest_after_walk = false

## Перейти на рабочий стол (опоры работают только там). true — уже на рабочем столе.
func switch_to_desktop() -> bool:
	var app = _app()
	if app == null:
		return false
	if app.host.preview:
		app._switch_mode(false)
	return not app.host.preview

func open_fitting_room() -> void:
	var app = _app()
	if app != null:
		app._switch_mode(true)

## Человек что-то сделал с Хоши — автономия выдерживает паузу.
func note_user_interaction() -> void:
	var app = _app()
	if app != null:
		app.director.user_interaction()

## Не выбирать места отдыха самостоятельно указанное время.
func pause_autonomous_places(seconds: float) -> void:
	var app = _app()
	if app != null:
		app.places.manual_pause(seconds)

func save_settings() -> void:
	var app = _app()
	if app != null:
		app._save_settings()

func test_mode() -> bool:
	var app = _app()
	return app != null and app._test_mode

## Человек держит Хоши мышью или открыл большое меню.
func user_busy() -> bool:
	var app = _app()
	return app != null and (app.desk_input.press_active or app.ui.menu.visible)

## Выполнить команду по имени (кнопки окна-уголка).
func run_command(command: String) -> void:
	var app = _app()
	if app != null:
		app.run_command(command)

## Добавить окно опоры (полочку/уголок) в сцену Хоши с её оформлением.
func add_support_window(window: Node) -> void:
	var app = _app()
	if app == null:
		return
	window.theme = app.ui.theme
	app.add_child(window)
