extends RefCounted
## ИИ-помощники на ПК (пока Claude Code): кто работает, кто закончил, кто ждёт.
##
## Claude Code сам присылает «записки» (хук tools/claude_hook.py) на
## http://127.0.0.1:18772/assistant — только с этого ПК. Хоши помнит по каждой
## сессии: папку проекта (только имя), статус и текст последнего ответа — и
## показывает это на пульте карточкой «Claude» (встроенный аддон, как MPC-BE).
## Приватность (решение 2026-09-27): статус, имя папки и текст последнего ответа
## идут на привязанный телефон; всё хранится только в памяти, на диск — нет.
##
## История бесед (решение 2026-09-27, на ПК): по просьбе телефона
## tools/claude_history.py читает журналы Claude Code — список сессий или
## тексты одной беседы (без служебных шагов); ответ уходит только тому
## телефону, который попросил (шина пульта забирает take_history()).
##
## Разрешения и вопросы с вариантами (решение 2026-09-27): хук claude_hook.py
## --ask присылает «Permission» или «Question» и ждёт. Телефона нет — сразу
## «нет» (обычное окно на ПК). Есть — карточка показывает запрос; ответ
## уходит хуку; нет ответа 30 с — «нет», и спросят на ПК.
##
## Ответ с телефона (решение 2026-09-27): когда Claude закончил, фоновый хук
## (claude_hook.py --wait, asyncRewake) присылает «Wait» и держит соединение.
## Пока он ждёт, на карточке есть поле «Ответить». Текст с телефона уходит ему,
## он будит Claude этим сообщением. Написал на ПК (новый вопрос) или сессия
## закрылась — ждун отпускается без ответа.

## Ключ «соединения» встроенного аддона в app_adapters.gd (MPC-BE — -1).
const PEER: int = -2
const ID: String = "claude"
const CODEX_PEER: int = -3
const APPS := ["claude", "codex"]
const PORT: int = 18772
## Помощник закончил ход (был «работает»/«ждёт» → ответил) — Хоши зовёт «Хей!».
signal finished(app: String)
const PATH: String = "/assistant"
const MAX_BODY: int = 32768
const MAX_SESSIONS: int = 8
const MAX_TEXT: int = 6000
## Самый длинный ответ с телефона.
const MAX_REPLY: int = 2000
const CODEX_REPLY_TIMEOUT: float = 60.0
## Сколько ждать ответа на разрешение/вопрос с телефона, потом — окно на ПК.
const ASK_TIMEOUT: float = 30.0
const ASK_LETTERS: String = "abcdefghijkmnopqrstuvwxyz" # без «l»: не спутать с «1»
## Картинки/гифки/видео из ответа (их находит хук): не больше, и какие виды.
const MAX_MEDIA: int = 8
const MAX_MEDIA_BYTES: int = 16 * 1024 * 1024
const MEDIA_TYPES := {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
	"webp": "image/webp", "mp4": "video/mp4", "webm": "video/webm"}
## Закончившие сессии без новостей дольше этого — убрать с пульта.
const FORGET_AFTER: float = 3.0 * 3600.0
## Облачко «✓ закончил» над Хоши держится не дольше этого.
const DONE_CLOUD_SECONDS: float = 600.0
## Облачка живые (просьба 28.09): «работает» — пока беседа Claude меняется;
## тихо дольше этого (прервали Esc, закрыли окно) — облачко уходит.
const WORKING_QUIET_SECONDS: float = 360.0
## «?» без ответа дольше этого — тоже уходит (на ПК ответят и без Хоши).
const WAITING_CLOUD_SECONDS: float = 3600.0
## Как часто смотреть время изменения файла беседы (только время, не текст).
const LIVE_POLL_SECONDS: float = 20.0

const STATUS_TEXT := {"working": "работает…", "done": "✓ закончил", "waiting": "? ждёт разрешения", "idle": "на связи",
	"failed": "⚠ прервался"}

## session id -> {folder, status, text, note, at (с), seen}
var sessions: Dictionary = {}
## Для тестов: другой порт.
var port: int = PORT
## Для тестов: где лежат беседы Claude ("" — ~/.claude/projects).
var transcripts_root: String = ""
var listening: bool = false

