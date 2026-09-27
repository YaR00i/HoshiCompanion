extends RefCounted
## Единый список команд Хоши — ЧТО она умеет делать.
##
## Скелет из трёх слоёв (подробно: docs/SKELETON_RU.md):
##   1. команды (этот файл)           — что сделать: "wave", "edge_sway";
##   2. исполнитель (command_runner.gd) — можно ли сейчас и как запустить;
##   3. библиотека движений (motion_library.gd) — чем двигается тело.
##
## Кнопка меню, горячая клавиша, сама Хоши (IntentPlanner), а позже телефон,
## голос и AI обращаются к действию по одному и тому же ИМЕНИ. Шаг плана
## автономии, которого нет в этом списке, выполнен не будет.
##
## Поля записи:
##   title     — подпись по-русски (для меню, пульта, подсказок);
##   group     — раздел (life, move, gesture, place, surface, seated, scene,
##               pause, seated_mode, tools, look, autonomy, talk, ...);
##   sources   — кто может отдать команду: "user" (человек: меню, клавиши),
##               "remote" (пульт с телефона, только вместе с "user") и/или
##               "auto" (сама Хоши);
##   menu_id   — внутренний номер пункта PopupMenu (-1 — в меню нет). Нужен
##               только самому меню; номера совпадают со старыми;
##   flags     — особые правила ручных команд:
##                 pauses_places — ставит автономный выбор места на паузу;
##                 keeps_intent  — не сбрасывает очередь посадки/сна;
##                 keeps_walk    — не останавливает текущую прогулку;
##                 confirm       — пульт спрашивает «Точно?» перед нажатием;
##   animation — id движения из motion_library.gd. Если это клип
##               ("kind": "clip"), его можно править в Godot:
##               scenes/animation_authoring_3d.tscn.
##
## Как добавить новую команду:
##   1. запись сюда (уникальное имя, sources, при необходимости menu_id);
##   2. как её запускать и когда она закончена — в command_runner.gd;
##      простые настройки меню остаются в companion.gd::_on_action;
##   3. кнопка — передать имя в меню (companion_ui.gd / hoshi_quick_menu.gd);
##   4. новое движение — сначала в motion_library.gd (для клипа: файл в
##      animations/, см. docs/ANIMATION_WORKSHOP_RU.md), затем поле animation.
## tests/test_commands.gd проверяет, что все три слоя сходятся.

const MotionLibrary = preload("res://scripts/motion_library.gd")

