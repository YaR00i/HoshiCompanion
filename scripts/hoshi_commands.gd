extends RefCounted
## Единый список команд Хоши.
##
## Каждая кнопка меню, горячая клавиша и тест обращаются к действию по ИМЕНИ
## из этого списка ("wave", "walk", "cozy_corner"), а не по номеру.
## Позже сюда же будут обращаться телефон, голос и AI: им не придётся знать,
## где нарисована кнопка.
##
## Поля записи:
##   title    — подпись по-русски (для меню, пульта, подсказок);
##   group    — раздел: life / mood / move / place / surface / seated / scene /
##              autonomy / look / tools / talk / diagnostics / app;
##   menu_id  — внутренний номер пункта PopupMenu в Godot. Нужен только самому
##              меню; всем остальным он не нужен. Номера совпадают со старыми,
##              поэтому поведение меню не изменилось;
##   flags    — особые правила, которые раньше были списками номеров в
##              companion.gd:
##                pauses_places — ручное действие ставит автономный выбор
##                                места на паузу;
##                keeps_intent  — не сбрасывает очередь посадки/сна;
##                keeps_walk    — не останавливает текущую прогулку;
##   animation — имя клипа из res://animations/, если команда использует
##               анимацию, которую правят в Godot (сцена
##               scenes/animation_authoring_3d.tscn). Клипы сидячих сценок
##               зарегистрированы в seated_motion.gd, "sketch" — в
##               sketch_motion.gd. Проверка tests/test_commands.gd следит, чтобы
##               каждая ссылка вела на существующий клип.
##
## Как добавить новую команду:
##   1. добавить запись сюда (уникальное имя, свободный menu_id);
##   2. выполнить её в companion.gd::_on_action (match по имени);
##   3. если нужна кнопка — передать имя в меню (companion_ui.gd /
##      hoshi_quick_menu.gd);
##   4. если нужна новая анимация — сначала клип в animations/ и его регистрация
##      (см. docs/ANIMATION_WORKSHOP_RU.md), затем поле animation здесь.

const SeatedMotion = preload("res://scripts/seated_motion.gd")
const SketchMotion = preload("res://scripts/sketch_motion.gd")