var _server := TCPServer.new()
var _clients: Array = []   # [{stream, buffer, age}]
var _waiters: Dictionary = {}  # session id -> StreamPeerTCP (ждун ответа с телефона)
var _waiter_at: Dictionary = {}
## Сколько телефонов на связи (ставит шина пульта): 0 — вопросы сразу на ПК.
var phones: int = 0
## Сообщение для Хоши на ПК (забирает шина пульта).
var notice: String = ""
## Открытый вопрос/разрешение: {id, session, kind, tool, detail, questions, stream, at}
var ask: Dictionary = {}
## Готовые ответы «история» для телефонов: [{peer, message}] (забирает шина).
var history_ready: Array = []
## Для тестов: вместо помощника записывать, что просили.
var history_dry_run: bool = false
var history_asked: Array = []
var _history_jobs: Array = []  # [{peer, kind, io, pid, buffer, age}]
const HISTORY_HELPER: String = "res://tools/claude_history.py"
const CODEX_HISTORY_HELPER: String = "res://tools/codex_history.py"
const HISTORY_MESSAGES: int = 50
var _clock: float = 0.0
var _live_wait: float = 0.0
## session id -> путь к файлу беседы (~/.claude/projects/*/<id>.jsonl), "" — не нашли.
var _transcripts: Dictionary = {}
var codex_transcripts_root: String = ""
var _crypto := Crypto.new()

func start() -> bool:
	stop()
	listening = _server.listen(port, "127.0.0.1") == OK
	return listening

func stop() -> void:
	for client in _clients:
		client["stream"].disconnect_from_host()
	_clients.clear()
	if not ask.is_empty():
		_finish_ask({}) # Хоши закрывается — вопрос уходит на ПК
	# Хоши закрывается: просто обрываем связь (не «отпускаем»), чтобы ждуны
	# постучались снова, когда она вернётся (перезапуск), и принесли карточку.
	for id in _waiters.keys():
		(_waiters[id] as StreamPeerTCP).disconnect_from_host()
	_waiters.clear()
	_waiter_at.clear()
	_server.stop()
	listening = false

func tick(delta: float) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	_clock += dt
	_poll_history(dt)
	_live_wait -= dt
	if _live_wait <= 0.0:
		_live_wait = LIVE_POLL_SECONDS
		poll_live()
	if not listening:
		return
	while _server.is_connection_available():
		var stream: StreamPeerTCP = _server.take_connection()
		if _clients.size() >= 8 or stream.get_connected_host() != "127.0.0.1":
			stream.disconnect_from_host()
			continue
		_clients.append({"stream": stream, "buffer": PackedByteArray(), "age": 0.0})
	for client in _clients.duplicate():
		var stream: StreamPeerTCP = client["stream"]
		stream.poll()
		client["age"] += dt
		var available: int = stream.get_available_bytes()
		if available > 0:
			var chunk: Array = stream.get_partial_data(mini(available, MAX_BODY))
			if chunk[0] == OK:
				# PackedByteArray is a value: store the grown copy back.
				var grown: PackedByteArray = client["buffer"]
				grown.append_array(chunk[1])
				client["buffer"] = grown
		var request: Variant = _complete_request(client["buffer"])
		var broken: bool = (client["buffer"] as PackedByteArray).size() > MAX_BODY + 2048 or client["age"] > 3.0 or stream.get_status() != StreamPeerTCP.STATUS_CONNECTED
		if request != null or broken:
			_clients.erase(client)
			if request is Dictionary and str(request.get("event", "")) == "Wait":
				_add_waiter(request, stream)
				continue
			if request is Dictionary and str(request.get("event", "")) in ["Permission", "Question"]:
				_add_ask(request, stream)
				continue
			if request is Dictionary:
				handle_event(request)
				stream.put_data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_utf8_buffer())
			stream.disconnect_from_host()
	for id in _waiters.keys():
		var waiter: StreamPeerTCP = _waiters[id]
		waiter.poll()
		if str(id).begins_with("codex:") and (_clock - float(_waiter_at.get(id, _clock)) >= CODEX_REPLY_TIMEOUT or phones <= 0):
			_release(id, "")
		elif waiter.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_waiters.erase(id)
			_waiter_at.erase(id)
	if not ask.is_empty():
		var held: StreamPeerTCP = ask["stream"]
		held.poll()
		if held.get_status() != StreamPeerTCP.STATUS_CONNECTED or _clock - float(ask["at"]) > ASK_TIMEOUT:
			_finish_ask({}) # не ответили — спросят на ПК

