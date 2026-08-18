extends Control

const VIDEO_EXTS: Array = ["ogv"]

# Hold 裁剪着色器代码
# UV.y=0(纹理顶部=hold起点) UV.y=1(纹理底部=hold终点)
# clip_uv: UV.y 超过此值的底部像素被裁掉（已判定部分）
const HOLD_CLIP_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_alpha_opaque;
uniform float clip_uv : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D texture_sprite : source_color;
void fragment() {
	vec4 tex = texture(texture_sprite, UV);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
	if (UV.y > clip_uv) {
		ALPHA = 0.0;
	}
}
"""

# 判定特效着色器：原图灰度 × 分级颜色
const JUDGE_EFFECT_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded;
uniform vec4 grade_color : source_color = vec4(1.0);
uniform sampler2D texture_sprite : source_color;
void fragment() {
	vec4 tex = texture(texture_sprite, UV);
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = grade_color.rgb * lum;
	ALPHA = tex.a;
}
"""

# 判定线着色器（全场景共享单个 Shader 资源，避免每线重复创建/编译）
const LINE_SHADER_CODE: String = "shader_type spatial;\nrender_mode unshaded, depth_draw_never, cull_disabled;\nuniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);\nvoid fragment() {\n\tALBEDO = line_color.rgb;\n\tALPHA = line_color.a;\n}"

# 渲染距离剔除：
# 雾效 alpha = exp(-dist / fog_dist)。dist > FOG_CULL_FACTOR * fog_dist 时 alpha < 0.0005，
# 视觉上已完全不可见，直接隐藏并跳过 modulate/exp 计算。
const FOG_CULL_FACTOR: float = 7.6
# 判定线级剔除的余量：音符相对线心的最大偏移（positionX ±半线长 + 速度积分位移）
const NOTE_OFFSET_MARGIN: float = 900.0

# 视频预取：提前多少秒发起后台加载（配合 ResourceLoader.load_threaded_request，
# 避免视频纹理首次出现那一帧在主线程同步读文件造成卡顿）
const VIDEO_PRELOAD_AHEAD_S: float = 4.0
# build_3d_scene 分帧：每帧最多创建的音符 sprite 数，降低大谱面进入场景的卡顿
const BUILD_CHUNK_NOTES: int = 128

# 判定线事件键（build 时统一遍历，事件数组引用缓存到 line_info["events_cache"]）
const LINE_EVENT_KEYS: Array = ["alphaEvents", "moveXEvents", "moveYEvents", "moveZEvents", "rotateXEvents", "rotateYEvents", "rotateZEvents", "speedEvents", "notesAlphaEvents", "lengthEvents"]

# 预加载纹理
var preloaded_textures: Dictionary = {}
var note_textures = {
	"hold_body": preload("res://res/note/hold.png"),
	"hold_head": preload("res://res/note/hold_head.png"),
	"tap": preload("res://res/note/tap.png"),
	"drag": preload("res://res/note/drag.png"),
}
var judge_textures = {
	"perfect1": preload("res://res/judgeEffects/perfect1.png"),
}
# 逐帧判定特效素材（运行时 load，避免未导入资源在解析期报错）
var judge_frame_textures: Array = []

func _load_judge_frame_textures() -> void:
	judge_frame_textures = []
	for i in range(6):
		var path = "res://res/judgeEffects/judge%d.png" % i
		# 优先用 ResourceLoader 加载（已导入，编辑器与打包后均可用）
		var tex = load(path)
		if tex is Texture2D:
			judge_frame_textures.append(tex)
			continue
		# 兜底：直接读 PNG（未导入场景）
		var img = Image.load_from_file(path)
		if img:
			judge_frame_textures.append(ImageTexture.create_from_image(img))
		else:
			print("[预览] 加载判定帧失败: judge%d.png" % i)

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

# 视频流后台加载缓存：full_path -> VideoStream（null 表示加载失败/不可用）
var _video_streams: Dictionary = {}
# 已发起后台加载的路径：full_path -> true
var _video_load_requested: Dictionary = {}

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
	# UI 标签在分帧构建前创建：构建期间 _process 已开始跑，需保证标签非空
	build_ui_labels()
	# 分帧构建 3D 场景（大谱面避免一次性创建全部节点卡住首帧）
	await build_3d_scene()
	_load_judge_frame_textures()
	_init_effect_pool()
	real_notes_data.sort()
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
		# 预计算 Shader 事件时间（静态，避免每帧重复换算）
		_annotate_event_times(arr)

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
		await _build_one_line(line_data)
	print("[预览] 3D场景构建完成")

