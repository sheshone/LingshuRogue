extends Control

@onready var summary_label: Label = %SummaryLabel


func _ready() -> void:
	var summary := RunState.completion_summary
	summary_label.text = "行过 %d 处山川　历经 %d 场斗法\n破精英 %d　败寨主 %d\n掌神通 %d　携法宝 %d\n灵枢总量 %d　余灵石 %d" % [
		int(summary.get("visited", 0)), int(summary.get("battles", 0)),
		int(summary.get("elites", 0)), int(summary.get("bosses", 0)),
		int(summary.get("spells", 0)), int(summary.get("relics", 0)),
		int(summary.get("core_qi", 0)), int(summary.get("spirit_stones", 0))
	]
	%RestartButton.pressed.connect(_restart)
	%MainMenuButton.pressed.connect(_main_menu)


func _restart() -> void:
	RunState.reset_run()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")


func _main_menu() -> void:
	RunState.reset_run()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
