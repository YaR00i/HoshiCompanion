extends Control

const Host = preload("res://scripts/desktop_host.gd")
const State = preload("res://scripts/companion_state.gd")
const Stage = preload("res://scripts/avatar_stage.gd")
const UI = preload("res://scripts/companion_ui.gd")
const Locomotion = preload("res://scripts/locomotion.gd")
const AirMotion = preload("res://scripts/air_motion.gd")
const Director = preload("res://scripts/behavior_director.gd")
const IntentPlanner = preload("res://scripts/intent_planner.gd")
const PlaceDirector = preload("res://scripts/place_director.gd")
const Playground = preload("res://scripts/shelf_playground.gd")
const InteractionSession = preload("res://scripts/interaction_session.gd")
const SETTINGS_PATH: String = "user://companion.cfg"
const DEFAULT_AVATAR: String = "res://assets/Hoshi_v1.vrm"

var host = Host.new()
var state = State.new()
var walker = Locomotion.new()
var air = AirMotion.new()
var director = Director.new()
var intent_planner = IntentPlanner.new()
var places = PlaceDirector.new()
var playground = Playground.new()
var interaction = InteractionSession.new()
var stage
var ui
var background: ColorRect
var frame_rate: int = 30
var _ready_to_run: bool = false
var _gaze: Vector2 = Vector2.ZERO
var _press_active: bool = false
var _dragged: bool = false
var _double_clicked: bool = false
var _press_cursor: Vector2i = Vector2i.ZERO
var _press_window: Vector2i = Vector2i.ZERO
var _press_yaw: float = 0.0
var _last_drag_cursor: Vector2i = Vector2i.ZERO
var _drag_velocity: Vector2 = Vector2.ZERO
var _hand_side: String = ""
var _hand_hold_age: float = 0.0
var _cursor_hanging: bool = false
var _quit_phase: String = ""
var _cinematic_mask_active: bool = false
var _preview_zoom: float = 1.0
var _ui_clock: float = 0.0
var _screen_clock: float = 0.0
var _input_alpha_clock: float = 0.0
var _walk_area: Rect2i = Rect2i()
var _walk_direction: int = 1
var _pending_action: String = ""
var _pending_auto: bool = false
var _rest_after_walk: bool = false
var _floor_intent_step_started: bool = false
var _floor_intent_wait: float = 4.0
var _surface_intent_step_started: bool = false
var _surface_step_wait: float = 0.0
var _surface_intent_wait: float = 5.0
var _test_mode: bool = false
var _settings: ConfigFile = ConfigFile.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.setup(get_window())
	var seed_value: int = 70420 if OS.get_cmdline_user_args().has("--test-mode") else int(Time.get_ticks_usec())
	state.seed_random(seed_value)
	director.seed_random(seed_value + 7)
	intent_planner.seed_random(seed_value + 17)
	_test_mode = OS.get_cmdline_user_args().has("--test-mode")
	_read_settings()
	director.set_activity(state.activity)
	places.change_mode(state.place_mode)
	Engine.max_fps = frame_rate
	background = ColorRect.new()
	background.color = Color("f3edf4")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	stage = Stage.new()
	stage.name = "AvatarStage"
	add_child(stage)
	ui = UI.new()
	ui.name = "CompanionUI"
	add_child(ui)
	playground.setup(self)
	ui.action_requested.connect(_on_action)
	ui.menu.popup_hide.connect(_on_menu_hidden)
	ui.bubbles_enabled = bool(_settings.get_value("behavior", "bubbles", true))
	get_window().close_requested.connect(_quit)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var wants_preview: bool = not args.has("--desktop") or args.has("--preview")
	_switch_mode(wants_preview)
	await get_tree().process_frame
	var avatar_path: String = DEFAULT_AVATAR
	for argument in args:
		if argument.begins_with("--avatar="):
			avatar_path = argument.trim_prefix("--avatar=")
	print("HOSHI_START version=0.7 engine=", Engine.get_version_info().get("string", ""))
	print("HOSHI_MODEL path=", avatar_path)
	print("HOSHI_DATA ", OS.get_user_data_dir())
	var result: Dictionary = stage.load_model(avatar_path)
	_write_diagnostics(avatar_path, result)
	if result.has("error"):
		push_error("HOSHI_LOAD_FAILED: " + str(result["error"]))
		_switch_mode(true)
		ui.show_error(str(result["error"]))
		return
	print("HOSHI_MODEL_READY status=", result.get("status", "ready"), " bones=", result.get("rig", {}).get("bones", 0), " meshes=", result.get("mesh_count", 0))
	_ready_to_run = true
	ui.model_ready(stage.model_name(), result)
	ui.refresh(state)
	_layout()
	if not host.preview and not _test_mode:
		_start_intro()
	ui.say("Привет, Серёж!")
	if args.has("--shelf-demo"):
		await get_tree().create_timer(0.5).timeout
		playground.show_demo()
	if args.has("--walk-demo"):
		await get_tree().create_timer(1.0).timeout
		_start_walk(false)
	if args.has("--capture"):
		_capture_after_settling()

func _switch_mode(preview: bool) -> void:
	var was_preview: bool = host.preview
	playground.release_for_mode_change()
	air.cancel(Vector2(host.window.position) if host.window != null else Vector2.ZERO)
	_press_active = false
	_dragged = false
	_hand_side = ""
	_hand_hold_age = 0.0
	_cursor_hanging = false
	interaction.cancel()
	state.cancel_pet_contact()
	state.cancel_release_reaction()
	state.end_cursor_hang()
	if stage != null:
		stage.cancel_cinematic()
		stage.clear_interaction_alpha()
		_hard_stop()
		stage.travel_offset_px = 0.0
	_input_alpha_clock = 0.0
	if _cinematic_mask_active:
		host.cinematic_mask(false)
		_cinematic_mask_active = false
	host.switch_mode(preview)
	ui.set_preview(host.preview)
	background.visible = host.preview
	if not host.preview:
		stage.yaw = 0.0
	_layout()
	_layout.call_deferred()
	if was_preview and not host.preview and _ready_to_run and not _test_mode:
		_start_intro()

