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
const PORT: int = 18772
const PATH: String = "/assistant"
const MAX_BODY: int = 32768
const MAX_SESSIONS: int = 8
const MAX_TEXT: int = 6000
## Самый длинный ответ с телефона.
const MAX_REPLY: int = 2000
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

const STATUS_TEXT := {"working": "работает…", "done": "✓ закончил", "waiting": "? ждёт разрешения", "idle": "на связи"}

## session id -> {folder, status, text, note, at (с), seen}
var sessions: Dictionary = {}
## Для тестов: другой порт.
var port: int = PORT
var listening: bool = false

var _server := TCPServer.new()
var _clients: Array = []   # [{stream, buffer, age}]
var _waiters: Dictionary = {}  # session id -> StreamPeerTCP (ждун ответа с телефона)
## Сколько телефонов на связи (ставит шина пульта): 0 — вопросы сразу на ПК.
var phones: int = 0
## Сообщение для Хоши на ПК (забирает шина пульта).
var notice: String = ""
## Открытый вопрос/разрешение: {id, session, kind, tool, detail, questions, stream, at}
var ask: Dictionary = {}
var _clock: float = 0.0
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
	_server.stop()
	listening = false

func tick(delta: float) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	_clock += dt
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
		if waiter.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_waiters.erase(id)
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
	if str(message.get("app", "")) != "claude":
		return
	var id: String = str(message.get("session", "")).left(64)
	if id.is_empty():
		return
	var event: String = str(message.get("event", ""))
	if event in ["SessionEnd", "UserPromptSubmit"]:
		_release(id, "") # на ПК написали сами / сессия закрылась — ждун больше не нужен
	if event == "SessionEnd":
		sessions.erase(id)
		return
	var session: Dictionary = sessions.get(id, {"folder": "", "status": "idle", "text": "", "note": "", "at": _clock, "seen": true})
	var folder: String = str(message.get("folder", "")).get_file().left(80)
	if not folder.is_empty():
		session["folder"] = folder
	match event:
		"SessionStart":
			pass
		"UserPromptSubmit":
			session["status"] = "working"
			session["note"] = ""
		"Stop":
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
					if session["status"] != "waiting":
						session["status"] = "done"
		_:
			return
	session["at"] = _clock
	sessions[id] = session
	_trim()

## Разрешение или вопрос от хука: телефона нет — сразу «нет»; есть — держим.
func _add_ask(message: Dictionary, stream: StreamPeerTCP) -> void:
	if phones <= 0 or not ask.is_empty():
		_reply(stream, {})
		return
	var session: String = str(message.get("session", "")).left(64)
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
	ask = {"id": code, "session": session, "kind": kind, "tool": str(message.get("tool", "")).left(60),
		"detail": str(message.get("detail", "")).left(600), "questions": questions, "stream": stream, "at": _clock}
	if not sessions.has(session):
		handle_event({"app": "claude", "event": "SessionStart", "session": session, "folder": message.get("folder", "")})
	sessions[session]["status"] = "waiting"
	sessions[session]["at"] = _clock
	notice = "Claude ждёт ответа на телефоне (%d с)" % int(ASK_TIMEOUT)

## Ответ телефона на разрешение: behavior — "allow" / "deny".
func answer_permission(ask_id: String, behavior: String) -> String:
	if ask.is_empty() or ask["id"] != ask_id or ask["kind"] != "permission":
		return "no_question"
	if not behavior in ["allow", "deny"]:
		return "bad_answer"
	_finish_ask({"behavior": behavior})
	return ""

## Ответ телефона на вопрос: {текст вопроса: выбранный вариант или свой текст}.
func answer_question(ask_id: String, answers: Variant) -> String:
	if ask.is_empty() or ask["id"] != ask_id or ask["kind"] != "question":
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
func can_reply(id: String) -> bool:
	return _waiters.has(id)

## Ответ с телефона. session — какая сессия была на карточке. Пусто — отправлено.
func reply(text: String, session: String) -> String:
	var clean: String = text.strip_edges().left(MAX_REPLY)
	if clean.is_empty():
		return "empty"
	if not sessions.has(session):
		return "unknown_session"
	if not can_reply(session):
		return "not_waiting"
	_release(session, clean)
	sessions[session]["status"] = "working"
	sessions[session]["note"] = ""
	sessions[session]["at"] = _clock
	return ""

