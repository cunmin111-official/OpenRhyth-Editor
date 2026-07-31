# Tasks

- [x] Task 1: Global.gd 新增判定特效设置
  - 在 `_ensure_defaults()` 中为 `settings["play"]` 添加默认值：`judge_effect_mode`（"frame"）、`judge_effect_curve`（{start:0.8, peak:1.4, peak_time:0.3, end:0.5}）。
  - 新增 getter/setter：`get_judge_effect_mode()` / `set_judge_effect_mode()`、`get_judge_effect_curve()` / `set_judge_effect_curve()`，setter 保存 settings.json。
  - 新增常量：分级颜色映射 `JUDGE_GRADE_COLORS = {"perfect1": Color("#1685A9"), "perfect": Color("#197855"), "good": Color("#D12920")}`。

- [x] Task 2: play_page.gd 实现逐帧判定特效
  - 加载 `judge0.png ~ judge5.png` 为帧数组（`preload`）。
  - 扩展 `spawn_judge_effect`：根据 `Global.get_judge_effect_mode()` 分支——
    - "frame"：取池中 sprite，用 `_update_judge_effects` 逐帧切换（每 20ms），灰度化帧图 × 分级颜色着色，播放期间按曲线放大 + 淡出，结束后归还对象池；
    - "original"：保留现有 perfect1/perfect/good.png 单帧渐隐逻辑。
  - miss 判定时 `spawn_judge_effect` 直接返回 null（已满足）。
  - Hold 特效（for_hold=true）在逐帧模式下播放完整动画后停留至结束/释放，由 `fade_hold_effect` 渐隐。

- [x] Task 3: preview_page.gd 同步逐帧判定特效
  - 与 Task 2 相同的帧加载、颜色、曲线、模式分支逻辑。
  - 预览页面始终以 Perfect1 渲染（沿用现有行为），但走逐帧动画与曲线。

- [x] Task 4: settings_page.gd 新增"判定特效"设置区
  - 在游玩 Tab 新增设置区：
    - 特效模式：OptionButton（逐帧动画 / 原动画），切换时调用 `Global.set_judge_effect_mode`；
    - 曲线参数滑块：起始大小、峰值大小、峰值时刻、结束大小，绑定 `Global.set_judge_effect_curve`；
    - 大小曲线预览：内嵌类 `ScaleCurvePreview`（`_draw` 绘制 scale-时间曲线），参数变化时实时刷新。

- [x] Task 5: 验证与修复
  - 静态验证完成：全部 4 个文件诊断通过；逐帧动画、颜色渲染（灰度×分级色）、放大淡出、miss 不显示、Hold 生命周期、模式切换持久化、曲线预览刷新均已通过代码审查确认。
  - 运行时验证：请运行 play/preview 场景确认实际表现。

# Task Dependencies
- [Task 2] 依赖 [Task 1]（使用 Global 设置）。
- [Task 3] 依赖 [Task 1] 与 [Task 2]（共用逻辑）。
- [Task 4] 依赖 [Task 1]。
- [Task 5] 依赖全部。
