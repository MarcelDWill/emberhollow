# PROTOTYPE - NOT FOR PRODUCTION
extends Node2D
## Forging prototype 1: "Four Stages" (the faithful baseline).
##
## The brief's four stages played one after another: Heat, Hammer, Quench,
## Finish. Each stage scores 0 to 100 and the average sets the quality tier.
## Standalone: all tuning comes from forge_four_stage.json and all input goes
## through the Input Map. Run with `-- --autoplay` to let a simple bot play a
## full forge and print debug_state_text() (used for headless checks).

const PROTOTYPE_NAME: String = "forge_four_stage"
const CONFIG_PATH: String = "res://prototypes/forge_four_stage/forge_four_stage.json"
const DESIGN_SIZE: Vector2 = Vector2(1152.0, 648.0)
const AUTOPLAY_RESULT_FRAMES: int = 90

const ACT_PRIMARY: StringName = &"p1_forge_primary"
const ACT_LEFT: StringName = &"p1_move_left"
const ACT_RIGHT: StringName = &"p1_move_right"
const ACT_UP: StringName = &"p1_move_up"
const ACT_DOWN: StringName = &"p1_move_down"

const COL_BG: Color = Color("2a1c17")
const COL_PANEL: Color = Color("3f2b22")
const COL_OUTLINE: Color = Color("150d0a")
const COL_CREAM: Color = Color("f6e9cf")
const COL_AMBER: Color = Color("e8a33d")
const COL_ORANGE: Color = Color("ff7a1f")
const COL_GLOW: Color = Color("fff3c4")
const COL_IRON: Color = Color("6f6763")
const COL_WATER: Color = Color("35505a")
const HEAT_RAMP: Array[Color] = [
	Color("3a302d"), Color("8f1d14"), Color("e2501a"), Color("ffa62b"), Color("fff3c4"),
]

enum State { READY, INTRO, PLAY, RESULT }

const STAGE_HEAT: int = 0
const STAGE_HAMMER: int = 1
const STAGE_QUENCH: int = 2
const STAGE_FINISH: int = 3
const STAGE_NAMES: Array[String] = ["Heat", "Hammer", "Quench", "Finish"]

var _cfg: Dictionary = {}
var _font: Font
var _autoplay: bool = false
var _bot_tap_down: bool = false
var _result_frames: int = 0

var _state: State = State.READY
var _stage: int = 0
var _stage_time: float = 0.0
var _total_time: float = 0.0
var _stage_scores: Array[float] = []
var _final_score: float = 0.0
var _tier: String = ""
var _quip: String = ""

# Heat
var _needle: float = 0.0
var _zone_center: float = 0.0
var _heat_in_zone: float = 0.0
var _heat_counted: float = 0.0
var _pump_anim: float = 0.0

# Hammer
var _strike_index: int = 0
var _ring_time: float = 0.0
var _gap_left: float = 0.0
var _strike_scores: Array[float] = []
var _hammer_anim: float = 0.0

# Quench
var _quench_holding: bool = false
var _quench_done: bool = false
var _quench_heat: float = 1.0
var _quench_target: float = 0.5
var _quench_settle: float = 0.0
var _quench_score: float = 0.0

# Finish
var _path: PackedVector2Array = PackedVector2Array()
var _cursor: Vector2 = Vector2.ZERO
var _finish_quality_sum: float = 0.0
var _finish_last_quality: float = 0.0

# Juice
var _sparks: Array[Dictionary] = []
var _pops: Array[Dictionary] = []
var _shake: float = 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_autoplay = OS.get_cmdline_user_args().has("--autoplay")
	if not _load_config():
		return
	_build_path()
	_reset_run()


## Returns the current prototype state as JSON text (the project's test hook).
func debug_state_text() -> String:
	var state: Dictionary = {
		"prototype": PROTOTYPE_NAME,
		"state": State.keys()[_state],
		"stage": STAGE_NAMES[mini(_stage, STAGE_NAMES.size() - 1)],
		"stage_index": _stage,
		"stage_timer": snappedf(_stage_time, 0.01),
		"total_timer": snappedf(_total_time, 0.01),
		"stage_scores": _rounded(_stage_scores),
		"strike_scores": _rounded(_strike_scores),
		"final_score": roundi(_final_score),
		"tier": _tier,
		"quip": _quip,
	}
	return JSON.stringify(state)


