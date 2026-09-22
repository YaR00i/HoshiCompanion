extends SubViewportContainer

const Source = preload("res://scripts/vrm_source.gd")
const Rig = preload("res://scripts/rig_driver.gd")
const Gait = preload("res://scripts/gait_driver.gd")
const PostureDriver = preload("res://scripts/posture_driver.gd")
const EdgePose = preload("res://scripts/edge_pose.gd")
const EdgeLife = preload("res://scripts/edge_life.gd")
const IdleLife = preload("res://scripts/idle_life.gd")
const ContextPose = preload("res://scripts/context_pose.gd")
const MagicDoor = preload("res://scripts/magic_door.gd")
const Expressions = preload("res://scripts/expression_driver.gd")

var view: SubViewport
var pivot: Node3D
var avatar: Node3D
var camera: Camera3D
var rig = Rig.new()
var expressions = Expressions.new()
var gait = Gait.new()
var posture_driver = PostureDriver.new()
var edge_pose = EdgePose.new()
var edge_life = EdgeLife.new()
var idle_life = IdleLife.new()
var context_pose = ContextPose.new()
var door
var edge_suspended: bool = false
var context_action: String = "idle"
var context_velocity: Vector2 = Vector2.ZERO
var context_progress: float = -1.0
var context_impact: float = 0.5
var _cinematic_mode: String = ""
var _cinematic_age: float = 0.0
var _cinematic_z: float = 0.0
var model_data: Dictionary = {}
var report: Dictionary = {}
var model_height: float = 1.5
var body_pixels: float = 480.0
var foot_margin: float = 38.0
var yaw: float = 0.0
var travel_offset_px: float = 0.0
var is_loaded: bool = false
var _mesh_count: int = 0
var _interaction_image: Image

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	view = SubViewport.new()
	view.name = "AvatarViewport"
	view.size = Vector2i(560, 620)
	view.transparent_bg = true
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_2X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	door = MagicDoor.new()
	door.name = "MagicDoor"
	view.add_child(door)
	pivot = Node3D.new()
	pivot.name = "AvatarPivot"
	view.add_child(pivot)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.01
	camera.far = 20.0
	camera.position = Vector3(0.0, 0.8, 4.0)
	camera.current = true
	view.add_child(camera)
	# Fallback light for a model with standard shaded materials. Hoshi's authored
	# KHR_materials_unlit fallbacks do not depend on this light.
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-22.0, -18.0, 0.0)
	light.light_energy = 1.0
	light.shadow_enabled = false
	view.add_child(light)
	resized.connect(_on_resized)
	_on_resized()

func load_model(path: String) -> Dictionary:
	is_loaded = false
	report = {}
	model_data = {}
	# A reload must not retain meshes, bone indices or drivers from the old avatar.
	rig = Rig.new()
	gait = Gait.new()
	posture_driver = PostureDriver.new()
	edge_pose = EdgePose.new()
	edge_life = EdgeLife.new()
	idle_life = IdleLife.new()
	context_pose = ContextPose.new()
	var life_seed: int = 42 if OS.get_cmdline_user_args().has("--test-mode") else int(Time.get_ticks_usec())
	edge_life.seed_random(life_seed)
	idle_life.seed_random(life_seed + 19)
	expressions = Expressions.new()
	_cinematic_mode = ""
	_cinematic_age = 0.0
	_cinematic_z = 0.0
	if is_instance_valid(avatar):
		pivot.remove_child(avatar)
		avatar.queue_free()
		avatar = null
	var loaded: Dictionary = Source.load_avatar(path)
	if loaded.has("error"):
		return loaded
	avatar = loaded["model"]
	pivot.add_child(avatar)
	model_data = loaded
	var rig_report: Dictionary = rig.setup(avatar, loaded["source"], loaded["state"])
	if rig_report.has("error"):
		return rig_report
	var merged: AABB = AABB()
	var have_bounds: bool = false
	var meshes: Array[Node] = avatar.find_children("*", "MeshInstance3D", true, false)
	_mesh_count = meshes.size()
	for child in meshes:
		var instance: MeshInstance3D = child as MeshInstance3D
		if instance.mesh == null:
			continue
		var transform_to_avatar: Transform3D = avatar.global_transform.affine_inverse() * instance.global_transform
		var bounds: AABB = transform_to_avatar * instance.get_aabb()
		merged = merged.merge(bounds) if have_bounds else bounds
		have_bounds = true
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = 0.25
	if not have_bounds or merged.size.y < 0.1:
		return {"error": "Модель импортирована, но её видимая геометрия не найдена."}
	model_height = merged.size.y
	avatar.position.y -= merged.position.y
	avatar.position.x -= merged.get_center().x
	avatar.position.z -= merged.get_center().z
	# Start the body independently of optional facial capabilities.
	rig.tick(0.0, 0.0, Vector2.ZERO, 0.0, 0.0, 0.0, true)
	var gait_report: Dictionary = gait.setup(rig, model_height)
	var posture_report: Dictionary = posture_driver.setup(rig, gait, model_height)
	edge_pose.setup(posture_driver)
	var context_report: Dictionary = context_pose.setup(rig, model_height)
	var idle_report: Dictionary = idle_life.setup(rig)
	door.setup(model_height)
	door.hide_door()
	var face_report: Dictionary = expressions.setup(avatar, loaded["source"], loaded["state"])
	is_loaded = true
	report = {"posture": posture_report, "context": context_report, "idle_life": idle_report, "rig": rig_report, "locomotion": gait_report, "face": face_report, "mesh_count": _mesh_count, "height_m": model_height,
		"status": "ready" if bool(face_report.get("blink_available", false)) else "partial",
		"warnings": face_report.get("warnings", PackedStringArray())}
	fit_camera()
	return report

