extends SceneTree
## Плеер MPC-BE на пульте: разбор variables.html (без пути к файлу), карточка,
## команды, маршрут через шину, появление/исчезновение карточки.
## Всё «вхолостую» (dry_run): к MPC-BE ничего не отправляется.

const MpcAdapter = preload("res://scripts/mpc_adapter.gd")
const RemoteBus = preload("res://scripts/remote_bus.gd")

const PAGE := """<html><body>
		<p id="file">Интерны_149.avi</p>
		<p id="filepatharg">D:\\downloads\\secret%20folder\\Интерны_149.avi</p>
		<p id="filepath">D:\\downloads\\Секретная папка\\Интерны_149.avi</p>
		<p id="filedir">D:\\downloads\\Секретная папка</p>
		<p id="state">2</p>
		<p id="statestring">Воспроизведение</p>
		<p id="position">483034</p>
		<p id="duration">1453840</p>
		<p id="volumelevel">20</p>
		<p id="muted">0</p>
</body></html>"""

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

func _run() -> void:
	var mpc = MpcAdapter.new()
	mpc.dry_run = true
	var info: Dictionary = mpc.parse_variables(PAGE)
	_check(info == {"file": "Интерны_149.avi", "state": 2, "position": 483, "duration": 1453, "volume": 20, "muted": false}, "only file name, state, times and volume are read")
	_check(not JSON.stringify(info).contains("downloads") and not JSON.stringify(info).contains("Секретная"), "the path to the file is never taken")
	_check(mpc.run("toggle", {}) == "not_running", "nothing is sent while MPC-BE is closed")

	mpc.present = true
	mpc.info = info
	var card: Dictionary = mpc.card_state()
	_check(card["title"] == "Интерны_149" and card["time"] == 483 and card["duration"] == 1453 and card["playing"] and card["icons"]["toggle"] == "⏸", "card shows the name without extension, time and a pause icon")
	_check(mpc.run("toggle", {}) == "" and mpc.sent[-1] == "wm_command=889", "play/pause")
	_check(mpc.run("next", {}) == "" and mpc.sent[-1] == "wm_command=920", "next file")
	_check(mpc.run("fullscreen", {}) == "" and mpc.sent[-1] == "wm_command=830", "fullscreen")
	_check(card["subtitle"] == "MPC-BE · громкость 20%" and card["icons"]["mute"] == "🔈", "card shows the player volume")
	mpc.run("vol_up", {})
	var up: String = mpc.sent[-1]
	mpc.run("vol_down", {})
	var down: String = mpc.sent[-1]
	mpc.run("mute", {})
	_check([up, down, mpc.sent[-1]] == ["wm_command=907", "wm_command=908", "wm_command=909"], "louder, quieter, mute")
	mpc.info["muted"] = true
	_check(mpc.card_state()["icons"]["mute"] == "🔇" and mpc.card_state()["active"] == ["mute"] and mpc.card_state()["subtitle"].ends_with("без звука"), "muted player is shown on the card")
	mpc.info["muted"] = false
	_check(mpc.run("forward", {"seconds": 10}) == "" and mpc.sent[-1] == "wm_command=-1&position=00:08:13", "+10 seconds seeks from the current position")
	mpc.run("forward", {"seconds": 10})
	_check(mpc.sent[-1] == "wm_command=-1&position=00:08:23", "two quick presses add up")
	_check(mpc.run("seek_to", {"time": 99999}) == "" and mpc.sent[-1] == "wm_command=-1&position=00:24:12", "seeking is kept inside the file")
	mpc.info["position"] = 4
	mpc.run("back", {"seconds": 10})
	_check(mpc.sent[-1] == "wm_command=-1&position=00:00:00", "going back stops at the start")
	_check(mpc.run("shutdown", {}) == "unknown_command", "unknown commands are refused")
	mpc.info = {"file": "", "state": -1}
	_check(mpc.card_state().has("hint") and not mpc.card_state().has("title"), "no file — a hint instead of a player")

	# Через шину: карточка появляется, кнопка доходит до MPC-BE, карточка исчезает.
	mpc.info = info
	var bus = RemoteBus.new()
	bus.setup(StubApp.new())
	bus.mpc = mpc
	bus._sync_mpc()
	var apps: Array = bus._state_message()["apps"]
	_check(apps.size() == 1 and apps[0]["id"] == "mpc" and apps[0]["state"]["title"] == "Интерны_149", "phone sees the MPC-BE card")
	var names: Array = []
	for command in apps[0]["commands"]:
		names.append(command["command"])
	_check("app:mpc:toggle" in names and "app:mpc:seek_to" in names, "card has the player buttons")
	_check(bus.run("app:mpc:toggle", {}) == "" and mpc.sent[-1] == "wm_command=889", "phone button reaches MPC-BE through the bus")
	_check(bus.run("app:mpc:seek_to", {"time": 60, "path": "C:/x"}) == "" and mpc.sent[-1] == "wm_command=-1&position=00:01:00", "the phone can only pass a time")
	mpc.present = false
	bus._sync_mpc()
	_check(bus._state_message()["apps"].is_empty(), "closing MPC-BE removes the card")
	_check(bus.run("app:mpc:toggle", {}) == "unknown_app_command", "no card — no button")
	_check(MpcAdapter.clock(3725) == "01:02:05", "time format for MPC-BE")
	print("HOSHI_MPC_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
