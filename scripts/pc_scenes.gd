extends RefCounted
## Сценарии: одна кнопка — несколько шагов по очереди (просьба 28.09.2026).
## Например, «🎬 Кино»: звук → телевизор, MPC-BE на экран телевизора во весь
## экран, Хоши сидит тихо.
##
## Шаг — это уже существующая кнопка пульта, по имени команды:
##   "sound:<id>"  — «Звук на пульте» (устройство вывода);
##   "pc:<id>"     — «Мои действия» (с их расстановкой окна; без «Точно?»);
##   "timer:<минуты>" — таймер сна (что потом — как выбрано в прошлый раз);
##   имя команды Хоши, разрешённой пульту ("sit", "mood_relaxed", …).
## Своих новых возможностей у сценария нет: только то, что и так можно нажать.
## Собираются только на ПК; телефон запускает готовый сценарий "scene:<id>".
##
## Шаги идут по очереди с паузой STEP_GAP; если шаг запустил программу с
## расстановкой окна, следующий ждёт, пока окно встанет (не дольше WAIT_LIMIT).

const FILE_PATH: String = "user://pc_scenes.json"
const MAX_SCENES: int = 12
const MAX_STEPS: int = 12
const STEP_GAP: float = 0.6
const WAIT_LIMIT: float = 15.0
const SERVICE_PC: Array = ["windows", "move", "front", "cancel"]

## [{"id", "title", "icon", "steps": ["sound:ab12", "pc:cd34", "sit"]}]
var scenes: Array = []
var path: String = FILE_PATH
## Идёт сейчас: {"id", "title", "steps", "index", "wait", "waited", "failed"}; пусто — ничего.
var running: Dictionary = {}
## Что сказать Хоши, когда сценарий закончился (забирает шина пульта).
var notice: String = ""
## Выполнить один шаг: func(command: String) -> String (пусто — получилось).
var run_step: Callable
## Занят ли ПК предыдущим шагом (окно ещё расставляется): func() -> bool.
var busy: Callable

func load_scenes() -> void:
	scenes.clear()
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	for item in parsed.get("scenes", []):
		var clean: Dictionary = _clean(item)
		if not clean.is_empty() and scenes.size() < MAX_SCENES:
			scenes.append(clean)

func save_scenes() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"scenes": scenes}, "\t"))

## Новый пустой сценарий. Возвращает id или "" (их уже слишком много).
func add(title: String, icon: String = "✨") -> String:
	if scenes.size() >= MAX_SCENES:
		return ""
	var item: Dictionary = _clean({"id": _new_id(), "title": title, "icon": icon, "steps": []})
	if item.is_empty():
		return ""
	scenes.append(item)
	save_scenes()
	return str(item["id"])

func remove(id: String) -> void:
	for index in range(scenes.size()):
		if scenes[index]["id"] == id:
			scenes.remove_at(index)
			save_scenes()
			return

func rename(id: String, title: String, icon: String) -> void:
	var item: Dictionary = find(id)
	if item.is_empty() or title.strip_edges().is_empty():
		return
	item["title"] = title.strip_edges().left(40)
	item["icon"] = icon.strip_edges().left(4) if not icon.strip_edges().is_empty() else "✨"
	save_scenes()

func move(id: String, step: int) -> void:
	for index in range(scenes.size()):
		if scenes[index]["id"] == id:
			var target: int = clampi(index + step, 0, scenes.size() - 1)
			var item: Dictionary = scenes[index]
			scenes.remove_at(index)
			scenes.insert(target, item)
			save_scenes()
			return

func add_step(id: String, command: String) -> bool:
	var item: Dictionary = find(id)
	if item.is_empty() or item["steps"].size() >= MAX_STEPS or not step_allowed(command):
		return false
	item["steps"].append(command)
	save_scenes()
	return true

