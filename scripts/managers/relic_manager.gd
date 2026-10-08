class_name RelicManager
extends Node

var relics: Dictionary = {}
var battle_once: Dictionary = {}
var turn_once: Dictionary = {}


func configure(relic_definitions: Array) -> void:
	relics = GameDataLoader.index_by_id(relic_definitions, "relics.json")
	battle_once.clear()
	turn_once.clear()
	for relic: Dictionary in get_owned_relics():
		var capacity_bonus := 0
		for effect: Variant in relic.get("effects", []):
			if effect is Dictionary and effect.get("type", "") == "modifier" and effect.get("target", "") == "player_rule:spiritual_sense_capacity" and effect.get("effect", "") == "capacity_up":
				capacity_bonus += int(effect.get("value", 0))
		RunState.set_spiritual_sense_capacity_modifier("relic:%s" % relic.get("id", ""), capacity_bonus)


func begin_turn() -> void:
	turn_once.clear()


func consume_modifier_once(target: String, effect_name: String, scope: String = "turn") -> Dictionary:
	var consumed: Dictionary = turn_once if scope == "turn" else battle_once
	for relic: Dictionary in get_owned_relics():
		for effect: Variant in relic.get("effects", []):
			if not effect is Dictionary or effect.get("type", "") != "modifier":
				continue
			if effect.get("target", "") != target or effect.get("effect", "") != effect_name:
				continue
			var relic_id := str(relic.get("id", ""))
			var key := "%s:%s:%s" % [relic_id, target, effect_name]
			if bool(consumed.get(key, false)):
				continue
			consumed[key] = true
			return {"relic_id": relic_id, "value": int(effect.get("value", 0))}
	return {}


func get_owned_relics() -> Array[Dictionary]:
	var owned: Array[Dictionary] = []
	for relic_id: Variant in RunState.relics:
		var relic: Dictionary = relics.get(str(relic_id), {})
		if not relic.is_empty():
			owned.append(relic)
	return owned


func get_owned_relic_names() -> Array[String]:
	var names: Array[String] = []
	for relic: Dictionary in get_owned_relics():
		names.append(str(relic.get("name", relic.get("id", "未知法宝"))))
	return names


func get_modifier_value(target: String, effect_name: String) -> int:
	var total := 0
	for relic: Dictionary in get_owned_relics():
		for effect: Variant in relic.get("effects", []):
			if effect is Dictionary and effect.get("type", "") == "modifier" and effect.get("target", "") == target and effect.get("effect", "") == effect_name:
				total += int(effect.get("value", 0))
	return total


func get_trigger_effects(trigger: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for relic: Dictionary in get_owned_relics():
		for definition: Variant in relic.get("effects", []):
			if not definition is Dictionary or definition.get("type", "") != "trigger_effect" or definition.get("trigger", "") != trigger:
				continue
			var effect: Variant = definition.get("effect", {})
			if effect is Dictionary:
				results.append(Dictionary(effect).duplicate(true))
	return results


func get_trigger_entries(trigger: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for relic: Dictionary in get_owned_relics():
		for definition: Variant in relic.get("effects", []):
			if definition is Dictionary and definition.get("type", "") == "trigger_effect" and definition.get("trigger", "") == trigger and definition.get("effect", {}) is Dictionary:
				results.append({"relic_id": str(relic.get("id", "")), "effect": Dictionary(definition.effect).duplicate(true)})
	return results


func apply_action_modifiers(action: Dictionary) -> Dictionary:
	var modified := action.duplicate(true)
	var tags: Array = modified.get("tags", [])
	for relic: Dictionary in get_owned_relics():
		for modifier: Variant in relic.get("effects", []):
			if not modifier is Dictionary or modifier.get("type", "") != "modifier":
				continue
			var target := str(modifier.get("target", ""))
			if target.begins_with("spell_tag:") and tags.has(target.trim_prefix("spell_tag:")):
				for effect: Variant in modified.get("effects", []):
					if effect is Dictionary and effect.get("type", "") == "damage" and modifier.get("effect", "") == "damage_up":
						effect["value"] = roundi(int(effect.get("value", 0)) * (1.0 + float(modifier.get("value", 0)) / 100.0))
			elif target == "spell_rule:any" and modifier.get("effect", "") == "damage_to_shield_percent":
				var total_damage := 0
				for action_effect: Variant in modified.get("effects", []):
					if action_effect is Dictionary and action_effect.get("type", "") == "damage":
						total_damage += int(action_effect.get("value", 0))
				var shield_value := floori(float(total_damage) * float(modifier.get("value", 0)) / 100.0)
				if shield_value > 0:
					modified["effects"].append({"type": "shield", "value": shield_value, "target": "self"})
	return modified
