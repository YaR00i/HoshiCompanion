extends SceneTree

const VoiceBridge = preload("res://scripts/chat_voice_bridge.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _pump(bridge, client: WebSocketPeer, frames: int = 10) -> void:
	for index in range(frames):
		bridge.tick(0.016)
		client.poll()
		OS.delay_msec(2)

func _run() -> void:
	var bridge = VoiceBridge.new()
	_check(bridge.start(18766), "local voice bridge listens")
	if not bridge.listening:
		_finish()
		return
	var client := WebSocketPeer.new()
	_check(client.connect_to_url("ws://127.0.0.1:18766/hoshi-voice-v1") == OK, "websocket client starts")
	_pump(bridge, client)
	_check(client.get_ready_state() == WebSocketPeer.STATE_OPEN, "websocket handshake opens")
	client.send_text('{"level":0.6}')
	_pump(bridge, client, 5)
	_check(is_equal_approx(bridge.level, 0.6), "numeric audio level arrives")
	client.send_text('{"level":0.9,"command":"quit"}')
	_pump(bridge, client, 5)
	_check(is_equal_approx(bridge.level, 0.6), "non-audio command is ignored")
	bridge.tick(0.3)
	_check(bridge.level == 0.0, "stale signal closes mouth")
	client.close()
	bridge.stop()
	_finish()

func _finish() -> void:
	print("HOSHI_CHAT_VOICE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
