class_name UnitVisual
extends Control

signal selected(unit_id: String)

const HUMAN_ATLAS: Texture2D = preload("res://assets/art/units/human_components-clean-v1.png")
const BEAST_ATLAS: Texture2D = preload("res://assets/art/units/beast_components-clean-v1.png")
const EXPANDED_ATLAS: Texture2D = preload("res://assets/art/units/expanded_units-clean-v1.png")
const SPECIALIST_ATLAS: Texture2D = preload("res://assets/art/units/enemy_specialists-clean-v1.png")

var unit_id := ""
var art_root: Control
var info_label: Label
var hit_area: Button
var hp_bar: ProgressBar
var shield_bar: ProgressBar
var hp_value_label: Label
var shield_value_label: Label
var intent_icon: TextureRect
var intent_value: Label
var intent_name_label: Label
var secondary_intent_icons: Array[TextureRect] = []
var status_row: HBoxContainer
var status_toggle: Button
var status_expanded := false
var base_position := Vector2.ZERO
var action_tween: Tween
var hit_tween: Tween
var guard_tween: Tween


func configure(unit: Dictionary, player_side: bool = false) -> void:
	unit_id = str(unit.get("unit_id", unit.get("id", "player")))
	custom_minimum_size = Vector2(230, 245)
	mouse_filter = Control.MOUSE_FILTER_PASS
	art_root = Control.new()
	art_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_root.offset_bottom = -110.0
	add_child(art_root)
	var recipe := _visual_recipe(str(unit.get("id", unit_id)), player_side)
	for part: Dictionary in recipe.parts:
		_add_part(part)
	info_label = Label.new()
	info_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info_label.offset_top = -108.0
	info_label.offset_bottom = -84.0
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 16)
	info_label.add_theme_color_override("font_color", Color("f4e7bd"))
	add_child(info_label)
	intent_icon = TextureRect.new()
	intent_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	intent_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	intent_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	intent_icon.z_index = 12
	add_child(intent_icon)
	intent_icon.anchor_left = 0.5
	intent_icon.anchor_right = 0.5
	intent_icon.offset_left = 34.0
	intent_icon.offset_top = 13.0
	intent_icon.offset_right = 66.0
	intent_icon.offset_bottom = 45.0
	intent_value = Label.new()
	intent_value.anchor_left = 0.5
	intent_value.anchor_right = 0.5
	intent_value.offset_left = 56.0
	intent_value.offset_top = 30.0
	intent_value.offset_right = 88.0
	intent_value.offset_bottom = 49.0
	intent_value.z_index = 13
	intent_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intent_value.add_theme_font_size_override("font_size", 12)
	intent_value.add_theme_color_override("font_color", Color("f7ddb0"))
	add_child(intent_value)
	intent_name_label = Label.new()
	intent_name_label.position = Vector2(72, 47)
	intent_name_label.size = Vector2(86, 20)
	intent_name_label.z_index = 13
	intent_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intent_name_label.add_theme_font_size_override("font_size", 12)
	intent_name_label.add_theme_color_override("font_color", Color("f4ddb0"))
	intent_name_label.add_theme_color_override("font_shadow_color", Color("11100c"))
	intent_name_label.add_theme_constant_override("shadow_offset_x", 1)
	intent_name_label.add_theme_constant_override("shadow_offset_y", 1)
	intent_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(intent_name_label)
	status_row = HBoxContainer.new()
	# 状态以角色中心为基准固定在立绘下沿。丹田图标位于玩家区域最左侧，
	# 因而无论分辨率或灵气数量如何变化，两者都不会再共享坐标区域。
	status_row.anchor_left = 0.5
	status_row.anchor_right = 0.5
	status_row.anchor_top = 1.0
	status_row.anchor_bottom = 1.0
	status_row.offset_left = -48.0
	status_row.offset_right = 175.0
	# 状态固定在生命/护盾条下方，不再覆盖立绘或左侧丹田灵气。
	status_row.offset_top = -42.0
	status_row.offset_bottom = 0.0
	status_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	status_row.add_theme_constant_override("separation", 7)
	status_row.z_index = 40
	add_child(status_row)
	status_toggle = Button.new()
	status_toggle.flat = true
	status_toggle.anchor_left = 0.5
	status_toggle.anchor_right = 0.5
	status_toggle.anchor_top = 1.0
	status_toggle.anchor_bottom = 1.0
	status_toggle.offset_left = -135.0
	status_toggle.offset_right = -53.0
	status_toggle.offset_top = -42.0
	status_toggle.offset_bottom = 0.0
	status_toggle.icon = UIArt.combat(13)
	status_toggle.expand_icon = true
	status_toggle.add_theme_constant_override("icon_max_width", 34)
	status_toggle.tooltip_text = "战斗状态｜点击展开"
	status_toggle.z_index = 41
	status_toggle.pressed.connect(func() -> void:
		status_expanded = not status_expanded
		status_row.visible = status_expanded
		status_toggle.text = "收起" if status_expanded else "状态 %d" % int(status_toggle.get_meta("status_count", 0))
		status_toggle.tooltip_text = "战斗状态｜点击收起" if status_expanded else "战斗状态｜点击展开"
	)
	add_child(status_toggle)
	hp_bar = _make_bar(Color("a7352e"), -82.0, -64.0)
	shield_bar = _make_bar(Color("4f8aa4"), -62.0, -44.0)
	hp_value_label = _bar_label(hp_bar)
	shield_value_label = _bar_label(shield_bar)
	hit_area = Button.new()
	hit_area.flat = true
	hit_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit_area.pressed.connect(func() -> void: selected.emit(unit_id))
	add_child(hit_area)
	move_child(intent_icon, get_child_count() - 1)
	move_child(intent_value, get_child_count() - 1)
	move_child(intent_name_label, get_child_count() - 1)
	move_child(status_row, get_child_count() - 1)
	move_child(status_toggle, get_child_count() - 1)
	update_unit(unit, false)
	_pulse_idle()


