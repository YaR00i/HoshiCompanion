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
##   "startapp" — приложение из меню «Пуск» (target — его AppID: программы
##              из Microsoft Store, приложения Chrome, обычные программы);
##              запускается через explorer.exe shell:AppsFolder\<AppID>;
##   "system" — встроенное системное: shutdown, restart, sleep, lock.
## Действие, которое запускает приложение пульта (MPC-BE, YouTube, Claude),
## Хоши узнаёт сама (app_for) — его иконка на главной пульта запускает его.
##
## Где появится окно (решение 2026-09-27): у действия есть "place" —
## {monitor: 0 — не трогать / 1..N — экран, mode: center|left|right|max,
## ask: спрашивать на телефоне при каждом запуске}. Тогда перед запуском
## tools/window_place.py запоминает, какие окна уже есть, и после запуска
## ставит НОВОЕ окно (только его, один раз). С телефона можно передать только
## номер экрана и один из четырёх режимов — и только если у действия «ask».
##
## Значки: для каждого действия Хоши один раз достаёт настоящий значок программы
## (tools/app_icon.py — как его показывает Windows) в user://pc_icons/<id>.png;
## пульт получает адрес /pc_icon/<id>.png. Для ссылок — 🌐 как раньше.
##
## «Если уже открыто — показать» (reuse, по умолчанию да): программа уже запущена —
## её окно выходит наверх (и встаёт, куда настроено) вместо второго запуска.
##
## Переставить уже открытое окно (решение 2026-09-27): "pc:windows" — обновить
## список открытых окон (только имя программы, экран, развёрнуто ли; заголовки
## не читаем), "pc:move" {hwnd, monitor, mode} — переставить окно из этого
## списка. Список обновляется только по просьбе (кнопка на ПК или телефоне).
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
const KIND_ICONS := {"open": "🚀", "folder": "📁", "file": "📄", "url": "🌐", "startapp": "🚀"}
## Приложения пульта и как узнать их запуск: слова в имени файла/AppID/названии, сайты.
const APP_WORDS := {"mpc": ["mpc-be", "mpc-hc"], "claude": ["claude_", "claude.exe", "anthropicclaude"], "codex": ["codex"]}
const APP_SITES := {"youtube": ["youtube.com", "youtu.be"]}
const PLACE_HELPER: String = "res://tools/window_place.py"
const ICON_HELPER: String = "res://tools/app_icon.py"
const ICON_DIR: String = "user://pc_icons/"
const PLACE_MODES := {"center": "По центру", "left": "Левая половина", "right": "Правая половина", "max": "На весь экран"}
const MAX_MONITORS: int = 16
## Известные программы из «Пуска», у которых AppID не говорит имя файла.
const APP_EXE := {"claude": "claude.exe", "youtube": "chrome.exe", "codex": "codex.exe"}

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
## Экраны ПК (для выбора «где появится окно»): [{index, label}], обновляет tools/window_place.py.
var monitors: Array = []
## Появились новые значки — пультам надо обновить кнопки (забирает шина).
var icons_changed: bool = false
var _icon_queue: Array = []
var _icon_io: FileAccess
var _icon_pid: int = 0
var _icon_age: float = 0.0
## Открытые окна (последний список по просьбе): [{hwnd, app, name, monitor, state}]
var open_windows: Array = []
## Растёт при каждом новом списке окон/экранов — окна на ПК перерисовываются.
var windows_version: int = 0
var _windows_io: FileAccess
var _windows_pid: int = 0
var _windows_buffer: String = ""
var _windows_again: float = 0.0
## Понятные имена программ вместо файлов.
const APP_NAMES := {"chrome.exe": "Chrome", "msedge.exe": "Edge", "firefox.exe": "Firefox", "mpc-be64.exe": "MPC-BE",
	"mpc-be.exe": "MPC-BE", "claude.exe": "Claude", "chatgpt.exe": "ChatGPT", "explorer.exe": "Проводник",
	"notepad.exe": "Блокнот", "steamwebhelper.exe": "Steam", "steam.exe": "Steam", "telegram.exe": "Telegram",
	"discord.exe": "Discord", "blender.exe": "Blender", "code.exe": "VS Code", "cursor.exe": "Cursor",
	"mstsc.exe": "Удалённый рабочий стол", "amneziavpn.exe": "AmneziaVPN", "obs64.exe": "OBS", "photoshop.exe": "Photoshop"}

