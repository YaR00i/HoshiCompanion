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
	var h: float = driver.height_m
	var skel: Skeleton3D = driver.skeleton
	var hip: Vector3 = driver.hips_rest
	hip.y = lerpf(hip.y, driver.ground_y + h * 0.42, p)
	hip.z -= h * 0.06 * p
	driver._set_position_global(driver.gait.hips_id, hip)
	driver._add_rotation("spine", Vector3(3.0 * p - lean * 19.0, 0.0, 0.0))
	driver._add_rotation("chest", Vector3(-lean * 10.0, 0.0, 0.0))
	driver._add_rotation("head", Vector3(peek * 14.0 + lean * 9.0, peek * 3.0, 0.0))
	seat_point = hip - Vector3(0.0, h * seat_offset_ratio, 0.0)
	ankle_targets.clear()
	for side in range(2):
		var leg: Dictionary = driver.gait.legs[side]
		var start: Vector3 = skel.get_bone_global_pose(int(leg["upper"])).origin
		var a: float = float(leg["a"])
		var b: float = float(leg["b"])
		var kick: float = (0.10 + sin(time * 1.3 + float(side) * 0.8) * 0.055) if motion else 0.10
		kick += sin(time * 2.6 + float(side) * PI) * 0.28 * swing
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
		var saved: Array[Quaternion] = []
		for key in ["upper", "lower", "end"]:
			saved.append(skel.get_bone_pose_rotation(int(arm[key])))
		var hand_q: Quaternion = Quaternion(Vector3.UP, -sign_x * PI * 0.5) * arm["end_q"]
		driver._solve(arm, wrist, Vector3(sign_x * 0.4, -1.0, -0.12), hand_q)
		var weight: float = p * (1.0 - clampf(wave, 0.0, 1.0) if side == 1 else 1.0)
		var keys: Array = ["upper", "lower", "end"]
		for index in range(3):
			var bone: int = int(arm[keys[index]])
			skel.set_bone_pose_rotation(bone, saved[index].slerp(skel.get_bone_pose_rotation(bone), weight).normalized())

func anchor_world() -> Vector3:
	return driver.skeleton.global_transform * seat_point
