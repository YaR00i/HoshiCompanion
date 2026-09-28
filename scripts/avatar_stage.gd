extends SubViewportContainer

const Source = preload("res://scripts/vrm_source.gd")
const Rig = preload("res://scripts/rig_driver.gd")
const Gait = preload("res://scripts/gait_driver.gd")
const PostureDriver = preload("res://scripts/posture_driver.gd")
const EdgePose = preload("res://scripts/edge_pose.gd")
const EdgeLife = preload("res://scripts/edge_life.gd")
const IdleLife = preload("res://scripts/idle_life.gd")
const TouchReactions = preload("res://scripts/touch_reactions.gd")
const ContextPose = preload("res://scripts/context_pose.gd")
const MagicDoor = preload("res://scripts/magic_door.gd")
const Expressions = preload("res://scripts/expression_driver.gd")
const PetEffect = preload("res://scripts/pet_effect.gd")
const SketchbookProp = preload("res://scripts/sketchbook_prop.gd")
const SketchMotion = preload("res://scripts/sketch_motion.gd")
const SeatedMotion = preload("res://scripts/seated_motion.gd")
const AnimatedProp = preload("res://scripts/animated_prop.gd")
const PaperStarProp = preload("res://scripts/paper_star_prop.gd")
const SoftToonShader = preload("res://scripts/soft_toon.gdshader")
const TopEdgeLightShader = preload("res://scripts/top_edge_light.gdshader")

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
## Реакции на касание по месту: ножка, ручка, животик, грудь (touch_reactions.gd).
var touch = TouchReactions.new()
var context_pose = ContextPose.new()
var door
var edge_suspended: bool = false
var cozy_corner_active: bool = false
var edge_scoot: Dictionary = {}
var animation_workshop_progress: float = -1.0
var last_sketch_channels: Dictionary = {}
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
var voice_level: float = 0.0
var _voice_mouth: float = 0.0
var _mesh_count: int = 0
var _interaction_image: Image
var pet_effect
var sketchbook
var paper_star
var _soft_toon_culled: Shader
var light_position: Vector3 = Vector3(-1.2, 2.2, 2.4)
var shadow_strength: float = 1.0
var shadow_tint: Color = Color.WHITE
var edge_strength: float = 0.16
var edge_color: Color = Color(1.0, 0.92, 0.98)
var edge_width: float = 0.4
var outline_strength: float = 0.45
var outline_color: Color = Color(0.20, 0.16, 0.27)
var outline_width: float = 0.35
var _soft_toon_materials: Array[ShaderMaterial] = []
var _last_toon_light_position: Vector3 = Vector3.ZERO
var _toon_light_dirty: bool = true
var edge_overlay: TextureRect
var _edge_overlay_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	view = SubViewport.new()
	view.name = "AvatarViewport"
	view.size = Vector2i(560, 620)
	view.transparent_bg = true
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
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
	# Keep a fallback light for other shaded VRMs. Hoshi's toon materials use
	# their own simple light bands and preserve the authored texture colors.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-22.0, -18.0, 0.0)
	light.light_energy = 1.0
	light.shadow_enabled = false
	view.add_child(light)
	_soft_toon_culled = Shader.new()
	_soft_toon_culled.code = SoftToonShader.code.replace("cull_disabled", "cull_back")
	edge_overlay = TextureRect.new()
	edge_overlay.name = "TopEdgeLight"
	edge_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	edge_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	edge_overlay.texture = view.get_texture()
	edge_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edge_overlay_material = ShaderMaterial.new()
	_edge_overlay_material.shader = TopEdgeLightShader
	_edge_overlay_material.set_shader_parameter("avatar_texture", view.get_texture())
	edge_overlay.material = _edge_overlay_material
	add_child(edge_overlay)
	pet_effect = PetEffect.new()
	pet_effect.name = "PetEffect"
	view.add_child(pet_effect)
	sketchbook = SketchbookProp.new()
	sketchbook.name = "Sketchbook"
	pivot.add_child(sketchbook)
	paper_star = PaperStarProp.new()
	paper_star.name = "PaperStar"
	pivot.add_child(paper_star)
	resized.connect(_on_resized)
	_on_resized()

