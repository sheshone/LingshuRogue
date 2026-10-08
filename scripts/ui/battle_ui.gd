class_name BattleUI
extends Control

signal spell_selected(spell_id: String)
signal item_selected(item_id: String)
signal target_selected(unit_id: String)
signal enemy_action_requested
signal continue_requested
signal reward_selected(option_index: int)
signal spell_replacement_selected(spell_id: String)

const ATTRIBUTE_NAMES := {
	"metal": "金",
	"wood": "木",
	"water": "水",
	"fire": "火",
	"earth": "土"
}
const ATTRIBUTE_COLORS := {
	"fire": Color("c95745"),
	"water": Color("4d86bd"),
	"wood": Color("45a078"),
	"metal": Color("d0a84f"),
	"earth": Color("ad7b3f")
}
const REALM_NAMES := {
	"qi_refining": "炼气"
}
const STATUS_NAMES := {
	"flame_seed": "火种",
	"terrain": "地势",
	"attack_up": "攻击提升",
	"defense_up": "防御提升",
	"charged": "蓄势"
	,"sharpness": "锋锐"
	,"vitality": "生机"
	,"flow": "回流"
}
const CARD_FRAME: Texture2D = preload("res://assets/ui/generated/spell_card_frame-v2.png")
const CULTIVATOR_ATLAS: Texture2D = preload("res://assets/art/portraits/cultivator_atlas-v1.png")
const BEAST_ATLAS: Texture2D = preload("res://assets/art/portraits/beast_atlas-v1.png")

@onready var title_label: Label = %TitleLabel
@onready var turn_label: Label = %TurnLabel
@onready var player_label: Label = %PlayerLabel
@onready var spell_title: RichTextLabel = %SpellTitle
@onready var qi_label: RichTextLabel = %QiLabel
@onready var core_qi_label: RichTextLabel = %CoreQiLabel
@onready var player_status_label: Label = %PlayerStatusLabel
@onready var relic_container: HBoxContainer = %RelicContainer
@onready var enemy_container: VBoxContainer = %EnemyContainer
@onready var enemy_scroll: ScrollContainer = %EnemyScroll
@onready var spell_container: HFlowContainer = %SpellContainer
@onready var player_visual_host: Control = %PlayerVisualHost
@onready var enemy_visual_host: HBoxContainer = %EnemyVisualHost
@onready var item_container: VBoxContainer = %ItemContainer
@onready var item_panel: PanelContainer = %ItemPanel
@onready var reward_panel: VBoxContainer = %RewardPanel
@onready var reward_screen: Control = %RewardScreen
@onready var battle_content: MarginContainer = %BattleContent
@onready var reward_title: Label = %RewardTitle
@onready var reward_help_label: Label = %RewardHelpLabel
@onready var reward_container: GridContainer = %RewardContainer
@onready var reward_skip_button: Button = %RewardSkipButton
@onready var enemy_action_button: Button = %EnemyActionButton
@onready var continue_button: Button = %ContinueButton
@onready var message_label: Label = %MessageLabel
@onready var action_flash: ColorRect = %ActionFlash

var last_player_hp := -1
var last_enemy_hp: Dictionary = {}
var feedback_tween: Tween
var floating_labels: Array[Label] = []
var relic_buttons: Dictionary = {}
var relic_render_signature := ""
var responsive_spell_height := 85.0
var responsive_enemy_height := 76.0
var enemy_visuals: Dictionary = {}
var player_visual: UnitVisual
var last_sea_qi_signature := ""
var last_sea_qi_state: Dictionary = {}
var victory_guard_shown := false
var dantian_overlay: Control
var dantian_icons: Dictionary = {}
var core_counter_tween: Tween
var spell_input_locked := false
var reward_skip_is_replacement := false


func _ready() -> void:
	# 法宝作为战场覆盖层显示，不再占用顶部 VBox 的自然高度。
	# 这样法宝数量增加也不会把回合信息和底部行动按钮推出视口。
	var arena := $BattleContent/Main/MiddlePanel/Middle/Arena as Control
	relic_container.reparent(arena, false)
	relic_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	relic_container.offset_left = 300.0
	relic_container.offset_top = 6.0
	relic_container.offset_right = -300.0
	relic_container.offset_bottom = 58.0
	relic_container.alignment = BoxContainer.ALIGNMENT_CENTER
	relic_container.z_index = 45
	resized.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	enemy_action_button.pressed.connect(func() -> void:
		_play_click_feedback(Color("d3ad62"))
		enemy_action_requested.emit()
	)
	continue_button.pressed.connect(func() -> void:
		_play_click_feedback(Color("d3ad62"))
		continue_requested.emit()
	)
	continue_button.visible = false
	reward_skip_button.pressed.connect(func() -> void:
		_play_click_feedback(Color("817968"))
		if reward_skip_is_replacement:
			spell_replacement_selected.emit("")
		else:
			reward_selected.emit(-1)
	)
	reward_panel.visible = false
	reward_screen.visible = false
	qi_label.tooltip_text = "丹田｜当前回合可用灵气\n由灵枢凝聚，施展神通时消耗；回合结束后未使用部分全部散逸。"
	core_qi_label.tooltip_text = "灵枢｜本场剩余可凝聚灵气\n战斗中逐次调用，战斗结束后恢复。"
	player_status_label.tooltip_text = "状态只在当前战斗生效；法宝会持续改变本局规则。"
	spell_title.tooltip_text = "神识：当前已占用容量 / 可用总容量。悬停神通卡可查看其占用。"
	spell_title.mouse_filter = Control.MOUSE_FILTER_STOP
	spell_title.z_index = 50


