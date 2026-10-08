class_name AttributeResolver
extends RefCounted

var default_multiplier := 1.0
var relationships: Dictionary = {}


func configure(data: Dictionary) -> void:
	default_multiplier = float(data.get("default_multiplier", 1.0))
	relationships.clear()
	for relationship: Variant in data.get("relationships", []):
		if relationship is Dictionary:
			var key := "%s>%s" % [relationship.get("attacker", ""), relationship.get("defender", "")]
			relationships[key] = float(relationship.get("multiplier", default_multiplier))


func get_multiplier(attack_attribute: String, target_attributes: Dictionary, enabled: bool) -> float:
	if not enabled or attack_attribute.is_empty():
		return default_multiplier
	var defender := str(target_attributes.get("primary", ""))
	if defender.is_empty():
		return default_multiplier
	return float(relationships.get("%s>%s" % [attack_attribute, defender], default_multiplier))
