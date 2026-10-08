class_name UnitFactory
extends RefCounted

const REQUIRED_RUNTIME_FIELDS := [
	"template_id",
	"unit_id",
	"unit_type",
	"faction",
	"name",
	"hp",
	"shield",
	"attributes",
	"skills",
	"inventory",
	"resources",
	"statuses"
]


static func create_unit(template: Dictionary, faction: String, runtime_seed: Dictionary = {}) -> Dictionary:
	var max_hp := int(template.get("max_hp", 1))
	var template_skills: Dictionary = template.get("skills", {})
	var unit := {
		"template_id": str(template.get("id", "")),
		"unit_id": str(runtime_seed.get("unit_id", template.get("id", ""))),
		"unit_type": str(template.get("unit_type", "unknown")),
		"faction": faction,
		"name": str(template.get("name", "未命名单位")),
		"hp": {
			"current": int(runtime_seed.get("current_hp", max_hp)),
			"max": max_hp
		},
		"shield": int(runtime_seed.get("shield", 0)),
		"attributes": Dictionary(template.get("attributes", {})).duplicate(true),
		"skills": {
			"spell_ids": Array(runtime_seed.get("learned_spell_ids", template_skills.get("spell_ids", []))).duplicate(),
			"ability_ids": Array(template_skills.get("ability_ids", [])).duplicate()
		},
		"inventory": Dictionary(runtime_seed.get("inventory", template.get("inventory", {}))).duplicate(true),
		"resources": Dictionary(runtime_seed.get("resources", {})).duplicate(true),
		"spiritual_sense": Dictionary(runtime_seed.get("spiritual_sense", template.get("spiritual_sense", {"base_capacity": 0, "capacity_modifiers": {}}))).duplicate(true),
		"statuses": Dictionary(runtime_seed.get("combat_statuses", {})).duplicate(true),
		"persistent_statuses": Array(runtime_seed.get("statuses", [])).duplicate(true),
		"intent": Dictionary(template.get("intent", {})).duplicate(true),
		"action_policy": Dictionary(template.get("action_policy", {})).duplicate(true),
		"action_index": 0,
		"selected_action": {},
		"reward_table_id": str(template.get("reward_table_id", ""))
	}
	return unit


static func is_valid_unit(unit: Dictionary) -> bool:
	for field: String in REQUIRED_RUNTIME_FIELDS:
		if not unit.has(field):
			return false
	return unit.get("hp", {}) is Dictionary and unit.get("skills", {}) is Dictionary
