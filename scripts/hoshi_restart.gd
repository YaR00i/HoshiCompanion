extends RefCounted
## «Перезапустить Хоши» (меню и пульт): закрыться и открыться снова уже с
## новыми файлами проекта.
##
## Сначала tools/restart_hoshi.py check проверяет новую версию (импорт без
## ошибок в скриптах, как перед обычным запуском). Только если всё хорошо,
## запускается ожидающий помощник (relaunch) и Хоши закрывается обычным путём —
## с порталом. Помощник дождётся, пока старая Хоши закроется, и запустит тот же
## Godot с теми же параметрами. Новая версия с ошибкой — Хоши остаётся, пульт
## не пропадает.

const HELPER: String = "res://tools/restart_hoshi.py"
const LOG: String = "res://logs/restart_import.log"
const CHECK_TIMEOUT: float = 200.0

## "" — ничего не идёт; "checking" — проверяю новую версию.
var status: String = ""
## Для тестов: вместо запуска записывать, что было бы выполнено.
var dry_run: bool = false
var executed: Array = []

var _io: FileAccess
var _err: FileAccess
var _pid: int = 0
var _buffer: String = ""
var _age: float = 0.0

## Начать. Пусто — проверка пошла, иначе причина отказа.
func begin() -> String:
	if status == "checking":
		return "busy"
	if OS.get_name() != "Windows" and not dry_run:
		return "platform"
	var helper: String = ProjectSettings.globalize_path(HELPER)
	if not dry_run and not FileAccess.file_exists(helper):
		return "packaging"
	var args: PackedStringArray = ["-u", helper, "check", OS.get_executable_path(),
		ProjectSettings.globalize_path("res://"), ProjectSettings.globalize_path(LOG)]
	status = "checking"
	_age = 0.0
	_buffer = ""
	if dry_run:
		executed.append(["check"])
		return ""
	var process: Dictionary = OS.execute_with_pipe(_python(), args, false)
	if process.is_empty():
		status = ""
		return "python"
	_pid = int(process["pid"])
	_io = process["stdio"]
	_err = process.get("stderr", null)
	return ""

## Каждый кадр. Возвращает "" (ждём), "ready" (можно закрываться — перезапуск
## уже ждёт) или причину отказа ("script_errors", "timeout", ...).
func tick(delta: float) -> String:
	if status != "checking" or _io == null:
		return ""
	_age += clampf(delta, 0.0, 0.1)
	_buffer += _io.get_buffer(4096).get_string_from_utf8()
	if _err != null:
		_err.get_buffer(4096) # Drain, but never log arbitrary subprocess text.
	var done: bool = not OS.is_process_running(_pid)
	if done:
		_buffer += _io.get_buffer(4096).get_string_from_utf8()
	elif _age < CHECK_TIMEOUT:
		return ""
	else:
		OS.kill(_pid)
	var parsed: Variant = JSON.parse_string(_buffer.strip_edges().get_slice("\n", 0)) if done else null
	return finish(parsed if parsed is Dictionary else {"ok": false, "error": "timeout" if not done else "no_answer"})

## Ответ проверки (отдельной функцией — тесты подают его сами).
func finish(result: Dictionary) -> String:
	status = ""
	_io = null
	_err = null
	_pid = 0
	if not bool(result.get("ok", false)):
		return str(result.get("error", "failed"))
	var args: PackedStringArray = ["-u", ProjectSettings.globalize_path(HELPER), "relaunch", str(OS.get_process_id()),
		OS.get_executable_path(), ProjectSettings.globalize_path("res://"), "--"]
	args.append_array(relaunch_args())
	if dry_run:
		executed.append(["relaunch"] + Array(args))
		return "ready"
	if OS.create_process(_python(), args) <= 0:
		return "python"
	return "ready"

## Параметры для новой Хоши: папка проекта и журнал как у tools/launch.cmd (Godot
## их «съедает» и не отдаёт обратно), плюс остальные параметры этого запуска и
## после «--» — её собственные (--desktop, --preview...).
static func relaunch_args() -> PackedStringArray:
	var root: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var args: PackedStringArray = ["--path", root, "--log-file", root + "/logs/session.log"]
	args.append_array(OS.get_cmdline_args())
	var user: PackedStringArray = OS.get_cmdline_user_args()
	if not user.is_empty():
		args.append("--")
		args.append_array(user)
	return args

## Что сказать, если перезапуск не получился.
static func reason_text(reason: String) -> String:
	match reason:
		"script_errors":
			return "В новой версии ошибка в скриптах — остаюсь как есть (logs/restart_import.log)"
		"busy":
			return "Уже проверяю новую версию"
		"timeout":
			return "Проверка новой версии зависла — остаюсь как есть"
		"python", "packaging", "platform":
			return "Не могу перезапуститься: нет помощника (см. python_path.txt)"
	return "Не получилось перезапуститься — остаюсь как есть"

func _python() -> String:
	if FileAccess.file_exists("res://python_path.txt"):
		return FileAccess.get_file_as_string("res://python_path.txt").strip_edges()
	return "python"
