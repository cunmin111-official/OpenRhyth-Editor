extends Node2D

# 音乐播放
var audio_player: AudioStreamPlayer
var is_music_playing: bool = false
var music_offset_sec: float = 0.0  # 谱面偏移（秒），后期做偏移校准用的
var is_auto_scrolling: bool = false  # 标记是否为自动滚动（防止触发手动滚动检测）

# 使用 @onready 获取 CanvasLayer 下的 UI 节点
@onready var file_path_label = $CanvasLayer/FilePathLabel

# 左边栏
@onready var judge_line_panel = $CanvasLayer/JudgeLinePanel
@onready var judge_line_tree = $CanvasLayer/JudgeLinePanel/JudgeLineTree
@onready var rename_button = $CanvasLayer/JudgeLinePanel/RenameButton
# 左下信息显示框
@onready var updated_at_label = $CanvasLayer/UpdatedAt
@onready var auto_saved_at_label = $CanvasLayer/AutoSavedAt
@onready var meta_display_label = $CanvasLayer/MetaDisplay
@onready var beats_display = $CanvasLayer/BeatsDisplay
@onready var time_display = $CanvasLayer/TimeDisplay

# 功能按钮引用
@onready var meta_btn = $CanvasLayer/MetaManageButton
@onready var note_btn = $CanvasLayer/NoteManageButton
@onready var effect_btn = $CanvasLayer/EffectManageButton
@onready var texture_btn = $CanvasLayer/TextureManageButton
@onready var shader_btn = $CanvasLayer/ShaderManageButton

# Meta 编辑面板
@onready var meta_edit_panel = $CanvasLayer/EditArea/MetaEditPanel
@onready var offset_line_edit = $CanvasLayer/EditArea/MetaEditPanel/OffsetLineEdit
@onready var bpm_tree = $CanvasLayer/EditArea/MetaEditPanel/BpmTree
@onready var bpm_value_edit = $CanvasLayer/EditArea/MetaEditPanel/BpmValueEdit
@onready var start_time_edit = $CanvasLayer/EditArea/MetaEditPanel/StartTimeEdit
@onready var add_bpm_button = $CanvasLayer/EditArea/MetaEditPanel/AddBpmButton
@onready var delete_bpm_button = $CanvasLayer/EditArea/MetaEditPanel/DeleteBpmButton
@onready var duration_line_edit = $CanvasLayer/EditArea/MetaEditPanel/DurationLineEdit
@onready var auto_fill_duration_button = $CanvasLayer/EditArea/MetaEditPanel/AutoFillDurationButton

# MIDI 导入控件
@onready var import_midi_button = $CanvasLayer/EditArea/MetaEditPanel/ImportMidiButton
@onready var midi_file_path_label = $CanvasLayer/EditArea/MetaEditPanel/MidiFilePathLabel
@onready var midi_track_list = $CanvasLayer/EditArea/MetaEditPanel/MidiTrackList
@onready var apply_bpm_from_midi_button = $CanvasLayer/EditArea/MetaEditPanel/ApplyBpmFromMidiButton
@onready var midi_note_count_label = $CanvasLayer/EditArea/MetaEditPanel/MidiNoteCountLabel
@onready var midi_offset_edit = $CanvasLayer/EditArea/MetaEditPanel/MidiOffsetEdit
@onready var midi_file_dialog = $CanvasLayer/EditArea/MetaEditPanel/MidiFileDialog

# MIDI 数据
var _midi_data: Dictionary = {}
var _midi_beat_positions: Array = []  # 选中轨道合并后的音符节拍位置（排序去重）

# Note 编辑面板
@onready var notes_edit_panel = $CanvasLayer/EditArea/NotesEditPanel

# Effect 编辑面板
@onready var effects_edit_panel = $CanvasLayer/EditArea/EffectsEditPanel

# Texture 编辑面板
@onready var texture_edit_panel = $CanvasLayer/EditArea/TextureEditPanel

# Shader 编辑面板
@onready var shader_edit_panel = $CanvasLayer/EditArea/ShaderEditPanel

# 是否保存
var is_saved: bool = true

# 编辑模式
enum EditMode {
	META,
	NOTE,
	EFFECT,
	TEXTURE,
	SHADER
}
var current_mode: EditMode = EditMode.META

# 谱面数据
var chart_data: Dictionary = {}
var current_rwc_path: String = ""

# 网格设置
const ALLOWED_SUBDIVISIONS := [1, 2, 3, 4, 5, 6, 7, 8, 12, 16, 24, 32]  # 允许的节拍细分分母
var subdivision: int = 1          # 节拍细分分母（1,2,3,...32）
var pixels_per_second: float = 500.0  # 像素密度

# 自动保存
var auto_save_timer: Timer = null
var last_auto_save_path: String = ""