func _layout() -> void:
	if stage == null:
		return
	stage.position = Vector2.ZERO
	stage.size = Vector2(560.0, 620.0) if host.preview else Vector2(host.window.size)
	stage.configure_frame(480.0 * _preview_zoom if host.preview else float(host.body_pixels), 38.0 if host.preview else 6.0)

func _process(delta: float) -> void:
	if not _ready_to_run:
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	interaction.tick(delta, _press_active or ui.menu.visible)
	_update_drag(dt)
	playground.before_tick(dt)
	var air_was_active: bool = air.active()
	var air_position: Vector2 = air.tick(dt)
	if air_was_active or air.active():
		host.place_at(air_position)
	_screen_clock += dt
	if walker.active() and not host.preview and _screen_clock >= 0.5:
		_screen_clock = 0.0
		# Floor routes are screen-bound; surface routes are relative to their support.
		if not playground.surface_walking() and host.walking_area() != _walk_area:
			_hard_stop()
			host.finish_drag()
	var was_walking: bool = walker.active()
	walker.tick(dt)
	if was_walking:
		stage.yaw = walker.yaw
		if host.preview:
			stage.travel_offset_px = walker.x_px
		elif playground.surface_walking():
			stage.travel_offset_px = 0.0
		elif not _dragged or not _press_active:
			stage.travel_offset_px = host.walk_to(walker.x_px)
		if not walker.active():
			if _rest_after_walk and state.rest_enabled and state.autonomy_enabled:
				_request_sit(true)
			_rest_after_walk = false
			_save_settings()
	_resolve_posture_intent()
	state.tick(dt, not _press_active and not ui.menu.visible and not walker.active())
	_resolve_posture_intent()
	var cursor: Vector2 = host.cursor_local() - stage.position
	var head: Vector2 = stage.head_pixel()
	var distance: float = cursor.distance_to(head)
	var cursor_gaze: Vector2 = (cursor - head) / maxf(1.0, stage.body_pixels * 0.95)
	cursor_gaze = cursor_gaze.clamp(Vector2(-1.0, -1.0), Vector2.ONE)
	director.enabled = state.autonomy_enabled
	director.walk_enabled = state.walk_enabled and state.motion_enabled
	director.rest_enabled = state.rest_enabled and state.motion_enabled and state.place_mode == "off"
	var control_blocked: bool = air.active() or stage.cinematic_active() or not _quit_phase.is_empty() or _press_active or ui.menu.visible or state.dozing or walker.active() or state.posture.transitioning() or not _pending_action.is_empty() or state.notice_weight > 0.1 or state.welcome_weight > 0.1 or state.pet_weight > 0.1 or state.wave_weight > 0.1 or state.release_reaction_active()
	var blocked: bool = playground.active() or control_blocked
	var place_request: String = places.tick(dt, state, {"blocked": blocked or host.preview, "can_place": not host.preview and host.is_grounded() and state.posture.mode == "standing"})
	if place_request == "cozy":
		blocked = playground.show_demo(true) or blocked
	elif place_request == "smart":
		blocked = playground.auto_choose_window() or blocked
	var preferred_side: String = playground.surface.available_side() if playground.active() else ""
	var surface_ready: bool = playground.active() and playground.phase == "attached" and not playground.surface_busy()
	var behavior_context: Dictionary = {"blocked": control_blocked or (playground.active() and not surface_ready), "cursor_gaze": cursor_gaze,
		"cursor_near": distance < stage.body_pixels * 1.8,
		"location": "surface" if playground.active() else "floor",
		"cozy": playground.active() and playground.cozy_mode,
		"quiet": state.activity == "quiet",
		"can_observe": state.look_enabled and not state.dozing,
		"can_social": not state.dozing,
		"can_walk": not playground.active() and not host.preview and host.is_grounded() and stage.gait.available and state.posture.mode == "standing",
		"can_rest": state.allows_autonomous_floor_rest() and not playground.active() and (host.preview or host.is_grounded()) and stage.posture_driver.available and state.posture.mode == "standing",
		"can_surface_walk": surface_ready and playground.surface.can_walk_route(),
		"can_surface_scoot": surface_ready and state.activity == "quiet" and playground.cozy_mode and playground.surface.can_scoot_route(),
		"can_side": surface_ready and not preferred_side.is_empty(),
		"preferred_side": preferred_side,
		"can_leave": surface_ready and not playground.cozy_mode}
	intent_planner.tick(dt, behavior_context)
	var active_intent_name: String = str(intent_planner.active_intent.get("name", ""))
	var surface_intent_active: bool = active_intent_name in ["explore_surface", "visit_side", "leave_support"]
	director.decisions_enabled = false
	director.tick(dt, behavior_context)
	if playground.active() or surface_intent_active:
		_tick_surface_intent(dt, behavior_context, cursor_gaze, distance < stage.body_pixels * 1.8)
	else:
		_tick_floor_intent(dt, behavior_context, cursor_gaze, distance < stage.body_pixels * 1.8)
	var target: Vector2 = Vector2.ZERO
	if state.look_enabled and not state.dozing and not ui.menu.visible and not walker.active() and absf(stage.yaw) < 55.0:
		target = director.gaze
		# Deliberate interaction briefly wins over independent attention.
		if state.pet_contact_active:
			target = Vector2.ZERO
		elif state.notice_weight > 0.1 or state.welcome_weight > 0.1 or state.pet_weight > 0.1 or state.wave_weight > 0.1:
			target = cursor_gaze if distance < 1000.0 else Vector2.ZERO
	_gaze = _gaze.lerp(target, 1.0 - exp(-dt * 6.0))
	state.curiosity = lerpf(state.curiosity, director.curiosity if state.motion_enabled and state.look_enabled else 0.0, 1.0 - exp(-dt * 5.0))
	var planner_scene_active: bool = not intent_planner.active_intent.is_empty()
	stage.idle_life.autonomous_enabled = not planner_scene_active or playground.active()
	stage.edge_life.autonomous_enabled = not planner_scene_active or not playground.active()
	stage.edge_suspended = _press_active or ui.menu.visible or (playground.active() and (playground.phase != "attached" or playground.surface_busy()))
	stage.cozy_corner_active = playground.active() and playground.cozy_mode and playground.phase == "attached"
	stage.edge_scoot = playground.surface.scoot_pose() if playground.active() else {}
	var context_action: String = "cursor_hang" if _cursor_hanging else ("carry" if _dragged and not host.preview else air.pose_mode())
	if context_action == "idle":
		context_action = playground.surface_context()
	var context_velocity: Vector2 = _drag_velocity if context_action in ["carry", "cursor_hang"] else (air.screen_velocity() if air.active() else Vector2.ZERO)
	var context_progress: float = clampf(float(_press_cursor.y - host.cursor_global().y) / maxf(stage.body_pixels * 0.60, 1.0), 0.0, 1.0) if context_action == "cursor_hang" else (air.pose_progress() if air.active() and context_action in ["jump", "fall", "land"] else -1.0)
	var context_impact: float = air.impact_strength() if air.active() and context_action in ["jump", "fall", "land"] else 0.5
	stage.set_context_action(context_action, context_velocity, context_progress, context_impact)
	stage.animate(dt, state, _gaze, walker.sample())
	if _cursor_hanging and not host.hang_hand_to(host.cursor_global(), stage.hand_pixel(_hand_side)):
		_end_cursor_hang()
	if not host.preview:
		_input_alpha_clock += dt
		if not stage.cinematic_active() and _input_alpha_clock >= 0.18:
			_input_alpha_clock = 0.0
			stage.refresh_interaction_alpha()
		var avatar_hit: bool = not stage.cinematic_active() and stage.visible_avatar_hit(cursor)
		host.update_pointer_interaction(avatar_hit, _press_active or ui.menu.visible)
	playground.after_tick()
	if _cinematic_mask_active and not stage.cinematic_active():
		host.cinematic_mask(false)
		_cinematic_mask_active = false
	if _quit_phase == "returning" and not playground.active() and not air.active() and state.posture.mode == "standing":
		_begin_outro()
	elif _quit_phase == "outro" and stage.outro_complete():
		_finalize_quit()
		return
	ui.shelf_active = playground.active()
	ui.tick(dt, stage.head_pixel() + stage.position, stage.size)
	_ui_clock += dt
	if _ui_clock >= 0.15:
		_ui_clock = 0.0
		var caption: String = playground.label() if playground.active() else walker.label()
		if host.preview and walker.mode == "walk":
			caption = "Проверяет походку в примерочной"
		if caption.is_empty() and playground.active():
			caption = stage.edge_life.label()
		if caption.is_empty() and not playground.active():
			caption = stage.idle_life.label()
		if caption.is_empty() and state.posture.mode != "standing":
			caption = state.state_label()
		if caption.is_empty() and not blocked and state.look_enabled:
			caption = director.attention_label
		if state.notice_weight > 0.1 or state.welcome_weight > 0.1 or state.pet_weight > 0.1 or state.release_reaction_active():
			caption = state.state_label()
		ui.refresh(state, caption, walker.active())

