extends RefCounted
## Small deterministic intention planner for Hoshi.
## 0.8.0 runs in shadow mode: it may choose/record plans, but it never moves the
## window, edits bones or invokes controllers. Existing owners execute actions.
const MAX_HISTORY: int = 6
const MAX_VARIANT_HISTORY: int = 5
const MAX_STEPS: int = 4
const INTENTS: Array[String] = [
	"observe", "explore_floor", "rest", "social_react",
	"explore_surface", "visit_side", "leave_support",
]
const COOLDOWN_SECONDS: Dictionary = {
	"observe": 5.0,
	"explore_floor": 18.0,
	"rest": 42.0,
	"social_react": 55.0,
	"explore_surface": 20.0,
	"visit_side": 32.0,
	"leave_support": 55.0,
}

var enabled: bool = true
var active_intent: Dictionary = {}
var history: Array[String] = []
var variant_history: Array[String] = []
var cooldowns: Dictionary = {}
var last_context: Dictionary = {}
var last_report: Dictionary = {}
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

func tick(delta: float, context: Dictionary = {}) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	for name in cooldowns.keys():
		var left: float = maxf(0.0, float(cooldowns[name]) - dt)
		if left <= 0.0001:
			cooldowns.erase(name)
		else:
			cooldowns[name] = left
	if not context.is_empty():
		observe_context(context)

func observe_context(context: Dictionary) -> void:
	# "blocked" prevents choosing a new intent. It must not erase an intent that
	# is blocked by its own in-flight controller (walking, jumping, posture).
	# User input and support loss interrupt explicitly through interrupt().
	last_context = context.duplicate(true)

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
	last_report = candidate_report(context, activity)
	if not enabled or bool(context.get("blocked", false)):
		return {}
	var candidates: Array[String] = []
	var weights: Array[float] = []
	var total: float = 0.0
	for name in INTENTS:
		var entry: Dictionary = last_report.get(name, {})
		if not bool(entry.get("available", false)):
			continue
		var weight: float = float(entry.get("weight", 0.0))
		if weight <= 0.0:
			continue
		candidates.append(name)
		weights.append(weight)
		total += weight
	if candidates.is_empty() or total <= 0.0:
		return {}
	var roll: float = _rng.randf() * total
	var chosen: String = candidates.back()
	for index in range(candidates.size()):
		roll -= weights[index]
		if roll <= 0.0:
			chosen = candidates[index]
			break
	return build_plan(chosen, context, activity)

func candidate_report(context: Dictionary, activity: String = "normal") -> Dictionary:
	var report: Dictionary = {}
	var decision_context: Dictionary = context.duplicate()
	decision_context["quiet"] = activity == "quiet"
	for name in INTENTS:
		var reason: String = rejection_reason(name, decision_context)
		var cooldown: float = cooldown_left(name)
		var available: bool = reason.is_empty() and cooldown <= 0.0
		if reason.is_empty() and cooldown > 0.0:
			reason = "cooldown"
		var novelty: float = _novelty_multiplier(name)
		var weight: float = _weight(name, activity) * novelty if available else 0.0
		report[name] = {
			"available": available,
			"reason": reason,
			"cooldown": cooldown,
			"novelty": novelty,
			"weight": weight,
		}
	return report

func intent_available(intent_name: String, context: Dictionary) -> bool:
	return rejection_reason(intent_name, context).is_empty() and cooldown_left(intent_name) <= 0.0

