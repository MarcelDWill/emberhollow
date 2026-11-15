# PROTOTYPE - NOT FOR PRODUCTION
extends Node2D
## Forging prototype 2: "One Heat".
##
## One continuous screen instead of four stages. Hold the secondary button to
## heat the bar in the fire, let go to bring it to the anvil, and strike with
## the primary button while the heat sits in the sweet band. Every strike cools
## the bar, so the skill is judgement: one more strike, or back to the fire?
## Standalone: tuning comes from forge_one_heat.json, input from the Input Map.
## Run with `-- --autoplay` to let a bot play a full forge (headless checks).

const PROTOTYPE_NAME: String = "forge_one_heat"
const CONFIG_PATH: String = "res://prototypes/forge_one_heat/forge_one_heat.json"
const DESIGN_SIZE: Vector2 = Vector2(1152.0, 648.0)
const AUTOPLAY_RESULT_FRAMES: int = 90

const ACT_PRIMARY: StringName = &"p1_forge_primary"
const ACT_SECONDARY: StringName = &"p1_forge_secondary"

const COL_BG: Color = Color("2a1c17")
const COL_PANEL: Color = Color("3f2b22")
const COL_OUTLINE: Color = Color("150d0a")
const COL_CREAM: Color = Color("f6e9cf")
const COL_AMBER: Color = Color("e8a33d")
const COL_ORANGE: Color = Color("ff7a1f")
const COL_GLOW: Color = Color("fff3c4")
const COL_IRON: Color = Color("6f6763")
const HEAT_RAMP: Array[Color] = [
	Color("3a302d"), Color("8f1d14"), Color("e2501a"), Color("ffa62b"), Color("fff3c4"),
]

const FIRE_POINT: Vector2 = Vector2(300.0, 372.0)
const ANVIL_POINT: Vector2 = Vector2(690.0, 386.0)

enum State { READY, PLAY, RESULT }

var _cfg: Dictionary = {}
var _font: Font
var _autoplay: bool = false
var _bot_tap_down: bool = false
var _result_frames: int = 0

var _state: State = State.READY
var _time: float = 0.0
var _heat: float = 0.0
var _bar_slide: float = 0.0  # 0 = in the fire, 1 = on the anvil
var _fire_time: float = 0.0
var _cooldown: float = 0.0
var _strike_scores: Array[float] = []
var _final_score: float = 0.0
var _tier: String = ""
var _quip: String = ""
var _hammer_anim: float = 0.0

var _sparks: Array[Dictionary] = []
var _pops: Array[Dictionary] = []
var _shake: float = 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_autoplay = OS.get_cmdline_user_args().has("--autoplay")
	if not _load_config():
		return
	_reset_run()


