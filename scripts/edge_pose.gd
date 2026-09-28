@tool
extends RefCounted
## Separate ledge pose. Reuses the tested IK solver, never changes the floor pose.
## +Z is forward; dangling legs are not treated as planted feet.
var driver
var available: bool = false
var seat_point: Vector3 = Vector3.ZERO
# Separate ledge contact calibration: do not alter the accepted floor seat.
var seat_offset_ratio: float = 0.078
var ankle_targets: Array[Vector3] = []
# Rhythm of the reference (procedural) seated gestures. Every frequency is a whole
# number of cycles per clip length in seated_motion.gd, so baked clips loop seamlessly.
const SWAY_W: float = TAU * 2.0 / 8.0
const SWAY_SLOW_W: float = TAU / 8.0
const SWING_W: float = TAU * 3.0 / 7.25
const HUM_W: float = TAU * 2.0 / 5.35
const NOD_W: float = TAU / 5.25
const BALANCE_W: float = TAU / 3.6

func setup(floor_driver) -> void:
	driver = floor_driver
	available = driver.available

func apply(amount: float, time: float, wave: float, motion: bool, life: Dictionary = {}) -> void:
	if not available or amount <= 0.0:
		return
	var p: float = clampf(amount, 0.0, 1.0)
	# Переход «сесть на край / встать»: посередине — наклон вперёд и упор руками
	# в полочку по бокам (как человек садится на выступ), к концу — обычная поза.
	var settle: float = sin(PI * p) * (1.0 - smoothstep(0.85, 1.0, p)) if p < 1.0 else 0.0
	var lean: float = clampf(float(life.get("lean", 0.0)), 0.0, 1.0) * p
	var swing: float = clampf(float(life.get("swing", 0.0)), 0.0, 1.0) * p
	var peek: float = clampf(float(life.get("peek", 0.0)), 0.0, 1.0) * p
	var balance: float = clampf(float(life.get("balance", 0.0)), 0.0, 1.0) * p
	var sway: float = clampf(float(life.get("sway", 0.0)), 0.0, 1.0) * p
	var hum: float = clampf(float(life.get("hum", 0.0)), 0.0, 1.0) * p
	var nod: float = clampf(float(life.get("nod", 0.0)), 0.0, 1.0) * p
	var sketch: float = clampf(float(life.get("sketch", 0.0)), 0.0, 1.0) * p
	var fold: float = clampf(float(life.get("fold", 0.0)), 0.0, 1.0) * p
	var admire_star: float = clampf(float(life.get("admire_star", 0.0)), 0.0, 1.0) * p
	var scoot: float = clampf(float(life.get("scoot_weight", 0.0)), 0.0, 1.0) * p
	var scoot_direction: float = signf(float(life.get("scoot_direction", 0.0)))
	var sketch_progress: float = clampf(float(life.get("sketch_progress", 0.0)), 0.0, 1.0)
	var sketch_show: float = smoothstep(0.70, 0.86, sketch_progress) * (1.0 - smoothstep(0.94, 1.0, sketch_progress))
	var sketch_channels: Dictionary = life.get("sketch_channels", {})
	var head_correction: float = 0.0
	var chest_correction: float = 0.0
	var hand_corrections: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var wrist_corrections: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var gesture_channels: Dictionary = life.get("gesture_channels", {})
	var baked_weights: Dictionary = {}
	for gesture in gesture_channels:
		var strength: float = clampf(float(life.get(gesture, 0.0)), 0.0, 1.0) * p
		var corrections: Dictionary = gesture_channels[gesture]
		if not (corrections.get("bones", {}) as Dictionary).is_empty():
			baked_weights[gesture] = strength
		head_correction += strength * float(corrections.get("head_pitch", 0.0))
		chest_correction += strength * float(corrections.get("chest_pitch", 0.0))
		hand_corrections[0] += strength * (corrections.get("left_hand", Vector3.ZERO) as Vector3) * driver.height_m
		hand_corrections[1] += strength * (corrections.get("right_hand", Vector3.ZERO) as Vector3) * driver.height_m
		wrist_corrections[0] += strength * (corrections.get("left_hand_rotation", Vector3.ZERO) as Vector3)
		wrist_corrections[1] += strength * (corrections.get("right_hand_rotation", Vector3.ZERO) as Vector3)
	# The saved pose now contains the visible gesture. Keep the old procedural path
	# for an unbaked clip and for the reference baker, but never apply both.
	for gesture in baked_weights:
		match gesture:
			"lean": lean = 0.0
			"swing": swing = 0.0
			"peek": peek = 0.0
			"balance": balance = 0.0
			"sway": sway = 0.0
			"hum": hum = 0.0
			"nod": nod = 0.0
			"fold": fold = 0.0
			"admire_star": admire_star = 0.0
	var fold_progress: float = clampf(float(life.get("fold_progress", 0.0)), 0.0, 1.0)
	var fold_show: float = smoothstep(0.70, 0.83, fold_progress) * (1.0 - smoothstep(0.93, 1.0, fold_progress))
	var admire_progress: float = clampf(float(life.get("admire_progress", 0.0)), 0.0, 1.0)
	var admire_show: float = smoothstep(0.0, 0.23, admire_progress) * (1.0 - smoothstep(0.80, 1.0, admire_progress))
	var balance_wave: float = sin(time * BALANCE_W) * balance
	# Two close but non-identical waves keep sway from reading as a metronome.
	var sway_spine: float = (sin(time * SWAY_W) * 0.82 + sin(time * SWAY_SLOW_W + 0.65) * 0.18) * sway
	var sway_chest: float = sin(time * SWAY_W - 0.20) * sway
	var sway_head: float = sin(time * SWAY_W - 0.38) * sway
	var hum_side: float = sin(time * HUM_W + 0.15) * hum
	var hum_bob: float = sin(time * HUM_W * 2.0 + 0.55) * hum
	var nod_cycle: float = sin(time * NOD_W * 4.0) * (0.82 + sin(time * NOD_W + 0.4) * 0.18) * nod
	var nod_side: float = sin(time * NOD_W * 2.0 + 0.9) * nod
	var h: float = driver.height_m
	var skel: Skeleton3D = driver.skeleton
	var hip: Vector3 = driver.hips_rest
	hip.y = lerpf(hip.y, driver.ground_y + h * 0.42, p)
	hip.z -= h * 0.06 * p
	# The seat contact remains on the edge while the pelvis briefly lifts for a push.
	seat_point = hip - Vector3(0.0, h * seat_offset_ratio, 0.0)
	hip.y += h * 0.018 * scoot
	driver._set_position_global(driver.gait.hips_id, hip)
	driver._add_rotation("spine", Vector3(
		3.0 * p + settle * 16.0 - lean * 19.0 + hum_bob * 0.45 + scoot * 3.0 + fold * (3.5 - fold_show * 4.5),
		balance_wave * 1.5 + sway_spine * 0.30 + hum_side * 0.25,
		balance_wave * 3.8 + sway_spine * 3.6 + hum_side * 0.45 + scoot_direction * scoot * 10.0))
	driver._add_rotation("chest", Vector3(
		settle * 7.0 - lean * 10.0 + hum_bob * 0.80 - nod_cycle * 0.45 + sketch * float(sketch_channels.get("chest_pitch", 0.0)) + chest_correction,
		-balance_wave * 1.0 - sway_chest * 0.18 - hum_side * 0.20,
		-balance_wave * 2.7 - sway_chest * 1.35 - hum_side * 0.18 + scoot_direction * scoot * 5.0))
	driver._add_rotation("neck", Vector3(
		-hum_bob * 0.45 + nod_cycle * 1.70,
		hum_side * 0.25 + nod_side * 0.20,
		-sway_head * 0.85 - hum_side * 0.18 + nod_side * 0.18))
	driver._add_rotation("head", Vector3(
		peek * 14.0 + lean * 9.0 + hum_bob * 0.35 + nod_cycle * 3.80 + sketch * float(sketch_channels.get("head_pitch", 11.0 * (1.0 - sketch_show) - 3.0 * sketch_show)) + fold * (10.0 * (1.0 - fold_show) - 4.0 * fold_show) - admire_star * admire_show * 3.0 + head_correction,
		peek * 3.0 - balance_wave * 2.0 - hum_side * 0.18 + nod_side * 0.35,
		-balance_wave * 2.2 - sway_head * 0.95 - hum_side * 0.12 - nod_side * 0.25))
	var left_hum: float = sin(time * HUM_W * 2.0 + 0.20) * hum
	var right_hum: float = sin(time * HUM_W * 2.0 + 0.55) * hum
	driver._add_rotation("leftShoulder", Vector3(-left_hum * 0.35 - nod_cycle * 0.18, 0.0, -left_hum * 0.55))
	driver._add_rotation("rightShoulder", Vector3(-right_hum * 0.35 - nod_cycle * 0.18, 0.0, right_hum * 0.55))
	ankle_targets.clear()
	for side in range(2):
		var leg: Dictionary = driver.gait.legs[side]
		var start: Vector3 = skel.get_bone_global_pose(int(leg["upper"])).origin
		var a: float = float(leg["a"])
		var b: float = float(leg["b"])
		var kick: float = (0.10 + sin(time * 1.3 + float(side) * 0.8) * 0.055) if motion else 0.10
		kick += sin(time * SWING_W + float(side) * PI) * 0.28 * swing
		# Sway carries a relaxed, slower counter-swing through the dangling legs.
		# It stays well below the dedicated playful "swing" gesture.
		kick += sin(time * SWAY_W + float(side) * PI) * 0.125 * sway
		kick += sin(time * HUM_W + float(side) * 0.65) * 0.006 * hum
		var endpoint: Vector3 = start + Vector3(0.0, -a * 0.045 - b * cos(kick), a * 0.999 + b * sin(kick))
		# Ступни сначала уходят вперёд за край, потом вниз — не сквозь полочку.
		var rest_ankle: Vector3 = leg["rest_ankle"]
		var target: Vector3 = Vector3(lerpf(rest_ankle.x, endpoint.x, p),
			lerpf(rest_ankle.y, endpoint.y, smoothstep(0.3, 1.0, p)),
			lerpf(rest_ankle.z, endpoint.z, smoothstep(0.0, 0.55, p)))
		ankle_targets.append(target)
		var chain: Dictionary = {"upper": leg["upper"], "lower": leg["lower"], "end": leg["foot"], "a": a, "b": b}
		driver._solve(chain, target, Vector3(0.0, 0.05, 1.0), leg["foot_q"])
	for side in range(2):
		var arm: Dictionary = driver.arms[side]
		var sign_x: float = 1.0 if side == 0 else -1.0
		var knee: Vector3 = skel.get_bone_global_pose(int(driver.gait.legs[side]["lower"])).origin
		var thigh: Vector3 = skel.get_bone_global_pose(int(driver.gait.legs[side]["upper"])).origin
		# Кисти лежат на середине бедра, чуть снаружи: локти мягко согнуты (раньше
		# кисть тянулась почти к колену и рука выпрямлялась — жалоба 28.09).
		var wrist: Vector3 = thigh.lerp(knee, 0.46) + Vector3(sign_x * h * 0.034, h * 0.046, -h * 0.004)
		var support_hand: Vector3 = hip + Vector3(sign_x * h * 0.12, -h * 0.040, -h * 0.07)
		wrist = wrist.lerp(support_hand, lean)
		if settle > 0.001:
			# Ладонь — на саму полочку (высота будущего сиденья), близко к бедру.
			var seat_y: float = driver.ground_y + h * (0.42 - seat_offset_ratio)
			var ledge_hand: Vector3 = Vector3(hip.x + sign_x * h * 0.115, seat_y + h * 0.02, hip.z - h * 0.03)
			wrist = wrist.lerp(ledge_hand, settle * 0.9)
		var bracing: bool = scoot > 0.001 and side == (1 if scoot_direction > 0.0 else 0)
		if bracing:
			# Ладонь-опора рядом с бедром, чуть сзади; корпус наклонён к ней — локоть
			# мягко согнут, а не прямая рука далеко в стороне (жалоба 28.09).
			var brace_hand: Vector3 = seat_point + Vector3(sign_x * h * 0.13, -h * 0.01, -h * 0.045)
			wrist = wrist.lerp(brace_hand, scoot)
		if sketch > 0.001:
			var default_hand: Vector3 = Vector3(sign_x * 0.09, -0.065 + sketch_show * 0.18, 0.27 - sketch_show * 0.07)
			var authored_hand: Vector3 = sketch_channels.get("left_hand" if side == 0 else "right_hand", default_hand)
			var drawing_hand: Vector3 = hip + authored_hand * h
			wrist = wrist.lerp(drawing_hand, sketch)
		if fold > 0.001:
			var folding_hand: Vector3 = hip + Vector3(sign_x * h * (0.072 + fold_show * 0.015), h * (-0.035 + fold_show * 0.18), h * (0.27 - fold_show * 0.035))
			if fold_progress > 0.12 and fold_progress < 0.68:
				var crease_motion: float = sin(fold_progress * TAU * 4.0 + float(side) * PI)
				folding_hand += Vector3(-sign_x * h * 0.016 * maxf(0.0, crease_motion), h * 0.007 * crease_motion, 0.0)
			wrist = wrist.lerp(folding_hand, fold)
		if admire_star > 0.001:
			var admire_hand: Vector3 = hip + Vector3(sign_x * h * 0.08, h * (-0.025 + admire_show * 0.18), h * (0.27 - admire_show * 0.035))
			wrist = wrist.lerp(admire_hand, admire_star)
		if baked_weights.is_empty():
			wrist += hand_corrections[side]
		# В переходе (0 < p < 1) ведём саму цель кисти от того, где рука висит сейчас,
		# к цели позы — рука тянется к ней по прямой. Раньше смешивались повороты
		# костей, и на полпути рука уходила в сторону (жалоба 28.09).
		var hand_now: Transform3D = skel.get_bone_global_pose(int(arm["end"]))
		wrist = hand_now.origin.lerp(wrist, p)
		var saved: Array[Quaternion] = []
		for key in ["upper", "lower", "end"]:
			saved.append(skel.get_bone_pose_rotation(int(arm[key])))
		var hand_q: Quaternion = Quaternion(Vector3.UP, -sign_x * PI * 0.5) * arm["end_q"]
		hand_q = hand_now.basis.orthonormalized().get_rotation_quaternion().slerp(hand_q, p).normalized()
		if sketch > 0.001:
			var rotation_key: String = "left_hand_rotation" if side == 0 else "right_hand_rotation"
			var hand_rotation: Vector3 = sketch_channels.get(rotation_key, Vector3.ZERO)
			# Authoring target axes are aligned with the scene, not the wrist's rest basis.
			var authored_q: Quaternion = Quaternion.from_euler(hand_rotation * (PI / 180.0)) * hand_q
			hand_q = hand_q.slerp(authored_q, sketch).normalized()
		if baked_weights.is_empty() and wrist_corrections[side].length_squared() > 0.000001:
			var extra_rotation: Vector3 = wrist_corrections[side].clamp(Vector3.ONE * -35.0, Vector3.ONE * 35.0)
			hand_q = Quaternion.from_euler(extra_rotation * (PI / 180.0)) * hand_q
		if bracing:
			var finger_axis: Vector3 = (hand_q * Vector3.RIGHT).normalized()
			var edge_grip: Quaternion = Quaternion(finger_axis, deg_to_rad(-72.0)) * hand_q
			hand_q = hand_q.slerp(edge_grip, scoot).normalized()
		driver._solve(arm, wrist, Vector3(sign_x * 0.4, -1.0, -0.12), hand_q)
		if bracing:
			var side_name: String = "left" if side == 0 else "right"
			var curl_sign: float = -1.0 if side == 0 else 1.0
			for finger in ["Index", "Middle", "Ring", "Little"]:
				driver._add_rotation(side_name + finger + "Proximal", Vector3(0.0, curl_sign * 20.0 * scoot, 0.0))
		# Совсем в начале перехода IK подмешивается мягко — без щелчка локтя.
		var weight: float = smoothstep(0.0, 0.15, p) * (1.0 - clampf(wave, 0.0, 1.0) if side == 1 else 1.0)
		var keys: Array = ["upper", "lower", "end"]
		for index in range(3):
			var bone: int = int(arm[keys[index]])
			skel.set_bone_pose_rotation(bone, saved[index].slerp(skel.get_bone_pose_rotation(bone), weight).normalized())
	for gesture in baked_weights:
		var weight: float = float(baked_weights[gesture])
		var bone_deltas: Dictionary = (gesture_channels[gesture] as Dictionary).get("bones", {})
		for semantic in bone_deltas:
			if not driver.rig.bones.has(semantic):
				continue
			var bone_id: int = int(driver.rig.bones[semantic])
			var base_rotation: Quaternion = skel.get_bone_pose_rotation(bone_id)
			var delta_rotation: Quaternion = bone_deltas[semantic]
			skel.set_bone_pose_rotation(bone_id, (base_rotation * Quaternion.IDENTITY.slerp(delta_rotation, weight)).normalized())
	if not baked_weights.is_empty():
		_apply_baked_hand_corrections(hand_corrections, wrist_corrections, p, wave)