func remove_step(id: String, index: int) -> void:
	var item: Dictionary = find(id)
	if not item.is_empty() and index >= 0 and index < item["steps"].size():
		item["steps"].remove_at(index)
		save_scenes()

func move_step(id: String, index: int, step: int) -> void:
	var item: Dictionary = find(id)
	if item.is_empty() or index < 0 or index >= item["steps"].size():
		return
	var target: int = clampi(index + step, 0, item["steps"].size() - 1)
	var command: String = item["steps"][index]
	item["steps"].remove_at(index)
	item["steps"].insert(target, command)
	save_scenes()

func find(id: String) -> Dictionary:
	for item in scenes:
		if item["id"] == id:
			return item
	return {}

## Можно ли такую команду сделать шагом (сценарий в сценарии — нет).
static func step_allowed(command: String) -> bool:
	if command.begins_with("sound:"):
		return command.length() > 6
	if command.begins_with("pc:"):
		var id: String = command.trim_prefix("pc:")
		return not id.is_empty() and not id in SERVICE_PC
	if command.begins_with("timer:"):
		var minutes: String = command.trim_prefix("timer:")
		return minutes.is_valid_int() and int(minutes) > 0 and int(minutes) <= 240
	if command.contains(":"):
		return false
	var Commands = load("res://scripts/hoshi_commands.gd")
	return Commands.allows(command, "remote")

## Кнопки для пульта: [{command, title, icon, steps}].
func catalog() -> Array:
	var items: Array = []
	for item in scenes:
		if not item["steps"].is_empty():
			items.append({"command": "scene:" + str(item["id"]), "title": item["title"], "icon": item["icon"], "steps": item["steps"].size()})
	return items

## Запустить "scene:<id>". Пусто — начали, иначе причина отказа.
func run(command: String, out: Dictionary = {}) -> String:
	var item: Dictionary = find(command.trim_prefix("scene:"))
	if item.is_empty():
		return "unknown_scene"
	if item["steps"].is_empty():
		return "empty_scene"
	running = {"id": item["id"], "title": item["title"], "steps": item["steps"].duplicate(), "index": 0,
		"wait": 0.0, "waited": 0.0, "failed": 0}
	out["say"] = "Сценарий «%s»" % item["title"]
	return ""

func is_running() -> bool:
	return not running.is_empty()

## Каждый кадр: следующий шаг, когда пауза прошла и окно прошлого шага встало.
func tick(delta: float) -> void:
	if running.is_empty():
		return
	running["wait"] -= delta
	if running["wait"] > 0.0:
		return
	if busy.is_valid() and busy.call() and running["waited"] < WAIT_LIMIT:
		running["waited"] += delta
		return
	if running["index"] >= running["steps"].size():
		notice = "Готово: «%s»" % running["title"] if running["failed"] == 0 else "«%s»: не всё получилось" % running["title"]
		running = {}
		return
	var command: String = running["steps"][running["index"]]
	running["index"] += 1
	var reason: String = run_step.call(command) if run_step.is_valid() and step_allowed(command) else "not_allowed"
	if not reason.is_empty():
		running["failed"] += 1
	running["wait"] = STEP_GAP
	running["waited"] = 0.0

func _clean(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var id: String = str(item.get("id", ""))
	var title: String = str(item.get("title", "")).strip_edges().left(40)
	if not id.is_valid_identifier() or id.length() > 16 or title.is_empty():
		return {}
	var steps: Array = []
	for command in item.get("steps", []):
		if command is String and step_allowed(command) and steps.size() < MAX_STEPS:
			steps.append(command)
	var icon: String = str(item.get("icon", "✨")).strip_edges().left(4)
	return {"id": id, "title": title, "icon": icon if not icon.is_empty() else "✨", "steps": steps}

func _new_id() -> String:
	var id: String = ""
	while id.is_empty() or not find(id).is_empty():
		id = "s%06x" % (randi() & 0xFFFFFF)
	return id
