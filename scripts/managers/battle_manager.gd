class_name BattleManager
extends Node

enum Phase { SETUP, PLAYER_ACTION, ENEMY_ACTION, VICTORY, DEFEAT, COMPLETE }

const DATA_PATHS := {
	"qi": "res://data/qi.json",
	"cores": "res://data/spirit_cores.json",
	"spells": "res://data/spells.json",
	"abilities": "res://data/abilities.json",
	"enemies": "res://data/enemies.json",
	"players": "res://data/player_templates.json",
	"setups": "res://data/battle_setups.json",
	"items": "res://data/items.json",
	"rewards": "res://data/reward_tables.json",
	"statuses": "res://data/statuses.json",
	"attributes": "res://data/attribute_rules.json",
	"pools": "res://data/encounter_pools.json",
	"methods": "res://data/cultivation_methods.json",
	"relics": "res://data/relics.json"
}

@export var battle_setup_id := "battle_1_training_puppet"

@onready var qi_manager: QiManager = $QiManager
@onready var spell_manager: SpellManager = $SpellManager
@onready var effect_executor: CombatEffectExecutor = $CombatEffectExecutor
@onready var reward_manager: RewardManager = $RewardManager
@onready var method_manager: CultivationMethodManager = $CultivationMethodManager
@onready var relic_manager: RelicManager = $RelicManager
@onready var battle_ui: BattleUI = $BattleUI

var phase := Phase.SETUP
var turn := 0
var player_state: Dictionary = {}
var enemy_units: Array[Dictionary] = []
var selected_enemy_id := ""
var current_setup: Dictionary = {}
var next_battle_id := ""
var rewards_granted := false
var reward_groups: Array[Dictionary] = []
var reward_group_index := 0
var rewards_resolved := false
var reward_messages: Array[String] = []
var pending_spell_reward: Dictionary = {}
var attributes_enabled := false
var relic_trigger_counts: Dictionary = {}

var abilities: Dictionary = {}
var items: Dictionary = {}
var status_definitions: Dictionary = {}
var attribute_resolver := AttributeResolver.new()


func _ready() -> void:
	battle_ui.spell_selected.connect(_on_spell_selected)
	battle_ui.item_selected.connect(_on_item_selected)
	battle_ui.target_selected.connect(_on_target_selected)
	battle_ui.enemy_action_requested.connect(_on_enemy_action_requested)
	battle_ui.continue_requested.connect(_on_continue_requested)
	battle_ui.reward_selected.connect(_on_reward_selected)
	battle_ui.spell_replacement_selected.connect(_on_spell_replacement_selected)
	# Battle actions refresh the UI at explicit animation boundaries. Refreshing
	# on every intermediate qi_changed signal used to redraw the dantian twice,
	# deleting gather/dissipation tweens before they became visible.
	if _load_battle():
		var battle_type := str(RunState.pending_map_node.get("type", "battle"))
		AudioDirector.set_context("boss" if battle_type == "boss" else ("elite" if battle_type == "elite" else "battle"))
		_start_turn()
	else:
		battle_ui.show_message("战斗数据加载失败，请查看输出日志。")
		battle_ui.set_enemy_action_enabled(false)


