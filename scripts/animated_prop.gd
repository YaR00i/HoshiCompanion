@tool
extends Node3D
## A scene prop that exposes its transform to an Animation resource and workshop.

@export var prop_id: String = ""
@export var display_name: String = "Предмет"
@export_enum("hips", "leftHand", "rightHand") var anchor_bone: String = "hips"
@export var default_position: Vector3 = Vector3.ZERO
@export var default_rotation_degrees: Vector3 = Vector3.ZERO
@export var default_scale: Vector3 = Vector3.ONE
var display_weight: float = 1.0

func default_value(property: String) -> Vector3:
	match property:
		"position": return default_position
		"rotation_degrees": return default_rotation_degrees
		"scale": return default_scale
	return Vector3.ZERO

func apply_pose(pivot: Node3D, rig, height_m: float, sample: Dictionary) -> void:
	var offset: Vector3 = sample.get("position", default_position)
	var anchor_position: Vector3 = pivot.to_local(rig.world_point(anchor_bone))
	var parent_3d: Node3D = get_parent() as Node3D
	position = parent_3d.to_local(pivot.to_global(anchor_position + offset * height_m))
	rotation_degrees = sample.get("rotation_degrees", default_rotation_degrees)
	scale = (sample.get("scale", default_scale) as Vector3) * clampf(display_weight, 0.0, 1.0)
