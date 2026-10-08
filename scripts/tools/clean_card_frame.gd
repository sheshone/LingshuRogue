extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(2)
		return
	var image := Image.load_from_file(args[0])
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	for y in height:
		for x in width:
			var nx := float(x) / width
			var ny := float(y) / height
			var keep_border := nx < 0.19 or nx > 0.83 or ny < 0.15 or ny > 0.88
			var c := image.get_pixel(x, y)
			if not keep_border:
				c.a = 0.0
			elif (nx < 0.035 or nx > 0.965 or ny < 0.02 or ny > 0.98):
				c.a = 0.0
			image.set_pixel(x, y, c)
	image.save_png(args[1])
	quit()
