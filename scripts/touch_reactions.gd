extends RefCounted
## Реакции на касание по месту (просьба 28.09.2026): куда ткнули — так и ответила.
##   leg   — ножкой дрыг-дрыг (сидя на краю — быстро болтает этой ножкой);
##   arm   — трясёт ручкой, будто стряхивает;
##   belly — прикрывает животик ладошками, чуть сгибается, хихикает;
##   chest — отворачивается полубоком, оглядывается и грозит пальчиком «ай-яй-яй».
## Голова — как раньше (внимание, поглаживание). Слой поверх позы: только
## добавочные повороты и цели кистей, ступни стоящей Хоши на месте.
## Сила — animations/life_style.tres (группа «Касания»).

const DURATION: Dictionary = {"leg": 1.4, "arm": 1.3, "belly": 1.8, "chest": 2.2}
const COOLDOWN: float = 0.8
const ZONES: Array[String] = ["leg", "arm", "belly", "chest"]

var rig
var driver               # posture_driver.gd: руки (IK) и повороты костей
var skeleton: Skeleton3D
var available: bool = false
var zone: String = ""
var side: String = "left"
var age: float = 0.0
var weight: float = 0.0
var _cooldown: float = 0.0

func setup(rig_driver, posture_driver) -> void:
	rig = rig_driver
	driver = posture_driver
	skeleton = rig.skeleton if rig != null else null
	available = skeleton != null and rig.bones.has("hips") and rig.bones.has("head")

## Начать реакцию. Та же зона во время реакции или сразу после — не перезапускаем.
func start(value: String, which: String = "left") -> bool:
	if not available or not value in ZONES:
		return false
	if (value == zone and weight > 0.05) or _cooldown > 0.0:
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

## Лицо на время реакции: {выражение: сила}.
func face() -> Dictionary:
	if not active():
		return {}
	match zone:
		"chest":
			return {"angry": 0.38 * weight}
		"belly", "leg", "arm":
			return {"happy": 0.55 * weight}
	return {}

func tick(delta: float) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	_cooldown = maxf(0.0, _cooldown - dt)
	if zone.is_empty():
		weight = 0.0
		return
	age += dt
	var length: float = float(DURATION.get(zone, 1.5))
	weight = smoothstep(0.0, 0.16, age) * (1.0 - smoothstep(length - 0.4, length, age))
	if age >= length:
		zone = ""
		weight = 0.0

## seated — сидит (на полу или на краю): ножками болтаем, а не поднимаем стоя.
func apply(time: float, seated: bool) -> void:
	if not active():
		return
	var w: float = weight
	var s: float = 1.0 if side == "left" else -1.0
	var life = load("res://scripts/life_style.gd").active()
	var k: float = float(life.touch_strength)
	match zone:
		"leg":
			var kick: float = sin(age * 17.0)
			if seated:
				_add(side + "UpperLeg", Vector3(-10.0 * kick, 0.0, 0.0) * w * k)
				_add(side + "LowerLeg", Vector3(38.0 * kick, 0.0, 0.0) * w * k)
			else:
				# Приподнять ножку и дрыгнуть: колено вперёд, голень туда-сюда.
				_add(side + "UpperLeg", Vector3(-22.0 - 6.0 * kick, 0.0, 0.0) * w * k)
				_add(side + "LowerLeg", Vector3(48.0 + 26.0 * kick, 0.0, 0.0) * w * k)
				_add(side + "Foot", Vector3(-14.0 + 10.0 * kick, 0.0, 0.0) * w * k)
				_add("spine", Vector3(-2.0, 0.0, s * 2.5) * w * k)
			_add("head", Vector3(3.0, 0.0, -s * 3.0) * w)
		"arm":
			var shake: float = sin(age * 19.0)
			# Ручку чуть вперёд-в сторону и потрясти предплечьем и кистью.
			_add(side + "UpperArm", Vector3(-22.0, 0.0, s * 18.0) * w * k)
			_add(side + "LowerArm", Vector3(0.0, s * 30.0 * shake, -s * 28.0) * w * k)
			_add(side + "Hand", Vector3(0.0, 0.0, s * 40.0 * shake) * w * k)
			_add("chest", Vector3(0.0, s * 3.0, 0.0) * w)
			_add("head", Vector3(2.0, s * 8.0, 0.0) * w)
		"belly":
			var giggle: float = sin(age * 15.0) * 1.4
			_add("spine", Vector3(8.0 + giggle, 0.0, 0.0) * w * k)
			_add("chest", Vector3(4.0 + giggle * 0.6, 0.0, 0.0) * w * k)
			_add("head", Vector3(7.0, 0.0, giggle) * w)
			_hands_to(Vector3(0.0, 0.055, 0.085), 0.045, w, "")
		"chest":
			# Полубоком от руки, голова — к тебе; правой ручкой грозит пальчиком.
			var wag: float = sin(age * 9.0)
			var turn: float = 24.0 * k
			_add("hips", Vector3(0.0, turn * 0.35, 0.0) * w)
			_add("spine", Vector3(-2.0, turn * 0.4, 0.0) * w)
			_add("chest", Vector3(-2.0, turn * 0.3, 0.0) * w)
			_add("neck", Vector3(0.0, -turn * 0.45, 0.0) * w)
			_add("head", Vector3(-3.0, -turn * 0.55, -4.0) * w)
			_finger_wag(w, wag)

