extends Node
class_name AudioManager

# Audio manager for office sound effects
# Place audio files in res://audio/ directory:
# - typing.wav (or .ogg) - keyboard typing sounds
# - meow.wav - cat meowing
# - stapler.wav - stapler/achievement sound
# - shredder.wav - paper shredder sound
# - filing.wav - filing cabinet drawer sound

# Sound effect players
var typing_player: AudioStreamPlayer
var meow_player: AudioStreamPlayer
var stapler_player: AudioStreamPlayer
var shredder_player: AudioStreamPlayer
var filing_player: AudioStreamPlayer

# Typing sound management
var typing_timer: float = 0.0
const TYPING_INTERVAL: float = 0.15  # Time between key sounds

# Default volumes (dB)
const DEFAULT_TYPING_VOLUME_DB: float = -15.0
const DEFAULT_MEOW_VOLUME_DB: float = -8.0
const DEFAULT_ACHIEVEMENT_VOLUME_DB: float = -5.0
const DEFAULT_OFFICE_VOLUME_DB: float = -10.0  # Shredder, filing cabinet

# Volume levels (0.0 to 1.0 for UI, converted to dB internally)
var typing_volume: float = 0.5
var meow_volume: float = 0.7
var achievement_volume: float = 0.8
var office_volume: float = 0.6  # Shredder, filing cabinet

# Meow management
var meow_cooldown: float = 0.0
const MEOW_COOLDOWN_TIME: float = 30.0

# Audio file paths
const AUDIO_PATH = "res://audio/"
const TYPING_SOUND = "typing.wav"
const MEOW_SOUND = "meow.wav"
const STAPLER_SOUND = "stapler.wav"
const SHREDDER_SOUND = "shredder.wav"
const FILING_SOUND = "filing.wav"

# Settings persistence
const SETTINGS_FILE: String = "user://audio_settings.json"

var sounds_enabled: bool = true
var sounds_loaded: bool = false

# Session alerts (turn done / needs attention) - independent of sounds_enabled
var alerts_enabled: bool = true
var alert_volume: float = 0.8
var alert_player: AudioStreamPlayer
var alert_streams: Dictionary = {}  # kind -> AudioStreamWAV
const DEFAULT_ALERT_VOLUME_DB: float = -6.0
const ALERT_COOLDOWN_MSEC: int = 1500
var _last_alert_msec: int = -ALERT_COOLDOWN_MSEC

func _ready() -> void:
	_register_with_settings()
	_setup_audio_players()
	_load_sounds()

