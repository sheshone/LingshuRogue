extends Node

func _ready() -> void:
	var spells_list := GameDataLoader.load_collection("res://data/spells.json", "spells")
	var spells := GameDataLoader.index_by_id(spells_list, "spells")
	var methods_list := GameDataLoader.load_collection("res://data/cultivation_methods.json", "cultivation_methods")
	var methods := GameDataLoader.index_by_id(methods_list, "methods")
	var relics := GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/relics.json", "relics"), "relics")
	var enemies := GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/enemies.json", "enemies"), "enemies")
	assert(spells.size() >= 26, "炼气神通池必须足以支持五条构筑路线。")
	assert(methods.size() == 5 and relics.size() >= 12)
	for method: Dictionary in methods.values():
		assert(not str(method.get("initial_spell_id", "")).is_empty())
		assert(spells.has(str(method.get("initial_spell_id", ""))))
		assert(method.get("replaces_spell_ids", []).has("qi_strike"))
	assert(enemies.get("black_tide_chief", {}).get("action_policy", {}).get("phases", []).size() >= 1, "Boss必须拥有实际执行的阶段策略。")

	RunState.reset_run()
	var battle_scene: PackedScene = load("res://scenes/battle/Battle.tscn")
	var battle: BattleManager = battle_scene.instantiate()
	add_child(battle)
	await get_tree().process_frame
	assert(RunState.get_spiritual_sense_capacity() == 10)
	assert(battle.enemy_units.size() == 1 and int(battle.enemy_units[0].hp.max) == 10)
	assert(RunState.player_state.skills.spell_ids == ["qi_strike"])
	battle.apply_damage_to_unit("player", str(battle.enemy_units[0].unit_id), 99)
	battle._check_battle_end()
	assert(battle.reward_groups.size() == 1 and battle.reward_groups[0].get("options", []).size() == 5)
	var target: Dictionary = battle.enemy_units[0]
	target.hp.max = 200
	target.hp.current = 200
	battle.player_state.shield = 10
	battle.effect_executor.execute_action(spells.rock_reversal, "player", str(target.unit_id), battle, battle.qi_manager)
	assert(int(target.hp.current) == 187 and int(battle.player_state.shield) == 0, "厚土必须能把防线转为反击。")
	battle.add_status_to_unit("player", "sharpness", 2)
	battle.effect_executor.execute_action(spells.meridian_severing_flash, "player", str(target.unit_id), battle, battle.qi_manager)
	assert(battle.get_status_value_for_unit("player", "sharpness") == 0, "锐金终结技必须消耗锋锐。")
	battle.add_status_to_unit("player", "vitality", 2)
	battle.player_state.hp.current = 30
	battle.effect_executor.execute_action(spells.life_bloom, "player", str(target.unit_id), battle, battle.qi_manager)
	assert(int(battle.player_state.hp.current) > 30 and battle.get_status_value_for_unit("player", "vitality") == 0)
	battle.queue_free()
	await get_tree().process_frame

	# 五种功法都通过同一 initial_spell_id 完成教学转化。
	for method_id: String in methods:
		RunState.player_state.skills.spell_ids = ["qi_strike"]
		RunState.learned_method_ids.clear()
		RunState.active_method_id = ""
		var manager := CultivationMethodManager.new()
		manager.configure(methods_list)
		var learned := manager.learn_method(method_id, true)
		assert(not learned.is_empty())
		assert(RunState.player_state.skills.spell_ids.has(str(learned.initial_spell_id)))
		assert(not RunState.player_state.skills.spell_ids.has("qi_strike"))
		manager.free()

	# 丹田保留有上限，随机结果不会无限累积；任意灵气成本可以正常支付。
	var qi := QiManager.new()
	add_child(qi)
	var core: Dictionary = GameDataLoader.load_collection("res://data/spirit_cores.json", "spirit_cores")[0]
	assert(qi.configure(GameDataLoader.load_collection("res://data/qi.json", "qi_types"), core))
	qi.start_battle()
	qi.add_sea_qi("fire", 5)
	qi.add_sea_qi("water", 3)
	var dissipation := qi.dissipate_sea_qi(0.5)
	assert(int(dissipation.retained_total) == 3 and int(dissipation.dissipated_total) == 5)
	assert(qi.can_pay({"any_qi": 1}) and qi.spend({"any_qi": 1}))

	# 普通战固定战利品后，神通三选一与灵气三选一互相独立。
	var rewards := RewardManager.new()
	add_child(rewards)
	rewards.configure(GameDataLoader.load_collection("res://data/reward_tables.json", "reward_tables"), GameDataLoader.load_collection("res://data/items.json", "items"), spells_list, methods_list, relics.values())
	var normal_groups := rewards.build_reward_groups(["qi_refining_no_reward"])
	assert(normal_groups.size() == 3)
	assert(normal_groups[0].mode == "fixed" and normal_groups[1].id == "qi_refining_spell_choice" and normal_groups[2].id == "qi_refining_qi_choice")
	assert(normal_groups[1].options.size() == 3 and normal_groups[2].options.size() == 3)
	var elite_groups := rewards.build_reward_groups(["qi_refining_elite_demo_rewards"])
	assert(elite_groups.size() == 4 and elite_groups[3].id == "qi_refining_elite_advanced_choice")
	var boss_groups := rewards.build_reward_groups(["qi_refining_boss_rewards"])
	assert(boss_groups.size() == 4 and boss_groups[3].id == "qi_refining_boss_rare_choice")

	# 滚动地图持续生成，且保底计数达到阈值时下一层必有精英。
	var maps := GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/map_nodes.json", "maps"), "maps")
	var rules := GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/map_generation.json", "map_generation"), "rules")
	var rule: Dictionary = rules.qi_refining_generation.duplicate(true)
	rule.runtime_elite_counter = 6
	var generated := MapGenerator.new(77).generate(maps.qi_refining_region, rule)
	var boss_seen := false
	for step: int in 12:
		var indexed := GameDataLoader.index_by_id(generated.nodes, "generated nodes")
		var current_id := str(generated.current_node_id)
		var next_ids: Array = indexed[current_id].next_node_ids
		assert(next_ids.size() >= 1 and next_ids.size() <= 3)
		if step == 0:
			assert(next_ids.any(func(node_id: Variant) -> bool: return indexed[str(node_id)].type == "elite"))
		boss_seen = boss_seen or next_ids.any(func(node_id: Variant) -> bool: return indexed[str(node_id)].type == "boss")
		generated = MapGenerator.new(78 + step).advance_exploration(generated, str(next_ids[0]), rule)
	assert(boss_seen, "探索至第12层前必须看见寨主入口。")

	# 休息处可炼化、整理并闭关；商店拥有五类消费接口。
	var node_manager := MapNodeManager.new()
	node_manager.configure()
	var rest := node_manager.get_content("rest_wind_shelter")
	assert(rest.choices.any(func(choice: Dictionary) -> bool: return choice.has("breakthrough_rule_id")))
	assert(rest.choices.any(func(choice: Dictionary) -> bool: return choice.get("effects", []).any(func(effect: Dictionary) -> bool: return effect.get("type", "") == "process_recipe")))
	var shop := node_manager.get_runtime_content({"id":"test_shop","type":"shop","content_id":"wandering_qi_shop"})
	assert(shop.choices.size() == 8)
	var chest := node_manager.get_runtime_content({"id":"test_chest","type":"treasure","content_id":"placeholder_sealed_chest"})
	assert(chest.choices.size() == 3)
	var shop_effect_types: Dictionary = {}
	for choice: Dictionary in node_manager.offer_tables.qi_refining_shop.entries:
		for effect: Dictionary in choice.effects:
			shop_effect_types[str(effect.type)] = true
	for required_type: String in ["add_item", "learn_spell", "add_relic", "forget_spell", "convert_core_qi"]:
		assert(shop_effect_types.has(required_type))

	print("QI_REFINING_VERTICAL_SLICE_TEST_PASS")
	qi.queue_free()
	rewards.queue_free()
	await get_tree().process_frame
	get_tree().quit()