func _process(delta: float) -> void:
	if _cfg.is_empty():
		return
	if _autoplay:
		_bot()
	match _state:
		State.READY:
			if Input.is_action_just_pressed(ACT_PRIMARY):
				_begin_stage(0)
		State.INTRO:
			_total_time += delta
			_stage_time += delta
			if _stage_time >= float(_cfg["stage_intro_seconds"]):
				_state = State.PLAY
				_stage_time = 0.0
				_log_state()
		State.PLAY:
			_total_time += delta
			_stage_time += delta
			match _stage:
				STAGE_HEAT:
					_update_heat(delta)
				STAGE_HAMMER:
					_update_hammer(delta)
				STAGE_QUENCH:
					_update_quench(delta)
				STAGE_FINISH:
					_update_finish(delta)
		State.RESULT:
			_result_frames += 1
			if _autoplay:
				if _result_frames == AUTOPLAY_RESULT_FRAMES:
					get_tree().quit()
			elif Input.is_action_just_pressed(ACT_PRIMARY):
				_reset_run()
	_update_juice(delta)
	queue_redraw()


# --- Flow -------------------------------------------------------------------

func _load_config() -> bool:
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % CONFIG_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("%s is not a JSON object" % CONFIG_PATH)
		return false
	_cfg = parsed
	return true


func _reset_run() -> void:
	_state = State.READY
	_stage = 0
	_stage_time = 0.0
	_total_time = 0.0
	_stage_scores.clear()
	_strike_scores.clear()
	_final_score = 0.0
	_tier = ""
	_quip = ""
	_result_frames = 0
	_pops.clear()
	_sparks.clear()
	_log_state()


func _begin_stage(index: int) -> void:
	_stage = index
	_stage_time = 0.0
	_state = State.INTRO
	match index:
		STAGE_HEAT:
			var heat: Dictionary = _cfg["heat"]
			_needle = float(heat["needle_start"])
			_zone_center = float(heat["zone_center"])
			_heat_in_zone = 0.0
			_heat_counted = 0.0
		STAGE_HAMMER:
			_strike_index = 0
			_ring_time = 0.0
			_gap_left = 0.0
			_strike_scores.clear()
		STAGE_QUENCH:
			var targets: Array = _cfg["quench"]["target_heats"]
			_quench_target = float(targets[randi() % targets.size()])
			_quench_holding = false
			_quench_done = false
			_quench_heat = 1.0
			_quench_settle = 0.0
		STAGE_FINISH:
			_cursor = _path[0]
			_finish_quality_sum = 0.0
			_finish_last_quality = 0.0
	_log_state()


func _finish_stage(score: float) -> void:
	_stage_scores.append(clampf(score, 0.0, 100.0))
	_add_pop("%s  %d" % [STAGE_NAMES[_stage].to_upper(), roundi(score)], Vector2(576.0, 130.0), 44, COL_GLOW)
	if _stage + 1 < STAGE_NAMES.size():
		_begin_stage(_stage + 1)
	else:
		_show_result()


func _show_result() -> void:
	var total: float = 0.0
	for score: float in _stage_scores:
		total += score
	_final_score = total / float(_stage_scores.size())
	_tier = _tier_for(_final_score)
	var lines: Array = _cfg["anvil_lines"][_tier]
	_quip = str(lines[randi() % lines.size()])
	_state = State.RESULT
	_result_frames = 0
	_add_pop(_tier.to_upper() + "!", Vector2(576.0, 190.0), 76, COL_ORANGE)
	_shake = float(_cfg["juice"]["shake_pixels"])
	_emit_sparks(Vector2(576.0, 190.0), int(_cfg["juice"]["sparks_on_perfect"]) * 2, COL_AMBER)
	_log_state()


func _tier_for(score: float) -> String:
	var best: String = ""
	for tier: Dictionary in _cfg["tiers"]:
		if roundi(score) >= int(tier["min_score"]):
			best = str(tier["name"])
	return best


func _rating_for(score: float) -> String:
	for rating: Dictionary in _cfg["ratings"]:
		if score >= float(rating["min_score"]):
			return str(rating["name"])
	return ""