# 完整构建一条判定线（节点 + 音符 + 事件缓存），音符超过 BUILD_CHUNK_NOTES 时让出一帧
func _build_one_line(line_data: Dictionary) -> void:
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
	var mat = ShaderMaterial.new()
	mat.shader = _get_line_shader()
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
		# 上一帧可见的 sprite 列表：帧首只隐藏这些，避免每帧 O(总音符数) 全量遍历
		"_prev_visible": [],
	}

	var notes = line_data.get("notes", [])
	# 确保音符按开始节拍升序（editor 可能未排序）
	notes.sort_custom(func(a, b): return fraction_to_beat(a.get("startTime", [0, 0, 1])) < fraction_to_beat(b.get("startTime", [0, 0, 1])))
	var line_max_visible: float = 0.0
	var built_in_frame: int = 0
	for note_data in notes:
		var note_type = int(note_data.get("type", 1))
		var is_fake = float(note_data.get("isFake", 0.0))
		# 预计算音符节拍/时间（静态，避免每帧重复 fraction_to_beat + 二分查找）
		var start_beat = fraction_to_beat(note_data.get("startTime", [0, 0, 1]))
		var end_beat = fraction_to_beat(note_data.get("endTime", [0, 0, 1]))
		note_data["_start_beat"] = start_beat
		note_data["_start_time"] = beat_to_time(start_beat)
		note_data["_end_beat"] = end_beat
		note_data["_end_time"] = beat_to_time(end_beat)
		note_data["_effect_triggered"] = false
		# 记录本线最大 visibleTime（毫秒→秒），决定二分查找的遍历上界
		var note_visible_s = float(note_data.get("visibleTime", 5000.0)) / 1000.0
		if note_visible_s > line_max_visible:
			line_max_visible = note_visible_s
		if is_fake == 0.0:
			var pass_time = note_data["_end_time"] if note_type == 0 else note_data["_start_time"]
			real_notes_data.append(pass_time)
			total_real_count += 1

		if note_type == 0:
			var hold_body = Sprite3D.new()
			hold_body.name = "HoldBody"
			hold_body.texture = note_textures["hold_body"]
			hold_body.visible = false
			hold_body.transparent = true
			hold_body.pixel_size = Global.get_effective_note_type_size("hold_body")
			hold_body.set_draw_flag(Sprite3D.FLAG_DOUBLE_SIDED, true)
			hold_body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			# 无着色器，裁剪在 update_hold_note 中通过 scale/position 实现
			note_group.add_child(hold_body)

			var hold_head = Sprite3D.new()
			hold_head.name = "HoldHead"
			hold_head.texture = note_textures["hold_head"]
			hold_head.visible = false
			hold_head.transparent = true
			hold_head.pixel_size = Global.get_effective_note_type_size("hold_head")
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
			sprite.visible = false
			sprite.transparent = true
			if note_type == 1:
				sprite.pixel_size = Global.get_effective_note_type_size("tap")
			elif note_type == 2:
				sprite.pixel_size = Global.get_effective_note_type_size("drag")
			else:
				sprite.pixel_size = Global.get_note_size() * Global.PIXEL_SIZE_SCALE
			sprite.set_draw_flag(Sprite3D.FLAG_DOUBLE_SIDED, true)
			sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			note_group.add_child(sprite)

			line_info["note_sprites"].append({
				"sprite": sprite,
				"data": note_data
			})

		# 分帧：本帧创建的音符达到上限就让出一帧，避免大谱面卡住
		built_in_frame += 1
		if built_in_frame >= BUILD_CHUNK_NOTES:
			built_in_frame = 0
			await get_tree().process_frame

	# 记录本线最大 visibleTime（秒），二分查找遍历时作为上界
	line_info["max_visible_s"] = line_max_visible
	_annotate_line_events(line_info)
	judge_line_nodes.append(line_info)

# 单线事件处理：排序 + 标注时间 + 缓存事件数组引用 + 预构建速度积分缓存
func _annotate_line_events(line_info: Dictionary) -> void:
	var line_data: Dictionary = line_info["data"]
	var layers = line_data.get("eventLayers", [])
	if not layers.is_empty():
		var layer = layers[0]
		if typeof(layer) == TYPE_DICTIONARY:
			for key in LINE_EVENT_KEYS:
				if layer.has(key) and typeof(layer[key]) == TYPE_ARRAY:
					if layer[key].size() > 1:
						layer[key].sort_custom(func(a, b): return fraction_to_beat(a.get("startTime", [0, 0, 1])) < fraction_to_beat(b.get("startTime", [0, 0, 1])))
					# 预计算事件时间（静态，避免每帧重复换算）
					_annotate_event_times(layer[key])
	# 缓存每线事件数组引用，避免 update_judge_lines 每帧做 10 次字典查找
	line_info["events_cache"] = {}
	for key in LINE_EVENT_KEYS:
		line_info["events_cache"][key] = get_layer_events(line_data, key)
	# 预计算速度积分缓存（速度事件静态，整局只需构建一次，避免每帧每线重建）
	line_info["speed_cache"] = _build_speed_cache(line_info["events_cache"].get("speedEvents", []))

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

# 将 y= / y~ 表达式字符串清洗为可直接 parse 的形式：x 保留为变量名（作为 execute 入参），
# 运行期只需 execute([x])，避免每帧每音符重新拼字符串 + parse
static func _build_expr_clean(expr_str: String) -> String:
	var s = expr_str.strip_edges().replace("～", "~").replace("：", ":")
	if s.begins_with("y=") or s.begins_with("y~") or s.begins_with("y:"):
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
				clean += "x"
			elif c in "0123456789+-*/().eE " or c == "*":
				clean += c
			i += 1
	# pi/tau 不是 Expression 内置常量，替换为数值字面量
	return Global.replace_expr_constants(clean)

# 求值缓存表达式：build 时已预解析（_expr），运行期只执行不重新 parse
func _eval_cached_expression(ev: Dictionary, x_val: float) -> float:
	var expression = ev.get("_expr")
	if not (expression is Expression):
		return 0.0
	var result = expression.execute([x_val], null, false)
	if expression.has_execute_failed() or result == null:
		return 0.0
	return float(result)

