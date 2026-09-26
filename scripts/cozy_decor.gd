extends Control
## Lightweight vector decoration inside the app-owned cozy window.
const GOLD := Color("d9b779")
const INK := Color("a18da8")
var star_count: int = 0
var star_revision: int = 0
var presenting_star: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_stars(count: int, revision: int) -> void:
	if star_count == count and star_revision == revision:
		return
	star_count = clampi(count, 0, 3)
	star_revision = maxi(0, revision)
	queue_redraw()

func set_presenting(active: bool) -> void:
	if presenting_star == active:
		return
	presenting_star = active
	queue_redraw()

func _draw() -> void:
	# A pinned card holds up to three folded stars made during this session.
	draw_rect(Rect2(Vector2(355, 43), Vector2(61, 59)), Color("eadccf"), true)
	draw_rect(Rect2(Vector2(352, 40), Vector2(61, 59)), Color("fff9ed"), true)
	draw_rect(Rect2(Vector2(352, 40), Vector2(61, 59)), Color("d7c4d6"), false, 1.2)
	draw_circle(Vector2(382, 43), 3.5, INK)
	var displayed: int = maxi(0, star_count - (1 if presenting_star else 0))
	if displayed == 0:
		_star_outline(Vector2(383, 69), 11.0)
	else:
		for i in range(displayed):
			var x: float = 383.0 if displayed == 1 else (372.0 + float(i) * 21.0 if displayed == 2 else 367.0 + float(i) * 16.0)
			var y: float = 68.0 + float((star_revision + i) % 2) * 5.0
			_folded_star(Vector2(x, y), 11.0 if displayed == 1 else (9.0 if displayed == 2 else 8.0), (star_revision + i) % 3)
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

func _star_outline(center: Vector2, radius: float) -> void:
	var points: PackedVector2Array = _paper_points(center, radius)
	points.append(points[0])
	draw_polyline(points, Color("d9c7ca"), 1.0, true)

func _folded_star(center: Vector2, radius: float, shade: int) -> void:
	var colors: Array[Color] = [Color("e9c982"), Color("e5b9aa"), Color("cdb9da")]
	var points: PackedVector2Array = _paper_points(center, radius)
	draw_colored_polygon(points, colors[shade])
	for i in range(5):
		var tip: Vector2 = points[i * 2]
		draw_line(center, center.lerp(tip, 0.85), colors[shade].darkened(0.16), 0.7, true)

func _paper_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(10):
		var angle: float = -PI / 2.0 + float(i) * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * (radius if i % 2 == 0 else radius * 0.45))
	return points