func _window_score(error: float, perfect: float, miss: float) -> float:
	if error <= perfect:
		return 100.0
	return clampf(remap(error, perfect, miss, 100.0, 0.0), 0.0, 100.0)


func _log_state() -> void:
	if _autoplay:
		print("[state] ", debug_state_text())


func _rounded(values: Array[float]) -> Array[int]:
	var out: Array[int] = []
	for value: float in values:
		out.append(roundi(value))
	return out


# --- Stage 1: Heat ----------------------------------------------------------

func _update_heat(delta: float) -> void:
	var heat: Dictionary = _cfg["heat"]
	var duration: float = float(heat["duration_seconds"])
	_zone_center = float(heat["zone_center"]) \
		+ float(heat["zone_sway"]) * sin(_stage_time * float(heat["zone_sway_speed"])) \
		+ float(heat["zone_wobble"]) * sin(_stage_time * float(heat["zone_wobble_speed"]))
	_needle -= float(heat["needle_fall_per_second"]) * delta
	if Input.is_action_just_pressed(ACT_PRIMARY):
		_needle += float(heat["pump_boost"])
		_pump_anim = 1.0
		_emit_sparks(Vector2(450.0, 330.0), 4, COL_ORANGE)
	_needle = clampf(_needle, 0.0, 1.0)
	if _stage_time >= float(heat["grace_seconds"]):
		_heat_counted += delta
		if _heat_needle_in_zone():
			_heat_in_zone += delta
	if _stage_time >= duration:
		_finish_stage(100.0 * _heat_in_zone / maxf(_heat_counted, 0.001))


func _heat_needle_in_zone() -> bool:
	return absf(_needle - _zone_center) <= float(_cfg["heat"]["zone_width"]) * 0.5


# --- Stage 2: Hammer --------------------------------------------------------

func _hammer_target_time() -> float:
	var times: Array = _cfg["hammer"]["ring_seconds"]
	return float(times[mini(_strike_index, times.size() - 1)])


func _update_hammer(delta: float) -> void:
	var hammer: Dictionary = _cfg["hammer"]
	if _gap_left > 0.0:
		_gap_left -= delta
		return
	_ring_time += delta
	var target: float = _hammer_target_time()
	var miss: float = float(hammer["miss_window_seconds"])
	if Input.is_action_just_pressed(ACT_PRIMARY):
		var error: float = absf(_ring_time - target)
		_register_strike(_window_score(error, float(hammer["perfect_window_seconds"]), miss))
	elif _ring_time > target + miss:
		_register_strike(0.0)


func _register_strike(score: float) -> void:
	var hammer: Dictionary = _cfg["hammer"]
	var juice: Dictionary = _cfg["juice"]
	_strike_scores.append(score)
	_strike_index += 1
	_ring_time = 0.0
	_gap_left = float(hammer["gap_seconds"])
	_hammer_anim = 1.0
	var power: float = score / 100.0
	_shake = float(juice["shake_pixels"]) * power
	_emit_sparks(Vector2(576.0, 384.0), int(float(juice["sparks_on_perfect"]) * power), COL_AMBER)
	_add_pop(_rating_for(score), Vector2(576.0, 250.0), 40, COL_GLOW if score >= 65.0 else COL_CREAM)
	if _strike_index >= int(hammer["strikes"]):
		var total: float = 0.0
		for value: float in _strike_scores:
			total += value
		_finish_stage(total / float(_strike_scores.size()))


# --- Stage 3: Quench --------------------------------------------------------

func _update_quench(delta: float) -> void:
	var quench: Dictionary = _cfg["quench"]
	if _quench_done:
		_quench_settle += delta
		if _quench_settle >= float(quench["settle_seconds"]):
			_finish_stage(_quench_score)
		return
	if not _quench_holding:
		if Input.is_action_just_pressed(ACT_PRIMARY):
			_quench_holding = true
		return
	_quench_heat = maxf(_quench_heat - delta / float(quench["cool_seconds"]), 0.0)
	if not Input.is_action_pressed(ACT_PRIMARY) or _quench_heat <= 0.0:
		var error: float = absf(_quench_heat - _quench_target)
		_quench_score = _window_score(error, float(quench["perfect_window"]), float(quench["miss_window"]))
		if _quench_heat <= 0.0:
			_quench_score = 0.0
		_quench_done = true
		_quench_holding = false
		_shake = float(_cfg["juice"]["shake_pixels"]) * 0.5 * _quench_score / 100.0
		_emit_sparks(Vector2(805.0, 440.0), int(_cfg["juice"]["sparks_on_perfect"]), COL_CREAM)
		_add_pop(_rating_for(_quench_score), Vector2(805.0, 300.0), 40, COL_GLOW)