# 预计算事件的起止时间（秒），标注到事件字典上：_st / _et
# 事件时间静态不变，预计算后 get_event_value_at_time 可省去每次的二分查找
func _annotate_event_times(events: Array) -> void:
	for ev in events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		ev["_st"] = beat_to_time(fraction_to_beat(ev.get("startTime", [0, 0, 1])))
		ev["_et"] = beat_to_time(fraction_to_beat(ev.get("endTime", [0, 0, 1])))
		var ev_type = str(ev.get("type", "Linear")).replace("～", "~").replace("：", ":")
		if ev_type.begins_with("y=") or ev_type.begins_with("y~") or ev_type.begins_with("y:"):
			# 预解析 y= / y~ / y: 表达式（x 为输入变量），避免每帧每音符重新 parse
			var expression = Expression.new()
			if expression.parse(_build_expr_clean(ev_type), ["x"]) == OK:
				ev["_expr"] = expression
				if ev_type.begins_with("y~"):
					_annotate_shape_bounds(ev)

# 预计算 y~ 形状端点/极值（f(0)/f(1)/采样min/max），用于将 f(x) 伸缩到 start~end
func _annotate_shape_bounds(ev: Dictionary) -> void:
	var f0 = _eval_cached_expression(ev, 0.0)
	var f1 = _eval_cached_expression(ev, 1.0)
	var fmin = min(f0, f1)
	var fmax = max(f0, f1)
	for i in range(1, 32):
		var v = _eval_cached_expression(ev, float(i) / 32.0)
		fmin = min(fmin, v)
		fmax = max(fmax, v)
	ev["_s_f0"] = f0
	ev["_s_f1"] = f1
	ev["_s_min"] = fmin
	ev["_s_max"] = fmax

# y~ 形状伸缩：f(0)→start、f(1)→end（端点归一化，正确支持 start>end 与任意形状）；
# 闭合曲线（f(0)≈f(1)）按采样极值 min→start、max→end；恒定形状退化为线性
func _shape_stretched_value(ev: Dictionary, prog: float, start_val: float, end_val: float) -> float:
	if ev.get("_s_f0") == null:
		_annotate_shape_bounds(ev)
	var f0: float = ev["_s_f0"]
	var f1: float = ev["_s_f1"]
	var f = _eval_cached_expression(ev, prog)
	if abs(f1 - f0) > 0.000001:
		return start_val + (end_val - start_val) * (f - f0) / (f1 - f0)
	var fmin: float = ev["_s_min"]
	var fmax: float = ev["_s_max"]
	if fmax - fmin > 0.000001:
		return start_val + (end_val - start_val) * (f - fmin) / (fmax - fmin)
	return start_val + (end_val - start_val) * prog

