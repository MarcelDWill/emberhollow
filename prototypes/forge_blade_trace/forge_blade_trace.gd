# PROTOTYPE - NOT FOR PRODUCTION
extends Node2D
## Forging prototype 4: "Blade Trace".
##
## Forging as drawing. The item's outline is on screen; the player guides the
## hammer along it with the stick / WASD at their own pace and strikes with the
## primary button at each ring. The hammer has weight (it speeds up and slows
## down), so the skill is a steady hand: staying on the line and settling on
## each ring before striking. Going slower is more accurate but costs time.
## Standalone: the outline and tuning come from forge_blade_trace.json, input
## from the Input Map. Run with `-- --autoplay` for a bot run (headless checks).

const PROTOTYPE_NAME: String = "forge_blade_trace"
const CONFIG_PATH: String = "res://prototypes/forge_blade_trace/forge_blade_trace.json"
const DESIGN_SIZE: Vector2 = Vector2(1152.0, 648.0)
const AUTOPLAY_RESULT_FRAMES: int = 90
const SEARCH_STEP: float = 2.0

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
const COL_MISS: Color = Color("8f1d14")

enum State { READY, PLAY, RESULT }

var _cfg: Dictionary = {}
var _font: Font
var _autoplay: bool = false
var _bot_tap_down: bool = false
var _result_frames: int = 0

var _state: State = State.READY
var _time: float = 0.0
var _points: PackedVector2Array = PackedVector2Array()
var _lengths: PackedFloat32Array = PackedFloat32Array()  # distance along the line at each point
var _total_length: float = 0.0
var _node_distances: Array[float] = []  # distance along the line of each strike ring
var _cursor: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
var _progress: float = 0.0
var _quality_sum: float = 0.0
var _line_distance: float = 0.0
var _strike_scores: Array[float] = []
var _path_score: float = 0.0
var _strike_score: float = 0.0
var _late_penalty: float = 0.0
var _final_score: float = 0.0
var _tier: String = ""
var _quip: String = ""

var _sparks: Array[Dictionary] = []
var _pops: Array[Dictionary] = []
var _shake: float = 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_autoplay = OS.get_cmdline_user_args().has("--autoplay")
	if not _load_config():
		return
	_build_line()
	_reset_run()


