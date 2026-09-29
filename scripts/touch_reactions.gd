extends RefCounted
## Реакции на касание по месту (просьба 28.09.2026, переделано по отзыву):
##   leg   — стоя: приподнимает ножку, плавно дрыгает, ставит обратно и
##           притопывает носочком; сидя — плавно болтает этой ножкой;
##   arm   — смотрит на свою ручку, потом протягивает её тебе ладошкой вверх
##           и улыбается;
##   belly — щекотно: прикрывает животик (пальцы навстречу), мотает головой,
##           ёрзает плечами и хихикает;
##   chest — плавно отворачивается спиной (~150°), оглядывается через плечо и
##           грозит пальчиком «ай-яй-яй»;
##   hips  — кружится на одной ножке на полный оборот («виу»), вторую поджимает.
## Голова — как раньше (внимание, поглаживание). Слой поверх позы: добавочные
## повороты, цели кистей и поворот всего тела (yaw_offset) для «отвернуться».
## Сила — animations/life_style.tres (группа «Касания»).

const TouchMotion = preload("res://scripts/touch_motion.gd")
const SketchMotion = preload("res://scripts/sketch_motion.gd")
const DURATION: Dictionary = {"leg": 2.6, "leg_seated": 1.9, "arm": 2.9, "belly": 2.4, "chest": 3.4, "hips": 2.4, "hips_seated": 1.6, "hey": 2.6, "stretch": 4.2, "hair": 2.6, "doze": 5.0}
const COOLDOWN: float = 0.8
const ZONES: Array[String] = ["leg", "arm", "belly", "chest", "hips"]
## Не касание, а оклик: «Хей!» — позвать тебя (Claude или Codex закончил работу).
## Мелочи сидя на полочке — тоже «вызовы» (их выбирает edge_life, не касание).
const CALLS: Array[String] = ["hey", "stretch", "hair", "doze"]
## Грудь: не разворот спиной (выглядело нелепо, отзыв 28.09), а смущённо
## отвернуться вполоборота, прикрыться ручкой и погрозить пальчиком.
const TURN_DEGREES: float = 32.0

var rig
var driver               # posture_driver.gd: руки (IK) и повороты костей
var skeleton: Skeleton3D
var available: bool = false
var zone: String = ""
var side: String = "left"
var age: float = 0.0
var weight: float = 0.0
var seated: bool = false
var _cooldown: float = 0.0
## Кости, которые кадр не сбрасывает сам (большой палец): поза до реакции —
## поворачиваем от неё, а не копим поворот каждый кадр; в конце — обратно.
var _base: Dictionary = {}
## Играть клипы animations/touch_*.tres (правятся в редакторе), если они есть.
var use_clips: bool = true
## Для запекания клипов (tools/bake_touch_clips.gd): поза до и после реакции.
var record: bool = false
var recorded: Dictionary = {}
## Кости клипа: какой поворот поставили в прошлый кадр и от какой позы.
var _clip_set: Dictionary = {}
var _clip_base: Dictionary = {}

func setup(rig_driver, posture_driver) -> void:
	rig = rig_driver
	driver = posture_driver
	skeleton = rig.skeleton if rig != null else null
	available = skeleton != null and rig.bones.has("hips") and rig.bones.has("head")

## Начать реакцию. Во время реакции и сразу после — не перезапускаем.
func start(value: String, which: String = "left") -> bool:
	if not available or not (value in ZONES or value in CALLS):
		return false
	if weight > 0.05 or _cooldown > 0.0:
		return false
	zone = value
	side = which if which in ["left", "right"] else "left"
	age = 0.0
	_cooldown = COOLDOWN
	return true

func active() -> bool:
	return not zone.is_empty() and weight > 0.01

func cancel() -> void:
	zone = ""
	weight = 0.0

func _length() -> float:
	var clip: Animation = _clip()
	if clip != null:
		return clip.length
	return float(DURATION.get(zone + "_seated" if zone in ["leg", "hips"] and seated else zone, 2.0))

## Клип для текущей реакции (стоя), иначе null — реакция кодом.
func _clip() -> Animation:
	# Касания сидя — кодом (ноги сидя другие); оклики и мелочи — только верх тела,
	# их клип годится и сидя.
	if not use_clips or zone.is_empty() or (seated and not zone in CALLS):
		return null
	return TouchMotion.clip_for(zone)

