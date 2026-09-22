extends Node3D
## Procedural magical doorway. No image assets: frame, door leaf and star field are generated locally.
var frame_root: Node3D
var leaf_pivot: Node3D
var portal: MeshInstance3D
var leaf: MeshInstance3D
var glow_light: OmniLight3D
var star_material: ShaderMaterial
var height_m: float = 1.5
var opening_size: Vector2 = Vector2.ZERO
var frame_bar: float = 0.0

func setup(model_height: float) -> void:
	height_m = maxf(0.5, model_height)
	if frame_root != null:
		frame_root.queue_free()
	frame_root = Node3D.new()
	frame_root.name = "StarDoor"
	add_child(frame_root)
	var h: float = height_m * 1.08
	var w: float = height_m * 0.64
	var bar: float = height_m * 0.045
	var depth: float = height_m * 0.042
	opening_size = Vector2(w, h)
	frame_bar = bar
	frame_root.position = Vector3(0.0, h * 0.50, -height_m * 0.10)

	portal = MeshInstance3D.new()
	var quad := QuadMesh.new()
	# Bleed beneath every inner edge of the frame: there must never be transparent
	# slits between the star field and the jamb while the leaf is open.
	quad.size = Vector2(w + bar * 1.40, h + bar * 1.10)
	portal.mesh = quad
	portal.position = Vector3(0.0, 0.0, -depth * 1.45)
	star_material = ShaderMaterial.new()
	star_material.shader = _star_shader()
	portal.material_override = star_material
	frame_root.add_child(portal)

	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("d8b875")
	gold.metallic = 0.22
	gold.roughness = 0.34
	gold.emission_enabled = true
	gold.emission = Color("765797")
	gold.emission_energy_multiplier = 0.42

	var inner_glow := StandardMaterial3D.new()
	inner_glow.albedo_color = Color("9b7bd2")
	inner_glow.roughness = 0.28
	inner_glow.emission_enabled = true
	inner_glow.emission = Color("a986ef")
	inner_glow.emission_energy_multiplier = 1.25

	_box(Vector3(bar, h + bar * 0.55, depth), Vector3(-w * 0.5 - bar * 0.5, 0.0, 0.0), gold)
	_box(Vector3(bar, h + bar * 0.55, depth), Vector3(w * 0.5 + bar * 0.5, 0.0, 0.0), gold)
	_box(Vector3(w + bar * 2.0, bar, depth), Vector3(0.0, h * 0.5 + bar * 0.5, 0.0), gold)
	_box(Vector3(w + bar * 1.55, bar * 0.52, depth * 0.92), Vector3(0.0, -h * 0.5 - bar * 0.18, depth * 0.02), gold)

	var glow_bar: float = bar * 0.22
	_box(Vector3(glow_bar, h * 0.985, depth * 0.36), Vector3(-w * 0.5 + glow_bar * 0.48, 0.0, -depth * 0.42), inner_glow)
	_box(Vector3(glow_bar, h * 0.985, depth * 0.36), Vector3(w * 0.5 - glow_bar * 0.48, 0.0, -depth * 0.42), inner_glow)
	_box(Vector3(w * 0.985, glow_bar, depth * 0.36), Vector3(0.0, h * 0.5 - glow_bar * 0.48, -depth * 0.42), inner_glow)
	_box(Vector3(w * 0.985, glow_bar, depth * 0.36), Vector3(0.0, -h * 0.5 + glow_bar * 0.48, -depth * 0.42), inner_glow)

	leaf_pivot = Node3D.new()
	leaf_pivot.position = Vector3(-w * 0.5, 0.0, depth * 0.18)
	frame_root.add_child(leaf_pivot)
	leaf = MeshInstance3D.new()
	var door_depth: float = depth * 0.72
	var leaf_width: float = w * 0.995
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(leaf_width, h * 0.988, door_depth)
	leaf.mesh = door_mesh
	leaf.position = Vector3(leaf_width * 0.5, 0.0, 0.0)

	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color("32213b")
	door_mat.metallic = 0.10
	door_mat.roughness = 0.47
	door_mat.emission_enabled = true
	door_mat.emission = Color("4a315f")
	door_mat.emission_energy_multiplier = 0.14
	leaf.material_override = door_mat
	leaf_pivot.add_child(leaf)

	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color("c9a66b")
	trim.metallic = 0.30
	trim.roughness = 0.30
	trim.emission_enabled = true
	trim.emission = Color("5c456e")
	trim.emission_energy_multiplier = 0.22
	_panel_outline(leaf, Vector2(leaf_width * 0.68, h * 0.30), h * 0.19, door_depth, trim)
	_panel_outline(leaf, Vector2(leaf_width * 0.68, h * 0.34), -h * 0.20, door_depth, trim)

	var knob := MeshInstance3D.new()
	var knob_mesh := SphereMesh.new()
	var knob_radius: float = height_m * 0.018
	knob_mesh.radius = knob_radius
	knob_mesh.height = knob_radius * 2.0
	knob.mesh = knob_mesh
	knob.position = Vector3(leaf_width * 0.36, -h * 0.01, door_depth * 0.56)
	knob.material_override = gold
	leaf.add_child(knob)

	glow_light = OmniLight3D.new()
	glow_light.position = Vector3(0.0, 0.0, depth * 0.8)
	glow_light.light_color = Color("b69bff")
	glow_light.light_energy = 0.0
	glow_light.omni_range = height_m * 2.5
	glow_light.shadow_enabled = false
	frame_root.add_child(glow_light)
	frame_root.visible = false