## Returns the current prototype state as JSON text (the project's test hook).
func debug_state_text() -> String:
	var state: Dictionary = {
		"prototype": PROTOTYPE_NAME,
		"state": State.keys()[_state],
		"stage": _stage_name(),
		"timer": snappedf(_time, 0.01),
		"traced_percent": roundi(100.0 * _progress / maxf(_total_length, 1.0)),
		"line_accuracy": roundi(_line_accuracy()),
		"strikes_done": _strike_scores.size(),
		"strikes_needed": _node_distances.size(),
		"strike_scores": _rounded(_strike_scores),
		"path_score": roundi(_path_score),
		"strike_score": roundi(_strike_score),
		"late_penalty": roundi(_late_penalty),
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
				_state = State.PLAY
				_log_state()
		State.PLAY:
			_update_play(delta)
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


func _build_line() -> void:
	var trace: Dictionary = _cfg["trace"]
	var raw: Array = trace["points"]
	_points.clear()
	_lengths.clear()
	_total_length = 0.0
	for i: int in raw.size():
		var pair: Array = raw[i]
		var point: Vector2 = Vector2(float(pair[0]), float(pair[1]))
		if i > 0:
			_total_length += _points[i - 1].distance_to(point)
		_points.append(point)
		_lengths.append(_total_length)
	_node_distances.clear()
	for index: Variant in trace["strike_points"]:
		_node_distances.append(_lengths[int(index)])
	_node_distances.sort()


func _reset_run() -> void:
	_state = State.READY
	_time = 0.0
	_cursor = _points[0]
	_velocity = Vector2.ZERO
	_progress = 0.0
	_quality_sum = 0.0
	_line_distance = 0.0
	_strike_scores.clear()
	_path_score = 0.0
	_strike_score = 0.0
	_late_penalty = 0.0
	_final_score = 0.0
	_tier = ""
	_quip = ""
	_result_frames = 0
	_pops.clear()
	_sparks.clear()
	_log_state()


## Point on the line at a given distance from its start.
func _line_point(distance: float) -> Vector2:
	var clamped: float = clampf(distance, 0.0, _total_length)
	for i: int in range(1, _points.size()):
		if clamped <= _lengths[i]:
			var span: float = _lengths[i] - _lengths[i - 1]
			var t: float = (clamped - _lengths[i - 1]) / span if span > 0.0 else 0.0
			return _points[i - 1].lerp(_points[i], t)
	return _points[_points.size() - 1]


## How far along the line tracing may go right now: the next unstruck ring.
func _gate_distance() -> float:
	if _strike_scores.size() < _node_distances.size():
		return _node_distances[_strike_scores.size()]
	return _total_length


func _at_gate() -> bool:
	# Close enough along the line to the next ring that a strike is allowed.
	var slack: float = float(_cfg["trace"]["strike_miss_radius"])
	return _strike_scores.size() < _node_distances.size() and _progress >= _gate_distance() - slack


func _stage_name() -> String:
	if _cfg.is_empty():
		return ""
	return str(_cfg["text"]["stage_strike"]) if _at_gate() else str(_cfg["text"]["stage_trace"])


func _line_accuracy() -> float:
	return 100.0 * _quality_sum / maxf(_progress, 0.001)


func _update_play(delta: float) -> void:
	var trace: Dictionary = _cfg["trace"]
	_time += delta
	var move: Vector2 = Input.get_vector(ACT_LEFT, ACT_RIGHT, ACT_UP, ACT_DOWN)
	_velocity = _velocity.move_toward(move * float(trace["max_speed"]), float(trace["acceleration"]) * delta)
	_cursor += _velocity * delta
	_cursor = _cursor.clamp(Vector2(40.0, 110.0), Vector2(1112.0, 560.0))
	# Find the closest point of the line just ahead of where tracing has reached.
	var gate: float = _gate_distance()
	var reach: float = minf(_progress + float(trace["look_ahead"]), gate)
	var best_distance: float = _progress
	_line_distance = _cursor.distance_to(_line_point(_progress))
	var probe: float = _progress + SEARCH_STEP
	while probe <= reach + SEARCH_STEP:
		var candidate: float = minf(probe, reach)
		var gap: float = _cursor.distance_to(_line_point(candidate))
		if gap < _line_distance:
			_line_distance = gap
			best_distance = candidate
		probe += SEARCH_STEP
	if best_distance > _progress and _line_distance <= float(trace["off_radius"]):
		var quality: float = _window_score(_line_distance, float(trace["perfect_radius"]), float(trace["miss_radius"])) / 100.0
		_quality_sum += quality * (best_distance - _progress)
		_progress = best_distance
		if quality > 0.6 and randf() < 0.5:
			_emit_sparks(_cursor, 1, COL_AMBER)
	if Input.is_action_just_pressed(ACT_PRIMARY) and _at_gate():
		_strike()
	var all_struck: bool = _strike_scores.size() >= _node_distances.size()
	if _state == State.PLAY and all_struck and _progress >= _total_length - 0.5:
		_show_result()
	elif _state == State.PLAY and _time >= float(trace["time_limit_seconds"]):
		_show_result()


func _strike() -> void:
	var trace: Dictionary = _cfg["trace"]
	var juice: Dictionary = _cfg["juice"]
	var ring: Vector2 = _line_point(_gate_distance())
	var gap: float = _cursor.distance_to(ring)
	if gap > float(trace["strike_miss_radius"]):
		return  # Too far from the ring to count as a strike at all.
	var score: float = _window_score(gap, float(trace["strike_perfect_radius"]), float(trace["strike_miss_radius"]))
	# The last few pixels up to the ring count as traced at the current accuracy.
	var quality: float = _window_score(_line_distance, float(trace["perfect_radius"]), float(trace["miss_radius"])) / 100.0
	_quality_sum += quality * (_gate_distance() - _progress)
	_progress = _gate_distance()
	_strike_scores.append(score)
	var power: float = score / 100.0
	_shake = float(juice["shake_pixels"]) * power
	_emit_sparks(ring, int(float(juice["sparks_on_perfect"]) * power), COL_AMBER)
	_add_pop(_rating_for(score), ring + Vector2(0.0, -40.0), 34, COL_GLOW if score >= 65.0 else COL_CREAM)
	_log_state()


func _show_result() -> void:
	var trace: Dictionary = _cfg["trace"]
	_path_score = 100.0 * _quality_sum / _total_length
	var total: float = 0.0
	for score: float in _strike_scores:
		total += score
	_strike_score = total / float(maxi(_node_distances.size(), 1))
	_late_penalty = maxf(_time - float(trace["par_seconds"]), 0.0) * float(trace["late_penalty_per_second"])
	_final_score = clampf(
		_path_score * float(trace["path_weight"]) + _strike_score * float(trace["strike_weight"]) - _late_penalty,
		0.0, 100.0)
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


# --- Autoplay bot (headless checks only) -----------------------------------

func _bot() -> void:
	if _bot_tap_down:
		Input.action_release(ACT_PRIMARY)
		_bot_tap_down = false
	if _state == State.READY:
		_bot_tap()
		return
	if _state != State.PLAY:
		_bot_steer(Vector2.ZERO)
		return
	var trace: Dictionary = _cfg["trace"]
	var target: Vector2 = _line_point(minf(_progress + 14.0, _gate_distance()))
	var offset: Vector2 = target - _cursor
	if _at_gate() and offset.length() < 5.0 and _velocity.length() < 60.0:
		_bot_tap()
	# Aim for a speed the hammer can still brake from before reaching the target.
	var wanted_speed: float = sqrt(2.0 * float(trace["acceleration"]) * offset.length()) * 0.7
	var push: float = clampf(wanted_speed / float(trace["max_speed"]), 0.3, 1.0) if offset.length() > 1.5 else 0.0
	_bot_steer(offset.normalized() * push)


func _bot_tap() -> void:
	Input.action_press(ACT_PRIMARY)
	_bot_tap_down = true


func _bot_steer(push: Vector2) -> void:
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
	var origin: Vector2 = (get_viewport_rect().size - DESIGN_SIZE) * 0.5
	position = origin + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(-3000.0, -3000.0, 7152.0, 6648.0), COL_BG)
	if _cfg.is_empty():
		return
	draw_string(_font, Vector2(24.0, 36.0), str(_cfg["text"]["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, COL_AMBER)
	match _state:
		State.READY:
			_draw_scene()
			_text(str(_cfg["text"]["ready"]), Vector2(576.0, 110.0), 22, COL_CREAM, 1120.0)
			_text(str(_cfg["text"]["start_prompt"]), Vector2(576.0, 160.0), 30, COL_ORANGE)
			_draw_instruction()
		State.PLAY:
			_draw_header()
			_draw_scene()
			_draw_instruction()
		State.RESULT:
			_draw_result()
	_draw_juice()


func _text(text: String, center: Vector2, size: int, color: Color, width: float = 1000.0) -> void:
	draw_string(_font, Vector2(center.x - width * 0.5, center.y), text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


func _box(rect: Rect2, fill: Color, outline: Color = COL_OUTLINE, width: float = 4.0) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, width)


func _draw_header() -> void:
	var trace: Dictionary = _cfg["trace"]
	var labels: Array[String] = [str(_cfg["text"]["stage_trace"]), str(_cfg["text"]["stage_strike"])]
	for i: int in labels.size():
		var rect: Rect2 = Rect2(366.0 + float(i) * 176.0, 16.0, 166.0, 40.0)
		var active: bool = (i == 1) == _at_gate()
		_box(rect, COL_ORANGE if active else COL_PANEL, COL_OUTLINE, 3.0)
		_text(labels[i], Vector2(rect.get_center().x, rect.position.y + 27.0), 18, COL_OUTLINE if active else COL_CREAM, rect.size.x)
	# Time bar: amber until par, red once the late penalty starts.
	var limit: float = float(trace["time_limit_seconds"])
	var par: float = float(trace["par_seconds"])
	draw_rect(Rect2(326.0, 76.0, 500.0, 8.0), COL_PANEL)
	draw_rect(Rect2(326.0, 76.0, 500.0 * clampf(_time / limit, 0.0, 1.0), 8.0), COL_AMBER if _time <= par else COL_MISS)
	var par_x: float = 326.0 + 500.0 * par / limit
	draw_line(Vector2(par_x, 68.0), Vector2(par_x, 92.0), COL_CREAM, 3.0)
	_text("par", Vector2(par_x, 112.0), 14, COL_CREAM, 80.0)
	_text("%d s" % int(_time), Vector2(870.0, 86.0), 18, COL_CREAM, 80.0)


func _draw_instruction() -> void:
	_text(str(_cfg["text"]["instruction"]), Vector2(576.0, 620.0), 18, COL_CREAM, 1130.0)


func _draw_scene() -> void:
	var trace: Dictionary = _cfg["trace"]
	# Forge glow behind the work.
	draw_circle(Vector2(1040.0, 190.0), 46.0, COL_ORANGE)
	draw_circle(Vector2(1040.0, 190.0), 22.0, COL_GLOW)
	# The item silhouette, the line to follow, and the part already traced.
	draw_colored_polygon(_points, COL_IRON.darkened(0.35))
	draw_polyline(_points, COL_CREAM.darkened(0.4), 5.0)
	var traced: PackedVector2Array = PackedVector2Array()
	for i: int in _points.size():
		if _lengths[i] < _progress:
			traced.append(_points[i])
	traced.append(_line_point(_progress))
	if traced.size() >= 2:
		draw_polyline(traced, COL_GLOW, 7.0)
	# Strike rings.
	var pulse: float = 0.5 + 0.5 * sin(_time * 8.0)
	for i: int in _node_distances.size():
		var ring: Vector2 = _line_point(_node_distances[i])
		if i < _strike_scores.size():
			draw_circle(ring, 13.0, COL_OUTLINE)
			draw_circle(ring, 10.0, COL_MISS.lerp(COL_GLOW, _strike_scores[i] / 100.0))
		elif i == _strike_scores.size():
			draw_arc(ring, 16.0 + (5.0 * pulse if _at_gate() else 0.0), 0.0, TAU, 32, COL_ORANGE, 5.0)
		else:
			draw_arc(ring, 14.0, 0.0, TAU, 32, COL_AMBER.darkened(0.3), 4.0)
	# The hammer.
	var on_line: bool = _line_distance <= float(trace["off_radius"])
	draw_circle(_cursor, 13.0, COL_OUTLINE)
	draw_circle(_cursor, 9.0, COL_ORANGE if on_line else COL_MISS)
	_text("Line accuracy %d%%     Strikes %d / %d" % [roundi(_line_accuracy()), _strike_scores.size(), _node_distances.size()],
		Vector2(576.0, 540.0), 20, COL_CREAM, 800.0)


func _draw_result() -> void:
	_text("Score %d / 100" % roundi(_final_score), Vector2(576.0, 270.0), 34, COL_CREAM)
	var summary: String = "Line %d   Strikes %d" % [roundi(_path_score), roundi(_strike_score)]
	if _late_penalty > 0.0:
		summary += "   Late -%d" % roundi(_late_penalty)
	summary += "   (%d seconds)" % roundi(_time)
	_text(summary, Vector2(576.0, 312.0), 20, COL_AMBER)
	if _result_frames > 50 or _pops.is_empty():
		_text(_tier.to_upper(), Vector2(576.0, 190.0), 76, COL_ORANGE)
	_draw_anvil(Vector2(250.0, 450.0), 0.8)
	_box(Rect2(400.0, 380.0, 640.0, 120.0), COL_CREAM)
	draw_colored_polygon(PackedVector2Array([Vector2(402.0, 420.0), Vector2(366.0, 440.0), Vector2(402.0, 456.0)]), COL_CREAM)
	draw_multiline_string(_font, Vector2(424.0, 426.0), _quip, HORIZONTAL_ALIGNMENT_LEFT, 592.0, 22, 3, COL_OUTLINE)
	_text(str(_cfg["text"]["retry_prompt"]), Vector2(576.0, 590.0), 28, COL_ORANGE)


func _draw_anvil(center: Vector2, s: float) -> void:
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
	for side: float in [-1.0, 1.0]:
		var eye: Vector2 = center + Vector2(side * 26.0, 22.0) * s
		draw_circle(eye, 9.0 * s, COL_GLOW)
		draw_circle(eye + Vector2(0.0, 2.0) * s, 4.0 * s, COL_OUTLINE)
	draw_line(center + Vector2(-48.0, 4.0) * s, center + Vector2(-10.0, 12.0) * s, COL_OUTLINE, 4.0)
	draw_line(center + Vector2(48.0, 4.0) * s, center + Vector2(10.0, 12.0) * s, COL_OUTLINE, 4.0)


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