## Лицо на время реакции: {выражение: сила}.
func face() -> Dictionary:
	if not active():
		return {}
	var clip: Animation = _clip()
	if clip != null:
		return _frame(clip)["face"]
	match zone:
		"chest":
			return {"angry": 0.38 * weight}
		"arm":
			return {"happy": 0.6 * weight * smoothstep(0.9, 1.4, age)}
		"belly":
			return {"happy": 0.62 * weight}
		"leg", "hips":
			return {"happy": 0.5 * weight}
		"hey":
			return {"happy": 0.85 * weight}
		"stretch":
			# Зевок на вершине потягивания: рот открыт, глазки жмурятся.
			var yawn: float = _smoother((age - 0.9) / 0.5) * (1.0 - _smoother((age - 2.3) / 0.5))
			return {"aa": 0.85 * yawn * weight, "blink": 0.7 * yawn * weight}
		"hair":
			return {"happy": 0.3 * weight}
		"doze":
			var sleep: float = _smoother((age - 0.4) / 1.2) * (1.0 - _smoother((age - 3.3) / 0.12))
			var jolt: float = _smoother((age - 3.3) / 0.12) * (1.0 - _smoother((age - 4.0) / 0.6))
			return {"blink": sleep * weight, "surprised": 0.7 * jolt * weight}
	return {}

## Поворот всего тела (градусы) — «отвернулась спиной» при касании груди.
func yaw_offset() -> float:
	if not active():
		return 0.0
	var clip: Animation = _clip()
	if clip != null:
		return float(_frame(clip)["yaw"])
	if zone == "hips" and not seated:
		# Полный оборот на одной ножке: 360° — то же, что 0°, конец без рывка.
		return 360.0 * _smoother((age - 0.3) / 1.2) * (1.0 if side == "left" else -1.0)
	if zone != "chest" or seated:
		return 0.0 # сидя тело не крутим — отворачиваются только плечи
	var length: float = _length()
	var turn: float = _smoother(age / 0.8) * (1.0 - _smoother((age - (length - 0.9)) / 0.9))
	return TURN_DEGREES * turn * (1.0 if side == "left" else -1.0)

func tick(delta: float) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	_cooldown = maxf(0.0, _cooldown - dt)
	if zone.is_empty():
		weight = 0.0
		return
	age += dt
	var length: float = _length()
	weight = smoothstep(0.0, 0.25, age) * (1.0 - smoothstep(length - 0.5, length, age))
	if age >= length:
		zone = ""
		weight = 0.0

## sitting — сидит (на полу или на краю): ножкой болтает, а не поднимает стоя.
func apply(time: float, sitting: bool) -> void:
	if zone.is_empty():
		seated = sitting
	if not active():
		_restore_base()
		_restore_clip_bones()
		return
	var clip: Animation = _clip()
	if clip != null:
		_apply_clip(clip)
		return
	if record:
		recorded = {"base": _pose_snapshot()}
	_apply_procedural(sitting)
	if record:
		recorded["posed"] = _pose_snapshot()
		recorded["yaw"] = yaw_offset()
		recorded["face"] = face()

func _apply_procedural(_sitting: bool) -> void:
	var w: float = weight
	var s: float = 1.0 if side == "left" else -1.0
	var k: float = float(load("res://scripts/life_style.gd").active().touch_strength)
	match zone:
		"leg":
			if seated:
				_leg_seated(w, k)
			else:
				_leg_standing(w, k, s)
		"arm":
			_arm_offer(w, s)
		"belly":
			_belly_tickle(w, k)
		"chest":
			_chest_cover(w, s)
		"hips":
			if seated:
				_hips_seated(w, k, s)
			else:
				_spin_on_one_leg(w, k, s)
		"hey":
			_hey(w, k, s)
		"stretch":
			_stretch(w, k)
		"hair":
			_hair_tuck(w, s)
		"doze":
			_doze(w, s)

## Стоя: поднять ножку (0–0,4 с), плавно дрыгнуть 2–3 раза (до 1,3 с), поставить
## (до 1,6 с) и притопнуть носочком два раза (до 2,3 с).
func _leg_standing(w: float, k: float, s: float) -> void:
	var t: float = age
	var lift: float = _smoother(t / 0.4) * (1.0 - _smoother((t - 1.2) / 0.4))
	var kick: float = sin(maxf(0.0, t - 0.25) * 9.0) * _smoother((t - 0.2) / 0.3) * (1.0 - _smoother((t - 1.0) / 0.3))
	var tap: float = maxf(0.0, sin((t - 1.6) * 11.0)) if t > 1.6 and t < 2.35 else 0.0
	var leg: String = side
	_add(leg + "UpperLeg", Vector3(-20.0 * lift - 5.0 * kick * lift - 3.0 * tap, 0.0, 0.0) * w * k)
	_add(leg + "LowerLeg", Vector3(42.0 * lift + 22.0 * kick * lift + 7.0 * tap, 0.0, 0.0) * w * k)
	# Носочком об пол: пятка приподнята, носок опускается и поднимается.
	_add(leg + "Foot", Vector3(-12.0 * lift + 8.0 * kick * lift + 14.0 * tap, 0.0, 0.0) * w * k)
	_add("spine", Vector3(-1.5, 0.0, s * 2.0) * lift * w * k)
	_add("head", Vector3(5.0 * lift + 3.0 * tap, 0.0, -s * 3.0 * lift) * w)

