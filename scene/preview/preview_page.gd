extends Control

const HOLD_TEXTURE_HEIGHT_PX: float = 400.0
const HOLD_SPRITE_PIXEL_SIZE: float = 0.05
const VIDEO_EXTS: Array = ["ogv"]

# 预加载纹理
var preloaded_textures: Dictionary = {}
var note_textures = {
	"hold_body": preload("res://res/note/hold.png"),
	"hold_head": preload("res://res/note/hold_head.png"),
	"tap": preload("res://res/note/tap.png"),
	"drag": preload("res://res/note/drag.png"),
}

var chart_data: Dictionary = {}
var bpm_list: Array = []
var bpm_cache: Array = []
var offset_ms: int = 0
var duration: float = 0.0
var current_time: float = 0.0
var is_playing: bool = false
var is_progress_bar_pressed: bool = false
var current_fog: float = 10.0

var judge_line_nodes: Array = []
var real_notes_data: Array = []
var total_real_count: int = 0

var combo_label: Label
var combo_text_label: Label
var score_label: Label
var accuracy_label: Label
var visible_note_count: int = 0

@onready var world_3d: Node3D = $World3D
@onready var camera: Camera3D = $World3D/Camera3D
@onready var info_label: Label = $CanvasLayer/InfoLabel
@onready var progress_bar: HSlider = $CanvasLayer/ProgressBar
@onready var return_button: Button = $CanvasLayer/ReturnButton
@onready var audio_player: AudioStreamPlayer = $AudioPlayer

func _ready() -> void:
	return_button.pressed.connect(_on_return_button_pressed)
	progress_bar.gui_input.connect(_on_progress_bar_gui_input)

	load_chart_data()
	load_audio()
	preload_textures()
	build_3d_scene()
	real_notes_data.sort()
	build_ui_labels()
	bind_video_textures.call_deferred()

func build_ui_labels() -> void:
	var canvas = $CanvasLayer

	combo_label = Label.new()
	combo_label.name = "ComboLabel"
	combo_label.text = "0"
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	combo_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	combo_label.add_theme_font_size_override("font_size", 60)
	combo_label.add_theme_color_override("font_color", Color(0, 0, 0))
	combo_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	combo_label.offset_left = 0.0
	combo_label.offset_right = 200.0
	combo_label.offset_top = -80.0
	combo_label.offset_bottom = -20.0
	canvas.add_child(combo_label)

	combo_text_label = Label.new()
	combo_text_label.name = "ComboTextLabel"
	combo_text_label.text = "『洛神』"
	combo_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	combo_text_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	combo_text_label.add_theme_font_size_override("font_size", 16)
	combo_text_label.add_theme_color_override("font_color", Color(0, 0, 0))
	combo_text_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	combo_text_label.offset_left = 0.0
	combo_text_label.offset_right = 100.0
	combo_text_label.offset_top = -20.0
	combo_text_label.offset_bottom = -6.0
	canvas.add_child(combo_text_label)

	score_label = Label.new()
	score_label.name = "ScoreLabel"
	score_label.text = "0"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", 36)
	score_label.add_theme_color_override("font_color", Color(0, 0, 0))
	score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_label.offset_left = -300.0
	score_label.offset_right = -20.0
	score_label.offset_top = 20.0
	score_label.offset_bottom = 54.0
	canvas.add_child(score_label)

	accuracy_label = Label.new()
	accuracy_label.name = "AccuracyLabel"
	accuracy_label.text = "准度100.00%"
	accuracy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	accuracy_label.add_theme_font_size_override("font_size", 16)
	accuracy_label.add_theme_color_override("font_color", Color(0.086, 0.522, 0.663))
	accuracy_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	accuracy_label.offset_left = -300.0
	accuracy_label.offset_right = -20.0
	accuracy_label.offset_top = 54.0
	accuracy_label.offset_bottom = 78.0
	canvas.add_child(accuracy_label)

func bind_video_textures() -> void:
	for line_info in judge_line_nodes:
		var vp = line_info.get("video_viewport")
		var vm = line_info.get("video_mesh")
		if vp and vm and vm.material_override:
			vm.material_override.albedo_texture = vp.get_texture()
			print("[预览] ViewportTexture 已绑定")