var _place_io: FileAccess
var _place_pid: int = 0
var _place_buffer: String = ""
var _place_item: Dictionary = {}
var _place_age: float = 0.0
var _monitors_io: FileAccess
var _monitors_pid: int = 0
var _monitors_buffer: String = ""

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
	monitors = _clean_monitors(parsed.get("monitors", []))
	refresh_icons()
	var system: Variant = parsed.get("system", {})
	if system is Dictionary:
		for id in SYSTEM:
			system_enabled[id] = bool(system.get(id, system_enabled[id]))

func save_actions() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"actions": actions, "system": system_enabled, "monitors": monitors}, "\t"))

## Добавить действие (из окна на ПК). Возвращает id или "".
func add(kind: String, title: String, target: String, args: String = "", icon: String = "") -> String:
	if actions.size() >= MAX_ACTIONS:
		return ""
	var item: Dictionary = _clean({"id": _new_id(), "kind": kind, "title": title, "target": target, "args": args, "icon": icon})
	if item.is_empty():
		return ""
	actions.append(item)
	save_actions()
	refresh_icons()
	return str(item["id"])

func remove(id: String) -> void:
	for index in range(actions.size()):
		if actions[index]["id"] == id:
			actions.remove_at(index)
			save_actions()
			DirAccess.remove_absolute(icon_file(id))
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

## Где появится окно этого действия (из окна «Мои действия» на ПК).
func set_place(id: String, monitor: int, mode: String, ask: bool, reuse: bool = true) -> void:
	for item in actions:
		if item["id"] == id:
			item["place"] = _clean_place({"monitor": monitor, "mode": mode, "ask": ask})
			item["reuse"] = reuse
			save_actions()

## Показывать уже открытое окно вместо второго запуска? (по умолчанию — да,
## если известно, чьё окно ждать).
static func reuses(item: Dictionary) -> bool:
	return bool(item.get("reuse", true)) and not window_exe(item).is_empty()

func set_system(id: String, enabled: bool) -> void:
	if SYSTEM.has(id):
		system_enabled[id] = enabled
		save_actions()

## Кнопки для пульта: [{command, title, icon, confirm}] + отменить, если ждём выключения.
func catalog() -> Array:
	var items: Array = []
	for item in actions:
		var entry: Dictionary = {"command": "pc:" + str(item["id"]), "title": item["title"], "icon": item["icon"], "confirm": false, "app": app_for(item)}
		if FileAccess.file_exists(icon_file(item["id"])):
			entry["icon_url"] = "/pc_icon/%s.png?v=%d" % [item["id"], FileAccess.get_modified_time(icon_file(item["id"]))]
		var place: Dictionary = item.get("place", {})
		if bool(place.get("ask", false)):
			# Телефон спросит, где открыть: экраны и режимы — только из этого списка.
			entry["ask_place"] = {"monitor": place["monitor"], "mode": place["mode"], "monitors": monitors, "modes": PLACE_MODES}
		items.append(entry)
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
	if id == "windows":
		refresh_windows()
		return ""
	if id == "move":
		return _move_window(args, out)
	if id == "front":
		return _front_window(args, out)
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
			var place: Dictionary = item.get("place", {})
			if bool(place.get("ask", false)) and args.has("monitor"):
				place = _clean_place({"monitor": args.get("monitor", 0), "mode": args.get("mode", ""), "ask": true})
			if (int(place.get("monitor", 0)) > 0 or reuses(item)) and item["kind"] != "url":
				return _run_placed(item, place if not place.is_empty() else {"monitor": 0, "mode": "center"}, out)
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
	if item["kind"] == "startapp":
		_exec("explorer.exe", ["shell:AppsFolder\\" + target])
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

