@tool
extends Node3D
## Godot-native 3D authoring preview. Uses the runtime seated pose controller.

const Source = preload("res://scripts/vrm_source.gd")
const Rig = preload("res://scripts/rig_driver.gd")
const Gait = preload("res://scripts/gait_driver.gd")
const Posture = preload("res://scripts/posture_driver.gd")
const EdgePose = preload("res://scripts/edge_pose.gd")
const Sketchbook = preload("res://scripts/sketchbook_prop.gd")
const PaperStar = preload("res://scripts/paper_star_prop.gd")
const AnimatedProp = preload("res://scripts/animated_prop.gd")
const SketchMotion = preload("res://scripts/sketch_motion.gd")
const PropTracks = preload("res://scripts/prop_track_schema.gd")
const TouchMotion = preload("res://scripts/touch_motion.gd")
const MODEL_PATH: String = "res://assets/Hoshi_v1.vrm"

var rig
var gait
var posture
var edge_pose
var sketchbook
var paper_star
var model_height: float = 1.5
var ready_to_preview: bool = false
var preview_error: String = ""
var _previewed_keys: Array = []
var _previewed_clip: String = ""
@export var show_bone_controls: bool = true
## Автоключ: повернул кольцо кости — ключ на текущем времени записан сам (Ctrl+Z отменяет).
@export var auto_key: bool = true

func _ready() -> void:
	if Engine.is_editor_hint():
		_load_preview.call_deferred()

func _load_preview() -> void:
	if not is_inside_tree() or ready_to_preview:
		return
	if not FileAccess.file_exists(MODEL_PATH):
		preview_error = "Локальная модель не найдена: " + MODEL_PATH
		return
	var loaded: Dictionary = Source.load_avatar(MODEL_PATH)
	if loaded.has("error"):
		preview_error = str(loaded["error"])
		return
	var avatar: Node3D = loaded["model"]
	$PreviewRoot.add_child(avatar)
	_convert_editor_meshes(avatar)
	var merged: AABB = AABB()
	var have_bounds: bool = false
	var mesh_nodes: Array[Node] = avatar.find_children("*", "MeshInstance3D", true, false)
	for mesh in mesh_nodes:
		var instance: MeshInstance3D = mesh as MeshInstance3D
		if instance.mesh == null:
			continue
		var bounds: AABB = (avatar.global_transform.affine_inverse() * instance.global_transform) * instance.get_aabb()
		merged = merged.merge(bounds) if have_bounds else bounds
		have_bounds = true
	if not have_bounds or merged.size.y < 0.1:
		preview_error = "У модели не найдена видимая геометрия."
		return
	model_height = merged.size.y
	avatar.position -= Vector3(merged.get_center().x, merged.position.y, merged.get_center().z)
	rig = Rig.new()
	var rig_report: Dictionary = rig.setup(avatar, loaded["source"], loaded["state"])
	if rig_report.has("error"):
		preview_error = str(rig_report["error"])
		return
	rig.hair_enabled = false
	rig.tick(0.0, 0.0, Vector2.ZERO, 0.0, 0.0, 0.0, false)
	_setup_rings()
	gait = Gait.new()
	gait.setup(rig, model_height)
	posture = Posture.new()
	posture.setup(rig, gait, model_height)
	edge_pose = EdgePose.new()
	edge_pose.setup(posture)
	sketchbook = Sketchbook.new()
	sketchbook.name = "PreviewSketchbook"
	$PreviewRoot.add_child(sketchbook)
	sketchbook.setup(model_height)
	paper_star = PaperStar.new()
	paper_star.name = "PreviewPaperStar"
	$PreviewRoot.add_child(paper_star)
	paper_star.setup(model_height)
	ready_to_preview = true
	set_process(true)
	_update_preview()

