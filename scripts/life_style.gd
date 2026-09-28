@tool
extends Resource
## Живые мелочи Хоши: сила поглаживания, переноса веса и опоры у края.
## Как walk_style.gd: сохранено в res://animations/life_style.tres — открой его в
## Godot («Инструменты и окно → Редакторы → Весь проект в редакторе Godot»,
## файл animations/life_style.tres) и двигай ползунки в инспекторе; после
## сохранения — «Перезапустить Хоши». Углы — в градусах.

const PATH: String = "res://animations/life_style.tres"
const SCRIPT_PATH: String = "res://scripts/life_style.gd"

@export_group("Поглаживание")
## Насколько голова и шея подаются к руке (1 — как было до 28.09).
@export_range(0.0, 3.0, 0.05) var pet_head: float = 1.6
## Наклон корпуса к руке (поясница и грудь), градусы.
@export_range(0.0, 12.0, 0.1) var pet_body: float = 4.0
## Мягкое покачивание корпусом, пока гладишь («ласкается»), градусы.
@export_range(0.0, 8.0, 0.1) var pet_sway: float = 2.2
## Скорость этого покачивания (раз в секунду ≈ значение / 6,3).
@export_range(0.5, 6.0, 0.1) var pet_sway_speed: float = 2.4

@export_group("Перенос веса")
## Насколько таз уходит на опорную ногу (доля длины ноги).
@export_range(0.0, 0.08, 0.001) var weight_hip_shift: float = 0.035
## Бедро опорной ноги чуть выше, градусы.
@export_range(0.0, 8.0, 0.1) var weight_hip_roll: float = 3.0
## Колено свободной ноги сгибается, градусы.
@export_range(0.0, 20.0, 0.5) var weight_knee: float = 8.0
## Плечи в ответ наклоняются в другую сторону, градусы.
@export_range(0.0, 6.0, 0.1) var weight_shoulders: float = 2.0

@export_group("Касания")
## Сила реакций на касание (ножка, ручка, животик, грудь): 1 — как задумано.
@export_range(0.0, 2.0, 0.05) var touch_strength: float = 1.0

@export_group("Опора у края")
## Наклон корпуса к краю окна, градусы.
@export_range(0.0, 15.0, 0.1) var lean_body: float = 6.0

static var _active: Resource

static func active() -> Resource:
	if _active == null:
		if ResourceLoader.exists(PATH):
			_active = load(PATH)
		if _active == null:
			_active = load(SCRIPT_PATH).new()
	return _active

static func set_active(style: Resource) -> void:
	_active = style
