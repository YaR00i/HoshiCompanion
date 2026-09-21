extends Node3D
## Procedural magical doorway. No image assets: frame, door leaf and star field are generated locally.
var frame_root: Node3D
var leaf_pivot: Node3D
var portal: MeshInstance3D
var leaf: MeshInstance3D
var glow_light: OmniLight3D
var star_material: ShaderMaterial
var height_m: float = 1.5

func setup(model_height: float) -> void:
	height_m = maxf(0.5, model_height)
	if frame_root != null:
		frame_root.queue_free()
	frame_root = Node3D.new()
	frame_root.name = "StarDoor"
	add_child(frame_root)
	var h: float = height_m * 1.10
	var w: float = height_m * 0.66
	var bar: float = height_m * 0.045
	var depth: float = height_m * 0.035
	frame_root.position = Vector3(0.0, h * 0.50, -height_m * 0.09)
	portal = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w * 0.88, h * 0.91)
	portal.mesh = quad
	portal.position = Vector3(0.0, 0.0, -depth * 0.9)
	star_material = ShaderMaterial.new()
	star_material.shader = _star_shader()
	portal.material_override = star_material
	frame_root.add_child(portal)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("d9b779")
	gold.emission_enabled = true
	gold.emission = Color("8061a8")
	gold.emission_energy_multiplier = 0.65
	gold.roughness = 0.42
	_box(Vector3(bar, h, depth), Vector3(-w * 0.5 - bar * 0.5, 0.0, 0.0), gold)
	_box(Vector3(bar, h, depth), Vector3(w * 0.5 + bar * 0.5, 0.0, 0.0), gold)
	_box(Vector3(w + bar * 2.0, bar, depth), Vector3(0.0, h * 0.5 + bar * 0.5, 0.0), gold)
	leaf_pivot = Node3D.new()
	leaf_pivot.position = Vector3(-w * 0.5, 0.0, depth * 0.1)
	frame_root.add_child(leaf_pivot)
	leaf = MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(w, h, depth * 0.55)
	leaf.mesh = door_mesh
	leaf.position = Vector3(w * 0.5, 0.0, 0.0)
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color("37263f")
	door_mat.metallic = 0.08
	door_mat.roughness = 0.54
	door_mat.emission_enabled = true
	door_mat.emission = Color("4a315f")
	door_mat.emission_energy_multiplier = 0.16
	leaf.material_override = door_mat
	leaf_pivot.add_child(leaf)
	glow_light = OmniLight3D.new()
	glow_light.light_color = Color("b69bff")
	glow_light.light_energy = 0.0
	glow_light.omni_range = height_m * 2.4
	glow_light.shadow_enabled = false
	frame_root.add_child(glow_light)
	frame_root.visible = false

func _box(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	item.position = pos
	item.material_override = material
	frame_root.add_child(item)
	return item

func set_state(visibility: float, open_amount: float, time: float) -> void:
	if frame_root == null:
		return
	var v: float = clampf(visibility, 0.0, 1.0)
	var opened: float = clampf(open_amount, 0.0, 1.0)
	frame_root.visible = v > 0.005
	if not frame_root.visible:
		return
	var s: float = lerpf(0.78, 1.0, smoothstep(0.0, 1.0, v))
	frame_root.scale = Vector3(s, s, s)
	leaf_pivot.rotation.y = deg_to_rad(-106.0) * smoothstep(0.0, 1.0, opened)
	glow_light.light_energy = 0.55 * v * (0.35 + opened * 0.65)
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
	vec2 cells = floor((uv + drift) * vec2(64.0, 92.0));
	float h = hash21(cells);
	float stars = smoothstep(0.982, 1.0, h);
	float haze = 0.5 + 0.5 * sin((uv.y + time_value * 0.015) * 8.0 + sin(uv.x * 7.0));
	vec3 deep = vec3(0.018, 0.012, 0.070);
	vec3 violet = vec3(0.115, 0.045, 0.205);
	vec3 sky = mix(deep, violet, uv.y * 0.65 + haze * 0.12);
	vec3 star = vec3(1.0, 0.88, 0.62) * stars * (1.8 + h * 2.0);
	ALBEDO = sky + star;
	EMISSION = (sky * 0.55 + star) * glow;
	ROUGHNESS = 1.0;
}
"""
	return shader