func get_event_value_at_time(events: Array, time_sec: float, default_value: float) -> float:
	if events.is_empty():
		return default_value
	var last_value = default_value
	for ev in events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		# 优先使用预标注的时间，未标注时回退到即时换算
		var start_time = ev.get("_st")
		var end_time
		if start_time == null:
			start_time = beat_to_time(fraction_to_beat(ev.get("startTime", [0, 0, 1])))
			end_time = beat_to_time(fraction_to_beat(ev.get("endTime", [0, 0, 1])))
		else:
			end_time = ev["_et"]
		var start_val = float(ev.get("start", default_value))
		var end_val = float(ev.get("end", default_value))
		var ev_type = str(ev.get("type", "Linear")).replace("～", "~").replace("：", ":")
		if time_sec < start_time:
			break
		if abs(start_time - end_time) < 0.0001:
			last_value = start_val
			continue
		if time_sec >= start_time and time_sec <= end_time:
			if ev_type == "Linear":
				var t = (time_sec - start_time) / (end_time - start_time)
				last_value = start_val + (end_val - start_val) * t
			elif ev_type.begins_with("y~") or ev_type.begins_with("y:"):
				# x 恒定 0~1 并伸缩至始末时间
				var prog = clamp((time_sec - start_time) / (end_time - start_time), 0.0, 1.0)
				if ev_type.begins_with("y~"):
					# 形状表达式：y 伸缩至 start~end（端点归一化）
					last_value = _shape_stretched_value(ev, prog, start_val, end_val)
				else:
					# 原始值表达式：y 直接作为数值
					last_value = _eval_cached_expression(ev, prog)
			elif ev_type.begins_with("y="):
				var x = time_sec - start_time
				last_value = _eval_cached_expression(ev, x)
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
	_update_judge_effects(delta)
	if is_playing:
		if audio_player.playing:
			var audio_offset_sec = Global.get_audio_offset_ms() / 1000.0
			current_time = audio_player.get_playback_position() + audio_offset_sec
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

	# 二分查找已过时音符
	var passed_count = _bisect_left(real_notes_data, current_time)
	combo_label.text = str(passed_count)
	if total_real_count > 0:
		var score_display_mode = Global.get_score_display_mode()
		if score_display_mode == "expectation":
			# 期望模式：假设所有已过音符为 perfect1，combo 按已过数推算
			var effective_acc = 1.0
			var acc_score = 900000.0 * effective_acc
			# 未判定任何音符时视为最大连击数占比 100%
			var combo_score = 100000.0 if passed_count == 0 else 100000.0 * float(passed_count) / float(passed_count)
			var bonus = float(passed_count)
			var total_score = int(acc_score + combo_score + bonus)
			score_label.text = str(total_score)
		else:
			# 累加模式：原有计数方式
			var score = (float(passed_count) / float(total_real_count)) * 1000000.0 + float(passed_count)
			score_label.text = str(int(floor(score)))
	else:
		score_label.text = "0"

	# FC/AP 指示器（预览无判定系统，始终显示"无双"）
	if Global.get_fc_ap_indicator():
		accuracy_label.add_theme_color_override("font_color", Color(0.086, 0.522, 0.663))
		combo_text_label.text = "无双"
	else:
		accuracy_label.add_theme_color_override("font_color", Color(0.086, 0.522, 0.663))
		combo_text_label.text = "『洛神』"

	update_shader_effects()
	update_judge_lines(current_time)

	# 在 update_judge_lines 之后使用 visible_note_count（此时已由 update_notes 递增完毕）
	info_label.text = "节拍: %.3f  FPS: %d  Notes: %d  %s" % [current_beat, fps, visible_note_count, video_debug]

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
		# 事件数组引用在 build 时已缓存，避免每帧 10 次字典查找
		var ev_cache: Dictionary = line_info["events_cache"]

		var move_x = get_event_value_at_time(ev_cache.get("moveXEvents", []), time_sec, 0.0)
		var move_y = get_event_value_at_time(ev_cache.get("moveYEvents", []), time_sec, 0.0)
		var move_z = get_event_value_at_time(ev_cache.get("moveZEvents", []), time_sec, 0.0)
		var rot_x = get_event_value_at_time(ev_cache.get("rotateXEvents", []), time_sec, 0.0)
		var rot_y = get_event_value_at_time(ev_cache.get("rotateYEvents", []), time_sec, 0.0)
		var rot_z = get_event_value_at_time(ev_cache.get("rotateZEvents", []), time_sec, 0.0)
		var alpha = get_event_value_at_time(ev_cache.get("alphaEvents", []), time_sec, 0.0)
		var speed_events = ev_cache.get("speedEvents", [])
		# 速度积分缓存在 build_3d_scene 中已构建一次，此处直接复用
		var speed_cache = line_info["speed_cache"]
		var notes_alpha = get_event_value_at_time(ev_cache.get("notesAlphaEvents", []), time_sec, 255.0)
		var line_length = get_event_value_at_time(ev_cache.get("lengthEvents", []), time_sec, 200.0)

		line_node.position = Vector3(move_x, move_y, move_z)
		line_node.rotation_degrees = Vector3(rot_x, rot_y, rot_z)

		var cylinder = line_mesh.mesh as CylinderMesh
		if cylinder and not is_equal_approx(cylinder.height, line_length):
			cylinder.height = line_length

		var line_alpha_normalized = alpha / 255.0
		var line_fog_dist = max(current_fog * 10.0, 1.0)
		var line_cam_dist = line_node.global_position.distance_to(cam_pos)
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
		# 判定线整体处于雾效剔除距离外（含音符最大偏移余量）：音符只触发特效，跳过渲染
		var render_culled = line_cam_dist > line_fog_dist * FOG_CULL_FACTOR + NOTE_OFFSET_MARGIN
		update_notes(line_info, time_sec, speed_events, speed_cache, notes_alpha, cam_pos, render_culled)

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

# 对即将进入时间窗（VIDEO_PRELOAD_AHEAD_S 内）或当前正在播放的视频纹理发起后台加载
func _preload_upcoming_videos(textures: Array, time_sec: float) -> void:
	for tex in textures:
		if not tex.has("_st") or not tex.has("_et"):
			continue
		# 只预取尚未结束的视频：未来 VIDEO_PRELOAD_AHEAD_S 秒内将进入，或正处于时间窗内
		if tex["_st"] - time_sec > VIDEO_PRELOAD_AHEAD_S:
			continue
		if tex["_et"] < time_sec:
			continue
		var display_path = tex.get("display", "")
		if display_path == "":
			continue
		var path_info = preloaded_paths.get(display_path)
		if path_info == null or not path_info["is_video"]:
			continue
		var full_path = path_info["full_path"]
		if _video_load_requested.has(full_path) or _video_streams.has(full_path):
			continue
		if not FileAccess.file_exists(full_path):
			continue
		ResourceLoader.load_threaded_request(full_path, "VideoStream")
		_video_load_requested[full_path] = true

