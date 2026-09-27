extends RefCounted
## Пульт Хоши с телефона и подключение аддонов — одна «шина команд».
##
## Два входа:
##   * телефон в ДОМАШНЕЙ сети: страница http://<ПК>:18770/ и WebSocket
##     ws://<ПК>:18771/hoshi-remote-v1. Сначала привязка по 6-значному коду,
##     который показывает Хоши на ПК; дальше телефон помнит свой ключ;
##   * аддоны (расширение Chrome, аддон Blender) — только с этого же ПК:
##     ws://127.0.0.1:18771/hoshi-adapter-v1 (см. app_adapters.gd).
##
## Безопасность:
##   * выключено по умолчанию, включается в меню «Пульт с телефона»;
##   * соединения только из локальной сети (192.168.*, 10.*, 172.16–31.*,
##     169.254.*, fe80::/fd*, 127.0.0.1); из интернета — отказ;
##   * телефон может запускать только команды с источником "remote"
##     (hoshi_commands.gd) и команды подключённых аддонов;
##   * 5 неверных кодов подряд — новый код;
##   * сообщения ограничены по размеру и частоте.
## Сама шина ничего не двигает: команды Хоши идут через app.run_command() —
## тот же исполнитель, что у кнопок меню.

const Commands = preload("res://scripts/hoshi_commands.gd")
const Adapters = preload("res://scripts/app_adapters.gd")
const PcActions = preload("res://scripts/pc_actions.gd")
const SoundOutputs = preload("res://scripts/sound_outputs.gd")
const MpcAdapter = preload("res://scripts/mpc_adapter.gd")

const HTTP_PORT: int = 18770
const WS_PORT: int = 18771
const REMOTE_PATH: String = "/hoshi-remote-v1"
const ADAPTER_PATH: String = "/hoshi-adapter-v1"
const PAGE_PATH: String = "res://remote/remote.html"
const MAX_PHONES: int = 4
const MAX_PEERS: int = 16
const MAX_PHONE_PACKET: int = 4096
const MAX_ADAPTER_PACKET: int = 65536
const MAX_RUNS_PER_SECOND: float = 8.0
## A visible remote page pings every 5 s. A phone that says nothing for this long (its
## screen locked and the connection died silently) is dropped to free its place.
const PHONE_SILENCE: float = 20.0

var enabled: bool = false
var pairing_code: String = ""
## Растёт при каждой смене кода — чтобы окно с QR обновилось.
var code_version: int = 0
## Ключи привязанных телефонов (хранятся в настройках Хоши).
var tokens: PackedStringArray = []
var adapters = Adapters.new()
## «Мои действия» для вкладки «Компьютер» (задаются только на ПК).
var pc = PcActions.new()
## «Звук на пульте»: куда идёт звук ПК (устройства выбираются только на ПК).
var sound = SoundOutputs.new()
## Плеер MPC-BE — встроенный аддон (карточка как у YouTube).
var mpc = MpcAdapter.new()
var last_error: String = ""
## Для тестов: слушать только 127.0.0.1 и на других портах.
var loopback_only: bool = false
var http_port: int = HTTP_PORT
var ws_port: int = WS_PORT

var _app_ref: WeakRef
var _http := TCPServer.new()
var _ws := TCPServer.new()
var _http_clients: Array = []   # [{stream, buffer, age}]
var _peers: Dictionary = {}     # key -> {ws, role, authed, host, runs, age}
var _next_key: int = 1
var _wrong_codes: int = 0
var _state_clock: float = 0.0
var _last_state_text: String = ""
var _rng := RandomNumberGenerator.new()

func setup(app) -> void:
	_app_ref = weakref(app)
	_rng.randomize()

func _app():
	return _app_ref.get_ref() if _app_ref != null else null

# ---------------------------------------------------------------- включение

func start() -> bool:
	stop()
	var bind: String = "127.0.0.1" if loopback_only else "*"
	if _http.listen(http_port, bind) != OK or _ws.listen(ws_port, bind) != OK:
		last_error = "port_busy"
		stop()
		return false
	enabled = true
	last_error = ""
	new_pairing_code()
	return true

