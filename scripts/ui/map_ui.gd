class_name MapUI
extends Control

const MAP_DATA_PATH := "res://data/map_nodes.json"
const MAP_GENERATION_PATH := "res://data/map_generation.json"
const DEFAULT_MAP_ID := "qi_refining_region"
const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"
const NODE_SCENE := "res://scenes/map/MapNode.tscn"
const CARD_SIZE := Vector2(116.0, 104.0)
const NODE_ICON_SIZE := Vector2(54.0, 54.0)

@onready var map_title: Label = %MapTitle
@onready var current_node_label: RichTextLabel = %CurrentNodeLabel
@onready var graph_canvas: Control = %GraphCanvas
@onready var message_label: Label = %MessageLabel

var map_definition: Dictionary = {}
var nodes: Dictionary = {}
var generation_rule: Dictionary = {}
var spell_definitions: Dictionary = {}
var relic_definitions: Dictionary = {}
var item_definitions: Dictionary = {}
var collection_overlay: Control


func _ready() -> void:
	AudioDirector.set_context("map")
	spell_definitions = GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/spells.json", "spells"), "spells")
	relic_definitions = GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/relics.json", "relics"), "relics")
	item_definitions = GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/items.json", "items"), "items")
	if not _load_map():
		message_label.text = "山路暂时无法辨认，请查看运行日志。"
		return
	graph_canvas.resized.connect(_render)
	RunState.save_game()
	_render.call_deferred()


func _load_map() -> bool:
	var maps := GameDataLoader.index_by_id(GameDataLoader.load_collection(MAP_DATA_PATH, "maps"), "map_nodes.json")
	var requested_map_id := RunState.current_map_id if RunState.map_active else DEFAULT_MAP_ID
	var base_map: Dictionary = maps.get(requested_map_id, {})
	if base_map.is_empty():
		push_error("找不到地图定义：%s" % requested_map_id)
		return false
	if not RunState.map_active:
		RunState.start_map(str(base_map.get("id", "")), str(base_map.get("start_node_id", "")))
	var rules := GameDataLoader.index_by_id(GameDataLoader.load_collection(MAP_GENERATION_PATH, "map_generation"), "map_generation.json")
	generation_rule = _find_generation_rule(rules, str(base_map.get("id", "")))
	generation_rule = generation_rule.duplicate(true)
	generation_rule["runtime_elite_counter"] = RunState.elite_encounter_counter
	var generator := MapGenerator.new()
	if RunState.generated_map_definition.is_empty():
		RunState.generated_map_definition = generator.generate(base_map, generation_rule)
	elif str(generation_rule.get("mode", "")) == "rolling_exploration":
		var generated_current := str(RunState.generated_map_definition.get("current_node_id", ""))
		if generated_current != RunState.current_map_node_id and RunState.completed_map_node_ids.has(RunState.current_map_node_id):
			RunState.generated_map_definition = generator.advance_exploration(RunState.generated_map_definition, RunState.current_map_node_id, generation_rule)
	map_definition = RunState.generated_map_definition
	nodes = GameDataLoader.index_by_id(map_definition.get("nodes", []), "generated map nodes")
	if not nodes.has(RunState.current_map_node_id):
		push_error("地图当前节点不存在：%s" % RunState.current_map_node_id)
		return false
	RunState.clear_pending_map_node()
	return true


func _find_generation_rule(rules: Dictionary, map_id: String) -> Dictionary:
	for rule: Variant in rules.values():
		if rule is Dictionary and str(rule.get("map_id", "")) == map_id:
			return rule
	return {}