# 取视频流：优先用后台加载结果；加载中返回 null（调用方隐藏本帧，下帧重试）
func _get_video_stream(full_path: String):
	if _video_streams.has(full_path):
		return _video_streams[full_path]
	var status = ResourceLoader.load_threaded_get_status(full_path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var stream = ResourceLoader.load_threaded_get(full_path)
		_video_streams[full_path] = stream if stream is VideoStream else null
		return _video_streams[full_path]
	elif status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		# 未发起过（如 seek 直接跳进视频段）：后台发起，本帧隐藏，下帧取结果
		ResourceLoader.load_threaded_request(full_path, "VideoStream")
		_video_load_requested[full_path] = true
		return null
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		# 后台加载失败：回退同步加载一次并缓存结果（含失败缓存，避免反复重试）
		var stream = ResourceLoader.load(full_path)
		_video_streams[full_path] = stream if stream is VideoStream else null
		return _video_streams[full_path]
	return null

func update_textures(line_info: Dictionary, time_sec: float, line_alpha: float, length_pct: float = 100.0) -> bool:
	var texture_sprite: Sprite3D = line_info["texture_sprite"]
	var video_viewport = line_info.get("video_viewport")
	var video_player_2d = line_info.get("video_player_2d")
	var video_mesh = line_info.get("video_mesh")
	var line_data: Dictionary = line_info["data"]
	var textures = line_data.get("textures", [])

	# 预取：对即将进入时间窗的视频纹理提前发起后台加载，避免播放帧同步读文件
	_preload_upcoming_videos(textures, time_sec)

	var active_texture: Dictionary = {}
	var active_start_time: float = 0.0
	for tex in textures:
		# 起止时间在 preload_textures 中已预计算，懒回退兜底（重复进入时也只在首次换算）
		if not tex.has("_st"):
			tex["_st"] = beat_to_time(fraction_to_beat(tex.get("startTime", [0, 0, 1])))
			tex["_et"] = beat_to_time(fraction_to_beat(tex.get("endTime", [999999, 0, 1])))
		var start_time = tex["_st"]
		var end_time = tex["_et"]
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
			# 后台预加载缓存：已就绪直接用；未就绪则隐藏本帧，下帧重试（不阻塞主线程）
			var stream = _get_video_stream(full_path)
			if stream == null:
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
			# 预计算纹理起止时间（静态），update_textures 每帧不再 fraction_to_beat + beat_to_time
			if not tex.has("_st"):
				tex["_st"] = beat_to_time(fraction_to_beat(tex.get("startTime", [0, 0, 1])))
				tex["_et"] = beat_to_time(fraction_to_beat(tex.get("endTime", [999999, 0, 1])))
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

func update_notes(line_info: Dictionary, time_sec: float, speed_events: Array, speed_cache: Array, notes_alpha: float, cam_pos: Vector3, render_culled: bool) -> void:
	# 增量隐藏：只清上一帧可见的 sprite，避免每帧 O(总音符数) 全量遍历
	var prev_visible: Array = line_info["_prev_visible"]
	for sp in prev_visible:
		sp.visible = false
	prev_visible.clear()

	var current_beat = time_to_beat(time_sec)
	var max_visible_s = line_info.get("max_visible_s", 5.0)
	# time_sec 的速度积分对本线所有音符相同，每线每帧只算一次
	var cum_now = _speed_cumulative(speed_cache, speed_events, time_sec)

	var note_sprites: Array = line_info["note_sprites"]
	var start_idx = _bisect_left_note_list(note_sprites, current_beat - 5.0)
	for i in range(start_idx, note_sprites.size()):
		var note_info: Dictionary = note_sprites[i]
		var note_data: Dictionary = note_info["data"]
		if note_data["_start_time"] - time_sec > max_visible_s:
			break
		var sprite: Sprite3D = note_info["sprite"]
		update_single_note(sprite, note_data, time_sec, current_beat, speed_events, speed_cache, notes_alpha, cam_pos, line_info["node"], cum_now, render_culled)
		if sprite.visible:
			visible_note_count += 1
			prev_visible.append(sprite)

	var hold_bodies: Array = line_info["hold_bodies"]
	# Hold 的可见性由 endTime 决定（start 可能很早但 end 还在未来），不从二分查找 skip
	for i in range(0, hold_bodies.size()):
		var hold_info: Dictionary = hold_bodies[i]
		var note_data: Dictionary = hold_info["data"]
		# start 还太远才 break（end 一定更远，后续必定都不可见）
		if note_data["_start_time"] - time_sec > max_visible_s:
			break
		var body: Sprite3D = hold_info["body"]
		var head: Sprite3D = hold_info["head"]
		update_hold_note(body, head, note_data, time_sec, current_beat, speed_events, speed_cache, notes_alpha, cam_pos, line_info["node"], cum_now, render_culled)
		if body.visible:
			visible_note_count += 1
			prev_visible.append(body)
		if head.visible:
			prev_visible.append(head)

# 二分查找：在 note_sprite / hold_body 的 data._start_beat 数组中找第一个 >= beat 的索引
static func _bisect_left_note_list(list: Array, beat: float) -> int:
	var lo = 0
	var hi = list.size()
	while lo < hi:
		var mid = (lo + hi) / 2
		if list[mid]["data"]["_start_beat"] < beat:
			lo = mid + 1
		else:
			hi = mid
	return lo

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

# ========== 判定特效对象池（预览均显示 Perfect1） ==========
const EFFECT_POOL_SIZE: int = 32
var _effect_pool: Array = []
# 逐帧动画运行中的特效：instance_id -> {sprite, elapsed, total, frame_duration, curve, holding}
var _judge_effect_animations: Dictionary = {}

func _init_effect_pool() -> void:
	for i in range(EFFECT_POOL_SIZE):
		_effect_pool.append(_new_effect_sprite())

# 判定线 Shader 单例：多条线/多次构建共享，避免每线重新创建与编译
var _line_shader: Shader = null
func _get_line_shader() -> Shader:
	if _line_shader == null:
		_line_shader = Shader.new()
		_line_shader.code = LINE_SHADER_CODE
	return _line_shader

# 特效 Shader 单例：特效池 32 个 sprite 共享同一 Shader 资源
var _effect_shader: Shader = null
func _get_effect_shader() -> Shader:
	if _effect_shader == null:
		_effect_shader = Shader.new()
		_effect_shader.code = JUDGE_EFFECT_SHADER_CODE
	return _effect_shader

func _new_effect_sprite() -> Sprite3D:
	var sprite = Sprite3D.new()
	sprite.transparent = true
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.pixel_size = 0.05
	sprite.visible = false
	# 逐帧动画用灰度×颜色着色器（Shader 全局共享，仅材质按 sprite 独立）
	var mat = ShaderMaterial.new()
	mat.shader = _get_effect_shader()
	mat.set_shader_parameter("grade_color", Color.WHITE)
	if not judge_frame_textures.is_empty():
		mat.set_shader_parameter("texture_sprite", judge_frame_textures[0])
	sprite.material_override = mat
	sprite.set_meta("judge_mat", mat)
	world_3d.add_child(sprite)
	return sprite

func _acquire_effect_sprite() -> Sprite3D:
	if _effect_pool.is_empty():
		return _new_effect_sprite()
	return _effect_pool.pop_back()

func _release_effect_sprite(sprite: Sprite3D) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	sprite.visible = false
	_effect_pool.append(sprite)

func spawn_judge_effect(world_pos: Vector3, for_hold: bool = false):
	# 预览始终显示 Perfect1
	var grade = "perfect1"
	if Global.get_judge_effect_mode() == "frame":
		return _spawn_frame_judge_effect(world_pos, grade, for_hold)
	var tex = judge_textures.get(grade)
	if tex == null:
		return null
	var sprite = _acquire_effect_sprite()
	sprite.material_override = null # 原动画不使用灰度着色器
	sprite.texture = tex
	sprite.position = world_pos
	sprite.modulate = Color(1, 1, 1, 1.0)
	sprite.visible = true
	if for_hold:
		# Hold 特效持续显示，由调用方控制生命周期
		return sprite
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1, 1, 1, 0.0), 0.5)
	tween.tween_callback(_release_effect_sprite.bind(sprite))
	return null

