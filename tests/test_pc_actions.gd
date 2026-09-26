extends SceneTree
## «Мои действия» для пульта: хранение, запреты, подтверждение и отмена выключения,
## нажатие с телефона через шину. Всё «вхолостую» (dry_run): ничего не запускается.

const PcActions = preload("res://scripts/pc_actions.gd")
const RemoteBus = preload("res://scripts/remote_bus.gd")

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

func _run() -> void:
	var pc = PcActions.new()
	pc.path = "user://test_pc_actions.json"
	pc.dry_run = true
	var blender: String = pc.add("open", "", "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe")
	var folder: String = pc.add("folder", "Проекты", "D:/projects")
	var site: String = pc.add("url", "", "https://www.youtube.com/feed/subscriptions")
	_check(blender != "" and folder != "" and site != "", "programs, folders and links can be added")
	_check(pc.add("url", "", "javascript:alert(1)") == "" and pc.add("open", "", "") == "" and pc.add("shell", "", "cmd /c del") == "", "bad links, empty paths and unknown kinds are refused")
	var titles: Array = []
	for item in pc.actions:
		titles.append(item["title"])
	_check(titles == ["blender", "Проекты", "www.youtube.com"], "titles are made from file names and sites")
	_check(pc.actions[0]["icon"] == "🚀" and pc.actions[1]["icon"] == "📁" and pc.actions[2]["icon"] == "🌐", "icons follow the kind")

	var again = PcActions.new()
	again.path = pc.path
	again.load_actions()
	_check(again.actions.size() == 3 and again.actions[1]["target"] == "D:/projects", "actions are saved and loaded back")
	pc.rename(folder, "Мои проекты")
	pc.move(site, -2)
	_check(pc.actions[0]["id"] == site and pc.actions[2]["title"] == "Мои проекты", "actions can be renamed and reordered")

	var out: Dictionary = {}
	_check(pc.run("pc:" + blender, {"target": "C:/Windows/System32/cmd.exe"}, out) == "", "saved action runs")
	_check(pc.executed[-1] == ["open", "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe"] and out["say"] == "Открываю: blender", "the phone cannot change what is opened; Hoshi says what she opens")
	_check(pc.run("pc:nope", {}) == "unknown_action", "unknown actions are refused")

	var catalog_text: String = JSON.stringify(pc.catalog())
	_check(catalog_text.contains("pc:system_lock") and not catalog_text.contains("pc:system_shutdown"), "only enabled system buttons are on the phone")
	_check(pc.run("pc:system_shutdown", {"confirm": true}) == "not_allowed", "shutdown is off until enabled on the PC")
	pc.set_system("shutdown", true)
	_check(pc.run("pc:system_shutdown", {}) == "need_confirm", "shutdown asks for confirmation")
	out = {}
	_check(pc.run("pc:system_shutdown", {"confirm": true}, out) == "" and pc.executed[-1] == ["shutdown.exe", "/s", "/t", "60"], "confirmed shutdown waits one minute")
	var pending: Dictionary = pc.pending_state()
	_check(pending.get("kind", "") == "shutdown" and int(pending.get("seconds", 0)) > 50 and pending.get("cancel", "") == "pc:cancel", "phone sees the countdown and a cancel button")
	_check(pc.run("pc:cancel", {}) == "" and pc.executed[-1] == ["shutdown.exe", "/a"] and pc.pending_state().is_empty(), "cancel stops the shutdown")
	_check(pc.run("pc:cancel", {}) == "nothing_to_cancel", "nothing to cancel twice")
	_check(pc.run("pc:system_lock", {}) == "" and pc.executed[-1] == ["rundll32.exe", "user32.dll,LockWorkStation"], "lock needs no confirmation")
	_check(PcActions._split_args('--factory-startup "D:/my files/scene.blend" -b') == ["--factory-startup", "D:/my files/scene.blend", "-b"], "program parameters keep quoted paths together")

	# Через шину: телефон нажимает кнопку — действие выполняется, Хоши говорит.
	var app := StubApp.new()
	var bus = RemoteBus.new()
	bus.setup(app)
	bus.pc = pc
	_check(bus.run("pc:" + folder, {}) == "" and pc.executed[-1] == ["open", "D:/projects"] and app.said[-1] == "Открываю: Мои проекты", "phone button reaches the PC through the bus")
	_check(JSON.stringify(bus.remote_catalog()).contains("Мои проекты"), "phone catalog lists my actions")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pc.path))
	print("HOSHI_PC_ACTIONS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
