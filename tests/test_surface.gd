extends SceneTree
const Surface = preload("res://scripts/surface_controller.gd")
const Stage = preload("res://scripts/avatar_stage.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var area := Rect2i(-1920, 0, 1920, 1080)
	var support := Rect2i(-1500, 500, 760, 360)
	var viewport := Vector2i(352, 426)
	var feet := Vector2(176, 390)
	var lane: Vector2 = Surface.top_lane(support, feet, viewport, area)
	check(lane.y > lane.x + 300.0, "top lane keeps usable walking span on negative-coordinate monitor")
	var standing: Dictionary = Surface.solve_top(support, lane.x + 80.0, feet, viewport, area)
	check(bool(standing.get("ok", false)), "standing placement fits above support")
	if bool(standing.get("ok", false)):
		check(absf((Vector2(standing["position"]) + feet).y - float(support.position.y + 2)) < 0.1, "standing foot anchor touches support top")
	var too_high := Rect2i(-1500, 20, 760, 280)
	check(not Surface.solve_top(too_high, 200.0, feet, viewport, area).get("ok", false), "top route rejects hidden avatar geometry")
	var valid_plan: Dictionary = Surface.plan_route(support, lane.x + 80.0, feet, viewport, area, 360.0, 0.004, 1.5, true)
	check(valid_plan.get("ok", false) and absf(float(valid_plan["target"]) - float(valid_plan["start"])) > 45.0, "surface planner validates a meaningful route before standing")
	check(not Surface.plan_route(too_high, 200.0, feet, viewport, area, 360.0, 0.004, 1.5).get("ok", false), "surface planner rejects impossible top placement before standing")
	var side_rect := Rect2i(-1200, 220, 720, 760)
	var left_contact := Vector2(255, 135)
	var right_contact := Vector2(95, 135)
	check(Surface.solve_side(side_rect, "left", left_contact, viewport, area).get("ok", false), "left vertical edge accepts floor-supported lean")
	check(Surface.solve_side(side_rect, "right", right_contact, viewport, area).get("ok", false), "right vertical edge accepts floor-supported lean")
	var short_side := Rect2i(-1200, 100, 720, 160)
	check(not Surface.solve_side(short_side, "left", left_contact, viewport, area).get("ok", false), "side lean rejects edge that does not reach shoulder height")

	var stage := Stage.new()
	stage.size = Vector2(560, 620)
	root.add_child(stage)
	await process_frame
	var result: Dictionary = stage.load_model("res://assets/Hoshi_v1.vrm")
	check(not result.has("error"), "real Hoshi loads for surface anchors")
	if not result.has("error"):
		var foot_pixel: Vector2 = stage.standing_anchor_pixel()
		var left_pixel: Vector2 = stage.side_anchor_pixel("left")
		var right_pixel: Vector2 = stage.side_anchor_pixel("right")
		check(foot_pixel.is_finite() and foot_pixel.y > stage.size.y * 0.5, "standing anchor resolves near Hoshi's feet")
		check(left_pixel.is_finite() and right_pixel.is_finite() and left_pixel.x > right_pixel.x, "side anchors resolve to opposite body sides")
		var rests: Array[Transform3D] = []
		for bone in range(stage.rig.skeleton.get_bone_count()):
			rests.append(stage.rig.skeleton.get_bone_rest(bone))
		var state = load("res://scripts/companion_state.gd").new()
		state.autonomy_enabled = false
		for mode in ["side_left", "side_right"]:
			stage.set_context_action(mode)
			for i in range(45):
				state.tick(1.0 / 30.0)
				stage.animate(1.0 / 30.0, state, Vector2.ZERO)
			check(stage.rig.world_point("head").is_finite(), mode + " lean keeps real rig finite")
		var unchanged: bool = true
		for bone in range(stage.rig.skeleton.get_bone_count()):
			unchanged = unchanged and stage.rig.skeleton.get_bone_rest(bone).is_equal_approx(rests[bone])
		check(unchanged, "side lean never edits authored REST transforms")
	stage.queue_free()
	await process_frame
	print("HOSHI_SURFACE_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