## Запуск с выбором экрана: сначала помощник запоминает окна (ready), потом
## запуск (в tick), потом он ставит новое окно. Нет помощника — просто запуск.
func _run_placed(item: Dictionary, place: Dictionary, out: Dictionary) -> String:
	if not dry_run and not item["kind"] in ["url", "startapp"] and not FileAccess.file_exists(str(item["target"])) and not DirAccess.dir_exists_absolute(str(item["target"])):
		out["say"] = "Не нашла: " + str(item["title"])
		return "missing"
	var args: Array = ["place", str(OS.get_process_id()), str(place["monitor"]), str(place["mode"]), window_exe(item) if not window_exe(item).is_empty() else "-"]
	if reuses(item):
		args.append("reuse")
	if dry_run:
		executed.append(args)
		return _run_saved(item, out)
	if _place_io != null or OS.get_name() != "Windows":
		return _run_saved(item, out) # один запуск с расстановкой за раз
	var helper: String = ProjectSettings.globalize_path(PLACE_HELPER)
	var process: Dictionary = OS.execute_with_pipe(_python(), PackedStringArray(["-u", helper] + args), false) if FileAccess.file_exists(helper) else {}
	if process.is_empty():
		return _run_saved(item, out)
	_place_io = process["stdio"]
	_place_pid = int(process["pid"])
	_place_buffer = ""
	_place_item = item
	_place_age = 0.0
	out["say"] = "Открываю: " + str(item["title"])
	return ""

## Где лежит значок действия.
func icon_file(id: String) -> String:
	return ProjectSettings.globalize_path(ICON_DIR + id + ".png")

## Поставить в очередь значки, которых ещё нет (ссылкам значок не нужен).
func refresh_icons() -> void:
	if dry_run:
		return
	for item in actions:
		if item["kind"] != "url" and not FileAccess.file_exists(icon_file(item["id"])) and not item["id"] in _icon_queue:
			_icon_queue.append(item["id"])

func _tick_icons(dt: float) -> void:
	if _icon_io != null:
		_icon_age += dt
		_icon_io.get_buffer(4096)
		if OS.is_process_running(_icon_pid) and _icon_age < 10.0:
			return
		if OS.is_process_running(_icon_pid):
			OS.kill(_icon_pid)
		_icon_io = null
		icons_changed = true
	while not _icon_queue.is_empty() and _icon_io == null:
		var id: String = _icon_queue.pop_front()
		var item: Dictionary = {}
		for candidate in actions:
			if candidate["id"] == id:
				item = candidate
		if item.is_empty() or OS.get_name() != "Windows":
			continue
		var target: String = "shell:AppsFolder\\" + str(item["target"]) if item["kind"] == "startapp" else str(item["target"])
		var helper: String = ProjectSettings.globalize_path(ICON_HELPER)
		if not FileAccess.file_exists(helper):
			_icon_queue.clear()
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ICON_DIR))
		var process: Dictionary = OS.execute_with_pipe(_python(), PackedStringArray(["-u", helper, target, icon_file(id), "96"]), false)
		if not process.is_empty():
			_icon_io = process["stdio"]
			_icon_pid = int(process["pid"])
			_icon_age = 0.0

## Погасить экраны (таймер сна): как «монитор в сон» в Windows, мышь будит.
func screen_off() -> void:
	var script: String = "Add-Type -Namespace W -Name M -MemberDefinition '[DllImport(\"user32.dll\")] public static extern int PostMessage(int h, int m, int w, int l);'; [W.M]::PostMessage(0xFFFF, 0x0112, 0xF170, 2)"
	_exec("powershell.exe", ["-NoProfile", "-WindowStyle", "Hidden", "-EncodedCommand", Marshalls.raw_to_base64(script.to_utf16_buffer())])

