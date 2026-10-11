extends ConfirmationDialog
# 缓动预设选择窗口：把 Robert Penner 缓动预设应用到当前持续事件
# 用法：var dlg = EasingPresetDialog.new(当前type, 当前start, 当前end, 应用回调)
#       add_child(dlg); dlg.popup_centered()
# apply_cb: Callable(new_type: String, new_start: float, new_end: float) -> void

const EasingPresets = preload("res://scene/editor/easing_presets.gd")
const EasingCurveView = preload("res://scene/editor/easing_curve_view.gd")

var _apply_cb: Callable = Callable()

# ---- 当前状态 ----
var _current_id: int = 2                 # 当前选中的预设编号（02-29）
var _fn_params: Dictionary = {}          # 函数内参数：key -> float
var _start: float = 0.0                  # 事件起始值
var _end: float = 1.0                    # 事件结束值
var _current_expr: String = ""           # 纯数学表达式（不含 y~ 前缀）

# ---- 控件引用 ----
var _list: ItemList
var _name_label: Label
var _expr_edit: TextEdit
var _params_grid: GridContainer
var _curve_view: Control

var _preset_ids: Array = []              # 列表索引 -> 预设编号
var _param_edits: Dictionary = {}        # 参数 key -> LineEdit

func _init(current_type: String, current_start: float, current_end: float, apply_cb: Callable) -> void:
	title = "缓动预设"
	ok_button_text = "确定"
	cancel_button_text = "取消"
	min_size = Vector2(980, 660)
	_apply_cb = apply_cb

	# 初始 start / end：取构造入参，无效（NaN）时兜底
	_start = current_start
	_end = current_end
	if is_nan(_start):
		_start = 0.0
	if is_nan(_end):
		_end = 1.0

	# 初始选中：按当前 type 反查，无匹配时回退到编号 02
	_current_id = EasingPresets.match_preset_id(current_type)
	if _current_id < 0:
		_current_id = 2
	_fn_params = EasingPresets.default_params(_current_id)

	_build_ui()
	_populate_list()

	confirmed.connect(_on_confirmed)
	canceled.connect(queue_free)

# ========== UI 构建 ==========
func _build_ui() -> void:
	var hbox = HBoxContainer.new()
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	add_child(hbox)

	# ---- 左栏：预设列表 ----
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(300, 0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("font_size", 18)
	_list.item_selected.connect(_on_preset_selected)
	hbox.add_child(_list)

	# ---- 右栏：详情 ----
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	right.add_child(_name_label)

	var desc = Label.new()
	desc.text = "对应表达式（只读）"
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	right.add_child(desc)

	_expr_edit = TextEdit.new()
	_expr_edit.custom_minimum_size = Vector2(560, 70)
	_expr_edit.editable = false
	_expr_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	if Global.mono_font:
		_expr_edit.add_theme_font_override("font", Global.mono_font)
	right.add_child(_expr_edit)

	# 参数区：始终两列（Label + LineEdit），行内容随预设动态重建
	_params_grid = GridContainer.new()
	_params_grid.columns = 2
	_params_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_params_grid)

	# 函数图像：放入普通 Control 占位，曲线控件自行设置 position / size
	var curve_holder = Control.new()
	curve_holder.custom_minimum_size = Vector2(560, 170)
	right.add_child(curve_holder)
	_curve_view = EasingCurveView.new()
	_curve_view.position = Vector2(0, 0)
	_curve_view.size = Vector2(560, 170)
	curve_holder.add_child(_curve_view)

	var hint = Label.new()
	hint.text = "表达式为只读，如需手动编辑请在事件详情中修改「缓动类型」。"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(hint)

# 填充列表并选中当前预设（select 不触发 item_selected，需手动初始化右栏）
func _populate_list() -> void:
	_preset_ids.clear()
	_list.clear()
	var selected_index: int = 0
	var presets: Array = EasingPresets.get_presets()
	for i in range(presets.size()):
		var id: int = int(presets[i]["id"])
		_preset_ids.append(id)
		_list.add_item(EasingPresets.display_name(id))
		if id == _current_id:
			selected_index = i
	_list.select(selected_index)
	_rebuild_param_rows()
	_refresh_all()

