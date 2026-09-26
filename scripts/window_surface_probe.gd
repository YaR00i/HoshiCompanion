extends RefCounted
## One-shot geometry inspection of the window explicitly selected under the cursor.

var status: String = "off"
var result: Dictionary = {}
var process_id: int = -1
var _io: FileAccess
var _err: FileAccess
var _buffer: String = ""
var _age: float = 0.0

func begin(mode: String = "structure") -> bool:
	close()
	if OS.get_name() != "Windows":
		_fail("platform")
		return false
	var python_path: String = "python"
	if FileAccess.file_exists("res://python_path.txt"):
		python_path = FileAccess.get_file_as_string("res://python_path.txt").strip_edges()
	var helper: String = ProjectSettings.globalize_path("res://tools/window_surfaces.py")
	if not FileAccess.file_exists(helper):
		_fail("packaging")
		return false
	var own: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	var args: PackedStringArray = ["-u", helper, str(OS.get_process_id()), str(own), mode]
	var process: Dictionary = OS.execute_with_pipe(python_path, args, false)
	if process.is_empty():
		_fail("python")
		return false
	process_id = int(process["pid"])
	_io = process["stdio"]
	_err = process["stderr"]
	status = "waiting"
	_age = 0.0
	return true

func tick(delta: float) -> void:
	if status != "waiting" or _io == null:
		return
	_age += clampf(delta, 0.0, 0.1)
	_buffer += _io.get_buffer(8192).get_string_from_utf8()
	if _err != null:
		_err.get_buffer(2048) # Do not log text from a foreign UIA provider.
	if _buffer.length() > 20000:
		_fail("protocol")
		return
	while _buffer.contains("\n"):
		var cut: int = _buffer.find("\n")
		var line: String = _buffer.substr(0, cut).strip_edges()
		_buffer = _buffer.substr(cut + 1)
		var parsed: Variant = JSON.parse_string(line)
		if not parsed is Dictionary:
			_fail("protocol")
			return
		if bool(parsed.get("ready", false)):
			continue
		if not parsed.has("ok"):
			_fail("protocol")
			return
		result = parsed
		status = "done"
		_release()
		return
	if _age > 13.0 or (process_id > 0 and not OS.is_process_running(process_id)):
		_fail("timeout")

func _fail(reason: String) -> void:
	result = {"ok": false, "reason": reason}
	status = "done"
	_release()

func close() -> void:
	_release()
	result = {}
	status = "off"

func _release() -> void:
	if _io != null:
		_io.close()
	if _err != null:
		_err.close()
	_io = null
	_err = null
	_buffer = ""
	process_id = -1