## Окно, запущенное с расстановкой, ещё ставится (сценарий ждёт его).
func placing() -> bool:
	return _place_io != null

## Каждый кадр (шина пульта): расстановка окна и список экранов.
func tick(delta: float) -> void:
	_tick_icons(clampf(delta, 0.0, 0.1))
	if _windows_again > 0.0:
		_windows_again -= clampf(delta, 0.0, 0.1)
		if _windows_again <= 0.0:
			refresh_windows()
	if _windows_io != null:
		_windows_buffer += _windows_io.get_buffer(65536).get_string_from_utf8()
		if not OS.is_process_running(_windows_pid):
			_windows_buffer += _windows_io.get_buffer(65536).get_string_from_utf8()
			_windows_io = null
			var parsed: Variant = JSON.parse_string(_windows_buffer.strip_edges())
			if parsed is Dictionary:
				apply_windows(parsed)
	if _place_io != null:
		_place_age += clampf(delta, 0.0, 0.1)
		_place_buffer += _place_io.get_buffer(4096).get_string_from_utf8()
		if not _place_item.is_empty() and (_place_buffer.contains("ready") or _place_age > 3.0 or not OS.is_process_running(_place_pid)):
			if not _place_buffer.contains("\"existing\": true"):
				_run_saved(_place_item, {}) # окна запомнены — теперь запуск
			_place_item = {} # уже было открыто — помощник сам показал окно
		if not OS.is_process_running(_place_pid) or _place_age > 20.0:
			if OS.is_process_running(_place_pid):
				OS.kill(_place_pid)
			_place_io = null
	if _monitors_io != null:
		_monitors_buffer += _monitors_io.get_buffer(16384).get_string_from_utf8()
		if not OS.is_process_running(_monitors_pid):
			_monitors_buffer += _monitors_io.get_buffer(16384).get_string_from_utf8()
			_monitors_io = null
			var parsed: Variant = JSON.parse_string(_monitors_buffer.strip_edges())
			if parsed is Dictionary and parsed.get("monitors", []) is Array:
				var fresh: Array = []
				for m in parsed["monitors"]:
					if m is Dictionary:
						fresh.append({"index": int(m.get("index", 0)), "label": "Экран %d%s · %d×%d" % [int(m.get("index", 0)), " (основной)" if bool(m.get("primary", false)) else "", int(m.get("width", 0)), int(m.get("height", 0))],
							"x": int(m.get("x", 0)), "y": int(m.get("y", 0)), "width": int(m.get("width", 0)), "height": int(m.get("height", 0)), "primary": bool(m.get("primary", false))})
				monitors = _clean_monitors(fresh)
				windows_version += 1
				save_actions()

## Обновить список открытых окон (по кнопке на ПК или телефоне).
func refresh_windows() -> void:
	if _windows_io != null or dry_run or OS.get_name() != "Windows":
		return
	var helper: String = ProjectSettings.globalize_path(PLACE_HELPER)
	if not FileAccess.file_exists(helper):
		return
	refresh_monitors()
	var process: Dictionary = OS.execute_with_pipe(_python(), PackedStringArray(["-u", helper, "list", str(OS.get_process_id())]), false)
	if not process.is_empty():
		_windows_io = process["stdio"]
		_windows_pid = int(process["pid"])
		_windows_buffer = ""