func _render() -> void:
	for child: Node in graph_canvas.get_children():
		child.queue_free()
	var current: Dictionary = nodes.get(RunState.current_map_node_id, {})
	map_title.text = ""
	var hp: Dictionary = RunState.player_state.get("hp", {})
	var spell_count := Array(RunState.player_state.get("skills", {}).get("spell_ids", [])).size()
	_render_top_stats(hp)
	_configure_collection_button(%SpellsButton, UIArt.reward(5), spell_count, "神通")
	%SpellsButton.set_meta("sfx_kind", "inventory")
	%SpellsButton.tooltip_text = _spells_tooltip()
	if not %SpellsButton.pressed.is_connected(_show_spells): %SpellsButton.pressed.connect(_show_spells)
	%RelicsButton.visible = false
	%RelicsButton.set_meta("sfx_kind", "inventory")
	%RelicsButton.tooltip_text = "随身法宝（%d）\n%s" % [RunState.relics.size(), _definition_names(RunState.relics, relic_definitions)]
	if not %RelicsButton.pressed.is_connected(_show_relics): %RelicsButton.pressed.connect(_show_relics)
	_configure_collection_button(%InventoryButton, UIArt.reward(8), RunState.inventory.size() + RunState.materials.size() + RunState.relics.size(), "储物袋")
	%InventoryButton.set_meta("sfx_kind", "inventory")
	%InventoryButton.tooltip_text = _full_inventory_tooltip()
	if not %InventoryButton.pressed.is_connected(_show_inventory): %InventoryButton.pressed.connect(_show_inventory)
	_configure_collection_button(%SettingsButton, UIArt.combat(14), -1, "设置")
	%SettingsButton.set_meta("sfx_kind", "click")
	%SettingsButton.tooltip_text = "设置"
	if not %SettingsButton.pressed.is_connected(_open_settings):
		%SettingsButton.pressed.connect(_open_settings)
	var reachable := _nodes_from_ids(current.get("next_node_ids", []))
	var future := _future_nodes(reachable)
	var width := maxf(graph_canvas.size.x, 540.0)
	var height := maxf(graph_canvas.size.y, 330.0)
	var current_pos := Vector2((width - CARD_SIZE.x) * 0.5, height - CARD_SIZE.y - 8.0)
	var reachable_positions := _row_positions(reachable.size(), width, height * 0.48)
	var future_positions := _row_positions(future.size(), width, 18.0)
	var positions := {str(current.get("id", "")): current_pos}
	for index: int in reachable.size():
		positions[str(reachable[index].get("id", ""))] = reachable_positions[index]
	for index: int in future.size():
		positions[str(future[index].get("id", ""))] = future_positions[index]
	for node: Dictionary in reachable:
		_add_connection(current, node, positions)
	for node: Dictionary in reachable:
		for target_id: Variant in node.get("next_node_ids", []):
			var target: Dictionary = nodes.get(str(target_id), {})
			if not target.is_empty():
				_add_connection(node, target, positions)
	_add_node_card(current, current_pos, false, "当前所在")
	for index: int in reachable.size():
		_add_node_card(reachable[index], reachable_positions[index], true, "可前往")
	for index: int in future.size():
		_add_node_card(future[index], future_positions[index], false, "云雾中的去处")
	message_label.text = "悬停查看地点，选择一条仍亮着的山路。"


func _render_top_stats(hp: Dictionary) -> void:
	var stored: Dictionary = RunState.core_state.get("stored_qi", {})
	var total := maxi(1, RunState.get_core_qi_total())
	var ratio_parts: Array[String] = []
	for qi_id: String in ["metal", "wood", "water", "fire", "earth"]:
		ratio_parts.append("%s%d%%" % [{"metal":"金", "wood":"木", "water":"水", "fire":"火", "earth":"土"}[qi_id], roundi(float(stored.get(qi_id, 0)) / total * 100.0)])
	_configure_stat_button(%HpStat, load("res://assets/ui/icons/combat_v2/hp.png"), "%d/%d" % [int(hp.get("current", 0)), int(hp.get("max", 0))], "生命", "生命")
	_configure_stat_button(%StoneStat, load("res://assets/ui/icons/combat_v2/spirit_stone.png"), str(RunState.spirit_stones), "灵石", "灵石")
	var core_total := RunState.get_core_qi_total()
	var core_capacity := RunState.get_core_capacity()
	var amount_parts: Array[String] = []
	for qi_id: String in ["metal", "wood", "water", "fire", "earth"]:
		amount_parts.append("%s %d" % [{"metal":"金", "wood":"木", "water":"水", "fire":"火", "earth":"土"}[qi_id], int(stored.get(qi_id, 0))])
	_configure_stat_button(%CoreStat, load("res://assets/ui/icons/combat_v2/any_qi.png"), "%d/%d" % [core_total, core_capacity], "灵枢", "灵枢：当前总量 / 容量上限\n%s\n%s" % ["　".join(amount_parts), "　".join(ratio_parts)])
	var sense_used := RunState.get_spiritual_sense_used(spell_definitions)
	_configure_stat_button(%SenseStat, UIArt.spiritual_sense(), "%d/%d" % [sense_used, RunState.get_spiritual_sense_capacity()], "神识", "神识：已占用 / 总容量")