func _load_battle() -> bool:
	var setups := GameDataLoader.index_by_id(GameDataLoader.load_collection(DATA_PATHS.setups, "battle_setups"), "battle_setups.json")
	var players := GameDataLoader.index_by_id(GameDataLoader.load_collection(DATA_PATHS.players, "player_templates"), "player_templates.json")
	var enemies := GameDataLoader.index_by_id(GameDataLoader.load_collection(DATA_PATHS.enemies, "enemies"), "enemies.json")
	var cores := GameDataLoader.index_by_id(GameDataLoader.load_collection(DATA_PATHS.cores, "spirit_cores"), "spirit_cores.json")
	var active_setup_id := RunState.current_battle_id if RunState.initialized else battle_setup_id
	current_setup = Dictionary(setups.get(active_setup_id, {})).duplicate(true)
	if current_setup.is_empty():
		push_error("找不到战斗配置：%s" % active_setup_id)
		return false
	var pending_pool_id := str(RunState.pending_map_node.get("encounter_pool_id", ""))
	if RunState.map_active and not pending_pool_id.is_empty():
		current_setup.erase("enemy_ids")
		current_setup["encounter_pool_id"] = pending_pool_id
		current_setup["enemy_count"] = int(RunState.pending_map_node.get("enemy_count", 1))

	var player_template: Dictionary = players.get(str(current_setup.get("player_template_id", "")), {})
	var core_definition: Dictionary = cores.get(str(current_setup.get("spirit_core_id", "")), {})
	if player_template.is_empty() or core_definition.is_empty():
		push_error("战斗配置引用了不存在的玩家或灵枢模板。")
		return false

	var runtime_seed: Dictionary = current_setup.get("runtime_seed", {})
	RunState.initialize_run(player_template, runtime_seed, core_definition)
	RunState.current_battle_id = active_setup_id
	player_state = RunState.player_state
	player_state.shield = 0
	player_state.statuses = {}

	enemy_units.clear()
	var resolved_enemy_ids := _resolve_enemy_ids(current_setup)
	for enemy_id: Variant in resolved_enemy_ids:
		var enemy_template: Dictionary = enemies.get(str(enemy_id), {})
		if enemy_template.is_empty():
			push_error("战斗配置引用了不存在的敌人：%s" % enemy_id)
			return false
		var enemy := UnitFactory.create_unit(enemy_template, "enemy", {"unit_id": str(enemy_id)})
		var hp_scale := float(current_setup.get("enemy_hp_multiplier", 1.0))
		if hp_scale != 1.0:
			enemy.hp.max = maxi(1, roundi(float(enemy.hp.max) * hp_scale))
			enemy.hp.current = enemy.hp.max
		if not UnitFactory.is_valid_unit(enemy):
			push_error("敌人未能创建为有效 Unit：%s" % enemy_id)
			return false
		enemy_units.append(enemy)
	if enemy_units.is_empty():
		push_error("战斗至少需要一个敌人。")
		return false
	selected_enemy_id = str(enemy_units[0].unit_id)

	var spell_definitions := GameDataLoader.load_collection(DATA_PATHS.spells, "spells")
	var method_definitions := GameDataLoader.load_collection(DATA_PATHS.methods, "cultivation_methods")
	var relic_definitions := GameDataLoader.load_collection(DATA_PATHS.relics, "relics")
	abilities = GameDataLoader.index_by_id(GameDataLoader.load_collection(DATA_PATHS.abilities, "abilities"), "abilities.json")
	items = GameDataLoader.index_by_id(GameDataLoader.load_collection(DATA_PATHS.items, "items"), "items.json")
	status_definitions = GameDataLoader.index_by_id(GameDataLoader.load_collection(DATA_PATHS.statuses, "statuses"), "statuses.json")
	attribute_resolver.configure(GameDataLoader.load_json(DATA_PATHS.attributes))
	attributes_enabled = bool(current_setup.get("attributes_enabled", false))
	next_battle_id = str(current_setup.get("next_battle_id", ""))

	if not qi_manager.configure(GameDataLoader.load_collection(DATA_PATHS.qi, "qi_types"), core_definition):
		return false
	spell_manager.configure(spell_definitions, player_state.skills.spell_ids)
	method_manager.configure(method_definitions)
	relic_manager.configure(relic_definitions)
	reward_manager.configure(GameDataLoader.load_collection(DATA_PATHS.rewards, "reward_tables"), items.values(), spell_definitions, method_definitions, relic_definitions)
	qi_manager.start_battle()
	_apply_relic_trigger("battle_start")
	for enemy: Dictionary in enemy_units:
		_plan_enemy_action(enemy)
	return true


func _resolve_enemy_ids(setup: Dictionary) -> Array:
	var explicit_ids: Array = setup.get("enemy_ids", [])
	if not explicit_ids.is_empty():
		return explicit_ids.duplicate()
	var pool_id := str(setup.get("encounter_pool_id", ""))
	if pool_id.is_empty():
		return []
	var pools := GameDataLoader.index_by_id(GameDataLoader.load_collection(DATA_PATHS.pools, "encounter_pools"), "encounter_pools.json")
	var pool: Dictionary = pools.get(pool_id, {})
	var candidates: Array = pool.get("enemy_ids", [])
	if candidates.is_empty():
		push_error("敌人池为空或不存在：%s" % pool_id)
		return []
	var count := clampi(int(setup.get("enemy_count", pool.get("enemy_count", 1))), 1, candidates.size())
	var shuffled := candidates.duplicate()
	shuffled.shuffle()
	return shuffled.slice(0, count)


func _start_turn(previous_action_message: String = "") -> void:
	if _check_battle_end():
		return
	turn += 1
	phase = Phase.PLAYER_ACTION
	relic_manager.begin_turn()
	var core_before_gather := qi_manager.get_core_stored_qi()
	qi_manager.generate_turn_qi(_get_active_method_primary_qi(), RunState.get_spiritual_sense_capacity())
	var core_after_gather := qi_manager.get_core_stored_qi()
	_apply_relic_trigger("turn_start")
	if _check_battle_end():
		return
	var message := "灵气入丹田。" if turn == 1 else "新一轮灵气已凝聚。"
	if not previous_action_message.is_empty():
		message = previous_action_message + "\n" + message
	battle_ui.show_message(message)
	_refresh_ui()
	battle_ui.animate_core_withdrawal(core_before_gather, core_after_gather)


