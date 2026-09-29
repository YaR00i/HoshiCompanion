extends "res://tests/test_shelf.gd"
## Запечь реакции на касание (кодовые, touch_reactions.gd) в клипы
## animations/touch_<место>.tres — стартовая точка для правки в «Позах и сценках
## в Godot». Уже существующий клип не перезаписывается без -- --force.
##   godot --path . --script res://tools/bake_touch_clips.gd -- --preview --test-mode [--force] [--only=chest]

const TouchMotion = preload("res://scripts/touch_motion.gd")
const SketchMotion = preload("res://scripts/sketch_motion.gd")
const FPS: float = 30.0
const KEY_EVERY: int = 2          # ключ каждые 2 кадра (15 в секунду)
const MIN_DEGREES: float = 0.5    # кость, повернувшаяся меньше, — без дорожки

func _run() -> void:
	var force: bool = OS.get_cmdline_user_args().has("--force")
	var only: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for i in range(20):
		await process_frame
		if app._ready_to_run: break
	if not app._ready_to_run:
		print("BAKE_RESULT failed=model")
		quit(1)
		return
	app.set_process(false)
	app.state.autonomy_enabled = false
	app.state.motion_enabled = false # ровная база: без дыхания и покачивания
	app.ui.bubbles_enabled = false
	_advance(40)
	var touch = app.stage.touch
	var height: float = touch.driver.height_m
	var written: int = 0
	for zone in TouchMotion.ZONES:
		if not only.is_empty() and zone != only:
			continue
		var path: String = TouchMotion.path_for(TouchMotion.clip_name(zone))
		if ResourceLoader.exists(path) and not force:
			print("BAKE skip ", zone, " (есть клип; -- --force перезапишет)")
			continue
		touch.use_clips = false
		touch.record = true
		touch.cancel()
		touch._cooldown = 0.0
		_advance(20)
		touch.start(zone, "left")
		var length: float = float(TouchMotion.ZONES[zone])
		var frames: Array = []
		var frame_index: int = 0
		while frame_index <= int(round(length * FPS)) + 2:
			_advance(1)
			if touch.recorded.has("posed") and frame_index % KEY_EVERY == 0:
				# Время — возраст реакции в этом кадре (а не номер кадра: они сдвинуты на один).
				frames.append({"time": minf(touch.age, length), "data": touch.recorded.duplicate(true)})
			frame_index += 1
		touch.record = false
		touch.use_clips = true
		var clip: Animation = _build(zone, length, frames, height)
		var error: String = TouchMotion.validation_error(TouchMotion.clip_name(zone), clip)
		if not error.is_empty():
			print("BAKE_ERROR ", zone, ": ", error)
			continue
		if ResourceSaver.save(clip, path) == OK:
			written += 1
			print("BAKE wrote ", path, " tracks=", clip.get_track_count())
	TouchMotion.forget_cache()
	print("BAKE_RESULT written=", written)
	app.queue_free()
	await process_frame
	quit(0)

func _build(zone: String, length: float, frames: Array, height: float) -> Animation:
	var clip := Animation.new()
	clip.resource_name = TouchMotion.clip_name(zone)
	clip.length = length
	clip.step = 1.0 / 15.0
	var semantics: Array = []
	for semantic in SketchMotion.BONE_TARGET_NAMES:
		var moved: float = 0.0
		for f in frames:
			var base: Dictionary = f["data"]["base"]["bones"]
			var posed: Dictionary = f["data"]["posed"]["bones"]
			if base.has(semantic) and posed.has(semantic):
				moved = maxf(moved, rad_to_deg((base[semantic] as Quaternion).angle_to(posed[semantic])))
		if moved >= MIN_DEGREES:
			semantics.append(semantic)
	for semantic in semantics:
		var track: int = clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath(SketchMotion.bone_path(semantic)))
		clip.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		for f in frames:
			var base_q: Quaternion = f["data"]["base"]["bones"][semantic]
			var posed_q: Quaternion = f["data"]["posed"]["bones"][semantic]
			clip.rotation_track_insert_key(track, f["time"], (base_q.inverse() * posed_q).normalized())
	for channel in TouchMotion.CHANNELS:
		var track: int = clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(track, NodePath("Channels:" + channel))
		clip.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		clip.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
		for f in frames:
			var data: Dictionary = f["data"]
			var value: Variant = 0.0
			match channel:
				"touch_yaw":
					value = float(data.get("yaw", 0.0))
				"hips_offset":
					value = (data["posed"]["hips"] - data["base"]["hips"]) / height
				_:
					value = float(data.get("face", {}).get(str(channel).trim_prefix("face_"), 0.0))
			clip.track_insert_key(track, f["time"], value)
	return clip
