extends RefCounted
## «Мои действия» — кнопки для управления компьютером с пульта.
##
## Список задаётся ТОЛЬКО на компьютере (окно «Мои действия» в меню Хоши) и
## хранится в user://pc_actions.json. Телефон видит кнопки и может нажать
## только их — сам он не передаёт, что запустить, поэтому даже привязанный
## телефон не выполнит на ПК ничего постороннего.
##
## Виды действий:
##   "open"   — открыть программу, файл или папку (target — путь на ПК;
##              args — необязательные параметры запуска программы);
##   "url"    — открыть ссылку в браузере по умолчанию;
##   "system" — встроенное системное: shutdown, restart, sleep, lock.
## Выключение и перезагрузка требуют подтверждения на телефоне и идут с
## отсрочкой: пока она не прошла, на пульте есть кнопка «Отменить».

const FILE_PATH: String = "user://pc_actions.json"
const SHUTDOWN_DELAY: int = 60
const MAX_ACTIONS: int = 40

## Встроенные системные действия: id -> заголовок, значок, нужно ли подтверждение.
const SYSTEM := {
	"lock": {"title": "Заблокировать", "icon": "🔒", "confirm": false},
	"sleep": {"title": "Сон", "icon": "🌙", "confirm": true},
	"restart": {"title": "Перезагрузить", "icon": "🔄", "confirm": true},
	"shutdown": {"title": "Выключить", "icon": "⏻", "confirm": true},
}
const KIND_ICONS := {"open": "🚀", "folder": "📁", "file": "📄", "url": "🌐"}

## Сохранённые действия: [{id, title, icon, kind, target, args}]
var actions: Array = []
## Какие системные кнопки показывать на пульте.
var system_enabled: Dictionary = {"lock": true, "sleep": false, "restart": false, "shutdown": false}
## Когда выключится/перезагрузится компьютер (мс Time.get_ticks_msec), 0 — ничего не ждём.
var pending_until: int = 0
var pending_kind: String = ""
## Для тестов: вместо запуска записывать, что было бы выполнено.
var dry_run: bool = false
var executed: Array = []
var path: String = FILE_PATH

func load_actions() -> void:
	actions = []
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	for item in parsed.get("actions", []):
		var clean: Dictionary = _clean(item)
		if not clean.is_empty() and actions.size() < MAX_ACTIONS:
			actions.append(clean)
	var system: Variant = parsed.get("system", {})
	if system is Dictionary:
		for id in SYSTEM:
			system_enabled[id] = bool(system.get(id, system_enabled[id]))

func save_actions() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"actions": actions, "system": system_enabled}, "\t"))

## Добавить действие (из окна на ПК). Возвращает id или "".
func add(kind: String, title: String, target: String, args: String = "", icon: String = "") -> String:
	if actions.size() >= MAX_ACTIONS:
		return ""
	var item: Dictionary = _clean({"id": _new_id(), "kind": kind, "title": title, "target": target, "args": args, "icon": icon})
	if item.is_empty():
		return ""
	actions.append(item)
	save_actions()
	return str(item["id"])

func remove(id: String) -> void:
	for index in range(actions.size()):
		if actions[index]["id"] == id:
			actions.remove_at(index)
			save_actions()
			return

func rename(id: String, title: String) -> void:
	for item in actions:
		if item["id"] == id and not title.strip_edges().is_empty():
			item["title"] = title.strip_edges().left(40)
			save_actions()

func move(id: String, step: int) -> void:
	for index in range(actions.size()):
		if actions[index]["id"] == id:
			var to: int = clampi(index + step, 0, actions.size() - 1)
			var item: Dictionary = actions[index]
			actions.remove_at(index)
			actions.insert(to, item)
			save_actions()
			return

func set_system(id: String, enabled: bool) -> void:
	if SYSTEM.has(id):
		system_enabled[id] = enabled
		save_actions()

## Кнопки для пульта: [{command, title, icon, confirm}] + отменить, если ждём выключения.
func catalog() -> Array:
	var items: Array = []
	for item in actions:
		items.append({"command": "pc:" + str(item["id"]), "title": item["title"], "icon": item["icon"], "confirm": false})
	for id in SYSTEM:
		if system_enabled.get(id, false):
			items.append({"command": "pc:system_" + id, "title": SYSTEM[id]["title"], "icon": SYSTEM[id]["icon"], "confirm": SYSTEM[id]["confirm"], "system": true})
	return items

func pending_seconds() -> int:
	return maxi(0, int(ceil(float(pending_until - Time.get_ticks_msec()) / 1000.0))) if pending_until > 0 else 0