func load_model(path: String) -> Dictionary:
	is_loaded = false
	_soft_toon_materials.clear()
	_toon_light_dirty = true
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
	if is_instance_valid(sketchbook):
		pivot.remove_child(sketchbook)
		sketchbook.queue_free()
	sketchbook = SketchbookProp.new()
	sketchbook.name = "Sketchbook"
	pivot.add_child(sketchbook)
	if is_instance_valid(paper_star):
		pivot.remove_child(paper_star)
		paper_star.queue_free()
	paper_star = PaperStarProp.new()
	paper_star.name = "PaperStar"
	pivot.add_child(paper_star)
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
	var source_materials: Dictionary = {}
	for item in loaded["source"].get("materials", []):
		if item is Dictionary:
			source_materials[str(item.get("name", ""))] = item
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
		_apply_soft_toon(instance, source_materials)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = 0.25
	if not have_bounds or merged.size.y < 0.1:
		return {"error": "Модель импортирована, но её видимая геометрия не найдена."}
	model_height = merged.size.y
	sketchbook.setup(model_height)
	paper_star.setup(model_height)
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
	touch.setup(rig, posture_driver)
	door.setup(model_height)
	door.hide_door()
	var face_report: Dictionary = expressions.setup(avatar, loaded["source"], loaded["state"])
	is_loaded = true
	report = {"posture": posture_report, "context": context_report, "idle_life": idle_report, "rig": rig_report, "locomotion": gait_report, "face": face_report, "mesh_count": _mesh_count, "height_m": model_height,
		"status": "ready" if bool(face_report.get("blink_available", false)) else "partial",
		"warnings": face_report.get("warnings", PackedStringArray())}
	fit_camera()
	_update_toon_light()
	_update_toon_shading()
	return report

func set_light_position(value: Vector3) -> void:
	light_position = Vector3(clampf(value.x, -3.0, 3.0), clampf(value.y, 0.2, 3.5), clampf(value.z, 0.4, 4.0))
	_toon_light_dirty = true
	_update_toon_light()

func _update_toon_light() -> void:
	var world_position: Vector3 = pivot.position + light_position if is_instance_valid(pivot) else light_position
	if not _toon_light_dirty and world_position == _last_toon_light_position:
		return
	for material in _soft_toon_materials:
		material.set_shader_parameter("light_position_world", world_position)
	_last_toon_light_position = world_position
	_toon_light_dirty = false

func set_shading_settings(shadow_power: float, shadow_color_value: Color, edge_power: float, edge_color_value: Color, edge_width_value: float,
		outline_power: float = 0.45, outline_color_value: Color = Color(0.20, 0.16, 0.27), outline_width_value: float = 0.35) -> void:
	shadow_strength = clampf(shadow_power, 0.0, 1.5)
	shadow_tint = Color(clampf(shadow_color_value.r, 0.0, 1.0), clampf(shadow_color_value.g, 0.0, 1.0), clampf(shadow_color_value.b, 0.0, 1.0))
	edge_strength = clampf(edge_power, 0.0, 0.5)
	edge_color = Color(clampf(edge_color_value.r, 0.0, 1.0), clampf(edge_color_value.g, 0.0, 1.0), clampf(edge_color_value.b, 0.0, 1.0))
	edge_width = clampf(edge_width_value, 0.0, 1.0)
	outline_strength = clampf(outline_power, 0.0, 1.0)
	outline_color = Color(clampf(outline_color_value.r, 0.0, 1.0), clampf(outline_color_value.g, 0.0, 1.0), clampf(outline_color_value.b, 0.0, 1.0))
	outline_width = clampf(outline_width_value, 0.0, 1.0)
	_update_toon_shading()

func _update_toon_shading() -> void:
	for material in _soft_toon_materials:
		material.set_shader_parameter("shadow_strength", shadow_strength)
		material.set_shader_parameter("shadow_tint", Vector3(shadow_tint.r, shadow_tint.g, shadow_tint.b))
	if _edge_overlay_material != null:
		_edge_overlay_material.set_shader_parameter("edge_strength", edge_strength)
		_edge_overlay_material.set_shader_parameter("edge_color", Vector3(edge_color.r, edge_color.g, edge_color.b))
		_edge_overlay_material.set_shader_parameter("edge_width", edge_width)
		_edge_overlay_material.set_shader_parameter("outline_strength", outline_strength)
		_edge_overlay_material.set_shader_parameter("outline_color", Vector3(outline_color.r, outline_color.g, outline_color.b))
		_edge_overlay_material.set_shader_parameter("outline_width", outline_width)
		edge_overlay.visible = (edge_strength > 0.001 or outline_strength > 0.001) and not cinematic_active()