func _ready():
	# 从设置加载偏好
	subdivision = Global.get_editor_subdivision()
	pixels_per_second = Global.get_editor_pixels_per_second()
	# 提前保存待恢复的滚动值（后续 update_data 会通过 v_scroll.value=0 触发 _on_any_scroll_changed 覆盖 Global）
	var initial_scroll = Global.preview_time if Global.preview_time > 0.0 else Global.editor_scroll_position
	_pending_scroll_restore = initial_scroll  # 直接保存到临时变量，不受 value_changed 影响
	
	# 复用 Global 中已 preload 的等宽字体，避免重复运行时加载
	var mono_font = Global.mono_font
	if mono_font:
		_apply_font_to_edit_controls(self, mono_font)
	
	set_mode_highlight(current_mode)
	notes_edit_panel.note_data_changed.connect(_on_note_data_changed)
	
	# 显示从开始页面传递过来的文件路径
	if Global.selected_rwc_path != "":
		file_path_label.text = "当前谱面: " + Global.selected_rwc_path
		current_rwc_path = Global.selected_rwc_path
		load_chart_file(current_rwc_path)
		refresh_judge_line_tree()
		refresh_meta_panel()
	else:
		file_path_label.text = "未选择任何文件"
	
	# 设置 BPM Tree
	bpm_tree.columns = 2
	bpm_tree.set_column_title(0, "BPM")
	bpm_tree.set_column_title(1, "StartTime")
	bpm_tree.select_mode = Tree.SelectMode.SELECT_ROW
	bpm_tree.allow_reselect = true
	
	# 连接信号
	bpm_tree.item_selected.connect(_on_bpm_tree_selected)
	bpm_value_edit.text_changed.connect(_on_bpm_value_changed)
	start_time_edit.text_changed.connect(_on_start_time_changed)
	add_bpm_button.pressed.connect(_on_add_bpm_pressed)
	delete_bpm_button.pressed.connect(_on_delete_bpm_pressed)
	offset_line_edit.text_changed.connect(_on_offset_changed)
	duration_line_edit.text_changed.connect(_on_duration_changed)
	
	# 初始显示 Meta 面板
	meta_edit_panel.visible = true
	notes_edit_panel.visible = false
	notes_edit_panel.set_view_size(1556.0, 1040.0)
	notes_edit_panel.update_data(chart_data, {})
	effects_edit_panel.set_view_size(1556.0, 1040.0)
	effects_edit_panel.effect_data_changed.connect(_on_effect_data_changed)
	effects_edit_panel.visible = false
	texture_edit_panel.texture_data_changed.connect(_on_texture_data_changed)
	texture_edit_panel.visible = false
	shader_edit_panel.set_view_size(1556.0, 1040.0)
	shader_edit_panel.shader_data_changed.connect(_on_shader_data_changed)
	shader_edit_panel.visible = false
	
	# 传递网格设置
	update_notes_panel_settings()
	
	# 传递 MIDI 参考（如果有）
	_apply_midi_data_to_panels()
	
	# 更新统计和保存状态
	update_metadata_display()
	update_saved_time_label()
	
	# 自动保存标签初始显示打开时间
	if auto_saved_at_label:
		var now = Time.get_datetime_string_from_system().replace("T", " ")
		auto_saved_at_label.text = "打开于 " + now
	
	# 监听判定线选择变化，实时更新显示
	judge_line_tree.item_selected.connect(_on_judge_line_selected)
	
	# 创建音频播放器
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	
	# 加载音乐
	var music_path = Global.selected_music_path
	if music_path != "" and FileAccess.file_exists(music_path):
		var music_stream = load_audio_from_path(music_path)
		if music_stream:
			audio_player.stream = music_stream
			print("已加载音乐: ", music_path, " 时长: ", music_stream.get_length())
		else:
			print("错误：无法加载音乐文件，可能格式不支持或路径错误: ", music_path)
	else:
		print("未选择音乐文件或文件不存在")
	
	audio_player.finished.connect(_on_music_finished)
	music_offset_sec = chart_data.get("META", {}).get("offset", 0) / 1000.0
	
	# 连接滚动条信号（手动滚动时停止音乐）
	notes_edit_panel.v_scroll.value_changed.connect(_on_any_scroll_changed)
	effects_edit_panel.v_scroll.value_changed.connect(_on_any_scroll_changed)
	shader_edit_panel.v_scroll.value_changed.connect(_on_any_scroll_changed)
	
	if Global.preview_time > 0.0:
		Global.editor_scroll_position = Global.preview_time
		notes_edit_panel.v_scroll.value = Global.preview_time
		effects_edit_panel.v_scroll.value = Global.preview_time
		shader_edit_panel.v_scroll.value = Global.preview_time
	elif initial_scroll > 0.0:
		notes_edit_panel.v_scroll.value = initial_scroll
		effects_edit_panel.v_scroll.value = initial_scroll
		shader_edit_panel.v_scroll.value = initial_scroll
	
	# 自动保存定时器
	auto_save_timer = Timer.new()
	auto_save_timer.one_shot = false
	auto_save_timer.timeout.connect(_on_auto_save_timer_timeout)
	add_child(auto_save_timer)
	_update_auto_save_timer()

func _on_music_finished():
	if is_music_playing:
		print("[音频控制] 音乐播放完成，自动停止预览")
		stop_preview()

func _process(delta: float) -> void:
	update_info_display()
	#if is_music_playing and audio_player.playing:
		#sync_grid_to_music()

func _on_judge_line_selected():
	_save_scroll_for_restore()
	update_metadata_display()
	if current_mode == EditMode.NOTE:
		var judge_line_data = get_selected_judge_line_data()
		notes_edit_panel.update_data(chart_data, judge_line_data)
		update_notes_panel_settings()
		_restore_panel_scroll(notes_edit_panel)
		_apply_midi_data_to_panels()
	elif current_mode == EditMode.EFFECT:
		var judge_line_data = get_selected_judge_line_data()
		effects_edit_panel.update_data(chart_data, judge_line_data)
		update_notes_panel_settings()
		_restore_panel_scroll(effects_edit_panel)
		_apply_midi_data_to_panels()
	elif current_mode == EditMode.TEXTURE:
		var judge_line_data = get_selected_judge_line_data()
		texture_edit_panel.update_data(chart_data, judge_line_data, current_rwc_path)

# 获取选中的判定线数据（字典），如果没有选中则返回空字典
func get_selected_judge_line_data() -> Dictionary:
	var selected = judge_line_tree.get_selected()
	if not selected:
		return {}
	var meta = selected.get_metadata(0)
	if typeof(meta) == TYPE_DICTIONARY:
		return meta
	return {}

# 应为网格全局调整
func update_notes_panel_settings():
	notes_edit_panel.set_subdivision(subdivision)
	notes_edit_panel.set_pixels_per_second(pixels_per_second)
	effects_edit_panel.set_subdivision(subdivision)
	effects_edit_panel.set_pixels_per_second(pixels_per_second)
	shader_edit_panel.set_subdivision(subdivision)
	shader_edit_panel.set_pixels_per_second(pixels_per_second)

# 设置按钮高亮
func set_mode_highlight(mode: EditMode):
	meta_btn.self_modulate = Color.WHITE
	note_btn.self_modulate = Color.WHITE
	effect_btn.self_modulate = Color.WHITE
	texture_btn.self_modulate = Color.WHITE
	shader_btn.self_modulate = Color.WHITE
	
	match mode:
		EditMode.META:
			meta_btn.self_modulate = Color.YELLOW
		EditMode.NOTE:
			note_btn.self_modulate = Color.YELLOW
		EditMode.EFFECT:
			effect_btn.self_modulate = Color.YELLOW
		EditMode.TEXTURE:
			texture_btn.self_modulate = Color.YELLOW
		EditMode.SHADER:
			shader_btn.self_modulate = Color.YELLOW