# ========== 参数区 ==========
# 重建参数行：始终包含「起始值 / 结束值」，再按预设追加函数内参数
func _rebuild_param_rows() -> void:
	for child in _params_grid.get_children():
		_params_grid.remove_child(child)
		child.queue_free()
	_param_edits.clear()
	_add_param_row("start", "起始值", _start)
	_add_param_row("end", "结束值", _end)
	for pd in EasingPresets.get_params(_current_id):
		var key: String = String(pd["key"])
		var value: float = float(_fn_params.get(key, pd["default"]))
		_add_param_row(key, String(pd["label"]), value)

func _add_param_row(key: String, label_text: String, value: float) -> void:
	var lbl = Label.new()
	lbl.text = label_text
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_params_grid.add_child(lbl)

	var le = LineEdit.new()
	le.custom_minimum_size = Vector2(220, 30)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text = str(value)
	le.text_changed.connect(func(t: String): _on_param_changed(key, t))
	_param_edits[key] = le
	_params_grid.add_child(le)

# 参数输入变化：仅合法数值才更新状态（无效输入忽略，不打断编辑）
func _on_param_changed(key: String, text: String) -> void:
	if not text.is_valid_float():
		return
	var v: float = text.to_float()
	if key == "start":
		_start = v
	elif key == "end":
		_end = v
	else:
		_fn_params[key] = v
	_refresh_all()

# ========== 预设切换与刷新 ==========
func _on_preset_selected(index: int) -> void:
	if index < 0 or index >= _preset_ids.size():
		return
	_current_id = int(_preset_ids[index])
	# 切换预设时用默认值重置函数内参数
	_fn_params = EasingPresets.default_params(_current_id)
	_rebuild_param_rows()
	_refresh_all()

# 重新生成表达式文本并刷新名称与曲线
func _refresh_all() -> void:
	_current_expr = EasingPresets.build_expression(_current_id, _fn_params)
	_expr_edit.text = "y~" + _current_expr
	_name_label.text = EasingPresets.display_name(_current_id)
	_refresh_curve()

# ========== 曲线：实际生效的值曲线 ==========
func _refresh_curve() -> void:
	var provider: Callable = _make_provider(_current_expr)
	_curve_view.setup(provider, _start, _end)

# 构造求值回调，与运行时 y~ 端点归一化语义一致：
#   value(prog) = start + (end - start) * (f(prog) - f0) / (f1 - f0)
# 表达式求值失败时返回 start（水平线）；f1≈f0 时退化为线性
func _make_provider(expr: String) -> Callable:
	var st: float = _start
	var en: float = _end
	# 与运行期一致：^ -> **，并替换 pi / tau 等常量
	var clean: String = Global.replace_expr_constants(expr.replace("^", "**"))
	var e = Expression.new()
	if e.parse(clean, ["x"]) != OK:
		return func(_prog: float) -> float:
			return st
	var r0 = e.execute([0.0])
	var r1 = e.execute([1.0])
	if not _ok_num(r0) or not _ok_num(r1):
		return func(_prog: float) -> float:
			return st
	var f0: float = float(r0)
	var f1: float = float(r1)
	var span: float = f1 - f0
	if abs(span) <= 1e-6:
		return func(prog: float) -> float:
			return st + (en - st) * prog
	return func(prog: float) -> float:
		var r = e.execute([prog])
		if not _ok_num(r):
			return st
		return st + (en - st) * (float(r) - f0) / span

# 数值有效性：类型为 float/int 且有限
func _ok_num(v) -> bool:
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return is_finite(float(v))
	return false

# ========== 确认 / 取消 ==========
func _on_confirmed() -> void:
	_apply_cb.call("y~" + _current_expr, _start, _end)
	queue_free()
