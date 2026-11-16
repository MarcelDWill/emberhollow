class_name ForgeStage
extends ForgeCanvas
## Base class for one stage of a forge job (design/game-brief.md, "Forging").
##
## The forge screen creates a stage, calls [method setup] then [method begin],
## and waits for [signal finished]. A stage only reads its own tuning (already
## scaled for difficulty) and the Input Map; it never touches game state.
## Subclasses override the `_stage_*` methods.

## Emitted once, when the stage is over. [param score] is 0 to 100.
signal finished(score: float)
## Asks the forge screen to shake by [param pixels].
signal shake_requested(pixels: float)

const ACT_PRIMARY: StringName = &"p1_forge_primary"
const ACT_SECONDARY: StringName = &"p1_forge_secondary"
const ACT_LEFT: StringName = &"p1_move_left"
const ACT_RIGHT: StringName = &"p1_move_right"
const ACT_UP: StringName = &"p1_move_up"
const ACT_DOWN: StringName = &"p1_move_down"
const ALL_ACTIONS: Array[StringName] = [ACT_PRIMARY, ACT_SECONDARY, ACT_LEFT, ACT_RIGHT, ACT_UP, ACT_DOWN]

var _cfg: Dictionary = {}
var _ratings: Array = []
var _text: Dictionary = {}
var _rating_text: Dictionary = {}
var _audio: ForgeAudio
var _autoplay: bool = false
var _running: bool = false
var _time: float = 0.0
var _bot_taps: Array[StringName] = []


## Prepares the stage. [param config] is this stage's tuning with difficulty
## applied; [param shared] holds the `ratings` and `juice` blocks; [param text]
## this stage's on-screen text; [param rating_text] rating id -> label.
## [param autoplay] lets a bot play, for automated checks.
func setup(config: Dictionary, shared: Dictionary, text: Dictionary, rating_text: Dictionary, audio: ForgeAudio, autoplay: bool) -> void:
	_cfg = config
	_ratings = shared.get("ratings", [])
	_text = text
	_rating_text = rating_text
	_audio = audio
	_autoplay = autoplay
	init_canvas(shared.get("juice", {}))


## Starts play.
func begin() -> void:
	_time = 0.0
	_running = true
	_stage_begin()


## The stage's current state as plain data, for `debug_state_text()`.
func stage_state() -> Dictionary:
	return {}


func _process(delta: float) -> void:
	if _running:
		if _autoplay:
			_release_bot_taps()
			_stage_bot()
		_time += delta
		_stage_update(delta)
	update_juice(delta)
	queue_redraw()


func _draw() -> void:
	_stage_draw()
	draw_juice()


func _exit_tree() -> void:
	if _autoplay:
		for action: StringName in ALL_ACTIONS:
			Input.action_release(action)


## Called once when play starts.
func _stage_begin() -> void:
	pass


## Called every frame while the stage is running.
func _stage_update(_delta: float) -> void:
	pass


## Called every frame before the update when a bot is playing.
func _stage_bot() -> void:
	pass


## Draws the stage.
func _stage_draw() -> void:
	pass


## Ends the stage with [param score] (clamped to 0 to 100).
func _finish(score: float) -> void:
	if not _running:
		return
	_running = false
	if _autoplay:
		for action: StringName in ALL_ACTIONS:
			Input.action_release(action)
	finished.emit(clampf(score, 0.0, 100.0))


## Label of the rating [param score] earns ("PERFECT", "GOOD", ...).
func _rating_for(score: float) -> String:
	for rating: Variant in _ratings:
		if score >= float(rating.get("min_score", 0.0)):
			return str(_rating_text.get(str(rating.get("id", "")), ""))
	return ""


## Lowest score of the rating called [param rating_id].
func _rating_min(rating_id: String) -> float:
	for rating: Variant in _ratings:
		if str(rating.get("id", "")) == rating_id:
			return float(rating.get("min_score", 0.0))
	return 0.0


func _shake(power: float) -> void:
	shake_requested.emit(float(_juice.get("shake_pixels", 0.0)) * power)


func _sparks_for(power: float) -> int:
	return int(float(_juice.get("sparks_on_perfect", 0.0)) * power)


func _txt(key: String) -> String:
	return str(_text.get(key, ""))


func _mean(values: Array[float], count: int) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(maxi(count, 1))


func _rounded(values: Array[float]) -> Array[int]:
	var out: Array[int] = []
	for value: float in values:
		out.append(roundi(value))
	return out


func _bot_tap(action: StringName) -> void:
	Input.action_press(action)
	_bot_taps.append(action)


func _release_bot_taps() -> void:
	for action: StringName in _bot_taps:
		Input.action_release(action)
	_bot_taps.clear()
