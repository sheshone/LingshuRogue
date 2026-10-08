extends Node

const LEGACY_SAVE_PATH := "user://run_save.json"
const SAVE_DIRECTORY := "user://saves"
const SAVE_SLOT_COUNT := 3

# 单次游玩运行态。模板数据只用于初始化，所有变化仅保存在这里。
var initialized := false
var player_state: Dictionary = {}
var core_state: Dictionary = {}
var inventory: Dictionary = {}
var materials: Dictionary = {}
var relics: Array = []
var current_battle_id := "battle_1_training_puppet"
var learned_method_ids: Array[String] = []
var active_method_id := ""
var map_active := false
var current_realm_id := "qi_refining"
var current_map_id := ""
var current_map_node_id := ""
var previous_map_node_id := ""
var generated_map_definition: Dictionary = {}
var visited_map_node_ids: Array[String] = []
var completed_map_node_ids: Array[String] = []
var chapter_progress: Dictionary = {}
var pending_map_node: Dictionary = {}
var spirit_stones := 0
var elite_encounter_counter := 0
var node_offer_cache: Dictionary = {}
var run_completed := false
var completion_summary: Dictionary = {}
var active_save_slot := 1


func _save_path(slot: int = active_save_slot) -> String:
	return "%s/run_slot_%d.json" % [SAVE_DIRECTORY, clampi(slot, 1, SAVE_SLOT_COUNT)]


func has_save(slot: int = active_save_slot) -> bool:
	return FileAccess.file_exists(_save_path(slot)) or (slot == 1 and FileAccess.file_exists(LEGACY_SAVE_PATH))


func has_any_save() -> bool:
	for slot: int in range(1, SAVE_SLOT_COUNT + 1):
		if has_save(slot):
			return true
	return false


func save_game(slot: int = active_save_slot) -> bool:
	if not initialized:
		return false
	active_save_slot = clampi(slot, 1, SAVE_SLOT_COUNT)
	var payload := {
		"version": 1, "initialized": initialized, "player_state": player_state,
		"core_state": core_state, "inventory": inventory, "materials": materials,
		"relics": relics, "current_battle_id": current_battle_id,
		"learned_method_ids": learned_method_ids, "active_method_id": active_method_id,
		"map_active": map_active, "current_realm_id": current_realm_id,
		"current_map_id": current_map_id, "current_map_node_id": current_map_node_id,
		"previous_map_node_id": previous_map_node_id,
		"generated_map_definition": generated_map_definition,
		"visited_map_node_ids": visited_map_node_ids,
		"completed_map_node_ids": completed_map_node_ids, "chapter_progress": chapter_progress,
		"pending_map_node": pending_map_node, "spirit_stones": spirit_stones,
		"elite_encounter_counter": elite_encounter_counter,
		"node_offer_cache": node_offer_cache, "run_completed": run_completed,
		"completion_summary": completion_summary
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIRECTORY))
	var file := FileAccess.open(_save_path(active_save_slot), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	return true


func load_game(slot: int = active_save_slot) -> bool:
	active_save_slot = clampi(slot, 1, SAVE_SLOT_COUNT)
	if not has_save(active_save_slot):
		return false
	var path := _save_path(active_save_slot)
	if active_save_slot == 1 and not FileAccess.file_exists(path) and FileAccess.file_exists(LEGACY_SAVE_PATH):
		path = LEGACY_SAVE_PATH
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1:
		return false
	initialized = bool(parsed.get("initialized", false))
	player_state = Dictionary(parsed.get("player_state", {})).duplicate(true)
	core_state = Dictionary(parsed.get("core_state", {})).duplicate(true)
	inventory = Dictionary(parsed.get("inventory", {})).duplicate(true)
	player_state["inventory"] = inventory
	materials = Dictionary(parsed.get("materials", {})).duplicate(true)
	relics = Array(parsed.get("relics", [])).duplicate(true)
	current_battle_id = str(parsed.get("current_battle_id", "battle_1_training_puppet"))
	learned_method_ids.clear()
	for id: Variant in parsed.get("learned_method_ids", []): learned_method_ids.append(str(id))
	active_method_id = str(parsed.get("active_method_id", ""))
	map_active = bool(parsed.get("map_active", false))
	current_realm_id = str(parsed.get("current_realm_id", "qi_refining"))
	current_map_id = str(parsed.get("current_map_id", ""))
	current_map_node_id = str(parsed.get("current_map_node_id", ""))
	previous_map_node_id = str(parsed.get("previous_map_node_id", ""))
	generated_map_definition = Dictionary(parsed.get("generated_map_definition", {})).duplicate(true)
	visited_map_node_ids.clear()
	for id: Variant in parsed.get("visited_map_node_ids", []): visited_map_node_ids.append(str(id))
	completed_map_node_ids.clear()
	for id: Variant in parsed.get("completed_map_node_ids", []): completed_map_node_ids.append(str(id))
	chapter_progress = Dictionary(parsed.get("chapter_progress", {})).duplicate(true)
	pending_map_node = Dictionary(parsed.get("pending_map_node", {})).duplicate(true)
	spirit_stones = int(parsed.get("spirit_stones", 0))
	elite_encounter_counter = int(parsed.get("elite_encounter_counter", 0))
	node_offer_cache = Dictionary(parsed.get("node_offer_cache", {})).duplicate(true)
	run_completed = bool(parsed.get("run_completed", false))
	completion_summary = Dictionary(parsed.get("completion_summary", {})).duplicate(true)
	if path == LEGACY_SAVE_PATH:
		save_game(1)
	return initialized


func clear_save(slot: int = active_save_slot) -> void:
	var normalized := clampi(slot, 1, SAVE_SLOT_COUNT)
	var path := _save_path(normalized)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if normalized == 1 and FileAccess.file_exists(LEGACY_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_SAVE_PATH))


