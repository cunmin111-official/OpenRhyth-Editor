extends Node2D

signal note_data_changed

enum PlaceMode { BROWSE, TAP, DRAG, HOLD }
var current_place_mode: PlaceMode = PlaceMode.BROWSE
var hold_start_beat: float = 0.0
var hold_start_posx: float = 0.0
var is_placing_hold: bool = false
var mouse_over_pos: Vector2 = Vector2.ZERO
var mouse_in_grid: bool = false

# 右键拖动
var right_drag_start: Vector2 = Vector2.ZERO
var right_dragging: bool = false
var drag_start_scroll_time: float = 0.0
var drag_start_scroll_x: float = 0.0

#选择器
var selected_notes: Array = []          # 存储选中的 note 字典引用
var selecting: bool = false             # 是否正在框选
#var select_start_pos: Vector2 = Vector2.ZERO
#var select_end_pos: Vector2 = Vector2.ZERO
var select_start_grid: Dictionary = {}   #{beat: float, posx: float}
var select_end_grid: Dictionary = {}

@onready var v_scroll = $VScrollBar

var chart_data: Dictionary = {}
var current_judge_line: Dictionary = {}
var current_notes: Array = []
var scroll_time: float = 0.0
var scroll_x: float = 0.0
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
var last_click_note = null

# 剪贴板（复制/粘贴）
var _clipboard_notes: Array = []

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

func update_data(new_chart_data: Dictionary, new_judge_line = null):
	chart_data = new_chart_data
	current_judge_line = new_judge_line if typeof(new_judge_line) == TYPE_DICTIONARY else {}
	
	# 直接引用原始音符列表，不创建副本
	current_notes = current_judge_line.get("notes", [])
	
	# 就地修正类型（浮点数转整数），确保 JSON 中的数字变为整数
	for note in current_notes:
		if note.has("type"):
			note["type"] = int(note["type"])
		if note.has("startTime") and typeof(note["startTime"]) == TYPE_ARRAY:
			var arr = note["startTime"]
			note["startTime"] = [int(arr[0]), int(arr[1]), int(arr[2])]
		if note.has("endTime") and typeof(note["endTime"]) == TYPE_ARRAY:
			var arr = note["endTime"]
			note["endTime"] = [int(arr[0]), int(arr[1]), int(arr[2])]
	
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
	scroll_x = 0.0
	v_scroll.value = 0.0
	queue_redraw()

func _on_v_scroll_changed(value: float):
	scroll_time = max(0.0, value)
	queue_redraw()

func time_to_y(time_sec: float) -> float:
	return view_height - (time_sec - scroll_time) * pixels_per_second

func posx_to_x(posx: float) -> float:
	var visible_left = -100 + scroll_x
	var visible_right = 100 + scroll_x
	return (posx - visible_left) / 200.0 * view_width