func load_chart_data() -> void:
	var path = Global.selected_rwc_path
	if path == "" or not FileAccess.file_exists(path):
		print("[预览] 谱面文件不存在: ", path)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(content)
	if err != OK:
		print("[预览] JSON解析失败: ", json.get_error_message())
		return
	chart_data = json.data
	if not chart_data.has("BPMList"):
		chart_data["BPMList"] = []
	if not chart_data.has("META"):
		chart_data["META"] = {"offset": 0}
	if not chart_data.has("judgeLineList"):
		chart_data["judgeLineList"] = []
	if not chart_data.has("Shader"):
		chart_data["Shader"] = {}

	bpm_list = chart_data["BPMList"].duplicate()
	bpm_list.sort_custom(func(a, b):
		return fraction_to_beat(a.get("startTime", [0, 0, 1])) < fraction_to_beat(b.get("startTime", [0, 0, 1]))
	)
	offset_ms = chart_data["META"].get("offset", 0)
	duration = chart_data["META"].get("duration", 0.0)
	bpm_cache = Global.build_bpm_cache(bpm_list, offset_ms)
	progress_bar.max_value = duration
	if Global.preview_time > 0.0:
		current_time = clamp(Global.preview_time, 0.0, duration)
		progress_bar.value = current_time
	else:
		progress_bar.value = 0.0

	for shader_key in ["Fog", "BackgroundR", "BackgroundG", "BackgroundB"]:
		if not chart_data["Shader"].has(shader_key):
			chart_data["Shader"][shader_key] = []
	for shader_key in ["Fog", "BackgroundR", "BackgroundG", "BackgroundB"]:
		var arr = chart_data["Shader"][shader_key]
		if arr.size() > 1:
			arr.sort_custom(func(a, b): return fraction_to_beat(a.get("startTime", [0, 0, 1])) < fraction_to_beat(b.get("startTime", [0, 0, 1])))

	print("[预览] 谱面加载完成, BPM段数: ", bpm_list.size(), " 判定线数: ", chart_data["judgeLineList"].size())

func load_audio() -> void:
	var music_path = Global.selected_music_path
	if music_path == "" or not FileAccess.file_exists(music_path):
		print("[预览] 音频文件不存在: ", music_path)
		return
	var stream = load_audio_from_path(music_path)
	if stream:
		audio_player.stream = stream
		print("[预览] 音频加载成功, 时长: ", stream.get_length())
	else:
		print("[预览] 音频加载失败")