func pending_state() -> Dictionary:
	if pending_until <= 0 or pending_seconds() <= 0:
		pending_until = 0
		return {}
	return {"kind": pending_kind, "seconds": pending_seconds(), "cancel": "pc:cancel"}

## Выполнить "pc:<id>". Пусто — выполнено, иначе причина отказа.
## Возвращает также реплику для Хоши через out["say"].
func run(command: String, args: Dictionary, out: Dictionary = {}) -> String:
	var id: String = command.trim_prefix("pc:")
	if id == "cancel":
		if pending_until <= 0:
			return "nothing_to_cancel"
		_exec("shutdown.exe", ["/a"])
		pending_until = 0
		out["say"] = "Хорошо, не выключаю"
		return ""
	if id.begins_with("system_"):
		var system_id: String = id.trim_prefix("system_")
		if not SYSTEM.has(system_id) or not system_enabled.get(system_id, false):
			return "not_allowed"
		if SYSTEM[system_id]["confirm"] and not bool(args.get("confirm", false)):
			return "need_confirm"
		return _run_system(system_id, out)
	for item in actions:
		if item["id"] == id:
			return _run_saved(item, out)
	return "unknown_action"

func _run_system(id: String, out: Dictionary) -> String:
	match id:
		"lock":
			_exec("rundll32.exe", ["user32.dll,LockWorkStation"])
			out["say"] = "Блокирую экран"
		"sleep":
			_exec("powershell.exe", ["-NoProfile", "-WindowStyle", "Hidden", "-Command",
				"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Application]::SetSuspendState('Suspend', $false, $false)"])
			out["say"] = "Спокойной ночи, компьютер"
		"shutdown", "restart":
			_exec("shutdown.exe", ["/r" if id == "restart" else "/s", "/t", str(SHUTDOWN_DELAY)])
			pending_until = Time.get_ticks_msec() + SHUTDOWN_DELAY * 1000
			pending_kind = id
			out["say"] = ("Перезагружаю" if id == "restart" else "Выключаю компьютер") + " через минуту"
	return ""

func _run_saved(item: Dictionary, out: Dictionary) -> String:
	var target: String = str(item["target"])
	out["say"] = "Открываю: " + str(item["title"])
	if item["kind"] == "url":
		_open(target)
		return ""
	if not dry_run and not FileAccess.file_exists(target) and not DirAccess.dir_exists_absolute(target):
		out["say"] = "Не нашла: " + str(item["title"])
		return "missing"
	var extra: String = str(item.get("args", ""))
	if target.to_lower().ends_with(".exe") and not extra.is_empty():
		_exec(target, _split_args(extra))
	else:
		_open(target)
	return ""

func _open(target: String) -> void:
	if dry_run:
		executed.append(["open", target])
	else:
		OS.shell_open(target)

func _exec(program: String, arguments: Array) -> void:
	if dry_run:
		executed.append([program] + arguments)
	elif OS.get_name() == "Windows":
		OS.create_process(program, PackedStringArray(arguments))

## Разбить строку параметров с учётом кавычек: a "b c" d -> [a, b c, d].
static func _split_args(text: String) -> Array:
	var result: Array = []
	var current: String = ""
	var quoted: bool = false
	for character in text:
		if character == "\"":
			quoted = not quoted
		elif character == " " and not quoted:
			if not current.is_empty():
				result.append(current)
			current = ""
		else:
			current += character
	if not current.is_empty():
		result.append(current)
	return result

func _clean(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var kind: String = str(item.get("kind", ""))
	var target: String = str(item.get("target", "")).strip_edges()
	if not kind in ["open", "folder", "file", "url"] or target.is_empty() or target.length() > 400:
		return {}
	if kind == "url" and not (target.begins_with("https://") or target.begins_with("http://")):
		return {}
	var id: String = str(item.get("id", ""))
	if id.is_empty() or id.length() > 16 or not id.is_valid_identifier():
		id = _new_id()
	var title: String = str(item.get("title", "")).strip_edges().left(40)
	if title.is_empty():
		title = target.get_file().get_basename() if kind != "url" else target.trim_prefix("https://").trim_prefix("http://").get_slice("/", 0)
	var icon: String = str(item.get("icon", "")).left(4)
	if icon.is_empty():
		icon = KIND_ICONS.get(kind, "🚀")
	return {"id": id, "kind": kind, "title": title, "target": target, "args": str(item.get("args", "")).left(200), "icon": icon}

func _new_id() -> String:
	var used: Dictionary = {}
	for item in actions:
		used[item["id"]] = true
	var index: int = actions.size() + 1
	while used.has("a%d" % index):
		index += 1
	return "a%d" % index
