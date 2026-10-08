class_name RewardManager
extends Node

const QI_NAMES := {
	"metal": "金", "wood": "木", "water": "水", "fire": "火", "earth": "土"
}

var reward_tables: Dictionary = {}
var items: Dictionary = {}
var spells: Dictionary = {}
var methods: Dictionary = {}
var relics: Dictionary = {}


func configure(reward_definitions: Array, item_definitions: Array, spell_definitions: Array = [], method_definitions: Array = [], relic_definitions: Array = []) -> void:
	reward_tables = GameDataLoader.index_by_id(reward_definitions, "reward_tables.json")
	items = GameDataLoader.index_by_id(item_definitions, "items.json")
	spells = GameDataLoader.index_by_id(spell_definitions, "spells.json")
	methods = GameDataLoader.index_by_id(method_definitions, "cultivation_methods.json")
	relics = GameDataLoader.index_by_id(relic_definitions, "relics.json")


func build_reward_groups(reward_table_ids: Array[String]) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var fixed_rewards: Array[Dictionary] = []
	var visited_tables: Dictionary = {}
	for table_id: String in reward_table_ids:
		_collect_table_rewards(table_id, fixed_rewards, groups, visited_tables)
	if not fixed_rewards.is_empty():
		groups.push_front({
			"id": "fixed_rewards",
			"mode": "fixed",
			"choose": fixed_rewards.size(),
			"options": fixed_rewards
		})
	return groups


func _collect_table_rewards(table_id: String, fixed_rewards: Array[Dictionary], groups: Array[Dictionary], visited_tables: Dictionary) -> void:
	if visited_tables.has(table_id):
		return
	visited_tables[table_id] = true
	var table: Dictionary = reward_tables.get(table_id, {})
	if table.is_empty():
		push_warning("找不到奖励表：%s" % table_id)
		return
	for reward: Variant in table.get("fixed_rewards", []):
		if reward is Dictionary:
			fixed_rewards.append(Dictionary(reward).duplicate(true))
	for included_id: Variant in table.get("include_table_ids", []):
		_collect_table_rewards(str(included_id), fixed_rewards, groups, visited_tables)
	for choice_group: Variant in table.get("choice_groups", []):
		if not choice_group is Dictionary:
			continue
		var eligible_options: Array = []
		for option: Variant in choice_group.get("options", []):
			if option is Dictionary and _is_reward_eligible(option):
				eligible_options.append(Dictionary(option).duplicate(true))
		if eligible_options.is_empty():
			continue
		if bool(choice_group.get("randomize", false)):
			eligible_options = _pick_weighted_options(eligible_options, int(choice_group.get("candidate_count", eligible_options.size())))
		var candidate_count := mini(int(choice_group.get("candidate_count", eligible_options.size())), eligible_options.size())
		eligible_options = eligible_options.slice(0, candidate_count)
		groups.append({
			"id": str(choice_group.get("id", "choice")),
			"title": str(choice_group.get("title", "选择一项奖励")),
			"mode": "choice",
			"choose": int(choice_group.get("choose", 1)),
			"skippable": bool(choice_group.get("skippable", false)),
			"options": eligible_options
		})


func _pick_weighted_options(options: Array, count: int) -> Array:
	var remaining := options.duplicate(true)
	var selected: Array = []
	while not remaining.is_empty() and selected.size() < count:
		var total_weight := 0
		for option: Dictionary in remaining:
			total_weight += _reward_weight(option)
		var roll := randi_range(1, total_weight)
		var selected_index := 0
		for index: int in remaining.size():
			roll -= _reward_weight(remaining[index])
			if roll <= 0:
				selected_index = index
				break
		selected.append(remaining.pop_at(selected_index))
	return selected


func _reward_weight(option: Dictionary) -> int:
	var weight := maxi(1, int(option.get("weight", 1)))
	var method: Dictionary = methods.get(RunState.active_method_id, {})
	var affinities: Dictionary = method.get("element_affinity", {})
	if option.get("type", "") == "learn_spell":
		var spell: Dictionary = spells.get(str(option.get("spell_id", "")), {})
		for qi_id: Variant in affinities:
			if spell.get("tags", []).has(str(qi_id)):
				weight += int(option.get("affinity_bonus", 4))
	if option.get("type", "") == "add_core_qi" and affinities.has(str(option.get("qi", ""))):
		weight += int(option.get("affinity_bonus", 4))
	return weight


