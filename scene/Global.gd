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


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