## Сидя: плавно поболтать ножкой три раза.
func _leg_seated(w: float, k: float) -> void:
	var swing: float = sin(age * 7.5) * _smoother(age / 0.3) * (1.0 - _smoother((age - 1.3) / 0.5))
	_add(side + "UpperLeg", Vector3(-8.0 * swing, 0.0, 0.0) * w * k)
	_add(side + "LowerLeg", Vector3(30.0 * swing, 0.0, 0.0) * w * k)
	_add("head", Vector3(4.0, 0.0, 0.0) * w)

## Посмотреть на свою ручку (до 1,1 с), потом протянуть её тебе ладошкой вверх.
func _arm_offer(w: float, s: float) -> void:
	if driver == null or not driver.available:
		return
	var h: float = driver.height_m
	var index: int = 0 if side == "left" else 1
	var chest: Vector3 = _origin("chest" if rig.bones.has("chest") else "spine")
	var look_at_hand: Vector3 = chest + Vector3(s * 0.10 * h, -0.09 * h, 0.14 * h)
	# Вперёд и чуть в сторону, ниже груди — спереди рука видна, а не «в камеру».
	# Не слишком далеко вперёд и не к середине — плечо остаётся сбоку, а не
	# заворачивается внутрь (отзыв 28.09).
	var offer: Vector3 = chest + Vector3(s * 0.11 * h, -0.10 * h, 0.21 * h)
	var reach: float = _smoother((age - 0.9) / 0.6)
	var look: float = 1.0 - reach
	# Пока смотрит на ручку — кисть как у тела (без выкручивания запястья).
	_reach(index, look_at_hand.lerp(offer, reach), w, Quaternion(Vector3.FORWARD, deg_to_rad(-s * 70.0 * reach)), "low")
	# Ладонь вверх, пальцы вперёд — к тебе: кисть поворачивается по замеру пальцев.
	# Ладонь всё время вверх (без переворота кисти): сначала наклонена к её лицу —
	# разглядывает ладошку, потом та же ладонь уезжает вперёд и наклоняется к тебе.
	var fingers: Vector3 = Vector3(s * 0.2, 0.0, 1.0).normalized().lerp(Vector3(-s * 0.08, 0.15, 1.0).normalized(), reach).normalized()
	var palm: Vector3 = Vector3(0.0, 1.0, -0.55).normalized().lerp(Vector3(0.0, 1.0, 0.55).normalized(), reach).normalized()
	# Возврат: опуская руку, сама разворачивает ладонь к бедру (как человек),
	# пальцы вниз — к концу поворачивать почти нечего, кисть не выкручивается.
	# Начало — так же: из естественной позы (ладонь к бедру, пальцы вниз) ладонь
	# за 0,7 с поворачивается вверх, а не рывком за четверть секунды.
	var intro: float = _smoother((age - 0.05) / 0.85)
	var back: float = _smoother((age - (_length() - 1.05)) / 0.7)
	var rest_fingers: Vector3 = Vector3(0.0, -1.0, 0.15).normalized()
	var rest_palm: Vector3 = Vector3(-s, 0.0, 0.0)
	fingers = rest_fingers.lerp(fingers, intro).lerp(rest_fingers, back).normalized()
	palm = rest_palm.slerp(palm, intro).slerp(rest_palm, back).normalized()
	_orient_hand(side, fingers, palm, w)
	# Сначала взгляд вниз на ручку, потом — на тебя (голова обратно к зрителю).
	_add("neck", Vector3(6.0 * look, s * 8.0 * look, 0.0) * w)
	_add("head", Vector3(10.0 * look - 2.0 * reach, s * 12.0 * look, -s * 5.0 * reach) * w)
	_add("chest", Vector3(0.0, s * 4.0 * reach, 0.0) * w)

