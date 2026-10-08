class_name QiManager
extends Node

signal qi_changed(current_qi: Dictionary)

var qi_definitions: Dictionary = {}
var spirit_core_definition: Dictionary = {}

# 灵枢长期状态与战斗气海有意分离。Demo 不消耗长期储量，后续存档可序列化此字段。
var core_runtime_state: Dictionary = {
	"stored_qi": {},
	"capacity_modifiers": {},
	"conversion_modifiers": {},
	"pollution_modifiers": {}
}
var sea_qi: Dictionary = {}
var battle_core_qi: Dictionary = {}
var battle_active := false
var turn_gather_capacity := 0


func configure(definitions: Array, core_definition: Dictionary) -> bool:
	qi_definitions = GameDataLoader.index_by_id(definitions, "qi.json")
	spirit_core_definition = core_definition.duplicate(true)
	if spirit_core_definition.is_empty():
		push_error("QiManager 缺少灵枢定义。")
		return false

	if RunState.initialized and RunState.core_state.get("definition_id", "") == spirit_core_definition.get("id", ""):
		core_runtime_state = RunState.core_state
	else:
		var storage: Dictionary = spirit_core_definition.get("storage", {})
		core_runtime_state = {
			"definition_id": spirit_core_definition.get("id", ""),
			"stored_qi": Dictionary(storage.get("initial_qi", {})).duplicate(true),
			"capacity_modifiers": {},
			"conversion_modifiers": {},
			"pollution_modifiers": {}
		}
	sea_qi.clear()
	for qi_id: String in qi_definitions:
		sea_qi[qi_id] = 0
	qi_changed.emit(get_sea_qi())
	return true


func start_battle() -> void:
	battle_active = true
	battle_core_qi = Dictionary(core_runtime_state.get("stored_qi", {})).duplicate(true)
	for qi_id: String in qi_definitions:
		sea_qi[qi_id] = 0
	qi_changed.emit(get_sea_qi())


func generate_turn_qi(guaranteed_qi_id: String = "", gather_amount: int = -1) -> Dictionary:
	var projection: Dictionary = spirit_core_definition.get("battle_projection", {})
	var amount_per_turn := int(projection.get("amount_per_turn", 0)) if gather_amount < 0 else maxi(0, gather_amount)
	turn_gather_capacity = amount_per_turn
	var generated := 0
	var guaranteed_primary := mini(amount_per_turn, int(projection.get("guaranteed_primary_per_turn", 1)))
	if qi_definitions.has(guaranteed_qi_id):
		for point: int in mini(guaranteed_primary, int(battle_core_qi.get(guaranteed_qi_id, 0))):
			add_sea_qi(guaranteed_qi_id, 1, false)
			battle_core_qi[guaranteed_qi_id] = int(battle_core_qi.get(guaranteed_qi_id, 0)) - 1
			generated += 1
	for index: int in amount_per_turn - generated:
		var qi_id := _pick_weighted_five_element()
		if qi_id.is_empty():
			break
		add_sea_qi(qi_id, 1, false)
		battle_core_qi[qi_id] = int(battle_core_qi.get(qi_id, 0)) - 1
	qi_changed.emit(get_sea_qi())
	return get_sea_qi()


func can_pay(cost: Dictionary) -> bool:
	if bool(cost.get("all_sea_qi", false)):
		return get_total_sea_qi() >= int(cost.get("minimum", 1))
	for qi_id: Variant in cost:
		if str(qi_id) in ["all_sea_qi", "minimum"]:
			continue
		if str(qi_id) == "any_qi":
			if get_total_sea_qi() < int(cost[qi_id]):
				return false
			continue
		if int(sea_qi.get(str(qi_id), 0)) < int(cost[qi_id]):
			return false
	return true


func spend(cost: Dictionary) -> bool:
	return bool(spend_with_result(cost).get("success", false))