func _apply_soft_toon(instance: MeshInstance3D, source_materials: Dictionary) -> void:
	# The imported glTF fallback is unlit. Use the VRM's authored MToon shade
	# factors on runtime materials; keep the supplied file and eye details intact.
	for surface in range(instance.mesh.get_surface_count()):
		var original: Material = instance.mesh.surface_get_material(surface)
		if not original is BaseMaterial3D:
			continue
		var base: BaseMaterial3D = original as BaseMaterial3D
		var material_name: String = base.resource_name.to_lower()
		if material_name.contains("eye") or material_name.contains("brow") or material_name.contains("mouth"):
			continue
		if base.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED or base.albedo_texture == null:
			continue
		var source_material: Dictionary = source_materials.get(base.resource_name, {})
		var mtoon: Dictionary = source_material.get("extensions", {}).get("VRMC_materials_mtoon", {})
		var shade_values: Array = mtoon.get("shadeColorFactor", [1.0, 1.0, 1.0])
		var shade_factor := Vector3(float(shade_values[0]), float(shade_values[1]), float(shade_values[2]))
		var extra_shade: float = 0.25 if material_name.contains("hair") else (0.08 if material_name.contains("skin") else 0.18)
		var toon := ShaderMaterial.new()
		toon.shader = SoftToonShader if base.cull_mode == BaseMaterial3D.CULL_DISABLED else _soft_toon_culled
		toon.set_shader_parameter("base_texture", base.albedo_texture)
		toon.set_shader_parameter("base_factor", base.albedo_color)
		toon.set_shader_parameter("shade_factor", shade_factor)
		toon.set_shader_parameter("shade_shift", float(mtoon.get("shadingShiftFactor", -0.3)))
		toon.set_shader_parameter("shade_toony", float(mtoon.get("shadingToonyFactor", 0.8)))
		toon.set_shader_parameter("extra_shade", extra_shade)
		toon.set_shader_parameter("rim_strength", 0.08 if material_name.contains("hair") else 0.035)
		toon.set_shader_parameter("alpha_cutoff", base.alpha_scissor_threshold)
		instance.set_surface_override_material(surface, toon)
		_soft_toon_materials.append(toon)

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
	edge_overlay.visible = (edge_strength > 0.001 or outline_strength > 0.001) and not cinematic_active()
	pivot.rotation.y = deg_to_rad(yaw + touch.yaw_offset()) # касание груди — отворачивается
	pivot.position = Vector3(travel_offset_px * meters_per_pixel(), 0.0, _cinematic_z)
	_update_toon_light()
	var life_frame: Dictionary = edge_life.tick(delta, state, edge_suspended, cozy_corner_active)
	if animation_workshop_progress >= 0.0:
		for key in edge_life.weights:
			life_frame[key] = 0.0
		life_frame["sketch"] = 1.0
	life_frame["sketch_progress"] = clampf(animation_workshop_progress, 0.0, 1.0) if animation_workshop_progress >= 0.0 else edge_life.sketch_progress
	life_frame["sketch_channels"] = SketchMotion.sample(float(life_frame["sketch_progress"]))
	last_sketch_channels = life_frame["sketch_channels"]
	var gesture_channels: Dictionary = {}
	for gesture in SeatedMotion.kinds():
		if float(life_frame.get(gesture, 0.0)) > 0.001:
			gesture_channels[gesture] = SeatedMotion.sample(gesture, float(edge_life.gesture_progress.get(gesture, 0.0)))
	life_frame["gesture_channels"] = gesture_channels
	life_frame["fold_progress"] = edge_life.fold_progress
	life_frame["admire_progress"] = edge_life.admire_progress
	life_frame["scoot_weight"] = float(edge_scoot.get("weight", 0.0))
	life_frame["scoot_direction"] = float(edge_scoot.get("direction", 0.0))
	var walk_weight: float = float(walk_frame.get("weight", 0.0))
	var idle_blocked: bool = cinematic_active() or context_action != "idle" or edge_suspended
	idle_life.tick(delta, state, idle_blocked, walk_weight)
	rig.hair_enabled = state.hair_enabled
	rig.tick(delta, state.time, gaze, state.wave_weight, state.pet_weight, state.sleep_weight, state.motion_enabled, state.curiosity, state.notice_weight, state.pet_follow, walk_frame, state.welcome_weight)
	var seated: float = state.posture.amount
	gait.apply(walk_frame, state.time, 0.45 * (1.0 - seated) if state.motion_enabled and state.autonomy_enabled and not state.dozing else 0.0)
	if state.posture.kind == "edge":
		edge_pose.apply(seated, state.time, state.wave_weight, state.motion_enabled and not state.dozing, life_frame)
	else:
		posture_driver.apply(seated, state.time, state.wave_weight, state.motion_enabled)
	idle_life.apply(state.time)
	touch.tick(delta)
	touch.apply(state.time, state.posture.amount > 0.5)
	var active_context: String = "portal" if cinematic_active() else context_action
	context_pose.tick(delta, active_context, context_velocity, context_progress, context_impact, yaw)
	context_pose.apply(state.time)
	sketchbook.update_pose(pivot, rig, float(life_frame.get("sketch", 0.0)) if state.posture.kind == "edge" and cozy_corner_active and not edge_suspended and not state.dozing else 0.0, float(life_frame["sketch_progress"]))
	var prop_samples: Dictionary = {}
	var prop_strengths: Dictionary = {}
	var clip_samples: Dictionary = {"sketch": life_frame["sketch_channels"]}
	clip_samples.merge(gesture_channels)
	for gesture in clip_samples:
		var weight: float = float(life_frame.get(gesture, 0.0))
		var gesture_props: Dictionary = (clip_samples[gesture] as Dictionary).get("props", {})
		for prop_id in gesture_props:
			if weight > float(prop_strengths.get(prop_id, -1.0)):
				prop_strengths[prop_id] = weight
				prop_samples[prop_id] = gesture_props[prop_id]
	for prop in animation_props():
		prop.apply_pose(pivot, rig, model_height, prop_samples.get(prop.prop_id, {}))
	paper_star.update_pose(pivot, rig,
		float(life_frame.get("fold", 0.0)) if state.posture.kind == "edge" and cozy_corner_active and not edge_suspended and not state.dozing else 0.0,
		edge_life.fold_progress,
		float(life_frame.get("admire_star", 0.0)) if state.posture.kind == "edge" and cozy_corner_active and not edge_suspended and not state.dozing else 0.0,
		edge_life.admire_progress,
		prop_samples)
	var face_weights: Dictionary = state.expression_weights()
	_voice_mouth = lerpf(_voice_mouth, voice_level, 1.0 - exp(-delta * (20.0 if voice_level > _voice_mouth else 12.0)))
	face_weights["aa"] = maxf(float(face_weights.get("aa", 0.0)), _voice_mouth * 0.72)
	if cozy_corner_active and not edge_suspended and float(life_frame.get("sketch", 0.0)) > 0.01:
		var show: float = smoothstep(0.70, 0.86, float(life_frame["sketch_progress"])) * (1.0 - smoothstep(0.94, 1.0, float(life_frame["sketch_progress"])))
		face_weights["happy"] = maxf(float(face_weights.get("happy", 0.0)), float(life_frame["sketch"]) * show * 0.34)
	if cozy_corner_active and not edge_suspended:
		var paper_show: float = smoothstep(0.70, 0.83, edge_life.fold_progress) * (1.0 - smoothstep(0.93, 1.0, edge_life.fold_progress))
		face_weights["happy"] = maxf(float(face_weights.get("happy", 0.0)), float(life_frame.get("fold", 0.0)) * paper_show * 0.42 + float(life_frame.get("admire_star", 0.0)) * 0.38)
	for key in touch.face():
		face_weights[key] = maxf(float(face_weights.get(key, 0.0)), float(touch.face()[key]))
	expressions.apply(face_weights)
	pet_effect.tick(delta, head_pixel() + state.pet_follow * body_pixels * 0.09 + Vector2(0.0, -body_pixels * 0.055), state.pet_contact_active)

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

