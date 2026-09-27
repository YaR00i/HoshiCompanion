extends SceneTree
## ИИ-помощники (Claude Code): записки хука -> статус сессий -> карточка «Claude»
## на пульте. Приём проверяется на тестовом порту, только 127.0.0.1.

const AssistantWatch = preload("res://scripts/assistant_watch.gd")
const RemoteBus = preload("res://scripts/remote_bus.gd")

class StubApp extends RefCounted:
	func run_command(_command: Variant) -> void:
		pass
	func remote_snapshot() -> Dictionary:
		return {}
	func remote_say(_text: String) -> void:
		pass
	func _save_settings() -> void:
		pass

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _note(watch, event: String, session: String, extra: Dictionary = {}) -> void:
	var message: Dictionary = {"app": "claude", "event": event, "session": session, "folder": "HoshiCompanion"}
	message.merge(extra, true)
	watch.handle_event(message)
	watch.tick(0.05)

func _run() -> void:
	var watch = AssistantWatch.new()
	_check(not watch.active() and watch.card_state().has("hint"), "no sessions — no card")
	_note(watch, "SessionStart", "s1")
	_note(watch, "UserPromptSubmit", "s1")
	_check(watch.sessions["s1"]["status"] == "working" and watch.card_state()["badge"] == "работает…", "a prompt makes Claude «working»")
	_note(watch, "Notification", "s1", {"kind": "permission_prompt", "text": "Claude needs your permission to use Bash"})
	var card: Dictionary = watch.card_state()
	_check(card["subtitle"] == "? ждёт разрешения" and card["text"].contains("permission"), "waiting for permission is shown with its note")
	_note(watch, "Notification", "s1", {"kind": "idle_prompt"})
	_check(watch.sessions["s1"]["status"] == "waiting", "idle reminder does not hide a permission wait")
	_note(watch, "Stop", "s1", {"text": "Готово: звук переключается."})
	card = watch.card_state()
	_check(card["title"] == "HoshiCompanion" and card["badge"] == "✓ закончил" and card["text"] == "Готово: звук переключается.", "finished answer is on the card")
	_note(watch, "UserPromptSubmit", "s2", {"folder": "D:/projects/Other/Game"})
	card = watch.card_state()
	_check(card["title"] == "Game" and card["lists"][0]["items"].size() == 2, "the newest session is on top; others are listed")
	_check(not JSON.stringify(watch.sessions).contains("D:/projects"), "only the folder name is kept, never the path")
	_note(watch, "Stop", "s3", {"app": "codex"})
	watch.handle_event({"app": "claude", "event": "Stop"})
	_check(watch.sessions.size() == 2, "unknown apps and notes without a session are ignored")
	_note(watch, "SessionEnd", "s2")
	_check(watch.latest() == "s1" and watch.sessions.size() == 1, "a closed session leaves the card")
	# Облачко над Хоши: одно на помощника; «ждёт» важнее «работает»; ✓ тает.
	var clouds = AssistantWatch.new()
	_check(clouds.clouds().is_empty(), "no sessions — no cloud")
	_note(clouds, "UserPromptSubmit", "a")
	_note(clouds, "Stop", "b", {"text": "готово"})
	_check(clouds.clouds() == [{"app": "claude", "status": "working"}], "one cloud per assistant: working wins over done")
	_note(clouds, "Notification", "b", {"kind": "permission_prompt"})
	_check(clouds.clouds()[0]["status"] == "waiting", "waiting for permission wins over working")
	_note(clouds, "Stop", "a", {"text": "ok"})
	_note(clouds, "Stop", "b", {"text": "ok"})
	_check(clouds.clouds()[0]["status"] == "done", "finished — a cloud with a check mark")
	clouds.mark_seen()
	_check(clouds.clouds().is_empty(), "petting Hoshi melts the check-mark cloud")
	_note(clouds, "Stop", "a", {"text": "ещё"})
	clouds.tick(AssistantWatch.DONE_CLOUD_SECONDS) # tick clamps delta: move the clock directly
	clouds._clock += AssistantWatch.DONE_CLOUD_SECONDS
	_check(clouds.clouds().is_empty() and clouds.sessions.has("a"), "the check mark melts by itself after 10 minutes; the card stays")

	for index in range(12):
		_note(watch, "UserPromptSubmit", "many%d" % index)
	_check(watch.sessions.size() == AssistantWatch.MAX_SESSIONS, "at most %d sessions are kept" % AssistantWatch.MAX_SESSIONS)

	# Настоящий приём записки по 127.0.0.1 (тестовый порт).
	var live = AssistantWatch.new()
	live.port = 18872
	_check(live.start(), "the note box listens on 127.0.0.1")
	var body: PackedByteArray = JSON.stringify({"app": "claude", "event": "Stop", "session": "live", "folder": "Проект", "text": "Привет с ПК"}).to_utf8_buffer()
	var answer: String = await _post(live, "POST /assistant HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % body.size(), body)
	_check(answer.begins_with("HTTP/1.1 204") and live.sessions.has("live") and live.sessions["live"]["text"] == "Привет с ПК" and live.sessions["live"]["folder"] == "Проект", "a note posted by the hook arrives (UTF-8 intact)")
	answer = await _post(live, "GET /assistant HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n", PackedByteArray())
	_check(not answer.begins_with("HTTP/1.1 204") and live.sessions.size() == 1, "anything but POST /assistant is dropped")

	# Ответ с телефона: ждун держит соединение, текст уходит ему; с ПК — отпускается.
	var bus_live = RemoteBus.new()
	bus_live.setup(StubApp.new())
	bus_live.assistants = live
	_check(live.reply("привет", "live") == "not_waiting", "no waiter — nothing to reply to")
	var waiter: StreamPeerTCP = await _open_waiter(live, "live")
	_check(live.can_reply("live") and live.card_state()["can_reply"] and live.card_state()["session"] == "live", "a waiting hook shows the reply box")
	bus_live._sync_assistants()
	_check(bus_live.run("app:claude:reply", {"text": "  ", "session": "live"}) == "empty" and bus_live.run("app:claude:reply", {"text": "x", "session": "nope"}) == "unknown_session", "empty replies and unknown sessions are refused")
	var long_text: String = "Сделай, пожалуйста, ещё облачко над Хоши. " + "а".repeat(2500)
	_check(bus_live.run("app:claude:reply", {"text": long_text, "session": "live"}) == "" and live.sessions["live"]["status"] == "working" and not live.can_reply("live"), "phone reply goes to the waiting hook; Claude is working again")
	var got: String = await _read_all(live, waiter)
	var reply_json: Variant = JSON.parse_string(got.get_slice("\r\n\r\n", 1))
	_check(got.begins_with("HTTP/1.1 200") and reply_json is Dictionary and str(reply_json["text"]).begins_with("Сделай, пожалуйста") and str(reply_json["text"]).length() == AssistantWatch.MAX_REPLY, "the hook receives the text (UTF-8, at most %d characters)" % AssistantWatch.MAX_REPLY)
	# После перезапуска Хоши пуста; ждун стучится снова и приносит последний ответ.
	live.sessions.clear()
	waiter = await _open_waiter(live, "live", "Ответ до перезапуска")
	_check(live.card_state()["text"] == "Ответ до перезапуска" and live.card_state()["title"] == "Проект" and live.card_state()["can_reply"], "after a Hoshi restart the waiting hook brings the card back")
	live.handle_event({"app": "claude", "event": "UserPromptSubmit", "session": "live"})
	got = await _read_all(live, waiter)
	_check(got.begins_with("HTTP/1.1 204") and not live.can_reply("live"), "typing on the PC lets the waiting hook go without a reply")
	waiter = await _open_waiter(live, "live")
	live.stop()
	got = await _read_all(live, waiter)
	_check(got.is_empty(), "closing Hoshi just drops the waiting hook (no «let go»), so it knocks again after a restart")

	# Картинки из ответа: только медиа-файлы с локальным путём, случайный адрес, путь не на телефон.
	var picture: String = ProjectSettings.globalize_path("user://test_media_probe.png")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.ORANGE)
	image.save_png(picture)
	var media_watch = AssistantWatch.new()
	_note(media_watch, "Stop", "m", {"text": "Вот картинка", "media": [{"path": picture}, {"path": "\\\\server\\share\\x.png"},
		{"path": "C:/Windows/notepad.exe"}, {"path": "relative/x.gif"}, {"path": "//host/y.png"}]})
	var shown: Array = media_watch.card_state()["media"]
	_check(shown.size() == 1 and shown[0]["name"] == "test_media_probe.png" and shown[0]["kind"] == "image" and str(shown[0]["id"]).length() == 32, "only local media files are kept, each with a random address")
	_check(not JSON.stringify(media_watch.card_state()).contains(picture.get_base_dir()), "the phone never sees the path of the file")
	var first_id: String = shown[0]["id"]
	_check(media_watch.media_file(first_id)["path"] == picture and media_watch.media_file("nope").is_empty(), "the address leads to the file; unknown addresses lead nowhere")
	_note(media_watch, "Stop", "m", {"text": "Новый ответ", "media": [{"path": picture}]})
	_check(media_watch.media_file(first_id).is_empty() and not media_watch.card_state()["media"].is_empty(), "a new answer gives new addresses; old ones stop working")
	var media_bus = RemoteBus.new()
	media_bus.setup(StubApp.new())
	media_bus.loopback_only = true
	media_bus.http_port = 18880
	media_bus.ws_port = 18881
	media_bus.assistants = media_watch
	media_bus.mpc.dry_run = true
	media_bus.sound.dry_run = true
	_check(media_bus.start(), "remote starts on test ports")
	var served: String = await _http_get(media_bus, "/media/" + str(media_watch.card_state()["media"][0]["id"]))
	_check(served.begins_with("HTTP/1.1 200") and served.contains("Content-Type: image/png") and served.contains("PNG"), "the phone page gets the picture by its address")
	served = await _http_get(media_bus, "/media/" + first_id)
	_check(served.begins_with("HTTP/1.1 404"), "an old or made-up address gets nothing")
	media_bus.stop()
	DirAccess.remove_absolute(picture)

	# Через шину: карточка «Claude» у телефона, исчезает без сессий.
	var bus = RemoteBus.new()
	bus.setup(StubApp.new())
	bus.assistants = watch
	bus._sync_assistants()
	var apps: Array = bus._state_message()["apps"]
	var claude: Dictionary = {}
	for app in apps:
		if app["id"] == "claude":
			claude = app
	_check(claude.get("title", "") == "Claude" and claude["state"].has("badge"), "phone sees the Claude card")
	watch.sessions.clear()
	bus._sync_assistants()
	_check(bus._state_message()["apps"].is_empty(), "no sessions and no note box — no card")
	watch.listening = true
	bus._sync_assistants()
	var always: Array = bus._state_message()["apps"]
	_check(always.size() == 1 and always[0]["id"] == "claude" and str(always[0]["state"].get("hint", "")).contains("напиши"), "with the note box on, the Claude card is always there, with a hint")
	watch.listening = false
	print("HOSHI_ASSISTANTS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

## Подключить «ждуна» (как claude_hook.py --wait) и дождаться, пока Хоши его примет.
func _open_waiter(watch, session: String, last_answer: String = "") -> StreamPeerTCP:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", watch.port)
	var body: PackedByteArray = JSON.stringify({"app": "claude", "event": "Wait", "session": session, "folder": "Проект", "text": last_answer}).to_utf8_buffer()
	var sent: bool = false
	for frame in range(120):
		peer.poll()
		watch.tick(0.016)
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and not sent:
			var data: PackedByteArray = ("POST /assistant HTTP/1.1\r\nContent-Length: %d\r\n\r\n" % body.size()).to_utf8_buffer()
			data.append_array(body)
			peer.put_data(data)
			sent = true
		if sent and watch.can_reply(session):
			break
		await process_frame
	return peer

func _read_all(watch, peer: StreamPeerTCP) -> String:
	var reply := PackedByteArray()
	for frame in range(120):
		peer.poll()
		watch.tick(0.016)
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() > 0:
			reply.append_array(peer.get_partial_data(peer.get_available_bytes())[1])
		elif peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		await process_frame
	return reply.get_string_from_utf8()

func _http_get(bus, path: String) -> String:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", bus.http_port)
	var sent: bool = false
	var reply := PackedByteArray()
	for frame in range(180):
		peer.poll()
		bus.tick(0.016)
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and not sent:
			peer.put_data(("GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" % path).to_utf8_buffer())
			sent = true
		if sent and peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		if sent and peer.get_available_bytes() > 0:
			reply.append_array(peer.get_partial_data(peer.get_available_bytes())[1])
		await process_frame
	return reply.get_string_from_ascii()

func _post(watch, head: String, body: PackedByteArray) -> String:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", watch.port)
	var sent: bool = false
	var reply := PackedByteArray()
	for frame in range(120):
		peer.poll()
		watch.tick(0.016)
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and not sent:
			var data: PackedByteArray = head.to_utf8_buffer()
			data.append_array(body)
			peer.put_data(data)
			sent = true
		if sent and peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		if sent and peer.get_available_bytes() > 0:
			reply.append_array(peer.get_partial_data(peer.get_available_bytes())[1])
		await process_frame
	return reply.get_string_from_utf8()