## Щекотно: ладошки на животик пальцами навстречу, сгибается, голова мотается,
## плечи и таз ёрзают «опа-па-пам» (ступни на месте).
func _belly_tickle(w: float, k: float) -> void:
	var giggle: float = sin(age * 10.0)
	var squirm: float = sin(age * 5.0 + 0.6)
	var wiggle: float = sin(age * 8.0)
	if not seated:
		var feet: Dictionary = _feet_now()
		_move_hips(Vector3(wiggle * 0.022 * _leg_length(), 0.0, 0.0) * w * k)
		_add("hips", Vector3(0.0, squirm * 5.0, wiggle * 4.0) * w * k)
		_keep_feet(feet, "")
	_add("spine", Vector3(15.0, -squirm * 4.0, giggle * 1.5 - wiggle * 3.0) * w * k)
	_add("chest", Vector3(3.0, -squirm * 3.0, giggle * 3.0) * w * k)
	_add("neck", Vector3(2.0, giggle * 7.0, -giggle * 2.0) * w * k)
	_add("head", Vector3(6.0, giggle * 12.0, -giggle * 5.0) * w * k)
	_hands_to_belly(w)

## Ай-яй-яй: отвернулась вполоборота (yaw_offset; сидя — только плечами),
## одна ручка прикрывает грудь, другой грозит пальчиком, голова к тебе.
func _chest_cover(w: float, s: float) -> void:
	var length: float = _length()
	var turn: float = _smoother(age / 0.6) * (1.0 - _smoother((age - (length - 0.9)) / 0.9))
	var wag: float = sin(age * 9.0) * _smoother((age - 0.8) / 0.3) * (1.0 - _smoother((age - (length - 1.0)) / 0.3))
	var body: float = 0.0 if not seated else 1.0 # сидя поворот делают плечи
	_add("spine", Vector3(-4.0 * turn, s * (6.0 + 10.0 * body) * turn, 0.0) * w)
	_add("chest", Vector3(-3.0 * turn, s * (6.0 + 8.0 * body) * turn, 0.0) * w)
	# Голова смотрит на тебя, чуть наклонена — «ну-ну».
	_add("neck", Vector3(0.0, -s * 10.0 * turn, s * 3.0 * turn) * w)
	_add("head", Vector3(3.0 * turn, -s * 16.0 * turn, s * 7.0 * turn) * w)
	if driver == null or not driver.available:
		return
	var h: float = driver.height_m
	var chest: Vector3 = _origin("chest" if rig.bones.has("chest") else "spine")
	# Ручка со стороны касания прикрывает грудь — ладонью к себе, пальцы к другому плечу.
	var cover: String = side
	var cs: float = 1.0 if cover == "left" else -1.0
	var cover_w: float = w * _smoother(age / 0.45) * (1.0 - _smoother((age - (length - 0.8)) / 0.7))
	_reach(0 if cover == "left" else 1, chest + Vector3(-cs * 0.01 * h, -0.005 * h, 0.085 * h), cover_w, Quaternion.IDENTITY, "low")
	_orient_hand(cover, Vector3(-cs, 0.25, 0.1).normalized(), Vector3(0.0, 0.0, -1.0), cover_w)
	# Другая — у плеча, указательный пальчик вверх качается «ай-яй-яй».
	var hand: String = "right" if side == "left" else "left"
	var hs: float = 1.0 if hand == "left" else -1.0
	var wag_w: float = w * _smoother((age - 0.3) / 0.5) * (1.0 - _smoother((age - (length - 0.8)) / 0.7))
	var target: Vector3 = _origin("head") + Vector3(hs * 0.19 * h, -0.05 * h, 0.13 * h)
	_reach(1 if hand == "right" else 0, target, wag_w, Quaternion.IDENTITY, "raise")
	_orient_hand(hand, Vector3(0.18 * wag - hs * 0.1, 1.0, 0.1).normalized(), Vector3(-hs * 0.3, 0.0, 1.0).normalized(), wag_w)
	# Кулачок: средний, безымянный, мизинец согнуты, указательный вверх (большой не трогаем).
	var bend := {"Proximal": 50.0, "Intermediate": 55.0, "Distal": 35.0}
	for finger in ["Middle", "Ring", "Little"]:
		for part in bend:
			_add(hand + finger + part, Vector3(0.0, -hs * float(bend[part]), 0.0) * wag_w)

