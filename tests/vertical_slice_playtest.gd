extends Node

var battle_scene: PackedScene
var node_manager := MapNodeManager.new()
var map_rule: Dictionary
var generated_map: Dictionary
var battles_won := 0
var intro_choice_index := 3


func _ready() -> void:
	RunState.reset_run()
	battle_scene = load("res://scenes/battle/Battle.tscn")
	node_manager.configure()
	await _play_battle("battle_1_training_puppet", {})
	assert(RunState.active_method_id == "flame_method")
	RunState.start_map("qi_refining_region", "realm_origin")
	var maps := GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/map_nodes.json", "maps"), "maps")
	var rules := GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/map_generation.json", "map_generation"), "rules")
	map_rule = rules.qi_refining_generation.duplicate(true)
	generated_map = MapGenerator.new(31415).generate(maps.qi_refining_region, map_rule)
	var explored_nodes := 0
	for step: int in 20:
		var indexed := GameDataLoader.index_by_id(generated_map.nodes, "playtest nodes")
		var current: Dictionary = indexed[str(generated_map.current_node_id)]
		var candidates: Array[Dictionary] = []
		for node_id: Variant in current.next_node_ids:
			candidates.append(indexed[str(node_id)])
		var chosen := _choose_route(candidates, step)
		RunState.select_map_node(chosen)
		if chosen.type in ["battle", "elite", "boss"]:
			await _play_battle(str(chosen.battle_setup_id), chosen)
		else:
			_resolve_node(chosen)
		assert(int(RunState.player_state.hp.current) > 0, "自动试玩在第%d步死亡。" % (step + 1))
		map_rule.runtime_elite_counter = RunState.elite_encounter_counter
		generated_map = MapGenerator.new(31416 + step).advance_exploration(generated_map, str(chosen.id), map_rule)
		explored_nodes += 1
		if step >= 9 and _can_breakthrough():
			break
	assert(battles_won >= 3)
	assert(RunState.player_state.skills.spell_ids.size() >= 4, "中期应自然形成至少4门神通。")
	assert(RunState.visited_map_node_ids.size() >= 10)
	assert(_can_breakthrough(), "20个探索节点内应能通过合理选择满足炼气突破条件。")
	var run_summary := "battles=%d hp=%d spells=%d stones=%d relics=%d" % [battles_won, RunState.player_state.hp.current, RunState.player_state.skills.spell_ids.size(), RunState.spirit_stones, RunState.relics.size()]
	for method_choice: int in 5:
		RunState.reset_run()
		intro_choice_index = method_choice
		await _play_battle("battle_1_training_puppet", {})
		await _play_battle("battle_2_bandit", {})
		assert(int(RunState.player_state.hp.current) > 0, "第%d门入门功法无法独立通过强盗战。" % method_choice)
	print("VERTICAL_SLICE_PLAYTEST_PASS %s five_methods=PASS" % run_summary)
	get_tree().quit()


func _can_breakthrough() -> bool:
	var checks := node_manager.evaluate_rule("qi_to_foundation")
	return not checks.is_empty() and checks.all(func(check: Dictionary) -> bool: return bool(check.met))


func _choose_route(candidates: Array[Dictionary], step: int) -> Dictionary:
	var hp := int(RunState.player_state.hp.current)
	var preferred: Array = ["rest", "treasure", "cultivation", "event", "battle", "elite", "shop", "boss"] if hp <= 28 else (["battle", "elite", "treasure", "cultivation", "event", "shop", "rest", "boss"] if step % 2 == 0 else ["event", "cultivation", "treasure", "battle", "elite", "shop", "rest", "boss"])
	for type_id: String in preferred:
		for node: Dictionary in candidates:
			if str(node.type) == type_id:
				return node
	return candidates[0]


func _resolve_node(node: Dictionary) -> void:
	var content := node_manager.get_content(str(node.get("content_id", "")))
	var choice_index := 0
	if node.type == "rest":
		choice_index = 0
	elif node.type == "shop":
		for index: int in content.get("choices", []).size():
			if node_manager.can_afford_choice(str(node.content_id), index):
				choice_index = index
				break
	node_manager.apply_choice(str(node.get("content_id", "")), choice_index)
	RunState.complete_pending_map_node()


func _play_battle(setup_id: String, pending_node: Dictionary) -> void:
	RunState.current_battle_id = setup_id
	RunState.pending_map_node = pending_node.duplicate(true)
	var battle: BattleManager = battle_scene.instantiate()
	add_child(battle)
	await get_tree().process_frame
	var safety := 0
	while battle.phase == BattleManager.Phase.PLAYER_ACTION and safety < 80:
		safety += 1
		var acted := false
		var castable := battle.spell_manager.get_castable_spells(battle.qi_manager.get_sea_qi(), {"statuses": battle.player_state.statuses})
		for spell: Dictionary in castable:
			if spell.get("effects", []).any(func(effect: Dictionary) -> bool: return effect.get("type", "") == "damage"):
				battle._on_spell_selected(str(spell.id))
				acted = true
				break
		if battle.phase != BattleManager.Phase.PLAYER_ACTION:
			break
		if not acted:
			if int(battle.player_state.hp.current) <= 24 and int(battle.player_state.inventory.get("recovery_talisman", 0)) > 0:
				battle._on_item_selected("recovery_talisman")
			else:
				battle._on_enemy_action_requested()
	assert(safety < 80, "战斗策略陷入无穷循环：%s" % setup_id)
	assert(battle.phase == BattleManager.Phase.VICTORY, "战斗未能获胜：%s" % setup_id)
	battles_won += 1
	while not battle.rewards_resolved:
		var group: Dictionary = battle.reward_groups[battle.reward_group_index]
		var selected := 0
		if group.id == "intro_method_choice":
			selected = intro_choice_index
		elif group.id == "qi_refining_spell_choice":
			for index: int in group.options.size():
				var spell_id := str(group.options[index].get("spell_id", ""))
				if battle.reward_manager.spells.get(spell_id, {}).get("tags", []).has("fire"):
					selected = index
					break
		elif group.id == "qi_refining_qi_choice":
			for index: int in group.options.size():
				if group.options[index].get("qi", "") == "fire":
					selected = index
					break
		battle._on_reward_selected(selected)
		if not battle.pending_spell_reward.is_empty():
			var learned: Array = RunState.player_state.skills.spell_ids
			battle._on_spell_replacement_selected(str(learned[0]))
	RunState.clear_pending_map_node()
	battle.queue_free()
	await get_tree().process_frame
