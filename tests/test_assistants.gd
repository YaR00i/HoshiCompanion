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
	_note(watch, "UserPromptSubmit", "s1")
	_note(watch, "StopFailure", "s1", {"kind": "rate_limit"})
	card = watch.card_state()
	_check(card["badge"] == "⚠ прервался" and card["text"].contains("лимит") and watch.sessions["s1"]["status"] != "working", "a turn cut by the usage limit no longer shows «working»")
	_note(watch, "Stop", "s1", {"text": "Готово: звук переключается."})
	_note(watch, "UserPromptSubmit", "s2", {"folder": "D:/projects/Other/Game"})
	card = watch.card_state()
	_check(card["title"] == "Game" and card["lists"][0]["items"].size() == 2, "the newest session is on top; others are listed")
	_check(not JSON.stringify(watch.sessions).contains("D:/projects"), "only the folder name is kept, never the path")
	_note(watch, "Stop", "s3", {"app": "other"})
	watch.handle_event({"app": "claude", "event": "Stop"})
	_check(watch.sessions.size() == 2, "unknown apps and notes without a session are ignored")
	_note(watch, "SessionEnd", "s2")
	_check(watch.latest() == "s1" and watch.sessions.size() == 1, "a closed session leaves the card")
	# Codex shares the receiver but keeps its sessions, card and history separate.
	_note(watch, "UserPromptSubmit", "0123abcd-4567-89ef-0123-456789abcdef", {"app": "codex", "folder": "D:/projects/CodexGame"})
	_note(watch, "Stop", "0123abcd-4567-89ef-0123-456789abcdef", {"app": "codex", "text": "Готово в Codex"})
	_check(watch.card_state("codex")["text"] == "Готово в Codex" and watch.card_state()["session"] == "s1" and watch.sessions.has("codex:0123abcd-4567-89ef-0123-456789abcdef"), "Codex answer stays on its own card")
	_check(watch.clouds().size() == 2 and watch.clouds()[0]["app"] == "claude" and watch.clouds()[1]["app"] == "codex", "each assistant has its own cloud")
	watch.handle_event({"app": "codex", "event": "SessionEnd", "session": "0123abcd-4567-89ef-0123-456789abcdef"})
	_check(not watch.active("codex") and watch.active("claude"), "closing Codex does not close Claude")
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
	# Живые облачка (28.09): «работает» — пока файл беседы меняется (смотрим только время).
	var live_clouds = AssistantWatch.new()
	var root_dir: String = ProjectSettings.globalize_path("user://test_transcripts")
	var sid: String = "0a1b2c3d-4e5f-6789-abcd-ef0123456789"
	DirAccess.make_dir_recursive_absolute(root_dir.path_join("D--projects-demo"))
	var file := FileAccess.open(root_dir.path_join("D--projects-demo").path_join(sid + ".jsonl"), FileAccess.WRITE)
	file.store_string("{}
")
	file.close()
	live_clouds.transcripts_root = root_dir
	_note(live_clouds, "UserPromptSubmit", sid)
	live_clouds.poll_live()
	_check(live_clouds.clouds()[0]["status"] == "working" and live_clouds.transcript_path(sid).ends_with(sid + ".jsonl"), "working cloud while the conversation is alive")
	live_clouds._clock += AssistantWatch.WORKING_QUIET_SECONDS + 1.0
	_check(live_clouds.clouds().is_empty(), "the conversation went quiet (Esc, closed) — the working cloud leaves by itself")
	live_clouds.sessions[sid]["file_time"] = 1.0 # файл изменился
	live_clouds.poll_live()
	_check(live_clouds.clouds()[0]["status"] == "working", "the conversation moves again — the cloud is back")
	_note(live_clouds, "Notification", sid, {"kind": "permission_prompt"})
	_check(live_clouds.clouds()[0]["status"] == "waiting", "permission request — a question cloud")
	live_clouds._clock += 5.0
	live_clouds.sessions[sid]["file_time"] = 1.0
	live_clouds.poll_live()
	_check(live_clouds.sessions[sid]["status"] == "working" and live_clouds.clouds()[0]["status"] == "working", "answered on the PC (the conversation moved on) — the question cloud leaves")
	_note(live_clouds, "Stop", sid, {"text": "ok"})
	live_clouds._clock += 500.0
	_note(live_clouds, "Notification", sid, {"kind": "idle_prompt"})
	live_clouds._clock += 200.0
	_check(live_clouds.clouds().is_empty(), "«waiting for input» after a minute does not keep the check mark alive")
	_note(live_clouds, "Notification", sid, {"kind": "permission_prompt"})
	live_clouds._clock += AssistantWatch.WAITING_CLOUD_SECONDS + 1.0
	_check(live_clouds.clouds().is_empty(), "an unanswered question cloud does not hang forever")
	DirAccess.remove_absolute(root_dir.path_join("D--projects-demo").path_join(sid + ".jsonl"))
	DirAccess.remove_absolute(root_dir.path_join("D--projects-demo"))
	DirAccess.remove_absolute(root_dir)

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
	# Codex: only a paired phone opens the one-minute reply window.
	var codex_id: String = "1234abcd-5678-90ef-1234-567890abcdef"
	var no_phone: StreamPeerTCP = await _open_waiter(live, codex_id, "Без телефона", "codex")
	_check((await _read_all(live, no_phone)).begins_with("HTTP/1.1 204") and not live.can_reply(codex_id, "codex"), "Codex does not wait when no phone is paired")
	live.phones = 1
	var codex_waiter: StreamPeerTCP = await _open_waiter(live, codex_id, "Ответ Codex", "codex")
	bus_live._sync_assistants()
	_check(live.card_state("codex")["text"] == "Ответ Codex" and live.card_state("codex")["can_reply"] and bus_live.adapters.resolve("app:codex:reply")["peer"] == AssistantWatch.CODEX_PEER, "Codex card and command appear for the paired phone")
	_check(bus_live.run("app:codex:reply", {"text": "С телефона", "session": codex_id}) == "" and live.sessions["codex:" + codex_id]["status"] == "working", "Codex reply is routed to its own session")
	var codex_response: String = await _read_all(live, codex_waiter)
	_check(codex_response.begins_with("HTTP/1.1 200") and str(JSON.parse_string(codex_response.get_slice("\r\n\r\n", 1)).get("text", "")) == "С телефона", "Codex hook receives the phone text")
	live.phones = 0
	# После перезапуска Хоши пуста; ждун стучится снова и приносит последний ответ.
	live.sessions.clear()
	waiter = await _open_waiter(live, "live", "Ответ до перезапуска")
	_check(live.card_state()["text"] == "Ответ до перезапуска" and live.card_state()["title"] == "Проект" and live.card_state()["can_reply"], "after a Hoshi restart the waiting hook brings the card back")
	live.handle_event({"app": "claude", "event": "UserPromptSubmit", "session": "live"})
	got = await _read_all(live, waiter)
	_check(got.begins_with("HTTP/1.1 204") and not live.can_reply("live"), "typing on the PC lets the waiting hook go without a reply")
	# Разрешения и вопросы: нет телефона — сразу «спроси на ПК»; есть — ждём ответа.
	live.phones = 0
	var perm: StreamPeerTCP = await _open_ask(live, {"app": "claude", "event": "Permission", "session": "live", "tool": "Bash", "detail": "git commit -m test"})
	got = await _read_all(live, perm)
	_check(got.begins_with("HTTP/1.1 204") and live.ask.is_empty(), "no phone connected — the question goes to the PC at once")
	live.phones = 1
	perm = await _open_ask(live, {"app": "claude", "event": "Permission", "session": "live", "tool": "Bash", "detail": "git commit -m test"})
	var shown_ask: Dictionary = live.card_state().get("ask", {})
	_check(shown_ask.get("kind", "") == "permission" and str(shown_ask.get("id", "")).length() == 5 and not str(shown_ask["id"]).contains("l") and shown_ask["detail"] == "git commit -m test" and live.clouds()[0]["status"] == "waiting", "with a phone the permission request waits on the card, with a 5-letter code")
	_check(live.notice.contains("телефоне"), "Hoshi tells the PC that Claude waits for the phone")
	_check(bus_live.run("app:claude:permit", {"id": "zzzzz", "behavior": "allow"}) == "no_question" and bus_live.run("app:claude:permit", {"id": shown_ask["id"], "behavior": "sudo"}) == "bad_answer", "a wrong code or answer is refused")
	_check(bus_live.run("app:claude:permit", {"id": shown_ask["id"], "behavior": "allow"}) == "" and live.ask.is_empty(), "the phone allows it")
	got = await _read_all(live, perm)
	_check(got.begins_with("HTTP/1.1 200") and got.contains("\"behavior\":\"allow\""), "the hook gets «allow»")
	var codex_permission: StreamPeerTCP = await _open_ask(live, {"app": "codex", "event": "Permission", "session": codex_id, "tool": "Bash", "detail": "test command"})
	bus_live._sync_assistants()
	var codex_ask: Dictionary = live.card_state("codex").get("ask", {})
	_check(not codex_ask.is_empty() and live.card_state().get("ask", {}).is_empty() and bus_live.run("app:claude:permit", {"id": codex_ask["id"], "behavior": "allow"}) == "no_question", "Codex permission stays on its own card and Claude cannot answer it")
	_check(bus_live.run("app:codex:permit", {"id": codex_ask["id"], "behavior": "allow"}) == "", "paired phone may answer Codex permission")
	got = await _read_all(live, codex_permission)
	_check(got.begins_with("HTTP/1.1 200") and got.contains("\"behavior\":\"allow\""), "Codex hook receives the permission decision")
	var question_note: Dictionary = {"app": "claude", "event": "Question", "session": "live", "questions": [
		{"question": "Какой цвет облачка?", "header": "Облачко", "multiSelect": false, "options": [{"label": "Оранжевый", "description": ""}, {"label": "Мятный", "description": ""}]},
		{"question": "Какие приложения?", "header": "", "multiSelect": true, "options": [{"label": "Claude"}, {"label": "Codex"}]}]}
	var held_q: StreamPeerTCP = await _open_ask(live, question_note)
	var q_id: String = live.card_state()["ask"]["id"]
	_check(live.card_state()["ask"]["questions"].size() == 2 and bus_live.run("app:claude:answer", {"id": q_id, "answers": {"Какой цвет облачка?": "Мятный"}}) == "not_all_answered", "every question needs an answer")
	_check(bus_live.run("app:claude:answer", {"id": q_id, "answers": {"Какой цвет облачка?": "Мятный", "Какие приложения?": "Claude, Codex", "Лишний": "x"}}) == "", "the phone answers the questions")
	got = await _read_all(live, held_q)
	var answer_json: Variant = JSON.parse_string(got.get_slice("\r\n\r\n", 1))
	_check(answer_json is Dictionary and answer_json["answers"] == {"Какой цвет облачка?": "Мятный", "Какие приложения?": "Claude, Codex"}, "the hook gets exactly the answers to its own questions")
	held_q = await _open_ask(live, question_note)
	live._clock += AssistantWatch.ASK_TIMEOUT + 1.0
	got = await _read_all(live, held_q)
	_check(got.begins_with("HTTP/1.1 204") and live.ask.is_empty(), "no answer in 30 s — the question goes to the PC")
	live.phones = 0

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
	# Автообновление Android-приложения: только два известных файла, больше ничего.
	served = await _http_get(media_bus, "/app/version.json")
	_check(served.begins_with("HTTP/1.1 200") or served.begins_with("HTTP/1.1 404"), "the app update file is served or plainly missing")
	served = await _http_get(media_bus, "/app/../project.godot")
	var other: String = await _http_get(media_bus, "/app/secret.txt")
	_check(served.begins_with("HTTP/1.1 404") and other.begins_with("HTTP/1.1 404"), "nothing else can be fetched through /app/")
	served = await _http_get(media_bus, "/pc_icon/../project.godot")
	other = await _http_get(media_bus, "/pc_icon/nope_nope.png")
	_check(served.begins_with("HTTP/1.1 404") and other.begins_with("HTTP/1.1 404"), "program icons: only real icons of saved actions")
	media_bus.stop()
	DirAccess.remove_absolute(picture)

	# История бесед: по просьбе телефона, только ему, только тексты сообщений.
	var history = AssistantWatch.new()
	history.history_dry_run = true
	_note(history, "UserPromptSubmit", "0123abcd-4567-89ef-0123-456789abcdef")
	history.request_history(7, "read", "")
	history.request_history(7, "sessions", "")
	history.request_history(7, "read", "../../secret")
	_check(history.history_asked == [[7, "read", "0123abcd-4567-89ef-0123-456789abcdef", str(AssistantWatch.HISTORY_MESSAGES)], [7, "sessions", "30"]], "the current conversation and the session list are read on request")
	var refused: Array = history.take_history()
	_check(refused.size() == 1 and refused[0]["peer"] == 7 and not refused[0]["message"]["ok"], "a made-up session id is refused")
	history.apply_history(9, "read", {"ok": true, "id": "0123abcd", "title": "Пульт", "messages": [
		{"role": "user", "text": "Привет", "time": "2026-09-27T12:00:00"}, {"role": "tool", "text": "cat secret"},
		{"role": "assistant", "text": "а".repeat(5000), "time": "2026-09-27T12:00:05"}]})
	var sent_history: Dictionary = history.take_history()[0]
	_check(sent_history["peer"] == 9 and sent_history["message"]["op"] == "history" and sent_history["message"]["messages"].size() == 2 and sent_history["message"]["messages"][1]["text"].length() == 3000, "only chat messages go to the phone that asked; long answers are cut")
	history.apply_history(9, "sessions", {"ok": true, "sessions": [{"id": "0123abcd-4567-89ef-0123-456789abcdef", "title": "Пульт", "folder": "HoshiCompanion", "updated": 5}]})
	_check(history.take_history()[0]["message"]["sessions"][0]["current"], "the session list marks the current one")
	history.handle_event({"app": "codex", "event": "Stop", "session": "1234abcd-5678-90ef-1234-567890abcdef", "folder": "Second", "text": "Codex ready"})
	history.request_history(11, "sessions", "", "codex")
	history.request_history(11, "read", "", "codex")
	_check(history.history_asked[-2] == [11, "codex", "sessions", "30"] and history.history_asked[-1] == [11, "codex", "read", "1234abcd-5678-90ef-1234-567890abcdef", str(AssistantWatch.HISTORY_MESSAGES)], "Codex history selects its own reader and session")
	history.apply_history(11, "read", {"ok": true, "id": "1234abcd-5678-90ef-1234-567890abcdef", "title": "Codex", "messages": [{"role": "assistant", "text": "ok"}]}, "codex")
	_check(history.take_history()[0]["message"]["app"] == "codex", "history response identifies the assistant for the requesting phone")

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
	_check(always.size() == 2 and always[0]["id"] == "claude" and always[1]["id"] == "codex" and str(always[0]["state"].get("hint", "")).contains("напиши"), "with the note box on, both assistant cards are always there")
	watch.listening = false
	# Облачко можно нажать: по точке окна — какое это облачко.
	var drawn = load("res://scripts/assistant_clouds.gd").new()
	drawn.items = [{"app": "claude", "status": "working"}, {"app": "codex", "status": "done"}]
	drawn.place(0.1, Vector2(200, 300), Vector2(400, 600))
	var first: Vector2 = drawn._anchor
	_check(drawn.cloud_at(first).get("app", "") == "claude" and drawn.cloud_at(first - Vector2(0, drawn.GAP)).get("app", "") == "codex" and drawn.cloud_at(Vector2(5, 590)).is_empty(), "a click finds the cloud under it (Claude, Codex) and nothing elsewhere")
	drawn.free()
	print("HOSHI_ASSISTANTS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

## Подключить «ждуна» (как claude_hook.py --wait) и дождаться, пока Хоши его примет.
func _open_waiter(watch, session: String, last_answer: String = "", app: String = "claude") -> StreamPeerTCP:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", watch.port)
	var body: PackedByteArray = JSON.stringify({"app": app, "event": "Wait", "session": session, "folder": "Проект", "text": last_answer}).to_utf8_buffer()
	var sent: bool = false
	for frame in range(120):
		peer.poll()
		watch.tick(0.016)
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and not sent:
			var data: PackedByteArray = ("POST /assistant HTTP/1.1\r\nContent-Length: %d\r\n\r\n" % body.size()).to_utf8_buffer()
			data.append_array(body)
			peer.put_data(data)
			sent = true
		if sent and watch.can_reply(session, app):
			break
		await process_frame
	return peer

## Прислать разрешение/вопрос (как claude_hook.py --ask) и дождаться, пока Хоши решит.
func _open_ask(watch, note: Dictionary) -> StreamPeerTCP:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", watch.port)
	var body: PackedByteArray = JSON.stringify(note).to_utf8_buffer()
	var sent: bool = false
	for frame in range(60):
		peer.poll()
		watch.tick(0.016)
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and not sent:
			var data: PackedByteArray = ("POST /assistant HTTP/1.1\r\nContent-Length: %d\r\n\r\n" % body.size()).to_utf8_buffer()
			data.append_array(body)
			peer.put_data(data)
			sent = true
		elif sent and frame > 10:
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
