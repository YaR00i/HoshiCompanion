@tool
extends Node
## Authoring targets for Godot's built-in AnimationPlayer timeline.
## Positions are relative to the seated hips, in fractions of avatar height.

@export_range(-25.0, 25.0, 0.1) var head_pitch: float = 11.0
@export_range(-15.0, 15.0, 0.1) var chest_pitch: float = 0.0
