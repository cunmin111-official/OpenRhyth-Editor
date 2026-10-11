extends RefCounted
# 缓动预设表（Robert Penner 缓动函数 / Re:PhiEdit easingType 编号 02-29）
# 仅供编辑器使用；生成的表达式写入事件已有的 type 字段（加 y~ 前缀），不改变谱面文件格式
#
# 引擎约束（已实测，必须遵守）：
#   - Expression 不支持 ?: 三元运算符
#   - A if cond else B 语法可通过但语义错误（条件被忽略，恒返回 A），不可使用
#   - 布尔值不能直接参与算术；float(cond) 可用（返回 1.0 / 0.0）
#   - 因此分段函数统一用「指示函数 × 分段表达式」求和实现
# 生成结果为纯数学表达式（不带 y~ 前缀），^ 表示幂（运行时会被归一化为 **），表达式中可写 pi。

# Back 系列（20 / 21 / 23）的函数内参数
const _PARAMS_BACK: Array = [
	{"key": "c1", "label": "回弹系数 c1", "default": 1.70158, "min": 0.0, "max": 5.0, "step": 0.001}
]

# Elastic 系列（24 / 25）的函数内参数，period 默认 2π/3
const _PARAMS_ELASTIC: Array = [
	{"key": "amp", "label": "幅值 amp", "default": 1.0, "min": 0.1, "max": 5.0, "step": 0.05},
	{"key": "period", "label": "周期系数 period", "default": 2.0 * PI / 3.0, "min": 0.05, "max": 5.0, "step": 0.05}
]

# In Out Elastic（29）的函数内参数，period 默认 2π/4.5
const _PARAMS_ELASTIC_IO: Array = [
	{"key": "amp", "label": "幅值 amp", "default": 1.0, "min": 0.1, "max": 5.0, "step": 0.05},
	{"key": "period", "label": "周期系数 period", "default": 2.0 * PI / 4.5, "min": 0.05, "max": 5.0, "step": 0.05}
]


# 返回 28 项预设，按编号（02-29）升序
static func get_presets() -> Array:
	return [
		{"id": 2, "rpe": "Out Sine", "cn": "缓出·正弦", "params": []},
		{"id": 3, "rpe": "In Sine", "cn": "缓入·正弦", "params": []},
		{"id": 4, "rpe": "Out Quad", "cn": "缓出·二次", "params": []},
		{"id": 5, "rpe": "In Quad", "cn": "缓入·二次", "params": []},
		{"id": 6, "rpe": "In Out Sine", "cn": "缓入缓出·正弦", "params": []},
		{"id": 7, "rpe": "In Out Quad", "cn": "缓入缓出·二次", "params": []},
		{"id": 8, "rpe": "Out Cubic", "cn": "缓出·三次", "params": []},
		{"id": 9, "rpe": "In Cubic", "cn": "缓入·三次", "params": []},
		{"id": 10, "rpe": "Out Quart", "cn": "缓出·四次", "params": []},
		{"id": 11, "rpe": "In Quart", "cn": "缓入·四次", "params": []},
		{"id": 12, "rpe": "In Out Cubic", "cn": "缓入缓出·三次", "params": []},
		{"id": 13, "rpe": "In Out Quart", "cn": "缓入缓出·四次", "params": []},
		{"id": 14, "rpe": "Out Quint", "cn": "缓出·五次", "params": []},
		{"id": 15, "rpe": "In Quint", "cn": "缓入·五次", "params": []},
		{"id": 16, "rpe": "Out Expo", "cn": "缓出·指数", "params": []},
		{"id": 17, "rpe": "In Expo", "cn": "缓入·指数", "params": []},
		{"id": 18, "rpe": "Out Circ", "cn": "缓出·圆", "params": []},
		{"id": 19, "rpe": "In Circ", "cn": "缓入·圆", "params": []},
		{"id": 20, "rpe": "Out Back", "cn": "缓出·回弹", "params": _PARAMS_BACK},
		{"id": 21, "rpe": "In Back", "cn": "缓入·回弹", "params": _PARAMS_BACK},
		{"id": 22, "rpe": "In Out Circ", "cn": "缓入缓出·圆", "params": []},
		{"id": 23, "rpe": "In Out Back", "cn": "缓入缓出·回弹", "params": _PARAMS_BACK},
		{"id": 24, "rpe": "Out Elastic", "cn": "缓出·弹性", "params": _PARAMS_ELASTIC},
		{"id": 25, "rpe": "In Elastic", "cn": "缓入·弹性", "params": _PARAMS_ELASTIC},
		{"id": 26, "rpe": "Out Bounce", "cn": "缓出·弹跳", "params": []},
		{"id": 27, "rpe": "In Bounce", "cn": "缓入·弹跳", "params": []},
		{"id": 28, "rpe": "In Out Bounce", "cn": "缓入缓出·弹跳", "params": []},
		{"id": 29, "rpe": "In Out Elastic", "cn": "缓入缓出·弹性", "params": _PARAMS_ELASTIC_IO},
	]