# 模式切换回调
func _on_meta_manage_button_pressed() -> void:
	_save_scroll_for_restore()
	current_mode = EditMode.META
	set_mode_highlight(current_mode)
	meta_edit_panel.visible = true
	notes_edit_panel.visible = false
	notes_edit_panel.update_data(chart_data, {})
	effects_edit_panel.visible = false
	texture_edit_panel.visible = false
	shader_edit_panel.visible = false
	_apply_midi_data_to_panels()
	update_metadata_display()
	print("切换到 Meta 编辑模式")

func _on_note_manage_button_pressed() -> void:
	_save_scroll_for_restore()
	current_mode = EditMode.NOTE
	set_mode_highlight(current_mode)
	meta_edit_panel.visible = false
	notes_edit_panel.visible = true
	effects_edit_panel.visible = false
	texture_edit_panel.visible = false
	shader_edit_panel.visible = false
	var judge_line_data = get_selected_judge_line_data()
	notes_edit_panel.update_data(chart_data, judge_line_data)
	update_notes_panel_settings()
	_restore_panel_scroll(notes_edit_panel)
	_apply_midi_data_to_panels()
	update_metadata_display()
	print("切换到 Note 编辑模式")

func _on_effect_manage_button_pressed() -> void:
	_save_scroll_for_restore()
	current_mode = EditMode.EFFECT
	set_mode_highlight(current_mode)
	meta_edit_panel.visible = false
	notes_edit_panel.visible = false
	effects_edit_panel.visible = true
	texture_edit_panel.visible = false
	shader_edit_panel.visible = false
	var selected = judge_line_tree.get_selected()
	var judge_line_data = {}
	if selected:
		var meta = selected.get_metadata(0)
		if typeof(meta) == TYPE_DICTIONARY:
			judge_line_data = meta
	effects_edit_panel.update_data(chart_data, judge_line_data)
	_restore_panel_scroll(effects_edit_panel)
	_apply_midi_data_to_panels()
	print("切换到 Effect 编辑模式")

func _on_texture_manage_button_pressed() -> void:
	_save_scroll_for_restore()
	current_mode = EditMode.TEXTURE
	set_mode_highlight(current_mode)
	meta_edit_panel.visible = false
	notes_edit_panel.visible = false
	effects_edit_panel.visible = false
	texture_edit_panel.visible = true
	shader_edit_panel.visible = false
	var selected = judge_line_tree.get_selected()
	var judge_line_data = {}
	if selected:
		var meta = selected.get_metadata(0)
		if typeof(meta) == TYPE_DICTIONARY:
			judge_line_data = meta
		else:
			# 选中的是分组节点，尝试选中该分组的第一个判定线
			var child = selected.get_first_child()
			if child:
				var child_meta = child.get_metadata(0)
				if typeof(child_meta) == TYPE_DICTIONARY:
					judge_line_data = child_meta
					child.select(0)
	elif chart_data.get("judgeLineList", []).size() > 0:
		# 未选中任何项，自动选中第一条判定线
		var root = judge_line_tree.get_root()
		if root:
			var first_group = root.get_first_child()
			if first_group:
				var first_line = first_group.get_first_child()
				if first_line:
					judge_line_data = first_line.get_metadata(0)
					first_line.select(0)
	texture_edit_panel.update_data(chart_data, judge_line_data, current_rwc_path)
	print("切换到 Texture 编辑模式")

func _on_shader_manage_button_pressed() -> void:
	_save_scroll_for_restore()
	current_mode = EditMode.SHADER
	set_mode_highlight(current_mode)
	meta_edit_panel.visible = false
	notes_edit_panel.visible = false
	effects_edit_panel.visible = false
	texture_edit_panel.visible = false
	shader_edit_panel.visible = true
	shader_edit_panel.update_data(chart_data)
	_restore_panel_scroll(shader_edit_panel)
	_apply_midi_data_to_panels()
	print("切换到 Shader 编辑模式")

func _on_return_button_pressed() -> void:
	# 回主页时重置滚动位置
	Global.editor_scroll_position = 0.0
	Global.preview_time = 0.0
	get_tree().change_scene_to_file("res://scene/start_scene.tscn")

func _on_preview_button_pressed() -> void:
	var scroll_pos = 0.0
	if notes_edit_panel.visible:
		scroll_pos = notes_edit_panel.v_scroll.value
	elif effects_edit_panel.visible:
		scroll_pos = effects_edit_panel.v_scroll.value
	elif shader_edit_panel.visible:
		scroll_pos = shader_edit_panel.v_scroll.value
	Global.editor_pre_preview_scroll = scroll_pos
	Global.preview_time = scroll_pos
	Global.editor_scroll_position = scroll_pos
	get_tree().change_scene_to_file("res://scene/preview/preview_page.tscn")

# 保存按钮
func _on_save_button_pressed():
	update_metadata_display()
	if save_chart_file():
		is_saved = true
		update_saved_time_label()
		_update_auto_save_timer()
		print("谱面已保存")
	else:
		print("保存失败")

# 加载谱面文件
func load_chart_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		print("文件不存在: ", path)
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		print("JSON 解析失败: ", json.get_error_message())
		return false
	chart_data = json.data
	if not chart_data.has("judgeLineList"):
		chart_data["judgeLineList"] = []
	if not chart_data.has("BPMList"):
		chart_data["BPMList"] = []
	if not chart_data.has("META"):
		chart_data["META"] = {"offset": 0, "notes": 0}
	sort_bpm_list()
	return true

# 保存谱面文件
func save_chart_file() -> bool:
	if current_rwc_path.is_empty():
		print("没有加载任何谱面文件")
		return false
	sort_all_events()
	var json_string = JSON.stringify(chart_data, "\t")
	var file = FileAccess.open(current_rwc_path, FileAccess.WRITE)
	if file == null:
		print("无法写入文件: ", current_rwc_path)
		return false
	file.store_string(json_string)
	file.close()
	print("保存成功: ", current_rwc_path)
	return true

func _sort_events_array(arr: Array) -> void:
	arr.sort_custom(func(a, b):
		if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
			return false
		return _fraction_to_beat_compare(a.get("startTime", [0, 0, 1]), b.get("startTime", [0, 0, 1]))
	)