func _register_with_settings() -> void:
	var registry = get_node_or_null("/root/SettingsRegistry")
	if not registry:
		# Fallback to legacy loading if registry not available
		_load_settings()
		return

	var schema: Array = [
		{"key": "typing_volume", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "description": "Typing sound volume"},
		{"key": "meow_volume", "type": "float", "default": 0.7, "min": 0.0, "max": 1.0, "description": "Cat meow volume"},
		{"key": "achievement_volume", "type": "float", "default": 0.8, "min": 0.0, "max": 1.0, "description": "Achievement sound volume"},
		{"key": "office_volume", "type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "description": "Office sounds volume (shredder, filing)"},
		{"key": "sounds_enabled", "type": "bool", "default": true, "description": "Enable/disable all sounds"},
		{"key": "alerts_enabled", "type": "bool", "default": true, "description": "Chime when a session finishes or needs attention"},
		{"key": "alert_volume", "type": "float", "default": 0.8, "min": 0.0, "max": 1.0, "description": "Session alert volume"}
	]

	registry.register_category("audio", SETTINGS_FILE, schema, _on_setting_changed)

	# Load values from registry with defaults
	var v_typing = registry.get_setting("audio", "typing_volume")
	typing_volume = v_typing if v_typing != null else 0.5
	var v_meow = registry.get_setting("audio", "meow_volume")
	meow_volume = v_meow if v_meow != null else 0.7
	var v_ach = registry.get_setting("audio", "achievement_volume")
	achievement_volume = v_ach if v_ach != null else 0.8
	var v_office = registry.get_setting("audio", "office_volume")
	office_volume = v_office if v_office != null else 0.6
	var v_enabled = registry.get_setting("audio", "sounds_enabled")
	sounds_enabled = v_enabled if v_enabled != null else true
	var v_alerts = registry.get_setting("audio", "alerts_enabled")
	alerts_enabled = v_alerts if v_alerts != null else true
	var v_alert_vol = registry.get_setting("audio", "alert_volume")
	alert_volume = v_alert_vol if v_alert_vol != null else 0.8

func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"typing_volume":
			typing_volume = float(value)
			if typing_player:
				typing_player.volume_db = _volume_to_db(typing_volume, DEFAULT_TYPING_VOLUME_DB)
		"meow_volume":
			meow_volume = float(value)
			if meow_player:
				meow_player.volume_db = _volume_to_db(meow_volume, DEFAULT_MEOW_VOLUME_DB)
		"achievement_volume":
			achievement_volume = float(value)
			if stapler_player:
				stapler_player.volume_db = _volume_to_db(achievement_volume, DEFAULT_ACHIEVEMENT_VOLUME_DB)
		"office_volume":
			office_volume = float(value)
			if shredder_player:
				shredder_player.volume_db = _volume_to_db(office_volume, DEFAULT_OFFICE_VOLUME_DB)
			if filing_player:
				filing_player.volume_db = _volume_to_db(office_volume, DEFAULT_OFFICE_VOLUME_DB)
		"sounds_enabled":
			sounds_enabled = bool(value)
		"alerts_enabled":
			alerts_enabled = bool(value)
		"alert_volume":
			alert_volume = float(value)
			if alert_player:
				alert_player.volume_db = _volume_to_db(alert_volume, DEFAULT_ALERT_VOLUME_DB)

func _setup_audio_players() -> void:
	typing_player = AudioStreamPlayer.new()
	typing_player.volume_db = _volume_to_db(typing_volume, DEFAULT_TYPING_VOLUME_DB)
	typing_player.bus = "Master"
	typing_player.max_polyphony = 16  # Allow multiple overlapping typing sounds
	add_child(typing_player)

	meow_player = AudioStreamPlayer.new()
	meow_player.volume_db = _volume_to_db(meow_volume, DEFAULT_MEOW_VOLUME_DB)
	meow_player.bus = "Master"
	add_child(meow_player)

	stapler_player = AudioStreamPlayer.new()
	stapler_player.volume_db = _volume_to_db(achievement_volume, DEFAULT_ACHIEVEMENT_VOLUME_DB)
	stapler_player.bus = "Master"
	stapler_player.max_polyphony = 4  # Allow overlapping achievement sounds
	add_child(stapler_player)

	shredder_player = AudioStreamPlayer.new()
	shredder_player.volume_db = _volume_to_db(office_volume, DEFAULT_OFFICE_VOLUME_DB)
	shredder_player.bus = "Master"
	add_child(shredder_player)

	filing_player = AudioStreamPlayer.new()
	filing_player.volume_db = _volume_to_db(office_volume, DEFAULT_OFFICE_VOLUME_DB)
	filing_player.bus = "Master"
	add_child(filing_player)

	alert_player = AudioStreamPlayer.new()
	alert_player.volume_db = _volume_to_db(alert_volume, DEFAULT_ALERT_VOLUME_DB)
	alert_player.bus = "Master"
	add_child(alert_player)
	# Synthesized so no extra asset/import is needed.
	# done: rising two-note chime (E6 -> A6); attention: three quick B5 pings
	alert_streams["done"] = _make_chime([[1318.5, 0.0, 0.35], [1760.0, 0.12, 0.5]], 0.65)
	alert_streams["attention"] = _make_chime([[987.8, 0.0, 0.12], [987.8, 0.16, 0.12], [987.8, 0.32, 0.25]], 0.6)

func _load_sounds() -> void:
	# Try to load sounds - they may not exist yet
	var typing_path = AUDIO_PATH + TYPING_SOUND
	var meow_path = AUDIO_PATH + MEOW_SOUND
	var stapler_path = AUDIO_PATH + STAPLER_SOUND

	if ResourceLoader.exists(typing_path):
		typing_player.stream = load(typing_path)
		sounds_loaded = true
	else:
		push_warning("[AudioManager] Typing sound not found at: " + typing_path)

	if ResourceLoader.exists(meow_path):
		meow_player.stream = load(meow_path)
		sounds_loaded = true
	else:
		push_warning("[AudioManager] Meow sound not found at: " + meow_path)

	if ResourceLoader.exists(stapler_path):
		stapler_player.stream = load(stapler_path)
		sounds_loaded = true
	else:
		push_warning("[AudioManager] Stapler sound not found at: " + stapler_path)

	var shredder_path = AUDIO_PATH + SHREDDER_SOUND
	if ResourceLoader.exists(shredder_path):
		shredder_player.stream = load(shredder_path)
		sounds_loaded = true

	var filing_path = AUDIO_PATH + FILING_SOUND
	if ResourceLoader.exists(filing_path):
		filing_player.stream = load(filing_path)
		sounds_loaded = true

	if not sounds_loaded:
		push_warning("[AudioManager] No sounds loaded. Create audio files in res://audio/")

func _process(delta: float) -> void:
	if meow_cooldown > 0:
		meow_cooldown -= delta

# Called when agents are working to play typing sounds
func play_typing() -> void:
	if not sounds_enabled or not typing_player.stream:
		return
	# Pitch variation for realism, polyphony allows overlapping
	typing_player.pitch_scale = randf_range(0.9, 1.1)
	typing_player.play()

# Called when agent stops working to cut off typing sounds
func stop_typing() -> void:
	if typing_player:
		typing_player.stop()

# Called by cat to meow
func play_meow() -> void:
	if not sounds_enabled or not meow_player.stream:
		return
	if meow_cooldown > 0:
		return
	meow_cooldown = MEOW_COOLDOWN_TIME
	meow_player.pitch_scale = randf_range(0.85, 1.15)
	meow_player.play()

# Called when achievement is earned
func play_achievement() -> void:
	if not sounds_enabled or not stapler_player.stream:
		return
	stapler_player.play()

# Called when agent uses shredder
func play_shredder() -> void:
	if not sounds_enabled or not shredder_player.stream:
		return
	shredder_player.pitch_scale = randf_range(0.95, 1.05)
	shredder_player.play()

# Called when agent uses filing cabinet
func play_filing() -> void:
	if not sounds_enabled or not filing_player.stream:
		return
	filing_player.pitch_scale = randf_range(0.9, 1.1)
	filing_player.play()

# Called when a session finishes its turn ("done") or asks the user something ("attention")
func play_alert(kind: String) -> void:
	if not alerts_enabled or not alert_streams.has(kind):
		return
	var now = Time.get_ticks_msec()
	if now - _last_alert_msec < ALERT_COOLDOWN_MSEC:
		return
	_last_alert_msec = now
	alert_player.stream = alert_streams[kind]
	alert_player.play()

# notes: [[frequency_hz, start_sec, length_sec], ...]
func _make_chime(notes: Array, total_sec: float) -> AudioStreamWAV:
	var mix_rate = 44100
	var frames = int(total_sec * mix_rate)
	var samples = PackedFloat32Array()
	samples.resize(frames)
	for note in notes:
		var freq: float = note[0]
		var start = int(note[1] * mix_rate)
		var length = int(note[2] * mix_rate)
		for i in range(length):
			var idx = start + i
			if idx >= frames:
				break
			var t = float(i) / mix_rate
			var attack = minf(1.0, t / 0.005)
			var env = attack * exp(-t * 9.0)
			# Fundamental plus a soft octave for a bell-like tone
			samples[idx] += env * (sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t))
	var data = PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		data.encode_s16(i * 2, int(clampf(samples[i] * 0.45, -1.0, 1.0) * 32767.0))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func set_sounds_enabled(enabled: bool) -> void:
	var registry = get_node_or_null("/root/SettingsRegistry")
	if registry:
		registry.set_setting("audio", "sounds_enabled", enabled)
	else:
		sounds_enabled = enabled
		_save_settings()

