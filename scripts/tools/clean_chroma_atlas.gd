extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- source.png target.png")
		quit(2)
		return
	var image := Image.load_from_file(args[0])
	if image.is_empty():
		printerr("cannot load %s" % args[0])
		quit(3)
		return
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			# Soft chroma removal plus magenta decontamination at antialiased edges.
			var magenta_floor := minf(c.r, c.b)
			var key_strength := clampf((magenta_floor - c.g * 0.72 - 0.18) / 0.42, 0.0, 1.0)
			var alpha := 1.0 - key_strength
			if c.r > 0.55 and c.b > 0.55 and c.g < magenta_floor * 0.68:
				alpha = 0.0
			var spill := maxf(0.0, minf(c.r, c.b) - c.g)
			c.r = maxf(0.0, c.r - spill * (1.0 - alpha) * 0.85)
			c.b = maxf(0.0, c.b - spill * (1.0 - alpha) * 0.85)
			c.a = alpha
			image.set_pixel(x, y, c)
	var error := image.save_png(args[1])
	if error != OK:
		printerr("save failed: %s" % error)
		quit(4)
		return
	quit(0)