## Повернуть кисть так, чтобы пальцы смотрели в fingers, а ладонь — в palm
## (мировые оси скелета). Замер по костям пальцев — без догадок о позе покоя.
func _orient_hand(which: String, fingers: Vector3, palm: Vector3, w: float) -> void:
	if w <= 0.001 or not (rig.bones.has(which + "Hand") and rig.bones.has(which + "MiddleProximal") and rig.bones.has(which + "IndexProximal") and rig.bones.has(which + "LittleProximal")):
		return
	var hand: int = int(rig.bones[which + "Hand"])
	var at: Vector3 = _origin(which + "Hand")
	var f_now: Vector3 = (_origin(which + "MiddleProximal") - at).normalized()
	var across: Vector3 = _origin(which + "IndexProximal") - _origin(which + "LittleProximal")
	# Нормаль ладони: у левой и правой руки «поперёк» направлен зеркально.
	var n_now: Vector3 = (f_now.cross(across) * (1.0 if which == "left" else -1.0)).normalized()
	var now := Basis(f_now, n_now, f_now.cross(n_now)).orthonormalized()
	var f_to: Vector3 = fingers.normalized()
	var n_to: Vector3 = (palm - f_to * palm.dot(f_to)).normalized()
	var goal := Basis(f_to, n_to, f_to.cross(n_to)).orthonormalized()
	var delta: Quaternion = (goal * now.inverse()).get_rotation_quaternion()
	var q_now: Quaternion = skeleton.get_bone_global_pose(hand).basis.orthonormalized().get_rotation_quaternion()
	driver._set_rotation_global(hand, q_now.slerp((delta * q_now).normalized(), clampf(w, 0.0, 1.0)).normalized())

## Кружится на одной ножке: опорная — со стороны касания, вторая поджата,
## ручки чуть в стороны для равновесия. Поворот тела — yaw_offset.
func _spin_on_one_leg(w: float, k: float, s: float) -> void:
	var t: float = age
	var lift: float = _smoother(t / 0.3) * (1.0 - _smoother((t - 1.5) / 0.45))
	var stand: String = side
	var free: String = "right" if side == "left" else "left"
	var feet: Dictionary = _feet_now()
	_move_hips(Vector3(s * 0.035 * _leg_length(), 0.0, 0.0) * lift * w)
	_keep_feet(feet, stand)
	_add(free + "UpperLeg", Vector3(-38.0, 0.0, 0.0) * lift * w * k)
	_add(free + "LowerLeg", Vector3(75.0, 0.0, 0.0) * lift * w * k)
	_add(free + "Foot", Vector3(-25.0, 0.0, 0.0) * lift * w * k)
	for arm in ["left", "right"]:
		var a: float = 1.0 if arm == "left" else -1.0
		_add(arm + "UpperArm", Vector3(0.0, 0.0, a * 22.0) * lift * w * k)
		_add(arm + "LowerArm", Vector3(0.0, 0.0, -a * 18.0) * lift * w * k)
	_add("head", Vector3(-4.0, 0.0, 0.0) * lift * w)

## «Хей!»: вскинуть ручку высоко над головой ладошкой к тебе и помахать,
## корпус и голова тянутся в ту же сторону. Сидя — то же, ноги не трогаем.
func _hey(w: float, k: float, s: float) -> void:
	var t: float = age
	var up: float = _smoother((t - 0.05) / 0.4) * (1.0 - _smoother((t - (_length() - 0.8)) / 0.65))
	var wave: float = sin((t - 0.45) * 10.0) * _smoother((t - 0.4) / 0.2) * (1.0 - _smoother((t - 1.6) / 0.3))
	var bounce: float = sin(t * 8.0) * up * 0.5 + 0.5 * up
	_add("spine", Vector3(-3.0 * up, 0.0, s * 4.0 * up) * w * k)
	_add("chest", Vector3(-2.0 * bounce, s * 3.0 * up, s * 3.0 * up) * w * k)
	_add("neck", Vector3(-2.0 * up, 0.0, -s * 3.0 * up) * w)
	_add("head", Vector3(-4.0 * up, 0.0, -s * 7.0 * up) * w)
	if driver == null or not driver.available:
		return
	var h: float = driver.height_m
	var index: int = 0 if side == "left" else 1
	var target: Vector3 = _origin("head") + Vector3(s * 0.17 * h, 0.10 * h, 0.05 * h)
	_reach(index, target, w * up, Quaternion.IDENTITY, "raise")
	# Ладонь к тебе (+Z), пальцы вверх и качаются из стороны в сторону — машет.
	var fingers: Vector3 = Vector3(s * 0.15 + 0.4 * wave, 1.0, 0.05).normalized()
	_orient_hand(side, fingers, Vector3(0.0, 0.0, 1.0), w * up)

