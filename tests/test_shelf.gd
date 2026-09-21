extends SceneTree
## Real avatar + optional native own-window test. Never captures other apps.
const Playground = preload("res://scripts/shelf_playground.gd")
var app
var checks: int = 0
var failures: int = 0
var native_tested: bool = false
var output: String = "res://.workspace/screenshots/shelf_04"

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _advance(count: int) -> void:
	for index in range(count):
		app._process(1.0 / 30.0)

func _run() -> void:
	_geometry_checks()
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for index in range(20):
		await process_frame
		if app._ready_to_run:
			break
	_check(app._ready_to_run, "actual coordinator and VRM load")
	if not app._ready_to_run:
		quit(1)
		return
	app.set_process(false)
	app.state.autonomy_enabled = false
	app.ui.bubbles_enabled = false
	_advance(5)
	_check(not app.playground.active() and app.playground.shelf == null, "no shelf is opened on normal startup")
	_check(app.ui.menu.get_item_index(40) >= 0 and app.ui.menu.get_item_index(41) >= 0, "shelf and return actions are present")
	_pose_checks()
	if DisplayServer.get_name() == "Windows":
		native_tested = true
		await _native_checks()
	else:
		_check(not app.playground.show_demo(), "headless cannot silently open a shelf")
	app._switch_mode(true)
	app.queue_free()
	await process_frame
	print("HOSHI_SHELF_RESULT checks=", checks, " failures=", failures, " native_windows=", native_tested)
	quit(0 if failures == 0 else 1)

func _geometry_checks() -> void:
	var area := Rect2i(-1920, -200, 1920, 1080)
	var rect := Rect2i(-1500, 320, 700, 285)
	var seat := Vector2(176.0, 298.4)
	var size := Vector2i(352, 426)
	var a: Dictionary = Playground.solve_placement(rect, 0.6, seat, size, area)
	_check(a.get("ok", false), "negative-coordinate monitor is supported")
	if a.get("ok", false):
		_check((a["position"] + seat).distance_to(a["anchor"]) < 1.0, "fractional anchor rounding stays below one pixel")
	var shifted := Rect2i(rect.position + Vector2i(61, 18), rect.size)
	var b: Dictionary = Playground.solve_placement(shifted, 0.6, seat, size, area)
	_check(b.get("ok", false) and b["position"] - a["position"] == Vector2(61, 18), "moving support translates avatar by same delta")
	var narrow := Rect2i(rect.position, Vector2i(100, 285))
	_check(not Playground.solve_placement(narrow, 0.6, seat, size, area)["ok"], "too narrow support rejected")
	var high := Rect2i(Vector2i(-1500, -195), rect.size)
	_check(not Playground.solve_placement(high, 0.6, seat, size, area)["ok"], "cannot hide avatar above monitor")
	_check(not Playground.solve_placement(rect, NAN, seat, size, area)["ok"], "invalid anchor rejected")

func _pose_checks() -> void:
	_check(app.stage.edge_pose.available, "edge pose maps the actual model")
	var skel: Skeleton3D = app.stage.rig.skeleton
	var rests: Array[Transform3D] = []
	for bone in range(skel.get_bone_count()):
		rests.append(skel.get_bone_rest(bone))
	app.state.posture.kind = "edge"
	app.state.posture.request_sit(false)
	_advance(110)
	_check(app.state.posture.mode == "seated", "edge pose settles without a route")
	var good: bool = true
	for side in ["left", "right"]:
		var knee: Vector3 = app.stage.rig.world_point(side + "LowerLeg")
		var ankle: Vector3 = app.stage.rig.world_point(side + "Foot")
		var hip: Vector3 = app.stage.rig.world_point(side + "UpperLeg")
		good = good and knee.is_finite() and ankle.is_finite() and knee.z > hip.z + 0.2 and ankle.y < knee.y - 0.2
	_check(good, "thighs forward and lower legs hang below knees")
	var pelvis: Vector3 = app.stage.rig.world_point("hips")
	app.state.wave()
	_advance(25)
	_check(app.stage.rig.world_point("hips").distance_to(pelvis) < 0.002, "greeting preserves edge pelvis support")
	_check(app.stage.rig.world_point("rightHand").y > app.stage.rig.world_point("rightUpperArm").y, "edge greeting raises wrist")
	var unchanged: bool = true
	for bone in range(skel.get_bone_count()):
		unchanged = unchanged and skel.get_bone_rest(bone).is_equal_approx(rests[bone])
	_check(unchanged, "edge pose never edits authored rest matrices")
	app.state.posture.reset_standing()
	_advance(150)

