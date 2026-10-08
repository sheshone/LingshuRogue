extends Node

var sfx_players: Array[AudioStreamPlayer] = []
var sfx_cursor := 0
var ambience_player: AudioStreamPlayer
var current_context := ""
var stream_cache: Dictionary = {}
var last_hovered_button: BaseButton
var random := RandomNumberGenerator.new()
var music_volume := 0.72
var sfx_volume := 0.78
var dantian_display_mode := "compact"
const SETTINGS_PATH := "user://audio_settings.json"


func _ready() -> void:
	random.randomize()
	_load_settings()
	ambience_player = AudioStreamPlayer.new()
	add_child(ambience_player)
	for index: int in 6:
		var player := AudioStreamPlayer.new()
		player.volume_db = linear_to_db(sfx_volume)
		add_child(player)
		sfx_players.append(player)
	ambience_player.volume_db = linear_to_db(music_volume)
	for kind: String in ["click", "hover", "node", "card", "choice", "reward", "reward_relic", "reward_stone", "reward_spell", "reward_method", "reward_qi", "reward_material", "reward_item", "shop", "inventory", "confirm", "back", "journey", "cast", "hit", "shield", "qi", "relic", "relic_trigger", "victory", "purchase", "chest", "enemy_beast", "enemy_cultivator", "enemy_construct"]:
		_cache_stream("res://assets/audio/sfx/%s.wav" % kind)
	for element: String in ["metal", "wood", "water", "fire", "earth", "neutral"]:
		_cache_stream("res://assets/audio/sfx/cast_%s.wav" % element)
	for enemy_id: String in ["training_puppet", "bandit", "steel_fang_wolf", "fire_tail_wolf", "rock_shell_tortoise", "withered_vine_spirit", "ember_dust_moth", "dusk_beak_crow", "iron_bark_guardian", "blood_root_demon", "seal_bearing_enforcer", "black_tide_chief"]:
		_cache_stream("res://assets/audio/sfx/enemy_%s.wav" % enemy_id)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered is BaseButton:
			play_sfx(str(hovered.get_meta("sfx_kind", "click")))


func _process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var hovered := get_viewport().gui_get_hovered_control()
	var button := hovered as BaseButton
	if button != last_hovered_button:
		last_hovered_button = button
		if is_instance_valid(button):
			play_sfx("hover")


func play_sfx(kind: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var path := "res://assets/audio/sfx/%s.wav" % kind
	if sfx_players.is_empty():
		return
	var player := sfx_players[sfx_cursor % sfx_players.size()]
	sfx_cursor += 1
	player.stream = _cache_stream(path) if ResourceLoader.exists(path) else _tone(520.0, 0.08, false)
	player.pitch_scale = random.randf_range(0.96, 1.04) if kind in ["click", "hover", "node", "card", "choice", "reward", "shop", "inventory", "confirm", "back"] else 1.0
	player.play()


func play_element_sfx(element: String) -> void:
	var normalized := element if element in ["metal", "wood", "water", "fire", "earth"] else "neutral"
	play_sfx("cast_%s" % normalized)


func play_relic_sfx(relic_id: String) -> void:
	if DisplayServer.get_name() == "headless" or sfx_players.is_empty():
		return
	var player := sfx_players[sfx_cursor % sfx_players.size()]
	sfx_cursor += 1
	player.stream = _cache_stream("res://assets/audio/sfx/relic_trigger.wav")
	player.pitch_scale = 0.92 + float(abs(relic_id.hash()) % 9) * 0.025
	player.play()


func play_enemy_sfx(enemy_id: String, unit_type: String, action: Dictionary) -> void:
	var effect_type := ""
	for effect: Variant in action.get("effects", []):
		if effect is Dictionary:
			effect_type = str(effect.get("type", ""))
			if effect_type in ["damage", "shield", "heal"]:
				break
	if effect_type == "shield":
		play_sfx("shield")
		return
	var enemy_path := "res://assets/audio/sfx/enemy_%s.wav" % enemy_id
	play_sfx("enemy_%s" % enemy_id if ResourceLoader.exists(enemy_path) else ("enemy_%s" % unit_type if unit_type in ["beast", "cultivator", "construct"] else "enemy_beast"))


func set_context(context: String) -> void:
	if context == current_context:
		return
	current_context = context
	if DisplayServer.get_name() == "headless":
		return
	if ambience_player.playing:
		var fade_out := create_tween()
		fade_out.tween_property(ambience_player, "volume_db", -32.0, 0.22)
		await fade_out.finished
	ambience_player.stop()
	var path := "res://assets/audio/music/%s.wav" % context
	var stream: AudioStream = _cache_stream(path) if ResourceLoader.exists(path) else _tone(110.0, 2.4, true)
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.data.size() / 2.0)
	ambience_player.stream = stream
	ambience_player.volume_db = -28.0
	ambience_player.play()
	create_tween().tween_property(ambience_player, "volume_db", linear_to_db(music_volume), 0.65)


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	if is_instance_valid(ambience_player):
		ambience_player.volume_db = linear_to_db(maxf(music_volume, 0.0001))
	save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	for player: AudioStreamPlayer in sfx_players:
		player.volume_db = linear_to_db(maxf(sfx_volume, 0.0001))
	save_settings()


func get_music_volume() -> float:
	return music_volume


func get_sfx_volume() -> float:
	return sfx_volume


func set_dantian_display_mode(mode: String) -> void:
	dantian_display_mode = mode if mode in ["compact", "scattered"] else "compact"
	save_settings()


func get_dantian_display_mode() -> String:
	return dantian_display_mode


func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"music":music_volume, "sfx":sfx_volume, "dantian_display":dantian_display_mode}))


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if parsed is Dictionary:
		music_volume = clampf(float(parsed.get("music", music_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(parsed.get("sfx", sfx_volume)), 0.0, 1.0)
		dantian_display_mode = str(parsed.get("dantian_display", dantian_display_mode))
		if dantian_display_mode not in ["compact", "scattered"]:
			dantian_display_mode = "compact"


func _cache_stream(path: String) -> AudioStream:
	if stream_cache.has(path):
		return stream_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	stream_cache[path] = stream
	return stream


func _tone(frequency: float, duration: float, looped: bool) -> AudioStreamWAV:
	var rate := 22050
	var frames := maxi(1, int(rate * duration))
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for frame: int in frames:
		var fade := minf(1.0, float(frames - frame) / float(maxi(1, int(rate * 0.03)))) if not looped else 1.0
		var value := int(sin(TAU * frequency * float(frame) / float(rate)) * 3500.0 * fade)
		bytes[frame * 2] = value & 0xff
		bytes[frame * 2 + 1] = (value >> 8) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED
	stream.loop_end = frames
	return stream
