extends Control

var current_page: String = "global"
var capturing_for: Dictionary = {}

var tab_container: TabContainer
var shortcut_page_list: ItemList
var shortcut_action_list: VBoxContainer
var return_button: Button
var auto_save_toggle: CheckButton
var interval_slider: HSlider
var interval_label: Label

# 延迟校准控件
var audio_slider: HSlider
var audio_input: LineEdit
var judge_slider: HSlider
var judge_input: LineEdit
var _audio_updating: bool = false
var _judge_updating: bool = false

func _ready() -> void:
	_build_ui()
	
	return_button.pressed.connect(_on_return_pressed)
	shortcut_page_list.item_selected.connect(_on_page_selected)
	auto_save_toggle.toggled.connect(_on_auto_save_toggled)
	interval_slider.value_changed.connect(_on_interval_changed)
	
	_init_page_list()
	
	# 加载当前自动保存设置
	auto_save_toggle.button_pressed = Global.get_auto_save_enabled()
	var interval = Global.get_auto_save_interval()
	interval_slider.value = interval
	interval_label.text = "%d 分钟" % interval
	interval_slider.editable = auto_save_toggle.button_pressed

func _build_ui() -> void:
	# 返回按钮
	return_button = Button.new()
	return_button.text = "← 返回主菜单"
	return_button.position = Vector2(20, 20)
	return_button.custom_minimum_size = Vector2(200, 50)
	return_button.add_theme_font_size_override("font_size", 24)
	add_child(return_button)
	
	# TabContainer
	tab_container = TabContainer.new()
	tab_container.position = Vector2(20, 80)
	tab_container.size = Vector2(1880, 920)
	tab_container.add_theme_font_size_override("font_size", 20)
	add_child(tab_container)
	
	# === 快捷键 Tab ===
	var shortcuts_tab = Control.new()
	shortcuts_tab.name = "快捷键"
	tab_container.add_child(shortcuts_tab)
	
	shortcut_page_list = ItemList.new()
	shortcut_page_list.position = Vector2(10, 10)
	shortcut_page_list.size = Vector2(240, 850)
	shortcut_page_list.add_theme_font_size_override("font_size", 20)
	shortcuts_tab.add_child(shortcut_page_list)
	
	var action_list_container = Control.new()
	action_list_container.position = Vector2(260, 10)
	action_list_container.size = Vector2(1580, 850)
	shortcuts_tab.add_child(action_list_container)
	
	var action_scroll = ScrollContainer.new()
	action_scroll.size = Vector2(1580, 850)
	action_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_list_container.add_child(action_scroll)
	
	shortcut_action_list = VBoxContainer.new()
	shortcut_action_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shortcut_action_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shortcut_action_list.custom_minimum_size.x = 1500
	action_scroll.add_child(shortcut_action_list)
	
	# === 自动保存 Tab ===
	var autosave_tab = Control.new()
	autosave_tab.name = "自动保存"
	tab_container.add_child(autosave_tab)
	
	var as_title = Label.new()
	as_title.text = "自动保存设置"
	as_title.position = Vector2(50, 30)
	as_title.add_theme_font_size_override("font_size", 28)
	autosave_tab.add_child(as_title)
	
	var toggle_label = Label.new()
	toggle_label.text = "启用自动保存"
	toggle_label.position = Vector2(50, 100)
	toggle_label.add_theme_font_size_override("font_size", 22)
	toggle_label.custom_minimum_size = Vector2(200, 40)
	autosave_tab.add_child(toggle_label)
	
	auto_save_toggle = CheckButton.new()
	auto_save_toggle.position = Vector2(260, 100)
	auto_save_toggle.custom_minimum_size = Vector2(80, 40)
	autosave_tab.add_child(auto_save_toggle)
	
	var interval_desc = Label.new()
	interval_desc.text = "保存间隔（每 N 分钟自动保存一次 .autosave.rwc）"
	interval_desc.position = Vector2(50, 170)
	interval_desc.add_theme_font_size_override("font_size", 22)
	interval_desc.custom_minimum_size = Vector2(600, 40)
	autosave_tab.add_child(interval_desc)
	
	interval_slider = HSlider.new()
	interval_slider.position = Vector2(50, 230)
	interval_slider.size = Vector2(400, 40)
	interval_slider.min_value = 1.0
	interval_slider.max_value = 60.0
	interval_slider.step = 1.0
	autosave_tab.add_child(interval_slider)
	
	interval_label = Label.new()
	interval_label.text = "5 分钟"
	interval_label.position = Vector2(470, 230)
	interval_label.add_theme_font_size_override("font_size", 22)
	interval_label.custom_minimum_size = Vector2(120, 40)
	autosave_tab.add_child(interval_label)
	
	var as_note = Label.new()
	as_note.text = "自动保存文件将保存在原谱面同目录下，文件名为「原文件名.autosave.rwc」，不会覆盖原文件。"
	as_note.position = Vector2(50, 310)
	as_note.add_theme_font_size_override("font_size", 18)
	as_note.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	as_note.custom_minimum_size = Vector2(900, 40)
	autosave_tab.add_child(as_note)
	
	# === 延迟校准 Tab ===
	var cal_tab = Control.new()
	cal_tab.name = "延迟校准"
	tab_container.add_child(cal_tab)
	
	var cal_title = Label.new()
	cal_title.text = "延迟校准设置"
	cal_title.position = Vector2(50, 30)
	cal_title.add_theme_font_size_override("font_size", 28)
	cal_tab.add_child(cal_title)
	
	# ---- 音画偏移 ----
	var ao_label = Label.new()
	ao_label.text = "音画偏移（全局）"
	ao_label.position = Vector2(50, 90)
	ao_label.add_theme_font_size_override("font_size", 22)
	ao_label.custom_minimum_size = Vector2(300, 40)
	cal_tab.add_child(ao_label)
	
	var ao_desc = Label.new()
	ao_desc.text = "音频相对画面延迟播放的毫秒数（负值表示音频提前）"
	ao_desc.position = Vector2(50, 120)
	ao_desc.add_theme_font_size_override("font_size", 16)
	ao_desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	ao_desc.custom_minimum_size = Vector2(600, 30)
	cal_tab.add_child(ao_desc)
	
	# 音画偏移控制行
	var ao_row = _build_calibration_row(cal_tab, 170, "audio")
	audio_slider = ao_row["slider"]
	audio_input = ao_row["input"]
	audio_slider.min_value = -500.0
	audio_slider.max_value = 500.0
	audio_slider.step = 1.0
	audio_slider.value = Global.get_audio_offset_ms()
	audio_input.text = str(Global.get_audio_offset_ms())
	audio_slider.value_changed.connect(_on_audio_slider_changed)
	audio_input.text_submitted.connect(_on_audio_input_submitted)
	audio_input.focus_exited.connect(_on_audio_input_focus_exited)
	
	# ---- 判定偏移 ----
	var jo_label = Label.new()
	jo_label.text = "判定偏移（游玩页面）"
	jo_label.position = Vector2(50, 280)
	jo_label.add_theme_font_size_override("font_size", 22)
	jo_label.custom_minimum_size = Vector2(300, 40)
	cal_tab.add_child(jo_label)
	
	var jo_desc = Label.new()
	jo_desc.text = "在判定时间点上增加的毫秒数（正值=判定时间点延后，玩家需更晚击打）"
	jo_desc.position = Vector2(50, 310)
	jo_desc.add_theme_font_size_override("font_size", 16)
	jo_desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	jo_desc.custom_minimum_size = Vector2(600, 30)
	cal_tab.add_child(jo_desc)
	
	# 判定偏移控制行
	var jo_row = _build_calibration_row(cal_tab, 360, "judge")
	judge_slider = jo_row["slider"]
	judge_input = jo_row["input"]
	judge_slider.min_value = -500.0
	judge_slider.max_value = 500.0
	judge_slider.step = 1.0
	judge_slider.value = Global.get_judge_offset_ms()
	judge_input.text = str(Global.get_judge_offset_ms())
	judge_slider.value_changed.connect(_on_judge_slider_changed)
	judge_input.text_submitted.connect(_on_judge_input_submitted)
	judge_input.focus_exited.connect(_on_judge_input_focus_exited)

