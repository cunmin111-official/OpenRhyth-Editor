# Checklist

- [x] Global.gd 存在判定特效模式与曲线设置的 getter/setter，默认值正确并持久化
- [x] play_page.gd 在"frame"模式下使用 judge0~judge5 逐帧动画（每帧 20ms），叠加放大-淡出，按分级颜色（perfect1 #1685A9 / perfect #197855 / good #D12920）渲染，灰度×颜色着色
- [x] play_page.gd 在"original"模式下保留 perfect1/perfect/good.png 单帧渐隐逻辑
- [x] miss 判定不显示任何判定特效
- [x] Hold 判定特效在逐帧模式下完整播放动画并持续至结束，结束后渐隐
- [x] preview_page.gd 使用与 play_page.gd 相同的特效渲染逻辑（始终 Perfect1）
- [x] settings_page.gd 游玩 Tab 新增"判定特效"设置区：模式切换、曲线参数滑块、曲线预览图
- [x] 设置切换（逐帧/原动画）持久化到 settings.json 并生效
- [x] 曲线预览图随参数变化实时刷新