## Полный POST на /assistant -> разобранный JSON; не весь ещё -> null; мусор -> {} .
func _complete_request(buffer: PackedByteArray) -> Variant:
	var text: String = buffer.get_string_from_utf8()
	var head_end: int = text.find("\r\n\r\n")
	if head_end < 0:
		return null
	var head: String = text.substr(0, head_end)
	if not head.begins_with("POST " + PATH + " "):
		return "bad"
	var length: int = -1
	for line in head.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			length = int(line.get_slice(":", 1).strip_edges())
	if length < 0 or length > MAX_BODY:
		return "bad"
	var body_start: int = head.to_utf8_buffer().size() + 4
	if buffer.size() - body_start < length:
		return null
	var parsed: Variant = JSON.parse_string(buffer.slice(body_start, body_start + length).get_string_from_utf8())
	return parsed if parsed is Dictionary else "bad"

## Записка от хука (отдельной функцией — тесты подают её сами).
func handle_event(message: Dictionary) -> void:
	var app: String = str(message.get("app", ""))
	if not app in APPS:
		return
	var raw_id: String = str(message.get("session", "")).left(64)
	if raw_id.is_empty():
		return
	var id: String = _key(app, raw_id)
	var event: String = str(message.get("event", ""))
	if event in ["SessionEnd", "UserPromptSubmit", "Interrupt"]:
		_release(id, "") # новый вопрос, прерывание или закрытие — ждун больше не нужен
	if event == "SessionEnd":
		sessions.erase(id)
		_transcripts.erase(id)
		return
	var session: Dictionary = sessions.get(id, {"app": app, "id": raw_id, "folder": "", "status": "idle", "text": "", "note": "", "at": _clock, "seen": true})
	if app == "codex" and str(message.get("transcript_path", "")) != "":
		var path: String = str(message["transcript_path"])
		if path.is_absolute_path() and path.get_file().ends_with(".jsonl"):
			_transcripts[id] = path
	var folder: String = str(message.get("folder", "")).get_file().left(80)
	if not folder.is_empty():
		session["folder"] = folder
	match event:
		"SessionStart":
			pass
		"UserPromptSubmit":
			session["status"] = "working"
			session["note"] = ""
		"StopFailure":
			# Ход оборвался (лимит использования или ошибка) — «работает» больше не правда.
			session["status"] = "failed"
			session["note"] = ("Codex" if app == "codex" else "Claude") + " прервался: закончился лимит или ошибка связи. Когда можно — нажми «▶ Продолжай»."
			session["seen"] = false
		"Interrupt":
			if app != "codex":
				return
			session["status"] = "failed"
			session["note"] = "Ход остановлен до завершения. Если нужно, напиши новое сообщение в Codex."
			session["seen"] = false
		"Stop":
			if str(session["status"]) in ["working", "waiting"]:
				finished.emit(app)
			session["status"] = "done"
			session["text"] = str(message.get("text", "")).left(MAX_TEXT)
			session["media"] = _clean_media(message.get("media", []))
			session["seen"] = false
		"Notification":
			match str(message.get("kind", "")):
				"permission_prompt":
					session["status"] = "waiting"
					session["note"] = str(message.get("text", "")).left(300)
					session["seen"] = false
				"idle_prompt":
					# «Claude ждёт ввода» через минуту простоя — не новость: срок «✓»
					# не продлеваем, сессия просто не «работает».
					if session["status"] == "working":
						session["status"] = "done"
					sessions[id] = session
					return
		_:
			return
	session["at"] = _clock
	session["active_at"] = _clock
	sessions[id] = session
	_trim()