func update_unit(unit: Dictionary, show_attribute: bool) -> void:
	if not is_instance_valid(info_label):
		return
	var attribute := str(unit.get("attributes", {}).get("primary", ""))
	var attribute_text := " · %s" % {"metal":"金", "wood":"木", "water":"水", "fire":"火", "earth":"土"}.get(attribute, attribute) if show_attribute and not attribute.is_empty() else ""
	var hp: Dictionary = unit.get("hp", {})
	var action: Dictionary = unit.get("selected_action", {})
	var intent := str(action.get("name", ""))
	info_label.text = "%s%s" % [str(unit.get("name", "修士")), attribute_text]
	var intent_types := _intent_types(action)
	intent_icon.visible = not intent_types.is_empty()
	var intent_type := "composite" if intent_types.size() > 1 else intent_types[0] if not intent_types.is_empty() else "unknown"
	intent_icon.texture = UIArt.intent(intent_type)
	var intent_name := str({"attack":"攻击", "shield":"防御", "buff":"强化", "heal":"恢复", "item":"使用物品", "charge":"蓄势", "debuff":"削弱", "composite":"复合行动"}.get(intent_type, "未知行动"))
	intent_icon.tooltip_text = "意图：%s\n%s\n%s" % [intent_name, intent, str(action.get("description", ""))]
	intent_name_label.visible = false
	intent_name_label.text = intent_name
	intent_value.visible = intent_icon.visible
	intent_value.text = _intent_value(action)
	var secondary_types: Array[String] = []
	if intent_types.size() <= 1:
		secondary_types = intent_types
	_render_secondary_intents(secondary_types, action)
	_render_statuses(unit.get("statuses", {}))
	hp_bar.max_value = maxf(1.0, float(hp.get("max", 1)))
	hp_bar.value = float(hp.get("current", 0))
	hp_value_label.text = "%d / %d" % [int(hp.get("current", 0)), int(hp.get("max", 0))]
	hp_bar.tooltip_text = "生命 %d/%d" % [int(hp.get("current", 0)), int(hp.get("max", 0))]
	var shield := int(unit.get("shield", 0))
	shield_bar.max_value = maxf(10.0, float(shield))
	shield_bar.value = shield
	shield_bar.visible = shield > 0
	shield_value_label.text = "护盾 %d" % shield
	shield_bar.tooltip_text = "护盾 %d" % shield


func _intent_type(action: Dictionary) -> String:
	var types := _intent_types(action)
	return types[0] if not types.is_empty() else "unknown"