# 逐帧判定特效：judge0~judge5 每帧 20ms，播放期间按大小曲线放大并淡出
func _spawn_frame_judge_effect(world_pos: Vector3, grade: String, for_hold: bool) -> Sprite3D:
	if judge_frame_textures.is_empty():
		return null
	var grade_color: Color = Global.JUDGE_GRADE_COLORS.get(grade, Color.WHITE)
	var sprite = _acquire_effect_sprite()
	var mat = sprite.get_meta("judge_mat")
	sprite.material_override = mat
	if mat is ShaderMaterial:
		mat.set_shader_parameter("grade_color", grade_color)
		mat.set_shader_parameter("texture_sprite", judge_frame_textures[0])
	sprite.texture = judge_frame_textures[0]
	sprite.position = world_pos
	sprite.scale = Vector3.ONE
	sprite.modulate = Color(1, 1, 1, 1.0)
	sprite.visible = true
	_judge_effect_animations[sprite.get_instance_id()] = {
		"sprite": sprite,
		"elapsed": 0.0,
		"total": 0.2,
		"frame_duration": 0.02,
		"curve": Global.get_judge_effect_curve(),
		"holding": for_hold,
	}
	return sprite

# 每帧推进逐帧判定特效动画
func _update_judge_effects(delta: float) -> void:
	if _judge_effect_animations.is_empty():
		return
	for id in _judge_effect_animations.keys():
		var anim: Dictionary = _judge_effect_animations[id]
		var sprite: Sprite3D = anim["sprite"]
		if not is_instance_valid(sprite):
			_judge_effect_animations.erase(id)
			continue
		anim["elapsed"] += delta
		var elapsed: float = anim["elapsed"]
		var total: float = anim["total"]
		if anim.get("holding", false):
			# Hold 进行中：保持第 0 帧，尺寸按曲线放大到峰值后保持，渐显结束后由 fade_hold_effect 再播放完整动画
			var t = clampf(elapsed / total, 0.0, 1.0)
			var peak_time: float = float(anim["curve"].get("peak_time", 0.3))
			var scale_val = Global.eval_scale_curve(anim["curve"], minf(t, peak_time))
			sprite.scale = Vector3(scale_val, scale_val, scale_val)
			# 渐显：默认 50ms，可在设置中调节
			var fade_in_s = float(Global.get_judge_effect_fade_in_ms()) / 1000.0
			var alpha = 1.0 if fade_in_s <= 0.0 else clampf(elapsed / fade_in_s, 0.0, 1.0)
			sprite.modulate = Color(1, 1, 1, alpha)
			continue
		if elapsed >= total:
			_release_effect_sprite(sprite)
			_judge_effect_animations.erase(id)
			continue
		var t = clampf(elapsed / total, 0.0, 1.0)
		# 第 0 帧显示 50ms，其余帧按 frame_duration（20ms）
		var frame_idx = 0
		if elapsed >= 0.05:
			frame_idx = clampi(1 + int((elapsed - 0.05) / anim["frame_duration"]), 1, judge_frame_textures.size() - 1)
		sprite.texture = judge_frame_textures[frame_idx]
		var mat = sprite.material_override
		if mat is ShaderMaterial:
			mat.set_shader_parameter("texture_sprite", judge_frame_textures[frame_idx])
		var scale_val = Global.eval_scale_curve(anim["curve"], t)
		sprite.scale = Vector3(scale_val, scale_val, scale_val)
		# 淡出
		sprite.modulate = Color(1, 1, 1, 1.0 - t)