func render_state(state: Dictionary, qi_manager: QiManager) -> void:
	title_label.text = str(state.get("title", "灵枢试炼"))
	turn_label.text = "回合 %d · %s" % [state.get("turn", 0), state.get("phase_name", "")]
	player_label.text = "%d/%d" % [state.get("spiritual_sense_used", 0), state.get("spiritual_sense_capacity", 0)]
	spell_title.text = "[center][img=22x22]res://assets/ui/icons/combat_v2/sense.png[/img] %d/%d[/center]" % [state.get("spiritual_sense_used", 0), state.get("spiritual_sense_capacity", 0)]
	var current_player_hp := int(state.get("player_hp", 0))
	if last_player_hp >= 0 and current_player_hp < last_player_hp:
		_flash_control(player_label, Color("ef7664"))
		_spawn_float_text("-%d" % (last_player_hp - current_player_hp), Color("ef7664"), Vector2(0.25, 0.2))
	last_player_hp = current_player_hp
	player_status_label.text = "状态　%s" % state.get("player_statuses", "无")
	player_status_label.tooltip_text = str(state.get("status_tooltip", "当前没有战斗状态。"))
	_render_relics(state.get("relics", []), state.get("relic_trigger_counts", {}))
	var sea_qi := qi_manager.get_sea_qi()
	var sea_signature := JSON.stringify(sea_qi)
	var core_qi := qi_manager.get_core_stored_qi()
	# Populate the core first. On the opening frame the container has not sorted
	# this label yet; defer gather particles until its final rect is available.
	_set_core_qi_display(core_qi)
	_render_dantian_arc(sea_qi)
	if sea_signature != last_sea_qi_signature:
		call_deferred("_animate_qi_gather", last_sea_qi_state.duplicate(true), sea_qi.duplicate(true))
	last_sea_qi_signature = sea_signature
	last_sea_qi_state = sea_qi.duplicate(true)
	if not is_instance_valid(player_visual):
		player_visual = UnitVisual.new()
		player_visual_host.add_child(player_visual)
		player_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		player_visual.configure({"id":"player","unit_id":"player","name":state.get("player_name","修士"),"hp":{"current":state.get("player_hp",0),"max":state.get("player_max_hp",0)},"shield":state.get("player_shield",0),"statuses":state.get("player_status_data",{})}, true)
	else:
		player_visual.update_unit({"name":state.get("player_name","修士"),"hp":{"current":state.get("player_hp",0),"max":state.get("player_max_hp",0)},"shield":state.get("player_shield",0),"statuses":state.get("player_status_data",{})}, false)


func _set_core_qi_display(core_qi: Dictionary) -> void:
	var parts: Array[String] = []
	var core_total := 0
	for qi_id: String in ["metal", "wood", "water", "fire", "earth"]:
		var qi_name := str(ATTRIBUTE_NAMES.get(qi_id, qi_id))
		var qi_amount := int(core_qi.get(qi_id, 0))
		core_total += qi_amount
		parts.append("[hint=%s灵气：%d][img=20x20]res://assets/ui/icons/combat_v2/%s.png[/img] %d[/hint]" % [qi_name, qi_amount, qi_id, qi_amount])
	core_qi_label.text = "[center][hint=本场可凝聚总量：%d。战斗结束后恢复。]灵枢[/hint]　%s[/center]" % [core_total, "　".join(parts)]
	core_qi_label.tooltip_text = ""


func animate_core_withdrawal(before_qi: Dictionary, after_qi: Dictionary) -> void:
	if core_counter_tween != null and core_counter_tween.is_valid():
		core_counter_tween.kill()
	var working := before_qi.duplicate(true)
	_set_core_qi_display(working)
	var snapshots: Array[Dictionary] = []
	var remaining := 1
	while remaining > 0:
		remaining = 0
		for qi_id: String in ["metal", "wood", "water", "fire", "earth"]:
			if int(working.get(qi_id, 0)) > int(after_qi.get(qi_id, 0)):
				working[qi_id] = int(working.get(qi_id, 0)) - 1
				snapshots.append(working.duplicate(true))
				remaining += 1
	core_counter_tween = create_tween()
	for snapshot: Dictionary in snapshots:
		core_counter_tween.tween_interval(0.055)
		core_counter_tween.tween_callback(_set_core_qi_display.bind(snapshot))
	core_counter_tween.tween_callback(_set_core_qi_display.bind(after_qi.duplicate(true)))


