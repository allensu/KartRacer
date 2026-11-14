extends Node
## Autoload "Sfx": every sound effect and the music loop are synthesised in
## code at startup (no audio files), so all audio is original.
## Sfx.play("pickup"), Sfx.engine_stream(), Sfx.play_music(), M toggles mute.

const RATE := 22050
const MUSIC_RATE := 16000

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _music: AudioStreamWAV
var _engine: AudioStreamWAV
var muted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -9.0
	add_child(_music_player)
	_build_sounds()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		muted = not muted
		AudioServer.set_bus_mute(0, muted)


func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _sounds.has(name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _sounds[name]
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


func engine_stream() -> AudioStreamWAV:
	return _engine


func play_music() -> void:
	if _music == null:
		_music = _build_music()
	if _music_player.stream != _music or not _music_player.playing:
		_music_player.stream = _music
		_music_player.play()


func stop_music() -> void:
	_music_player.stop()


# ---------------------------------------------------------------- synthesis

func _build_sounds() -> void:
	_sounds["beep"] = _tone([660.0], 0.16, "square", 0.35)
	_sounds["go"] = _tone([990.0], 0.45, "square", 0.35)
	_sounds["pickup"] = _tone([880.0, 1108.7, 1318.5, 1760.0], 0.05, "square", 0.25)
	_sounds["lap"] = _tone([784.0, 1046.5], 0.12, "square", 0.3)
	_sounds["finish"] = _tone([523.3, 659.3, 784.0, 1046.5, 784.0, 1046.5], 0.11, "square", 0.3)
	_sounds["spark"] = _tone([1567.98], 0.05, "sine", 0.25)
	_sounds["shield"] = _sweep(600.0, 1400.0, 0.4, "sine", 0.3, 0.0)
	_sounds["seeker"] = _sweep(300.0, 1600.0, 0.3, "saw", 0.25, 0.1)
	_sounds["boost"] = _sweep(180.0, 520.0, 0.55, "saw", 0.3, 0.5)
	_sounds["hit"] = _sweep(700.0, 90.0, 0.55, "square", 0.35, 0.35)
	_sounds["oil"] = _sweep(220.0, 80.0, 0.25, "sine", 0.4, 0.6)
	_sounds["bump"] = _sweep(140.0, 50.0, 0.18, "sine", 0.6, 0.4)
	_engine = _build_engine()


func _osc(kind: String, phase: float) -> float:
	var f := phase - floorf(phase)
	match kind:
		"square":
			return 1.0 if f < 0.5 else -1.0
		"saw":
			return f * 2.0 - 1.0
		"tri":
			return 1.0 - 4.0 * absf(f - 0.5)
		_:
			return sin(f * TAU)


## A sequence of notes, each `note_len` seconds, with a short decay.
func _tone(freqs: Array, note_len: float, kind: String, vol: float) -> AudioStreamWAV:
	var n := int(note_len * RATE)
	var data := PackedFloat32Array()
	data.resize(n * freqs.size())
	var phase := 0.0
	for k in freqs.size():
		for i in n:
			phase += freqs[k] / RATE
			var env := minf(1.0, i / 80.0) * (1.0 - float(i) / n)
			data[k * n + i] = _osc(kind, phase) * env * vol
	return _to_wav(data, RATE, false)


## A pitch sweep mixed with some noise.
func _sweep(f0: float, f1: float, length: float, kind: String, vol: float, noise: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 * 31 + f1)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		phase += lerpf(f0, f1, t) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.3)
		var env := minf(1.0, i / 60.0) * pow(1.0 - t, 1.5)
		data[i] = (_osc(kind, phase) * (1.0 - noise) + lp * noise * 2.0) * env * vol
	return _to_wav(data, RATE, false)


