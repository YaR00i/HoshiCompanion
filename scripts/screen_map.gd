extends RefCounted
## Единая карта экранов для прогулок Хоши (просьба 28.09.2026).
##
## Пол — нижний край рабочей области экрана (над панелью задач). Панель задач —
## настоящая граница: на ней стоят всегда. Без панели внизу край — пол только
## там, где под экраном нет другого экрана (иначе оттуда падают вниз). Полы соседних экранов на одной высоте (±SAME_LEVEL px) сливаются в одну
## дорожку — по ней Хоши идёт через стык, не упираясь. Если у соседа пол выше или
## ниже (ступенька) — через край можно перепрыгнуть (hop), если ступенька не
## выше MAX_STEP_BODIES роста. Запрещённые экраны (выбор на ПК) полов не дают:
## туда Хоши сама не ходит и не прыгает.
##
## Экран опознаётся по расположению и размеру: "x,y,w,h" (номера Windows меняются).

const SAME_LEVEL: int = 8
const TOUCH: int = 3
const MAX_STEP_BODIES: float = 0.9
## При разном масштабе экранов (100% и 125%) Windows оставляет между ними в
## пикселях «пустоту»: сосед может начинаться дальше края. Прыжок её перелетает.
const MAX_GAP: int = 1400

## [{id, index, full: Rect2i, usable: Rect2i, allowed: bool, primary: bool}]
var screens: Array = []
## Дорожки пола: [{x0, x1, y}] — по x слева направо.
var lanes: Array = []

static func screen_id(full: Rect2i) -> String:
	return "%d,%d,%d,%d" % [full.position.x, full.position.y, full.size.x, full.size.y]

## Экраны этого ПК, как их видит Godot.
static func display_screens() -> Array:
	var result: Array = []
	for index in range(DisplayServer.get_screen_count()):
		var full := Rect2i(DisplayServer.screen_get_position(index), DisplayServer.screen_get_size(index))
		var usable: Rect2i = DisplayServer.screen_get_usable_rect(index)
		if usable.size.x <= 0 or usable.size.y <= 0:
			usable = full
		result.append({"index": index, "full": full, "usable": usable, "primary": index == DisplayServer.get_primary_screen()})
	return result

## Собрать карту. items — [{index, full, usable, primary}]; blocked — id запрещённых экранов.
func build(items: Array, blocked: PackedStringArray = PackedStringArray()) -> void:
	screens.clear()
	for item in items:
		var full: Rect2i = item["full"]
		screens.append({"id": screen_id(full), "index": int(item.get("index", screens.size())), "full": full,
			"usable": item.get("usable", full), "allowed": not screen_id(full) in blocked, "primary": bool(item.get("primary", false))})
	var pieces: Array = []
	for screen in screens:
		if not screen["allowed"]:
			continue
		for part in _floor_parts(screen):
			pieces.append(part)
	pieces.sort_custom(func(a, b): return a["x0"] < b["x0"])
	lanes.clear()
	for piece in pieces:
		var last: Dictionary = lanes.back() if not lanes.is_empty() else {}
		if not last.is_empty() and absi(piece["x0"] - last["x1"]) <= TOUCH and absi(piece["y"] - last["y"]) <= SAME_LEVEL:
			last["x1"] = maxi(last["x1"], piece["x1"])
			last["y"] = maxi(last["y"], piece["y"]) # стоим на более низком краю — не висим в воздухе
		else:
			lanes.append({"x0": piece["x0"], "x1": piece["x1"], "y": piece["y"]})

## Нижний край экрана — пол, кроме участков, под которыми вплотную другой экран.
func _floor_parts(screen: Dictionary) -> Array:
	var full: Rect2i = screen["full"]
	var usable: Rect2i = screen["usable"]
	var spans: Array = [[usable.position.x, usable.end.x]]
	var taskbar_below: bool = usable.end.y < full.end.y - TOUCH
	for other in screens:
		if taskbar_below:
			break
		var below: Rect2i = other["full"]
		if other == screen or absi(below.position.y - full.end.y) > TOUCH:
			continue
		var cut0: int = maxi(below.position.x, usable.position.x)
		var cut1: int = mini(below.end.x, usable.end.x)
		if cut1 <= cut0:
			continue
		var next: Array = []
		for span in spans:
			if cut1 <= span[0] or cut0 >= span[1]:
				next.append(span)
				continue
			if cut0 > span[0]:
				next.append([span[0], cut0])
			if cut1 < span[1]:
				next.append([cut1, span[1]])
		spans = next
	var parts: Array = []
	for span in spans:
		if span[1] - span[0] >= 40:
			parts.append({"x0": span[0], "x1": span[1], "y": usable.end.y})
	return parts

## Дорожка под точкой ступней: x внутри, пол не выше ступней (с запасом) —
## ближайший снизу. {} — под ней пола нет (запрещённый экран, пустота).
func lane_at(feet: Vector2) -> Dictionary:
	var best: Dictionary = {}
	for lane in lanes:
		if feet.x < lane["x0"] or feet.x > lane["x1"] or float(lane["y"]) < feet.y - SAME_LEVEL - 2:
			continue
		if best.is_empty() or lane["y"] < best["y"]:
			best = lane
	return best

## Соседняя дорожка через край (side −1 — слева, +1 — справа) со ступенькой,
## на которую можно запрыгнуть. {} — стена.
func neighbor(lane: Dictionary, side: int, body_pixels: float) -> Dictionary:
	if lane.is_empty():
		return {}
	var edge: int = lane["x0"] if side < 0 else lane["x1"]
	var best: Dictionary = {}
	var best_gap: int = MAX_GAP + 1
	for other in lanes:
		if other == lane:
			continue
		var gap: int = (edge - int(other["x1"])) if side < 0 else (int(other["x0"]) - edge)
		if gap < -TOUCH or gap > MAX_GAP or gap >= best_gap:
			continue
		best = other
		best_gap = gap
	# Ближайший пол сбоку; ступенька выше, чем можно запрыгнуть, — стена.
	if best.is_empty() or absi(int(best["y"]) - int(lane["y"])) > int(body_pixels * MAX_STEP_BODIES):
		return {}
	return best

## Разрешён ли экран под точкой (нет экрана — да: не мешаем).
func allowed_at(point: Vector2) -> bool:
	for screen in screens:
		if (screen["full"] as Rect2i).has_point(Vector2i(point)):
			return bool(screen["allowed"])
	return true