func initialize_run(player_template: Dictionary, runtime_seed: Dictionary, core_definition: Dictionary) -> void:
	if initialized:
		return
	player_state = UnitFactory.create_unit(player_template, "player", runtime_seed)
	# 尚未迁移的长期系统继续保留在玩家 Unit 上，但不进入公共 Unit 必填接口。
	player_state["artifacts"] = Array(runtime_seed.get("artifacts", [])).duplicate(true)
	player_state["companions"] = Array(runtime_seed.get("companions", [])).duplicate(true)
	var storage: Dictionary = core_definition.get("storage", {})
	core_state = {
		"definition_id": core_definition.get("id", ""),
		"stored_qi": Dictionary(storage.get("initial_qi", {})).duplicate(true),
		"base_capacity": int(storage.get("total_capacity", 0)),
		"attribute_capacity": Dictionary(storage.get("attribute_capacity", {})).duplicate(true),
		"capacity_modifiers": {},
		"conversion_modifiers": {},
		"pollution_modifiers": {}
	}
	inventory = player_state["inventory"]
	materials = Dictionary(runtime_seed.get("materials", {})).duplicate(true)
	relics = Array(runtime_seed.get("relics", [])).duplicate(true)
	learned_method_ids.clear()
	for method_id: Variant in runtime_seed.get("learned_method_ids", []):
		learned_method_ids.append(str(method_id))
	active_method_id = str(runtime_seed.get("active_method_id", ""))
	initialized = true


func add_item(item_id: String, quantity: int) -> int:
	if item_id.is_empty() or quantity <= 0:
		return 0
	inventory[item_id] = int(inventory.get(item_id, 0)) + quantity
	return quantity


func has_items(requirements: Dictionary) -> bool:
	for item_id: Variant in requirements:
		if int(inventory.get(str(item_id), 0)) < int(requirements[item_id]):
			return false
	return true


func consume_items(requirements: Dictionary) -> bool:
	if not has_items(requirements):
		return false
	for item_id: Variant in requirements:
		var normalized_id := str(item_id)
		inventory[normalized_id] = int(inventory.get(normalized_id, 0)) - int(requirements[item_id])
		if int(inventory[normalized_id]) <= 0:
			inventory.erase(normalized_id)
	return true


func get_inventory() -> Dictionary:
	return inventory.duplicate(true)


func learn_spell(spell_id: String) -> bool:
	var spell_ids: Array = player_state.get("skills", {}).get("spell_ids", [])
	if spell_id.is_empty() or spell_ids.has(spell_id):
		return false
	spell_ids.append(spell_id)
	player_state["skills"]["spell_ids"] = spell_ids
	return true


func forget_spell(spell_id: String) -> bool:
	var spell_ids: Array = player_state.get("skills", {}).get("spell_ids", [])
	var index := spell_ids.find(spell_id)
	if index < 0:
		return false
	spell_ids.remove_at(index)
	player_state["skills"]["spell_ids"] = spell_ids
	return true


func get_spiritual_sense_capacity() -> int:
	var sense: Dictionary = player_state.get("spiritual_sense", {})
	var total := int(sense.get("base_capacity", 0))
	for amount: Variant in sense.get("capacity_modifiers", {}).values():
		total += int(amount)
	return maxi(0, total)


