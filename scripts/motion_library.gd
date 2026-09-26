extends RefCounted
## Библиотека движений Хоши — полный список того, как она умеет двигаться.
##
## Три слоя скелета (см. docs/SKELETON_RU.md):
##   команды (hoshi_commands.gd)  — ЧТО сделать: «помахать», «покачаться»;
##   исполнитель (command_runner.gd) — КОГДА можно и КАК запустить;
##   эта библиотека               — ЧЕМ двигается тело.
## Команда ссылается на движение по его id (поле animation в списке команд).
## Одно движение может использоваться разными командами, и наоборот.
##
## Поля записи:
##   title   — подпись по-русски;
##   kind    — "clip": ключевая анимация Godot, файл в res://animations/,
##                     правится в scenes/animation_authoring_3d.tscn;
##             "code": движение пока описано формулами в скрипте. Такие
##                     движения — кандидаты на перевод в клипы, чтобы их
##                     тоже можно было править руками;
##   posture — в какой позе оно возможно: seated / standing / any;
##   player  — какой скрипт его проигрывает и владеет костями (только он!);
##   gesture — имя, по которому player запускает движение;
##   path    — для kind == "clip": файл клипа.
##
## Как добавить новый клип сидячей сценки: docs/ANIMATION_WORKSHOP_RU.md,
## затем запись сюда и, если нужна кнопка/автономия, команда в hoshi_commands.gd.
## tests/test_commands.gd проверяет, что всё сходится.

const SeatedMotion = preload("res://scripts/seated_motion.gd")
const SketchMotion = preload("res://scripts/sketch_motion.gd")