func spend_with_result(cost: Dictionary) -> Dictionary:
	if not can_pay(cost):
		return {"success": false, "total_spent": 0, "spent_qi": {}}
	var spent_qi: Dictionary = {}
	if bool(cost.get("all_sea_qi", false)):
		for qi_id: String in sea_qi:
			spent_qi[qi_id] = int(sea_qi[qi_id])
			sea_qi[qi_id] = 0
		var total_spent := 0
		for amount: Variant in spent_qi.values():
			total_spent += int(amount)
		qi_changed.emit(get_sea_qi())
		return {"success": true, "total_spent": total_spent, "spent_qi": spent_qi}
	for qi_id: Variant in cost:
		if str(qi_id) in ["all_sea_qi", "minimum"]:
			continue
		if str(qi_id) == "any_qi":
			var before := sea_qi.duplicate(true)
			_spend_any_qi(int(cost[qi_id]))
			for spent_id: String in sea_qi:
				var amount := int(before.get(spent_id, 0)) - int(sea_qi[spent_id])
				if amount > 0:
					spent_qi[spent_id] = amount
		else:
			spent_qi[str(qi_id)] = int(cost[qi_id])
			sea_qi[str(qi_id)] = int(sea_qi.get(str(qi_id), 0)) - int(cost[qi_id])
	qi_changed.emit(get_sea_qi())
	var total_spent := 0
	for amount: Variant in spent_qi.values():
		total_spent += int(amount)
	return {"success": true, "total_spent": total_spent, "spent_qi": spent_qi}


func _spend_any_qi(amount: int) -> void:
	var remaining := amount
	for qi_id: String in sea_qi:
		var spent := mini(remaining, int(sea_qi[qi_id]))
		sea_qi[qi_id] = int(sea_qi[qi_id]) - spent
		remaining -= spent
		if remaining <= 0:
			return


func retain_sea_qi(retention_rate: float) -> Dictionary:
	return Dictionary(dissipate_sea_qi(retention_rate).get("retained_qi", {}))


func dissipate_sea_qi(retention_rate: float) -> Dictionary:
	var retention: Dictionary = spirit_core_definition.get("battle_projection", {}).get("retention", {})
	var maximum_rate := float(retention.get("maximum_rate", 1.0))
	var maximum_total := int(retention.get("maximum_total", int(spirit_core_definition.get("battle_projection", {}).get("sea_capacity", 999999))))
	var clamped_rate := clampf(retention_rate, 0.0, maximum_rate)
	var before_total := get_total_sea_qi()
	var remaining_by_qi := sea_qi.duplicate(true)
	for qi_id: String in sea_qi:
		sea_qi[qi_id] = 0
	var retained_target := mini(maximum_total, floori(before_total * clamped_rate))
	for point_index: int in retained_target:
		var largest_qi_id := ""
		for qi_id: String in remaining_by_qi:
			if largest_qi_id.is_empty() or int(remaining_by_qi[qi_id]) > int(remaining_by_qi[largest_qi_id]):
				largest_qi_id = qi_id
		if largest_qi_id.is_empty() or int(remaining_by_qi[largest_qi_id]) <= 0:
			break
		sea_qi[largest_qi_id] = int(sea_qi[largest_qi_id]) + 1
		remaining_by_qi[largest_qi_id] = int(remaining_by_qi[largest_qi_id]) - 1
	qi_changed.emit(get_sea_qi())
	return {
		"retained_qi": get_sea_qi(),
		"retained_total": get_total_sea_qi(),
		"dissipated_total": maxi(0, before_total - get_total_sea_qi()),
		"applied_rate": clamped_rate
	}


func add_sea_qi(qi_id: String, amount: int, emit_change: bool = true) -> void:
	if not qi_definitions.has(qi_id):
		push_warning("尝试加入未定义的灵气：%s" % qi_id)
		return
	# 神识决定本回合基础聚气量；额外凝聚效果仍需要少量余量。
	var configured_capacity := int(spirit_core_definition.get("battle_projection", {}).get("sea_capacity", 999999))
	var sea_capacity := maxi(configured_capacity, turn_gather_capacity + 3)
	var remaining_capacity: int = maxi(0, sea_capacity - get_total_sea_qi())
	sea_qi[qi_id] = int(sea_qi.get(qi_id, 0)) + mini(maxi(amount, 0), remaining_capacity)
	if emit_change:
		qi_changed.emit(get_sea_qi())