func _attach() -> bool:
	var accepted: bool = app.playground.show_demo()
	await process_frame
	await process_frame
	_advance(130)
	await process_frame
	return accepted and app.playground.phase == "attached"

func _native_checks() -> void:
	var attached: bool = await _attach()
	_check(attached, "native shelf opens and avatar docks")
	if not attached:
		print("SHELF_PHASE ", app.playground.phase)
		return
	var shelf = app.playground.shelf
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = Vector2(30, 10)
	press.pressed = true
	shelf.push_input(press, true)
	_check(shelf._dragging, "drag strip receives GUI input through its layout")
	press = press.duplicate()
	press.pressed = false
	shelf.push_input(press, true)
	_check(not shelf._dragging, "drag strip releases without global mouse injection")
	_check(not shelf.is_embedded() and shelf.get_window_id() != root.get_window_id(), "shelf is a distinct native window")
	_check(app.playground.last_support_error < 1.1, "native seat anchor aligned within one pixel")
	_check(app.state.posture.kind == "edge" and app.state.posture.mode == "seated", "native shelf uses edge pose, not floor crouch")
	await _capture("01_attached")
	var before: Vector2i = root.position
	var saved_floor: Vector2i = app.playground.saved_floor_position
	shelf.position += Vector2i(75, 12)
	await process_frame
	_advance(3)
	_check((Vector2(root.position - before) - Vector2(75, 12)).length() < 1.5, "native support movement is followed")
	_check(app.playground.saved_floor_position == saved_floor, "moving shelf preserves floor save position")
	before = root.position
	shelf.size.x += 100
	await process_frame
	_advance(3)
	_check(absf(float(root.position.x - before.x) - 60.0) < 2.0, "resize keeps relative seat position on shelf")
	_check(app.playground.last_support_error < 1.1, "resize keeps vertical contact")
	await _capture("02_moved_resized")
	app._on_action(305)
	var surface_walk_seen: bool = false
	for index in range(720):
		_advance(1)
		surface_walk_seen = surface_walk_seen or (app.playground.surface.mode == "walk" and app.walker.active())
		if surface_walk_seen and app.playground.surface.mode == "sit" and app.state.posture.mode == "seated":
			break
	_check(surface_walk_seen, "surface route walks along the app-owned support")
	_check(app.playground.phase == "attached" and app.playground.surface.mode == "sit" and app.state.posture.mode == "seated", "surface walk returns to a stable seated edge")
	_check(app.playground.last_support_error < 1.5, "surface walk keeps support contact after resitting")
	var window_id: int = shelf.get_window_id()
	app.playground.show_demo()
	_check(app.playground.shelf.get_window_id() == window_id, "repeated show reuses a single shelf")
	app._hard_stop()
	app.playground.begin_drag()
	var carried: Vector2i = root.position
	shelf.position.x += 35
	await process_frame
	_advance(3)
	_check(root.position == carried, "pickup suspends support following")
	app.playground.finish_drag()
	_advance(3)
	_check(app.playground.phase == "attached" and not app.walker.active(), "drop at shelf reattaches without old route")
	app._on_action(112)
	await process_frame
	await process_frame
	_advance(3)
	_check(app.playground.phase == "attached" and app.playground.last_support_error < 1.1, "avatar scaling preserves support")
	app._on_action(111)
	await process_frame
	await process_frame
	_advance(3)
	app._on_action(11)
	_advance(24)
	_check(app.playground.phase == "attached" and app.state.posture.mode == "seated", "pet does not detach shelf")
	app._on_action(10)
	_advance(28)
	_check(app.playground.last_support_error < 1.1, "wave does not shift seat anchor")
	await _capture("03_wave")
	_advance(140)
	app._on_action(12)
	_advance(100)
	_check(app.state.dozing and app.playground.phase == "attached", "dozing stays attached")
	await _capture("04_doze")
	app._on_action(12)
	_check(not app.state.dozing, "wake does not require standing")
	app._on_action(30)
	var walked: bool = false
	var overlap: bool = false
	for index in range(420):
		_advance(1)
		walked = walked or app.walker.active()
		overlap = overlap or (app.walker.active() and app.playground.active())
	_check(walked and not overlap, "walk waits for return and standing")
	_check(app.host.is_grounded() and app.state.posture.kind == "floor", "return ends at usable bottom in floor mode")
	_check(await _attach(), "shelf can be reused after walking")
	app._on_action(30)
	app._on_action(11)
	var resumed: bool = false
	for index in range(200):
		_advance(1)
		resumed = resumed or app.walker.active()
	_check(not resumed and not app.playground.active(), "pet cancels pending walk on return")
	_check(await _attach(), "shelf can be reused after canceled intent")
	shelf = app.playground.shelf
	shelf.mode = Window.MODE_MINIMIZED
	await process_frame
	await process_frame
	_advance(180)
	_check(not app.playground.active() and app.host.is_grounded(), "minimizing support safely returns avatar")
	_check(await _attach(), "minimized shelf can be reopened")
	app.playground.close_shelf()
	_advance(180)
	await process_frame
	_check(app.playground.shelf == null and not app.playground.active(), "closing support releases window reference")
	_check(app.host.is_grounded() and app.state.posture.mode == "standing", "closed shelf leaves standing avatar on floor")
	_check(await _attach(), "closed shelf can be recreated")
	app.stage.yaw = 60.0
	_advance(2)
	await _capture("05_side")
	var inside: bool = true
	for name in ["head", "hips", "leftHand", "rightHand", "leftFoot", "rightFoot"]:
		inside = inside and app.host.mask_contains(app.stage.camera.unproject_position(app.stage.rig.world_point(name)))
	_check(inside, "edge pose anchors fit native mouse/render mask")
	app.stage.yaw = 0.0
	var area: Rect2i = app.host.walking_area()
	app.playground.shelf.position.y = area.position.y + 15
	await process_frame
	_advance(200)
	_check(not app.playground.active() and app.host.is_grounded(), "unsafe support near screen top triggers return")
	app.playground.close_shelf()
	await process_frame
	_check(await _attach(), "recreate support after unsafe geometry")
	app._switch_mode(true)
	await process_frame
	_check(app.playground.shelf == null and not app.playground.active(), "preview switch frees shelf and cancels ownership")
	_check(app.host.preview and app.state.posture.kind == "floor" and app.state.posture.mode == "standing", "preview restores standing floor state")

