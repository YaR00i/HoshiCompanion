extends Control

const Host = preload("res://scripts/desktop_host.gd")
const State = preload("res://scripts/companion_state.gd")
const Stage = preload("res://scripts/avatar_stage.gd")
const UI = preload("res://scripts/companion_ui.gd")
const Locomotion = preload("res://scripts/locomotion.gd")
const AirMotion = preload("res://scripts/air_motion.gd")
const Director = preload("res://scripts/behavior_director.gd")
const PlaceDirector = preload("res://scripts/place_director.gd")
const Playground = preload("res://scripts/shelf_playground.gd")
const SETTINGS_PATH: String = "user://companion.cfg"
const DEFAULT_AVATAR: String = "res://assets/Hoshi_v1.vrm"

var host = Host.new()
var state = State.new()
var walker = Locomotion.new()
var air = AirMotion.new()
var director = Director.new()
var places = PlaceDirector.new()
var playground = Playground.new()
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
var _quit_phase: String = ""
var _cinematic_mask_active: bool = false
var _preview_zoom: float = 1.0
var _ui_clock: float = 0.0
var _screen_clock: float = 0.0
var _walk_area: Rect2i = Rect2i()
var _walk_direction: int = 1
var _pending_action: String = ""
var _pending_auto: bool = false
var _rest_after_walk: bool = false
var _test_mode: bool = false
var _settings: ConfigFile = ConfigFile.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.setup(get_window())
	state.seed_random(int(Time.get_ticks_usec()))
	director.seed_random(int(Time.get_ticks_usec()) + 7)
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
	print("HOSHI_START version=0.6 engine=", Engine.get_version_info().get("string", ""))
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
	if stage != null:
		stage.cancel_cinematic()
		_hard_stop()
		stage.travel_offset_px = 0.0
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
	var blocked: bool = playground.active() or air.active() or stage.cinematic_active() or not _quit_phase.is_empty() or _press_active or ui.menu.visible or state.dozing or walker.active() or state.posture.transitioning() or not _pending_action.is_empty() or state.pet_weight > 0.1 or state.wave_weight > 0.1
	var place_request: String = places.tick(dt, state, {"blocked": blocked or host.preview, "can_place": not host.preview and host.is_grounded() and state.posture.mode == "standing"})
	if place_request == "cozy":
		blocked = playground.show_demo(true) or blocked
	elif place_request == "smart":
		blocked = playground.auto_choose_window() or blocked
	var action: String = director.tick(dt, {"blocked": blocked, "cursor_gaze": cursor_gaze,
		"cursor_near": distance < stage.body_pixels * 1.8,
		"can_walk": not host.preview and host.is_grounded() and stage.gait.available and state.posture.mode == "standing",
		"can_rest": (host.preview or host.is_grounded()) and stage.posture_driver.available and state.posture.mode == "standing"})
	if action == "walk":
		_start_walk(true)
	elif action == "wave":
		state.wave()
	elif action == "sit":
		_request_sit(true)
	var target: Vector2 = Vector2.ZERO
	if state.look_enabled and not state.dozing and not ui.menu.visible and not walker.active() and absf(stage.yaw) < 55.0:
		target = director.gaze
		# Deliberate interaction briefly wins over independent attention.
		if state.pet_weight > 0.1 or state.wave_weight > 0.1:
			target = cursor_gaze if distance < 1000.0 else Vector2.ZERO
	_gaze = _gaze.lerp(target, 1.0 - exp(-dt * 6.0))
	state.curiosity = lerpf(state.curiosity, director.curiosity if state.motion_enabled and state.look_enabled else 0.0, 1.0 - exp(-dt * 5.0))
	stage.edge_suspended = _press_active or ui.menu.visible or (playground.active() and (playground.phase != "attached" or playground.surface_busy()))
	var context_action: String = "carry" if _dragged and not host.preview else air.pose_mode()
	if context_action == "idle":
		context_action = playground.surface_context()
	stage.set_context_action(context_action, _drag_velocity)
	stage.animate(dt, state, _gaze, walker.sample())
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
		if caption.is_empty() and state.posture.mode != "standing":
			caption = state.state_label()
		if caption.is_empty() and not blocked and state.look_enabled:
			caption = director.attention_label
		ui.refresh(state, caption, walker.active())

