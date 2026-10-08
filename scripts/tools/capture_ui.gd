extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if not args.is_empty() else "res://scenes/ui/MainMenu.tscn"
	var output_path := args[1] if args.size() > 1 else "res://artifacts/ui_capture.png"
	if scene_path.ends_with("Map.tscn") or scene_path.ends_with("Battle.tscn") or scene_path.ends_with("MapNode.tscn"):
		var run_state: Node = root.get_node("RunState")
		run_state.reset_run()
		var player: Dictionary = GameDataLoader.load_collection("res://data/player_templates.json", "player_templates")[0]
		var core: Dictionary = GameDataLoader.load_collection("res://data/spirit_cores.json", "spirit_cores")[0]
		run_state.initialize_run(player, {"learned_spell_ids":["qi_strike"], "inventory":{}, "materials":{}, "relics":[]}, core)
		if scene_path.ends_with("Battle.tscn") and args.size() > 2 and args[2] == "cards":
			run_state.player_state["skills"]["spell_ids"] = ["five_element_guard", "flame_burst", "body_protection"]
		run_state.start_map("initiation_grounds", "initiation_origin")
		if scene_path.ends_with("Battle.tscn"):
			run_state.current_battle_id = args[2] if args.size() > 2 and args[2] != "cards" else "initiation_earth"
		elif scene_path.ends_with("MapNode.tscn"):
			var node_type := args[2] if args.size() > 2 else "rest"
			var content_id := "wandering_qi_shop" if node_type == "shop" else "rest_wind_shelter"
			run_state.pending_map_node = {"id":"capture_node", "name":"避风石窟" if node_type == "rest" else "松烟行脚铺", "type":node_type, "content_id":content_id}
	change_scene_to_file(scene_path)
	await process_frame
	await process_frame
	await create_timer(0.35).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output_path))
	print("UI_CAPTURE:%s:%s" % [output_path, error])
	quit()