func _on_spell_selected(spell_id: String) -> void:
	if phase != Phase.PLAYER_ACTION:
		return
	var spell := spell_manager.get_spell(spell_id)
	if spell.is_empty():
		return
	AudioDirector.play_element_sfx(_action_attribute(spell))
	var spend_result := qi_manager.spend_with_result(spell.get("cost", {}))
	if not bool(spend_result.get("success", false)):
		battle_ui.show_message("当前丹田灵气不足。")
		return
	var runtime_spell: Dictionary = relic_manager.apply_action_modifiers(method_manager.apply_action_modifiers(spell))
	runtime_spell["runtime_values"] = {"spent_qi_total": int(spend_result.get("total_spent", 0))}
	var messages := effect_executor.execute_action(runtime_spell, "player", selected_enemy_id, self, qi_manager)
	var repeat_entry := relic_manager.consume_modifier_once("battle_rule:first_spell", "repeat_percent", "turn")
	if not repeat_entry.is_empty():
		var repeated_spell := _scaled_repeat_action(runtime_spell, int(repeat_entry.get("value", 50)))
		if not repeated_spell.get("effects", []).is_empty() and not _living_enemies().is_empty():
			_select_first_living_enemy_if_needed()
			messages.append_array(effect_executor.execute_action(repeated_spell, "player", selected_enemy_id, self, qi_manager))
			_show_relic_trigger(str(repeat_entry.get("relic_id", "")))
	if qi_manager.get_total_sea_qi() == 0:
		var empty_entry := relic_manager.consume_modifier_once("battle_rule:empty_sea", "shield_once_per_turn", "turn")
		if not empty_entry.is_empty():
			add_shield_to_unit("player", int(empty_entry.get("value", 0)))
			_show_relic_trigger(str(empty_entry.get("relic_id", "")))
	_apply_relic_trigger("after_spell")
	battle_ui.show_message("施展%s。%s" % [spell.get("name", spell_id), " ".join(messages)])
	if not _check_battle_end():
		_select_first_living_enemy_if_needed()
		_refresh_ui()


func _scaled_repeat_action(action: Dictionary, percent: int) -> Dictionary:
	var repeated := {"name": action.get("name", ""), "effects": []}
	for effect_value: Variant in action.get("effects", []):
		if not effect_value is Dictionary:
			continue
		var effect: Dictionary = Dictionary(effect_value).duplicate(true)
		if str(effect.get("type", "")) not in ["damage", "shield", "heal"]:
			continue
		effect["value"] = maxi(1, roundi(float(effect.get("value", 0)) * float(percent) / 100.0))
		effect.erase("scaling")
		repeated.effects.append(effect)
	return repeated


func _show_relic_trigger(relic_id: String) -> void:
	if relic_id.is_empty():
		return
	relic_trigger_counts[relic_id] = int(relic_trigger_counts.get(relic_id, 0)) + 1
	battle_ui.show_relic_trigger([relic_id])
	AudioDirector.play_relic_sfx(relic_id)


func _action_attribute(action: Dictionary) -> String:
	for tag: Variant in action.get("tags", []):
		if str(tag) in ["metal", "wood", "water", "fire", "earth"]:
			return str(tag)
	for effect: Variant in action.get("effects", []):
		if effect is Dictionary and not str(effect.get("attribute", "")).is_empty():
			return str(effect.get("attribute", ""))
	return "neutral"


func _on_item_selected(item_id: String) -> void:
	if phase != Phase.PLAYER_ACTION or not items.has(item_id):
		return
	var item: Dictionary = items[item_id]
	if item.get("type", "") != "consumable" or not RunState.consume_unit_item(player_state, item_id):
		battle_ui.show_message("该物品无法使用或数量不足。")
		return
	var action: Dictionary = item.get("combat_use", {})
	var messages := effect_executor.execute_action(action, "player", selected_enemy_id, self, qi_manager)
	battle_ui.show_message("使用%s。%s" % [item.get("name", item_id), " ".join(messages)])
	if not _check_battle_end():
		_select_first_living_enemy_if_needed()
		_refresh_ui()


func _on_target_selected(unit_id: String) -> void:
	var unit := get_unit(unit_id)
	if phase == Phase.PLAYER_ACTION and not unit.is_empty() and int(unit.hp.current) > 0 and unit.faction == "enemy":
		selected_enemy_id = unit_id
		_refresh_ui()