func is_sounds_enabled() -> bool:
	return sounds_enabled

# Volume setters (0.0 to 1.0)
func set_typing_volume(volume: float) -> void:
	var registry = get_node_or_null("/root/SettingsRegistry")
	if registry:
		registry.set_setting("audio", "typing_volume", volume)
	else:
		typing_volume = clampf(volume, 0.0, 1.0)
		if typing_player:
			typing_player.volume_db = _volume_to_db(typing_volume, DEFAULT_TYPING_VOLUME_DB)
		_save_settings()

func set_meow_volume(volume: float) -> void:
	var registry = get_node_or_null("/root/SettingsRegistry")
	if registry:
		registry.set_setting("audio", "meow_volume", volume)
	else:
		meow_volume = clampf(volume, 0.0, 1.0)
		if meow_player:
			meow_player.volume_db = _volume_to_db(meow_volume, DEFAULT_MEOW_VOLUME_DB)
		_save_settings()

func set_achievement_volume(volume: float) -> void:
	var registry = get_node_or_null("/root/SettingsRegistry")
	if registry:
		registry.set_setting("audio", "achievement_volume", volume)
	else:
		achievement_volume = clampf(volume, 0.0, 1.0)
		if stapler_player:
			stapler_player.volume_db = _volume_to_db(achievement_volume, DEFAULT_ACHIEVEMENT_VOLUME_DB)
		_save_settings()

