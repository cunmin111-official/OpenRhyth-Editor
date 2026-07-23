# MIDI 文件解析器
# 从 MIDI 文件中提取 BPM 列表和音符节拍位置
# 返回数据格式：
# {
#   "bpm_list": [{"bpm": 120.0, "startTime": [0,0,1]}, ...],
#   "track_names": ["Track 1", ...],
#   "track_notes": [[1.0, 2.5, ...], ...],  # 每个轨道的音符节拍列表
#   "ppqn": 480
# }
static func parse_midi_file(path: String) -> Dictionary:
	var result = {
		"bpm_list": [],
		"track_names": [],
		"track_notes": [],
		"ppqn": 480,
		"success": false,
		"error": ""
	}
	
	if not FileAccess.file_exists(path):
		result["error"] = "文件不存在: " + path
		return result
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		result["error"] = "无法打开文件: " + path
		return result
	
	# 读取文件头
	var header = file.get_buffer(4).get_string_from_ascii()
	if header != "MThd":
		result["error"] = "无效的 MIDI 文件头"
		file.close()
		return result
	
	# 头长度 (4 bytes, big-endian)
	var header_len = _read_32bit_be(file)
	
	var format = _read_16bit_be(file)
	var track_count = _read_16bit_be(file)
	var division_raw = _read_16bit_be(file)
	
	var ppqn = division_raw  # 假设为 ticks per quarter note（正数）
	if division_raw & 0x8000:
		# SMPTE 格式，暂不支持
		result["error"] = "不支持 SMPTE 格式的 MIDI 文件"
		file.close()
		return result
	
	result["ppqn"] = ppqn
	
	# 跳过剩余的头（如果有）
	if header_len > 6:
		file.get_buffer(header_len - 6)
	
	# 读取所有轨道
	var all_tempo_events = []  # [{tick, microseconds_per_qn}]
	var track_names = []
	var track_notes_raw = []  # [{tick}]
	
	for t in range(track_count):
		var chunk_type = file.get_buffer(4).get_string_from_ascii()
		var chunk_len = _read_32bit_be(file)
		
		var track_ticks = []  # 音符 tick 列表（去重）
		var track_name = ""
		
		if chunk_type == "MTrk":
			var track_data = file.get_buffer(chunk_len)
			var pos = 0
			var abs_tick = 0
			
			while pos < track_data.size():
				# 读取可变长度 delta_time
				var delta = _read_variable_length(track_data, pos)
				pos = delta[1]
				abs_tick += delta[0]
				
				if pos >= track_data.size():
					break
				
				var status_byte = track_data[pos]
				pos += 1
				
				# 处理 running status? 不处理，但大部分 MIDI 文件会明确写 status
				if status_byte == 0xFF:
					# Meta 事件
					var meta_type = track_data[pos]
					pos += 1
					var meta_len = _read_variable_length(track_data, pos)
					pos = meta_len[1]
					var meta_data = track_data.slice(pos, pos + meta_len[0])
					pos += meta_len[0]
					
					match meta_type:
						0x03:  # Track Name
							track_name = meta_data.get_string_from_ascii()
						0x51:  # Set Tempo
							if meta_data.size() >= 3:
								var us_per_qn = (meta_data[0] << 16) | (meta_data[1] << 8) | meta_data[2]
								all_tempo_events.append({"tick": abs_tick, "us_per_qn": us_per_qn})
						0x58:  # Time Signature - 可忽略，不影响音符位置
							pass
						0x2F:  # End of Track
							break
				
				elif (status_byte & 0xF0) == 0x90:
					# Note On
					if pos + 1 < track_data.size():
						var note = track_data[pos]
						var velocity = track_data[pos + 1]
						pos += 2
						if velocity > 0:
							track_ticks.append(abs_tick)
				
				elif (status_byte & 0xF0) == 0x80:
					# Note Off - 忽略，不记录结束位置
					pos += 2
				
				elif (status_byte & 0xE0) == 0xC0 or (status_byte & 0xF0) == 0xD0:
					# Program Change (2 bytes) or Channel Aftertouch (2 bytes)
					pos += 1
				
				elif (status_byte & 0xE0) == 0xE0:
					# Pitch Bend (3 bytes)
					pos += 2
				
				elif (status_byte & 0xF0) == 0xA0 or (status_byte & 0xF0) == 0xB0:
					# Polyphonic Aftertouch or Control Change (3 bytes)
					pos += 2
				
				elif status_byte == 0xF0 or status_byte == 0xF7:
					# SysEx (F0) or SysEx continuation (F7)
					var sysex_len = _read_variable_length(track_data, pos)
					pos = sysex_len[1] + sysex_len[0]
				
				else:
					# Running status - 回退并尝试用上一个 status 解析
					# 简单跳过
					pass
			
			# 去重并排序
			track_ticks.sort()
			var unique_ticks = []
			for tick in track_ticks:
				if unique_ticks.is_empty() or tick != unique_ticks.back():
					unique_ticks.append(tick)
			
			track_notes_raw.append(unique_ticks)
			track_names.append(track_name if track_name != "" else "Track " + str(t + 1))
		else:
			# 非 MTrk 块，跳过
			file.get_buffer(chunk_len)
	
	file.close()
	
	# 如果没有解析到任何轨道数据
	if track_notes_raw.is_empty():
		result["error"] = "未解析到任何音符数据"
		return result
	
	# 确保所有轨道都有数据
	while track_notes_raw.size() < track_count:
		track_notes_raw.append([])
		track_names.append("Track " + str(track_notes_raw.size()))
	
	# 转换 tempo 事件为 BPM 列表
	var bpm_list = []
	for tempo in all_tempo_events:
		var tick = tempo["tick"]
		var us_per_qn = tempo["us_per_qn"]
		var bpm = 60000000.0 / us_per_qn
		var beat = float(tick) / float(ppqn)
		# 转换为 [整数, 分子, 分母] 格式的 startTime
		var start_time = _beat_to_fraction(beat)
		bpm_list.append({
			"bpm": bpm,
			"startTime": [int(start_time[0]), int(start_time[1]), int(start_time[2])]
		})
	
	# 转换音符 tick → beat
	var track_notes = []
	for ticks in track_notes_raw:
		var beats = []
		for tick in ticks:
			beats.append(float(tick) / float(ppqn))
		track_notes.append(beats)
	
	result["bpm_list"] = bpm_list
	result["track_names"] = track_names
	result["track_notes"] = track_notes
	result["success"] = true
	
	return result

# 读取 32 位大端整数
static func _read_32bit_be(file: FileAccess) -> int:
	var b = file.get_buffer(4)
	if b.size() < 4:
		return 0
	return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]

# 读取 16 位大端整数
static func _read_16bit_be(file: FileAccess) -> int:
	var b = file.get_buffer(2)
	if b.size() < 2:
		return 0
	return (b[0] << 8) | b[1]

# 读取 MIDI 可变长度值（VLV）
# 返回 [value, new_pos]
static func _read_variable_length(data: PackedByteArray, pos: int) -> Array:
	var value = 0
	var p = pos
	while p < data.size():
		var byte = data[p]
		p += 1
		value = (value << 7) | (byte & 0x7F)
		if (byte & 0x80) == 0:
			break
	return [value, p]

# 将浮点节拍转换为 [整数, 分子, 分母]
static func _beat_to_fraction(beat: float) -> Array:
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
	return [int(integer), int(best_num), int(best_den)]