func _on_enemy_action_requested() -> void:
	if phase != Phase.PLAYER_ACTION:
		return
	phase = Phase.ENEMY_ACTION
	var messages: Array[String] = []
	for enemy: Dictionary in enemy_units:
		if int(enemy.hp.current) <= 0:
			continue
		# A defensive action must protect the enemy during the following player
		# turn. Expire its previous guard only when it is about to act again.
		var enemy_shield_retention := clampf(float(current_setup.get("enemy_shield_retention", 0.0)), 0.0, 1.0)
		enemy.shield = floori(int(enemy.get("shield", 0)) * enemy_shield_retention)
		var action: Dictionary = enemy.get("selected_action", {})
		if action.is_empty():
			continue
		battle_ui.animate_enemy_action(str(enemy.unit_id), action)
		AudioDirector.play_enemy_sfx(str(enemy.get("template_id", "")), str(enemy.get("unit_type", "")), action)
		if action.get("source_type", "") == "item":
			if not RunState.consume_unit_item(enemy, str(action.get("source_id", ""))):
				_plan_enemy_action(enemy)
				continue
		var action_messages := effect_executor.execute_action(action, str(enemy.unit_id), "player", self)
		messages.append("%s使用%s。%s" % [enemy.name, action.get("name", "行动"), " ".join(action_messages)])
		enemy.action_index = int(enemy.action_index) + 1
		_plan_enemy_action(enemy)
		if int(player_state.hp.current) <= 0:
			break
	var action_message := "\n".join(messages)
	battle_ui.show_message(action_message)
	if not _check_battle_end():
		var shield_retention := clampf(float(relic_manager.get_modifier_value("battle_rule:shield_retention", "retention_set")) / 100.0, 0.0, 1.0)
		player_state.shield = floori(int(player_state.shield) * shield_retention)
		var sea_retention_bonus := method_manager.get_rule_modifier("battle_rule:sea_retention", "retention_up") + relic_manager.get_modifier_value("battle_rule:sea_retention", "retention_up")
		var projection: Dictionary = qi_manager.spirit_core_definition.get("battle_projection", {})
		var base_retention := float(projection.get("retention", {}).get("base_rate", 0.0))
		var dissipation := qi_manager.dissipate_sea_qi(base_retention + float(sea_retention_bonus) / 100.0)
		action_message += "\n回合结束，丹田保留%d点灵气，散逸%d点。" % [dissipation.get("retained_total", 0), dissipation.get("dissipated_total", 0)]
		if int(dissipation.get("dissipated_total", 0)) > 0:
			await battle_ui.animate_qi_dissipation(Dictionary(dissipation.get("retained_qi", {})))
		_start_turn(action_message)


func _plan_enemy_action(enemy: Dictionary) -> void:
	var policy: Dictionary = enemy.get("action_policy", {})
	var actions: Array = policy.get("actions", [])
	var hp_ratio := float(enemy.hp.current) / maxf(1.0, float(enemy.hp.max))
	for phase_definition: Variant in policy.get("phases", []):
		if phase_definition is Dictionary and hp_ratio <= float(phase_definition.get("hp_ratio_lte", -1.0)):
			actions = phase_definition.get("actions", actions)
			break
	if actions.is_empty():
		enemy.selected_action = {}
		return
	for offset: int in actions.size():
		var index := (int(enemy.action_index) + offset) % actions.size()
		var reference: Dictionary = actions[index]
		var action := _build_action(reference)
		if action.is_empty():
			continue
		if action.get("source_type", "") == "item" and int(enemy.inventory.get(action.source_id, 0)) <= 0:
			continue
		enemy.action_index = index
		enemy.selected_action = action
		return
	enemy.selected_action = {}


func _build_action(reference: Dictionary) -> Dictionary:
	var source_type := str(reference.get("source_type", ""))
	var source_id := str(reference.get("source_id", ""))
	if source_type == "ability" and abilities.has(source_id):
		var ability: Dictionary = abilities[source_id]
		return {
			"source_type": source_type,
			"source_id": source_id,
			"name": ability.get("name", source_id),
			"description": ability.get("description", ""),
			"effects": Array(ability.get("effects", [])).duplicate(true)
		}
	if source_type == "item" and items.has(source_id):
		var item: Dictionary = items[source_id]
		var combat_use: Dictionary = item.get("combat_use", {})
		return {
			"source_type": source_type,
			"source_id": source_id,
			"name": item.get("name", source_id),
			"description": item.get("description", ""),
			"effects": Array(combat_use.get("effects", [])).duplicate(true)
		}
	return {}


func get_unit(unit_id: String) -> Dictionary:
	if unit_id == "player":
		return player_state
	for enemy: Dictionary in enemy_units:
		if enemy.unit_id == unit_id:
			return enemy
	return {}


