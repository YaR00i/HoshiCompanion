extends RefCounted
## Плеер MPC-BE на пульте — «встроенный аддон»: карточка как у YouTube.
##
## MPC-BE сам отдаёт состояние и принимает команды через свой веб-интерфейс
## (Настройки → Веб-интерфейс; включать только для этого ПК). Хоши говорит с
## ним только по 127.0.0.1:13579 и только пока пульт включён и телефон на
## связи: раз в секунду читает variables.html, а если плеер закрыт — пробует
## раз в 3 секунды.
##
## Приватность (решение 2026-09-27): берём только имя файла, время, длительность,
## играет ли и громкость плеера. Полный путь (filepath, filedir) MPC-BE тоже отдаёт — его не
## разбираем и никуда не передаём.
## Команды — только по нажатию человека на пульте, сама Хоши их не запускает.

## Ключ «соединения» встроенного аддона в app_adapters.gd (у настоящих — >= 1).
const PEER: int = -1
const ID: String = "mpc"
const HOST: String = "127.0.0.1"
const PORT: int = 13579
const POLL_EVERY: float = 1.0
const PROBE_EVERY: float = 3.0
const REQUEST_TIMEOUT: float = 2.0
const MAX_BODY: int = 32768
const STEP_SECONDS: int = 10

## Номера команд MPC-BE (wm_command), сверены с его веб-интерфейсом 1.8.9.
const WM := {"toggle": 889, "next": 920, "prev": 919, "fullscreen": 830,
	"vol_up": 907, "vol_down": 908, "mute": 909}

const COMMANDS: Array = [
	{"name": "back", "title": "−10 секунд", "icon": "⏪", "row": "main", "args": {"seconds": STEP_SECONDS}},
	{"name": "toggle", "title": "Пауза / играть", "icon": "⏯", "row": "main"},
	{"name": "forward", "title": "+10 секунд", "icon": "⏩", "row": "main", "args": {"seconds": STEP_SECONDS}},
	{"name": "next", "title": "Следующий файл", "icon": "⏭", "row": "main"},
	{"name": "prev", "title": "Предыдущий файл", "icon": "⏮"},
	{"name": "vol_down", "title": "Тише", "icon": "🔉"},
	{"name": "vol_up", "title": "Громче", "icon": "🔊"},
	{"name": "mute", "title": "Без звука", "icon": "🔈"},
	{"name": "fullscreen", "title": "Во весь экран", "icon": "⛶"},
	{"name": "seek_to", "title": "Перейти к моменту", "icon": "", "row": "hidden", "args": {"time": 0}},
]

## MPC-BE отвечает (плеер открыт, веб-интерфейс включён).
var present: bool = false
## Разобранное состояние: file, state (-1 нет, 0 стоп, 1 пауза, 2 играет), position/duration (с),
## volume (0–100), muted.
var info: Dictionary = {}
## Для тестов: вместо запросов записывать, что было бы отправлено.
var dry_run: bool = false
var sent: Array = []

var _http := HTTPClient.new()
var _job: Dictionary = {}       # {"kind": "poll"|"cmd", "body": String}
var _queue: Array = []
var _requested: bool = false
var _body := PackedByteArray()
var _age: float = 0.0
var _clock: float = 0.0
var _field := RegEx.new()

func _init() -> void:
	_field.compile("<p id=\"(file|state|position|duration|volumelevel|muted)\">([^<]*)</p>")

## Объявление для app_adapters.announce().
func announcement() -> Dictionary:
	return {"id": ID, "title": "MPC-BE", "commands": COMMANDS, "state": card_state()}

## Что показать на карточке пульта (формат как у расширения YouTube).
func card_state() -> Dictionary:
	var file: String = str(info.get("file", ""))
	var state: int = int(info.get("state", -1))
	if file.is_empty() or state < 0:
		return {"hint": "MPC-BE открыт — выбери файл"}
	var playing: bool = state == 2
	var muted: bool = bool(info.get("muted", false))
	var subtitle: String = "MPC-BE" + (" · стоп" if state == 0 else "")
	if info.has("volume"):
		subtitle += " · " + ("без звука" if muted else "громкость %d%%" % int(info["volume"]))
	return {"title": file.get_basename(), "subtitle": subtitle,
		"time": int(info.get("position", 0)), "duration": int(info.get("duration", 0)),
		"playing": playing, "icons": {"toggle": "⏸" if playing else "▶", "mute": "🔇" if muted else "🔈"},
		"active": ["mute"] if muted else []}

