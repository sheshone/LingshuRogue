extends SceneTree


func _initialize() -> void:
	var run_state: Node = root.get_node("RunState")
	run_state.reset_run()
	run_state.initialized = true
	run_state.player_state = {"inventory": {}, "skills": {"spell_ids": ["qi_strike"]}}
	run_state.inventory = run_state.player_state.inventory
	run_state.core_state = {"stored_qi": {"fire": 7}, "base_capacity": 100, "capacity_modifiers": {}}
	run_state.spirit_stones = 37
	run_state.current_map_id = "save_test_map"
	assert(run_state.save_game())
	run_state.reset_run()
	assert(run_state.load_game())
	assert(run_state.spirit_stones == 37)
	assert(run_state.current_map_id == "save_test_map")
	assert(Array(run_state.player_state.skills.spell_ids).has("qi_strike"))
	run_state.clear_save()
	run_state.reset_run()
	print("SAVE_ROUNDTRIP_OK")
	quit()