func load_audio_from_path(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var ext = path.get_extension().to_lower()
	match ext:
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"ogg", "oga":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
		_:
			return ResourceLoader.load(path, "AudioStream")

func build_3d_scene() -> void:
	for line_data in chart_data.get("judgeLineList", []):
		var line_group = Node3D.new()
		line_group.name = line_data.get("Name", "JudgeLine")
		world_3d.add_child(line_group)

		var line_mesh = MeshInstance3D.new()
		line_mesh.name = "LineMesh"
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.15
		cylinder.bottom_radius = 0.15
		cylinder.height = line_data.get("length", 200.0)
		line_mesh.mesh = cylinder
		line_mesh.rotation_degrees.z = -90.0
		var line_shader = Shader.new()
		line_shader.code = "shader_type spatial;\nrender_mode unshaded, depth_draw_never, cull_disabled;\nuniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);\nvoid fragment() {\n\tALBEDO = line_color.rgb;\n\tALPHA = line_color.a;\n}"
		var mat = ShaderMaterial.new()
		mat.shader = line_shader
		mat.set_shader_parameter("line_color", Color(0, 0, 0, 1.0))
		line_mesh.material_override = mat
		line_group.add_child(line_mesh)

		var name_label = Label3D.new()
		name_label.name = "NameLabel"
		name_label.text = line_data.get("Name", "JudgeLine")
		name_label.modulate = Color(0.6, 0.85, 1.0)
		name_label.pixel_size = 0.1
		name_label.font_size = 32
		name_label.outline_size = 0
		name_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		if Global.mono_font:
			name_label.font = Global.mono_font
		name_label.position = Vector3(0, 0, 0)
		line_group.add_child(name_label)

		var texture_sprite = Sprite3D.new()
		texture_sprite.name = "TextureSprite"
		texture_sprite.visible = false
		texture_sprite.transparent = true
		texture_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		texture_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		line_group.add_child(texture_sprite)

		# 视频节点懒初始化：仅当遇到视频纹理时按需创建

		var note_group = Node3D.new()
		note_group.name = "NoteGroup"
		line_group.add_child(note_group)

		var line_info = {
			"node": line_group,
			"mesh": line_mesh,
			"texture_sprite": texture_sprite,
			"video_viewport": null,
			"video_player_2d": null,
			"video_mesh": null,
			"video_initialized": false,
			"name_label": name_label,
			"note_group": note_group,
			"data": line_data,
			"note_sprites": [],
			"hold_bodies": [],
		}

		var notes = line_data.get("notes", [])
		for note_data in notes:
			var note_type = int(note_data.get("type", 1))
			var is_fake = float(note_data.get("isFake", 0.0))
			if is_fake == 0.0:
				var pass_beat: float
				if note_type == 0:
					pass_beat = fraction_to_beat(note_data.get("endTime", [0, 0, 1]))
				else:
					pass_beat = fraction_to_beat(note_data.get("startTime", [0, 0, 1]))
				var pass_time = beat_to_time(pass_beat)
				real_notes_data.append(pass_time)
				total_real_count += 1

			if note_type == 0:
				var hold_body = Sprite3D.new()
				hold_body.name = "HoldBody"
				hold_body.texture = note_textures["hold_body"]
				hold_body.transparent = true
				hold_body.pixel_size = 0.05
				hold_body.set_draw_flag(Sprite3D.FLAG_DOUBLE_SIDED, true)
				hold_body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				note_group.add_child(hold_body)

				var hold_head = Sprite3D.new()
				hold_head.name = "HoldHead"
				hold_head.texture = note_textures["hold_head"]
				hold_head.transparent = true
				hold_head.pixel_size = 0.05
				hold_head.set_draw_flag(Sprite3D.FLAG_DOUBLE_SIDED, true)
				hold_head.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				note_group.add_child(hold_head)

				line_info["hold_bodies"].append({
					"body": hold_body,
					"head": hold_head,
					"data": note_data
				})
			else:
				var sprite = Sprite3D.new()
				sprite.name = "NoteSprite"
				if note_type == 1:
					sprite.texture = note_textures["tap"]
				elif note_type == 2:
					sprite.texture = note_textures["drag"]
				sprite.transparent = true
				sprite.pixel_size = 0.05
				sprite.set_draw_flag(Sprite3D.FLAG_DOUBLE_SIDED, true)
				sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				note_group.add_child(sprite)

				line_info["note_sprites"].append({
					"sprite": sprite,
					"data": note_data
				})

		judge_line_nodes.append(line_info)

	var line_event_keys = ["alphaEvents", "moveXEvents", "moveYEvents", "moveZEvents", "rotateXEvents", "rotateYEvents", "rotateZEvents", "speedEvents", "notesAlphaEvents", "lengthEvents"]
	for line_info in judge_line_nodes:
		var layers = line_info["data"].get("eventLayers", [])
		if layers.is_empty():
			continue
		var layer = layers[0]
		if typeof(layer) != TYPE_DICTIONARY:
			continue
		for key in line_event_keys:
			if layer.has(key) and typeof(layer[key]) == TYPE_ARRAY and layer[key].size() > 1:
				layer[key].sort_custom(func(a, b): return fraction_to_beat(a.get("startTime", [0, 0, 1])) < fraction_to_beat(b.get("startTime", [0, 0, 1])))

	print("[预览] 3D场景构建完成")

func fraction_to_beat(fraction: Array) -> float:
	if fraction.size() != 3:
		return 0.0
	var integer = float(fraction[0])
	var numerator = float(fraction[1])
	var denominator = float(fraction[2])
	if denominator == 0:
		denominator = 1.0
	return integer + numerator / denominator

func beat_to_time(beat: float) -> float:
	return Global.cached_beat_to_time(bpm_cache, beat)

func time_to_beat(time_sec: float) -> float:
	return Global.cached_time_to_beat(bpm_cache, time_sec)

func eval_expression(expr_str: String, x_val: float) -> float:
	var s = expr_str.strip_edges()
	if s.begins_with("y="):
		s = s.substr(2)
	s = s.replace("^", "**")
	var func_names = ["sin", "cos", "tan", "abs", "sqrt", "log", "exp", "floor", "ceil", "round", "min", "max", "pi"]
	var clean = ""
	var i = 0
	while i < s.length():
		var matched = false
		for fn in func_names:
			if s.substr(i, fn.length()) == fn:
				clean += fn
				i += fn.length()
				matched = true
				break
		if not matched:
			var c = s[i]
			if c == "x":
				clean += "(" + str(x_val) + ")"
			elif c in "0123456789+-*/().eE " or c == "*":
				clean += c
			i += 1
	var expression = Expression.new()
	var err = expression.parse(clean, [])
	if err != OK:
		return 0.0
	var result = expression.execute([], null, false)
	if expression.has_execute_failed() or result == null:
		return 0.0
	return float(result)

func get_event_value_at_time(events: Array, time_sec: float, default_value: float) -> float:
	if events.is_empty():
		return default_value
	var last_value = default_value
	for ev in events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var start_beat = fraction_to_beat(ev.get("startTime", [0, 0, 1]))
		var end_beat = fraction_to_beat(ev.get("endTime", [0, 0, 1]))
		var start_time = beat_to_time(start_beat)
		var end_time = beat_to_time(end_beat)
		var start_val = float(ev.get("start", default_value))
		var end_val = float(ev.get("end", default_value))
		var ev_type = str(ev.get("type", "Linear"))
		if time_sec < start_time:
			break
		if start_beat == end_beat or abs(start_time - end_time) < 0.0001:
			last_value = start_val
			continue
		if time_sec >= start_time and time_sec <= end_time:
			if ev_type == "Linear":
				var t = (time_sec - start_time) / (end_time - start_time)
				last_value = start_val + (end_val - start_val) * t
			elif ev_type.begins_with("y="):
				var x = time_sec - start_time
				last_value = eval_expression(ev_type, x)
			else:
				var t = (time_sec - start_time) / (end_time - start_time)
				last_value = start_val + (end_val - start_val) * t
			return last_value
		if time_sec > end_time:
			last_value = end_val
	return last_value

func get_layer_events(line_data: Dictionary, event_key: String) -> Array:
	var layers = line_data.get("eventLayers", [])
	if layers.is_empty():
		return []
	return layers[0].get(event_key, [])

func _process(delta: float) -> void:
	if is_playing:
		if audio_player.playing:
			current_time = audio_player.get_playback_position()
		else:
			current_time += delta
		if current_time >= duration:
			current_time = duration
			is_playing = false
			audio_player.stop()

	if is_progress_bar_pressed:
		current_time = progress_bar.value
	else:
		progress_bar.value = current_time

	var current_beat = time_to_beat(current_time)
	var fps = Engine.get_frames_per_second()
	var video_debug = ""
	# 增量计数由 update_notes 填充
	visible_note_count = 0
	for line_info in judge_line_nodes:
		var vm = line_info.get("video_mesh")
		if vm and vm.visible:
			var vp = line_info.get("video_player_2d")
			var mat = vm.material_override
			var playing = vp and vp.is_playing()
			var tex = mat.albedo_texture if mat else null
			video_debug = "Vplay=%s tex=%s" % [playing, tex != null]
	info_label.text = "节拍: %.3f  FPS: %d  Notes: %d  %s" % [current_beat, fps, visible_note_count, video_debug]

	# 二分查找已过时音符
	var passed_count = _bisect_left(real_notes_data, current_time)
	combo_label.text = str(passed_count)
	if total_real_count > 0:
		var score = (float(passed_count) / float(total_real_count)) * 1000000.0 + float(passed_count)
		score_label.text = str(int(floor(score)))
	else:
		score_label.text = "0"

	update_shader_effects()
	update_judge_lines(current_time)

func update_shader_effects() -> void:
	var shader = chart_data.get("Shader", {})
	var fog_val = get_event_value_at_time(shader.get("Fog", []), current_time, 10.0)
	current_fog = fog_val
	var bg_r = get_event_value_at_time(shader.get("BackgroundR", []), current_time, 255.0) / 255.0
	var bg_g = get_event_value_at_time(shader.get("BackgroundG", []), current_time, 255.0) / 255.0
	var bg_b = get_event_value_at_time(shader.get("BackgroundB", []), current_time, 255.0) / 255.0
	RenderingServer.set_default_clear_color(Color(bg_r, bg_g, bg_b))

func update_judge_lines(time_sec: float) -> void:
	var cam_pos = camera.global_position # 缓存每帧只取一次
	for line_info in judge_line_nodes:
		var line_data = line_info["data"]
		var line_node: Node3D = line_info["node"]
		var line_mesh: MeshInstance3D = line_info["mesh"]

		var move_x = get_event_value_at_time(get_layer_events(line_data, "moveXEvents"), time_sec, 0.0)
		var move_y = get_event_value_at_time(get_layer_events(line_data, "moveYEvents"), time_sec, 0.0)
		var move_z = get_event_value_at_time(get_layer_events(line_data, "moveZEvents"), time_sec, 0.0)
		var rot_x = get_event_value_at_time(get_layer_events(line_data, "rotateXEvents"), time_sec, 0.0)
		var rot_y = get_event_value_at_time(get_layer_events(line_data, "rotateYEvents"), time_sec, 0.0)
		var rot_z = get_event_value_at_time(get_layer_events(line_data, "rotateZEvents"), time_sec, 0.0)
		var alpha = get_event_value_at_time(get_layer_events(line_data, "alphaEvents"), time_sec, 0.0)
		var speed_events = get_layer_events(line_data, "speedEvents")
		var speed_cache = _build_speed_cache(speed_events)
		var notes_alpha = get_event_value_at_time(get_layer_events(line_data, "notesAlphaEvents"), time_sec, 255.0)
		var line_length = get_event_value_at_time(get_layer_events(line_data, "lengthEvents"), time_sec, 200.0)

		line_node.position = Vector3(move_x, move_y, move_z)
		line_node.rotation_degrees = Vector3(rot_x, rot_y, rot_z)

		var cylinder = line_mesh.mesh as CylinderMesh
		if cylinder and not is_equal_approx(cylinder.height, line_length):
			cylinder.height = line_length

		var line_alpha_normalized = alpha / 255.0
		var line_fog_dist = max(current_fog * 10.0, 1.0)
		var line_cam_dist = line_node.global_position.distance_to(camera.global_position)
		var line_fog_alpha = exp(-line_cam_dist / line_fog_dist)
		var line_alpha_with_fog = clamp(line_alpha_normalized * line_fog_alpha, 0.0, 1.0)
		if line_mesh.material_override:
			line_mesh.material_override.set_shader_parameter("line_color", Color(0, 0, 0, line_alpha_with_fog))

		var has_image = update_textures(line_info, time_sec, line_alpha_with_fog, line_length)
		line_mesh.visible = not has_image
		var name_label: Label3D = line_info.get("name_label", null)
		if name_label:
			name_label.visible = not has_image
		if not has_image:
			if name_label:
				name_label.modulate = Color(0.6, 0.85, 1.0, 0.5 + 0.5 * line_alpha_with_fog)
		update_notes(line_info, time_sec, speed_events, speed_cache, notes_alpha, cam_pos)

func _ensure_video_nodes(line_info: Dictionary, line_group: Node3D) -> void:
	if line_info.get("video_initialized", false):
		return
	line_info["video_initialized"] = true

	var video_viewport = SubViewport.new()
	video_viewport.name = "VideoViewport"
	video_viewport.size = Vector2i(1920, 1080)
	video_viewport.transparent_bg = false
	video_viewport.handle_input_locally = false
	video_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	line_group.add_child(video_viewport)
	line_info["video_viewport"] = video_viewport

	var video_player_2d = VideoStreamPlayer.new()
	video_player_2d.name = "VideoPlayer2D"
	video_player_2d.volume_db = -80
	video_player_2d.set_anchors_preset(Control.PRESET_FULL_RECT)
	video_viewport.add_child(video_player_2d)
	line_info["video_player_2d"] = video_player_2d

	var video_mesh = MeshInstance3D.new()
	video_mesh.name = "VideoMesh"
	video_mesh.visible = false
	var plane = PlaneMesh.new()
	plane.size = Vector2(200.0, 112.5)
	video_mesh.mesh = plane
	var video_mat = StandardMaterial3D.new()
	video_mat.albedo_color = Color(1, 1, 1, 1.0)
	video_mat.billboard_mode = StandardMaterial3D.BILLBOARD_DISABLED
	video_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	video_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	video_mesh.material_override = video_mat
	line_group.add_child(video_mesh)
	line_info["video_mesh"] = video_mesh

func update_textures(line_info: Dictionary, time_sec: float, line_alpha: float, length_pct: float = 100.0) -> bool:
	var texture_sprite: Sprite3D = line_info["texture_sprite"]
	var video_viewport = line_info.get("video_viewport")
	var video_player_2d = line_info.get("video_player_2d")
	var video_mesh = line_info.get("video_mesh")
	var line_data: Dictionary = line_info["data"]
	var textures = line_data.get("textures", [])

	var active_texture: Dictionary = {}
	var active_start_time: float = 0.0
	for tex in textures:
		var start_beat = fraction_to_beat(tex.get("startTime", [0, 0, 1]))
		var end_beat = fraction_to_beat(tex.get("endTime", [999999, 0, 1]))
		var start_time = beat_to_time(start_beat)
		var end_time = beat_to_time(end_beat)
		if time_sec >= start_time and time_sec <= end_time:
			active_texture = tex
			active_start_time = start_time
			break
	if active_texture.is_empty():
		texture_sprite.visible = false
		stop_video_mesh(video_player_2d, video_mesh)
		return false
	var display_path = active_texture.get("display", "")
	if display_path == "":
		texture_sprite.visible = false
		stop_video_mesh(video_player_2d, video_mesh)
		return false
	# 从预加载缓存中查找路径信息
	var path_info = preloaded_paths.get(display_path)
	if path_info == null:
		texture_sprite.visible = false
		stop_video_mesh(video_player_2d, video_mesh)
		return false
	var full_path = path_info["full_path"]
	var ext = path_info["ext"]
	if path_info["is_video"]:
		texture_sprite.visible = false
		if video_player_2d == null:
			_ensure_video_nodes(line_info, line_info["node"])
			video_viewport = line_info["video_viewport"]
			video_player_2d = line_info["video_player_2d"]
			video_mesh = line_info["video_mesh"]
		if not FileAccess.file_exists(full_path):
			stop_video_mesh(video_player_2d, video_mesh)
			return false
		if video_player_2d.stream == null:
			var stream = ResourceLoader.load(full_path, "VideoStream")
			if stream == null:
				stream = ResourceLoader.load(full_path)
			if stream == null or not (stream is VideoStream):
				stop_video_mesh(video_player_2d, video_mesh)
				return false
			video_player_2d.stream = stream
		var video_time = max(time_sec - active_start_time, 0.0)
		if not video_mesh.visible:
			video_mesh.visible = true
		if not video_player_2d.is_playing():
			video_player_2d.play()
			video_player_2d.stream_position = video_time
		elif abs(video_player_2d.stream_position - video_time) > 1.0:
			video_player_2d.stream_position = video_time
		video_player_2d.paused = not is_playing
		if video_mesh.material_override:
			if video_mesh.material_override.albedo_texture == null:
				video_mesh.material_override.albedo_texture = video_viewport.get_texture()
			video_mesh.material_override.albedo_color = Color(1, 1, 1, 1.0)
		return false
	else:
		stop_video_mesh(video_player_2d, video_mesh)
		var tex = load_image_fallback(full_path)
		if tex == null:
			texture_sprite.visible = false
			return false
		texture_sprite.texture = tex
		texture_sprite.visible = true
		texture_sprite.modulate = Color(1, 1, 1, line_alpha)
		var base_ps = 200.0 / tex.get_width()
		texture_sprite.pixel_size = base_ps * (length_pct / 100.0)
		return true

# 预加载路径缓存：display_path → {full_path, ext, is_video}
var preloaded_paths: Dictionary = {}

func preload_textures() -> void:
	preloaded_textures.clear()
	preloaded_paths.clear()
	var rwc_path = Global.selected_rwc_path
	var base_dir = rwc_path.get_base_dir()
	for line_data in chart_data.get("judgeLineList", []):
		var textures = line_data.get("textures", [])
		for tex in textures:
			var display_path = tex["display"]
			if preloaded_paths.has(display_path):
				continue
			var full_path = base_dir.path_join(display_path)
			if not ResourceLoader.exists(full_path) and not FileAccess.file_exists(full_path):
				if ResourceLoader.exists(display_path) or FileAccess.file_exists(display_path):
					full_path = display_path
				else:
					continue
			var ext = full_path.get_extension().to_lower()
			var is_video = ext in VIDEO_EXTS
			preloaded_paths[display_path] = {"full_path": full_path, "ext": ext, "is_video": is_video}
			if not is_video:
				var tex_obj = load_image_fallback(full_path)
				if tex_obj:
					preloaded_textures[full_path] = tex_obj

func load_image_fallback(path: String) -> Texture2D:
	if preloaded_textures.has(path):
		return preloaded_textures[path]
	var tex = load(path)
	if tex:
		return tex
	if not FileAccess.file_exists(path):
		return null
	var img = Image.new()
	var err = img.load(path)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)