## Ответ помощника со списком окон (отдельной функцией — тесты подают его сами).
func apply_windows(result: Dictionary) -> void:
	var fresh: Array = []
	for w in result.get("windows", []):
		if not w is Dictionary or not str(w.get("hwnd", "")).is_valid_int() or fresh.size() >= 60:
			continue
		var app: String = str(w.get("app", "")).to_lower().left(64)
		var state: String = str(w.get("state", "normal"))
		fresh.append({"hwnd": str(w["hwnd"]), "app": app, "name": pretty_app(app),
			"monitor": int(w.get("monitor", 0)), "state": state if state in ["normal", "maximized", "minimized"] else "normal"})
	open_windows = fresh
	windows_version += 1

## Что знает телефон об окнах: список и экраны для схемы.
func windows_state() -> Dictionary:
	return {"list": open_windows, "monitors": monitors, "modes": PLACE_MODES} if not open_windows.is_empty() else {}

static func pretty_app(app: String) -> String:
	if APP_NAMES.has(app):
		return APP_NAMES[app]
	if app.begins_with("godot"):
		return "Godot"
	var base: String = app.trim_suffix(".exe")
	return base.left(1).to_upper() + base.substr(1) if not base.is_empty() else "Окно"

## "pc:move" {hwnd, monitor, mode}: только окно из последнего списка, только
## экран из списка и один из четырёх режимов.
func _move_window(args: Dictionary, out: Dictionary) -> String:
	var hwnd: String = str(args.get("hwnd", ""))
	var target: Dictionary = {}
	for w in open_windows:
		if w["hwnd"] == hwnd:
			target = w
	if target.is_empty():
		return "unknown_window"
	var place: Dictionary = _clean_place({"monitor": args.get("monitor", 0), "mode": args.get("mode", "")})
	if int(place["monitor"]) <= 0:
		return "bad_screen"
	out["say"] = "Переставляю: " + str(target["name"])
	var command: Array = ["move", str(OS.get_process_id()), hwnd, str(place["monitor"]), str(place["mode"])]
	if bool(args.get("front", false)):
		command.append("front") # и поверх других окон
	if dry_run:
		executed.append(command)
		return ""
	var helper: String = ProjectSettings.globalize_path(PLACE_HELPER)
	if OS.get_name() != "Windows" or not FileAccess.file_exists(helper):
		return "no_helper"
	OS.create_process(_python(), PackedStringArray([helper] + command))
	_windows_again = 1.5 # потом перечитать, где теперь окна
	return ""

## "pc:front" {hwnd}: окно из последнего списка — поверх других окон, не двигая.
func _front_window(args: Dictionary, out: Dictionary) -> String:
	var hwnd: String = str(args.get("hwnd", ""))
	var target: Dictionary = {}
	for w in open_windows:
		if w["hwnd"] == hwnd:
			target = w
	if target.is_empty():
		return "unknown_window"
	out["say"] = "Показываю: " + str(target["name"])
	var command: Array = ["front", str(OS.get_process_id()), hwnd]
	if dry_run:
		executed.append(command)
		return ""
	var helper: String = ProjectSettings.globalize_path(PLACE_HELPER)
	if OS.get_name() != "Windows" or not FileAccess.file_exists(helper):
		return "no_helper"
	OS.create_process(_python(), PackedStringArray([helper] + command))
	_windows_again = 1.0
	return ""

## Перечитать экраны ПК (открыли окно «Мои действия», включили пульт).
func refresh_monitors() -> void:
	if _monitors_io != null or dry_run or OS.get_name() != "Windows":
		return
	var helper: String = ProjectSettings.globalize_path(PLACE_HELPER)
	if not FileAccess.file_exists(helper):
		return
	var process: Dictionary = OS.execute_with_pipe(_python(), PackedStringArray(["-u", helper, "monitors"]), false)
	if not process.is_empty():
		_monitors_io = process["stdio"]
		_monitors_pid = int(process["pid"])
		_monitors_buffer = ""