## Потянуться: ручки вверх над головой, прогнуться, на вершине — зевок (face),
## потом опустить ручки и чуть встряхнуть головой.
func _stretch(w: float, k: float) -> void:
	var t: float = age
	var up: float = _smoother((t - 0.1) / 0.8) * (1.0 - _smoother((t - 2.5) / 0.9))
	var sway: float = sin((t - 0.9) * 3.0) * _smoother((t - 0.9) / 0.3) * (1.0 - _smoother((t - 2.4) / 0.3))
	var shake: float = sin((t - 3.4) * 14.0) * _smoother((t - 3.35) / 0.1) * (1.0 - _smoother((t - 3.9) / 0.2))
	_add("spine", Vector3(-7.0 * up, 0.0, 3.0 * sway * up) * w * k)
	_add("chest", Vector3(-6.0 * up, 0.0, 2.0 * sway * up) * w * k)
	_add("neck", Vector3(-6.0 * up, 0.0, 0.0) * w)
	_add("head", Vector3(-10.0 * up, 6.0 * shake, -3.0 * sway * up) * w)
	if driver == null or not driver.available:
		return
	var h: float = driver.height_m
	var head: Vector3 = _origin("head")
	for index in range(2):
		var sx: float = 1.0 if index == 0 else -1.0
		var which: String = "left" if index == 0 else "right"
		# Ладошки над макушкой, чуть в стороны; пальцы вверх, ладони вперёд-внутрь.
		_reach(index, head + Vector3(sx * (0.06 + 0.02 * sway * sx) * h, 0.24 * h, 0.03 * h), w * up, Quaternion.IDENTITY, "raise")
		_orient_hand(which, Vector3(0.0, 1.0, 0.0), Vector3(-sx * 0.6, 0.0, 1.0).normalized(), w * up)

## Поправить волосы: ручка к виску, заправляет прядку за ушко, голова чуть
## наклоняется навстречу; лёгкая улыбка.
func _hair_tuck(w: float, s: float) -> void:
	var t: float = age
	var reach: float = _smoother((t - 0.05) / 0.55) * (1.0 - _smoother((t - 1.7) / 0.7))
	var slide: float = _smoother((t - 0.6) / 0.7)
	_add("neck", Vector3(0.0, 0.0, s * 4.0 * reach) * w)
	_add("head", Vector3(2.0 * reach, -s * 5.0 * reach, s * 8.0 * reach) * w)
	if driver == null or not driver.available:
		return
	var h: float = driver.height_m
	var head: Vector3 = _origin("head")
	# От виска назад за ушко.
	var target: Vector3 = head + Vector3(s * 0.085 * h, 0.035 * h, 0.05 * h).lerp(Vector3(s * 0.085 * h, 0.01 * h, -0.005 * h), slide)
	_reach(0 if side == "left" else 1, target, w * reach, Quaternion.IDENTITY, "raise")
	_orient_hand(side, Vector3(-s * 0.15, 0.6, -1.0).normalized(), Vector3(-s, 0.0, 0.0), w * reach)

## Клюёт носом: голова медленно опускается, глазки закрываются — и вдруг
## вздрагивает («ой!»), выпрямляется и оглядывается.
func _doze(w: float, s: float) -> void:
	var t: float = age
	var drop: float = _smoother((t - 0.3) / 2.8) * (1.0 - _smoother((t - 3.3) / 0.15))
	var jolt: float = _smoother((t - 3.3) / 0.1) * (1.0 - _smoother((t - 3.6) / 0.4))
	var look: float = sin((t - 3.7) * 4.0) * _smoother((t - 3.6) / 0.2) * (1.0 - _smoother((t - 4.4) / 0.5))
	_add("spine", Vector3(5.0 * drop - 2.0 * jolt, 0.0, 0.0) * w)
	_add("chest", Vector3(4.0 * drop - 3.0 * jolt, 0.0, 0.0) * w)
	_add("neck", Vector3(10.0 * drop - 3.0 * jolt, 0.0, s * 3.0 * drop) * w)
	_add("head", Vector3(16.0 * drop - 6.0 * jolt, 14.0 * look, s * 6.0 * drop) * w)
	for which in ["left", "right"]:
		var ws: float = 1.0 if which == "left" else -1.0
		_add(which + "Shoulder", Vector3(0.0, 0.0, ws * 6.0 * jolt) * w)

