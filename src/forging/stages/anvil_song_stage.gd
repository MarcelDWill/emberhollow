class_name AnvilSongStage
extends ForgeStage
## Forge stage 2, "Anvil Song": work the metal to the beat. Notes slide along
## two lanes: the top lane is the bellows (second button), the bottom lane is
## the hammer (main button). Long notes are held and released on time. The
## skill is rhythm. Score = the average of the phrase scores. Tuning and the
## note chart: `stages.anvil_song` in data/forging_stages.json.

const _BUTTON_ACTIONS: Array[StringName] = [ACT_PRIMARY, ACT_SECONDARY]
const _BUTTON_PRIMARY: int = 0
const _BUTTON_SECONDARY: int = 1
const _NOTE_PENDING: int = 0
const _NOTE_HOLDING: int = 1
const _NOTE_DONE: int = 2

# Where notes are hit, and each lane's height (index = button).
const _HIT_X: float = 300.0
const _LANE_Y: Array[float] = [410.0, 250.0]
# How early the bot presses, so its press lands on the note (seconds).
const _BOT_LEAD_SECONDS: float = 0.008

var _beat_seconds: float = 0.6
var _song_end: float = 0.0
var _notes: Array[Dictionary] = []
var _phrase_names: Array[String] = []
var _phrase_starts: Array[float] = []
var _phrase_marks: Array[Array] = []
var _phrase_expected: Array[int] = []
var _phrase_scores: Array[float] = []
var _last_tick_beat: int = -1
var _target_flash: Array[float] = [0.0, 0.0]
var _bot_release_at: Array[float] = [0.0, 0.0]


## See [method ForgeStage.stage_state].
func stage_state() -> Dictionary:
	var judged: int = 0
	for note: Dictionary in _notes:
		if int(note["state"]) == _NOTE_DONE:
			judged += 1
	return {
		"song_timer": snappedf(_time, 0.01),
		"beat": snappedf(_time / _beat_seconds, 0.01),
		"notes_judged": judged,
		"notes_total": _notes.size(),
		"phrase_scores": _rounded(_phrase_scores),
	}


func _stage_begin() -> void:
	_beat_seconds = 60.0 / float(_cfg["bpm"])
	_last_tick_beat = -1
	_notes.clear()
	_phrase_names.clear()
	_phrase_starts.clear()
	_phrase_marks.clear()
	_phrase_expected.clear()
	_phrase_scores.clear()
	var phrase_text: Dictionary = _text.get("phrases", {})
	var beat: float = float(_cfg["lead_in_beats"])
	var phrases: Array = _cfg.get("phrases", [])
	for phrase_index: int in phrases.size():
		var phrase: Dictionary = phrases[phrase_index]
		var phrase_id: String = str(phrase.get("id", ""))
		_phrase_names.append(str(phrase_text.get(phrase_id, phrase_id)))
		_phrase_starts.append(beat * _beat_seconds)
		_phrase_marks.append([])
		_phrase_scores.append(-1.0)
		var expected: int = 0
		for entry: Dictionary in phrase.get("notes", []):
			var start: float = (beat + float(entry["beat"])) * _beat_seconds
			var hold: float = float(entry.get("hold_beats", 0.0)) * _beat_seconds
			_notes.append({
				"time": start,
				"end": start + hold,
				"button": _BUTTON_PRIMARY if str(entry.get("button", "primary")) == "primary" else _BUTTON_SECONDARY,
				"phrase": phrase_index,
				"state": _NOTE_PENDING,
				"score": -1.0,
			})
			# A long note is judged twice: once on the press, once on the release.
			expected += 2 if hold > 0.0 else 1
		_phrase_expected.append(expected)
		beat += float(phrase["beats"])
	_song_end = (beat + float(_cfg["outro_beats"])) * _beat_seconds


