class_name CombatEffectExecutor
extends Node


func execute_action(action: Dictionary, source_unit_id: String, opponent_unit_id: String, battle_manager: Node, qi_manager: QiManager = null) -> Array[String]:
	var messages: Array[String] = []
	for effect: Variant in action.get("effects", []):
		if not effect is Dictionary or not _meets_condition(effect.get("condition", {}), source_unit_id, opponent_unit_id, battle_manager):
			continue
		var target_unit_ids: Array[String] = battle_manager.resolve_effect_targets(
			str(effect.get("target", "opponent")),
			source_unit_id,
			opponent_unit_id,
			effect
		)
		match str(effect.get("type", "")):
			"damage":
				var effect_value := _resolve_effect_value(effect, action, source_unit_id, opponent_unit_id, battle_manager)
				for target_unit_id: String in target_unit_ids:
					var result: Dictionary = battle_manager.apply_damage_to_unit(source_unit_id, target_unit_id, effect_value, str(effect.get("attribute", "")))
					messages.append(str(result.get("message", "")))
			"shield":
				var target_unit_id: String = target_unit_ids[0] if not target_unit_ids.is_empty() else source_unit_id
				var shield_value := _resolve_effect_value(effect, action, source_unit_id, opponent_unit_id, battle_manager)
				battle_manager.add_shield_to_unit(target_unit_id, shield_value)
				var target: Dictionary = battle_manager.get_unit(target_unit_id)
				messages.append("%s获得 %d 点护盾。" % [target.get("name", "单位"), shield_value])
			"heal":
				var target_unit_id: String = target_unit_ids[0] if not target_unit_ids.is_empty() else source_unit_id
				var healed: int = battle_manager.heal_unit(target_unit_id, _resolve_effect_value(effect, action, source_unit_id, opponent_unit_id, battle_manager))
				var target: Dictionary = battle_manager.get_unit(target_unit_id)
				messages.append("%s恢复 %d 点生命。" % [target.get("name", "单位"), healed])
			"buff":
				var target_unit_id: String = target_unit_ids[0] if not target_unit_ids.is_empty() else source_unit_id
				battle_manager.add_buff_to_unit(
					target_unit_id,
					str(effect.get("status", "")),
					int(effect.get("value", 0)),
					int(effect.get("duration", 1))
				)
				var target: Dictionary = battle_manager.get_unit(target_unit_id)
				var status_name := str({"attack_up":"攻势", "defense_up":"守势"}.get(str(effect.get("status", "")), effect.get("status", "力量")))
				messages.append("%s的%s增强。" % [target.get("name", "单位"), status_name])
			"add_sea_qi":
				if qi_manager != null and source_unit_id == "player":
					qi_manager.add_sea_qi(str(effect.get("qi", "")), int(effect.get("value", 0)))
			"convert_sea_qi":
				if qi_manager != null and source_unit_id == "player":
					var converted := qi_manager.convert_sea_qi(str(effect.get("from_qi", "")), str(effect.get("to_qi", "")), int(effect.get("value", 0)))
					messages.append("转化%d点丹田灵气。" % converted)
			"consume_shield":
				var target_unit_id: String = target_unit_ids[0] if not target_unit_ids.is_empty() else source_unit_id
				var consumed: int = battle_manager.consume_shield_from_unit(target_unit_id, int(effect.get("value", 0)), bool(effect.get("all", false)))
				messages.append("消耗%d点护盾。" % consumed)
			"add_status":
				var target_unit_id: String = target_unit_ids[0] if not target_unit_ids.is_empty() else source_unit_id
				battle_manager.add_status_to_unit(target_unit_id, str(effect.get("status", "")), int(effect.get("value", 0)))
			"consume_status":
				var target_unit_id: String = target_unit_ids[0] if not target_unit_ids.is_empty() else source_unit_id
				var amount: int = battle_manager.get_status_value_for_unit(target_unit_id, str(effect.get("status", ""))) if bool(effect.get("all", false)) else int(effect.get("value", 0))
				battle_manager.consume_status_from_unit(target_unit_id, str(effect.get("status", "")), amount)
			_:
				push_warning("暂不支持的战斗效果：%s" % effect.get("type", "<missing>"))
	return messages


func _resolve_effect_value(effect: Dictionary, action: Dictionary, source_unit_id: String, opponent_unit_id: String, battle_manager: Node) -> int:
	var value := int(effect.get("value", 0))
	var scaling: Dictionary = effect.get("scaling", {})
	if scaling.is_empty():
		return value
	var source_id := str(scaling.get("source", ""))
	var source_value := 0
	if source_id == "status":
		var status_target: String = battle_manager.resolve_effect_target(str(scaling.get("target", "self")), source_unit_id, opponent_unit_id, scaling)
		source_value = battle_manager.get_status_value_for_unit(status_target, str(scaling.get("status", "")))
	elif source_id == "shield":
		var shield_target: String = battle_manager.resolve_effect_target(str(scaling.get("target", "self")), source_unit_id, opponent_unit_id, scaling)
		source_value = int(battle_manager.get_unit(shield_target).get("shield", 0))
	else:
		source_value = int(action.get("runtime_values", {}).get(source_id, 0))
	var points_per_bonus := maxi(1, int(scaling.get("points_per_bonus", 1)))
	return value + floori(float(source_value) / float(points_per_bonus)) * int(scaling.get("per_point", 0))


func _resolve_target(target: String, source_unit_id: String, opponent_unit_id: String) -> String:
	if target == "self":
		return source_unit_id
	return opponent_unit_id


func _meets_condition(condition: Dictionary, source_unit_id: String, opponent_unit_id: String, battle_manager: Node) -> bool:
	if condition.is_empty():
		return true
	if condition.has("status"):
		var status_condition: Dictionary = condition["status"]
		var target_id: String = battle_manager.resolve_effect_target(str(status_condition.get("target", "self")), source_unit_id, opponent_unit_id, status_condition)
		return battle_manager.get_status_value_for_unit(target_id, str(status_condition.get("id", ""))) >= int(status_condition.get("min", 1))
	if condition.has("hp_ratio_lte"):
		var hp_condition: Dictionary = condition["hp_ratio_lte"]
		var target_id: String = battle_manager.resolve_effect_target(str(hp_condition.get("target", "opponent")), source_unit_id, opponent_unit_id, hp_condition)
		var unit: Dictionary = battle_manager.get_unit(target_id)
		return not unit.is_empty() and float(unit.hp.current) / maxf(1.0, float(unit.hp.max)) <= float(hp_condition.get("value", 0.5))
	return true