func set_office_volume(volume: float) -> void:
	var registry = get_node_or_null("/root/SettingsRegistry")
	if registry:
		registry.set_setting("audio", "office_volume", volume)
	else:
		office_volume = clampf(volume, 0.0, 1.0)
		if shredder_player:
			shredder_player.volume_db = _volume_to_db(office_volume, DEFAULT_OFFICE_VOLUME_DB)
		if filing_player:
			filing_player.volume_db = _volume_to_db(office_volume, DEFAULT_OFFICE_VOLUME_DB)
		_save_settings()

# Volume getters
func get_typing_volume() -> float:
	return typing_volume

func get_meow_volume() -> float:
	return meow_volume

func get_achievement_volume() -> float:
	return achievement_volume

func get_office_volume() -> float:
	return office_volume

# Convert 0-1 volume to dB
# 0.0 = muted, 0.5 = default, 1.0 = +6dB boost from default
func _volume_to_db(volume: float, default_db: float) -> float:
	if volume <= 0.0:
		return -80.0  # Effectively silent
	if volume <= 0.5:
		# 0.0 to 0.5 maps -80dB to default_db
		return lerpf(-80.0, default_db, volume * 2.0)
	else:
		# 0.5 to 1.0 maps default_db to default_db + 6dB
		return lerpf(default_db, default_db + 6.0, (volume - 0.5) * 2.0)

# Settings persistence
func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_FILE):
		return
	var file = FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if not file:
		return
	var json_string = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return
	var data = json.get_data()
	if data is Dictionary:
		typing_volume = clampf(data.get("typing_volume", 0.5), 0.0, 1.0)
		meow_volume = clampf(data.get("meow_volume", 0.7), 0.0, 1.0)
		achievement_volume = clampf(data.get("achievement_volume", 0.8), 0.0, 1.0)
		office_volume = clampf(data.get("office_volume", 0.6), 0.0, 1.0)
		sounds_enabled = data.get("sounds_enabled", true)

func _save_settings() -> void:
	var data = {
		"typing_volume": typing_volume,
		"meow_volume": meow_volume,
		"achievement_volume": achievement_volume,
		"office_volume": office_volume,
		"sounds_enabled": sounds_enabled
	}
	var file = FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
