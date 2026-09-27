extends RefCounted
## Мышь и клавиатура Хоши: касание, поглаживание, перенос мышкой, хват за
## курсор, колёсико масштаба, правый клик — меню, горячие клавиши.
##
## Здесь только РАСПОЗНАВАНИЕ жеста человека и вызов готовых действий.
## Кости и окно по-прежнему двигают их владельцы (host, air, playground,
## state/pose-слои). Горячие клавиши — это просто имена команд из
## hoshi_commands.gd, как кнопки меню.

## Состояние текущего нажатия (читается coordinator'ом и опорами).
var press_active: bool = false
var dragged: bool = false
var double_clicked: bool = false
var press_cursor: Vector2i = Vector2i.ZERO
var press_window: Vector2i = Vector2i.ZERO
var press_yaw: float = 0.0
var last_drag_cursor: Vector2i = Vector2i.ZERO
var drag_velocity: Vector2 = Vector2.ZERO
var hand_side: String = ""
var hand_hold_age: float = 0.0
var cursor_hanging: bool = false

var _app_ref: WeakRef

func setup(app) -> void:
	_app_ref = weakref(app)

func _app():
	return _app_ref.get_ref() if _app_ref != null else null

## Сбросить нажатие при смене режима (примерочная ↔ рабочий стол).
func reset() -> void:
	press_active = false
	dragged = false
	hand_side = ""
	hand_hold_age = 0.0
	cursor_hanging = false

## Каждый кадр: пока Хоши держится за курсор, окно следует за ладонью.
func tick_hang() -> void:
	var app = _app()
	if app == null:
		return
	if cursor_hanging and not app.host.hang_hand_to(app.host.cursor_global(), app.stage.hand_pixel(hand_side)):
		end_cursor_hang()

func handle(event: InputEvent) -> void:
	var app = _app()
	if app == null:
		return
	if not app._ready_to_run or not app.lifecycle.phase.is_empty() or app.stage.cinematic_active():
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		var local_point: Vector2 = button.position - app.stage.position
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			open_menu()
			app.get_viewport().set_input_as_handled()
			return
		if not app.stage.get_rect().has_point(button.position):
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			zoom(1)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			zoom(-1)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed and app.stage.hit_avatar(local_point):
				app._abort_autonomous_intent("pointer")
				app._stop_walk()
				app._clear_intent()
				app.state.posture.keep_rest()
				press_active = true
				dragged = false
				hand_side = ""
				hand_hold_age = 0.0
				cursor_hanging = false
				double_clicked = button.double_click
				press_cursor = app.host.cursor_global()
				press_window = app.get_window().position
				press_yaw = app.stage.yaw
				last_drag_cursor = press_cursor
				drag_velocity = Vector2.ZERO
				app.state.cancel_release_reaction()
				var on_head: bool = app.stage.head_contact_hit(local_point)
				if not on_head and not button.double_click and not app.host.preview and app.host.is_grounded() and not app.playground.active() and not app.air.active() and app.state.posture.mode == "standing" and not app.state.posture.transitioning() and app.state.wave_weight < 0.1:
					hand_side = app.stage.hand_contact_side(local_point)
				if hand_side.is_empty():
					app.interaction.begin(Vector2(press_cursor), on_head, app.stage.body_pixels)
				else:
					app.interaction.cancel()
					app.interaction.manual_activity()
				if not on_head:
					app.state.cancel_pet_contact()
				if button.double_click and app.interaction.accept_wave():
					app.state.wave()
					if app.interaction.allow_bubble():
						app.ui.say("Привет-привет!")
			elif not button.pressed and press_active:
				finish_press()
	elif event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		match key_event.physical_keycode:
			KEY_ESCAPE:
				if app.walker.active():
					app._on_action("stop")
				elif app.host.preview:
					app._quit()
			KEY_SPACE: app._on_action("wave")
			KEY_W: app._on_action("walk")
			KEY_C: app._on_action("stand" if app.state.posture.target_seated else "sit")
			KEY_S: app._on_action("doze")
			KEY_F: app._on_action("reset_view")
			KEY_P: app._switch_mode(not app.host.preview)

