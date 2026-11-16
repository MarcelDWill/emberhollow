extends ForgeCanvas
## The forge screen: runs one forge job (design/game-brief.md, "Forging").
##
## A job is three stages in a fixed order (Blade Trace, Anvil Song, One Heat).
## Each stage scores 0 to 100; the weighted average is the job's score. The
## score earns a quality tier, but the tier awarded is capped by what the
## player has unlocked (smithing level, quests, blueprints), and gear above the
## player's smithing level is harder to forge. All of that is decided by
## ForgeRules from the JSON files in data/; this script only runs the flow,
## draws it, and announces the result on EventBus.item_forged.
##
## Debug launch arguments (after `--`), for automated checks and tuning:
## `--autoplay` lets a bot play and quits at the end; `--recipe=<id>`,
## `--smithing-level=<n>`, `--quests=<id,id>`, `--blueprints=<id,id>` set up
## the player; `--capture-dir=<folder>` saves screenshots along the way.

const TIERS_PATH: String = "res://data/forging_tiers.json"
const DIFFICULTY_PATH: String = "res://data/forging_difficulty.json"
const STAGES_PATH: String = "res://data/forging_stages.json"
const RECIPES_PATH: String = "res://data/forging_recipes.json"
const TEXT_PATH: String = "res://data/forging_text.json"

const STAGE_SCRIPTS: Dictionary = {
	"blade_trace": preload("res://src/forging/stages/blade_trace_stage.gd"),
	"anvil_song": preload("res://src/forging/stages/anvil_song_stage.gd"),
	"one_heat": preload("res://src/forging/stages/one_heat_stage.gd"),
}

const ACT_PRIMARY: StringName = &"p1_forge_primary"
const ACT_LEFT: StringName = &"p1_move_left"
const ACT_RIGHT: StringName = &"p1_move_right"

# Bot and screenshot timing for automated checks only (seconds / frames).
const _AUTOPLAY_START_SECONDS: float = 1.0
const _AUTOPLAY_RESULT_FRAMES: int = 150
const _CAPTURE_READY_SECONDS: float = 0.5
const _CAPTURE_INTRO_SECONDS: float = 1.2
const _CAPTURE_STAGE_SECONDS: float = 8.0
const _CAPTURE_RESULT_FRAMES: int = 90

## READY: choosing an item. INTRO: a stage's title card. STAGE: a stage is
## being played. STAGE_DONE: its score is shown. RESULT: the finished item.
## Transitions: READY -> INTRO -> STAGE -> STAGE_DONE -> (INTRO | RESULT) -> READY.
enum State { READY, INTRO, STAGE, STAGE_DONE, RESULT }

var _rules: ForgeRules
var _stages_data: Dictionary = {}
var _stage_configs: Dictionary = {}
var _order: Array[String] = []
var _recipes: Array[Dictionary] = []
var _text: Dictionary = {}
var _audio: ForgeAudio
var _ready_ok: bool = false

var _autoplay: bool = false
var _capture_dir: String = ""
var _captured: Dictionary = {}

var _state: State = State.READY
var _state_time: float = 0.0
var _result_frames: int = 0
var _recipe_index: int = 0
var _progress: Dictionary = {}
var _factor: float = 1.0
var _stage_index: int = 0
var _stage: ForgeStage
var _stage_scores: Dictionary = {}
var _final_score: float = 0.0
var _award: Dictionary = {}
var _quip: String = ""
var _shake_pixels: float = 0.0


func _ready() -> void:
	var tiers: Dictionary = JsonData.load_dict(TIERS_PATH)
	var difficulty: Dictionary = JsonData.load_dict(DIFFICULTY_PATH)
	_stages_data = JsonData.load_dict(STAGES_PATH)
	var recipes: Dictionary = JsonData.load_dict(RECIPES_PATH)
	_text = JsonData.load_dict(TEXT_PATH)
	if tiers.is_empty() or difficulty.is_empty() or _stages_data.is_empty() or recipes.is_empty() or _text.is_empty():
		push_error("Forge: a data file is missing or broken, see the errors above.")
		return
	_rules = ForgeRules.new(tiers, difficulty)
	_stage_configs = _stages_data.get("stages", {})
	for stage_id: Variant in _stages_data.get("order", []):
		if STAGE_SCRIPTS.has(str(stage_id)) and _stage_configs.has(str(stage_id)):
			_order.append(str(stage_id))
		else:
			push_error("Forge: unknown stage '%s' in %s" % [stage_id, STAGES_PATH])
	for recipe: Variant in recipes.get("recipes", []):
		if recipe is Dictionary:
			_recipes.append(recipe)
	if _order.is_empty() or _recipes.is_empty() or _rules.tier_count() == 0:
		push_error("Forge: need at least one stage, one recipe and one tier.")
		return
	init_canvas(_stages_data.get("juice", {}))
	RenderingServer.set_default_clear_color(COL_BG)
	_audio = ForgeAudio.new()
	add_child(_audio)
	_audio.setup(_stages_data.get("sounds", {}))
	_apply_debug_args()
	_ready_ok = true
	_enter_ready()


