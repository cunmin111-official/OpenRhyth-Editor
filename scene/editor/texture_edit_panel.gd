extends Panel

signal texture_data_changed

@onready var texture_tree = $TextureTree
@onready var add_button = $AddButton
@onready var delete_button = $DeleteButton
@onready var file_dialog = $FileDialog
@onready var modify_button = $TextureManageButton

var chart_data: Dictionary = {}
var current_judge_line: Dictionary = {}
var current_textures: Array = []
var current_chart_path: String = ""

func _ready():
	texture_tree.columns = 3
	texture_tree.set_column_title(0, "文件路径")
	texture_tree.set_column_title(1, "开始时间 (节拍)")
	texture_tree.set_column_title(2, "结束时间 (节拍)")
	texture_tree.select_mode = Tree.SELECT_ROW
	
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.add_filter("*.png;*.jpg;*.jpeg;*.ogv", "图片/视频文件")
	
	file_dialog.file_selected.connect(_on_file_selected)
	texture_tree.item_activated.connect(_on_texture_activated)

func update_data(new_chart_data: Dictionary, new_judge_line = null, chart_file_path: String = ""):
	chart_data = new_chart_data
	current_judge_line = new_judge_line if typeof(new_judge_line) == TYPE_DICTIONARY else {}
	current_chart_path = chart_file_path
	if not current_judge_line.has("textures"):
		current_judge_line["textures"] = []
	current_textures = current_judge_line["textures"]
	refresh_tree()

func refresh_tree():
	texture_tree.clear()
	var root = texture_tree.create_item()
	root.set_text(0, "贴图列表")
	root.set_selectable(0, false)
	for tex in current_textures:
		var item = texture_tree.create_item(root)
		var display = tex.get("display", "")
		var start_time = tex.get("startTime", [0,0,1])
		var start_str = "[%d, %d, %d]" % [start_time[0], start_time[1], start_time[2]]
		var end_time = tex.get("endTime", start_time)
		var end_str = "[%d, %d, %d]" % [end_time[0], end_time[1], end_time[2]]
		item.set_text(0, display)
		item.set_text(1, start_str)
		item.set_text(2, end_str)
		item.set_metadata(0, tex)

func get_selected_texture():
	var selected = texture_tree.get_selected()
	if not selected:
		return null
	# 检查是否为根节点（根节点的文本是"贴图列表"）
	if selected.get_text(0) == "贴图列表":
		return null
	return selected.get_metadata(0)

func _on_add_button_pressed():
	file_dialog.popup_centered()

func _on_delete_button_pressed():
	var tex_data = get_selected_texture()
	if tex_data == null:
		print("删除失败：未选中任何贴图")
		return
	var idx = current_textures.find(tex_data)
	if idx != -1:
		current_textures.remove_at(idx)
		refresh_tree()
		texture_data_changed.emit()
		print("已删除贴图")
	else:
		print("删除失败：无法在列表中找到选中的贴图")

func _on_texture_manage_button_pressed():
	var tex_data = get_selected_texture()
	if tex_data == null:
		print("编辑失败：未选中任何贴图")
		return
	edit_texture_properties(tex_data)

func _on_file_selected(path: String):
	var relative_path = get_relative_path(path)
	var ext = relative_path.get_extension().to_lower()
	var tex_type = "image" if ext in ["png", "jpg", "jpeg"] else "video"
	var new_texture = {
		"display": relative_path,
		"type": tex_type,
		"startTime": [0,0,1],
		"endTime": [0,0,1]
	}
	current_textures.append(new_texture)
	refresh_tree()
	texture_data_changed.emit()

func _on_texture_activated():
	var tex_data = get_selected_texture()
	if tex_data == null:
		return
	edit_texture_properties(tex_data)

func edit_texture_properties(texture: Dictionary):
	var texture_json = JSON.stringify(texture, "\t")
	var dialog = ConfirmationDialog.new()
	dialog.title = "编辑贴图属性 (JSON)"
	dialog.ok_button_text = "确认"
	dialog.cancel_button_text = "取消"
	dialog.min_size = Vector2(600, 500)
	
	var vbox = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.size = Vector2(600, 500)
	
	var label = Label.new()
	label.text = "直接编辑 JSON 数据，确认后将更新贴图。\n字段说明：display(文件路径), type(image/video), startTime(节拍), endTime(节拍)。"
	var text_edit = TextEdit.new()
	text_edit.text = texture_json
	text_edit.custom_minimum_size = Vector2(500, 400)
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	if Global.mono_font:
		text_edit.add_theme_font_override("font", Global.mono_font)
	vbox.add_child(label)
	vbox.add_child(text_edit)
	dialog.add_child(vbox)
	
	dialog.confirmed.connect(func():
		var new_text = text_edit.text
		var json = JSON.new()
		var error = json.parse(new_text)
		if error == OK and typeof(json.data) == TYPE_DICTIONARY:
			var new_tex = json.data
			for field in ["startTime", "endTime"]:
				if new_tex.has(field) and typeof(new_tex[field]) == TYPE_ARRAY:
					var arr = new_tex[field]
					new_tex[field] = [int(arr[0]), int(arr[1]), int(arr[2])]
			# 直接替换原对象，保持引用
			var idx = current_textures.find(texture)
			if idx != -1:
				current_textures[idx] = new_tex
				refresh_tree()
				texture_data_changed.emit()
				print("贴图属性已更新")
			else:
				print("错误：找不到要编辑的贴图")
		else:
			var err_dialog = AcceptDialog.new()
			err_dialog.title = "JSON 解析错误"
			err_dialog.dialog_text = "无效的 JSON 格式:\n" + json.get_error_message()
			add_child(err_dialog)
			err_dialog.popup_centered()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func get_relative_path(abs_path: String) -> String:
	if current_chart_path.is_empty():
		var proj_root = ProjectSettings.globalize_path("res://").replace("\\", "/")
		if not proj_root.ends_with("/"):
			proj_root += "/"
		if abs_path.begins_with(proj_root):
			return abs_path.trim_prefix(proj_root)
		return abs_path
	
	var chart_dir = current_chart_path.get_base_dir()
	abs_path = abs_path.replace("\\", "/")
	chart_dir = chart_dir.replace("\\", "/")
	if abs_path.begins_with(chart_dir):
		var rel = abs_path.trim_prefix(chart_dir)
		if rel.begins_with("/"):
			rel = rel.substr(1)
		return rel
	return abs_path

func get_current_bottom_time() -> float:
	return 0.0

func time_to_beat(time_sec: float) -> float:
	return 0.0
