extends SceneTree
## Проверка скелета «команды → исполнитель → библиотека движений».
## Не требует VRM. Ловит рассинхрон: команда без движения, клип без записи,
## шаг автономии, которого нет в списке команд, пункт меню без команды.

const Commands = preload("res://scripts/hoshi_commands.gd")
const CommandRunner = preload("res://scripts/command_runner.gd")
const MotionLibrary = preload("res://scripts/motion_library.gd")
const SeatedMotion = preload("res://scripts/seated_motion.gd")
const IdleLife = preload("res://scripts/idle_life.gd")
const EdgeLife = preload("res://scripts/edge_life.gd")
const UI = preload("res://scripts/companion_ui.gd")

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	_check_registry()
	_check_library()
	_check_autonomy_vocabulary()
	_check_support_boundary()
	await _check_menus()
	_finish()

func _check_registry() -> void:
	var ids: Dictionary = {}
	var complete: bool = true
	for command in Commands.names():
		var id: int = Commands.menu_id(command)
		if id >= 0:
			complete = complete and not ids.has(id)
			ids[id] = command
		complete = complete and not Commands.title(command).is_empty() and not Commands.group(command).is_empty()
		var sources: Array = Commands.LIST[command].get("sources", [])
		complete = complete and not sources.is_empty()
		for source in sources:
			complete = complete and source in ["user", "auto", "remote"]
		# Пульт с телефона — только то, что можно и из меню.
		complete = complete and (not "remote" in sources or "user" in sources)
		# Команда без пункта меню должна быть доступна хотя бы самой Хоши.
		complete = complete and (id >= 0 or Commands.allows(command, "auto"))
	_check(complete, "every command has a title, a group, valid sources and a unique menu id")
	_check(Commands.resolve("wave") == "wave" and Commands.resolve(10) == "wave", "names and legacy numbers resolve to the same command")
	_check(Commands.resolve("no_such_command").is_empty() and Commands.resolve(9999).is_empty() and Commands.from_menu_id(-1).is_empty(), "unknown commands are rejected")
	var choices_known: bool = true
	for command in Commands.ACTIVITY_CHOICES + Commands.PLACE_CHOICES + Commands.EDGE_CHOICES:
		choices_known = choices_known and Commands.has(command)
	_check(choices_known, "drop-down choices point to known commands")
	var edge_values: Array[String] = []
	for command in Commands.EDGE_CHOICES:
		edge_values.append(Commands.edge_activity(command))
	_check(str(edge_values) == str(UI.EDGE_ACTIVITIES), "seated-mode commands follow the UI list order")
	_check(Commands.allows("wave", "user") and Commands.allows("wave", "auto") and not Commands.allows("quit", "auto"), "sources separate what Hoshi may do on her own")

func _check_library() -> void:
	var linked: bool = true
	for command in Commands.names():
		var motion: String = Commands.animation(command)
		if not motion.is_empty() and not MotionLibrary.has(motion):
			linked = false
			push_error("Command %s points to unknown motion %s" % [command, motion])
	_check(linked, "every command animation exists in the motion library")
	for id in MotionLibrary.editable_clips():
		var path: String = MotionLibrary.path(id)
		var clip: Animation = load(path) as Animation if ResourceLoader.exists(path) else null
		_check(clip != null, "%s clip file loads: %s" % [id, path])
		_check(MotionLibrary.loader_path(id) == path, "%s is the same file the runtime loads" % id)
		var gesture: String = MotionLibrary.gesture(id)
		if clip != null and SeatedMotion.DURATIONS.has(gesture):
			_check(SeatedMotion.validation_error(gesture, clip).is_empty(), "%s passes seated-motion validation" % id)
	var registered: bool = true
	for kind in SeatedMotion.kinds() + ["sketch"]:
		if MotionLibrary.find("edge_life", kind).is_empty():
			registered = false
			push_error("Seated clip %s is missing from motion_library.gd" % kind)
	_check(registered, "every seated clip file is listed in the motion library")
	var players_known: bool = true
	for gesture in IdleLife.new().weights:
		players_known = players_known and not MotionLibrary.find("idle_life", str(gesture)).is_empty()
	for gesture in EdgeLife.new().weights:
		players_known = players_known and not MotionLibrary.find("edge_life", str(gesture)).is_empty()
	_check(players_known, "every standing and seated gesture is listed in the motion library")
	var fold_commands: Array[String] = Commands.commands_for_animation("seated_fold")
	_check(fold_commands.size() == 1 and fold_commands[0] == "edge_fold", "a clip can be traced back to its command")
	var shown: Array[String] = []
	for command in Commands.names():
		if not Commands.animation_path(command).is_empty():
			shown.append(command)
	print("INFO: commands with editable Godot clips: ", ", ".join(shown))