## Сидя: покачаться тазом из стороны в сторону.
func _hips_seated(w: float, k: float, s: float) -> void:
	var sway: float = sin(age * 7.0) * _smoother(age / 0.3)
	_add("spine", Vector3(0.0, sway * 6.0, sway * 5.0) * w * k)
	_add("chest", Vector3(0.0, sway * 4.0, -sway * 3.0) * w * k)
	_add("head", Vector3(3.0, -sway * 5.0, 0.0) * w)

## Ступни на месте после сдвига таза: повернуть бёдра, чтобы стопы вернулись вбок,
## и опустить таз по опорной (only — одна нога; "" — обе, по средней).
func _feet_now() -> Dictionary:
	return {"left": _origin("leftFoot"), "right": _origin("rightFoot")} if rig.bones.has("leftFoot") and rig.bones.has("rightFoot") else {}

func _keep_feet(before: Dictionary, only: String) -> void:
	if before.is_empty():
		return
	var length: float = _leg_length()
	for leg in (["left", "right"] if only.is_empty() else [only]):
		var dx: float = _origin(leg + "Foot").x - float(before[leg].x)
		if absf(dx) < 0.0005:
			continue
		var angle: float = rad_to_deg(asin(clampf(dx / length, -0.5, 0.5)))
		_add(leg + "UpperLeg", Vector3(0.0, 0.0, angle))
		if absf(_origin(leg + "Foot").x - float(before[leg].x)) > absf(dx):
			_add(leg + "UpperLeg", Vector3(0.0, 0.0, -2.0 * angle))
	var ref: String = only if not only.is_empty() else "left"
	_move_hips(Vector3(0.0, float(before[ref].y) - _origin(ref + "Foot").y, 0.0))

func _leg_length() -> float:
	return maxf(0.3, _origin("hips").y - _origin("leftFoot").y) if rig.bones.has("leftFoot") else 0.75

func _move_hips(offset: Vector3) -> void:
	var hips: int = int(rig.bones["hips"])
	var parent: int = skeleton.get_bone_parent(hips)
	var parent_basis: Basis = skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + parent_basis.inverse() * offset)

func _hands_to_belly(w: float) -> void:
	if driver == null or not driver.available:
		return
	var h: float = driver.height_m
	var hips: Vector3 = _origin("hips")
	for index in range(2):
		var sign_x: float = 1.0 if index == 0 else -1.0
		var target: Vector3 = hips + Vector3(sign_x * 0.035 * h, 0.06 * h, 0.09 * h)
		# Ладонью к животику, пальцы — навстречу друг другу (не вниз).
		var palm: Quaternion = Quaternion(Vector3(0.0, 0.0, 1.0), deg_to_rad(-sign_x * 90.0)) * Quaternion(Vector3.RIGHT, deg_to_rad(90.0))
		_reach(index, target, w, palm, "low")

## Кисть руки index к цели target (IK), плавно по весу w; extra — доворот кисти.
## style: "raise" — локоть вниз (рука у лица), "low" — локоть в сторону-назад.
func _reach(index: int, target: Vector3, w: float, extra: Quaternion, style: String) -> void:
	if w <= 0.001:
		return
	var arm: Dictionary = driver.arms[index]
	var sign_x: float = 1.0 if index == 0 else -1.0
	var hand_now: Transform3D = skeleton.get_bone_global_pose(int(arm["end"]))
	var goal: Vector3 = hand_now.origin.lerp(target, w)
	var keys: Array = ["upper", "lower", "end"]
	var saved: Array[Quaternion] = []
	for key in keys:
		saved.append(skeleton.get_bone_pose_rotation(int(arm[key])))
	var aim: Quaternion = extra * arm["end_q"] if style in ["raise", "raw"] else extra * Quaternion(Vector3.UP, -sign_x * PI * 0.5) * arm["end_q"]
	var hand_q: Quaternion = hand_now.basis.orthonormalized().get_rotation_quaternion().slerp(aim.normalized(), w).normalized()
	var pole: Vector3 = Vector3(sign_x * 0.25, -1.0, 0.15) if style == "raise" else Vector3(sign_x * 0.5, -1.0, -0.1)
	driver._solve(arm, goal, pole, hand_q)
	var blend: float = smoothstep(0.0, 0.2, w)
	for i in range(3):
		var bone: int = int(arm[keys[i]])
		skeleton.set_bone_pose_rotation(bone, saved[i].slerp(skeleton.get_bone_pose_rotation(bone), blend).normalized())