func _capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--shelf-capture"):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var shelf = app.playground.shelf
	if not is_instance_valid(shelf):
		return
	var avatar_image: Image = root.get_texture().get_image()
	var shelf_image: Image = shelf.get_texture().get_image()
	avatar_image.convert(Image.FORMAT_RGBA8)
	shelf_image.convert(Image.FORMAT_RGBA8)
	var avatar_rect := Rect2i(root.position, avatar_image.get_size())
	var shelf_rect := Rect2i(shelf.position, shelf_image.get_size())
	var outer: Rect2i = shelf.outer_rect()
	var union: Rect2i = avatar_rect.merge(outer).merge(shelf_rect).grow(20)
	var canvas: Image = Image.create(union.size.x, union.size.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("e8e0ed"))
	# Native chrome is not a Viewport texture. Indicate its measured extent;
	# this is a labeled app-only composite, not a desktop screenshot.
	canvas.fill_rect(Rect2i(outer.position - union.position, outer.size), Color("cbbcd4"))
	canvas.fill_rect(Rect2i(outer.position - union.position, Vector2i(outer.size.x, 2)), Color("96749e"))
	canvas.blend_rect(shelf_image, Rect2i(Vector2i.ZERO, shelf_image.get_size()), shelf_rect.position - union.position)
	canvas.blend_rect(avatar_image, Rect2i(Vector2i.ZERO, avatar_image.get_size()), avatar_rect.position - union.position)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var result: Error = canvas.save_png(output.path_join(label + ".png"))
	_check(result == OK, "save app-only composite " + label)
	print("SHELF_COMPOSITE ", ProjectSettings.globalize_path(output.path_join(label + ".png")))