# 返回指定预设的函数内参数定义数组；无参数或未找到返回 []
static func get_params(id: int) -> Array:
	for preset in get_presets():
		if int(preset["id"]) == id:
			return preset["params"]
	return []


# 返回指定预设的函数内参数默认值 {key: default}；未找到返回 {}
static func default_params(id: int) -> Dictionary:
	var out: Dictionary = {}
	for pd in get_params(id):
		out[pd["key"]] = pd["default"]
	return out


# 按参数生成纯数学表达式（不带 y~ 前缀）；params 缺某 key 时使用默认值
static func build_expression(id: int, params: Dictionary) -> String:
	var p: Dictionary = default_params(id)
	for k in params.keys():
		p[k] = float(params[k])

	# Back 系列常量（未使用也一并计算，成本可忽略）
	var c1f: float = 1.70158
	if p.has("c1"):
		c1f = float(p["c1"])
	var c1: String = _n(c1f)
	var c3: String = _n(c1f + 1.0)
	var c2: String = _n(c1f * 1.525)
	var c2p1: String = _n(c1f * 1.525 + 1.0)

	# Elastic 系列常量
	var amp: String = "1"
	if p.has("amp"):
		amp = _n(float(p["amp"]))
	var period: String = _n(2.0 * PI / 3.0)
	if p.has("period"):
		period = _n(float(p["period"]))

	match id:
		2:
			return "sin(x*pi/2)"
		3:
			return "1-cos(x*pi/2)"
		4:
			return "1-(1-x)^2"
		5:
			return "x^2"
		6:
			return "(1-cos(pi*x))/2"
		7:
			return _piecewise(0.5, "2*x^2", "1-(-2*x+2)^2/2")
		8:
			return "1-(1-x)^3"
		9:
			return "x^3"
		10:
			return "1-(1-x)^4"
		11:
			return "x^4"
		12:
			return _piecewise(0.5, "4*x^3", "1-(-2*x+2)^3/2")
		13:
			return _piecewise(0.5, "8*x^4", "1-(-2*x+2)^4/2")
		14:
			return "1-(1-x)^5"
		15:
			return "x^5"
		16:
			return "1-2^(-10*x)"
		17:
			return "2^(10*x-10)"
		18:
			return "sqrt(1-(x-1)^2)"
		19:
			return "1-sqrt(1-x^2)"
		20:
			# 1 + c3*(x-1)^3 + c1*(x-1)^2，c3 = c1 + 1
			return "1+" + c3 + "*(x-1)^3+" + c1 + "*(x-1)^2"
		21:
			# c3*x^3 - c1*x^2，c3 = c1 + 1
			return c3 + "*x^3-" + c1 + "*x^2"
		22:
			# 注意：sqrt 的被减数在「非激活段」会取到负值（如 x>0.5 时 1-(2x)^2 < 0），
			# sqrt(负数) 得到 nan，而 nan*float(条件) 仍为 nan，会污染整条曲线；
			# 因此用 abs 包裹根号内被减数（激活段内该值本就 >= 0，取值不受影响）。
			return _piecewise(0.5, "(1-sqrt(abs(1-(2*x)^2)))/2", "(sqrt(abs(1-(-2*x+2)^2))+1)/2")
		23:
			# c2 = c1 * 1.525；P1 = ((2x)^2*((c2+1)*2x - c2))/2
			#                  P2 = ((2x-2)^2*((c2+1)*(2x-2) + c2) + 2)/2
			var p1_23: String = "((2*x)^2*((" + c2p1 + ")*2*x-" + c2 + "))/2"
			var p2_23: String = "((2*x-2)^2*((" + c2p1 + ")*(2*x-2)+" + c2 + ")+2)/2"
			return _piecewise(0.5, p1_23, p2_23)
		24:
			return amp + "*2^(-10*x)*sin((x*10-0.75)*" + period + ")+1"
		25:
			return "-" + amp + "*2^(10*x-10)*sin((10*x-10.75)*" + period + ")"
		26:
			return _bounce_expr("x")
		27:
			return "1-" + _bounce_expr("(1-x)")
		28:
			return _piecewise(0.5, "(1-" + _bounce_expr("(1-2*x)") + ")/2", "(1+" + _bounce_expr("(2*x-1)") + ")/2")
		29:
			var p1_29: String = "-(" + amp + "*2^(20*x-10)*sin((20*x-11.125)*" + period + "))/2"
			var p2_29: String = "(" + amp + "*2^(-20*x+10)*sin((20*x-11.125)*" + period + "))/2+1"
			return _piecewise(0.5, p1_29, p2_29)
	return ""