# 构建一行校准控件：[-10] [-1] [滑块] [输入框] [+1] [+10]
func _build_calibration_row(parent: Control, top_y: int, prefix: String) -> Dictionary:
	var slider: HSlider
	var input: LineEdit
	
	var adjust = func(delta: int):
		var val: int
		if prefix == "audio":
			val = clampi(int(audio_slider.value) + delta, -500, 500)
			audio_slider.value = val
		else:
			val = clampi(int(judge_slider.value) + delta, -500, 500)
			judge_slider.value = val
	
	var x = 50
	var btn_w = 50
	var btn_h = 40
	var gap = 5
	
	# m-10
	var btn_m10 = Button.new()
	btn_m10.text = "-10"
	btn_m10.position = Vector2(x, top_y)
	btn_m10.size = Vector2(btn_w, btn_h)
	btn_m10.pressed.connect(adjust.bind(-10))
	parent.add_child(btn_m10)
	x += btn_w + gap
	
	# m-1
	var btn_m1 = Button.new()
	btn_m1.text = "-1"
	btn_m1.position = Vector2(x, top_y)
	btn_m1.size = Vector2(btn_w, btn_h)
	btn_m1.pressed.connect(adjust.bind(-1))
	parent.add_child(btn_m1)
	x += btn_w + gap
	
	# slider
	slider = HSlider.new()
	slider.position = Vector2(x, top_y + 5)
	slider.size = Vector2(350, btn_h)
	parent.add_child(slider)
	x += 350 + gap
	
	# input
	input = LineEdit.new()
	input.position = Vector2(x, top_y)
	input.size = Vector2(90, btn_h)
	input.add_theme_font_size_override("font_size", 20)
	input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(input)
	x += 90 + gap
	
	# +1
	var btn_p1 = Button.new()
	btn_p1.text = "+1"
	btn_p1.position = Vector2(x, top_y)
	btn_p1.size = Vector2(btn_w, btn_h)
	btn_p1.pressed.connect(adjust.bind(1))
	parent.add_child(btn_p1)
	x += btn_w + gap
	
	# +10
	var btn_p10 = Button.new()
	btn_p10.text = "+10"
	btn_p10.position = Vector2(x, top_y)
	btn_p10.size = Vector2(btn_w, btn_h)
	btn_p10.pressed.connect(adjust.bind(10))
	parent.add_child(btn_p10)
	
	return {"slider": slider, "input": input}