func rejection_reason(intent_name: String, context: Dictionary) -> String:
	if not INTENTS.has(intent_name):
		return "unknown"
	if bool(context.get("blocked", false)):
		return "blocked"
	var location: String = str(context.get("location", "floor"))
	match intent_name:
		"observe":
			if not bool(context.get("can_observe", true)):
				return "cannot_observe"
		"explore_floor":
			if location != "floor":
				return "not_floor"
			if not bool(context.get("can_walk", false)):
				return "cannot_walk"
		"rest":
			if not bool(context.get("can_rest", false)):
				return "cannot_rest"
		"social_react":
			if not bool(context.get("can_social", true)):
				return "cannot_social"
		"explore_surface":
			if location != "surface":
				return "not_surface"
			if bool(context.get("cozy", false)) and bool(context.get("quiet", false)):
				if not bool(context.get("can_surface_scoot", false)):
					return "cannot_surface_scoot"
				return ""
			if not bool(context.get("can_surface_walk", false)):
				return "cannot_surface_walk"
		"visit_side":
			if location != "surface":
				return "not_surface"
			if not bool(context.get("can_side", false)):
				return "cannot_side"
		"leave_support":
			if location != "surface":
				return "not_surface"
			if not bool(context.get("can_leave", false)):
				return "cannot_leave"
	return ""

func cooldown_left(intent_name: String) -> float:
	return maxf(0.0, float(cooldowns.get(intent_name, 0.0)))

func build_plan(intent_name: String, context: Dictionary, activity: String = "normal") -> Dictionary:
	var decision_context: Dictionary = context.duplicate()
	decision_context["quiet"] = activity == "quiet"
	if not rejection_reason(intent_name, decision_context).is_empty():
		return {}
	var variants: Array = _variants(intent_name, decision_context, activity)
	if variants.is_empty():
		return {}
	var options: Array = []
	var last_variant: String = variant_history.back() if not variant_history.is_empty() else ""
	for variant in variants:
		if variants.size() == 1 or str(variant.get("id", "")) != last_variant:
			options.append(variant)
	if options.is_empty():
		options = variants
	var selected: Dictionary = options[_rng.randi_range(0, options.size() - 1)]
	var steps: Array = selected.get("steps", [])
	if steps.is_empty() or steps.size() > MAX_STEPS:
		return {}
	return {
		"name": intent_name,
		"variant": str(selected.get("id", intent_name)),
		"steps": steps.duplicate(),
		"index": 0,
		"source": "planner",
		"generation": generation,
	}

func activate(plan: Dictionary, source: String = "planner") -> bool:
	if plan.is_empty():
		return false
	var name: String = str(plan.get("name", ""))
	var steps: Array = plan.get("steps", [])
	if not INTENTS.has(name) or steps.is_empty() or steps.size() > MAX_STEPS:
		return false
	active_intent = plan.duplicate(true)
	active_intent["source"] = source
	active_intent["generation"] = generation
	_record(name)
	_record_variant(str(active_intent.get("variant", name)))
	_arm_cooldown(name)
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