## Returns the forge's current state as JSON text (the project's test hook).
func debug_state_text() -> String:
	var state: Dictionary = {
		"scene": "forge",
		"state": State.keys()[_state],
		"recipe": _recipe_id(),
		"gear_level": _gear_level(),
		"smithing_level": int(_progress.get("smithing_level", 0)),
		"difficulty": snappedf(_factor, 0.01),
		"stage": _order[_stage_index] if _state in [State.INTRO, State.STAGE, State.STAGE_DONE] else "",
		"stage_scores": _rounded_scores(),
	}
	if _stage != null:
		state["stage_state"] = _stage.stage_state()
	if _state == State.RESULT:
		state["final_score"] = int(_award.get("score", 0))
		state["earned_tier"] = str(_award.get("earned_id", ""))
		state["tier"] = str(_award.get("tier_id", ""))
		state["capped"] = bool(_award.get("capped", false))
		state["quip"] = _quip
	return JSON.stringify(state)


func _process(delta: float) -> void:
	if not _ready_ok:
		return
	_state_time += delta
	match _state:
		State.READY:
			_update_ready()
		State.INTRO:
			_capture_once("intro-%s" % _order[_stage_index], _state_time >= _CAPTURE_INTRO_SECONDS)
			if _state_time >= _flow("intro_seconds"):
				_start_stage()
		State.STAGE:
			_capture_once("stage-%s" % _order[_stage_index], _state_time >= _CAPTURE_STAGE_SECONDS)
		State.STAGE_DONE:
			if _state_time >= _flow("stage_done_seconds"):
				_next_stage()
		State.RESULT:
			_update_result()
	update_juice(delta)
	_shake_pixels = maxf(_shake_pixels - float(_juice.get("shake_decay_per_second", 0.0)) * delta, 0.0)
	var origin: Vector2 = (get_viewport_rect().size - DESIGN_SIZE) * 0.5
	position = origin + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_pixels
	queue_redraw()


# --- Flow -------------------------------------------------------------------

func _enter(state: State) -> void:
	_state = state
	_state_time = 0.0
	if _autoplay:
		print("[state] ", debug_state_text())


func _enter_ready() -> void:
	_progress = GameState.forge_progress()
	_factor = _rules.difficulty_factor(_gear_level(), _progress)
	_stage_scores.clear()
	_stage_index = 0
	_award = {}
	_quip = ""
	clear_juice()
	_enter(State.READY)


func _update_ready() -> void:
	_capture_once("ready", _state_time >= _CAPTURE_READY_SECONDS)
	if Input.is_action_just_pressed(ACT_LEFT):
		_choose_recipe(-1)
	elif Input.is_action_just_pressed(ACT_RIGHT):
		_choose_recipe(1)
	if Input.is_action_just_pressed(ACT_PRIMARY) or (_autoplay and _state_time >= _AUTOPLAY_START_SECONDS):
		_enter(State.INTRO)


func _choose_recipe(step: int) -> void:
	_recipe_index = posmod(_recipe_index + step, _recipes.size())
	_factor = _rules.difficulty_factor(_gear_level(), _progress)
	if _audio != null:
		_audio.play("tick")