func _configure_stat_button(button: Button, icon: Texture2D, value_text: String, title_text: String, tooltip: String) -> void:
	button.icon = null
	button.text = ""
	button.tooltip_text = tooltip
	var art := button.get_node_or_null("Art") as TextureRect
	if not is_instance_valid(art):
		art = TextureRect.new(); art.name = "Art"; art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.position = Vector2(9, 2); art.size = Vector2(38, 38); button.add_child(art)
	var value := button.get_node_or_null("Value") as Label
	if not is_instance_valid(value):
		value = Label.new(); value.name = "Value"; value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value.position = Vector2(46, 0); value.size = Vector2(button.custom_minimum_size.x - 48, 39)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		value.add_theme_font_size_override("font_size", 17); button.add_child(value)
	var title := button.get_node_or_null("Title") as Label
	if not is_instance_valid(title):
		title = Label.new(); title.name = "Title"; title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.position = Vector2(0, 37); title.size = Vector2(button.custom_minimum_size.x, 21)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", Color("eadfbd"))
		button.add_child(title)
	art.texture = icon
	value.text = value_text
	title.text = title_text


func _definition_names(ids: Array, definitions: Dictionary) -> String:
	var names: Array[String] = []
	for id: Variant in ids:
		names.append(str(definitions.get(str(id), {}).get("name", id)))
	return "、".join(names) if not names.is_empty() else "尚无"


func _inventory_tooltip() -> String:
	var lines: Array[String] = []
	for item_id: String in RunState.inventory:
		var amount := int(RunState.inventory[item_id])
		if amount > 0:
			lines.append("%s ×%d" % [item_definitions.get(item_id, {}).get("name", item_id), amount])
	return "\n".join(lines) if not lines.is_empty() else "空"


func _full_inventory_tooltip() -> String:
	var lines: Array[String] = ["储物袋"]
	for item_id: String in RunState.inventory:
		var amount := int(RunState.inventory[item_id])
		if amount > 0:
			lines.append("物品｜%s ×%d" % [item_definitions.get(item_id, {}).get("name", item_id), amount])
	for item_id: String in RunState.materials:
		var amount := int(RunState.materials[item_id])
		if amount > 0:
			lines.append("材料｜%s ×%d" % [item_definitions.get(item_id, {}).get("name", item_id), amount])
	for relic_id: Variant in RunState.relics:
		lines.append("法宝｜%s" % relic_definitions.get(str(relic_id), {}).get("name", relic_id))
	if lines.size() == 1:
		lines.append("袋中尚空")
	lines.append("点击打开分类查看")
	return "\n".join(lines)


func _spells_tooltip() -> String:
	var ids: Array = RunState.player_state.get("skills", {}).get("spell_ids", [])
	var used := RunState.get_spiritual_sense_used(spell_definitions)
	var lines: Array[String] = ["神通｜神识 %d/%d" % [used, RunState.get_spiritual_sense_capacity()]]
	for spell_id: Variant in ids:
		var spell: Dictionary = spell_definitions.get(str(spell_id), {})
		lines.append("%s　神识%d" % [spell.get("name", spell_id), int(spell.get("sense_cost", 1))])
	if ids.is_empty():
		lines.append("尚未掌握神通")
	lines.append("点击查看全部神通")
	return "\n".join(lines)