func _floor_intent_delay() -> float:
	match state.activity:
		"quiet": return 13.0
		"playful": return 5.0
	return 8.0

func _finish_floor_intent_step() -> void:
	_floor_intent_step_started = false
	var finished: String = intent_planner.complete_step()
	if not finished.is_empty() and intent_planner.active_intent.is_empty():
		_floor_intent_wait = _floor_intent_delay()

func _abort_autonomous_intent(reason: String) -> void:
	intent_planner.interrupt(reason)
	if playground.active():
		playground.surface.cancel_scoot()
	_floor_intent_step_started = false
	_surface_intent_step_started = false
	_surface_step_wait = 0.0
	_floor_intent_wait = maxf(_floor_intent_wait, 2.0)
	_surface_intent_wait = maxf(_surface_intent_wait, 2.0)

func _tick_floor_intent(delta: float, context: Dictionary, cursor_gaze: Vector2, cursor_near: bool) -> void:
	if playground.active():
		_floor_intent_step_started = false
		return
	if intent_planner.active_intent.is_empty():
		_floor_intent_step_started = false
		_floor_intent_wait = maxf(0.0, _floor_intent_wait - delta)
		if _floor_intent_wait > 0.0 or not state.autonomy_enabled or bool(context.get("blocked", false)):
			return
		var plan: Dictionary = intent_planner.choose(context, state.activity)
		if plan.is_empty() or not intent_planner.activate(plan):
			_floor_intent_wait = 1.0
			return
	var step: String = intent_planner.current_step()
	if step.is_empty():
		_abort_autonomous_intent("empty_step")
		return
	if not _floor_intent_step_started:
		match step:
			"walk":
				if not bool(context.get("can_walk", false)):
					_abort_autonomous_intent("walk_unavailable")
					return
				_start_walk(true, true)
				if not walker.active():
					_abort_autonomous_intent("walk_failed")
					return
				_floor_intent_step_started = true
			"look":
				if not bool(context.get("can_observe", false)):
					_abort_autonomous_intent("observe_unavailable")
					return
				director.request_observe(cursor_gaze, cursor_near)
				_floor_intent_step_started = true
			"sit":
				if not bool(context.get("can_rest", false)):
					_abort_autonomous_intent("rest_unavailable")
					return
				_request_sit(true)
				_floor_intent_step_started = true
			"wave":
				if not bool(context.get("can_social", false)):
					_abort_autonomous_intent("social_unavailable")
					return
				state.wave()
				_floor_intent_step_started = true
				_finish_floor_intent_step()
			"floor_peek_left", "floor_peek_right", "floor_weight_left", "floor_weight_right", "floor_hands", "floor_shoulders":
				var gesture_name: String = step.trim_prefix("floor_")
				if not stage.idle_life.request_gesture(gesture_name):
					_abort_autonomous_intent("floor_gesture_unavailable")
					return
				_floor_intent_step_started = true
			_:
				_abort_autonomous_intent("unsupported_floor_step")
		return
	match step:
		"walk":
			if not walker.active():
				_finish_floor_intent_step()
		"look":
			if not director.look_active():
				_finish_floor_intent_step()
		"sit":
			if state.posture.mode == "seated":
				_finish_floor_intent_step()
		"floor_peek_left", "floor_peek_right", "floor_weight_left", "floor_weight_right", "floor_hands", "floor_shoulders":
			if not stage.idle_life.forced_active():
				_finish_floor_intent_step()