func _render_dantian_arc(sea_qi: Dictionary) -> void:
	# Keep this empty top slot in the container so the spirit core remains
	# geometrically centered; the actual dantian is rendered beside the player.
	qi_label.visible = true
	qi_label.text = ""
	if not is_instance_valid(dantian_overlay):
		dantian_overlay = Control.new()
		dantian_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dantian_overlay.z_index = 30
		dantian_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		player_visual_host.add_child(dantian_overlay)
	for child: Node in dantian_overlay.get_children():
		child.queue_free()
	dantian_icons.clear()
	var order := ["metal", "wood", "water", "fire", "earth"]
	if AudioDirector.get_dantian_display_mode() == "scattered":
		var scattered_index := 0
		for qi_id: String in order:
			dantian_icons[qi_id] = []
			for amount_index: int in int(sea_qi.get(qi_id, 0)):
				var icon := TextureRect.new()
				icon.texture = UIArt.qi(qi_id)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				var column := scattered_index % 3
				var row := scattered_index / 3
				var drift_x := float((scattered_index * 17) % 9) - 4.0
				var drift_y := float((scattered_index * 11) % 7) - 3.0
				icon.position = Vector2(4.0 + column * 33.0 + drift_x, 76.0 + row * 31.0 + drift_y)
				icon.size = Vector2(29, 29)
				icon.mouse_filter = Control.MOUSE_FILTER_PASS
				icon.tooltip_text = "丹田｜%s灵气\n施展对应神通时消耗。" % ATTRIBUTE_NAMES.get(qi_id, qi_id)
				dantian_overlay.add_child(icon)
				(dantian_icons[qi_id] as Array).append(icon)
				scattered_index += 1
		return
	var visual_index := 0
	for qi_id: String in order:
		dantian_icons[qi_id] = []
		var amount := int(sea_qi.get(qi_id, 0))
		if amount <= 0:
			continue
		var holder := Control.new()
		var column := visual_index % 2
		var row := visual_index / 2
		holder.position = Vector2(5.0 + column * 58.0, 78.0 + row * 39.0)
		holder.size = Vector2(54, 34)
		holder.mouse_filter = Control.MOUSE_FILTER_PASS
		holder.tooltip_text = "丹田｜%s灵气 ×%d\n施展对应神通时消耗。" % [ATTRIBUTE_NAMES.get(qi_id, qi_id), amount]
		var icon := TextureRect.new()
		icon.texture = UIArt.qi(qi_id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(0, 2)
		icon.size = Vector2(30, 30)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(icon)
		var count := Label.new()
		count.text = str(amount)
		count.position = Vector2(29, 5)
		count.size = Vector2(25, 24)
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.add_theme_font_size_override("font_size", 17)
		count.add_theme_color_override("font_color", Color("fff0c4"))
		count.add_theme_color_override("font_outline_color", Color("17140f"))
		count.add_theme_constant_override("outline_size", 3)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(count)
		dantian_overlay.add_child(holder)
		# 动画仍按实际数量生成粒子，但静态界面只显示一枚图标与数字。
		for amount_index: int in amount:
			(dantian_icons[qi_id] as Array).append(icon)
		visual_index += 1


func render_enemies(enemies: Array[Dictionary], selected_enemy_id: String, show_attributes: bool) -> void:
	_clear_container(enemy_container)
	var living_visual_ids: Dictionary = {}
	var visible_enemy_count := clampi(enemies.size(), 1, 3)
	var enemy_card_height := responsive_enemy_height
	enemy_scroll.custom_minimum_size.y = float(visible_enemy_count) * enemy_card_height
	for enemy: Dictionary in enemies:
		var visual_id := str(enemy.unit_id)
		living_visual_ids[visual_id] = true
		var visual: UnitVisual = enemy_visuals.get(visual_id)
		if not is_instance_valid(visual):
			visual = UnitVisual.new()
			visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			visual.configure(enemy, false)
			visual.selected.connect(func(unit_id: String) -> void: target_selected.emit(unit_id))
			enemy_visual_host.add_child(visual)
			enemy_visuals[visual_id] = visual
		visual.update_unit(enemy, show_attributes)
		visual.modulate = Color("fff0b5") if str(enemy.unit_id) == selected_enemy_id else Color.WHITE
		var button := Button.new()
		_configure_wrapped_button(button, enemy_card_height)
		var attribute_text := ""
		var primary := str(enemy.get("attributes", {}).get("primary", ""))
		if show_attributes and not primary.is_empty():
			attribute_text = "  属性：%s" % ATTRIBUTE_NAMES.get(primary, primary)
		var selection := "▶ " if enemy.unit_id == selected_enemy_id else ""
		var defeated := "（已击败）" if int(enemy.hp.current) <= 0 else ""
		button.text = "%s%s  HP %d/%d  护盾 %d%s %s\n%s" % [
			selection, enemy.name, enemy.hp.current, enemy.hp.max, enemy.shield,
			attribute_text, defeated, _format_intent(enemy.get("selected_action", {}))
		]
		button.disabled = int(enemy.hp.current) <= 0
		button.icon = _enemy_portrait(str(enemy.get("id", enemy.get("unit_id", ""))))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 68)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_apply_element_card_style(button, primary, enemy.unit_id == selected_enemy_id)
		var old_hp := int(last_enemy_hp.get(str(enemy.unit_id), int(enemy.hp.current)))
		if int(enemy.hp.current) < old_hp:
			_flash_control(button, Color("ef7664"))
			_spawn_float_text("-%d" % (old_hp - int(enemy.hp.current)), Color("f4b36c"), Vector2(0.55, 0.38))
		last_enemy_hp[str(enemy.unit_id)] = int(enemy.hp.current)
		var unit_id := str(enemy.unit_id)
		button.pressed.connect(func() -> void:
			_play_click_feedback(Color("d3ad62"))
			target_selected.emit(unit_id)
		)
		enemy_container.add_child(button)
	for visual_id: String in enemy_visuals.keys():
		if not living_visual_ids.has(visual_id):
			var stale: UnitVisual = enemy_visuals[visual_id]
			if is_instance_valid(stale):
				stale.queue_free()
			enemy_visuals.erase(visual_id)


func render_spells(spells: Array[Dictionary], enabled: bool) -> void:
	_clear_container(spell_container)
	if spells.is_empty():
		_add_empty_label(spell_container, "当前没有可施展神通")
		return
	var available_width := maxf(420.0, size.x - item_panel.custom_minimum_size.x - 82.0)
	var columns := mini(spells.size(), clampi(floori(available_width / 90.0), 5, 10))
	var rows := maxi(1, ceili(float(spells.size()) / float(maxi(1, columns))))
	var max_hand_height := clampf(size.y * 0.28, 150.0, 310.0)
	var card_height := clampf((max_hand_height - float(rows - 1) * 5.0) / float(rows), 112.0, 202.0)
	var width_from_height := card_height * 138.0 / 202.0
	var width_from_row := (available_width + float(columns - 1) * 8.0) / float(maxi(1, columns))
	var card_width := clampf(minf(width_from_height, width_from_row), 76.0, 138.0)
	card_height = card_width * 202.0 / 138.0
	spell_container.custom_minimum_size.y = card_height * float(rows) + float(rows - 1) * 5.0
	for spell: Dictionary in spells:
		var is_castable := bool(spell.get("ui_castable", true))
		var card := SpellCard.new()
		card.configure(spell, enabled and is_castable, card_width, card_height)
		var spell_id := str(spell.get("id", ""))
		card.chosen.connect(func(_id: String) -> void:
			_play_spell_then_commit(spell, card, spell_id)
		)
		spell_container.add_child(card)


func _play_spell_then_commit(spell: Dictionary, card: Control, spell_id: String) -> void:
	if spell_input_locked:
		return
	spell_input_locked = true
	_animate_qi_cast(spell, card)
	if is_instance_valid(player_visual):
		player_visual.play_attack(1.0)
	# Resolve damage after the visible strike reaches its target. Previously the
	# victory state replaced the battlefield before the final blow was shown.
	await get_tree().create_timer(0.34).timeout
	if is_inside_tree():
		spell_selected.emit(spell_id)
	spell_input_locked = false


func animate_enemy_action(unit_id: String, action: Dictionary = {}) -> void:
	var visual: UnitVisual = enemy_visuals.get(unit_id)
	if is_instance_valid(visual):
		var guarding := false
		for effect: Variant in action.get("effects", []):
			if effect is Dictionary and str(effect.get("type", "")) in ["shield", "buff", "heal"]:
				guarding = true
				break
		if guarding:
			visual.play_guard()
		else:
			visual.play_attack(-1.0)


func animate_guard(unit_id: String) -> void:
	var visual: UnitVisual = player_visual if unit_id == "player" else enemy_visuals.get(unit_id)
	if is_instance_valid(visual):
		visual.play_guard()