func _run_summary_tooltip(hp: Dictionary) -> String:
	var stored: Dictionary = RunState.core_state.get("stored_qi", {})
	var total := maxi(1, RunState.get_core_qi_total())
	var lines := ["生命 %d/%d", "灵石 %d", "灵枢总量 %d", "神识容量 %d", "", "灵枢五行比例"]
	var result := "\n".join(lines) % [int(hp.get("current", 0)), int(hp.get("max", 0)), RunState.spirit_stones, RunState.get_core_qi_total(), RunState.get_spiritual_sense_capacity()]
	for qi_id: String in ["metal", "wood", "water", "fire", "earth"]:
		result += "\n%s %d%%" % [{"metal":"金", "wood":"木", "water":"水", "fire":"火", "earth":"土"}[qi_id], roundi(float(stored.get(qi_id, 0)) / total * 100.0)]
	return result


func _show_spells() -> void:
	var entries: Array[Dictionary] = []
	for id: Variant in RunState.player_state.get("skills", {}).get("spell_ids", []):
		var definition: Dictionary = spell_definitions.get(str(id), {})
		entries.append({"name":definition.get("name", id), "description":definition.get("description", ""), "icon":UIArt.reward(5)})
	_show_collection("已掌握神通", entries)


func _show_relics() -> void:
	var entries: Array[Dictionary] = []
	for id: Variant in RunState.relics:
		var definition: Dictionary = relic_definitions.get(str(id), {})
		entries.append({"name":definition.get("name", id), "description":definition.get("description", ""), "icon":UIArt.relic(str(id))})
	_show_collection("随身法宝", entries)


func _show_inventory() -> void:
	var item_entries: Array[Dictionary] = []
	var material_entries: Array[Dictionary] = []
	for id: String in RunState.inventory:
		var definition: Dictionary = item_definitions.get(id, {})
		var entry := {"name":"%s ×%d" % [definition.get("name", id), int(RunState.inventory[id])], "description":definition.get("description", ""), "icon":UIArt.reward(10) if definition.get("type", "") == "material" else UIArt.reward(8)}
		if definition.get("type", "") == "material": material_entries.append(entry)
		else: item_entries.append(entry)
	for id: String in RunState.materials:
		var definition: Dictionary = item_definitions.get(id, {})
		material_entries.append({"name":"%s ×%d" % [definition.get("name", id), int(RunState.materials[id])], "description":definition.get("description", ""), "icon":UIArt.reward(10)})
	var relic_entries: Array[Dictionary] = []
	for id: Variant in RunState.relics:
		var definition: Dictionary = relic_definitions.get(str(id), {})
		relic_entries.append({"name":definition.get("name", id), "description":definition.get("description", ""), "icon":UIArt.relic(str(id))})
	_show_bag_tabs({"物品":item_entries, "材料":material_entries, "法宝":relic_entries})


func _show_collection(title_text: String, entries: Array[Dictionary]) -> void:
	if is_instance_valid(collection_overlay): collection_overlay.queue_free()
	collection_overlay = Control.new()
	collection_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	collection_overlay.z_index = 100
	add_child(collection_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.015, 0.012, 0.78)
	collection_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 80; center.offset_top = 50; center.offset_right = -80; center.offset_bottom = -50
	collection_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ArtPanel"
	panel.custom_minimum_size = Vector2(680, 520)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	var heading := Label.new()
	heading.text = title_text
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 26)
	content.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	if entries.is_empty():
		var empty := Label.new(); empty.text = "尚无"; empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; list.add_child(empty)
	for entry: Dictionary in entries:
		var row := HBoxContainer.new(); row.custom_minimum_size.y = 68; row.add_theme_constant_override("separation", 14); list.add_child(row)
		var icon := TextureRect.new(); icon.texture = entry.icon; icon.custom_minimum_size = Vector2(54,54); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; row.add_child(icon)
		var copy := VBoxContainer.new(); copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(copy)
		var name := Label.new(); name.text = str(entry.name); name.add_theme_font_size_override("font_size",18); copy.add_child(name)
		var desc := Label.new(); desc.text = str(entry.description); desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; copy.add_child(desc)
	var close := Button.new(); close.text = "合上"; close.custom_minimum_size = Vector2(200,42); close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; close.set_meta("sfx_kind","back"); close.pressed.connect(func() -> void: collection_overlay.queue_free()); content.add_child(close)