func resolve_effect_target(target: String, source_unit_id: String, opponent_unit_id: String, effect: Dictionary = {}) -> String:
	if effect.has("target_id") and not get_unit(str(effect.target_id)).is_empty():
		return str(effect.target_id)
	if target == "self":
		return source_unit_id
	if target == "ally":
		var source := get_unit(source_unit_id)
		if source.is_empty():
			return source_unit_id
		var allies: Array[Dictionary] = []
		if source.faction == "player":
			allies.append(player_state)
		else:
			for enemy: Dictionary in enemy_units:
				if int(enemy.hp.current) > 0 and enemy.unit_id != source_unit_id:
					allies.append(enemy)
		if allies.is_empty():
			return source_unit_id
		allies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.hp.current) / maxf(1.0, float(a.hp.max)) < float(b.hp.current) / maxf(1.0, float(b.hp.max))
		)
		return str(allies[0].unit_id)
	return opponent_unit_id


func resolve_effect_targets(target: String, source_unit_id: String, opponent_unit_id: String, effect: Dictionary = {}) -> Array[String]:
	if target == "all_opponents":
		var source := get_unit(source_unit_id)
		var targets: Array[String] = []
		if not source.is_empty() and source.get("faction", "") == "player":
			for enemy: Dictionary in enemy_units:
				if int(enemy.hp.current) > 0:
					targets.append(str(enemy.unit_id))
		elif int(player_state.get("hp", {}).get("current", 0)) > 0:
			targets.append("player")
		return targets
	return [resolve_effect_target(target, source_unit_id, opponent_unit_id, effect)]


func _apply_relic_trigger(trigger: String) -> void:
	var entries := relic_manager.get_trigger_entries(trigger)
	if entries.is_empty():
		return
	var effects: Array[Dictionary] = []
	var triggered_ids: Array[String] = []
	for entry: Dictionary in entries:
		effects.append(entry.effect)
		var relic_id := str(entry.relic_id)
		triggered_ids.append(relic_id)
		relic_trigger_counts[relic_id] = int(relic_trigger_counts.get(relic_id, 0)) + 1
	effect_executor.execute_action({"effects": effects}, "player", selected_enemy_id, self, qi_manager)
	battle_ui.show_relic_trigger(triggered_ids)
	for relic_id: String in triggered_ids:
		AudioDirector.play_relic_sfx(relic_id)


func _get_active_method_primary_qi() -> String:
	var affinities := method_manager.get_active_element_affinity()
	var selected_id := ""
	var selected_weight := -1.0
	for qi_id: String in affinities:
		var weight := float(affinities[qi_id])
		if weight > selected_weight:
			selected_id = qi_id
			selected_weight = weight
	return selected_id


func apply_damage_to_unit(_source_unit_id: String, target_unit_id: String, base_amount: int, attack_attribute: String = "") -> Dictionary:
	var target := get_unit(target_unit_id)
	if target.is_empty():
		return {"damage": 0, "multiplier": 1.0, "message": ""}
	var source := get_unit(_source_unit_id)
	var multiplier := attribute_resolver.get_multiplier(attack_attribute, target.attributes, attributes_enabled)
	var attack_bonus := _get_buff_value(source, "attack_up") if not source.is_empty() else 0
	var defense_bonus := _get_buff_value(target, "defense_up")
	var buff_multiplier := maxf(0.0, (1.0 + float(attack_bonus) / 100.0) * (1.0 - float(defense_bonus) / 100.0))
	var amount := maxi(0, roundi(base_amount * multiplier * buff_multiplier))
	var absorbed := mini(int(target.shield), amount)
	target.shield = int(target.shield) - absorbed
	var hp_damage := amount - absorbed
	if target_unit_id == "player" and hp_damage >= int(target.hp.current) and int(target.hp.current) > 0:
		var guard_entry := relic_manager.consume_modifier_once("battle_rule:lethal_damage", "survive_once", "battle")
		if not guard_entry.is_empty():
			hp_damage = maxi(0, int(target.hp.current) - 1)
			target.shield = int(guard_entry.get("value", 0))
			_show_relic_trigger(str(guard_entry.get("relic_id", "")))
	target.hp.current = maxi(0, int(target.hp.current) - hp_damage)
	if amount > 0:
		AudioDirector.play_sfx("hit")
	if attack_bonus > 0:
		_consume_buff_use(source, "attack_up")
	if defense_bonus > 0:
		_consume_buff_use(target, "defense_up")
	var multiplier_text := "（克制 ×%.1f）" % multiplier if multiplier > 1.0 else ""
	_refresh_ui()
	return {"damage": hp_damage, "multiplier": multiplier, "message": "%s受到 %d 点伤害%s。" % [target.name, hp_damage, multiplier_text]}


func heal_unit(unit_id: String, amount: int) -> int:
	var unit := get_unit(unit_id)
	if unit.is_empty() or amount <= 0 or int(unit.hp.current) <= 0:
		return 0
	var before := int(unit.hp.current)
	unit.hp.current = mini(int(unit.hp.max), before + amount)
	_refresh_ui()
	return int(unit.hp.current) - before