## Телефон просит историю: kind "sessions" (все сессии) или "read" (беседа;
## пустой session — текущая, с карточки).
func request_history(peer: int, kind: String, session: String, app: String = "claude") -> void:
	if not app in APPS or not kind in ["sessions", "read"] or _history_jobs.size() >= 3:
		return
	if kind == "read" and session.is_empty():
		session = latest(app)
	if kind == "read" and (session.is_empty() or not _looks_like_session(session)):
		history_ready.append({"peer": peer, "message": {"op": "history", "app": app, "kind": "read", "ok": false, "error": "no_session"}})
		return
	var args: Array = ["sessions", "30"] if kind == "sessions" else ["read", session, str(HISTORY_MESSAGES)]
	if history_dry_run:
		history_asked.append([peer] + args if app == "claude" else [peer, app] + args)
		return
	var helper: String = ProjectSettings.globalize_path(CODEX_HISTORY_HELPER if app == "codex" else HISTORY_HELPER)
	if OS.get_name() != "Windows" or not FileAccess.file_exists(helper):
		return
	var python: String = FileAccess.get_file_as_string("res://python_path.txt").strip_edges() if FileAccess.file_exists("res://python_path.txt") else "python"
	var process: Dictionary = OS.execute_with_pipe(python, PackedStringArray(["-u", helper] + args), false)
	if not process.is_empty():
		_history_jobs.append({"peer": peer, "kind": kind, "app": app, "io": process["stdio"], "pid": int(process["pid"]), "buffer": PackedByteArray(), "age": 0.0})

static func _looks_like_session(id: String) -> bool:
	if id.length() < 8 or id.length() > 64:
		return false
	for character in id:
		if not (character.is_valid_hex_number() or character == "-"):
			return false
	return true

## Ответ помощника истории (отдельной функцией — тесты подают его сами).
func apply_history(peer: int, kind: String, result: Variant, app: String = "claude") -> void:
	var message: Dictionary = {"op": "history", "app": app, "kind": kind, "ok": result is Dictionary and bool(result.get("ok", false))}
	if message["ok"]:
		if kind == "sessions":
			var list: Array = []
			for s in result.get("sessions", []):
				if s is Dictionary and list.size() < 30:
					list.append({"id": str(s.get("id", "")).left(64), "title": str(s.get("title", "")).left(80),
						"folder": str(s.get("folder", "")).left(80), "updated": int(s.get("updated", 0)), "current": str(s.get("id", "")) == latest(app)})
			message["sessions"] = list
		else:
			var messages: Array = []
			for m in result.get("messages", []):
				if m is Dictionary and str(m.get("role", "")) in ["user", "phone", "assistant"] and messages.size() < HISTORY_MESSAGES:
					messages.append({"role": m["role"], "text": str(m.get("text", "")).left(3000), "time": str(m.get("time", "")).left(19)})
			message["id"] = str(result.get("id", "")).left(64)
			message["title"] = str(result.get("title", "")).left(80)
			message["messages"] = messages
	history_ready.append({"peer": peer, "message": message})

## Забрать готовые ответы истории (шина отправит каждый своему телефону).
func take_history() -> Array:
	var ready: Array = history_ready
	history_ready = []
	return ready

func _poll_history(dt: float) -> void:
	for job in _history_jobs.duplicate():
		job["age"] = float(job["age"]) + dt
		var chunk: PackedByteArray = (job["io"] as FileAccess).get_buffer(262144)
		if not chunk.is_empty():
			var grown: PackedByteArray = job["buffer"]
			grown.append_array(chunk)
			job["buffer"] = grown
		if OS.is_process_running(int(job["pid"])) and float(job["age"]) < 10.0:
			continue
		if OS.is_process_running(int(job["pid"])):
			OS.kill(int(job["pid"]))
		var rest: PackedByteArray = (job["io"] as FileAccess).get_buffer(1048576)
		var all: PackedByteArray = job["buffer"]
		all.append_array(rest)
		_history_jobs.erase(job)
		apply_history(int(job["peer"]), str(job["kind"]), JSON.parse_string(all.get_string_from_utf8().strip_edges()), str(job["app"]))