func apply_reward(reward: Dictionary, qi_manager: QiManager, method_manager: CultivationMethodManager) -> String:
	match str(reward.get("type", "")):
		"add_core_qi":
			var qi_id := str(reward.get("qi", ""))
			var accepted := qi_manager.add_core_qi(qi_id, int(reward.get("value", 0)))
			return "%s +%d" % [qi_manager.get_qi_name(qi_id), accepted]
		"spirit_stones":
			var amount := RunState.add_spirit_stones(int(reward.get("value", 0)))
			return "灵石 +%d" % amount
		"learn_spell", "learn_reward":
			var spell_id := str(reward.get("spell_id", reward.get("ability_id", "")))
			if spells.has(spell_id) and RunState.can_fit_spell(spell_id, spells):
				RunState.learn_spell(spell_id)
				return "学会神通：%s" % spells[spell_id].get("name", spell_id)
			if spells.has(spell_id):
				return "神识容量不足，尚未学会%s。" % spells[spell_id].get("name", spell_id)
		"learn_method":
			var method_id := str(reward.get("method_id", ""))
			var method := method_manager.learn_method(method_id, bool(reward.get("set_active", true)))
			if not method.is_empty():
				var spell_id := str(method.get("initial_spell_id", method.get("bound_spell_id", "")))
				var spell_text := "，并学会%s" % spells.get(spell_id, {}).get("name", spell_id) if not spell_id.is_empty() else ""
				return "获得功法：%s%s" % [method.get("name", method_id), spell_text]
		"consumable", "item":
			var item_id := str(reward.get("item_id", ""))
			var quantity := int(reward.get("quantity", 1))
			if items.has(item_id) and RunState.add_item(item_id, quantity) > 0:
				return "%s ×%d" % [items[item_id].get("name", item_id), quantity]
		"material":
			var item_id := str(reward.get("item_id", ""))
			var quantity := int(reward.get("quantity", 1))
			if items.has(item_id) and RunState.add_material(item_id, quantity) > 0:
				return "材料：%s ×%d" % [items[item_id].get("name", item_id), quantity]
		"relic":
			var relic_id := str(reward.get("relic_id", ""))
			if relics.has(relic_id) and RunState.add_relic(relic_id):
				_apply_relic_capacity_modifier(relic_id)
				return "获得法宝：%s" % relics[relic_id].get("name", relic_id)
		_:
			push_warning("暂不支持的奖励类型：%s" % reward.get("type", "<missing>"))
	return "奖励未能生效"


func describe_reward(reward: Dictionary) -> Dictionary:
	var result := {"title": "未知奖励", "description": ""}
	match str(reward.get("type", "")):
		"add_core_qi":
			var qi_id := str(reward.get("qi", ""))
			result.title = "灵枢灵气：%s +%d" % [QI_NAMES.get(qi_id, "未知属性"), int(reward.get("value", 0))]
			result.description = "增加长期灵枢储量，不影响当前丹田。"
		"spirit_stones":
			result.title = "灵石 ×%d" % int(reward.get("value", 0))
			result.description = "可在探索途中向游商购买物品。"
		"learn_spell", "learn_reward":
			var spell_id := str(reward.get("spell_id", reward.get("ability_id", "")))
			var spell: Dictionary = spells.get(spell_id, {})
			result.title = "神通：%s（神识 %d）" % [spell.get("name", spell_id), int(spell.get("sense_cost", 1))]
			result.description = spell.get("description", "永久掌握该神通。")
		"learn_method":
			var method_id := str(reward.get("method_id", ""))
			var method: Dictionary = methods.get(method_id, {})
			var bound_spell: Dictionary = spells.get(str(method.get("initial_spell_id", method.get("bound_spell_id", ""))), {})
			result.title = "功法：%s" % method.get("name", method_id)
			result.description = "%s\n初始神通：%s" % [method.get("description", ""), bound_spell.get("name", "无")]
		"consumable", "item", "material":
			var item_id := str(reward.get("item_id", ""))
			var item: Dictionary = items.get(item_id, {})
			result.title = "%s ×%d" % [item.get("name", item_id), int(reward.get("quantity", 1))]
			result.description = item.get("description", "")
		"relic":
			var relic_id := str(reward.get("relic_id", ""))
			var relic: Dictionary = relics.get(relic_id, {})
			result.title = "法宝：%s" % relic.get("name", relic_id)
			result.description = relic.get("description", "获得一件长期影响本局战斗规则的法宝。")
	return result


func can_fit_spell_reward(reward: Dictionary) -> bool:
	var spell_id := str(reward.get("spell_id", reward.get("ability_id", "")))
	return spells.has(spell_id) and RunState.can_fit_spell(spell_id, spells)


func get_learned_spell_definitions() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for spell_id: Variant in RunState.player_state.get("skills", {}).get("spell_ids", []):
		var spell: Dictionary = spells.get(str(spell_id), {})
		if not spell.is_empty():
			results.append(spell)
	return results


func replace_spell_for_reward(replaced_spell_id: String, reward: Dictionary) -> String:
	var new_spell_id := str(reward.get("spell_id", reward.get("ability_id", "")))
	var old_name := str(spells.get(replaced_spell_id, {}).get("name", replaced_spell_id))
	var new_name := str(spells.get(new_spell_id, {}).get("name", new_spell_id))
	if RunState.replace_spell(replaced_spell_id, new_spell_id, spells):
		return "遗忘%s，学会神通：%s" % [old_name, new_name]
	return "替换失败：释放的神识容量不足。"


func _apply_relic_capacity_modifier(relic_id: String) -> void:
	var bonus := 0
	for effect: Variant in relics.get(relic_id, {}).get("effects", []):
		if effect is Dictionary and effect.get("type", "") == "modifier" and effect.get("target", "") == "player_rule:spiritual_sense_capacity" and effect.get("effect", "") == "capacity_up":
			bonus += int(effect.get("value", 0))
	RunState.set_spiritual_sense_capacity_modifier("relic:%s" % relic_id, bonus)


func _is_reward_eligible(reward: Dictionary) -> bool:
	var requirements: Dictionary = reward.get("requirements", {})
	var method_ids: Array = requirements.get("active_method_ids", [])
	if not method_ids.is_empty() and not method_ids.has(RunState.active_method_id):
		return false
	if bool(requirements.get("not_learned", false)):
		var spell_id := str(reward.get("spell_id", ""))
		if RunState.player_state.get("skills", {}).get("spell_ids", []).has(spell_id):
			return false
	if bool(requirements.get("not_owned", false)) and RunState.relics.has(str(reward.get("relic_id", ""))):
		return false
	return true