func _convert_editor_meshes(avatar: Node3D) -> void:
	# GLTFDocument returns editor-only ImporterMeshInstance3D in editor mode.
	# Convert only the in-memory preview; the source VRM and skin data stay intact.
	for candidate in avatar.find_children("*", "ImporterMeshInstance3D", true, false):
		var imported: ImporterMeshInstance3D = candidate as ImporterMeshInstance3D
		var parent: Node = imported.get_parent()
		var sibling_index: int = imported.get_index()
		var name_before: String = imported.name
		var transform_before: Transform3D = imported.transform
		var mesh: Mesh = imported.mesh.get_mesh() if imported.mesh != null else null
		var skin: Skin = imported.skin
		var skeleton_path: NodePath = imported.skeleton_path
		parent.remove_child(imported)
		imported.free()
		var display := MeshInstance3D.new()
		display.name = name_before
		display.transform = transform_before
		display.mesh = mesh
		display.skin = skin
		display.skeleton = skeleton_path
		parent.add_child(display)
		parent.move_child(display, sibling_index)

func _process(_delta: float) -> void:
	if ready_to_preview and Engine.is_editor_hint():
		_update_preview()

func _update_preview() -> void:
	var player: AnimationPlayer = $AnimationPlayer
	var selected: String = player.selected_clip_name()
	if selected.is_empty():
		return
	var clip: Animation = player.get_animation(selected)
	var keys: Array = _clip_key_snapshot(clip)
	if keys != _previewed_keys:
		_previewed_keys = keys
		if player.assigned_animation == selected:
			# Editing a paused key changes the resource but leaves the animated target
			# at its previously evaluated transform until AnimationPlayer seeks again.
			player.seek(player.current_animation_position, true)
	# The editor timeline can be paused while still assigning the selected clip.
	var time: float = player.current_animation_position
	var progress: float = clampf(time / clip.length, 0.0, 1.0)
	_mark_tracked(clip, selected)
	if TouchMotion.is_touch(selected):
		_update_touch_preview(clip, time)
		return
	$PreviewRoot.rotation = Vector3.ZERO
	rig.skeleton.reset_bone_poses() # после клипа касания не оставлять повёрнутые большие пальцы
	$Targets.visible = selected == "sketch"
	$Corrections.visible = selected != "sketch"
	$Bones.visible = selected != "sketch" and show_bone_controls
	for anchor_node in $Props.get_children():
		var anchor: Node3D = anchor_node as Node3D
		var prop_path: NodePath = NodePath(PropTracks.path_for(str(anchor.name), "position"))
		anchor.visible = clip.find_track(prop_path, Animation.TYPE_POSITION_3D) >= 0 or clip.find_track(prop_path, Animation.TYPE_ROTATION_3D) >= 0 or clip.find_track(prop_path, Animation.TYPE_SCALE_3D) >= 0
	var left_target: Marker3D = $Targets/left_hand if selected == "sketch" else get_node(SketchMotion.correction_path("left_hand")) as Marker3D
	var right_target: Marker3D = $Targets/right_hand if selected == "sketch" else get_node(SketchMotion.correction_path("right_hand")) as Marker3D
	var channels: Dictionary = {
		"head_pitch": $Channels.head_pitch,
		"chest_pitch": $Channels.chest_pitch,
		"left_hand": left_target.position,
		"right_hand": right_target.position,
		"left_hand_rotation": left_target.rotation_degrees.clamp(Vector3.ONE * -SketchMotion.HAND_ROTATION_LIMIT_DEGREES, Vector3.ONE * SketchMotion.HAND_ROTATION_LIMIT_DEGREES),
		"right_hand_rotation": right_target.rotation_degrees.clamp(Vector3.ONE * -SketchMotion.HAND_ROTATION_LIMIT_DEGREES, Vector3.ONE * SketchMotion.HAND_ROTATION_LIMIT_DEGREES),
	}
	# Все кости с кольцами: и с дорожкой, и без (повёрнутое кольцо без дорожки видно
	# сразу, а ключ и дорожку создаёт кнопка «Записать поворот»).
	var has_bone_tracks: bool = false
	for bone_anchor in $Bones.get_children():
		var semantic: String = str(bone_anchor.name)
		var editable: bool = selected != "sketch" and rig.bones.has(semantic)
		bone_anchor.visible = show_bone_controls and editable
		if editable:
			has_bone_tracks = true
			channels["bones"] = channels.get("bones", {})
			channels["bones"][semantic] = bone_anchor.get_node(SketchMotion.BONE_TARGET_NAMES[semantic]).quaternion
	rig.tick(0.0, time, Vector2.ZERO, 0.0, 0.0, 0.0, true)
	var life: Dictionary = {selected: 1.0}
	if selected == "sketch":
		life["sketch_progress"] = progress
		life["sketch_channels"] = channels
	else:
		life["fold_progress"] = progress if selected == "fold" else 0.0
		life["admire_progress"] = progress if selected == "admire_star" else 0.0
		# Anchor rotation controls in the calm seated pose. Their local rotation is
		# the same semantic bone delta that the runtime applies from the clip.
		edge_pose.apply(1.0, time, 0.0, true)
		for bone_anchor in $Bones.get_children():
			if not rig.bones.has(str(bone_anchor.name)):
				continue
			var bone_id: int = int(rig.bones[str(bone_anchor.name)])
			var base_pose: Transform3D = rig.skeleton.get_bone_global_pose(bone_id)
			bone_anchor.global_transform = rig.skeleton.global_transform * base_pose
		# Calculate the wrist after the authored bone pose, before the separate
		# correction track, so its gizmo represents a true offset.
		rig.tick(0.0, time, Vector2.ZERO, 0.0, 0.0, 0.0, true)
		var base_life: Dictionary = life.duplicate()
		if has_bone_tracks:
			base_life["gesture_channels"] = {selected: {"bones": channels["bones"]}}
		# Place correction gizmos at the uncorrected wrists, then apply the clip.
		edge_pose.apply(1.0, time, 0.0, true, base_life)
		$Corrections/left_hand.global_position = rig.world_point("leftHand")
		$Corrections/right_hand.global_position = rig.world_point("rightHand")
		$Corrections/left_hand.scale = Vector3.ONE * model_height
		$Corrections/right_hand.scale = Vector3.ONE * model_height
		rig.tick(0.0, time, Vector2.ZERO, 0.0, 0.0, 0.0, true)
		life["gesture_channels"] = {selected: channels}
	edge_pose.apply(1.0, time, 0.0, true, life)
	var hip: Vector3 = rig.world_point("hips")
	$Targets.position = hip
	$Targets.scale = Vector3.ONE * model_height
	sketchbook.update_pose($PreviewRoot, rig, 1.0 if selected == "sketch" else 0.0, progress)
	var paper_props: Dictionary = {}
	if selected in ["fold", "admire_star"]:
		for prop_id in ["paper_star", "paper_sheet", "paper_shape"]:
			var target: Marker3D = $Props.get_node("%s/%s" % [prop_id, PropTracks.target_name(prop_id)])
			paper_props[prop_id] = {"position": target.position, "rotation_degrees": target.rotation_degrees, "scale": target.scale}
	paper_star.update_pose($PreviewRoot, rig, 1.0 if selected == "fold" else 0.0, progress, 1.0 if selected == "admire_star" else 0.0, progress, paper_props)
	if selected in ["fold", "admire_star"]:
		$Props/paper_star.position = hip
		$Props/paper_star.scale = Vector3.ONE * model_height
		for prop_id in ["paper_sheet", "paper_shape"]:
			var anchor: Node3D = $Props.get_node(prop_id)
			anchor.global_transform = paper_star.global_transform
			anchor.scale = Vector3.ONE * model_height
	for candidate in $PreviewRoot.find_children("*", "Node3D", true, false):
		if not candidate is AnimatedProp:
			continue
		var prop: AnimatedProp = candidate as AnimatedProp
		var anchor: Node3D = $Props.get_node_or_null(NodePath(prop.prop_id)) as Node3D
		if anchor == null:
			preview_error = "Нет цели для предмета: " + prop.prop_id
			continue
		var target: Node3D = anchor.get_node_or_null(PropTracks.target_name(prop.prop_id)) as Node3D
		if target == null:
			preview_error = "Нет узла Target для предмета: " + prop.prop_id
			continue
		anchor.position = rig.world_point(prop.anchor_bone)
		anchor.scale = Vector3.ONE * model_height
		prop.apply_pose($PreviewRoot, rig, model_height, {
			"position": target.position,
			"rotation_degrees": target.rotation_degrees,
			"scale": target.scale,
		})