func _variants(intent_name: String, context: Dictionary, activity: String) -> Array:
	var location: String = str(context.get("location", "floor"))
	match intent_name:
		"observe":
			if location == "surface":
				if bool(context.get("cozy", false)):
					if activity == "quiet":
						return [
							{"id": "cozy_sway", "steps": ["edge_sway"]},
							{"id": "cozy_sketch", "steps": ["edge_sketch"]},
							{"id": "cozy_look", "steps": ["look"]},
						]
					return [
						{"id": "cozy_sway", "steps": ["edge_sway"]},
						{"id": "cozy_sketch", "steps": ["edge_sketch"]},
						{"id": "cozy_look", "steps": ["look"]},
						{"id": "cozy_peek", "steps": ["edge_peek"]},
					]
				if activity == "quiet":
					return [{"id": "edge_sway", "steps": ["edge_sway"]}]
				return [
					{"id": "edge_sway", "steps": ["edge_sway"]},
					{"id": "edge_peek", "steps": ["edge_peek"]},
					{"id": "edge_balance_peek", "steps": ["edge_balance", "edge_peek"]},
				]
			if activity == "quiet":
				return [
					{"id": "look_only", "steps": ["look"]},
					{"id": "look_weight_left", "steps": ["look", "floor_weight_left"]},
					{"id": "look_weight_right", "steps": ["look", "floor_weight_right"]},
				]
			return [
				{"id": "look_peek_left", "steps": ["look", "floor_peek_left"]},
				{"id": "look_peek_right", "steps": ["look", "floor_peek_right"]},
				{"id": "look_hands", "steps": ["look", "floor_hands"]},
			]
		"explore_floor":
			var variants: Array = [
				{"id": "walk_look", "steps": ["walk", "look"]},
				{"id": "walk_weight_left_look", "steps": ["walk", "floor_weight_left", "look"]},
				{"id": "walk_weight_right_look", "steps": ["walk", "floor_weight_right", "look"]},
			]
			if activity != "quiet":
				variants.append({"id": "look_walk_peek_left", "steps": ["look", "walk", "floor_peek_left"]})
				variants.append({"id": "look_walk_peek_right", "steps": ["look", "walk", "floor_peek_right"]})
			return variants
		"rest":
			return [{"id": "sit", "steps": ["sit"]}]
		"social_react":
			return [{"id": "wave", "steps": ["wave"]}]
		"explore_surface":
			if activity == "quiet" and bool(context.get("cozy", false)):
				return [{"id": "cozy_scoot_settle", "steps": ["surface_scoot", "surface_settle"]}]
			var surface_variants: Array = [
				{"id": "edge_walk_settle", "steps": ["surface_walk", "surface_settle"]},
				{"id": "edge_walk_sway", "steps": ["surface_walk", "surface_settle", "edge_sway"]},
			]
			if activity != "quiet":
				surface_variants.append({"id": "edge_walk_peek", "steps": ["surface_walk", "surface_settle", "edge_peek"]})
				surface_variants.append({"id": "edge_walk_balance", "steps": ["surface_walk", "surface_settle", "edge_balance"]})
			if activity == "playful":
				surface_variants.append({"id": "edge_walk_swing", "steps": ["surface_walk", "surface_settle", "edge_swing"]})
			return surface_variants
		"visit_side":
			var side: String = str(context.get("preferred_side", "left"))
			if not side in ["left", "right"]:
				side = "left"
			return [{"id": "side_" + side + "_peek", "steps": ["side_" + side, "side_wait", "side_return", "edge_peek"]}]
		"leave_support":
			if activity == "quiet":
				return [{"id": "return_look", "steps": ["return_floor", "look"]}]
			return [
				{"id": "return_look_peek_left", "steps": ["return_floor", "look", "floor_peek_left"]},
				{"id": "return_look_peek_right", "steps": ["return_floor", "look", "floor_peek_right"]},
			]
	return []

func _weight(intent_name: String, activity: String) -> float:
	match intent_name:
		"observe":
			return 4.2 if activity == "quiet" else 2.4
		"explore_floor", "explore_surface":
			return 0.7 if activity == "quiet" else (4.0 if activity == "playful" else 2.4)
		"rest":
			return 0.55 if activity == "quiet" else (0.30 if activity == "playful" else 0.50)
		"social_react":
			return 2.0 if activity == "playful" else 0.0
		"visit_side":
			return 0.0 if activity == "quiet" else (2.2 if activity == "playful" else 1.2)
		"leave_support":
			return 0.25 if activity == "quiet" else (1.1 if activity == "playful" else 0.8)
	return 1.0

func _novelty_multiplier(intent_name: String) -> float:
	if history.is_empty():
		return 1.0
	var multiplier: float = 1.0
	var distance: int = 0
	for index in range(history.size() - 1, -1, -1):
		distance += 1
		if history[index] != intent_name:
			continue
		match distance:
			1:
				multiplier *= 0.12
			2:
				multiplier *= 0.32
			3:
				multiplier *= 0.58
			_:
				multiplier *= 0.82
	return clampf(multiplier, 0.05, 1.0)

func _arm_cooldown(name: String) -> void:
	var seconds: float = float(COOLDOWN_SECONDS.get(name, 0.0))
	if seconds > 0.0:
		cooldowns[name] = maxf(cooldown_left(name), seconds)

func _record(name: String) -> void:
	history.append(name)
	while history.size() > MAX_HISTORY:
		history.pop_front()

func _record_variant(name: String) -> void:
	variant_history.append(name)
	while variant_history.size() > MAX_VARIANT_HISTORY:
		variant_history.pop_front()