func fade_hold_effect(sprite: Sprite3D) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var id = sprite.get_instance_id()
	if _judge_effect_animations.has(id):
		# Hold 结束：重置为从第 0 帧播放完整动画（含大小曲线），播完由 _update_judge_effects 归还对象池
		var anim: Dictionary = _judge_effect_animations[id]
		anim["holding"] = false
		anim["elapsed"] = 0.0
		sprite.modulate = Color(1, 1, 1, 1.0)
	else:
		# 无逐帧动画条目（原动画模式）：退化为渐隐
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(1, 1, 1, 0.0), 0.5)
		tween.tween_callback(_release_effect_sprite.bind(sprite))

func _trigger_note_effect(note_data: Dictionary, line_node: Node3D, for_hold: bool = false) -> void:
	if note_data.get("_effect_triggered", false):
		return
	var pos_x = float(note_data.get("positionX", 0.0))
	var effect_pos = line_node.global_position + Vector3(pos_x, 0.0, 0.0)
	if for_hold:
		note_data["_effect_sprite"] = spawn_judge_effect(effect_pos, true)
	else:
		spawn_judge_effect(effect_pos)
	note_data["_effect_triggered"] = true

func update_single_note(sprite: Sprite3D, note_data: Dictionary, time_sec: float, current_beat: float, speed_events: Array, speed_cache: Array, notes_alpha: float, cam_pos: Vector3, line_node: Node3D, cum_now: float, render_culled: bool) -> void:
	var note_beat = note_data["_start_beat"]
	var note_time = note_data["_start_time"]
	# visibleTime 单位为毫秒，转为秒
	var visible_time_s = float(note_data.get("visibleTime", 5000.0)) / 1000.0

	var time_diff = note_time - time_sec
	var beat_diff = note_beat - current_beat

	# 音符刚过其判定时刻时触发 Perfect1 特效
	if time_diff < 0 and not note_data.get("_effect_triggered", false) and line_node != null:
		_trigger_note_effect(note_data, line_node)

	# 超出可见时间范围（以秒为单位）或已过时 → 隐藏
	if time_diff > visible_time_s or time_diff < 0:
		sprite.visible = false
		return

	# 判定线整体处于雾效剔除距离外：只触发特效，跳过全部渲染计算
	if render_culled:
		sprite.visible = false
		return

	# 可见范围内才计算位置/透明度
	sprite.visible = true
	var pos_x = float(note_data.get("positionX", 0.0))
	var note_speed = float(note_data.get("speed", 10.0))

	# cum_now 由 update_notes 每线每帧算一次，此处只对 note_time 做一次积分
	var y_offset = note_speed * (_speed_cumulative(speed_cache, speed_events, note_time) - cum_now)
	sprite.position = Vector3(pos_x, y_offset, 0.0)

	var note_alpha = float(note_data.get("alpha", 1.0))
	var combined_alpha = notes_alpha * clamp(note_alpha, 0.0, 1.0)
	var base_alpha = combined_alpha / 255.0
	var fog_distance = max(current_fog * 10.0, 1.0)
	var cam_dist = sprite.global_position.distance_to(cam_pos)
	# 渲染距离剔除：雾效已衰减到不可见，直接隐藏并跳过 exp/modulate
	if cam_dist > fog_distance * FOG_CULL_FACTOR:
		sprite.visible = false
		return
	var fog_alpha = exp(-cam_dist / fog_distance)
	base_alpha *= fog_alpha
	sprite.modulate = Color(1, 1, 1, clamp(base_alpha, 0.0, 1.0))