# --- Stage 4: Finish --------------------------------------------------------

func _build_path() -> void:
	var finish: Dictionary = _cfg["finish"]
	var samples: int = 96
	_path.resize(samples + 1)
	for i: int in samples + 1:
		var u: float = float(i) / float(samples)
		var y: float = 330.0 \
			+ float(finish["wave_height"]) * sin(u * TAU * float(finish["wave_count"])) \
			+ float(finish["ripple_height"]) * sin(u * TAU * float(finish["ripple_count"]))
		_path[i] = Vector2(lerpf(220.0, 930.0, u), y)


func _path_point(u: float) -> Vector2:
	var scaled: float = clampf(u, 0.0, 1.0) * float(_path.size() - 1)
	var index: int = mini(int(scaled), _path.size() - 2)
	return _path[index].lerp(_path[index + 1], scaled - float(index))


func _finish_progress() -> float:
	return clampf(_stage_time / float(_cfg["finish"]["duration_seconds"]), 0.0, 1.0)


func _update_finish(delta: float) -> void:
	var finish: Dictionary = _cfg["finish"]
	var move: Vector2 = Input.get_vector(ACT_LEFT, ACT_RIGHT, ACT_UP, ACT_DOWN)
	_cursor += move * float(finish["cursor_speed"]) * delta
	_cursor = _cursor.clamp(Vector2(60.0, 120.0), Vector2(1092.0, 560.0))
	var distance: float = _cursor.distance_to(_path_point(_finish_progress()))
	_finish_last_quality = _window_score(distance, float(finish["perfect_radius"]), float(finish["miss_radius"])) / 100.0
	_finish_quality_sum += _finish_last_quality * delta
	if _finish_last_quality > 0.6 and randf() < 0.5:
		_emit_sparks(_cursor, 1, COL_AMBER)
	if _stage_time >= float(finish["duration_seconds"]):
		_finish_stage(100.0 * _finish_quality_sum / _stage_time)


# --- Autoplay bot (headless checks only) -----------------------------------

func _bot() -> void:
	if _bot_tap_down:
		Input.action_release(ACT_PRIMARY)
		_bot_tap_down = false
		return
	match _state:
		State.READY:
			_bot_tap()
		State.PLAY:
			match _stage:
				STAGE_HEAT:
					if _needle < _zone_center:
						_bot_tap()
				STAGE_HAMMER:
					if _gap_left <= 0.0 and _ring_time >= _hammer_target_time() - 0.02:
						_bot_tap()
				STAGE_QUENCH:
					if not _quench_done:
						if _quench_heat > _quench_target + 0.01:
							Input.action_press(ACT_PRIMARY)
						else:
							Input.action_release(ACT_PRIMARY)
				STAGE_FINISH:
					_bot_steer(_path_point(_finish_progress()) - _cursor)
		_:
			pass
	if _state != State.PLAY or _stage != STAGE_FINISH:
		_bot_steer(Vector2.ZERO)


func _bot_tap() -> void:
	Input.action_press(ACT_PRIMARY)
	_bot_tap_down = true


func _bot_steer(offset: Vector2) -> void:
	var push: Vector2 = (offset / 12.0).limit_length(1.0)
	_bot_axis(ACT_LEFT, -push.x)
	_bot_axis(ACT_RIGHT, push.x)
	_bot_axis(ACT_UP, -push.y)
	_bot_axis(ACT_DOWN, push.y)


