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

	# Приложения из меню «Пуск» и какие из них — приложения пульта.
	var claude_app: String = pc.add("startapp", "Claude", "Claude_pzs8sxrjxfjjc!Claude")
	var mpc_app: String = pc.add("startapp", "MPC-BE x64", "{6D809377-6AF0-444B-8957-A3773F02200E}\\MPC-BE\\mpc-be64.exe")
	var youtube_app: String = pc.add("startapp", "YouTube", "Chrome._crx_agimnkijcamfeangaknmldooml")
	_check(claude_app != "" and mpc_app != "" and youtube_app != "", "apps from the Start menu can be added")
	_check(pc.add("startapp", "x", "Claude\" & calc") == "" and pc.add("startapp", "x", "\\\\server\\share") == "" and pc.add("startapp", "x", "..\\..\\x") == "", "start-menu ids with quotes, network paths or .. are refused")
	out = {}
	_check(pc.run("pc:" + claude_app, {}, out) == "" and pc.executed[-1] == ["explorer.exe", "shell:AppsFolder\\Claude_pzs8sxrjxfjjc!Claude"] and out["say"] == "Открываю: Claude", "a Start-menu app starts through explorer.exe shell:AppsFolder")
	var apps: Dictionary = {}
	for item in pc.catalog():
		if item.has("app") and not str(item["app"]).is_empty():
			apps[item["app"]] = item["command"]
	_check(apps.get("claude", "") == "pc:" + claude_app and apps.get("mpc", "") == "pc:" + mpc_app and apps.get("youtube", "") == "pc:" + youtube_app, "Hoshi knows which action starts Claude, MPC-BE and YouTube")
	_check(PcActions.app_for({"kind": "url", "target": "https://www.youtube.com/feed/subscriptions"}) == "youtube" and PcActions.app_for({"kind": "url", "target": "https://notyoutube.com.evil.io/"}) == "" and PcActions.app_for({"kind": "open", "target": "C:/Program Files/MPC-BE/mpc-be64.exe"}) == "mpc" and PcActions.app_for({"kind": "folder", "target": "D:/projects"}) == "", "links and programs are matched by site and file name only")

	# Где откроется окно: экран и положение у действия; с телефона — только если «спрашивать».
	pc.monitors = [{"index": 1, "label": "Экран 1 (основной) · 2560×1440"}, {"index": 2, "label": "Экран 2 · 1920×1080"}]
	pc.set_place(mpc_app, 2, "right", false)
	out = {}
	_check(pc.run("pc:" + mpc_app, {"monitor": 1, "mode": "max"}, out) == "" and pc.executed[-2] == ["place", str(OS.get_process_id()), "2", "right", "mpc-be64.exe", "reuse"] and pc.executed[-1][0] == "explorer.exe", "the window goes where the PC settings say; the phone cannot change it without «ask»")
	pc.set_place(mpc_app, 2, "right", true)
	pc.run("pc:" + mpc_app, {"monitor": 1, "mode": "max"})
	_check(pc.executed[-2] == ["place", str(OS.get_process_id()), "1", "max", "mpc-be64.exe", "reuse"], "with «ask» the phone chooses the screen and the position")
	pc.run("pc:" + mpc_app, {"monitor": 99, "mode": "rm -rf"})
	_check(pc.executed[-2][2] == "16" and pc.executed[-2][3] == "center", "the phone can pass only a screen number and one of four positions")
	pc.run("pc:" + mpc_app, {"monitor": 0, "mode": "left"})
	_check(pc.executed[-2] == ["place", str(OS.get_process_id()), "0", "left", "mpc-be64.exe", "reuse"] and pc.executed[-1][0] == "explorer.exe", "«as it opens» on the phone launches without moving anything (only «already open?» is checked)")
	# «Если уже открыто — показать»: выключили — запуск без проверки.
	pc.set_place(mpc_app, 0, "center", false, false)
	var before_count: int = pc.executed.size()
	pc.run("pc:" + mpc_app, {})
	_check(pc.executed.size() == before_count + 1 and pc.executed[-1][0] == "explorer.exe", "with «show if already open» off it just starts")
	pc.set_place(mpc_app, 0, "center", false, true)
	pc.run("pc:" + mpc_app, {})
	_check(pc.executed[-2][-1] == "reuse" and not PcActions.reuses({"kind": "url", "target": "https://x.io"}), "«show if already open» is on by default when Hoshi knows the program")
	pc.set_place(mpc_app, 2, "right", true)
	var ask_item: Dictionary = {}
	for item in pc.catalog():
		if item["command"] == "pc:" + mpc_app:
			ask_item = item
	_check(ask_item.has("ask_place") and ask_item["ask_place"]["monitors"].size() == 2 and ask_item["ask_place"]["modes"].has("left"), "the phone gets the screens and positions to choose from")
	_check(PcActions.window_exe({"kind": "startapp", "target": "Claude_pzs8sxrjxfjjc!Claude"}) == "claude.exe" and PcActions.window_exe({"kind": "folder", "target": "D:/x"}) == "explorer.exe" and PcActions.window_exe({"kind": "open", "target": "D:/a.lnk"}) == "", "Hoshi knows whose window to wait for")
	var reloaded = PcActions.new()
	reloaded.path = pc.path
	reloaded.load_actions()
	var saved_place: Dictionary = {}
	for item in reloaded.actions:
		if item["id"] == mpc_app:
			saved_place = item.get("place", {})
	_check(saved_place == {"monitor": 2, "mode": "right", "ask": true} and reloaded.monitors.size() == 2, "window settings and the screen list are saved")

	# Переставить уже открытое окно: только из последнего списка, экран и положение — из списков.
	_check(pc.windows_state().is_empty() and pc.run("pc:move", {"hwnd": "123", "monitor": 1, "mode": "left"}) == "unknown_window", "no window list yet — nothing to move")
	pc.apply_windows({"windows": [{"hwnd": "132456", "app": "CHROME.EXE", "monitor": 2, "state": "maximized", "title": "Секретная переписка"},
		{"hwnd": "not-a-number", "app": "x.exe"}, {"hwnd": "777", "app": "mpc-be64.exe", "monitor": 1, "state": "hacked"}]})
	_check(pc.open_windows.size() == 2 and pc.open_windows[0]["name"] == "Chrome" and pc.open_windows[1]["name"] == "MPC-BE" and pc.open_windows[1]["state"] == "normal", "open windows: program names only, bad entries dropped")
	_check(not JSON.stringify(pc.windows_state()).contains("Секретная") and pc.windows_state()["monitors"].size() == 2, "window titles never reach the phone; the screen map does")
	out = {}
	_check(pc.run("pc:move", {"hwnd": "132456", "monitor": 1, "mode": "left"}, out) == "" and pc.executed[-1] == ["move", str(OS.get_process_id()), "132456", "1", "left"] and out["say"] == "Переставляю: Chrome", "a listed window moves to the chosen screen and half")
	_check(pc.run("pc:move", {"hwnd": "999", "monitor": 1, "mode": "left"}) == "unknown_window" and pc.run("pc:move", {"hwnd": "777", "monitor": 0, "mode": "max"}) == "bad_screen", "unknown windows and «no screen» are refused")
	pc.run("pc:move", {"hwnd": "777", "monitor": 3, "mode": "evil"})
	_check(pc.executed[-1][4] == "center", "unknown positions become «centre»")
	_check(PcActions.pretty_app("blender.exe") == "Blender" and PcActions.pretty_app("someapp.exe") == "Someapp", "friendly program names")
	pc.run("pc:move", {"hwnd": "132456", "monitor": 2, "mode": "right", "front": true})
	_check(pc.executed[-1] == ["move", str(OS.get_process_id()), "132456", "2", "right", "front"], "«over other windows» brings the moved window to the top")
	out = {}
	_check(pc.run("pc:front", {"hwnd": "777"}, out) == "" and pc.executed[-1] == ["front", str(OS.get_process_id()), "777"] and out["say"] == "Показываю: MPC-BE", "«show on top» without moving")
	_check(pc.run("pc:front", {"hwnd": "31337"}) == "unknown_window", "only listed windows can be brought to the top")

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
