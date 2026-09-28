extends Control
## Схема экранов, как в «Параметры → Дисплей» Windows: прямоугольники в том же
## расположении и пропорциях, с номерами. Нажал на экран — он выбран.
## Экраны — из pc_actions.monitors: [{index, x, y, width, height, primary}].

signal picked(index: int)

const PAPER := Color("fffdfb")
const EDGE := Color("cdbdd6")
const ON := Color("665479")
const TEXT := Color("3b3449")

var monitors: Array = []:
	set(value):
		monitors = value
		queue_redraw()
var selected: int = 0:
	set(value):
		selected = value
		queue_redraw()

## Номера экранов, где Хоши нельзя гулять: серые с «✕» (окно «Экраны для Хоши»).
var blocked: Array = []:
	set(value):
		blocked = value
		queue_redraw()
## Полы (screen_map.gd lanes): [{x0, x1, y}] — рисуются золотой линией.
var floors: Array = []:
	set(value):
		floors = value
		queue_redraw()

var _rects: Dictionary = {}  # index -> Rect2 на схеме

func _init() -> void:
	custom_minimum_size = Vector2(0, 150)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	_rects.clear()
	if monitors.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(8, size.y * 0.5), "Экраны ещё не прочитаны…", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, EDGE)
		return
	var bounds := Rect2(Vector2(monitors[0]["x"], monitors[0]["y"]), Vector2(monitors[0]["width"], monitors[0]["height"]))
	for m in monitors:
		bounds = bounds.merge(Rect2(Vector2(m["x"], m["y"]), Vector2(m["width"], m["height"])))
	var scale: float = minf((size.x - 12.0) / bounds.size.x, (size.y - 12.0) / bounds.size.y)
	var offset: Vector2 = (size - bounds.size * scale) * 0.5 - bounds.position * scale
	var font: Font = ThemeDB.fallback_font
	for m in monitors:
		var rect := Rect2(Vector2(m["x"], m["y"]) * scale + offset, Vector2(m["width"], m["height"]) * scale).grow(-2.0)
		_rects[int(m["index"])] = rect
		var on: bool = int(m["index"]) == selected
		var off: bool = blocked.has(int(m["index"]))
		draw_rect(rect, ON if on else (Color("ece7ef") if off else PAPER))
		draw_rect(rect, ON if on else EDGE, false, 2.0)
		var label: String = str(m["index"]) + (" ★" if bool(m.get("primary", false)) else "") + ("  ✕" if off else "")
		var font_size: int = int(clampf(rect.size.y * 0.32, 11.0, 26.0))
		var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, rect.get_center() + Vector2(-width * 0.5, font_size * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE if on else (EDGE if off else TEXT))
	for lane in floors:
		var from := Vector2(lane["x0"], lane["y"]) * scale + offset
		var to := Vector2(lane["x1"], lane["y"]) * scale + offset
		draw_line(from + Vector2(3, -3), to + Vector2(-3, -3), Color("d8a54a"), 3.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for index in _rects:
			if (_rects[index] as Rect2).has_point(event.position):
				selected = index
				picked.emit(index)
				return