## Реакция на касание (touch_*): Хоши стоит; у каждой кости с дорожкой — стрелка
## в её позе до собственного поворота (после родителей), поворот стрелки = ключ.
## Channels: touch_yaw — поворот тела, hips_offset — сдвиг таза (доли роста).
## Лицо (face_happy/face_angry) в просмотре не показывается — только в Хоши.
func _update_touch_preview(clip: Animation, time: float) -> void:
	$Targets.visible = false
	$Corrections.visible = false
	$Bones.visible = show_bone_controls
	for anchor_node in $Props.get_children():
		(anchor_node as Node3D).visible = false
	# Касания — без предметов: спрятать блокнот, мелок и бумагу прошлых сценок.
	sketchbook.update_pose($PreviewRoot, rig, 0.0, 0.0)
	paper_star.update_pose($PreviewRoot, rig, 0.0, 0.0, 0.0, 0.0, {})
	$PreviewRoot.rotation = Vector3(0.0, deg_to_rad($Channels.touch_yaw), 0.0)
	var skeleton: Skeleton3D = rig.skeleton
	skeleton.reset_bone_poses() # иначе кости, которые поза не сбрасывает (большой палец), копили бы поворот
	rig.tick(0.0, time, Vector2.ZERO, 0.0, 0.0, 0.0, false)
	var hips: int = int(rig.bones["hips"])
	var parent: int = skeleton.get_bone_parent(hips)
	var parent_basis: Basis = skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + parent_basis.inverse() * ($Channels.hips_offset * model_height))
	var ordered: Array = []
	for bone_anchor in $Bones.get_children():
		var semantic: String = str(bone_anchor.name)
		var editable: bool = rig.bones.has(semantic)
		(bone_anchor as Node3D).visible = show_bone_controls and editable
		if editable:
			ordered.append([int(rig.bones[semantic]), bone_anchor])
	ordered.sort_custom(func(a, b): return a[0] < b[0]) # родители раньше детей
	for item in ordered:
		var bone_id: int = item[0]
		var bone_anchor: Node3D = item[1]
		bone_anchor.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(bone_id)
		var marker: Node3D = bone_anchor.get_node_or_null(NodePath(SketchMotion.BONE_TARGET_NAMES[str(bone_anchor.name)])) as Node3D
		if marker != null:
			skeleton.set_bone_pose_rotation(bone_id, (skeleton.get_bone_pose_rotation(bone_id) * marker.quaternion).normalized())