func _render_relics(relics: Array, trigger_counts: Dictionary) -> void:
	var signature := JSON.stringify([relics.map(func(relic: Dictionary) -> String: return str(relic.get("id", ""))), trigger_counts])
	if signature == relic_render_signature:
		return
	relic_render_signature = signature
	_clear_container(relic_container)
	relic_buttons.clear()
	for relic: Dictionary in relics:
		var button := Button.new()
		button.text = ""
		button.icon = UIArt.relic(str(relic.get("id", "")))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 48)
		button.custom_minimum_size = Vector2(54, 50)
		button.flat = true
		button.mouse_default_cursor_shape = Control.CURSOR_HELP
		var relic_id := str(relic.get("id", ""))
		var count := int(trigger_counts.get(relic_id, 0))
		button.tooltip_text = "%s\n%s\n\n%s" % [str(relic.get("name", "法宝")), str(relic.get("description", "")), _relic_trigger_state(relic, count)]
		relic_container.add_child(button)
		relic_buttons[relic_id] = button


func _apply_responsive_layout() -> void:
	var compact := size.y < 650.0
	responsive_spell_height = 50.0 if compact else 85.0
	responsive_enemy_height = 54.0 if compact else 76.0
	# 神通区域高度由 render_spells 根据卡牌数量与视口计算，避免固定高度反向撑开画布。
	if is_instance_valid(enemy_scroll):
		enemy_scroll.custom_minimum_size.y = responsive_enemy_height


func _relic_trigger_state(relic: Dictionary, count: int) -> String:
	for effect: Variant in relic.get("effects", []):
		if not effect is Dictionary:
			continue
		if effect.get("type", "") == "trigger_effect":
			var trigger_name: String = str({"battle_start":"入战时", "turn_start":"回合开始", "after_spell":"施展神通后"}.get(str(effect.get("trigger", "")), "条件达成时"))
			return "%s触发 · 本场已响应%d次" % [trigger_name, count]
	return "持续生效"


func show_relic_trigger(relic_ids: Array[String]) -> void:
	for relic_id: String in relic_ids:
		var button: Button = relic_buttons.get(relic_id)
		if not is_instance_valid(button):
			continue
		_flash_control(button, Color("f0c86b"))
		_spawn_float_text("法宝响应", Color("f0c86b"), Vector2(0.72, 0.18))


func render_items(inventory: Dictionary, item_definitions: Dictionary, enabled: bool) -> void:
	_clear_container(item_container)
	var found := false
	for item_id: String in inventory:
		var item: Dictionary = item_definitions.get(item_id, {})
		if item.get("type", "") != "consumable" or int(inventory[item_id]) <= 0:
			continue
		found = true
		var button := Button.new()
		_configure_wrapped_button(button, 40.0)
		var combat_use: Dictionary = item.get("combat_use", {})
		var effects: Array = combat_use.get("effects", [])
		_apply_element_card_style(button, _get_action_attribute(combat_use))
		button.icon = _item_icon(item_id, item)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 34)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(170, 52)
		button.text = "%s  ×%d" % [str(item.get("name", item_id)), int(inventory[item_id])]
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.tooltip_text = "%s\n%s\n%s" % [item.get("name", item_id), item.get("description", ""), _format_effects(effects)]
		button.disabled = not enabled
		button.pressed.connect(func() -> void:
			_play_click_feedback(Color("d3ad62"))
			item_selected.emit(item_id)
		)
		item_container.add_child(button)
	if not found:
		item_panel.visible = false
	else:
		item_panel.visible = true


func _item_icon(item_id: String, item: Dictionary) -> Texture2D:
	if str(item.get("type", "")) == "material":
		return UIArt.reward(10)
	if "pill" in item_id or "dan" in item_id:
		return UIArt.reward(9)
	return UIArt.reward(8)


func set_enemy_action_enabled(enabled: bool) -> void:
	# Preserve the bottom bar's height through the complete turn. Visibility used
	# to collapse this control and hand its space to the arena, enlarging units.
	enemy_action_button.visible = true
	enemy_action_button.disabled = not enabled
	enemy_action_button.modulate = Color.WHITE if enabled else Color(0.65, 0.65, 0.65, 0.62)
	enemy_action_button.text = "结束行动" if enabled else "敌人行动中"


func set_continue_state(visible: bool, label: String) -> void:
	continue_button.visible = visible
	continue_button.disabled = not visible
	continue_button.text = label


func render_reward_group(group: Dictionary, reward_manager: RewardManager) -> void:
	_clear_floating_text()
	battle_content.visible = false
	reward_screen.visible = true
	reward_panel.visible = true
	if not victory_guard_shown:
		victory_guard_shown = true
		_show_reward_input_guard()
	_clear_container(reward_container)
	reward_skip_is_replacement = false
	reward_skip_button.text = "跳过"
	reward_skip_button.visible = false
	var options: Array = group.get("options", [])
	reward_help_label.text = _build_reward_help(group, options)
	if group.get("mode", "choice") == "fixed":
		reward_title.text = "固定战斗奖励"
		for reward: Variant in options:
			if reward is Dictionary:
				var description := reward_manager.describe_reward(reward)
				var label := Label.new()
				label.text = "• %s\n  %s" % [description.title, description.description]
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				label.custom_minimum_size = Vector2(0.0, 44.0)
				reward_container.add_child(label)
		var claim_button := Button.new()
		_configure_wrapped_button(claim_button, 44.0)
		claim_button.custom_minimum_size.x = 230.0
		claim_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		claim_button.text = "领取全部奖励"
		if not options.is_empty() and options[0] is Dictionary:
			claim_button.set_meta("sfx_kind", _reward_sound(options[0]))
		claim_button.pressed.connect(func() -> void:
			_play_click_feedback(Color("d3ad62"))
			reward_selected.emit(-1)
		)
		reward_container.add_child(claim_button)
	else:
		reward_title.text = str(group.get("title", "选择一项奖励"))
		for index: int in options.size():
			var reward: Dictionary = options[index]
			var description := reward_manager.describe_reward(reward)
			var card := RewardChoiceCard.new()
			var reward_attribute := _get_reward_attribute(reward, reward_manager)
			card.configure(description.title, description.description, _reward_icon(reward, reward_manager), ATTRIBUTE_COLORS.get(reward_attribute, Color("d3ad62")))
			card.set_reward_sound(_reward_sound(reward))
			card.chosen.connect(func() -> void:
				_play_click_feedback(Color("d3ad62"))
				reward_selected.emit(index)
			)
			reward_container.add_child(card)
		if bool(group.get("skippable", false)):
			reward_skip_button.visible = true


