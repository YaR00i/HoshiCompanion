extends SceneTree
## Пульт с телефона и аддоны: страница, привязка по коду, запреты, маршрут
## команды до аддона. Без VRM; сеть — только 127.0.0.1 на тестовых портах.

const RemoteBus = preload("res://scripts/remote_bus.gd")
const Commands = preload("res://scripts/hoshi_commands.gd")
const QR = preload("res://scripts/qr_code.gd")
const HoshiRestart = preload("res://scripts/hoshi_restart.gd")

class StubApp extends RefCounted:
	var ran: Array[String] = []
	var events: Array[String] = []
	var saves: int = 0
	func run_command(command: Variant) -> void:
		ran.append(str(command))
	func remote_snapshot() -> Dictionary:
		return {"name": "Хоши", "status": "Сидит в уголке", "selected": ["activity_normal"]}
	func on_app_event(app_id: String, event: String) -> void:
		events.append(app_id + ":" + event)
	func _save_settings() -> void:
		saves += 1

var checks: int = 0
var failures: int = 0
var bus
var app := StubApp.new()

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _pump(clients: Array, frames: int = 20) -> void:
	for index in range(frames):
		bus.tick(0.016)
		for client in clients:
			client.poll()
		OS.delay_msec(3)

func _inbox(client: WebSocketPeer) -> Array:
	var messages: Array = []
	while client.get_available_packet_count() > 0:
		var parsed: Variant = JSON.parse_string(client.get_packet().get_string_from_utf8())
		if parsed is Dictionary:
			messages.append(parsed)
	return messages

func _find(messages: Array, op: String) -> Dictionary:
	for message in messages:
		if message.get("op", "") == op:
			return message
	return {}

func _open(path: String) -> WebSocketPeer:
	var client := WebSocketPeer.new()
	client.connect_to_url("ws://127.0.0.1:%d%s" % [bus.ws_port, path])
	_pump([client], 30)
	return client

func _http(path: String) -> String:
	var stream := StreamPeerTCP.new()
	stream.connect_to_host("127.0.0.1", bus.http_port)
	var text: String = ""
	var sent: bool = false
	for index in range(200):
		bus.tick(0.016)
		stream.poll()
		if stream.get_status() == StreamPeerTCP.STATUS_CONNECTED and not sent:
			stream.put_data(("GET %s HTTP/1.1\r\nHost: test\r\n\r\n" % path).to_utf8_buffer())
			sent = true
		if stream.get_status() == StreamPeerTCP.STATUS_CONNECTED and stream.get_available_bytes() > 0:
			text += (stream.get_partial_data(stream.get_available_bytes())[1] as PackedByteArray).get_string_from_utf8()
		if sent and stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		OS.delay_msec(3)
	return text