const LIBRARY := {
	# --- Ключевые клипы Godot: сидя на краю/в уголке (играет edge_life.gd) ---
	"seated_swing": {"title": "Болтает ножками", "kind": "clip", "posture": "seated", "player": "edge_life", "gesture": "swing", "path": "res://animations/swing.tres"},
	"seated_lean": {"title": "Откидывается на ладони", "kind": "clip", "posture": "seated", "player": "edge_life", "gesture": "lean", "path": "res://animations/lean.tres"},
	"seated_peek": {"title": "Смотрит вниз", "kind": "clip", "posture": "seated", "player": "edge_life", "gesture": "peek", "path": "res://animations/peek.tres"},
	"seated_balance": {"title": "Балансирует", "kind": "clip", "posture": "seated", "player": "edge_life", "gesture": "balance", "path": "res://animations/balance.tres"},
	"seated_sway": {"title": "Мягко покачивается", "kind": "clip", "posture": "seated", "player": "edge_life", "gesture": "sway", "path": "res://animations/sway.tres"},
	"seated_hum": {"title": "Тихонько напевает", "kind": "clip", "posture": "seated", "player": "edge_life", "gesture": "hum", "path": "res://animations/hum.tres"},
	"seated_nod": {"title": "Кивает в такт", "kind": "clip", "posture": "seated", "player": "edge_life", "gesture": "nod", "path": "res://animations/nod.tres"},
	"seated_sketch": {"title": "Рисует в блокноте", "kind": "clip", "posture": "seated", "player": "edge_life", "gesture": "sketch", "path": "res://animations/sketch.tres"},
	"seated_fold": {"title": "Складывает бумажную звезду", "kind": "clip", "posture": "seated", "player": "edge_life", "gesture": "fold", "path": "res://animations/fold.tres"},
	"seated_admire_star": {"title": "Показывает звёздочку", "kind": "clip", "posture": "seated", "player": "edge_life", "gesture": "admire_star", "path": "res://animations/admire_star.tres"},
	# --- Стоя: короткие жесты (пока формулами в idle_life.gd) ---
	"stand_peek_left": {"title": "Заглядывает влево", "kind": "code", "posture": "standing", "player": "idle_life", "gesture": "peek_left"},
	"stand_peek_right": {"title": "Заглядывает вправо", "kind": "code", "posture": "standing", "player": "idle_life", "gesture": "peek_right"},
	"stand_weight_left": {"title": "Переносит вес влево", "kind": "code", "posture": "standing", "player": "idle_life", "gesture": "weight_left"},
	"stand_weight_right": {"title": "Переносит вес вправо", "kind": "code", "posture": "standing", "player": "idle_life", "gesture": "weight_right"},
	"stand_hands": {"title": "Возится с руками", "kind": "code", "posture": "standing", "player": "idle_life", "gesture": "hands"},
	"stand_shoulders": {"title": "Разминает плечи", "kind": "code", "posture": "standing", "player": "idle_life", "gesture": "shoulders"},
	# --- Реакции верхней части тела (формулы в rig_driver.gd по весам состояния) ---
	"wave": {"title": "Машет рукой", "kind": "code", "posture": "any", "player": "rig_driver", "gesture": "wave"},
	"pet_react": {"title": "Подставляет голову под ладонь", "kind": "code", "posture": "any", "player": "rig_driver", "gesture": "pet"},
	"doze": {"title": "Дремлет", "kind": "code", "posture": "any", "player": "rig_driver", "gesture": "sleepy"},
	# --- Перемещение и позы (процедурные системы: IK ног, переходы, прыжки) ---
	"walk_cycle": {"title": "Шагает", "kind": "code", "posture": "standing", "player": "gait_driver", "gesture": "walk"},
	"sit_down": {"title": "Садится / встаёт", "kind": "code", "posture": "any", "player": "posture_driver", "gesture": "sit"},
	"edge_seat": {"title": "Сидит на краю, ноги свешены", "kind": "code", "posture": "seated", "player": "edge_pose", "gesture": "seat"},
	"carry": {"title": "Висит, когда несут мышкой", "kind": "code", "posture": "any", "player": "context_pose", "gesture": "carry"},
	"cursor_hang": {"title": "Держится за курсор", "kind": "code", "posture": "any", "player": "context_pose", "gesture": "cursor_hang"},
	"jump": {"title": "Прыжок на опору", "kind": "code", "posture": "any", "player": "context_pose", "gesture": "jump"},
	"fall_land": {"title": "Падение и приземление", "kind": "code", "posture": "any", "player": "context_pose", "gesture": "fall"},
	"portal": {"title": "Выход и уход через звёздную дверь", "kind": "code", "posture": "standing", "player": "context_pose", "gesture": "portal"},
	"side_lean": {"title": "Прислоняется к боку окна", "kind": "code", "posture": "standing", "player": "context_pose", "gesture": "side"},
}

static func has(id: String) -> bool:
	return LIBRARY.has(id)

static func ids() -> Array[String]:
	var result: Array[String] = []
	for id in LIBRARY:
		result.append(str(id))
	return result

static func entry(id: String) -> Dictionary:
	return LIBRARY.get(id, {})

static func is_clip(id: String) -> bool:
	return str(entry(id).get("kind", "")) == "clip"

static func path(id: String) -> String:
	return str(entry(id).get("path", ""))

static func gesture(id: String) -> String:
	return str(entry(id).get("gesture", ""))

static func player(id: String) -> String:
	return str(entry(id).get("player", ""))

## Движения, которые сейчас можно править руками в Godot.
static func editable_clips() -> Array[String]:
	var result: Array[String] = []
	for id in LIBRARY:
		if is_clip(str(id)):
			result.append(str(id))
	return result

## Путь, по которому движок реально загружает клип (для проверки согласованности).
static func loader_path(id: String) -> String:
	var name: String = gesture(id)
	if name == "sketch":
		return SketchMotion.CLIP_PATH
	return SeatedMotion.path_for(name)

## id движения по имени жеста у конкретного проигрывателя.
static func find(player_name: String, gesture_name: String) -> String:
	for id in LIBRARY:
		if player(str(id)) == player_name and gesture(str(id)) == gesture_name:
			return str(id)
	return ""