func _reward_icon(reward: Dictionary, reward_manager: RewardManager) -> Texture2D:
	match str(reward.get("type", "")):
		"relic": return UIArt.relic(str(reward.get("relic_id", "")))
		"spirit_stones": return UIArt.combat(9)
		"consumable", "item": return UIArt.reward(8)
		"material": return UIArt.reward(10)
		"add_core_qi", "core_qi": return UIArt.qi(str(reward.get("qi", "any_qi")))
		"learn_spell":
			var spell: Dictionary = reward_manager.spells.get(str(reward.get("spell_id", "")), {})
			for tag: Variant in spell.get("tags", []):
				var index := ["metal", "wood", "water", "fire", "earth"].find(str(tag))
				if index >= 0: return UIArt.reward(index)
			return UIArt.reward(5)
		"learn_method":
			var method: Dictionary = reward_manager.methods.get(str(reward.get("method_id", "")), {})
			for qi_id: String in ["metal", "wood", "water", "fire", "earth"]:
				if method.get("element_affinity", {}).has(qi_id): return UIArt.reward(["metal", "wood", "water", "fire", "earth"].find(qi_id))
			return UIArt.reward(6)
		_: return UIArt.combat(5)


func _reward_sound(reward: Dictionary) -> String:
	return str({
		"relic":"reward_relic", "spirit_stones":"reward_stone",
		"learn_spell":"reward_spell", "learn_reward":"reward_spell",
		"learn_method":"reward_method", "add_core_qi":"reward_qi", "core_qi":"reward_qi",
		"material":"reward_material", "consumable":"reward_item", "item":"reward_item"
	}.get(str(reward.get("type", "")), "reward"))


func clear_rewards() -> void:
	reward_panel.visible = false
	reward_screen.visible = false
	battle_content.visible = true
	_clear_container(reward_container)
	reward_skip_is_replacement = false
	reward_skip_button.visible = false


func render_spell_replacement(new_spell_reward: Dictionary, reward_manager: RewardManager) -> void:
	battle_content.visible = false
	reward_screen.visible = true
	reward_panel.visible = true
	_clear_container(reward_container)
	# 固定出口，不再把“暂不学习”埋在长列表底部。
	reward_skip_is_replacement = true
	reward_skip_button.text = "暂不学习"
	reward_skip_button.visible = true
	var new_spell_id := str(new_spell_reward.get("spell_id", new_spell_reward.get("ability_id", "")))
	var new_spell: Dictionary = reward_manager.spells.get(new_spell_id, {})
	var new_cost := int(new_spell.get("sense_cost", 1))
	var used := RunState.get_spiritual_sense_used(reward_manager.spells)
	var capacity := RunState.get_spiritual_sense_capacity()
	var required_free := maxi(1, used + new_cost - capacity)
	reward_title.text = "神识已满"
	reward_help_label.text = "欲纳入「%s」（%d点），需腾出至少%d点神识。" % [new_spell.get("name", new_spell_id), new_cost, required_free]
	for spell: Dictionary in reward_manager.get_learned_spell_definitions():
		if not bool(spell.get("replaceable", true)):
			continue
		var sense_cost := int(spell.get("sense_cost", 1))
		if sense_cost < required_free:
			continue
		var button := RewardChoiceCard.new()
		button.configure(str(spell.get("name", spell.get("id", ""))), "释放 %d 点神识\n%s" % [sense_cost, str(spell.get("description", ""))], UIArt.reward(5), ATTRIBUTE_COLORS.get(_get_action_attribute(spell), Color("d3ad62")))
		var spell_id := str(spell.get("id", ""))
		button.chosen.connect(func() -> void: spell_replacement_selected.emit(spell_id))
		reward_container.add_child(button)


func _show_reward_input_guard() -> void:
	if reward_screen.has_node("RewardInputGuard"):
		return
	var guard := ColorRect.new()
	guard.name = "RewardInputGuard"
	guard.color = Color(0.015, 0.025, 0.022, 0.84)
	guard.mouse_filter = Control.MOUSE_FILTER_STOP
	guard.z_index = 100
	reward_screen.add_child(guard)
	guard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	label.text = "战斗胜利"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 38)
	label.add_theme_color_override("font_color", Color("e8c875"))
	guard.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tween := create_tween()
	tween.tween_interval(0.55)
	tween.tween_property(guard, "modulate:a", 0.0, 0.28)
	tween.tween_callback(_safe_queue_free.bind(guard))


func show_message(message: String) -> void:
	message_label.text = message
	message_label.tooltip_text = message
	message_label.modulate = Color(1.0, 0.87, 0.55, 0.35)
	var tween := create_tween()
	tween.tween_property(message_label, "modulate", Color.WHITE, 0.22)


func _format_intent(action: Dictionary) -> String:
	if action.is_empty():
		return "下一行动：无"
	var description := str(action.get("description", ""))
	return "下一行动：%s%s" % [action.get("name", "行动"), " · %s" % description if not description.is_empty() else ""]


func _format_cost(cost: Dictionary) -> String:
	if bool(cost.get("all_sea_qi", false)):
		return "当前丹田全部灵气（至少%d点）" % int(cost.get("minimum", 1))
	var parts: Array[String] = []
	for qi_id: Variant in cost:
		if str(qi_id) in ["all_sea_qi", "minimum"]:
			continue
		if str(qi_id) == "any_qi":
			parts.append("任意灵气 ×%d" % int(cost[qi_id]))
		else:
			parts.append("%s灵气 ×%d" % [ATTRIBUTE_NAMES.get(str(qi_id), str(qi_id)), int(cost[qi_id])])
	return "、".join(parts) if not parts.is_empty() else "无"


