extends RefCounted
## 0.9.1 «Характер» (Personality State): четыре медленных параметра Хоши.
##   energy     — бодрость: гулять и двигаться (тратится на прогулки, копится в отдыхе);
##   curiosity  — любопытство: сменить место, осмотреться (растёт, пока стоит на месте);
##   comfort    — уют: посидеть и остаться на удобной опоре (растёт, когда устала
##                или её резко уронили; спадает, пока отдыхает);
##   social     — общительность: откликаться тебе (растёт от касаний, медленно спадает).
## Всё от 0 до 1, у каждого «обычное» значение — к нему параметр медленно
## возвращается. Это не тамагочи: ни голода, ни наказаний, ни уведомлений.
## Параметры только мягко меняют веса того, что Хоши и так может выбрать
## (intent_planner.gd): множитель 0,5…1,6, при обычных значениях ≈ 1.
## Живёт только в текущем запуске, ничего не сохраняется и не уходит в сеть.

const TRAITS: Array[String] = ["energy", "curiosity", "comfort", "social"]
## Куда возвращается каждый параметр (за ~10 минут наполовину).
const BASELINE: Dictionary = {"energy": 0.55, "curiosity": 0.5, "comfort": 0.45, "social": 0.4}
const RETURN_RATE: float = 0.00116 # ln 2 / 600 с
## Активность из меню сдвигает «обычное»: тихая — меньше бодрости, игривая — больше.
const ACTIVITY_SHIFT: Dictionary = {"quiet": {"energy": -0.15, "comfort": 0.12}, "playful": {"energy": 0.15, "curiosity": 0.1, "comfort": -0.1}}

var energy: float = 0.55
var curiosity: float = 0.5
var comfort: float = 0.45
var social: float = 0.4
var activity: String = "normal"

## Каждый кадр. context: walking (идёт/прыгает), resting (сидит), dozing (дремлет).
func tick(delta: float, context: Dictionary = {}) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	var walking: bool = bool(context.get("walking", false))
	var resting: bool = bool(context.get("resting", false)) or bool(context.get("dozing", false))
	if walking:
		_add("energy", -0.004 * dt)      # ~4 минуты ходьбы — с бодрой до уставшей
		_add("curiosity", -0.003 * dt)   # нагулялась — насмотрелась
	elif resting:
		_add("energy", (0.004 if bool(context.get("dozing", false)) else 0.0025) * dt)
		_add("comfort", -0.0008 * dt)    # насиделась
		_add("curiosity", 0.0012 * dt)
	else:
		_add("curiosity", 0.0015 * dt)   # стоит на месте — хочется посмотреть, что вокруг
		if energy < 0.35:
			_add("comfort", 0.002 * dt)  # устала — тянет присесть
	var pull: float = 1.0 - exp(-RETURN_RATE * dt)
	for name in TRAITS:
		set(name, lerpf(float(get(name)), _baseline(name), pull))

## Событие контакта (interaction_session.gd): attention, pet, pet_button, wave,
## wake, return, quiet, release_soft, release_rough.
func on_event(kind: String) -> void:
	match kind:
		"pet", "pet_button":
			_add("social", 0.08)
			_add("comfort", 0.04)
		"attention", "return":
			_add("social", 0.06)
			_add("curiosity", 0.03)
		"wave":
			_add("social", 0.05)
		"wake":
			_add("social", 0.05)
			_add("energy", 0.05)
		"quiet":
			_add("social", 0.01)          # часто нажимают — не раздувать
		"release_soft":
			_add("comfort", 0.03)
		"release_rough":
			_add("comfort", 0.1)          # испугалась — хочется посидеть
			_add("energy", -0.04)

## Хоши начала занятие (intent_planner.activate).
func on_intent(intent_name: String) -> void:
	match intent_name:
		"explore_floor", "explore_surface", "visit_side", "leave_support":
			_add("curiosity", -0.06)      # сменила место — любопытство утолено
		"rest":
			_add("comfort", -0.05)
		"social_react":
			_add("social", -0.05)

## Множитель веса занятия: 0,5…1,6; при обычных значениях около 1.
func intent_factor(intent_name: String) -> float:
	var factor: float = 1.0
	match intent_name:
		"explore_floor", "explore_surface":
			factor = 0.45 + energy * 0.7 + curiosity * 0.4
		"visit_side", "leave_support":
			factor = 0.55 + curiosity * 0.7 + energy * 0.2
		"rest":
			factor = 0.5 + (1.0 - energy) * 0.8 + comfort * 0.4
		"observe":
			factor = 0.75 + comfort * 0.3 + (1.0 - energy) * 0.2
		"social_react":
			factor = 0.5 + social * 1.2
	return clampf(factor, 0.5, 1.6)

## Коротко по-русски, для строки состояния: «бодрая, любопытная».
func describe() -> String:
	var words: Array[String] = []
	if energy >= 0.7:
		words.append("бодрая")
	elif energy <= 0.3:
		words.append("сонная")
	if curiosity >= 0.7:
		words.append("любопытная")
	if comfort >= 0.7:
		words.append("уютная")
	if social >= 0.7:
		words.append("общительная")
	return ", ".join(words) if not words.is_empty() else "спокойная"

func snapshot() -> Dictionary:
	return {"energy": snappedf(energy, 0.01), "curiosity": snappedf(curiosity, 0.01), "comfort": snappedf(comfort, 0.01), "social": snappedf(social, 0.01), "mood": describe()}

func _baseline(name: String) -> float:
	return clampf(float(BASELINE[name]) + float(ACTIVITY_SHIFT.get(activity, {}).get(name, 0.0)), 0.05, 0.95)

func _add(name: String, amount: float) -> void:
	set(name, clampf(float(get(name)) + amount, 0.0, 1.0))