func _bot_axis(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


# --- Juice ------------------------------------------------------------------

func _emit_sparks(at: Vector2, count: int, color: Color) -> void:
	var juice: Dictionary = _cfg["juice"]
	for i: int in count:
		var angle: float = randf_range(-PI, 0.0)
		var speed: float = float(juice["spark_speed"]) * randf_range(0.3, 1.0)
		_sparks.append({
			"pos": at,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"age": 0.0,
			"color": color,
		})


func _add_pop(text: String, at: Vector2, size: int, color: Color) -> void:
	_pops.append({ "text": text, "pos": at, "size": size, "color": color, "age": 0.0 })


func _update_juice(delta: float) -> void:
	var juice: Dictionary = _cfg["juice"]
	var gravity: float = float(juice["spark_gravity"])
	var spark_life: float = float(juice["spark_seconds"])
	for spark: Dictionary in _sparks:
		spark["age"] = float(spark["age"]) + delta
		var velocity: Vector2 = spark["vel"]
		velocity.y += gravity * delta
		spark["vel"] = velocity
		spark["pos"] = Vector2(spark["pos"]) + velocity * delta
	_sparks = _sparks.filter(func(spark: Dictionary) -> bool: return float(spark["age"]) < spark_life)
	var pop_life: float = float(juice["pop_seconds"])
	for pop: Dictionary in _pops:
		pop["age"] = float(pop["age"]) + delta
	_pops = _pops.filter(func(pop: Dictionary) -> bool: return float(pop["age"]) < pop_life)
	_shake = maxf(_shake - float(juice["shake_decay_per_second"]) * delta, 0.0)
	_pump_anim = maxf(_pump_anim - delta * 5.0, 0.0)
	_hammer_anim = maxf(_hammer_anim - delta * 6.0, 0.0)
	var origin: Vector2 = (get_viewport_rect().size - DESIGN_SIZE) * 0.5
	position = origin + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(-3000.0, -3000.0, 7152.0, 6648.0), COL_BG)
	if _cfg.is_empty():
		return
	_draw_header()
	match _state:
		State.READY:
			_draw_ready()
		State.INTRO, State.PLAY:
			_draw_stage_scene()
			_draw_instruction()
		State.RESULT:
			_draw_result()
	_draw_juice()


func _text(text: String, center: Vector2, size: int, color: Color, width: float = 1000.0) -> void:
	draw_string(_font, Vector2(center.x - width * 0.5, center.y), text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


func _box(rect: Rect2, fill: Color, outline: Color = COL_OUTLINE, width: float = 4.0) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, width)


func _heat_color(heat: float) -> Color:
	var scaled: float = clampf(heat, 0.0, 1.0) * float(HEAT_RAMP.size() - 1)
	var index: int = mini(int(scaled), HEAT_RAMP.size() - 2)
	return HEAT_RAMP[index].lerp(HEAT_RAMP[index + 1], scaled - float(index))