const LIST := {
	# Общение
	"wave": {"title": "Помахать", "group": "life", "menu_id": 10, "flags": ["pauses_places"], "sources": ["user", "auto", "remote"], "animation": "wave"},
	"pet": {"title": "Погладить", "group": "life", "menu_id": 11, "flags": ["pauses_places"], "sources": ["user", "remote"], "animation": "pet_react"},
	"doze": {"title": "Подремать / разбудить", "group": "life", "menu_id": 12, "flags": ["pauses_places", "keeps_intent"], "sources": ["user", "remote"], "animation": "doze"},
	"look": {"title": "Осмотреться", "group": "life", "menu_id": -1, "sources": ["auto"]},
	# Настроение
	"mood_neutral": {"title": "Спокойная", "group": "mood", "menu_id": 20, "sources": ["user", "remote"]},
	"mood_happy": {"title": "Радостная", "group": "mood", "menu_id": 21, "sources": ["user", "remote"]},
	"mood_relaxed": {"title": "Расслабленная", "group": "mood", "menu_id": 22, "sources": ["user", "remote"]},
	"mood_surprised": {"title": "Удивлённая", "group": "mood", "menu_id": 23, "sources": ["user", "remote"]},
	"mood_sad": {"title": "Грустная", "group": "mood", "menu_id": 24, "sources": ["user", "remote"]},
	# Движение по полу
	"walk": {"title": "Пройтись", "group": "move", "menu_id": 30, "flags": ["pauses_places", "keeps_intent", "keeps_walk"], "sources": ["user", "auto", "remote"], "animation": "walk_cycle"},
	"stop": {"title": "Остановиться", "group": "move", "menu_id": 31, "flags": ["pauses_places", "keeps_walk"], "sources": ["user", "remote"]},
	"sit": {"title": "Сесть отдохнуть", "group": "move", "menu_id": 32, "flags": ["pauses_places", "keeps_intent"], "sources": ["user", "auto", "remote"], "animation": "sit_down"},
	"stand": {"title": "Встать", "group": "move", "menu_id": 33, "flags": ["pauses_places"], "sources": ["user", "remote"], "animation": "sit_down"},
	# Короткие жесты стоя (пока только сама)
	"floor_peek_left": {"title": "Заглянуть влево", "group": "gesture", "menu_id": -1, "sources": ["auto"], "animation": "stand_peek_left"},
	"floor_peek_right": {"title": "Заглянуть вправо", "group": "gesture", "menu_id": -1, "sources": ["auto"], "animation": "stand_peek_right"},
	"floor_weight_left": {"title": "Перенести вес влево", "group": "gesture", "menu_id": -1, "sources": ["auto"], "animation": "stand_weight_left"},
	"floor_weight_right": {"title": "Перенести вес вправо", "group": "gesture", "menu_id": -1, "sources": ["auto"], "animation": "stand_weight_right"},
	"floor_hands": {"title": "Повозиться с руками", "group": "gesture", "menu_id": -1, "sources": ["auto"], "animation": "stand_hands"},
	"floor_shoulders": {"title": "Размять плечи", "group": "gesture", "menu_id": -1, "sources": ["auto"], "animation": "stand_shoulders"},
	# Места: полочка, окна, уголок
	"shelf_demo": {"title": "Полочка — попробовать", "group": "place", "menu_id": 40, "flags": ["pauses_places"], "sources": ["user"]},
	"return_floor": {"title": "Вернуться на пол", "group": "place", "menu_id": 41, "flags": ["pauses_places"], "sources": ["user", "auto", "remote"], "animation": "jump"},
	"pick_window": {"title": "Выбрать окно под курсором · 4 с", "group": "place", "menu_id": 42, "flags": ["pauses_places"], "sources": ["user"]},
	"cozy_corner": {"title": "Мой уютный уголок", "group": "place", "menu_id": 43, "flags": ["pauses_places"], "sources": ["user", "remote"]},
	# На поверхности окна
	"surface_walk": {"title": "Пройтись по краю", "group": "surface", "menu_id": 305, "flags": ["pauses_places"], "sources": ["user", "auto", "remote"], "animation": "walk_cycle"},
	"surface_scoot": {"title": "Подвинуться сидя", "group": "surface", "menu_id": 313, "flags": ["pauses_places"], "sources": ["user", "auto", "remote"], "animation": "edge_seat"},
	"side_left": {"title": "Опора у левого края", "group": "surface", "menu_id": 306, "flags": ["pauses_places"], "sources": ["user", "auto", "remote"], "animation": "side_lean"},
	"side_right": {"title": "Опора у правого края", "group": "surface", "menu_id": 307, "flags": ["pauses_places"], "sources": ["user", "auto", "remote"], "animation": "side_lean"},
	"side_return": {"title": "Сесть обратно", "group": "surface", "menu_id": 308, "flags": ["pauses_places"], "sources": ["user", "auto", "remote"], "animation": "jump"},
	# Сценки сидя: играют ключевые клипы Godot один раз
	"edge_swing": {"title": "Поболтать ножками", "group": "seated", "menu_id": -1, "sources": ["auto"], "animation": "seated_swing"},
	"edge_lean": {"title": "Откинуться назад", "group": "seated", "menu_id": -1, "sources": ["auto"], "animation": "seated_lean"},
	"edge_peek": {"title": "Посмотреть вниз", "group": "seated", "menu_id": -1, "sources": ["auto"], "animation": "seated_peek"},
	"edge_balance": {"title": "Побалансировать", "group": "seated", "menu_id": -1, "sources": ["auto"], "animation": "seated_balance"},
	"edge_sway": {"title": "Покачаться", "group": "seated", "menu_id": -1, "sources": ["auto"], "animation": "seated_sway"},
	"edge_hum": {"title": "Помурлыкать мелодию", "group": "seated", "menu_id": -1, "sources": ["auto"], "animation": "seated_hum"},
	"edge_nod": {"title": "Покивать в такт", "group": "seated", "menu_id": -1, "sources": ["auto"], "animation": "seated_nod"},
	"edge_sketch": {"title": "Рисовать в блокноте", "group": "scene", "menu_id": 312, "sources": ["user", "auto", "remote"], "animation": "seated_sketch"},
	"edge_fold": {"title": "Сложить звёздочку", "group": "scene", "menu_id": 314, "flags": ["pauses_places"], "sources": ["user", "auto", "remote"], "animation": "seated_fold"},
	"edge_admire_star": {"title": "Полюбоваться звёздочкой", "group": "scene", "menu_id": 315, "flags": ["pauses_places"], "sources": ["user", "remote"], "animation": "seated_admire_star"},
	# Паузы внутри плана: не движения, а ритм (только сама)
	"surface_settle": {"title": "Устроиться поудобнее", "group": "pause", "menu_id": -1, "sources": ["auto"]},
	"side_wait": {"title": "Постоять у края", "group": "pause", "menu_id": -1, "sources": ["auto"]},
	# Какое занятие она предпочитает сидя (это настройка, а не разовое действие)
	"edge_mode_auto": {"title": "Сама выбирает", "group": "seated_mode", "menu_id": 300, "sources": ["user", "remote"], "edge_activity": "auto"},
	"edge_mode_calm": {"title": "Спокойно", "group": "seated_mode", "menu_id": 301, "sources": ["user", "remote"], "edge_activity": "calm"},
	"edge_mode_swing": {"title": "Болтать ножками", "group": "seated_mode", "menu_id": 302, "sources": ["user", "remote"], "edge_activity": "swing", "animation": "seated_swing"},
	"edge_mode_lean": {"title": "Откинуться назад", "group": "seated_mode", "menu_id": 303, "sources": ["user", "remote"], "edge_activity": "lean", "animation": "seated_lean"},
	"edge_mode_peek": {"title": "Посмотреть вниз", "group": "seated_mode", "menu_id": 304, "sources": ["user", "remote"], "edge_activity": "peek", "animation": "seated_peek"},
	"edge_mode_sway": {"title": "Мягко покачиваться", "group": "seated_mode", "menu_id": 309, "sources": ["user", "remote"], "edge_activity": "sway", "animation": "seated_sway"},
	"edge_mode_hum": {"title": "Тихонько напевать", "group": "seated_mode", "menu_id": 310, "sources": ["user", "remote"], "edge_activity": "hum", "animation": "seated_hum"},
	"edge_mode_nod": {"title": "Кивать в такт", "group": "seated_mode", "menu_id": 311, "sources": ["user", "remote"], "edge_activity": "nod", "animation": "seated_nod"},
	# Окно Хоши и вид
	"open_preview": {"title": "Открыть примерочную", "group": "tools", "menu_id": 100, "flags": ["pauses_places"], "sources": ["user"]},
	"to_desktop": {"title": "На рабочий стол", "group": "tools", "menu_id": 101, "flags": ["pauses_places"], "sources": ["user"]},
	"size_small": {"title": "Небольшая · 280 px", "group": "tools", "menu_id": 110, "flags": ["pauses_places"], "sources": ["user"]},
	"size_normal": {"title": "Обычная · 360 px", "group": "tools", "menu_id": 111, "flags": ["pauses_places"], "sources": ["user"]},
	"size_large": {"title": "Крупная · 440 px", "group": "tools", "menu_id": 112, "flags": ["pauses_places"], "sources": ["user"]},
	"return_bottom": {"title": "Вернуть к нижнему краю", "group": "tools", "menu_id": 140, "flags": ["pauses_places"], "sources": ["user", "remote"]},
	"reset_view": {"title": "Вернуть вид спереди", "group": "tools", "menu_id": 141, "flags": ["pauses_places"], "sources": ["user"]},
	"fps_60": {"title": "60 FPS · плавнее", "group": "tools", "menu_id": 130, "sources": ["user"]},
	"fps_30": {"title": "30 FPS · экономно", "group": "tools", "menu_id": 131, "sources": ["user"]},
	"light_editor": {"title": "Настроить свет, тени и обводку…", "group": "tools", "menu_id": 150, "sources": ["user"]},
	"light_reset": {"title": "Сбросить настройки света", "group": "tools", "menu_id": 151, "sources": ["user"]},
	"quit": {"title": "Закрыть Хоши", "group": "app", "menu_id": 199, "sources": ["user"]},
	"restart": {"title": "Перезапустить Хоши", "group": "app", "menu_id": 198, "flags": ["confirm"], "sources": ["user", "remote"]},
	# Пульт с телефона (домашняя сеть)
	"toggle_remote": {"title": "Пульт с телефона", "group": "remote", "menu_id": 180, "sources": ["user"]},
	"remote_info": {"title": "Адрес и код для телефона…", "group": "remote", "menu_id": 181, "sources": ["user"]},
	"remote_forget": {"title": "Забыть все телефоны", "group": "remote", "menu_id": 182, "sources": ["user"]},
	"pc_actions_editor": {"title": "Мои действия для пульта…", "group": "remote", "menu_id": 183, "sources": ["user"]},
	"sound_outputs_editor": {"title": "Звук на пульте…", "group": "remote", "menu_id": 184, "sources": ["user"]},
	# Переключатели
	"toggle_look": {"title": "Внимание к курсору", "group": "look", "menu_id": 120, "sources": ["user"]},
	"toggle_motion": {"title": "Мягкие движения", "group": "look", "menu_id": 121, "sources": ["user"]},
	"toggle_hair": {"title": "Движение волос", "group": "look", "menu_id": 122, "sources": ["user"]},
	"toggle_bubbles": {"title": "Короткие реплики", "group": "look", "menu_id": 123, "sources": ["user"]},
	"toggle_clickthrough": {"title": "Клики только по Хоши", "group": "tools", "menu_id": 124, "sources": ["user"]},
	"toggle_auto_walk": {"title": "Самостоятельные прогулки", "group": "autonomy", "menu_id": 125, "sources": ["user", "remote"]},
	"toggle_autonomy": {"title": "Самостоятельность", "group": "autonomy", "menu_id": 126, "sources": ["user", "remote"]},
	"toggle_auto_rest": {"title": "Самостоятельный отдых", "group": "autonomy", "menu_id": 127, "sources": ["user", "remote"]},
	# Проверка краёв окна
	"scan_window_structure": {"title": "Структура окна · без снимка", "group": "diagnostics", "menu_id": 160, "sources": ["user"]},
	"scan_window_visual": {"title": "Видимые края окна · 1 кадр", "group": "diagnostics", "menu_id": 161, "sources": ["user"]},
	# Разговор
	"talk_voice": {"title": "Поговорить через ChatGPT", "group": "talk", "menu_id": 170, "sources": ["user"]},
	"talk_text": {"title": "Открыть текстовый чат", "group": "talk", "menu_id": 171, "sources": ["user"]},
	# Ритм и места отдыха
	"activity_quiet": {"title": "Тихая · без прогулок", "group": "rhythm", "menu_id": 200, "sources": ["user", "remote"]},
	"activity_normal": {"title": "Обычная", "group": "rhythm", "menu_id": 201, "sources": ["user", "remote"]},
	"activity_playful": {"title": "Игривая", "group": "rhythm", "menu_id": 202, "sources": ["user", "remote"]},
	"place_manual": {"title": "Только вручную", "group": "rest_place", "menu_id": 210, "sources": ["user", "remote"]},
	"place_cozy": {"title": "Свой уголок", "group": "rest_place", "menu_id": 211, "sources": ["user", "remote"]},
	"place_smart": {"title": "Окна → уголок", "group": "rest_place", "menu_id": 212, "sources": ["user", "remote"]},
	"place_focus": {"title": "Моё окно → уголок", "group": "rest_place", "menu_id": 213, "sources": ["user", "remote"]},
}

