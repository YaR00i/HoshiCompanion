extends "res://tests/test_shelf.gd"
## Native app-owned cozy-window acceptance. No external application capture.

func _run() -> void:
	output = "res://.workspace/screenshots/cozy_06"
	if DisplayServer.get_name() != "Windows":
		print("HOSHI_COZY_RESULT checks=0 failures=0 native_windows=false")
		quit(0)
		return
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for i in range(20):
		await process_frame
		if app._ready_to_run: break
	_check(app._ready_to_run, "real avatar loads for cozy corner")
	if not app._ready_to_run:
		quit(1)
		return
	app.set_process(false)
	app.ui.bubbles_enabled = false
	app._switch_mode(false)
	app.state.activity = "quiet"
	app.director.set_activity("quiet")
	app.state.place_mode = "cozy"
	app.places.change_mode("cozy")
	app.state.edge_activity = "auto"
	app.state.autonomy_enabled = true
	var floor_sit_seen: bool = false
	var previous_boarding_position: Vector2i = root.position
	var max_boarding_sit_step: float = 0.0
	for i in range(20):
		for frame in range(30):
			_advance(1)
			if app.playground.phase == "boarding" and app.state.posture.target_seated and not app.air.active():
				max_boarding_sit_step = maxf(max_boarding_sit_step, Vector2(root.position - previous_boarding_position).length())
			previous_boarding_position = root.position
		floor_sit_seen = floor_sit_seen or (app.state.posture.kind == "floor" and app.state.posture.target_seated)
		await process_frame
		if app.playground.phase == "attached":
			break
	_check(app.places.requests == 1 and app.playground.phase == "attached" and not floor_sit_seen, "quiet startup reaches its cozy place before any floor sit")
	_check(max_boarding_sit_step <= 2.0, "boarding keeps one seat contact while sitting down")
	app.state.autonomy_enabled = false
	app.state.edge_activity = "calm"
	var accepted: bool = app.playground.show_demo(true)
	await process_frame
	await process_frame
	_advance(130)
	_check(accepted and app.playground.phase == "attached", "cozy corner docks avatar")
	var cozy = app.playground.shelf
	_check(app.playground.cozy_mode and is_instance_valid(cozy), "cozy support owns a distinct window")
	_check(cozy.borderless and cozy.transparent_bg and cozy.size == Vector2i(460, 170), "cozy window uses compact transparent frame")
	_check(app.playground.last_support_error < 1.1, "cozy seat contact stays within one pixel")
	await _capture("01_calm")
	var corner_id: int = cozy.get_window_id()
	app._open_menu()
	app._on_action(43)
	app.ui.menu.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	_advance(3)
	var corner_image: Image = cozy.get_texture().get_image()
	_check(app.playground.phase == "attached" and app.playground.shelf == cozy and cozy.get_window_id() == corner_id and cozy.visible and cozy.mode == Window.MODE_WINDOWED and corner_image.get_pixel(100, 50).a > 0.9, "reselecting cozy corner from menu keeps existing viewport content")
	var original_corner_position: Vector2i = cozy.position
	var all_screen_bounds: Rect2i = app.host.usable_area(0)
	for screen in range(1, DisplayServer.get_screen_count()):
		all_screen_bounds = all_screen_bounds.merge(app.host.usable_area(screen))
	cozy.position = all_screen_bounds.end + Vector2i(800, 800)
	app._on_action(43)
	_advance(3)
	var corner_visible_on_screen: bool = false
	for screen in range(DisplayServer.get_screen_count()):
		corner_visible_on_screen = corner_visible_on_screen or Rect2(app.host.usable_area(screen)).intersects(Rect2(cozy.outer_rect()))
	_check(corner_visible_on_screen and app.playground.phase == "attached", "reselecting a visually lost cozy corner brings it back on screen")
	cozy.position = original_corner_position
	_advance(3)
	cozy.mode = Window.MODE_MINIMIZED
	app._on_action(43)
	await process_frame
	_advance(3)
	_check(app.playground.phase == "attached" and app.state.posture.mode == "seated" and cozy.visible and cozy.mode == Window.MODE_WINDOWED, "reselecting a minimized cozy corner restores it without making Hoshi stand")
	var calm_hand_rotations: Array[Quaternion] = []
	var calm_hand_local_rotations: Array[Quaternion] = []
	for arm in app.stage.posture_driver.arms:
		calm_hand_rotations.append(app.stage.rig.skeleton.get_bone_global_pose(int(arm["end"])).basis.get_rotation_quaternion())
		calm_hand_local_rotations.append(app.stage.rig.skeleton.get_bone_pose_rotation(int(arm["end"])))
	# Quiet autonomous movement on the app-owned corner should stay seated.
	app.state.edge_activity = "sway"
	app.state.autonomy_enabled = true
	var quiet_context: Dictionary = {"location": "surface", "cozy": true, "quiet": true, "blocked": false,
		"can_surface_walk": app.playground.surface.can_walk_route(), "can_surface_scoot": app.playground.surface.can_scoot_route()}
	var quiet_plan: Dictionary = app.intent_planner.build_plan("explore_surface", quiet_context, "quiet")
	_check(not quiet_plan.is_empty() and (quiet_plan.get("steps", []) as Array).has("surface_scoot"), "quiet cozy exploration plans a seated scoot")
	if not quiet_plan.is_empty():
		app.intent_planner.activate(quiet_plan)
		_advance(1)
		_check(app.state.posture.target_seated and app.playground.surface.mode == "scoot" and not app.walker.active(), "quiet cozy movement begins without standing or gait")
	app.state.autonomy_enabled = false
	var scoot_origin: Vector2i = root.position
	var scoot_previous: Vector2i = root.position
	var scoot_max_step: float = 0.0
	var scoot_stayed_seated: bool = true
	for i in range(120):
		_advance(1)
		scoot_max_step = maxf(scoot_max_step, Vector2(root.position - scoot_previous).length())
		scoot_previous = root.position
		scoot_stayed_seated = scoot_stayed_seated and app.state.posture.target_seated and app.state.posture.mode == "seated" and not app.walker.active()
		if i == 22:
			var brace_side: int = 1 if float(app.playground.surface.scoot_pose().get("direction", 0.0)) > 0.0 else 0
			var hand_id: int = int(app.stage.posture_driver.arms[brace_side]["end"])
			var brace_rotation: Quaternion = app.stage.rig.skeleton.get_bone_global_pose(hand_id).basis.get_rotation_quaternion()
			var side_name: String = "left" if brace_side == 0 else "right"
			var skel: Skeleton3D = app.stage.rig.skeleton
			var rest_hand: Transform3D = skel.get_bone_global_rest(hand_id)
			var index_id: int = int(app.stage.rig.bones[side_name + "IndexProximal"])
			var little_id: int = int(app.stage.rig.bones[side_name + "LittleProximal"])
			var index_local: Vector3 = rest_hand.affine_inverse() * skel.get_bone_global_rest(index_id).origin
			var little_local: Vector3 = rest_hand.affine_inverse() * skel.get_bone_global_rest(little_id).origin
			var arm: Dictionary = app.stage.posture_driver.arms[brace_side]
			var palm_normal: Vector3 = brace_rotation * index_local.cross(little_local).normalized()
			var wrist_height: float = skel.get_bone_global_pose(hand_id).origin.y - app.stage.edge_pose.seat_point.y
			var rest_hand_q: Quaternion = skel.get_bone_rest(hand_id).basis.get_rotation_quaternion()
			var wrist_local_angle: float = rad_to_deg(rest_hand_q.angle_to(skel.get_bone_pose_rotation(hand_id)))
			var calm_wrist_angle: float = rad_to_deg(rest_hand_q.angle_to(calm_hand_local_rotations[brace_side]))
			_check(rad_to_deg(calm_hand_rotations[brace_side].angle_to(brace_rotation)) >= 20.0, "bracing palm turns away from its resting angle on the knee")
			_check(palm_normal.dot(Vector3.UP) < 0.5 and wrist_height < 0.08, "bracing palm turns toward the shelf edge and reaches near its top")
			_check(wrist_local_angle <= calm_wrist_angle + 15.0, "scoot does not bend the wrist further than its seated pose")
			await _capture("01_scoot_push")
			app.stage.yaw = -45.0
			app.stage.animate(0.0, app.state, Vector2.ZERO, app.walker.sample())
			await _capture("01_scoot_three_quarter")
			app.stage.yaw = 0.0
			app.stage.animate(0.0, app.state, Vector2.ZERO, app.walker.sample())
		if app.playground.surface.mode == "sit" and app.state.posture.mode == "seated":
			break
	_check(scoot_stayed_seated and app.playground.surface.mode == "sit", "seated scoot completes without standing")
	_check(absf(float(root.position.x - scoot_origin.x)) >= 18.0 and scoot_max_step <= 4.0 and app.playground.last_support_error < 1.1, "seated scoot travels smoothly while holding its edge contact")
	await _capture("01_scoot_settle")
	app._on_action(313)
	var interrupted_scoot: bool = app.playground.surface.mode == "scoot"
	_advance(25)
	if interrupted_scoot:
		var second_side: int = 1 if float(app.playground.surface.scoot_pose().get("direction", 0.0)) > 0.0 else 0
		var second_arm: Dictionary = app.stage.posture_driver.arms[second_side]
		var second_hand: int = int(second_arm["end"])
		var second_skel: Skeleton3D = app.stage.rig.skeleton
		var second_rotation: Quaternion = second_skel.get_bone_global_pose(second_hand).basis.get_rotation_quaternion()
		_check(rad_to_deg(calm_hand_rotations[second_side].angle_to(second_rotation)) >= 20.0, "opposite hand also turns when the scoot reverses")
		var second_rest_q: Quaternion = second_skel.get_bone_rest(second_hand).basis.get_rotation_quaternion()
		var second_wrist_angle: float = rad_to_deg(second_rest_q.angle_to(second_skel.get_bone_pose_rotation(second_hand)))
		var second_calm_angle: float = rad_to_deg(second_rest_q.angle_to(calm_hand_local_rotations[second_side]))
		_check(second_wrist_angle <= second_calm_angle + 15.0, "reverse scoot also keeps its wrist near the seated bend")
	app._abort_autonomous_intent("manual_contact")
	var interrupted_position: Vector2i = root.position
	_advance(80)
	_check(interrupted_scoot and app.playground.surface.mode == "sit" and root.position.distance_to(interrupted_position) <= 1.0, "manual interruption stops the seated route without resuming it")
	app._abort_autonomous_intent("test_finished")
	var seat: Vector3 = app.stage.edge_pose.anchor_world()
	app._on_action(312)
	_advance(120)
	_check(float(app.stage.edge_life.weights["sketch"]) > 0.9 and app.stage.sketchbook.visible, "notebook button starts drawing in the cozy corner")
	_check(app.stage.edge_pose.anchor_world().distance_to(seat) < 0.001, "notebook keeps the corner seat steady")
	var partial_strokes: int = 0
	for stroke in app.stage.sketchbook.star_strokes:
		if stroke.visible: partial_strokes += 1
	_check(partial_strokes > 0 and partial_strokes < 5, "the star develops in separate strokes")
	var drawing_height: float = app.stage.sketchbook.position.y
	await _capture("01_sketch_drawing")
	app.stage.yaw = 65.0
	_advance(1)
	await _capture("01_sketch_side")
	app.stage.yaw = 0.0
	_advance(145)
	var complete_strokes: int = 0
	for stroke in app.stage.sketchbook.star_strokes:
		if stroke.visible: complete_strokes += 1
	_check(complete_strokes == 5 and app.stage.sketchbook.position.y > drawing_height + app.stage.model_height * 0.1, "finished star rises as Hoshi shows the page")
	await _capture("01_sketch_show")
	app.stage.edge_suspended = true
	app.stage.animate(1.0 / 30.0, app.state, Vector2.ZERO)
	_check(not app.stage.sketchbook.visible, "manual contact hides the notebook immediately")
	app.stage.edge_suspended = false
	app._on_action(302)
	_advance(120)
	_check(app.state.edge_activity == "swing" and float(app.stage.edge_life.weights["swing"]) > 0.9, "cozy button selects dangling legs")
	_check(not app.stage.sketchbook.visible, "another activity puts notebook away")
	await _capture("02_swing")
	app._on_action(303)
	_advance(120)
	_check(app.state.edge_activity == "lean" and float(app.stage.edge_life.weights["lean"]) > 0.9, "cozy button selects lean-back pose")
	await _capture("03_lean")
	var before: Vector2i = root.position
	cozy.position += Vector2i(60, 10)
	await process_frame
	_advance(3)
	_check((Vector2(root.position - before) - Vector2(60, 10)).length() < 1.5, "avatar follows cozy corner movement")
	app.playground.return_home()
	_advance(190)
	_check(not app.playground.active() and is_instance_valid(cozy) and cozy.visible, "cozy corner remains available after returning to floor")
	var drop_point: Vector2 = Vector2(cozy.outer_rect().position) + Vector2(float(cozy.outer_rect().size.x) * 0.5, 0.0)
	var reused: bool = app.playground.finish_drag_at(drop_point)
	await process_frame
	_advance(130)
	_check(reused and app.playground.phase == "attached" and app.playground.cozy_mode and app.playground.shelf == cozy and not cozy.is_queued_for_deletion(), "dropping from floor onto cozy corner reuses its borderless window")
	app.playground.close_shelf()
	await process_frame
	_advance(190)
	_check(not app.playground.active() and app.host.is_grounded(), "closing cozy corner returns avatar safely")
	_check(app.playground.auto_choose_window(OS.get_process_id()), "smart rest can start bounded automatic search")
	var deadline: int = Time.get_ticks_msec() + 5000
	while app.playground.phase != "attached" and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
		app._process(0.05)
	_check(app.playground.phase == "attached" and app.playground.cozy_mode, "no suitable candidate falls back to cozy corner")
	app.playground.return_home()
	_advance(190)
	app._switch_mode(true)
	app.queue_free()
	await process_frame
	print("HOSHI_COZY_RESULT checks=", checks, " failures=", failures, " native_windows=true")
	quit(0 if failures == 0 else 1)
