# PROTOTYPE - NOT FOR PRODUCTION
extends Node2D
## Forging prototype 3: "Anvil Song".
##
## Forging as a rhythm game. The four stages are four phrases of one short
## song with no pauses between them. Notes slide along two lanes: the top lane
## is the bellows (secondary button), the bottom lane is the hammer (primary
## button). Long notes are held and released on time (the quench).
## Standalone: the chart and tuning come from forge_anvil_song.json, input from
## the Input Map. Run with `-- --autoplay` to let a bot play (headless checks).

const PROTOTYPE_NAME: String = "forge_anvil_song"
const CONFIG_PATH: String = "res://prototypes/forge_anvil_song/forge_anvil_song.json"
const DESIGN_SIZE: Vector2 = Vector2(1152.0, 648.0)
const AUTOPLAY_RESULT_FRAMES: int = 90

const ACT_PRIMARY: StringName = &"p1_forge_primary"
const ACT_SECONDARY: StringName = &"p1_forge_secondary"
const ACTIONS: Array[StringName] = [ACT_PRIMARY, ACT_SECONDARY]
const BUTTON_PRIMARY: int = 0
const BUTTON_SECONDARY: int = 1

const COL_BG: Color = Color("2a1c17")
const COL_PANEL: Color = Color("3f2b22")
const COL_OUTLINE: Color = Color("150d0a")
const COL_CREAM: Color = Color("f6e9cf")
const COL_AMBER: Color = Color("e8a33d")
const COL_ORANGE: Color = Color("ff7a1f")
const COL_GLOW: Color = Color("fff3c4")
const COL_IRON: Color = Color("6f6763")
const COL_MISS: Color = Color("8f1d14")

const HIT_X: float = 300.0
const LANE_Y: Array[float] = [410.0, 250.0]  # index = button
const NOTE_PENDING: int = 0
const NOTE_HOLDING: int = 1
const NOTE_DONE: int = 2

enum State { READY, PLAY, RESULT }

var _cfg: Dictionary = {}
var _font: Font
var _autoplay: bool = false
var _bot_release_at: Array[float] = [0.0, 0.0]
var _result_frames: int = 0

var _state: State = State.READY
var _song_time: float = 0.0
var _beat_seconds: float = 0.6
var _song_end: float = 0.0
var _notes: Array[Dictionary] = []
var _stage_names: Array[String] = []
var _stage_starts: Array[float] = []
var _stage_marks: Array[Array] = []
var _stage_expected: Array[int] = []
var _stage_scores: Array[float] = []
var _last_tick_beat: int = -1
var _final_score: float = 0.0
var _tier: String = ""
var _quip: String = ""
var _target_flash: Array[float] = [0.0, 0.0]

var _tick_player: AudioStreamPlayer
var _hit_player: AudioStreamPlayer

var _sparks: Array[Dictionary] = []
var _pops: Array[Dictionary] = []
var _shake: float = 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_autoplay = OS.get_cmdline_user_args().has("--autoplay")
	if not _load_config():
		return
	var sound: Dictionary = _cfg["sound"]
	_tick_player = _make_player(float(sound["tick_hz"]), float(sound["tick_seconds"]), float(sound["volume_db"]))
	_hit_player = _make_player(float(sound["hit_hz"]), float(sound["hit_seconds"]), float(sound["volume_db"]))
	_reset_run()


func _exit_tree() -> void:
	# Stop the beeps before quitting so their playbacks are released cleanly.
	if _tick_player != null:
		_tick_player.stop()
	if _hit_player != null:
		_hit_player.stop()


