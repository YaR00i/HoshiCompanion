extends RefCounted
## Small deterministic intention planner for Hoshi.
## 0.8.0 runs in shadow mode: it may choose/record plans, but it never moves the
## window, edits bones or invokes controllers. Existing owners execute actions.
const MAX_HISTORY: int = 6
const MAX_STEPS: int = 4

var enabled: bool = true
var active_intent: Dictionary = {}
var history: Array[String] = []
var last_context: Dictionary = {}
var generation: int = 0
var last_interrupt_reason: String = ""
var _rng := RandomNumberGenerator.new()

func seed_random(value: int) -> void:
	_rng.seed = value

func clear() -> void:
	active_intent = {}
	last_interrupt_reason = ""

func interrupt(reason: String = "manual") -> void:
	if not active_intent.is_empty():
		last_interrupt_reason = reason
	active_intent = {}
	generation += 1

func observe_context(context: Dictionary) -> void:
	last_context = context.duplicate(true)
	if bool(context.get("blocked", false)):
		active_intent = {}

func observe_legacy_action(action: String, context: Dictionary) -> Dictionary:
	observe_context(context)
	if action.is_empty() or bool(context.get("blocked", false)):
		return {}
	var intent_name: String = _legacy_intent(action, context)
	if intent_name.is_empty():
		return {}
	var plan: Dictionary = build_plan(intent_name, context)
	if plan.is_empty():
		return {}
	activate(plan, "legacy")
	return active_intent.duplicate(true)

func choose(context: Dictionary, activity: String = "normal") -> Dictionary:
	observe_context(context)
	if not enabled or bool(context.get("blocked", false)):
		return {}
	var candidates: Array[String] = []
	if _valid("observe", context):
		candidates.append("observe")
	if _valid("explore_floor", context):
		candidates.append("explore_floor")
	if _valid("rest", context):
		candidates.append("rest")
	if _valid("social_react", context) and activity == "playful":
		candidates.append("social_react")
	if _valid("explore_surface", context):
		candidates.append("explore_surface")
	if _valid("visit_side", context) and activity != "quiet":
		candidates.append("visit_side")
	if _valid("leave_support", context):
		candidates.append("leave_support")
	if candidates.is_empty():
		return {}
	var filtered: Array[String] = []
	for name in candidates:
		if _recent_count(name, 2) < 2:
			filtered.append(name)
	if filtered.is_empty():
		filtered = candidates
	var weights: Array[float] = []
	var total: float = 0.0
	for name in filtered:
		var weight: float = _weight(name, activity)
		if history.has(name):
			weight *= 0.45
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return {}
	var roll: float = _rng.randf() * total
	var chosen: String = filtered.back()
	for index in range(filtered.size()):
		roll -= weights[index]
		if roll <= 0.0:
			chosen = filtered[index]
			break
	return build_plan(chosen, context)

func build_plan(intent_name: String, context: Dictionary) -> Dictionary:
	if not _valid(intent_name, context):
		return {}
	var steps: Array[String] = _steps(intent_name, context)
	if steps.is_empty() or steps.size() > MAX_STEPS:
		return {}
	return {
		"name": intent_name,
		"steps": steps,
		"index": 0,
		"source": "planner",
		"generation": generation,
	}

func activate(plan: Dictionary, source: String = "planner") -> bool:
	if plan.is_empty():
		return false
	var name: String = str(plan.get("name", ""))
	var steps: Array = plan.get("steps", [])
	if name.is_empty() or steps.is_empty() or steps.size() > MAX_STEPS:
		return false
	active_intent = plan.duplicate(true)
	active_intent["source"] = source
	active_intent["generation"] = generation
	_record(name)
	return true

func complete_step() -> String:
	if active_intent.is_empty():
		return ""
	var steps: Array = active_intent.get("steps", [])
	var index: int = int(active_intent.get("index", 0)) + 1
	if index >= steps.size():
		var finished: String = str(active_intent.get("name", ""))
		active_intent = {}
		return finished
	active_intent["index"] = index
	return str(steps[index])

func current_step() -> String:
	if active_intent.is_empty():
		return ""
	var steps: Array = active_intent.get("steps", [])
	var index: int = int(active_intent.get("index", 0))
	if index < 0 or index >= steps.size():
		return ""
	return str(steps[index])

func _legacy_intent(action: String, context: Dictionary) -> String:
	match action:
		"walk":
			return "explore_surface" if str(context.get("location", "floor")) == "surface" else "explore_floor"
		"sit":
			return "rest"
		"wave":
			return "social_react"
	return ""

func _valid(intent_name: String, context: Dictionary) -> bool:
	if bool(context.get("blocked", false)):
		return false
	var location: String = str(context.get("location", "floor"))
	match intent_name:
		"observe":
			return bool(context.get("can_observe", true))
		"explore_floor":
			return location == "floor" and bool(context.get("can_walk", false))
		"rest":
			return bool(context.get("can_rest", false))
		"social_react":
			return bool(context.get("can_social", true))
		"explore_surface":
			return location == "surface" and bool(context.get("can_surface_walk", false))
		"visit_side":
			return location == "surface" and bool(context.get("can_side", false))
		"leave_support":
			return location == "surface" and bool(context.get("can_leave", false))
	return false

func _steps(intent_name: String, context: Dictionary) -> Array[String]:
	match intent_name:
		"observe":
			return ["look"]
		"explore_floor":
			return ["walk", "look"]
		"rest":
			return ["sit"]
		"social_react":
			return ["wave"]
		"explore_surface":
			return ["surface_walk", "surface_settle"]
		"visit_side":
			var side: String = str(context.get("preferred_side", "left"))
			if not side in ["left", "right"]:
				side = "left"
			return ["side_" + side, "side_wait", "side_return"]
		"leave_support":
			return ["return_floor", "look"]
	return []

func _weight(intent_name: String, activity: String) -> float:
	match intent_name:
		"observe":
			return 4.2 if activity == "quiet" else 2.4
		"explore_floor", "explore_surface":
			return 0.7 if activity == "quiet" else (4.0 if activity == "playful" else 2.4)
		"rest":
			return 3.0 if activity == "quiet" else (0.7 if activity == "playful" else 1.6)
		"social_react":
			return 2.0
		"visit_side":
			return 2.2 if activity == "playful" else 1.2
		"leave_support":
			return 0.8
	return 1.0

func _record(name: String) -> void:
	history.append(name)
	while history.size() > MAX_HISTORY:
		history.pop_front()

func _recent_count(name: String, count: int) -> int:
	var result: int = 0
	var first: int = maxi(0, history.size() - count)
	for index in range(first, history.size()):
		if history[index] == name:
			result += 1
	return result