## Кадр клипа поверх обычной позы: поворот кости = поза * поворот из клипа.
## Кость, которую кадр не сбросил (большой палец), считаем от её позы до
## реакции — без накопления.
func _apply_clip(clip: Animation) -> void:
	var frame: Dictionary = _frame(clip)
	for semantic in frame["bones"]:
		if not rig.bones.has(semantic):
			continue
		var bone: int = int(rig.bones[semantic])
		var current: Quaternion = skeleton.get_bone_pose_rotation(bone)
		if _clip_set.has(bone) and current.is_equal_approx(_clip_set[bone]):
			current = _clip_base[bone]
		else:
			_clip_base[bone] = current
		var posed: Quaternion = (current * (frame["bones"][semantic] as Quaternion)).normalized()
		skeleton.set_bone_pose_rotation(bone, posed)
		_clip_set[bone] = posed
	var offset: Vector3 = frame["hips_offset"]
	if offset.length_squared() > 0.0 and driver != null:
		_move_hips(offset * driver.height_m)

## Кадр клипа для этой стороны. Клип записан для левой стороны; для правой —
## зеркало: левые и правые кости меняются местами, повороты отражаются
## (VRM: оси костей в покое совпадают с осями сцены), поворот тела и сдвиг
## таза вбок — с обратным знаком.
func _frame(clip: Animation) -> Dictionary:
	var frame: Dictionary = TouchMotion.sample(clip, age)
	if side != "right":
		return frame
	var mirrored: Dictionary = {}
	for semantic in frame["bones"]:
		var q: Quaternion = frame["bones"][semantic]
		var other: String = semantic
		if semantic.begins_with("left"):
			other = "right" + semantic.trim_prefix("left")
		elif semantic.begins_with("right"):
			other = "left" + semantic.trim_prefix("right")
		mirrored[other] = Quaternion(q.x, -q.y, -q.z, q.w)
	frame["bones"] = mirrored
	frame["yaw"] = -float(frame["yaw"])
	var offset: Vector3 = frame["hips_offset"]
	frame["hips_offset"] = Vector3(-offset.x, offset.y, offset.z)
	return frame

func _restore_clip_bones() -> void:
	for bone in _clip_set:
		if skeleton.get_bone_pose_rotation(bone).is_equal_approx(_clip_set[bone]):
			skeleton.set_bone_pose_rotation(bone, _clip_base[bone])
	_clip_set.clear()
	_clip_base.clear()

## Поза всех редактируемых костей и положение таза — для запекания клипа.
func _pose_snapshot() -> Dictionary:
	var bones: Dictionary = {}
	for semantic in SketchMotion.BONE_TARGET_NAMES:
		if rig.bones.has(semantic):
			bones[semantic] = skeleton.get_bone_pose_rotation(int(rig.bones[semantic]))
	return {"bones": bones, "hips": _origin("hips")}

## Повернуть кость от её позы до реакции (для костей, которые кадр не сбрасывает).
func _hold(semantic: String, degrees: Vector3) -> void:
	if not rig.bones.has(semantic) or not rig.parent_rest_rotations.has(int(rig.bones[semantic])):
		return
	var bone: int = int(rig.bones[semantic])
	if not _base.has(bone):
		_base[bone] = skeleton.get_bone_pose_rotation(bone)
	var parent_q: Quaternion = rig.parent_rest_rotations[bone]
	var extra: Quaternion = parent_q.inverse() * Quaternion.from_euler(degrees * (PI / 180.0)) * parent_q
	skeleton.set_bone_pose_rotation(bone, (extra * _base[bone]).normalized())

func _restore_base() -> void:
	for bone in _base:
		skeleton.set_bone_pose_rotation(bone, _base[bone])
	_base.clear()

func _origin(semantic: String) -> Vector3:
	return skeleton.get_bone_global_pose(int(rig.bones[semantic])).origin

static func _smoother(x: float) -> float:
	var v: float = clampf(x, 0.0, 1.0)
	return v * v * v * (v * (v * 6.0 - 15.0) + 10.0)

func _add(semantic: String, degrees: Vector3) -> void:
	if not rig.bones.has(semantic) or not rig.parent_rest_rotations.has(int(rig.bones[semantic])):
		return
	var bone: int = int(rig.bones[semantic])
	var parent_q: Quaternion = rig.parent_rest_rotations[bone]
	var extra: Quaternion = parent_q.inverse() * Quaternion.from_euler(degrees * (PI / 180.0)) * parent_q
	skeleton.set_bone_pose_rotation(bone, (extra * skeleton.get_bone_pose_rotation(bone)).normalized())