func update_hold_note(body: Sprite3D, head: Sprite3D, note_data: Dictionary, time_sec: float, current_beat: float, speed_events: Array, speed_cache: Array, notes_alpha: float, cam_pos: Vector3, line_node: Node3D, cum_now: float, render_culled: bool) -> void:
	var start_beat = note_data["_start_beat"]
	var start_time = note_data["_start_time"]
	var end_time = note_data["_end_time"]
	# visibleTime 单位为毫秒，转为秒
	var visible_time_s = float(note_data.get("visibleTime", 5000.0)) / 1000.0

	var time_diff_start = start_time - time_sec
	var time_diff_end = end_time - time_sec

	# Hold 刚过其开始时刻时触发 Perfect1 特效（持续显示到结束）
	if time_diff_start < 0 and not note_data.get("_effect_triggered", false) and line_node != null:
		_trigger_note_effect(note_data, line_node, true)

	# 每帧更新 Hold 特效精灵位置
	var effect_sprite: Sprite3D = note_data.get("_effect_sprite")
	var pos_x = float(note_data.get("positionX", 0.0))
	if effect_sprite and is_instance_valid(effect_sprite) and effect_sprite.visible:
		effect_sprite.position = line_node.global_position + Vector3(pos_x, 0.0, 0.0)

	# Hold 的可见性：start 还太远（整体不可见）→ 隐藏；end 已过时（已结束）→ 隐藏
	if time_diff_start > visible_time_s or time_diff_end < 0:
		body.visible = false
		head.visible = false
		# Hold 结束时渐隐特效
		if effect_sprite and is_instance_valid(effect_sprite):
			fade_hold_effect(effect_sprite)
			note_data["_effect_sprite"] = null
		return

	# 判定线整体处于雾效剔除距离外：只触发特效/处理生命周期，跳过全部渲染计算
	if render_culled:
		body.visible = false
		head.visible = false
		return

	# 可见范围内才计算位置/透明度
	var note_speed = float(note_data.get("speed", 10.0))
	var note_alpha = float(note_data.get("alpha", 1.0))

	# cum_now 由 update_notes 每线每帧算一次，此处只对 start/end 各做一次积分
	var y_start = note_speed * (_speed_cumulative(speed_cache, speed_events, start_time) - cum_now)
	var y_end = note_speed * (_speed_cumulative(speed_cache, speed_events, end_time) - cum_now)

	# Hold 体：region_rect 只显示未判定部分的纹理，保持全长度比例不压缩
	var full_len = y_end - y_start
	var tex_h = body.texture.get_size().y
	var pixel_s = Global.get_effective_note_type_size("hold_body")

	if full_len > 0.01:
		var unplayed_frac = clampf(max(y_end, 0.0) / full_len, 0.0, 1.0)
		if unplayed_frac > 0.001:
			body.visible = true
			body.centered = false
			body.region_enabled = true
			var tex_w = body.texture.get_size().x
			body.region_rect = Rect2(0, 0, tex_w, tex_h * unplayed_frac)
			# 全长度 scale 保持纹理比例
			body.scale = Vector3(1.0, full_len / (tex_h * pixel_s), 1.0)
			# centered=false：top-left 为 position，左上角对齐到 visible_start
			body.position = Vector3(pos_x - tex_w * pixel_s / 2.0, max(y_start, 0.0), 0.0)
		else:
			body.visible = false
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
	# 渲染距离剔除：雾效已衰减到不可见，直接隐藏并跳过 exp/modulate
	if cam_dist > fog_distance * FOG_CULL_FACTOR:
		body.visible = false
		head.visible = false
		return
	var fog_alpha = exp(-cam_dist / fog_distance)
	base_alpha *= fog_alpha
	var final_alpha = clamp(base_alpha, 0.0, 1.0)
	body.modulate = Color(1, 1, 1, final_alpha)
	head.modulate = Color(1, 1, 1, final_alpha)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if Global.is_shortcut_match(event, "preview", "play_pause"):
			if is_playing:
				pause_playback()
			else:
				start_playback()
			get_viewport().set_input_as_handled()
		elif Global.is_shortcut_match(event, "preview", "return_editor"):
			get_viewport().set_input_as_handled()
			_on_return_button_pressed()

func start_playback() -> void:
	is_playing = true
	if audio_player.stream:
		var audio_offset_sec = Global.get_audio_offset_ms() / 1000.0
		var play_pos = current_time - audio_offset_sec
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
		var audio_offset_sec = Global.get_audio_offset_ms() / 1000.0
		current_time = audio_player.get_playback_position() + audio_offset_sec
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
	# 拖动后强制重置所有音符可见性，下一帧 update_notes 会重新计算
	_reset_all_sprites()
	if is_playing and audio_player.stream:
		var audio_offset_sec = Global.get_audio_offset_ms() / 1000.0
		var seek_pos = current_time - audio_offset_sec
		if seek_pos < 0:
			seek_pos = 0
		if seek_pos < audio_player.stream.get_length():
			audio_player.play(seek_pos)
		else:
			audio_player.stop()
			is_playing = false

func _reset_all_sprites() -> void:
	for line_info in judge_line_nodes:
		# 增量隐藏方案下：全部置为不可见并清空上一帧可见列表，下一帧 update_notes 重新计算
		var prev_visible: Array = line_info["_prev_visible"]
		for note_info in line_info.get("note_sprites", []):
			var sprite: Sprite3D = note_info["sprite"]
			sprite.visible = false
			note_info["data"]["judged"] = false
			note_info["data"]["_effect_triggered"] = false
		for hold_info in line_info.get("hold_bodies", []):
			hold_info["body"].visible = false
			hold_info["head"].visible = false
			hold_info["data"]["judged"] = false
			hold_info["data"]["hold_finalized"] = false
			hold_info["data"]["_effect_triggered"] = false
			# 清除旧的 hold 特效精灵
			var old_effect = hold_info["data"].get("_effect_sprite")
			if old_effect and is_instance_valid(old_effect):
				_release_effect_sprite(old_effect)
			hold_info["data"]["_effect_sprite"] = null
		prev_visible.clear()

func _on_return_button_pressed() -> void:
	if audio_player.playing:
		audio_player.stop()
	is_playing = false
	stop_all_videos()
	# 如果预览已播完（current_time >= duration），回退到进入预览前的位置
	if current_time >= duration and Global.editor_pre_preview_scroll > 0.0 and Global.editor_pre_preview_scroll < duration:
		Global.preview_time = Global.editor_pre_preview_scroll
	else:
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
