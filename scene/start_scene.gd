extends Control

@onready var file_picker = $FilePicker
@onready var file_path_label = $FilePathLabel
@onready var music_picker = $MusicPicker
@onready var music_path_label = $MusicPathLabel
@onready var new_chart_picker = $NewChartPicker

func _ready():
	# 谱面文件选择器设置
	file_picker.access = FileDialog.ACCESS_FILESYSTEM
	file_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_picker.add_filter("*.rwc", "Rhythm World Chart")
	file_picker.file_selected.connect(_on_file_picker_file_selected)
	
	# 音乐文件选择器设置
	music_picker.access = FileDialog.ACCESS_FILESYSTEM
	music_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	music_picker.add_filter("*.mp3;*.ogg;*.wav", "音频文件")
	music_picker.file_selected.connect(_on_music_picker_file_selected)
	
	# 显示已有的路径（如果全局已有）
	if Global.selected_rwc_path != "":
		file_path_label.text = Global.selected_rwc_path
	if Global.selected_music_path != "":
		music_path_label.text = Global.selected_music_path

func _on_play_file_pressed():
	if Global.selected_rwc_path == "":
		print("[游玩] 错误：未选择谱面文件")
		return
	if Global.selected_music_path == "":
		print("[游玩] 错误：未选择音乐文件")
		return
	# 重置预览时间，从开头播放
	Global.preview_time = 0.0
	get_tree().change_scene_to_file("res://scene/play/play_page.tscn")

func _on_edit_file_pressed():
	get_tree().change_scene_to_file("res://scene/editor/editor_main.tscn")

func _on_settings_pressed():
	get_tree().change_scene_to_file("res://scene/settings/settings_page.tscn")

func _on_select_file_button_pressed():
	file_picker.popup()

func _on_select_music_button_pressed():
	music_picker.popup()

func get_relative_path(abs_path: String) -> String:
	var project_root = ProjectSettings.globalize_path("res://")
	if abs_path.begins_with(project_root):
		var rel = abs_path.trim_prefix(project_root)
		return "res://" + rel
	else:
		return abs_path

func _on_file_picker_file_selected(path: String):
	var relative_path = get_relative_path(path)
	Global.selected_rwc_path = relative_path
	file_path_label.text = relative_path

func _on_music_picker_file_selected(path: String):
	var relative_path = get_relative_path(path)
	Global.selected_music_path = relative_path
	music_path_label.text = relative_path

func _on_new_file_button_pressed():
	new_chart_picker.popup()

func _on_new_chart_picker_file_selected(path: String):
	# 确保扩展名为 .rwc
	if not path.to_lower().ends_with(".rwc"):
		path += ".rwc"
	
	var relative_path = get_relative_path(path)
	
	# 如果已存在则覆盖
	if FileAccess.file_exists(path):
		print("[新建谱面] 文件已存在，覆盖: ", path)
	
	# 创建默认谱面模板
	var default_chart = {
		"BPMList": [
			{"bpm": 120.0, "startTime": [0, 0, 1]}
		],
		"META": {
			"offset": 0,
			"notes": 0,
			"duration": 0.0
		},
		"judgeLineList": []
	}
	
	var json_string = JSON.stringify(default_chart, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("[新建谱面] 无法写入文件: ", path)
		return
	file.store_string(json_string)
	file.close()
	
	# 自动选中新建的文件
	Global.selected_rwc_path = relative_path
	file_path_label.text = relative_path
	print("[新建谱面] 已创建: ", relative_path)
