extends AcceptDialog
# 通用属性编辑对话框（Note / Effect / Shader 面板共用）
# 第一选项卡「属性」：表单字段，按 Enter 或点击其他位置（失去焦点）即确认保存
# 第二选项卡「JSON」：原 JSON 编辑，点击「应用 JSON」保存

const EasingCurveView = preload("res://scene/editor/easing_curve_view.gd")

var _field_defs: Array = []
var _get_display: Callable
var _apply_value: Callable
var _build_json: Callable
var _apply_json: Callable
var _curve_provider: Callable = Callable()   # 曲线求值回调：Callable(prog: float) -> float；有效时才显示曲线图
var _on_open_presets: Callable = Callable()  # 「选择缓动预设…」回调；有效时才显示该按钮

var _line_edits: Dictionary = {}
var _json_edit: TextEdit
var _curve_view: Control = null

func _init(title_str: String, field_defs: Array, get_display: Callable, apply_value: Callable, build_json: Callable, apply_json: Callable, curve_provider: Callable = Callable(), on_open_presets: Callable = Callable()) -> void:
	title = title_str
	ok_button_text = "关闭"
	_field_defs = field_defs
	_get_display = get_display
	_apply_value = apply_value
	_build_json = build_json
	_apply_json = apply_json
	_curve_provider = curve_provider
	_on_open_presets = on_open_presets
	# 曲线图占用额外高度，避免内容被压缩
	if _curve_provider.is_valid():
		min_size = Vector2(600, 760)
	else:
		min_size = Vector2(600, 560)
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

	# ---- 函数实际图像（仅在提供曲线回调时创建）----
	if _curve_provider.is_valid():
		var curve_title = Label.new()
		curve_title.text = "函数实际图像"
		curve_title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		prop_vbox.add_child(curve_title)

		_curve_view = EasingCurveView.new()
		_curve_view.custom_minimum_size = Vector2(560, 170)
		_curve_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prop_vbox.add_child(_curve_view)
		_refresh_curve()

	# ---- 缓动预设入口（仅在提供回调时创建）----
	if _on_open_presets.is_valid():
		var presets_btn = Button.new()
		presets_btn.text = "选择缓动预设…"
		presets_btn.pressed.connect(func(): _on_open_presets.call(self))
		prop_vbox.add_child(presets_btn)

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
	# 字段变化后同步刷新曲线图（曲线不存在时为空操作）
	_refresh_curve()

# 刷新字段显示与曲线图（供外部在数据被其它窗口修改后调用）
func refresh_all() -> void:
	_refresh_fields()

# 重新解析 start / end 参考值并刷新曲线图（无曲线图时为空操作）
func _refresh_curve() -> void:
	if _curve_view == null:
		return
	var ref_start: float = _resolve_ref_value("start", 0.0)
	var ref_end: float = _resolve_ref_value("end", 1.0)
	_curve_view.setup(_curve_provider, ref_start, ref_end)

# 从字段定义中查找 key 对应的字段，解析其当前显示值为 float；取不到或无效时返回 fallback
func _resolve_ref_value(key: String, fallback: float) -> float:
	for def in _field_defs:
		if str(def.get("key", "")) == key:
			var s: String = str(_get_display.call(key))
			if s.is_valid_float():
				return s.to_float()
			return fallback
	return fallback

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