## Кольца: бледные у костей без дорожки. При смене клипа кольца без дорожки
## возвращаются в покой — иначе в них остался бы поворот из прошлого клипа.
func _mark_tracked(clip: Animation, selected: String) -> void:
	var switched: bool = selected != _previewed_clip
	_previewed_clip = selected
	for bone_anchor in $Bones.get_children():
		var marker: Node3D = bone_anchor.get_node_or_null(NodePath(SketchMotion.BONE_TARGET_NAMES.get(str(bone_anchor.name), ""))) as Node3D
		if marker == null:
			continue
		var has_track: bool = clip.find_track(NodePath(SketchMotion.bone_path(str(bone_anchor.name))), Animation.TYPE_ROTATION_3D) >= 0
		marker.set("tracked", has_track)
		if switched and not has_track:
			marker.quaternion = Quaternion.IDENTITY

# Кость → следующая по цепочке (куда она «смотрит»). У концевых — продолжение родителя.
const RING_NEXT := {
	"hips": "spine", "spine": "chest", "chest": "upperChest", "upperChest": "neck", "neck": "head",
	"Shoulder": "UpperArm", "UpperArm": "LowerArm", "LowerArm": "Hand", "Hand": "MiddleProximal",
	"UpperLeg": "LowerLeg", "LowerLeg": "Foot", "Foot": "Toes",
	"ThumbMetacarpal": "ThumbProximal", "ThumbProximal": "ThumbDistal",
	"IndexProximal": "IndexIntermediate", "IndexIntermediate": "IndexDistal",
	"MiddleProximal": "MiddleIntermediate", "MiddleIntermediate": "MiddleDistal",
	"RingProximal": "RingIntermediate", "RingIntermediate": "RingDistal",
	"LittleProximal": "LittleIntermediate", "LittleIntermediate": "LittleDistal",
}
# Радиус кольца, м (для роста 1.5 м): туловище охватывает тело, суставы — конечность.
const RING_RADIUS := {
	"hips": 0.15, "spine": 0.12, "chest": 0.13, "upperChest": 0.12, "neck": 0.045, "head": 0.11, "jaw": 0.03,
	"Shoulder": 0.035, "UpperArm": 0.045, "LowerArm": 0.035, "Hand": 0.03,
	"UpperLeg": 0.075, "LowerLeg": 0.055, "Foot": 0.045, "Toes": 0.03, "Eye": 0.016,
}