## Разрешение или вопрос от хука: телефона нет — сразу «нет»; есть — держим.
func _add_ask(message: Dictionary, stream: StreamPeerTCP) -> void:
	var app: String = str(message.get("app", ""))
	if not app in APPS or phones <= 0 or not ask.is_empty() or str(message.get("session", "")).is_empty():
		_reply(stream, {})
		return
	var raw_id: String = str(message.get("session", "")).left(64)
	var session: String = _key(app, raw_id)
	var code: String = ""
	for i in range(5):
		code += ASK_LETTERS[_crypto.generate_random_bytes(1)[0] % ASK_LETTERS.length()]
	var questions: Array = []
	for q in message.get("questions", []):
		if q is Dictionary and questions.size() < 4:
			var options: Array = []
			for o in q.get("options", []):
				if o is Dictionary and options.size() < 6:
					options.append({"label": str(o.get("label", "")).left(80), "description": str(o.get("description", "")).left(200)})
			questions.append({"question": str(q.get("question", "")).left(400), "header": str(q.get("header", "")).left(30),
				"multiSelect": bool(q.get("multiSelect", false)), "options": options})
	var kind: String = "question" if str(message.get("event", "")) == "Question" else "permission"
	if kind == "question" and questions.is_empty():
		_reply(stream, {})
		return
	ask = {"id": code, "app": app, "session": session, "kind": kind, "tool": str(message.get("tool", "")).left(60),
		"detail": str(message.get("detail", "")).left(600), "questions": questions, "stream": stream, "at": _clock}
	if not sessions.has(session):
		handle_event({"app": app, "event": "SessionStart", "session": raw_id, "folder": message.get("folder", ""), "transcript_path": message.get("transcript_path", "")})
	sessions[session]["status"] = "waiting"
	sessions[session]["at"] = _clock
	notice = ("Codex" if app == "codex" else "Claude") + " ждёт ответа на телефоне (%d с)" % int(ASK_TIMEOUT)

## Ответ телефона на разрешение: behavior — "allow" / "deny".
func answer_permission(ask_id: String, behavior: String, app: String = "claude") -> String:
	if ask.is_empty() or ask["id"] != ask_id or ask["kind"] != "permission" or ask["app"] != app:
		return "no_question"
	if not behavior in ["allow", "deny"]:
		return "bad_answer"
	_finish_ask({"behavior": behavior})
	return ""

## Ответ телефона на вопрос: {текст вопроса: выбранный вариант или свой текст}.
func answer_question(ask_id: String, answers: Variant, app: String = "claude") -> String:
	if ask.is_empty() or ask["id"] != ask_id or ask["kind"] != "question" or ask["app"] != app:
		return "no_question"
	if not answers is Dictionary:
		return "bad_answer"
	var clean: Dictionary = {}
	for q in ask["questions"]:
		var value: String = str(answers.get(q["question"], "")).strip_edges().left(500)
		if value.is_empty():
			return "not_all_answered"
		clean[q["question"]] = value
	_finish_ask({"answers": clean})
	return ""

func _finish_ask(answer: Dictionary) -> void:
	if ask.is_empty():
		return
	var session: String = ask["session"]
	_reply(ask["stream"], answer)
	ask = {}
	if sessions.has(session):
		sessions[session]["status"] = "working"
		sessions[session]["at"] = _clock

## Ответ хуку: пустой — 204 («спроси на ПК»), иначе 200 с JSON.
func _reply(stream: StreamPeerTCP, answer: Dictionary) -> void:
	if stream.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		if answer.is_empty():
			stream.put_data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_utf8_buffer())
		else:
			var body: PackedByteArray = JSON.stringify(answer).to_utf8_buffer()
			stream.put_data(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % body.size()).to_utf8_buffer())
			stream.put_data(body)
	stream.disconnect_from_host()

## Можно ли ответить этой сессии с телефона (её ждун на связи).
func can_reply(id: String, app: String = "claude") -> bool:
	return _waiters.has(_key(app, id))