func _start_stage() -> void:
	var stage_id: String = _order[_stage_index]
	var stage_text: Dictionary = _text.get("stages", {}).get(stage_id, {})
	_stage = STAGE_SCRIPTS[stage_id].new()
	_stage.show_behind_parent = true
	_stage.setup(
		ForgeRules.apply_difficulty(_stage_configs[stage_id], _factor),
		{ "ratings": _stages_data.get("ratings", []), "juice": _juice },
		stage_text, _text.get("ratings", {}), _audio, _autoplay)
	_stage.finished.connect(_on_stage_finished)
	_stage.shake_requested.connect(_on_shake_requested)
	add_child(_stage)
	_stage.begin()
	_enter(State.STAGE)


func _on_stage_finished(score: float) -> void:
	_stage_scores[_order[_stage_index]] = score
	_audio.play("stage_done")
	_enter(State.STAGE_DONE)


func _on_shake_requested(pixels: float) -> void:
	_shake_pixels = maxf(_shake_pixels, pixels)


func _next_stage() -> void:
	if _stage != null:
		_stage.queue_free()
		_stage = null
	_stage_index += 1
	if _stage_index < _order.size():
		_enter(State.INTRO)
	else:
		_stage_index = _order.size() - 1
		_finish_job()


func _finish_job() -> void:
	_final_score = ForgeRules.combine_scores(_stage_scores, _stage_configs)
	_award = _rules.award(_final_score, _progress, _recipes[_recipe_index])
	var lines: Array = _text.get("anvil_lines", {}).get(str(_award["tier_id"]), [])
	if bool(_award["capped"]):
		lines = _text.get("anvil_lines_capped", lines)
	_quip = str(lines[randi() % lines.size()]) if not lines.is_empty() else ""
	_result_frames = 0
	add_pop(_tier_name(str(_award["tier_id"])).to_upper() + "!", Vector2(576.0, 170.0), 76, COL_ORANGE)
	_shake_pixels = float(_juice.get("shake_pixels", 0.0))
	emit_sparks(Vector2(576.0, 170.0), int(_juice.get("sparks_on_perfect", 0)) * 2, COL_AMBER)
	_enter(State.RESULT)
	EventBus.item_forged.emit({
		"recipe_id": _recipe_id(),
		"score": int(_award["score"]),
		"tier_id": str(_award["tier_id"]),
		"earned_tier_id": str(_award["earned_id"]),
		"capped": bool(_award["capped"]),
		"stage_scores": _rounded_scores(),
	})


func _update_result() -> void:
	_result_frames += 1
	_capture_once("result", _result_frames >= _CAPTURE_RESULT_FRAMES)
	if _autoplay:
		if _result_frames == _AUTOPLAY_RESULT_FRAMES:
			# Bot runs can be faster than real time: let the audio thread let go
			# of the last tone before quitting.
			_audio.stop_all()
			OS.delay_msec(300)
			get_tree().quit()
	elif Input.is_action_just_pressed(ACT_PRIMARY):
		_enter_ready()


# --- Helpers ----------------------------------------------------------------

func _flow(key: String) -> float:
	var flow: Dictionary = _stages_data.get("flow", {})
	return float(flow.get(key, 0.0))


func _recipe_id() -> String:
	return str(_recipes[_recipe_index].get("id", "")) if not _recipes.is_empty() else ""


func _gear_level() -> int:
	return int(_recipes[_recipe_index].get("gear_level", 1)) if not _recipes.is_empty() else 1


func _rounded_scores() -> Dictionary:
	var out: Dictionary = {}
	for stage_id: Variant in _stage_scores:
		out[stage_id] = roundi(float(_stage_scores[stage_id]))
	return out


func _label(group: String, id: String) -> String:
	var names: Dictionary = _text.get(group, {})
	return str(names.get(id, id))


func _tier_name(tier_id: String) -> String:
	return _label("tiers", tier_id)


func _stage_name(stage_id: String) -> String:
	var stage_text: Dictionary = _text.get("stages", {}).get(stage_id, {})
	return str(stage_text.get("name", stage_id))


func _t(group: String, key: String) -> String:
	var block: Dictionary = _text.get(group, {})
	return str(block.get(key, ""))