## Пульт с телефона. Вкладки: "main" — главное (быстрые кнопки и приложения),
## "play" — всё, что Хоши делает (плитки с иконками), "modes" — режимы (чипы).
const REMOTE_QUICK: Array[String] = ["wave", "pet", "cozy_corner", "walk", "stop", "doze"]
## Разделы пульта: [группа команд, заголовок, вкладка], по порядку.
## «Общение» (помахать, погладить, дремать) — только быстрыми кнопками на главной.
const REMOTE_GROUPS: Array = [
	["scene", "Сценки", "play"], ["mood", "Настроение", "play"],
	["move", "Движение", "play"], ["place", "Места", "play"], ["surface", "На окне", "play"],
	["rhythm", "Ритм дня", "modes"], ["rest_place", "Где отдыхать", "modes"],
	["seated_mode", "Занятие сидя", "modes"], ["autonomy", "Самостоятельность", "modes"],
	["app", "Программа", "modes"],
]
## Значки для пульта (плитки и быстрые кнопки).
const ICONS := {
	"restart": "🔄", "wave": "👋", "pet": "🤍", "doze": "😴", "walk": "🚶", "stop": "✋", "sit": "🪑", "stand": "🧍",
	"cozy_corner": "🏠", "return_floor": "⬇️", "surface_walk": "↔️", "surface_scoot": "🔀",
	"side_left": "⬅️", "side_right": "➡️", "side_return": "⤴️",
	"edge_sketch": "✏️", "edge_fold": "⭐", "edge_admire_star": "🌟",
	"mood_neutral": "🙂", "mood_happy": "😊", "mood_relaxed": "🍃", "mood_surprised": "😮", "mood_sad": "🥺",
}
## Короткие подписи для маленьких кнопок (иначе — обычный title).
const SHORT_TITLES := {
	"wave": "Помахать", "pet": "Погладить", "cozy_corner": "Уголок", "walk": "Пройтись", "stop": "Стоп",
	"doze": "Дремать", "return_floor": "На пол", "restart": "Перезапустить", "sit": "Сесть", "stand": "Встать",
	"surface_walk": "По краю", "surface_scoot": "Подвинуться", "side_left": "Левый бок", "side_right": "Правый бок",
	"side_return": "Сесть обратно", "edge_sketch": "Рисовать", "edge_fold": "Звёздочка", "edge_admire_star": "Любоваться",
	"mood_neutral": "Спокойная", "mood_happy": "Радостная", "mood_relaxed": "Расслабленная",
	"mood_surprised": "Удивлённая", "mood_sad": "Грустная",
	"toggle_autonomy": "Сама решает", "toggle_auto_walk": "Гуляет сама", "toggle_auto_rest": "Отдыхает сама",
	"activity_quiet": "Тихая",
}