func stop() -> void:
	for key in _peers.keys():
		_peers[key]["ws"].close(1001, "Hoshi remote off")
	_peers.clear()
	for client in _http_clients:
		client["stream"].disconnect_from_host()
	_http_clients.clear()
	_http.stop()
	_ws.stop()
	adapters = Adapters.new()
	enabled = false

func new_pairing_code() -> void:
	pairing_code = "%06d" % _rng.randi_range(0, 999999)
	_wrong_codes = 0
	code_version += 1

## Ссылка для QR: адрес пульта + одноразовый код. Телефон, открыв её,
## привязывается сам, без ввода кода.
func pairing_url(address: String) -> String:
	return "%s#pair=%s" % [address, pairing_code]

func forget_phones() -> void:
	tokens = PackedStringArray()
	for key in _peers.keys():
		if _peers[key]["role"] == "phone":
			_peers[key]["ws"].close(4001, "Forgotten")
	new_pairing_code()

## Адреса, по которым телефон может открыть пульт.
func addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.contains(".") and is_home_address(address) and not address.begins_with("127.") and not address.begins_with("169.254."):
			result.append("http://%s:%d/" % [address, http_port])
	return result

## Только домашняя/локальная сеть и сам ПК.
static func is_home_address(address: String) -> bool:
	if address in ["127.0.0.1", "::1"] or address.begins_with("::ffff:127."):
		return true
	var plain: String = address.trim_prefix("::ffff:")
	if plain.begins_with("192.168.") or plain.begins_with("10.") or plain.begins_with("169.254."):
		return true
	if plain.begins_with("172."):
		var parts: PackedStringArray = plain.split(".")
		return parts.size() == 4 and int(parts[1]) >= 16 and int(parts[1]) <= 31
	var lower: String = address.to_lower()
	return lower.begins_with("fe80:") or lower.begins_with("fd") or lower.begins_with("fc")

static func is_same_pc(address: String) -> bool:
	return address in ["127.0.0.1", "::1"] or address.begins_with("::ffff:127.")

# ---------------------------------------------------------------- каждый кадр

func tick(delta: float) -> void:
	if not enabled:
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	_accept_http()
	_serve_http(dt)
	_accept_ws()
	for key in _peers.keys():
		# A reconnecting phone may have closed another peer earlier in this loop.
		if _peers.has(key):
			_poll_peer(key, dt)
	mpc.tick(dt, phone_count() > 0)
	_sync_mpc()
	if not sound.notice.is_empty():
		_say(sound.notice)
		sound.notice = ""
	_state_clock += dt
	if _state_clock >= 0.5:
		_state_clock = 0.0
		_broadcast_state(false)

func phone_count() -> int:
	var count: int = 0
	for key in _peers:
		if _peers[key]["role"] == "phone" and _peers[key]["authed"]:
			count += 1
	return count

# ---------------------------------------------------------------- страница

func _accept_http() -> void:
	while _http.is_connection_available():
		var stream: StreamPeerTCP = _http.take_connection()
		if _http_clients.size() >= 8 or not is_home_address(stream.get_connected_host()):
			stream.disconnect_from_host()
			continue
		_http_clients.append({"stream": stream, "buffer": "", "age": 0.0})

func _serve_http(dt: float) -> void:
	for client in _http_clients.duplicate():
		var stream: StreamPeerTCP = client["stream"]
		stream.poll()
		client["age"] += dt
		var available: int = stream.get_available_bytes()
		if available > 0:
			var chunk: Array = stream.get_partial_data(mini(available, 4096))
			if chunk[0] == OK:
				client["buffer"] += (chunk[1] as PackedByteArray).get_string_from_utf8()
		var request: String = client["buffer"]
		if request.contains("\r\n\r\n") or request.length() > 4096 or client["age"] > 3.0 or stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			if request.contains("\r\n\r\n"):
				_respond(stream, request.get_slice("\r\n", 0))
			stream.disconnect_from_host()
			_http_clients.erase(client)