func _draw_header() -> void:
	draw_string(_font, Vector2(24.0, 36.0), str(_cfg["text"]["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, COL_AMBER)
	for i: int in STAGE_NAMES.size():
		var rect: Rect2 = Rect2(286.0 + float(i) * 156.0, 16.0, 146.0, 40.0)
		var active: bool = _state != State.READY and _state != State.RESULT and i == _stage
		var label: String = "%d %s" % [i + 1, STAGE_NAMES[i]]
		var fill: Color = COL_PANEL
		var ink: Color = COL_CREAM
		if i < _stage_scores.size():
			fill = COL_AMBER.darkened(0.45)
			label = "%s %d" % [STAGE_NAMES[i], roundi(_stage_scores[i])]
		if active:
			fill = COL_ORANGE
			ink = COL_OUTLINE
		_box(rect, fill, COL_OUTLINE, 3.0)
		_text(label, Vector2(rect.get_center().x, rect.position.y + 27.0), 18, ink, rect.size.x)


func _draw_ready() -> void:
	_draw_anvil(Vector2(576.0, 330.0), 1.4, true)
	_text(str(_cfg["text"]["ready"]), Vector2(576.0, 500.0), 24, COL_CREAM)
	_text(str(_cfg["text"]["start_prompt"]), Vector2(576.0, 560.0), 30, COL_ORANGE)


func _draw_instruction() -> void:
	var instructions: Array = _cfg["text"]["instructions"]
	if _state == State.INTRO:
		_text("Stage %d: %s" % [_stage + 1, STAGE_NAMES[_stage]], Vector2(576.0, 110.0), 40, COL_ORANGE)
	_text(str(instructions[_stage]), Vector2(576.0, 612.0), 22, COL_CREAM)


func _draw_stage_scene() -> void:
	match _stage:
		STAGE_HEAT:
			_draw_heat()
		STAGE_HAMMER:
			_draw_hammer()
		STAGE_QUENCH:
			_draw_quench()
		STAGE_FINISH:
			_draw_finish()


func _draw_time_bar(remaining: float) -> void:
	draw_rect(Rect2(326.0, 76.0, 500.0, 8.0), COL_PANEL)
	draw_rect(Rect2(326.0, 76.0, 500.0 * clampf(remaining, 0.0, 1.0), 8.0), COL_AMBER)


func _draw_heat() -> void:
	var heat: Dictionary = _cfg["heat"]
	_draw_time_bar(1.0 - _stage_time / float(heat["duration_seconds"]) if _state == State.PLAY else 1.0)
	# Bellows (squash on each pump) and furnace.
	var squash: float = 30.0 * _pump_anim
	draw_colored_polygon(PackedVector2Array([
		Vector2(170.0, 395.0 + squash), Vector2(300.0, 425.0), Vector2(300.0, 445.0), Vector2(170.0, 475.0 - squash),
	]), COL_AMBER.darkened(0.3))
	_box(Rect2(300.0, 180.0, 300.0, 320.0), COL_PANEL)
	draw_circle(Vector2(450.0, 350.0), 100.0, COL_OUTLINE)
	var glow: float = 0.25 + 0.75 * _needle
	draw_circle(Vector2(450.0, 350.0), 40.0 + 55.0 * _needle, _heat_color(glow))
	draw_circle(Vector2(450.0, 350.0), 12.0 + 40.0 * _needle, COL_GLOW)
	# Temperature gauge.
	var gauge: Rect2 = Rect2(760.0, 150.0, 56.0, 340.0)
	_box(gauge, COL_OUTLINE, COL_CREAM, 3.0)
	var zone_width: float = float(heat["zone_width"])
	var zone_top: float = gauge.end.y - clampf(_zone_center + zone_width * 0.5, 0.0, 1.0) * gauge.size.y
	var zone_bottom: float = gauge.end.y - clampf(_zone_center - zone_width * 0.5, 0.0, 1.0) * gauge.size.y
	var in_zone: bool = _heat_needle_in_zone()
	draw_rect(Rect2(gauge.position.x, zone_top, gauge.size.x, zone_bottom - zone_top), COL_GLOW if in_zone else COL_AMBER.darkened(0.2))
	var needle_y: float = gauge.end.y - _needle * gauge.size.y
	draw_line(Vector2(gauge.position.x - 10.0, needle_y), Vector2(gauge.end.x + 10.0, needle_y), COL_ORANGE, 6.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(gauge.position.x - 34.0, needle_y - 12.0), Vector2(gauge.position.x - 10.0, needle_y), Vector2(gauge.position.x - 34.0, needle_y + 12.0),
	]), COL_ORANGE)
	_text("TEMP", Vector2(788.0, 138.0), 18, COL_CREAM, 200.0)
	var percent: int = roundi(100.0 * _heat_in_zone / maxf(_heat_counted, 0.001))
	_text("In zone %d%%" % percent, Vector2(788.0, 524.0), 20, COL_GLOW if in_zone else COL_CREAM, 240.0)


func _draw_anvil(center: Vector2, scale_factor: float, with_face: bool) -> void:
	var s: float = scale_factor
	var body: PackedVector2Array = PackedVector2Array([
		center + Vector2(-220.0, -40.0) * s, center + Vector2(140.0, -40.0) * s, center + Vector2(140.0, 0.0) * s,
		center + Vector2(60.0, 0.0) * s, center + Vector2(60.0, 50.0) * s, center + Vector2(100.0, 50.0) * s,
		center + Vector2(100.0, 80.0) * s, center + Vector2(-100.0, 80.0) * s, center + Vector2(-100.0, 50.0) * s,
		center + Vector2(-60.0, 50.0) * s, center + Vector2(-60.0, 0.0) * s, center + Vector2(-140.0, -8.0) * s,
	])
	draw_colored_polygon(body, COL_IRON)
	var outline: PackedVector2Array = body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, COL_OUTLINE, 4.0)
	if with_face:
		for side: float in [-1.0, 1.0]:
			var eye: Vector2 = center + Vector2(side * 26.0, 22.0) * s
			draw_circle(eye, 9.0 * s, COL_GLOW)
			draw_circle(eye + Vector2(0.0, 2.0) * s, 4.0 * s, COL_OUTLINE)
		draw_line(center + Vector2(-48.0, 4.0) * s, center + Vector2(-10.0, 12.0) * s, COL_OUTLINE, 4.0)
		draw_line(center + Vector2(48.0, 4.0) * s, center + Vector2(10.0, 12.0) * s, COL_OUTLINE, 4.0)