func _format_cost_compact(cost: Dictionary) -> String:
	if bool(cost.get("all_sea_qi", false)):
		return "全丹田 ≥%d" % int(cost.get("minimum", 1))
	var parts: Array[String] = []
	for qi_id: Variant in cost:
		if str(qi_id) in ["all_sea_qi", "minimum"]:
			continue
		if str(qi_id) == "any_qi":
			parts.append("任意×%d" % int(cost[qi_id]))
		else:
			parts.append("%s×%d" % [ATTRIBUTE_NAMES.get(str(qi_id), str(qi_id)), int(cost[qi_id])])
	return " ".join(parts) if not parts.is_empty() else "无消耗"


func _format_attributes(effects: Array) -> String:
	var attributes: Array[String] = []
	for effect: Variant in effects:
		if not effect is Dictionary:
			continue
		var attribute := str(effect.get("attribute", ""))
		if not attribute.is_empty():
			var display_name := str(ATTRIBUTE_NAMES.get(attribute, attribute))
			if not attributes.has(display_name):
				attributes.append(display_name)
	return "、".join(attributes) if not attributes.is_empty() else "无属性"


func _format_effects(effects: Array) -> String:
	var summaries: Array[String] = []
	for effect: Variant in effects:
		if not effect is Dictionary:
			continue
		var value := int(effect.get("value", 0))
		var attribute := str(effect.get("attribute", ""))
		var attribute_text := "%s属性" % ATTRIBUTE_NAMES.get(attribute, attribute) if not attribute.is_empty() else ""
		match str(effect.get("type", "")):
			"damage":
				var scaling: Dictionary = effect.get("scaling", {})
				var scaling_text := ""
				if scaling.get("source", "") == "spent_qi_total":
					scaling_text = "，每消耗1点灵气额外造成%d点伤害" % int(scaling.get("per_point", 0))
				elif scaling.get("source", "") == "status":
					var status_id := str(scaling.get("status", ""))
					scaling_text = "，每层%s额外造成%d点伤害" % [STATUS_NAMES.get(status_id, status_id), int(scaling.get("per_point", 0))]
				summaries.append("造成%d点%s伤害%s" % [value, attribute_text, scaling_text])
			"shield":
				summaries.append("获得%d点护盾" % value)
			"heal":
				summaries.append("恢复%d点生命" % value)
			"add_sea_qi":
				var qi_id := str(effect.get("qi", ""))
				summaries.append("获得%s灵气 ×%d" % [ATTRIBUTE_NAMES.get(qi_id, qi_id), value])
			"add_status":
				var status_id := str(effect.get("status", ""))
				summaries.append("获得%s ×%d" % [STATUS_NAMES.get(status_id, "状态"), value])
			"consume_status":
				var status_id := str(effect.get("status", ""))
				var amount_text := "全部" if bool(effect.get("all", false)) else "×%d" % value
				summaries.append("消耗%s %s" % [STATUS_NAMES.get(status_id, "状态"), amount_text])
			"buff":
				var status_id := str(effect.get("status", ""))
				summaries.append("获得%s（%d%%）" % [STATUS_NAMES.get(status_id, "属性强化"), value])
			_:
				summaries.append("特殊效果")
	return "；".join(summaries) if not summaries.is_empty() else "无"


func _format_short_effects(effects: Array) -> String:
	var summaries: Array[String] = []
	for effect: Variant in effects:
		if not effect is Dictionary:
			continue
		var value := int(effect.get("value", 0))
		var attribute := str(effect.get("attribute", ""))
		match str(effect.get("type", "")):
			"damage": summaries.append("%d点%s伤害" % [value, ATTRIBUTE_NAMES.get(attribute, "无属性")])
			"shield": summaries.append("获得%d点护盾" % value)
			"heal": summaries.append("恢复%d点生命" % value)
			"add_sea_qi": summaries.append("凝聚%s灵气×%d" % [ATTRIBUTE_NAMES.get(str(effect.get("qi", "")), ""), value])
			"add_status": summaries.append("获得%s×%d" % [STATUS_NAMES.get(str(effect.get("status", "")), "状态"), value])
			"consume_status": summaries.append("消耗%s" % STATUS_NAMES.get(str(effect.get("status", "")), "状态"))
			"buff": summaries.append("获得%s" % STATUS_NAMES.get(str(effect.get("status", "")), "强化"))
			_: summaries.append("特殊效果")
		if summaries.size() >= 2:
			break
	return "；".join(summaries) if not summaries.is_empty() else "无即时效果"


func _format_keyword_help(effects: Array) -> String:
	var keywords: Dictionary = {}
	for effect: Variant in effects:
		if not effect is Dictionary:
			continue
		var status_id := str(effect.get("status", effect.get("scaling", {}).get("status", "")))
		if not status_id.is_empty():
			keywords[status_id] = true
	var explanations := {
		"flame_seed": "火种：被炎爆类神通消耗以追加伤害。",
		"terrain": "地势：由守御积累，可强化山崩类神通。",
		"sharpness": "锋锐：锐金铺垫资源，可被斩杀神通消耗。",
		"vitality": "生机：青木成长资源，可转化为治疗和护盾。",
		"flow": "回流：清水循环资源，代表连续施法的势能。"
	}
	var lines: Array[String] = []
	for keyword: String in keywords:
		if explanations.has(keyword):
			lines.append(str(explanations[keyword]))
	return "\n\n" + "\n".join(lines) if not lines.is_empty() else ""


func _clear_container(container: Container) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _add_empty_label(container: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(0.0, 24.0)
	container.add_child(label)


func _configure_wrapped_button(button: Button, minimum_height: float) -> void:
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, minimum_height)


func _build_reward_help(group: Dictionary, options: Array) -> String:
	var explanation := "灵光浮现，择一收入行囊。"
	var option_types: Dictionary = {}
	for option: Variant in options:
		if option is Dictionary:
			option_types[str(option.get("type", ""))] = true
	if option_types.size() > 1:
		explanation = "战利品已收入行囊，眼前灵光可择一带走。"
	elif not options.is_empty() and options[0] is Dictionary:
		match str(options[0].get("type", "")):
			"learn_method":
				explanation = "功法玉简悬于眼前。"
			"learn_spell", "learn_reward":
				explanation = "玉简悬光，择一参悟，亦可拂袖离去。"
			"add_core_qi":
				explanation = "择一缕五行灵机，纳入灵枢。"
			"relic":
				explanation = "宝光流转，择一件随身温养。"
	return explanation