## Returns the current prototype state as JSON text (the project's test hook).
func debug_state_text() -> String:
	var needed: int = int(_cfg["forge"]["strikes_needed"]) if not _cfg.is_empty() else 0
	var state: Dictionary = {
		"prototype": PROTOTYPE_NAME,
		"state": State.keys()[_state],
		"stage": _stage_name(),
		"timer": snappedf(_time, 0.01),
		"heat": snappedf(_heat, 0.01),
		"strikes_done": _strike_scores.size(),
		"strikes_needed": needed,
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


func _reset_run() -> void:
	_state = State.READY
	_time = 0.0
	_heat = float(_cfg["forge"]["start_heat"])
	_bar_slide = 0.0
	_fire_time = 0.0
	_cooldown = 0.0
	_strike_scores.clear()
	_final_score = 0.0
	_tier = ""
	_quip = ""
	_result_frames = 0
	_pops.clear()
	_sparks.clear()
	_log_state()


func _in_fire() -> bool:
	return _bar_slide <= 0.05


func _on_anvil() -> bool:
	return _bar_slide >= 0.95


func _stage_name() -> String:
	if _cfg.is_empty():
		return ""
	return str(_cfg["text"]["stage_fire"]) if _bar_slide < 0.5 else str(_cfg["text"]["stage_anvil"])


func _update_play(delta: float) -> void:
	var forge: Dictionary = _cfg["forge"]
	_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	var wants_fire: bool = Input.is_action_pressed(ACT_SECONDARY)
	_bar_slide = move_toward(_bar_slide, 0.0 if wants_fire else 1.0, delta / float(forge["move_seconds"]))
	if _in_fire():
		_fire_time += delta
		_heat += (float(forge["fire_heat_per_second"]) + float(forge["fire_roar_per_second"]) * _fire_time) * delta
		if randf() < 0.3:
			_emit_sparks(FIRE_POINT + Vector2(0.0, -30.0), 1, COL_ORANGE)
		if _heat >= float(forge["burn_heat"]):
			_heat = float(forge["burn_reset_heat"])
			_fire_time = 0.0
			_shake = float(_cfg["juice"]["shake_pixels"])
			_add_pop(str(_cfg["text"]["scorched"]), FIRE_POINT + Vector2(0.0, -130.0), 40, COL_ORANGE)
			_record_strike(0.0)
	else:
		_fire_time = 0.0
		_heat -= float(forge["cool_per_second"]) * delta
	_heat = clampf(_heat, 0.0, 1.0)
	if _state == State.PLAY and Input.is_action_just_pressed(ACT_PRIMARY) and _on_anvil() and _cooldown <= 0.0:
		_strike()
	if _state == State.PLAY and _time >= float(forge["time_limit_seconds"]):
		_show_result()


func _strike() -> void:
	var forge: Dictionary = _cfg["forge"]
	var juice: Dictionary = _cfg["juice"]
	var error: float = absf(_heat - float(forge["sweet_heat"]))
	var score: float = _window_score(error, float(forge["perfect_window"]), float(forge["miss_window"]))
	_heat = maxf(_heat - float(forge["strike_cool"]), 0.0)
	_cooldown = float(forge["strike_cooldown_seconds"])
	_hammer_anim = 1.0
	var power: float = score / 100.0
	_shake = float(juice["shake_pixels"]) * power
	_emit_sparks(ANVIL_POINT, int(float(juice["sparks_on_perfect"]) * power), COL_AMBER)
	_add_pop(_rating_for(score), ANVIL_POINT + Vector2(0.0, -150.0), 40, COL_GLOW if score >= 65.0 else COL_CREAM)
	_record_strike(score)


func _record_strike(score: float) -> void:
	_strike_scores.append(score)
	if _strike_scores.size() >= int(_cfg["forge"]["strikes_needed"]):
		_show_result()


func _show_result() -> void:
	var total: float = 0.0
	for score: float in _strike_scores:
		total += score
	_final_score = total / float(_cfg["forge"]["strikes_needed"])
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
		Input.action_release(ACT_SECONDARY)
		return
	var forge: Dictionary = _cfg["forge"]
	var sweet: float = float(forge["sweet_heat"])
	var heating: bool = Input.is_action_pressed(ACT_SECONDARY)
	if heating and _heat >= sweet + 0.05:
		Input.action_release(ACT_SECONDARY)
	elif not heating and _heat < sweet - 0.07:
		Input.action_press(ACT_SECONDARY)
	elif not heating and _on_anvil() and _cooldown <= 0.0 and _heat <= sweet + 0.04:
		_bot_tap()
		if _strike_scores.size() % 6 == 5:
			print("[state] ", debug_state_text())


func _bot_tap() -> void:
	Input.action_press(ACT_PRIMARY)
	_bot_tap_down = true


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
	_hammer_anim = maxf(_hammer_anim - delta * 6.0, 0.0)
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
			_text(str(_cfg["text"]["ready"]), Vector2(576.0, 110.0), 24, COL_CREAM)
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


func _heat_color(heat: float) -> Color:
	var scaled: float = clampf(heat, 0.0, 1.0) * float(HEAT_RAMP.size() - 1)
	var index: int = mini(int(scaled), HEAT_RAMP.size() - 2)
	return HEAT_RAMP[index].lerp(HEAT_RAMP[index + 1], scaled - float(index))


func _draw_header() -> void:
	var forge: Dictionary = _cfg["forge"]
	var labels: Array[String] = [str(_cfg["text"]["stage_fire"]), str(_cfg["text"]["stage_anvil"])]
	for i: int in labels.size():
		var rect: Rect2 = Rect2(366.0 + float(i) * 176.0, 16.0, 166.0, 40.0)
		var active: bool = (i == 0) == (_bar_slide < 0.5)
		_box(rect, COL_ORANGE if active else COL_PANEL, COL_OUTLINE, 3.0)
		_text(labels[i], Vector2(rect.get_center().x, rect.position.y + 27.0), 18, COL_OUTLINE if active else COL_CREAM, rect.size.x)
	var limit: float = float(forge["time_limit_seconds"])
	draw_rect(Rect2(326.0, 76.0, 500.0, 8.0), COL_PANEL)
	draw_rect(Rect2(326.0, 76.0, 500.0 * clampf(1.0 - _time / limit, 0.0, 1.0), 8.0), COL_AMBER)
	_text("%d s" % ceili(maxf(limit - _time, 0.0)), Vector2(870.0, 86.0), 18, COL_CREAM, 80.0)


func _draw_instruction() -> void:
	_text(str(_cfg["text"]["instruction"]), Vector2(576.0, 630.0), 19, COL_CREAM, 1120.0)


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


func _draw_scene() -> void:
	var forge: Dictionary = _cfg["forge"]
	# Furnace.
	_box(Rect2(150.0, 220.0, 300.0, 290.0), COL_PANEL)
	draw_circle(FIRE_POINT, 96.0, COL_OUTLINE)
	var roar: float = clampf(_fire_time * 0.5, 0.0, 1.0) if _in_fire() else 0.0
	draw_circle(FIRE_POINT, 70.0 + 18.0 * roar, _heat_color(0.6 + 0.2 * roar))
	draw_circle(FIRE_POINT, 34.0 + 14.0 * roar, COL_GLOW)
	# Anvil and hammer.
	_draw_anvil(Vector2(690.0, 440.0), 1.0, false)
	var drop: float = 150.0 * _hammer_anim
	_box(Rect2(654.0, 150.0 + drop, 72.0, 46.0), COL_IRON)
	draw_rect(Rect2(726.0, 164.0 + drop, 120.0, 16.0), COL_AMBER.darkened(0.4))
	# The bar slides between fire and anvil; its colour is its heat.
	var bar_center: Vector2 = FIRE_POINT.lerp(ANVIL_POINT, _bar_slide)
	var bar: Rect2 = Rect2(bar_center - Vector2(90.0, 13.0), Vector2(180.0, 26.0))
	draw_rect(bar, _heat_color(_heat))
	draw_rect(bar, COL_OUTLINE, false, 3.0)
	# Heat gauge with the sweet band and the burn line.
	var gauge: Rect2 = Rect2(980.0, 150.0, 56.0, 340.0)
	_box(gauge, COL_OUTLINE, COL_CREAM, 3.0)
	var sweet: float = float(forge["sweet_heat"])
	var miss: float = float(forge["miss_window"])
	var perfect: float = float(forge["perfect_window"])
	var wide_top: float = gauge.end.y - clampf(sweet + miss, 0.0, 1.0) * gauge.size.y
	var wide_bottom: float = gauge.end.y - clampf(sweet - miss, 0.0, 1.0) * gauge.size.y
	draw_rect(Rect2(gauge.position.x, wide_top, gauge.size.x, wide_bottom - wide_top), COL_AMBER.darkened(0.55))
	var band_top: float = gauge.end.y - (sweet + perfect) * gauge.size.y
	var in_band: bool = absf(_heat - sweet) <= perfect
	draw_rect(Rect2(gauge.position.x, band_top, gauge.size.x, perfect * 2.0 * gauge.size.y), COL_GLOW if in_band else COL_AMBER)
	var burn_y: float = gauge.end.y - float(forge["burn_heat"]) * gauge.size.y
	draw_line(Vector2(gauge.position.x, burn_y), Vector2(gauge.end.x, burn_y), HEAT_RAMP[1], 5.0)
	var needle_y: float = gauge.end.y - _heat * gauge.size.y
	draw_line(Vector2(gauge.position.x - 10.0, needle_y), Vector2(gauge.end.x + 10.0, needle_y), COL_ORANGE, 6.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(gauge.position.x - 34.0, needle_y - 12.0), Vector2(gauge.position.x - 10.0, needle_y), Vector2(gauge.position.x - 34.0, needle_y + 12.0),
	]), COL_ORANGE)
	_text("HEAT", Vector2(1008.0, 138.0), 18, COL_CREAM, 200.0)
	# One pip per strike needed.
	var needed: int = int(forge["strikes_needed"])
	for i: int in needed:
		var pip: Vector2 = Vector2(576.0 + (float(i) - float(needed - 1) * 0.5) * 34.0, 556.0)
		var fill: Color = COL_PANEL
		if i < _strike_scores.size():
			fill = HEAT_RAMP[1].lerp(COL_GLOW, _strike_scores[i] / 100.0)
		draw_circle(pip, 13.0, COL_OUTLINE)
		draw_circle(pip, 10.0, fill)
	_text("Strikes %d / %d" % [_strike_scores.size(), needed], Vector2(576.0, 596.0), 16, COL_AMBER, 400.0)


func _draw_result() -> void:
	var needed: int = int(_cfg["forge"]["strikes_needed"])
	_text("Score %d / 100" % roundi(_final_score), Vector2(576.0, 270.0), 34, COL_CREAM)
	_text("%d of %d strikes landed in %d seconds" % [_strike_scores.size(), needed, roundi(_time)], Vector2(576.0, 312.0), 20, COL_AMBER)
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