# 二分查找：返回第一个 >= value 的索引（已排序数组用）
static func _bisect_left(arr: Array, value: float) -> int:
	var lo = 0
	var hi = arr.size()
	while lo < hi:
		var mid = (lo + hi) / 2
		if arr[mid] < value:
			lo = mid + 1
		else:
			hi = mid
	return lo

func stop_video_mesh(video_player_2d, video_mesh) -> void:
	if video_player_2d and video_player_2d.is_playing():
		video_player_2d.stop()
	if video_mesh and video_mesh.visible:
		video_mesh.visible = false

func update_notes(line_info: Dictionary, time_sec: float, speed_events: Array, speed_cache: Array, notes_alpha: float, cam_pos: Vector3) -> void:
	var current_beat = time_to_beat(time_sec)

	for note_info in line_info["note_sprites"]:
		var sprite: Sprite3D = note_info["sprite"]
		var note_data: Dictionary = note_info["data"]
		update_single_note(sprite, note_data, time_sec, current_beat, speed_events, speed_cache, notes_alpha, cam_pos)
		if sprite.visible:
			visible_note_count += 1

	for hold_info in line_info["hold_bodies"]:
		var body: Sprite3D = hold_info["body"]
		var head: Sprite3D = hold_info["head"]
		var note_data: Dictionary = hold_info["data"]
		update_hold_note(body, head, note_data, time_sec, current_beat, speed_events, speed_cache, notes_alpha, cam_pos)
		if body.visible:
			visible_note_count += 1

