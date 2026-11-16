class_name ForgeCanvas
extends Node2D
## Shared placeholder-art drawing for the forge: the palette, text and box
## helpers, the anvil, and the "juice" (sparks and pop-in text). The forge
## screen and every forging stage extend this so they look like one scene.
## Colours and layout are placeholder art (design/game-brief.md, "Art
## direction"); how the juice behaves comes from data/forging_stages.json.

## The forge is laid out for this size and centred in larger windows.
const DESIGN_SIZE: Vector2 = Vector2(1152.0, 648.0)

const COL_BG: Color = Color("2a1c17")
const COL_PANEL: Color = Color("3f2b22")
const COL_OUTLINE: Color = Color("150d0a")
const COL_CREAM: Color = Color("f6e9cf")
const COL_AMBER: Color = Color("e8a33d")
const COL_ORANGE: Color = Color("ff7a1f")
const COL_GLOW: Color = Color("fff3c4")
const COL_IRON: Color = Color("6f6763")
const COL_MISS: Color = Color("8f1d14")
const HEAT_RAMP: Array[Color] = [
	Color("3a302d"), Color("8f1d14"), Color("e2501a"), Color("ffa62b"), Color("fff3c4"),
]

# Pop-in text animation shape (seconds). Purely visual.
const _POP_IN_SECONDS: float = 0.18
const _POP_FADE_SECONDS: float = 0.25

var _font: Font
var _juice: Dictionary = {}
var _sparks: Array[Dictionary] = []
var _pops: Array[Dictionary] = []


## Call once before drawing. [param juice] is the `juice` block of
## data/forging_stages.json.
func init_canvas(juice: Dictionary) -> void:
	_font = ThemeDB.fallback_font
	_juice = juice


## Score from 100 (error inside [param perfect]) falling to 0 (at [param miss]).
static func window_score(error: float, perfect: float, miss: float) -> float:
	if error <= perfect:
		return 100.0
	if miss <= perfect:
		return 0.0
	return clampf(remap(error, perfect, miss, 100.0, 0.0), 0.0, 100.0)


## True when [param score] counts as a strong hit (brighter feedback).
func is_strong(score: float) -> bool:
	return score >= float(_juice.get("strong_min_score", 0.0))


## Draws [param text] centred on [param center].
func draw_text_centered(text: String, center: Vector2, size: int, color: Color, width: float = 1000.0) -> void:
	draw_string(_font, Vector2(center.x - width * 0.5, center.y), text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


## Draws a filled box with an outline.
func draw_box(rect: Rect2, fill: Color, outline: Color = COL_OUTLINE, width: float = 4.0) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, width)


## Colour of metal at [param heat] (0 cold to 1 white-hot).
func heat_color(heat: float) -> Color:
	var scaled: float = clampf(heat, 0.0, 1.0) * float(HEAT_RAMP.size() - 1)
	var index: int = mini(int(scaled), HEAT_RAMP.size() - 2)
	return HEAT_RAMP[index].lerp(HEAT_RAMP[index + 1], scaled - float(index))


## Draws the anvil. [param with_face] adds the ghost ancestor's eyes and brows.
func draw_anvil(center: Vector2, s: float, with_face: bool) -> void:
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


## Draws a cream speech bubble holding [param text], with a tail on its left.
func draw_speech_bubble(rect: Rect2, text: String, size: int) -> void:
	draw_box(rect, COL_CREAM)
	var mid: float = rect.position.y + rect.size.y * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(rect.position.x + 2.0, mid - 18.0), Vector2(rect.position.x - 34.0, mid), Vector2(rect.position.x + 2.0, mid + 18.0),
	]), COL_CREAM)
	draw_multiline_string(_font, rect.position + Vector2(24.0, 18.0 + float(size)), text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 48.0, size, 4, COL_OUTLINE)


## Throws [param count] sparks up from [param at].
func emit_sparks(at: Vector2, count: int, color: Color) -> void:
	for i: int in count:
		var angle: float = randf_range(-PI, 0.0)
		var speed: float = float(_juice.get("spark_speed", 0.0)) * randf_range(0.3, 1.0)
		_sparks.append({
			"pos": at,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"age": 0.0,
			"color": color,
		})


## Shows [param text] popping in at [param at], then fading.
func add_pop(text: String, at: Vector2, size: int, color: Color) -> void:
	_pops.append({ "text": text, "pos": at, "size": size, "color": color, "age": 0.0 })


## Removes all sparks and pop-in text.
func clear_juice() -> void:
	_sparks.clear()
	_pops.clear()


## True while any pop-in text is still on screen.
func has_pops() -> bool:
	return not _pops.is_empty()


## Advances sparks and pop-in text. Call every frame.
func update_juice(delta: float) -> void:
	var gravity: float = float(_juice.get("spark_gravity", 0.0))
	var spark_life: float = float(_juice.get("spark_seconds", 0.0))
	for spark: Dictionary in _sparks:
		spark["age"] = float(spark["age"]) + delta
		var velocity: Vector2 = spark["vel"]
		velocity.y += gravity * delta
		spark["vel"] = velocity
		spark["pos"] = Vector2(spark["pos"]) + velocity * delta
	_sparks = _sparks.filter(func(spark: Dictionary) -> bool: return float(spark["age"]) < spark_life)
	var pop_life: float = float(_juice.get("pop_seconds", 0.0))
	for pop: Dictionary in _pops:
		pop["age"] = float(pop["age"]) + delta
	_pops = _pops.filter(func(pop: Dictionary) -> bool: return float(pop["age"]) < pop_life)


## Draws sparks and pop-in text. Call last in `_draw`.
func draw_juice() -> void:
	var spark_life: float = maxf(float(_juice.get("spark_seconds", 0.0)), 0.001)
	for spark: Dictionary in _sparks:
		var fade: float = 1.0 - float(spark["age"]) / spark_life
		draw_circle(Vector2(spark["pos"]), 2.0 + 3.0 * fade, Color(Color(spark["color"]), fade))
	var pop_life: float = float(_juice.get("pop_seconds", 0.0))
	for pop: Dictionary in _pops:
		var age: float = float(pop["age"])
		var grow: float = 0.6 + 0.4 * ease(clampf(age / _POP_IN_SECONDS, 0.0, 1.0), 0.3)
		if age < _POP_IN_SECONDS:
			grow *= 1.0 + 0.25 * sin(age / _POP_IN_SECONDS * PI)
		var alpha: float = clampf((pop_life - age) / _POP_FADE_SECONDS, 0.0, 1.0)
		var size: int = int(float(pop["size"]) * grow)
		var at: Vector2 = Vector2(pop["pos"]) - Vector2(500.0, 0.0)
		draw_string_outline(_font, at, str(pop["text"]), HORIZONTAL_ALIGNMENT_CENTER, 1000.0, size, 8, Color(COL_OUTLINE, alpha))
		draw_string(_font, at, str(pop["text"]), HORIZONTAL_ALIGNMENT_CENTER, 1000.0, size, Color(Color(pop["color"]), alpha))
