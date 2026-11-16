class_name BladeTraceStage
extends ForgeStage
## Forge stage 1, "Blade Trace": guide a weighted hammer along the item's
## outline at your own pace and strike at each ring. The skill is a steady
## hand. Score = line accuracy and strike accuracy, minus a penalty for going
## past par time. Tuning: `stages.blade_trace` in data/forging_stages.json.

# How finely the line is searched for the point nearest the hammer (pixels).
const _SEARCH_STEP: float = 2.0
# The hammer cannot leave this area of the screen.
const _PLAY_AREA_MIN: Vector2 = Vector2(40.0, 110.0)
const _PLAY_AREA_MAX: Vector2 = Vector2(1112.0, 560.0)

var _points: PackedVector2Array = PackedVector2Array()
var _lengths: PackedFloat32Array = PackedFloat32Array()  # distance along the line at each point
var _total_length: float = 0.0
var _ring_distances: Array[float] = []  # distance along the line of each strike ring
var _cursor: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
var _progress: float = 0.0
var _quality_sum: float = 0.0
var _line_distance: float = 0.0
var _strike_scores: Array[float] = []


## See [method ForgeStage.stage_state].
func stage_state() -> Dictionary:
	return {
		"timer": snappedf(_time, 0.01),
		"traced_percent": roundi(100.0 * _progress / maxf(_total_length, 1.0)),
		"line_accuracy": roundi(_line_accuracy()),
		"strikes_done": _strike_scores.size(),
		"strikes_needed": _ring_distances.size(),
		"strike_scores": _rounded(_strike_scores),
	}


func _stage_begin() -> void:
	_points.clear()
	_lengths.clear()
	_total_length = 0.0
	var raw: Array = _cfg.get("points", [])
	for i: int in raw.size():
		var pair: Array = raw[i]
		var point: Vector2 = Vector2(float(pair[0]), float(pair[1]))
		if i > 0:
			_total_length += _points[i - 1].distance_to(point)
		_points.append(point)
		_lengths.append(_total_length)
	_ring_distances.clear()
	for index: Variant in _cfg.get("strike_points", []):
		_ring_distances.append(_lengths[int(index)])
	_ring_distances.sort()
	_cursor = _points[0]
	_velocity = Vector2.ZERO
	_progress = 0.0
	_quality_sum = 0.0
	_line_distance = 0.0
	_strike_scores.clear()


func _stage_update(delta: float) -> void:
	var move: Vector2 = Input.get_vector(ACT_LEFT, ACT_RIGHT, ACT_UP, ACT_DOWN)
	_velocity = _velocity.move_toward(move * float(_cfg["max_speed"]), float(_cfg["acceleration"]) * delta)
	_cursor = (_cursor + _velocity * delta).clamp(_PLAY_AREA_MIN, _PLAY_AREA_MAX)
	# Find the closest point of the line just ahead of where tracing has reached.
	var reach: float = minf(_progress + float(_cfg["look_ahead"]), _gate_distance())
	var best_distance: float = _progress
	_line_distance = _cursor.distance_to(_line_point(_progress))
	var probe: float = _progress + _SEARCH_STEP
	while probe <= reach + _SEARCH_STEP:
		var candidate: float = minf(probe, reach)
		var gap: float = _cursor.distance_to(_line_point(candidate))
		if gap < _line_distance:
			_line_distance = gap
			best_distance = candidate
		probe += _SEARCH_STEP
	if best_distance > _progress and _line_distance <= float(_cfg["off_radius"]):
		var quality: float = _line_quality()
		_quality_sum += quality * (best_distance - _progress)
		_progress = best_distance
		if is_strong(quality * 100.0) and randf() < 0.5:
			emit_sparks(_cursor, 1, COL_AMBER)
	if Input.is_action_just_pressed(ACT_PRIMARY) and _at_gate():
		_strike()
	var all_struck: bool = _strike_scores.size() >= _ring_distances.size()
	if (all_struck and _progress >= _total_length - 0.5) or _time >= float(_cfg["time_limit_seconds"]):
		_finish(_final_score())


func _strike() -> void:
	var ring: Vector2 = _line_point(_gate_distance())
	var gap: float = _cursor.distance_to(ring)
	var miss_radius: float = float(_cfg["strike_miss_radius"])
	if gap > miss_radius:
		return  # Too far from the ring to count as a strike at all.
	var score: float = window_score(gap, float(_cfg["strike_perfect_radius"]), miss_radius)
	# The last few pixels up to the ring count as traced at the current accuracy.
	_quality_sum += _line_quality() * (_gate_distance() - _progress)
	_progress = _gate_distance()
	_strike_scores.append(score)
	var power: float = score / 100.0
	_shake(power)
	emit_sparks(ring, _sparks_for(power), COL_AMBER)
	add_pop(_rating_for(score), ring + Vector2(0.0, -40.0), 34, COL_GLOW if is_strong(score) else COL_CREAM)
	if _audio != null:
		_audio.play("hit", 0.8 + 0.4 * power)


