extends SceneTree
## Пульт с телефона и аддоны: страница, привязка по коду, запреты, маршрут
## команды до аддона. Без VRM; сеть — только 127.0.0.1 на тестовых портах.

const RemoteBus = preload("res://scripts/remote_bus.gd")
const Commands = preload("res://scripts/hoshi_commands.gd")
const QR = preload("res://scripts/qr_code.gd")

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
	bus.http_port = 18870
	bus.ws_port = 18871
	_check(bus.start() and bus.pairing_code.length() == 6, "remote starts with a 6-digit code")

	var version_before: int = bus.code_version
	var link: String = bus.pairing_url("http://192.168.1.23:18770/")
	_check(link == "http://192.168.1.23:18770/#pair=" + bus.pairing_code, "QR link carries the address and the one-time code")
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
	again.send_text(JSON.stringify({"op": "run", "command": "app:blender:render"}))
	_pump([again, addon])
	_check(_find(_inbox(again), "ran").get("reason", "") == "unknown_app_command", "commands of apps that are not connected are refused")
	addon.close()
	_pump([again, addon], 40)
	var after: Dictionary = _find(_inbox(again), "state")
	_check(not after.is_empty() and after.get("apps", []).is_empty(), "closing the add-on removes its section from the phone")

	bus.forget_phones()
	_pump([again], 20)
	_check(bus.tokens.is_empty() and again.get_ready_state() != WebSocketPeer.STATE_OPEN, "forget phones disconnects them")
	bus.stop()
	print("HOSHI_REMOTE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