## Разобрать variables.html: только нужные поля, путь к файлу не трогаем.
func parse_variables(html: String) -> Dictionary:
	var result: Dictionary = {}
	for found in _field.search_all(html):
		var value: String = found.get_string(2).xml_unescape().strip_edges()
		match found.get_string(1):
			"file":
				result["file"] = value.get_file().left(160)
			"state":
				result["state"] = int(value) if value.is_valid_int() else -1
			"position", "duration":
				result[found.get_string(1)] = floori(float(value) / 1000.0) if value.is_valid_int() else 0
			"volumelevel":
				result["volume"] = clampi(int(value), 0, 100) if value.is_valid_int() else 0
			"muted":
				result["muted"] = value == "1"
	return result

## Нажатие на пульте: name — из COMMANDS. Пусто — отправлено, иначе причина.
func run(name: String, args: Dictionary) -> String:
	if not present:
		return "not_running"
	var body: String = ""
	match name:
		"toggle", "next", "prev", "fullscreen", "vol_up", "vol_down", "mute":
			body = "wm_command=%d" % WM[name]
		"back", "forward", "seek_to":
			var duration: int = int(info.get("duration", 0))
			var target: int = int(args.get("time", 0))
			if name != "seek_to":
				var step: int = clampi(int(args.get("seconds", STEP_SECONDS)), 1, 600)
				target = int(info.get("position", 0)) + (step if name == "forward" else -step)
			target = clampi(target, 0, maxi(0, duration - 1)) if duration > 0 else maxi(0, target)
			info["position"] = target # два быстрых нажатия складываются
			body = "wm_command=-1&position=" + clock(target)
		_:
			return "unknown_command"
	if dry_run:
		sent.append(body)
		return ""
	if _queue.size() < 8:
		_queue.append({"kind": "cmd", "body": body})
	_clock = POLL_EVERY # сразу перечитать состояние после команды
	return ""

static func clock(seconds: int) -> String:
	return "%02d:%02d:%02d" % [floori(seconds / 3600.0), floori(seconds / 60.0) % 60, seconds % 60]

## wanted — есть телефон на связи. Запросы идут по одному и не держат кадр.
func tick(delta: float, wanted: bool) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	if not wanted:
		_queue.clear()
		if _job.is_empty():
			return
	_clock += dt
	if _job.is_empty():
		if not _queue.is_empty():
			_start(_queue.pop_front())
		elif wanted and not dry_run and _clock >= (POLL_EVERY if present else PROBE_EVERY):
			_clock = 0.0
			_start({"kind": "poll", "body": ""})
		return
	_advance(dt)

func _start(job: Dictionary) -> void:
	_http.close()
	if _http.connect_to_host(HOST, PORT) != OK:
		_finish(false)
		return
	_job = job
	_requested = false
	_body = PackedByteArray()
	_age = 0.0

func _advance(dt: float) -> void:
	_age += dt
	_http.poll()
	match _http.get_status():
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			pass
		HTTPClient.STATUS_CONNECTED:
			if not _requested:
				_requested = true
				if _job["kind"] == "poll":
					_http.request(HTTPClient.METHOD_GET, "/variables.html", PackedStringArray())
				else:
					_http.request(HTTPClient.METHOD_POST, "/command.html",
						PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]), str(_job["body"]))
			elif _http.has_response():
				_finish(_http.get_response_code() == 200)
				return
		HTTPClient.STATUS_BODY:
			_body.append_array(_http.read_response_body_chunk())
			if _body.size() > MAX_BODY:
				_finish(false)
				return
		_:
			# MPC-BE может закрыть соединение сразу после ответа.
			_finish(_requested and _http.has_response() and _http.get_response_code() == 200)
			return
	if _age > REQUEST_TIMEOUT:
		_finish(false)

func _finish(ok: bool) -> void:
	var job: Dictionary = _job
	_job = {}
	_http.close()
	if job.get("kind", "") == "poll" or job.is_empty():
		present = ok
		info = parse_variables(_body.get_string_from_utf8()) if ok else {}
	_body = PackedByteArray()