# ========== 速度积分缓存（预计算 + 二分查找） ==========
func _build_speed_cache(events: Array) -> Array:
	var cache: Array = [ {"time": 0.0, "cum": 0.0}]
	if events.is_empty():
		return cache
	var cum = 0.0
	var prev_t = 0.0
	var current_speed = 50.0
	for ev in events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var start_beat = fraction_to_beat(ev.get("startTime", [0, 0, 1]))
		var end_beat = fraction_to_beat(ev.get("endTime", start_beat))
		var start_t = beat_to_time(start_beat)
		var end_t = beat_to_time(end_beat)
		if start_t > prev_t:
			cum += current_speed * (start_t - prev_t)
			cache.append({"time": start_t, "cum": cum})
			prev_t = start_t
		if end_t > start_t:
			var start_val = float(ev.get("start", current_speed))
			var end_val = float(ev.get("end", start_val))
			cum += (start_val + end_val) * (end_t - start_t) / 2.0
			cache.append({"time": end_t, "cum": cum})
			prev_t = end_t
			current_speed = end_val
		else:
			current_speed = float(ev.get("start", current_speed))
	return cache

func _speed_cumulative(cache: Array, events: Array, t: float) -> float:
	if cache.is_empty():
		return 50.0 * t
	if t <= 0.0:
		return 0.0
	var last = cache[cache.size() - 1]
	if t >= last["time"]:
		var final_speed = 50.0
		if not events.is_empty():
			var last_ev = events[events.size() - 1]
			if typeof(last_ev) == TYPE_DICTIONARY:
				final_speed = float(last_ev.get("end", last_ev.get("start", 50.0)))
		return last["cum"] + final_speed * (t - last["time"])
	var lo = 0
	var hi = cache.size() - 1
	while lo < hi:
		var mid = (lo + hi) / 2
		if cache[mid]["time"] < t:
			lo = mid + 1
		else:
			hi = mid
	var entry = cache[lo - 1] if lo > 0 else cache[0]
	var dt = t - entry["time"]
	if dt <= 0:
		return entry["cum"]
	return entry["cum"] + get_event_value_at_time(events, entry["time"] + dt / 2.0, 50.0) * dt

