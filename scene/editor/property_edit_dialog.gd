extends AcceptDialog
# 通用属性编辑对话框（Note / Effect / Shader 面板共用）
# 第一选项卡「属性」：表单字段，按 Enter 或点击其他位置（失去焦点）即确认保存
# 第二选项卡「JSON」：原 JSON 编辑，点击「应用 JSON」保存

var _field_defs: Array = []
var _get_display: Callable
var _apply_value: Callable
var _build_json: Callable
var _apply_json: Callable

var _line_edits: Dictionary = {}
var _json_edit: TextEdit

func _init(title_str: String, field_defs: Array, get_display: Callable, apply_value: Callable, build_json: Callable, apply_json: Callable) -> void:
	title = title_str
	ok_button_text = "关闭"
	min_size = Vector2(600, 560)
	_field_defs = field_defs
	_get_display = get_display
	_apply_value = apply_value
	_build_json = build_json
	_apply_json = apply_json
	_build_ui()
	confirmed.connect(queue_free)
	canceled.connect(queue_free)

func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	add_child(vbox)

	var tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(580, 480)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)

	# ---- 选项卡 1：属性 ----
	var prop_vbox = VBoxContainer.new()
	prop_vbox.name = "属性"
	tabs.add_child(prop_vbox)

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prop_vbox.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for def in _field_defs:
		var key: String = def["key"]
		var lbl = Label.new()
		lbl.text = def["label"]
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(lbl)
		var le = LineEdit.new()
		le.custom_minimum_size = Vector2(260, 34)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text = str(_get_display.call(key))
		le.text_submitted.connect(func(_t: String): _commit_field(key))
		le.focus_exited.connect(func(): _commit_field(key))
		_line_edits[key] = le
		grid.add_child(le)

	var hint = Label.new()
	hint.text = "按 Enter 或点击其他位置即确认保存。"
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	prop_vbox.add_child(hint)

	# ---- 选项卡 2：JSON ----
	var json_vbox = VBoxContainer.new()
	json_vbox.name = "JSON"
	tabs.add_child(json_vbox)

	var json_hint = Label.new()
	json_hint.text = "编辑 JSON 后点击「应用 JSON」按钮保存。"
	json_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	json_vbox.add_child(json_hint)

	_json_edit = TextEdit.new()
	_json_edit.custom_minimum_size = Vector2(560, 400)
	_json_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_json_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	if Global.mono_font:
		_json_edit.add_theme_font_override("font", Global.mono_font)
	json_vbox.add_child(_json_edit)
	_json_edit.text = _build_json.call()

	var apply_btn = Button.new()
	apply_btn.text = "应用 JSON"
	apply_btn.pressed.connect(_on_apply_json_pressed)
	json_vbox.add_child(apply_btn)

	# 切换到 JSON 选项卡时刷新为当前最新数据
	tabs.tab_changed.connect(func(idx: int):
		if idx == 1:
			_json_edit.text = _build_json.call()
	)

func _commit_field(key: String) -> void:
	var le: LineEdit = _line_edits.get(key)
	if le == null:
		return
	var ok: bool = _apply_value.call(key, le.text)
	if ok:
		_refresh_fields()
	else:
		le.text = str(_get_display.call(key))

func _refresh_fields() -> void:
	for key in _line_edits:
		var le: LineEdit = _line_edits[key]
		le.text = str(_get_display.call(key))
		if le.has_focus():
			le.caret_column = le.text.length()

func _on_apply_json_pressed() -> void:
	var err: String = _apply_json.call(_json_edit.text)
	if err.is_empty():
		_json_edit.text = _build_json.call()
		_refresh_fields()
	else:
		var err_dialog = AcceptDialog.new()
		err_dialog.title = "JSON 错误"
		err_dialog.dialog_text = err
		add_child(err_dialog)
		err_dialog.popup_centered()
		err_dialog.confirmed.connect(err_dialog.queue_free)
		err_dialog.canceled.connect(err_dialog.queue_free)