func _run() -> void:
	# Только домашняя сеть.
	for address in ["127.0.0.1", "192.168.1.5", "10.0.0.2", "172.20.1.1", "::ffff:192.168.0.3", "fe80::1"]:
		_check(RemoteBus.is_home_address(address), "home network address accepted: " + address)
	for address in ["8.8.8.8", "172.40.1.1", "2001:db8::1", "100.64.0.1"]:
		_check(not RemoteBus.is_home_address(address), "internet address refused: " + address)
	var remote_ok: bool = true
	for command in Commands.names():
		if Commands.allows(command, "remote") and not Commands.allows(command, "user"):
			remote_ok = false
	_check(remote_ok and Commands.allows("wave", "remote") and not Commands.allows("quit", "remote") and not Commands.allows("pick_window", "remote"), "phone commands are a safe subset of menu commands")

	bus = RemoteBus.new()
	bus.setup(app)
	bus.loopback_only = true
	# Never touch a real MPC-BE or sound devices of this PC from a test.
	bus.mpc.dry_run = true
	bus.sound.dry_run = true
	bus.http_port = 18870
	bus.ws_port = 18871
	_check(bus.start() and bus.pairing_code.length() == 6, "remote starts with a 6-digit code")

	var version_before: int = bus.code_version
	var link: String = bus.pairing_url("http://192.168.1.23:18770/")
	_check(link == "http://192.168.1.23:18770/#pair=" + bus.pairing_code, "QR link carries the address and the one-time code")
	var with_alts: String = bus.pairing_url("http://192.168.1.23:18770/", PackedStringArray(["10.8.1.2", "26.1.2.3"]))
	_check(with_alts == "http://192.168.1.23:18770/#pair=" + bus.pairing_code + "&alt=10.8.1.2,26.1.2.3" and not QR.encode(with_alts).is_empty(), "QR link can carry spare addresses for the app (home and VPN)")
	var all_networks: String = bus.pairing_url("http://192.168.1.23:18770/", PackedStringArray(["10.8.1.2", "172.22.1.5", "192.168.0.94", "10.9.2.3", "172.30.4.5"]))
	_check(not QR.encode(all_networks).is_empty(), "one QR can hold the complete six-address phone list")
	# Один QR использует обычную сеть как основной адрес; VPN доступен через alt.
	_check(RemoteBus.is_virtual_network("AmneziaVPN") and RemoteBus.is_virtual_network("Radmin VPN") and RemoteBus.is_virtual_network("vEthernet (WSL)") and not RemoteBus.is_virtual_network("Ethernet") and not RemoteBus.is_virtual_network("Беспроводная сеть"), "VPN and virtual networks are recognised by name")
	var choices: Array = [{"url": "http://192.168.0.94:18870/", "ip": "192.168.0.94", "network": "Ethernet", "virtual": false},
		{"url": "http://10.8.1.2:18870/", "ip": "10.8.1.2", "network": "AmneziaVPN", "virtual": true}]
	_check(bus.qr_choice(choices)["ip"] == "192.168.0.94", "QR uses the first ordinary network by default")
	_check(bus.qr_choice([]).is_empty(), "no network means no QR address")
	var real_ok: bool = true
	for choice in bus.address_choices():
		real_ok = real_ok and RemoteBus.is_home_address(choice["ip"]) and not choice["ip"].begins_with("169.254.") and choice["url"] == "http://%s:18870/" % choice["ip"] and not str(choice["network"]).is_empty()
	for item in bus.skipped_networks():
		real_ok = real_ok and not RemoteBus.is_home_address(item["ip"])
	_check(real_ok, "this PC's addresses are home-network only, each with its network name")
	var modules: Array = QR.encode(link)
	_check(modules.size() == 29 and modules[0][0] and modules[0][6] and not modules[1][1] and modules[3][3] and modules[28][0], "QR code is built with finder squares (version 3)")
	_check(QR.to_image(link, 6, 4).get_width() == (29 + 8) * 6 and QR.encode("x".repeat(400)).is_empty(), "QR image size; too long text is refused")
	var page: String = _http("/")
	_check(page.begins_with("HTTP/1.1 200") and page.contains("<title>Хоши</title>"), "phone gets the remote page")
	_check(_http("/../project.godot").begins_with("HTTP/1.1 404"), "other files are not served")

	var phone: WebSocketPeer = _open("/hoshi-remote-v1")
	_check(phone.get_ready_state() == WebSocketPeer.STATE_OPEN, "phone connects")
	phone.send_text(JSON.stringify({"op": "run", "command": "wave"}))
	_pump([phone])
	_check(app.ran.is_empty() and _find(_inbox(phone), "error").get("reason", "") == "need_pairing", "unpaired phone cannot run anything")
	phone.send_text(JSON.stringify({"op": "pair", "code": "000000" if bus.pairing_code != "000000" else "111111"}))
	_pump([phone])
	_check(_find(_inbox(phone), "error").get("reason", "") == "bad_code", "wrong code is refused")
	var code: String = bus.pairing_code
	phone.send_text(JSON.stringify({"op": "pair", "code": code}))
	_pump([phone])
	var messages: Array = _inbox(phone)
	var token: String = str(_find(messages, "paired").get("token", ""))
	var welcome: Dictionary = _find(messages, "welcome")
	_check(token.length() >= 32 and bus.tokens.has(token) and app.saves >= 1, "right code pairs the phone and remembers it")
	_check(bus.pairing_code != code, "a code works only once")
	_check(bus.code_version > version_before, "a new code refreshes the QR window")
	var catalog_text: String = JSON.stringify(welcome.get("catalog", []))
	_check(catalog_text.contains("\"wave\"") and not catalog_text.contains("\"quit\"") and not catalog_text.contains("\"look\""), "phone sees only phone commands")
	_check(_find(messages, "state").get("hoshi", {}).get("status", "") == "Сидит в уголке", "phone sees what Hoshi is doing")

	phone.send_text(JSON.stringify({"op": "run", "command": "wave"}))
	phone.send_text(JSON.stringify({"op": "run", "command": "quit"}))
	phone.send_text(JSON.stringify({"op": "run", "command": "edge_sway"}))
	_pump([phone])
	messages = _inbox(phone)
	_check(app.ran.size() == 1 and app.ran[0] == "wave", "phone runs allowed commands through Hoshi's normal command path")
	var refused: int = 0
	for message in messages:
		if message.get("op", "") == "ran" and message.get("reason", "") == "not_allowed":
			refused += 1
	_check(refused == 2, "closing Hoshi or autonomy-only scenes is refused from the phone")

	# Второе подключение того же телефона — по ключу, без кода.
	phone.close()
	_pump([phone])
	var again: WebSocketPeer = _open("/hoshi-remote-v1")
	again.send_text(JSON.stringify({"op": "hello", "token": token}))
	_pump([again])
	_check(not _find(_inbox(again), "welcome").is_empty(), "a paired phone reconnects without a code")

	# Блокировка телефона: связь умирает молча, телефон возвращается с тем же ключом.
	again.send_text(JSON.stringify({"op": "ping"}))
	_pump([again])
	_check(not _find(_inbox(again), "pong").is_empty(), "the remote page heartbeat gets an answer")
	var woke: WebSocketPeer = _open("/hoshi-remote-v1")
	woke.send_text(JSON.stringify({"op": "hello", "token": token}))
	_pump([again, woke], 30)
	_check(not _find(_inbox(woke), "welcome").is_empty() and again.get_ready_state() != WebSocketPeer.STATE_OPEN and bus.phone_count() == 1, "the same phone coming back replaces its old connection at once")
	var strangers: Array = []
	for index in range(bus.MAX_PHONES):
		strangers.append(_open("/hoshi-remote-v1"))
	_pump([woke] + strangers, 20)
	var phone_peers: int = 0
	for key in bus._peers:
		if bus._peers[key]["role"] == "phone":
			phone_peers += 1
	_check(phone_peers == bus.MAX_PHONES and strangers[strangers.size() - 1].get_ready_state() == WebSocketPeer.STATE_OPEN, "a new phone is let in when places are taken, the quietest one makes room")
	for stranger in strangers:
		stranger.close()
	_pump([woke] + strangers, 20)
	for key in bus._peers:
		if bus._peers[key]["role"] == "phone":
			bus._peers[key]["seen"] = bus.PHONE_SILENCE + 1.0
	_pump([woke], 10)
	_check(bus.phone_count() == 0 and woke.get_ready_state() != WebSocketPeer.STATE_OPEN, "a phone that went silent (locked) is dropped to free its place")
	again = _open("/hoshi-remote-v1")
	again.send_text(JSON.stringify({"op": "hello", "token": token}))
	_pump([again])
	_check(not _find(_inbox(again), "welcome").is_empty(), "after that the phone reconnects straight away")

	# Аддон YouTube (заглушка вместо расширения Chrome).
	var addon: WebSocketPeer = _open("/hoshi-adapter-v1")
	addon.send_text(JSON.stringify({"op": "adapter", "id": "youtube", "title": "YouTube",
		"commands": [{"name": "pause", "title": "Пауза", "icon": "⏸"}, {"name": "seek", "title": "+10 с", "args": {"seconds": 10}}],
		"state": {"title": "Lo-fi для рисования", "subtitle": "Hoshi Radio", "time": 42, "duration": 3600, "playing": true}}))
	_pump([again, addon])
	var state: Dictionary = _find(_inbox(again), "state")
	var apps_text: String = JSON.stringify(state.get("apps", []))
	_check(apps_text.contains("app:youtube:pause") and apps_text.contains("Lo-fi для рисования"), "an app add-on appears on the phone with its buttons and what is playing")
	_check(_find(_inbox(addon), "welcome").get("id", "") == "youtube", "the add-on is welcomed")
	again.send_text(JSON.stringify({"op": "run", "command": "app:youtube:seek", "args": {"seconds": 10, "evil": {"nested": true}}}))
	_pump([again, addon])
	var routed: Dictionary = _find(_inbox(addon), "run")
	_check(routed.get("command", "") == "seek" and int(routed.get("args", {}).get("seconds", 0)) == 10 and not routed.get("args", {}).has("evil"), "phone button reaches the add-on with clean arguments")
	addon.send_text(JSON.stringify({"op": "event", "id": "youtube", "event": "liked"}))
	_pump([again, addon])
	_check(app.events.size() == 1 and app.events[0] == "youtube:liked", "add-on events reach Hoshi")
	_inbox(again) # ответы на предыдущие нажатия
	var browser: WebSocketPeer = _open("/hoshi-adapter-v1")
	browser.send_text(JSON.stringify({"op": "adapter", "id": "tabs", "title": "Вкладки Chrome",
		"commands": [{"name": "list", "title": "Показать вкладки"}, {"name": "play_item", "title": "Переключить вкладку"}],
		"state": {"lists": [{"id": "tabs", "title": "Вкладки", "items": [
			{"id": "17", "title": "Первый ролик", "subtitle": "youtube.com"},
			{"id": "28", "title": "Другое видео", "subtitle": "example.org"}]}]}}))
	_pump([again, addon, browser])
	apps_text = JSON.stringify(_find(_inbox(again), "state").get("apps", []))
	_check(apps_text.contains("app:youtube:pause") and apps_text.contains("app:tabs:play_item") and apps_text.contains("Другое видео"), "YouTube and open browser tabs reach the phone together")
	_check(_find(_inbox(browser), "welcome").get("id", "") == "tabs", "the browser add-on is welcomed")
	# The Android foreground service needs alerts and media controls, not the full
	# recommendation lists or a new packet for every playback second.
	bus.tokens.append("background-test-token")
	var background: WebSocketPeer = _open("/hoshi-remote-v1")
	background.send_text(JSON.stringify({"op": "hello", "token": "background-test-token", "background": true}))
	_pump([again, background, addon, browser])
	var background_messages: Array = _inbox(background)
	var background_state: Dictionary = _find(background_messages, "state")
	var background_text: String = JSON.stringify(background_state)
	_check(not background_state.is_empty() and not background_text.contains("Другое видео") and not background_text.contains("pc_pending") and background_text.contains("Lo-fi для рисования"), "background phone receives compact media state without browser lists")
	_inbox(background)
	addon.send_text(JSON.stringify({"op": "adapter_state", "state": {"title": "Lo-fi для рисования", "subtitle": "Hoshi Radio", "time": 43, "duration": 3600, "playing": true, "lists": [{"id": "next", "items": [{"title": "Новая рекомендация"}]}]}}))
	_pump([again, background, addon, browser])
	_check(_find(_inbox(background), "state").is_empty(), "recommendations and playback seconds do not wake background phone")
	addon.send_text(JSON.stringify({"op": "adapter_state", "state": {"title": "Lo-fi для рисования", "subtitle": "Hoshi Radio", "time": 43, "duration": 3600, "playing": false}}))
	_pump([again, background, addon, browser])
	_check(not _find(_inbox(background), "state").is_empty(), "play or pause changes still reach background phone")
	background.close()
	_pump([again, background, addon, browser])
	again.send_text(JSON.stringify({"op": "run", "command": "app:tabs:play_item", "args": {"id": "28"}}))
	_pump([again, addon, browser])
	routed = _find(_inbox(browser), "run")
	_check(routed.get("command", "") == "play_item" and routed.get("args", {}).get("id", "") == "28", "choosing a listed tab reaches the browser add-on")
	_inbox(again) # результат выбора вкладки до проверки неизвестной команды
	again.send_text(JSON.stringify({"op": "run", "command": "app:blender:render"}))
	_pump([again, addon])
	_check(_find(_inbox(again), "ran").get("reason", "") == "unknown_app_command", "commands of apps that are not connected are refused")
	addon.close()
	browser.close()
	_pump([again, addon, browser], 40)
	var after: Dictionary = {}
	for message in _inbox(again):
		if message.get("op", "") == "state":
			after = message # оба соединения закрываются по очереди — нужен последний снимок
	_check(not after.is_empty() and after.get("apps", []).is_empty(), "closing the add-ons removes both sections from the phone")
	bus.assistants.handle_event({"app": "claude", "event": "Stop", "session": "chat-a", "folder": "A", "text": "Ответ первого чата"})
	bus.assistants.handle_event({"app": "claude", "event": "Stop", "session": "chat-b", "folder": "B", "text": "Ответ второго чата"})
	again.send_text(JSON.stringify({"op": "assistant_session", "app": "claude", "session": "chat-a"}))
	_pump([again], 10)
	var detail: Dictionary = _find(_inbox(again), "assistant_session")
	_check(detail.get("ok", false) and detail.get("state", {}).get("text", "") == "Ответ первого чата" and detail.get("state", {}).get("session", "") == "chat-a", "paired phone can fetch the chosen chat without switching to the newest")
	again.send_text(JSON.stringify({"op": "assistant_session", "app": "claude", "session": "missing"}))
	_pump([again], 10)
	_check(not _find(_inbox(again), "assistant_session").get("ok", true), "unknown chat details are refused")

	bus.forget_phones()
	_pump([again], 20)
	_check(bus.tokens.is_empty() and again.get_ready_state() != WebSocketPeer.STATE_OPEN, "forget phones disconnects them")
	bus.stop()
	_check_scenes()
	_check_timer()
	_check_restart()
	print("HOSHI_REMOTE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

## Сценарии: шаги — только готовые кнопки пульта, по очереди, ждут расстановку окна.
func _check_scenes() -> void:
	var scenes = bus.scenes
	scenes.path = "user://test_pc_scenes.json"
	scenes.scenes.clear()
	var id: String = scenes.add("Кино", "🎬")
	_check(scenes.add_step(id, "sit") and scenes.add_step(id, "mood_relaxed") and not scenes.add_step(id, "quit")
		and not scenes.add_step(id, "scene:" + id) and not scenes.add_step(id, "pc:windows") and not scenes.add_step(id, "app:mpc:toggle"),
		"scene steps are only ready phone buttons (no menu-only commands, no scene in scene)")
	var listed: Array = bus.remote_catalog().get("scenes", [])
	_check(listed.size() == 1 and listed[0]["command"] == "scene:" + id and listed[0]["steps"] == 2, "scenes reach the phone catalog")
	var copy = RemoteBus.PcScenes.new()
	copy.path = scenes.path
	copy.load_scenes()
	_check(copy.scenes.size() == 1 and copy.scenes[0]["steps"] == ["sit", "mood_relaxed"] and copy.scenes[0]["icon"] == "🎬", "scenes are saved and loaded")
	_check(bus.run("scene:nope") == "unknown_scene", "unknown scene is refused")
	bus.tick_scenes(0.0) # связывает шаги с шиной
	var placing: Array = [true]
	scenes.busy = func() -> bool: return placing[0]
	app.ran.clear()
	_check(bus.run("scene:" + id).is_empty() and scenes.is_running(), "scene starts from the phone")
	bus.tick_scenes(0.1)
	var waited: bool = app.ran.is_empty()
	placing[0] = false
	bus.tick_scenes(0.1)
	var first: Array = app.ran.duplicate()
	bus.tick_scenes(0.3)
	var gap: bool = app.ran.size() == 1
	for i in range(4):
		bus.tick_scenes(0.4)
	_check(waited and first == ["sit"] and gap and app.ran == ["sit", "mood_relaxed"] and not scenes.is_running(),
		"steps run in order, with a pause, after the previous window is placed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scenes.path))

## Таймер сна: пауза всего, что играет (одно видео YouTube — один раз), сон ПК — только если включён.
func _check_timer() -> void:
	var toggle := [{"name": "toggle", "title": "Пауза"}]
	bus.adapters.announce(901, {"id": "youtube", "title": "YouTube", "commands": toggle, "state": {"playing": true, "title": "Видео"}})
	bus.adapters.announce(902, {"id": "tabs", "title": "Вкладки", "commands": toggle, "state": {"playing": true, "subtitle": "youtube.com · 🔊"}})
	bus.adapters.announce(903, {"id": "vk", "title": "VK", "commands": toggle, "state": {"playing": false}})
	bus.pc.system_enabled["sleep"] = false
	_check(bus.run("timer:30", {"then": "sleep"}) == "not_allowed" and not bus.timer.active(), "sleep timer cannot put the PC to sleep unless «Сон» is enabled on the PC")
	_check(bus.run("timer:500") == "bad_minutes" and bus.run("timer:abc") == "bad_minutes", "timer minutes are checked")
	_check(bus.run("timer:30", {"then": "pause"}).is_empty() and bus.timer.state()["seconds"] > 1790, "timer starts and shows the time left")
	_check(bus.remote_catalog()["timer"]["minutes"].has(30) and bus._state_message()["timer"]["cancel"] == "timer:cancel", "timer reaches the phone")
	_check(bus.run("timer:cancel").is_empty() and not bus.timer.active() and bus.run("timer:cancel") == "nothing_to_cancel", "timer can be cancelled")
	bus.run("timer:15")
	bus.timer.ends_at = Time.get_ticks_msec() - 1
	bus.tick_scenes(0.1)
	_check(not bus.timer.active() and bus.last_paused == ["youtube"], "time is up: playing players are paused, the same YouTube video only once")
	_check(RemoteBus.PcScenes.step_allowed("timer:30") and not RemoteBus.PcScenes.step_allowed("timer:cancel"), "a scene can start the sleep timer")
	for peer in [901, 902, 903]:
		bus.adapters.drop_peer(peer)

## «Перезапустить Хоши»: на пульте с «Точно?»; новая версия с ошибкой — не закрываемся.
func _check_restart() -> void:
	var restart_item: Dictionary = {}
	for group in RemoteBus.new().remote_catalog()["groups"]:
		for item in group["commands"]:
			if item["command"] == "restart":
				restart_item = item
	_check(Commands.allows("restart", "remote") and restart_item.get("confirm", false) and restart_item.get("icon", "") == "🔄", "restart is on the phone and asks for confirmation")
	var restarter = HoshiRestart.new()
	restarter.dry_run = true
	_check(restarter.begin() == "" and restarter.status == "checking" and restarter.begin() == "busy", "restart first checks the new version, once at a time")
	_check(restarter.finish({"ok": false, "error": "script_errors"}) == "script_errors" and restarter.executed.size() == 1 and restarter.status == "", "a new version with script errors does not close Hoshi")
	restarter.begin()
	_check(restarter.finish({"ok": true}) == "ready", "a good new version lets Hoshi close")
	var relaunch: Array = restarter.executed[-1]
	var dash: int = relaunch.find("--")
	_check(relaunch[0] == "relaunch" and relaunch.has(str(OS.get_process_id())) and dash > 0 and relaunch[dash + 1] == "--path", "the waiting helper restarts the same project after this Hoshi exits")
	_check(HoshiRestart.relaunch_args()[0] == "--path" and HoshiRestart.relaunch_args().has("--log-file"), "new Hoshi gets the project folder and the session log")
