extends SceneTree
## «Звук на пульте»: хранение, выбор на ПК, нажатие с телефона через шину,
## недоступное устройство, чужие id. Всё «вхолостую» (dry_run): звук не переключается.

const SoundOutputs = preload("res://scripts/sound_outputs.gd")
const RemoteBus = preload("res://scripts/remote_bus.gd")

const HEADPHONES := "{0.0.0.00000000}.{11111111-aaaa-bbbb-cccc-000000000001}"
const TV := "{0.0.0.00000000}.{22222222-aaaa-bbbb-cccc-000000000002}"
const SPEAKERS := "{0.0.0.00000000}.{33333333-aaaa-bbbb-cccc-000000000003}"

class StubApp extends RefCounted:
	var said: Array[String] = []
	func run_command(_command: Variant) -> void:
		pass
	func remote_snapshot() -> Dictionary:
		return {}
	func remote_say(text: String) -> void:
		said.append(text)
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

func _helper_answer(default_device: String, tv_on: bool) -> Dictionary:
	var devices: Array = [
		{"id": HEADPHONES, "name": "Наушники (HyperX Cloud III)", "state": "active", "default": default_device == HEADPHONES},
		{"id": TV, "name": "LG TV (NVIDIA High Definition Audio)", "state": "active" if tv_on else "not_present", "default": default_device == TV},
		{"id": SPEAKERS, "name": "Динамики (Realtek(R) Audio)", "state": "active", "default": default_device == SPEAKERS},
		{"id": "{0.0.0.00000000}.{44444444-aaaa-bbbb-cccc-000000000004}", "name": "Mi Monitor", "state": "disabled", "default": false},
	]
	return {"ok": true, "devices": devices}

func _run() -> void:
	var sound = SoundOutputs.new()
	sound.path = "user://test_sound_outputs.json"
	sound.dry_run = true
	_check(sound.state().is_empty() and sound.catalog().is_empty(), "nothing on the phone until chosen on the PC")
	sound.apply_result(_helper_answer(SPEAKERS, true))
	_check(sound.known and sound.devices.size() == 3 and sound.current_device() == SPEAKERS, "only active devices are kept; the default is known")

	sound.set_shown(HEADPHONES, "Наушники (HyperX Cloud III)", true)
	sound.set_shown(TV, "LG TV (NVIDIA High Definition Audio)", true)
	sound.set_shown(SPEAKERS, "Динамики (Realtek(R) Audio)", true)
	sound.set_shown("C:/Windows/System32/cmd.exe", "evil", true)
	var titles: Array = []
	var icons: Array = []
	for item in sound.outputs:
		titles.append(item["title"])
		icons.append(item["icon"])
	_check(titles == ["Наушники", "LG TV", "Динамики"], "short names come from Windows names")
	_check(icons == ["🎧", "📺", "🔊"], "icons are guessed: headphones, TV, speakers")
	_check(sound.outputs.size() == 3, "something that is not a Windows device id is refused")
	var tv_id: String = sound.outputs[1]["id"]
	sound.rename(tv_id, "Телевизор")
	sound.move(tv_id, -1)
	_check(sound.outputs[0]["title"] == "Телевизор", "buttons can be renamed and reordered")

	var again = SoundOutputs.new()
	again.path = sound.path
	again.load_outputs()
	_check(again.outputs.size() == 3 and again.outputs[0]["device"] == TV, "choices are saved and loaded back")

	var state: Dictionary = sound.state()
	var speakers_cmd: String = "sound:" + str(sound.outputs[2]["id"])
	_check(state["current"] == speakers_cmd and state["available"].size() == 3, "phone sees which button is current")

	var out: Dictionary = {}
	_check(sound.run("sound:" + tv_id, out) == "" and sound.executed[-1] == ["set", TV] and out["say"] == "Звук: Телевизор", "phone button switches to the saved device")
	_check(sound.current_device() == TV, "the current device follows the switch")
	_check(sound.run("sound:nope") == "unknown_output", "unknown buttons are refused")
	_check(sound.run(TV) == "unknown_output", "the phone cannot name a device itself")

	sound.apply_result(_helper_answer(HEADPHONES, false))
	state = sound.state()
	_check(not ("sound:" + tv_id) in state["available"], "a TV that is off is shown as not available")
	out = {}
	var before: int = sound.executed.size()
	_check(sound.run("sound:" + tv_id, out) == "not_available" and sound.executed.size() == before and out["say"] == "Телевизор сейчас не на связи", "a TV that is off is not switched to")
	sound.apply_result({"ok": false, "error": "no_answer", "devices": []}, TV)
	_check(sound.notice == "Не получилось переключить звук" and sound.devices.size() == 2, "a failed switch keeps the last list and tells Hoshi")

	sound.set_shown(HEADPHONES, "", false)
	_check(sound.outputs.size() == 2 and sound.index_of_device(HEADPHONES) < 0, "a device can be removed from the phone")

	# Через шину: телефон нажимает кнопку — звук переключается, Хоши говорит.
	var app := StubApp.new()
	var bus = RemoteBus.new()
	bus.setup(app)
	bus.sound = sound
	var speakers_id: String = str(sound.outputs[1]["id"])
	_check(bus.run("sound:" + speakers_id, {}) == "" and sound.executed[-1] == ["set", SPEAKERS] and app.said[-1] == "Звук: Динамики", "phone button reaches the sound helper through the bus")
	_check(JSON.stringify(bus.remote_catalog()).contains("Телевизор"), "phone catalog lists sound buttons")
	_check(bus._state_message()["sound"]["current"] == "sound:" + speakers_id, "phone state shows the current sound button")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sound.path))
	print("HOSHI_SOUND_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
