extends RefCounted
## Separate ledge pose. Reuses the tested IK solver, never changes the floor pose.
## +Z is forward; dangling legs are not treated as planted feet.
var driver
var available: bool = false
var seat_point: Vector3 = Vector3.ZERO
# Separate ledge contact calibration: do not alter the accepted floor seat.
var seat_offset_ratio: float = 0.078
var ankle_targets: Array[Vector3] = []

func setup(floor_driver) -> void:
	driver = floor_driver
	available = driver.available

func apply(amount: float, time: float, wave: float, motion: bool, life: Dictionary = {}) -> void:
	if not available or amount <= 0.0:
		return
	var p: float = clampf(amount, 0.0, 1.0)
	var lean: float = clampf(float(life.get("lean", 0.0)), 0.0, 1.0) * p
	var swing: float = clampf(float(life.get("swing", 0.0)), 0.0, 1.0) * p
	var peek: float = clampf(float(life.get("peek", 0.0)), 0.0, 1.0) * p
	var balance: float = clampf(float(life.get("balance", 0.0)), 0.0, 1.0) * p
	var sway: float = clampf(float(life.get("sway", 0.0)), 0.0, 1.0) * p
	var hum: float = clampf(float(life.get("hum", 0.0)), 0.0, 1.0) * p
	var nod: float = clampf(float(life.get("nod", 0.0)), 0.0, 1.0) * p
	var sketch: float = clampf(float(life.get("sketch", 0.0)), 0.0, 1.0) * p
	var scoot: float = clampf(float(life.get("scoot_weight", 0.0)), 0.0, 1.0) * p
	var scoot_direction: float = signf(float(life.get("scoot_direction", 0.0)))
	var sketch_progress: float = clampf(float(life.get("sketch_progress", 0.0)), 0.0, 1.0)
	var sketch_show: float = smoothstep(0.70, 0.86, sketch_progress) * (1.0 - smoothstep(0.94, 1.0, sketch_progress))
	var balance_wave: float = sin(time * 1.75) * balance
	# Two close but non-identical waves keep sway from reading as a metronome.
	var sway_spine: float = (sin(time * 1.55) * 0.82 + sin(time * 0.73 + 0.65) * 0.18) * sway
	var sway_chest: float = sin(time * 1.55 - 0.20) * sway
	var sway_head: float = sin(time * 1.55 - 0.38) * sway
	var hum_side: float = sin(time * 2.35 + 0.15) * hum
	var hum_bob: float = sin(time * 4.70 + 0.55) * hum
	var nod_cycle: float = sin(time * 4.80) * (0.82 + sin(time * 1.15 + 0.4) * 0.18) * nod
	var nod_side: float = sin(time * 2.40 + 0.9) * nod
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
		3.0 * p - lean * 19.0 + hum_bob * 0.45 + scoot * 3.0,
		balance_wave * 1.5 + sway_spine * 0.30 + hum_side * 0.25,
		balance_wave * 3.8 + sway_spine * 3.6 + hum_side * 0.45 + scoot_direction * scoot * 18.0))
	driver._add_rotation("chest", Vector3(
		-lean * 10.0 + hum_bob * 0.80 - nod_cycle * 0.45,
		-balance_wave * 1.0 - sway_chest * 0.18 - hum_side * 0.20,
		-balance_wave * 2.7 - sway_chest * 1.35 - hum_side * 0.18 + scoot_direction * scoot * 9.0))
	driver._add_rotation("neck", Vector3(
		-hum_bob * 0.45 + nod_cycle * 1.70,
		hum_side * 0.25 + nod_side * 0.20,
		-sway_head * 0.85 - hum_side * 0.18 + nod_side * 0.18))
	driver._add_rotation("head", Vector3(
		peek * 14.0 + lean * 9.0 + hum_bob * 0.35 + nod_cycle * 3.80 + sketch * (11.0 * (1.0 - sketch_show) - 3.0 * sketch_show),
		peek * 3.0 - balance_wave * 2.0 - hum_side * 0.18 + nod_side * 0.35,
		-balance_wave * 2.2 - sway_head * 0.95 - hum_side * 0.12 - nod_side * 0.25))
	var left_hum: float = sin(time * 4.70 + 0.20) * hum
	var right_hum: float = sin(time * 4.70 + 0.55) * hum
	driver._add_rotation("leftShoulder", Vector3(-left_hum * 0.35 - nod_cycle * 0.18, 0.0, -left_hum * 0.55))
	driver._add_rotation("rightShoulder", Vector3(-right_hum * 0.35 - nod_cycle * 0.18, 0.0, right_hum * 0.55))
	ankle_targets.clear()
	for side in range(2):
		var leg: Dictionary = driver.gait.legs[side]
		var start: Vector3 = skel.get_bone_global_pose(int(leg["upper"])).origin
		var a: float = float(leg["a"])
		var b: float = float(leg["b"])
		var kick: float = (0.10 + sin(time * 1.3 + float(side) * 0.8) * 0.055) if motion else 0.10
		kick += sin(time * 2.6 + float(side) * PI) * 0.28 * swing
		# Sway carries a relaxed, slower counter-swing through the dangling legs.
		# It stays well below the dedicated playful "swing" gesture.
		kick += sin(time * 1.55 + float(side) * PI) * 0.150 * sway
		kick += sin(time * 2.35 + float(side) * 0.65) * 0.006 * hum
		var endpoint: Vector3 = start + Vector3(0.0, -a * 0.045 - b * cos(kick), a * 0.999 + b * sin(kick))
		var target: Vector3 = (leg["rest_ankle"] as Vector3).lerp(endpoint, p)
		ankle_targets.append(target)
		var chain: Dictionary = {"upper": leg["upper"], "lower": leg["lower"], "end": leg["foot"], "a": a, "b": b}
		driver._solve(chain, target, Vector3(0.0, 0.05, 1.0), leg["foot_q"])
	for side in range(2):
		var arm: Dictionary = driver.arms[side]
		var sign_x: float = 1.0 if side == 0 else -1.0
		var knee: Vector3 = skel.get_bone_global_pose(int(driver.gait.legs[side]["lower"])).origin
		var thigh: Vector3 = skel.get_bone_global_pose(int(driver.gait.legs[side]["upper"])).origin
		var wrist: Vector3 = thigh.lerp(knee, 0.70) + Vector3(sign_x * h * 0.018, h * 0.038, 0.0)
		var support_hand: Vector3 = hip + Vector3(sign_x * h * 0.12, -h * 0.040, -h * 0.07)
		wrist = wrist.lerp(support_hand, lean)
		var bracing: bool = scoot > 0.001 and side == (1 if scoot_direction > 0.0 else 0)
		if bracing:
			var brace_hand: Vector3 = seat_point + Vector3(sign_x * h * 0.17, h * 0.012, -h * 0.05)
			wrist = wrist.lerp(brace_hand, scoot)
		if sketch > 0.001:
			var drawing_hand: Vector3 = hip + Vector3(sign_x * h * 0.09, h * (-0.065 + sketch_show * 0.18), h * (0.27 - sketch_show * 0.07))
			if side == 1 and sketch_show < 0.5:
				drawing_hand += Vector3(sin(time * 8.2) * h * 0.012, cos(time * 6.5) * h * 0.006, h * 0.012)
			wrist = wrist.lerp(drawing_hand, sketch)
		var saved: Array[Quaternion] = []
		for key in ["upper", "lower", "end"]:
			saved.append(skel.get_bone_pose_rotation(int(arm[key])))
		var hand_q: Quaternion = Quaternion(Vector3.UP, -sign_x * PI * 0.5) * arm["end_q"]
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
		var weight: float = p * (1.0 - clampf(wave, 0.0, 1.0) if side == 1 else 1.0)
		var keys: Array = ["upper", "lower", "end"]
		for index in range(3):
			var bone: int = int(arm[keys[index]])
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
