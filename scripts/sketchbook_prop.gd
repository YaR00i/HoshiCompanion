extends Node3D
## App-owned little book for the cozy-corner seated scene. No avatar assets are changed.

var book: Node3D
var pencil: MeshInstance3D
var star_strokes: Array[MeshInstance3D] = []
var height_m: float = 1.0

func setup(body_height: float) -> void:
	height_m = body_height
	book = Node3D.new()
	book.name = "OpenBook"
	add_child(book)
	_add_box(book, "Cover", Vector3(0.275, 0.205, 0.012) * height_m, Vector3(0.0, 0.0, -0.012) * height_m, Color("8e77a6"))
	_add_box(book, "Page", Vector3(0.255, 0.185, 0.012) * height_m, Vector3(0.0, 0.0, 0.0), Color("fff6dd"))
	_add_box(book, "Spine", Vector3(0.009, 0.193, 0.019) * height_m, Vector3(-0.132, 0.0, -0.002) * height_m, Color("655381"))
	var points: Array[Vector2] = []
	for i in range(5):
		var angle: float = -PI * 0.5 + float(i) * TAU / 5.0
		points.append(Vector2(cos(angle), sin(angle)) * height_m * 0.052)
	var order: Array[int] = [0, 2, 4, 1, 3, 0]
	for index in range(5):
		var i: int = order[index]
		var next: int = order[index + 1]
		var a: Vector2 = points[i]
		var b: Vector2 = points[next]
		var stroke: MeshInstance3D = _add_box(book, "StarStroke", Vector3(height_m * 0.005, a.distance_to(b), height_m * 0.003), Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, height_m * 0.009), Color("d7a74d"))
		stroke.rotation.z = -atan2(b.x - a.x, b.y - a.y)
		star_strokes.append(stroke)
	pencil = _add_box(self, "Pencil", Vector3(0.010, 0.110, 0.010) * height_m, Vector3.ZERO, Color("9871a5"))
	pencil.rotation.z = -0.42
	visible = false

func update_pose(pivot: Node3D, rig, weight: float, progress: float) -> void:
	var w: float = clampf(weight, 0.0, 1.0)
	visible = w > 0.015
	if not visible:
		return
	var show: float = smoothstep(0.70, 0.86, progress) * (1.0 - smoothstep(0.94, 1.0, progress))
	var hip: Vector3 = pivot.to_local(rig.world_point("hips"))
	position = hip + Vector3(0.0, height_m * (-0.065 + show * 0.18), height_m * (0.27 - show * 0.07))
	book.rotation = Vector3(deg_to_rad(-13.0 + show * 10.0), 0.0, sin(progress * 8.0) * 0.018)
	book.scale = Vector3.ONE * smoothstep(0.0, 0.28, w)
	var drawn: float = clampf((progress - 0.13) / 0.52, 0.0, 1.0)
	for i in range(star_strokes.size()):
		star_strokes[i].visible = drawn > float(i) / float(star_strokes.size())
	pencil.position = to_local(rig.world_point("rightHand")) + Vector3(-0.006, 0.035, 0.012) * height_m
	pencil.scale = Vector3.ONE * smoothstep(0.0, 0.28, w) * (1.0 - show * 0.65)

func _add_box(parent: Node3D, title: String, dimensions: Vector3, offset: Vector3, tint: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	mesh.material = material
	var item := MeshInstance3D.new()
	item.name = title
	item.mesh = mesh
	item.position = offset
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(item)
	return item