## Все шаги планов IntentPlanner — это команды, которые разрешены самой Хоши.
func _check_autonomy_vocabulary() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/intent_planner.gd")
	var steps: Dictionary = {}
	var block := RegEx.new()
	block.compile("\"steps\": \\[([^\\]]*)\\]")
	var word := RegEx.new()
	word.compile("\"(\\w+)\"")
	for found in block.search_all(source):
		var body: String = found.get_string(1)
		for item in word.search_all(body):
			var name: String = item.get_string(1)
			if body.contains("\"%s\" + side" % name):
				steps[name + "left"] = true
				steps[name + "right"] = true
			else:
				steps[name] = true
	_check(steps.size() >= 20, "planner vocabulary was read (%d steps)" % steps.size())
	var known: bool = true
	for step in steps:
		var runnable: bool = str(step) in CommandRunner.FLOOR_STEPS or str(step) in CommandRunner.SURFACE_STEPS
		if not Commands.allows(str(step), "auto") or not runnable:
			known = false
			push_error("Planner step %s is not an autonomous command in the runner" % step)
	_check(known, "every planner step is a registered command Hoshi may run herself")
	var runner_known: bool = true
	for step in CommandRunner.FLOOR_STEPS + CommandRunner.SURFACE_STEPS:
		runner_known = runner_known and Commands.allows(step, "auto")
	for command in CommandRunner.USER_SUPPORT_COMMANDS:
		runner_known = runner_known and Commands.allows(command, "user")
	_check(runner_known, "runner only executes registered commands")

## Опоры просят Хоши только через support_port.gd и не лезут во внутренности.
func _check_support_boundary() -> void:
	var forbidden := RegEx.new()
	forbidden.compile("(\\bapp|_app\\(\\))\\.(_\\w+|ui\\b|director\\b|places\\b|intent_planner\\b|runner\\b|add_child\\b)")
	for path in ["res://scripts/shelf_playground.gd", "res://scripts/surface_controller.gd"]:
		var leaks: Array[String] = []
		for found in forbidden.search_all(FileAccess.get_file_as_string(path)):
			leaks.append(found.get_string())
		if not leaks.is_empty():
			push_error("%s bypasses support_port.gd: %s" % [path, ", ".join(leaks)])
		_check(leaks.is_empty(), "%s talks to Hoshi only through support_port.gd" % path.get_file())

func _check_menus() -> void:
	var user_interface = UI.new()
	root.add_child(user_interface)
	await process_frame
	var popups: Array[PopupMenu] = [user_interface.menu_tree]
	var menu_ok: bool = true
	var seen: int = 0
	while not popups.is_empty():
		var popup: PopupMenu = popups.pop_back()
		for child in popup.get_children():
			if child is PopupMenu:
				popups.append(child)
		for index in range(popup.item_count):
			if popup.is_item_separator(index) or not popup.get_item_submenu(index).is_empty():
				continue
			var id: int = popup.get_item_id(index)
			if id == 999:
				continue
			seen += 1
			var command: String = Commands.from_menu_id(id)
			if command.is_empty() or not Commands.allows(command, "user"):
				menu_ok = false
				push_error("Menu item without user command: %s (%d)" % [popup.get_item_text(index), id])
	_check(menu_ok and seen > 40, "every desktop menu item maps to a user command (%d items)" % seen)
	var emitted: Array[String] = []
	user_interface.action_requested.connect(func(command: String): emitted.append(command))
	user_interface._on_menu_id(Commands.menu_id("wave"))
	_check(emitted.size() == 1 and emitted[0] == "wave", "menu click is delivered as the command name")
	# Меню — одна панель: раздел открывается в ней же, «‹ Назад» — вверх.
	user_interface.open_menu(Vector2i(100, 100))
	var top_count: int = user_interface.menu.item_count
	var life_index: int = -1
	for index in range(user_interface.menu.item_count):
		if user_interface.menu.get_item_text(index).begins_with("Общение"):
			life_index = index
	user_interface._on_nav_id(user_interface.menu.get_item_id(life_index))
	var edge_index: int = -1
	for index in range(user_interface.menu.item_count):
		if user_interface.menu.get_item_text(index).begins_with("Занятие на краю"):
			edge_index = index
	user_interface._on_nav_id(user_interface.menu.get_item_id(edge_index))
	var third: Array[String] = []
	for index in range(user_interface.menu.item_count):
		third.append(user_interface.menu.get_item_text(index))
	_check(third.has("Сама выбирает") and third[0].begins_with("‹") and user_interface.menu.visible, "third level opens in the same panel, with «Back»")
	emitted.clear()
	user_interface._on_nav_id(Commands.menu_id("edge_mode_auto"))
	_check(emitted == ["edge_mode_auto"] and not user_interface.menu.visible, "choosing an item runs its command and closes the menu")
	user_interface.open_menu(Vector2i(100, 100))
	user_interface._on_nav_id(user_interface.menu.get_item_id(life_index))
	user_interface._on_nav_id(user_interface.NAV_BACK)
	_check(user_interface.menu.item_count == top_count, "«Back» returns to the upper level")
	user_interface.menu.hide()
	user_interface.queue_free()

func _finish() -> void:
	print("HOSHI_COMMANDS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
