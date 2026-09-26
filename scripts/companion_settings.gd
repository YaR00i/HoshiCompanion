extends RefCounted
## Настройки Хоши: что сохраняется между запусками (user://companion.cfg)
## и внешний вид — свет, тени, обводка.
##
## Только чтение/запись значений. Поведение, которое от них зависит,
## остаётся у своих владельцев (state, host, stage).

const SETTINGS_PATH: String = "user://companion.cfg"
const DEFAULT_LIGHT_POSITION: Vector3 = Vector3(-1.2, 2.2, 2.4)
const DEFAULT_EDGE_COLOR: Color = Color(1.0, 0.92, 0.98)
const DEFAULT_OUTLINE_COLOR: Color = Color(0.20, 0.16, 0.27)

var config: ConfigFile = ConfigFile.new()
var light_position: Vector3 = DEFAULT_LIGHT_POSITION
var shading: Dictionary = {"shadow_strength": 1.0, "shadow_color": Color.WHITE,
	"edge_strength": 0.16, "edge_color": DEFAULT_EDGE_COLOR, "edge_width": 0.4,
	"outline_strength": 0.45, "outline_color": DEFAULT_OUTLINE_COLOR, "outline_width": 0.35}
## Свет сохраняется с небольшой задержкой, пока ползунок ещё двигают.
var save_delay: float = -1.0

var _app_ref: WeakRef

func setup(app) -> void:
	_app_ref = weakref(app)

func _app():
	return _app_ref.get_ref() if _app_ref != null else null

static func default_shading() -> Dictionary:
	return {"shadow_strength": 1.0, "shadow_color": Color.WHITE,
		"edge_strength": 0.16, "edge_color": DEFAULT_EDGE_COLOR, "edge_width": 0.4,
		"outline_strength": 0.45, "outline_color": DEFAULT_OUTLINE_COLOR, "outline_width": 0.35}

static func clickthrough_setting(config: ConfigFile) -> bool:
	# Legacy mask_enabled=false came from an unlabeled toggle. It is deliberately
	# not treated as an opt-out of the explicit click-through setting.
	return bool(config.get_value("window", "clickthrough_enabled", true))

func bubbles_enabled() -> bool:
	return bool(config.get_value("behavior", "bubbles", true))

## Каждый кадр: отложенное сохранение после правки света.
func tick(dt: float) -> void:
	if save_delay >= 0.0:
		save_delay -= dt
		if save_delay < 0.0:
			save()

## Команда "light_reset": вернуть свет и обводку по умолчанию.
func reset_light() -> void:
	var app = _app()
	if app == null:
		return
	set_light_position(DEFAULT_LIGHT_POSITION)
	set_shading(default_shading())
	app.ui.set_light_position(light_position)
	app.ui.set_shading_settings(shading)