func _stage_update(delta: float) -> void:
	var miss: float = float(_cfg["miss_window_seconds"])
	var beat_index: int = int(_time / _beat_seconds)
	if beat_index != _last_tick_beat:
		_last_tick_beat = beat_index
		if _audio != null:
			_audio.play("tick")
	for button: int in _BUTTON_ACTIONS.size():
		if Input.is_action_just_pressed(_BUTTON_ACTIONS[button]):
			_press(button)
		_target_flash[button] = maxf(_target_flash[button] - delta * 5.0, 0.0)
	for note: Dictionary in _notes:
		var note_state: int = int(note["state"])
		var button: int = int(note["button"])
		if note_state == _NOTE_PENDING and _time > float(note["time"]) + miss:
			# Never pressed: the press is a miss, and so is the release of a long note.
			note["state"] = _NOTE_DONE
			_judge(note, 0.0)
			if float(note["end"]) > float(note["time"]):
				_judge(note, 0.0)
		elif note_state == _NOTE_HOLDING:
			var released: bool = not Input.is_action_pressed(_BUTTON_ACTIONS[button])
			if released or _time > float(note["end"]) + miss:
				note["state"] = _NOTE_DONE
				_judge(note, _timing_score(absf(_time - float(note["end"]))) if released else 0.0)
	if _time >= _song_end:
		var total: float = 0.0
		for score: float in _phrase_scores:
			total += maxf(score, 0.0)
		_finish(total / float(maxi(_phrase_scores.size(), 1)))


func _press(button: int) -> void:
	var miss: float = float(_cfg["miss_window_seconds"])
	_target_flash[button] = 1.0
	for note: Dictionary in _notes:
		if int(note["button"]) != button or int(note["state"]) != _NOTE_PENDING:
			continue
		var error: float = absf(_time - float(note["time"]))
		if error <= miss:
			var is_hold: bool = float(note["end"]) > float(note["time"])
			note["state"] = _NOTE_HOLDING if is_hold else _NOTE_DONE
			_judge(note, _timing_score(error))
		return  # Only the next note in this lane can be hit.


func _timing_score(error: float) -> float:
	return window_score(error, float(_cfg["perfect_window_seconds"]), float(_cfg["miss_window_seconds"]))


func _judge(note: Dictionary, score: float) -> void:
	var phrase: int = int(note["phrase"])
	var button: int = int(note["button"])
	var at: Vector2 = Vector2(_HIT_X, _LANE_Y[button])
	note["score"] = score
	_phrase_marks[phrase].append(score)
	var power: float = score / 100.0
	if score > 0.0:
		# The hammer lands harder than the bellows.
		var weight: float = 1.0 if button == _BUTTON_PRIMARY else 0.4
		if _audio != null:
			_audio.play("hit", 1.0 if button == _BUTTON_PRIMARY else 1.5)
		_shake(power * weight)
		emit_sparks(at, _sparks_for(power * weight), COL_AMBER)
	add_pop(_rating_for(score), at + Vector2(0.0, -52.0), 30, COL_GLOW if is_strong(score) else COL_CREAM)
	if _phrase_marks[phrase].size() >= _phrase_expected[phrase] and _phrase_scores[phrase] < 0.0:
		var total: float = 0.0
		for mark: float in _phrase_marks[phrase]:
			total += mark
		_phrase_scores[phrase] = total / float(maxi(_phrase_expected[phrase], 1))
		add_pop("%s  %d" % [_phrase_names[phrase].to_upper(), roundi(_phrase_scores[phrase])], Vector2(576.0, 150.0), 44, COL_GLOW)


func _current_phrase() -> int:
	var current: int = -1
	for phrase: int in _phrase_starts.size():
		if _time >= _phrase_starts[phrase]:
			current = phrase
	return current


func _stage_bot() -> void:
	for button: int in _BUTTON_ACTIONS.size():
		var action: StringName = _BUTTON_ACTIONS[button]
		if Input.is_action_pressed(action):
			if _time >= _bot_release_at[button]:
				Input.action_release(action)
			continue
		for note: Dictionary in _notes:
			if int(note["button"]) == button and int(note["state"]) == _NOTE_PENDING:
				if _time >= float(note["time"]) - _BOT_LEAD_SECONDS:
					Input.action_press(action)
					_bot_release_at[button] = float(note["end"])
				break


