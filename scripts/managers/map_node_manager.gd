class_name MapNodeManager
extends RefCounted

const CONTENT_PATH := "res://data/map_node_contents.json"
const PROCESSING_PATH := "res://data/processing_recipes.json"

var contents: Dictionary = {}
var items: Dictionary = {}
var breakthrough_rules: Dictionary = {}
var methods: Dictionary = {}
var spells: Dictionary = {}
var relics: Dictionary = {}
var processing_recipes: Dictionary = {}
var offer_tables: Dictionary = {}
var random := RandomNumberGenerator.new()


func configure() -> void:
	contents = GameDataLoader.index_by_id(
		GameDataLoader.load_collection(CONTENT_PATH, "node_contents"),
		"map_node_contents.json"
	)
	items = GameDataLoader.index_by_id(
		GameDataLoader.load_collection("res://data/items.json", "items"),
		"items.json"
	)
	breakthrough_rules = GameDataLoader.index_by_id(
		GameDataLoader.load_collection("res://data/breakthrough_rules.json", "breakthrough_rules"),
		"breakthrough_rules.json"
	)
	methods = GameDataLoader.index_by_id(
		GameDataLoader.load_collection("res://data/cultivation_methods.json", "cultivation_methods"),
		"cultivation_methods.json"
	)
	spells = GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/spells.json", "spells"), "spells.json")
	relics = GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/relics.json", "relics"), "relics.json")
	processing_recipes = GameDataLoader.index_by_id(GameDataLoader.load_collection(PROCESSING_PATH, "processing_recipes"), "processing_recipes.json")
	offer_tables = GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/node_offer_tables.json", "node_offer_tables"), "node_offer_tables.json")
	random.randomize()


func get_runtime_content(node: Dictionary) -> Dictionary:
	var content := get_content(str(node.get("content_id", "")))
	var type_id := str(node.get("type", ""))
	if type_id not in ["shop", "treasure"]:
		return content
	var cache_id := str(node.get("id", ""))
	if not RunState.node_offer_cache.has(cache_id):
		RunState.node_offer_cache[cache_id] = _generate_offers(type_id)
	content["choices"] = Array(RunState.node_offer_cache.get(cache_id, [])).duplicate(true)
	return content


func _generate_offers(type_id: String) -> Array:
	var table: Dictionary = offer_tables.get("qi_refining_%s" % type_id, {})
	var candidates: Array = []
	for entry: Variant in table.get("entries", []):
		if entry is Dictionary and _choice_available(entry):
			var weight := int(entry.get("weight", 10))
			var tags: Array = entry.get("tags", [])
			var method_id := RunState.active_method_id.trim_suffix("_method")
			if not method_id.is_empty() and tags.has(method_id):
				weight += int(table.get("affinity_bonus", 4))
			candidates.append({"choice": Dictionary(entry).duplicate(true), "weight": weight})
	var result: Array = []
	var count := mini(int(table.get("offer_count", 3)), candidates.size())
	# 商店先保证基础品类，再用权重补足货架，避免一次随机结果全是攻击神通。
	if type_id == "shop":
		for category: String in ["consumable", "spell", "relic", "service"]:
			if result.size() >= count:
				break
			var category_candidates: Array = []
			for candidate_index: int in candidates.size():
				if _offer_category(candidates[candidate_index].choice) == category:
					category_candidates.append({"source_index": candidate_index, "weight": candidates[candidate_index].weight})
			if category_candidates.is_empty():
				continue
			var picked_local := _weighted_candidate(category_candidates)
			var picked_source := int(category_candidates[picked_local].source_index)
			var guaranteed: Dictionary = candidates[picked_source].choice
			guaranteed.erase("weight")
			guaranteed.erase("tags")
			result.append(guaranteed)
			candidates.remove_at(picked_source)
	for _index: int in count - result.size():
		var selected := _weighted_candidate(candidates)
		if selected < 0:
			break
		var choice: Dictionary = candidates[selected].choice
		choice.erase("weight")
		choice.erase("tags")
		result.append(choice)
		candidates.remove_at(selected)
	return result