func _final_score() -> float:
	var path_score: float = 100.0 * _quality_sum / maxf(_total_length, 1.0)
	var strike_score: float = _mean(_strike_scores, _ring_distances.size())
	var late_penalty: float = maxf(_time - float(_cfg["par_seconds"]), 0.0) * float(_cfg["late_penalty_per_second"])
	return path_score * float(_cfg["path_weight"]) + strike_score * float(_cfg["strike_weight"]) - late_penalty


func _line_quality() -> float:
	return window_score(_line_distance, float(_cfg["perfect_radius"]), float(_cfg["miss_radius"])) / 100.0


func _line_accuracy() -> float:
	return 100.0 * _quality_sum / maxf(_progress, 0.001)


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
	if _strike_scores.size() < _ring_distances.size():
		return _ring_distances[_strike_scores.size()]
	return _total_length


## True when tracing is close enough to the next ring that a strike is allowed.
func _at_gate() -> bool:
	var slack: float = float(_cfg["strike_miss_radius"])
	return _strike_scores.size() < _ring_distances.size() and _progress >= _gate_distance() - slack


func _stage_bot() -> void:
	var target: Vector2 = _line_point(minf(_progress + 14.0, _gate_distance()))
	var offset: Vector2 = target - _cursor
	if _at_gate() and offset.length() < 5.0 and _velocity.length() < 60.0:
		_bot_tap(ACT_PRIMARY)
	# Aim for a speed the hammer can still brake from before reaching the target.
	var wanted_speed: float = sqrt(2.0 * float(_cfg["acceleration"]) * offset.length()) * 0.7
	var push: float = clampf(wanted_speed / float(_cfg["max_speed"]), 0.3, 1.0) if offset.length() > 1.5 else 0.0
	var steer: Vector2 = offset.normalized() * push
	_bot_axis(ACT_LEFT, -steer.x)
	_bot_axis(ACT_RIGHT, steer.x)
	_bot_axis(ACT_UP, -steer.y)
	_bot_axis(ACT_DOWN, steer.y)


func _bot_axis(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


func _stage_draw() -> void:
	if _points.is_empty():
		return
	_draw_time_bar()
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
	for i: int in _ring_distances.size():
		var ring: Vector2 = _line_point(_ring_distances[i])
		if i < _strike_scores.size():
			draw_circle(ring, 13.0, COL_OUTLINE)
			draw_circle(ring, 10.0, COL_MISS.lerp(COL_GLOW, _strike_scores[i] / 100.0))
		elif i == _strike_scores.size():
			draw_arc(ring, 16.0 + (5.0 * pulse if _at_gate() else 0.0), 0.0, TAU, 32, COL_ORANGE, 5.0)
		else:
			draw_arc(ring, 14.0, 0.0, TAU, 32, COL_AMBER.darkened(0.3), 4.0)
	# The hammer.
	var on_line: bool = _line_distance <= float(_cfg["off_radius"])
	draw_circle(_cursor, 13.0, COL_OUTLINE)
	draw_circle(_cursor, 9.0, COL_ORANGE if on_line else COL_MISS)
	if _at_gate():
		draw_text_centered(_txt("stage_strike"), Vector2(576.0, 500.0), 26, COL_ORANGE, 400.0)
	draw_text_centered(_txt("status") % [roundi(_line_accuracy()), _strike_scores.size(), _ring_distances.size()],
		Vector2(576.0, 540.0), 20, COL_CREAM, 800.0)
	draw_text_centered(_txt("instruction"), Vector2(576.0, 620.0), 18, COL_CREAM, 1130.0)


## Time bar: amber until par, red once the late penalty starts.
func _draw_time_bar() -> void:
	var limit: float = float(_cfg["time_limit_seconds"])
	var par: float = float(_cfg["par_seconds"])
	draw_rect(Rect2(326.0, 76.0, 500.0, 8.0), COL_PANEL)
	draw_rect(Rect2(326.0, 76.0, 500.0 * clampf(_time / limit, 0.0, 1.0), 8.0), COL_AMBER if _time <= par else COL_MISS)
	var par_x: float = 326.0 + 500.0 * par / limit
	draw_line(Vector2(par_x, 68.0), Vector2(par_x, 92.0), COL_CREAM, 3.0)
	draw_text_centered(_txt("par"), Vector2(par_x, 112.0), 14, COL_CREAM, 80.0)
	draw_text_centered("%d s" % int(_time), Vector2(870.0, 86.0), 18, COL_CREAM, 80.0)
