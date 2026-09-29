extends Node2D
## Звёздочки, которые вылетают из рисунка или звёздочки, когда ты ответил на
## сценку «Ждёт» (edge_life.answer_wait). Рисуется поверх Хоши, как pet_effect.

const COLORS: Array[Color] = [Color(1.0, 0.86, 0.36), Color(1.0, 0.72, 0.86), Color(1.0, 0.97, 0.88)]
var _stars: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func burst(point: Vector2, body_pixels: float, count: int = 14) -> void:
	var unit: float = maxf(body_pixels, 80.0)
	for i in range(count):
		var angle: float = -PI * 0.5 + _rng.randf_range(-1.15, 1.15)
		var speed: float = unit * _rng.randf_range(0.32, 0.62)
		_stars.append({
			"pos": point + Vector2(_rng.randf_range(-0.03, 0.03), _rng.randf_range(-0.02, 0.02)) * unit,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"spin": _rng.randf_range(-4.0, 4.0),
			"angle": _rng.randf_range(0.0, TAU),
			"size": unit * _rng.randf_range(0.026, 0.045),
			"age": 0.0,
			"life": _rng.randf_range(1.0, 1.6),
			"color": COLORS[i % COLORS.size()],
		})

func active() -> bool:
	return not _stars.is_empty()

func tick(delta: float, body_pixels: float) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	var gravity: float = maxf(body_pixels, 80.0) * 0.55
	for star in _stars:
		star["age"] = float(star["age"]) + dt
		star["vel"] = (star["vel"] as Vector2) * exp(-dt * 1.2) + Vector2(0.0, gravity * dt)
		star["pos"] = (star["pos"] as Vector2) + (star["vel"] as Vector2) * dt
		star["angle"] = float(star["angle"]) + float(star["spin"]) * dt
	_stars = _stars.filter(func(star): return float(star["age"]) < float(star["life"]))
	queue_redraw()

func _draw() -> void:
	for star in _stars:
		var t: float = float(star["age"]) / float(star["life"])
		var alpha: float = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.55, 1.0, t))
		var grow: float = 0.6 + 0.4 * smoothstep(0.0, 0.2, t)
		var color: Color = star["color"]
		color.a = alpha
		draw_colored_polygon(_star_points(star["pos"], float(star["size"]) * grow, float(star["angle"])), color)

func _star_points(center: Vector2, radius: float, angle: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(10):
		var r: float = radius if i % 2 == 0 else radius * 0.45
		var a: float = angle - PI * 0.5 + float(i) * PI / 5.0
		points.append(center + Vector2(cos(a), sin(a)) * r)
	return points