func _offer_category(choice: Dictionary) -> String:
	for effect: Variant in choice.get("effects", []):
		if not effect is Dictionary:
			continue
		match str(effect.get("type", "")):
			"learn_spell": return "spell"
			"add_relic": return "relic"
			"add_item": return "consumable"
			"convert_core_qi", "forget_spell": return "service"
	return "other"


func _weighted_candidate(candidates: Array) -> int:
	var total := 0
	for candidate: Dictionary in candidates:
		total += maxi(1, int(candidate.weight))
	if total <= 0:
		return -1
	var roll := random.randi_range(1, total)
	for index: int in candidates.size():
		roll -= maxi(1, int(candidates[index].weight))
		if roll <= 0:
			return index
	return candidates.size() - 1


func _choice_available(choice: Dictionary) -> bool:
	for effect: Variant in choice.get("effects", []):
		if not effect is Dictionary:
			continue
		if effect.get("type", "") == "add_relic" and RunState.relics.has(str(effect.get("relic_id", ""))):
			return false
		if effect.get("type", "") == "learn_spell" and RunState.player_state.get("skills", {}).get("spell_ids", []).has(str(effect.get("spell_id", ""))):
			return false
	return true


func apply_runtime_choice(choice: Dictionary) -> Array[String]:
	var messages: Array[String] = []
	if not can_afford_runtime_choice(choice):
		return ["灵石或条件不足，交易没有发生。"]
	var cost := int(choice.get("spirit_stone_cost", 0))
	if cost > 0:
		RunState.spend_spirit_stones(cost)
	for effect: Variant in choice.get("effects", []):
		if effect is Dictionary:
			messages.append(_apply_effect(effect))
	return messages


func can_afford_runtime_choice(choice: Dictionary) -> bool:
	if RunState.spirit_stones < int(choice.get("spirit_stone_cost", 0)):
		return false
	return _choice_available(choice)


func get_content(content_id: String) -> Dictionary:
	return Dictionary(contents.get(content_id, {})).duplicate(true)


func apply_choice(content_id: String, choice_index: int) -> Array[String]:
	var content := get_content(content_id)
	var choices: Array = content.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size() or not choices[choice_index] is Dictionary:
		return ["该选择无效。"]
	var messages: Array[String] = []
	for effect: Variant in choices[choice_index].get("effects", []):
		if effect is Dictionary and effect.get("type", "") == "learn_spell":
			var spell_id := str(effect.get("spell_id", ""))
			if not spells.has(spell_id) or not RunState.can_fit_spell(spell_id, spells) or RunState.player_state.get("skills", {}).get("spell_ids", []).has(spell_id):
				return ["神识容量不足，或已经掌握该神通。灵石未被消耗。"]
		if effect is Dictionary and effect.get("type", "") == "add_relic" and RunState.relics.has(str(effect.get("relic_id", ""))):
			return ["已经拥有该法宝。灵石未被消耗。"]
		if effect is Dictionary and effect.get("type", "") == "forget_spell" and not RunState.player_state.get("skills", {}).get("spell_ids", []).has(str(effect.get("spell_id", ""))):
			return ["当前没有掌握该神通。灵石未被消耗。"]
	var cost := int(choices[choice_index].get("spirit_stone_cost", 0))
	if cost > 0 and not RunState.spend_spirit_stones(cost):
		return ["灵石不足，需要%d枚灵石。" % cost]
	for effect: Variant in choices[choice_index].get("effects", []):
		if effect is Dictionary:
			messages.append(_apply_effect(effect))
	return messages


