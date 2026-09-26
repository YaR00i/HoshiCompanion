extends SceneTree
## Проверка единого списка команд (scripts/hoshi_commands.gd).
## Не требует VRM: проверяет имена, меню и связь команд с клипами animations/.

const Commands = preload("res://scripts/hoshi_commands.gd")
const SeatedMotion = preload("res://scripts/seated_motion.gd")
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
	var ids: Dictionary = {}
	var complete: bool = true
	for command in Commands.names():
		var id: int = Commands.menu_id(command)
		complete = complete and id >= 0 and not ids.has(id)
		complete = complete and not Commands.title(command).is_empty() and not Commands.group(command).is_empty()
		ids[id] = command
	_check(complete, "every command has a title, a group and a unique menu id")
	_check(Commands.resolve("wave") == "wave" and Commands.resolve(10) == "wave", "names and legacy numbers resolve to the same command")
	_check(Commands.resolve("no_such_command").is_empty() and Commands.resolve(9999).is_empty(), "unknown commands are rejected")
	var choices_known: bool = true
	for command in Commands.ACTIVITY_CHOICES + Commands.PLACE_CHOICES + Commands.EDGE_CHOICES:
		choices_known = choices_known and Commands.has(command)
	_check(choices_known, "drop-down choices point to known commands")
	var edge_values: Array[String] = []
	for command in Commands.EDGE_CHOICES:
		edge_values.append(Commands.edge_activity(command))
	_check(str(edge_values) == str(UI.EDGE_ACTIVITIES), "edge activity commands follow the UI list order")

	# Анимации, которые правят в Godot: каждая ссылка команды ведёт на живой клип.
	var bound_clips: Dictionary = {}
	for command in Commands.names():
		var clip_name: String = Commands.animation(command)
		if clip_name.is_empty():
			continue
		bound_clips[clip_name] = true
		var path: String = Commands.animation_path(command)
		var clip: Animation = load(path) as Animation if ResourceLoader.exists(path) else null
		_check(clip != null, "%s uses an existing clip %s" % [command, path])
		if clip != null and SeatedMotion.DURATIONS.has(clip_name):
			_check(SeatedMotion.validation_error(clip_name, clip).is_empty(), "%s clip passes seated-motion validation" % clip_name)
	for clip_name in SeatedMotion.kinds():
		if not bound_clips.has(clip_name):
			print("INFO: clip %s is used only by Hoshi's own choices, no command plays it" % clip_name)
	var fold_commands: Array[String] = Commands.commands_for_animation("fold")
	_check(fold_commands.size() == 1 and fold_commands[0] == "cozy_fold_star", "a clip can be traced back to its command")

	# Меню: каждый пункт соответствует команде из списка.
	var user_interface = UI.new()
	root.add_child(user_interface)
	await process_frame
	var popups: Array[PopupMenu] = [user_interface.menu]
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
			if Commands.from_menu_id(id).is_empty():
				menu_ok = false
				push_error("Menu item without command: %s (%d)" % [popup.get_item_text(index), id])
	_check(menu_ok and seen > 40, "every desktop menu item maps to a named command (%d items)" % seen)
	var emitted: Array[String] = []
	user_interface.action_requested.connect(func(command: String): emitted.append(command))
	user_interface._on_menu_id(Commands.menu_id("wave"))
	_check(emitted.size() == 1 and emitted[0] == "wave", "menu click is delivered as the command name")
	user_interface.queue_free()
	_finish()

func _finish() -> void:
	print("HOSHI_COMMANDS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