func read() -> void:
	var app = _app()
	if app == null:
		return
	if app._test_mode or OS.get_cmdline_user_args().has("--reset"):
		return
	if config.load(SETTINGS_PATH) != OK:
		return
	app.host.body_pixels = clampi(int(config.get_value("window", "body_pixels", 360)), 240, 520)
	var stored_position: Variant = config.get_value("window", "position", Vector2i(-99999, -99999))
	if stored_position is Vector2i:
		app.host.saved_position = stored_position
	app.host.mask_enabled = clickthrough_setting(config)
	app.state.look_enabled = bool(config.get_value("behavior", "look", true))
	app.state.motion_enabled = bool(config.get_value("behavior", "motion", true))
	app.state.hair_enabled = bool(config.get_value("behavior", "hair", true))
	app.state.rest_enabled = bool(config.get_value("behavior", "rest", true))
	app.state.walk_enabled = bool(config.get_value("behavior", "walk", true))
	app.state.autonomy_enabled = bool(config.get_value("behavior", "autonomy", true))
	var place_mode: String = str(config.get_value("behavior", "place_mode", "off"))
	app.state.place_mode = place_mode if place_mode in ["off", "cozy", "smart", "focus"] else "off"
	var edge_activity: String = str(config.get_value("behavior", "edge_activity", "auto"))
	app.state.edge_activity = edge_activity if edge_activity in ["auto", "calm", "swing", "lean", "peek", "sway", "hum", "nod"] else "auto"
	var activity: String = str(config.get_value("behavior", "activity", "normal"))
	app.state.activity = activity if activity in ["quiet", "normal", "playful"] else "normal"
	app.frame_rate = 60 if int(config.get_value("render", "fps", 30)) == 60 else 30
	var stored_light: Variant = config.get_value("render", "light_position", DEFAULT_LIGHT_POSITION)
	if stored_light is Vector3:
		light_position = Vector3(clampf(stored_light.x, -3.0, 3.0), clampf(stored_light.y, 0.2, 3.5), clampf(stored_light.z, 0.4, 4.0))
	shading["shadow_strength"] = clampf(float(config.get_value("render", "shadow_strength", 1.0)), 0.0, 1.5)
	shading["edge_strength"] = clampf(float(config.get_value("render", "edge_strength", 0.16)), 0.0, 0.5)
	shading["edge_width"] = clampf(float(config.get_value("render", "edge_width", 0.4)), 0.0, 1.0)
	shading["outline_strength"] = clampf(float(config.get_value("render", "outline_strength", 0.45)), 0.0, 1.0)
	shading["outline_width"] = clampf(float(config.get_value("render", "outline_width", 0.35)), 0.0, 1.0)
	var stored_shadow_color: Variant = config.get_value("render", "shadow_color", Color.WHITE)
	if stored_shadow_color is Color:
		shading["shadow_color"] = stored_shadow_color
	var stored_edge_color: Variant = config.get_value("render", "edge_color", DEFAULT_EDGE_COLOR)
	if stored_edge_color is Color:
		shading["edge_color"] = stored_edge_color
	var stored_outline_color: Variant = config.get_value("render", "outline_color", DEFAULT_OUTLINE_COLOR)
	if stored_outline_color is Color:
		shading["outline_color"] = stored_outline_color

func save() -> void:
	var app = _app()
	if app == null:
		return
	if app.host.headless or app._test_mode:
		return
	config.set_value("window", "body_pixels", app.host.body_pixels)
	var saved_window: Vector2i = app.host.saved_position if app.host.preview or app.air.active() else app.get_window().position
	if app.playground.active():
		saved_window = app.playground.saved_floor_position
	config.set_value("window", "position", saved_window)
	config.erase_section_key("window", "mask_enabled")
	config.set_value("window", "clickthrough_enabled", app.host.mask_enabled)
	config.set_value("behavior", "look", app.state.look_enabled)
	config.set_value("behavior", "motion", app.state.motion_enabled)
	config.set_value("behavior", "hair", app.state.hair_enabled)
	config.set_value("behavior", "rest", app.state.rest_enabled)
	config.set_value("behavior", "walk", app.state.walk_enabled)
	config.set_value("behavior", "autonomy", app.state.autonomy_enabled)
	config.set_value("behavior", "place_mode", app.state.place_mode)
	config.set_value("behavior", "edge_activity", app.state.edge_activity)
	config.set_value("behavior", "activity", app.state.activity)
	config.set_value("behavior", "bubbles", app.ui.bubbles_enabled)
	config.set_value("render", "fps", app.frame_rate)
	config.set_value("render", "light_position", light_position)
	for key in ["shadow_strength", "shadow_color", "edge_strength", "edge_color", "edge_width",
		"outline_strength", "outline_color", "outline_width"]:
		config.set_value("render", key, shading[key])
	var result: Error = config.save(SETTINGS_PATH)
	if result != OK:
		push_warning("Settings could not be saved: " + error_string(result))

func set_light_position(position_value: Vector3) -> void:
	var app = _app()
	if app == null:
		return
	light_position = position_value
	app.stage.set_light_position(position_value)
	save_delay = 0.4

func set_shading(settings: Dictionary) -> void:
	var app = _app()
	if app == null:
		return
	shading = settings.duplicate()
	apply_shading()
	save_delay = 0.4

func apply_shading() -> void:
	var app = _app()
	if app == null:
		return
	app.stage.set_shading_settings(float(shading["shadow_strength"]), shading["shadow_color"],
		float(shading["edge_strength"]), shading["edge_color"], float(shading["edge_width"]),
		float(shading["outline_strength"]), shading["outline_color"], float(shading["outline_width"]))
