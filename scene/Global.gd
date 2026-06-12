extends Node
# 全局变量
# 文件路径
var selected_rwc_path: String = ""
var selected_music_path: String = ""
var preview_time: float = 0.0
# 等宽字体（用于 JSON 编辑器等）
var mono_font: Font = null

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
