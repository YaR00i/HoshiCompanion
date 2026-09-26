extends RefCounted
## Какое окно сейчас активно и как долго — для режима «Моё окно → уголок».
##
## Работает только пока этот режим включён (companion.gd вызывает ensure()).
## Помощник tools/window_focus.py сообщает номер активного окна, имя программы
## (только имя файла) и его состояние. Заголовки и содержимое не читаются.
## Когда активна сама Хоши (на неё нажали), это не считается сменой окна.

var running: bool = false
## Текущее активное окно: {hwnd, app, state}; пусто — неизвестно.
var focus: Dictionary = {}
var _since: float = 0.0
var _clock: float = 0.0
## Когда каждое окно было активным в последний раз (секунды часов трекера).
var _last_seen: Dictionary = {}
var _io: FileAccess
var _err: FileAccess
var _pid: int = -1
var _buffer: String = ""

func ensure(wanted: bool) -> void:
	if wanted and not running:
		start()
	elif not wanted and running:
		stop()

func start() -> bool:
	stop()
	if OS.get_name() != "Windows":
		return false
	var python_path: String = "python"
	if FileAccess.file_exists("res://python_path.txt"):
		python_path = FileAccess.get_file_as_string("res://python_path.txt").strip_edges()
	var helper: String = ProjectSettings.globalize_path("res://tools/window_focus.py")
	if not FileAccess.file_exists(helper):
		return false
	var process: Dictionary = OS.execute_with_pipe(python_path, ["-u", helper, str(OS.get_process_id())], false)
	if process.is_empty():
		return false
	_pid = int(process["pid"])
	_io = process["stdio"]
	_err = process["stderr"]
	running = true
	return true

func stop() -> void:
	if _io != null:
		if _pid > 0 and OS.is_process_running(_pid):
			_io.store_line("quit")
		_io.close()
	if _err != null:
		_err.close()
	_io = null
	_err = null
	_pid = -1
	_buffer = ""
	running = false
	focus = {}

func tick(delta: float) -> void:
	_clock += clampf(delta, 0.0, 0.1)
	if not focus.is_empty():
		_last_seen[str(focus.get("hwnd", ""))] = _clock
	if _io == null:
		return
	_buffer += _io.get_buffer(4096).get_string_from_utf8()
	if _err != null:
		_err.get_buffer(2048)
	if _buffer.length() > 8192:
		stop()
		return
	while _buffer.contains("\n"):
		var cut: int = _buffer.find("\n")
		var line: String = _buffer.substr(0, cut).strip_edges()
		_buffer = _buffer.substr(cut + 1)
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			accept(parsed)
	if _pid > 0 and not OS.is_process_running(_pid):
		stop()

## Принять одно сообщение помощника (отдельно — чтобы проверять тестами).
func accept(report: Dictionary) -> void:
	if bool(report.get("ready", false)) or bool(report.get("own", false)):
		return # нажали на саму Хоши — это не смена окна
	if not report.has("hwnd"):
		return
	var hwnd: String = str(report["hwnd"])
	var same: bool = str(focus.get("hwnd", "")) == hwnd
	focus = {"hwnd": hwnd, "app": str(report.get("app", "")), "state": str(report.get("state", ""))}
	if not same:
		_since = _clock
	_last_seen[hwnd] = _clock

## Сколько секунд подряд активно текущее окно.
func dwell_seconds() -> float:
	return 0.0 if focus.is_empty() else _clock - _since

## Сколько секунд назад окно было активным (INF — ни разу).
func seconds_since_active(hwnd: String) -> float:
	if str(focus.get("hwnd", "")) == hwnd:
		return 0.0
	return _clock - float(_last_seen[hwnd]) if _last_seen.has(hwnd) else INF

## Для тестов: сдвинуть часы трекера.
func advance(seconds: float) -> void:
	_clock += seconds