## Куда нажали: {"zone": "head|arm|leg|belly|chest|body", "side": "left|right"}.
## По проекциям костей на окно (только своё окно Хоши).
func body_zone(point: Vector2) -> Dictionary:
	if not is_loaded:
		return {"zone": "body", "side": "left"}
	var neck: Vector2 = camera.unproject_position(rig.world_point("neck")) if rig.bones.has("neck") else head_pixel()
	var hips: Vector2 = camera.unproject_position(rig.world_point("hips")) if rig.bones.has("hips") else neck
	# Голова — только выше шеи (круг головы иначе захватывает верх груди).
	if head_contact_hit(point) and point.y < neck.y:
		return {"zone": "head", "side": "left"}
	# Таз: полоса у тазобедренных суставов (шорты) — кружится на одной ножке.
	if absf(point.x - hips.x) < body_pixels * 0.10 and point.y > hips.y - body_pixels * 0.035 and point.y < hips.y + body_pixels * 0.09:
		return {"zone": "hips", "side": "left" if point.x >= hips.x else "right"}
	# Туловище: полоса между шеей и тазом — грудь выше середины, ниже — животик.
	if absf(point.x - lerpf(neck.x, hips.x, 0.5)) < body_pixels * 0.075 and point.y >= neck.y and point.y <= hips.y:
		return {"zone": "chest" if point.y < lerpf(neck.y, hips.y, 0.5) else "belly", "side": "left"}
	var best: Dictionary = {"zone": "body", "side": "left"}
	var best_distance: float = INF
	for limb in [["arm", ["UpperArm", "LowerArm", "Hand"], 0.07], ["leg", ["UpperLeg", "LowerLeg", "Foot"], 0.08]]:
		for which in ["left", "right"]:
			var chain: Array = []
			for part in limb[1]:
				if rig.bones.has(which + part):
					chain.append(camera.unproject_position(rig.world_point(which + part)))
			for index in range(chain.size() - 1):
				var distance: float = point.distance_to(Geometry2D.get_closest_point_to_segment(point, chain[index], chain[index + 1]))
				if distance < body_pixels * float(limb[2]) and distance < best_distance:
					best_distance = distance
					best = {"zone": limb[0], "side": which}
	return best

