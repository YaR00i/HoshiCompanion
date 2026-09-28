extends Control
## Облачка над Хоши: какой ИИ-помощник сейчас занят (Claude, потом Codex).
##
## Круглое «облачко-мысль» сбоку от головы с двумя кружками-хвостиками, внутри —
## иконка помощника, нарисованная кодом (временная: пользователь нарисует свои).
## Работает — иконка тихо «дышит»; закончил — зелёная ✓ в уголке; ждёт
## разрешения — жёлтый «?». Несколько помощников — облачка столбиком.
## Только рисует: что показывать, решает assistant_watch.gd (clouds()).
## Клики сквозь облачко проходят (как у пузыря реплик).

const RADIUS: float = 19.0
const GAP: float = 46.0
const PAPER := Color(1.0, 0.98, 0.95, 0.97)
const EDGE := Color("b9a6c6")
const ICON_COLORS := {"claude": Color("e07a3f"), "codex": Color("2fa88a")}
const DONE := Color("4caf7a")
const WAITING := Color("e0a33a")

## [{app, status}] — status: working / done / waiting.
var items: Array = []
var _anchor: Vector2 = Vector2.ZERO
var _head: Vector2 = Vector2.ZERO
var _time: float = 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## head_point — голова Хоши в пикселях окна; облачка встают справа-сверху от неё.
func place(delta: float, head_point: Vector2, frame_size: Vector2) -> void:
	_time += delta
	visible = not items.is_empty()
	if not visible:
		return
	# Как у пузыря реплик: держимся в устойчивой средней части окна.
	_anchor = Vector2(clampf(head_point.x + 58.0, frame_size.x * 0.25 + RADIUS, frame_size.x * 0.75 - RADIUS - 4.0),
		maxf(frame_size.y * 0.04 + RADIUS + GAP * float(items.size() - 1), head_point.y - 58.0))
	_head = head_point
	queue_redraw()

func _draw() -> void:
	for index in range(items.size()):
		var center: Vector2 = _anchor - Vector2(0.0, GAP * float(index))
		if index == 0:
			_draw_tail(center)
		_draw_cloud(center, items[index])

## Облачко под точкой окна (для нажатия): {"app", "status"} или {}.
func cloud_at(point: Vector2) -> Dictionary:
	if not visible:
		return {}
	for index in range(items.size()):
		var center: Vector2 = _anchor - Vector2(0.0, GAP * float(index))
		if Rect2(center - Vector2(RADIUS * 1.7, RADIUS * 1.3), Vector2(RADIUS * 3.4, RADIUS * 2.6)).has_point(point):
			return items[index]
	return {}

## Два кружка-хвостика от головы к нижнему облачку — «это мысль».
func _draw_tail(center: Vector2) -> void:
	var from: Vector2 = _head + Vector2(18.0, -30.0)
	for step in [[0.3, 3.0], [0.56, 4.4]]:
		var point: Vector2 = from.lerp(center, step[0])
		draw_circle(point, step[1], PAPER)
		draw_arc(point, step[1], 0.0, TAU, 16, EDGE, 1.0, true)

func _draw_cloud(center: Vector2, item: Dictionary) -> void:
	var status: String = str(item.get("status", ""))
	draw_circle(center, RADIUS, PAPER)
	draw_arc(center, RADIUS, 0.0, TAU, 40, EDGE, 1.5, true)
	var breathe: float = 1.0 + (0.1 * sin(_time * 3.2) if status == "working" else 0.0)
	var app: String = str(item.get("app", ""))
	var color: Color = ICON_COLORS.get(app, EDGE)
	if app == "claude":
		_draw_sparkle(center, 10.0 * breathe, color)
	else:
		var font: Font = ThemeDB.fallback_font
		var size: int = int(13.0 * breathe)
		var text: String = "</>"
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, center + Vector2(-width * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	if status == "done":
		var badge: Vector2 = center + Vector2(RADIUS * 0.72, RADIUS * 0.62)
		draw_circle(badge, 7.0, DONE)
		draw_polyline(PackedVector2Array([badge + Vector2(-3.4, 0.2), badge + Vector2(-0.8, 2.8), badge + Vector2(3.6, -2.6)]), Color.WHITE, 1.8, true)
	elif status == "waiting":
		var badge: Vector2 = center + Vector2(RADIUS * 0.72, RADIUS * 0.62)
		draw_circle(badge, 7.0, WAITING)
		var font: Font = ThemeDB.fallback_font
		draw_string(font, badge + Vector2(-3.2, 4.4), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

## Искорка: четыре длинных луча и четыре коротких по диагонали.
func _draw_sparkle(center: Vector2, size: float, color: Color) -> void:
	for index in range(8):
		var angle: float = TAU * float(index) / 8.0 - PI * 0.5
		var length: float = size if index % 2 == 0 else size * 0.55
		draw_line(center, center + Vector2.from_angle(angle) * length, color, 2.6 if index % 2 == 0 else 2.0, true)
	draw_circle(center, 2.4, color)