func _surface_intent_delay() -> float:
	match state.activity:
		"quiet": return 16.0
		"playful": return 6.0
	return 10.0

func _finish_surface_intent_step() -> void:
	_surface_intent_step_started = false
	_surface_step_wait = 0.0
	var finished: String = intent_planner.complete_step()
	if not finished.is_empty() and intent_planner.active_intent.is_empty():
		_surface_intent_wait = _surface_intent_delay()

func _tick_surface_intent(delta: float, context: Dictionary, cursor_gaze: Vector2, cursor_near: bool) -> void:
	var active_name: String = str(intent_planner.active_intent.get("name", ""))
	if not playground.active() and active_name not in ["leave_support"]:
		if not intent_planner.active_intent.is_empty():
			_abort_autonomous_intent("support_lost")
		return
	if intent_planner.active_intent.is_empty():
		_surface_intent_step_started = false
		_surface_step_wait = 0.0
		_surface_intent_wait = maxf(0.0, _surface_intent_wait - delta)
		if _surface_intent_wait > 0.0 or not state.autonomy_enabled or not state.edge_activity in ["auto", "sway"] or stage.edge_life.forced_active() or bool(context.get("blocked", false)):
			return
		var plan: Dictionary = intent_planner.choose(context, state.activity)
		if plan.is_empty() or not intent_planner.activate(plan):
			_surface_intent_wait = 1.5
			return
	var step: String = intent_planner.current_step()
	if step.is_empty():
		_abort_autonomous_intent("empty_surface_step")
		return
	if not _surface_intent_step_started:
		match step:
			"surface_scoot":
				if not playground.active() or not playground.surface.request_scoot():
					_abort_autonomous_intent("surface_scoot_unavailable")
					return
				_surface_intent_step_started = true
			"surface_walk":
				if not playground.active() or not playground.surface.request_walk():
					_abort_autonomous_intent("surface_walk_unavailable")
					return
				_surface_intent_step_started = true
			"surface_settle":
				_surface_step_wait = 1.4 if state.activity == "playful" else (3.2 if state.activity == "quiet" else 2.2)
				_surface_intent_step_started = true
			"side_left", "side_right":
				var side_name: String = step.trim_prefix("side_")
				if not playground.active() or not playground.surface.request_side(side_name, false):
					_abort_autonomous_intent("side_unavailable")
					return
				_surface_intent_step_started = true
			"side_wait":
				_surface_step_wait = 4.0 if state.activity == "playful" else 5.5
				_surface_intent_step_started = true
			"side_return":
				if not playground.active() or not playground.surface.request_sit_top():
					_abort_autonomous_intent("side_return_failed")
					return
				_surface_intent_step_started = true
			"return_floor":
				if not playground.active():
					_finish_surface_intent_step()
					return
				playground.return_home()
				_surface_intent_step_started = true
			"look":
				if not bool(context.get("can_observe", true)):
					_abort_autonomous_intent("surface_observe_unavailable")
					return
				director.request_observe(cursor_gaze, cursor_near)
				_surface_intent_step_started = true
			"wave":
				state.wave()
				_surface_intent_step_started = true
				_finish_surface_intent_step()
			"edge_peek", "edge_balance", "edge_swing", "edge_lean", "edge_sway", "edge_hum", "edge_nod", "edge_sketch":
				var edge_gesture: String = step.trim_prefix("edge_")
				if not playground.active() or state.posture.mode != "seated" or (edge_gesture == "sketch" and not playground.cozy_mode) or not stage.edge_life.request_gesture(edge_gesture):
					_abort_autonomous_intent("edge_gesture_unavailable")
					return
				_surface_intent_step_started = true
			"floor_peek_left", "floor_peek_right", "floor_weight_left", "floor_weight_right", "floor_hands", "floor_shoulders":
				var floor_gesture: String = step.trim_prefix("floor_")
				if playground.active() or state.posture.mode != "standing" or not stage.idle_life.request_gesture(floor_gesture):
					_abort_autonomous_intent("return_gesture_unavailable")
					return
				_surface_intent_step_started = true
			_:
				_abort_autonomous_intent("unsupported_surface_step")
		return
	match step:
		"surface_walk", "surface_scoot":
			if playground.active() and playground.surface.mode == "sit" and state.posture.mode == "seated":
				_finish_surface_intent_step()
		"surface_settle", "side_wait":
			_surface_step_wait = maxf(0.0, _surface_step_wait - delta)
			if _surface_step_wait <= 0.0:
				_finish_surface_intent_step()
		"side_left", "side_right":
			if playground.active() and playground.surface.mode == step:
				_finish_surface_intent_step()
		"side_return":
			if playground.active() and playground.surface.mode == "sit" and state.posture.mode == "seated":
				_finish_surface_intent_step()
		"return_floor":
			if not playground.active() and state.posture.mode == "standing":
				_finish_surface_intent_step()
		"look":
			if not director.look_active():
				_finish_surface_intent_step()
		"edge_peek", "edge_balance", "edge_swing", "edge_lean", "edge_sway", "edge_hum", "edge_nod", "edge_sketch":
			if not stage.edge_life.forced_active():
				_finish_surface_intent_step()
		"floor_peek_left", "floor_peek_right", "floor_weight_left", "floor_weight_right", "floor_hands", "floor_shoulders":
			if not stage.idle_life.forced_active():
				_finish_surface_intent_step()

