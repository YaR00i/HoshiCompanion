extends RefCounted
## Судья опор: решает, можно ли Хоши сесть на найденную линию.
##
## Линии приходят из разных «органов чувств» (docs/SUPPORTS_RU.md):
##   frame     — верхний край самого окна (надёжно всегда);
##   structure — UI Automation: программа сама рассказывает, где её панели;
##   visual    — один кадр окна, поиск горизонтальных краёв (только подсказка);
##   adapter   — позже: расширение браузера, аддон Blender (точно);
##   taught    — позже: линия, которую человек показал руками.
## Все источники дают кандидата одного формата:
##   {source, kind, x, y, width, confidence}
## где x, y, width — пиксели Хоши относительно левого верхнего угла окна.
## Судья один для всех, поэтому правила безопасности не зависят от источника.
##
## Уровень доверия:
##   "auto"   — Хоши может выбрать эту линию сама;
##   "manual" — только если человек сам на неё показал;
##   "show"   — только показать на карте, садиться нельзя.

const SOURCE_CONFIDENCE := {"frame": 1.0, "taught": 0.9, "adapter": 0.85, "structure": 0.55, "visual": 0.3}
## Широкие панели из UI Automation — самые надёжные внутренние опоры.
const STRONG_KINDS: Array[String] = ["ToolBar", "Header", "Tab", "Pane", "Group", "Custom"]
const MIN_WIDTH: int = 180        # как у SurfaceController: иначе негде сесть
const MIN_BELOW: int = 80         # под линией должно оставаться окно, а не пустота
const MIN_TOP_OFFSET: int = 24    # линия у самого верха — это просто верх окна
const POINT_ABOVE: float = 160.0  # насколько выше указателя может быть линия
const POINT_BELOW: float = 16.0   # и чуть ниже (промах мышью)

static func level_for(confidence: float) -> String:
	if confidence >= 0.9:
		return "auto"
	if confidence >= 0.5:
		return "manual"
	return "show"

static func confidence(source: String, kind: String, width: float, window_width: float) -> float:
	var value: float = float(SOURCE_CONFIDENCE.get(source, 0.2))
	if source == "structure":
		if kind in STRONG_KINDS and width >= 240.0:
			value = 0.7
		elif width >= window_width * 0.5:
			value = 0.6
	if source == "visual" and kind == "VisualItem":
		value = 0.2
	return value

## Перевести ответ помощника окон в кандидатов в пикселях Хоши.
## result.window — размер того же окна в пикселях помощника (физических).
static func normalize(result: Dictionary, window_size: Vector2i) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if not bool(result.get("ok", false)):
		return output
	var measured: Array = result.get("window", [])
	if measured.size() != 2 or float(measured[0]) <= 0.0 or float(measured[1]) <= 0.0:
		return output
	var scale := Vector2(float(window_size.x) / float(measured[0]), float(window_size.y) / float(measured[1]))
	var source: String = str(result.get("source", "structure"))
	for item in result.get("candidates", []):
		if not item is Dictionary:
			continue
		var width: float = float(item.get("width", 0)) * scale.x
		var kind: String = str(item.get("kind", ""))
		output.append({"source": source, "kind": kind,
			"x": int(round(float(item.get("x", 0)) * scale.x)),
			"y": int(round(float(item.get("y", 0)) * scale.y)),
			"width": int(round(width)),
			"confidence": confidence(source, kind, width, float(window_size.x))})
	return output

## Можно ли сесть на линию в окне такого размера.
static func judge(candidate: Dictionary, window_size: Vector2i) -> Dictionary:
	var x: int = int(candidate.get("x", 0))
	var y: int = int(candidate.get("y", 0))
	var width: int = int(candidate.get("width", 0))
	var level: String = level_for(float(candidate.get("confidence", 0.0)))
	var reason: String = ""
	if width < MIN_WIDTH:
		reason = "narrow"
	elif y < MIN_TOP_OFFSET:
		reason = "top_edge"
	elif window_size.y - y < MIN_BELOW:
		reason = "too_low"
	elif x < -2 or x + width > window_size.x + 2:
		reason = "outside"
	elif level == "show":
		reason = "unsure"
	return {"ok": reason.is_empty(), "reason": reason, "level": level}

## Линия, на которую показал человек: верх элемента под указателем или
## ближайшая пригодная линия чуть выше него. Пустой словарь — не нашлось.
static func pick_under_cursor(candidates: Array, cursor: Vector2, window_size: Vector2i) -> Dictionary:
	var best: Dictionary = {}
	var best_gap: float = INF
	for item in candidates:
		var left: float = float(item["x"]) - 12.0
		var right: float = float(item["x"]) + float(item["width"]) + 12.0
		if cursor.x < left or cursor.x > right:
			continue
		var gap: float = cursor.y - float(item["y"])
		if gap < -POINT_BELOW or gap > POINT_ABOVE:
			continue
		var verdict: Dictionary = judge(item, window_size)
		if not bool(verdict["ok"]):
			continue
		if absf(gap) < best_gap:
			best_gap = absf(gap)
			best = item.duplicate()
			best["level"] = verdict["level"]
	return best

## Опора-линия как «маленькое окно»: её верхний край — сама линия. Тогда вся
## существующая логика посадки и ходьбы по верхнему краю работает без изменений.
static func ledge_rect(window_rect: Rect2i, ledge: Dictionary) -> Rect2i:
	var y: int = int(ledge.get("y", 0))
	return Rect2i(window_rect.position.x + int(ledge.get("x", 0)), window_rect.position.y + y,
		int(ledge.get("width", window_rect.size.x)), window_rect.size.y - y)

## Где на линии сесть, чтобы оказаться под указателем (0..1, как anchor_u).
static func seat_fraction(ledge: Dictionary, cursor_x: float) -> float:
	var width: float = maxf(1.0, float(ledge.get("width", 1)) - 48.0)
	return clampf((cursor_x - float(ledge.get("x", 0)) - 24.0) / width, 0.05, 0.95)