func _setup_rings() -> void:
	var skeleton: Skeleton3D = rig.skeleton
	var world_scale: float = skeleton.global_basis.get_scale().x
	var size: float = model_height / 1.5
	for bone_anchor in $Bones.get_children():
		var semantic: String = str(bone_anchor.name)
		var marker: Node3D = bone_anchor.get_node_or_null(NodePath(SketchMotion.BONE_TARGET_NAMES.get(semantic, ""))) as Node3D
		if marker == null or not marker.has_method("set_ring") or not rig.bones.has(semantic):
			continue
		var side: int = 1 if semantic.begins_with("left") else (-1 if semantic.begins_with("right") else 0)
		var part: String = semantic.trim_prefix("left").trim_prefix("right")
		var bone: int = int(rig.bones[semantic])
		var own: Transform3D = skeleton.get_bone_global_rest(bone)
		var to_local: Basis = own.basis.orthonormalized().inverse()
		var direction: Vector3 = Vector3.ZERO
		var next_part: String = str(RING_NEXT.get(part, ""))
		var next_semantic: String = next_part if side == 0 else ("left" if side > 0 else "right") + next_part
		if next_semantic == "upperChest" and not rig.bones.has("upperChest"):
			next_semantic = "neck"
		if part == "Eye":
			direction = Vector3.BACK * 0.02 / world_scale # взгляд вперёд (лицом к +Z)
		elif rig.bones.has(next_semantic):
			direction = skeleton.get_bone_global_rest(int(rig.bones[next_semantic])).origin - own.origin
		else:
			var parent: int = skeleton.get_bone_parent(bone)
			direction = own.origin - skeleton.get_bone_global_rest(parent).origin if parent >= 0 else Vector3.UP
			if part == "head":
				direction = direction.normalized() * 0.2 * size / world_scale
			else:
				direction *= 0.8
		var length: float = direction.length() * world_scale
		var small: bool = part in ["Eye", "jaw"] or part.contains("Thumb") or part.contains("Index") or part.contains("Middle") or part.contains("Ring") or part.contains("Little")
		var radius: float = float(RING_RADIUS.get(part, 0.0)) * size
		if radius <= 0.0:
			radius = clampf(length * 0.45, 0.006 * size, 0.012 * size)
		marker.call("set_ring", to_local * direction, length, radius, side, small)

func _clip_key_snapshot(clip: Animation) -> Array:
	var keys: Array = [clip.get_instance_id(), clip.length, clip.get_track_count()]
	for track in range(clip.get_track_count()):
		keys.append(clip.track_get_path(track))
		keys.append(clip.track_get_type(track))
		keys.append(clip.track_is_enabled(track))
		keys.append(clip.track_get_key_count(track))
		for key in range(clip.track_get_key_count(track)):
			keys.append(clip.track_get_key_time(track, key))
			keys.append(clip.track_get_key_value(track, key))
	return keys
