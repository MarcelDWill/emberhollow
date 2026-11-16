class_name ForgeAudio
extends Node
## Placeholder forge sounds: short decaying tones built in code, so the game
## ships no audio files until real sound exists. Which tones exist, and their
## pitch, length and volume, come from the `sounds` block of
## data/forging_stages.json.

const _MIX_RATE: int = 22050
const _OVERTONE_RATIO: float = 2.7
const _OVERTONE_LEVEL: float = 0.4
const _PEAK: float = 9000.0

var _players: Dictionary = {}


## Builds one player per entry of [param sounds] (name -> `hz`, `seconds`,
## `volume_db`).
func setup(sounds: Dictionary) -> void:
	for sound_name: Variant in sounds:
		var sound: Dictionary = sounds[sound_name]
		_players[str(sound_name)] = _make_player(
			float(sound.get("hz", 440.0)), float(sound.get("seconds", 0.1)), float(sound.get("volume_db", -10.0)))


## Plays the tone called [param sound_name]. [param pitch] shifts it (1 = as
## defined). Unknown names are ignored.
func play(sound_name: String, pitch: float = 1.0) -> void:
	var player: AudioStreamPlayer = _players.get(sound_name)
	if player != null:
		player.pitch_scale = maxf(pitch, 0.01)
		player.play()


## Stops every tone, so their playbacks are released before the game quits.
func stop_all() -> void:
	for player: AudioStreamPlayer in _players.values():
		player.stop()


func _exit_tree() -> void:
	stop_all()


func _make_player(hz: float, seconds: float, volume_db: float) -> AudioStreamPlayer:
	var count: int = maxi(int(float(_MIX_RATE) * seconds), 1)
	var data: PackedByteArray = PackedByteArray()
	data.resize(count * 2)
	for i: int in count:
		var fade: float = 1.0 - float(i) / float(count)
		var phase: float = TAU * hz * float(i) / float(_MIX_RATE)
		var wave: float = sin(phase) + _OVERTONE_LEVEL * sin(phase * _OVERTONE_RATIO)
		data.encode_s16(i * 2, int(wave * fade * fade * _PEAK))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = _MIX_RATE
	stream.data = data
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player
