@tool
extends Resource
## How Hoshi walks: every number the walk workshop exposes as a slider. Saved to
## res://animations/walk_style.tres; locomotion, gait IK and the upper-body rig read
## the shared active instance, so a saved style is what the live companion uses.
## Angles are in degrees; lengths are shares of her height.

const PATH: String = "res://animations/walk_style.tres"
const SCRIPT_PATH: String = "res://scripts/walk_style.gd"

@export_group("Шаг и стопы")
## Stride length (share of height). Longer strides need more knee bend.
@export_range(0.10, 0.34, 0.005) var step_length: float = 0.17
## Walking speed (share of height per second). With the stride it sets the cadence.
@export_range(0.15, 0.50, 0.005) var speed: float = 0.23
## How high the foot rises while it passes under the body (share of height): this is
## what bends the knee in the swing. Low = the leg swings forward almost straight.
@export_range(0.005, 0.15, 0.001) var foot_lift: float = 0.038
## Heel rises before the step: rolling over the ball of the foot.
@export_range(0.0, 45.0, 0.5) var push_off: float = 22.0
## Toes up just before the heel touches down.
@export_range(0.0, 25.0, 0.5) var heel_strike: float = 12.0
## Leg thrown forward: the straightened leg reaches past its landing spot in the air
## (share of height; 0.06 is a full playful kick) earlier in the swing, then the heel
## comes down and back onto the spot. 0 = ordinary reach.
@export_range(0.0, 0.10, 0.002) var leg_kick: float = 0.0
## How high the foot is at that forward reach (share of height, with a full kick).
@export_range(0.0, 0.30, 0.002) var kick_height: float = 0.025
## The back leg stays behind on its toes before it swings (share of the step).
@export_range(0.0, 0.35, 0.01) var back_hold: float = 0.0
## How early the back leg starts letting the pelvis rise before its toes leave the floor
## (share of the step). More = smoother pelvis, but the toes leave the floor earlier.
@export_range(0.08, 0.35, 0.01) var rear_release: float = 0.18
## Up-down spring of the whole body on each step (share of height).
@export_range(0.0, 0.06, 0.001) var bounce: float = 0.016

## 0 = the body springs evenly; 1 = it drops quickly with the landing foot ("опа")
## and rises slowly while passing over it.
@export_range(0.0, 1.0, 0.05) var drop_snap: float = 0.0

@export_group("Таз и корпус")
## Pelvis turns with the swinging leg (around the vertical axis).
@export_range(0.0, 25.0, 0.1) var hip_turn: float = 4.5
## Pelvis drops on the swinging side.
@export_range(0.0, 15.0, 0.1) var hip_tilt: float = 3.0
## Whole back leans forward (+) or back (−, proud upright walk).
@export_range(-15.0, 20.0, 0.1) var torso_lean: float = 1.4
## Chest lifts (−) or curls forward (+).
@export_range(-15.0, 15.0, 0.1) var chest_pitch: float = 2.2
## Torso leans forward while the leg is thrown forward (degrees at the reach).
@export_range(0.0, 20.0, 0.1) var kick_lean: float = 0.0
## Torso gives a little forward on each footfall.
@export_range(0.0, 12.0, 0.1) var footfall_dip: float = 1.2
## Torso leans over the standing leg.
@export_range(0.0, 15.0, 0.1) var side_lean: float = 2.3
## Shoulders turn against the hips.
@export_range(0.0, 25.0, 0.1) var shoulder_turn: float = 2.4

@export_group("Голова")
## Head tilts side to side with the steps.
@export_range(0.0, 15.0, 0.1) var head_tilt: float = 3.5
## Small nod after each footfall.
@export_range(0.0, 12.0, 0.1) var head_nod: float = 2.4
## How late the head follows the body (radians of the step cycle).
@export_range(0.0, 1.5, 0.05) var head_lag: float = 0.7

@export_group("Руки")
## Arm swing forward.
@export_range(0.0, 60.0, 0.5) var arm_forward: float = 17.0
## Arm swing back.
@export_range(0.0, 60.0, 0.5) var arm_back: float = 13.0
## Arms held away from the body.
@export_range(0.0, 80.0, 0.5) var arm_open: float = 5.5
## Extra elbow bend on the forward swing.
@export_range(0.0, 70.0, 0.5) var elbow_bend: float = 12.0
## How late the arms follow the legs (radians of the step cycle).
@export_range(0.0, 1.2, 0.05) var arm_lag: float = 0.35
## Loose hands trailing the swing.
@export_range(0.0, 45.0, 0.5) var hand_flop: float = 11.0

static var _active: Resource

## The style everyone reads. Loaded once from PATH; defaults when the file is missing.
static func active() -> Resource:
	if _active == null:
		if ResourceLoader.exists(PATH):
			_active = load(PATH)
		if _active == null:
			_active = load(SCRIPT_PATH).new()
	return _active

static func set_active(style: Resource) -> void:
	_active = style

static func defaults() -> Resource:
	return load(SCRIPT_PATH).new()

func save_to_project() -> Error:
	return ResourceSaver.save(self, PATH)

## Property names of every tunable number, in inspector order.
static func tunables() -> PackedStringArray:
	var names := PackedStringArray()
	for info in defaults().get_property_list():
		if int(info["usage"]) & PROPERTY_USAGE_EDITOR and int(info["type"]) == TYPE_FLOAT:
			names.append(str(info["name"]))
	return names
