extends RefCounted

# Optional, local-only signal from the browser extension. No audio or text crosses
# this socket; it accepts only a bounded mouth-opening value.
const PORT: int = 18765
const PATH: String = "/hoshi-voice-v1"

var level: float = 0.0
var listening: bool = false
var _server: TCPServer = TCPServer.new()
var _peer: WebSocketPeer
var _signal_age: float = 1.0

func start(port: int = PORT) -> bool:
	if listening:
		return true
	var result: Error = _server.listen(port, "127.0.0.1")
	listening = result == OK
	if not listening:
		push_warning("Chat voice bridge unavailable on 127.0.0.1:%d (%d)" % [port, result])
	return listening

func tick(delta: float) -> void:
	if not listening:
		return
	_signal_age += maxf(delta, 0.0)
	if _signal_age > 0.25:
		level = 0.0
	while _server.is_connection_available():
		var stream: StreamPeerTCP = _server.take_connection()
		if _peer != null:
			stream.disconnect_from_host()
			continue
		var candidate := WebSocketPeer.new()
		candidate.max_queued_packets = 8
		candidate.inbound_buffer_size = 1024
		if candidate.accept_stream(stream) == OK:
			_peer = candidate
		else:
			stream.disconnect_from_host()
	if _peer == null:
		return
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _peer.get_requested_url().ends_with(PATH):
				_peer.close(1008, "Wrong path")
				return
			while _peer.get_available_packet_count() > 0:
				var packet: PackedByteArray = _peer.get_packet()
				if packet.size() > 128 or not _peer.was_string_packet():
					continue
				var payload: Variant = JSON.parse_string(packet.get_string_from_utf8())
				if payload is Dictionary and payload.size() == 1 and payload.has("level"):
					var value: Variant = payload["level"]
					if value is float or value is int:
						level = clampf(float(value), 0.0, 1.0)
						_signal_age = 0.0
		WebSocketPeer.STATE_CLOSED:
			_peer = null
			level = 0.0

func stop() -> void:
	if _peer != null:
		_peer.close(-1)
		_peer = null
	_server.stop()
	listening = false
	level = 0.0