func _note_x(time: float) -> float:
	var speed: float = float(_cfg["scroll_pixels_per_beat"]) / _beat_seconds
	return _HIT_X + (time - _time) * speed


func _stage_draw() -> void:
	if _phrase_starts.is_empty():
		return
	var beat_phase: float = fposmod(_time, _beat_seconds) / _beat_seconds
	var pulse: float = (1.0 - beat_phase) * (1.0 - beat_phase) if _running else 0.0
	# Forge glow in the corner beats with the song.
	draw_circle(Vector2(1010.0, 150.0), 44.0 + 14.0 * pulse, COL_ORANGE)
	draw_circle(Vector2(1010.0, 150.0), 20.0 + 12.0 * pulse, COL_GLOW)
	# Lanes and their button labels.
	var labels: Array[String] = [_txt("primary_label"), _txt("secondary_label")]
	for button: int in _BUTTON_ACTIONS.size():
		var y: float = _LANE_Y[button]
		draw_rect(Rect2(0.0, y - 36.0, 1152.0, 72.0), COL_PANEL)
		draw_line(Vector2(0.0, y), Vector2(1152.0, y), COL_OUTLINE, 3.0)
		draw_text_centered(labels[button], Vector2(130.0, y + 68.0), 18, COL_CREAM, 240.0)
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
	for phrase: int in _phrase_starts.size():
		var flag_x: float = _note_x(_phrase_starts[phrase])
		if flag_x > _HIT_X - 40.0 and flag_x < 1200.0:
			draw_line(Vector2(flag_x, 196.0), Vector2(flag_x, 464.0), COL_CREAM.darkened(0.4), 3.0)
			draw_string(_font, Vector2(flag_x + 8.0, 204.0), _phrase_names[phrase].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, COL_CREAM)
	_draw_notes()
	for button: int in _BUTTON_ACTIONS.size():
		var target: Vector2 = Vector2(_HIT_X, _LANE_Y[button])
		var ring: Color = COL_CREAM.lerp(COL_GLOW, _target_flash[button])
		draw_arc(target, 30.0 + 4.0 * pulse + 6.0 * _target_flash[button], 0.0, TAU, 48, ring, 5.0)
	if _running and _current_phrase() < 0:
		var beats_left: int = ceili((_phrase_starts[0] - _time) / _beat_seconds)
		draw_text_centered("%s  %d" % [_txt("lead_in"), beats_left], Vector2(576.0, 150.0), 36, COL_ORANGE)
	draw_text_centered(_txt("instruction"), Vector2(576.0, 620.0), 17, COL_CREAM, 1130.0)


func _draw_notes() -> void:
	for note: Dictionary in _notes:
		var button: int = int(note["button"])
		var note_state: int = int(note["state"])
		var y: float = _LANE_Y[button]
		var start_x: float = _note_x(float(note["time"]))
		var end_x: float = _note_x(float(note["end"]))
		if end_x < -40.0 or start_x > 1200.0:
			continue
		if note_state == _NOTE_DONE and float(note["score"]) > 0.0:
			continue  # Hit notes disappear; missed ones drift past, dimmed.
		var color: Color = COL_ORANGE if button == _BUTTON_PRIMARY else COL_AMBER
		if note_state == _NOTE_DONE:
			color = COL_MISS
		if note_state == _NOTE_HOLDING:
			start_x = _HIT_X
			color = COL_GLOW
		if end_x > start_x:
			draw_rect(Rect2(start_x, y - 12.0, end_x - start_x, 24.0), color)
			draw_rect(Rect2(start_x, y - 12.0, end_x - start_x, 24.0), COL_OUTLINE, false, 3.0)
			draw_circle(Vector2(end_x, y), 14.0, COL_OUTLINE)
			draw_circle(Vector2(end_x, y), 10.0, COL_CREAM)
		if button == _BUTTON_PRIMARY:
			draw_circle(Vector2(start_x, y), 24.0, COL_OUTLINE)
			draw_circle(Vector2(start_x, y), 20.0, color)
		else:
			draw_box(Rect2(start_x - 20.0, y - 20.0, 40.0, 40.0), color)
