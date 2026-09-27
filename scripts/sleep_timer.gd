extends RefCounted
## Таймер сна (просьба 28.09.2026): «через 30 минут — пауза». Засыпать под
## фильм: когда время вышло, все плееры встают на паузу (MPC-BE, YouTube,
## видео во вкладках), и по выбору — гаснет экран или ПК засыпает.
##
## Запуск — только по нажатию на пульте ("timer:<минуты>", args.then) или из
## сценария; "timer:cancel" — отменить. Сон ПК — только если кнопка «Сон»
## включена на ПК в «Моих действиях» (как и сама кнопка сна на пульте).
## За минуту до конца Хоши предупреждает.

const MINUTES: Array = [15, 30, 45, 60, 90]
const MAX_MINUTES: int = 240
const THEN: Dictionary = {"pause": "Пауза", "screen": "Пауза и погасить экран", "sleep": "Пауза и сон ПК"}
const WARN_SECONDS: int = 60

## Когда сработает (Time.get_ticks_msec), 0 — не запущен.
var ends_at: int = 0
var then: String = "pause"
## Последний выбор «что потом» — для быстрых кнопок без выбора.
var last_then: String = "pause"
var _warned: bool = false

func active() -> bool:
	return ends_at > 0

func seconds_left() -> int:
	return maxi(0, int(ceil(float(ends_at - Time.get_ticks_msec()) / 1000.0))) if ends_at > 0 else 0

## Пусто — запущен, иначе причина отказа. sleep_allowed — включён ли «Сон» на ПК.
func start(minutes: int, what: String, sleep_allowed: bool, out: Dictionary = {}) -> String:
	if minutes <= 0 or minutes > MAX_MINUTES:
		return "bad_minutes"
	if what.is_empty():
		what = last_then
	if not THEN.has(what):
		return "bad_then"
	if what == "sleep" and not sleep_allowed:
		return "not_allowed"
	then = what
	last_then = what
	ends_at = Time.get_ticks_msec() + minutes * 60 * 1000
	_warned = minutes * 60 <= WARN_SECONDS
	out["say"] = "Хорошо, через %d мин — %s" % [minutes, THEN[what].to_lower()]
	return ""

func cancel(out: Dictionary = {}) -> String:
	if ends_at <= 0:
		return "nothing_to_cancel"
	ends_at = 0
	out["say"] = "Таймер сна отменён"
	return ""

## Для пульта: {} — не запущен.
func state() -> Dictionary:
	if ends_at <= 0:
		return {}
	return {"seconds": seconds_left(), "then": then, "title": THEN[then], "cancel": "timer:cancel"}

## Каждый кадр. Возвращает "warn" (минута осталась), "fire" (время вышло) или "".
func tick() -> String:
	if ends_at <= 0:
		return ""
	var left: int = seconds_left()
	if left <= 0:
		ends_at = 0
		return "fire"
	if left <= WARN_SECONDS and not _warned:
		_warned = true
		return "warn"
	return ""