func get_spiritual_sense_used(spell_definitions: Dictionary) -> int:
	var used := 0
	for spell_id: Variant in player_state.get("skills", {}).get("spell_ids", []):
		used += int(spell_definitions.get(str(spell_id), {}).get("sense_cost", 1))
	return used


func can_fit_spell(spell_id: String, spell_definitions: Dictionary) -> bool:
	if player_state.get("skills", {}).get("spell_ids", []).has(spell_id):
		return true
	var cost := int(spell_definitions.get(spell_id, {}).get("sense_cost", 1))
	return get_spiritual_sense_used(spell_definitions) + cost <= get_spiritual_sense_capacity()


func replace_spell(replaced_spell_id: String, new_spell_id: String, spell_definitions: Dictionary) -> bool:
	if replaced_spell_id == new_spell_id or not player_state.get("skills", {}).get("spell_ids", []).has(replaced_spell_id):
		return false
	var freed := int(spell_definitions.get(replaced_spell_id, {}).get("sense_cost", 1))
	var needed := int(spell_definitions.get(new_spell_id, {}).get("sense_cost", 1))
	var used_after_forget := get_spiritual_sense_used(spell_definitions) - freed
	if used_after_forget + needed > get_spiritual_sense_capacity():
		return false
	forget_spell(replaced_spell_id)
	return learn_spell(new_spell_id)


func add_spiritual_sense_capacity_modifier(source_id: String, amount: int) -> int:
	if source_id.is_empty() or amount == 0:
		return 0
	var sense: Dictionary = player_state.get("spiritual_sense", {})
	var modifiers: Dictionary = sense.get("capacity_modifiers", {})
	modifiers[source_id] = int(modifiers.get(source_id, 0)) + amount
	sense["capacity_modifiers"] = modifiers
	player_state["spiritual_sense"] = sense
	return amount


func set_spiritual_sense_capacity_modifier(source_id: String, amount: int) -> void:
	if source_id.is_empty():
		return
	var sense: Dictionary = player_state.get("spiritual_sense", {})
	var modifiers: Dictionary = sense.get("capacity_modifiers", {})
	if amount == 0:
		modifiers.erase(source_id)
	else:
		modifiers[source_id] = amount
	sense["capacity_modifiers"] = modifiers
	player_state["spiritual_sense"] = sense


func add_material(item_id: String, quantity: int) -> int:
	if item_id.is_empty() or quantity <= 0:
		return 0
	materials[item_id] = int(materials.get(item_id, 0)) + quantity
	return quantity


