extends Node3D
## Procedural paper used only by the seated cozy-corner folding scene.

var paper: Node3D
var star: MeshInstance3D
var height_m: float = 1.0

func setup(body_height: float) -> void:
	height_m = body_height
	paper = Node3D.new()
	paper.name = "PaperSquare"
	add_child(paper)
	_add_box(paper, "Sheet", Vector3(0.145, 0.145, 0.004) * height_m, Vector3.ZERO, Color("fff4d8"))
	for angle in [-0.75, 0.75]:
		var crease: MeshInstance3D = _add_box(paper, "FoldCrease", Vector3(0.002, 0.13, 0.001) * height_m, Vector3(0.0, 0.0, 0.003) * height_m, Color("dcc29a"))
		crease.rotation.z = angle
	star = MeshInstance3D.new()
	star.name = "FoldedStar"
	star.mesh = _star_mesh()
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(star)
	visible = false

func update_pose(pivot: Node3D, rig, fold_weight: float, fold_progress: float, admire_weight: float, admire_progress: float, props: Dictionary = {}) -> void:
	var fold: float = clampf(fold_weight, 0.0, 1.0)
	var admire: float = clampf(admire_weight, 0.0, 1.0)
	visible = maxf(fold, admire) > 0.015
	if not visible:
		return
	var h: float = height_m
	var showing: float = smoothstep(0.70, 0.83, fold_progress) * (1.0 - smoothstep(0.93, 1.0, fold_progress))
	var admire_show: float = smoothstep(0.0, 0.23, admire_progress) * (1.0 - smoothstep(0.80, 1.0, admire_progress))
	var raised: float = maxf(showing * fold, admire_show * admire)
	var hip: Vector3 = pivot.to_local(rig.world_point("hips"))
	position = hip + Vector3(0.0, h * (0.015 + raised * 0.14), h * (0.29 - raised * 0.035))
	rotation.z = sin(fold_progress * TAU * 2.0) * 0.07 * fold + sin(admire_progress * TAU) * 0.05 * admire
	rotation.y = sin(fold_progress * TAU * 1.5) * 0.13 * fold
	paper.visible = fold > 0.015 and fold_progress < 0.70
	if paper.visible:
		var folding: float = smoothstep(0.12, 0.65, fold_progress)
		paper.scale = Vector3(1.0 - folding * 0.34, 1.0 - folding * 0.28, 1.0) * fold
		paper.rotation.z = sin(fold_progress * TAU * 3.0) * 0.11
	star.visible = (fold_progress >= 0.57 and fold > 0.015) or admire > 0.015
	if star.visible:
		var opened: float = smoothstep(0.57, 0.75, fold_progress) * (1.0 - smoothstep(0.94, 1.0, fold_progress)) * fold
		star.scale = Vector3.ONE * maxf(opened, admire_show * admire)
	if props.has("paper_star"):
		var root_sample: Dictionary = props["paper_star"]
		position = hip + (root_sample.get("position", Vector3.ZERO) as Vector3) * h
		rotation_degrees = root_sample.get("rotation_degrees", Vector3.ZERO)
		scale = root_sample.get("scale", Vector3.ONE)
	if props.has("paper_sheet"):
		var sheet_sample: Dictionary = props["paper_sheet"]
		paper.position = (sheet_sample.get("position", Vector3.ZERO) as Vector3) * h
		paper.rotation_degrees = sheet_sample.get("rotation_degrees", Vector3.ZERO)
		paper.scale = (sheet_sample.get("scale", Vector3.ZERO) as Vector3) * fold
		paper.visible = paper.scale.length_squared() > 0.0001 and fold > 0.015
	if props.has("paper_shape"):
		var shape_sample: Dictionary = props["paper_shape"]
		star.position = (shape_sample.get("position", Vector3.ZERO) as Vector3) * h
		star.rotation_degrees = shape_sample.get("rotation_degrees", Vector3.ZERO)
		star.scale = (shape_sample.get("scale", Vector3.ZERO) as Vector3) * maxf(fold, admire)
		star.visible = star.scale.length_squared() > 0.0001 and maxf(fold, admire) > 0.015

func _star_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var shades: Array[Color] = [Color("f5d99a"), Color("e9bf79"), Color("f9e2ad"), Color("e8bc77"), Color("f2d08e")]
	var points: Array[Vector2] = []
	for i in range(10):
		var angle: float = -PI * 0.5 + float(i) * PI / 5.0
		var radius: float = height_m * (0.075 if i % 2 == 0 else 0.033)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	for i in range(10):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % 10]
		vertices.append_array(PackedVector3Array([Vector3(0.0, 0.0, 0.005), Vector3(a.x, a.y, 0.005), Vector3(b.x, b.y, 0.005)]))
		var tint: Color = shades[int(i / 2)]
		colors.append_array(PackedColorArray([tint.lightened(0.06), tint, tint]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, material)
	return mesh

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