func _on_resized() -> void:
	if view == null:
		return
	# SubViewportContainer with stretch=true owns the child viewport size.
	# Camera fitting is deferred until the container has completed its resize.
	fit_camera.call_deferred()

func configure_frame(pixels: float, margin: float) -> void:
	body_pixels = maxf(100.0, pixels)
	foot_margin = margin
	fit_camera()

func fit_camera() -> void:
	if camera == null or view == null:
		return
	var view_height: float = float(maxi(view.size.y, 1))
	camera.size = model_height * view_height / body_pixels
	camera.position = Vector3(0.0, camera.size * (0.5 - foot_margin / view_height), maxf(4.0, model_height * 2.5))
	camera.rotation = Vector3.ZERO

func animate(delta: float, state, gaze: Vector2, walk_frame: Dictionary = {}) -> void:
	if not is_loaded:
		return
	_tick_cinematic(delta, state.time)
	pivot.rotation.y = deg_to_rad(yaw)
	pivot.position = Vector3(travel_offset_px * meters_per_pixel(), 0.0, _cinematic_z)
	var life_frame: Dictionary = edge_life.tick(delta, state, edge_suspended)
	var walk_weight: float = float(walk_frame.get("weight", 0.0))
	var idle_blocked: bool = cinematic_active() or context_action != "idle" or edge_suspended
	idle_life.tick(delta, state, idle_blocked, walk_weight)
	rig.hair_enabled = state.hair_enabled
	rig.tick(delta, state.time, gaze, state.wave_weight, state.pet_weight, state.sleep_weight, state.motion_enabled, state.curiosity, walk_frame)
	var seated: float = state.posture.amount
	gait.apply(walk_frame, state.time, 0.45 * (1.0 - seated) if state.motion_enabled and state.autonomy_enabled and not state.dozing else 0.0)
	if state.posture.kind == "edge":
		edge_pose.apply(seated, state.time, state.wave_weight, state.motion_enabled and not state.dozing, life_frame)
	else:
		posture_driver.apply(seated, state.time, state.wave_weight, state.motion_enabled)
	idle_life.apply(state.time)
	var active_context: String = "portal" if cinematic_active() else context_action
	context_pose.tick(delta, active_context, context_velocity, context_progress, context_impact)
	context_pose.apply(state.time)
	expressions.apply(state.expression_weights())

func set_context_action(value: String, velocity: Vector2 = Vector2.ZERO, normalized_progress: float = -1.0, impact_strength: float = 0.5) -> void:
	context_action = value
	context_velocity = velocity
	context_progress = normalized_progress
	context_impact = impact_strength

func start_portal_intro() -> void:
	if not is_loaded:
		return
	_interaction_image = null
	_cinematic_mode = "intro"
	_cinematic_age = 0.0
	# Start well behind both portal plane and the complete door-leaf sweep.
	_cinematic_z = -model_height * 0.58

func start_portal_outro() -> void:
	if not is_loaded:
		_cinematic_mode = "outro_done"
		return
	_interaction_image = null
	_cinematic_mode = "outro"
	_cinematic_age = 0.0
	# Keep the whole avatar in front while the inward-opening leaf clears the doorway.
	_cinematic_z = model_height * 0.12

func cinematic_active() -> bool:
	return _cinematic_mode in ["intro", "outro"]

func outro_complete() -> bool:
	return _cinematic_mode == "outro_done"

func cancel_cinematic() -> void:
	_cinematic_mode = ""
	_cinematic_age = 0.0
	_cinematic_z = 0.0
	if door != null:
		door.hide_door()