func can_afford_choice(content_id: String, choice_index: int) -> bool:
	var choices: Array = get_content(content_id).get("choices", [])
	if choice_index < 0 or choice_index >= choices.size() or RunState.spirit_stones < int(choices[choice_index].get("spirit_stone_cost", 0)):
		return false
	for effect: Variant in choices[choice_index].get("effects", []):
		if not effect is Dictionary:
			continue
		if effect.get("type", "") == "learn_spell":
			var spell_id := str(effect.get("spell_id", ""))
			if not spells.has(spell_id) or not RunState.can_fit_spell(spell_id, spells) or RunState.player_state.get("skills", {}).get("spell_ids", []).has(spell_id):
				return false
		if effect.get("type", "") == "add_relic" and RunState.relics.has(str(effect.get("relic_id", ""))):
			return false
		if effect.get("type", "") == "forget_spell" and not RunState.player_state.get("skills", {}).get("spell_ids", []).has(str(effect.get("spell_id", ""))):
			return false
		if effect.get("type", "") == "convert_core_qi" and int(RunState.core_state.get("stored_qi", {}).get(str(effect.get("from_qi", "")), 0)) < int(effect.get("value", 0)):
			return false
		if effect.get("type", "") == "process_recipe":
			var recipe: Dictionary = processing_recipes.get(str(effect.get("recipe_id", "")), {})
			if recipe.is_empty() or int(RunState.materials.get(str(recipe.get("consume", "")), 0)) < int(recipe.get("quantity", 1)):
				return false
	return true


func evaluate_rule(rule_id: String) -> Array[Dictionary]:
	return _evaluate_rule(Dictionary(breakthrough_rules.get(rule_id, {})))


func evaluate_conditions(content_id: String) -> Array[Dictionary]:
	var content := get_content(content_id)
	var rule: Dictionary = breakthrough_rules.get(str(content.get("breakthrough_rule_id", "")), {})
	return _evaluate_rule(rule)


func _evaluate_rule(rule: Dictionary) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for condition: Variant in rule.get("conditions", []):
		if not condition is Dictionary:
			continue
		var type_id := str(condition.get("type", ""))
		var target := int(condition.get("value", 0))
		var current := 0
		var met := false
		match type_id:
			"core_qi_total":
				current = RunState.get_core_qi_total()
				met = current >= target
			"method_affinity_qi":
				var affinity_result := _evaluate_method_affinity(condition)
				current = int(affinity_result.current)
				target = int(affinity_result.target)
				met = bool(affinity_result.met)
				results.append({
					"type": type_id,
					"label": str(condition.get("label", type_id)),
					"current": current,
					"target": target,
					"met": met,
					"detail": str(affinity_result.detail)
				})
				continue
			"active_method":
				current = 1 if not RunState.active_method_id.is_empty() else 0
				target = 1
				met = current >= target
			"learned_spell_count":
				current = Array(RunState.player_state.get("skills", {}).get("spell_ids", [])).size()
				met = current >= target
			_:
				push_warning("暂不支持的突破条件：%s" % type_id)
		results.append({
			"type": type_id,
			"label": str(condition.get("label", type_id)),
			"current": current,
			"target": target,
			"met": met
		})
	return results


func _evaluate_method_affinity(condition: Dictionary) -> Dictionary:
	var method: Dictionary = methods.get(RunState.active_method_id, {})
	var affinities: Dictionary = method.get("element_affinity", {})
	if affinities.is_empty():
		return {"current": 0, "target": int(condition.get("minimum", 0)), "met": false, "detail": "尚未选择主功法"}
	var affinity_qi := ""
	var strongest := -1.0
	for qi_id: Variant in affinities:
		var affinity := float(affinities[qi_id])
		if affinity > strongest:
			strongest = affinity
			affinity_qi = str(qi_id)
	var stored: Dictionary = RunState.core_state.get("stored_qi", {})
	var current := int(stored.get(affinity_qi, 0))
	var total := RunState.get_core_qi_total()
	var ratio := float(current) / float(total) if total > 0 else 0.0
	var target := int(condition.get("minimum", 0))
	var target_ratio := float(condition.get("minimum_ratio", 0.0))
	return {
		"current": current,
		"target": target,
		"met": current >= target and ratio >= target_ratio,
		"detail": "%s灵气：%d / %d，占比%d%% / %d%%" % [
			_qi_name(affinity_qi), current, target, roundi(ratio * 100.0), roundi(target_ratio * 100.0)
		]
	}