const LIST := {
	# Общение
	"wave": {"title": "Помахать", "group": "life", "menu_id": 10, "flags": ["pauses_places"]},
	"pet": {"title": "Погладить", "group": "life", "menu_id": 11, "flags": ["pauses_places"]},
	"doze": {"title": "Подремать / разбудить", "group": "life", "menu_id": 12, "flags": ["pauses_places", "keeps_intent"]},
	# Настроение
	"mood_neutral": {"title": "Спокойная", "group": "mood", "menu_id": 20},
	"mood_happy": {"title": "Радостная", "group": "mood", "menu_id": 21},
	"mood_relaxed": {"title": "Расслабленная", "group": "mood", "menu_id": 22},
	"mood_surprised": {"title": "Удивлённая", "group": "mood", "menu_id": 23},
	"mood_sad": {"title": "Грустная", "group": "mood", "menu_id": 24},
	# Движение по полу
	"walk": {"title": "Пройтись", "group": "move", "menu_id": 30, "flags": ["pauses_places", "keeps_intent", "keeps_walk"]},
	"stop": {"title": "Остановиться", "group": "move", "menu_id": 31, "flags": ["pauses_places", "keeps_walk"]},
	"sit": {"title": "Сесть отдохнуть", "group": "move", "menu_id": 32, "flags": ["pauses_places", "keeps_intent"]},
	"stand": {"title": "Встать", "group": "move", "menu_id": 33, "flags": ["pauses_places"]},
	# Места: полочка, окна, уголок
	"shelf_demo": {"title": "Полочка — попробовать", "group": "place", "menu_id": 40, "flags": ["pauses_places"]},
	"return_floor": {"title": "Вернуться на пол", "group": "place", "menu_id": 41, "flags": ["pauses_places"]},
	"pick_window": {"title": "Выбрать окно под курсором · 4 с", "group": "place", "menu_id": 42, "flags": ["pauses_places"]},
	"cozy_corner": {"title": "Мой уютный уголок", "group": "place", "menu_id": 43, "flags": ["pauses_places"]},
	# Окно Хоши и вид
	"open_preview": {"title": "Открыть примерочную", "group": "tools", "menu_id": 100, "flags": ["pauses_places"]},
	"to_desktop": {"title": "На рабочий стол", "group": "tools", "menu_id": 101, "flags": ["pauses_places"]},
	"size_small": {"title": "Небольшая · 280 px", "group": "tools", "menu_id": 110, "flags": ["pauses_places"]},
	"size_normal": {"title": "Обычная · 360 px", "group": "tools", "menu_id": 111, "flags": ["pauses_places"]},
	"size_large": {"title": "Крупная · 440 px", "group": "tools", "menu_id": 112, "flags": ["pauses_places"]},
	"return_bottom": {"title": "Вернуть к нижнему краю", "group": "tools", "menu_id": 140, "flags": ["pauses_places"]},
	"reset_view": {"title": "Вернуть вид спереди", "group": "tools", "menu_id": 141, "flags": ["pauses_places"]},
	"fps_60": {"title": "60 FPS · плавнее", "group": "tools", "menu_id": 130},
	"fps_30": {"title": "30 FPS · экономно", "group": "tools", "menu_id": 131},
	"light_editor": {"title": "Настроить свет, тени и обводку…", "group": "tools", "menu_id": 150},
	"light_reset": {"title": "Сбросить настройки света", "group": "tools", "menu_id": 151},
	"quit": {"title": "Закрыть Хоши", "group": "app", "menu_id": 199},
	# Переключатели
	"toggle_look": {"title": "Внимание к курсору", "group": "look", "menu_id": 120},
	"toggle_motion": {"title": "Мягкие движения", "group": "look", "menu_id": 121},
	"toggle_hair": {"title": "Движение волос", "group": "look", "menu_id": 122},
	"toggle_bubbles": {"title": "Короткие реплики", "group": "look", "menu_id": 123},
	"toggle_clickthrough": {"title": "Клики только по Хоши", "group": "tools", "menu_id": 124},
	"toggle_auto_walk": {"title": "Самостоятельные прогулки", "group": "autonomy", "menu_id": 125},
	"toggle_autonomy": {"title": "Самостоятельность", "group": "autonomy", "menu_id": 126},
	"toggle_auto_rest": {"title": "Самостоятельный отдых", "group": "autonomy", "menu_id": 127},
	# Проверка краёв окна
	"scan_window_structure": {"title": "Структура окна · без снимка", "group": "diagnostics", "menu_id": 160},
	"scan_window_visual": {"title": "Видимые края окна · 1 кадр", "group": "diagnostics", "menu_id": 161},
	# Разговор
	"talk_voice": {"title": "Поговорить через ChatGPT", "group": "talk", "menu_id": 170},
	"talk_text": {"title": "Открыть текстовый чат", "group": "talk", "menu_id": 171},
	# Ритм и места отдыха
	"activity_quiet": {"title": "Тихая · без прогулок", "group": "autonomy", "menu_id": 200},
	"activity_normal": {"title": "Обычная", "group": "autonomy", "menu_id": 201},
	"activity_playful": {"title": "Игривая", "group": "autonomy", "menu_id": 202},
	"place_manual": {"title": "Только вручную", "group": "autonomy", "menu_id": 210},
	"place_cozy": {"title": "Свой уголок", "group": "autonomy", "menu_id": 211},
	"place_smart": {"title": "Окна → уголок", "group": "autonomy", "menu_id": 212},
	# Занятие сидя на краю (выбор предпочтения; клип играет edge_life.gd)
	"edge_auto": {"title": "Сама выбирает", "group": "seated", "menu_id": 300, "edge_activity": "auto"},
	"edge_calm": {"title": "Спокойно", "group": "seated", "menu_id": 301, "edge_activity": "calm"},
	"edge_swing": {"title": "Болтать ножками", "group": "seated", "menu_id": 302, "edge_activity": "swing", "animation": "swing"},
	"edge_lean": {"title": "Откинуться назад", "group": "seated", "menu_id": 303, "edge_activity": "lean", "animation": "lean"},
	"edge_peek": {"title": "Посмотреть вниз", "group": "seated", "menu_id": 304, "edge_activity": "peek", "animation": "peek"},
	"edge_sway": {"title": "Мягко покачиваться", "group": "seated", "menu_id": 309, "edge_activity": "sway", "animation": "sway"},
	"edge_hum": {"title": "Тихонько напевать", "group": "seated", "menu_id": 310, "edge_activity": "hum", "animation": "hum"},
	"edge_nod": {"title": "Кивать в такт", "group": "seated", "menu_id": 311, "edge_activity": "nod", "animation": "nod"},
	# На поверхности окна
	"surface_walk": {"title": "Пройтись по краю", "group": "surface", "menu_id": 305, "flags": ["pauses_places"]},
	"surface_lean_left": {"title": "Опора у левого края", "group": "surface", "menu_id": 306, "flags": ["pauses_places"]},
	"surface_lean_right": {"title": "Опора у правого края", "group": "surface", "menu_id": 307, "flags": ["pauses_places"]},
	"surface_sit_back": {"title": "Сесть обратно", "group": "surface", "menu_id": 308, "flags": ["pauses_places"]},
	"surface_scoot": {"title": "Подвинуться сидя", "group": "surface", "menu_id": 313, "flags": ["pauses_places"]},
	# Особые сценки уютного уголка
	"cozy_sketch": {"title": "Рисовать в блокноте", "group": "scene", "menu_id": 312, "animation": "sketch"},
	"cozy_fold_star": {"title": "Сложить звёздочку", "group": "scene", "menu_id": 314, "flags": ["pauses_places"], "animation": "fold"},
	"cozy_admire_star": {"title": "Полюбоваться звёздочкой", "group": "scene", "menu_id": 315, "flags": ["pauses_places"], "animation": "admire_star"},
}