func head_pixel() -> Vector2:
	if not is_loaded:
		return size * Vector2(0.5, 0.24)
	return camera.unproject_position(rig.world_point("head") + Vector3(0.0, model_height * 0.05, 0.0))

func hand_pixel(side: String) -> Vector2:
	if not is_loaded or side not in ["left", "right"]:
		return size * 0.5
	return camera.unproject_position(rig.world_point(side + "Hand") + Vector3(0.0, model_height * 0.015, 0.0))

func hand_contact_side(point: Vector2) -> String:
	if not visible_avatar_hit(point):
		return ""
	var radius: float = maxf(24.0, body_pixels * 0.065)
	var left_distance: float = point.distance_to(hand_pixel("left"))
	var right_distance: float = point.distance_to(hand_pixel("right"))
	if minf(left_distance, right_distance) > radius:
		return ""
	return "left" if left_distance <= right_distance else "right"

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

func head_contact_hit(point: Vector2) -> bool:
	if not visible_avatar_hit(point):
		return false
	return _head_zone_hit(point, Vector2(maxf(40.0, body_pixels * 0.17), maxf(48.0, body_pixels * 0.20)))

func head_stroke_zone_hit(point: Vector2) -> bool:
	# Follow the projected head with a little room for hair and stale alpha
	# snapshots. Only the initial press requires a visible-avatar hit.
	return _head_zone_hit(point, Vector2(maxf(52.0, body_pixels * 0.22), maxf(62.0, body_pixels * 0.26)))

func _head_zone_hit(point: Vector2, radius: Vector2) -> bool:
	var relative: Vector2 = (point - head_pixel()) / radius
	return relative.length_squared() <= 1.0

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

func animation_props() -> Array:
	var result: Array = []
	if pivot == null:
		return result
	for node in pivot.find_children("*", "Node3D", true, false):
		if node is AnimatedProp and not (node as AnimatedProp).prop_id.is_empty():
			result.append(node)
	return result