func _start_walk(automatic: bool, planner_owned: bool = false) -> void:
	if playground.active():
		if not automatic:
			playground.return_home(true)
		return
	if not _ready_to_run or walker.active():
		return
	if not stage.gait.available:
		if not automatic:
			ui.say("Ноги не подключены — проверь лог")
		return
	if not state.motion_enabled:
		if not automatic:
			ui.say("Сначала включи мягкие движения")
		return
	if state.posture.mode != "standing":
		_pending_action = "walk"
		_pending_auto = automatic
		state.sleep_requested = false
		state.dozing = false
		state.posture.request_stand()
		return
	if not host.preview and not host.is_grounded():
		if not automatic:
			ui.say("Сначала поставь меня к нижнему краю")
		return
	var start_x: float = stage.travel_offset_px if host.preview else float(host.window.position.x)
	var lane: Vector2 = Vector2(-140.0, 140.0) if host.preview else host.walking_lane()
	var right_room: float = lane.y - start_x
	var left_room: float = start_x - lane.x
	var span: float = 210.0 if host.preview else stage.body_pixels * (0.85 if state.activity == "playful" else 0.65)
	var chosen: int = _walk_direction
	if (chosen > 0 and right_room < stage.body_pixels * 0.15) or (chosen < 0 and left_room < stage.body_pixels * 0.15):
		chosen = -chosen
	if automatic:
		chosen = 1 if right_room > left_room else -1
	var target: float = start_x + float(chosen) * span
	var ok: bool = walker.request(start_x, target, lane, stage.meters_per_pixel(), stage.model_height, stage.yaw, state.activity == "playful")
	if not ok:
		if not automatic:
			ui.say("Здесь тесно для двух шагов")
		return
	_walk_direction = -chosen
	_rest_after_walk = automatic and state.rest_enabled and director.rest_after_walk and not planner_owned
	state.dozing = false
	if not planner_owned:
		director.user_interaction()
	_walk_area = host.walking_area()
	print("HOSHI_WALK start_px=", start_x, " target_px=", clampf(target, lane.x, lane.y), " steps=", walker.step_count, " mpp=", walker.meters_per_pixel, " preview=", host.preview)

func _stop_walk(keep_facing: bool = false) -> void:
	walker.stop(keep_facing)
	director.user_interaction()

func _hard_stop() -> void:
	if stage == null:
		return
	_abort_autonomous_intent("hard_stop")
	_clear_intent()
	state.posture.keep_rest()
	walker.reset(stage.travel_offset_px if host.preview else float(get_window().position.x), stage.yaw)
	if stage.gait != null:
		stage.gait.reset()
	director.user_interaction()

func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_run or not _quit_phase.is_empty() or stage.cinematic_active():
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		var local_point: Vector2 = button.position - stage.position
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			_open_menu()
			get_viewport().set_input_as_handled()
			return
		if not stage.get_rect().has_point(button.position):
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom(1)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom(-1)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed and stage.hit_avatar(local_point):
				_abort_autonomous_intent("pointer")
				_stop_walk()
				_clear_intent()
				state.posture.keep_rest()
				_press_active = true
				_dragged = false
				_hand_side = ""
				_hand_hold_age = 0.0
				_cursor_hanging = false
				_double_clicked = button.double_click
				_press_cursor = host.cursor_global()
				_press_window = get_window().position
				_press_yaw = stage.yaw
				_last_drag_cursor = _press_cursor
				_drag_velocity = Vector2.ZERO
				state.cancel_release_reaction()
				var on_head: bool = stage.head_contact_hit(local_point)
				if not on_head and not button.double_click and not host.preview and host.is_grounded() and not playground.active() and not air.active() and state.posture.mode == "standing" and not state.posture.transitioning() and state.wave_weight < 0.1:
					_hand_side = stage.hand_contact_side(local_point)
				if _hand_side.is_empty():
					interaction.begin(Vector2(_press_cursor), on_head, stage.body_pixels)
				else:
					interaction.cancel()
					interaction.manual_activity()
				if not on_head:
					state.cancel_pet_contact()
				if button.double_click and interaction.accept_wave():
					state.wave()
					if interaction.allow_bubble():
						ui.say("Привет-привет!")
			elif not button.pressed and _press_active:
				_finish_press()
	elif event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		match key_event.physical_keycode:
			KEY_ESCAPE:
				if walker.active():
					_on_action(31)
				elif host.preview:
					_quit()
			KEY_SPACE: _on_action(10)
			KEY_W: _on_action(30)
			KEY_C: _on_action(33 if state.posture.target_seated else 32)
			KEY_S: _on_action(12)
			KEY_F: _on_action(141)
			KEY_P: _switch_mode(not host.preview)

