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
const SurfaceProbe = preload("res://scripts/window_surface_probe.gd")
const InteractionSession = preload("res://scripts/interaction_session.gd")
const ChatVoiceBridge = preload("res://scripts/chat_voice_bridge.gd")
const Commands = preload("res://scripts/hoshi_commands.gd")
const CommandRunner = preload("res://scripts/command_runner.gd")
const DesktopInput = preload("res://scripts/desktop_input.gd")
const CompanionSettings = preload("res://scripts/companion_settings.gd")
const SessionLifecycle = preload("res://scripts/session_lifecycle.gd")
const SupportPort = preload("res://scripts/support_port.gd")
const DEFAULT_AVATAR: String = "res://assets/Hoshi_v1.vrm"

var host = Host.new()
var surface_probe = SurfaceProbe.new()
var state = State.new()
var walker = Locomotion.new()
var air = AirMotion.new()
var director = Director.new()
var intent_planner = IntentPlanner.new()
var places = PlaceDirector.new()
var playground = Playground.new()
var interaction = InteractionSession.new()
var chat_voice_bridge = ChatVoiceBridge.new()
var runner = CommandRunner.new()
## Помощники coordinator'а (у каждого одна забота, см. docs/SKELETON_RU.md):
var desk_input = DesktopInput.new()        # мышь и клавиатура
var settings = CompanionSettings.new()     # сохранение настроек, свет
var lifecycle = SessionLifecycle.new()     # вход и уход через звёздную дверь
var support_port = SupportPort.new()       # что опорам можно попросить у Хоши
var stage
var ui
var background: ColorRect
var frame_rate: int = 30
var _ready_to_run: bool = false
var _gaze: Vector2 = Vector2.ZERO
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
var _surface_intent_wait: float = 5.0
var _test_mode: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	desk_input.setup(self)
	settings.setup(self)
	lifecycle.setup(self)
	support_port.setup(self)
	host.setup(get_window())
	var seed_value: int = 70420 if OS.get_cmdline_user_args().has("--test-mode") else int(Time.get_ticks_usec())
	state.seed_random(seed_value)
	director.seed_random(seed_value + 7)
	intent_planner.seed_random(seed_value + 17)
	_test_mode = OS.get_cmdline_user_args().has("--test-mode")
	settings.read()
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
	stage.set_light_position(settings.light_position)
	settings.apply_shading()
	ui = UI.new()
	ui.name = "CompanionUI"
	add_child(ui)
	ui.clickthrough_enabled = host.mask_enabled
	playground.setup(self)
	runner.setup(self)
	ui.action_requested.connect(_on_action)
	ui.light_position_changed.connect(settings.set_light_position)
	ui.shading_changed.connect(settings.set_shading)
	ui.menu.popup_hide.connect(_on_menu_hidden)
	ui.quick_menu.popup_hide.connect(_on_menu_hidden)
	ui.bubbles_enabled = settings.bubbles_enabled()
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
	stage.edge_life.paper_star_completed.connect(_on_paper_star_completed)
	print("HOSHI_MODEL_READY status=", result.get("status", "ready"), " bones=", result.get("rig", {}).get("bones", 0), " meshes=", result.get("mesh_count", 0))
	_ready_to_run = true
	if args.has("--chat-voice-bridge"):
		chat_voice_bridge.start()
	ui.model_ready(stage.model_name(), result)
	ui.refresh(state)
	_layout()
	if not host.preview and not _test_mode:
		lifecycle.start_intro()
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
	desk_input.reset()
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
	lifecycle.clear_mask()
	host.switch_mode(preview)
	ui.set_preview(host.preview)
	background.visible = host.preview
	if not host.preview:
		stage.yaw = 0.0
	_layout()
	_layout.call_deferred()
	if was_preview and not host.preview and _ready_to_run and not _test_mode:
		lifecycle.start_intro()

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
	chat_voice_bridge.tick(dt)
	stage.voice_level = chat_voice_bridge.level
	if surface_probe.status == "waiting":
		surface_probe.tick(dt)
		if surface_probe.status == "done":
			ui.show_surface_scan(surface_probe.result)
	settings.tick(dt)
	interaction.tick(delta, desk_input.press_active or ui.menu_open())
	desk_input.update_drag(dt)
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
		elif not desk_input.dragged or not desk_input.press_active:
			stage.travel_offset_px = host.walk_to(walker.x_px)
		if not walker.active():
			if _rest_after_walk and state.rest_enabled and state.autonomy_enabled:
				_request_sit(true)
			_rest_after_walk = false
			_save_settings()
	_resolve_posture_intent()
	state.tick(dt, not desk_input.press_active and not ui.menu_open() and not walker.active())
	_resolve_posture_intent()
	var cursor: Vector2 = host.cursor_local() - stage.position
	var head: Vector2 = stage.head_pixel()
	var distance: float = cursor.distance_to(head)
	var cursor_gaze: Vector2 = (cursor - head) / maxf(1.0, stage.body_pixels * 0.95)
	cursor_gaze = cursor_gaze.clamp(Vector2(-1.0, -1.0), Vector2.ONE)
	director.enabled = state.autonomy_enabled
	director.walk_enabled = state.walk_enabled and state.motion_enabled
	director.rest_enabled = state.rest_enabled and state.motion_enabled and state.place_mode == "off"
	var control_blocked: bool = air.active() or stage.cinematic_active() or not lifecycle.phase.is_empty() or desk_input.press_active or ui.menu_open() or state.dozing or walker.active() or state.posture.transitioning() or not _pending_action.is_empty() or state.notice_weight > 0.1 or state.welcome_weight > 0.1 or state.pet_weight > 0.1 or state.wave_weight > 0.1 or state.release_reaction_active()
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
	if state.look_enabled and not state.dozing and not ui.menu_open() and not walker.active() and absf(stage.yaw) < 55.0:
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
	stage.edge_suspended = desk_input.press_active or ui.menu_open() or (playground.active() and (playground.phase != "attached" or playground.surface_busy()))
	stage.cozy_corner_active = playground.active() and playground.cozy_mode and playground.phase == "attached"
	stage.edge_scoot = playground.surface.scoot_pose() if playground.active() else {}
	var context_action: String = "cursor_hang" if desk_input.cursor_hanging else ("carry" if desk_input.dragged and not host.preview else air.pose_mode())
	if context_action == "idle":
		context_action = playground.surface_context()
	var context_velocity: Vector2 = desk_input.drag_velocity if context_action in ["carry", "cursor_hang"] else (air.screen_velocity() if air.active() else Vector2.ZERO)
	var context_progress: float = clampf(float(desk_input.press_cursor.y - host.cursor_global().y) / maxf(stage.body_pixels * 0.60, 1.0), 0.0, 1.0) if context_action == "cursor_hang" else (air.pose_progress() if air.active() and context_action in ["jump", "fall", "land"] else -1.0)
	var context_impact: float = air.impact_strength() if air.active() and context_action in ["jump", "fall", "land"] else 0.5
	stage.set_context_action(context_action, context_velocity, context_progress, context_impact)
	stage.animate(dt, state, _gaze, walker.sample())
	if playground.cozy_mode and is_instance_valid(playground.shelf):
		playground.shelf.set_star_presenting(float(stage.edge_life.weights.get("admire_star", 0.0)) > 0.05)
	desk_input.tick_hang()
	if not host.preview:
		_input_alpha_clock += dt
		if not stage.cinematic_active() and _input_alpha_clock >= 0.18:
			_input_alpha_clock = 0.0
			stage.refresh_interaction_alpha()
		var avatar_hit: bool = not stage.cinematic_active() and stage.visible_avatar_hit(cursor)
		host.update_pointer_interaction(avatar_hit, desk_input.press_active or ui.menu_open())
	playground.after_tick()
	if lifecycle.tick():
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
	runner.reset_pause()
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
	# Шаг плана — это обычная команда из hoshi_commands.gd; как её запустить
	# и когда она закончена, знает command_runner.gd (тот же, что и для кнопок).
	if not _floor_intent_step_started:
		var reason: String = runner.start(step, "auto", {"where": "floor", "context": context, "cursor_gaze": cursor_gaze, "cursor_near": cursor_near})
		if not reason.is_empty():
			_abort_autonomous_intent(reason)
			return
		_floor_intent_step_started = true
		if runner.is_instant(step):
			_finish_floor_intent_step()
		return
	if runner.is_done(step, delta):
		_finish_floor_intent_step()