func _tick_cinematic(delta: float, time_value: float) -> void:
	if not cinematic_active():
		if _cinematic_mode.is_empty():
			_cinematic_z = 0.0
		return
	_cinematic_age += clampf(delta, 0.0, 0.1)
	var duration: float = 2.48 if _cinematic_mode == "intro" else 2.44
	var u: float = clampf(_cinematic_age / duration, 0.0, 1.0)
	var visibility: float = smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.95, 1.0, u))
	var close_start: float = 0.82 if _cinematic_mode == "intro" else 0.88
	var opened: float = smoothstep(0.06, 0.24, u) * (1.0 - smoothstep(close_start, 0.975, u))
	var front_z: float = model_height * 0.12
	var hidden_z: float = -model_height * 0.58
	var opening_direction: float = 1.0 if _cinematic_mode == "intro" else -1.0
	if _cinematic_mode == "intro":
		# Door fully clears Hoshi first; only then does she cross the portal plane.
		_cinematic_z = lerpf(hidden_z, front_z, smoothstep(0.29, 0.71, u))
	else:
		# Hoshi waits in front until the inward leaf is open, then moves completely
		# behind the portal before the closing phase begins.
		_cinematic_z = lerpf(front_z, hidden_z, smoothstep(0.30, 0.77, u))
	door.set_state(visibility, opened, time_value, opening_direction)
	if u >= 1.0:
		door.hide_door()
		if _cinematic_mode == "intro":
			_cinematic_mode = ""
			_cinematic_z = 0.0
		else:
			_cinematic_mode = "outro_done"

func meters_per_pixel() -> float:
	return model_height / maxf(body_pixels, 1.0)

func head_pixel() -> Vector2:
	if not is_loaded:
		return size * Vector2(0.5, 0.24)
	return camera.unproject_position(rig.world_point("head") + Vector3(0.0, model_height * 0.05, 0.0))

func standing_anchor_pixel() -> Vector2:
	if not is_loaded or not gait.available or gait.legs.size() < 2:
		return Vector2(size.x * 0.5, size.y - foot_margin)
	var point: Vector3 = ((gait.legs[0]["rest_ankle"] as Vector3) + (gait.legs[1]["rest_ankle"] as Vector3)) * 0.5
	point.y -= model_height * 0.025
	return camera.unproject_position(rig.skeleton.global_transform * point)

func side_anchor_pixel(window_side: String) -> Vector2:
	if not is_loaded:
		return size * Vector2(0.5, 0.42)
	var semantic: String = "leftUpperArm" if window_side == "left" else "rightUpperArm"
	if not rig.bones.has(semantic):
		return head_pixel()
	var bone: int = int(rig.bones[semantic])
	var point: Vector3 = rig.skeleton.get_bone_global_rest(bone).origin
	point.x += model_height * (0.12 if window_side == "left" else -0.12)
	point.y -= model_height * 0.035
	return camera.unproject_position(rig.skeleton.global_transform * point)

func refresh_interaction_alpha() -> bool:
	if view == null or not is_loaded or view.get_texture() == null:
		return false
	var image: Image = view.get_texture().get_image()
	if image == null or image.is_empty():
		return false
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_interaction_image = image
	return true

func clear_interaction_alpha() -> void:
	_interaction_image = null

func visible_avatar_hit(point: Vector2) -> bool:
	if _interaction_image == null or _interaction_image.is_empty():
		return hit_avatar(point)
	return alpha_image_hit(_interaction_image, point, size)

static func alpha_image_hit(image: Image, point: Vector2, logical_size: Vector2, radius_px: int = 2, alpha_threshold: float = 0.035) -> bool:
	if image == null or image.is_empty() or logical_size.x <= 0.0 or logical_size.y <= 0.0:
		return false
	if point.x < 0.0 or point.y < 0.0 or point.x >= logical_size.x or point.y >= logical_size.y:
		return false
	var width: int = image.get_width()
	var height: int = image.get_height()
	var px: int = clampi(int(floor(point.x * float(width) / logical_size.x)), 0, width - 1)
	var py: int = clampi(int(floor(point.y * float(height) / logical_size.y)), 0, height - 1)
	var radius: int = maxi(0, radius_px)
	for y in range(maxi(0, py - radius), mini(height, py + radius + 1)):
		for x in range(maxi(0, px - radius), mini(width, px + radius + 1)):
			if image.get_pixel(x, y).a >= alpha_threshold:
				return true
	return false

func hit_avatar(point: Vector2) -> bool:
	# Conservative fallback before the first app-owned alpha snapshot is ready.
	if not is_loaded:
		return false
	var bounds: Rect2 = Rect2(head_pixel(), Vector2.ONE)
	for semantic in ["head", "hips", "leftHand", "rightHand", "leftUpperArm", "rightUpperArm", "leftLowerLeg", "rightLowerLeg", "leftFoot", "rightFoot"]:
		bounds = bounds.expand(camera.unproject_position(rig.world_point(semantic)))
	return bounds.grow(body_pixels * 0.14).has_point(point)

func model_name() -> String:
	return str(model_data.get("vrm", {}).get("meta", {}).get("name", "Hoshi"))
