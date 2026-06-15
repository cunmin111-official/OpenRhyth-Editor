extends Node
# 全局变量
# 文件路径
var selected_rwc_path: String = ""
var selected_music_path: String = ""
var preview_time: float = 0.0
# 等宽字体（用于 JSON 编辑器等）
var mono_font: Font = null

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

func _ready() -> void:
	var font = load("res://res/fonts/LXGWWenKaiMono-Regular.ttf")
	if font:
		mono_font = font

# 全局快捷键
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
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
