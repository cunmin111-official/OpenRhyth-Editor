extends Node2D

signal shader_data_changed

const PropertyEditDialog = preload("res://scene/editor/property_edit_dialog.gd")

enum PlaceMode { BROWSE, INSTANT, CONTINUOUS }
var current_place_mode: PlaceMode = PlaceMode.BROWSE
var continuous_start_beat: float = 0.0
var continuous_effect_type: int = 0
var is_placing_continuous: bool = false

const EFFECT_TYPES = ["Fog", "BackgroundR", "BackgroundG", "BackgroundB"]
const DEFAULT_VALUES = [10.0, 255.0, 255.0, 255.0]

var mouse_over_pos: Vector2 = Vector2.ZERO
var mouse_in_grid: bool = false

var right_drag_start: Vector2 = Vector2.ZERO
var right_dragging: bool = false
var drag_start_scroll_time: float = 0.0

var selected_events: Array = []
var selecting: bool = false
var select_start_grid: Dictionary = {}
var select_end_grid: Dictionary = {}

@onready var v_scroll = $VScrollBar

var chart_data: Dictionary = {}
var current_events: Array = []
var scroll_time: float = 0.0
var view_width: float = 0.0
var view_height: float = 0.0
var total_duration: float = 0.0
var offset_ms: int = 0
var bpm_list: Array = []
var bpm_cache: Array = []
var pixels_per_second: float = 500.0
var subdivision: int = 1

var is_playing: bool = false
var playback_timer: Timer = null
var last_update_time: float = 0.0

var last_click_time: int = 0
var last_click_event = null

# 剪贴板（复制/粘贴）
var _clipboard_events: Array = []

# MIDI 参考节拍位置
var _midi_reference_beats: Array = []

func set_midi_reference(beats: Array):
	_midi_reference_beats = beats
	queue_redraw()

func _ready():
	v_scroll.value_changed.connect(_on_v_scroll_changed)
	v_scroll.min_value = 0
	v_scroll.max_value = 100
	v_scroll.page = 100
	v_scroll.z_index = 1
	queue_redraw()
	
	playback_timer = Timer.new()
	playback_timer.wait_time = 0.02
	playback_timer.autostart = false
	playback_timer.timeout.connect(_on_playback_timer_timeout)
	add_child(playback_timer)
	
	set_process_input(true)

func update_data(new_chart_data: Dictionary):
	chart_data = new_chart_data
	_shape_bounds_cache.clear()
	
	# 确保 Shader 字段存在且为 Dictionary
	if not chart_data.has("Shader") or typeof(chart_data["Shader"]) != TYPE_DICTIONARY:
		chart_data["Shader"] = {}
	var shader_dict = chart_data["Shader"]
	
	# 确保每个效果类型都有数组
	for name in EFFECT_TYPES:
		if not shader_dict.has(name) or typeof(shader_dict[name]) != TYPE_ARRAY:
			shader_dict[name] = []
	
	# 收集所有事件，并进行类型检查和修正
	current_events = []
	for i in range(EFFECT_TYPES.size()):
		var effect_name = EFFECT_TYPES[i]
		var events = shader_dict[effect_name]
		events.sort_custom(func(a, b): return fraction_to_beat(a.get("startTime", [0, 0, 1])) < fraction_to_beat(b.get("startTime", [0, 0, 1])))
		for ev in events:
			# 跳过非字典元素
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			# 确保 startTime 和 endTime 是整数数组
			for time_field in ["startTime", "endTime"]:
				if ev.has(time_field) and typeof(ev[time_field]) == TYPE_ARRAY:
					var arr = ev[time_field]
					if arr.size() == 3:
						ev[time_field] = [int(arr[0]), int(arr[1]), int(arr[2])]
				else:
					# 默认值
					ev[time_field] = [0,0,1]
			# 确保 type 是字符串
			if ev.has("type") and typeof(ev["type"]) == TYPE_INT:
				ev["type"] = str(ev["type"])
			elif not ev.has("type"):
				ev["type"] = "Linear"
			# 添加内部字段
			ev["_effect_type"] = i
			ev["_is_continuous"] = ev.has("endTime") and ev["endTime"] != ev.get("startTime")
			current_events.append(ev)
	
	var meta = chart_data.get("META", {})
	offset_ms = meta.get("offset", 0)
	total_duration = meta.get("duration", 0.0)
	bpm_list = chart_data.get("BPMList", []).duplicate()
	bpm_cache = Global.build_bpm_cache(bpm_list, offset_ms)
	
	var visible_seconds = view_height / pixels_per_second
	v_scroll.max_value = max(0.0, total_duration + visible_seconds)
	v_scroll.page = visible_seconds
	v_scroll.visible = true
	stop_playback()
	scroll_time = 0.0
	v_scroll.value = 0.0
	queue_redraw()

func _on_v_scroll_changed(value: float):
	scroll_time = max(0.0, value)
	queue_redraw()

func time_to_y(time_sec: float) -> float:
	return view_height - (time_sec - scroll_time) * pixels_per_second

func get_column_x(column: int) -> float:
	var col_width = view_width / EFFECT_TYPES.size()
	return column * col_width