# 用当前事件的 type 字符串反查预设编号：去掉 y= / y~ / y: 前缀与所有空白后，
# 与「默认参数生成的表达式（同样去空白）」逐项比较；命中返回编号，无匹配返回 -1
static func match_preset_id(type_str: String) -> int:
	var s: String = _strip_ws(_strip_prefix(type_str))
	if s == "":
		return -1
	for preset in get_presets():
		var id: int = int(preset["id"])
		var gen: String = _strip_ws(build_expression(id, default_params(id)))
		if gen == s:
			return id
	return -1


# 返回形如 "02 缓出·正弦 Out Sine" 的展示名（两位编号，不足补 0）
static func display_name(id: int) -> String:
	for preset in get_presets():
		if int(preset["id"]) == id:
			return "%02d %s %s" % [id, preset["cn"], preset["rpe"]]
	return ""


# 分段模板：段表达式 × 指示函数求和。每段用括号包裹自身，
# 避免 P2 以减号开头（如 1-(...)/2）时因运算符优先级写成 段1 + 1 - 段2。
static func _piecewise(threshold: float, p1: String, p2: String) -> String:
	var t: String = _n(threshold)
	return "(" + p1 + ")*float(x<" + t + ")+(" + p2 + ")*float(" + t + "<=x)"


# 弹跳 4 段表达式 B(u)，u 为参数表达式字符串（如 x、(1-x)、(1-2*x)、(2*x-1)）。
# 返回带最外层括号的完整表达式，便于安全代入。
static func _bounce_expr(u: String) -> String:
	var n1: String = _n(7.5625)
	var d1: float = 2.75
	var t1: String = _n(1.0 / d1)
	var t2: String = _n(2.0 / d1)
	var t3: String = _n(2.5 / d1)
	var k1: String = _n(1.5 / d1)
	var k2: String = _n(2.25 / d1)
	var k3: String = _n(2.625 / d1)
	var b2: String = _n(0.75)
	var b3: String = _n(0.9375)
	var b4: String = _n(0.984375)
	var seg1: String = n1 + "*(" + u + ")^2*float(" + u + "<" + t1 + ")"
	var seg2: String = "(" + n1 + "*(" + u + "-" + k1 + ")^2+" + b2 + ")*float(" + t1 + "<=" + u + ")*float(" + u + "<" + t2 + ")"
	var seg3: String = "(" + n1 + "*(" + u + "-" + k2 + ")^2+" + b3 + ")*float(" + t2 + "<=" + u + ")*float(" + u + "<" + t3 + ")"
	var seg4: String = "(" + n1 + "*(" + u + "-" + k3 + ")^2+" + b4 + ")*float(" + t3 + "<=" + u + ")"
	return "(" + seg1 + "+" + seg2 + "+" + seg3 + "+" + seg4 + ")"


# 去掉 y= / y~ / y: 前缀
static func _strip_prefix(s: String) -> String:
	var t: String = s.strip_edges()
	if t.begins_with("y~") or t.begins_with("y=") or t.begins_with("y:"):
		return t.substr(2)
	return t


# 去掉所有空白字符（空格 / 制表 / 换行 / 回车）
static func _strip_ws(s: String) -> String:
	var out: String = ""
	for i in range(s.length()):
		var c: String = s[i]
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			continue
		out += c
	return out


# 数值格式化：String.num(v, 12) 后去掉末尾多余 0 与孤立小数点（1.0 -> "1"，1.70158 -> "1.70158"）
static func _n(v: float) -> String:
	var s: String = String.num(v, 12)
	if s.contains("."):
		while s.length() > 0 and s.ends_with("0"):
			s = s.substr(0, s.length() - 1)
		if s.ends_with("."):
			s = s.substr(0, s.length() - 1)
	return s