## A seamless engine loop: whole number of cycles of a buzzy low tone.
func _build_engine() -> AudioStreamWAV:
	var period := 220  # samples -> ~100 Hz at 22050 Hz
	var n := period * 10
	var data := PackedFloat32Array()
	data.resize(n)
	for i in n:
		var ph := float(i) / period
		data[i] = (_osc("saw", ph) * 0.5 + _osc("square", ph * 2.0) * 0.2 + sin(ph * TAU * 0.5) * 0.3) * 0.22
	return _to_wav(data, RATE, true)


## Original 16-second loop: C - Am - F - G, bass, arpeggio and drums at 120 BPM.
func _build_music() -> AudioStreamWAV:
	var bpm := 120.0
	var beat := 60.0 / bpm
	var bars := 8
	var n := int(bars * 4 * beat * MUSIC_RATE)
	var data := PackedFloat32Array()
	data.resize(n)
	# Chord roots (Hz) per two bars and their arpeggio tones.
	var chords := [
		[65.41, [261.63, 329.63, 392.0, 523.25]],
		[55.0, [220.0, 261.63, 329.63, 440.0]],
		[43.65, [174.61, 220.0, 261.63, 349.23]],
		[49.0, [196.0, 246.94, 293.66, 392.0]],
	]
	var melody := [523.25, 0, 587.33, 659.25, 0, 783.99, 659.25, 0, 587.33, 0, 523.25, 587.33, 659.25, 0, 0, 0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var eighth := beat / 2.0
	var bass_phase := 0.0
	var arp_phase := 0.0
	var mel_phase := 0.0
	var noise_lp := 0.0
	for i in n:
		var t := float(i) / MUSIC_RATE
		var bar := int(t / (beat * 4.0))
		var chord: Array = chords[(bar / 2) % chords.size()]
		var step := int(t / eighth)
		var in_step := fmod(t, eighth) / eighth
		var in_beat := fmod(t, beat) / beat
		var beat_idx := int(t / beat) % 4
		# Bass: root on every 8th note, octave jump on the off-beat.
		var bass_f: float = chord[0] * (2.0 if step % 2 == 1 else 1.0)
		bass_phase += bass_f / MUSIC_RATE
		var bass := _osc("tri", bass_phase) * 0.32 * (1.0 - in_step * 0.6)
		# Arpeggio: 16th-note pattern over the chord.
		var tones: Array = chord[1]
		var sixteenth := int(t / (eighth / 2.0))
		arp_phase += tones[sixteenth % 4] / MUSIC_RATE
		var arp := _osc("square", arp_phase) * 0.06 * (1.0 - fmod(t, eighth / 2.0) / (eighth / 2.0))
		# Melody on the second half of the loop.
		var mel := 0.0
		if bar >= 4:
			var mf: float = melody[step % melody.size()]
			if mf > 0.0:
				mel_phase += mf / MUSIC_RATE
				mel = (_osc("square", mel_phase) * 0.5 + _osc("sine", mel_phase) * 0.5) * 0.09 * (1.0 - in_step * 0.7)
		# Drums: kick on 1 and 3, snare on 2 and 4, hats on 8ths.
		noise_lp = lerpf(noise_lp, rng.randf_range(-1.0, 1.0), 0.6)
		var drums := 0.0
		var bt := in_beat * beat
		if beat_idx % 2 == 0 and bt < 0.15:
			drums += sin(TAU * (60.0 + 90.0 * exp(-bt * 30.0)) * bt) * exp(-bt * 18.0) * 0.5
		if beat_idx % 2 == 1 and bt < 0.12:
			drums += noise_lp * exp(-bt * 25.0) * 0.25
		var et := in_step * eighth
		if et < 0.03:
			drums += rng.randf_range(-1.0, 1.0) * (1.0 - et / 0.03) * 0.06
		data[i] = clampf(bass + arp + mel + drums, -1.0, 1.0)
	return _to_wav(data, MUSIC_RATE, true)


func _to_wav(data: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = data.size()
	return wav