# ========== 音画偏移回调 ==========
func _on_audio_slider_changed(value: float) -> void:
	if _audio_updating:
		return
	_audio_updating = true
	var val = int(value)
	Global.set_audio_offset_ms(val)
	audio_input.text = str(val)
	_audio_updating = false

func _on_audio_input_submitted(text: String) -> void:
	_apply_audio_input(text)

func _on_audio_input_focus_exited() -> void:
	_apply_audio_input(audio_input.text)

func _apply_audio_input(text: String) -> void:
	if _audio_updating:
		return
	_audio_updating = true
	var val = clampi(int(text), -500, 500)
	Global.set_audio_offset_ms(val)
	audio_slider.value = val
	audio_input.text = str(val)
	_audio_updating = false

# ========== 判定偏移回调 ==========
func _on_judge_slider_changed(value: float) -> void:
	if _judge_updating:
		return
	_judge_updating = true
	var val = int(value)
	Global.set_judge_offset_ms(val)
	judge_input.text = str(val)
	_judge_updating = false

func _on_judge_input_submitted(text: String) -> void:
	_apply_judge_input(text)

func _on_judge_input_focus_exited() -> void:
	_apply_judge_input(judge_input.text)

func _apply_judge_input(text: String) -> void:
	if _judge_updating:
		return
	_judge_updating = true
	var val = clampi(int(text), -500, 500)
	Global.set_judge_offset_ms(val)
	judge_slider.value = val
	judge_input.text = str(val)
	_judge_updating = false

