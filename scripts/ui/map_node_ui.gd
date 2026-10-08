class_name MapNodeUI
extends Control

const MAP_SCENE := "res://scenes/map/Map.tscn"
const COMPLETE_SCENE := "res://scenes/map/ChapterComplete.tscn"

@onready var title_label: Label = %TitleLabel
@onready var type_label: Label = %TypeLabel
@onready var description_label: Label = %DescriptionLabel
@onready var choice_container: GridContainer = %ChoiceContainer
@onready var result_label: Label = %ResultLabel
@onready var continue_button: Button = %ContinueButton
@onready var main_panel: PanelContainer = $Center/Panel

var node_manager := MapNodeManager.new()
var current_node: Dictionary = {}
var current_content: Dictionary = {}
var spell_definitions: Dictionary = {}
var item_definitions: Dictionary = {}
var method_definitions: Dictionary = {}


func _ready() -> void:
	resized.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	node_manager.configure()
	spell_definitions = GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/spells.json", "spells"), "spells.json")
	item_definitions = GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/items.json", "items"), "items.json")
	method_definitions = GameDataLoader.index_by_id(GameDataLoader.load_collection("res://data/cultivation_methods.json", "cultivation_methods"), "cultivation_methods.json")
	current_node = RunState.pending_map_node
	continue_button.pressed.connect(_on_continue)
	if current_node.is_empty():
		title_label.text = "地图节点"
		type_label.text = "没有待处理的节点。"
		description_label.text = "返回地图继续选择路线。"
		continue_button.visible = true
		return
	var type_id := str(current_node.get("type", ""))
	AudioDirector.set_context("shop" if type_id == "shop" else ("rest" if type_id == "rest" else "map"))
	if type_id == "treasure":
		AudioDirector.play_sfx("chest")
	current_content = node_manager.get_runtime_content(current_node)
	choice_container.columns = (3 if size.x >= 1080.0 else (2 if size.x >= 720.0 else 1)) if type_id == "shop" else 1
	title_label.text = str(current_content.get("title", current_node.get("name", "地图节点")))
	type_label.text = _shop_resource_summary() if type_id == "shop" else _type_name(type_id)
	description_label.text = str(current_content.get("description", current_node.get("description", "")))
	if type_id == "breakthrough":
		_render_breakthrough_button()
	else:
		_render_choices()
	if type_id in ["shop", "treasure"]:
		continue_button.text = "离开" if type_id == "shop" else "合上木匣"
		continue_button.visible = true


func _apply_responsive_layout() -> void:
	if not is_instance_valid(main_panel):
		return
	main_panel.custom_minimum_size = Vector2(clampf(size.x * 0.72, 420.0, 900.0), clampf(size.y - 160.0, 380.0, 570.0))
	if is_instance_valid(choice_container) and str(current_node.get("type", "")) == "shop":
		choice_container.columns = 3 if size.x >= 1080.0 else (2 if size.x >= 720.0 else 1)


func _render_choices() -> void:
	var choices: Array = current_content.get("choices", [])
	if choices.is_empty():
		RunState.complete_pending_map_node()
		result_label.text = "此处暂时没有可取之物。"
		continue_button.visible = true
		return
	for index: int in choices.size():
		var choice: Dictionary = choices[index]
		var is_shop := str(current_node.get("type", "")) == "shop"
		var price := int(choice.get("spirit_stone_cost", 0))
		var price_text := " · %d灵石" % price if price > 0 else ""
		if is_shop:
			_add_shop_card(choice, index, price)
			continue
		var button := Button.new()
		button.text = "%s\n%d 灵石" % [choice.get("name", "货品"), price] if is_shop else "%s%s\n%s" % [choice.get("name", "选择"), price_text, choice.get("description", "")]
		button.tooltip_text = "%s%s\n%s" % [choice.get("name", "选择"), price_text, choice.get("description", "")]
		button.icon = _choice_icon(choice)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 58 if is_shop else 36)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if is_shop else HORIZONTAL_ALIGNMENT_LEFT
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER if is_shop else HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(190.0, 116.0) if is_shop else Vector2(clampf(main_panel.size.x - 150.0, 360.0, 720.0), 72.0)
		button.set_meta("sfx_kind", "shop" if str(current_node.get("type", "")) == "shop" else "choice")
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if is_shop else Control.SIZE_SHRINK_CENTER
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = not node_manager.can_afford_runtime_choice(choice)
		button.pressed.connect(func() -> void: _choose(index))
		choice_container.add_child(button)