func convert_sea_qi(from_qi: String, to_qi: String, amount: int) -> int:
	if amount <= 0 or from_qi == to_qi or not qi_definitions.has(from_qi) or not qi_definitions.has(to_qi):
		return 0
	var converted := mini(amount, int(sea_qi.get(from_qi, 0)))
	sea_qi[from_qi] = int(sea_qi.get(from_qi, 0)) - converted
	sea_qi[to_qi] = int(sea_qi.get(to_qi, 0)) + converted
	qi_changed.emit(get_sea_qi())
	return converted


func get_total_sea_qi() -> int:
	var total := 0
	for amount: Variant in sea_qi.values():
		total += int(amount)
	return total


func get_sea_qi() -> Dictionary:
	return sea_qi.duplicate(true)


func get_core_stored_qi() -> Dictionary:
	var stored: Dictionary = battle_core_qi if battle_active else core_runtime_state.get("stored_qi", {})
	return stored.duplicate(true)


func end_battle() -> void:
	battle_active = false
	battle_core_qi.clear()
	qi_changed.emit(get_sea_qi())


func add_core_qi(qi_id: String, amount: int) -> int:
	if not qi_definitions.has(qi_id) or amount <= 0:
		return 0
	if not bool(qi_definitions[qi_id].get("storable", false)):
		push_warning("不可储存的属性不能写入灵枢：%s" % qi_id)
		return 0
	var stored: Dictionary = core_runtime_state.get("stored_qi", {})
	var storage_definition: Dictionary = spirit_core_definition.get("storage", {})
	var capacity_modifiers: Dictionary = core_runtime_state.get("capacity_modifiers", {})
	var total_capacity := int(storage_definition.get("total_capacity", 0)) + int(capacity_modifiers.get("total", 0))
	var attribute_capacities: Dictionary = storage_definition.get("attribute_capacity", {})
	var attribute_capacity := int(attribute_capacities.get(qi_id, total_capacity)) + int(capacity_modifiers.get(qi_id, 0))
	var total_stored := 0
	for stored_amount: Variant in stored.values():
		total_stored += int(stored_amount)
	var accepted: int = mini(amount, mini(maxi(0, total_capacity - total_stored), maxi(0, attribute_capacity - int(stored.get(qi_id, 0)))))
	stored[qi_id] = int(stored.get(qi_id, 0)) + accepted
	core_runtime_state["stored_qi"] = stored
	return accepted


func withdraw_from_core(qi_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var stored: Dictionary = core_runtime_state.get("stored_qi", {})
	var withdrawn: int = mini(amount, int(stored.get(qi_id, 0)))
	stored[qi_id] = int(stored.get(qi_id, 0)) - withdrawn
	core_runtime_state["stored_qi"] = stored
	return withdrawn


func get_core_composition_ratios() -> Dictionary:
	var ratios := {}
	var stored: Dictionary = core_runtime_state.get("stored_qi", {})
	var total := 0
	for qi_id: String in qi_definitions:
		if qi_definitions[qi_id].get("category", "") == "five_element":
			total += int(stored.get(qi_id, 0))
	for qi_id: String in qi_definitions:
		if qi_definitions[qi_id].get("category", "") == "five_element":
			ratios[qi_id] = float(stored.get(qi_id, 0)) / float(total) if total > 0 else 0.0
	return ratios


func _pick_weighted_five_element() -> String:
	var stored: Dictionary = battle_core_qi if battle_active else core_runtime_state.get("stored_qi", {})
	var candidates: Array[String] = []
	var total_weight := 0
	for qi_id: String in qi_definitions:
		var definition: Dictionary = qi_definitions[qi_id]
		if definition.get("category", "") != "five_element":
			continue
		var weight := maxi(0, int(stored.get(qi_id, 0)))
		if weight > 0:
			candidates.append(qi_id)
			total_weight += weight
	if total_weight <= 0:
		return ""
	var roll := randi_range(1, total_weight)
	for qi_id: String in candidates:
		roll -= int(stored.get(qi_id, 0))
		if roll <= 0:
			return qi_id
	return candidates.back()


func get_qi_name(qi_id: String) -> String:
	return str(qi_definitions.get(qi_id, {}).get("name", qi_id))