func _fraction_to_beat_compare(a: Array, b: Array) -> bool:
	var a_val = float(a[0]) + float(a[1]) / float(a[2] if a[2] != 0 else 1)
	var b_val = float(b[0]) + float(b[1]) / float(b[2] if b[2] != 0 else 1)
	return a_val < b_val

func sort_all_events() -> void:
	var shader = chart_data.get("Shader", {})
	for key in ["Fog", "BackgroundR", "BackgroundG", "BackgroundB"]:
		if shader.has(key) and typeof(shader[key]) == TYPE_ARRAY:
			_sort_events_array(shader[key])
	var line_list = chart_data.get("judgeLineList", [])
	var event_keys = ["alphaEvents", "moveXEvents", "moveYEvents", "moveZEvents", "rotateXEvents", "rotateYEvents", "rotateZEvents", "speedEvents", "notesAlphaEvents", "lengthEvents"]
	for line in line_list:
		if typeof(line) != TYPE_DICTIONARY:
			continue
		# 确保 textures 字段存在
		if not line.has("textures"):
			line["textures"] = []
		# 音符按开始节拍升序排序
		if line.has("notes") and typeof(line["notes"]) == TYPE_ARRAY:
			line["notes"].sort_custom(func(a, b):
				if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
					return false
				return _fraction_to_beat_compare(a.get("startTime", [0, 0, 1]), b.get("startTime", [0, 0, 1]))
			)
		var layers = line.get("eventLayers", [])
		if layers.is_empty():
			continue
		var layer = layers[0]
		if typeof(layer) != TYPE_DICTIONARY:
			continue
		for key in event_keys:
			if layer.has(key) and typeof(layer[key]) == TYPE_ARRAY:
				_sort_events_array(layer[key])

# 刷新判定线树
func refresh_judge_line_tree():
	judge_line_tree.clear()
	var root = judge_line_tree.create_item()
	root.set_text(0, "判定线列表")
	root.set_selectable(0, false)
	
	var groups = {}
	for line in chart_data["judgeLineList"]:
		var group_id = int(line.get("Group", 0))
		if not groups.has(group_id):
			groups[group_id] = []
		groups[group_id].append(line)
	
	var sorted_groups = groups.keys()
	sorted_groups.sort()
	
	for gid in sorted_groups:
		var group_item = judge_line_tree.create_item(root)
		group_item.set_text(0, "分组 " + str(gid))
		group_item.set_selectable(0, true)
		group_item.set_metadata(0, gid)
		for line in groups[gid]:
			var line_item = judge_line_tree.create_item(group_item)
			line_item.set_text(0, line.get("Name", "未命名"))
			line_item.set_metadata(0, line)

# 新建判定线
func create_new_judge_line() -> Dictionary:
	return {
		"Group": 1,
		"Name": "新判定线",
		"eventLayers": [
			{
				"alphaEvents": [],
				"moveXEvents": [],
				"moveYEvents": [],
				"moveZEvents": [],
				"rotateXEvents": [],
				"rotateYEvents": [],
				"rotateZEvents": [],
				"speedEvents": []
			}
		],
		"notes": [],
		"textures": []
	}

func _on_new_judge_line_button_pressed():
	var new_line = create_new_judge_line()
	chart_data["judgeLineList"].append(new_line)
	refresh_judge_line_tree()
	mark_unsaved()

func _on_delete_judge_line_button_pressed():
	var selected = judge_line_tree.get_selected()
	if not selected:
		print("未选中任何判定线")
		return
	var meta = selected.get_metadata(0)
	if meta == null:
		print("选中的是根节点，不能删除")
		return
	if typeof(meta) == TYPE_INT:
		print("不能删除分组，只能删除判定线")
		return
	var index = chart_data["judgeLineList"].find(meta)
	if index != -1:
		chart_data["judgeLineList"].remove_at(index)
		refresh_judge_line_tree()
		mark_unsaved()
	else:
		print("未找到对应的判定线数据")

func _on_rename_button_pressed():
	var selected = judge_line_tree.get_selected()
	if not selected:
		print("未选中任何项")
		return
	var meta = selected.get_metadata(0)
	if meta == null:
		print("不能重命名根节点")
		return
	
	if typeof(meta) == TYPE_INT:
		# 重命名分组：修改分组序号
		var old_group_id = meta
		var new_group_id_str = await show_input_dialog("修改分组序号", "请输入新的分组序号（整数）:", str(old_group_id))
		if new_group_id_str.is_empty():
			return
		var new_group_id = int(new_group_id_str)
		for line in chart_data["judgeLineList"]:
			if int(line.get("Group", 0)) == old_group_id:
				line["Group"] = new_group_id
		refresh_judge_line_tree()
		mark_unsaved()
	else:
		# 重命名判定线：同时修改名称和分组
		var line_data = meta
		var old_name = line_data.get("Name", "未命名")
		var old_group = line_data.get("Group", 1)
		
		var dialog = ConfirmationDialog.new()
		dialog.title = "修改判定线"
		var vbox = VBoxContainer.new()
		var name_label = Label.new()
		name_label.text = "判定线名称:"
		var name_edit = LineEdit.new()
		name_edit.text = old_name
		var group_label = Label.new()
		group_label.text = "分组序号:"
		var group_edit = LineEdit.new()
		group_edit.text = str(old_group)
		group_edit.placeholder_text = "整数"
		vbox.add_child(name_label)
		vbox.add_child(name_edit)
		vbox.add_child(group_label)
		vbox.add_child(group_edit)
		dialog.add_child(vbox)
		add_child(dialog)
		dialog.popup_centered()
		await dialog.confirmed
		var new_name = name_edit.text
		var new_group_str = group_edit.text
		dialog.queue_free()
		
		if new_name.is_empty():
			return
		var new_group = int(new_group_str) if new_group_str.is_valid_int() else old_group
		line_data["Name"] = new_name
		line_data["Group"] = new_group
		refresh_judge_line_tree()
		mark_unsaved()

# 输入对话框
func show_input_dialog(title: String, message: String, default_text: String = "") -> String:
	var dialog = ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	var line_edit = LineEdit.new()
	line_edit.text = default_text
	dialog.add_child(line_edit)
	dialog.get_ok_button().pressed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	await dialog.confirmed
	var input_text = line_edit.text
	dialog.queue_free()
	return input_text