func _start_walk(automatic: bool) -> void:
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
	_rest_after_walk = automatic and state.rest_enabled
	state.dozing = false
	director.user_interaction()
	_walk_area = host.walking_area()
	print("HOSHI_WALK start_px=", start_x, " target_px=", clampf(target, lane.x, lane.y), " steps=", walker.step_count, " mpp=", walker.meters_per_pixel, " preview=", host.preview)

func _stop_walk(keep_facing: bool = false) -> void:
	walker.stop(keep_facing)
	director.user_interaction()

func _hard_stop() -> void:
	if stage == null:
		return
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
				_stop_walk()
				_clear_intent()
				state.posture.keep_rest()
				_press_active = true
				_dragged = false
				_double_clicked = button.double_click
				_press_cursor = host.cursor_global()
				_press_window = get_window().position
				_press_yaw = stage.yaw
				_last_drag_cursor = _press_cursor
				_drag_velocity = Vector2.ZERO
				if button.double_click:
					state.wave()
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
	var instant_velocity: Vector2 = frame_move / maxf(delta, 0.001)
	_drag_velocity = _drag_velocity.lerp(instant_velocity, 1.0 - exp(-delta * 10.0))
	if Vector2(movement).length() > 6.0:
		if not _dragged:
			# Carrying supersedes navigation and releases the body into a hanging pose.
			_hard_stop()
			air.cancel(Vector2(host.window.position))
			playground.begin_drag()
			state.dozing = false
			state.posture.request_stand()
			_dragged = true
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
	var was_dragged: bool = _dragged
	_press_active = false
	_dragged = false
	if was_dragged:
		var support_handled: bool = playground.finish_drag()
		if not support_handled:
			if host.preview:
				host.finish_drag()
			else:
				state.dozing = false
				state.posture.request_stand()
				air.begin_fall(Vector2(host.window.position), Vector2(host.floor_position()), float(host.body_pixels))
		_drag_velocity = Vector2.ZERO
		_save_settings()
	elif not _double_clicked:
		places.manual_pause()
		_clear_intent()
		playground.cancel_queued_walk()
		state.posture.keep_rest()
		state.pet()
		ui.say("М-м, спасибо!")
	director.user_interaction()

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
	places.manual_pause()
	playground.cancel_queued_walk()
	_clear_intent()
	state.posture.keep_rest()
	_press_active = false
	_stop_walk()
	ui.refresh(state, walker.label(), walker.active())
	host.menu_focus(true)
	ui.menu.position = host.cursor_global()
	ui.menu.popup()

func _on_menu_hidden() -> void:
	host.menu_focus(false)
	director.user_interaction()

func _on_action(action: int) -> void:
	if action == 199:
		_quit()
		return
	if action == 100:
		_switch_mode(true)
		return
	if not _ready_to_run:
		return
	if action in [10, 11, 12, 30, 31, 32, 33, 40, 41, 42, 43, 100, 101, 110, 111, 112, 140, 141, 305, 306, 307, 308]:
		places.manual_pause()
	if action in [210, 211, 212]:
		state.place_mode = ["off", "cozy", "smart"][action - 210]
		places.change_mode(state.place_mode)
		ui.refresh(state, playground.label(), walker.active())
		_save_settings()
		return
	if action >= 300 and action <= 304:
		state.edge_activity = ["auto", "calm", "swing", "lean", "peek"][action - 300]
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
			state.wave()
			ui.say("Я тут!")
		11:
			state.pet()
			ui.say("Спасибо!")
		12:
			if state.dozing or state.sleep_requested:
				_clear_intent()
				state.dozing = false
				state.posture.keep_rest()
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
	state.edge_activity = edge_activity if edge_activity in ["auto", "calm", "swing", "lean", "peek"] else "auto"
	var activity: String = str(_settings.get_value("behavior", "activity", "normal"))
	state.activity = activity if activity in ["quiet", "normal", "playful"] else "normal"
	frame_rate = 60 if int(_settings.get_value("render", "fps", 30)) == 60 else 30

func _save_settings() -> void:
	if host.headless or _test_mode:
		return
	_settings.set_value("window", "body_pixels", host.body_pixels)
	var saved_window: Vector2i = host.saved_position if host.preview else get_window().position
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
	var diagnostic: Dictionary = {"version": "0.6", "engine": Engine.get_version_info(),
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
		state.posture.request_sit(_pending_auto, 75.0 if state.activity == "quiet" else 45.0)
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
	playground.external.close()
