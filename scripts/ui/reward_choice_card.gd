class_name RewardChoiceCard
extends PanelContainer

signal chosen
var hit_button: Button


func configure(title_text: String, description_text: String, icon_texture: Texture2D, accent: Color) -> void:
	custom_minimum_size = Vector2(420, 108)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.07, 0.055, 0.94)
	style.border_color = Color(accent, 0.78)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 12.0
	add_theme_stylebox_override("panel", style)
	var layout := HBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 16)
	add_child(layout)
	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(icon)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(copy)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", accent.lightened(0.25))
	copy.add_child(title)
	var description := Label.new()
	description.text = description_text
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = 3
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(description)
	var hit := Button.new()
	hit_button = hit
	hit.flat = true
	hit.set_meta("sfx_kind", "reward")
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.tooltip_text = "%s\n\n%s" % [title_text, description_text]
	add_child(hit)
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.pressed.connect(func() -> void: chosen.emit())
	hit.mouse_entered.connect(func() -> void:
		pivot_offset = size * 0.5
		create_tween().tween_property(self, "scale", Vector2(1.035, 1.035), 0.1)
	)
	hit.mouse_exited.connect(func() -> void: create_tween().tween_property(self, "scale", Vector2.ONE, 0.1))


func set_reward_sound(kind: String) -> void:
	if is_instance_valid(hit_button):
		hit_button.set_meta("sfx_kind", kind)
