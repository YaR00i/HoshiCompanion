extends RefCounted
## «Звук на пульте» — кнопки «Наушники · Телевизор · Колонки»: куда идёт звук ПК.
##
## Какие устройства показывать и как их назвать, выбирают ТОЛЬКО на компьютере
## (меню → Пульт с телефона → Звук на пульте); хранится в
## user://sound_outputs.json. Телефон присылает только "sound:<id>" из этого
## списка — сам он не может назвать устройство.
##
## Список устройств и переключение делает tools/audio_devices.py (Windows Core
## Audio). Приватность (решение 2026-09-27): только названия устройств вывода и
## какое из них главное; меняется только обычное главное устройство, «связь»
## (Discord, звонки) остаётся как была. Помощник запускается отдельным
## процессом и не держит кадр: ответ приходит в tick().

signal devices_changed

const FILE_PATH: String = "user://sound_outputs.json"
const HELPER: String = "res://tools/audio_devices.py"
const MAX_OUTPUTS: int = 8
## Пока есть телефон на связи — раз в столько секунд перечитывать список
## (включили телевизор — кнопка оживает).
const REFRESH_EVERY: float = 10.0
const HELPER_TIMEOUT: float = 5.0

## Кнопки на пульте: [{id, device, title, icon}]
var outputs: Array = []
## Последний ответ помощника — только активные устройства: [{device, name, default}]
var devices: Array = []
## Список хоть раз получен (до этого не знаем, что доступно).
var known: bool = false
## Сообщение для Хоши, если переключить не вышло (забирает remote_bus).
var notice: String = ""
## Для тестов: вместо помощника записывать, что было бы выполнено.
var dry_run: bool = false
var executed: Array = []
var path: String = FILE_PATH

var _io: FileAccess
var _err: FileAccess
var _pid: int = 0
var _buffer: String = ""
var _age: float = 0.0
var _running_set: String = ""
var _want_list: bool = false
var _want_set: String = ""
var _clock: float = 0.0

func load_outputs() -> void:
	outputs = []
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	for item in parsed.get("outputs", []):
		var clean: Dictionary = _clean(item)
		if not clean.is_empty() and outputs.size() < MAX_OUTPUTS:
			outputs.append(clean)

func save_outputs() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"outputs": outputs}, "\t"))

# ---------------------------------------------------------------- окно на ПК

## Показывать устройство на пульте или убрать. name — его имя в Windows.
func set_shown(device: String, name: String, shown: bool) -> void:
	var index: int = index_of_device(device)
	if not shown:
		if index >= 0:
			outputs.remove_at(index)
			save_outputs()
		return
	if index >= 0 or outputs.size() >= MAX_OUTPUTS:
		return
	var item: Dictionary = _clean({"id": _new_id(), "device": device, "title": short_name(name), "icon": guess_icon(name)})
	if not item.is_empty():
		outputs.append(item)
		save_outputs()

func rename(id: String, title: String) -> void:
	for item in outputs:
		if item["id"] == id and not title.strip_edges().is_empty():
			item["title"] = title.strip_edges().left(24)
			save_outputs()

func move(id: String, step: int) -> void:
	for index in range(outputs.size()):
		if outputs[index]["id"] == id:
			var to: int = clampi(index + step, 0, outputs.size() - 1)
			var item: Dictionary = outputs[index]
			outputs.remove_at(index)
			outputs.insert(to, item)
			save_outputs()
			return

func is_active(device: String) -> bool:
	for entry in devices:
		if entry["device"] == device:
			return true
	return false

func current_device() -> String:
	for entry in devices:
		if entry["default"]:
			return str(entry["device"])
	return ""

## «Наушники (HyperX Cloud III)» -> «Наушники».
static func short_name(name: String) -> String:
	var plain: String = name.get_slice(" (", 0).strip_edges()
	return (plain if not plain.is_empty() else name.strip_edges()).left(24)

static func guess_icon(name: String) -> String:
	var lower: String = name.to_lower()
	for word in ["наушник", "headphone", "headset", "гарнитур", "buds", "airpods"]:
		if lower.contains(word):
			return "🎧"
	for word in [" tv", "tv ", "тв", "телевиз", "hdmi", "monitor", "монитор"]:
		if lower.contains(word):
			return "📺"
	return "🔊"

# ---------------------------------------------------------------- пульт

## Кнопки для пульта: [{command, title, icon}]
func catalog() -> Array:
	var items: Array = []
	for item in outputs:
		items.append({"command": "sound:" + str(item["id"]), "title": item["title"], "icon": item["icon"]})
	return items

## Что подсветить на пульте: главное сейчас и какие кнопки живые.
func state() -> Dictionary:
	if outputs.is_empty():
		return {}
	var current: String = ""
	var available: Array = []
	var now: String = current_device()
	for item in outputs:
		if is_active(item["device"]):
			available.append("sound:" + str(item["id"]))
		if item["device"] == now:
			current = "sound:" + str(item["id"])
	return {"current": current, "available": available, "known": known}