## Returns the current prototype state as JSON text (the project's test hook).
func debug_state_text() -> String:
	var judged: int = 0
	for note: Dictionary in _notes:
		if int(note["state"]) == NOTE_DONE:
			judged += 1
	var state: Dictionary = {
		"prototype": PROTOTYPE_NAME,
		"state": State.keys()[_state],
		"stage": _current_stage_name(),
		"song_timer": snappedf(_song_time, 0.01),
		"beat": snappedf(_song_time / _beat_seconds, 0.01),
		"notes_judged": judged,
		"notes_total": _notes.size(),
		"stage_scores": _rounded(_stage_scores),
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
			_update_song(delta)
		State.RESULT:
			_result_frames += 1
			if _autoplay:
				if _result_frames == AUTOPLAY_RESULT_FRAMES:
					# Bot runs are faster than real time: give the audio thread a
					# moment to let go of the last beep before quitting.
					_tick_player.stop()
					_hit_player.stop()
					OS.delay_msec(300)
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
	var song: Dictionary = _cfg["song"]
	_beat_seconds = 60.0 / float(song["bpm"])
	_state = State.READY
	_song_time = 0.0
	_last_tick_beat = -1
	_notes.clear()
	_stage_names.clear()
	_stage_starts.clear()
	_stage_marks.clear()
	_stage_expected.clear()
	_stage_scores.clear()
	var beat: float = float(song["lead_in_beats"])
	var phrases: Array = _cfg["phrases"]
	for stage: int in phrases.size():
		var phrase: Dictionary = phrases[stage]
		_stage_names.append(str(phrase["stage"]))
		_stage_starts.append(beat * _beat_seconds)
		_stage_marks.append([])
		_stage_scores.append(-1.0)
		var expected: int = 0
		for entry: Dictionary in phrase["notes"]:
			var start: float = (beat + float(entry["beat"])) * _beat_seconds
			var hold: float = float(entry.get("hold_beats", 0.0)) * _beat_seconds
			_notes.append({
				"time": start,
				"end": start + hold,
				"button": BUTTON_PRIMARY if str(entry["button"]) == "primary" else BUTTON_SECONDARY,
				"stage": stage,
				"state": NOTE_PENDING,
				"score": -1.0,
			})
			expected += 2 if hold > 0.0 else 1
		_stage_expected.append(expected)
		beat += float(phrase["beats"])
	_song_end = (beat + float(song["outro_beats"])) * _beat_seconds
	_final_score = 0.0
	_tier = ""
	_quip = ""
	_result_frames = 0
	_pops.clear()
	_sparks.clear()
	_log_state()


func _current_stage() -> int:
	var current: int = -1
	for stage: int in _stage_starts.size():
		if _song_time >= _stage_starts[stage]:
			current = stage
	return current


func _current_stage_name() -> String:
	var stage: int = _current_stage()
	if stage < 0 or _state == State.READY:
		return str(_cfg["text"]["lead_in"]) if not _cfg.is_empty() else ""
	return _stage_names[stage]


func _update_song(delta: float) -> void:
	var song: Dictionary = _cfg["song"]
	var miss: float = float(song["miss_window_seconds"])
	var stage_before: int = _current_stage()
	_song_time += delta
	if _current_stage() != stage_before:
		_log_state()
	var beat_index: int = int(_song_time / _beat_seconds)
	if beat_index != _last_tick_beat:
		_last_tick_beat = beat_index
		_tick_player.play()
	for button: int in ACTIONS.size():
		if Input.is_action_just_pressed(ACTIONS[button]):
			_press(button)
		_target_flash[button] = maxf(_target_flash[button] - delta * 5.0, 0.0)
	for note: Dictionary in _notes:
		var note_state: int = int(note["state"])
		var button: int = int(note["button"])
		if note_state == NOTE_PENDING and _song_time > float(note["time"]) + miss:
			# Never pressed: the press is a miss, and so is the release of a long note.
			note["state"] = NOTE_DONE
			_judge(note, 0.0)
			if float(note["end"]) > float(note["time"]):
				_judge(note, 0.0)
		elif note_state == NOTE_HOLDING:
			var released: bool = not Input.is_action_pressed(ACTIONS[button])
			if released or _song_time > float(note["end"]) + miss:
				note["state"] = NOTE_DONE
				_judge(note, _timing_score(absf(_song_time - float(note["end"]))) if released else 0.0)
	if _song_time >= _song_end:
		_show_result()


func _press(button: int) -> void:
	var miss: float = float(_cfg["song"]["miss_window_seconds"])
	_target_flash[button] = 1.0
	for note: Dictionary in _notes:
		if int(note["button"]) != button or int(note["state"]) != NOTE_PENDING:
			continue
		var error: float = absf(_song_time - float(note["time"]))
		if error <= miss:
			var is_hold: bool = float(note["end"]) > float(note["time"])
			note["state"] = NOTE_HOLDING if is_hold else NOTE_DONE
			_judge(note, _timing_score(error))
		return  # Only the next note in this lane can be hit.


func _timing_score(error: float) -> float:
	var song: Dictionary = _cfg["song"]
	return _window_score(error, float(song["perfect_window_seconds"]), float(song["miss_window_seconds"]))


func _judge(note: Dictionary, score: float) -> void:
	var juice: Dictionary = _cfg["juice"]
	var stage: int = int(note["stage"])
	var button: int = int(note["button"])
	var at: Vector2 = Vector2(HIT_X, LANE_Y[button])
	note["score"] = score
	_stage_marks[stage].append(score)
	var power: float = score / 100.0
	if score > 0.0:
		_hit_player.play()
		var weight: float = 1.0 if button == BUTTON_PRIMARY else 0.4
		_shake = float(juice["shake_pixels"]) * power * weight
		_emit_sparks(at, int(float(juice["sparks_on_perfect"]) * power * weight), COL_AMBER)
	_add_pop(_rating_for(score), at + Vector2(0.0, -52.0), 30, COL_GLOW if score >= 65.0 else COL_CREAM)
	if _stage_marks[stage].size() >= _stage_expected[stage] and _stage_scores[stage] < 0.0:
		var total: float = 0.0
		for mark: float in _stage_marks[stage]:
			total += mark
		_stage_scores[stage] = total / float(_stage_expected[stage])
		_add_pop("%s  %d" % [_stage_names[stage].to_upper(), roundi(_stage_scores[stage])], Vector2(576.0, 150.0), 44, COL_GLOW)


func _show_result() -> void:
	var total: float = 0.0
	for score: float in _stage_scores:
		total += maxf(score, 0.0)
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


## Builds a short decaying beep in code, so the prototype ships no audio files.
func _make_player(hz: float, seconds: float, volume_db: float) -> AudioStreamPlayer:
	var rate: int = 22050
	var count: int = int(float(rate) * seconds)
	var data: PackedByteArray = PackedByteArray()
	data.resize(count * 2)
	for i: int in count:
		var fade: float = 1.0 - float(i) / float(count)
		var wave: float = sin(TAU * hz * float(i) / float(rate)) + 0.4 * sin(TAU * hz * 2.7 * float(i) / float(rate))
		data.encode_s16(i * 2, int(wave * fade * fade * 9000.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player


# --- Autoplay bot (headless checks only) -----------------------------------

func _bot() -> void:
	for button: int in ACTIONS.size():
		if Input.is_action_pressed(ACTIONS[button]) and _song_time >= _bot_release_at[button]:
			Input.action_release(ACTIONS[button])
			continue
		if _state == State.READY:
			if button == BUTTON_PRIMARY and not Input.is_action_pressed(ACT_PRIMARY):
				Input.action_press(ACT_PRIMARY)
				_bot_release_at[button] = 0.0
			continue
		if _state != State.PLAY or Input.is_action_pressed(ACTIONS[button]):
			continue
		for note: Dictionary in _notes:
			if int(note["button"]) == button and int(note["state"]) == NOTE_PENDING:
				if _song_time >= float(note["time"]) - 0.008:
					Input.action_press(ACTIONS[button])
					_bot_release_at[button] = float(note["end"])
				break


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
			_draw_header()
			_draw_track()
			_text(str(_cfg["text"]["ready"]), Vector2(576.0, 110.0), 22, COL_CREAM, 1120.0)
			_text(str(_cfg["text"]["start_prompt"]), Vector2(576.0, 160.0), 30, COL_ORANGE)
			_draw_instruction()
		State.PLAY:
			_draw_header()
			_draw_track()
			_draw_instruction()
		State.RESULT:
			_draw_header()
			_draw_result()
	_draw_juice()


func _text(text: String, center: Vector2, size: int, color: Color, width: float = 1000.0) -> void:
	draw_string(_font, Vector2(center.x - width * 0.5, center.y), text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


func _box(rect: Rect2, fill: Color, outline: Color = COL_OUTLINE, width: float = 4.0) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, width)


func _draw_header() -> void:
	var current: int = _current_stage() if _state == State.PLAY else -1
	for i: int in _stage_names.size():
		var rect: Rect2 = Rect2(286.0 + float(i) * 156.0, 16.0, 146.0, 40.0)
		var label: String = "%d %s" % [i + 1, _stage_names[i]]
		var fill: Color = COL_PANEL
		var ink: Color = COL_CREAM
		if _stage_scores[i] >= 0.0:
			fill = COL_AMBER.darkened(0.45)
			label = "%s %d" % [_stage_names[i], roundi(_stage_scores[i])]
		elif i == current:
			fill = COL_ORANGE
			ink = COL_OUTLINE
		_box(rect, fill, COL_OUTLINE, 3.0)
		_text(label, Vector2(rect.get_center().x, rect.position.y + 27.0), 18, ink, rect.size.x)


func _draw_instruction() -> void:
	_text(str(_cfg["text"]["instruction"]), Vector2(576.0, 620.0), 17, COL_CREAM, 1130.0)


func _note_x(time: float) -> float:
	var speed: float = float(_cfg["song"]["scroll_pixels_per_beat"]) / _beat_seconds
	return HIT_X + (time - _song_time) * speed


func _draw_track() -> void:
	var beat_phase: float = fposmod(_song_time, _beat_seconds) / _beat_seconds
	var pulse: float = (1.0 - beat_phase) * (1.0 - beat_phase) if _state == State.PLAY else 0.0
	# Forge glow in the corner beats with the song.
	draw_circle(Vector2(1010.0, 150.0), 44.0 + 14.0 * pulse, COL_ORANGE)
	draw_circle(Vector2(1010.0, 150.0), 20.0 + 12.0 * pulse, COL_GLOW)
	# Lanes, labels and targets.
	var labels: Array[String] = [str(_cfg["text"]["primary_label"]), str(_cfg["text"]["secondary_label"])]
	for button: int in ACTIONS.size():
		var y: float = LANE_Y[button]
		draw_rect(Rect2(0.0, y - 36.0, 1152.0, 72.0), COL_PANEL)
		draw_line(Vector2(0.0, y), Vector2(1152.0, y), COL_OUTLINE, 3.0)
		_text(labels[button], Vector2(130.0, y + 68.0), 18, COL_CREAM, 240.0)
	# Bellows icon (top lane) and anvil icon (bottom lane).
	draw_colored_polygon(PackedVector2Array([
		Vector2(70.0, 222.0), Vector2(190.0, 244.0), Vector2(190.0, 256.0), Vector2(70.0, 278.0),
	]), COL_AMBER)
	draw_colored_polygon(PackedVector2Array([
		Vector2(60.0, 388.0), Vector2(200.0, 388.0), Vector2(200.0, 404.0), Vector2(160.0, 404.0), Vector2(160.0, 424.0),
		Vector2(180.0, 424.0), Vector2(180.0, 436.0), Vector2(100.0, 436.0), Vector2(100.0, 424.0), Vector2(120.0, 424.0),
		Vector2(120.0, 404.0), Vector2(90.0, 400.0),
	]), COL_IRON)
	# Phrase flags scroll in with the notes.
	for stage: int in _stage_starts.size():
		var flag_x: float = _note_x(_stage_starts[stage])
		if flag_x > HIT_X - 40.0 and flag_x < 1200.0:
			draw_line(Vector2(flag_x, 196.0), Vector2(flag_x, 464.0), COL_CREAM.darkened(0.4), 3.0)
			draw_string(_font, Vector2(flag_x + 8.0, 204.0), _stage_names[stage].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, COL_CREAM)
	# Notes.
	for note: Dictionary in _notes:
		var button: int = int(note["button"])
		var note_state: int = int(note["state"])
		var y: float = LANE_Y[button]
		var start_x: float = _note_x(float(note["time"]))
		var end_x: float = _note_x(float(note["end"]))
		if end_x < -40.0 or start_x > 1200.0:
			continue
		if note_state == NOTE_DONE and float(note["score"]) > 0.0:
			continue  # Hit notes disappear; missed ones drift past, dimmed.
		var color: Color = COL_ORANGE if button == BUTTON_PRIMARY else COL_AMBER
		if note_state == NOTE_DONE:
			color = COL_MISS
		if note_state == NOTE_HOLDING:
			start_x = HIT_X
			color = COL_GLOW
		if end_x > start_x:
			draw_rect(Rect2(start_x, y - 12.0, end_x - start_x, 24.0), color)
			draw_rect(Rect2(start_x, y - 12.0, end_x - start_x, 24.0), COL_OUTLINE, false, 3.0)
			draw_circle(Vector2(end_x, y), 14.0, COL_OUTLINE)
			draw_circle(Vector2(end_x, y), 10.0, COL_CREAM)
		if button == BUTTON_PRIMARY:
			draw_circle(Vector2(start_x, y), 24.0, COL_OUTLINE)
			draw_circle(Vector2(start_x, y), 20.0, color)
		else:
			_box(Rect2(start_x - 20.0, y - 20.0, 40.0, 40.0), color)
	for button: int in ACTIONS.size():
		var target: Vector2 = Vector2(HIT_X, LANE_Y[button])
		var ring: Color = COL_CREAM.lerp(COL_GLOW, _target_flash[button])
		draw_arc(target, 30.0 + 4.0 * pulse + 6.0 * _target_flash[button], 0.0, TAU, 48, ring, 5.0)
	if _state == State.PLAY and _current_stage() < 0:
		var beats_left: int = ceili((_stage_starts[0] - _song_time) / _beat_seconds)
		_text("%s  %d" % [str(_cfg["text"]["lead_in"]), beats_left], Vector2(576.0, 150.0), 36, COL_ORANGE)


func _draw_result() -> void:
	_text("Score %d / 100" % roundi(_final_score), Vector2(576.0, 270.0), 34, COL_CREAM)
	var parts: PackedStringArray = PackedStringArray()
	for i: int in _stage_scores.size():
		parts.append("%s %d" % [_stage_names[i], roundi(maxf(_stage_scores[i], 0.0))])
	_text("   ".join(parts), Vector2(576.0, 312.0), 20, COL_AMBER)
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