## Ответ с телефона. session — какая сессия была на карточке. Пусто — отправлено.
func reply(text: String, session: String, app: String = "claude") -> String:
	var clean: String = text.strip_edges().left(MAX_REPLY)
	if not app in APPS:
		return "unknown_app_command"
	var id: String = _key(app, session)
	if clean.is_empty():
		return "empty"
	if not sessions.has(id):
		return "unknown_session"
	if not can_reply(session, app):
		return "not_waiting"
	_release(id, clean)
	sessions[id]["status"] = "working"
	sessions[id]["note"] = ""
	sessions[id]["at"] = _clock
	return ""

func _add_waiter(message: Dictionary, stream: StreamPeerTCP) -> void:
	var app: String = str(message.get("app", ""))
	if not app in APPS or (app == "codex" and phones <= 0):
		_reply(stream, {})
		return
	var raw_id: String = str(message.get("session", "")).left(64)
	var id: String = _key(app, raw_id)
	if raw_id.is_empty() or (not _waiters.has(id) and _waiters.size() >= MAX_SESSIONS):
		stream.disconnect_from_host()
		return
	_release(id, "") # у сессии один ждун — старого отпускаем
	_waiters[id] = stream
	_waiter_at[id] = _clock
	# Ждун приносит последний ответ: после перезапуска Хоши карточка возвращается сама.
	if not sessions.has(id) or str(sessions[id]["text"]).is_empty():
		handle_event({"app": app, "event": "Stop", "session": raw_id, "folder": message.get("folder", ""), "text": message.get("text", ""), "media": message.get("media", []), "transcript_path": message.get("transcript_path", "")})

## Отпустить ждуна: text — ответ с телефона, пусто — без ответа.
func _release(id: String, text: String) -> void:
	if not _waiters.has(id):
		return
	var stream: StreamPeerTCP = _waiters[id]
	_waiters.erase(id)
	_waiter_at.erase(id)
	if stream.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		if text.is_empty():
			stream.put_data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_utf8_buffer())
		else:
			var body: PackedByteArray = JSON.stringify({"text": text}).to_utf8_buffer()
			stream.put_data(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % body.size()).to_utf8_buffer())
			stream.put_data(body)
	stream.disconnect_from_host()

## Облачка над Хоши: по одному на помощника — [{app, status}]. Ждёт разрешения
## важнее, чем работает; «закончил» — пока не погладили Хоши и не дольше 10 минут.
func clouds() -> Array:
	var result: Array = []
	for app in APPS:
		var status: String = ""
		for id in sessions:
			var session: Dictionary = sessions[id]
			if str(session.get("app", "claude")) != app:
				continue
			match str(session["status"]):
				"waiting":
					if _clock - float(session["at"]) < WAITING_CLOUD_SECONDS or (not ask.is_empty() and ask["session"] == id):
						status = "waiting"
				"working":
					var alive: float = maxf(float(session["at"]), float(session.get("active_at", 0.0)))
					var quiet: float = WORKING_QUIET_SECONDS if not transcript_path(id).is_empty() else 1800.0
					if status != "waiting" and _clock - alive < quiet:
						status = "working"
				"done", "failed":
					if status.is_empty() and not bool(session["seen"]) and _clock - float(session["at"]) < DONE_CLOUD_SECONDS:
						status = "done"
		if not status.is_empty():
			result.append({"app": app, "status": status})
	return result

## Жива ли беседа: смотрим только время изменения её файла (текст не читаем).
## Файл меняется — Claude работает; после «?» беседа пошла дальше — на ПК
## уже ответили, это снова «работает».
func poll_live() -> void:
	for id in sessions:
		var session: Dictionary = sessions[id]
		if not str(session["status"]) in ["working", "waiting"]:
			continue
		var path: String = transcript_path(id)
		if path.is_empty():
			continue
		var changed: float = float(FileAccess.get_modified_time(path))
		var known: float = float(session.get("file_time", 0.0))
		session["file_time"] = changed
		if known <= 0.0 or changed <= known:
			continue
		session["active_at"] = _clock
		var answered_here: bool = not ask.is_empty() and ask["session"] == id
		if str(session["status"]) == "waiting" and not answered_here and _clock - float(session["at"]) > 3.0:
			session["status"] = "working"
			session["note"] = ""

