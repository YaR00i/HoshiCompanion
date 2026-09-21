extends Control
## Lightweight vector decoration inside the app-owned cozy window.
const GOLD := Color("d9b779")
const INK := Color("a18da8")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var c := Vector2(183.0, 65.0)
	draw_circle(c + Vector2(1, 8), 22, Color("e9d8c3"))
	draw_circle(c + Vector2(16, 0), 13, Color("e9d8c3"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(5,-7), c + Vector2(7,-20), c + Vector2(16,-11)]), Color("e9d8c3"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(19,-11), c + Vector2(28,-20), c + Vector2(29,-1)]), Color("e9d8c3"))
	draw_arc(c + Vector2(13,-2), 3, 0.2, PI - 0.2, 12, INK, 1.3, true)
	draw_arc(c + Vector2(22,-2), 3, 0.2, PI - 0.2, 12, INK, 1.3, true)
	draw_arc(c + Vector2(-8,10), 12, 0.1, PI * 1.6, 25, Color("c7aa8c"), 3.5, true)
	for pair in [[Vector2(20,20), 5.0], [Vector2(219,24), 4.0], [Vector2(407,59), 5.0], [Vector2(383,92), 3.0]]:
		_star(pair[0], pair[1])
	draw_circle(Vector2(42,96), 2, GOLD)
	draw_circle(Vector2(421,92), 2, GOLD)

func _star(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for i in range(8):
		var angle: float = -PI / 2.0 + i * PI / 4.0
		points.append(center + Vector2(cos(angle), sin(angle)) * (radius if i % 2 == 0 else radius * 0.33))
	draw_colored_polygon(points, GOLD)
