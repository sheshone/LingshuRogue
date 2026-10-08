class_name SpellManager
extends Node

var spells_by_id: Dictionary = {}
var learned_spell_ids: Array[String] = []


func configure(spell_definitions: Array, runtime_learned_spell_ids: Array) -> void:
	spells_by_id = GameDataLoader.index_by_id(spell_definitions, "spells.json")
	learned_spell_ids.clear()
	for spell_id: Variant in runtime_learned_spell_ids:
		var normalized_id := str(spell_id)
		if spells_by_id.has(normalized_id):
			learned_spell_ids.append(normalized_id)
		else:
			push_warning("运行时神通列表引用了不存在的神通：%s" % normalized_id)


func get_castable_spells(current_qi: Dictionary, context: Dictionary = {}) -> Array[Dictionary]:
	var castable: Array[Dictionary] = []
	for spell_id: String in learned_spell_ids:
		var spell: Dictionary = spells_by_id[spell_id]
		if _meets_cost(spell.get("cost", {}), current_qi) and _meets_requirements(spell.get("requirements", {}), current_qi, context):
			castable.append(spell)
	return castable


func get_spell(spell_id: String) -> Dictionary:
	return spells_by_id.get(spell_id, {})


func get_learned_spells_with_castability(current_qi: Dictionary, context: Dictionary = {}) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for spell_id: String in learned_spell_ids:
		var spell: Dictionary = spells_by_id[spell_id].duplicate(true)
		spell["ui_castable"] = _meets_cost(spell.get("cost", {}), current_qi) and _meets_requirements(spell.get("requirements", {}), current_qi, context)
		results.append(spell)
	return results


func has_spell_with_payable_cost(available_qi: Dictionary) -> bool:
	for spell_id: String in learned_spell_ids:
		if _meets_cost(spells_by_id[spell_id].get("cost", {}), available_qi):
			return true
	return false


func forget_spell(spell_id: String) -> bool:
	var index := learned_spell_ids.find(spell_id)
	if index < 0:
		return false
	learned_spell_ids.remove_at(index)
	return true


func learn_spell(spell_id: String) -> bool:
	if not spells_by_id.has(spell_id) or learned_spell_ids.has(spell_id):
		return false
	learned_spell_ids.append(spell_id)
	return true


func _meets_cost(cost: Dictionary, current_qi: Dictionary) -> bool:
	if bool(cost.get("all_sea_qi", false)):
		var total := 0
		for amount: Variant in current_qi.values():
			total += int(amount)
		return total >= int(cost.get("minimum", 1))
	for qi_id: Variant in cost:
		if str(qi_id) in ["all_sea_qi", "minimum"]:
			continue
		if str(qi_id) == "any_qi":
			var total := 0
			for amount: Variant in current_qi.values():
				total += int(amount)
			if total < int(cost[qi_id]):
				return false
			continue
		if int(current_qi.get(str(qi_id), 0)) < int(cost[qi_id]):
			return false
	return true


func _meets_requirements(requirements: Dictionary, current_qi: Dictionary, context: Dictionary) -> bool:
	var required_qi: Dictionary = requirements.get("qi", {})
	if not _meets_cost(required_qi, current_qi):
		return false
	if requirements.has("status"):
		var statuses: Variant = context.get("statuses", {})
		if not statuses.has(requirements["status"]):
			return false
	return true
