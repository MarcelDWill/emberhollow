class_name OneHeatStage
extends ForgeStage
## Forge stage 3, "One Heat": hold the second button to heat the bar in the
## fire, let go to bring it to the anvil, and strike with the main button while
## the heat sits in the sweet band. Every strike cools the bar, so the skill is
## judgement: one more strike, or back to the fire? Score = the average strike
## quality over the strikes needed. Tuning: `stages.one_heat` in
## data/forging_stages.json (its `polish` block drives the feedback).

const _FIRE_POINT: Vector2 = Vector2(300.0, 372.0)
const _ANVIL_POINT: Vector2 = Vector2(690.0, 386.0)
const _GAUGE: Rect2 = Rect2(980.0, 150.0, 56.0, 340.0)
const _BARK_RECT: Rect2 = Rect2(396.0, 96.0, 420.0, 46.0)
# Animation speeds (per second). Purely visual.
const _HAMMER_RECOVER: float = 6.0
const _IMPACT_FADE: float = 3.5
const _SQUASH_RECOVER: float = 9.0
const _EMBER_SECONDS: float = 1.1
const _EMBER_RISE: float = 90.0

var _heat: float = 0.0
var _shown_heat: float = 0.0  # the needle follows the heat smoothly
var _bar_slide: float = 0.0  # 0 = in the fire, 1 = on the anvil
var _fire_time: float = 0.0
var _cooldown: float = 0.0
var _strike_scores: Array[float] = []
var _streak: int = 0
var _best_streak: int = 0
var _was_in_band: bool = false
var _last_warning_second: int = -1

var _hammer_anim: float = 0.0
var _impact: float = 0.0
var _impact_strong: bool = false
var _squash: float = 0.0
var _streak_pulse: float = 0.0
var _embers: Array[Dictionary] = []
var _ember_debt: float = 0.0
var _bark: String = ""
var _bark_left: float = 0.0


## See [method ForgeStage.stage_state].
func stage_state() -> Dictionary:
	return {
		"timer": snappedf(_time, 0.01),
		"place": "fire" if _bar_slide < 0.5 else "anvil",
		"heat": snappedf(_heat, 0.01),
		"strikes_done": _strike_scores.size(),
		"strikes_needed": int(_cfg.get("strikes_needed", 0)),
		"strike_scores": _rounded(_strike_scores),
		"streak": _streak,
		"best_streak": _best_streak,
	}


func _stage_begin() -> void:
	_heat = float(_cfg["start_heat"])
	_shown_heat = _heat
	_bar_slide = 0.0
	_fire_time = 0.0
	_cooldown = 0.0
	_strike_scores.clear()
	_streak = 0
	_best_streak = 0
	_was_in_band = false
	_last_warning_second = -1
	_embers.clear()
	_bark_left = 0.0


