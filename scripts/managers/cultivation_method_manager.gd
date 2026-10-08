class_name CultivationMethodManager
extends Node

var methods: Dictionary = {}


func configure(method_definitions: Array) -> void:
	methods = GameDataLoader.index_by_id(method_definitions, "cultivation_methods.json")


func learn_method(method_id: String, set_active: bool = true) -> Dictionary:
	var method: Dictionary = methods.get(method_id, {})
	if method.is_empty():
		push_warning("找不到功法：%s" % method_id)
		return {}
	RunState.learn_method(method_id)
	if set_active:
		RunState.set_active_method(method_id)
	var initial_spell_id := str(method.get("initial_spell_id", method.get("bound_spell_id", "")))
	if not initial_spell_id.is_empty():
		RunState.learn_spell(initial_spell_id)
	for replaced_spell_id: Variant in method.get("replaces_spell_ids", []):
		RunState.forget_spell(str(replaced_spell_id))
	return method


func get_method(method_id: String) -> Dictionary:
	return methods.get(method_id, {})


func get_active_method() -> Dictionary:
	return methods.get(RunState.active_method_id, {})


func get_active_effects() -> Array:
	var active := get_active_method()
	return Array(active.get("effects", [])).duplicate(true) if not active.is_empty() else []


func get_active_element_affinity() -> Dictionary:
	var active := get_active_method()
	return Dictionary(active.get("element_affinity", {})).duplicate(true) if not active.is_empty() else {}


func apply_action_modifiers(action: Dictionary) -> Dictionary:
	var modified := action.duplicate(true)
	var tags: Array = modified.get("tags", [])
	for modifier: Variant in get_active_effects():
		if not modifier is Dictionary or modifier.get("type", "") != "modifier":
			continue
		var target := str(modifier.get("target", ""))
		var matches_tag := target.begins_with("spell_tag:") and tags.has(target.trim_prefix("spell_tag:"))
		var matches_effect := target.begins_with("effect:")
		if not matches_tag and not matches_effect:
			continue
		for effect: Variant in modified.get("effects", []):
			if not effect is Dictionary:
				continue
			if matches_effect and str(effect.get("type", "")) != target.trim_prefix("effect:"):
				continue
			if modifier.get("effect", "") == "damage_up" and effect.get("type", "") == "damage":
				effect["value"] = roundi(int(effect.get("value", 0)) * (1.0 + float(modifier.get("value", 0)) / 100.0))
			elif modifier.get("effect", "") == "shield_up" and effect.get("type", "") == "shield":
				effect["value"] = roundi(int(effect.get("value", 0)) * (1.0 + float(modifier.get("value", 0)) / 100.0))
	return modified


func get_rule_modifier(target: String, effect_name: String) -> int:
	var total := 0
	for modifier: Variant in get_active_effects():
		if modifier is Dictionary and modifier.get("type", "") == "modifier" and modifier.get("target", "") == target and modifier.get("effect", "") == effect_name:
			total += int(modifier.get("value", 0))
	return total
