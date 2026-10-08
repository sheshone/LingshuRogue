class_name UIArt
extends RefCounted

const COMBAT_ATLAS: Texture2D = preload("res://assets/ui/icons/combat_icons-clean-v2.png")
const RELIC_ATLAS: Texture2D = preload("res://assets/ui/icons/relic_icons-clean-v2.png")
const MAP_ATLAS: Texture2D = preload("res://assets/ui/icons/map_node_icons-clean-v2.png")
const REWARD_ATLAS: Texture2D = preload("res://assets/ui/icons/reward_categories-clean-v1.png")
const INTENT_ATLAS: Texture2D = preload("res://assets/ui/icons/intent_icons-clean-v1.png")
const SPIRITUAL_SENSE_ICON: Texture2D = preload("res://assets/ui/icons/spiritual_sense-icon-clean-v1.png")
const COMPOSITE_INTENT_ICON: Texture2D = preload("res://assets/ui/icons/intent_combo.svg")
const HUMAN_UNITS: Texture2D = preload("res://assets/art/units/human_components-clean-v1.png")
const BEAST_UNITS: Texture2D = preload("res://assets/art/units/beast_components-clean-v1.png")
const EXPANDED_UNITS: Texture2D = preload("res://assets/art/units/expanded_units-clean-v1.png")
const SPECIALIST_UNITS: Texture2D = preload("res://assets/art/units/enemy_specialists-clean-v1.png")

const QI_INDEX := {"metal":0, "wood":1, "water":2, "fire":3, "earth":4, "any_qi":5}
const RELIC_INDEX := {
	"scarlet_flame_pearl":0, "black_tortoise_armor":1, "mystic_water_bottle":2,
	"five_element_compass":3, "sword_nurturing_gourd":4, "verdant_spirit_cauldron":5,
	"spirit_focus_seal":6, "golden_edge_whetstone":7, "vein_stabilizing_stone":8,
	"green_sprout_pendant":9, "earth_anchor_seal":10, "tidal_droplet":11,
	"echoing_dharma_mirror":12, "hollow_valley_cup":13,
	"returning_light_lamp":14, "karma_balance":15
}
const NODE_INDEX := {
	"battle":0, "elite":1, "boss":2, "event":3, "cultivation":4, "rest":5,
	"treasure":6, "shop":7, "breakthrough":8, "current":9, "locked":10, "completed":11
}
const SIMPLE_NODE_ICONS := {
	"battle": preload("res://assets/ui/icons/map_simple/battle.svg"),
	"elite": preload("res://assets/ui/icons/map_simple/elite.svg"),
	"boss": preload("res://assets/ui/icons/map_simple/boss.svg"),
	"event": preload("res://assets/ui/icons/map_simple/event.svg"),
	"cultivation": preload("res://assets/ui/icons/map_simple/cultivation.svg"),
	"rest": preload("res://assets/ui/icons/map_simple/rest.svg"),
	"treasure": preload("res://assets/ui/icons/map_simple/treasure.svg"),
	"shop": preload("res://assets/ui/icons/map_simple/shop.svg"),
	"breakthrough": preload("res://assets/ui/icons/map_simple/breakthrough.svg"),
	"current": preload("res://assets/ui/icons/map_simple/current.svg"),
	"locked": preload("res://assets/ui/icons/map_simple/locked.svg"),
	"completed": preload("res://assets/ui/icons/map_simple/completed.svg")
}


static func qi(id: String) -> Texture2D:
	return _cell(COMBAT_ATLAS, int(QI_INDEX.get(id, 5)), 4, 4)


static func combat(index: int) -> Texture2D:
	return _cell(COMBAT_ATLAS, index, 4, 4)


static func relic(id: String) -> Texture2D:
	return _cell(RELIC_ATLAS, int(RELIC_INDEX.get(id, 15)), 4, 4)


static func node(type_id: String) -> Texture2D:
	# 使用上一版绘制细节更完整的节点图集；节点名称由 MapUI 单独显示。
	return _cell(MAP_ATLAS, int(NODE_INDEX.get(type_id, NODE_INDEX.locked)), 4, 3)


static func reward(index: int) -> Texture2D:
	return _cell(REWARD_ATLAS, clampi(index, 0, 11), 4, 3)


static func intent(type_id: String) -> Texture2D:
	if type_id == "composite":
		return COMPOSITE_INTENT_ICON
	var indices := {"attack":0, "shield":1, "buff":2, "heal":3, "item":4, "charge":5, "debuff":6, "unknown":7}
	return _cell(INTENT_ATLAS, int(indices.get(type_id, 7)), 4, 2)


static func spiritual_sense() -> Texture2D:
	return SPIRITUAL_SENSE_ICON


static func enemy_preview(enemy_id: String) -> Texture2D:
	var source: Texture2D = HUMAN_UNITS
	var index := 1
	match enemy_id:
		"steel_fang_wolf": source = BEAST_UNITS; index = 0
		"withered_vine_spirit": source = SPECIALIST_UNITS; index = 3
		"ember_dust_moth": source = SPECIALIST_UNITS; index = 4
		"rock_shell_tortoise": source = EXPANDED_UNITS; index = 4
		"bandit": source = HUMAN_UNITS; index = 1
	return _cell(source, index, 3, 2)


static func _cell(atlas: Texture2D, index: int, columns: int, rows: int) -> Texture2D:
	var texture := AtlasTexture.new()
	texture.filter_clip = true
	texture.atlas = atlas
	var cell := Vector2(float(atlas.get_width()) / columns, float(atlas.get_height()) / rows)
	texture.region = Rect2(Vector2(index % columns, floori(float(index) / columns)) * cell, cell)
	return texture