func _apply_baked_hand_corrections(positions: Array[Vector3], rotations: Array[Vector3], pose_weight: float, wave: float) -> void:
	var skel: Skeleton3D = driver.skeleton
	for side in range(2):
		if positions[side].length_squared() < 0.00000001 and rotations[side].length_squared() < 0.000001:
			continue
		var arm: Dictionary = driver.arms[side]
		var end_id: int = int(arm["end"])
		var end_pose: Transform3D = skel.get_bone_global_pose(end_id)
		var target: Vector3 = end_pose.origin + positions[side]
		var rotation: Vector3 = rotations[side].clamp(Vector3.ONE * -35.0, Vector3.ONE * 35.0)
		var hand_q: Quaternion = Quaternion.from_euler(rotation * (PI / 180.0)) * end_pose.basis.get_rotation_quaternion()
		var saved: Array[Quaternion] = []
		for key in ["upper", "lower", "end"]:
			saved.append(skel.get_bone_pose_rotation(int(arm[key])))
		var sign_x: float = 1.0 if side == 0 else -1.0
		driver._solve(arm, target, Vector3(sign_x * 0.4, -1.0, -0.12), hand_q)
		var weight: float = pose_weight * (1.0 - clampf(wave, 0.0, 1.0) if side == 1 else 1.0)
		for index in range(3):
			var bone: int = int(arm[["upper", "lower", "end"][index]])
			skel.set_bone_pose_rotation(bone, saved[index].slerp(skel.get_bone_pose_rotation(bone), weight).normalized())

func anchor_world() -> Vector3:
	return driver.skeleton.global_transform * seat_point

func planned_anchor_world() -> Vector3:
	if not available:
		return Vector3.ZERO
	var hip: Vector3 = driver.hips_rest
	hip.y = driver.ground_y + driver.height_m * 0.42
	hip.z -= driver.height_m * 0.06
	var planned_seat: Vector3 = hip - Vector3(0.0, driver.height_m * driver.seat_height_ratio, 0.0)
	return driver.skeleton.global_transform * planned_seat