## Файл беседы этой сессии (ищем один раз); "" — не нашли.
func transcript_path(id: String) -> String:
	if _transcripts.has(id):
		return _transcripts[id]
	var found: String = ""
	if id.begins_with("codex:"):
		var root: String = codex_transcripts_root
		if root.is_empty():
			root = OS.get_environment("USERPROFILE").path_join(".codex").path_join("sessions")
		var raw_id: String = id.trim_prefix("codex:")
		if _looks_like_session(raw_id) and DirAccess.dir_exists_absolute(root):
			for year in DirAccess.get_directories_at(root):
				for month in DirAccess.get_directories_at(root.path_join(year)):
					for day in DirAccess.get_directories_at(root.path_join(year).path_join(month)):
						for name in DirAccess.get_files_at(root.path_join(year).path_join(month).path_join(day)):
							if name.ends_with(raw_id + ".jsonl"):
								found = root.path_join(year).path_join(month).path_join(day).path_join(name)
		_transcripts[id] = found
		return found
	var root: String = transcripts_root
	if root.is_empty():
		root = OS.get_environment("USERPROFILE").path_join(".claude").path_join("projects")
	if _looks_like_session(id) and DirAccess.dir_exists_absolute(root):
		for folder in DirAccess.get_directories_at(root):
			var candidate: String = root.path_join(folder).path_join(id + ".jsonl")
			if FileAccess.file_exists(candidate):
				found = candidate
				break
	_transcripts[id] = found
	return found

## Погладили Хоши — «видела»: облачка с ✓ тают.
func mark_seen() -> void:
	for id in sessions:
		sessions[id]["seen"] = true

## Файл по случайному адресу /media/<id> — только из последних ответов Claude.
## Пусто — такого нет. Путь никогда не уходит на телефон.
func media_file(media_id: String) -> Dictionary:
	for id in sessions:
		for item in sessions[id].get("media", []):
			if item["id"] == media_id:
				return item
	return {}

## Что знает телефон о картинках ответа: только адрес, имя файла и вид.
func _public_media(session: Dictionary) -> Array:
	var result: Array = []
	for item in session.get("media", []):
		result.append({"id": item["id"], "name": item["name"], "kind": item["kind"]})
	return result

## Список от хука -> [{id, path, name, kind, type}]: только медиа-файлы (по
## расширению), только локальные пути, новый случайный адрес на каждый ответ.
func _clean_media(items: Variant) -> Array:
	var result: Array = []
	if not items is Array:
		return result
	for item in items:
		if result.size() >= MAX_MEDIA or not item is Dictionary:
			break
		var path: String = str(item.get("path", ""))
		var extension: String = path.get_extension().to_lower()
		if not MEDIA_TYPES.has(extension) or path.begins_with("\\\\") or path.begins_with("//") or not path.is_absolute_path():
			continue
		result.append({"id": _crypto.generate_random_bytes(16).hex_encode(), "path": path,
			"name": path.get_file().left(80), "kind": "video" if MEDIA_TYPES[extension].begins_with("video") else "image",
			"type": MEDIA_TYPES[extension]})
	return result

## Самая свежая сессия (её показывает карточка). Пусто — сессий нет.
func latest(app: String = "claude") -> String:
	var best: String = ""
	for id in sessions:
		if str(sessions[id].get("app", "claude")) != app:
			continue
		if best.is_empty() or float(sessions[id]["at"]) > float(sessions[best]["at"]):
			best = id
	return best.trim_prefix("codex:") if app == "codex" else best

## Есть ли что показать на пульте.
func active(app: String = "claude") -> bool:
	return not latest(app).is_empty()

## Объявление для app_adapters.announce().
func announcement(app: String = "claude") -> Dictionary:
	var title: String = "Codex" if app == "codex" else "Claude"
	return {"id": app, "title": title, "commands": [{"name": "reply", "title": "Ответить", "row": "hidden", "args": {"text": "", "session": ""}},
		{"name": "permit", "title": "Разрешить/запретить", "row": "hidden", "args": {"id": "", "behavior": ""}},
		{"name": "answer", "title": "Ответить на вопрос", "row": "hidden", "args": {"id": "", "answers": {}}}], "state": card_state(app)}