## Нажатие "sound:<id>" с телефона. Пусто — принято, иначе причина отказа.
func run(command: String, out: Dictionary = {}) -> String:
	var id: String = command.trim_prefix("sound:")
	for item in outputs:
		if item["id"] != id:
			continue
		if known and not is_active(item["device"]):
			out["say"] = "%s сейчас не на связи" % item["title"]
			return "not_available"
		out["say"] = "Звук: " + str(item["title"])
		if item["device"] == current_device():
			return ""
		if dry_run:
			executed.append(["set", item["device"]])
			for entry in devices:
				entry["default"] = entry["device"] == item["device"]
			return ""
		_want_set = str(item["device"])
		_start_next()
		return ""
	return "unknown_output"

# ---------------------------------------------------------------- помощник

## Перечитать список устройств (окно открыли, телефон подключился).
func request_refresh() -> void:
	_want_list = true
	_start_next()

## keep_fresh — есть кому смотреть (телефон на связи): перечитывать по часам.
func tick(delta: float, keep_fresh: bool) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	if keep_fresh and not outputs.is_empty():
		_clock += dt
		if _clock >= REFRESH_EVERY:
			_clock = 0.0
			request_refresh()
	if _io == null:
		return
	_age += dt
	_buffer += _io.get_buffer(8192).get_string_from_utf8()
	if _err != null:
		_err.get_buffer(2048) # Drain, but never log arbitrary subprocess text.
	var done: bool = not OS.is_process_running(_pid)
	if done:
		_buffer += _io.get_buffer(65536).get_string_from_utf8()
	if done or _buffer.length() > 65536 or _age > HELPER_TIMEOUT:
		var line: String = _buffer.strip_edges().get_slice("\n", 0)
		var was_set: String = _running_set
		if not done:
			OS.kill(_pid)
		_io = null
		_err = null
		_pid = 0
		_buffer = ""
		_running_set = ""
		var result: Variant = JSON.parse_string(line) if done else null
		apply_result(result if result is Dictionary else {"ok": false, "error": "no_answer"}, was_set)
		_start_next()

## Ответ помощника (отдельной функцией — тесты подают его сами).
func apply_result(result: Dictionary, switched_to: String = "") -> void:
	var fresh: Array = []
	for entry in result.get("devices", []):
		if entry is Dictionary and str(entry.get("state", "")) == "active" and not str(entry.get("id", "")).is_empty():
			fresh.append({"device": str(entry["id"]), "name": str(entry.get("name", "")).left(80), "default": bool(entry.get("default", false))})
	if not fresh.is_empty() or bool(result.get("ok", false)):
		devices = fresh
		known = true
	if not switched_to.is_empty() and not bool(result.get("ok", false)):
		notice = "Не получилось переключить звук"
	devices_changed.emit()

func _start_next() -> void:
	if _io != null or dry_run:
		return
	var args: PackedStringArray = []
	if not _want_set.is_empty():
		args = ["set", _want_set]
		_running_set = _want_set
		_want_set = ""
		_want_list = false # «set» сам отвечает свежим списком
	elif _want_list:
		args = ["list"]
		_want_list = false
	else:
		return
	if OS.get_name() != "Windows":
		return
	var helper: String = ProjectSettings.globalize_path(HELPER)
	if not FileAccess.file_exists(helper):
		return
	var python_path: String = "python"
	if FileAccess.file_exists("res://python_path.txt"):
		python_path = FileAccess.get_file_as_string("res://python_path.txt").strip_edges()
	var process: Dictionary = OS.execute_with_pipe(python_path, PackedStringArray(["-u", helper]) + args, false)
	if process.is_empty():
		_running_set = ""
		return
	_pid = int(process["pid"])
	_io = process["stdio"]
	_err = process.get("stderr", null)
	_buffer = ""
	_age = 0.0

func index_of_device(device: String) -> int:
	for index in range(outputs.size()):
		if outputs[index]["device"] == device:
			return index
	return -1

func _clean(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var device: String = str(item.get("device", "")).strip_edges()
	# Windows id выглядит как {0.0.0.00000000}.{guid}: без путей, пробелов и кавычек.
	if device.is_empty() or device.length() > 128 or not device.begins_with("{"):
		return {}
	for character in device:
		if not (character.is_valid_hex_number() or character in "{}.-"):
			return {}
	var id: String = str(item.get("id", ""))
	if id.is_empty() or id.length() > 8 or not id.is_valid_identifier():
		id = _new_id()
	var title: String = str(item.get("title", "")).strip_edges().left(24)
	if title.is_empty():
		title = "Звук"
	var icon: String = str(item.get("icon", "")).left(4)
	if icon.is_empty():
		icon = "🔊"
	return {"id": id, "device": device, "title": title, "icon": icon}

func _new_id() -> String:
	var used: Dictionary = {}
	for item in outputs:
		used[item["id"]] = true
	var index: int = outputs.size() + 1
	while used.has("s%d" % index):
		index += 1
	return "s%d" % index