func _draw():
	if view_height <= 0 or pixels_per_second <= 0:
		return
	
	draw_rect(Rect2(0, 0, view_width, view_height), Color(0.9, 0.9, 0.9), true)
	
	var col_width = view_width / EFFECT_TYPES.size()
	for i in range(1, EFFECT_TYPES.size()):
		var x = i * col_width
		draw_line(Vector2(x, 0), Vector2(x, view_height), Color(0.7, 0.7, 0.7), 1.0)
	
	for i in range(EFFECT_TYPES.size()):
		var title = EFFECT_TYPES[i]
		var x = i * col_width + 5
		draw_string(ThemeDB.fallback_font, Vector2(x, 20), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
	
	var visible_seconds = view_height / pixels_per_second
	var bottom_time = scroll_time
	var top_time = scroll_time + visible_seconds
	
	var bottom_beat = time_to_beat(bottom_time)
	var top_beat = time_to_beat(top_time)
	var start_beat = floor(bottom_beat)
	var end_beat = ceil(top_beat) + 1
	
	var lines = []
	for beat in range(start_beat, end_beat + 1):
		lines.append([float(beat), false, 0])
		if subdivision > 1:
			for part in range(1, subdivision):
				var sub_beat = beat + float(part) / subdivision
				lines.append([sub_beat, true, part])
	lines.sort_custom(func(a, b): return a[0] < b[0])
	
	for line in lines:
		var beat = line[0]
		var is_sub = line[1]
		var part = line[2]
		var beat_time = beat_to_time(beat)
		if beat_time < 0 or beat_time > total_duration + 0.001:
			continue
		if beat_time < bottom_time - 0.001 or beat_time > top_time + 0.001:
			continue
		var y = time_to_y(beat_time)
		if y < -5 or y > view_height + 5:
			continue
		
		if is_sub:
			draw_line(Vector2(0, y), Vector2(view_width, y), Color.DARK_GRAY, 2.0)
			draw_string(ThemeDB.fallback_font, Vector2(2, y - 2), "+" + str(part), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.LIGHT_GRAY)
		else:
			draw_line(Vector2(0, y), Vector2(view_width, y), Color.GRAY, 3.0)
			draw_string(ThemeDB.fallback_font, Vector2(2, y - 2), str(beat), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
			if beat_time >= 0:
				var minutes = floor(beat_time / 60)
				var seconds = int(beat_time) % 60
				var millis = floor((beat_time - floor(beat_time)) * 1000)
				var time_str = "%d:%02d.%03d" % [minutes, seconds, millis]
				draw_string(ThemeDB.fallback_font, Vector2(2, y + 12), time_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.BLACK)
	
	# MIDI 参考线（蓝色 #66ccff）
	var midi_color = Color(0.4, 0.8, 1.0, 0.6)
	for beat in _midi_reference_beats:
		var beat_time = beat_to_time(beat)
		if beat_time < bottom_time - 0.001 or beat_time > top_time + 0.001:
			continue
		var y = time_to_y(beat_time)
		if y < -5 or y > view_height + 5:
			continue
		draw_line(Vector2(0, y), Vector2(view_width, y), midi_color, 3.0)
	
	var ref_y = view_height - 5
	draw_line(Vector2(0, ref_y), Vector2(view_width, ref_y), Color.RED, 2.0)
	var ref_beat = time_to_beat(scroll_time)
	draw_string(ThemeDB.fallback_font, Vector2(view_width - 80, ref_y - 5), "节拍: " + str(floor(ref_beat)), HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, Color.YELLOW)
	
	var mode_text = ""
	match current_place_mode:
		PlaceMode.BROWSE: mode_text = "浏览模式 | Shader编辑器(beta)"
		PlaceMode.INSTANT: mode_text = "瞬时Shader放置"
		PlaceMode.CONTINUOUS: mode_text = "持续Shader放置 | " + ("点击第二个点" if is_placing_continuous else "点击第一个点")
	draw_string(ThemeDB.fallback_font, Vector2(10, 30), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
	
	if mouse_in_grid:
		var grid_data = screen_to_grid(mouse_over_pos)
		var col = grid_data.column
		var beat = grid_data.beat
		var value_at_beat = get_value_at_beat(col, beat)
		var info_text = "列: %s  节拍: %.3f  取值: %.2f" % [EFFECT_TYPES[col], beat, value_at_beat]
		draw_string(ThemeDB.fallback_font, Vector2(mouse_over_pos.x + 10, mouse_over_pos.y - 10), info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.DARK_BLUE)
		
		if current_place_mode == PlaceMode.CONTINUOUS and is_placing_continuous:
			var start_time = beat_to_time(continuous_start_beat)
			var end_time = beat_to_time(beat)
			var start_y = time_to_y(start_time)
			var end_y = time_to_y(end_time)
			var col_x = get_column_x(continuous_effect_type)
			var rect_top = min(start_y, end_y)
			var rect_bottom = max(start_y, end_y)
			var rect = Rect2(col_x, rect_top, col_width, rect_bottom - rect_top)
			draw_rect(rect, Color(0, 1, 0, 0.3), true)
			draw_rect(rect, Color.GREEN, false, 1.0)
	
	if selecting:
		var start_screen = grid_to_screen(select_start_grid)
		var end_screen = grid_to_screen(select_end_grid)
		var rect = Rect2(start_screen, end_screen - start_screen).abs()
		draw_rect(rect, Color(0.5, 0.5, 0.5, 0.3), true)
		draw_rect(rect, Color.WHITE, false, 1.0)
	
	if current_events.is_empty():
		return
	var visible_time_min = bottom_time - 1.0
	var visible_time_max = top_time + 1.0
	for ev in current_events:
		var effect_type = ev["_effect_type"]
		var is_cont = ev["_is_continuous"]
		var start_beat_val = fraction_to_beat(ev.get("startTime", [0,0,1]))
		var start_time = beat_to_time(start_beat_val)
		var end_beat_val = fraction_to_beat(ev.get("endTime", start_beat_val))
		var end_time = beat_to_time(end_beat_val)
		
		if is_cont:
			if end_time < visible_time_min or start_time > visible_time_max:
				continue
		else:
			if start_time < visible_time_min or start_time > visible_time_max:
				continue
		
		var col_x = get_column_x(effect_type)
		var start_y = time_to_y(start_time)
		var end_y = time_to_y(end_time)
		
		if is_cont:
			var rect_width = 12
			var rect_x = col_x + (col_width - rect_width) / 2
			var rect_top = min(start_y, end_y)
			var rect_bottom = max(start_y, end_y)
			var rect = Rect2(rect_x, rect_top, rect_width, rect_bottom - rect_top)
			draw_rect(rect, Color(0.2, 0.2, 0.8, 0.7), true)
			draw_rect(rect, Color.BLACK, false, 1.0)
			var info = ev.get("type", "")
			if info != "":
				draw_string(ThemeDB.fallback_font, Vector2(col_x + 2, start_y + 12), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.BLACK)
		else:
			var center = Vector2(col_x + col_width/2, start_y)
			draw_circle(center, 8, Color(0.8, 0.4, 0.1, 0.9))
			var val = ev.get("start", 0.0)
			draw_string(ThemeDB.fallback_font, Vector2(col_x + 2, start_y - 2), str(val), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.BLACK)
		
		if selected_events.has(ev):
			if is_cont:
				var rect_width = 12
				var rect_x = col_x + (col_width - rect_width) / 2
				var rect_top = min(start_y, end_y)
				var rect_bottom = max(start_y, end_y)
				var rect = Rect2(rect_x - 2, rect_top - 2, rect_width + 4, rect_bottom - rect_top + 4)
				draw_rect(rect, Color.YELLOW, false, 2.0)
			else:
				draw_circle(Vector2(col_x + col_width/2, start_y), 11, Color.YELLOW, false, 2.0)

# ========== 转换函数 ==========
func beat_to_time(beat: float) -> float:
	return Global.cached_beat_to_time(bpm_cache, beat)

func time_to_beat(time_sec: float) -> float:
	return Global.cached_time_to_beat(bpm_cache, time_sec)

func fraction_to_beat(fraction: Array) -> float:
	if fraction.size() != 3:
		return 0.0
	var integer = float(fraction[0])
	var numerator = float(fraction[1])
	var denominator = float(fraction[2])
	if denominator == 0:
		denominator = 1.0
	return integer + numerator / denominator

func beat_to_fraction(beat: float) -> Array:
	var integer = floor(beat)
	var frac = beat - integer
	var best_num = 0
	var best_den = 1
	var best_diff = 1.0
	for den in range(1, 101):
		var num = round(frac * den)
		var diff = abs(frac - num / den)
		if diff < best_diff:
			best_diff = diff
			best_num = num
			best_den = den
	return [integer, best_num, best_den]

func set_view_size(width: float, height: float):
	view_width = width
	view_height = height
	v_scroll.position = Vector2(width - 20, 0)
	v_scroll.size = Vector2(20, height)
	var visible_seconds = view_height / pixels_per_second
	v_scroll.page = visible_seconds
	if total_duration > 0:
		v_scroll.max_value = max(0.0, total_duration + visible_seconds)
	queue_redraw()

func start_playback():
	if is_playing:
		print("[Shader面板] 播放已在进行中，跳过启动")
		return
	if scroll_time >= total_duration:
		scroll_time = 0.0
		v_scroll.value = 0.0
	is_playing = true
	last_update_time = Time.get_ticks_msec() / 1000.0
	playback_timer.start()
	print("[Shader面板] 开始播放 - scroll_time: %.3f" % scroll_time)

func stop_playback():
	if not is_playing:
		return
	is_playing = false
	playback_timer.stop()
	print("[Shader面板] 停止播放")

func _on_playback_timer_timeout():
	if not is_playing:
		return
	var now = Time.get_ticks_msec() / 1000.0
	var delta = now - last_update_time
	last_update_time = now
	var new_scroll_time = scroll_time + delta
	if new_scroll_time >= total_duration:
		new_scroll_time = total_duration
		stop_playback()
	v_scroll.value = new_scroll_time

func _input(event: InputEvent):
	if visible and event is InputEventKey and event.pressed and not event.echo:
		if Global.is_shortcut_match(event, "shader_edit", "delete_selected"):
			if selected_events.size() > 0:
				for ev in selected_events:
					remove_event_from_data(ev)
				clear_selection()
				shader_data_changed.emit()
				queue_redraw()
				print("删除了 ", selected_events.size(), " 个 Shader 事件")
			get_viewport().set_input_as_handled()
			return
		
		if Global.is_shortcut_match(event, "shader_edit", "copy_selected"):
			if selected_events.size() > 0:
				_clipboard_events = []
				for ev in selected_events:
					var copy = JSON.parse_string(JSON.stringify(ev))
					# 保留 _effect_type 以识别效果类型列
					_clipboard_events.append(copy)
				print("复制了 ", _clipboard_events.size(), " 个 Shader 事件")
			get_viewport().set_input_as_handled()
			return
		
		if Global.is_shortcut_match(event, "shader_edit", "paste_clipboard"):
			if _clipboard_events.is_empty():
				print("剪贴板为空，无法粘贴")
				get_viewport().set_input_as_handled()
				return
			_show_paste_beat_dialog()
			get_viewport().set_input_as_handled()
			return
		
		if Global.is_shortcut_match(event, "shader_edit", "quantize_selected"):
			if selected_events.size() > 0:
				_quantize_selected_events()
				shader_data_changed.emit()
				queue_redraw()
				print("量化了 ", selected_events.size(), " 个 Shader 事件")
			get_viewport().set_input_as_handled()
			return
		
		if event.ctrl_pressed and event.shift_pressed:
			var step_beat = 1.0 / subdivision
			if Global.is_shortcut_match(event, "shader_edit", "shift_up"):
				for ev in selected_events:
					var beat = fraction_to_beat(ev["startTime"])
					beat += step_beat
					ev["startTime"] = beat_to_fraction(beat)
					if ev.has("endTime"):
						var end_beat = fraction_to_beat(ev["endTime"])
						end_beat += step_beat
						ev["endTime"] = beat_to_fraction(end_beat)
				queue_redraw()
				shader_data_changed.emit()
				get_viewport().set_input_as_handled()
			elif Global.is_shortcut_match(event, "shader_edit", "shift_down"):
				for ev in selected_events:
					var beat = fraction_to_beat(ev["startTime"])
					beat -= step_beat
					ev["startTime"] = beat_to_fraction(beat)
					if ev.has("endTime"):
						var end_beat = fraction_to_beat(ev["endTime"])
						end_beat -= step_beat
						ev["endTime"] = beat_to_fraction(end_beat)
				queue_redraw()
				shader_data_changed.emit()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT:
				pass
			return
		
		match event.keycode:
			KEY_LEFT, KEY_RIGHT:
				pass
		if event.ctrl_pressed:
			if Global.is_shortcut_match(event, "shader_edit", "continuous_mode"):
				current_place_mode = PlaceMode.CONTINUOUS
				is_placing_continuous = false
				print("放置模式: 持续Shader效果")
				queue_redraw()
				get_viewport().set_input_as_handled()
			elif Global.is_shortcut_match(event, "shader_edit", "instant_mode"):
				current_place_mode = PlaceMode.INSTANT
				is_placing_continuous = false
				print("放置模式: 瞬时Shader效果")
				queue_redraw()
				get_viewport().set_input_as_handled()
			elif Global.is_shortcut_match(event, "shader_edit", "browse_mode"):
				current_place_mode = PlaceMode.BROWSE
				is_placing_continuous = false
				print("浏览模式")
				queue_redraw()
				get_viewport().set_input_as_handled()
	
	if visible and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			v_scroll.value -= 0.2
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			v_scroll.value += 0.2
			get_viewport().set_input_as_handled()
		
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var mouse_pos = get_local_mouse_position()
			if mouse_pos.x > view_width - 20:
				pass
			elif mouse_pos.x >= 0 and mouse_pos.x <= view_width and mouse_pos.y >= 0 and mouse_pos.y <= view_height:
				if current_place_mode == PlaceMode.BROWSE:
					var clicked_event = get_event_at_position(mouse_pos)
					if clicked_event != null:
						var current_time = Time.get_ticks_msec()
						if last_click_event == clicked_event and (current_time - last_click_time) < 300:
							edit_event_properties(clicked_event)
							last_click_time = 0
							last_click_event = null
						else:
							if event.ctrl_pressed:
								if selected_events.has(clicked_event):
									selected_events.erase(clicked_event)
								else:
									add_to_selection(clicked_event)
							else:
								clear_selection()
								add_to_selection(clicked_event)
						last_click_time = current_time
						last_click_event = clicked_event
						get_viewport().set_input_as_handled()
					else:
						selecting = true
						var grid_data = screen_to_grid(mouse_pos)
						select_start_grid = {"column": grid_data.column, "beat": grid_data.beat}
						select_end_grid = {"column": grid_data.column, "beat": grid_data.beat}
						if not event.ctrl_pressed:
							clear_selection()
						get_viewport().set_input_as_handled()
				else:
					var grid_data = screen_to_grid(mouse_pos)
					if current_place_mode == PlaceMode.INSTANT:
						place_instant_event(grid_data)
						get_viewport().set_input_as_handled()
					elif current_place_mode == PlaceMode.CONTINUOUS:
						if not is_placing_continuous:
							continuous_start_beat = grid_data.beat
							continuous_effect_type = grid_data.column
							is_placing_continuous = true
							print("持续Shader起始点: beat=", continuous_start_beat, " 类型=", EFFECT_TYPES[continuous_effect_type])
						else:
							place_continuous_event(continuous_start_beat, grid_data.beat, continuous_effect_type)
							is_placing_continuous = false
						get_viewport().set_input_as_handled()
		
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if selecting:
				selecting = false
				select_events_in_rect_grid(select_start_grid, select_end_grid)
				queue_redraw()
				get_viewport().set_input_as_handled()
		
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				right_drag_start = event.position
				right_dragging = true
				drag_start_scroll_time = scroll_time
				get_viewport().set_input_as_handled()
			else:
				right_dragging = false
				get_viewport().set_input_as_handled()
	
	if visible and event is InputEventMouseMotion:
		mouse_over_pos = get_local_mouse_position()
		mouse_in_grid = (mouse_over_pos.x >= 0 and mouse_over_pos.x <= view_width and mouse_over_pos.y >= 0 and mouse_over_pos.y <= view_height)
		if right_dragging:
			var delta = event.position - right_drag_start
			var delta_time = delta.y / pixels_per_second
			scroll_time = clamp(drag_start_scroll_time + delta_time, 0.0, v_scroll.max_value)
			v_scroll.value = scroll_time
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif selecting:
			var mouse_pos = get_local_mouse_position()
			var grid_data = screen_to_grid(mouse_pos)
			select_end_grid = {"column": grid_data.column, "beat": grid_data.beat}
			var edge_threshold = 30
			var scroll_speed = 3
			if mouse_pos.y < edge_threshold:
				v_scroll.value += 0.05 * scroll_speed
				queue_redraw()
			elif mouse_pos.y > view_height - edge_threshold:
				v_scroll.value -= 0.05 * scroll_speed
				queue_redraw()
			queue_redraw()
			get_viewport().set_input_as_handled()
		else:
			if mouse_in_grid:
				queue_redraw()

func _exit_tree():
	if playback_timer:
		playback_timer.stop()

func get_current_bottom_time() -> float:
	return scroll_time

func set_subdivision(val: int):
	subdivision = val
	queue_redraw()

func set_pixels_per_second(val: float):
	pixels_per_second = val
	var visible_seconds = view_height / pixels_per_second
	v_scroll.page = visible_seconds
	if total_duration > 0:
		v_scroll.max_value = max(0.0, total_duration + visible_seconds)
	queue_redraw()

func screen_to_grid(screen_pos: Vector2) -> Dictionary:
	var time = scroll_time + (view_height - screen_pos.y) / pixels_per_second
	var beat = time_to_beat(time)
	var col = int(screen_pos.x / (view_width / EFFECT_TYPES.size()))
	col = clamp(col, 0, EFFECT_TYPES.size() - 1)
	var align = Input.is_key_pressed(KEY_CTRL)
	if align:
		var step = 1.0 / subdivision
		# 优先吸附到 MIDI 参考节拍
		if not _midi_reference_beats.is_empty():
			var nearest_midi_beat = _find_nearest_midi_beat(beat)
			if nearest_midi_beat >= 0 and abs(nearest_midi_beat - beat) < step * 0.5:
				beat = nearest_midi_beat
			else:
				beat = round(beat / step) * step
		else:
			beat = round(beat / step) * step
	return {"time": time, "beat": beat, "column": col, "value_at_beat": DEFAULT_VALUES[col]}

# 查找最近的 MIDI 参考节拍
func _find_nearest_midi_beat(beat: float) -> float:
	if _midi_reference_beats.is_empty():
		return -1.0
	var lo = 0
	var hi = _midi_reference_beats.size() - 1
	while lo <= hi:
		var mid = (lo + hi) / 2
		var mid_val = _midi_reference_beats[mid] as float
		if beat < mid_val:
			hi = mid - 1
		elif beat > mid_val:
			lo = mid + 1
		else:
			return mid_val
	if lo == 0:
		return _midi_reference_beats[0] as float
	if lo >= _midi_reference_beats.size():
		return _midi_reference_beats[_midi_reference_beats.size() - 1] as float
	var prev = _midi_reference_beats[lo - 1] as float
	var next = _midi_reference_beats[lo] as float
	if abs(beat - prev) < abs(beat - next):
		return prev
	return next

func grid_to_screen(grid: Dictionary) -> Vector2:
	var time = beat_to_time(grid.beat)
	var x = get_column_x(grid.column)
	var y = time_to_y(time)
	return Vector2(x, y)

# 缓动类型归一化：全角 ～/： 转半角 ~/，保存与求值统一使用英文半角
func _normalize_easing_type(t: String) -> String:
	return t.strip_edges().replace("～", "~").replace("：", ":")

# 表达式求值：支持 "y=..."（x 为经过秒数，y 直接作为数值）
# "y~..."（x 恒定 0~1 表示事件内进度，y 作为形状伸缩到 start~end）
# "y:..."（x 恒定 0~1 表示事件内进度，y 为函数原始取值）
func eval_expression(expr_str: String, x: float) -> float:
	expr_str = _normalize_easing_type(expr_str)
	if expr_str.begins_with("y=") or expr_str.begins_with("y~") or expr_str.begins_with("y:"):
		expr_str = expr_str.substr(2)
	else:
		return x
	var expr = Expression.new()
	var error = expr.parse(Global.replace_expr_constants(expr_str.replace("^", "**")), ["x"])
	if error != OK:
		return x
	var result = expr.execute([x])
	if typeof(result) == TYPE_FLOAT or typeof(result) == TYPE_INT:
		return float(result)
	return x

# y~ 形状伸缩求值缓存：type_str -> [f0, f1, fmin, fmax]
var _shape_bounds_cache: Dictionary = {}

func _get_shape_bounds(type_str: String) -> Array:
	if _shape_bounds_cache.has(type_str):
		return _shape_bounds_cache[type_str]
	var f0 = eval_expression(type_str, 0.0)
	var f1 = eval_expression(type_str, 1.0)
	var fmin = min(f0, f1)
	var fmax = max(f0, f1)
	for i in range(1, 32):
		var v = eval_expression(type_str, float(i) / 32.0)
		fmin = min(fmin, v)
		fmax = max(fmax, v)
	var bounds = [f0, f1, fmin, fmax]
	_shape_bounds_cache[type_str] = bounds
	return bounds

# y~ 形状伸缩：f(0)→start、f(1)→end（端点归一化，正确支持 start>end 与任意形状）；
# 闭合曲线（f(0)≈f(1)，如 sin 脉冲）按采样极值 min→start、max→end；恒定形状退化为线性
func _eval_shape_stretched(type_str: String, prog: float, start_val: float, end_val: float) -> float:
	var b = _get_shape_bounds(type_str)
	var f0: float = b[0]
	var f1: float = b[1]
	if abs(f1 - f0) > 0.000001:
		var f = eval_expression(type_str, prog)
		return start_val + (end_val - start_val) * (f - f0) / (f1 - f0)
	var fmin: float = b[2]
	var fmax: float = b[3]
	if fmax - fmin > 0.000001:
		var fc = eval_expression(type_str, prog)
		return start_val + (end_val - start_val) * (fc - fmin) / (fmax - fmin)
	return start_val + (end_val - start_val) * prog

func get_value_at_beat(col: int, beat: float) -> float:
	var events = []
	for ev in current_events:
		if ev["_effect_type"] == col:
			events.append(ev)
	if events.is_empty():
		return DEFAULT_VALUES[col]
	events.sort_custom(func(a, b): return fraction_to_beat(a.get("startTime", [0,0,1])) < fraction_to_beat(b.get("startTime", [0,0,1])))
	var last_value = DEFAULT_VALUES[col]
	for ev in events:
		var start_beat = fraction_to_beat(ev.get("startTime", [0,0,1]))
		var end_beat = fraction_to_beat(ev.get("endTime", start_beat))
		if ev["_is_continuous"]:
			if beat >= start_beat and beat <= end_beat:
				var start_val = ev.get("start", DEFAULT_VALUES[col])
				var end_val = ev.get("end", start_val)
				if start_beat == end_beat:
					return start_val
				var t = (beat - start_beat) / (end_beat - start_beat)
				var type_str = _normalize_easing_type(str(ev.get("type", "Linear")))
				if type_str == "Linear":
					return start_val + (end_val - start_val) * t
				elif type_str.begins_with("y~") or type_str.begins_with("y:"):
					# x 恒定 0~1 并伸缩至始末时间
					var start_sec = beat_to_time(start_beat)
					var end_sec = beat_to_time(end_beat)
					if end_sec <= start_sec:
						return start_val
					var prog = clamp((beat_to_time(beat) - start_sec) / (end_sec - start_sec), 0.0, 1.0)
					if type_str.begins_with("y~"):
						# 形状表达式：y 伸缩至 start~end（端点归一化）
						return _eval_shape_stretched(type_str, prog, start_val, end_val)
					# 原始值表达式：y 直接作为数值
					return eval_expression(type_str, prog)
				elif type_str.begins_with("y="):
					var elapsed_sec = beat_to_time(beat) - beat_to_time(start_beat)
					return eval_expression(type_str, elapsed_sec)
				else:
					return start_val + (end_val - start_val) * t
			elif beat > end_beat:
				last_value = ev.get("end", DEFAULT_VALUES[col])
		else:
			if abs(beat - start_beat) < 0.001:
				return ev.get("start", DEFAULT_VALUES[col])
			if beat > start_beat:
				last_value = ev.get("start", DEFAULT_VALUES[col])
	return last_value

func is_overlap(col: int, start_beat: float, end_beat: float, ignore_event = null) -> bool:
	for ev in current_events:
		if ev["_effect_type"] != col:
			continue
		if ignore_event != null and ev == ignore_event:
			continue
		var ev_start = fraction_to_beat(ev.get("startTime", [0,0,1]))
		var ev_end = fraction_to_beat(ev.get("endTime", ev_start))
		if ev["_is_continuous"]:
			if not (end_beat <= ev_start or start_beat >= ev_end):
				return true
		else:
			if abs(start_beat - ev_start) < 0.001:
				return true
	return false

func place_instant_event(grid_data: Dictionary):
	var col = grid_data.column
	var beat = grid_data.beat
	if is_overlap(col, beat, beat):
		print("错误：该位置已有瞬时效果，不允许重叠")
		return
	# 新事件默认读取放置时刻的当前数值，而非程序默认值
	var cur_val = get_value_at_beat(col, beat)
	var event = {
		"type": "Linear",
		"startTime": beat_to_fraction(beat),
		"endTime": beat_to_fraction(beat),
		"start": cur_val,
		"end": cur_val,
		"isContinuous": 0
	}
	add_event_to_current_line(event, col)
	print("放置瞬时Shader效果: 列=", EFFECT_TYPES[col], " beat=", beat, " 值=", cur_val)

func place_continuous_event(start_beat: float, end_beat: float, effect_type: int):
	if abs(start_beat - end_beat) < 0.001:
		print("持续Shader效果起始结束节拍相同，无效")
		return
	var start = min(start_beat, end_beat)
	var end = max(start_beat, end_beat)
	if is_overlap(effect_type, start, end):
		print("错误：该时间段内已有效果，不允许重叠")
		return
	# 新事件默认读取起止时刻的当前数值，而非程序默认值
	var start_val = get_value_at_beat(effect_type, start)
	var end_val = get_value_at_beat(effect_type, end)
	var event = {
		"type": "Linear",
		"startTime": beat_to_fraction(start),
		"endTime": beat_to_fraction(end),
		"start": start_val,
		"end": end_val,
		"isContinuous": 1
	}
	add_event_to_current_line(event, effect_type)
	print("放置持续Shader效果: 列=", EFFECT_TYPES[effect_type], " start=", start, " end=", end, " 值=", start_val, "~", end_val)

func add_event_to_current_line(event_data: Dictionary, effect_type: int):
	var shader_dict = chart_data["Shader"]
	var effect_name = EFFECT_TYPES[effect_type]
	if not shader_dict.has(effect_name) or typeof(shader_dict[effect_name]) != TYPE_ARRAY:
		shader_dict[effect_name] = []
	shader_dict[effect_name].append(event_data)
	shader_dict[effect_name].sort_custom(func(a, b): return fraction_to_beat(a.get("startTime", [0, 0, 1])) < fraction_to_beat(b.get("startTime", [0, 0, 1])))
	event_data["_effect_type"] = effect_type
	event_data["_is_continuous"] = event_data.get("isContinuous", 0) == 1
	current_events.append(event_data)
	shader_data_changed.emit()
	queue_redraw()

func remove_event_from_data(event: Dictionary):
	var effect_type = event["_effect_type"]
	var effect_name = EFFECT_TYPES[effect_type]
	var shader_dict = chart_data["Shader"]
	var idx = shader_dict[effect_name].find(event)
	if idx != -1:
		shader_dict[effect_name].remove_at(idx)
	var ce_idx = current_events.find(event)
	if ce_idx != -1:
		current_events.remove_at(ce_idx)

func get_event_at_position(mouse_pos: Vector2):
	var grid_data = screen_to_grid(mouse_pos)
	var col = grid_data.column
	var click_beat = grid_data.beat
	var tolerance = 0.1
	for ev in current_events:
		if ev["_effect_type"] != col:
			continue
		var start_beat = fraction_to_beat(ev.get("startTime", [0,0,1]))
		var end_beat = fraction_to_beat(ev.get("endTime", start_beat))
		if ev["_is_continuous"]:
			if click_beat >= start_beat - tolerance and click_beat <= end_beat + tolerance:
				return ev
		else:
			if abs(click_beat - start_beat) < tolerance:
				return ev
	return null

func clear_selection():
	selected_events.clear()

func add_to_selection(ev):
	if not selected_events.has(ev):
		selected_events.append(ev)

func select_events_in_rect_grid(start_grid: Dictionary, end_grid: Dictionary):
	clear_selection()
	var beat_min = min(start_grid.beat, end_grid.beat)
	var beat_max = max(start_grid.beat, end_grid.beat)
	var col_min = min(start_grid.column, end_grid.column)
	var col_max = max(start_grid.column, end_grid.column)
	for ev in current_events:
		var ev_col = ev["_effect_type"]
		if ev_col < col_min or ev_col > col_max:
			continue
		var start_beat = fraction_to_beat(ev.get("startTime", [0,0,1]))
		var end_beat = fraction_to_beat(ev.get("endTime", start_beat))
		if ev["_is_continuous"]:
			if start_beat <= beat_max and end_beat >= beat_min:
				add_to_selection(ev)
		else:
			if start_beat >= beat_min and start_beat <= beat_max:
				add_to_selection(ev)

# ========== 复制粘贴 ==========
func _parse_beat_input(text: String) -> float:
	text = text.strip_edges()
	if text.is_empty():
		return -1.0
	if text.is_valid_float():
		return text.to_float()
	var parts = text.split(" ", false)
	var integer_part: float = 0.0
	var frac_part: float = 0.0
	if parts.size() == 2:
		if parts[0].is_valid_float():
			integer_part = parts[0].to_float()
		var frac_parts = parts[1].split("/", false)
		if frac_parts.size() == 2:
			var num = frac_parts[0].to_float()
			var den = frac_parts[1].to_float()
			if den != 0.0:
				frac_part = num / den
		return integer_part + frac_part
	elif parts.size() == 1:
		var frac_parts = parts[0].split("/", false)
		if frac_parts.size() == 2:
			var num = frac_parts[0].to_float()
			var den = frac_parts[1].to_float()
			if den != 0.0:
				return num / den
	return -1.0

func _show_paste_beat_dialog():
	var dialog = ConfirmationDialog.new()
	dialog.title = "粘贴 Shader 事件"
	dialog.ok_button_text = "确认"
	dialog.cancel_button_text = "取消"
	dialog.min_size = Vector2(400, 150)
	
	var vbox = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.size = Vector2(400, 150)
	
	var label = Label.new()
	label.text = "输入起始节拍（小数或带分数格式，如 4.5 或 4 1/2）："
	
	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "例如: 4.5 或 4 1/2"
	line_edit.custom_minimum_size = Vector2(300, 30)
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	vbox.add_child(label)
	vbox.add_child(line_edit)
	dialog.add_child(vbox)
	
	dialog.confirmed.connect(func():
		var beat_text = line_edit.text
		if beat_text.is_empty():
			return
		var paste_beat = _parse_beat_input(beat_text)
		if paste_beat < 0:
			print("粘贴失败：无效的节拍格式")
			return
		_paste_events_at_beat(paste_beat)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	
	add_child(dialog)
	dialog.popup_centered()

func _paste_events_at_beat(paste_beat: float):
	if _clipboard_events.is_empty():
		return
	
	var min_beat = INF
	for ev in _clipboard_events:
		var b = fraction_to_beat(ev.get("startTime", [0, 0, 1]))
		if b < min_beat:
			min_beat = b
	if min_beat == INF:
		return
	
	var offset = paste_beat - min_beat
	var pasted_count = 0
	
	var shader_dict = chart_data["Shader"]
	
	for ev in _clipboard_events:
		var new_ev = JSON.parse_string(JSON.stringify(ev))
		var effect_type = new_ev.get("_effect_type", -1)
		if effect_type < 0 or effect_type >= EFFECT_TYPES.size():
			continue
		
		var start_b = fraction_to_beat(new_ev["startTime"])
		start_b += offset
		new_ev["startTime"] = beat_to_fraction(start_b)
		
		if new_ev.has("endTime"):
			var end_b = fraction_to_beat(new_ev["endTime"])
			end_b += offset
			new_ev["endTime"] = beat_to_fraction(end_b)
		
		# 设置 isContinuous 和 _is_continuous
		var start_beat_f = fraction_to_beat(new_ev["startTime"])
		var end_beat_f = fraction_to_beat(new_ev.get("endTime", new_ev["startTime"]))
		var is_cont = abs(start_beat_f - end_beat_f) > 0.001
		new_ev["isContinuous"] = 1 if is_cont else 0
		new_ev["_is_continuous"] = is_cont
		
		if not new_ev.has("type"):
			new_ev["type"] = "Linear"
		
		# 添加到对应的 shader 数组
		var effect_name = EFFECT_TYPES[effect_type]
		if not shader_dict.has(effect_name) or typeof(shader_dict[effect_name]) != TYPE_ARRAY:
			shader_dict[effect_name] = []
		shader_dict[effect_name].append(new_ev)
		shader_dict[effect_name].sort_custom(func(a, b): return fraction_to_beat(a.get("startTime", [0, 0, 1])) < fraction_to_beat(b.get("startTime", [0, 0, 1])))
		
		# 添加到 current_events
		current_events.append(new_ev)
		pasted_count += 1
	
	clear_selection()
	shader_data_changed.emit()
	queue_redraw()
	print("粘贴了 ", pasted_count, " 个 Shader 事件，起始节拍: ", paste_beat)

# 量化：将选中 Shader 事件的开始位置对齐到最近的网格线
func _quantize_selected_events():
	if selected_events.is_empty():
		return
	var step = 1.0 / subdivision
	for ev in selected_events:
		var start_beat = fraction_to_beat(ev.get("startTime", [0, 0, 1]))
		var nearest = round(start_beat / step) * step
		ev["startTime"] = beat_to_fraction(nearest)
		# 持续事件：endTime 同步偏移
		if ev.get("_is_continuous", false) and ev.has("endTime"):
			var end_beat = fraction_to_beat(ev["endTime"])
			var delta = nearest - start_beat
			end_beat += delta
			ev["endTime"] = beat_to_fraction(end_beat)

func edit_event_properties(event: Dictionary):
	var is_cont: bool = event.get("_is_continuous", false)
	var fields: Array = [
		{"key": "type", "label": "缓动类型 (Linear / y=… / y~… / y:…)"},
		{"key": "startTime", "label": "开始节拍 (如 4.5 或 4 1/2)"},
		{"key": "endTime", "label": "结束节拍"},
	]
	if is_cont:
		fields.append({"key": "start", "label": "起始值"})
		fields.append({"key": "end", "label": "结束值"})
	else:
		fields.append({"key": "value", "label": "数值 (start 与 end 同步)"})

	var dialog = PropertyEditDialog.new(
		"编辑 Shader 属性",
		fields,
		func(key: String) -> String: return _event_display(event, key),
		func(key: String, text: String) -> bool: return _event_apply_value(event, key, text),
		func() -> String: return _event_build_json(event),
		func(json_text: String) -> String: return _event_apply_json(event, json_text)
	)
	add_child(dialog)
	dialog.popup_centered()

# 节拍显示为原生带分数格式（如 "4"、"2 1/2"），不转小数以避免精度丢失
func _format_beat(fraction_arr: Array) -> String:
	if fraction_arr.size() != 3:
		return "0"
	var integer: int = int(fraction_arr[0])
	var num: int = abs(int(fraction_arr[1]))
	var den: int = int(fraction_arr[2])
	if den <= 0:
		den = 1
	var g: int = _gcd(num, den)
	if g > 1:
		num /= g
		den /= g
	integer += num / den
	num = num % den
	if num == 0:
		return str(integer)
	return "%d %d/%d" % [integer, num, den]

func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t: int = b
		b = a % b
		a = t
	return a

func _event_display(event: Dictionary, key: String) -> String:
	match key:
		"type":
			return str(event.get("type", "Linear"))
		"startTime":
			return _format_beat(event.get("startTime", [0, 0, 1]))
		"endTime":
			return _format_beat(event.get("endTime", event.get("startTime", [0, 0, 1])))
		"value":
			return str(event.get("start", DEFAULT_VALUES[event["_effect_type"]]))
		_:
			return str(event.get(key, 0.0))

func _event_apply_value(event: Dictionary, key: String, text: String) -> bool:
	var col: int = event["_effect_type"]
	match key:
		"type":
			var t := _normalize_easing_type(text)
			if t.is_empty():
				return false
			event["type"] = t
			_sync_expression_bounds(event)
		"startTime", "endTime":
			var beat := _parse_beat_input(text)
			if beat < 0:
				return false
			var start_beat := fraction_to_beat(event.get("startTime", [0, 0, 1]))
			var end_beat := fraction_to_beat(event.get("endTime", start_beat))
			if key == "startTime":
				start_beat = beat
			else:
				end_beat = beat
			if is_overlap(col, min(start_beat, end_beat), max(start_beat, end_beat), event):
				print("错误：修改后的效果与现有效果时间重叠，已取消")
				return false
			event["startTime"] = beat_to_fraction(start_beat)
			event["endTime"] = beat_to_fraction(end_beat)
			var is_cont: bool = abs(start_beat - end_beat) > 0.001
			event["isContinuous"] = 1 if is_cont else 0
			event["_is_continuous"] = is_cont
			_sync_expression_bounds(event)
			_sort_shader_events(col)
		"start", "end":
			if not text.is_valid_float():
				return false
			event[key] = text.to_float()
		"value":
			if not text.is_valid_float():
				return false
			event["start"] = text.to_float()
			event["end"] = text.to_float()
	shader_data_changed.emit()
	queue_redraw()
	return true

# y= 表达式按经过秒数、y: 表达式按 0~1 进度自动计算 start/end；y~（形状）保留 start/end 作为伸缩范围
func _sync_expression_bounds(event: Dictionary) -> void:
	var type_str := _normalize_easing_type(str(event.get("type", "Linear")))
	var start_beat := fraction_to_beat(event.get("startTime", [0, 0, 1]))
	var end_beat := fraction_to_beat(event.get("endTime", start_beat))
	if type_str.begins_with("y="):
		event["start"] = eval_expression(type_str, 0.0)
		event["end"] = eval_expression(type_str, beat_to_time(end_beat) - beat_to_time(start_beat))
	elif type_str.begins_with("y:"):
		event["start"] = eval_expression(type_str, 0.0)
		event["end"] = eval_expression(type_str, 1.0)

func _sort_shader_events(effect_type: int) -> void:
	var effect_name: String = EFFECT_TYPES[effect_type]
	var shader_dict: Dictionary = chart_data.get("Shader", {})
	var arr: Array = shader_dict.get(effect_name, [])
	arr.sort_custom(func(a, b): return fraction_to_beat(a.get("startTime", [0, 0, 1])) < fraction_to_beat(b.get("startTime", [0, 0, 1])))
	current_events.sort_custom(func(a, b): return fraction_to_beat(a.get("startTime", [0, 0, 1])) < fraction_to_beat(b.get("startTime", [0, 0, 1])))

func _event_build_json(event: Dictionary) -> String:
	var display_event: Dictionary = event.duplicate()
	for k in display_event.keys():
		if k.begins_with("_"):
			display_event.erase(k)
	return JSON.stringify(display_event, "\t")

func _event_apply_json(event: Dictionary, json_text: String) -> String:
	var json := JSON.new()
	if json.parse(json_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return "无效的 JSON 格式:\n" + json.get_error_message()
	var new_data: Dictionary = json.data
	if new_data.has("type"):
		new_data["type"] = _normalize_easing_type(str(new_data["type"]))
	for field in ["startTime", "endTime"]:
		if new_data.has(field) and typeof(new_data[field]) == TYPE_ARRAY and new_data[field].size() == 3:
			var arr: Array = new_data[field]
			new_data[field] = [int(arr[0]), int(arr[1]), int(arr[2])]
	var col: int = event["_effect_type"]
	var new_start := fraction_to_beat(new_data.get("startTime", [0, 0, 1]))
	var new_end := fraction_to_beat(new_data.get("endTime", new_start))
	if is_overlap(col, min(new_start, new_end), max(new_start, new_end), event):
		return "修改后的效果与现有效果时间重叠，操作已取消。"
	# 就地替换字段（保持对象引用不变，选择集与事件列表自动同步）
	for k in event.keys():
		if not k.begins_with("_"):
			event.erase(k)
	for k in new_data.keys():
		if not k.begins_with("_"):
			event[k] = new_data[k]
	if not event.has("start"):
		event["start"] = DEFAULT_VALUES[col]
	var is_cont: bool = abs(new_start - new_end) > 0.001
	event["isContinuous"] = 1 if is_cont else 0
	event["_is_continuous"] = is_cont
	if is_cont and not event.has("end"):
		event["end"] = event["start"]
	_sync_expression_bounds(event)
	_sort_shader_events(col)
	shader_data_changed.emit()
	queue_redraw()
	return ""