func update_single_note(sprite: Sprite3D, note_data: Dictionary, time_sec: float, current_beat: float, speed_events: Array, speed_cache: Array, notes_alpha: float, cam_pos: Vector3) -> void:
	var note_beat = fraction_to_beat(note_data.get("startTime", [0, 0, 1]))
	var note_time = beat_to_time(note_beat)
	var pos_x = float(note_data.get("positionX", 0.0))
	var note_alpha = float(note_data.get("alpha", 1.0))
	var visible_time = float(note_data.get("visibleTime", 5.0))
	var note_speed = float(note_data.get("speed", 10.0))

	var time_diff = note_time - time_sec
	var beat_diff = note_beat - current_beat

	if beat_diff > visible_time or time_diff < 0:
		sprite.visible = false
		return

	sprite.visible = true

	var y_offset = note_speed * (_speed_cumulative(speed_cache, speed_events, note_time) - _speed_cumulative(speed_cache, speed_events, time_sec))
	sprite.position = Vector3(pos_x, y_offset, 0.0)

	var combined_alpha = notes_alpha * clamp(note_alpha, 0.0, 1.0)
	var base_alpha = combined_alpha / 255.0
	var fog_distance = max(current_fog * 10.0, 1.0)
	var cam_dist = sprite.global_position.distance_to(cam_pos)
	var fog_alpha = exp(-cam_dist / fog_distance)
	base_alpha *= fog_alpha
	sprite.modulate = Color(1, 1, 1, clamp(base_alpha, 0.0, 1.0))