func _respond(stream: StreamPeerTCP, request_line: String) -> void:
	var parts: PackedStringArray = request_line.split(" ")
	var path: String = parts[1].get_slice("?", 0) if parts.size() >= 2 else ""
	var body := PackedByteArray()
	var kind: String = "text/plain; charset=utf-8"
	var status: String = "200 OK"
	if parts.size() < 2 or parts[0] != "GET":
		status = "405 Method Not Allowed"
		body = "Only GET".to_utf8_buffer()
	elif path == "/" or path == "/index.html":
		body = FileAccess.get_file_as_bytes(PAGE_PATH)
		kind = "text/html; charset=utf-8"
		if body.is_empty():
			status = "500 Internal Server Error"
			body = "Remote page missing".to_utf8_buffer()
	elif path == "/manifest.webmanifest":
		kind = "application/manifest+json"
		body = JSON.stringify({"name": "Хоши", "short_name": "Хоши", "start_url": "/", "display": "standalone",
			"background_color": "#fff8f1", "theme_color": "#665479"}).to_utf8_buffer()
	else:
		status = "404 Not Found"
		body = "Not found".to_utf8_buffer()
	var head: String = "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n" % [status, kind, body.size()]
	stream.put_data(head.to_utf8_buffer())
	stream.put_data(body)

# ---------------------------------------------------------------- соединения

func _accept_ws() -> void:
	while _ws.is_connection_available():
		var stream: StreamPeerTCP = _ws.take_connection()
		var host: String = stream.get_connected_host()
		if _peers.size() >= MAX_PEERS or not is_home_address(host):
			stream.disconnect_from_host()
			continue
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = MAX_ADAPTER_PACKET * 2
		ws.max_queued_packets = 64
		if ws.accept_stream(stream) != OK:
			stream.disconnect_from_host()
			continue
		_peers[_next_key] = {"ws": ws, "role": "", "authed": false, "host": host, "runs": 0.0, "age": 0.0, "seen": 0.0, "token": ""}
		_next_key += 1

func _poll_peer(key: int, dt: float) -> void:
	var peer: Dictionary = _peers[key]
	var ws: WebSocketPeer = peer["ws"]
	ws.poll()
	peer["age"] += dt
	peer["seen"] = float(peer["seen"]) + dt
	peer["runs"] = maxf(0.0, float(peer["runs"]) - dt * MAX_RUNS_PER_SECOND)
	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if peer["role"] == "":
				_assign_role(key)
				if not _peers.has(key):
					return
			while ws.get_available_packet_count() > 0:
				var packet: PackedByteArray = ws.get_packet()
				var limit: int = MAX_ADAPTER_PACKET if peer["role"] == "adapter" else MAX_PHONE_PACKET
				if packet.size() > limit or not ws.was_string_packet():
					continue
				var message: Variant = JSON.parse_string(packet.get_string_from_utf8())
				peer["seen"] = 0.0
				if message is Dictionary:
					_handle(key, message)
				if not _peers.has(key):
					return
			if peer["role"] == "phone" and float(peer["seen"]) > PHONE_SILENCE:
				_drop_peer(key, 4000, "Silent")
				return
		WebSocketPeer.STATE_CLOSED:
			if peer["role"] == "adapter":
				adapters.drop_peer(key)
				_broadcast_state(true)
			_peers.erase(key)
		_:
			if peer["age"] > 5.0 and peer["role"] == "":
				ws.close()