func _show_bag_tabs(groups: Dictionary) -> void:
	if is_instance_valid(collection_overlay): collection_overlay.queue_free()
	collection_overlay = Control.new(); collection_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); collection_overlay.z_index = 100; add_child(collection_overlay)
	var shade := ColorRect.new(); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.color = Color(0.01, 0.015, 0.012, 0.78); collection_overlay.add_child(shade)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); center.offset_left = 100; center.offset_top = 60; center.offset_right = -100; center.offset_bottom = -60; collection_overlay.add_child(center)
	var panel := PanelContainer.new(); panel.theme_type_variation = &"ArtPanel"; panel.custom_minimum_size = Vector2(720, 520); center.add_child(panel)
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation", 10); panel.add_child(content)
	var heading := Label.new(); heading.text = "储物袋"; heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; heading.add_theme_font_size_override("font_size", 26); content.add_child(heading)
	var tabs := TabContainer.new(); tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL; content.add_child(tabs)
	for group_name: String in ["物品", "材料", "法宝"]:
		var scroll := ScrollContainer.new(); scroll.name = group_name; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; tabs.add_child(scroll)
		var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list.add_theme_constant_override("separation", 8); scroll.add_child(list)
		var entries: Array = groups.get(group_name, [])
		if entries.is_empty():
			var empty := Label.new(); empty.text = "暂无%s" % group_name; empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; list.add_child(empty)
		for entry: Dictionary in entries:
			var row := HBoxContainer.new(); row.custom_minimum_size.y = 72; row.add_theme_constant_override("separation", 14); list.add_child(row)
			var icon := TextureRect.new(); icon.texture = entry.icon; icon.custom_minimum_size = Vector2(58,58); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; row.add_child(icon)
			var copy := VBoxContainer.new(); copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(copy)
			var name := Label.new(); name.text = str(entry.name); name.add_theme_font_size_override("font_size",18); copy.add_child(name)
			var desc := Label.new(); desc.text = str(entry.description); desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; copy.add_child(desc)
	var close := Button.new(); close.text = "合上"; close.custom_minimum_size = Vector2(200,42); close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; close.set_meta("sfx_kind","back"); close.pressed.connect(func() -> void: collection_overlay.queue_free()); content.add_child(close)


func _configure_collection_button(button: Button, icon: Texture2D, count: int, title: String) -> void:
	button.icon = null
	button.text = ""
	var art := button.get_node_or_null("Art") as TextureRect
	if not is_instance_valid(art):
		art = TextureRect.new()
		art.name = "Art"
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		button.add_child(art)
		art.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		art.position = Vector2(28, 0)
		art.size = Vector2(56, 40)
	var title_label := button.get_node_or_null("Title") as Label
	if not is_instance_valid(title_label):
		title_label = Label.new()
		title_label.name = "Title"
		title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.add_theme_font_size_override("font_size", 15)
		button.add_child(title_label)
		title_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		title_label.position = Vector2(0, 39)
		title_label.size = Vector2(112, 21)
	art.texture = icon
	title_label.text = title
	var badge := button.get_node_or_null("CountBadge") as Label
	if not is_instance_valid(badge):
		badge = Label.new()
		badge.name = "CountBadge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", Color("fff2c5"))
		badge.add_theme_color_override("font_shadow_color", Color("000000"))
		badge.add_theme_constant_override("shadow_offset_x", 1)
		badge.add_theme_constant_override("shadow_offset_y", 1)
		button.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		badge.position = Vector2(70, 12)
		badge.size = Vector2(22, 22)
	badge.text = str(count)
	badge.visible = count >= 0