## Полная карточка одной известной сессии — только по её точному id.
func session_state(app: String, raw_id: String) -> Dictionary:
	if not app in APPS or raw_id.is_empty() or raw_id.length() > 64:
		return {}
	var id: String = _key(app, raw_id)
	if not sessions.has(id) or str(sessions[id].get("app", "")) != app:
		return {}
	var session: Dictionary = sessions[id]
	var state: Dictionary = {"title": session["folder"] if not str(session["folder"]).is_empty() else ("Codex" if app == "codex" else "Claude"),
		"subtitle": STATUS_TEXT.get(session["status"], ""), "badge": STATUS_TEXT.get(session["status"], ""),
		"text": session["note"] if session["status"] in ["waiting", "failed"] else session["text"],
		"session": raw_id, "can_reply": can_reply(raw_id, app), "media": _public_media(session),
		"revision": _session_revision(session, id)}
	if not ask.is_empty() and ask["session"] == id:
		state["ask"] = {"id": ask["id"], "kind": ask["kind"], "tool": ask["tool"], "detail": ask["detail"], "questions": ask["questions"],
			"seconds": maxi(0, int(ASK_TIMEOUT - (_clock - float(ask["at"]))))}
		state["badge"] = "? ждёт ответа"
	return state

func _session_revision(session: Dictionary, id: String) -> String:
	var ask_id: String = str(ask.get("id", "")) if not ask.is_empty() and ask.get("session", "") == id else ""
	return str(hash([session.get("at", 0.0), session.get("status", ""), session.get("text", ""),
		session.get("note", ""), session.get("media", []), _waiters.has(id), ask_id]))

## Карточка «Claude»/«Codex»: свежая сессия крупно, остальные — с полными id.
func card_state(app: String = "claude") -> Dictionary:
	var raw_id: String = latest(app)
	if raw_id.is_empty():
		return {"hint": ("Codex" if app == "codex" else "Claude") + " пока молчит — напиши ему в сессии на ПК, и здесь появится его ответ"}
	var id: String = _key(app, raw_id)
	var state: Dictionary = session_state(app, raw_id)
	var summaries: Array = []
	for other in _by_time(app):
		var item: Dictionary = sessions[other]
		var other_id: String = str(item.get("id", other))
		summaries.append({"id": other_id, "title": str(item["folder"]) if not str(item["folder"]).is_empty() else ("Codex" if app == "codex" else "Claude"),
			"subtitle": STATUS_TEXT.get(item["status"], ""), "can_reply": can_reply(other_id, app),
			"revision": _session_revision(item, other),
			"ask_seconds": maxi(0, int(ASK_TIMEOUT - (_clock - float(ask["at"])))) if not ask.is_empty() and ask.get("session", "") == other else -1})
	state["sessions"] = summaries
	if _by_time(app).size() > 1:
		var items: Array = []
		for other in _by_time(app):
			items.append({"id": str(sessions[other].get("id", other)), "title": sessions[other]["folder"], "subtitle": STATUS_TEXT.get(sessions[other]["status"], ""), "current": other == id})
		state["lists"] = [{"id": "sessions", "title": "Сессии", "items": items}]
	return state

func _by_time(app: String = "") -> Array:
	var ids: Array = []
	for id in sessions:
		if app.is_empty() or str(sessions[id].get("app", "claude")) == app:
			ids.append(id)
	ids.sort_custom(func(a, b): return float(sessions[a]["at"]) > float(sessions[b]["at"]))
	return ids

static func _key(app: String, id: String) -> String:
	return "codex:" + id if app == "codex" else id

func _trim() -> void:
	for id in sessions.keys():
		if sessions[id]["status"] == "done" and _clock - float(sessions[id]["at"]) > FORGET_AFTER:
			sessions.erase(id)
	for app in APPS:
		var ids: Array = _by_time(app)
		while ids.size() > MAX_SESSIONS:
			sessions.erase(ids.pop_back())
