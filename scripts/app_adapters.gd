extends RefCounted
## Аддоны приложений: расширение Chrome (YouTube), позже аддон Blender и другие.
##
## Аддон подключается к Хоши по локальному WebSocket (только с этого же ПК) и
## объявляет себя:
##   {"op": "adapter", "id": "youtube", "title": "YouTube",
##    "commands": [{"name": "pause", "title": "Пауза", "icon": "⏸", "row": "main", "args": {...}}],
##   row: "main" — большие кнопки плеера, "hidden" — без кнопки (вызывается из
##   списков или полосы времени), иначе маленькие кнопки во втором ряду.
## state.lists — раскрывающиеся списки на пульте:
##   [{"id": "next", "title": "Дальше", "items": [{"id", "title", "subtitle", "thumbnail", "current"}]}];
##   нажатие на пункт вызывает команду "play_item" с {"id": ..., "list": ...}.
##    "state": {...}}
## Потом присылает обновления состояния {"op": "adapter_state", "state": {...}}.
## Его команды появляются в пульте и в списке команд под именем
## "app:<id>:<name>", например "app:youtube:pause". Нажатие на телефоне
## уходит обратно в аддон как {"op": "run", "command": "pause", "args": {...}}.
##
## Команды аддонов выполняются только по нажатию человека (пульт, меню) —
## сама Хоши их не запускает (см. ASSISTANT_ROADMAP_RU.md, уровень «Действовать»).
## Аддон отключился — его раздел в пульте исчезает.

const MAX_ADAPTERS: int = 8
const MAX_COMMANDS: int = 40
const ID_PATTERN: String = "^[a-z][a-z0-9_]{1,23}$"

## id -> {"title", "commands": [{name, title, icon, args}], "state": {}, "peer": ключ соединения}
var adapters: Dictionary = {}
var _id_check := RegEx.new()

func _init() -> void:
	_id_check.compile(ID_PATTERN)

## Принять объявление аддона. Возвращает id или "" (отказ).
func announce(peer_key: int, message: Dictionary) -> String:
	var id: String = str(message.get("id", ""))
	if _id_check.search(id) == null:
		return ""
	if not adapters.has(id) and adapters.size() >= MAX_ADAPTERS:
		return ""
	var commands: Array = []
	for item in message.get("commands", []):
		if commands.size() >= MAX_COMMANDS or not item is Dictionary:
			break
		var name: String = str(item.get("name", ""))
		if _id_check.search(name) == null:
			continue
		commands.append({"name": name, "title": str(item.get("title", name)).left(40),
			"icon": str(item.get("icon", "")).left(4), "row": str(item.get("row", "")) if str(item.get("row", "")) in ["main", "hidden"] else "extra", "args": item.get("args", {}) if item.get("args", {}) is Dictionary else {}})
	adapters[id] = {"title": str(message.get("title", id)).left(40), "commands": commands,
		"state": _clean_state(message.get("state", {})), "peer": peer_key}
	return id

func update_state(peer_key: int, state: Variant) -> bool:
	for id in adapters:
		if int(adapters[id]["peer"]) == peer_key:
			adapters[id]["state"] = _clean_state(state)
			return true
	return false

## Соединение закрылось: убрать все аддоны этого соединения.
func drop_peer(peer_key: int) -> void:
	for id in adapters.keys():
		if int(adapters[id]["peer"]) == peer_key:
			adapters.erase(id)

## "app:youtube:pause" -> {"id": "youtube", "name": "pause", "peer": ...}; пусто — нет такой команды.
func resolve(full_name: String) -> Dictionary:
	var parts: PackedStringArray = full_name.split(":")
	if parts.size() != 3 or parts[0] != "app" or not adapters.has(parts[1]):
		return {}
	for command in adapters[parts[1]]["commands"]:
		if command["name"] == parts[2]:
			return {"id": parts[1], "name": parts[2], "peer": adapters[parts[1]]["peer"]}
	return {}

## Разделы для пульта: [{id, title, state, commands: [{command, title, icon, args}]}].
func catalog() -> Array:
	var groups: Array = []
	var ids: Array = adapters.keys()
	ids.sort()
	for id in ids:
		var commands: Array = []
		for command in adapters[id]["commands"]:
			commands.append({"command": "app:%s:%s" % [id, command["name"]], "title": command["title"],
				"icon": command["icon"], "row": command["row"], "args": command["args"]})
		groups.append({"id": id, "title": adapters[id]["title"], "state": adapters[id]["state"], "commands": commands})
	return groups

## Состояние аддона — только простые значения и ограниченный размер.
func _clean_state(state: Variant) -> Dictionary:
	if not state is Dictionary:
		return {}
	var text: String = JSON.stringify(state)
	if text.length() > 48000:
		return {"error": "state_too_large"}
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