func _panel_outline(parent: Node3D, panel_size: Vector2, center_y: float, depth: float, material: Material) -> void:
	var edge: float = height_m * 0.010
	var z: float = depth * 0.56
	_box_child(parent, Vector3(panel_size.x, edge, edge * 0.55), Vector3(0.0, center_y + panel_size.y * 0.5, z), material)
	_box_child(parent, Vector3(panel_size.x, edge, edge * 0.55), Vector3(0.0, center_y - panel_size.y * 0.5, z), material)
	_box_child(parent, Vector3(edge, panel_size.y, edge * 0.55), Vector3(-panel_size.x * 0.5, center_y, z), material)
	_box_child(parent, Vector3(edge, panel_size.y, edge * 0.55), Vector3(panel_size.x * 0.5, center_y, z), material)

func _box(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	return _box_child(frame_root, size, pos, material)

func _box_child(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	item.position = pos
	item.material_override = material
	parent.add_child(item)
	return item

func set_state(visibility: float, open_amount: float, time: float) -> void:
	if frame_root == null:
		return
	var v: float = clampf(visibility, 0.0, 1.0)
	var opened: float = clampf(open_amount, 0.0, 1.0)
	frame_root.visible = v > 0.005
	if not frame_root.visible:
		return
	var s: float = lerpf(0.84, 1.0, smoothstep(0.0, 1.0, v))
	frame_root.scale = Vector3(s, s, s)
	# Keep the leaf on the camera side of the portal and stop before an overswing.
	leaf_pivot.rotation.y = deg_to_rad(-82.0) * smoothstep(0.0, 1.0, opened)
	glow_light.light_energy = 0.72 * v * (0.30 + opened * 0.70)
	if star_material != null:
		star_material.set_shader_parameter("time_value", time)
		star_material.set_shader_parameter("glow", v)

func hide_door() -> void:
	if frame_root != null:
		frame_root.visible = false

func _star_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float time_value = 0.0;
uniform float glow = 1.0;
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
void fragment() {
	vec2 uv = UV;
	vec2 drift = vec2(time_value * 0.006, time_value * -0.002);
	vec2 cells = floor((uv + drift) * vec2(68.0, 96.0));
	float h = hash21(cells);
	float stars = smoothstep(0.982, 1.0, h);
	float twinkle = 0.68 + 0.32 * sin(time_value * 2.1 + h * 17.0);
	float ribbon = 0.5 + 0.5 * sin((uv.y + time_value * 0.014) * 8.0 + sin(uv.x * 7.5) * 1.4);
	float cloud = 0.5 + 0.5 * sin(uv.x * 5.2 - uv.y * 3.6 + time_value * 0.018);
	vec3 deep = vec3(0.014, 0.010, 0.060);
	vec3 violet = vec3(0.120, 0.046, 0.220);
	vec3 blue = vec3(0.045, 0.090, 0.180);
	vec3 sky = mix(deep, violet, uv.y * 0.58 + ribbon * 0.16);
	sky = mix(sky, blue, cloud * 0.16);
	vec3 star = vec3(1.0, 0.88, 0.64) * stars * twinkle * (2.0 + h * 2.2);
	ALBEDO = sky + star;
	EMISSION = (sky * 0.62 + star) * glow;
	ROUGHNESS = 1.0;
}
"""
	return shader
