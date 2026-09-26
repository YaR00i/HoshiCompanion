extends Control
## Draws app-owned contact guides over the real Hoshi SubViewport.

var stage
var enabled: bool = true
var selected_prop_id: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if not enabled or stage == null or not stage.is_loaded:
		return
	for prop in stage.animation_props():
		if not prop.is_visible_in_tree():
			continue
		var point: Vector2 = _screen(prop.global_position)
		var selected: bool = prop.prop_id == selected_prop_id
		_mark(point, Color("ffca70") if selected else Color("ddb6ff"))
		if selected:
			draw_arc(point, 8.0, 0.0, TAU, 24, Color("ffca70"), 1.5)
			draw_string(get_theme_default_font(), point + Vector2(10.0, 19.0), prop.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ffca70"))
	if not stage.sketchbook.visible:
		return
	var sample: Dictionary = stage.last_sketch_channels
	if sample.is_empty():
		return
	var hip_local: Vector3 = stage.pivot.to_local(stage.rig.world_point("hips"))
	for side in ["left", "right"]:
		var authored: Vector3 = sample.get(side + "_hand", Vector3.ZERO)
		var target_world: Vector3 = stage.pivot.to_global(hip_local + authored * stage.model_height)
		var actual_world: Vector3 = stage.rig.world_point(side + "Hand")
		var side_x: float = 1.0 if side == "left" else -1.0
		var corner_world: Vector3 = stage.sketchbook.book.to_global(Vector3(side_x * 0.1275, 0.0925, 0.012) * stage.model_height)
		var target: Vector2 = _screen(target_world)
		var actual: Vector2 = _screen(actual_world)
		var corner: Vector2 = _screen(corner_world)
		draw_line(target, corner, Color(1.0, 0.78, 0.42, 0.7), 1.5)
		draw_line(target, actual, Color(0.45, 0.9, 1.0, 0.65), 1.5)
		_mark(corner, Color("ffca70"))
		_mark(target, Color("74ddff"))
		_mark(actual, Color("7ef0b4"))

func _screen(world: Vector3) -> Vector2:
	var viewport_size: Vector2 = Vector2(stage.view.size)
	return stage.camera.unproject_position(world) * (size / viewport_size)

func _mark(point: Vector2, color: Color) -> void:
	draw_circle(point, 5.0, Color.BLACK)
	draw_circle(point, 3.5, color)