## Turns requirement gaps from ForgeRules into one readable line.
func _gaps_text(gaps: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for gap: Dictionary in gaps:
		match str(gap.get("kind", "")):
			ForgeRules.GAP_SMITHING_LEVEL:
				parts.append(_t("requirements", "smithing_level") % int(gap.get("need", 0)))
			ForgeRules.GAP_QUEST:
				parts.append(_t("requirements", "quest") % _label("quests", str(gap.get("id", ""))))
			ForgeRules.GAP_BLUEPRINT:
				parts.append(_t("requirements", "blueprint") % _label("blueprints", str(gap.get("id", ""))))
			ForgeRules.GAP_NO_BLUEPRINT:
				parts.append(_t("requirements", "no_blueprint"))
	return ", ".join(parts)


func _apply_debug_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var value: String = arg.get_slice("=", 1) if arg.contains("=") else ""
		if arg == "--autoplay":
			_autoplay = true
		elif arg.begins_with("--capture-dir="):
			_capture_dir = value
		elif arg.begins_with("--smithing-level="):
			GameState.smithing_level = int(value)
		elif arg.begins_with("--quests="):
			GameState.completed_quests.assign(value.split(",", false))
		elif arg.begins_with("--blueprints="):
			GameState.blueprints.assign(value.split(",", false))
		elif arg.begins_with("--recipe="):
			for index: int in _recipes.size():
				if str(_recipes[index].get("id", "")) == value:
					_recipe_index = index


## Saves one screenshot called [param shot] the first time [param due] is true.
## Only active with `--capture-dir`.
func _capture_once(shot: String, due: bool) -> void:
	if _capture_dir.is_empty() or not due or _captured.has(shot):
		return
	_captured[shot] = true
	await RenderingServer.frame_post_draw
	var path: String = _capture_dir.path_join("%02d-%s.png" % [_captured.size(), shot])
	var error: Error = get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Forge: could not save screenshot %s (error %d)" % [path, error])


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	if not _ready_ok:
		return
	draw_string(_font, Vector2(24.0, 36.0), str(_text.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, COL_AMBER)
	_draw_header()
	match _state:
		State.READY:
			_draw_ready()
		State.INTRO:
			_draw_intro()
		State.STAGE_DONE:
			_draw_stage_done()
		State.RESULT:
			_draw_result()
	draw_juice()


## One chip per stage: the current one is lit, finished ones show their score.
func _draw_header() -> void:
	var playing: bool = _state in [State.INTRO, State.STAGE, State.STAGE_DONE]
	var left: float = 576.0 - float(_order.size()) * 95.0
	for i: int in _order.size():
		var rect: Rect2 = Rect2(left + float(i) * 190.0 + 5.0, 16.0, 180.0, 40.0)
		var label: String = "%d %s" % [i + 1, _stage_name(_order[i])]
		var fill: Color = COL_PANEL
		var ink: Color = COL_CREAM
		if _stage_scores.has(_order[i]):
			fill = COL_AMBER.darkened(0.45)
			label = _t("result", "stage_score") % [_stage_name(_order[i]), roundi(float(_stage_scores[_order[i]]))]
		elif playing and i == _stage_index:
			fill = COL_ORANGE
			ink = COL_OUTLINE
		draw_box(rect, fill, COL_OUTLINE, 3.0)
		draw_text_centered(label, Vector2(rect.get_center().x, rect.position.y + 27.0), 17, ink, rect.size.x)


func _draw_ready() -> void:
	var recipe: Dictionary = _recipes[_recipe_index]
	draw_text_centered("<   %s   >" % _label("recipes", _recipe_id()), Vector2(576.0, 124.0), 40, COL_ORANGE)
	draw_text_centered(_t("ready", "levels") % [_gear_level(), int(_progress.get("smithing_level", 0))], Vector2(576.0, 160.0), 20, COL_CREAM)
	draw_text_centered(_difficulty_text(), Vector2(576.0, 190.0), 17, COL_AMBER, 1120.0)
	# The tier ladder, best tier on top, with what still locks each tier.
	var count: int = _rules.tier_count()
	for row: int in count:
		var index: int = count - 1 - row
		var gaps: Array[Dictionary] = _rules.tier_gaps(index, _progress, recipe)
		var unlocked: bool = gaps.is_empty()
		var rect: Rect2 = Rect2(66.0, 214.0 + float(row) * 58.0, 1020.0, 48.0)
		draw_box(rect, COL_PANEL if unlocked else COL_PANEL.darkened(0.35), COL_OUTLINE, 3.0)
		var name_line: String = _t("ready", "tier_row") % [_tier_name(_rules.tier_id(index)), _rules.tier_min_score(index)]
		draw_string(_font, rect.position + Vector2(18.0, 31.0), name_line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, COL_GLOW if unlocked else COL_CREAM.darkened(0.3))
		var status: String = _t("ready", "unlocked") if unlocked else _t("ready", "locked") % _gaps_text(gaps)
		draw_string(_font, rect.position + Vector2(290.0, 30.0), status, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, COL_AMBER if unlocked else COL_CREAM)
	draw_text_centered(_t("ready", "choose"), Vector2(576.0, 540.0), 18, COL_CREAM)
	draw_text_centered(_t("ready", "start"), Vector2(576.0, 590.0), 30, COL_ORANGE)


func _difficulty_text() -> String:
	var gap: int = _gear_level() - int(_progress.get("smithing_level", 0))
	if gap > 0:
		return _t("ready", "difficulty_harder") % _factor
	if gap < 0:
		if _rules.is_mastery_unlocked(_progress):
			return _t("ready", "difficulty_easier") % _factor
		return _t("ready", "mastery_locked") % _gaps_text(_rules.mastery_gaps(_progress))
	return _t("ready", "difficulty_even")


func _draw_intro() -> void:
	var stage_id: String = _order[_stage_index]
	var stage_text: Dictionary = _text.get("stages", {}).get(stage_id, {})
	draw_text_centered(_t("flow", "stage_intro") % [_stage_index + 1, _order.size()], Vector2(576.0, 200.0), 24, COL_AMBER)
	draw_text_centered(_stage_name(stage_id).to_upper(), Vector2(576.0, 280.0), 64, COL_ORANGE)
	draw_text_centered(str(stage_text.get("intro", "")), Vector2(576.0, 340.0), 22, COL_CREAM, 1120.0)
	draw_text_centered(str(stage_text.get("instruction", "")), Vector2(576.0, 420.0), 17, COL_CREAM, 1130.0)
	# Countdown bar to the start of the stage.
	var left: float = clampf(1.0 - _state_time / maxf(_flow("intro_seconds"), 0.001), 0.0, 1.0)
	draw_rect(Rect2(376.0, 470.0, 400.0, 8.0), COL_PANEL)
	draw_rect(Rect2(376.0, 470.0, 400.0 * left, 8.0), COL_AMBER)


func _draw_stage_done() -> void:
	var stage_id: String = _order[_stage_index]
	var rect: Rect2 = Rect2(276.0, 250.0, 600.0, 120.0)
	draw_rect(rect, Color(COL_OUTLINE, 0.85))
	draw_rect(rect, COL_AMBER, false, 4.0)
	var line: String = _t("flow", "stage_done") % [_stage_name(stage_id).to_upper(), roundi(float(_stage_scores.get(stage_id, 0.0)))]
	draw_text_centered(line, Vector2(576.0, 328.0), 48, COL_GLOW, rect.size.x)


func _draw_result() -> void:
	var tier_id: String = str(_award.get("tier_id", ""))
	if _result_frames > 50 or not has_pops():
		draw_text_centered(_tier_name(tier_id).to_upper(), Vector2(576.0, 170.0), 76, COL_ORANGE)
	draw_text_centered(_label("recipes", _recipe_id()), Vector2(576.0, 92.0), 22, COL_CREAM)
	draw_text_centered(_t("result", "score") % int(_award.get("score", 0)), Vector2(576.0, 226.0), 34, COL_CREAM)
	if bool(_award.get("capped", false)):
		var capped: String = _t("result", "capped") % [
			_tier_name(str(_award.get("earned_id", ""))).to_upper(), _tier_name(tier_id).to_upper()]
		draw_text_centered(capped, Vector2(576.0, 268.0), 20, COL_GLOW, 1120.0)
		var gaps: Array[Dictionary] = []
		gaps.assign(_award.get("gaps", []))
		var hint: String = _t("result", "unlock_hint") % [_tier_name(str(_award.get("blocking_id", ""))), _gaps_text(gaps)]
		draw_text_centered(hint, Vector2(576.0, 298.0), 16, COL_AMBER, 1130.0)
	draw_anvil(Vector2(250.0, 450.0), 0.8, true)
	draw_speech_bubble(Rect2(400.0, 380.0, 640.0, 120.0), _quip, 22)
	draw_text_centered(_t("result", "retry"), Vector2(576.0, 590.0), 28, COL_ORANGE)