func update_hold_note(body: Sprite3D, head: Sprite3D, note_data: Dictionary, time_sec: float, current_beat: float, speed_events: Array, speed_cache: Array, notes_alpha: float, cam_pos: Vector3) -> void:
	var start_beat = fraction_to_beat(note_data.get("startTime", [0, 0, 1]))
	var end_beat = fraction_to_beat(note_data.get("endTime", [0, 0, 1]))
	var start_time = beat_to_time(start_beat)
	var end_time = beat_to_time(end_beat)
	var pos_x = float(note_data.get("positionX", 0.0))
	var note_alpha = float(note_data.get("alpha", 1.0))
	var visible_time = float(note_data.get("visibleTime", 5.0))

	var note_speed = float(note_data.get("speed", 10.0))

	var beat_diff = start_beat - current_beat
	var time_diff_start = start_time - time_sec
	var time_diff_end = end_time - time_sec

	if beat_diff > visible_time:
		body.visible = false
		head.visible = false
		return

	var y_start = note_speed * (_speed_cumulative(speed_cache, speed_events, start_time) - _speed_cumulative(speed_cache, speed_events, time_sec))
	var y_end = note_speed * (_speed_cumulative(speed_cache, speed_events, end_time) - _speed_cumulative(speed_cache, speed_events, time_sec))

	var clip_start = max(y_start, 0.0)
	var clip_end = max(y_end, 0.0)
	var clip_len = clip_end - clip_start
	var clip_mid = (clip_start + clip_end) / 2.0

	if clip_len > 0.01:
		body.visible = true
		body.position = Vector3(pos_x, clip_mid, 0.0)
		body.scale = Vector3(1.0, max(clip_len / (HOLD_TEXTURE_HEIGHT_PX * HOLD_SPRITE_PIXEL_SIZE), 0.01), 1.0)
	else:
		body.visible = false

	if time_diff_start > 0:
		head.visible = true
		head.position = Vector3(pos_x, y_start, 0.0)
	else:
		head.visible = false

	var combined_alpha = notes_alpha * clamp(note_alpha, 0.0, 1.0)
	var base_alpha = combined_alpha / 255.0
	var fog_distance = max(current_fog * 10.0, 1.0)
	var cam_dist = body.global_position.distance_to(cam_pos)
	var fog_alpha = exp(-cam_dist / fog_distance)
	base_alpha *= fog_alpha
	var final_alpha = clamp(base_alpha, 0.0, 1.0)
	body.modulate = Color(1, 1, 1, final_alpha)
	head.modulate = Color(1, 1, 1, final_alpha)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			if is_playing:
				pause_playback()
			else:
				start_playback()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_on_return_button_pressed()
			get_viewport().set_input_as_handled()