# 全局输入事件
func _input(event: InputEvent):
	# 空格键：播放/暂停预览（优先处理，避免被其他面板重复处理）
	if Global.is_shortcut_match(event, "editor", "start_preview"):
		if is_music_playing:
			stop_preview()
			print("[音频控制] 停止预览")
		else:
			start_preview()
			print("[音频控制] 开始预览")
		get_viewport().set_input_as_handled()
		return
	if Global.is_shortcut_match(event, "editor", "save"):
		_on_save_button_pressed()
		get_viewport().set_input_as_handled()
	elif notes_edit_panel.visible or effects_edit_panel.visible or shader_edit_panel.visible:
		if Global.is_shortcut_match(event, "editor", "increase_subdivision"):
			# 增大细分分母（更密）
			var new_sub = subdivision + 1
			var allowed = ALLOWED_SUBDIVISIONS
			if new_sub in allowed:
				subdivision = new_sub
			elif new_sub > 32:
				subdivision = 32
			else:
				# 找到下一个允许的值
				for val in allowed:
					if val > subdivision:
						subdivision = val
						break
			Global.set_editor_subdivision(subdivision)
			update_notes_panel_settings()
			get_viewport().set_input_as_handled()
		elif Global.is_shortcut_match(event, "editor", "decrease_subdivision"):
			var new_sub = subdivision - 1
			var allowed = ALLOWED_SUBDIVISIONS
			if new_sub in allowed:
				subdivision = new_sub
			elif new_sub < 1:
				subdivision = 1
			else:
				# 找到上一个允许的值
				for i in range(allowed.size()-1, -1, -1):
					if allowed[i] < subdivision:
						subdivision = allowed[i]
						break
			Global.set_editor_subdivision(subdivision)
			update_notes_panel_settings()
			get_viewport().set_input_as_handled()
		elif Global.is_shortcut_match(event, "editor", "increase_pixels"):
			pixels_per_second = clamp(pixels_per_second + 50, 50, 3000)
			Global.set_editor_pixels_per_second(pixels_per_second)
			update_notes_panel_settings()
			get_viewport().set_input_as_handled()
		elif Global.is_shortcut_match(event, "editor", "decrease_pixels"):
			pixels_per_second = clamp(pixels_per_second - 50, 50, 3000)
			Global.set_editor_pixels_per_second(pixels_per_second)
			update_notes_panel_settings()
			get_viewport().set_input_as_handled()
		elif Global.is_shortcut_match(event, "editor", "fix_integers"):
			fix_chart_data_integers()
			get_viewport().set_input_as_handled()

func _update_auto_save_timer() -> void:
	if Global.get_auto_save_enabled() and current_rwc_path != "":
		auto_save_timer.wait_time = Global.get_auto_save_interval() * 60.0
		auto_save_timer.start()
	else:
		auto_save_timer.stop()

