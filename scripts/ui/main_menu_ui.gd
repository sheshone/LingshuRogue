class_name MainMenuUI
extends Control

const BATTLE_SCENE: PackedScene = preload("res://scenes/battle/Battle.tscn")
const MAP_SCENE: PackedScene = preload("res://scenes/map/Map.tscn")

@onready var menu: VBoxContainer = %Menu
@onready var help_panel: PanelContainer = %HelpPanel
var player_template: Dictionary = {}
var starting_core: Dictionary = {}


func _ready() -> void:
	AudioDirector.set_context("menu")
	player_template = GameDataLoader.load_collection("res://data/player_templates.json", "player_templates")[0]
	starting_core = GameDataLoader.load_collection("res://data/spirit_cores.json", "spirit_cores")[0]
	%StartButton.pressed.connect(_start_new_run)
	%ContinueButton.pressed.connect(_continue_run)
	%HelpButton.pressed.connect(func() -> void: help_panel.visible = not help_panel.visible)
	%SettingsButton.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/ui/Settings.tscn"))
	%CloseHelpButton.pressed.connect(func() -> void: help_panel.visible = false)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	%ContinueButton.visible = RunState.initialized or RunState.has_any_save()
	for button: Button in [%StartButton, %ContinueButton, %HelpButton, %SettingsButton, %QuitButton]:
		button.set_meta("sfx_kind", "journey" if button == %StartButton else "click")
		button.mouse_entered.connect(func() -> void: _focus_button(button))
	_start_menu_motion()


func _start_menu_motion() -> void:
	%ArtTitle.pivot_offset = %ArtTitle.size * 0.5
	var title_tween := create_tween().set_loops()
	title_tween.tween_property(%ArtTitle, "position:y", %ArtTitle.position.y - 7.0, 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	title_tween.parallel().tween_property(%ArtTitle, "modulate", Color(1.08, 1.04, 0.9, 1.0), 2.8)
	title_tween.tween_property(%ArtTitle, "position:y", %ArtTitle.position.y + 7.0, 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	title_tween.parallel().tween_property(%ArtTitle, "modulate", Color.WHITE, 2.8)
	$Background.pivot_offset = size * 0.5
	var background_tween := create_tween().set_loops()
	background_tween.tween_property($Background, "scale", Vector2(1.018, 1.018), 8.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	background_tween.tween_property($Background, "scale", Vector2.ONE, 8.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for index: int in 18:
		var mote := ColorRect.new()
		var radius := 2.0 + float(index % 3)
		mote.size = Vector2(radius, radius)
		mote.position = Vector2(size.x * (0.48 + fmod(index * 0.173, 0.48)), size.y * fmod(index * 0.287, 0.9))
		mote.color = Color(0.92, 0.76, 0.38, 0.18 + float(index % 4) * 0.05)
		mote.mouse_filter = Control.MOUSE_FILTER_IGNORE
		%Motes.add_child(mote)
		var drift := create_tween().set_loops()
		drift.tween_property(mote, "position", mote.position + Vector2(18.0 + index % 5 * 4.0, -80.0 - index % 4 * 18.0), 5.0 + index % 5).set_trans(Tween.TRANS_SINE)
		drift.tween_property(mote, "position", mote.position, 0.0)


func _start_new_run() -> void:
	%StartButton.disabled = true
	RunState.clear_save()
	RunState.reset_run()
	RunState.initialize_run(player_template, {"learned_spell_ids":["qi_strike"], "inventory":{}, "materials":{}, "relics":[]}, starting_core)
	RunState.start_map("initiation_grounds", "initiation_origin")
	get_tree().call_deferred("change_scene_to_packed", MAP_SCENE)


func _continue_run() -> void:
	if not RunState.initialized:
		var loaded := false
		for slot: int in range(1, RunState.SAVE_SLOT_COUNT + 1):
			if RunState.has_save(slot) and RunState.load_game(slot):
				loaded = true
				break
		if not loaded:
			%ContinueButton.visible = false
			return
	get_tree().change_scene_to_packed(MAP_SCENE if RunState.map_active else BATTLE_SCENE)


func _focus_button(button: Button) -> void:
	button.pivot_offset = button.size * 0.5
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(1.035, 1.035), 0.1)
	tween.tween_property(button, "scale", Vector2.ONE, 0.12)