## Группы вариантов для выпадающих списков: порядок = порядок пунктов.
const ACTIVITY_CHOICES: Array[String] = ["activity_quiet", "activity_normal", "activity_playful"]
const PLACE_CHOICES: Array[String] = ["place_manual", "place_cozy", "place_smart", "place_focus"]
## Значение state.place_mode для каждого пункта PLACE_CHOICES (тот же порядок).
const PLACE_MODES: Array[String] = ["off", "cozy", "smart", "focus"]
const EDGE_CHOICES: Array[String] = ["edge_mode_auto", "edge_mode_calm", "edge_mode_swing", "edge_mode_lean", "edge_mode_peek", "edge_mode_sway", "edge_mode_hum", "edge_mode_nod"]

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
	if id < 0:
		return ""
	for command in LIST:
		if int(LIST[command]["menu_id"]) == id:
			return str(command)
	return ""

static func icon(command: String) -> String:
	return str(ICONS.get(command, ""))

static func short_title(command: String) -> String:
	return str(SHORT_TITLES.get(command, title(command)))

static func has_flag(command: String, flag: String) -> bool:
	return flag in LIST.get(command, {}).get("flags", [])

static func edge_activity(command: String) -> String:
	return str(LIST.get(command, {}).get("edge_activity", ""))

## Кто может отдать команду: "user" (меню, клавиши), "remote" (пульт с
## телефона — только вместе с "user") и/или "auto" (сама Хоши через IntentPlanner).
static func allows(command: String, source: String) -> bool:
	return source in LIST.get(command, {}).get("sources", [])

## id движения из motion_library.gd, которое использует команда.
static func animation(command: String) -> String:
	return str(LIST.get(command, {}).get("animation", ""))

## Путь к файлу клипа, который можно открыть и поправить в Godot
## (пусто, если движение пока описано кодом).
static func animation_path(command: String) -> String:
	var id: String = animation(command)
	return MotionLibrary.path(id) if MotionLibrary.is_clip(id) else ""

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