func _add_shop_card(choice: Dictionary, index: int, price: int) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(190, 138)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("091813e8")
	style.border_color = Color("8f753dbb")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12; style.content_margin_right = 12; style.content_margin_top = 10; style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(content)
	var icon := TextureRect.new()
	icon.texture = _choice_icon(choice)
	icon.custom_minimum_size = Vector2(66, 66)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(icon)
	var name := Label.new()
	name.text = str(choice.get("name", "货品"))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.clip_text = true
	content.add_child(name)
	var price_label := Label.new()
	price_label.text = "%d 灵石" % price
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.add_theme_color_override("font_color", Color("e4bd58"))
	content.add_child(price_label)
	var hit := Button.new()
	hit.flat = true
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.tooltip_text = _shop_choice_tooltip(choice, price)
	hit.set_meta("sfx_kind", "shop")
	hit.disabled = not node_manager.can_afford_runtime_choice(choice)
	hit.pressed.connect(func() -> void: _choose(index))
	card.add_child(hit)
	if hit.disabled: card.modulate = Color(0.55, 0.57, 0.53, 0.72)
	choice_container.add_child(card)


func _choice_icon(choice: Dictionary) -> Texture2D:
	var effects: Array = choice.get("effects", [])
	if effects.is_empty():
		return UIArt.combat(12)
	var effect: Dictionary = effects[0]
	match str(effect.get("type", "")):
		"add_relic": return UIArt.relic(str(effect.get("relic_id", "")))
		"add_item":
			var item: Dictionary = item_definitions.get(str(effect.get("item_id", "")), {})
			if str(item.get("type", "")) == "material": return UIArt.reward(10)
			return UIArt.reward(9 if "pill" in str(effect.get("item_id", "")) else 8)
		"add_spirit_stones": return UIArt.combat(9)
		"add_core_qi": return UIArt.qi(str(effect.get("qi", "any_qi")))
		"learn_spell": return _spell_manual_icon(str(effect.get("spell_id", "")))
		"learn_method": return _method_manual_icon(str(effect.get("method_id", "")))
		"heal": return UIArt.combat(11)
		_: return UIArt.reward(11)


func _spell_manual_icon(spell_id: String) -> Texture2D:
	var spell: Dictionary = spell_definitions.get(spell_id, {})
	for tag: Variant in spell.get("tags", []):
		var index := ["metal", "wood", "water", "fire", "earth"].find(str(tag))
		if index >= 0:
			return UIArt.reward(index)
	return UIArt.reward(5)


func _method_manual_icon(method_id: String) -> Texture2D:
	var method: Dictionary = method_definitions.get(method_id, {})
	for qi_id: String in ["metal", "wood", "water", "fire", "earth"]:
		if method.get("element_affinity", {}).has(qi_id):
			return UIArt.reward(["metal", "wood", "water", "fire", "earth"].find(qi_id))
	return UIArt.reward(6)


func _render_breakthrough_button() -> void:
	var button := Button.new()
	button.text = "检查当前突破条件"
	button.custom_minimum_size = Vector2(0.0, 48.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_check_breakthrough)
	choice_container.add_child(button)


func _choose(index: int) -> void:
	var choices: Array = current_content.get("choices", [])
	var choice: Dictionary = choices[index] if index >= 0 and index < choices.size() else {}
	if choice.has("breakthrough_rule_id"):
		_attempt_rest_breakthrough(str(choice.get("breakthrough_rule_id", "")))
		return
	var messages := node_manager.apply_runtime_choice(choice)
	var is_shop := str(current_node.get("type", "")) == "shop"
	if not is_shop:
		RunState.complete_pending_map_node()
	result_label.text = "\n".join(messages)
	if is_shop:
		AudioDirector.play_sfx("purchase")
		current_content = node_manager.get_runtime_content(current_node)
		_render_choices_after_purchase(index)
	else:
		_clear_choices()
		continue_button.visible = true


func _render_choices_after_purchase(index: int) -> void:
	var cache_id := str(current_node.get("id", ""))
	var offers: Array = RunState.node_offer_cache.get(cache_id, [])
	if index >= 0 and index < offers.size():
		offers.remove_at(index)
	RunState.node_offer_cache[cache_id] = offers
	_clear_choices()
	current_content["choices"] = offers
	_render_choices()
	type_label.text = _shop_resource_summary()


func _shop_resource_summary() -> String:
	var stored: Dictionary = RunState.core_state.get("stored_qi", {})
	return "商棚　灵石 %d　｜　灵枢 %d/%d　金%d 木%d 水%d 火%d 土%d" % [
		RunState.spirit_stones, RunState.get_core_qi_total(), RunState.get_core_capacity(),
		int(stored.get("metal", 0)), int(stored.get("wood", 0)), int(stored.get("water", 0)),
		int(stored.get("fire", 0)), int(stored.get("earth", 0))
	]


