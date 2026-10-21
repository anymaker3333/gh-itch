extends Node
## UI and game sound service (autoload `Audio`).
##
## All sounds are synthesised at startup (short PCM envelopes) so that the
## project ships without binary audio assets while still giving audible feedback
## for hover, click, confirm, error and card/dice events.

enum Sfx { CLICK = 0, HOVER = 1, CONFIRM = 2, CANCEL = 3, ERROR = 4, NOTIFY = 5, CARD = 6, DICE = 7, WIN = 8, LOSE = 9 }

const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"
const POLYPHONY: int = 6

var enabled: bool = true

var _streams: Dictionary = {}  # Sfx -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0


func _ready() -> void:
	_ensure_buses()
	_build_streams()
	for i: int in range(POLYPHONY):
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_players.append(player)
	apply_volumes()
	Prefs.setting_changed.connect(_on_setting_changed)


func _ensure_buses() -> void:
	for bus_name: String in [SFX_BUS, MUSIC_BUS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var index := AudioServer.bus_count
			AudioServer.add_bus(index)
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


func apply_volumes() -> void:
	var muted := bool(Prefs.get_value("audio/mute", false))
	_set_bus_volume("Master", float(Prefs.get_value("audio/master_volume", 0.85)), muted)
	_set_bus_volume(SFX_BUS, float(Prefs.get_value("audio/sfx_volume", 0.8)), muted)
	_set_bus_volume(MUSIC_BUS, float(Prefs.get_value("audio/music_volume", 0.5)), muted)


func _set_bus_volume(bus_name: String, volume: float, muted: bool) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, muted or volume <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(volume, 0.0, 1.0)))


func _on_setting_changed(path: String, _value: Variant) -> void:
	if path.begins_with("audio/"):
		apply_volumes()


func play(sfx: Sfx) -> void:
	if not enabled or not _streams.has(sfx):
		return
	if bool(Prefs.get_value("audio/mute", false)):
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _streams[sfx]
	player.play()


# ----------------------------------------------------- procedural sound design

func _build_streams() -> void:
	_streams[Sfx.CLICK] = _make_click(1180.0, 0.045, 0.30)
	_streams[Sfx.HOVER] = _make_click(2100.0, 0.028, 0.12)
	_streams[Sfx.CONFIRM] = _make_arpeggio([660.0, 880.0, 1320.0], 0.085, 0.26)
	_streams[Sfx.CANCEL] = _make_arpeggio([520.0, 380.0], 0.09, 0.22)
	_streams[Sfx.ERROR] = _make_arpeggio([300.0, 220.0], 0.11, 0.26, true)
	_streams[Sfx.NOTIFY] = _make_arpeggio([880.0, 1180.0], 0.09, 0.20)
	_streams[Sfx.CARD] = _make_noise_sweep(0.075, 0.20)
	_streams[Sfx.DICE] = _make_arpeggio([420.0, 300.0, 520.0, 360.0], 0.045, 0.20)
	_streams[Sfx.WIN] = _make_arpeggio([523.0, 659.0, 784.0, 1046.0], 0.13, 0.28)
	_streams[Sfx.LOSE] = _make_arpeggio([440.0, 392.0, 330.0], 0.15, 0.24)


func _make_click(frequency: float, duration: float, amplitude: float) -> AudioStreamWAV:
	return _make_arpeggio([frequency], duration, amplitude, false, true)


func _make_arpeggio(frequencies: Array, note_duration: float, amplitude: float, square: bool = false, fast_decay: bool = false) -> AudioStreamWAV:
	var mix_rate := 22050
	var samples := PackedFloat32Array()
	var total := int(note_duration * mix_rate)
	for i: int in range(frequencies.size()):
		var freq := float(frequencies[i])
		for s: int in range(total):
			var t := float(s) / float(mix_rate)
			var env := exp(-t * (34.0 if fast_decay else 12.0))
			var phase := TAU * freq * t
			var value := (1.0 if sin(phase) >= 0.0 else -1.0) if square else sin(phase)
			# A touch of the second harmonic gives the blips a metallic character.
			value = value * 0.85 + sin(phase * 2.0) * 0.15
			samples.append(value * env * amplitude)
	return _pack(samples, mix_rate)


func _make_noise_sweep(duration: float, amplitude: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var samples := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240607
	var count := int(duration * mix_rate)
	var previous := 0.0
	for s: int in range(count):
		var t := float(s) / float(count)
		var white := rng.randf_range(-1.0, 1.0)
		# One-pole low pass whose cutoff drops over time: a soft card "swish".
		var alpha := lerpf(0.55, 0.06, t)
		previous = previous + alpha * (white - previous)
		var env: float = sin(PI * t)
		samples.append(previous * env * amplitude)
	return _pack(samples, mix_rate)


func _pack(samples: PackedFloat32Array, mix_rate: int) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		var value := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream
