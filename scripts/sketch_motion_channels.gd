@tool
extends Node
## Authoring targets for Godot's built-in AnimationPlayer timeline.
## Positions are relative to the seated hips, in fractions of avatar height.

@export_range(-25.0, 25.0, 0.1) var head_pitch: float = 11.0
@export_range(-15.0, 15.0, 0.1) var chest_pitch: float = 0.0

@export_group("Касания (touch_*)")
## Поворот всего тела, градусы: «отвернулась спиной», «кружится на ножке».
@export_range(-360.0, 360.0, 0.5) var touch_yaw: float = 0.0
## Сдвиг таза в долях роста: x — вбок (к левой ноге +), y — вверх, z — вперёд.
@export var hips_offset: Vector3 = Vector3.ZERO
## Улыбка (0…1).
@export_range(0.0, 1.0, 0.01) var face_happy: float = 0.0
## Надутые губки, «ай-яй-яй» (0…1).
@export_range(0.0, 1.0, 0.01) var face_angry: float = 0.0
## Открытый рот — зевок (0…1).
@export_range(0.0, 1.0, 0.01) var face_aa: float = 0.0
## Закрытые глазки (0…1).
@export_range(0.0, 1.0, 0.01) var face_blink: float = 0.0
## Удивление — «ой!» (0…1).
@export_range(0.0, 1.0, 0.01) var face_surprised: float = 0.0