func _update_drag(delta: float) -> void:
	if not _press_active or host.headless:
		return
	var cursor_now: Vector2i = host.cursor_global()
	var movement: Vector2i = cursor_now - _press_cursor
	var frame_move: Vector2 = Vector2(cursor_now - _last_drag_cursor)
	_last_drag_cursor = cursor_now
	var pointer_local: Vector2 = host.cursor_local() - stage.position
	interaction.update(Vector2(cursor_now), delta, stage.head_stroke_zone_hit(pointer_local) if not _dragged else false)
	var instant_velocity: Vector2 = frame_move / maxf(delta, 0.001)
	_drag_velocity = _drag_velocity.lerp(instant_velocity, 1.0 - exp(-delta * 10.0))
	if not _hand_side.is_empty():
		_hand_hold_age += delta
		if _cursor_hanging and cursor_now.y > _press_cursor.y + 24:
			_end_cursor_hang()
			return
		if not _cursor_hanging and _hand_hold_age >= 0.16 and _press_cursor.y - cursor_now.y >= 12:
			_hard_stop()
			state.begin_cursor_hang()
			state.posture.request_stand()
			_cursor_hanging = true
			places.manual_pause()
		if (DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT) == 0:
			_finish_press()
		return
	if interaction.should_begin_drag():
		if not _dragged:
			# Carrying supersedes navigation and releases the body into a hanging pose.
			state.cancel_pet_contact()
			_hard_stop()
			air.cancel(Vector2(host.window.position))
			playground.begin_drag()
			state.dozing = false
			state.posture.request_stand()
			_dragged = true
	if not _dragged and not _double_clicked and interaction.petting_now():
		if not state.pet_contact_active:
			state.begin_pet_contact()
		var head_offset: Vector2 = (pointer_local - stage.head_pixel()) / maxf(stage.body_pixels * 0.18, 1.0)
		state.update_pet_contact(head_offset, delta)
	elif state.pet_contact_active:
		state.end_pet_contact()
	if _dragged:
		if host.preview:
			stage.yaw = clampf(_press_yaw + float(movement.x) * 0.4, -180.0, 180.0)
		else:
			stage.travel_offset_px = 0.0
			host.drag_to(_press_window + movement)
	if (DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT) == 0:
		_finish_press()

func _finish_press() -> void:
	if not _press_active:
		return
	_abort_autonomous_intent("pointer")
	if not _hand_side.is_empty():
		if _cursor_hanging:
			_end_cursor_hang()
		else:
			_press_active = false
			_hand_side = ""
			_hand_hold_age = 0.0
			if interaction.accept_palm_attention():
				state.notice()
		director.user_interaction()
		return
	var was_dragged: bool = _dragged
	var floor_goal: Vector2i = host.floor_position() if was_dragged and not host.preview else Vector2i.ZERO
	var drop_pixels: float = maxf(0.0, float(floor_goal.y - host.window.position.y)) if was_dragged and not host.preview else 0.0
	var release_style: String = interaction.release_style(_drag_velocity, drop_pixels) if was_dragged and not host.preview else ""
	var gesture: String = interaction.finish(was_dragged, _double_clicked, state.dozing)
	_press_active = false
	_dragged = false
	if state.pet_contact_active:
		state.end_pet_contact()
	if was_dragged:
		var support_handled: bool = playground.finish_drag()
		if not support_handled:
			if host.preview:
				host.finish_drag()
			else:
				state.dozing = false
				state.posture.request_stand()
				floor_goal = host.remember_floor_position()
				interaction.record_release(release_style)
				state.react_to_release(release_style)
				air.begin_fall(Vector2(host.window.position), Vector2(floor_goal), float(host.body_pixels), release_style)
		_drag_velocity = Vector2.ZERO
		_save_settings()
	elif gesture in ["attention", "pet", "wake", "return", "quiet"]:
		places.manual_pause()
		_clear_intent()
		playground.cancel_queued_walk()
		state.posture.keep_rest()
		if gesture == "pet":
			if interaction.allow_bubble():
				ui.say("М-м…")
		elif gesture in ["wake", "return"]:
			state.recognize()
		elif gesture == "attention":
			state.notice()
	director.user_interaction()

func _end_cursor_hang() -> void:
	var was_hanging: bool = _cursor_hanging
	_press_active = false
	_cursor_hanging = false
	state.end_cursor_hang()
	_hand_side = ""
	_hand_hold_age = 0.0
	_drag_velocity = Vector2.ZERO
	interaction.cancel()
	if not was_hanging or host.preview:
		return
	var floor: Vector2i = host.remember_floor_position()
	if host.window.position.y >= floor.y:
		host.place_at(Vector2(floor))
	else:
		air.begin_fall(Vector2(host.window.position), Vector2(floor), float(host.body_pixels))
	_save_settings()

func _zoom(direction: int) -> void:
	_hard_stop()
	if host.preview:
		_preview_zoom = clampf(_preview_zoom + float(direction) * 0.04, 0.75, 1.10)
		stage.travel_offset_px = clampf(stage.travel_offset_px, -130.0, 130.0)
	else:
		stage.travel_offset_px = 0.0
		host.resize_body(host.body_pixels + direction * 20)
	_layout()
	_save_settings()