func _play_click_feedback(color: Color) -> void:
	if feedback_tween != null and feedback_tween.is_valid():
		feedback_tween.kill()
	action_flash.visible = true
	action_flash.color = Color(color.r, color.g, color.b, 0.1)
	feedback_tween = create_tween()
	feedback_tween.tween_property(action_flash, "color:a", 0.0, 0.18)
	feedback_tween.tween_callback(func() -> void: action_flash.visible = false)


func _animate_qi_gather(previous_qi: Dictionary, sea_qi: Dictionary) -> void:
	var shown := 0
	for qi_id: String in ["metal", "wood", "water", "fire", "earth"]:
		var origin := _core_qi_origin(qi_id)
		var old_amount := int(previous_qi.get(qi_id, 0))
		var new_amount := int(sea_qi.get(qi_id, 0))
		var icons: Array = dantian_icons.get(qi_id, [])
		for index: int in range(old_amount, mini(new_amount, icons.size())):
			var resting_icon := icons[index] as TextureRect
			var compact_display := AudioDirector.get_dantian_display_mode() == "compact"
			if not compact_display:
				resting_icon.modulate.a = 0.0
			var mote := TextureRect.new()
			mote.texture = resting_icon.texture
			mote.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mote.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mote.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mote.z_index = 90
			mote.size = Vector2(29, 29)
			mote.position = origin - mote.size * 0.5
			dantian_overlay.add_child(mote)
			# Both mote and resting icon now share dantian_overlay as their parent.
			# The destination is therefore the exact final icon position, with no
			# viewport/fullscreen conversion involved.
			var destination := resting_icon.position + resting_icon.size * 0.5 - mote.size * 0.5
			var delay := shown * 0.055
			var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(mote, "position", destination, 0.52).set_delay(delay)
			tween.parallel().tween_property(mote, "scale", Vector2(1.04, 1.04), 0.28).set_delay(delay)
			tween.tween_callback(func() -> void:
				if is_instance_valid(resting_icon) and not compact_display: resting_icon.modulate.a = 1.0
				_safe_queue_free(mote)
			)
			shown += 1


func _core_qi_origin(qi_id: String) -> Vector2:
	var order := ["metal", "wood", "water", "fire", "earth"]
	var index := order.find(qi_id)
	# Each particle departs from its own five-element entry, rather than from the
	# label's upper-left corner or from one shared arbitrary point.
	var group_spacing := minf(54.0, core_qi_label.size.x * 0.115)
	var label_point := core_qi_label.size * 0.5 + Vector2((float(index) - 2.0) * group_spacing + 28.0, 0.0)
	var global_origin := core_qi_label.get_global_transform() * label_point
	return dantian_overlay.get_global_transform().affine_inverse() * global_origin


func _control_center_in_battle(control: Control) -> Vector2:
	# Keep both sides of the conversion in the same global-transform space.
	# Mixing get_global_rect() with a canvas transform double-applied fullscreen
	# stretch and displaced the destination toward the lower-left corner.
	var global_center := control.get_global_transform() * (control.size * 0.5)
	return get_global_transform().affine_inverse() * global_center


func animate_qi_dissipation(retained_qi: Dictionary) -> void:
	# The model has already resolved retention, while the old dantian icons are
	# still on screen. Dissipate only the excess icons before the next turn draws
	# newly gathered qi, keeping the two resource events visually distinct.
	var dissipated := 0
	for qi_id: String in ["metal", "wood", "water", "fire", "earth"]:
		var icons: Array = dantian_icons.get(qi_id, [])
		var retained_count := int(retained_qi.get(qi_id, 0))
		for index: int in range(retained_count, icons.size()):
			var source := icons[index] as TextureRect
			if not is_instance_valid(source):
				continue
			var animated_source: TextureRect = source
			if AudioDirector.get_dantian_display_mode() == "compact":
				animated_source = TextureRect.new()
				animated_source.texture = source.texture
				animated_source.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				animated_source.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				animated_source.size = source.size
				var source_center := dantian_overlay.get_global_transform().affine_inverse() * (source.get_global_transform() * (source.size * 0.5))
				animated_source.position = source_center - animated_source.size * 0.5
				animated_source.mouse_filter = Control.MOUSE_FILTER_IGNORE
				animated_source.z_index = 90
				dantian_overlay.add_child(animated_source)
			var direction := Vector2(-1.15 + float(dissipated % 5) * 0.58, -1.0 + float(dissipated % 2) * 0.22).normalized()
			var delay := float(dissipated) * 0.05
			var tween := create_tween().set_parallel(true)
			tween.tween_property(animated_source, "position", animated_source.position + direction * (78.0 + float(dissipated % 3) * 14.0), 0.68).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(animated_source, "rotation", (-0.7 + float(dissipated % 4) * 0.42), 0.68).set_delay(delay)
			tween.tween_property(animated_source, "scale", Vector2(1.06, 1.06), 0.16).set_delay(delay)
			tween.tween_property(animated_source, "scale", Vector2(0.25, 0.25), 0.42).set_delay(delay + 0.22)
			tween.tween_property(animated_source, "modulate:a", 0.0, 0.38).set_delay(delay + 0.25)
			if animated_source != source:
				tween.chain().tween_callback(_safe_queue_free.bind(animated_source))
			dissipated += 1
	if dissipated > 0:
		AudioDirector.play_sfx("qi")
		_spawn_float_text("灵气散逸", Color("b7d8cf"), Vector2(0.16, 0.42))
		await get_tree().create_timer(0.76 + minf(0.45, float(dissipated) * 0.05)).timeout