func update_drag(delta: float) -> void:
	var app = _app()
	if app == null:
		return
	if not press_active or app.host.headless:
		return
	var cursor_now: Vector2i = app.host.cursor_global()
	var movement: Vector2i = cursor_now - press_cursor
	var frame_move: Vector2 = Vector2(cursor_now - last_drag_cursor)
	last_drag_cursor = cursor_now
	var pointer_local: Vector2 = app.host.cursor_local() - app.stage.position
	app.interaction.update(Vector2(cursor_now), delta, app.stage.head_stroke_zone_hit(pointer_local) if not dragged else false)
	var instant_velocity: Vector2 = frame_move / maxf(delta, 0.001)
	drag_velocity = drag_velocity.lerp(instant_velocity, 1.0 - exp(-delta * 10.0))
	if not hand_side.is_empty():
		hand_hold_age += delta
		if cursor_hanging and cursor_now.y > press_cursor.y + 24:
			end_cursor_hang()
			return
		if not cursor_hanging and hand_hold_age >= 0.16 and press_cursor.y - cursor_now.y >= 12:
			app._hard_stop()
			app.state.begin_cursor_hang()
			app.state.posture.request_stand()
			cursor_hanging = true
			app.places.manual_pause()
		if (DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT) == 0:
			finish_press()
		return
	if app.interaction.should_begin_drag():
		if not dragged:
			# Carrying supersedes navigation and releases the body into a hanging pose.
			app.state.cancel_pet_contact()
			app._hard_stop()
			app.air.cancel(Vector2(app.host.window.position))
			app.playground.begin_drag()
			app.state.dozing = false
			app.state.posture.request_stand()
			dragged = true
	if not dragged and not double_clicked and app.interaction.petting_now():
		if not app.state.pet_contact_active:
			app.state.begin_pet_contact()
		var head_offset: Vector2 = (pointer_local - app.stage.head_pixel()) / maxf(app.stage.body_pixels * 0.18, 1.0)
		app.state.update_pet_contact(head_offset, delta)
	elif app.state.pet_contact_active:
		app.state.end_pet_contact()
	if dragged:
		if app.host.preview:
			app.stage.yaw = clampf(press_yaw + float(movement.x) * 0.4, -180.0, 180.0)
		else:
			app.stage.travel_offset_px = 0.0
			app.host.drag_to(press_window + movement)
	if (DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT) == 0:
		finish_press()

func finish_press() -> void:
	var app = _app()
	if app == null:
		return
	if not press_active:
		return
	app._abort_autonomous_intent("pointer")
	if not hand_side.is_empty():
		if cursor_hanging:
			end_cursor_hang()
		else:
			press_active = false
			hand_side = ""
			hand_hold_age = 0.0
			if app.interaction.accept_palm_attention():
				app.state.notice()
		app.director.user_interaction()
		return
	var was_dragged: bool = dragged
	var floor_goal: Vector2i = app.host.floor_position() if was_dragged and not app.host.preview else Vector2i.ZERO
	var drop_pixels: float = maxf(0.0, float(floor_goal.y - app.host.window.position.y)) if was_dragged and not app.host.preview else 0.0
	var release_style: String = app.interaction.release_style(drag_velocity, drop_pixels) if was_dragged and not app.host.preview else ""
	var gesture: String = app.interaction.finish(was_dragged, double_clicked, app.state.dozing)
	press_active = false
	dragged = false
	if app.state.pet_contact_active:
		app.state.end_pet_contact()
	if was_dragged:
		var support_handled: bool = app.playground.finish_drag()
		if not support_handled:
			if app.host.preview:
				app.host.finish_drag()
			else:
				app.state.dozing = false
				app.state.posture.request_stand(true)
				floor_goal = app.host.remember_floor_position()
				app.interaction.record_release(release_style)
				app.state.react_to_release(release_style)
				app.air.begin_fall(Vector2(app.host.window.position), Vector2(floor_goal), float(app.host.body_pixels), release_style)
		drag_velocity = Vector2.ZERO
		app._save_settings()
	elif gesture in ["attention", "pet", "wake", "return", "quiet"]:
		app.places.manual_pause()
		app._clear_intent()
		app.playground.cancel_queued_walk()
		app.state.posture.keep_rest()
		if gesture == "pet":
			if app.interaction.allow_bubble():
				app.ui.say("М-м…")
		elif gesture in ["wake", "return"]:
			app.state.recognize()
		elif gesture == "attention":
			app.state.notice()
	app.director.user_interaction()

func end_cursor_hang() -> void:
	var app = _app()
	if app == null:
		return
	var was_hanging: bool = cursor_hanging
	press_active = false
	cursor_hanging = false
	app.state.end_cursor_hang()
	hand_side = ""
	hand_hold_age = 0.0
	drag_velocity = Vector2.ZERO
	app.interaction.cancel()
	if not was_hanging or app.host.preview:
		return
	var floor: Vector2i = app.host.remember_floor_position()
	if app.host.window.position.y >= floor.y:
		app.host.place_at(Vector2(floor))
	else:
		app.air.begin_fall(Vector2(app.host.window.position), Vector2(floor), float(app.host.body_pixels))
	app._save_settings()

func zoom(direction: int) -> void:
	var app = _app()
	if app == null:
		return
	app._hard_stop()
	if app.host.preview:
		app._preview_zoom = clampf(app._preview_zoom + float(direction) * 0.04, 0.75, 1.10)
		app.stage.travel_offset_px = clampf(app.stage.travel_offset_px, -130.0, 130.0)
	else:
		app.stage.travel_offset_px = 0.0
		app.host.resize_body(app.host.body_pixels + direction * 20)
	app._layout()
	app._save_settings()

func open_menu() -> void:
	var app = _app()
	if app == null:
		return
	if cursor_hanging:
		end_cursor_hang()
	app._abort_autonomous_intent("menu")
	app.places.manual_pause()
	app.playground.cancel_queued_walk()
	app._clear_intent()
	app.state.posture.keep_rest()
	press_active = false
	hand_side = ""
	hand_hold_age = 0.0
	app.interaction.cancel()
	app.interaction.manual_activity()
	app.state.cancel_pet_contact()
	app._stop_walk()
	app.ui.clickthrough_enabled = app.host.mask_enabled
	app.ui.refresh(app.state, app.walker.label(), app.walker.active())
	app.host.menu_focus(true)
	app.ui.open_quick_menu(app.host.cursor_global())