func _assign_role(key: int) -> void:
	var peer: Dictionary = _peers[key]
	var path: String = peer["ws"].get_requested_url().get_slice("?", 0)
	if path.ends_with(ADAPTER_PATH) and is_same_pc(peer["host"]):
		peer["role"] = "adapter"
	elif path.ends_with(REMOTE_PATH):
		var phones: int = 0
		for other in _peers:
			if _peers[other]["role"] == "phone":
				phones += 1
		if phones >= MAX_PHONES:
			# Places are usually taken by connections of locked phones that died silently:
			# make room by dropping the one that has been quiet the longest.
			var quietest: int = -1
			for other in _peers:
				if other != key and _peers[other]["role"] == "phone" and (quietest < 0 or float(_peers[other]["seen"]) > float(_peers[quietest]["seen"])):
					quietest = other
			if quietest < 0:
				peer["ws"].close(1013, "Too many phones")
				_peers.erase(key)
				return
			_drop_peer(quietest, 4000, "Replaced")
		peer["role"] = "phone"
	else:
		peer["ws"].close(1008, "Wrong path")
		_peers.erase(key)

func _send(key: int, message: Dictionary) -> void:
	if _peers.has(key) and _peers[key]["ws"].get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peers[key]["ws"].send_text(JSON.stringify(message))

# ---------------------------------------------------------------- сообщения

func _handle(key: int, message: Dictionary) -> void:
	var peer: Dictionary = _peers[key]
	var op: String = str(message.get("op", ""))
	if peer["role"] == "adapter":
		_handle_adapter(key, op, message)
		return
	if op == "ping":
		# Heartbeat of a visible remote page; any message already refreshed "seen".
		_send(key, {"op": "pong"})
		return
	if not peer["authed"]:
		match op:
			"pair":
				if str(message.get("code", "")) == pairing_code and pairing_code != "":
					var token: String = _new_token()
					tokens.append(token)
					peer["authed"] = true
					peer["token"] = token
					_send(key, {"op": "paired", "token": token})
					_welcome(key)
					new_pairing_code() # один код — один телефон
					_on_tokens_changed()
				else:
					_wrong_codes += 1
					if _wrong_codes >= 5:
						new_pairing_code()
					_send(key, {"op": "error", "reason": "bad_code"})
			"hello":
				if str(message.get("token", "")) in tokens:
					peer["authed"] = true
					peer["token"] = str(message.get("token", ""))
					_drop_same_phone(key)
					_welcome(key)
				else:
					_send(key, {"op": "error", "reason": "need_pairing"})
			_:
				_send(key, {"op": "error", "reason": "need_pairing"})
		return
	match op:
		"run":
			peer["runs"] = float(peer["runs"]) + 1.0
			if float(peer["runs"]) > MAX_RUNS_PER_SECOND:
				_send(key, {"op": "error", "reason": "too_fast"})
				return
			var command: String = str(message.get("command", ""))
			var result: String = run(command, message.get("args", {}))
			_send(key, {"op": "ran", "command": command, "ok": result.is_empty(), "reason": result})
			_broadcast_state(true)
		"state":
			_send(key, _state_message())
		_:
			_send(key, {"op": "error", "reason": "unknown_op"})

func _handle_adapter(key: int, op: String, message: Dictionary) -> void:
	match op:
		"adapter":
			var id: String = adapters.announce(key, message)
			_send(key, {"op": "welcome", "id": id} if not id.is_empty() else {"op": "error", "reason": "bad_adapter"})
			_broadcast_state(true)
		"adapter_state":
			if adapters.update_state(key, message.get("state", {})):
				_broadcast_state(false)
		"event":
			# Событие аддона (например, видео закончилось) — Хоши может отреагировать.
			var app = _app()
			if app != null and app.has_method("on_app_event"):
				app.on_app_event(str(message.get("id", "")), str(message.get("event", "")))

## Выполнить команду с телефона. Пусто — выполнено, иначе причина отказа.
func run(command: String, args: Variant = {}) -> String:
	if command.begins_with("pc:") or command.begins_with("sound:"):
		var out: Dictionary = {}
		var reason: String = pc.run(command, args if args is Dictionary else {}, out) if command.begins_with("pc:") else sound.run(command, out)
		if out.has("say"):
			_say(str(out["say"]))
		return reason
	if command.begins_with("app:"):
		var target: Dictionary = adapters.resolve(command)
		if target.is_empty():
			return "unknown_app_command"
		if int(target["peer"]) == MpcAdapter.PEER:
			return mpc.run(target["name"], _clean_args(args))
		_send(int(target["peer"]), {"op": "run", "command": target["name"], "args": _clean_args(args)})
		return ""
	if not Commands.allows(command, "remote"):
		return "not_allowed"
	var app = _app()
	if app == null:
		return "no_app"
	app.run_command(command)
	return ""

