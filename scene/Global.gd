extends Node
# 全局变量
# 文件路径
var selected_rwc_path: String = ""
var selected_music_path: String = ""
var preview_time: float = 0.0
# 编辑器的滚动位置（切换面板/判线时保持，回主页时重置）
var editor_scroll_position: float = 0.0
# 进入预览前的编辑器滚动位置（预览播完后回退用）
var editor_pre_preview_scroll: float = 0.0
# 等宽字体（用于 JSON 编辑器等）
var mono_font: Font = null

# ========== 设置管理 ==========
var settings: Dictionary = {}

const SETTINGS_PATH: String = "res://settings.json"

# 快捷键默认配置：页面 → 操作名 → {label, key, mod_ctrl, mod_shift, mod_alt}
const DEFAULT_SHORTCUTS: Dictionary = {
	"global": {
		"toggle_fullscreen": {"label": "切换全屏", "key": KEY_F11, "mod_ctrl": false, "mod_shift": false, "mod_alt": false}
	},
	"editor": {
		"save": {"label": "保存谱面", "key": KEY_S, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"fix_integers": {"label": "修复整数并保存", "key": KEY_F, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"start_preview": {"label": "开始/停止预览播放", "key": KEY_SPACE, "mod_ctrl": false, "mod_shift": false, "mod_alt": false},
		"increase_subdivision": {"label": "增大节拍细分", "key": KEY_UP, "mod_ctrl": false, "mod_shift": false, "mod_alt": false},
		"decrease_subdivision": {"label": "减小节拍细分", "key": KEY_DOWN, "mod_ctrl": false, "mod_shift": false, "mod_alt": false},
		"increase_pixels": {"label": "增大像素密度", "key": KEY_UP, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"decrease_pixels": {"label": "减小像素密度", "key": KEY_DOWN, "mod_ctrl": true, "mod_shift": false, "mod_alt": false}
	},
	"notes_edit": {
		"copy_selected": {"label": "复制选中音符", "key": KEY_C, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"paste_clipboard": {"label": "粘贴音符", "key": KEY_V, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"quantize_selected": {"label": "量化选中音符", "key": KEY_U, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"delete_selected": {"label": "删除选中音符", "key": KEY_DELETE, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"move_up": {"label": "上移选中音符", "key": KEY_UP, "mod_ctrl": true, "mod_shift": true, "mod_alt": false},
		"move_down": {"label": "下移选中音符", "key": KEY_DOWN, "mod_ctrl": true, "mod_shift": true, "mod_alt": false}
	},
	"effects_edit": {
		"copy_selected": {"label": "复制选中动效", "key": KEY_C, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"paste_clipboard": {"label": "粘贴动效", "key": KEY_V, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"quantize_selected": {"label": "量化选中动效", "key": KEY_U, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"continuous_mode": {"label": "持续动效放置模式", "key": KEY_0, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"instant_mode": {"label": "瞬时动效放置模式", "key": KEY_1, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"browse_mode": {"label": "浏览模式", "key": KEY_SPACE, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"delete_selected": {"label": "删除选中动效", "key": KEY_DELETE, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"shift_up": {"label": "上移动效", "key": KEY_UP, "mod_ctrl": true, "mod_shift": true, "mod_alt": false},
		"shift_down": {"label": "下移动效", "key": KEY_DOWN, "mod_ctrl": true, "mod_shift": true, "mod_alt": false},
		"fix_format": {"label": "修复动效格式", "key": KEY_F, "mod_ctrl": true, "mod_shift": true, "mod_alt": false}
	},
	"shader_edit": {
		"copy_selected": {"label": "复制选中Shader事件", "key": KEY_C, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"paste_clipboard": {"label": "粘贴Shader事件", "key": KEY_V, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"quantize_selected": {"label": "量化选中Shader事件", "key": KEY_U, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"continuous_mode": {"label": "持续Shader放置模式", "key": KEY_0, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"instant_mode": {"label": "瞬时Shader放置模式", "key": KEY_1, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"browse_mode": {"label": "浏览模式", "key": KEY_SPACE, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"delete_selected": {"label": "删除选中Shader事件", "key": KEY_DELETE, "mod_ctrl": true, "mod_shift": false, "mod_alt": false},
		"shift_up": {"label": "上移Shader事件", "key": KEY_UP, "mod_ctrl": true, "mod_shift": true, "mod_alt": false},
		"shift_down": {"label": "下移Shader事件", "key": KEY_DOWN, "mod_ctrl": true, "mod_shift": true, "mod_alt": false}
	},
	"preview": {
		"play_pause": {"label": "播放/暂停", "key": KEY_SPACE, "mod_ctrl": false, "mod_shift": false, "mod_alt": false},
		"return_editor": {"label": "返回编辑器", "key": KEY_ESCAPE, "mod_ctrl": false, "mod_shift": false, "mod_alt": false}
	},
	"play": {
		"return_menu": {"label": "返回主菜单", "key": KEY_ESCAPE, "mod_ctrl": false, "mod_shift": false, "mod_alt": false}
	}
}

# 按键名称 → KEY_* 映射（用于显示）
const KEY_DISPLAY_NAMES: Dictionary = {
	KEY_SPACE: "Space",
	KEY_ESCAPE: "Esc",
	KEY_ENTER: "Enter",
	KEY_TAB: "Tab",
	KEY_BACKSPACE: "Backspace",
	KEY_DELETE: "Delete",
	KEY_INSERT: "Insert",
	KEY_HOME: "Home",
	KEY_END: "End",
	KEY_PAGEUP: "PageUp",
	KEY_PAGEDOWN: "PageDown",
	KEY_UP: "↑",
	KEY_DOWN: "↓",
	KEY_LEFT: "←",
	KEY_RIGHT: "→",
	KEY_F1: "F1", KEY_F2: "F2", KEY_F3: "F3", KEY_F4: "F4",
	KEY_F5: "F5", KEY_F6: "F6", KEY_F7: "F7", KEY_F8: "F8",
	KEY_F9: "F9", KEY_F10: "F10", KEY_F11: "F11", KEY_F12: "F12",
}

func load_settings() -> void:
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file:
		var json = JSON.new()
		var err = json.parse(file.get_as_text())
		file.close()
		if err == OK and typeof(json.data) == TYPE_DICTIONARY:
			settings = json.data
		else:
			settings = {}
	else:
		# 文件不存在，使用默认设置
		settings = {}
		print("[设置] settings.json 不存在，使用默认设置")
	# 确保所有默认值存在，并写入文件（自动创建/补全）
	_ensure_defaults()
	save_settings()

func save_settings() -> void:
	_ensure_defaults()
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))
		file.close()

func _ensure_defaults() -> void:
	if not settings.has("shortcuts"):
		settings["shortcuts"] = {}
	if not settings.has("auto_save"):
		settings["auto_save"] = {"enabled": false, "interval_minutes": 5}
	if not settings.has("calibration"):
		settings["calibration"] = {"audio_offset_ms": 0, "judge_offset_ms": 0}
	if not settings.has("play"):
		settings["play"] = {}
	if not settings["play"].has("score_display_mode"):
		settings["play"]["score_display_mode"] = "accumulate"
	if not settings["play"].has("fc_ap_indicator"):
		settings["play"]["fc_ap_indicator"] = true
	if not settings["play"].has("note_size"):
		settings["play"]["note_size"] = 1.0
	if not settings["play"].has("judge_effect_mode"):
		settings["play"]["judge_effect_mode"] = "frame"
	if not settings["play"].has("judge_effect_curve"):
		settings["play"]["judge_effect_curve"] = {"start": 0.8, "peak": 1.4, "peak_time": 0.3, "end": 0.5}
	if not settings["play"].has("judge_effect_fade_in_ms"):
		settings["play"]["judge_effect_fade_in_ms"] = 50
	if not settings.has("editor"):
		settings["editor"] = {}
	if not settings["editor"].has("subdivision"):
		settings["editor"]["subdivision"] = 1
	if not settings["editor"].has("pixels_per_second"):
		settings["editor"]["pixels_per_second"] = 500
	var sc = settings["shortcuts"]
	for page_name in DEFAULT_SHORTCUTS:
		if not sc.has(page_name):
			sc[page_name] = {}
		for action_name in DEFAULT_SHORTCUTS[page_name]:
			if not sc[page_name].has(action_name):
				var def_action = DEFAULT_SHORTCUTS[page_name][action_name]
				sc[page_name][action_name] = {
					"key": def_action["key"],
					"mod_ctrl": def_action["mod_ctrl"],
					"mod_shift": def_action["mod_shift"],
					"mod_alt": def_action["mod_alt"]
				}

func get_shortcut(page: String, action: String) -> Dictionary:
	var sc = settings.get("shortcuts", {})
	var pg = sc.get(page, {})
	var act = pg.get(action, {})
	if act.is_empty():
		# 回退到默认
		var def_page = DEFAULT_SHORTCUTS.get(page, {})
		var def_act = def_page.get(action, {})
		if def_act.is_empty():
			return {"key": 0, "mod_ctrl": false, "mod_shift": false, "mod_alt": false}
		return {"key": def_act["key"], "mod_ctrl": def_act["mod_ctrl"], "mod_shift": def_act["mod_shift"], "mod_alt": def_act["mod_alt"]}
	# 确保所有字段存在
	return {
		"key": act.get("key", 0),
		"mod_ctrl": act.get("mod_ctrl", false),
		"mod_shift": act.get("mod_shift", false),
		"mod_alt": act.get("mod_alt", false)
	}

func set_shortcut(page: String, action: String, keycode: int, ctrl: bool, shift: bool, alt: bool) -> void:
	if not settings.has("shortcuts"):
		settings["shortcuts"] = {}
	if not settings["shortcuts"].has(page):
		settings["shortcuts"][page] = {}
	settings["shortcuts"][page][action] = {
		"key": keycode,
		"mod_ctrl": ctrl,
		"mod_shift": shift,
		"mod_alt": alt
	}
	save_settings()

func get_auto_save_enabled() -> bool:
	return settings.get("auto_save", {}).get("enabled", false)

func set_auto_save_enabled(enabled: bool) -> void:
	if not settings.has("auto_save"):
		settings["auto_save"] = {"enabled": false, "interval_minutes": 5}
	settings["auto_save"]["enabled"] = enabled
	save_settings()

func get_auto_save_interval() -> int:
	return settings.get("auto_save", {}).get("interval_minutes", 5)

func set_auto_save_interval(minutes: int) -> void:
	if not settings.has("auto_save"):
		settings["auto_save"] = {"enabled": false, "interval_minutes": 5}
	settings["auto_save"]["interval_minutes"] = clampi(minutes, 1, 60)
	save_settings()

# ========== 编辑器偏好设置 ==========
func get_editor_subdivision() -> int:
	return settings.get("editor", {}).get("subdivision", 1)

func set_editor_subdivision(val: int) -> void:
	if not settings.has("editor"):
		settings["editor"] = {}
	settings["editor"]["subdivision"] = clampi(val, 1, 32)
	save_settings()

func get_editor_pixels_per_second() -> float:
	return settings.get("editor", {}).get("pixels_per_second", 500.0)

func set_editor_pixels_per_second(val: float) -> void:
	if not settings.has("editor"):
		settings["editor"] = {}
	settings["editor"]["pixels_per_second"] = clampf(val, 50.0, 3000.0)
	save_settings()

# ========== 延迟校准 ==========
func get_audio_offset_ms() -> int:
	return settings.get("calibration", {}).get("audio_offset_ms", 0)

func set_audio_offset_ms(val: int) -> void:
	if not settings.has("calibration"):
		settings["calibration"] = {}
	settings["calibration"]["audio_offset_ms"] = clampi(val, -500, 500)
	save_settings()

func get_judge_offset_ms() -> int:
	return settings.get("calibration", {}).get("judge_offset_ms", 0)

func set_judge_offset_ms(val: int) -> void:
	if not settings.has("calibration"):
		settings["calibration"] = {}
	settings["calibration"]["judge_offset_ms"] = clampi(val, -500, 500)
	save_settings()

# ========== 游玩设置 ==========
func get_score_display_mode() -> String:
	return settings.get("play", {}).get("score_display_mode", "accumulate")

func set_score_display_mode(mode: String) -> void:
	if not settings.has("play"):
		settings["play"] = {}
	settings["play"]["score_display_mode"] = mode
	save_settings()

func get_fc_ap_indicator() -> bool:
	return settings.get("play", {}).get("fc_ap_indicator", true)

func set_fc_ap_indicator(enabled: bool) -> void:
	if not settings.has("play"):
		settings["play"] = {}
	settings["play"]["fc_ap_indicator"] = enabled
	save_settings()

func get_note_size() -> float:
	# 通用倍数缩放，默认 1.0（1 倍）
	return settings.get("play", {}).get("note_size", 1.0)

func set_note_size(val: float) -> void:
	if not settings.has("play"):
		settings["play"] = {}
	settings["play"]["note_size"] = clampf(val, 0.1, 5.0)
	save_settings()

# 各类型音符的基础尺寸（用户可见值，默认 1.0）
# 内部乘以 PIXEL_SIZE_SCALE 转换为 Sprite3D 的 pixel_size
const NOTE_TYPES := ["tap", "drag", "hold_body", "hold_head"]
const PIXEL_SIZE_SCALE: float = 0.05
const DEFAULT_TYPE_SIZE: float = 1.0

func get_note_type_size(type_name: String) -> float:
	# 返回类型的基础尺寸（用户可见值）
	if type_name not in NOTE_TYPES:
		return DEFAULT_TYPE_SIZE
	var sizes = settings.get("play", {}).get("note_type_sizes", {})
	return sizes.get(type_name, DEFAULT_TYPE_SIZE)

func set_note_type_size(type_name: String, val: float) -> void:
	if type_name not in NOTE_TYPES:
		return
	if not settings.has("play"):
		settings["play"] = {}
	if not settings["play"].has("note_type_sizes"):
		settings["play"]["note_type_sizes"] = {}
	settings["play"]["note_type_sizes"][type_name] = clampf(val, 0.1, 10.0)
	save_settings()

func get_effective_note_type_size(type_name: String) -> float:
	# 有效 pixel_size = 通用倍数 * 类型基础尺寸 * 缩放系数
	return get_note_size() * get_note_type_size(type_name) * PIXEL_SIZE_SCALE

# ========== 判定特效设置 ==========
# 分级颜色映射（miss 不显示）
const JUDGE_GRADE_COLORS: Dictionary = {
	"perfect1": Color("#1685A9"),
	"perfect": Color("#197855"),
	"good": Color("#D12920"),
}

# 特效模式："frame" 逐帧动画 / "original" 原动画
func get_judge_effect_mode() -> String:
	return settings.get("play", {}).get("judge_effect_mode", "frame")

func set_judge_effect_mode(mode: String) -> void:
	if mode not in ["frame", "original"]:
		return
	if not settings.has("play"):
		settings["play"] = {}
	settings["play"]["judge_effect_mode"] = mode
	save_settings()

func get_judge_effect_curve() -> Dictionary:
	return settings.get("play", {}).get("judge_effect_curve", {"start": 0.8, "peak": 1.4, "peak_time": 0.3, "end": 0.5})

func set_judge_effect_curve(val: Dictionary) -> void:
	if not settings.has("play"):
		settings["play"] = {}
	settings["play"]["judge_effect_curve"] = {
		"start": clampf(float(val.get("start", 0.8)), 0.1, 3.0),
		"peak": clampf(float(val.get("peak", 1.4)), 0.1, 3.0),
		"peak_time": clampf(float(val.get("peak_time", 0.3)), 0.0, 1.0),
		"end": clampf(float(val.get("end", 0.5)), 0.1, 3.0),
	}
	save_settings()

# Hold 判定特效渐显时长（毫秒，默认 50ms）
func get_judge_effect_fade_in_ms() -> int:
	return int(settings.get("play", {}).get("judge_effect_fade_in_ms", 50))

func set_judge_effect_fade_in_ms(ms: int) -> void:
	if not settings.has("play"):
		settings["play"] = {}
	settings["play"]["judge_effect_fade_in_ms"] = clampi(ms, 0, 1000)
	save_settings()

# 计算大小曲线在归一化时间 t 处的倍率（静态，play/preview/设置预览共用）
static func eval_scale_curve(curve: Dictionary, t: float) -> float:
	var start = float(curve.get("start", 0.8))
	var peak = float(curve.get("peak", 1.4))
	var peak_time = clampf(float(curve.get("peak_time", 0.3)), 0.0, 1.0)
	var end = float(curve.get("end", 0.5))
	t = clampf(t, 0.0, 1.0)
	if peak_time <= 0.0:
		return peak
	if t <= peak_time:
		return lerpf(start, peak, t / peak_time)
	var denom = 1.0 - peak_time
	if denom <= 0.0:
		return peak
	return lerpf(peak, end, (t - peak_time) / denom)

# FC/AP 指示器状态计算（静态函数，play 和 preview 共享）
# 返回值：{color: Color, combo_text: String}
static func calc_fc_ap_status(perfect1_cnt: int, perfect_cnt: int, good_cnt: int, miss_cnt: int) -> Dictionary:
	var total = perfect1_cnt + perfect_cnt + good_cnt + miss_cnt
	# 条件1：无判定或全 perfect1
	if total == 0 or (perfect1_cnt == total):
		return {"color": Color(0.086, 0.522, 0.663), "combo_text": "无双"}
	# 条件2：全 perfect1 + perfect（无 good/miss）
	if miss_cnt == 0 and good_cnt == 0:
		return {"color": Color(0.098, 0.757, 0.557), "combo_text": "宗师"}
	# 条件3：无 miss
	if miss_cnt == 0:
		return {"color": Color(0.820, 0.161, 0.125), "combo_text": "豪侠"}
	# 条件4：有 miss
	return {"color": Color(0.0, 0.0, 0.0), "combo_text": "连击"}

# 检查快捷键是否匹配
static func is_shortcut_match(event: InputEvent, page: String, action: String) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	# 从 Global 实例读取配置（通过 scene tree）
	var global = null
	if Engine.get_main_loop():
		global = Engine.get_main_loop().root.get_node_or_null("/root/Global")
	if global == null:
		return false
	var sc = global.get_shortcut(page, action)
	if sc["key"] == 0:
		return false
	var ev: InputEventKey = event
	return ev.keycode == sc["key"] \
		and ev.ctrl_pressed == sc["mod_ctrl"] \
		and ev.shift_pressed == sc["mod_shift"] \
		and ev.alt_pressed == sc["mod_alt"]

# 获取快捷键的显示文本
static func get_shortcut_display(page: String, action: String) -> String:
	var global = null
	if Engine.get_main_loop():
		global = Engine.get_main_loop().root.get_node_or_null("/root/Global")
	if global == null:
		return ""
	var sc = global.get_shortcut(page, action)
	if sc["key"] == 0:
		return "无"
	var parts: Array = []
	if sc["mod_ctrl"]:
		parts.append("Ctrl")
	if sc["mod_alt"]:
		parts.append("Alt")
	if sc["mod_shift"]:
		parts.append("Shift")
	var key_name = _keycode_to_name(sc["key"])
	parts.append(key_name)
	return "+".join(parts)

# 将 Godot keycode 转为可读名称（避免 char() 对非 ASCII keycode 产生乱码）
static func _keycode_to_name(keycode: int) -> String:
	var name = KEY_DISPLAY_NAMES.get(keycode)
	if name != null:
		return name
	# ASCII 可打印范围（32-126）：空格、数字、字母、标点
	if keycode >= 32 and keycode <= 126:
		return char(keycode)
	# 兜底：显示 keycode 数字
	return "Key(%d)" % keycode

# 获取某个页面的所有操作的快捷键信息
static func get_page_shortcut_actions(page: String) -> Array:
	var result: Array = []
	var def_page = DEFAULT_SHORTCUTS.get(page, {})
	for action_name in def_page:
		var display = get_shortcut_display(page, action_name)
		result.append({
			"action": action_name,
			"label": def_page[action_name]["label"],
			"display": display
		})
	result.sort_custom(func(a, b): return a["label"] < b["label"])
	return result

# 获取所有页面列表
static func get_all_shortcut_pages() -> Array:
	var pages: Array = []
	for page_name in DEFAULT_SHORTCUTS:
		var label = page_name
		match page_name:
			"global": label = "全局"
			"editor": label = "编辑器"
			"notes_edit": label = "音符编辑"
			"effects_edit": label = "动效编辑"
			"shader_edit": label = "Shader编辑"
			"preview": label = "预览"
			"play": label = "游玩"
		pages.append({"id": page_name, "label": label})
	return pages

# 按键事件转存储格式（用于设置快捷键时抓取按键）
static func event_to_shortcut_data(event: InputEvent) -> Dictionary:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return {}
	var ev: InputEventKey = event
	# 不捕获纯修饰键
	if ev.keycode in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
		return {}
	return {
		"key": ev.keycode,
		"mod_ctrl": ev.ctrl_pressed,
		"mod_shift": ev.shift_pressed,
		"mod_alt": ev.alt_pressed
	}

# ========== 表达式常量替换 ==========
# Expression 不内置 pi/tau 常量（会被当作未知标识符导致求值静默失败），
# 求值前需将它们替换为数值字面量。按标识符整词替换，避免误伤其他名字。
static func replace_expr_constants(s: String) -> String:
	var out: String = ""
	var i: int = 0
	var n: int = s.length()
	while i < n:
		var c: String = s[i]
		var is_letter: bool = (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"
		if is_letter:
			var j: int = i
			while j < n:
				var cj: String = s[j]
				if (cj >= "a" and cj <= "z") or (cj >= "A" and cj <= "Z") or (cj >= "0" and cj <= "9") or cj == "_":
					j += 1
				else:
					break
			var word: String = s.substr(i, j - i)
			match word:
				"pi", "PI":
					out += "(3.14159265358979323846)"
				"tau", "TAU":
					out += "(6.28318530717958647692)"
				_:
					out += word
			i = j
		else:
			out += c
			i += 1
	return out

# ========== BPM 缓存工具（静态函数，所有文件共享） ==========
# 构建 BPM 分段缓存：返回有序数组，每段包含 {start_beat, start_time, bpm, end_beat, end_time}
static func build_bpm_cache(bpm_list: Array, offset_ms: int) -> Array:
	var cache: Array = []
	if bpm_list.is_empty():
		return cache
	var offset_sec = offset_ms / 1000.0
	var acc_time = 0.0
	for i in range(bpm_list.size()):
		var entry = bpm_list[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var start_beat = _fraction_to_beat(entry.get("startTime", [0, 0, 1]))
		var bpm = entry.get("bpm", 120.0)
		var end_beat = INF
		var end_time = INF
		if i + 1 < bpm_list.size():
			var next = bpm_list[i + 1]
			if typeof(next) == TYPE_DICTIONARY:
				end_beat = _fraction_to_beat(next.get("startTime", [0, 0, 1]))
				end_time = acc_time + (end_beat - start_beat) * 60.0 / bpm + offset_sec
		cache.append({
			"start_beat": start_beat,
			"start_time": acc_time + offset_sec,
			"bpm": bpm,
			"end_beat": end_beat,
			"end_time": end_time
		})
		if end_beat != INF:
			acc_time += (end_beat - start_beat) * 60.0 / bpm
	return cache

# 二分查找：节拍 → 时间
static func cached_beat_to_time(cache: Array, beat: float) -> float:
	if cache.is_empty():
		return 0.0
	# 处理第一个段之前
	var first = cache[0]
	if beat < first["start_beat"]:
		return first["start_time"] - (first["start_beat"] - beat) * 60.0 / first["bpm"]
	# 二分查找所在段
	var lo = 0
	var hi = cache.size() - 1
	while lo <= hi:
		var mid = (lo + hi) / 2
		var seg = cache[mid]
		if beat < seg["start_beat"]:
			hi = mid - 1
		elif seg["end_beat"] != INF and beat >= seg["end_beat"]:
			lo = mid + 1
		else:
			return seg["start_time"] + (beat - seg["start_beat"]) * 60.0 / seg["bpm"]
	# 超出最后一个段，用最后一段的BPM推算
	var last = cache[cache.size() - 1]
	return last["start_time"] + (beat - last["start_beat"]) * 60.0 / last["bpm"]

# 二分查找：时间 → 节拍
static func cached_time_to_beat(cache: Array, time_sec: float) -> float:
	if cache.is_empty():
		return 0.0
	# 处理第一个段之前
	var first = cache[0]
	if time_sec < first["start_time"]:
		return first["start_beat"] - (first["start_time"] - time_sec) * first["bpm"] / 60.0
	# 二分查找所在段
	var lo = 0
	var hi = cache.size() - 1
	while lo <= hi:
		var mid = (lo + hi) / 2
		var seg = cache[mid]
		if time_sec < seg["start_time"]:
			hi = mid - 1
		elif seg["end_time"] != INF and time_sec >= seg["end_time"]:
			lo = mid + 1
		else:
			return seg["start_beat"] + (time_sec - seg["start_time"]) * seg["bpm"] / 60.0
	# 超出最后一个段
	var last = cache[cache.size() - 1]
	return last["start_beat"] + (time_sec - last["start_time"]) * last["bpm"] / 60.0

static func _fraction_to_beat(fraction: Array) -> float:
	if fraction.size() != 3:
		return 0.0
	var integer = float(fraction[0])
	var numerator = float(fraction[1])
	var denominator = float(fraction[2])
	if denominator == 0:
		denominator = 1.0
	return integer + numerator / denominator

const MONO_FONT_RES = preload("res://res/fonts/LXGWWenKaiMono-Regular.ttf")

func _ready() -> void:
	# 加载设置
	load_settings()
	# 等宽字体改为编译期 preload（路径错误编译期即暴露，避免运行时 IO）
	mono_font = MONO_FONT_RES

# 全局快捷键
func _input(event: InputEvent) -> void:
	if is_shortcut_match(event, "global", "toggle_fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()

# 切换全屏
func toggle_fullscreen() -> void:
	var mode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