func _on_auto_save_timer_timeout() -> void:
	if current_rwc_path.is_empty():
		return
	# 自动保存到 .autosave.rwc，不覆盖原文件
	var auto_save_path = current_rwc_path.replace(".rwc", ".autosave.rwc")
	sort_all_events()
	var json_string = JSON.stringify(chart_data, "\t")
	var file = FileAccess.open(auto_save_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		var now = Time.get_datetime_string_from_system().replace("T", " ")
		auto_saved_at_label.text = "自动保存于 " + now
		print("[自动保存] 已保存到: ", auto_save_path)

# 更新统计显示（根据选中的判定线或全局）
func update_metadata_display():
	if chart_data.is_empty():
		meta_display_label.text = "0 物量  0 动效"
		return
	
	var selected_judge_line = get_selected_judge_line_data()
	if not selected_judge_line.is_empty():
		# 显示选中的判定线的统计
		var true_note_count = 0
		var total_events = 0
		for note in selected_judge_line.get("notes", []):
			if note.get("isFake", 0) == 0:
				true_note_count += 1
		for layer in selected_judge_line.get("eventLayers", []):
			total_events += layer.get("alphaEvents", []).size()
			total_events += layer.get("moveXEvents", []).size()
			total_events += layer.get("moveYEvents", []).size()
			total_events += layer.get("moveZEvents", []).size()
			total_events += layer.get("rotateXEvents", []).size()
			total_events += layer.get("rotateYEvents", []).size()
			total_events += layer.get("rotateZEvents", []).size()
			total_events += layer.get("speedEvents", []).size()
		var line_name = selected_judge_line.get("Name", "未命名")
		meta_display_label.text = "选定的线 %s %d 物量 %d 动效" % [line_name, true_note_count, total_events]
	else:
		# 没有选中任何判定线，显示全局统计
		var true_note_count = 0
		var total_events = 0
		for line in chart_data.get("judgeLineList", []):
			for note in line.get("notes", []):
				if note.get("isFake", 0) == 0:
					true_note_count += 1
			for layer in line.get("eventLayers", []):
				total_events += layer.get("alphaEvents", []).size()
				total_events += layer.get("moveXEvents", []).size()
				total_events += layer.get("moveYEvents", []).size()
				total_events += layer.get("moveZEvents", []).size()
				total_events += layer.get("rotateXEvents", []).size()
				total_events += layer.get("rotateYEvents", []).size()
				total_events += layer.get("rotateZEvents", []).size()
				total_events += layer.get("speedEvents", []).size()
		meta_display_label.text = "全局 %d 物量 %d 动效" % [true_note_count, total_events]
		# 同步到 META.notes
		chart_data["META"]["notes"] = true_note_count

# 更新保存时间标签
func update_saved_time_label():
	if is_saved:
		var current_time = Time.get_datetime_string_from_system().replace("T", " ")
		updated_at_label.text = "已保存于 " + current_time
	else:
		updated_at_label.text = "未保存"

# 全屏切换
func toggle_fullscreen():
	var mode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ===================== Meta 编辑相关函数 =====================

func get_beat_from_start_time(start_time: Array) -> float:
	if start_time.size() != 3:
		return 0.0
	var integer = float(start_time[0])
	var numerator = float(start_time[1])
	var denominator = float(start_time[2])
	if denominator == 0:
		denominator = 1.0
	return integer + numerator / denominator

func sort_bpm_list():
	var bpm_list = chart_data.get("BPMList", [])
	bpm_list.sort_custom(func(a, b):
		var beat_a = get_beat_from_start_time(a.get("startTime", [0,0,1]))
		var beat_b = get_beat_from_start_time(b.get("startTime", [0,0,1]))
		return beat_a < beat_b
	)
	chart_data["BPMList"] = bpm_list

func refresh_meta_panel():
	if chart_data.has("META"):
		offset_line_edit.text = str(chart_data["META"].get("offset", 0))
		duration_line_edit.text = str(chart_data["META"].get("duration", 0.0))
	else:
		offset_line_edit.text = "0"
		duration_line_edit.text = "0"
	sort_bpm_list()
	refresh_bpm_tree()

func refresh_bpm_tree():
	bpm_tree.clear()
	var root = bpm_tree.create_item()
	root.set_text(0, "BPM 列表")
	root.set_selectable(0, false)
	
	for bpm_item in chart_data.get("BPMList", []):
		var item = bpm_tree.create_item(root)
		item.set_text(0, str(bpm_item.get("bpm", 120.0)))
		var start_time_arr = bpm_item.get("startTime", [0,0,1])
		var start_time_str = "[%d, %d, %d]" % [int(start_time_arr[0]), int(start_time_arr[1]), int(start_time_arr[2])]
		item.set_text(1, start_time_str)
		item.set_metadata(0, bpm_item)
		item.set_selectable(0, true)
		item.set_selectable(1, true)

func _on_bpm_tree_selected():
	var selected = bpm_tree.get_selected()
	if not selected:
		return
	var bpm_data = selected.get_metadata(0)
	if bpm_data == null or typeof(bpm_data) != TYPE_DICTIONARY:
		bpm_value_edit.text = ""
		start_time_edit.text = ""
		return
	bpm_value_edit.text = str(bpm_data.get("bpm", 120.0))
	var start_time_arr = bpm_data.get("startTime", [0,0,1])
	start_time_edit.text = "[%d, %d, %d]" % [int(start_time_arr[0]), int(start_time_arr[1]), int(start_time_arr[2])]

func _on_bpm_value_changed(new_text: String):
	var selected = bpm_tree.get_selected()
	if not selected:
		return
	var bpm_data = selected.get_metadata(0)
	if bpm_data == null or typeof(bpm_data) != TYPE_DICTIONARY:
		return
	var new_bpm = new_text.to_float()
	bpm_data["bpm"] = new_bpm
	selected.set_text(0, str(new_bpm))
	mark_unsaved()

func _on_start_time_changed(new_text: String):
	var selected = bpm_tree.get_selected()
	if not selected:
		return
	var bpm_data = selected.get_metadata(0)
	if bpm_data == null or typeof(bpm_data) != TYPE_DICTIONARY:
		return
	var json = JSON.new()
	var parse_result = json.parse(new_text)
	if parse_result == OK and typeof(json.data) == TYPE_ARRAY and json.data.size() == 3:
		var new_arr = [int(json.data[0]), int(json.data[1]), int(json.data[2])]
		bpm_data["startTime"] = new_arr
		selected.set_text(1, "[%d, %d, %d]" % new_arr)
		sort_bpm_list()
		refresh_bpm_tree()
	else:
		var original_arr = bpm_data.get("startTime", [0,0,1])
		start_time_edit.text = "[%d, %d, %d]" % [int(original_arr[0]), int(original_arr[1]), int(original_arr[2])]
		return
	mark_unsaved()

func _on_offset_changed(new_text: String):
	if new_text.is_valid_int():
		chart_data["META"]["offset"] = int(new_text)
	else:
		chart_data["META"]["offset"] = 0
	mark_unsaved()

func _on_add_bpm_pressed():
	var new_bpm = {
		"bpm": 120.0,
		"startTime": [0, 0, 1]
	}
	chart_data["BPMList"].append(new_bpm)
	sort_bpm_list()
	refresh_bpm_tree()
	mark_unsaved()

func _on_delete_bpm_pressed():
	var selected = bpm_tree.get_selected()
	if not selected:
		print("未选中任何 BPM 项")
		return
	var bpm_data = selected.get_metadata(0)
	if bpm_data == null or typeof(bpm_data) != TYPE_DICTIONARY:
		print("选中的不是有效的 BPM 项")
		return
	var index = chart_data["BPMList"].find(bpm_data)
	if index != -1:
		chart_data["BPMList"].remove_at(index)
		refresh_bpm_tree()
		mark_unsaved()
	else:
		print("未找到对应的 BPM 数据")

func mark_unsaved():
	update_metadata_display()
	is_saved = false
	update_saved_time_label()

func _on_duration_changed(new_text: String):
	if new_text.is_valid_float():
		chart_data["META"]["duration"] = new_text.to_float()
	else:
		chart_data["META"]["duration"] = 0.0
	mark_unsaved()

func _on_auto_fill_duration_pressed():
	if Global.selected_music_path == "" or not FileAccess.file_exists(Global.selected_music_path):
		print("无法自动填充：未选择音乐文件")
		return
	var stream = load_audio_from_path(Global.selected_music_path)
	if stream == null:
		print("无法自动填充：加载音乐文件失败")
		return
	var length = stream.get_length()
	duration_line_edit.text = str(length)

# ===================== MIDI 导入相关 =====================

func _on_import_midi_button_pressed():
	midi_file_dialog.popup_centered(Vector2(800, 600))

func _on_midi_file_selected(path: String):
	print("[MIDI] 选择文件: ", path)
	var result = load("res://scene/editor/midi_parser.gd").parse_midi_file(path)
	if not result["success"]:
		print("[MIDI] 解析失败: ", result["error"])
		midi_file_path_label.text = "解析失败: " + result["error"]
		return
	
	_midi_data = result
	midi_file_path_label.text = "已加载: " + path.get_file()
	
	# 填充轨道列表
	midi_track_list.clear()
	var track_names = result["track_names"] as Array
	for name in track_names:
		midi_track_list.add_item(str(name))
	
	# 默认全选
	for i in range(midi_track_list.item_count):
		midi_track_list.select(i)
	
	_update_midi_reference_positions()
	_apply_midi_data_to_panels()
	print("[MIDI] 成功加载，共 ", track_names.size(), " 个轨道")

func _on_midi_track_selected(index: int, selected: bool):
	_update_midi_reference_positions()
	_apply_midi_data_to_panels()

func _on_apply_bpm_from_midi_pressed():
	if _midi_data.is_empty() or not _midi_data.get("success", false):
		print("[MIDI] 没有已加载的 MIDI 数据")
		return
	
	var midi_bpm = _midi_data.get("bpm_list", [])
	if midi_bpm.is_empty():
		print("[MIDI] MIDI 文件中没有 BPM 信息")
		return
	
	chart_data["BPMList"] = midi_bpm.duplicate(true)
	sort_bpm_list()
	refresh_bpm_tree()
	mark_unsaved()
	
	# 重新刷新所有面板
	var judge_line_data = get_selected_judge_line_data()
	notes_edit_panel.update_data(chart_data, judge_line_data)
	effects_edit_panel.update_data(chart_data, judge_line_data)
	shader_edit_panel.update_data(chart_data)
	update_notes_panel_settings()
	
	print("[MIDI] 已应用 BPM，共 ", midi_bpm.size(), " 个 BPM 事件")

# 根据选中的轨道更新 MIDI 参考节拍位置
func _update_midi_reference_positions():
	if _midi_data.is_empty():
		_midi_beat_positions = []
		midi_note_count_label.text = ""
		return
	
	var all_beats: Array = []
	var track_notes = _midi_data.get("track_notes", []) as Array
	
	for i in range(midi_track_list.item_count):
		if midi_track_list.is_selected(i) and i < track_notes.size():
			var beats = track_notes[i] as Array
			for b in beats:
				all_beats.append(b)
	
	# 排序去重
	all_beats.sort()
	var unique_beats = []
	for b in all_beats:
		if unique_beats.is_empty() or abs(b - unique_beats.back()) > 0.001:
			unique_beats.append(b)
	
	# 应用偏移量
	var offset = midi_offset_edit.text.to_float()
	if offset != 0.0:
		var offset_beats = []
		for b in unique_beats:
			offset_beats.append(b + offset)
		_midi_beat_positions = offset_beats
	else:
		_midi_beat_positions = unique_beats
	
	midi_note_count_label.text = "MIDI 参考音符: " + str(_midi_beat_positions.size()) + " 个"

func _on_midi_offset_changed(new_text: String):
	_update_midi_reference_positions()
	_apply_midi_data_to_panels()

# 传递 MIDI 参考位置到各编辑面板
func _apply_midi_data_to_panels():
	notes_edit_panel.set_midi_reference(_midi_beat_positions)
	effects_edit_panel.set_midi_reference(_midi_beat_positions)
	shader_edit_panel.set_midi_reference(_midi_beat_positions)

# 切换前保存的滚动位置（局部暂存，避免被 _on_any_scroll_changed 覆盖）
var _pending_scroll_restore: float = -1.0

# 保存当前可见面板的滚动位置到暂存变量
func _save_scroll_for_restore():
	if notes_edit_panel.visible:
		_pending_scroll_restore = notes_edit_panel.v_scroll.value
	elif effects_edit_panel.visible:
		_pending_scroll_restore = effects_edit_panel.v_scroll.value
	elif shader_edit_panel.visible:
		_pending_scroll_restore = shader_edit_panel.v_scroll.value
	elif Global.editor_scroll_position > 0.0:
		_pending_scroll_restore = Global.editor_scroll_position
	# else: 保留 _pending_scroll_restore 现有值（可能来自 _ready 或之前的保存）

# 恢复面板滚动位置（update_data 会通过 v_scroll.value=0 触发 _on_any_scroll_changed 覆盖 Global）
func _restore_panel_scroll(panel):
	var restore_val = _pending_scroll_restore if _pending_scroll_restore >= 0.0 else Global.editor_scroll_position
	if restore_val > 0.0:
		panel.v_scroll.value = restore_val
	_pending_scroll_restore = -1.0

var _last_beats_text: String = ""
var _last_time_text: String = ""

func update_info_display():
	var beats_text: String
	var time_text: String
	if current_mode == EditMode.META:
		var duration = chart_data.get("META", {}).get("duration", 0.0)
		var total_beat = 0.0
		if duration > 0 and notes_edit_panel:
			total_beat = notes_edit_panel.time_to_beat(duration)
		beats_text = "总计 %.3f" % total_beat
		var minutes = floor(duration / 60)
		var seconds = int(duration) % 60
		var millis = floor((duration - floor(duration)) * 1000)
		time_text = "%d:%02d.%03d" % [minutes, seconds, millis]
	else:
		var current_time = 0.0
		var current_beat = 0.0
		if notes_edit_panel and notes_edit_panel.visible:
			current_time = notes_edit_panel.get_current_bottom_time()
			current_beat = notes_edit_panel.time_to_beat(current_time)
		elif effects_edit_panel and effects_edit_panel.visible:
			current_time = effects_edit_panel.get_current_bottom_time()
			current_beat = effects_edit_panel.time_to_beat(current_time)
		elif shader_edit_panel and shader_edit_panel.visible:
			current_time = shader_edit_panel.get_current_bottom_time()
			current_beat = shader_edit_panel.time_to_beat(current_time)
		else:
			current_time = 0.0
			current_beat = 0.0

		beats_text = "当前 %.3f" % current_beat
		var minutes = floor(current_time / 60)
		var seconds = int(current_time) % 60
		var millis = floor((current_time - floor(current_time)) * 1000)
		time_text = "%d:%02d.%03d" % [minutes, seconds, millis]

	# 仅在文本变化时写入，避免每帧无谓的 Label 赋值
	if beats_text != _last_beats_text:
		beats_display.text = beats_text
		_last_beats_text = beats_text
	if time_text != _last_time_text:
		time_display.text = time_text
		_last_time_text = time_text

func fix_chart_data_integers():
	# 修复所有判定线中的音符
	for line in chart_data.get("judgeLineList", []):
		for note in line.get("notes", []):
			if note.has("type"):
				note["type"] = int(note["type"])
			if note.has("startTime") and typeof(note["startTime"]) == TYPE_ARRAY:
				var arr = note["startTime"]
				note["startTime"] = [int(arr[0]), int(arr[1]), int(arr[2])]
			if note.has("endTime") and typeof(note["endTime"]) == TYPE_ARRAY:
				var arr = note["endTime"]
				note["endTime"] = [int(arr[0]), int(arr[1]), int(arr[2])]
	# 修复 BPM 列表中的 startTime
	for bpm in chart_data.get("BPMList", []):
		if bpm.has("startTime") and typeof(bpm["startTime"]) == TYPE_ARRAY:
			var arr = bpm["startTime"]
			bpm["startTime"] = [int(arr[0]), int(arr[1]), int(arr[2])]
	# 修复判定线中的贴图数据
	for line in chart_data.get("judgeLineList", []):
		if not line.has("textures"):
			line["textures"] = []
		for tex in line["textures"]:
			for time_field in ["startTime", "endTime"]:
				if tex.has(time_field) and typeof(tex[time_field]) == TYPE_ARRAY:
					var arr = tex[time_field]
					tex[time_field] = [int(arr[0]), int(arr[1]), int(arr[2])]
	# 保存文件
	if save_chart_file():
		# 刷新界面
		refresh_judge_line_tree()
		refresh_meta_panel()
		if current_mode == EditMode.NOTE:
			var judge_line_data = get_selected_judge_line_data()
			notes_edit_panel.update_data(chart_data, judge_line_data)
			update_notes_panel_settings()
		update_metadata_display()
		print("已修复整数类型并保存")
	else:
		print("保存失败")

func _on_note_data_changed():
	mark_unsaved()

func _on_effect_data_changed():
	mark_unsaved()

func _on_texture_data_changed():
	mark_unsaved()

func _on_shader_data_changed():
	mark_unsaved()

func sync_grid_to_music():
	if not audio_player.playing:
		return
	var current_time = audio_player.get_playback_position()
	var chart_time = current_time - music_offset_sec
	if chart_time < 0:
		chart_time = 0
	if notes_edit_panel.visible:
		notes_edit_panel.v_scroll.value = chart_time
	elif effects_edit_panel.visible:
		effects_edit_panel.v_scroll.value = chart_time
	elif shader_edit_panel.visible:
		shader_edit_panel.v_scroll.value = chart_time

func start_preview():
	var current_chart_time = 0.0
	var panel_name = ""
	
	# 设置自动滚动标志，防止触发手动滚动检测
	is_auto_scrolling = true
	
	if notes_edit_panel.visible:
		current_chart_time = notes_edit_panel.get_current_bottom_time()
		notes_edit_panel.start_playback()
		panel_name = "Notes"
	elif effects_edit_panel.visible:
		current_chart_time = effects_edit_panel.get_current_bottom_time()
		effects_edit_panel.start_playback()
		panel_name = "Effects"
	elif shader_edit_panel.visible:
		current_chart_time = shader_edit_panel.get_current_bottom_time()
		shader_edit_panel.start_playback()
		panel_name = "Shader"
	else:
		is_auto_scrolling = false
		print("[预览控制] 警告：没有可见的编辑面板，无法开始预览")
		return
	
	if audio_player.stream:
		# 音乐起始时间 = 当前谱面时间（不加offset，因为网格显示的是音乐时间）
		var audio_offset_sec = Global.get_audio_offset_ms() / 1000.0
		var music_start = current_chart_time - audio_offset_sec
		if music_start < 0:
			music_start = 0
		if music_start < audio_player.stream.get_length():
			audio_player.play(music_start)
			is_music_playing = true
			print("[预览控制] 开始预览 - 面板: %s, 音乐起始时间: %.3f秒" % [panel_name, music_start])
		else:
			is_auto_scrolling = false
			print("[预览控制] 警告：起始时间 %.3f秒 超过音乐长度 %.3f秒" % [music_start, audio_player.stream.get_length()])
			is_music_playing = false
	else:
		print("[预览控制] 警告：未加载音乐文件，仅播放网格滚动")
		is_music_playing = true

func stop_preview():
	# 清除自动滚动标志
	is_auto_scrolling = false
	# 停止所有面板的播放，防止滚动失控
	notes_edit_panel.stop_playback()
	effects_edit_panel.stop_playback()
	shader_edit_panel.stop_playback()
	if audio_player.playing:
		audio_player.stop()
	is_music_playing = false
	print("[预览控制] 停止预览 - 所有面板播放已停止")

func stop_music():
	if audio_player.playing:
		audio_player.stop()
	is_music_playing = false
	print("[音频控制] 停止音乐")

func _on_any_scroll_changed(value):
	# 跟踪滚动位置
	Global.editor_scroll_position = value
	# 如果是自动滚动，不触发停止音乐
	if is_auto_scrolling:
		return
	if is_music_playing:
		print("[滚动控制] 检测到手动滚动，停止音乐")
		stop_music()

func _exit_tree():
	if audio_player:
		audio_player.stop()

# 从文件路径加载音频（支持项目外路径）
func load_audio_from_path(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		print("[音频加载] 文件不存在: ", path)
		return null
	
	var extension = path.get_extension().to_lower()
	var audio_stream: AudioStream = null
	
	print("[音频加载] 尝试加载音频，扩展名: ", extension)
	
	match extension:
		"mp3":
			audio_stream = AudioStreamMP3.load_from_file(path)
			print("[音频加载] MP3 加载结果: ", audio_stream)
		"ogg", "oga":
			audio_stream = AudioStreamOggVorbis.load_from_file(path)
			print("[音频加载] OGG 加载结果: ", audio_stream)
		"wav":
			audio_stream = AudioStreamWAV.load_from_file(path)
			print("[音频加载] WAV 加载结果: ", audio_stream)
		_:
			# 尝试使用 ResourceLoader 加载其他格式
			audio_stream = ResourceLoader.load(path, "AudioStream")
			print("[音频加载] ResourceLoader 加载结果: ", audio_stream)
	
	if audio_stream == null:
		print("[音频加载] 无法加载音频文件，格式可能不支持: ", extension)
	
	return audio_stream

# 递归应用字体到所有 LineEdit 和 TextEdit 控件
func _apply_font_to_edit_controls(node: Node, font: Font):
	for child in node.get_children():
		if child is LineEdit:
			child.add_theme_font_override("font", font)
		elif child is TextEdit:
			child.add_theme_font_override("font", font)
		elif child is CodeEdit:
			child.add_theme_font_override("font", font)
		# 递归处理子节点
		if child.get_child_count() > 0:
			_apply_font_to_edit_controls(child, font)