## Обе кисти (или одна) — к точке у тела: offset — от таза (доли роста: x вбок,
## y вверх, z вперёд), spread — насколько кисти врозь.
func _hands_to(offset: Vector3, spread: float, w: float, only: String) -> void:
	if driver == null or not driver.available:
		return
	var h: float = driver.height_m
	var hips: Vector3 = skeleton.get_bone_global_pose(int(rig.bones["hips"])).origin
	for index in range(2):
		var name: String = "left" if index == 0 else "right"
		if not only.is_empty() and name != only:
			continue
		var sign_x: float = 1.0 if index == 0 else -1.0
		# Ладонью к животику: кисть повёрнута вокруг пальцев на 90°.
		_reach(index, hips + Vector3(offset.x * h + sign_x * spread * h, offset.y * h, offset.z * h), w, Quaternion(Vector3.RIGHT, deg_to_rad(90.0)), false)

## Правая ручка у лица, указательный пальчик вверх, кисть качается «ай-яй-яй».
func _finger_wag(w: float, wag: float) -> void:
	if driver == null or not driver.available:
		return
	var h: float = driver.height_m
	var chest: Vector3 = skeleton.get_bone_global_pose(int(rig.bones["chest" if rig.bones.has("chest") else "spine"])).origin
	var target: Vector3 = chest + Vector3(-0.09 * h, 0.16 * h, 0.15 * h)
	_reach(1, target, w, Quaternion(Vector3(0.0, 0.0, 1.0), deg_to_rad(-90.0 + 22.0 * wag)), true)
	for finger in ["Middle", "Ring", "Little"]:
		for part in ["Proximal", "Intermediate"]:
			_add("right" + finger + part, Vector3(0.0, 70.0, 0.0) * w)
	_add("rightThumbProximal", Vector3(0.0, 25.0, 20.0) * w)

## Кисть руки index к цели target (IK), плавно по весу w; extra — доворот кисти.
func _reach(index: int, target: Vector3, w: float, extra: Quaternion, raise: bool) -> void:
	var arm: Dictionary = driver.arms[index]
	var sign_x: float = 1.0 if index == 0 else -1.0
	var hand_now: Transform3D = skeleton.get_bone_global_pose(int(arm["end"]))
	var goal: Vector3 = hand_now.origin.lerp(target, w)
	var keys: Array = ["upper", "lower", "end"]
	var saved: Array[Quaternion] = []
	for key in keys:
		saved.append(skeleton.get_bone_pose_rotation(int(arm[key])))
	var hand_q: Quaternion = hand_now.basis.orthonormalized().get_rotation_quaternion()
	var aim: Quaternion = (extra * arm["end_q"]) if raise else (extra * Quaternion(Vector3.UP, -sign_x * PI * 0.5) * arm["end_q"])
	hand_q = hand_q.slerp(aim.normalized(), w).normalized()
	# Поднятая к лицу рука — локтем вниз; у тела — локтем в сторону-назад.
	var pole: Vector3 = Vector3(sign_x * 0.25, -1.0, 0.15) if raise else Vector3(sign_x * 0.5, -1.0, -0.1)
	driver._solve(arm, goal, pole, hand_q)
	var blend: float = smoothstep(0.0, 0.2, w)
	for i in range(3):
		var bone: int = int(arm[keys[i]])
		skeleton.set_bone_pose_rotation(bone, saved[i].slerp(skeleton.get_bone_pose_rotation(bone), blend).normalized())

func _add(semantic: String, degrees: Vector3) -> void:
	if not rig.bones.has(semantic) or not rig.parent_rest_rotations.has(int(rig.bones[semantic])):
		return
	var bone: int = int(rig.bones[semantic])
	var parent_q: Quaternion = rig.parent_rest_rotations[bone]
	var extra: Quaternion = parent_q.inverse() * Quaternion.from_euler(degrees * (PI / 180.0)) * parent_q
	skeleton.set_bone_pose_rotation(bone, (extra * skeleton.get_bone_pose_rotation(bone)).normalized())
