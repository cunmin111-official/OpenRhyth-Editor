extends Control

@onready var file_picker = $FilePicker
@onready var file_path_label = $FilePathLabel
@onready var music_picker = $MusicPicker
@onready var music_path_label = $MusicPathLabel

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
	pass

func _on_edit_file_pressed():
	get_tree().change_scene_to_file("res://scene/editor/editor_main.tscn")

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
