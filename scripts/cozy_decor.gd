extends Control
## Lightweight vector decoration inside the app-owned cozy window.
const GOLD := Color("d9b779")
const INK := Color("a18da8")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	# A pinned drawing quietly echoes the notebook scene without competing with Hoshi.
	draw_rect(Rect2(Vector2(355, 43), Vector2(61, 59)), Color("eadccf"), true)
	draw_rect(Rect2(Vector2(352, 40), Vector2(61, 59)), Color("fff9ed"), true)
	draw_rect(Rect2(Vector2(352, 40), Vector2(61, 59)), Color("d7c4d6"), false, 1.2)
	draw_circle(Vector2(382, 43), 3.5, INK)
	_star(Vector2(383, 69), 12.0)
	draw_line(Vector2(366, 87), Vector2(400, 87), Color("ddc8d7"), 1.0, true)
	for pair in [[Vector2(20,20), 5.0], [Vector2(219,24), 4.0], [Vector2(330,72), 2.5], [Vector2(426,103), 3.0]]:
		_star(pair[0], pair[1])
	draw_circle(Vector2(42,97), 2, GOLD)

func _star(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for i in range(8):
		var angle: float = -PI / 2.0 + i * PI / 4.0
		points.append(center + Vector2(cos(angle), sin(angle)) * (radius if i % 2 == 0 else radius * 0.33))
	draw_colored_polygon(points, GOLD)