func add_buff_to_unit(unit_id: String, status_id: String, value: int, duration: int) -> void:
	if status_id not in ["attack_up", "defense_up"]:
		push_warning("Demo暂不支持的强化状态：%s" % status_id)
		return
	var unit := get_unit(unit_id)
	if unit.is_empty() or value <= 0 or duration <= 0:
		return
	unit.statuses[status_id] = {
		"value": maxi(value, int(unit.statuses.get(status_id, {}).get("value", 0)) if unit.statuses.get(status_id, {}) is Dictionary else 0),
		"duration": maxi(duration, int(unit.statuses.get(status_id, {}).get("duration", 0)) if unit.statuses.get(status_id, {}) is Dictionary else 0)
	}
	_refresh_ui()


func _get_buff_value(unit: Dictionary, status_id: String) -> int:
	if unit.is_empty():
		return 0
	var status: Variant = unit.get("statuses", {}).get(status_id, {})
	return int(status.get("value", 0)) if status is Dictionary else 0


func _consume_buff_use(unit: Dictionary, status_id: String) -> void:
	var status: Variant = unit.get("statuses", {}).get(status_id, {})
	if not status is Dictionary:
		return
	status["duration"] = int(status.get("duration", 1)) - 1
	if int(status.duration) <= 0:
		unit.statuses.erase(status_id)
	else:
		unit.statuses[status_id] = status


func add_shield_to_unit(unit_id: String, amount: int) -> void:
	var unit := get_unit(unit_id)
	if not unit.is_empty():
		AudioDirector.play_sfx("shield")
		unit.shield = int(unit.shield) + maxi(0, amount)
		battle_ui.animate_guard(unit_id)
		_refresh_ui()


func consume_shield_from_unit(unit_id: String, amount: int, consume_all: bool = false) -> int:
	var unit := get_unit(unit_id)
	if unit.is_empty():
		return 0
	var consumed := int(unit.shield) if consume_all else mini(int(unit.shield), maxi(0, amount))
	unit.shield = int(unit.shield) - consumed
	_refresh_ui()
	return consumed


func add_status_to_unit(unit_id: String, status_id: String, amount: int) -> void:
	var unit := get_unit(unit_id)
	if unit.is_empty() or status_id.is_empty() or amount <= 0:
		return
	unit.statuses[status_id] = int(unit.statuses.get(status_id, 0)) + amount


func consume_status_from_unit(unit_id: String, status_id: String, amount: int) -> int:
	var unit := get_unit(unit_id)
	if unit.is_empty() or amount <= 0:
		return 0
	var consumed := mini(amount, int(unit.statuses.get(status_id, 0)))
	unit.statuses[status_id] = int(unit.statuses.get(status_id, 0)) - consumed
	if int(unit.statuses[status_id]) <= 0:
		unit.statuses.erase(status_id)
	return consumed


func get_status_value_for_unit(unit_id: String, status_id: String) -> int:
	var unit := get_unit(unit_id)
	if unit.is_empty():
		return 0
	var status: Variant = unit.get("statuses", {}).get(status_id, 0)
	return int(status.get("value", 0)) if status is Dictionary else int(status)


func _check_battle_end() -> bool:
	if not enemy_units.is_empty() and _living_enemies().is_empty():
		phase = Phase.VICTORY
		qi_manager.end_battle()
		AudioDirector.play_sfx("victory")
		if RunState.map_active and not RunState.pending_map_node.is_empty():
			RunState.complete_pending_map_node()
		if not rewards_granted:
			rewards_granted = true
			var reward_table_ids: Array[String] = []
			for table_id: Variant in current_setup.get("reward_table_ids", []):
				reward_table_ids.append(str(table_id))
			if reward_table_ids.is_empty():
				for enemy: Dictionary in enemy_units:
					var table_id := str(enemy.reward_table_id)
					if not table_id.is_empty():
						reward_table_ids.append(table_id)
			reward_groups = reward_manager.build_reward_groups(reward_table_ids)
			_apply_automatic_fixed_rewards()
			reward_group_index = 0
			rewards_resolved = reward_groups.is_empty()
		battle_ui.show_message("战斗胜利！请选择或领取战斗奖励。" if not rewards_resolved else "战斗胜利！")
		_refresh_ui()
		if rewards_resolved:
			call_deferred("_return_to_map_after_rewards")
		return true
	if not player_state.is_empty() and int(player_state.hp.current) <= 0:
		phase = Phase.DEFEAT
		qi_manager.end_battle()
		battle_ui.show_message("战斗失败。")
		_refresh_ui()
		return true
	if phase in [Phase.PLAYER_ACTION, Phase.ENEMY_ACTION] and not player_state.is_empty() and not enemy_units.is_empty() and not _can_ever_cast_learned_spell():
		phase = Phase.DEFEAT
		qi_manager.end_battle()
		battle_ui.show_message("丹田与灵枢均已无法支撑任何神通，战斗失败。")
		_refresh_ui()
		return true
	return false