func _draw_hammer() -> void:
	var hammer: Dictionary = _cfg["hammer"]
	var strikes: int = int(hammer["strikes"])
	_draw_anvil(Vector2(576.0, 440.0), 1.0, false)
	draw_rect(Rect2(476.0, 370.0, 200.0, 28.0), _heat_color(0.8))
	draw_rect(Rect2(476.0, 370.0, 200.0, 28.0), COL_GLOW, false, 3.0)
	var strike_point: Vector2 = Vector2(576.0, 384.0)
	var target_radius: float = 46.0
	draw_arc(strike_point, target_radius, 0.0, TAU, 64, COL_CREAM, 5.0)
	if _state == State.PLAY and _gap_left <= 0.0 and _strike_index < strikes:
		var progress: float = _ring_time / _hammer_target_time()
		var ring_scale: float = lerpf(float(hammer["ring_start_scale"]), 1.0, progress)
		if ring_scale > 0.05:
			draw_arc(strike_point, target_radius * ring_scale, 0.0, TAU, 64, COL_ORANGE, 7.0)
	# Hammer head drops on each strike.
	var drop: float = 150.0 * _hammer_anim
	_box(Rect2(540.0, 150.0 + drop, 72.0, 46.0), COL_IRON)
	draw_rect(Rect2(612.0, 164.0 + drop, 120.0, 16.0), COL_AMBER.darkened(0.4))
	for i: int in strikes:
		var pip: Vector2 = Vector2(576.0 + (float(i) - float(strikes - 1) * 0.5) * 40.0, 566.0)
		var fill: Color = COL_PANEL
		if i < _strike_scores.size():
			fill = HEAT_RAMP[1].lerp(COL_GLOW, _strike_scores[i] / 100.0)
		draw_circle(pip, 13.0, COL_OUTLINE)
		draw_circle(pip, 10.0, fill)


func _draw_blade(center: Vector2, color: Color) -> void:
	draw_rect(Rect2(center.x - 160.0, center.y - 7.0, 54.0, 14.0), COL_AMBER.darkened(0.5))
	var blade: PackedVector2Array = PackedVector2Array([
		center + Vector2(-110.0, -13.0), center + Vector2(80.0, -13.0), center + Vector2(125.0, 0.0),
		center + Vector2(80.0, 13.0), center + Vector2(-110.0, 13.0),
	])
	draw_colored_polygon(blade, color)
	var outline: PackedVector2Array = blade.duplicate()
	outline.append(blade[0])
	draw_polyline(outline, COL_OUTLINE, 3.0)


func _draw_quench() -> void:
	# Fire on the left, trough on the right.
	_box(Rect2(170.0, 250.0, 220.0, 250.0), COL_PANEL)
	draw_circle(Vector2(280.0, 380.0), 80.0, _heat_color(0.75))
	draw_circle(Vector2(280.0, 380.0), 42.0, COL_GLOW)
	_box(Rect2(640.0, 430.0, 330.0, 96.0), COL_PANEL)
	draw_rect(Rect2(652.0, 444.0, 306.0, 70.0), COL_WATER)
	# Target colour swatch.
	_text("Plunge at this colour", Vector2(805.0, 150.0), 20, COL_CREAM, 400.0)
	_box(Rect2(735.0, 164.0, 140.0, 44.0), _heat_color(_quench_target), COL_CREAM, 3.0)
	if _quench_done:
		_draw_blade(Vector2(805.0, 478.0), _heat_color(_quench_heat * 0.25))
		draw_rect(Rect2(652.0, 444.0, 306.0, 70.0), Color(COL_WATER, 0.55))
	elif _quench_holding:
		_draw_blade(Vector2(805.0, 320.0), _heat_color(_quench_heat))
	else:
		_draw_blade(Vector2(330.0, 380.0), _heat_color(1.0))


