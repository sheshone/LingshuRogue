extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		quit(2)
		return
	var source := Image.load_from_file(args[0])
	source.convert(Image.FORMAT_RGBA8)
	var columns := int(args[1])
	var rows := int(args[2])
	var output_dir := args[3]
	var names := args[4].split(",")
	var cell_size := Vector2i(source.get_width() / columns, source.get_height() / rows)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	for index in mini(names.size(), columns * rows):
		var cell := Image.create(cell_size.x, cell_size.y, false, Image.FORMAT_RGBA8)
		cell.blit_rect(source, Rect2i(Vector2i(index % columns, floori(float(index) / columns)) * cell_size, cell_size), Vector2i.ZERO)
		cell.save_png("%s/%s.png" % [output_dir, names[index]])
	quit()