func _can_ever_cast_learned_spell() -> bool:
	var available := qi_manager.get_sea_qi()
	var remaining_core := qi_manager.get_core_stored_qi()
	for qi_id: String in remaining_core:
		available[qi_id] = int(available.get(qi_id, 0)) + int(remaining_core.get(qi_id, 0))
	return spell_manager.has_spell_with_payable_cost(available)


func _apply_automatic_fixed_rewards() -> void:
	while not reward_groups.is_empty() and reward_groups[0].get("mode", "") == "fixed":
		var fixed_group: Dictionary = reward_groups.pop_front()
		for reward: Variant in fixed_group.get("options", []):
			if reward is Dictionary:
				reward_messages.append(reward_manager.apply_reward(reward, qi_manager, method_manager))


func _living_enemies() -> Array[Dictionary]:
	var living: Array[Dictionary] = []
	for enemy: Dictionary in enemy_units:
		if int(enemy.hp.current) > 0:
			living.append(enemy)
	return living


func _select_first_living_enemy_if_needed() -> void:
	var selected := get_unit(selected_enemy_id)
	if selected.is_empty() or int(selected.hp.current) <= 0:
		var living := _living_enemies()
		selected_enemy_id = str(living[0].unit_id) if not living.is_empty() else ""


func _refresh_ui() -> void:
	if player_state.is_empty() or not is_instance_valid(battle_ui):
		return
	var phase_names := {
		Phase.SETUP: "准备",
		Phase.PLAYER_ACTION: "玩家行动",
		Phase.ENEMY_ACTION: "敌人行动",
		Phase.VICTORY: "胜利",
		Phase.DEFEAT: "失败",
		Phase.COMPLETE: "完成"
	}
	battle_ui.render_state({
		"title": current_setup.get("title", "战斗"),
		"turn": turn,
		"phase_name": phase_names.get(phase, ""),
		"player_name": player_state.name,
		"realm_id": RunState.current_realm_id,
		"player_hp": player_state.hp.current,
		"player_max_hp": player_state.hp.max,
		"player_shield": player_state.shield,
		"player_statuses": _format_statuses(player_state.statuses),
		"player_status_data": player_state.statuses.duplicate(true),
		"status_tooltip": _format_status_tooltip(player_state.statuses),
		"relics": relic_manager.get_owned_relics(),
		"relic_trigger_counts": relic_trigger_counts,
		"spiritual_sense_used": RunState.get_spiritual_sense_used(reward_manager.spells),
		"spiritual_sense_capacity": RunState.get_spiritual_sense_capacity(),
		"materials": RunState.materials
	}, qi_manager)
	# Attributes remain part of combat calculation, but are not printed beside
	# enemy names. Players infer them through art, actions and combat feedback.
	battle_ui.render_enemies(enemy_units, selected_enemy_id, false)
	var is_player_turn := phase == Phase.PLAYER_ACTION
	# Keep the hand rendered during enemy actions. Clearing it changed the VBox
	# allocation and made every combatant visibly jump in size between phases.
	var castable: Array[Dictionary] = spell_manager.get_learned_spells_with_castability(qi_manager.get_sea_qi(), {"statuses": player_state.statuses})
	if not is_player_turn:
		for spell: Dictionary in castable:
			spell["ui_castable"] = false
	battle_ui.render_spells(castable, is_player_turn)
	battle_ui.render_items(player_state.inventory, items, is_player_turn)
	battle_ui.set_enemy_action_enabled(is_player_turn)
	if phase == Phase.VICTORY and not pending_spell_reward.is_empty():
		battle_ui.render_spell_replacement(pending_spell_reward, reward_manager)
	elif phase == Phase.VICTORY and not rewards_resolved and reward_group_index < reward_groups.size():
		var display_group: Dictionary = reward_groups[reward_group_index].duplicate(true)
		display_group["claimed_messages"] = reward_messages.duplicate()
		battle_ui.render_reward_group(display_group, reward_manager)
	else:
		battle_ui.clear_rewards()
	if phase == Phase.DEFEAT:
		battle_ui.set_continue_state(true, "返回主界面")
	elif phase == Phase.VICTORY and rewards_resolved and not RunState.map_active and str(current_setup.get("map_after_victory_id", "")).is_empty():
		var continue_text := "返回炼气地图" if RunState.map_active else ("进入下一战" if not next_battle_id.is_empty() else "结束战斗")
		battle_ui.set_continue_state(true, continue_text)
	else:
		battle_ui.set_continue_state(false, "")


