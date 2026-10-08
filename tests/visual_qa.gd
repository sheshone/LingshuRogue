extends Node

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/artifacts"))
	RunState.reset_run()
	var menu: MainMenuUI = load("res://scenes/ui/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	_save("main_menu.png")
	remove_child(menu)
	menu.queue_free()
	await get_tree().process_frame
	var player_template: Dictionary = GameDataLoader.load_collection("res://data/player_templates.json", "player_templates")[0]
	var opening_core: Dictionary = GameDataLoader.load_collection("res://data/spirit_cores.json", "spirit_cores")[0]
	RunState.initialize_run(player_template, {"learned_spell_ids":["qi_strike"]}, opening_core)
	RunState.start_map("initiation_grounds", "initiation_origin")
	var opening_map: MapUI = load("res://scenes/map/Map.tscn").instantiate()
	add_child(opening_map)
	await get_tree().process_frame
	await get_tree().process_frame
	_save("initiation_map.png")
	remove_child(opening_map)
	opening_map.queue_free()
	RunState.reset_run()
	await get_tree().process_frame
	var battle: BattleManager = load("res://scenes/battle/Battle.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	_save("battle.png")
	battle.apply_damage_to_unit("player", str(battle.enemy_units[0].unit_id), 999)
	battle._check_battle_end()
	await get_tree().process_frame
	_save("reward.png")
	remove_child(battle)
	battle.queue_free()
	await get_tree().process_frame
	RunState.start_map("qi_refining_region", "realm_origin")
	var map: MapUI = load("res://scenes/map/Map.tscn").instantiate()
	add_child(map)
	await get_tree().process_frame
	await get_tree().process_frame
	_save("map.png")
	remove_child(map)
	map.queue_free()
	await get_tree().process_frame
	RunState.pending_map_node = {"id":"qa_shop","name":"松烟行脚铺","type":"shop","content_id":"wandering_qi_shop"}
	RunState.spirit_stones = 80
	var shop: MapNodeUI = load("res://scenes/map/MapNode.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	await get_tree().process_frame
	_save("shop.png")
	remove_child(shop)
	shop.queue_free()
	await get_tree().process_frame
	RunState.reset_run()
	player_template = GameDataLoader.load_collection("res://data/player_templates.json", "player_templates")[0]
	var core: Dictionary = GameDataLoader.load_collection("res://data/spirit_cores.json", "spirit_cores")[0]
	RunState.initialize_run(player_template, {
		"learned_spell_ids":["fireball","kindling_art","ember_guard","flame_burst","five_element_guard","water_cycle","metallic_guard","golden_arc","wooden_aegis","rock_reversal"],
		"learned_method_ids":["flame_method"],"active_method_id":"flame_method","relics":["scarlet_flame_pearl","five_element_compass","vein_stabilizing_stone","green_sprout_pendant"]
	}, core)
	RunState.current_battle_id = "map_qi_normal"
	var midgame: BattleManager = load("res://scenes/battle/Battle.tscn").instantiate()
	add_child(midgame)
	await get_tree().process_frame
	await get_tree().process_frame
	_save("midgame_battle.png")
	print("VISUAL_QA_CAPTURED")
	get_tree().quit()


func _save(file_name: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://tests/artifacts/%s" % file_name)
