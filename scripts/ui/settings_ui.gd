class_name SettingsUI
extends Control

const MAIN_MENU := "res://scenes/ui/MainMenu.tscn"
const MAP_SCENE := "res://scenes/map/Map.tscn"
const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"

@onready var slots: VBoxContainer = %SaveSlots


func _ready() -> void:
	AudioDirector.set_context("map")
	%MusicSlider.value = AudioDirector.get_music_volume()
	%SfxSlider.value = AudioDirector.get_sfx_volume()
	%Fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	%DantianDisplay.select(1 if AudioDirector.get_dantian_display_mode() == "scattered" else 0)
	%MusicSlider.value_changed.connect(AudioDirector.set_music_volume)
	%SfxSlider.value_changed.connect(AudioDirector.set_sfx_volume)
	%Fullscreen.toggled.connect(_toggle_fullscreen)
	%DantianDisplay.item_selected.connect(_set_dantian_display)
	%BackButton.pressed.connect(_go_back)
	%MainMenuButton.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU))
	_build_slots()


func _build_slots() -> void:
	for child: Node in slots.get_children():
		child.queue_free()
	for slot: int in range(1, RunState.SAVE_SLOT_COUNT + 1):
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(620, 58)
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.custom_minimum_size = Vector2(210, 48)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = "玉简 %d　%s" % [slot, "已有记录" if RunState.has_save(slot) else "空"]
		row.add_child(label)
		var load_button := _button("读取", "confirm")
		load_button.disabled = not RunState.has_save(slot)
		load_button.pressed.connect(func() -> void: _load_slot(slot))
		row.add_child(load_button)
		var save_button := _button("保存", "reward")
		save_button.disabled = not RunState.initialized
		save_button.pressed.connect(func() -> void: _save_slot(slot))
		row.add_child(save_button)
		var delete_button := _button("清除", "back")
		delete_button.disabled = not RunState.has_save(slot)
		delete_button.pressed.connect(func() -> void: RunState.clear_save(slot); _build_slots())
		row.add_child(delete_button)
		slots.add_child(row)


func _button(text_value: String, sound: String) -> Button:
	var result := Button.new()
	result.text = text_value
	result.custom_minimum_size = Vector2(112, 44)
	result.set_meta("sfx_kind", sound)
	return result


func _save_slot(slot: int) -> void:
	RunState.save_game(slot)
	_build_slots()


func _load_slot(slot: int) -> void:
	if RunState.load_game(slot):
		get_tree().change_scene_to_file(MAP_SCENE if RunState.map_active else BATTLE_SCENE)


func _toggle_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	AudioDirector.save_settings()


func _set_dantian_display(index: int) -> void:
	AudioDirector.set_dantian_display_mode("scattered" if index == 1 else "compact")


func _go_back() -> void:
	get_tree().change_scene_to_file(MAP_SCENE if RunState.initialized and RunState.map_active else MAIN_MENU)