## MPC-BE отвечает — его карточка есть на пульте; закрыли плеер — карточка исчезает.
func _sync_mpc() -> void:
	if not mpc.present:
		adapters.drop_peer(MpcAdapter.PEER)
	elif not adapters.adapters.has(MpcAdapter.ID):
		adapters.announce(MpcAdapter.PEER, mpc.announcement())
	else:
		adapters.update_state(MpcAdapter.PEER, mpc.card_state())

func _say(text: String) -> void:
	var app = _app()
	if app != null and app.has_method("remote_say"):
		app.remote_say(text)

func _clean_args(args: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not args is Dictionary:
		return result
	for name in args:
		if result.size() >= 8:
			break
		var value: Variant = args[name]
		if value is bool or value is int or value is float:
			result[str(name).left(24)] = value
		elif value is String:
			result[str(name).left(24)] = (value as String).left(200)
	return result

func _welcome(key: int) -> void:
	_send(key, {"op": "welcome", "catalog": remote_catalog()})
	sound.request_refresh()
	_send(key, _state_message())

## Команды Хоши для пульта: быстрые кнопки и разделы по вкладкам.
func remote_catalog() -> Dictionary:
	var quick: Array = []
	for command in Commands.REMOTE_QUICK:
		if Commands.allows(command, "remote"):
			quick.append(_item(command))
	var groups: Array = []
	for group in Commands.REMOTE_GROUPS:
		var items: Array = []
		for command in Commands.names():
			if Commands.group(command) == group[0] and Commands.allows(command, "remote"):
				items.append(_item(command))
		if not items.is_empty():
			groups.append({"id": group[0], "title": group[1], "tab": group[2], "commands": items})
	return {"quick": quick, "groups": groups, "pc": pc.catalog(), "sound": sound.catalog()}

## Список «Моих действий» или «Звука на пульте» изменили на ПК — обновить пульты.
func refresh_catalog() -> void:
	for key in _peers:
		if _peers[key]["role"] == "phone" and _peers[key]["authed"]:
			_send(key, {"op": "catalog", "catalog": remote_catalog()})

func _item(command: String) -> Dictionary:
	return {"command": command, "title": Commands.short_title(command), "icon": Commands.icon(command)}

func _state_message() -> Dictionary:
	var app = _app()
	var hoshi: Dictionary = app.remote_snapshot() if app != null and app.has_method("remote_snapshot") else {}
	return {"op": "state", "hoshi": hoshi, "apps": adapters.catalog(), "pc_pending": pc.pending_state(), "sound": sound.state()}

func _broadcast_state(force: bool) -> void:
	var message: Dictionary = _state_message()
	var text: String = JSON.stringify(message)
	if not force and text == _last_state_text:
		return
	_last_state_text = text
	for key in _peers:
		if _peers[key]["role"] == "phone" and _peers[key]["authed"]:
			_peers[key]["ws"].send_text(text)

## The same phone came back (after its screen was locked): close its old connection
## right away instead of keeping a dead one around.
func _drop_same_phone(key: int) -> void:
	for other in _peers.keys():
		if other != key and _peers[other]["role"] == "phone" and str(_peers[other]["token"]) == str(_peers[key]["token"]):
			_drop_peer(other, 4000, "Replaced")

func _drop_peer(key: int, code: int, reason: String) -> void:
	if _peers.has(key):
		_peers[key]["ws"].close(code, reason)
		_peers.erase(key)

func _new_token() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(24).hex_encode()

func _on_tokens_changed() -> void:
	var app = _app()
	if app != null and app.has_method("_save_settings"):
		app._save_settings()
