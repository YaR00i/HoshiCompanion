extends RefCounted
## On-demand read-only bridge. No service, ports, titles, screenshots or hooks.
## Only one outstanding request; all pipe reads are non-blocking and bounded.
var status: String = "off"
var reason: String = ""
var snapshot: Dictionary = {}
var seconds_left: float = 4.0
var process_id: int = -1
var last_process_id: int = -1
var _io: FileAccess
var _err: FileAccess
var _buffer: String = ""
var _target: int = 0
var _pending: bool = false
var _age: float = 0.0
var _poll: float = 0.0

func begin(owner_pid: int, explicit_handle: int = 0) -> bool:
	close()
	if OS.get_name() != "Windows":
		_fail("platform")
		return false
	var python_path: String = "python"
	if FileAccess.file_exists("res://python_path.txt"):
		python_path = FileAccess.get_file_as_string("res://python_path.txt").strip_edges()
	var helper: String = ProjectSettings.globalize_path("res://tools/window_geometry.py")
	if not FileAccess.file_exists(helper):
		_fail("packaging")
		return false
	var own: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	var position: Vector2i = DisplayServer.window_get_position()
	var args: PackedStringArray = ["-u", helper, str(owner_pid), str(own), str(position.x), str(position.y)]
	var process: Dictionary = OS.execute_with_pipe(python_path, args, false)
	if process.is_empty():
		_fail("python")
		return false
	process_id = int(process["pid"])
	last_process_id = process_id
	_io = process["stdio"]
	_err = process["stderr"]
	_target = explicit_handle
	status = "starting"
	reason = ""
	seconds_left = 4.0
	_age = 0.0
	_poll = 0.0
	return true

func tick(delta: float) -> void:
	if _io == null:
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	_age += dt
	_buffer += _io.get_buffer(4096).get_string_from_utf8()
	if _err != null:
		_err.get_buffer(2048) # Drain, but never log arbitrary subprocess text.
	if _buffer.length() > 8192:
		_fail("protocol")
		return
	while _buffer.contains("\n"):
		var end: int = _buffer.find("\n")
		var line: String = _buffer.substr(0, end).strip_edges()
		_buffer = _buffer.substr(end + 1)
		_receive(line)
		if status == "error":
			return
	if status == "selecting":
		seconds_left -= dt
		if seconds_left <= 0.0:
			status = "probing"
			_send({"op": "pick"})
	elif status == "following" and not _pending:
		_poll += dt
		if _poll >= 0.04:
			_poll = 0.0
			_send({"op": "probe"})
	if (status == "starting" or _pending) and _age > 2.0:
		_fail("timeout")
	elif process_id > 0 and not OS.is_process_running(process_id):
		_fail("disconnected")

func _send(message: Dictionary) -> void:
	if _io == null:
		return
	_io.store_line(JSON.stringify(message))
	_pending = true
	_age = 0.0

func _receive(line: String) -> void:
	var data: Variant = JSON.parse_string(line)
	if not data is Dictionary:
		_fail("protocol")
		return
	_pending = false
	_age = 0.0
	if bool(data.get("ready", false)) and status == "starting":
		if OS.get_cmdline_user_args().has("--test-mode"):
			print("HOST_COORDINATE_SHIFT ", data.get("coordinate_shift", []), " current_host=", DisplayServer.window_get_position())
		if _target > 0:
			status = "probing"
			_send({"op": "bind", "hwnd": str(_target)})
		else:
			status = "selecting"
		return
	if not bool(data.get("ok", false)):
		_fail(str(data.get("reason", "unavailable")))
		return
	if data.get("space", "") != "godot_virtual_pixels":
		_fail("protocol")
		return
	for key in ["rect", "area"]:
		var values: Variant = data.get(key, [])
		if not values is Array or values.size() != 4:
			_fail("protocol")
			return
		for number in values:
			if not (number is float or number is int) or not is_finite(float(number)) or absf(float(number)) > 1000000:
				_fail("protocol")
				return
		if float(values[2]) <= 0.0 or float(values[3]) <= 0.0:
			_fail("protocol")
			return
	snapshot = data
	status = "following"

func _fail(value: String) -> void:
	close()
	reason = value
	status = "error"

func close() -> void:
	if _io != null:
		if process_id > 0 and OS.is_process_running(process_id):
			_io.store_line('{"op":"quit"}')
		_io.close()
	if _err != null:
		_err.close()
	_io = null
	_err = null
	process_id = -1
	_buffer = ""
	_pending = false
	snapshot = {}
	status = "off"

func current_rect() -> Rect2i:
	var a: Array = snapshot.get("rect", [0, 0, 0, 0])
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))

func current_area() -> Rect2i:
	var a: Array = snapshot.get("area", [0, 0, 0, 0])
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))

func message() -> String:
	match reason:
		"packaging": return "Для внешних окон нужна папка tools рядом с проектом"
		"own": return "Наведи курсор на другое приложение, не на Хоши"
		"maximized", "fullscreen": return "Сначала уменьши окно: сверху нужно место"
		"python", "startup", "timeout", "disconnected": return "Нет связи с помощником окон; см. python_path.txt"
		"closed", "minimized", "hidden", "changed": return "Опора исчезла — вернусь на пол"
	return "Это окно не подходит. Попробуй обычное окно браузера"