func _apply_effect(effect: Dictionary) -> String:
	match str(effect.get("type", "")):
		"add_core_qi":
			var qi_id := str(effect.get("qi", ""))
			var accepted := RunState.add_core_qi(qi_id, int(effect.get("value", 0)))
			return "灵枢 · %s +%d" % [_qi_name(qi_id), accepted]
		"add_core_capacity":
			var accepted := RunState.add_core_capacity(int(effect.get("value", 0)))
			return "灵枢容量增加%d。" % accepted
		"add_item":
			var item_id := str(effect.get("item_id", ""))
			var quantity := RunState.add_item(item_id, int(effect.get("quantity", 1)))
			return "获得%s ×%d。" % [items.get(item_id, {}).get("name", "未知物品"), quantity]
		"add_spirit_stones":
			var amount := RunState.add_spirit_stones(int(effect.get("value", 0)))
			return "获得灵石%d枚。" % amount
		"learn_spell":
			var spell_id := str(effect.get("spell_id", ""))
			if spells.has(spell_id) and RunState.can_fit_spell(spell_id, spells) and RunState.learn_spell(spell_id):
				return "学会神通：%s。" % spells[spell_id].get("name", spell_id)
			return "未能学会神通，可能已掌握或神识容量不足。"
		"add_relic":
			var relic_id := str(effect.get("relic_id", ""))
			if relics.has(relic_id) and RunState.add_relic(relic_id):
				for relic_effect: Variant in relics[relic_id].get("effects", []):
					if relic_effect is Dictionary and relic_effect.get("type", "") == "modifier" and relic_effect.get("target", "") == "player_rule:spiritual_sense_capacity" and relic_effect.get("effect", "") == "capacity_up":
						RunState.set_spiritual_sense_capacity_modifier("relic:%s" % relic_id, int(relic_effect.get("value", 0)))
				return "获得法宝：%s。" % relics[relic_id].get("name", relic_id)
			return "该法宝已在行囊之中。"
		"forget_spell":
			var spell_id := str(effect.get("spell_id", ""))
			if RunState.forget_spell(spell_id):
				return "已遗忘神通：%s。" % spells.get(spell_id, {}).get("name", spell_id)
			return "未能遗忘该神通。"
		"process_recipe":
			var recipe: Dictionary = processing_recipes.get(str(effect.get("recipe_id", "")), {})
			var material_id := str(recipe.get("consume", ""))
			if recipe.is_empty() or not RunState.consume_material(material_id, int(recipe.get("quantity", 1))):
				return "缺少炼化材料。"
			var messages: Array[String] = []
			for recipe_effect: Variant in recipe.get("effects", []):
				if recipe_effect is Dictionary:
					messages.append(_apply_effect(recipe_effect))
			return "炼化完成：%s" % " ".join(messages)
		"heal_player_full":
			if not RunState.player_state.is_empty():
				RunState.player_state.hp.current = RunState.player_state.hp.max
			return "生命已完全恢复。"
		"convert_core_qi":
			var from_qi := str(effect.get("from_qi", ""))
			var to_qi := str(effect.get("to_qi", ""))
			var converted := RunState.convert_core_qi(from_qi, to_qi, int(effect.get("value", 0)))
			return "%s灵气转化为%s灵气%d点。" % [_qi_name(from_qi), _qi_name(to_qi), converted]
		_:
			push_warning("暂不支持的地图节点效果：%s" % effect.get("type", ""))
			return "该结果暂未实现。"


func _qi_name(qi_id: String) -> String:
	return {
		"metal": "金", "wood": "木", "water": "水", "fire": "火", "earth": "土"
	}.get(qi_id, qi_id)
