class_name MapGenerator
extends RefCounted

var random := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		random.randomize()
	else:
		random.seed = seed_value


func generate(base_map: Dictionary, rule: Dictionary) -> Dictionary:
	if str(rule.get("mode", "")) == "choice_opening":
		return _generate_choice_opening(base_map, rule)
	if str(rule.get("mode", "")) == "rolling_exploration":
		return _generate_exploration(base_map, rule)
	return base_map.duplicate(true)


func _generate_choice_opening(base_map: Dictionary, rule: Dictionary) -> Dictionary:
	var result := base_map.duplicate(true)
	var indexed := _index_nodes(result.get("nodes", []))
	var origin: Dictionary = indexed.get(str(result.get("start_node_id", "initiation_origin")), {}).duplicate(true)
	var pool: Array = rule.get("choice_pool", []).duplicate(true)
	pool.shuffle()
	var choices: Array[Dictionary] = []
	for index: int in mini(int(rule.get("choice_count", 3)), pool.size()):
		var entry: Dictionary = Dictionary(pool[index]).duplicate(true)
		entry["id"] = "initiation_choice_%d" % index
		entry["layer"] = 1
		entry["next_node_ids"] = []
		choices.append(entry)
	origin["layer"] = 0
	origin["next_node_ids"] = _node_ids(choices)
	var nodes: Array = [origin]
	nodes.append_array(choices)
	result["nodes"] = nodes
	result["current_node_id"] = str(origin.get("id", "initiation_origin"))
	return result


func advance_exploration(map_data: Dictionary, selected_id: String, rule: Dictionary) -> Dictionary:
	var result := map_data.duplicate(true)
	var indexed := _index_nodes(result.get("nodes", []))
	var selected: Dictionary = indexed.get(selected_id, {}).duplicate(true)
	if selected.is_empty():
		return result
	var depth := int(result.get("exploration_depth", 0)) + 1
	selected["layer"] = 0
	selected["depth"] = depth
	var reachable: Array[Dictionary] = []
	for node_id: Variant in selected.get("next_node_ids", []):
		var existing: Dictionary = indexed.get(str(node_id), {})
		if not existing.is_empty():
			var copy := existing.duplicate(true)
			copy["layer"] = 1
			reachable.append(copy)
	if reachable.is_empty():
		reachable = _create_layer(depth + 1, int(rule.get("reachable_count", 3)), rule)
	_enforce_elite_guarantee(reachable, rule)
	var future := _create_layer(depth + 2, int(rule.get("future_count", 3)), rule)
	_connect_layers(reachable, future, int(rule.get("connections_per_node", 2)))
	selected["next_node_ids"] = _node_ids(reachable)
	var nodes: Array = [selected]
	nodes.append_array(reachable)
	nodes.append_array(future)
	result["nodes"] = nodes
	result["current_node_id"] = selected_id
	result["exploration_depth"] = depth
	return result


func _enforce_elite_guarantee(nodes: Array[Dictionary], rule: Dictionary) -> void:
	var elite_rule: Dictionary = rule.get("elite_encounter", {})
	if int(rule.get("runtime_elite_counter", 0)) < int(elite_rule.get("guaranteed_at", 6)):
		return
	if nodes.any(func(node: Dictionary) -> bool: return node.get("type", "") == "elite"):
		return
	if not nodes.is_empty():
		_fill_node(nodes[0], "elite", rule)


func _generate_exploration(base_map: Dictionary, rule: Dictionary) -> Dictionary:
	var result := base_map.duplicate(true)
	var indexed := _index_nodes(result.get("nodes", []))
	var origin: Dictionary = indexed.get(str(result.get("start_node_id", "realm_origin")), {}).duplicate(true)
	var reachable := _create_layer(1, int(rule.get("reachable_count", 3)), rule)
	var future := _create_layer(2, int(rule.get("future_count", 3)), rule)
	_connect_layers(reachable, future, int(rule.get("connections_per_node", 2)))
	origin["layer"] = 0
	origin["depth"] = 0
	origin["next_node_ids"] = _node_ids(reachable)
	var nodes: Array = [origin]
	nodes.append_array(reachable)
	nodes.append_array(future)
	result["nodes"] = nodes
	result["current_node_id"] = str(origin.get("id", "realm_origin"))
	result["exploration_depth"] = 0
	result["generation_rule_id"] = str(rule.get("id", ""))
	return result