## Группы вариантов для выпадающих списков: порядок = порядок пунктов.
const ACTIVITY_CHOICES: Array[String] = ["activity_quiet", "activity_normal", "activity_playful"]
const PLACE_CHOICES: Array[String] = ["place_manual", "place_cozy", "place_smart"]
const EDGE_CHOICES: Array[String] = ["edge_auto", "edge_calm", "edge_swing", "edge_lean", "edge_peek", "edge_sway", "edge_hum", "edge_nod"]

static func has(command: String) -> bool:
	return LIST.has(command)

static func names() -> Array[String]:
	var result: Array[String] = []
	for command in LIST:
		result.append(str(command))
	return result

static func title(command: String) -> String:
	return str(LIST.get(command, {}).get("title", command))

static func group(command: String) -> String:
	return str(LIST.get(command, {}).get("group", ""))

static func menu_id(command: String) -> int:
	return int(LIST.get(command, {}).get("menu_id", -1))

static func from_menu_id(id: int) -> String:
	for command in LIST:
		if int(LIST[command]["menu_id"]) == id:
			return str(command)
	return ""

static func has_flag(command: String, flag: String) -> bool:
	return flag in LIST.get(command, {}).get("flags", [])

static func edge_activity(command: String) -> String:
	return str(LIST.get(command, {}).get("edge_activity", ""))

static func animation(command: String) -> String:
	return str(LIST.get(command, {}).get("animation", ""))

## Путь к файлу клипа, который можно открыть и поправить в Godot.
static func animation_path(command: String) -> String:
	var clip: String = animation(command)
	if clip.is_empty():
		return ""
	if clip == "sketch":
		return SketchMotion.CLIP_PATH
	return SeatedMotion.path_for(clip)

## Команды, которые используют указанный клип (для подсказки «что сломается,
## если переименовать анимацию»).
static func commands_for_animation(clip: String) -> Array[String]:
	var result: Array[String] = []
	for command in LIST:
		if animation(str(command)) == clip:
			result.append(str(command))
	return result

## Привести старый номер или имя к имени команды. Пустая строка — неизвестно.
static func resolve(command: Variant) -> String:
	if command is int:
		return from_menu_id(int(command))
	var text: String = str(command)
	return text if LIST.has(text) else ""