func _add_waiter(message: Dictionary, stream: StreamPeerTCP) -> void:
	var id: String = str(message.get("session", "")).left(64)
	if id.is_empty() or (not _waiters.has(id) and _waiters.size() >= MAX_SESSIONS):
		stream.disconnect_from_host()
		return
	_release(id, "") # у сессии один ждун — старого отпускаем
	_waiters[id] = stream
	# Ждун приносит последний ответ: после перезапуска Хоши карточка возвращается сама.
	if not sessions.has(id) or str(sessions[id]["text"]).is_empty():
		handle_event({"app": "claude", "event": "Stop", "session": id, "folder": message.get("folder", ""), "text": message.get("text", ""), "media": message.get("media", [])})

## Отпустить ждуна: text — ответ с телефона, пусто — без ответа.
func _release(id: String, text: String) -> void:
	if not _waiters.has(id):
		return
	var stream: StreamPeerTCP = _waiters[id]
	_waiters.erase(id)
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
	var status: String = ""
	for id in sessions:
		var session: Dictionary = sessions[id]
		match str(session["status"]):
			"waiting":
				status = "waiting"
			"working":
				if status != "waiting":
					status = "working"
			"done":
				if status.is_empty() and not bool(session["seen"]) and _clock - float(session["at"]) < DONE_CLOUD_SECONDS:
					status = "done"
	return [] if status.is_empty() else [{"app": "claude", "status": status}]

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
func latest() -> String:
	var best: String = ""
	for id in sessions:
		if best.is_empty() or float(sessions[id]["at"]) > float(sessions[best]["at"]):
			best = id
	return best

## Есть ли что показать на пульте.
func active() -> bool:
	return not sessions.is_empty()

## Объявление для app_adapters.announce().
func announcement() -> Dictionary:
	return {"id": ID, "title": "Claude", "commands": [{"name": "reply", "title": "Ответить", "row": "hidden", "args": {"text": "", "session": ""}},
		{"name": "permit", "title": "Разрешить/запретить", "row": "hidden", "args": {"id": "", "behavior": ""}},
		{"name": "answer", "title": "Ответить на вопрос", "row": "hidden", "args": {"id": "", "answers": {}}}], "state": card_state()}

## Карточка «Claude»: свежая сессия крупно, остальные — списком.
func card_state() -> Dictionary:
	var id: String = latest()
	if id.is_empty():
		return {"hint": "Claude пока молчит — напиши ему в сессии на ПК, и здесь появится его ответ"}
	var session: Dictionary = sessions[id]
	var state: Dictionary = {"title": session["folder"] if not str(session["folder"]).is_empty() else "Claude",
		"subtitle": STATUS_TEXT.get(session["status"], ""), "badge": STATUS_TEXT.get(session["status"], ""),
		"text": session["note"] if session["status"] == "waiting" else session["text"],
		"session": id, "can_reply": can_reply(id), "media": _public_media(session)}
	if not ask.is_empty():
		# Открытый вопрос/разрешение — наверху карточки (без самого соединения).
		state["ask"] = {"id": ask["id"], "kind": ask["kind"], "tool": ask["tool"], "detail": ask["detail"], "questions": ask["questions"],
			"seconds": maxi(0, int(ASK_TIMEOUT - (_clock - float(ask["at"]))))}
		state["badge"] = "? ждёт ответа"
	if sessions.size() > 1:
		var items: Array = []
		for other in _by_time():
			items.append({"id": other.left(12), "title": sessions[other]["folder"], "subtitle": STATUS_TEXT.get(sessions[other]["status"], ""), "current": other == id})
		state["lists"] = [{"id": "sessions", "title": "Сессии", "items": items}]
	return state

func _by_time() -> Array:
	var ids: Array = sessions.keys()
	ids.sort_custom(func(a, b): return float(sessions[a]["at"]) > float(sessions[b]["at"]))
	return ids

func _trim() -> void:
	for id in sessions.keys():
		if sessions[id]["status"] == "done" and _clock - float(sessions[id]["at"]) > FORGET_AFTER:
			sessions.erase(id)
	var ids: Array = _by_time()
	while ids.size() > MAX_SESSIONS:
		sessions.erase(ids.pop_back())
