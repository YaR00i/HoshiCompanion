@tool
extends EditorNode3DGizmoPlugin
## Кольцо вокруг кости вместо крестика: видно сквозь тело, кликается, цвет по стороне
## (левая — синяя, правая — красная, центр — жёлтый). Кость без дорожки в клипе —
## бледная; выбранная — с двойным кольцом. Размеры задаёт animation_authoring_3d.gd.

const TARGET_SCRIPT: String = "res://scripts/animation_authoring_target.gd"
const LEFT := Color(0.35, 0.62, 1.0)
const RIGHT := Color(1.0, 0.42, 0.42)
const CENTER := Color(1.0, 0.84, 0.3)

var last_selected: Array = []

func _init() -> void:
	create_material("ring", Color.WHITE, false, true, true)

func _get_gizmo_name() -> String:
	return "Hoshi bone ring"

func _get_priority() -> int:
	return 1

func is_ring_target(node: Node) -> bool:
	if not node is Marker3D:
		return false
	var script: Script = node.get_script() as Script
	if script == null or script.resource_path != TARGET_SCRIPT:
		return false
	var anchor: Node = node.get_parent()
	return anchor != null and anchor.get_parent() != null and anchor.get_parent().name == "Bones"

func _has_gizmo(node: Node3D) -> bool:
	return is_ring_target(node)

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node: Node3D = gizmo.get_node_3d()
	var scale: float = maxf(node.global_basis.get_scale().x, 0.0001)
	var axis: Vector3 = node.get("ring_axis")
	var length: float = float(node.get("ring_length")) / scale
	var radius: float = float(node.get("ring_radius")) / scale
	var side: int = int(node.get("ring_side"))
	var small: bool = bool(node.get("ring_small"))
	var tracked: bool = bool(node.get("tracked"))
	var selected: bool = EditorInterface.get_selection().get_selected_nodes().has(node)
	var color: Color = LEFT if side > 0 else (RIGHT if side < 0 else CENTER)
	if not tracked:
		color = color.lerp(Color(0.8, 0.8, 0.8), 0.35)
		color.a = 0.45
	if selected:
		color = color.lerp(Color.WHITE, 0.45)
		color.a = 1.0
	var u: Vector3 = axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var v: Vector3 = axis.cross(u).normalized()
	var center: Vector3 = axis * length * (0.5 if small else 0.35)
	var ring: PackedVector3Array = _circle(center, u, v, radius, 14 if small else 32)
	var lines := PackedVector3Array(ring)
	# Засечка: видно, как кость повёрнута вокруг себя.
	lines.append(center + u * radius)
	lines.append(center + u * radius * 1.45)
	if selected:
		lines.append_array(_circle(center, u, v, radius * 1.18, 14 if small else 32))
	var material: StandardMaterial3D = get_material("ring", gizmo)
	gizmo.add_lines(lines, material, false, color)
	if not small:
		var stick_color: Color = color
		stick_color.a *= 0.5
		gizmo.add_lines(PackedVector3Array([Vector3.ZERO, axis * length]), material, false, stick_color)
	gizmo.add_collision_segments(ring)

func _circle(center: Vector3, u: Vector3, v: Vector3, radius: float, steps: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in range(steps):
		var a: float = TAU * i / steps
		var b: float = TAU * (i + 1) / steps
		points.append(center + (u * cos(a) + v * sin(a)) * radius)
		points.append(center + (u * cos(b) + v * sin(b)) * radius)
	return points
