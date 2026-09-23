extends Node2D
## A tiny app-owned glimmer over the head while the user is stroking it.

var _point: Vector2 = Vector2.ZERO
var _strength: float = 0.0
var _time: float = 0.0

func tick(delta: float, point: Vector2, active: bool) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	if _strength < 0.01:
		_point = point
	else:
		_point = _point.lerp(point, 1.0 - exp(-dt * 9.0))
	_strength = lerpf(_strength, 1.0 if active else 0.0, 1.0 - exp(-dt * 8.0))
	_time += dt
	queue_redraw()

func _draw() -> void:
	if _strength < 0.02:
		return
	var line: Color = Color(1.0, 0.82, 0.94, 0.66 * _strength)
	draw_arc(_point, 8.0, PI * 1.08, PI * 1.86, 12, line, 1.5, true)
	draw_arc(_point + Vector2(5.0, 3.0), 10.0, PI * 1.12, PI * 1.72, 12, Color(1.0, 0.75, 0.9, 0.40 * _strength), 1.2, true)
	for index in range(2):
		var phase: float = _time * 2.6 + float(index) * 2.3
		var sparkle: Vector2 = _point + Vector2(cos(phase) * 12.0, -5.0 + sin(phase) * 4.0)
		draw_circle(sparkle, 1.1, Color(1.0, 0.9, 0.97, 0.75 * _strength))
