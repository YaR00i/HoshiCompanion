extends Control
## Schematic view of candidate ledges; never draws pixels from other apps.

signal candidate_selected(index: int)

var window_size: Vector2 = Vector2(1, 1)
var candidates: Array = []
var selected: int = -1

func show_result(data: Dictionary) -> void:
	var size_value: Array = data.get("window", [1, 1])
	window_size = Vector2(maxf(1.0, float(size_value[0])), maxf(1.0, float(size_value[1])))
	candidates = data.get("candidates", [])
	selected = -1
	queue_redraw()

func _map_rect() -> Rect2:
	var available: Vector2 = size - Vector2(36, 32)
	var scale_value: float = minf(available.x / window_size.x, available.y / window_size.y)
	var drawn: Vector2 = window_size * scale_value
	return Rect2((size - drawn) * 0.5, drawn)

func _draw() -> void:
	var frame: Rect2 = _map_rect()
	draw_rect(frame, Color("f8f5fb"), true)
	draw_rect(frame, Color("aa99b2"), false, 2.0)
	for index in range(candidates.size()):
		var item: Dictionary = candidates[index]
		var scale_value: float = frame.size.x / window_size.x
		var from_point: Vector2 = frame.position + Vector2(float(item["x"]), float(item["y"])) * scale_value
		var to_point: Vector2 = from_point + Vector2(float(item["width"]) * scale_value, 0.0)
		var item_row: bool = str(item.get("kind", "")) == "VisualItem"
		var color_value: Color = Color("ed9e75") if index == selected else (Color("458f92") if item_row else Color("8b6bc0"))
		draw_line(from_point, to_point, color_value, 4.0 if index == selected else 2.5, true)
		draw_circle(from_point, 3.0, color_value)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var frame: Rect2 = _map_rect()
	if not frame.has_point(event.position):
		return
	var scale_value: float = frame.size.x / window_size.x
	var best: int = -1
	var distance: float = 12.0
	for index in range(candidates.size()):
		var item: Dictionary = candidates[index]
		var left: float = frame.position.x + float(item["x"]) * scale_value
		var right: float = left + float(item["width"]) * scale_value
		var y: float = frame.position.y + float(item["y"]) * scale_value
		if event.position.x < left - 6.0 or event.position.x > right + 6.0:
			continue
		var gap: float = absf(event.position.y - y)
		if gap < distance:
			distance = gap
			best = index
	if best >= 0:
		selected = best
		candidate_selected.emit(best)
		queue_redraw()