func _open_menu() -> void:
	if _cursor_hanging:
		_end_cursor_hang()
	_abort_autonomous_intent("menu")
	places.manual_pause()
	playground.cancel_queued_walk()
	_clear_intent()
	state.posture.keep_rest()
	_press_active = false
	_hand_side = ""
	_hand_hold_age = 0.0
	interaction.cancel()
	interaction.manual_activity()
	state.cancel_pet_contact()
	_stop_walk()
	ui.refresh(state, walker.label(), walker.active())
	host.menu_focus(true)
	ui.menu.position = host.cursor_global()
	ui.menu.popup()

func _on_menu_hidden() -> void:
	host.menu_focus(false)
	director.user_interaction()

func _on_action(action: int) -> void:
	_abort_autonomous_intent("manual_action")
	if action == 199:
		_quit()
		return
	if action == 100:
		_switch_mode(true)
		return
	if not _ready_to_run:
		return
	interaction.manual_activity()
	if action in [10, 11, 12, 30, 31, 32, 33, 40, 41, 42, 43, 100, 101, 110, 111, 112, 140, 141, 305, 306, 307, 308, 313]:
		places.manual_pause()
	if action in [210, 211, 212]:
		state.place_mode = ["off", "cozy", "smart"][action - 210]
		places.change_mode(state.place_mode)
		ui.refresh(state, playground.label(), walker.active())
		_save_settings()
		return
	if action == 312:
		if playground.active() and playground.cozy_mode and playground.phase == "attached" and state.posture.mode == "seated" and state.motion_enabled and not state.dozing:
			stage.edge_life.request_gesture("sketch")
		return
	var edge_actions: Dictionary = {300: "auto", 301: "calm", 302: "swing", 303: "lean", 304: "peek", 309: "sway", 310: "hum", 311: "nod"}
	if edge_actions.has(action):
		stage.edge_life.cancel_forced()
		state.edge_activity = str(edge_actions[action])
		ui.refresh(state, playground.label(), walker.active())
		_save_settings()
		return
	if playground.handle_action(action):
		ui.shelf_active = playground.active()
		ui.refresh(state, playground.label(), walker.active())
		_save_settings()
		return
	if action not in [30, 32, 12]:
		_clear_intent()
		state.posture.keep_rest()
	if action not in [30, 31]:
		_stop_walk()
	director.user_interaction()
	match action:
		10:
			if interaction.accept_wave():
				state.wave()
				if interaction.allow_bubble():
					ui.say("Я тут!")
		11:
			if interaction.accept_button_pet():
				state.pet()
				if interaction.allow_bubble():
					ui.say("Спасибо!")
		12:
			if state.dozing or state.sleep_requested:
				var was_dozing: bool = state.dozing
				_clear_intent()
				if was_dozing:
					state.recognize()
				else:
					state.dozing = false
				state.posture.keep_rest()
				if was_dozing and interaction.allow_bubble():
					ui.say("Проснулась!")
			else:
				_request_sit(false, true)
		20: state.set_mood("neutral")
		21: state.set_mood("happy")
		22: state.set_mood("relaxed")
		23: state.set_mood("surprised")
		24: state.set_mood("sad")
		30: _start_walk(false)
		31: _stop_all_actions()
		32: _request_sit()
		33: _request_stand()
		101: _switch_mode(false)
		110, 111, 112:
			_hard_stop()
			stage.travel_offset_px = 0.0
			host.resize_body({110: 280, 111: 360, 112: 440}[action])
		120: state.look_enabled = not state.look_enabled
		121:
			state.motion_enabled = not state.motion_enabled
			if not state.motion_enabled:
				_hard_stop()
				if state.posture.transitioning():
					state.posture.request_stand()
		122: state.hair_enabled = not state.hair_enabled
		123: ui.bubbles_enabled = not ui.bubbles_enabled
		124:
			host.mask_enabled = not host.mask_enabled
			host.apply_mask()
		125: state.walk_enabled = not state.walk_enabled
		126: state.autonomy_enabled = not state.autonomy_enabled
		127: state.rest_enabled = not state.rest_enabled
		130:
			frame_rate = 60
			Engine.max_fps = 60
		131:
			frame_rate = 30
			Engine.max_fps = 30
		140:
			_hard_stop()
			stage.travel_offset_px = 0.0
			host.home()
		141:
			_hard_stop()
			stage.yaw = 0.0
			stage.travel_offset_px = 0.0
			_preview_zoom = 1.0
			_gaze = Vector2.ZERO
			stage.rig.reset()
		200, 201, 202:
			state.activity = ["quiet", "normal", "playful"][action - 200]
			director.set_activity(state.activity)
	_layout()
	ui.refresh(state, walker.label(), walker.active())
	_save_settings()

func _read_settings() -> void:
	if _test_mode or OS.get_cmdline_user_args().has("--reset"):
		return
	if _settings.load(SETTINGS_PATH) != OK:
		return
	host.body_pixels = clampi(int(_settings.get_value("window", "body_pixels", 360)), 240, 520)
	var stored_position: Variant = _settings.get_value("window", "position", Vector2i(-99999, -99999))
	if stored_position is Vector2i:
		host.saved_position = stored_position
	host.mask_enabled = bool(_settings.get_value("window", "mask_enabled", true))
	state.look_enabled = bool(_settings.get_value("behavior", "look", true))
	state.motion_enabled = bool(_settings.get_value("behavior", "motion", true))
	state.hair_enabled = bool(_settings.get_value("behavior", "hair", true))
	state.rest_enabled = bool(_settings.get_value("behavior", "rest", true))
	state.walk_enabled = bool(_settings.get_value("behavior", "walk", true))
	state.autonomy_enabled = bool(_settings.get_value("behavior", "autonomy", true))
	var place_mode: String = str(_settings.get_value("behavior", "place_mode", "off"))
	state.place_mode = place_mode if place_mode in ["off", "cozy", "smart"] else "off"
	var edge_activity: String = str(_settings.get_value("behavior", "edge_activity", "auto"))
	state.edge_activity = edge_activity if edge_activity in ["auto", "calm", "swing", "lean", "peek", "sway", "hum", "nod"] else "auto"
	var activity: String = str(_settings.get_value("behavior", "activity", "normal"))
	state.activity = activity if activity in ["quiet", "normal", "playful"] else "normal"
	frame_rate = 60 if int(_settings.get_value("render", "fps", 30)) == 60 else 30

