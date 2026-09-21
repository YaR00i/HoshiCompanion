extends SceneTree
const State = preload("res://scripts/companion_state.gd")
const Place = preload("res://scripts/place_director.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var state = State.new()
	var place = Place.new()
	state.place_mode = "cozy"
	state.autonomy_enabled = true
	state.rest_enabled = true
	state.motion_enabled = true
	place.change_mode("cozy")
	var action := ""
	for i in range(121):
		action = place.tick(0.1, state, {"blocked": false, "can_place": true})
	check(action == "cozy" and place.requests == 1, "cozy mode emits one bounded place request")
	check(place.tick(0.1, state, {"blocked": false, "can_place": true}) == "", "request enters cooldown")
	place.wait_left = 0.0
	place.manual_pause(1.0)
	check(place.tick(0.1, state, {"blocked": false, "can_place": true}) == "", "manual interaction pauses autonomy")
	for i in range(10): place.tick(0.1, state, {"blocked": false, "can_place": true})
	place.wait_left = 0.0
	check(place.tick(0.1, state, {"blocked": true, "can_place": true}) == "", "blocked context prevents place request")
	check(place.tick(0.1, state, {"blocked": false, "can_place": false}) == "", "airborne/preview context prevents place request")
	state.place_mode = "smart"
	place.change_mode("smart")
	place.wait_left = 0.0
	check(place.tick(0.1, state, {"blocked": false, "can_place": true}) == "smart", "smart mode emits automatic-window request")
	state.autonomy_enabled = false
	place.wait_left = 0.0
	check(place.tick(0.1, state, {"blocked": false, "can_place": true}) == "", "autonomy toggle disables place director")
	print("HOSHI_PLACE_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