func _animate_qi_cast(spell: Dictionary, card: Control) -> void:
	var sources: Array[TextureRect] = []
	var cost: Dictionary = spell.get("cost", {})
	if bool(cost.get("all_sea_qi", false)):
		for qi_id: String in ["metal", "wood", "water", "fire", "earth"]:
			for icon: TextureRect in dantian_icons.get(qi_id, []): sources.append(icon)
	else:
		for qi_id: Variant in cost:
			if str(qi_id) in ["minimum", "all_sea_qi"]: continue
			var available: Array = dantian_icons.get(str(qi_id), [])
			for index: int in mini(int(cost[qi_id]), available.size()): sources.append(available[index])
	var destination := _control_center_in_battle(card)
	for index: int in sources.size():
		var source := sources[index]
		var mote := TextureRect.new()
		mote.texture = source.texture
		mote.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mote.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mote.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mote.z_index = 95
		add_child(mote)
		mote.custom_minimum_size = Vector2.ZERO
		mote.size = Vector2(30, 30)
		mote.position = _control_center_in_battle(source) - mote.size * 0.5
		var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.set_parallel(true)
		tween.tween_property(mote, "position", destination - mote.size * 0.5, 0.32).set_delay(index * 0.035)
		tween.tween_property(mote, "scale", Vector2(1.12, 1.12), 0.22)
		tween.tween_property(mote, "modulate:a", 0.0, 0.12).set_delay(0.24 + index * 0.04)
		tween.chain().tween_callback(_safe_queue_free.bind(mote))
	_spawn_spell_impact(_get_action_attribute(spell))


func _spawn_spell_impact(attribute: String) -> void:
	var color: Color = ATTRIBUTE_COLORS.get(attribute, Color("d9c88e"))
	var start := Vector2(size.x * 0.31, size.y * 0.40)
	var finish := Vector2(size.x * 0.70, size.y * 0.34)
	var streak := Line2D.new()
	streak.points = PackedVector2Array([start, finish])
	streak.width = 10.0
	streak.default_color = Color(color, 0.9)
	streak.z_index = 92
	add_child(streak)
	var streak_tween := create_tween().set_parallel(true)
	streak_tween.tween_property(streak, "width", 2.0, 0.22)
	streak_tween.tween_property(streak, "modulate:a", 0.0, 0.25)
	streak_tween.chain().tween_callback(_safe_queue_free.bind(streak))
	for index: int in 8:
		var spark := ColorRect.new()
		spark.color = color.lightened(float(index % 3) * 0.12)
		spark.size = Vector2(7, 7)
		spark.position = finish - spark.size * 0.5
		spark.rotation = float(index) * TAU / 8.0
		spark.pivot_offset = spark.size * 0.5
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spark.z_index = 93
		add_child(spark)
		var direction := Vector2.RIGHT.rotated(float(index) * TAU / 8.0)
		var spark_tween := create_tween().set_parallel(true)
		spark_tween.tween_property(spark, "position", spark.position + direction * 54.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		spark_tween.tween_property(spark, "modulate:a", 0.0, 0.3)
		spark_tween.tween_property(spark, "scale", Vector2(0.2, 0.2), 0.3)
		spark_tween.chain().tween_callback(_safe_queue_free.bind(spark))


func _animate_card_press(button: Button, color: Color, callback: Callable) -> void:
	_play_click_feedback(color)
	button.pivot_offset = button.size * 0.5
	button.disabled = true
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(1.04, 1.04), 0.07)
	tween.tween_property(button, "scale", Vector2.ONE, 0.08)
	tween.tween_callback(callback)


func _spawn_float_text(text: String, color: Color, anchor: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.add_theme_font_size_override("font_size", 26)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = size * anchor
	add_child(label)
	floating_labels.append(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 42.0, 0.55)
	tween.tween_property(label, "modulate:a", 0.0, 0.55)
	tween.chain().tween_callback(func() -> void:
		floating_labels.erase(label)
		if is_instance_valid(label):
			label.queue_free()
	)


func _clear_floating_text() -> void:
	for label: Label in floating_labels:
		if is_instance_valid(label):
			label.queue_free()
	floating_labels.clear()


func _safe_queue_free(node: Node) -> void:
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		node.queue_free()


func _flash_control(control: Control, color: Color) -> void:
	control.modulate = color
	var tween := create_tween()
	tween.tween_property(control, "modulate", Color.WHITE, 0.28)


func _get_action_attribute(action: Dictionary) -> String:
	for effect: Variant in action.get("effects", []):
		if effect is Dictionary and not str(effect.get("attribute", "")).is_empty():
			return str(effect.get("attribute", ""))
	for tag: Variant in action.get("tags", []):
		if ATTRIBUTE_COLORS.has(str(tag)):
			return str(tag)
	for qi_id: Variant in action.get("cost", {}):
		if ATTRIBUTE_COLORS.has(str(qi_id)):
			return str(qi_id)
	return ""


func _get_reward_attribute(reward: Dictionary, reward_manager: RewardManager) -> String:
	match str(reward.get("type", "")):
		"add_core_qi":
			return str(reward.get("qi", ""))
		"learn_spell", "learn_reward":
			return _get_action_attribute(reward_manager.spells.get(str(reward.get("spell_id", "")), {}))
		"relic":
			var relic: Dictionary = reward_manager.relics.get(str(reward.get("relic_id", "")), {})
			for tag: Variant in relic.get("tags", []):
				if ATTRIBUTE_COLORS.has(str(tag)):
					return str(tag)
	return ""


func _apply_element_card_style(button: Button, attribute: String, selected: bool = false, use_card_frame: bool = false) -> void:
	var accent: Color = ATTRIBUTE_COLORS.get(attribute, Color("d3ad62"))
	button.add_theme_color_override("font_color", accent.lightened(0.35) if selected else Color("f2ead0"))
	button.add_theme_color_override("font_hover_color", accent.lightened(0.45))


func _enemy_portrait(enemy_id: String) -> Texture2D:
	var human_indices := {"training_puppet":0, "bandit":1, "seal_bearing_enforcer":2, "black_tide_chief":3}
	var beast_indices := {"steel_fang_wolf":0, "dusk_beak_crow":0, "fire_tail_wolf":1, "ember_dust_moth":1, "rock_shell_tortoise":2, "iron_bark_guardian":2, "blood_root_demon":3, "withered_vine_spirit":3}
	var atlas_texture: Texture2D = null
	var index := -1
	if human_indices.has(enemy_id):
		atlas_texture = CULTIVATOR_ATLAS
		index = int(human_indices[enemy_id])
	elif beast_indices.has(enemy_id):
		atlas_texture = BEAST_ATLAS
		index = int(beast_indices[enemy_id])
	if atlas_texture == null or index < 0:
		return null
	var region := AtlasTexture.new()
	region.atlas = atlas_texture
	var cell_width := float(atlas_texture.get_width()) / 4.0
	region.region = Rect2(cell_width * index, 0.0, cell_width, minf(cell_width, float(atlas_texture.get_height())))
	return region