func consume_material(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0 or int(materials.get(item_id, 0)) < quantity:
		return false
	materials[item_id] = int(materials.get(item_id, 0)) - quantity
	if int(materials[item_id]) <= 0:
		materials.erase(item_id)
	return true


func learn_method(method_id: String) -> bool:
	if method_id.is_empty() or learned_method_ids.has(method_id):
		return false
	learned_method_ids.append(method_id)
	return true


func add_relic(relic_id: String) -> bool:
	if relic_id.is_empty() or relics.has(relic_id):
		return false
	relics.append(relic_id)
	return true


func add_spirit_stones(amount: int) -> int:
	if amount <= 0:
		return 0
	spirit_stones += amount
	return amount


func spend_spirit_stones(amount: int) -> bool:
	if amount < 0 or spirit_stones < amount:
		return false
	spirit_stones -= amount
	return true


func set_active_method(method_id: String) -> bool:
	if not learned_method_ids.has(method_id):
		return false
	active_method_id = method_id
	return true


func consume_unit_item(unit: Dictionary, item_id: String, quantity: int = 1) -> bool:
	var unit_inventory: Dictionary = unit.get("inventory", {})
	if quantity <= 0 or int(unit_inventory.get(item_id, 0)) < quantity:
		return false
	unit_inventory[item_id] = int(unit_inventory[item_id]) - quantity
	if int(unit_inventory[item_id]) <= 0:
		unit_inventory.erase(item_id)
	unit["inventory"] = unit_inventory
	return true


func add_core_qi(qi_id: String, amount: int) -> int:
	if amount <= 0 or not core_state.get("stored_qi", {}).has(qi_id):
		return 0
	var stored: Dictionary = core_state.get("stored_qi", {})
	var total_capacity := get_core_capacity()
	var attribute_capacities: Dictionary = core_state.get("attribute_capacity", {})
	var modifiers: Dictionary = core_state.get("capacity_modifiers", {})
	var attribute_capacity := int(attribute_capacities.get(qi_id, total_capacity)) + int(modifiers.get(qi_id, 0))
	var accepted := mini(amount, mini(maxi(0, total_capacity - get_core_qi_total()), maxi(0, attribute_capacity - int(stored.get(qi_id, 0)))))
	stored[qi_id] = int(stored.get(qi_id, 0)) + accepted
	core_state["stored_qi"] = stored
	return accepted


func add_core_capacity(amount: int) -> int:
	if amount <= 0:
		return 0
	var modifiers: Dictionary = core_state.get("capacity_modifiers", {})
	modifiers["total"] = int(modifiers.get("total", 0)) + amount
	core_state["capacity_modifiers"] = modifiers
	return amount


func convert_core_qi(from_qi: String, to_qi: String, amount: int) -> int:
	if amount <= 0 or from_qi == to_qi:
		return 0
	var stored: Dictionary = core_state.get("stored_qi", {})
	if not stored.has(from_qi) or not stored.has(to_qi):
		return 0
	var converted := mini(amount, int(stored.get(from_qi, 0)))
	stored[from_qi] = int(stored.get(from_qi, 0)) - converted
	core_state["stored_qi"] = stored
	var accepted := add_core_qi(to_qi, converted)
	if accepted < converted:
		stored = core_state.get("stored_qi", {})
		stored[from_qi] = int(stored.get(from_qi, 0)) + converted - accepted
		core_state["stored_qi"] = stored
	return accepted


func get_core_qi_total() -> int:
	var total := 0
	for amount: Variant in core_state.get("stored_qi", {}).values():
		total += int(amount)
	return total


func get_core_capacity() -> int:
	return int(core_state.get("base_capacity", 0)) + int(core_state.get("capacity_modifiers", {}).get("total", 0))


func start_map(map_id: String, start_node_id: String) -> void:
	map_active = true
	current_map_id = map_id
	current_map_node_id = start_node_id
	previous_map_node_id = ""
	generated_map_definition.clear()
	visited_map_node_ids.clear()
	completed_map_node_ids.clear()
	chapter_progress.clear()
	_mark_visited(start_node_id)
	pending_map_node.clear()
	node_offer_cache.clear()
	run_completed = false
	completion_summary.clear()


func complete_realm(realm_id: String) -> void:
	run_completed = true
	map_active = false
	completion_summary = {
		"realm_id": realm_id,
		"visited": visited_map_node_ids.size(),
		"battles": int(chapter_progress.get("battle_completed", 0)),
		"elites": int(chapter_progress.get("elite_completed", 0)),
		"bosses": int(chapter_progress.get("boss_completed", 0)),
		"spells": Array(player_state.get("skills", {}).get("spell_ids", [])).size(),
		"relics": relics.size(),
		"core_qi": get_core_qi_total(),
		"spirit_stones": spirit_stones
	}


func select_map_node(node: Dictionary) -> void:
	previous_map_node_id = current_map_node_id
	current_map_node_id = str(node.get("id", ""))
	_mark_visited(current_map_node_id)
	pending_map_node = node.duplicate(true)


func complete_pending_map_node() -> void:
	var node_id := str(pending_map_node.get("id", current_map_node_id))
	if node_id.is_empty() or completed_map_node_ids.has(node_id):
		return
	completed_map_node_ids.append(node_id)
	var type_id := str(pending_map_node.get("type", ""))
	if not type_id.is_empty():
		var progress_key := "%s_completed" % type_id
		chapter_progress[progress_key] = int(chapter_progress.get(progress_key, 0)) + 1
	if type_id == "elite":
		elite_encounter_counter = 0
	elif type_id in ["battle", "event", "cultivation", "rest", "treasure", "shop"]:
		elite_encounter_counter += 1


func _mark_visited(node_id: String) -> void:
	if not node_id.is_empty() and not visited_map_node_ids.has(node_id):
		visited_map_node_ids.append(node_id)


func clear_pending_map_node() -> void:
	pending_map_node.clear()


func return_from_breakthrough_check() -> void:
	if not previous_map_node_id.is_empty():
		current_map_node_id = previous_map_node_id
	pending_map_node.clear()


func reset_run() -> void:
	initialized = false
	player_state.clear()
	core_state.clear()
	inventory.clear()
	materials.clear()
	relics.clear()
	learned_method_ids.clear()
	active_method_id = ""
	current_battle_id = "battle_1_training_puppet"
	map_active = false
	current_realm_id = "qi_refining"
	current_map_id = ""
	current_map_node_id = ""
	previous_map_node_id = ""
	generated_map_definition.clear()
	visited_map_node_ids.clear()
	completed_map_node_ids.clear()
	chapter_progress.clear()
	pending_map_node.clear()
	spirit_stones = 0
	elite_encounter_counter = 0
	node_offer_cache.clear()
	run_completed = false
	completion_summary.clear()
