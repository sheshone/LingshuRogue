class_name SpellCard
extends PanelContainer

signal chosen(spell_id: String)

const ART_ATLAS: Texture2D = preload("res://assets/art/cards/five_elements_atlas-v1.png")
const SPELL_ATLAS_A: Texture2D = preload("res://assets/art/cards/spell_art_atlas-a-v1.png")
const SPELL_ATLAS_B: Texture2D = preload("res://assets/art/cards/spell_art_atlas-b-v1.png")
const CARD_FRAME: Texture2D = preload("res://assets/ui/generated/spell_card_frame-clean-v6.png")
const ART_ZOOM := {
	"qi_strike": 1.20, "five_phase_exchange": 1.24, "honing_breath": 1.18,
	"meridian_severing_flash": 1.18, "sprouting_guard": 1.20, "life_bloom": 1.18,
	"wildfire_wave": 1.18, "mountain_guard": 1.18, "water_cycle": 1.18
}
const SPELL_ART := {
	"honing_breath":[0,0], "meridian_severing_flash":[0,1], "sprouting_guard":[0,2], "life_bloom":[0,3], "ember_guard":[0,4],
	"wildfire_wave":[0,5], "rock_reversal":[0,6], "mountain_guard":[0,7], "water_cycle":[0,8], "five_phase_exchange":[0,9],
	"golden_arc":[0,10], "metallic_guard":[0,11], "verdant_recovery":[0,12], "wooden_aegis":[0,13], "five_element_guard":[0,14],
	"qi_strike":[1,0], "metal_edge_art":[1,1], "wood_thorn_art":[1,2], "fireball":[1,3], "kindling_art":[1,4],
	"flame_burst":[1,5], "body_protection":[1,6], "terrain_art":[1,7], "mountain_collapse":[1,8], "water_arrow":[1,9], "returning_flow":[1,10], "tidal_art":[1,10]
}

var spell_id := ""
var button: Button


