@tool
extends RefCounted
## Shared Animation track format for scene props; independent of a particular clip.

const PROPERTIES: PackedStringArray = ["position", "rotation_degrees", "scale"]
const NAMED_TARGETS := {
	"open_book": "Блокнот",
	"pencil": "Мелок",
	"paper_star": "Бумажная сценка",
	"paper_sheet": "Лист бумаги",
	"paper_shape": "Сложенная звезда",
}

static func target_name(prop_id: String) -> String:
	return NAMED_TARGETS.get(prop_id, "Target")

static func path_for(prop_id: String, property: String) -> String:
	return "Props/%s/%s" % [prop_id, target_name(prop_id)]

static func type_for(property: String) -> int:
	match property:
		"position": return Animation.TYPE_POSITION_3D
		"rotation_degrees": return Animation.TYPE_ROTATION_3D
		"scale": return Animation.TYPE_SCALE_3D
	return -1

static func parse(path: String, track_type: int) -> Dictionary:
	if not path.begins_with("Props/"):
		return {}
	var suffix: String = path.trim_prefix("Props/")
	var parts: PackedStringArray = suffix.split("/")
	if parts.size() != 2:
		return {}
	var prop_id: String = parts[0]
	if not prop_id.is_valid_identifier() or parts[1] != target_name(prop_id):
		return {}
	for property in PROPERTIES:
		if type_for(property) == track_type:
			return {"id": prop_id, "property": property}
	return {}

static func clamped_value(property: String, value: Variant) -> Variant:
	if not PROPERTIES.has(property) or not value is Vector3 or not (value as Vector3).is_finite():
		return null
	var v: Vector3 = value
	match property:
		"position": return v.clamp(Vector3.ONE * -1.0, Vector3.ONE)
		"rotation_degrees": return v.clamp(Vector3.ONE * -180.0, Vector3.ONE * 180.0)
		"scale": return v.clamp(Vector3.ZERO, Vector3.ONE * 4.0)
	return null