func _open_settings() -> void:
	RunState.save_game()
	get_tree().change_scene_to_file("res://scenes/ui/Settings.tscn")


func _row_positions(count: int, width: float, y: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if count <= 0:
		return result
	var gap := minf(40.0, maxf(8.0, (width - CARD_SIZE.x * count) / float(count + 1)))
	var total := CARD_SIZE.x * count + gap * (count - 1)
	var start_x := maxf(0.0, (width - total) * 0.5)
	for index: int in count:
		result.append(Vector2(start_x + index * (CARD_SIZE.x + gap), y))
	return result


func _nodes_from_ids(ids: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node_id: Variant in ids:
		var node: Dictionary = nodes.get(str(node_id), {})
		if not node.is_empty():
			result.append(node)
	return result


func _future_nodes(reachable: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for source: Dictionary in reachable:
		for node_id: Variant in source.get("next_node_ids", []):
			var normalized := str(node_id)
			if seen.has(normalized):
				continue
			var node: Dictionary = nodes.get(normalized, {})
			if not node.is_empty():
				seen[normalized] = true
				result.append(node)
	return result


func _add_connection(from_node: Dictionary, to_node: Dictionary, positions: Dictionary) -> void:
	var from_id := str(from_node.get("id", ""))
	var to_id := str(to_node.get("id", ""))
	if not positions.has(from_id) or not positions.has(to_id):
		return
	var line := Line2D.new()
	var reachable_now := from_id == RunState.current_map_node_id
	line.width = 2.6 if reachable_now else 1.4
	line.default_color = Color(0.86, 0.69, 0.3, 0.9) if reachable_now else Color(0.36, 0.38, 0.34, 0.48)
	line.points = PackedVector2Array([_node_icon_center(positions[from_id]), _node_icon_center(positions[to_id])])
	graph_canvas.add_child(line)


func _node_icon_center(card_position: Vector2) -> Vector2:
	return card_position + Vector2(CARD_SIZE.x * 0.5, 2.0 + NODE_ICON_SIZE.y * 0.5)


func _add_node_card(node: Dictionary, position: Vector2, selectable: bool, state_text: String) -> void:
	var card := Control.new()
	card.position = position
	card.size = CARD_SIZE
	card.clip_contents = true
	graph_canvas.add_child(card)
	var type_id := str(node.get("type", ""))
	var button := TextureButton.new()
	var display_texture := UIArt.node(type_id if state_text != "当前所在" else "current")
	if str(map_definition.get("id", "")) == "initiation_grounds" and selectable and node.has("element"):
		display_texture = UIArt.qi(str(node.get("element", "any_qi")))
	button.texture_normal = display_texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.position = Vector2((CARD_SIZE.x - NODE_ICON_SIZE.x) * 0.5, 2.0)
	button.size = NODE_ICON_SIZE
	if state_text == "当前所在":
		button.tooltip_text = "%s\n%s" % [str(node.get("name", "山路")), str(node.get("description", ""))]
	else:
		button.tooltip_text = "%s｜%s\n%s" % [_type_name(type_id), str(node.get("name", "未知地点")), str(node.get("description", ""))]
	button.disabled = not selectable
	button.set_meta("sfx_kind", "node")
	button.set_meta("map_node_id", str(node.get("id", "")))
	button.set_meta("route_preview", not selectable)
	card.add_child(button)
	var type_caption := Label.new()
	type_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_caption.position = Vector2(2.0, 60.0)
	type_caption.size = Vector2(CARD_SIZE.x - 4.0, 28.0)
	type_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_caption.text = _node_caption(node, state_text)
	type_caption.add_theme_font_size_override("font_size", 14)
	type_caption.add_theme_color_override("font_color", _node_caption_color(type_id, selectable))
	type_caption.add_theme_color_override("font_outline_color", Color("151813"))
	type_caption.add_theme_constant_override("outline_size", 3)
	card.add_child(type_caption)
	card.modulate = Color.WHITE if selectable or state_text == "当前所在" else Color(0.48, 0.5, 0.47, 0.78)
	if selectable:
		var node_id := str(node.get("id", ""))
		button.pressed.connect(func() -> void: _select_node(node_id))
		button.mouse_entered.connect(func() -> void:
			card.pivot_offset = card.size * 0.5
			create_tween().tween_property(card, "scale", Vector2(1.1, 1.1), 0.12)
		)
		button.mouse_exited.connect(func() -> void: create_tween().tween_property(card, "scale", Vector2.ONE, 0.12))


func _node_caption(node: Dictionary, state_text: String) -> String:
	if state_text == "当前所在":
		return "当前位置"
	if str(map_definition.get("id", "")) == "initiation_grounds" and node.has("element"):
		return "%s行试炼" % {"metal":"金", "wood":"木", "water":"水", "fire":"火", "earth":"土"}.get(str(node.get("element", "")), "五行")
	return str({
		"battle":"历战", "elite":"苦斗", "boss":"首领",
		"event":"机缘", "cultivation":"修行", "rest":"歇脚",
		"treasure":"丰获", "shop":"坊市", "breakthrough":"闭关"
	}.get(str(node.get("type", "")), "未知"))


func _node_caption_color(type_id: String, selectable: bool) -> Color:
	if not selectable:
		return Color("9a9d94")
	return {
		"battle":Color("ead7a0"), "elite":Color("e5a84c"), "boss":Color("df6655"),
		"event":Color("c5a5dc"), "cultivation":Color("82cba3"), "rest":Color("e8a066"),
		"treasure":Color("e2bd58"), "shop":Color("d9c27a"), "breakthrough":Color("8fd7df")
	}.get(type_id, Color("eadfbd"))


func _select_node(node_id: String) -> void:
	if not _is_selectable(node_id):
		message_label.text = "此处尚无道路可达。"
		return
	var node: Dictionary = nodes.get(node_id, {})
	if node.is_empty():
		return
	RunState.select_map_node(node)
	match str(node.get("type", "")):
		"battle", "elite", "boss":
			var setup_id := str(node.get("battle_setup_id", ""))
			if setup_id.is_empty():
				message_label.text = "这处遭遇缺少战斗配置。"
				return
			RunState.current_battle_id = setup_id
			get_tree().change_scene_to_file(BATTLE_SCENE)
		"event", "cultivation", "rest", "breakthrough", "treasure", "shop":
			get_tree().change_scene_to_file(NODE_SCENE)
		_:
			message_label.text = "此处尚未开放。"


func _is_selectable(node_id: String) -> bool:
	var current: Dictionary = nodes.get(RunState.current_map_node_id, {})
	if Array(current.get("next_node_ids", [])).has(node_id):
		return true
	return bool(nodes.get(node_id, {}).get("early_access", false))


func _type_name(type_id: String) -> String:
	return {"battle":"战斗", "elite":"精英", "boss":"首领", "event":"机缘", "cultivation":"修炼", "rest":"休息", "treasure":"宝匣", "shop":"商铺", "breakthrough":"突破"}.get(type_id, "未知")


func _type_color(type_id: String) -> Color:
	return {"battle":Color("c7b47a"), "elite":Color("d85a52"), "boss":Color("b77be2"), "event":Color("64c4ad"), "cultivation":Color("73a8d5"), "rest":Color("8fbd79"), "treasure":Color("e0bc58"), "shop":Color("d58b55"), "breakthrough":Color("f0dfaa")}.get(type_id, Color("aaaaaa"))