## Имя программы, чьё окно ждать после запуска ("" — любое новое окно).
static func window_exe(item: Dictionary) -> String:
	var target: String = str(item.get("target", ""))
	match str(item.get("kind", "")):
		"open":
			return target.get_file().to_lower() if target.to_lower().ends_with(".exe") else ""
		"folder":
			return "explorer.exe"
		"startapp":
			if target.to_lower().ends_with(".exe"):
				return target.get_file().to_lower()
			return str(APP_EXE.get(app_for(item), ""))
	return ""

func _clean_place(place: Variant) -> Dictionary:
	if not place is Dictionary:
		return {}
	var monitor: int = clampi(int(place.get("monitor", 0)), 0, MAX_MONITORS)
	var mode: String = str(place.get("mode", "center"))
	if not PLACE_MODES.has(mode):
		mode = "center"
	return {"monitor": monitor, "mode": mode, "ask": bool(place.get("ask", false))}

func _clean_monitors(items: Variant) -> Array:
	var result: Array = []
	if items is Array:
		for m in items:
			if m is Dictionary and int(m.get("index", 0)) > 0 and result.size() < MAX_MONITORS:
				# x, y, width, height — где экран стоит в раскладке Windows (для схемы экранов).
				result.append({"index": int(m["index"]), "label": str(m.get("label", "")).left(60),
					"x": int(m.get("x", 0)), "y": int(m.get("y", 0)), "width": maxi(1, int(m.get("width", 1920))),
					"height": maxi(1, int(m.get("height", 1080))), "primary": bool(m.get("primary", false))})
	return result

func _python() -> String:
	if FileAccess.file_exists("res://python_path.txt"):
		return FileAccess.get_file_as_string("res://python_path.txt").strip_edges()
	return "python"

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
	if not kind in ["open", "folder", "file", "url", "startapp"] or target.is_empty() or target.length() > 400:
		return {}
	if kind == "url" and not (target.begins_with("https://") or target.begins_with("http://")):
		return {}
	if kind == "startapp" and not is_app_id(target):
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
	var clean: Dictionary = {"id": id, "kind": kind, "title": title, "target": target, "args": str(item.get("args", "")).left(200), "icon": icon}
	if item.has("reuse"):
		clean["reuse"] = bool(item["reuse"])
	var place: Dictionary = _clean_place(item.get("place", {}))
	if int(place.get("monitor", 0)) > 0 or bool(place.get("ask", false)):
		clean["place"] = place
	return clean

## AppID из меню «Пуск»: буквы, цифры и . _ - ! { } \ пробел — без кавычек и
## других символов, которые могли бы превратить запуск во что-то иное.
static func is_app_id(text: String) -> bool:
	if text.is_empty() or text.length() > 300 or text.contains("..") or text.begins_with("\\"):
		return false
	for character in text:
		if not (character.is_valid_identifier() or character.is_valid_int() or character in "._-!{}\\ :;"):
			return false
	return true

## Какое приложение пульта запускает это действие ("mpc", "youtube", "claude"…), "" — никакое.
static func app_for(item: Dictionary) -> String:
	var target: String = str(item.get("target", "")).to_lower()
	if str(item.get("kind", "")) == "url":
		var host: String = target.trim_prefix("https://").trim_prefix("http://").get_slice("/", 0)
		for app in APP_SITES:
			for site in APP_SITES[app]:
				if host == site or host.ends_with("." + site):
					return app
		return ""
	var name: String = target.get_file() if str(item.get("kind", "")) != "startapp" else target
	var title: String = str(item.get("title", "")).to_lower()
	for app in APP_WORDS:
		for word in APP_WORDS[app]:
			if name.contains(word):
				return app
	# Приложение Chrome «YouTube» из «Пуска»: узнаём по названию.
	if str(item.get("kind", "")) == "startapp" and title == "youtube":
		return "youtube"
	return ""

func _new_id() -> String:
	var used: Dictionary = {}
	for item in actions:
		used[item["id"]] = true
	var index: int = actions.size() + 1
	while used.has("a%d" % index):
		index += 1
	return "a%d" % index