func _stage_update(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	var wants_fire: bool = Input.is_action_pressed(ACT_SECONDARY)
	_bar_slide = move_toward(_bar_slide, 0.0 if wants_fire else 1.0, delta / float(_cfg["move_seconds"]))
	if _in_fire():
		_fire_time += delta
		_heat += (float(_cfg["fire_heat_per_second"]) + float(_cfg["fire_roar_per_second"]) * _fire_time) * delta
		if _heat >= float(_cfg["burn_heat"]):
			_scorch()
	else:
		_fire_time = 0.0
		_heat -= float(_cfg["cool_per_second"]) * delta
	_heat = clampf(_heat, 0.0, 1.0)
	if not _running:
		return
	if Input.is_action_just_pressed(ACT_PRIMARY) and _on_anvil() and _cooldown <= 0.0:
		_strike()
	if not _running:
		return
	_update_cues(delta)
	if _time >= float(_cfg["time_limit_seconds"]):
		_finish(_final_score())


func _scorch() -> void:
	_heat = float(_cfg["burn_reset_heat"])
	_fire_time = 0.0
	_streak = 0
	_shake(1.0)
	add_pop(_txt("scorched"), _FIRE_POINT + Vector2(0.0, -130.0), 40, COL_ORANGE)
	emit_sparks(_FIRE_POINT, _sparks_for(0.6), COL_MISS)
	if _audio != null:
		_audio.play("scorch")
	_say("scorch")
	_record_strike(0.0)


func _strike() -> void:
	var error: float = absf(_heat - float(_cfg["sweet_heat"]))
	var score: float = window_score(error, float(_cfg["perfect_window"]), float(_cfg["miss_window"]))
	_heat = maxf(_heat - float(_cfg["strike_cool"]), 0.0)
	_cooldown = float(_cfg["strike_cooldown_seconds"])
	var power: float = score / 100.0
	var strong: bool = is_strong(score)
	_hammer_anim = 1.0
	_impact = 1.0
	_impact_strong = strong
	_squash = power
	if strong:
		_streak += 1
		_best_streak = maxi(_best_streak, _streak)
		_streak_pulse = 1.0
		if _streak % maxi(int(_polish("streak_bark_every")), 1) == 0:
			_say("streak")
	else:
		_streak = 0
		if score <= 0.0:
			_say("cold")
	_shake(power)
	emit_sparks(_ANVIL_POINT, _sparks_for(power), COL_GLOW if score >= _rating_min("perfect") else COL_AMBER)
	add_pop(_rating_for(score), _ANVIL_POINT + Vector2(0.0, -150.0), 40, COL_GLOW if strong else COL_CREAM)
	if _audio != null:
		# The clang rises a little with each strike of a streak.
		var pitch: float = 1.0 + 0.03 * float(mini(_streak, 12))
		if score >= _rating_min("perfect"):
			_audio.play("strike_perfect", pitch)
		elif strong:
			_audio.play("strike_good", pitch)
		else:
			_audio.play("strike_weak")
	_record_strike(score)


func _record_strike(score: float) -> void:
	_strike_scores.append(score)
	if _strike_scores.size() >= int(_cfg["strikes_needed"]):
		_finish(_final_score())


func _final_score() -> float:
	return _mean(_strike_scores, int(_cfg["strikes_needed"]))


## Sound cues that tell the player what to do without watching the gauge.
func _update_cues(delta: float) -> void:
	var in_band: bool = _on_anvil() and absf(_heat - float(_cfg["sweet_heat"])) <= float(_cfg["perfect_window"])
	if in_band and not _was_in_band and _audio != null:
		_audio.play("in_band")
	_was_in_band = in_band
	var left: float = float(_cfg["time_limit_seconds"]) - _time
	if left <= _polish("low_time_seconds"):
		var second: int = ceili(left)
		if second != _last_warning_second:
			_last_warning_second = second
			if _audio != null:
				_audio.play("tick")
	# Embers rise from the fire while the bar is heating.
	if _in_fire():
		_ember_debt += _polish("embers_per_second") * delta
		while _ember_debt >= 1.0:
			_ember_debt -= 1.0
			_embers.append({
				"pos": _FIRE_POINT + Vector2(randf_range(-60.0, 60.0), randf_range(-40.0, 10.0)),
				"drift": randf_range(-25.0, 25.0),
				"age": 0.0,
			})


func _process(delta: float) -> void:
	super(delta)
	# Feedback keeps animating after the stage ends, until the forge removes it.
	_shown_heat = lerpf(_shown_heat, _heat, clampf(_polish("needle_smoothing") * delta, 0.0, 1.0))
	_hammer_anim = maxf(_hammer_anim - delta * _HAMMER_RECOVER, 0.0)
	_impact = maxf(_impact - delta * _IMPACT_FADE, 0.0)
	_squash = maxf(_squash - delta * _SQUASH_RECOVER, 0.0)
	_streak_pulse = maxf(_streak_pulse - delta * _IMPACT_FADE, 0.0)
	_bark_left = maxf(_bark_left - delta, 0.0)
	for ember: Dictionary in _embers:
		ember["age"] = float(ember["age"]) + delta
		ember["pos"] = Vector2(ember["pos"]) + Vector2(float(ember["drift"]), -_EMBER_RISE) * delta
	_embers = _embers.filter(func(ember: Dictionary) -> bool: return float(ember["age"]) < _EMBER_SECONDS)


func _polish(key: String) -> float:
	var polish: Dictionary = _cfg.get("polish", {})
	return float(polish.get(key, 0.0))


## Shows one of the anvil's short remarks of [param kind] above the scene.
func _say(kind: String) -> void:
	var barks: Dictionary = _text.get("barks", {})
	var lines: Array = barks.get(kind, [])
	if lines.is_empty():
		return
	_bark = str(lines[randi() % lines.size()])
	_bark_left = _polish("bark_seconds")


func _in_fire() -> bool:
	return _bar_slide <= 0.05


func _on_anvil() -> bool:
	return _bar_slide >= 0.95


func _stage_bot() -> void:
	var sweet: float = float(_cfg["sweet_heat"])
	var perfect: float = float(_cfg["perfect_window"])
	var heating: bool = Input.is_action_pressed(ACT_SECONDARY)
	if heating and _heat >= sweet + perfect:
		Input.action_release(ACT_SECONDARY)
	elif not heating and _heat < sweet - perfect:
		Input.action_press(ACT_SECONDARY)
	elif not heating and _on_anvil() and _cooldown <= 0.0 and _heat <= sweet + perfect:
		_bot_tap(ACT_PRIMARY)


func _stage_draw() -> void:
	if _cfg.is_empty():
		return
	_draw_time_bar()
	_draw_furnace()
	_draw_anvil_and_hammer()
	_draw_bar()
	_draw_gauge()
	_draw_strikes()
	if _bark_left > 0.0:
		draw_speech_bubble(_BARK_RECT, _bark, 17)
	draw_text_centered(_txt("instruction"), Vector2(576.0, 630.0), 19, COL_CREAM, 1120.0)


func _draw_time_bar() -> void:
	var limit: float = float(_cfg["time_limit_seconds"])
	var left: float = maxf(limit - _time, 0.0)
	var low: bool = left <= _polish("low_time_seconds")
	var blink: float = 0.5 + 0.5 * sin(_time * 14.0) if low else 0.0
	draw_rect(Rect2(326.0, 76.0, 500.0, 8.0), COL_PANEL)
	draw_rect(Rect2(326.0, 76.0, 500.0 * clampf(left / limit, 0.0, 1.0), 8.0), COL_MISS.lerp(COL_ORANGE, blink) if low else COL_AMBER)
	draw_text_centered(_txt("seconds") % ceili(left), Vector2(870.0, 86.0), 22 if low else 18, COL_ORANGE if low else COL_CREAM, 80.0)


func _draw_furnace() -> void:
	draw_box(Rect2(150.0, 220.0, 300.0, 290.0), COL_PANEL)
	draw_circle(_FIRE_POINT, 96.0, COL_OUTLINE)
	var roar: float = clampf(_fire_time * 0.5, 0.0, 1.0) if _in_fire() else 0.0
	var flicker: float = 3.0 * sin(_time * 23.0) + 2.0 * sin(_time * 37.0)
	draw_circle(_FIRE_POINT, 70.0 + 18.0 * roar + flicker, heat_color(0.6 + 0.2 * roar))
	draw_circle(_FIRE_POINT, 34.0 + 14.0 * roar + flicker * 0.5, COL_GLOW)
	for ember: Dictionary in _embers:
		var fade: float = 1.0 - float(ember["age"]) / _EMBER_SECONDS
		draw_circle(Vector2(ember["pos"]), 1.5 + 2.5 * fade, Color(COL_AMBER, fade))
	var in_fire: bool = _bar_slide < 0.5
	draw_text_centered(_txt("stage_fire"), Vector2(300.0, 204.0), 18, COL_ORANGE if in_fire else COL_CREAM.darkened(0.4), 300.0)


func _draw_anvil_and_hammer() -> void:
	draw_anvil(Vector2(690.0, 440.0), 1.0, false)
	var on_anvil: bool = _bar_slide >= 0.5
	draw_text_centered(_txt("stage_anvil"), Vector2(690.0, 544.0), 18, COL_ORANGE if on_anvil else COL_CREAM.darkened(0.4), 300.0)
	# Hammer: drops on a strike, then lifts back.
	var drop: float = 150.0 * _hammer_anim
	draw_box(Rect2(654.0, 150.0 + drop, 72.0, 46.0), COL_IRON)
	draw_rect(Rect2(726.0, 164.0 + drop, 120.0, 16.0), COL_AMBER.darkened(0.4))
	# Impact ring bursts from the anvil face on a strike.
	if _impact > 0.0:
		var ring_color: Color = COL_GLOW if _impact_strong else COL_CREAM.darkened(0.3)
		draw_arc(_ANVIL_POINT, 30.0 + 120.0 * (1.0 - _impact), 0.0, TAU, 48, Color(ring_color, _impact), 6.0 * _impact + 1.0)
	if _streak >= 2:
		var size: int = 22 + mini(_streak, 12) + int(8.0 * _streak_pulse)
		draw_text_centered(_txt("streak") % _streak, Vector2(1004.0, 594.0), size, COL_GLOW, 280.0)


## The bar slides between fire and anvil. Its colour and glow are its heat.
func _draw_bar() -> void:
	var center: Vector2 = _FIRE_POINT.lerp(_ANVIL_POINT, _bar_slide)
	var sweet: float = float(_cfg["sweet_heat"])
	var in_band: bool = absf(_heat - sweet) <= float(_cfg["perfect_window"])
	# Halo: hotter metal throws more light. The forge glow is the brightest thing on screen.
	var glow: float = clampf((_heat - 0.3) / 0.7, 0.0, 1.0)
	if glow > 0.0:
		var halo: Color = heat_color(_heat)
		draw_circle(center, 60.0 + 50.0 * glow, Color(halo, 0.10 * glow))
		draw_circle(center, 40.0 + 30.0 * glow, Color(halo, 0.16 * glow))
	# A strike flattens the bar for a moment.
	var half: Vector2 = Vector2(90.0 + 14.0 * _squash, 13.0 - 5.0 * _squash)
	var bar: Rect2 = Rect2(center - half, half * 2.0)
	draw_rect(bar, heat_color(_heat))
	draw_rect(bar, COL_OUTLINE, false, 3.0)
	if in_band and _on_anvil():
		# Ready to strike: the bar pulses bright.
		var pulse: float = 0.5 + 0.5 * sin(_time * 16.0)
		draw_rect(bar.grow(4.0 + 3.0 * pulse), Color(COL_GLOW, 0.5 + 0.5 * pulse), false, 4.0)
		draw_text_centered(_txt("strike_now"), center + Vector2(0.0, -34.0), 24, COL_GLOW, 300.0)


## Heat gauge with the sweet band and the burn line.
func _draw_gauge() -> void:
	var sweet: float = float(_cfg["sweet_heat"])
	var miss: float = float(_cfg["miss_window"])
	var perfect: float = float(_cfg["perfect_window"])
	var burn: float = float(_cfg["burn_heat"])
	var too_hot: bool = _in_fire() and _heat >= burn - _polish("burn_warning_margin")
	var jitter: Vector2 = Vector2(randf_range(-2.0, 2.0), 0.0) if too_hot else Vector2.ZERO
	var gauge: Rect2 = Rect2(_GAUGE.position + jitter, _GAUGE.size)
	draw_box(gauge, COL_OUTLINE, COL_MISS if too_hot else COL_CREAM, 3.0)
	var wide_top: float = gauge.end.y - clampf(sweet + miss, 0.0, 1.0) * gauge.size.y
	var wide_bottom: float = gauge.end.y - clampf(sweet - miss, 0.0, 1.0) * gauge.size.y
	draw_rect(Rect2(gauge.position.x, wide_top, gauge.size.x, wide_bottom - wide_top), COL_AMBER.darkened(0.55))
	var band_top: float = gauge.end.y - (sweet + perfect) * gauge.size.y
	var in_band: bool = absf(_heat - sweet) <= perfect
	draw_rect(Rect2(gauge.position.x, band_top, gauge.size.x, perfect * 2.0 * gauge.size.y), COL_GLOW if in_band else COL_AMBER)
	var burn_y: float = gauge.end.y - burn * gauge.size.y
	draw_line(Vector2(gauge.position.x, burn_y), Vector2(gauge.end.x, burn_y), COL_MISS, 5.0)
	var needle_y: float = gauge.end.y - _shown_heat * gauge.size.y
	var needle: Color = COL_MISS.lerp(COL_ORANGE, 0.5 + 0.5 * sin(_time * 30.0)) if too_hot else COL_ORANGE
	draw_line(Vector2(gauge.position.x - 10.0, needle_y), Vector2(gauge.end.x + 10.0, needle_y), needle, 6.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(gauge.position.x - 34.0, needle_y - 12.0), Vector2(gauge.position.x - 10.0, needle_y), Vector2(gauge.position.x - 34.0, needle_y + 12.0),
	]), needle)
	draw_text_centered(_txt("heat"), Vector2(1008.0, 138.0), 18, COL_CREAM, 200.0)
	if too_hot:
		draw_text_centered(_txt("too_hot"), Vector2(1008.0, 520.0), 22, COL_ORANGE, 200.0)


## One pip per strike needed, coloured by how good the strike was.
func _draw_strikes() -> void:
	var needed: int = int(_cfg["strikes_needed"])
	for i: int in needed:
		var pip: Vector2 = Vector2(540.0 + (float(i) - float(needed - 1) * 0.5) * 26.0, 584.0)
		var fill: Color = COL_PANEL
		if i < _strike_scores.size():
			fill = COL_MISS.lerp(COL_GLOW, _strike_scores[i] / 100.0)
		draw_circle(pip, 10.0, COL_OUTLINE)
		draw_circle(pip, 7.5, fill)
	draw_text_centered(_txt("strikes") % [_strike_scores.size(), needed], Vector2(120.0, 590.0), 16, COL_AMBER, 220.0)