func _intent_types(action: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if str(action.get("source_type", "")) == "item" or bool(action.get("consume_item", false)):
		result.append("item")
	for effect: Variant in action.get("effects", []):
		if not effect is Dictionary:
			continue
		var type_id := ""
		match str(effect.get("type", "")):
			"heal": type_id = "heal"
			"shield": type_id = "shield"
			"buff": type_id = "buff"
			"add_status": type_id = "charge"
			"damage": type_id = "attack"
		if not type_id.is_empty() and not result.has(type_id):
			result.append(type_id)
	return result


func _render_secondary_intents(types: Array[String], action: Dictionary) -> void:
	for icon: TextureRect in secondary_intent_icons:
		icon.queue_free()
	secondary_intent_icons.clear()
	var visible_count := mini(3, types.size())
	intent_icon.offset_left = 34.0
	intent_icon.offset_right = 66.0
	intent_value.offset_left = 56.0
	intent_value.offset_right = 88.0
	for index: int in range(1, visible_count):
		var type_id := types[index]
		var icon := TextureRect.new()
		icon.texture = UIArt.intent(type_id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(intent_icon.position.x + index * 50.0, 4.0)
		icon.size = Vector2(46, 46)
		icon.z_index = 12
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		icon.tooltip_text = "%s\n%s" % [_intent_display_name(type_id), str(action.get("description", ""))]
		add_child(icon)
		secondary_intent_icons.append(icon)


func _intent_display_name(type_id: String) -> String:
	return str({"attack":"攻击", "shield":"防御", "buff":"强化", "heal":"恢复", "item":"使用物品", "charge":"蓄势", "debuff":"削弱"}.get(type_id, "行动"))


func _render_statuses(statuses: Dictionary) -> void:
	for child: Node in status_row.get_children():
		child.queue_free()
	status_toggle.visible = not statuses.is_empty()
	status_toggle.set_meta("status_count", statuses.size())
	status_toggle.text = "收起" if status_expanded else "状态 %d" % statuses.size()
	status_row.visible = status_expanded and not statuses.is_empty()
	var summary: Array[String] = []
	for status_id: String in statuses.keys().slice(0, 4):
		var raw: Variant = statuses[status_id]
		var value := int(raw.get("value", 0)) if raw is Dictionary else int(raw)
		var duration := int(raw.get("duration", 0)) if raw is Dictionary else 0
		summary.append("%s ×%d%s" % [_status_name(status_id), value, "（%d回合）" % duration if duration > 0 else ""])
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(44, 44)
		var button := Button.new()
		button.flat = true
		button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.icon = _status_icon(status_id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 40)
		button.tooltip_text = "战斗状态｜%s\n%s%s" % [_status_name(status_id), _status_description(status_id), "\n剩余 %d 回合" % duration if duration > 0 else ""]
		holder.add_child(button)
		var count := Label.new()
		count.text = str(value)
		count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count.offset_left = -21.0
		count.offset_top = -21.0
		count.offset_right = 1.0
		count.offset_bottom = 1.0
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.add_theme_font_size_override("font_size", 16)
		count.add_theme_color_override("font_color", Color("fff2c5"))
		count.add_theme_color_override("font_outline_color", Color("11100c"))
		count.add_theme_constant_override("outline_size", 3)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(count)
		status_row.add_child(holder)
	status_toggle.tooltip_text = "战斗状态｜点击%s\n%s" % ["收起" if status_expanded else "展开", "\n".join(summary)] if not summary.is_empty() else ""


func _status_icon(status_id: String) -> Texture2D:
	match status_id:
		"flame_seed": return UIArt.qi("fire")
		"attack_up": return UIArt.intent("buff")
		"defense_up": return UIArt.intent("shield")
		_: return UIArt.combat(13)


func _status_name(status_id: String) -> String:
	return str({"flame_seed":"火种", "attack_up":"攻击提升", "defense_up":"防御提升", "charged":"蓄势", "terrain":"地势", "sharpness":"锋锐", "vitality":"生机", "flow":"回流"}.get(status_id, status_id.replace("_", " ")))


func _status_description(status_id: String) -> String:
	return str({
		"flame_seed":"可被火系神通消耗，转化为额外伤害。",
		"attack_up":"接下来的攻击造成更多伤害。",
		"defense_up":"接下来的受击会被减轻。",
		"charged":"下一次攻击会承接积蓄的力量。",
		"terrain":"土系守御积累的地势。",
		"sharpness":"可被金系神通消耗并放大伤害。",
		"vitality":"可转化为治疗、护盾或持续攻势。",
		"flow":"可提高后续神通的灵气效率。"
	}.get(status_id, "只在当前战斗中生效。"))


func _intent_value(action: Dictionary) -> String:
	for effect: Variant in action.get("effects", []):
		if effect is Dictionary and str(effect.get("type", "")) in ["damage", "shield", "heal"]:
			return str(int(effect.get("value", 0)))
	return ""


func play_hit() -> void:
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
	art_root.position.x = 0.0
	hit_tween = create_tween()
	hit_tween.tween_property(art_root, "modulate", Color("ff765e"), 0.06)
	hit_tween.parallel().tween_property(art_root, "position:x", 12.0, 0.06)
	hit_tween.tween_property(art_root, "position:x", 0.0, 0.09)
	hit_tween.parallel().tween_property(art_root, "modulate", Color.WHITE, 0.12)
	hit_tween.tween_callback(func() -> void: art_root.position.x = 0.0; art_root.modulate = Color.WHITE)


func play_attack(direction: float) -> void:
	if action_tween and action_tween.is_valid():
		action_tween.kill()
	art_root.position.x = 0.0
	action_tween = create_tween()
	action_tween.tween_property(art_root, "position:x", 72.0 * direction, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	action_tween.tween_interval(0.08)
	action_tween.tween_property(art_root, "position:x", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	action_tween.tween_callback(func() -> void: art_root.position.x = 0.0)


func play_guard() -> void:
	if guard_tween and guard_tween.is_valid():
		guard_tween.kill()
	art_root.scale = Vector2.ONE
	art_root.modulate = Color.WHITE
	guard_tween = create_tween()
	guard_tween.tween_property(art_root, "scale", Vector2.ONE * 1.12, 0.16).set_trans(Tween.TRANS_BACK)
	guard_tween.parallel().tween_property(art_root, "modulate", Color("8edbff"), 0.16)
	guard_tween.tween_interval(0.12)
	guard_tween.tween_property(art_root, "scale", Vector2.ONE, 0.24)
	guard_tween.parallel().tween_property(art_root, "modulate", Color.WHITE, 0.24)
	guard_tween.tween_callback(func() -> void: art_root.scale = Vector2.ONE; art_root.modulate = Color.WHITE)


func _add_part(part: Dictionary) -> void:
	var texture := AtlasTexture.new()
	texture.filter_clip = true
	texture.atlas = HUMAN_ATLAS if part.atlas == "human" else BEAST_ATLAS if part.atlas == "beast" else SPECIALIST_ATLAS if part.atlas == "specialist" else EXPANDED_ATLAS
	var cell := Vector2(float(texture.atlas.get_width()) / 3.0, float(texture.atlas.get_height()) / 2.0)
	var index := int(part.index)
	texture.region = Rect2(
		Vector2(index % 3, floori(float(index) / 3.0)) * cell + Vector2(float(part.get("region_x", 0.0)), float(part.get("region_y", 0.0))),
		cell + Vector2(float(part.get("region_width", 0.0)), float(part.get("region_height", 0.0)))
	)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.flip_h = bool(part.get("flip", false))
	rect.position += Vector2(part.get("x", 0.0), part.get("y", 0.0))
	rect.scale = Vector2.ONE * float(part.get("scale", 1.0))
	art_root.add_child(rect)


func _visual_recipe(id: String, player_side: bool) -> Dictionary:
	if player_side:
		return {"parts":[{"atlas":"human","index":0}]}
	if id == "training_puppet":
		return {"parts":[{"atlas":"specialist","index":0}]}
	if id == "bandit":
		return {"parts":[{"atlas":"human","index":1,"flip":true}]}
	if id == "black_tide_chief":
		return {"parts":[{"atlas":"expanded","index":2}]}
	if id == "seal_bearing_enforcer":
		return {"parts":[{"atlas":"human","index":2,"flip":true}]}
	if id == "dusk_beak_crow":
		return {"parts":[{"atlas":"specialist","index":5}]}
	if id == "steel_fang_wolf":
		return {"parts":[{"atlas":"beast","index":0}]}
	if id in ["fire_tail_wolf", "ember_dust_moth"]:
		return {"parts":[{"atlas":"specialist","index":4}]} if id == "ember_dust_moth" else {"parts":[{"atlas":"expanded","index":5,"region_x":-56,"region_width":56}]}
	if id == "rock_shell_tortoise":
		# Dedicated verified slot: bottom-centre of the 3x2 expanded atlas.
		# Keeping it as a single whole creature prevents accidental wolf-part mixing.
		return {"parts":[{"atlas":"expanded","index":4,"region_width":-54}]}
	if id == "iron_bark_guardian":
		return {"parts":[{"atlas":"specialist","index":1}]}
	if id in ["withered_vine_spirit", "blood_root_demon"]:
		return {"parts":[{"atlas":"specialist","index":3 if id == "withered_vine_spirit" else 2}]}
	return {"parts":[{"atlas":"human","index":1}]}


func _make_bar(color: Color, top: float, bottom: float) -> ProgressBar:
	var bar := ProgressBar.new()
	# UnitVisual may stretch to fill an enemy column. Keep bars centred beneath
	# the figure instead of letting a single enemy create a screen-wide bar.
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -155.0
	bar.offset_right = 155.0
	bar.offset_top = top
	bar.offset_bottom = bottom
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color("171a19")
	background.border_color = Color("9a8453")
	background.set_border_width_all(1)
	background.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)
	return bar


func _bar_label(bar: ProgressBar) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("fff2d2"))
	label.add_theme_color_override("font_shadow_color", Color("000000"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	bar.add_child(label)
	return label


func _pulse_idle() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(art_root, "position:y", -4.0, 1.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(art_root, "position:y", 2.0, 1.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