func _surface_intent_delay() -> float:
	match state.activity:
		"quiet": return 16.0
		"playful": return 6.0
	return 10.0

func _finish_surface_intent_step() -> void:
	_surface_intent_step_started = false
	runner.reset_pause()
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
		runner.reset_pause()
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
		var reason: String = runner.start(step, "auto", {"where": "surface", "context": context, "cursor_gaze": cursor_gaze, "cursor_near": cursor_near})
		if reason == CommandRunner.ALREADY_DONE:
			_finish_surface_intent_step()
			return
		if not reason.is_empty():
			_abort_autonomous_intent(reason)
			return
		_surface_intent_step_started = true
		if runner.is_instant(step):
			_finish_surface_intent_step()
		return
	if runner.is_done(step, delta):
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

func _on_menu_hidden() -> void:
	_finish_menu_close.call_deferred()

func _finish_menu_close() -> void:
	if ui.menu_open():
		return
	host.menu_focus(false)
	director.user_interaction()

func _on_paper_star_completed() -> void:
	playground.add_cozy_star()

## Единая точка входа для команд по имени (см. hoshi_commands.gd).
## Старые числовые номера пока принимаются для совместимости.
func run_command(command: Variant) -> void:
	_on_action(command)

func _on_action(command: Variant) -> void:
	var action: String = Commands.resolve(command)
	if action.is_empty():
		push_warning("Unknown Hoshi command: %s" % str(command))
		return
	if not Commands.allows(action, "user"):
		push_warning("Hoshi command %s is not available from the menu or remote" % action)
		return
	_abort_autonomous_intent("manual_action")
	if action == "quit":
		_quit()
		return
	if action == "open_preview":
		_switch_mode(true)
		return
	if not _ready_to_run:
		return
	if action == "light_editor":
		ui.show_light_editor(settings.light_position, settings.shading)
		return
	if action == "talk_voice":
		chat_voice_bridge.start()
		OS.shell_open("https://chatgpt.com/")
		return
	if action == "talk_text":
		OS.shell_open("https://chatgpt.com/")
		return
	if action in ["scan_window_structure", "scan_window_visual"]:
		var visual: bool = action == "scan_window_visual"
		ui.surface_window.hide()
		if surface_probe.begin("visual" if visual else "structure"):
			ui.say("Наведи на окно · кадр через 4 с" if visual else "Наведи на окно · структура через 4 с")
			ui._bubble_left = 5.0
		else:
			ui.show_surface_scan(surface_probe.result)
		return
	if action == "light_reset":
		settings.reset_light()
		return
	interaction.manual_activity()
	if Commands.has_flag(action, "pauses_places"):
		places.manual_pause()
	if action in Commands.PLACE_CHOICES:
		state.place_mode = ["off", "cozy", "smart"][Commands.PLACE_CHOICES.find(action)]
		places.change_mode(state.place_mode)
		ui.refresh(state, playground.label(), walker.active())
		_save_settings()
		return
	if action in ["edge_sketch", "edge_fold", "edge_admire_star"]:
		runner.start(action, "user")
		return
	if not Commands.edge_activity(action).is_empty():
		stage.edge_life.cancel_forced()
		state.edge_activity = Commands.edge_activity(action)
		ui.refresh(state, playground.label(), walker.active())
		_save_settings()
		return
	if action in CommandRunner.USER_SUPPORT_COMMANDS:
		var support_reason: String = runner.start(action, "user")
		if support_reason.is_empty() or playground.active() or action == "return_floor":
			ui.shelf_active = playground.active()
			ui.refresh(state, playground.label(), walker.active())
			_save_settings()
			return
	if playground.handle_action(action):
		ui.shelf_active = playground.active()
		ui.refresh(state, playground.label(), walker.active())
		_save_settings()
		return
	if not Commands.has_flag(action, "keeps_intent"):
		_clear_intent()
		state.posture.keep_rest()
	if not Commands.has_flag(action, "keeps_walk"):
		_stop_walk()
	director.user_interaction()
	match action:
		"wave": runner.start("wave", "user")
		"pet":
			if interaction.accept_button_pet():
				state.pet()
				if interaction.allow_bubble():
					ui.say("Спасибо!")
		"doze":
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
		"mood_neutral": state.set_mood("neutral")
		"mood_happy": state.set_mood("happy")
		"mood_relaxed": state.set_mood("relaxed")
		"mood_surprised": state.set_mood("surprised")
		"mood_sad": state.set_mood("sad")
		"walk": runner.start("walk", "user")
		"stop": _stop_all_actions()
		"sit": runner.start("sit", "user")
		"stand": _request_stand()
		"to_desktop": _switch_mode(false)
		"size_small", "size_normal", "size_large":
			_hard_stop()
			stage.travel_offset_px = 0.0
			host.resize_body({"size_small": 280, "size_normal": 360, "size_large": 440}[action])
		"toggle_look": state.look_enabled = not state.look_enabled
		"toggle_motion":
			state.motion_enabled = not state.motion_enabled
			if not state.motion_enabled:
				_hard_stop()
				if state.posture.transitioning():
					state.posture.request_stand()
		"toggle_hair": state.hair_enabled = not state.hair_enabled
		"toggle_bubbles": ui.bubbles_enabled = not ui.bubbles_enabled
		"toggle_clickthrough":
			host.mask_enabled = not host.mask_enabled
			host.apply_mask()
			ui.clickthrough_enabled = host.mask_enabled
		"toggle_auto_walk": state.walk_enabled = not state.walk_enabled
		"toggle_autonomy": state.autonomy_enabled = not state.autonomy_enabled
		"toggle_auto_rest": state.rest_enabled = not state.rest_enabled
		"fps_60":
			frame_rate = 60
			Engine.max_fps = 60
		"fps_30":
			frame_rate = 30
			Engine.max_fps = 30
		"return_bottom":
			_hard_stop()
			stage.travel_offset_px = 0.0
			host.home()
		"reset_view":
			_hard_stop()
			stage.yaw = 0.0
			stage.travel_offset_px = 0.0
			_preview_zoom = 1.0
			_gaze = Vector2.ZERO
			stage.rig.reset()
		"activity_quiet", "activity_normal", "activity_playful":
			state.activity = ["quiet", "normal", "playful"][Commands.ACTIVITY_CHOICES.find(action)]
			director.set_activity(state.activity)
	_layout()
	ui.refresh(state, walker.label(), walker.active())
	_save_settings()

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
	if _pending_action.is_empty() or walker.active() or desk_input.press_active or ui.menu_open():
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
	chat_voice_bridge.stop()
	host.shutdown()
	playground.external.close()
	surface_probe.close()

# --- Тонкие переходники: старые имена, которыми пользуются опоры и тесты ---

## Нажатие мышью сейчас активно (читают shelf_playground/surface_controller).
var _press_active: bool:
	get:
		return desk_input.press_active

func _unhandled_input(event: InputEvent) -> void:
	desk_input.handle(event)

func _open_menu() -> void:
	desk_input.open_menu()

func _save_settings() -> void:
	settings.save()

func _quit() -> void:
	lifecycle.request_quit()

static func clickthrough_setting(config: ConfigFile) -> bool:
	return CompanionSettings.clickthrough_setting(config)