func configure(spell: Dictionary, castable: bool, width: float, height: float = 202.0) -> void:
	spell_id = str(spell.get("id", ""))
	var scale_y := height / 202.0
	custom_minimum_size = Vector2(width, height)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	var color: Color = {"metal":Color("d5ad55"),"wood":Color("55a879"),"water":Color("5594cf"),"fire":Color("d95e45"),"earth":Color("b08348")}.get(_attribute(spell), Color("b6aa88"))
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.border_color = Color(0, 0, 0, 0)
	frame.set_border_width_all(0)
	frame.content_margin_left = 0.0; frame.content_margin_right = 0.0; frame.content_margin_top = 0.0; frame.content_margin_bottom = 0.0
	add_theme_stylebox_override("panel", frame)
	var canvas := Control.new()
	canvas.clip_contents = true
	add_child(canvas)
	var art_window := TextureRect.new()
	art_window.texture = _spell_art_texture(spell_id, _attribute(spell))
	art_window.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_window.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(art_window)
	# The illustration deliberately runs underneath the ornamental frame.  The
	# overlay masks its edge, avoiding the detached "picture in a rectangle" look.
	art_window.position = Vector2(width * 0.015, 10.0 * scale_y)
	art_window.size = Vector2(width * 0.97, 163.0 * scale_y)
	var frame_art := TextureRect.new()
	frame_art.texture = CARD_FRAME
	frame_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame_art.stretch_mode = TextureRect.STRETCH_SCALE
	frame_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_art.modulate = Color(1, 1, 1, 0.99)
	frame_art.z_index = 5
	canvas.add_child(frame_art)
	frame_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := Label.new()
	title.text = str(spell.get("name", "神通"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.z_index = 6
	title.add_theme_font_size_override("font_size", clampi(roundi(14.0 * scale_y), 10, 14))
	title.add_theme_color_override("font_color", color.lightened(0.35))
	canvas.add_child(title)
	title.position = Vector2(width * 0.11, 0.0)
	title.size = Vector2(width * 0.78, 23.0 * scale_y)
	var cost: Dictionary = spell.get("cost", {})
	var cost_icon := TextureRect.new()
	cost_icon.texture = UIArt.qi(_primary_cost_qi(cost))
	cost_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cost_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cost_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_icon.z_index = 6
	canvas.add_child(cost_icon)
	var cost_box := Vector2(width * 0.25, 28.0 * scale_y)
	var cost_scale := _qi_icon_visual_scale(_primary_cost_qi(cost))
	var cost_visual_offset := Vector2(-4.0, 0.0) if _primary_cost_qi(cost) == "wood" else Vector2.ZERO
	cost_icon.position = Vector2(width * 0.018, 132.0 * scale_y) + cost_box * (1.0 - cost_scale) * 0.5 + cost_visual_offset * scale_y
	cost_icon.size = cost_box * cost_scale
	var cost_value := Label.new()
	cost_value.text = str(_total_cost(cost))
	cost_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_value.z_index = 6
	cost_value.add_theme_font_size_override("font_size", clampi(roundi(12.0 * scale_y), 9, 12))
	cost_value.add_theme_color_override("font_color", Color("f5ddb0"))
	canvas.add_child(cost_value)
	cost_value.position = Vector2(width * 0.018, 155.0 * scale_y)
	cost_value.size = Vector2(width * 0.25, 16.0 * scale_y)
	var effect_row := _effect_symbols(spell.get("effects", []))
	effect_row.z_index = 6
	canvas.add_child(effect_row)
	# The ornamental frame's safe footer is 172-197 px. Keep the complete
	# icon/value summary inside it so neither the frame nor card clipping hides it.
	effect_row.position = Vector2(width * 0.10, 173.0 * scale_y)
	effect_row.size = Vector2(width * 0.80, 21.0 * scale_y)
	button = Button.new()
	button.flat = true
	button.set_meta("sfx_kind", "card")
	button.z_index = 10
	button.disabled = not castable
	button.tooltip_text = _card_tooltip(spell)
	button.pressed.connect(func() -> void: chosen.emit(spell_id))
	button.mouse_entered.connect(_raise)
	button.mouse_exited.connect(_lower)
	canvas.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not castable:
		modulate = Color(0.52, 0.54, 0.52, 0.86)


func _add_cost_icons(row: HBoxContainer, cost: Dictionary) -> void:
	if bool(cost.get("all_sea_qi", false)):
		for index: int in 3:
			_add_qi_icon(row, "any_qi")
		return
	for qi_id: Variant in cost:
		if str(qi_id) in ["minimum", "all_sea_qi"]:
			continue
		for index: int in mini(4, int(cost[qi_id])):
			_add_qi_icon(row, str(qi_id))


func _total_cost(cost: Dictionary) -> int:
	if bool(cost.get("all_sea_qi", false)):
		return int(cost.get("minimum", 1))
	var total := 0
	for qi_id: Variant in cost:
		if str(qi_id) not in ["minimum", "all_sea_qi"]:
			total += int(cost[qi_id])
	return maxi(0, total)


func _card_tooltip(spell: Dictionary) -> String:
	var qi_names := {"metal":"金灵气", "wood":"木灵气", "water":"水灵气", "fire":"火灵气", "earth":"土灵气", "any_qi":"任意灵气"}
	var cost: Dictionary = spell.get("cost", {})
	var costs: Array[String] = []
	if bool(cost.get("all_sea_qi", false)):
		costs.append("全部丹田灵气（至少%d）" % int(cost.get("minimum", 1)))
	else:
		for qi_id: Variant in cost:
			if str(qi_id) not in ["minimum", "all_sea_qi"]:
				costs.append("%s ×%d" % [qi_names.get(str(qi_id), str(qi_id)), int(cost[qi_id])])
	var attribute := _attribute(spell)
	return "%s\n属性：%s　神识：%d\n消耗：%s\n\n%s\n%s" % [
		spell.get("name", "神通"), qi_names.get(attribute, "无属性"), int(spell.get("sense_cost", 1)),
		"、".join(costs) if not costs.is_empty() else "无", str(spell.get("description", "")), _short_effect(spell.get("effects", []))
	]


func _add_qi_icon(row: HBoxContainer, qi_id: String) -> void:
	var icon := TextureRect.new()
	icon.texture = UIArt.qi(qi_id)
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)


func _raise() -> void:
	z_index = 20
	var tween := create_tween()
	tween.tween_property(self, "position:y", -8.0, 0.1)


func _lower() -> void:
	z_index = 0
	var tween := create_tween()
	tween.tween_property(self, "position:y", 0.0, 0.1)


func _attribute(spell: Dictionary) -> String:
	for tag: Variant in spell.get("tags", []):
		if str(tag) in ["metal","wood","water","fire","earth"]:
			return str(tag)
	return "neutral"


func _art_texture(attribute: String) -> Texture2D:
	var indices := {"metal":0,"wood":1,"water":2,"fire":3,"earth":4,"neutral":5}
	var index := int(indices.get(attribute, 5))
	var cell := Vector2(float(ART_ATLAS.get_width()) / 3.0, float(ART_ATLAS.get_height()) / 2.0)
	var texture := AtlasTexture.new()
	texture.atlas = ART_ATLAS
	texture.region = Rect2(Vector2(index % 3, floori(float(index) / 3.0)) * cell, cell)
	return texture


func _spell_art_texture(id: String, attribute: String) -> Texture2D:
	if not SPELL_ART.has(id):
		return _art_texture(attribute)
	var entry: Array = SPELL_ART[id]
	var atlas: Texture2D = SPELL_ATLAS_A if int(entry[0]) == 0 else SPELL_ATLAS_B
	var index := int(entry[1])
	var cell := Vector2(float(atlas.get_width()) / 5.0, float(atlas.get_height()) / 3.0)
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	var zoom := float(ART_ZOOM.get(id, 1.14))
	var region_size := cell / zoom
	var cell_origin := Vector2(index % 5, floori(float(index) / 5.0)) * cell
	var focus_offset := (cell - region_size) * 0.5
	# Most source paintings leave extra air above and place their subject low.
	focus_offset.y += cell.y * 0.025
	texture.region = Rect2(cell_origin + focus_offset, region_size)
	return texture


func _primary_cost_qi(cost: Dictionary) -> String:
	if bool(cost.get("all_sea_qi", false)):
		return "any_qi"
	for qi: Variant in cost:
		if str(qi) not in ["minimum", "all_sea_qi"]:
			return str(qi)
	return "any_qi"


func _qi_icon_visual_scale(qi_id: String) -> float:
	# Atlas cells have different amounts of transparent breathing room. These
	# values normalize the visible silhouettes rather than their raw cell size.
	return float({
		"metal": 0.90,
		"wood": 0.88,
		"water": 0.84,
		"fire": 0.76,
		"earth": 0.82,
		"any_qi": 1.0
	}.get(qi_id, 0.9))


func _effect_symbols(effects: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shown := 0
	for effect: Variant in effects:
		if not effect is Dictionary or shown >= 2:
			continue
		var type_id := str(effect.get("type", ""))
		var icon: Texture2D
		var value_text := ""
		match type_id:
			"damage": icon = load("res://assets/ui/icons/card_attack.svg"); value_text = str(int(effect.get("value", 0)))
			"shield": icon = load("res://assets/ui/icons/card_shield.svg"); value_text = str(int(effect.get("value", 0)))
			"heal": icon = load("res://assets/ui/icons/card_heal.svg"); value_text = str(int(effect.get("value", 0)))
			"add_status": icon = load("res://assets/ui/icons/card_status.svg"); value_text = "+%d" % int(effect.get("value", 1))
			"add_sea_qi": icon = load("res://assets/ui/icons/combat_v2/%s.png" % str(effect.get("qi", "any_qi"))); value_text = "+%d" % int(effect.get("value", 0))
			_: continue
		var pair := HBoxContainer.new()
		pair.custom_minimum_size = Vector2(0, 21)
		pair.alignment = BoxContainer.ALIGNMENT_CENTER
		pair.add_theme_constant_override("separation", 3)
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon
		icon_rect.custom_minimum_size = Vector2(19, 19)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(icon_rect)
		var value := Label.new()
		value.text = value_text
		value.custom_minimum_size = Vector2(13, 21)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.add_theme_font_size_override("font_size", 13)
		value.add_theme_color_override("font_color", Color("f3e5bd"))
		value.add_theme_color_override("font_outline_color", Color("080b09"))
		value.add_theme_constant_override("outline_size", 2)
		pair.add_child(value)
		row.add_child(pair)
		shown += 1
	return row


func _trimmed_effect_icon(path: String, height_ratio: float) -> Texture2D:
	var source: Texture2D = load(path)
	var trimmed := AtlasTexture.new()
	trimmed.filter_clip = true
	trimmed.atlas = source
	trimmed.region = Rect2(0, 0, source.get_width(), floorf(source.get_height() * height_ratio))
	return trimmed


func _cost_text(cost: Dictionary) -> String:
	if bool(cost.get("all_sea_qi", false)):
		return "全部丹田"
	var names := {"metal":"金","wood":"木","water":"水","fire":"火","earth":"土","any_qi":"任意"}
	var parts: Array[String] = []
	for qi: Variant in cost:
		if str(qi) not in ["minimum","all_sea_qi"]:
			parts.append("%s×%d" % [names.get(str(qi), "任意"), int(cost[qi])])
	return " ".join(parts) if not parts.is_empty() else "无消耗"


func _short_effect(effects: Array) -> String:
	var parts: Array[String] = []
	for effect: Variant in effects:
		if not effect is Dictionary: continue
		match str(effect.get("type", "")):
			"damage": parts.append("造成%d点伤害" % int(effect.get("value", 0)))
			"shield": parts.append("获得%d点护盾" % int(effect.get("value", 0)))
			"heal": parts.append("恢复%d点生命" % int(effect.get("value", 0)))
			"add_status":
				var status_id := str(effect.get("status", ""))
				parts.append("获得%s" % {"flame_seed":"火种", "attack_up":"攻击提升", "defense_up":"防御提升", "charged":"蓄势", "terrain":"地势", "sharpness":"锋锐", "vitality":"生机", "flow":"回流"}.get(status_id, "状态"))
			"add_sea_qi": parts.append("凝聚灵气")
		if parts.size() >= 2: break
	return "；".join(parts) if not parts.is_empty() else "特殊效果"