func _draw():
	if view_height <= 0 or pixels_per_second <= 0:
		return
	
	# 背景
	draw_rect(Rect2(0, 0, view_width, view_height), Color(0.9, 0.9, 0.9), true)
	
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
			draw_line(Vector2(0, y), Vector2(view_width, y), Color.DARK_GRAY, 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(2, y - 2), "+" + str(part), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.LIGHT_GRAY)
		else:
			draw_line(Vector2(0, y), Vector2(view_width, y), Color.GRAY, 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(2, y - 2), str(beat), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
			if beat_time >= 0:
				var minutes = floor(beat_time / 60)
				var seconds = int(beat_time) % 60
				var millis = floor((beat_time - floor(beat_time)) * 1000)
				var time_str = "%d:%02d.%03d" % [minutes, seconds, millis]
				draw_string(ThemeDB.fallback_font, Vector2(2, y + 12), time_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.BLACK)
	
	# 竖线
	var visible_left = -100 + scroll_x
	var visible_right = 100 + scroll_x
	var start_x = ceil(visible_left / 10.0) * 10
	var end_x = floor(visible_right / 10.0) * 10
	for x_val in range(start_x, end_x + 1, 10):
		var screen_x = (x_val - visible_left) / 200.0 * view_width
		draw_line(Vector2(screen_x, 0), Vector2(screen_x, view_height), Color.GRAY, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(screen_x + 2, 12), str(x_val), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.BLACK)
	
	# 参考线
	var ref_y = view_height - 5
	draw_line(Vector2(0, ref_y), Vector2(view_width, ref_y), Color.RED, 2.0)
	var ref_beat = time_to_beat(scroll_time)
	draw_string(ThemeDB.fallback_font, Vector2(view_width - 80, ref_y - 5), "节拍: " + str(floor(ref_beat)), HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, Color.YELLOW)
	
	# 模式提示
	var mode_text = ""
	match current_place_mode:
		PlaceMode.BROWSE: mode_text = "浏览模式"
		PlaceMode.TAP: mode_text = "Tap放置模式"
		PlaceMode.DRAG: mode_text = "Drag放置模式"
		PlaceMode.HOLD: mode_text = "Hold放置模式 | " + ("点击第二个点" if is_placing_hold else "点击第一个点")
	draw_string(ThemeDB.fallback_font, Vector2(10, 30), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
	# 鼠标悬停提示
	if mouse_in_grid:
		var grid_pos = screen_to_grid(mouse_over_pos)
		var info_text = "X: %.1f  节拍: %.3f" % [grid_pos.posx, grid_pos.beat]
		draw_string(ThemeDB.fallback_font, Vector2(mouse_over_pos.x + 10, mouse_over_pos.y - 10), info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.DARK_BLUE)
		# Hold 预览
		if current_place_mode == PlaceMode.HOLD and is_placing_hold:
			var start_time = beat_to_time(hold_start_beat)
			var end_time = grid_pos.time
			var start_y = time_to_y(start_time)
			var end_y = time_to_y(end_time)
			var screen_x = posx_to_x(hold_start_posx)
			var rect_top = min(start_y, end_y)
			var rect_bottom = max(start_y, end_y)
			var rect = Rect2(screen_x - 6, rect_top, 12, rect_bottom - rect_top)
			draw_rect(rect, Color(0, 1, 0, 0.3), true)
			draw_rect(rect, Color.GREEN, false, 1.0)
	
	# 绘制选区矩形（如果正在框选）
	if selecting:
		var start_screen = grid_to_screen(select_start_grid)
		var end_screen = grid_to_screen(select_end_grid)
		var rect = Rect2(start_screen, end_screen - start_screen).abs()
		draw_rect(rect, Color(0.5, 0.5, 0.5, 0.3), true)
		draw_rect(rect, Color.WHITE, false, 1.0)
	
	# 绘制音符
	if current_notes.is_empty():
		return
	var visible_time_min = bottom_time - 1.0
	var visible_time_max = top_time + 1.0
	for note in current_notes:
		var note_type = note.get("type", 1)  # 0=Hold, 1=Tap, 2=Drag
		var posx = note.get("positionX", 0.0)
		var start_time_beat = fraction_to_beat(note.get("startTime", [0,0,1]))
		var start_time_sec = beat_to_time(start_time_beat)
		var end_time_beat = fraction_to_beat(note.get("endTime", [0,0,1]))
		var end_time_sec = beat_to_time(end_time_beat)
		
		# 确保时间在有效范围内（避免负时间）
		start_time_sec = clamp(start_time_sec, 0.0, total_duration)
		end_time_sec = clamp(end_time_sec, 0.0, total_duration)
		
		# 可见性判断
		var is_visible = false
		if note_type == 0:  # Hold
			if end_time_sec >= visible_time_min and start_time_sec <= visible_time_max:
				is_visible = true
		else:  # Tap or Drag
			if start_time_sec >= visible_time_min and start_time_sec <= visible_time_max:
				is_visible = true
		if not is_visible:
			continue
		
		var screen_x = posx_to_x(posx)
		var start_y = time_to_y(start_time_sec)
		var end_y = time_to_y(end_time_sec)
		
		# 边界裁剪（避免绘制超出屏幕过多导致看不见）
		screen_x = clamp(screen_x, -50.0, view_width + 50.0)
		start_y = clamp(start_y, -50.0, view_height + 50.0)
		end_y = clamp(end_y, -50.0, view_height + 50.0)
		
		match note_type:
			1:  # Tap
				draw_circle(Vector2(screen_x, start_y), 8, Color.BLACK)
			2:  # Drag
				draw_rect(Rect2(screen_x - 6, start_y - 6, 12, 12), Color.DARK_RED, true)
			0:  # Hold
				var rect_top = min(start_y, end_y)
				var rect_bottom = max(start_y, end_y)
				var rect = Rect2(screen_x - 6, rect_top, 12, rect_bottom - rect_top)
				draw_rect(rect, Color(0, 0, 0, 0.5), true)
				draw_rect(rect, Color.BLACK, false, 1.0)
		if selected_notes.has(note):
			match note_type:
				1:  # Tap
					draw_circle(Vector2(screen_x, start_y), 10, Color.YELLOW, false, 2.0)
				2:  # Drag
					draw_rect(Rect2(screen_x - 7, start_y - 7, 14, 14), Color.YELLOW, false, 2.0)
				0:  # Hold
					var rect_top = min(start_y, end_y)
					var rect_bottom = max(start_y, end_y)
					var rect = Rect2(screen_x - 7, rect_top - 1, 14, rect_bottom - rect_top + 2)
					draw_rect(rect, Color.YELLOW, false, 2.0)

# ========== 转换函数（修复关键逻辑） ==========
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
# ========== 结束 ==========

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
		print("[Notes面板] 播放已在进行中，跳过启动")
		return
	if scroll_time >= total_duration:
		scroll_time = 0.0
		v_scroll.value = 0.0
	is_playing = true
	last_update_time = Time.get_ticks_msec() / 1000.0
	playback_timer.start()
	print("[Notes面板] 开始播放 - scroll_time: %.3f" % scroll_time)

func stop_playback():
	if not is_playing:
		return
	is_playing = false
	playback_timer.stop()
	print("[Notes面板] 停止播放")

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
	# 键盘事件（模式切换、空格播放等）
	if visible and event is InputEventKey and event.pressed and not event.echo:
		# 处理删除和平移（需要先处理，避免被其他分支拦截）
		if Global.is_shortcut_match(event, "notes_edit", "delete_selected"):
			if selected_notes.size() > 0:
				for note in selected_notes:
					var idx = current_notes.find(note)
					if idx != -1:
						current_notes.remove_at(idx)
				clear_selection()
				note_data_changed.emit()
				queue_redraw()
				print("删除了 ", selected_notes.size(), " 个音符")
			get_viewport().set_input_as_handled()
			return
		
		if Global.is_shortcut_match(event, "notes_edit", "copy_selected"):
			if selected_notes.size() > 0:
				_clipboard_notes = []
				for note in selected_notes:
					_clipboard_notes.append(JSON.parse_string(JSON.stringify(note)))
				print("复制了 ", _clipboard_notes.size(), " 个音符")
			get_viewport().set_input_as_handled()
			return
		
		if Global.is_shortcut_match(event, "notes_edit", "paste_clipboard"):
			if _clipboard_notes.is_empty():
				print("剪贴板为空，无法粘贴")
				get_viewport().set_input_as_handled()
				return
			_show_paste_beat_dialog()
			get_viewport().set_input_as_handled()
			return
		
		if event.ctrl_pressed and event.shift_pressed:
			# 平移选中的 Notes（以网格间距为单位）
			var step_beat = 1.0 / subdivision
			var step_posx = 10.0
			if Global.is_shortcut_match(event, "notes_edit", "move_up"):
				for note in selected_notes:
					var beat = fraction_to_beat(note["startTime"])
					beat += step_beat
					note["startTime"] = beat_to_fraction(beat)
					if note["type"] == 0:  # Hold
						var end_beat = fraction_to_beat(note["endTime"])
						end_beat += step_beat
						note["endTime"] = beat_to_fraction(end_beat)
				queue_redraw()
				get_viewport().set_input_as_handled()
			elif Global.is_shortcut_match(event, "notes_edit", "move_down"):
				for note in selected_notes:
					var beat = fraction_to_beat(note["startTime"])
					beat -= step_beat
					note["startTime"] = beat_to_fraction(beat)
					if note["type"] == 0:
						var end_beat = fraction_to_beat(note["endTime"])
						end_beat -= step_beat
						note["endTime"] = beat_to_fraction(end_beat)
				queue_redraw()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_LEFT:
				for note in selected_notes:
					note["positionX"] -= step_posx
				queue_redraw()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_RIGHT:
				for note in selected_notes:
					note["positionX"] += step_posx
				queue_redraw()
				get_viewport().set_input_as_handled()
			if event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
				note_data_changed.emit()
				return
		
		# 普通按键（非 Ctrl+Shift 组合）
		match event.keycode:
			KEY_LEFT:
				scroll_x -= 10
				queue_redraw()
				get_viewport().set_input_as_handled()
			KEY_RIGHT:
				scroll_x += 10
				queue_redraw()
				get_viewport().set_input_as_handled()
		
		if event.ctrl_pressed:
			match event.keycode:
				KEY_1:
					current_place_mode = PlaceMode.TAP
					is_placing_hold = false
					print("放置模式: Tap")
					queue_redraw()
					get_viewport().set_input_as_handled()
				KEY_2:
					current_place_mode = PlaceMode.DRAG
					is_placing_hold = false
					print("放置模式: Drag")
					queue_redraw()
					get_viewport().set_input_as_handled()
				KEY_0:
					current_place_mode = PlaceMode.HOLD
					is_placing_hold = false
					print("放置模式: Hold (点击第一个点)")
					queue_redraw()
					get_viewport().set_input_as_handled()
				KEY_SPACE:
					current_place_mode = PlaceMode.BROWSE
					is_placing_hold = false
					print("浏览模式")
					queue_redraw()
					get_viewport().set_input_as_handled()
				KEY_M:
					scroll_x = 0.0
					queue_redraw()
					get_viewport().set_input_as_handled()
	
	# 鼠标事件
	if visible and event is InputEventMouseButton:
		# 滚轮
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			v_scroll.value -= 0.2
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			v_scroll.value += 0.2
			get_viewport().set_input_as_handled()
		
		# 左键按下
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var mouse_pos = get_local_mouse_position()
			# 滚动条区域（右侧20像素）不处理
			if mouse_pos.x > view_width - 20:
				pass
			elif mouse_pos.x >= 0 and mouse_pos.x <= view_width and mouse_pos.y >= 0 and mouse_pos.y <= view_height:
				if current_place_mode == PlaceMode.BROWSE:
					# 浏览模式：处理选择
					var clicked_note = get_note_at_position(mouse_pos)
					if clicked_note != null:
						var current_time = Time.get_ticks_msec()
						if last_click_note == clicked_note and (current_time - last_click_time) < 300:
							# 双击：编辑属性
							edit_note_properties(clicked_note)
							# 重置双击记录
							last_click_time = 0
							last_click_note = null
						else:
							# 单击：选择逻辑
							if event.ctrl_pressed:
								if selected_notes.has(clicked_note):
									selected_notes.erase(clicked_note)
								else:
									add_to_selection(clicked_note)
							else:
								clear_selection()
								add_to_selection(clicked_note)
						last_click_time = current_time
						last_click_note = clicked_note
						get_viewport().set_input_as_handled()
					else:
						# 单击空白：开始框选
						selecting = true
						var grid_pos = screen_to_grid(mouse_pos)
						select_start_grid = {"beat": grid_pos.beat, "posx": grid_pos.posx}
						select_end_grid = {"beat": grid_pos.beat, "posx": grid_pos.posx}
						if not event.ctrl_pressed:
							clear_selection()
						get_viewport().set_input_as_handled()
				else:
					# 放置模式
					var grid_pos = screen_to_grid(mouse_pos)
					if current_place_mode == PlaceMode.TAP:
						place_tap(grid_pos)
						get_viewport().set_input_as_handled()
					elif current_place_mode == PlaceMode.DRAG:
						place_drag(grid_pos)
						get_viewport().set_input_as_handled()
					elif current_place_mode == PlaceMode.HOLD:
						if not is_placing_hold:
							hold_start_beat = grid_pos.beat
							hold_start_posx = grid_pos.posx
							is_placing_hold = true
							print("Hold起始点: beat=", hold_start_beat, " posx=", hold_start_posx)
						else:
							place_hold(hold_start_beat, grid_pos.beat, hold_start_posx)
							is_placing_hold = false
						get_viewport().set_input_as_handled()
		
		# 左键释放
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if selecting:
				selecting = false
				select_notes_in_rect_grid(select_start_grid, select_end_grid)
				queue_redraw()
				get_viewport().set_input_as_handled()
		
		# 右键拖动
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				right_drag_start = event.position
				right_dragging = true
				drag_start_scroll_time = scroll_time
				drag_start_scroll_x = scroll_x
				get_viewport().set_input_as_handled()
			else:
				right_dragging = false
				get_viewport().set_input_as_handled()
	
	# 鼠标移动事件
	if visible and event is InputEventMouseMotion:
		mouse_over_pos = get_local_mouse_position()
		mouse_in_grid = (mouse_over_pos.x >= 0 and mouse_over_pos.x <= view_width and mouse_over_pos.y >= 0 and mouse_over_pos.y <= view_height)
		if right_dragging:
			var delta = event.position - right_drag_start
			var delta_time = delta.y / pixels_per_second
			scroll_time = clamp(drag_start_scroll_time + delta_time, 0.0, v_scroll.max_value)
			var delta_x = -delta.x / view_width * 200.0
			scroll_x = drag_start_scroll_x + delta_x
			v_scroll.value = scroll_time
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif selecting:
			var mouse_pos = get_local_mouse_position()
			var grid_pos = screen_to_grid(mouse_pos)
			select_end_grid = {"beat": grid_pos.beat, "posx": grid_pos.posx}
			# 边缘自动滚动
			var edge_threshold = 30
			var scroll_speed = 3
			if mouse_pos.x < edge_threshold:
				scroll_x -= scroll_speed
				queue_redraw()
			elif mouse_pos.x > view_width - edge_threshold:
				scroll_x += scroll_speed
				queue_redraw()
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

# 将屏幕坐标转换为网格数据
func screen_to_grid(screen_pos: Vector2) -> Dictionary:
	var time = scroll_time + (view_height - screen_pos.y) / pixels_per_second
	var beat = time_to_beat(time)
	var posx = -100 + scroll_x + (screen_pos.x / view_width) * 200.0
	var align = Input.is_key_pressed(KEY_CTRL)
	if align:
		var step = 1.0 / subdivision
		beat = round(beat / step) * step
		posx = round(posx / 10.0) * 10.0
		#posx = clamp(posx, -100, 100)
	#else:
		#posx = clamp(posx, -100, 100)
	return {"time": time, "beat": beat, "posx": posx}

# 将节拍浮点数转换为带分数数组 [整数,分子,分母]
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

# 添加音符到当前判定线
func add_note_to_current_line(note_data: Dictionary):
	current_notes.append(note_data)   # 因为 current_notes 就是原始列表
	note_data_changed.emit()
	queue_redraw()

# 放置 Tap
func place_tap(grid_pos: Dictionary):
	var note = {
		"type": 1,
		"startTime": beat_to_fraction(grid_pos.beat),
		"endTime": beat_to_fraction(grid_pos.beat),
		"positionX": grid_pos.posx,
		"size": 1.0,
		"alpha": 1.0,
		"speed": 1.0,
		"visibleTime": 5000.0,
		"isFake": 0
	}
	add_note_to_current_line(note)
	print("放置 Tap: beat=", grid_pos.beat, " posx=", grid_pos.posx)

# 放置 Drag
func place_drag(grid_pos: Dictionary):
	var note = {
		"type": 2,
		"startTime": beat_to_fraction(grid_pos.beat),
		"endTime": beat_to_fraction(grid_pos.beat),
		"positionX": grid_pos.posx,
		"size": 1.0,
		"alpha": 1.0,
		"speed": 1.0,
		"visibleTime": 5000.0,
		"isFake": 0
	}
	add_note_to_current_line(note)
	print("放置 Drag: beat=", grid_pos.beat, " posx=", grid_pos.posx)

# 放置 Hold
func place_hold(start_beat: float, end_beat: float, posx: float):
	if abs(start_beat - end_beat) < 0.001:
		print("Hold起始和结束节拍相同，无效")
		return
	var start = min(start_beat, end_beat)
	var end = max(start_beat, end_beat)
	var note = {
		"type": 0,
		"startTime": beat_to_fraction(start),
		"endTime": beat_to_fraction(end),
		"positionX": posx,
		"size": 1.0,
		"alpha": 1.0,
		"speed": 1.0,
		"visibleTime": 5000.0,
		"isFake": 0
	}
	add_note_to_current_line(note)
	print("放置 Hold: start=", start, " end=", end, " posx=", posx)

# 获取鼠标位置的 Note（从 current_notes 中查找）
func get_note_at_position(mouse_pos: Vector2):
	var grid_pos = screen_to_grid(mouse_pos)
	var click_beat = grid_pos.beat
	var click_posx = grid_pos.posx
	var tolerance = 0.1
	for note in current_notes:
		var note_type = note.get("type", 1)
		var note_beat = fraction_to_beat(note.get("startTime", [0,0,1]))
		var note_posx = note.get("positionX", 0.0)
		if abs(note_posx - click_posx) > 10:
			continue
		if note_type == 0:  # Hold：检查点击位置是否在 startTime~endTime 范围内
			var end_beat = fraction_to_beat(note.get("endTime", note.get("startTime", [0,0,1])))
			var hold_min = min(note_beat, end_beat)
			var hold_max = max(note_beat, end_beat)
			if click_beat >= hold_min - tolerance and click_beat <= hold_max + tolerance:
				return note
		else:  # Tap/Drag：只检查 startTime
			if abs(note_beat - click_beat) < tolerance:
				return note
	return null

# 清空选择
func clear_selection():
	selected_notes.clear()

# 添加 Note 到选择集（避免重复）
func add_to_selection(note):
	if not selected_notes.has(note):
		selected_notes.append(note)

# 矩形框选（根据两个屏幕坐标）
func select_notes_in_rect(start_pos, end_pos):
	clear_selection()
	var rect = Rect2(start_pos, end_pos - start_pos).abs()
	# 将屏幕矩形转换为时间和 positionX 范围
	var top_left = screen_to_grid(rect.position)
	var bottom_right = screen_to_grid(rect.end)
	var time_min = min(top_left.time, bottom_right.time)
	var time_max = max(top_left.time, bottom_right.time)
	var posx_min = min(top_left.posx, bottom_right.posx)
	var posx_max = max(top_left.posx, bottom_right.posx)
	for note in current_notes:
		var note_beat = fraction_to_beat(note.get("startTime", [0,0,1]))
		var note_time = beat_to_time(note_beat)
		var note_posx = note.get("positionX", 0.0)
		if note_time >= time_min and note_time <= time_max and note_posx >= posx_min and note_posx <= posx_max:
			add_to_selection(note)

func grid_to_screen(grid: Dictionary) -> Vector2:
	var time = beat_to_time(grid.beat)
	var x = posx_to_x(grid.posx)
	var y = time_to_y(time)
	return Vector2(x, y)

func select_notes_in_rect_grid(start_grid: Dictionary, end_grid: Dictionary):
	clear_selection()
	var beat_min = min(start_grid.beat, end_grid.beat)
	var beat_max = max(start_grid.beat, end_grid.beat)
	var posx_min = min(start_grid.posx, end_grid.posx)
	var posx_max = max(start_grid.posx, end_grid.posx)
	for note in current_notes:
		var note_type = note.get("type", 1)
		var note_beat = fraction_to_beat(note.get("startTime", [0,0,1]))
		var note_posx = note.get("positionX", 0.0)
		if note_posx < posx_min or note_posx > posx_max:
			continue
		if note_type == 0:  # Hold：只要 startTime~endTime 范围与选区有交集就选中
			var end_beat = fraction_to_beat(note.get("endTime", note.get("startTime", [0,0,1])))
			var hold_min = min(note_beat, end_beat)
			var hold_max = max(note_beat, end_beat)
			if hold_max >= beat_min and hold_min <= beat_max:
				add_to_selection(note)
		else:  # Tap/Drag：只检查 startTime
			if note_beat >= beat_min and note_beat <= beat_max:
				add_to_selection(note)

# ========== 复制粘贴 ==========
# 解析用户输入的节拍文本（支持小数或带分数格式）
func _parse_beat_input(text: String) -> float:
	text = text.strip_edges()
	if text.is_empty():
		return -1.0
	# 尝试直接解析为浮点数
	if text.is_valid_float():
		return text.to_float()
	# 尝试带分数格式：如 "4 1/2" 或 "1/2"
	var parts = text.split(" ", false)
	var integer_part: float = 0.0
	var frac_part: float = 0.0
	if parts.size() == 2:
		# 带分数 "整数 分子/分母"
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
		# 纯分数 "分子/分母"
		var frac_parts = parts[0].split("/", false)
		if frac_parts.size() == 2:
			var num = frac_parts[0].to_float()
			var den = frac_parts[1].to_float()
			if den != 0.0:
				return num / den
	return -1.0

# 显示粘贴节拍输入对话框
func _show_paste_beat_dialog():
	var dialog = ConfirmationDialog.new()
	dialog.title = "粘贴音符"
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
		_paste_notes_at_beat(paste_beat)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	
	add_child(dialog)
	dialog.popup_centered()

# 在指定节拍粘贴剪贴板中的音符
func _paste_notes_at_beat(paste_beat: float):
	if _clipboard_notes.is_empty():
		return
	
	# 计算剪贴板中最早节拍
	var min_beat = INF
	for note in _clipboard_notes:
		var b = fraction_to_beat(note.get("startTime", [0, 0, 1]))
		if b < min_beat:
			min_beat = b
	if min_beat == INF:
		return
	
	var offset = paste_beat - min_beat
	var pasted_count = 0
	
	for note in _clipboard_notes:
		var new_note = JSON.parse_string(JSON.stringify(note))
		# 平移 startTime
		var start_b = fraction_to_beat(new_note["startTime"])
		start_b += offset
		new_note["startTime"] = beat_to_fraction(start_b)
		# 平移 endTime（Hold 音符）
		if new_note.has("endTime"):
			var end_b = fraction_to_beat(new_note["endTime"])
			end_b += offset
			new_note["endTime"] = beat_to_fraction(end_b)
		# 确保整数类型
		if new_note.has("type"):
			new_note["type"] = int(new_note["type"])
		if new_note.has("isFake"):
			new_note["isFake"] = int(new_note["isFake"])
		# 去除内部字段（如果有）
		new_note.erase("_start_beat")
		new_note.erase("_start_time")
		new_note.erase("_end_beat")
		new_note.erase("_end_time")
		new_note.erase("_effect_triggered")
		
		current_notes.append(new_note)
		pasted_count += 1
	
	clear_selection()
	note_data_changed.emit()
	queue_redraw()
	print("粘贴了 ", pasted_count, " 个音符，起始节拍: ", paste_beat)

func edit_note_properties(note: Dictionary):
	var note_json = JSON.stringify(note, "\t")
	
	var dialog = ConfirmationDialog.new()
	dialog.title = "编辑 Note 属性 (JSON)"
	dialog.ok_button_text = "确认"
	dialog.cancel_button_text = "取消"
	dialog.min_size = Vector2(600, 500)
	
	var vbox = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.size = Vector2(600, 500)
	
	var label = Label.new()
	label.text = "直接编辑 JSON 数据，确认后将更新 Note。"
	
	var text_edit = TextEdit.new()
	text_edit.text = note_json
	text_edit.custom_minimum_size = Vector2(500, 400)
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	if Global.mono_font:
		text_edit.add_theme_font_override("font", Global.mono_font)
	
	vbox.add_child(label)
	vbox.add_child(text_edit)
	dialog.add_child(vbox)
	
	# 连接确认信号
	dialog.confirmed.connect(func():
		var new_text = text_edit.text
		var json = JSON.new()
		var error = json.parse(new_text)
		if error == OK and typeof(json.data) == TYPE_DICTIONARY:
			var new_note = json.data
			# 修正类型
			if new_note.has("type"):
				new_note["type"] = int(new_note["type"])
			for field in ["startTime", "endTime"]:
				if new_note.has(field) and typeof(new_note[field]) == TYPE_ARRAY:
					var arr = new_note[field]
					new_note[field] = [int(arr[0]), int(arr[1]), int(arr[2])]
			
			# 替换 note 对象
			var idx = current_notes.find(note)
			if idx != -1:
				current_notes[idx] = new_note
				# 同步到 current_judge_line["notes"]
				var line_idx = current_judge_line["notes"].find(note)
				if line_idx != -1:
					current_judge_line["notes"][line_idx] = new_note
				# 同步到 selected_notes
				var sel_idx = selected_notes.find(note)
				if sel_idx != -1:
					selected_notes[sel_idx] = new_note
				queue_redraw()
				note_data_changed.emit()
				print("Note 属性已更新")
			else:
				print("错误：找不到要编辑的 Note")
		else:
			var err_dialog = AcceptDialog.new()
			err_dialog.title = "JSON 解析错误"
			err_dialog.dialog_text = "无效的 JSON 格式:\n" + json.get_error_message()
			add_child(err_dialog)
			err_dialog.popup_centered()
		dialog.queue_free()
	)
	# 取消时直接释放对话框
	dialog.canceled.connect(dialog.queue_free)
	
	add_child(dialog)
	dialog.popup_centered()
