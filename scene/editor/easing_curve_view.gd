extends Control
# 函数实际曲线示意图（事件详情对话框与缓动预设窗口共用）

var _provider: Callable = Callable()   # 求值回调：Callable(prog: float) -> float
var _ref_start: float = 0.0            # 参考起点值
var _ref_end: float = 0.0              # 参考终点值
var _samples: Array = []               # 采样值缓存（无效点存 NaN）

const SAMPLE_STEPS: int = 60


# 设置求值回调与区间参考值，并重绘
func setup(provider: Callable, ref_start: float, ref_end: float) -> void:
	_provider = provider
	_ref_start = ref_start
	_ref_end = ref_end
	refresh()


# 重新采样并重绘
func refresh() -> void:
	_samples.clear()
	if _provider.is_valid():
		for i in range(SAMPLE_STEPS + 1):
			var prog: float = float(i) / float(SAMPLE_STEPS)
			var value = _provider.call(prog)
			var vt: int = typeof(value)
			if vt != TYPE_FLOAT and vt != TYPE_INT:
				# 结果不是数值，记为无效点
				_samples.append(NAN)
				continue
			var fv: float = float(value)
			if not is_finite(fv):
				# 非有限数（NaN / Inf），记为无效点
				_samples.append(NAN)
				continue
			_samples.append(fv)
	else:
		for i in range(SAMPLE_STEPS + 1):
			_samples.append(NAN)
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	# 背景与边框
	draw_rect(Rect2(0, 0, w, h), Color(0.12, 0.12, 0.14, 0.9))
	draw_rect(Rect2(0, 0, w, h), Color(0.5, 0.5, 0.5, 0.6), false, 1.0)
	# 边距
	var left: float = 24.0
	var right: float = w - 10.0
	var top: float = 10.0
	var bottom: float = h - 24.0
	if right <= left or bottom <= top:
		return
	# 坐标轴（左竖线、底横线）
	draw_line(Vector2(left, top), Vector2(left, bottom), Color(0.6, 0.6, 0.6, 0.8))
	draw_line(Vector2(left, bottom), Vector2(right, bottom), Color(0.6, 0.6, 0.6, 0.8))
	# Y 轴自适应：统计有效采样值与参考值的极值
	var vmin: float = INF
	var vmax: float = -INF
	for v in _samples:
		if typeof(v) == TYPE_FLOAT and is_nan(v):
			continue
		var fv: float = float(v)
		if not is_finite(fv):
			continue
		vmin = minf(vmin, fv)
		vmax = maxf(vmax, fv)
	if not is_finite(vmin):
		vmin = 0.0
	if not is_finite(vmax):
		vmax = 0.0
	vmin = minf(vmin, minf(_ref_start, _ref_end))
	vmax = maxf(vmax, maxf(_ref_start, _ref_end))
	if vmax - vmin < 1e-6:
		# 范围过窄时向两侧扩展
		var center: float = (vmax + vmin) * 0.5
		vmin = center - 1.0
		vmax = center + 1.0
	# 值越大越靠上：value -> y
	var span: float = vmax - vmin
	var plot_h: float = bottom - top
	# 参考线（起点值、终点值）
	var y_ref_start: float = bottom - plot_h * ((_ref_start - vmin) / span)
	var y_ref_end: float = bottom - plot_h * ((_ref_end - vmin) / span)
	draw_line(Vector2(left, y_ref_start), Vector2(right, y_ref_start), Color(0.35, 0.35, 0.35, 0.7), 1.0)
	draw_line(Vector2(left, y_ref_end), Vector2(right, y_ref_end), Color(0.35, 0.35, 0.35, 0.7), 1.0)
	# 曲线折线：无效采样点处断开
	var prev: Vector2 = Vector2.ZERO
	var has_prev: bool = false
	var count: int = _samples.size()
	for i in range(count):
		var v = _samples[i]
		if typeof(v) == TYPE_FLOAT and is_nan(v):
			has_prev = false
			continue
		var fv: float = float(v)
		if not is_finite(fv):
			has_prev = false
			continue
		var t: float = float(i) / float(SAMPLE_STEPS)
		var x: float = left + (right - left) * t
		var y: float = bottom - plot_h * ((fv - vmin) / span)
		var cur: Vector2 = Vector2(x, y)
		if has_prev:
			draw_line(prev, cur, Color(0.25, 0.75, 1.0, 1.0), 2.0)
		prev = cur
		has_prev = true
	# 轴标签
	var font = ThemeDB.fallback_font
	# X 轴：进度 0 / 1
	draw_string(font, Vector2(left - 4, bottom + 14), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))
	draw_string(font, Vector2(right - 14, bottom + 14), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))
	# Y 轴：最大值（左上）/ 最小值（左下）
	draw_string(font, Vector2(2, top + 10), "%.2f" % vmax, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))
	draw_string(font, Vector2(2, bottom - 2), "%.2f" % vmin, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))