func start_playback() -> void:
	is_playing = true
	if audio_player.stream:
		var play_pos = current_time
		if play_pos < 0:
			play_pos = 0
		if play_pos < audio_player.stream.get_length():
			audio_player.play(play_pos)
		else:
			is_playing = false
	for line_info in judge_line_nodes:
		var vp = line_info.get("video_player_2d")
		var vm = line_info.get("video_mesh")
		if vp and vm and vm.visible:
			vp.paused = false

func pause_playback() -> void:
	is_playing = false
	if audio_player.playing:
		current_time = audio_player.get_playback_position()
		audio_player.stop()
	for line_info in judge_line_nodes:
		var vp = line_info.get("video_player_2d")
		var vm = line_info.get("video_mesh")
		if vp and vm and vm.visible:
			vp.paused = true

func _on_progress_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_progress_bar_pressed = true
			else:
				is_progress_bar_pressed = false
				seek_to(progress_bar.value)
	elif event is InputEventScreenTouch:
		if event.pressed:
			is_progress_bar_pressed = true
		else:
			is_progress_bar_pressed = false
			seek_to(progress_bar.value)

func seek_to(time_sec: float) -> void:
	current_time = clamp(time_sec, 0.0, duration)
	if is_playing and audio_player.stream:
		if current_time < audio_player.stream.get_length():
			audio_player.play(current_time)
		else:
			audio_player.stop()
			is_playing = false

func _on_return_button_pressed() -> void:
	if audio_player.playing:
		audio_player.stop()
	is_playing = false
	stop_all_videos()
	Global.preview_time = current_time
	get_tree().change_scene_to_file("res://scene/editor/editor_main.tscn")

func stop_all_videos() -> void:
	for line_info in judge_line_nodes:
		var vp = line_info.get("video_player_2d")
		if vp and vp.is_playing():
			vp.stop()
		var vm = line_info.get("video_mesh")
		if vm:
			vm.visible = false

func _exit_tree() -> void:
	if audio_player:
		audio_player.stop()
	stop_all_videos()
	RenderingServer.set_default_clear_color(Color(0.173, 0.173, 0.173))