func _format_statuses(statuses: Dictionary) -> String:
	var parts: Array[String] = []
	for status_id: String in statuses:
		var status: Variant = statuses[status_id]
		var detail := "%d%% / %d次" % [status.get("value", 0), status.get("duration", 0)] if status is Dictionary else "×%d" % status
		parts.append("%s %s" % [status_definitions.get(status_id, {}).get("name", status_id), detail])
	return "、".join(parts) if not parts.is_empty() else "无"


func _format_status_tooltip(statuses: Dictionary) -> String:
	if statuses.is_empty():
		return "当前没有战斗状态。"
	var lines: Array[String] = []
	for status_id: String in statuses:
		var definition: Dictionary = status_definitions.get(status_id, {})
		lines.append("%s：%s" % [definition.get("name", status_id), definition.get("description", "战斗中的临时状态。")])
	return "\n".join(lines)


func _on_continue_requested() -> void:
	if phase == Phase.DEFEAT:
		RunState.clear_save()
		RunState.reset_run()
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
		return
	if phase != Phase.VICTORY or not rewards_resolved:
		return
	var map_after_victory_id := str(current_setup.get("map_after_victory_id", ""))
	if not map_after_victory_id.is_empty():
		RunState.start_map(map_after_victory_id, str(current_setup.get("map_start_node_id", "")))
	if RunState.map_active:
		RunState.clear_pending_map_node()
		RunState.save_game()
		get_tree().change_scene_to_file("res://scenes/map/Map.tscn")
		return
	if next_battle_id.is_empty():
		phase = Phase.COMPLETE
		battle_ui.show_message("本次战斗流程已经结束。")
		battle_ui.set_continue_state(false, "")
		return
	RunState.current_battle_id = next_battle_id
	get_tree().change_scene_to_file("res://scenes/battle/Battle.tscn")


func _on_reward_selected(option_index: int) -> void:
	if phase != Phase.VICTORY or rewards_resolved or reward_group_index >= reward_groups.size():
		return
	var group: Dictionary = reward_groups[reward_group_index]
	var options: Array = group.get("options", [])
	if group.get("mode", "choice") == "fixed":
		for reward: Variant in options:
			if reward is Dictionary:
				reward_messages.append(reward_manager.apply_reward(reward, qi_manager, method_manager))
	else:
		if option_index < 0:
			if not bool(group.get("skippable", false)):
				return
			reward_messages.append("已跳过：%s" % group.get("title", "本层奖励"))
		elif option_index >= options.size():
			return
		else:
			var reward: Dictionary = options[option_index]
			if str(reward.get("type", "")) in ["learn_spell", "learn_reward"] and not reward_manager.can_fit_spell_reward(reward):
				pending_spell_reward = reward.duplicate(true)
				battle_ui.render_spell_replacement(pending_spell_reward, reward_manager)
				return
			reward_messages.append(reward_manager.apply_reward(reward, qi_manager, method_manager))
	_finish_current_reward_group()


func _on_spell_replacement_selected(replaced_spell_id: String) -> void:
	if pending_spell_reward.is_empty() or phase != Phase.VICTORY:
		return
	if replaced_spell_id.is_empty():
		pending_spell_reward.clear()
		reward_messages.append("已跳过：%s" % reward_groups[reward_group_index].get("title", "本层奖励"))
		_finish_current_reward_group()
		return
	var message := reward_manager.replace_spell_for_reward(replaced_spell_id, pending_spell_reward)
	if message.begins_with("替换失败"):
		battle_ui.show_message(message)
		return
	reward_messages.append(message)
	pending_spell_reward.clear()
	_finish_current_reward_group()


func _finish_current_reward_group() -> void:
	reward_group_index += 1
	if reward_group_index >= reward_groups.size():
		rewards_resolved = true
		battle_ui.show_message("奖励结算完成：\n%s" % "\n".join(reward_messages))
		call_deferred("_return_to_map_after_rewards")
	else:
		battle_ui.show_message("继续选择奖励。")
	_refresh_ui()


func _return_to_map_after_rewards() -> void:
	# BattleManager在测试中也可作为子节点运行；只有实际战斗场景负责场景跳转。
	if get_tree().current_scene != self:
		return
	var map_after_victory_id := str(current_setup.get("map_after_victory_id", ""))
	if not map_after_victory_id.is_empty():
		RunState.start_map(map_after_victory_id, str(current_setup.get("map_start_node_id", "")))
	if RunState.map_active:
		RunState.clear_pending_map_node()
		get_tree().change_scene_to_file("res://scenes/map/Map.tscn")