func _save_settings() -> void:
	if host.headless or _test_mode:
		return
	_settings.set_value("window", "body_pixels", host.body_pixels)
	var saved_window: Vector2i = host.saved_position if host.preview or air.active() else get_window().position
	if playground.active():
		saved_window = playground.saved_floor_position
	_settings.set_value("window", "position", saved_window)
	_settings.set_value("window", "mask_enabled", host.mask_enabled)
	_settings.set_value("behavior", "look", state.look_enabled)
	_settings.set_value("behavior", "motion", state.motion_enabled)
	_settings.set_value("behavior", "hair", state.hair_enabled)
	_settings.set_value("behavior", "rest", state.rest_enabled)
	_settings.set_value("behavior", "walk", state.walk_enabled)
	_settings.set_value("behavior", "autonomy", state.autonomy_enabled)
	_settings.set_value("behavior", "place_mode", state.place_mode)
	_settings.set_value("behavior", "edge_activity", state.edge_activity)
	_settings.set_value("behavior", "activity", state.activity)
	_settings.set_value("behavior", "bubbles", ui.bubbles_enabled)
	_settings.set_value("render", "fps", frame_rate)
	var result: Error = _settings.save(SETTINGS_PATH)
	if result != OK:
		push_warning("Settings could not be saved: " + error_string(result))

func _write_diagnostics(avatar_path: String, result: Dictionary) -> void:
	var diagnostic: Dictionary = {"version": "0.7", "engine": Engine.get_version_info(),
		"model_path": avatar_path, "display_server": DisplayServer.get_name(), "load": result}
	print("HOSHI_LOAD_DIAGNOSTICS ", JSON.stringify(diagnostic))
	var file: FileAccess = FileAccess.open("user://avatar_diagnostics.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(diagnostic, "\t"))
		file.close()

func _capture_after_settling() -> void:
	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "user://hoshi_preview.png"
	var result: Error = image.save_png(path)
	print("HOSHI_CAPTURE ", ProjectSettings.globalize_path(path), " result=", result)

func _start_intro() -> void:
	if stage == null or host.preview:
		return
	stage.start_portal_intro()
	host.cinematic_mask(true)
	_cinematic_mask_active = true

func _quit() -> void:
	if not _quit_phase.is_empty():
		return
	if _cursor_hanging:
		_end_cursor_hang()
	if _ready_to_run and not host.preview and not _test_mode and stage != null:
		places.manual_pause(999.0)
		_clear_intent()
		_stop_walk()
		state.dozing = false
		if playground.active():
			_quit_phase = "returning"
			playground.return_home()
		elif air.active():
			_quit_phase = "returning"
			air.begin_fall(Vector2(host.window.position), Vector2(host.floor_position()), float(host.body_pixels))
		elif state.posture.mode != "standing":
			_quit_phase = "returning"
			state.posture.request_stand()
		else:
			_begin_outro()
		return
	_finalize_quit()

func _begin_outro() -> void:
	if _quit_phase == "outro":
		return
	_quit_phase = "outro"
	state.dozing = false
	state.posture.request_stand()
	stage.yaw = 0.0
	host.cinematic_mask(true)
	_cinematic_mask_active = true
	stage.start_portal_outro()
	ui.say("До скорого!")

func _finalize_quit() -> void:
	playground.release_for_mode_change()
	if _cinematic_mask_active:
		host.cinematic_mask(false)
		_cinematic_mask_active = false
	_save_settings()
	get_tree().quit()

func _clear_intent() -> void:
	_pending_action = ""
	_pending_auto = false
	_rest_after_walk = false
	state.sleep_requested = false

func _request_sit(automatic: bool = false, sleep_after: bool = false) -> void:
	if not stage.posture_driver.available or not state.motion_enabled:
		if not automatic:
			ui.say("Посадка сейчас недоступна")
		return
	if not host.preview and not host.is_grounded():
		if not automatic:
			ui.say("Сначала поставь меня к нижнему краю")
		return
	_clear_intent()
	_pending_action = "sleep" if sleep_after else "sit"
	_pending_auto = automatic
	state.sleep_requested = sleep_after
	state.dozing = false
	_stop_walk()

func _request_stand() -> void:
	_clear_intent()
	state.dozing = false
	state.posture.request_stand()
	director.user_interaction()

func _resolve_posture_intent() -> void:
	if playground.active():
		return
	if _pending_action.is_empty() or walker.active() or _press_active or ui.menu.visible:
		return
	if _pending_action == "walk":
		if state.posture.mode == "standing":
			var automatic: bool = _pending_auto
			_clear_intent()
			_start_walk(automatic)
		return
	if not state.posture.target_seated:
		state.posture.request_sit(_pending_auto, director.automatic_rest_duration() if _pending_auto else 45.0)
		director.rest_started()
	if not _pending_auto:
		state.posture.keep_rest()
	if _pending_action == "sit":
		_pending_action = ""
	elif _pending_action == "sleep" and state.posture.mode == "seated":
		state.dozing = true
		state.sleep_requested = false
		_pending_action = ""

func _stop_all_actions() -> void:
	_clear_intent()
	_stop_walk()
	state.posture.keep_rest()
	if state.posture.transitioning():
		state.posture.request_stand()

func _exit_tree() -> void:
	host.shutdown()
	playground.external.close()