func _shop_choice_tooltip(choice: Dictionary, price: int) -> String:
	var lines: Array[String] = ["%s · %d灵石" % [choice.get("name", "货品"), price], str(choice.get("description", ""))]
	var stored: Dictionary = RunState.core_state.get("stored_qi", {})
	for effect: Variant in choice.get("effects", []):
		if effect is Dictionary and str(effect.get("type", "")) == "convert_core_qi":
			var from_qi := str(effect.get("from_qi", ""))
			var to_qi := str(effect.get("to_qi", ""))
			var amount := int(effect.get("value", 0))
			var names := {"metal":"金", "wood":"木", "water":"水", "fire":"火", "earth":"土"}
			var total := maxi(1, RunState.get_core_qi_total())
			var attribute_caps: Dictionary = RunState.core_state.get("attribute_capacity", {})
			var modifiers: Dictionary = RunState.core_state.get("capacity_modifiers", {})
			var target_cap := int(attribute_caps.get(to_qi, RunState.get_core_capacity())) + int(modifiers.get(to_qi, 0))
			var transferable := mini(amount, mini(int(stored.get(from_qi, 0)), maxi(0, target_cap - int(stored.get(to_qi, 0)))))
			var from_before := float(stored.get(from_qi, 0)) / float(total) * 100.0
			var to_before := float(stored.get(to_qi, 0)) / float(total) * 100.0
			var from_after := float(int(stored.get(from_qi, 0)) - transferable) / float(total) * 100.0
			var to_after := float(int(stored.get(to_qi, 0)) + transferable) / float(total) * 100.0
			lines.append("当前：%s%d　%s%d" % [names.get(from_qi, from_qi), int(stored.get(from_qi, 0)), names.get(to_qi, to_qi), int(stored.get(to_qi, 0))])
			lines.append("交易后：%s-%d　%s+%d" % [names.get(from_qi, from_qi), transferable, names.get(to_qi, to_qi), transferable])
			lines.append("占比：%s %.0f%%→%.0f%%　%s %.0f%%→%.0f%%" % [names.get(from_qi, from_qi), from_before, from_after, names.get(to_qi, to_qi), to_before, to_after])
	return "\n".join(lines)


func _leave_without_choice() -> void:
	RunState.complete_pending_map_node()
	result_label.text = "山风掠过案前，你转身继续赶路。"
	_clear_choices()
	continue_button.visible = true


func _on_continue() -> void:
	if str(current_node.get("type", "")) in ["shop", "treasure"] and not RunState.completed_map_node_ids.has(str(current_node.get("id", ""))):
		RunState.complete_pending_map_node()
	_return_to_map()


func _attempt_rest_breakthrough(rule_id: String) -> void:
	var lines: Array[String] = []
	var all_met := true
	for result: Dictionary in node_manager.evaluate_rule(rule_id):
		all_met = all_met and bool(result.met)
		var condition_text := str(result.get("detail", "%s：%d / %d" % [result.label, result.current, result.target]))
		lines.append("%s（%s）" % [condition_text, "已满足" if result.met else "未满足"])
	lines.append("闭关根基圆满，已具备筑基资格。" if all_met else "此次闭关未能叩开玄关，休息机会已经消耗。")
	RunState.complete_pending_map_node()
	if all_met:
		AudioDirector.set_context("breakthrough")
		AudioDirector.play_sfx("breakthrough")
		RunState.complete_realm("qi_refining")
	result_label.text = "\n".join(lines)
	_clear_choices()
	continue_button.visible = true
	if all_met:
		continue_button.text = "查看炼气篇结算"


func _check_breakthrough() -> void:
	var lines: Array[String] = []
	var all_met := true
	for result: Dictionary in node_manager.evaluate_conditions(str(current_node.get("content_id", ""))):
		var met: bool = result.met
		all_met = all_met and met
		var condition_text := str(result.get("detail", "%s：%d / %d" % [result.label, result.current, result.target]))
		lines.append("%s（%s）" % [condition_text, "已满足" if met else "未满足"])
	lines.append("诸项根基已经齐备，可以择机叩关。" if all_met else "根基尚有缺漏，先返回山中继续历练。")
	if all_met:
		RunState.complete_pending_map_node()
	else:
		RunState.return_from_breakthrough_check()
	result_label.text = "\n".join(lines)
	_clear_choices()
	continue_button.visible = true


func _clear_choices() -> void:
	for child: Node in choice_container.get_children():
		child.queue_free()


func _return_to_map() -> void:
	RunState.clear_pending_map_node()
	RunState.save_game()
	get_tree().change_scene_to_file(COMPLETE_SCENE if RunState.run_completed else MAP_SCENE)


func _type_name(type_id: String) -> String:
	return {
		"event": "机缘节点",
		"cultivation": "修炼节点",
		"rest": "休息节点",
		"breakthrough": "突破节点",
		"shop": "商棚",
		"treasure": "宝匣"
	}.get(type_id, "地图节点")