func _create_layer(depth: int, count: int, rule: Dictionary) -> Array[Dictionary]:
	var layer: Array[Dictionary] = []
	var elite_rule: Dictionary = rule.get("elite_encounter", {})
	var counter := int(rule.get("runtime_elite_counter", 0))
	var threshold := int(elite_rule.get("guaranteed_at", 6))
	var forced_elite_index := random.randi_range(0, count - 1) if count > 0 and counter >= threshold else -1
	var boss_rule: Dictionary = rule.get("boss_encounter", {})
	var forced_boss_index := random.randi_range(0, count - 1) if count > 0 and depth >= int(boss_rule.get("guaranteed_at_depth", 12)) else -1
	if forced_boss_index == forced_elite_index:
		forced_elite_index = (forced_elite_index + 1) % count
	for index: int in count:
		var node := {
			"id": "explore_%d_%d_%d" % [depth, index, random.randi()],
			"layer": depth,
			"depth": depth,
			"next_node_ids": []
		}
		var type_id := "boss" if index == forced_boss_index else ("elite" if index == forced_elite_index else _pick_exploration_type(rule, counter, not layer.any(func(existing: Dictionary) -> bool: return existing.get("type", "") == "elite"), depth, not layer.any(func(existing: Dictionary) -> bool: return existing.get("type", "") == "boss")))
		_fill_node(node, type_id, rule)
		for retry: int in 4:
			if not layer.any(func(existing: Dictionary) -> bool: return existing.get("name", "") == node.get("name", "")):
				break
			_fill_node(node, type_id, rule)
		layer.append(node)
	return layer


func _pick_exploration_type(rule: Dictionary, counter: int, elite_allowed: bool, depth: int, boss_allowed: bool) -> String:
	var weights: Dictionary = Dictionary(rule.get("type_weights", {})).duplicate(true)
	var elite_rule: Dictionary = rule.get("elite_encounter", {})
	if elite_allowed:
		weights["elite"] = int(elite_rule.get("base_weight", 2)) + counter * int(elite_rule.get("weight_per_node", 4))
	else:
		weights["elite"] = 0
	var boss_rule: Dictionary = rule.get("boss_encounter", {})
	var minimum_depth := int(boss_rule.get("minimum_depth", 7))
	weights["boss"] = (int(weights.get("boss", 0)) + maxi(0, depth - minimum_depth) * int(boss_rule.get("weight_per_depth", 3))) if boss_allowed and depth >= minimum_depth else 0
	return _pick_weighted_type(weights)


func _connect_layers(from_nodes: Array[Dictionary], to_nodes: Array[Dictionary], connection_count: int) -> void:
	if to_nodes.is_empty():
		return
	var count := clampi(connection_count, 1, maxi(1, to_nodes.size() - 1))
	var incoming := {}
	for index: int in from_nodes.size():
		var targets: Array[String] = []
		var start := clampi(index + random.randi_range(-1, 1), 0, to_nodes.size() - 1)
		for offset: int in count:
			var target_index := clampi(start + offset, 0, to_nodes.size() - 1)
			var target_id := str(to_nodes[target_index].get("id", ""))
			if not targets.has(target_id):
				targets.append(target_id)
				incoming[target_id] = true
		from_nodes[index]["next_node_ids"] = targets
	# 避免生成看得见却永远不可达的孤立节点。
	for target_index: int in to_nodes.size():
		var target_id := str(to_nodes[target_index].get("id", ""))
		if incoming.has(target_id) or from_nodes.is_empty():
			continue
		var source_index := clampi(target_index, 0, from_nodes.size() - 1)
		from_nodes[source_index]["next_node_ids"].append(target_id)


func _pick_weighted_type(weights: Dictionary) -> String:
	var total := 0
	for value: Variant in weights.values():
		total += maxi(0, int(value))
	if total <= 0:
		return "battle"
	var roll := random.randi_range(1, total)
	for type_id: Variant in weights:
		roll -= maxi(0, int(weights[type_id]))
		if roll <= 0:
			return str(type_id)
	return "battle"


func _fill_node(node: Dictionary, type_id: String, rule: Dictionary) -> void:
	node["type"] = type_id
	var pool: Array = rule.get("%s_pool" % type_id, [])
	if pool.is_empty():
		push_warning("地图生成池为空：%s_pool" % type_id)
		return
	var entry: Dictionary = pool[random.randi_range(0, pool.size() - 1)]
	for key: String in entry:
		node[key] = entry[key]


func _index_nodes(node_list: Array) -> Dictionary:
	var result := {}
	for node: Variant in node_list:
		if node is Dictionary:
			result[str(node.get("id", ""))] = node
	return result


func _node_ids(node_list: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for node: Dictionary in node_list:
		result.append(str(node.get("id", "")))
	return result