# ========== 以下为原设置页面的快捷键和自动保存逻辑 ==========

func _init_page_list() -> void:
	var pages = Global.get_all_shortcut_pages()
	for p in pages:
		shortcut_page_list.add_item(p["label"])
	if pages.size() > 0:
		shortcut_page_list.select(0)
		_on_page_selected(0)

func _on_page_selected(index: int) -> void:
	if capturing_for:
		_cancel_capture()
	var pages = Global.get_all_shortcut_pages()
	if index < 0 or index >= pages.size():
		return
	current_page = pages[index]["id"]
	_refresh_shortcut_list()

func _refresh_shortcut_list() -> void:
	for child in shortcut_action_list.get_children():
		child.queue_free()
	
	var actions = Global.get_page_shortcut_actions(current_page)
	for act in actions:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size.y = 42
		
		var label = Label.new()
		label.text = act["label"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = 1.0
		label.add_theme_font_size_override("font_size", 20)
		
		var key_btn = Button.new()
		key_btn.text = act["display"]
		key_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key_btn.size_flags_stretch_ratio = 0.4
		key_btn.custom_minimum_size.x = 220
		key_btn.add_theme_font_size_override("font_size", 18)
		key_btn.toggle_mode = true
		key_btn.pressed.connect(_on_key_button_pressed.bind(key_btn, current_page, act["action"]))
		
		row.add_child(label)
		row.add_child(key_btn)
		shortcut_action_list.add_child(row)

func _on_key_button_pressed(btn: Button, page: String, action: String) -> void:
	if btn.button_pressed:
		for child in shortcut_action_list.get_children():
			if child is HBoxContainer:
				for c in child.get_children():
					if c is Button and c != btn:
						c.button_pressed = false
		btn.text = "按下新快捷键..."
		capturing_for = { "page": page, "action": action, "btn": btn }
	else:
		_cancel_capture()

func _cancel_capture() -> void:
	if capturing_for.is_empty():
		return
	var btn = capturing_for["btn"]
	if is_instance_valid(btn):
		btn.text = Global.get_shortcut_display(capturing_for["page"], capturing_for["action"])
		btn.button_pressed = false
	capturing_for = {}

func _input(event: InputEvent) -> void:
	if capturing_for.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var data = Global.event_to_shortcut_data(event)
		if data.is_empty():
			return
		
		var page = capturing_for["page"]
		var action = capturing_for["action"]
		var btn = capturing_for["btn"]
		
		var other_actions = Global.get_page_shortcut_actions(page)
		for other in other_actions:
			if other["action"] == action:
				continue
			var other_sc = Global.get_shortcut(page, other["action"])
			if other_sc["key"] == data["key"] \
				and other_sc["mod_ctrl"] == data["mod_ctrl"] \
				and other_sc["mod_shift"] == data["mod_shift"] \
				and other_sc["mod_alt"] == data["mod_alt"]:
				show_conflict_warning(other["label"])
				_cancel_capture()
				get_viewport().set_input_as_handled()
				return
		
		Global.set_shortcut(page, action, data["key"], data["mod_ctrl"], data["mod_shift"], data["mod_alt"])
		btn.text = Global.get_shortcut_display(page, action)
		btn.button_pressed = false
		capturing_for = {}
		get_viewport().set_input_as_handled()

func show_conflict_warning(other_label: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "快捷键冲突"
	dialog.dialog_text = "该快捷键已被「%s」使用，请选择其他按键。" % other_label
	dialog.min_size = Vector2(400, 150)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)

func _on_auto_save_toggled(enabled: bool) -> void:
	Global.set_auto_save_enabled(enabled)
	interval_slider.editable = enabled

func _on_interval_changed(value: float) -> void:
	var minutes = int(value)
	interval_label.text = "%d 分钟" % minutes
	Global.set_auto_save_interval(minutes)

func _on_return_pressed() -> void:
	get_tree().change_scene_to_file("res://scene/start_scene.tscn")