func _draw_finish() -> void:
	var finish: Dictionary = _cfg["finish"]
	var progress: float = _finish_progress() if _state == State.PLAY else 0.0
	_draw_time_bar(1.0 - progress)
	var body: PackedVector2Array = _path.duplicate()
	body.append(Vector2(930.0, 450.0))
	body.append(Vector2(220.0, 450.0))
	draw_colored_polygon(body, COL_IRON)
	draw_polyline(_path, COL_CREAM.darkened(0.35), 5.0)
	var done_count: int = int(progress * float(_path.size() - 1)) + 1
	if done_count >= 2:
		draw_polyline(_path.slice(0, done_count), COL_GLOW, 6.0)
	var mark: Vector2 = _path_point(progress)
	draw_arc(mark, float(finish["perfect_radius"]) + 8.0, 0.0, TAU, 32, COL_AMBER, 4.0)
	draw_circle(_cursor, 15.0, COL_OUTLINE)
	draw_circle(_cursor, 11.0, COL_ORANGE.lerp(COL_GLOW, _finish_last_quality))
	var percent: int = roundi(100.0 * _finish_quality_sum / maxf(_stage_time, 0.001)) if _state == State.PLAY else 0
	_text("Steadiness %d%%" % percent, Vector2(576.0, 530.0), 20, COL_CREAM, 400.0)


func _draw_result() -> void:
	_text("Score %d / 100" % roundi(_final_score), Vector2(576.0, 270.0), 34, COL_CREAM)
	var parts: PackedStringArray = PackedStringArray()
	for i: int in _stage_scores.size():
		parts.append("%s %d" % [STAGE_NAMES[i], roundi(_stage_scores[i])])
	_text("   ".join(parts), Vector2(576.0, 312.0), 20, COL_AMBER)
	if _result_frames > 50 or _pops.is_empty():
		_text(_tier.to_upper(), Vector2(576.0, 190.0), 76, COL_ORANGE)
	_draw_anvil(Vector2(250.0, 450.0), 0.8, true)
	_box(Rect2(400.0, 380.0, 640.0, 120.0), COL_CREAM)
	draw_colored_polygon(PackedVector2Array([Vector2(402.0, 420.0), Vector2(366.0, 440.0), Vector2(402.0, 456.0)]), COL_CREAM)
	draw_multiline_string(_font, Vector2(424.0, 426.0), _quip, HORIZONTAL_ALIGNMENT_LEFT, 592.0, 22, 3, COL_OUTLINE)
	_text(str(_cfg["text"]["retry_prompt"]), Vector2(576.0, 590.0), 28, COL_ORANGE)


func _draw_juice() -> void:
	var spark_life: float = float(_cfg["juice"]["spark_seconds"])
	for spark: Dictionary in _sparks:
		var fade: float = 1.0 - float(spark["age"]) / spark_life
		draw_circle(Vector2(spark["pos"]), 2.0 + 3.0 * fade, Color(Color(spark["color"]), fade))
	var pop_life: float = float(_cfg["juice"]["pop_seconds"])
	for pop: Dictionary in _pops:
		var age: float = float(pop["age"])
		var grow: float = 0.6 + 0.4 * ease(clampf(age / 0.18, 0.0, 1.0), 0.3)
		if age < 0.18:
			grow *= 1.0 + 0.25 * sin(age / 0.18 * PI)
		var alpha: float = clampf((pop_life - age) / 0.25, 0.0, 1.0)
		var size: int = int(float(pop["size"]) * grow)
		var at: Vector2 = Vector2(pop["pos"]) - Vector2(500.0, 0.0)
		draw_string_outline(_font, at, str(pop["text"]), HORIZONTAL_ALIGNMENT_CENTER, 1000.0, size, 8, Color(COL_OUTLINE, alpha))
		draw_string(_font, at, str(pop["text"]), HORIZONTAL_ALIGNMENT_CENTER, 1000.0, size, Color(Color(pop["color"]), alpha))
